# Segregation of duties, proven and tested

A machine-checked proof that an approval workflow enforces segregation of
duties in every possible sequence of actions, including delegation of approval
rights, with automated tests that tie the proof to running code.

The workflow is small. A user files a request and may edit it while it is
open. An approver approves or denies it. Approvers can hand their approval
right to any other user. The question is the one an auditor asks: can anyone,
by any sequence of steps, end up approving their own request? A test suite
answers that for the sequences someone wrote down. The proof covers all of
them.

## The control and its theorem

In plain language: in every state the workflow can reach, from any starting
set of approvers, through any actions by any users in any order, an approved
request was approved by someone other than the person who requested it.

As checked by the proof assistant, in [SodPolicy.lean](lean/Workflow/Thm/SodPolicy.lean):

```lean
theorem segregation_of_duties {s : State} (h : Reachable cedarGuard s) :
    ∀ (id : ReqId) (r : Req),
      s.requests[id]? = some r → r.status = .approved → r.decidedBy ≠ some r.requester
```

For every reachable state `s` and every request `r` in it, if `r` is approved
then whoever decided it is not its requester. `Reachable` covers every finite
sequence of actions, so nothing is sampled. [Lean](https://lean-lang.org) is a
proof assistant: it checks each step of the proof, and the build fails if a
case is missing.

Four controls are proven this way.

| | Control | Theorem |
| --- | --- | --- |
| C1 | Decisions are final: an approved or denied request never changes again | `decisions_are_final` |
| C2 | The requester of a request cannot be changed, by editing or otherwise | `requester_is_immutable` |
| C3 | Segregation of duties: nobody approves their own request | `segregation_of_duties` |
| C4 | Only approvers decide: approving or denying takes effect only for a user who holds approval rights at that moment | `only_approvers_decide` |

[docs/traceability.md](docs/traceability.md) maps each control to its theorem,
its tests and the planted bugs that violate it.

## The delegation scenario

Approval processes are commonly circumvented through substitution: an approver
makes the requester their substitute, and the requester approves their own
request. In this example Bob starts as the only approver.

| Step | Who | Action | Result |
| --- | --- | --- | --- |
| 1 | Alice | files request 0 | accepted |
| 2 | Bob | delegates approval rights to Alice | accepted, Alice is now an approver |
| 3 | Alice | approves request 0 | refused, it is her own request |
| 4 | Bob | approves request 0 | accepted |

The theorem says step 3 is refused however the delegation is arranged,
repeated or chained. The rule that forbids self-approval never looks at who
holds approval rights, so redistributing those rights cannot weaken it.

## Two authorization mechanisms

Who may perform an action is decided by a guard, which is a parameter of the
model. The proofs are carried out for two guards.

| | Plain guard | Policy engine guard |
| --- | --- | --- |
| Authorization decided by | Ordinary conditions written in Lean | Five policies evaluated by the formal semantics of the Cedar policy engine |
| What the proof covers | The workflow rules alone, independent of any authorization product | The workflow rules together with a real policy engine, including the engine's failure modes |
| Theorem for C3 | `segregation_of_duties_plain` | `segregation_of_duties` |

Both use the same argument, `segregation_of_duties_of_noSelfApproval`:
segregation of duties holds for any guard that refuses to let a requester
approve their own request. Each of the two proofs then shows that its guard
has that property. C1 and C2 hold for every guard.

[Cedar](https://www.cedarpolicy.com) is used for the second guard because its
semantics are published as a Lean specification that other proofs can build
on. The plain guard does not depend on Cedar, and its proof carries over to
other authorization models.

## Proven, tested, assumed

| Proven | Tested | Assumed |
| --- | --- | --- |
| C1 to C4 hold in every reachable state of the model, which is the workflow written in Lean with Cedar's Lean specification deciding authorization. | The TypeScript implementation calls the official Cedar engine and behaves like the model: same decision and same resulting state at every step of 10,000 random action sequences on every push, and of 1,000,000 in a separate local run. | The Lean proof checker is correct. |
| The model's translation from workflow state to the policy engine's input always supplies what the policies read. | The five policies as text in [policies.cedar](impl/policies.cedar) mean the same as the five syntax trees used in the proofs. | Cedar's Lean specification describes what the Cedar engine does. The Cedar project tests this itself, and the differential test here checks it for these five policies. |
| The proofs contain no unfinished steps and use no axioms beyond Lean's three standard ones. CI checks this on every push. | Each of five planted bugs makes the differential test fail. | The model is the right definition of the workflow. |

Limits:

- The proof is about the model. The implementation is tested against the
  model and is not itself proven.
- The policies exist twice, as text and as syntax trees. Only the
  differential test catches a mismatch between the two.
- The translation into the policy engine's input is proven for the Lean
  version. The TypeScript version is separate code and is tested against it.
- Delegation is unlimited and permanent. Time limits and revocation are not
  modelled.
- Emergency access is not modelled.

## Planted bugs

Five bugs were planted in the implementation. Each is a one-line change of a
kind that occurs in real systems. Two test suites ran against each bug: ten
example-based unit tests, and the differential test against the model.

| Bug | What was changed | Unit tests (10) | Differential test | Traces until caught: median (range) |
| --- | --- | --- | --- | --- |
| M1 | The segregation-of-duties policy is deleted from the policy file (policy regression) | caught, 1 test fails | caught in 20 of 20 runs | 7 (1 to 47) |
| M2 | Editing a request copies `requester` from the input (mass assignment) | missed | caught in 20 of 20 runs | 27 (2 to 63) |
| M3 | Approving does not check that the request is still open (lifecycle flaw) | missed | caught in 20 of 20 runs | 7 (1 to 40) |
| M4 | The engine's input omits the `requester` attribute (skipped policy, see below) | caught, 2 tests fail | caught in 20 of 20 runs | 4 (1 to 25) |
| M5 | Approving skips the policy engine when the actor is an approver (a fast path) | caught, 1 test fails | caught in 20 of 20 runs | 7 (1 to 47) |

The unit tests caught 3 of the 5 bugs. The differential test caught all 5,
each within 63 random traces, in 20 runs with different seeds.

The same person wrote the unit tests and the bugs, so the comparison
illustrates the difference between the two kinds of test and does not measure
it. The unit tests were written first and were not changed afterwards. They
miss M2 and M3 because no test sends an extra field with an edit, and none
tries to approve a request that was already denied. The differential test
takes the expected outcome of every sequence from the model, so it does not
depend on someone having thought of the case. For each bug it reports a short
failing sequence. For M3:

```json
{"approvers":["bob"],"steps":[
  {"actor":"alice","action":"create","justification":""},
  {"actor":"bob","action":"delegate","to":"alice"},
  {"actor":"alice","action":"deny","id":0},
  {"actor":"bob","action":"approve","id":0}]}
```

Alice's request is denied in step 3 and approved in step 4.

## Skipped policies

Cedar evaluates each policy against data that the application supplies. If
evaluating a policy raises an error, for example because an attribute it reads
is missing, Cedar skips that policy. A skipped permit rule grants nothing. A
skipped forbid rule forbids nothing. An application that forgets to pass the
`requester` attribute therefore switches segregation of duties off, and the
policy file still looks correct in a review. Planted bug M4 does this: the
engine answers "allow" to a self-approval and mentions the skipped policy only
in its diagnostics.

The proof excludes this for the model. The lemma `forbidSelfApproval_satisfied`
states that the forbid rule is evaluated without error, and applies, whenever
a requester asks to approve their own request. It holds because the code that
prepares the engine's input always includes the attribute. With the attribute
removed from that code, the lemma no longer checks and the build fails.

Cedar can also validate its input against a schema on each call, and then
rejects the incomplete data. The implementation here leaves that validation
off, so M4 runs without it.

## Run everything

Requires [elan](https://lean-lang.org/install/), the Lean version manager,
and Node.js 22.18 or later.

```sh
(cd lean && lake build) && scripts/check-axioms.sh   # check all proofs and their axioms
(cd impl && npm ci && npm test)                      # typecheck, validate policies, unit tests, 10,000 traces
(cd impl && npm run test:mutants)                    # run both suites against the five planted bugs
```

The first build downloads Lean and the pinned Cedar specification and takes a
few minutes. Later builds check every proof in seconds. To run a single
sequence of actions through the model:

```sh
echo '{"approvers":["bob"],"steps":[
  {"actor":"alice","action":"create","justification":"db migration"},
  {"actor":"bob","action":"delegate","to":"alice"},
  {"actor":"alice","action":"approve","id":0},
  {"actor":"bob","action":"approve","id":0}]}' | tr -d '\n' | lean/.lake/build/bin/runner
```

## Where things are

```
lean/Workflow/Model.lean           the workflow: state, actions, one step, reachability
lean/Workflow/PlainGuard.lean      authorization as plain Lean conditions
lean/Workflow/Policies.lean        the five policies as syntax trees
lean/Workflow/Bridge.lean          from workflow state to the policy engine's input
lean/Workflow/Thm/                 the proofs: Finality (C1), Requester (C2),
                                   Sod, SodPlain, SodPolicy (C3), OnlyApprovers (C4)
lean/Workflow/Checks.lean          concrete examples evaluated at build time
lean/Main.lean                     runs sequences of actions through the model
impl/policies.cedar                the five policies as text
impl/src/                          the implementation: workflow.ts, entities.ts, mutants.ts
impl/test/unit/                    ten example-based tests
impl/test/differential/            random sequences, model against implementation
docs/traceability.md               controls, theorems, tests and planted bugs
docs/notes-on-cedar-spec.md        notes on building proofs on Cedar's specification
```

## Possible extensions

Emergency access is the closest one: a user obtains access immediately,
without prior approval, and a second person must review it afterwards. It adds
a review obligation and a second lifecycle to the model. The property to prove
becomes that every emergency access is reviewed, by someone other than the
person who used it. Others are delegation with time limits and revocation,
expiry of granted access, an audit log proven complete, and a single source
for the policies in place of the two versions kept here.

## Licence

Apache License 2.0, see [LICENSE](LICENSE). Cedar's Lean specification and the
Cedar engine, which this repository depends on, use the same licence.
