import Workflow.Thm.Step

/-!
# C3: segregation of duties, for any guard that refuses self-approval

Proven once, for any guard with `NoSelfApproval`. `SodPlain.lean` and
`SodPolicy.lean` show that their guard has it.
-/

namespace Workflow

/-- The only property of a guard that segregation of duties needs: it never
lets a user approve their own request. Nothing is assumed about who holds
approval rights. -/
def Guard.NoSelfApproval (guard : Guard) : Prop :=
  ∀ (s : State) (actor : User) (id : ReqId) (r : Req),
    s.requests[id]? = some r → r.requester = actor → guard s actor (.approve id) = false

/-- The invariant: every approved request was approved by someone other than
its requester. -/
def SodInv (s : State) : Prop :=
  ∀ (id : ReqId) (r : Req),
    s.requests[id]? = some r → r.status = .approved → r.decidedBy ≠ some r.requester

theorem sodInv_init (approvers : List User) : SodInv (State.init approvers) := by
  intro id r hr
  simp [State.init] at hr

/-- Every step preserves the invariant. The only step that can newly approve a
request is an authorized `approve`, and the guard refuses that to the
requester. -/
theorem sodInv_step {guard : Guard} (hg : guard.NoSelfApproval)
    (s : State) (actor : User) (a : Action) (hinv : SodInv s) :
    SodInv (step guard s actor a).1 := by
  rcases step_cases guard s actor a with h | ⟨hguard, h⟩
  · rw [h]; exact hinv
  · intro id r' hr' happroved
    rcases apply_backward h hr' with hold | hnot | ⟨r, hr, hreq, hby, ha⟩
    · exact hinv id r' hold happroved
    · exact absurd happroved hnot
    · intro hself
      rw [hby, Option.some.injEq] at hself
      have hdeny := hg s actor id r hr (hreq.symm.trans hself.symm)
      rw [ha, hdeny] at hguard
      cases hguard

theorem sodInv_reaches {guard : Guard} (hg : guard.NoSelfApproval) {s s' : State}
    (h : Reaches guard s s') (hinv : SodInv s) : SodInv s' := by
  induction h with
  | refl => exact hinv
  | step actor a _ ih => exact sodInv_step hg _ actor a ih

/-- Segregation of duties for any guard that refuses self-approval: in every
reachable state, an approved request was approved by someone other than its
requester. -/
theorem segregation_of_duties_of_noSelfApproval {guard : Guard} (hg : guard.NoSelfApproval)
    {s : State} (h : Reachable guard s) :
    ∀ (id : ReqId) (r : Req),
      s.requests[id]? = some r → r.status = .approved → r.decidedBy ≠ some r.requester := by
  obtain ⟨approvers, hreach⟩ := h
  exact sodInv_reaches hg hreach (sodInv_init approvers)

end Workflow
