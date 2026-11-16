import Workflow.Thm.Step

/-!
# C2: the requester of a request cannot be changed

No action, by anyone, changes who the requester of an existing request is. In
particular `edit` only replaces the justification text. This holds for every
guard.
-/

namespace Workflow

/-- A single step keeps every existing request and its requester. -/
theorem step_preserves_requester (guard : Guard) (s : State) (actor : User) (a : Action)
    {id : ReqId} {r : Req} (hr : s.requests[id]? = some r) :
    ∃ r', (step guard s actor a).1.requests[id]? = some r' ∧ r'.requester = r.requester := by
  rcases step_cases guard s actor a with h | ⟨_, h⟩
  · rw [h]; exact ⟨r, hr, rfl⟩
  · obtain ⟨r', hr', hreq, _⟩ := apply_forward h hr
    exact ⟨r', hr', hreq⟩

/-- C2. A request that exists keeps existing, under the same identifier and
with the same requester, in every later state. -/
theorem requester_is_immutable {guard : Guard} {s s' : State} (h : Reaches guard s s')
    {id : ReqId} {r : Req} (hr : s.requests[id]? = some r) :
    ∃ r', s'.requests[id]? = some r' ∧ r'.requester = r.requester := by
  induction h with
  | refl => exact ⟨r, hr, rfl⟩
  | step actor a _ ih =>
    obtain ⟨r₁, hr₁, heq₁⟩ := ih
    obtain ⟨r₂, hr₂, heq₂⟩ := step_preserves_requester guard _ actor a hr₁
    exact ⟨r₂, hr₂, heq₂.trans heq₁⟩

end Workflow
