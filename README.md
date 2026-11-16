# Segregation of duties, proven and tested

A machine-checked proof that an approval workflow enforces segregation of
duties in every possible sequence of actions, including delegation of approval
rights, with automated tests that tie the proof to running code.

The workflow is small on purpose: a user files a request, may edit it while it
is open, and an approver approves or denies it. Approvers can hand their
approval right to anyone. The question is the one an auditor asks: *can anyone,
by any sequence of steps, end up approving their own request?*

A test suite answers that for the sequences someone thought of. The proof here
answers it for all of them.

## The control and its theorem

**In plain language.** In every state the workflow can ever reach, from any
starting set of approvers, through any actions by any users in any order: if a
request is approved, the person who approved it is not the person who
requested it.

**As checked by the proof assistant** ([SodPolicy.lean](lean/Workflow/Thm/SodPolicy.lean)):

```lean
theorem segregation_of_duties {s : State} (h : Reachable cedarGuard s) :
    ∀ (id : ReqId) (r : Req),
      s.requests[id]? = some r → r.status = .approved → r.decidedBy ≠ some r.requester
```

Read it as: for every reachable state `s`, and every request `r` in it, if
`r` is approved then whoever decided it is not its requester. `Reachable`
covers every finite sequence of actions; nothing is sampled. The proof is
checked by [Lean](https://lean-lang.org), a proof assistant: if a single case
were missing, the build would fail.

Three more controls are proven the same way:

| | Control | Theorem |
| --- | --- | --- |
| C1 | Decisions are final: an approved or denied request never changes again | `decisions_are_final` |
| C2 | The requester of a request cannot be changed, by editing or otherwise | `requester_is_immutable` |
| C3 | Segregation of duties (above) | `segregation_of_duties` |
| C4 | Only approvers decide: approving or denying takes effect only for a user who holds approval rights at that moment | `only_approvers_decide` |

The full mapping from controls to theorems, tests and planted bugs is in
[docs/traceability.md](docs/traceability.md).

## The delegation scenario

Substitution and delegation are how approval processes get circumvented in
practice: an approver makes the requester their substitute, and the requester
approves their own request. Here, Bob is the only approver:

| Step | Who | Action | Result |
| --- | --- | --- | --- |
| 1 | Alice | files request 0 | accepted |
| 2 | Bob | delegates approval rights to Alice | accepted; Alice is now an approver |
| 3 | Alice | approves request 0 | **refused**: it is her own request |
| 4 | Bob | approves request 0 | accepted |

The theorem says step 3 is refused not only in this trace, but however the
delegation is arranged, repeated or chained. The reason is visible in the
proof: the rule that forbids self-approval never looks at who holds approval
rights, so no redistribution of those rights can weaken it.

## Two versions of the result

The proof is done twice, and both are kept.

| | Stage A | Stage B |
| --- | --- | --- |
| Authorization decided by | Ordinary conditions written in Lean | Five policies evaluated by a real policy engine's formal semantics |
| What it shows | The method works for approval workflows in general, whatever authorizes them | The method reaches through a real policy engine, including its failure modes |
| Theorem | `segregation_of_duties_plain` | `segregation_of_duties` |

Both rest on one shared argument (`segregation_of_duties_of_noSelfApproval`):
segregation of duties holds for *any* authorization mechanism that refuses to
let a requester approve their own request. Each stage only has to show that
its mechanism has that one property.

**Why Cedar appears here.** Stage B uses the [Cedar](https://www.cedarpolicy.com)
policy language for one reason: it is the policy engine whose semantics are
published as a Lean specification that outside proofs can build on. This is
not a recommendation of a product. Stage A does not depend on Cedar at all,
and is the part that transfers directly to any other authorization model.

## Proven, tested, assumed

| Proven | Tested | Assumed |
| --- | --- | --- |
| C1 to C4 hold in every reachable state of the **model**: the workflow written in Lean, with Cedar's Lean specification deciding authorization in stage B. | The TypeScript **implementation**, which calls the official Cedar engine, behaves exactly like the model: same decision and same resulting state at every step of 10,000 random action sequences on every push, and of 1,000,000 before this release. | The Lean proof checker is correct. |
| The translation from workflow state to the policy engine's input, on the model side, always supplies what the policies need. | The five policies as text in [policies.cedar](impl/policies.cedar) mean the same as the five syntax trees the proofs are about. | Cedar's Lean specification describes what the Cedar engine does. The Cedar project tests this continuously; the differential test here adds evidence for these five policies. |
| The proofs use no unfinished steps and no axioms beyond Lean's three standard ones. This is checked on every push. | Each of five deliberately planted bugs makes the tests fail. | The model is the right definition of the workflow. A model can be wrong the way a specification can be wrong. |

Limits, stated openly:

- **The proof is about the model.** The implementation is tested against it,
  not proven.
- **The policies exist twice**, once as text and once as syntax trees. The
  differential test is what catches a mismatch between them.
- **The call into the policy engine is proven on the Lean side only.** The
  TypeScript code that builds the engine's input is separate code, tested
  against its Lean counterpart.
- **Delegation is unlimited and permanent.** Time limits and revocation are
  not modelled.
- **There is no emergency access.**

## Planted bugs

Five bugs were planted in the implementation, each a one-line change, each of
a kind that occurs in practice. Two test suites were run against every one:
ten ordinary unit tests, and the differential test against the model.

| Bug | What was changed | Unit tests (10) | Differential test | Traces until caught: median (range) |
| --- | --- | --- | --- | --- |
| M1 | The segregation-of-duties policy is deleted from the policy file (policy regression) | caught, 1 test fails | caught in 20 of 20 runs | 7 (1 to 47) |
| M2 | Editing a request copies `requester` from the input (mass assignment) | **missed** | caught in 20 of 20 runs | 27 (2 to 63) |
| M3 | Approving does not check that the request is still open (lifecycle flaw) | **missed** | caught in 20 of 20 runs | 7 (1 to 40) |
| M4 | The engine's input omits the `requester` attribute (the skipped-policy pitfall, below) | caught, 2 tests fail | caught in 20 of 20 runs | 4 (1 to 25) |
| M5 | Approving skips the policy engine when the actor is an approver (a "fast path") | caught, 1 test fails | caught in 20 of 20 runs | 7 (1 to 47) |

**Unit tests caught 3 of 5. The differential test caught 5 of 5,** each within
63 random traces, in 20 runs with different seeds.

How to read this honestly: the unit tests and the bugs were written by the
same person, so this is an illustration, not a measurement. The unit tests
were written first and were not adjusted afterwards. The two bugs they miss
are the ones nobody wrote an example for: no test sends an extra field with an
edit, and none tries to approve a request that was already denied. The
differential test needs no such foresight, because the model defines the
expected outcome of every sequence, including the ones nobody thought of. For
each bug it reports a shortest failing sequence it could find; for M3:

```json
{"approvers":["bob"],"steps":[
  {"actor":"alice","action":"create","justification":""},
  {"actor":"bob","action":"delegate","to":"alice"},
  {"actor":"alice","action":"deny","id":0},
  {"actor":"bob","action":"approve","id":0}]}
```

Alice's request is denied, and then approved after all.

## The skipped-policy pitfall

A policy engine can be correct and the system built on it still wrong. Cedar
evaluates each policy against data supplied by the application. If evaluating
a policy raises an error, for example because an attribute it reads is
missing, Cedar skips that policy. For a rule that permits, this fails safe.
For a rule that forbids, it fails open: a skipped prohibition prohibits
nothing. So an application that forgets to pass one attribute, `requester`,
silently switches segregation of duties off, while the policy file still looks
correct in every review. This is planted bug M4: the engine answers "allow"
to a self-approval and mentions the skipped policy only in its diagnostics.

The proof rules this out for the model. Its central lemma
(`forbidSelfApproval_satisfied`) states that the prohibition is evaluated
successfully, and applies, whenever a requester asks to approve their own
request. That lemma holds only because the code that prepares the engine's
input always includes the attribute. Remove the attribute there and the proof
no longer builds. Cedar can also check its input against a schema on each
call, which would reject the incomplete data; the implementation here leaves
that off so that M4 exercises the unprotected path.

## Run everything

Requires [elan](https://lean-lang.org/install/) (the Lean version manager) and
Node.js 22.18 or later.

```sh
(cd lean && lake build) && scripts/check-axioms.sh   # check all proofs and their axioms
(cd impl && npm ci && npm test)                      # typecheck, validate policies, unit tests, 10,000 traces
(cd impl && npm run test:mutants)                    # run both suites against the five planted bugs
```

The first build downloads Lean and the pinned Cedar specification and takes a
few minutes; after that, checking every proof takes seconds. To try a single
sequence of actions against the model:

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
lean/Workflow/PlainGuard.lean      stage A authorization
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
docs/traceability.md               control → theorem → tests → planted bugs
docs/notes-on-cedar-spec.md        notes on building proofs on Cedar's specification
```

## Next step

Emergency access: a user obtains access immediately, without prior approval,
and a second person must review it afterwards. It adds a review obligation and
a second lifecycle to the model, and the property to prove changes from
"nobody approves their own request" to "no emergency access goes unreviewed,
and nobody reviews their own". After that: delegation with time limits and
revocation, expiry of granted access, an audit log proven complete, and one
source of truth for the policies instead of two.
