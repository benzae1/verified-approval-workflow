// The differential test runs random action sequences through the Lean model
// and through the TypeScript implementation. The decision and the resulting
// state must agree at every step.
import { type ChildProcessWithoutNullStreams, spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { createInterface } from 'node:readline';
import fc from 'fast-check';
import type { Mutant } from '../../src/mutants.ts';
import { type Action, type State, type StepResult, createWorkflow, initialState } from '../../src/workflow.ts';

export interface Step {
  actor: string;
  [field: string]: unknown;
}
export interface Trace {
  approvers: string[];
  steps: (Step & Action)[];
}

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------

// The universe is small: three users and at most four requests. Actors and
// requesters therefore often coincide, so self-approval attempts, delegation
// to a requester and actions on decided requests are frequent. A generator
// drawing from many users would rarely try to self-approve.
export const USERS = ['alice', 'bob', 'carol'];
export const MAX_REQUESTS = 4;
export const MAX_STEPS = 20;

const user = fc.constantFrom(...USERS);
// Identifiers 0..4: one more than can exist, so unknown requests are tried too.
// Low identifiers are favoured, because those requests exist in most traces.
const id = fc.oneof(
  ...[5, 4, 2, 1, 1].map((weight, n) => ({ weight, arbitrary: fc.constant(n) })),
);
const text = fc.string({ maxLength: 6 });

const action: fc.Arbitrary<Action> = fc.oneof(
  { weight: 3, arbitrary: fc.record({ action: fc.constant('create' as const), justification: text }) },
  { weight: 2, arbitrary: fc.record({ action: fc.constant('edit' as const), id, justification: text }) },
  {
    // An edit with a `requester` field in its input. The model has no such
    // field, so a correct implementation ignores it.
    weight: 1,
    arbitrary: fc.record({ action: fc.constant('edit' as const), id, justification: text, requester: user }),
  },
  { weight: 5, arbitrary: fc.record({ action: fc.constant('approve' as const), id }) },
  { weight: 2, arbitrary: fc.record({ action: fc.constant('deny' as const), id }) },
  { weight: 2, arbitrary: fc.record({ action: fc.constant('delegate' as const), to: user }) },
);

export const trace: fc.Arbitrary<Trace> = fc
  .record({
    approvers: fc.uniqueArray(user, { maxLength: USERS.length, size: 'max' }),
    // `size: 'max'` makes trace lengths uniform up to MAX_STEPS. The default
    // favours short traces, in which few requests get decided.
    steps: fc.array(
      fc.tuple(user, action).map(([actor, a]) => ({ actor, ...a })),
      { maxLength: MAX_STEPS, size: 'max' },
    ),
  })
  .map(({ approvers, steps }) => {
    // at most MAX_REQUESTS requests per trace
    let created = 0;
    return { approvers, steps: steps.filter((s) => s.action !== 'create' || ++created <= MAX_REQUESTS) };
  });

// ---------------------------------------------------------------------------
// The Lean model, as a child process speaking JSON lines
// ---------------------------------------------------------------------------

const DEFAULT_RUNNER = fileURLToPath(new URL('../../../lean/.lake/build/bin/runner', import.meta.url));

export class Model {
  private readonly child: ChildProcessWithoutNullStreams;
  private readonly waiting: { resolve: (line: string) => void; reject: (e: Error) => void }[] = [];
  private exited = false;

  constructor(guard: 'cedar' | 'plain' = 'cedar') {
    const runner = process.env.MODEL_RUNNER ?? DEFAULT_RUNNER;
    if (!existsSync(runner)) {
      throw new Error(`model runner not found at ${runner}; run \`lake build\` in lean/ first`);
    }
    this.child = spawn(runner, ['--guard', guard], { stdio: ['pipe', 'pipe', 'pipe'] });
    createInterface({ input: this.child.stdout }).on('line', (line) => this.waiting.shift()?.resolve(line));
    let stderr = '';
    this.child.stderr.on('data', (d) => (stderr += d));
    this.child.on('exit', (code) => {
      this.exited = true;
      for (const w of this.waiting.splice(0)) w.reject(new Error(`model runner exited (${code}): ${stderr}`));
    });
  }

  /** Runs one trace through the model; one result per step. */
  run(t: Trace): Promise<StepResult[]> {
    if (this.exited) return Promise.reject(new Error('model runner has exited'));
    return new Promise<string>((resolve, reject) => {
      this.waiting.push({ resolve, reject });
      this.child.stdin.write(JSON.stringify(t) + '\n');
    }).then((line) => (JSON.parse(line) as { decision: 'allow' | 'deny'; state: ModelState }[]).map(fromModel));
  }

  close(): void {
    this.child.stdin.end();
  }
}

interface ModelState {
  approvers: string[];
  requests: { id: number; requester: string; justification: string; status: string; decidedBy: string | null }[];
}

function fromModel(r: { decision: 'allow' | 'deny'; state: ModelState }): StepResult {
  r.state.requests.forEach((req, i) => {
    if (req.id !== i) throw new Error('model output: request ids out of order');
  });
  return {
    decision: r.decision,
    state: {
      approvers: r.state.approvers,
      requests: r.state.requests.map(({ id: _id, ...rest }) => rest as State['requests'][number]),
    },
  };
}

// ---------------------------------------------------------------------------
// Comparison
// ---------------------------------------------------------------------------

/** Canonical JSON: object keys sorted, so equal values give equal strings. */
export function canonical(value: unknown): string {
  return JSON.stringify(value, (_key, v) =>
    v !== null && typeof v === 'object' && !Array.isArray(v)
      ? Object.fromEntries(Object.entries(v as object).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)))
      : v,
  );
}

