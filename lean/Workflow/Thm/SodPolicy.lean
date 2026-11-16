import Cedar.Spec
import Cedar.Thm.Authorization
import Cedar.Thm.Data.Map
import Workflow.Bridge
import Workflow.Thm.Sod

/-!
# C3: segregation of duties with Cedar as the guard

Four parts:

1. The bridge lemma `forbidSelfApproval_satisfied`, proven here: for every
   state and every request in it, P4 is satisfied when the requester asks to
   approve, evaluated against the entities from `toEntities`.
2. `Cedar.Thm.forbid_trumps_permit`, from Cedar's own proofs: a satisfied
   forbid policy means deny.
3. The guard lemma `cedarGuard_noSelfApproval`, from 1 and 2.
4. The invariant, proven for all guards in `Workflow/Thm/Sod.lean`.

The bridge lemma never mentions the approver group, so delegation cannot
weaken it: making the requester an approver changes nothing P4 reads.

It also rules out a skipped policy. A forbid policy whose evaluation errors is
skipped and denies nothing. P4 reads `resource.requester`, and the lemma holds
because `requestEntity` always sets it and `toEntities` always includes the
request.
-/

namespace Workflow

open Cedar.Spec Cedar.Data

/-! ### Looking up a request in the entity store -/

/-- Distinct request identifiers give distinct entity identifiers. -/
theorem requestUID_inj {i j : Nat} : requestUID i = requestUID j ↔ i = j := by
  simp [requestUID, Nat.repr_inj]

@[simp] theorem requestUID_ty (id : Nat) : (requestUID id).ty = requestType := rfl

/-- Searching the request entities for request `id` finds exactly the entity
built from request `id`. -/
theorem find?_requestEntities (rs : List Req) (first id : Nat) (r : Req)
    (hle : first ≤ id) (hr : rs[id - first]? = some r) :
    (requestEntities rs first).find? (fun x => x.fst == requestUID id)
      = some (requestEntity id r) := by
  induction rs generalizing first with
  | nil => simp at hr
  | cons r₀ rs ih =>
    by_cases h : first = id
    · subst h
      simp at hr
      subst hr
      simp [requestEntities, requestEntity]
    · have hlt : first < id := by omega
      have hsub : id - first = (id - (first + 1)) + 1 := by omega
      rw [hsub] at hr
      simp only [List.getElem?_cons_succ] at hr
      have ih' := ih (first + 1) (by omega) hr
      have hne : (requestEntity first r₀).fst ≠ requestUID id := by
        simpa [requestEntity, requestUID_inj] using h
      simp only [requestEntities, List.find?_cons, beq_eq_false_iff_ne.mpr hne]
      exact ih'

/-- The entity store of a state contains every request of that state, with the
attributes built by `requestEntity`. -/
theorem find?_toEntities_request (s : State) (id : Nat) (r : Req)
    (hr : s.requests[id]? = some r) :
    (toEntities s).find? (requestUID id) = some (requestEntity id r).snd := by
  unfold toEntities
  rw [Map.make_find?_eq_list_find?]
  have hreq := find?_requestEntities s.requests 0 id r (by omega) (by simpa using hr)
  have hpre : ([(approversGroup, bareEntity), (defaultQueue, bareEntity)]
        ++ s.approvers.map approverEntity).find? (fun x => x.fst == requestUID id) = none := by
    rw [List.find?_eq_none]
    intro x hx
    simp only [List.mem_append, List.mem_cons, List.mem_map, List.not_mem_nil, or_false] at hx
    rcases hx with (rfl | rfl) | ⟨u, _, rfl⟩ <;>
      simp [approversGroup, defaultQueue, approverEntity, userUID, requestUID,
        groupType, queueType, userType, requestType]
  rw [entityList, List.find?_append, hpre, hreq]
  rfl

/-! ### The bridge lemma -/

/-- Unfolds the evaluation of a policy on a concrete request. -/
macro "eval_policy" "[" ts:Lean.Parser.Tactic.simpLemma,* "]" : tactic =>
  `(tactic| simp [satisfied, Policy.toExpr, PrincipalScope.toExpr, ActionScope.toExpr,
      ResourceScope.toExpr, Scope.toExpr, Conditions.toExpr, Condition.toExpr, evaluate,
      toRequest, Var.eqEntityUID, Var.inEntityUID, Var.isEntityType,
      resourceRequesterIsPrincipal, Result.as, apply₁, apply₂, getAttr, attrsOf,
      Entities.attrs, Map.findOrErr, Value.asBool, Coe.coe, $ts,*])

/-- The bridge lemma. Policy P4 is satisfied whenever the requester of an
existing request asks to approve it. Its evaluation therefore raises no error,
and Cedar does not skip it. -/
theorem forbidSelfApproval_satisfied (s : State) (id : Nat) (r : Req)
    (hr : s.requests[id]? = some r) :
    satisfied forbidSelfApproval (toRequest r.requester (.approve id)) (toEntities s) = true := by
  have hfind := find?_toEntities_request s id r hr
  eval_policy [forbidSelfApproval, hfind, requestEntity, Map.make_find?_eq_list_find?]

/-! ### From the bridge lemma to the guard -/

/-- Any policy set that contains P4 denies self-approval, whatever else it
contains: by Cedar's `forbid_trumps_permit`, no permit can override it. -/
theorem cedarGuardWith_noSelfApproval (ps : Policies) (hmem : forbidSelfApproval ∈ ps) :
    (cedarGuardWith ps).NoSelfApproval := by
  intro s actor id r hr hself
  subst hself
  have hforbidden : Cedar.Thm.IsExplicitlyForbidden
      (toRequest r.requester (.approve id)) (toEntities s) ps :=
    ⟨forbidSelfApproval, hmem, rfl, forbidSelfApproval_satisfied s id r hr⟩
  have hdeny := Cedar.Thm.forbid_trumps_permit _ _ _ hforbidden
  simp [cedarGuardWith, hdeny]

theorem cedarGuard_noSelfApproval : cedarGuard.NoSelfApproval :=
  cedarGuardWith_noSelfApproval policies (by simp [policies])

/-! ### The theorem -/

/-- C3 for the Cedar guard. With Cedar's authorizer and the workflow's five
policies as the guard, in every reachable state an approved request was
approved by someone other than its requester, whatever delegations took
place. -/
theorem segregation_of_duties {s : State} (h : Reachable cedarGuard s) :
    ∀ (id : ReqId) (r : Req),
      s.requests[id]? = some r → r.status = .approved → r.decidedBy ≠ some r.requester :=
  segregation_of_duties_of_noSelfApproval cedarGuard_noSelfApproval h

/-- The same for any policy set that contains P4: adding, removing or changing
other policies cannot break segregation of duties. -/
theorem segregation_of_duties_with (ps : Policies) (hmem : forbidSelfApproval ∈ ps)
    {s : State} (h : Reachable (cedarGuardWith ps) s) :
    ∀ (id : ReqId) (r : Req),
      s.requests[id]? = some r → r.status = .approved → r.decidedBy ≠ some r.requester :=
  segregation_of_duties_of_noSelfApproval (cedarGuardWith_noSelfApproval ps hmem) h

end Workflow
