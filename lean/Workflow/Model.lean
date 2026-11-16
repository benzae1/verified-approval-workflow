/-!
# The approval workflow model

A user creates a request and may edit it while it is open. An approver
approves or denies it. Approvers may delegate their approval right to any
user.

A `Guard`, a parameter of `step`, decides who may act. `step` decides whether
the action is legal, i.e. whether the request is still open. There are two
guards: `plainGuard` (`Workflow/PlainGuard.lean`), a plain Lean function, and
`cedarGuard` (`Workflow/Bridge.lean`), which asks Cedar's formal semantics.
The theorems in `Workflow/Thm` take the guard as a parameter, so both share
one model and one invariant proof.
-/

namespace Workflow

/-- Users are identified by name. -/
abbrev User := String

/-- A request's position in `State.requests`. Requests are only appended, so
identifiers are unique and stable. -/
abbrev ReqId := Nat

inductive Status where
  | requested
  | approved
  | denied
  deriving DecidableEq, Repr, Inhabited

structure Req where
  requester     : User
  justification : String
  status        : Status
  /-- Who approved or denied the request; `none` while it is still open. -/
  decidedBy     : Option User
  deriving DecidableEq, Repr, Inhabited

structure State where
  /-- The users who currently hold approval rights. -/
  approvers : List User
  /-- All requests ever created; request `id` is `requests[id]`. -/
  requests  : List Req
  deriving DecidableEq, Repr, Inhabited

/-- The initial state: a set of approvers and no requests. -/
def State.init (approvers : List User) : State :=
  { approvers, requests := [] }

inductive Action where
  | create   (justification : String)
  | edit     (id : ReqId) (justification : String)
  | approve  (id : ReqId)
  | deny     (id : ReqId)
  | delegate (to : User)
  deriving DecidableEq, Repr, Inhabited

/-- A guard decides whether `actor` is authorized to perform an action in a
given state. Lifecycle checks are left to `step`. -/
abbrev Guard := State → User → Action → Bool

/-- Replace request `id` by `f` of itself, provided it exists and is still
open. Every change to an existing request goes through this function. -/
def updateOpen (s : State) (id : ReqId) (f : Req → Req) : Option State :=
  match s.requests[id]? with
  | some r =>
    if r.status = .requested
    then some { s with requests := s.requests.set id (f r) }
    else none
  | none => none

/-- The state change of an action that has already been authorized. Returns
`none` if the action is not legal in the current lifecycle status. -/
def apply (s : State) (actor : User) : Action → Option State
  | .create justification =>
    let r : Req :=
      { requester := actor, justification := justification, status := .requested, decidedBy := none }
    some { s with requests := s.requests ++ [r] }
  | .edit id justification =>
    updateOpen s id fun r => { r with justification := justification }
  | .approve id =>
    updateOpen s id fun r => { r with status := .approved, decidedBy := some actor }
  | .deny id =>
    updateOpen s id fun r => { r with status := .denied, decidedBy := some actor }
  | .delegate to =>
    some { s with approvers := if to ∈ s.approvers then s.approvers else s.approvers ++ [to] }

/-- One step. Returns the new state and whether the action took effect. A step
that is not authorized, or not legal in the current status, leaves the state
unchanged and returns `false`. -/
def step (guard : Guard) (s : State) (actor : User) (a : Action) : State × Bool :=
  if guard s actor a then
    match apply s actor a with
    | some s' => (s', true)
    | none    => (s, false)
  else (s, false)

/-- `Reaches guard s s'`: the workflow can get from `s` to `s'` in zero or more
steps, by any actors performing any actions. -/
inductive Reaches (guard : Guard) : State → State → Prop where
  | refl (s : State) : Reaches guard s s
  | step {s s' : State} (actor : User) (a : Action) :
      Reaches guard s s' → Reaches guard s (step guard s' actor a).1

/-- The states the workflow can ever be in, starting from any initial set of
approvers. -/
def Reachable (guard : Guard) (s : State) : Prop :=
  ∃ approvers, Reaches guard (State.init approvers) s

theorem Reaches.trans {guard : Guard} {s₁ s₂ s₃ : State}
    (h₁ : Reaches guard s₁ s₂) (h₂ : Reaches guard s₂ s₃) : Reaches guard s₁ s₃ := by
  induction h₂ with
  | refl => exact h₁
  | step actor a _ ih => exact .step actor a ih

end Workflow