/** Runs a trace through the implementation. */
export function runImplementation(workflow: ReturnType<typeof createWorkflow>, t: Trace): StepResult[] {
  let state = initialState(t.approvers);
  return t.steps.map(({ actor, ...a }) => {
    const result = workflow.step(state, actor, a as Action);
    state = result.state;
    return result;
  });
}

export class Mismatch extends Error {}

/** Throws a `Mismatch` at the first step where model and implementation differ. */
export function compare(t: Trace, model: StepResult[], impl: StepResult[]): void {
  if (model.length !== impl.length) throw new Mismatch('different number of steps');
  for (let i = 0; i < model.length; i++) {
    const m = canonical(model[i]);
    const s = canonical(impl[i]);
    if (m !== s) {
      throw new Mismatch(
        `step ${i + 1} (${JSON.stringify(t.steps[i])}):\n  model:          ${m}\n  implementation: ${s}`,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Coverage statistics: what the generated traces actually exercised
// ---------------------------------------------------------------------------

export class Coverage {
  traces = 0;
  steps = 0;
  allowed = 0;
  approveSteps = 0;
  selfApprovalAttempts = 0;
  selfApprovalAttemptsByApprover = 0;
  delegationsToARequester = 0;
  actionsOnDecidedRequests = 0;
  editsWithForeignRequester = 0;
  tracesWithSelfApprovalAttempt = 0;

  /** Records one trace, given the (agreed) results of each step. */
  record(t: Trace, results: StepResult[]): void {
    this.traces++;
    let state = initialState(t.approvers);
    let selfAttempt = false;
    t.steps.forEach((s, i) => {
      this.steps++;
      if (results[i]?.decision === 'allow') this.allowed++;
      const target = 'id' in s && typeof s.id === 'number' ? state.requests[s.id] : undefined;
      if (s.action === 'approve') {
        this.approveSteps++;
        if (target?.requester === s.actor) {
          this.selfApprovalAttempts++;
          selfAttempt = true;
          if (state.approvers.includes(s.actor)) this.selfApprovalAttemptsByApprover++;
        }
      }
      if (s.action === 'delegate' && state.requests.some((r) => r.requester === s.to)) this.delegationsToARequester++;
      if (s.action !== 'create' && s.action !== 'delegate' && target && target.status !== 'Requested') {
        this.actionsOnDecidedRequests++;
      }
      if (s.action === 'edit' && 'requester' in s && target && s.requester !== target.requester) {
        this.editsWithForeignRequester++;
      }
      state = results[i]?.state ?? state;
    });
    if (selfAttempt) this.tracesWithSelfApprovalAttempt++;
  }
}

// ---------------------------------------------------------------------------
// The property
// ---------------------------------------------------------------------------

export interface RunOptions {
  runs: number;
  seed: number;
  guard?: 'cedar' | 'plain';
  mutant?: Mutant;
}

export interface RunOutcome {
  failed: boolean;
  /** Number of traces executed; if failed, the failing one is the last. */
  runs: number;
  seed: number;
  /** The shrunk counterexample and its mismatch, if failed. */
  counterexample?: Trace;
  mismatch?: string;
  coverage: Coverage;
}

/** Runs the differential property and reports the outcome instead of throwing. */
export async function differential(options: RunOptions): Promise<RunOutcome> {
  const model = new Model(options.guard ?? 'cedar');
  const workflow = createWorkflow(options.mutant);
  const coverage = new Coverage();
  try {
    const details = await fc.check(
      fc.asyncProperty(trace, async (t) => {
        const expected = await model.run(t);
        compare(t, expected, runImplementation(workflow, t));
        coverage.record(t, expected);
      }),
      { numRuns: options.runs, seed: options.seed, endOnFailure: false },
    );
    if (!details.failed) return { failed: false, runs: details.numRuns, seed: details.seed, coverage };
    const error = details.errorInstance;
    if (!(error instanceof Mismatch)) throw error ?? new Error('property failed without an error');
    return {
      failed: true,
      runs: details.numRuns,
      seed: details.seed,
      counterexample: details.counterexample?.[0],
      mismatch: error.message,
      coverage,
    };
  } finally {
    model.close();
  }
}
