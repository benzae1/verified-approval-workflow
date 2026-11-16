// Differential test of the implementation against the Lean model.
//
//   node test/differential/run.ts            10,000 traces, both guards
//   RUNS=1000000 SEED=7 node test/differential/run.ts
//
// Exits non-zero on the first mismatch, printing a shrunk counterexample.
import { differential } from './harness.ts';

const runs = Number(process.env.RUNS ?? 10_000);
const seed = Number(process.env.SEED ?? 20261116);
let failed = false;

for (const guard of ['cedar', 'plain'] as const) {
  const started = Date.now();
  const outcome = await differential({ runs, seed, guard });
  const seconds = ((Date.now() - started) / 1000).toFixed(1);
  const c = outcome.coverage;
  if (outcome.failed) {
    failed = true;
    console.error(`MISMATCH against the model (${guard} guard) after ${outcome.runs} traces, seed ${seed}`);
    console.error(`shrunk counterexample: ${JSON.stringify(outcome.counterexample)}`);
    console.error(outcome.mismatch);
    continue;
  }
  console.log(`model with ${guard} guard: ${outcome.runs} traces, no mismatches (seed ${seed}, ${seconds}s)`);
  console.log(
    [
      `  steps: ${c.steps} (${c.allowed} took effect)`,
      `  approve steps: ${c.approveSteps}`,
      `  self-approval attempts: ${c.selfApprovalAttempts} (${c.selfApprovalAttemptsByApprover} by a user holding approval rights), in ${c.tracesWithSelfApprovalAttempt} traces`,
      `  delegations to a requester: ${c.delegationsToARequester}`,
      `  actions on decided requests: ${c.actionsOnDecidedRequests}`,
      `  edits carrying a foreign requester: ${c.editsWithForeignRequester}`,
    ].join('\n'),
  );
}
process.exit(failed ? 1 : 0);
