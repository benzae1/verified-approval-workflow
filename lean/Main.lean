import Lean.Data.Json
import Workflow

/-!
# Trace runner

Reads traces from standard input, one JSON document per line, runs each through
the model, and prints one line of JSON per trace: for every step, whether the
action took effect and the full state afterwards.

    echo '{"approvers":["bob"],"steps":[{"actor":"alice","action":"create","justification":"x"}]}' \
      | lake exe runner

`--guard cedar` (the default) uses Cedar's formal semantics as the guard,
`--guard plain` the stage A guard.
-/

open Lean (Json)
open Workflow

def actionOfJson (j : Json) : Except String Action := do
  let kind ← j.getObjValAs? String "action"
  match kind with
  | "create"   => return .create (← j.getObjValAs? String "justification")
  | "edit"     => return .edit (← j.getObjValAs? Nat "id") (← j.getObjValAs? String "justification")
  | "approve"  => return .approve (← j.getObjValAs? Nat "id")
  | "deny"     => return .deny (← j.getObjValAs? Nat "id")
  | "delegate" => return .delegate (← j.getObjValAs? String "to")
  | other      => throw s!"unknown action: {other}"

def reqToJson (id : Nat) (r : Req) : Json :=
  Json.mkObj [
    ("id", id),
    ("requester", r.requester),
    ("justification", r.justification),
    ("status", r.status.toString),
    ("decidedBy", match r.decidedBy with | some u => Json.str u | none => Json.null)]

def stateToJson (s : State) : Json :=
  Json.mkObj [
    ("approvers", Json.arr (s.approvers.map Json.str).toArray),
    ("requests", Json.arr (s.requests.zipIdx.map fun (r, id) => reqToJson id r).toArray)]

def runTrace (guard : Guard) (line : String) : Except String Json := do
  let j ← Json.parse line
  let approvers ← j.getObjValAs? (List String) "approvers"
  let steps ← j.getObjValAs? (Array Json) "steps"
  let mut s := State.init approvers
  let mut out : Array Json := #[]
  for st in steps do
    let actor ← st.getObjValAs? String "actor"
    let a ← actionOfJson st
    let (s', effect) := step guard s actor a
    s := s'
    out := out.push <| Json.mkObj [
      ("decision", if effect then "allow" else "deny"),
      ("state", stateToJson s)]
  return Json.arr out

partial def loop (guard : Guard) (stdin stdout : IO.FS.Stream) : IO Unit := do
  let line ← stdin.getLine
  if line.isEmpty then return
  if !line.trimAscii.isEmpty then
    match runTrace guard line with
    | .ok j    => do stdout.putStrLn j.compress; stdout.flush
    | .error e => throw <| IO.userError s!"bad trace: {e}"
  loop guard stdin stdout

def main (args : List String) : IO UInt32 := do
  let guard ← match args with
    | [] | ["--guard", "cedar"] => pure cedarGuard
    | ["--guard", "plain"]      => pure plainGuard
    | _ =>
      IO.eprintln "usage: runner [--guard cedar|plain] < traces.jsonl"
      return 2
  loop guard (← IO.getStdin) (← IO.getStdout)
  (← IO.getStdout).flush
  return 0
