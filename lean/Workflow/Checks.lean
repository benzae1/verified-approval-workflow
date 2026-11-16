import Workflow.Bridge
import Workflow.PlainGuard

/-!
# Concrete checks

Checks of the policies and the model on small concrete states. Lean
evaluates them at build time, and a false `#guard` fails the build. They show
the intended behaviour by example; the theorems cover all cases.
-/

namespace Workflow.Checks

open Workflow

/-- Run a list of steps from an initial state; return the final state and the
outcome of each step. -/
def run (guard : Guard) (approvers : List User) (steps : List (User × Action)) :
    State × List Bool :=
  steps.foldl (fun (s, out) (actor, a) =>
    let (s', ok) := step guard s actor a
    (s', out ++ [ok])) (State.init approvers, [])

/-- One open request by alice; bob is the only approver. -/
def s₁ : State := (run cedarGuard ["bob"] [("alice", .create "db migration")]).1

/-- The same, after bob has delegated approval rights to alice. -/
def s₂ : State := (step cedarGuard s₁ "bob" (.delegate "alice")).1

/-! ### The policies, one decision at a time -/

-- P1: anyone may create a request
#guard cedarGuard s₁ "carol" (.create "x")
-- P2: only the requester may edit
#guard cedarGuard s₁ "alice" (.edit 0 "y")
#guard !cedarGuard s₁ "bob" (.edit 0 "y")
-- P3: approvers decide; others do not
#guard cedarGuard s₁ "bob" (.approve 0)
#guard cedarGuard s₁ "bob" (.deny 0)
#guard !cedarGuard s₁ "carol" (.approve 0)
#guard !cedarGuard s₁ "carol" (.deny 0)
-- P4: the requester may not approve, not being an approver ...
#guard !cedarGuard s₁ "alice" (.approve 0)
-- ... and also not after being made one
#guard "alice" ∈ s₂.approvers
#guard !cedarGuard s₂ "alice" (.approve 0)
-- but may deny their own request once an approver (P4 only forbids approve)
#guard cedarGuard s₂ "alice" (.deny 0)
-- P5: only approvers delegate
#guard cedarGuard s₁ "bob" (.delegate "carol")
#guard !cedarGuard s₁ "alice" (.delegate "carol")

/-! ### The delegation scenario -/

def delegationTrace : List (User × Action) := [
  ("alice", .create "db migration"),   -- alice asks
  ("bob",   .delegate "alice"),        -- bob makes alice an approver
  ("alice", .approve 0),               -- alice tries to approve her own request
  ("bob",   .approve 0)]               -- bob approves it

#guard (run cedarGuard ["bob"] delegationTrace).2 = [true, true, false, true]
#guard (run plainGuard ["bob"] delegationTrace).2 = [true, true, false, true]
#guard (run cedarGuard ["bob"] delegationTrace).1.requests[0]?.map (·.decidedBy) = some (some "bob")

/-! ### Lifecycle -/

-- a decided request can be neither edited nor decided again
#guard (run cedarGuard ["bob", "carol"] [
    ("alice", .create "x"), ("bob", .deny 0),
    ("alice", .edit 0 "y"), ("carol", .approve 0), ("carol", .deny 0)]).2
  = [true, true, false, false, false]

/-! ### The two guards agree on these states -/

def sampleActions : List Action :=
  [.create "x", .edit 0 "y", .edit 1 "y", .approve 0, .approve 1, .deny 0, .deny 1,
   .delegate "alice", .delegate "dave"]

#guard [s₁, s₂].all fun s => ["alice", "bob", "carol"].all fun u =>
  sampleActions.all fun a => cedarGuard s u a == plainGuard s u a

end Workflow.Checks
