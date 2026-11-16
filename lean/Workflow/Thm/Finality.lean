import Workflow.Thm.Step

/-!
# C1: decisions are final

Once a request is approved or denied, no action by anyone changes it. This
holds for every guard: it is a property of the lifecycle, not of authorization.
-/

namespace Workflow

/-- A decided request is untouched by any single step. -/
theorem step_preserves_decided (guard : Guard) (s : State) (actor : User) (a : Action)
    {id : ReqId} {r : Req}
    (hr : s.requests[id]? = some r) (hd : r.status ≠ .requested) :
    (step guard s actor a).1.requests[id]? = some r := by
  rcases step_cases guard s actor a with h | ⟨_, h⟩
  · rw [h]; exact hr
  · obtain ⟨r', hr', _, hsame⟩ := apply_forward h hr
    rw [hr', hsame hd]

/-- **C1.** Once a request is approved or denied, it stays exactly as it is in
every later state: same status, same decider, same requester, same text. -/
theorem decisions_are_final {guard : Guard} {s s' : State} (h : Reaches guard s s')
    {id : ReqId} {r : Req}
    (hr : s.requests[id]? = some r) (hd : r.status ≠ .requested) :
    s'.requests[id]? = some r := by
  induction h with
  | refl => exact hr
  | step actor a _ ih => exact step_preserves_decided guard _ actor a ih hd

end Workflow
