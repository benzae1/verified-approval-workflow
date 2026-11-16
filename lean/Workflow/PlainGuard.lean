import Workflow.Model

/-!
# A guard written as ordinary Lean conditions

`plainGuard` uses no policy engine. It states the authorization rules of the
workflow directly:

* anyone may create a request;
* only the requester may edit a request;
* only approvers may approve, deny and delegate;
* nobody may approve their own request.
-/

namespace Workflow

def plainGuard : Guard := fun s actor a =>
  match a with
  | .create _   => true
  | .edit id _  =>
    match s.requests[id]? with
    | some r => r.requester == actor
    | none   => false
  | .approve id =>
    actor ∈ s.approvers &&
    match s.requests[id]? with
    | some r => r.requester != actor
    | none   => true   -- no such request: `step` rejects the action anyway
  | .deny _     => actor ∈ s.approvers
  | .delegate _ => actor ∈ s.approvers

end Workflow
