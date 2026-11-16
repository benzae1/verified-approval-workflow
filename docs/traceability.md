# Traceability

Each control, the theorem that proves it, the tests that tie the theorem to
the running code, and the planted bugs that violate it.

Test figures are from the configuration that runs in CI: 10,000 random traces
(seed 20261116), 95,573 steps in total, each compared step by step between the
Lean model and the TypeScript implementation.

| Control | Requirement | Theorem | Holds for | Differential test coverage | Planted bugs that violate it |
| --- | --- | --- | --- | --- | --- |
| C1 | Decisions are final: once a request is approved or denied, no action changes it. | `decisions_are_final` in [Finality.lean](../lean/Workflow/Thm/Finality.lean) | Every guard | 5,191 edit, approve and deny steps aimed at an already decided request | M3 |
| C2 | The requester of a request cannot be changed. | `requester_is_immutable` in [Requester.lean](../lean/Workflow/Thm/Requester.lean) | Every guard | All 95,573 steps compare the requester of every request; 1,646 edits carry a different requester in their input | M2 |
| C3 | Segregation of duties: nobody approves their own request, whatever delegations took place. | `segregation_of_duties` in [SodPolicy.lean](../lean/Workflow/Thm/SodPolicy.lean) (policy engine); `segregation_of_duties_plain` in [SodPlain.lean](../lean/Workflow/Thm/SodPlain.lean) (plain guard) | Any guard that refuses self-approval; shown for both guards | 32,295 approve steps, 4,089 of them self-approval attempts, 2,031 of those by a user who held approval rights at that moment; 4,052 delegations to a user who is a requester | M1, M4, M5 directly; M2 as a way around it |
| C4 | Only approvers decide: an approve or deny takes effect only if the actor holds approval rights at that moment. | `only_approvers_decide` in [OnlyApprovers.lean](../lean/Workflow/Thm/OnlyApprovers.lean) | Policy engine guard | All approve and deny steps, by approvers and non-approvers alike | None planted |

## Supporting lemmas

| Lemma | File | Role |
| --- | --- | --- |
| `apply_forward`, `apply_backward` | [Step.lean](../lean/Workflow/Thm/Step.lean) | What one authorized action can do to a request; every control proof rests on these two |
| `segregation_of_duties_of_noSelfApproval` | [Sod.lean](../lean/Workflow/Thm/Sod.lean) | The invariant proof for C3, done once for an arbitrary guard |
| `forbidSelfApproval_satisfied` | [SodPolicy.lean](../lean/Workflow/Thm/SodPolicy.lean) | Bridge lemma: P4 is satisfied, and in particular does not raise an error, when a requester asks to approve their own request |
| `Cedar.Thm.forbid_trumps_permit` | cedar-spec, `Cedar/Thm/Authorization.lean` | The engine's own theorem: a satisfied forbid policy means deny |
| `Cedar.Thm.allowed_only_if_explicitly_permitted` | cedar-spec, `Cedar/Thm/Authorization.lean` | The engine's own theorem: allow means some permit policy is satisfied |
| `segregation_of_duties_with` | [SodPolicy.lean](../lean/Workflow/Thm/SodPolicy.lean) | C3 for any policy set that contains P4 |

## Policies

| Policy | Text | Syntax tree used in the proofs |
| --- | --- | --- |
| P1 to P5 | [policies.cedar](../impl/policies.cedar) | [Policies.lean](../lean/Workflow/Policies.lean) |

The two versions are written separately. Their agreement is tested, not
proven: the differential test runs the text version in the Cedar engine and
the syntax trees in Cedar's Lean specification on the same requests.

## Checks on the proofs themselves

| Check | Where |
| --- | --- |
| No `sorry`, no `native_decide`, no axioms beyond `propext`, `Classical.choice`, `Quot.sound` | [check-axioms.sh](../scripts/check-axioms.sh), run in CI |
| Concrete decisions of each policy, and the delegation scenario, evaluated when the proofs are built | [Checks.lean](../lean/Workflow/Checks.lean) |
