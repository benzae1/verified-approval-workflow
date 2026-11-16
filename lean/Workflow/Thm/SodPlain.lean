import Workflow.PlainGuard
import Workflow.Thm.Sod

/-!
# C3: segregation of duties with the plain guard
-/

namespace Workflow

theorem plainGuard_noSelfApproval : plainGuard.NoSelfApproval := by
  intro s actor id r hr hself
  simp [plainGuard, hr, hself]

/-- C3 for the plain guard: in every reachable state, an approved request was
approved by someone other than its requester, whatever delegations took
place. -/
theorem segregation_of_duties_plain {s : State} (h : Reachable plainGuard s) :
    ∀ (id : ReqId) (r : Req),
      s.requests[id]? = some r → r.status = .approved → r.decidedBy ≠ some r.requester :=
  segregation_of_duties_of_noSelfApproval plainGuard_noSelfApproval h

end Workflow
