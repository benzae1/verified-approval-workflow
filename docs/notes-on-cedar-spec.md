# Notes on using `cedar-spec` as a library

The proofs in `lean/Workflow` build on Cedar's Lean specification from a
separate Lake project. Pinned versions: `cedar-spec` at commit
`e619491a5bfb04970ef994dbe286df0bb9d0b73f`, Lean `v4.35.0`, and the Cedar
engine `@cedar-policy/cedar-wasm` `4.14.0`.

## Setup

Lake can depend on a subdirectory of a git repository:

```lean
require Cedar from git
  "https://github.com/cedar-policy/cedar-spec" @ "<commit>" / "cedar-lean"
```

The toolchain has to match Cedar's `lean-toolchain` exactly.

`lake build` compiles only the modules that are imported. This project imports
`Cedar.Spec`, `Cedar.Thm.Authorization` and `Cedar.Thm.Data.Map`, which comes
to about 90 modules including Batteries. A cold build takes under a minute on
a laptop. Cedar's symbolic compiler and validator proofs are never built.

## Unfolding Cedar's definitions from another package

Cedar's files start with `module`. Most definitions in `Cedar.Spec` are
`public` without `@[expose]`, among them `satisfied`, `isAuthorized`,
`Scope.toExpr`, `Conditions.toExpr`, `Map.make` and `Map.findOrErr`. Cedar's
own theorem files use `import all` to unfold them.

A file without a `module` header sees the bodies of everything it imports. All
files in `lean/Workflow` are such files, so `unfold satisfied` and
`simp [Conditions.toExpr, ...]` work there. Cross-package `import all` and a
fork of `cedar-spec` were not needed.

These proofs therefore depend on the bodies of Cedar's definitions as well as
their statements, and may break when the pinned commit is moved.

## Lemmas and definitions that carried the proofs

`forbid_trumps_permit` gives C3 from one satisfied forbid policy.
`allowed_only_if_explicitly_permitted` gives C4: it yields some satisfied
permit policy, and a case split over the five policies finishes the proof.

`evaluate` is exposed. `simp` with the definitions of the scope and condition
translations reduces a policy applied to a request with a known action to a
small remaining goal. The tactic macro `eval_policy` in
`Workflow/Thm/SodPolicy.lean` collects that simp set.

`Map.make_find?_eq_list_find?` reduces a lookup in a canonical map to
`List.find?` on the list the map was built from. With it the proofs never
reason about the sorted form of the entity store, and no well-formedness side
conditions appear.

## Design choices the proofs forced

The proof for P4 needs the lookup of `Request::"<id>"` to find the entity of
request `id` and no other, so the encoding of identifiers has to be injective.
Requests are numbered by position and the entity identifier is `Nat.repr id`.
`Nat.repr_inj` from Lean's standard library supplies injectivity.

A request's identifier is its position in the list of requests, which makes
identifiers unique by construction. A list of `(id, request)` pairs would need
a separate invariant stating uniqueness.

`omega` failed with "no usable constraints" on goals whose hypotheses were
typed with `abbrev ReqId := Nat`. The lemmas that do arithmetic on identifiers
are stated with `Nat`.

## Cedar behaviour that matters here

`in` treats a missing entity as an entity without parents. `inₑ` uses
`Entities.ancestorsOrEmpty`, so a principal with no entity is in no group. The
model relies on this: only approvers get a user entity.

Attribute access on a missing entity, or on an entity that lacks the
attribute, raises an error. `isAuthorized` then leaves that policy out of the
decision: `satisfied` is false and the policy is listed under
`erroringPolicies`. A permit policy that errors grants nothing. A forbid policy
that errors forbids nothing. The engine behaves the same way. Called with a
`Request` entity that lacks `requester`, `cedar-wasm` 4.14.0 answers `allow`
to a self-approval and reports P4 under `diagnostics.errors`.

Schema-based validation catches this case in the engine. With the schema and
`validateRequest: true` passed to the same call, the engine refuses the entity
with the message "expected entity `Request::"0"` to have attribute
`requester`". The implementation in `impl/` does not pass the schema with each
call, so planted bug M4 runs without that validation.

The Lean specification has no parser. Policies are written as syntax trees and
exist a second time as text. Comparing the syntax trees with the parsed
`policies.cedar`, through the engine's JSON policy format, would remove the
duplication.

## Open questions

Can a theorem be stated about a policy file instead of a syntax tree written
by hand? Cedar's own differential testing passes policies to Lean through
protobuf (`CedarProto`). That route has not been tried here.

How stable are the bodies of the `Cedar.Spec` definitions across releases?
