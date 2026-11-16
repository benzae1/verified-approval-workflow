# Segregation of duties, proven and tested

A machine-checked proof that an approval workflow enforces segregation of
duties under every sequence of actions, delegation included, plus tests that
tie the proof to running code.

A user files a request and may edit it while it is open. An approver approves
or denies it. Approvers can pass their approval right to any user. Can anyone,
by some sequence of steps, approve their own request? Tests answer that for
the sequences someone wrote down. The proof answers it for all of them.

## The theorem

In every state the workflow can reach, from any initial approvers, through
any actions by anyone in any order, an approved request was approved by
someone other than its requester.

In [SodPolicy.lean](lean/Workflow/Thm/SodPolicy.lean):

```lean
theorem segregation_of_duties {s : State} (h : Reachable cedarGuard s) :
    ∀ (id : ReqId) (r : Req),
      s.requests[id]? = some r → r.status = .approved → r.decidedBy ≠ some r.requester
```

`Reachable` covers every finite action sequence, so nothing is sampled.
[Lean](https://lean-lang.org) checks every step of the proof, and a missing
case fails the build.

Four controls are proven:

| | Control | Theorem |
| --- | --- | --- |
| C1 | Decisions are final: an approved or denied request never changes again | `decisions_are_final` |
| C2 | The requester of a request cannot be changed, by editing or otherwise | `requester_is_immutable` |
| C3 | Segregation of duties: nobody approves their own request | `segregation_of_duties` |
| C4 | Only approvers decide: approve or deny takes effect only for a user holding approval rights at that moment | `only_approvers_decide` |

[docs/traceability.md](docs/traceability.md) maps each control to its theorem,
its tests and the planted bugs that break it.

## Delegation

The usual way around an approval process is substitution: the approver makes
the requester their substitute, and the requester approves their own request.
Bob starts as the only approver:

| Step | Who | Action | Result |
| --- | --- | --- | --- |
| 1 | Alice | files request 0 | accepted |
| 2 | Bob | delegates approval rights to Alice | accepted, Alice is now an approver |
| 3 | Alice | approves request 0 | refused, it is her own request |
| 4 | Bob | approves request 0 | accepted |

Step 3 is refused however the delegation is arranged, repeated or chained. The
rule against self-approval never reads who holds approval rights, so moving
those rights around cannot weaken it.

## Two guards

A guard, which is a parameter of the model, decides who may act. Everything is
proven for two guards:

| | Plain guard | Policy engine guard |
| --- | --- | --- |
| Decides by | Plain Lean conditions | Five policies, evaluated by the formal semantics of the Cedar policy engine |
| Proof covers | The workflow rules alone, with no authorization product | The workflow rules plus a real policy engine, including its failure modes |
| C3 theorem | `segregation_of_duties_plain` | `segregation_of_duties` |

Both rest on `segregation_of_duties_of_noSelfApproval`: segregation of duties
holds for any guard that refuses self-approval. Each guard is then shown to
have that property. C1 and C2 hold for every guard.

[Cedar](https://www.cedarpolicy.com) was chosen because its semantics are
published as a Lean specification that other proofs can build on. The plain
guard does not depend on Cedar, and its proof carries over to other
authorization models.

## Proven, tested, assumed

| Proven | Tested | Assumed |
| --- | --- | --- |
| C1 to C4 hold in every reachable state of the model: the workflow in Lean, with Cedar's Lean specification deciding authorization. | The TypeScript implementation, which calls the official Cedar engine, matches the model in decision and resulting state at every step: 10,000 random sequences on every push, 1,000,000 in a separate local run. | The Lean proof checker is correct. |
| The model's translation into the engine's input always supplies the attribute the segregation-of-duties policy (P4) reads, so P4 is never skipped. | The policy text in [policies.cedar](impl/policies.cedar) means the same as the syntax trees in the proofs. | Cedar's Lean specification describes the Cedar engine. The Cedar project tests this, and the differential test here checks it for these five policies. |
| No unfinished proofs and no axioms beyond Lean's standard three. CI checks this on every push. | Each of five planted bugs fails the differential test. | The model is the right definition of the workflow. |

Limits:

- The proof is about the model. The implementation is tested against it, not
  proven.
- The policies exist twice, as text and as syntax trees. Only the
  differential test would catch the two drifting apart.
- The translation into the engine's input is proven in Lean. The TypeScript
  copy is only tested.
- Delegation is unlimited and permanent: no time limits, no revocation.
- Emergency access is not modelled.

## Planted bugs

Five one-line bugs, each of a kind found in real systems, run against two
suites: ten example-based unit tests and the differential test.

| Bug | What was changed | Unit tests (10) | Differential test | Traces until caught: median (range) |
| --- | --- | --- | --- | --- |
| M1 | The segregation-of-duties policy is deleted from the policy file (policy regression) | caught, 1 test fails | caught in 20 of 20 runs | 7 (1 to 47) |
| M2 | Editing a request copies `requester` from the input (mass assignment) | missed | caught in 20 of 20 runs | 27 (2 to 63) |
| M3 | Approving does not check that the request is still open (lifecycle flaw) | missed | caught in 20 of 20 runs | 7 (1 to 40) |
| M4 | The engine's input omits the `requester` attribute (skipped policy, see below) | caught, 2 tests fail | caught in 20 of 20 runs | 4 (1 to 25) |
| M5 | Denying skips the policy engine, so anyone can deny a request (missing authorization check) | caught, 1 test fails | caught in 20 of 20 runs | 6 (1 to 26) |

The unit tests caught 3 of 5. The differential test caught all 5 in each of 20
seeded runs, within at most 63 traces.

The same person wrote the unit tests and the bugs, so this illustrates the
difference between the two kinds of test without measuring it. The unit tests
miss M2 because none sends an extra field with an edit, and M3 because none
approves a request that was already denied. The differential test takes every
expected outcome from the model, so nobody has to think of the case. It
reports a short failing sequence for each bug. For M3:

```json
{"approvers":["bob"],"steps":[
  {"actor":"alice","action":"create","justification":""},
  {"actor":"bob","action":"delegate","to":"alice"},
  {"actor":"alice","action":"deny","id":0},
  {"actor":"bob","action":"approve","id":0}]}
```

Alice's request is denied in step 3, then approved in step 4.

## Skipped policies

Cedar evaluates each policy against data the application supplies. If
evaluation raises an error, for example because an attribute is missing, Cedar
skips the policy: a skipped permit grants nothing, a skipped forbid forbids
nothing. An application that forgets to pass `requester` has switched off
segregation of duties, and the policy file still passes review. M4 does this:
the engine allows a self-approval and mentions the skipped policy only in its
diagnostics.

The proof rules this out for the model. `forbidSelfApproval_satisfied` states
that the forbid rule evaluates without error, and applies, whenever a
requester tries to approve their own request. It holds because the code that
builds the engine's input always includes the attribute. Remove it there and
the lemma, and so the build, fails.

Cedar can also validate input against a schema on each call, which would
reject the incomplete data. The implementation leaves this off, so M4 runs
without it.

## Running it

Needs [elan](https://lean-lang.org/install/), the Lean version manager, and
Node.js 22.18 or later.

```sh
(cd lean && lake build) && scripts/check-axioms.sh   # check all proofs and their axioms
(cd impl && npm ci && npm test)                      # typecheck, validate policies, unit tests, 10,000 traces
(cd impl && npm run test:mutants)                    # run both suites against the five planted bugs
```

The first build downloads Lean and the pinned Cedar specification and takes a
few minutes. After that the proofs check in seconds. To run one sequence
through the model:

```sh
echo '{"approvers":["bob"],"steps":[
  {"actor":"alice","action":"create","justification":"db migration"},
  {"actor":"bob","action":"delegate","to":"alice"},
  {"actor":"alice","action":"approve","id":0},
  {"actor":"bob","action":"approve","id":0}]}' | tr -d '\n' | lean/.lake/build/bin/runner
```

## Layout

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

## Extensions

Emergency access is the nearest extension: a user gets access immediately,
without approval, and a second person reviews it afterwards. That adds a
review obligation and a second lifecycle. The property to prove becomes that
every emergency access is reviewed by someone other than the person who used
it. Further out: delegation with time limits and revocation, expiring access,
an audit log proven complete, and one source for the policies instead of two.

## Licence

Apache License 2.0, see [LICENSE](LICENSE). Cedar's Lean specification and the
Cedar engine, which this repository depends on, use the same licence.
