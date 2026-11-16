import Cedar.Spec
import Cedar.Thm.Authorization
import Cedar.Thm.Data.Map
import Workflow.Bridge
import Workflow.Thm.SodPolicy

/-!
# C4: only approvers decide

Whoever approves or denies a request holds approval rights at that moment.

C3 needed one satisfied forbid policy; C4 goes the other way. Cedar's
`allowed_only_if_explicitly_permitted` yields a satisfied permit policy. For
approve or deny that can only be P3, which is satisfied only for members of
the approver group.
-/

namespace Workflow

open Cedar.Spec Cedar.Data

/-- No request entity has a user's identifier. -/
theorem find?_requestEntities_user (rs : List Req) (first : Nat) (u : User) :
    (requestEntities rs first).find? (fun x => x.fst == userUID u) = none := by
  induction rs generalizing first with
  | nil => rfl
  | cons r₀ rs ih =>
    simp only [requestEntities, List.find?_cons]
    have : (requestEntity first r₀).fst ≠ userUID u := by
      simp [requestEntity, requestUID, userUID, requestType, userType]
    simp only [beq_eq_false_iff_ne.mpr this]
    exact ih (first + 1)

/-- A user who is not an approver has no entity, and therefore no parents. -/
theorem find?_toEntities_nonApprover (s : State) (u : User) (hu : u ∉ s.approvers) :
    (toEntities s).find? (userUID u) = none := by
  unfold toEntities
  rw [Map.make_find?_eq_list_find?]
  have hpre : ([(approversGroup, bareEntity), (defaultQueue, bareEntity)]
        ++ s.approvers.map approverEntity).find? (fun x => x.fst == userUID u) = none := by
    rw [List.find?_eq_none]
    intro x hx
    simp only [List.mem_append, List.mem_cons, List.mem_map, List.not_mem_nil, or_false] at hx
    rcases hx with (rfl | rfl) | ⟨v, hv, rfl⟩
    · simp [approversGroup, userUID, groupType, userType]
    · simp [defaultQueue, userUID, queueType, userType]
    · have : v ≠ u := fun h => hu (h ▸ hv)
      simpa [approverEntity, userUID] using this
  rw [entityList, List.find?_append, hpre, find?_requestEntities_user]
  rfl

/-- Membership in the approver group, as Cedar sees it, implies membership in
the model's list of approvers. -/
theorem approver_of_in_group (s : State) (u : User)
    (h : inₑ (userUID u) approversGroup (toEntities s) = true) : u ∈ s.approvers := by
  apply Classical.byContradiction
  intro hu
  have hnone := find?_toEntities_nonApprover s u hu
  have hne : (userUID u == approversGroup) = false := by
    simp [userUID, approversGroup, userType, groupType]
  simp [inₑ, hne, Entities.ancestorsOrEmpty, hnone, Set.contains, Set.empty] at h
  cases h

/-- If Cedar allows `actor` to approve or deny, then `actor` is an approver. -/
theorem cedarGuard_decide_approver (s : State) (actor : User) (a : Action)
    (ha : (∃ id, a = .approve id) ∨ (∃ id, a = .deny id))
    (hallow : cedarGuard s actor a = true) : actor ∈ s.approvers := by
  have hdec : (isAuthorized (toRequest actor a) (toEntities s) policies).decision = .allow := by
    simpa [cedarGuard, cedarGuardWith] using hallow
  obtain ⟨p, hp, heff, hsat⟩ := Cedar.Thm.allowed_only_if_explicitly_permitted _ _ _ hdec
  simp only [policies, List.mem_cons, List.not_mem_nil, or_false] at hp
  rcases ha with ⟨id, rfl⟩ | ⟨id, rfl⟩ <;>
  rcases hp with rfl | rfl | rfl | rfl | rfl
  -- P4 is a forbid policy
  case inl.inr.inr.inr.inl | inr.inr.inr.inr.inl => cases heff
  -- P3: the principal must be in the approver group
  case inl.inr.inr.inl | inr.inr.inr.inl =>
    apply approver_of_in_group
    cases hin : inₑ (userUID actor) approversGroup (toEntities s)
    · exfalso
      revert hsat
      eval_policy [permitApproversDecide, hin]
    · rfl
  -- P1, P2, P5 are about other actions
  all_goals
    exfalso
    revert hsat
    eval_policy [permitCreate, permitEditOwn, permitDelegate,
      createAction, editAction, approveAction, denyAction, delegateAction]
    split <;> simp_all

/-- C4. With Cedar as the guard, an approve or deny step only takes effect
if the actor holds approval rights in the state where the step is taken. -/
theorem only_approvers_decide (s : State) (actor : User) (a : Action)
    (ha : (∃ id, a = .approve id) ∨ (∃ id, a = .deny id))
    (heffect : (step cedarGuard s actor a).2 = true) : actor ∈ s.approvers := by
  apply cedarGuard_decide_approver s actor a ha
  unfold step at heffect
  split at heffect
  · assumption
  · cases heffect

end Workflow
