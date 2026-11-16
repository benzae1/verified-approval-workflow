# Notes on using `cedar-spec` as a library

Working notes from building proofs on top of Cedar's Lean specification from
an outside Lake project. Pinned versions: `cedar-spec` at commit
`e619491a5bfb04970ef994dbe286df0bb9d0b73f`, Lean `v4.35.0`, Cedar engine
(`@cedar-policy/cedar-wasm`) `4.14.0`.

## Setup

- Depending on the subdirectory of a git repository works as written in the
  Lake documentation:
  `require Cedar from git "https://github.com/cedar-policy/cedar-spec" @ "<commit>" / "cedar-lean"`.
- The toolchain must match Cedar's `lean-toolchain` exactly.
- `lake build` only compiles the modules that are imported. This project
  imports `Cedar.Spec`, `Cedar.Thm.Authorization` and `Cedar.Thm.Data.Map`,
  about 90 modules including Batteries; a cold build takes well under a minute
  on a laptop. The symbolic compiler and validator proofs are never built.

## The module system was not an obstacle

Cedar's files start with `module`, and most definitions in `Cedar.Spec` are
`public` but not `@[expose]`: `satisfied`, `isAuthorized`, `Scope.toExpr`,
`Conditions.toExpr`, `Map.make`, `Map.findOrErr` among them. Cedar's own
theorem files use `import all` to unfold them. The open question before
starting was whether an outside package can unfold them at all.

It can, with no special effort: **a file without a `module` header sees the
bodies of everything it imports.** All files in `lean/Workflow` are ordinary
non-module files, and `unfold satisfied` and `simp [Conditions.toExpr, ...]`
work. None of the fallbacks (cross-package `import all`, a fork, an assumed
lemma) were needed.

The cost is that these proofs depend on the *bodies* of Cedar's definitions,
not only on their statements, so they may break when the pin is moved. That is
the reason for pinning a commit.

## What was easy

- **`forbid_trumps_permit` and `allowed_only_if_explicitly_permitted`** are
  stated exactly in the form an application proof wants. The first gives C3
  from one satisfied forbid policy; the second gives C4 by handing over *some*
  satisfied permit policy, after which a case split over the five policies
  finishes the proof.
- **Evaluating a concrete policy.** `evaluate` is exposed, and `simp` with the
  definitions of the scope and condition translations reduces a policy applied
  to a request with a known action to a small residual goal. The tactic macro
  `eval_policy` in `Workflow/Thm/SodPolicy.lean` collects that simp set.
- **`Map.make_find?_eq_list_find?`** reduces a lookup in a canonical map to
  `List.find?` on the list it was built from. With it, the entity store never
  has to be reasoned about in sorted form, and no well-formedness side
  conditions appear anywhere.

## What needed thought

- **Identifiers of requests.** P4's proof needs the lookup of `Request::"<id>"`
  to find the entity of request `id` and no other, so the encoding of
  identifiers must be injective. Requests are numbered by their position and
  the entity identifier is `Nat.repr id`; `Nat.repr_inj` from Lean's standard
  library supplies injectivity.
- **Uniqueness of request identifiers.** An earlier design kept requests as a
  list of `(id, request)` pairs, which needs an invariant that identifiers are
  unique. Using the position in the list as the identifier makes uniqueness
  hold by construction and removes that invariant.
- **`omega` and type abbreviations.** `omega` failed ("no usable constraints")
  on goals whose hypotheses were typed with `abbrev ReqId := Nat`; the lemmas
  that do arithmetic on identifiers are therefore stated with `Nat`.

## Behaviour worth knowing

- **Missing entities are not errors for `in`.** `inₑ` uses
  `Entities.ancestorsOrEmpty`, so a principal with no entity is simply in no
  group. The model uses this: only approvers get a user entity.
- **Missing entities and attributes *are* errors for attribute access.**
  `getAttr` on an entity that is absent, or lacks the attribute, raises an
  error, and `isAuthorized` then ignores that policy for the decision
  (`satisfied` is false, the policy is listed under `erroringPolicies`). For a
  permit policy this fails safe. For a forbid policy it fails open. The
  engine's published behaviour is the same: called with a `Request` entity
  that lacks `requester`, `cedar-wasm` 4.14.0 answers `allow` and reports P4
  under `diagnostics.errors`.
- **Schema-based validation closes this particular hole in the engine.** With
  the schema and `validateRequest: true` passed to the same call, the engine
  refuses the entity ("expected entity `Request::"0"` to have attribute
  `requester`"). The implementation here does not pass the schema at request
  time, so that planted bug M4 exercises the unprotected path.
- **The Lean specification has no parser.** Policies are written as syntax
  trees, so they exist twice. A check that the syntax trees equal the parsed
  `policies.cedar` (via the engine's JSON policy format) would remove this
  duplication and is listed as thesis work.

## Open questions

- Is there a supported way to state a theorem about a policy *file*, rather
  than a hand-written syntax tree? Cedar's own differential testing passes
  policies to Lean through protobuf (`CedarProto`); that route was not explored.
- How stable are the bodies of `Cedar.Spec` definitions across releases?
