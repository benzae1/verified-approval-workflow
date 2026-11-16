import Workflow.Model

/-!
# What a single step can do to a request

The effect of one authorized action on the requests, seen forward from the
old state and backward from the new one. Used by C1, C2 and C3.
-/

namespace Workflow

/-- A step either leaves the state unchanged, or it was authorized by the guard
and `apply` produced the new state. -/
theorem step_cases (guard : Guard) (s : State) (actor : User) (a : Action) :
    (step guard s actor a).1 = s ∨
    (guard s actor a = true ∧ apply s actor a = some (step guard s actor a).1) := by
  unfold step
  split
  · rename_i hg
    split
    · rename_i s' hs'
      exact .inr ⟨hg, hs'⟩
    · exact .inl rfl
  · exact .inl rfl

/-- `updateOpen`, seen from the old state: every request is still there, and it
is unchanged unless it is the open request being updated. -/
theorem updateOpen_forward {s s' : State} {id' : ReqId} {f : Req → Req}
    (h : updateOpen s id' f = some s') {id : ReqId} {r : Req}
    (hr : s.requests[id]? = some r) :
    s'.requests[id]? = some r ∨
    (id' = id ∧ r.status = .requested ∧ s'.requests[id]? = some (f r)) := by
  have hlt : id < s.requests.length := (List.getElem?_eq_some_iff.mp hr).1
  unfold updateOpen at h
  split at h
  case h_2 => cases h
  case h_1 r₀ hr₀ =>
    split at h
    case isFalse => cases h
    case isTrue hopen =>
      cases h
      by_cases hid : id' = id
      · subst hid
        rw [hr] at hr₀; cases hr₀
        exact .inr ⟨rfl, hopen, by simp [List.getElem?_set_self hlt]⟩
      · exact .inl (by simp [List.getElem?_set_ne hid, hr])

/-- `updateOpen`, seen from the new state: every request was there before, and
is unchanged unless it is the open request that was updated. -/
theorem updateOpen_backward {s s' : State} {id' : ReqId} {f : Req → Req}
    (h : updateOpen s id' f = some s') {id : ReqId} {r' : Req}
    (hr' : s'.requests[id]? = some r') :
    s.requests[id]? = some r' ∨
    (id' = id ∧ ∃ r, s.requests[id]? = some r ∧ r.status = .requested ∧ r' = f r) := by
  unfold updateOpen at h
  split at h
  case h_2 => cases h
  case h_1 r₀ hr₀ =>
    split at h
    case isFalse => cases h
    case isTrue hopen =>
      cases h
      have hlt : id' < s.requests.length := (List.getElem?_eq_some_iff.mp hr₀).1
      by_cases hid : id' = id
      · subst hid
        simp only [List.getElem?_set_self hlt, Option.some.injEq] at hr'
        exact .inr ⟨rfl, r₀, hr₀, hopen, hr'.symm⟩
      · simp only [List.getElem?_set_ne hid] at hr'
        exact .inl hr'

/-- Forward: an existing request still exists after the action, with the same
requester; and if it was already decided, it is entirely unchanged. -/
theorem apply_forward {s s' : State} {actor : User} {a : Action}
    (h : apply s actor a = some s') {id : ReqId} {r : Req}
    (hr : s.requests[id]? = some r) :
    ∃ r', s'.requests[id]? = some r' ∧ r'.requester = r.requester ∧
      (r.status ≠ .requested → r' = r) := by
  have hlt : id < s.requests.length := (List.getElem?_eq_some_iff.mp hr).1
  cases a <;> simp only [apply] at h
  case create j =>
    cases h
    exact ⟨r, by simp [List.getElem?_append_left hlt, hr], rfl, fun _ => rfl⟩
  case delegate to =>
    cases h
    exact ⟨r, hr, rfl, fun _ => rfl⟩
  all_goals
    rcases updateOpen_forward h hr with hsame | ⟨_, hopen, hnew⟩
    · exact ⟨r, hsame, rfl, fun _ => rfl⟩
    · exact ⟨_, hnew, rfl, fun hd => absurd hopen hd⟩

/-- Backward: every request in the new state is either unchanged, or not
approved, or has just been approved by `actor` through the action
`approve id`, keeping its requester. -/
theorem apply_backward {s s' : State} {actor : User} {a : Action}
    (h : apply s actor a = some s') {id : ReqId} {r' : Req}
    (hr' : s'.requests[id]? = some r') :
    s.requests[id]? = some r' ∨
    r'.status ≠ .approved ∨
    (∃ r, s.requests[id]? = some r ∧ r'.requester = r.requester ∧
      r'.decidedBy = some actor ∧ a = .approve id) := by
  cases a <;> simp only [apply] at h
  case create j =>
    cases h
    simp only [List.getElem?_append] at hr'
    split at hr'
    · exact .inl hr'
    · -- the newly created request is open
      refine .inr (.inl ?_)
      cases hk : id - s.requests.length <;> simp [hk] at hr'
      rw [← hr']
      simp
  case delegate to =>
    cases h
    exact .inl hr'
  case edit id' j =>
    rcases updateOpen_backward h hr' with hsame | ⟨_, r, _, hopen, hnew⟩
    · exact .inl hsame
    · exact .inr (.inl (by simp [hnew, hopen]))
  case deny id' =>
    rcases updateOpen_backward h hr' with hsame | ⟨_, r, _, _, hnew⟩
    · exact .inl hsame
    · exact .inr (.inl (by simp [hnew]))
  case approve id' =>
    rcases updateOpen_backward h hr' with hsame | ⟨hid, r, hr, _, hnew⟩
    · exact .inl hsame
    · exact .inr (.inr ⟨r, hr, by simp [hnew], by simp [hnew], by rw [hid]⟩)

end Workflow
