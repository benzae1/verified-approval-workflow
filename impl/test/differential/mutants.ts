// Runs the unit tests and the differential test against each planted bug and
// prints a results table (Markdown).
//
//   node test/differential/mutants.ts
//   RUNS=10000 SEEDS=20 node test/differential/mutants.ts
//
// Exits non-zero if the differential test misses a planted bug, or if either
// suite fails on the correct implementation.
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { MUTANTS, type Mutant } from '../../src/mutants.ts';
import { differential } from './harness.ts';

const runs = Number(process.env.RUNS ?? 10_000);
const seeds = Number(process.env.SEEDS ?? 20);
const firstSeed = Number(process.env.SEED ?? 20261116);
const implDir = fileURLToPath(new URL('../..', import.meta.url));

/** Runs the unit tests against a variant; returns the names of failing tests. */
function unitTests(mutant?: Mutant): string[] {
  const result = spawnSync(
    process.execPath,
    ['--test', '--test-reporter=tap', 'test/unit/workflow.test.ts'],
    { cwd: implDir, env: { ...process.env, WORKFLOW_MUTANT: mutant ?? '' }, encoding: 'utf8' },
  );
  const failing = [...result.stdout.matchAll(/^not ok \d+ - (.*)$/gm)].map((m) => m[1] ?? '?');
  if (result.status !== 0 && failing.length === 0) {
    throw new Error(`unit test run broke for ${mutant ?? 'the correct implementation'}:\n${result.stdout}${result.stderr}`);
  }
  return failing;
}

const median = (xs: number[]): number => {
  const s = [...xs].sort((a, b) => a - b);
  return s[Math.floor((s.length - 1) / 2)] ?? NaN;
};

// The correct implementation must pass both suites.
const baselineUnit = unitTests();
const baselineDiff = await differential({ runs, seed: firstSeed });
if (baselineUnit.length > 0 || baselineDiff.failed) {
  console.error('the correct implementation does not pass its own tests; fix that first');
  process.exit(1);
}

let missed = 0;
let unitCaught = 0;
const rows: string[] = [];
const examples: string[] = [];

for (const mutant of Object.keys(MUTANTS) as Mutant[]) {
  const failingUnit = unitTests(mutant);
  if (failingUnit.length > 0) unitCaught++;

  const tracesNeeded: number[] = [];
  let example: Awaited<ReturnType<typeof differential>> | undefined;
  for (let i = 0; i < seeds; i++) {
    const outcome = await differential({ runs, seed: firstSeed + i, mutant });
    if (outcome.failed) {
      tracesNeeded.push(outcome.runs);
      example ??= outcome;
    }
  }
  const caught = tracesNeeded.length === seeds;
  if (!caught) missed++;

  rows.push(
    `| ${mutant} | ${MUTANTS[mutant]} | ` +
      (failingUnit.length > 0 ? `caught (${failingUnit.length} of 10 tests fail)` : 'missed') +
      ' | ' +
      (caught
        ? `caught in ${seeds} of ${seeds} runs`
        : `missed in ${seeds - tracesNeeded.length} of ${seeds} runs of ${runs} traces`) +
      ` | ${tracesNeeded.length > 0 ? `${median(tracesNeeded)} (${Math.min(...tracesNeeded)} to ${Math.max(...tracesNeeded)})` : 'n/a'} |`,
  );
  if (example?.counterexample) {
    examples.push(
      `${mutant}, shrunk counterexample:\n\n\`\`\`json\n${JSON.stringify(example.counterexample)}\n\`\`\`\n\n` +
        `\`\`\`\n${example.mismatch}\n\`\`\`` +
        (failingUnit.length > 0 ? `\n\nFailing unit tests: ${failingUnit.map((n) => `"${n}"`).join(', ')}.` : ''),
    );
  }
}

const total = Object.keys(MUTANTS).length;
console.log(`| Bug | What was changed | Unit tests (10) | Differential test | Traces until caught: median (range) |`);
console.log(`| --- | --- | --- | --- | --- |`);
for (const row of rows) console.log(row);
console.log(
  `\nUnit tests caught ${unitCaught} of ${total}; the differential test caught ${total - missed} of ${total}. ` +
    `Differential runs: ${seeds} seeds starting at ${firstSeed}, up to ${runs} traces each.\n`,
);
console.log(examples.join('\n\n'));
process.exit(missed > 0 ? 1 : 0);
