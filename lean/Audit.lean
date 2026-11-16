import Workflow

/-!
Prints the axioms that each of the main theorems depends on.
`scripts/check-axioms.sh` runs this file and fails if anything other than
Lean's three standard axioms (`propext`, `Classical.choice`, `Quot.sound`)
appears. It fails on `sorryAx`, which marks an unfinished proof, and on
`Lean.ofReduceBool` or `Lean.trustCompiler`, which mark a proof by
`native_decide`.
-/

#print axioms Workflow.decisions_are_final
#print axioms Workflow.requester_is_immutable
#print axioms Workflow.segregation_of_duties_plain
#print axioms Workflow.segregation_of_duties
#print axioms Workflow.segregation_of_duties_with
#print axioms Workflow.only_approvers_decide
