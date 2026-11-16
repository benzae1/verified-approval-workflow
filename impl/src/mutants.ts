/**
 * Planted bugs. Each is a one-line deviation from the correct implementation,
 * switched on by name, so the test suites can run against every variant.
 * Search for `mutant ===` and `mutant !==` to find each one in the code.
 */
export const MUTANTS = {
  M1: 'P4 deleted from the policy set (policy regression)',
  M2: 'editRequest copies `requester` from the input (mass assignment)',
  M3: 'approve does not check the current status (lifecycle flaw)',
  M4: 'entity builder omits the `requester` attribute (skipped policy)',
  M5: 'approve skips the policy engine when the actor is an approver (fast path)',
} as const;

export type Mutant = keyof typeof MUTANTS;

export function parseMutant(name: string | undefined): Mutant | undefined {
  if (name === undefined || name === '') return undefined;
  if (name in MUTANTS) return name as Mutant;
  throw new Error(`unknown mutant: ${name}`);
}
