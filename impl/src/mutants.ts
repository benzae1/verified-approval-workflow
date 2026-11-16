/**
 * Planted bugs: one-line deviations from the correct implementation, switched
 * on by name so the test suites can run against each. Search for
 * `mutant ===` and `mutant !==` to find them.
 */
export const MUTANTS = {
  M1: 'P4 deleted from the policy set (policy regression)',
  M2: 'editRequest copies `requester` from the input (mass assignment)',
  M3: 'approve does not check the current status (lifecycle flaw)',
  M4: 'entity builder omits the `requester` attribute (skipped policy)',
  M5: 'deny skips the policy engine (missing authorization check)',
} as const;

export type Mutant = keyof typeof MUTANTS;

export function parseMutant(name: string | undefined): Mutant | undefined {
  if (name === undefined || name === '') return undefined;
  if (name in MUTANTS) return name as Mutant;
  throw new Error(`unknown mutant: ${name}`);
}
