import Cedar.Spec
import Workflow.Policies

/-!
# From the workflow model to the policy engine

`toEntities` and `toRequest` translate a model state and an action into the
inputs of Cedar's authorizer. `cedarGuard` is the guard that asks Cedar.

An error in this translation can disable a policy. If `requestEntity` left out
the `requester` attribute, policy P4 would raise an error on every evaluation,
Cedar would skip it, and self-approval would be allowed.
`Workflow/Thm/SodPolicy.lean` proves that P4 is evaluated without error.
-/

namespace Workflow

open Cedar.Spec Cedar.Data

def Status.toString : Status → String
  | .requested => "Requested"
  | .approved  => "Approved"
  | .denied    => "Denied"

/-- An entity with no attributes and no parents. -/
def bareEntity : EntityData :=
  { attrs := Map.empty, ancestors := Set.empty, tags := Map.empty }

/-- A user with approval rights: a member of `Group::"approvers"`. -/
def approverEntity (u : User) : EntityUID × EntityData :=
  (userUID u, { attrs := Map.empty, ancestors := Set.make [approversGroup], tags := Map.empty })

/-- A request, with its `requester` and `status` attributes. -/
def requestEntity (id : ReqId) (r : Req) : EntityUID × EntityData :=
  (requestUID id,
   { attrs := Map.make [
       ("requester", .prim (.entityUID (userUID r.requester))),
       ("status",    .prim (.string r.status.toString))],
     ancestors := Set.empty,
     tags := Map.empty })

/-- The entities for the requests `rs`, numbered from `first`. -/
def requestEntities : List Req → ReqId → List (EntityUID × EntityData)
  | [],      _     => []
  | r :: rs, first => requestEntity first r :: requestEntities rs (first + 1)

/-- All entities of a state, as a list: the approver group, the queue, one
entity per approver, one per request. Users without approval rights need no
entity: they have no attributes and no parents. -/
def entityList (s : State) : List (EntityUID × EntityData) :=
  [(approversGroup, bareEntity), (defaultQueue, bareEntity)]
    ++ s.approvers.map approverEntity
    ++ requestEntities s.requests 0

/-- The entity store handed to the policy engine. -/
def toEntities (s : State) : Entities :=
  Map.make (entityList s)

/-- The authorization request for `actor` performing `a`. -/
def toRequest (actor : User) (a : Action) : Request :=
  let (action, resource) : EntityUID × EntityUID :=
    match a with
    | .create _    => (createAction,   defaultQueue)
    | .edit id _   => (editAction,     requestUID id)
    | .approve id  => (approveAction,  requestUID id)
    | .deny id     => (denyAction,     requestUID id)
    | .delegate to => (delegateAction, userUID to)
  { principal := userUID actor, action, resource, context := Map.empty }

/-- A guard that asks Cedar's authorizer, with the given policy set. -/
def cedarGuardWith (policies : Policies) : Guard := fun s actor a =>
  (isAuthorized (toRequest actor a) (toEntities s) policies).decision == .allow

/-- Cedar's authorizer with the workflow's five policies. -/
def cedarGuard : Guard := cedarGuardWith policies

end Workflow
