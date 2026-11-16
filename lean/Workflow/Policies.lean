import Cedar.Spec
import Workflow.Model

/-!
# The five policies, as Cedar syntax trees

Cedar's Lean specification does not parse policy text, so the policies are
written here directly as abstract syntax. The same policies exist a second time
as text in `impl/policies.cedar`; each definition below quotes the text it
mirrors. The differential test is what ties the two together.
-/

namespace Workflow

open Cedar.Spec

/-! ### Entity types and identifiers -/

def userType    : EntityType := { id := "User",    path := [] }
def groupType   : EntityType := { id := "Group",   path := [] }
def requestType : EntityType := { id := "Request", path := [] }
def queueType   : EntityType := { id := "Queue",   path := [] }
def actionType  : EntityType := { id := "Action",  path := [] }

/-- `User::"<name>"` -/
def userUID (u : User) : EntityUID := { ty := userType, eid := u }

/-- `Request::"<id>"`, with the identifier written in decimal. -/
def requestUID (id : ReqId) : EntityUID := { ty := requestType, eid := Nat.repr id }

/-- `Group::"approvers"` -/
def approversGroup : EntityUID := { ty := groupType, eid := "approvers" }

/-- `Queue::"default"` -/
def defaultQueue : EntityUID := { ty := queueType, eid := "default" }

def createAction   : EntityUID := { ty := actionType, eid := "createRequest" }
def editAction     : EntityUID := { ty := actionType, eid := "editRequest" }
def approveAction  : EntityUID := { ty := actionType, eid := "approve" }
def denyAction     : EntityUID := { ty := actionType, eid := "deny" }
def delegateAction : EntityUID := { ty := actionType, eid := "delegate" }

/-- The expression `resource.requester == principal`. -/
def resourceRequesterIsPrincipal : Expr :=
  .binaryApp .eq (.getAttr (.var .resource) "requester") (.var .principal)

/-! ### The policies -/

/--
```cedar
// P1: any user may create a request
permit (principal is User, action == Action::"createRequest", resource is Queue);
```
-/
def permitCreate : Policy := {
  id             := "P1",
  effect         := .permit,
  principalScope := .principalScope (.is userType),
  actionScope    := .actionScope (.eq createAction),
  resourceScope  := .resourceScope (.is queueType),
  condition      := []
}

/--
```cedar
// P2: the requester may edit their own request
permit (principal is User, action == Action::"editRequest", resource is Request)
when { resource.requester == principal };
```
-/
def permitEditOwn : Policy := {
  id             := "P2",
  effect         := .permit,
  principalScope := .principalScope (.is userType),
  actionScope    := .actionScope (.eq editAction),
  resourceScope  := .resourceScope (.is requestType),
  condition      := [⟨.when, resourceRequesterIsPrincipal⟩]
}

/--
```cedar
// P3: approvers decide
permit (principal in Group::"approvers",
        action in [Action::"approve", Action::"deny"],
        resource is Request);
```
-/
def permitApproversDecide : Policy := {
  id             := "P3",
  effect         := .permit,
  principalScope := .principalScope (.mem approversGroup),
  actionScope    := .actionInAny [approveAction, denyAction],
  resourceScope  := .resourceScope (.is requestType),
  condition      := []
}

/--
```cedar
// P4: segregation of duties
forbid (principal, action == Action::"approve", resource is Request)
when { resource.requester == principal };
```
-/
def forbidSelfApproval : Policy := {
  id             := "P4",
  effect         := .forbid,
  principalScope := .principalScope .any,
  actionScope    := .actionScope (.eq approveAction),
  resourceScope  := .resourceScope (.is requestType),
  condition      := [⟨.when, resourceRequesterIsPrincipal⟩]
}

/--
```cedar
// P5: approvers may delegate their approval right
permit (principal in Group::"approvers", action == Action::"delegate", resource is User);
```
-/
def permitDelegate : Policy := {
  id             := "P5",
  effect         := .permit,
  principalScope := .principalScope (.mem approversGroup),
  actionScope    := .actionScope (.eq delegateAction),
  resourceScope  := .resourceScope (.is userType),
  condition      := []
}

/-- The policy set of the workflow. -/
def policies : Policies :=
  [permitCreate, permitEditOwn, permitApproversDecide, forbidSelfApproval, permitDelegate]

end Workflow
