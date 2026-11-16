# Traceability

Test figures are from the CI configuration: 10,000 random traces, seed
20261116, 95,573 steps, each compared between the Lean model and the
TypeScript implementation.

| Control | Requirement | Theorem | Holds for | Differential test coverage | Planted bugs that violate it |
| --- | --- | --- | --- | --- | --- |
| C1 | Decisions are final: once a request is approved or denied, no action changes it. | `decisions_are_final` in [Finality.lean](../lean/Workflow/Thm/Finality.lean) | Every guard | 5,191 edit, approve and deny steps on an already decided request | M3 |
| C2 | The requester of a request cannot be changed. | `requester_is_immutable` in [Requester.lean](../lean/Workflow/Thm/Requester.lean) | Every guard | All 95,573 steps compare the requester of every request; 1,646 edits carry a different requester in their input | M2 |
| C3 | Segregation of duties: nobody approves their own request, whatever the delegations. | `segregation_of_duties` in [SodPolicy.lean](../lean/Workflow/Thm/SodPolicy.lean) (policy engine); `segregation_of_duties_plain` in [SodPlain.lean](../lean/Workflow/Thm/SodPlain.lean) (plain guard) | Any guard that refuses self-approval; shown for both | 32,295 approve steps, 4,089 of them self-approval attempts, 2,031 of those by a user holding approval rights at the time; 4,052 delegations to a requester | M1 and M4 directly; M2 opens a way around it |
| C4 | Only approvers decide: approve or deny takes effect only if the actor holds approval rights at that moment. | `only_approvers_decide` in [OnlyApprovers.lean](../lean/Workflow/Thm/OnlyApprovers.lean) | Policy engine guard | All approve and deny steps, by approvers and non-approvers | M5 |

## Supporting lemmas

| Lemma | File | Role |
| --- | --- | --- |
| `apply_forward`, `apply_backward` | [Step.lean](../lean/Workflow/Thm/Step.lean) | What one authorized action can do to a request. Used by C1, C2 and C3. |
| `segregation_of_duties_of_noSelfApproval` | [Sod.lean](../lean/Workflow/Thm/Sod.lean) | The invariant proof for C3, for any guard |
| `forbidSelfApproval_satisfied` | [SodPolicy.lean](../lean/Workflow/Thm/SodPolicy.lean) | Bridge lemma: P4 is satisfied, so raises no error, when a requester asks to approve their own request |
| `Cedar.Thm.forbid_trumps_permit` | cedar-spec, `Cedar/Thm/Authorization.lean` | From the Cedar project: a satisfied forbid policy means deny |
| `Cedar.Thm.allowed_only_if_explicitly_permitted` | cedar-spec, `Cedar/Thm/Authorization.lean` | From the Cedar project: allow means some permit policy is satisfied |
| `segregation_of_duties_with` | [SodPolicy.lean](../lean/Workflow/Thm/SodPolicy.lean) | C3 for any policy set that contains P4 |

## Policies

| Policy | Text | Syntax tree used in the proofs |
| --- | --- | --- |
| P1 to P5 | [policies.cedar](../impl/policies.cedar) | [Policies.lean](../lean/Workflow/Policies.lean) |

The two versions are written separately. The differential test runs the text
in the Cedar engine and the syntax trees in Cedar's Lean specification on the
same requests. Their agreement is tested, not proven.

## Checks on the proofs

| Check | Where |
| --- | --- |
| No `sorry`, no `native_decide`, no axioms beyond `propext`, `Classical.choice`, `Quot.sound` | [check-axioms.sh](../scripts/check-axioms.sh), run in CI |
| Concrete decisions of each policy, and the delegation scenario, evaluated at build time | [Checks.lean](../lean/Workflow/Checks.lean) |
