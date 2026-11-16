# Notes on using `cedar-spec` as a library

The proofs in `lean/Workflow` build on Cedar's Lean specification from a
separate Lake project. Pinned: `cedar-spec` at commit
`e619491a5bfb04970ef994dbe286df0bb9d0b73f`, Lean `v4.35.0`, and the engine
`@cedar-policy/cedar-wasm` `4.14.0`.

## Setup

Lake can depend on a subdirectory of a git repository:

```lean
require Cedar from git
  "https://github.com/cedar-policy/cedar-spec" @ "<commit>" / "cedar-lean"
```

The toolchain must match Cedar's `lean-toolchain` exactly.

`lake build` compiles only imported modules. This project imports
`Cedar.Spec`, `Cedar.Thm.Authorization` and `Cedar.Thm.Data.Map`: about 90
modules, Batteries included.

## Unfolding Cedar's definitions from another package

Cedar's files start with `module`. Most definitions in `Cedar.Spec` are
`public` without `@[expose]`, including `satisfied`, `isAuthorized`,
`Scope.toExpr`, `Conditions.toExpr`, `Map.make` and `Map.findOrErr`. Cedar's
own theorem files use `import all` to unfold them.

A file without a `module` header sees the bodies of everything it imports.
Every file in `lean/Workflow` is such a file, so `unfold satisfied` and
`simp [Conditions.toExpr, ...]` work there. No cross-package `import all` and
no fork of `cedar-spec` were needed.

The proofs therefore depend on the bodies of Cedar's definitions, not only
their statements, and may break when the pinned commit moves.

## Lemmas and definitions that carried the proofs

`forbid_trumps_permit` gives C3 from one satisfied forbid policy.
`allowed_only_if_explicitly_permitted` gives C4: it yields a satisfied permit
policy, and a case split over the five policies finishes the proof.

`evaluate` is exposed. `simp` with the scope and condition translations
reduces a policy applied to a request with a known action to a small goal. The
tactic macro `eval_policy` in `Workflow/Thm/SodPolicy.lean` bundles that simp
set.

`Map.make_find?_eq_list_find?` turns a lookup in a canonical map into
`List.find?` on the list the map was built from. With it the proofs never
touch the sorted form of the entity store, and no well-formedness side
conditions appear.

## Design choices forced by the proofs

The proof for P4 needs the lookup of `Request::"<id>"` to find request `id`
and nothing else, so the identifier encoding must be injective. The entity
identifier is `Nat.repr id`, and `Nat.repr_inj` from Lean's standard library
gives injectivity.

A request's identifier is its position in the list of requests, so
identifiers are unique by construction. A list of `(id, request)` pairs would
need a separate uniqueness invariant.

`omega` failed with "no usable constraints" on goals whose hypotheses were
typed with `abbrev ReqId := Nat`. Lemmas that do arithmetic on identifiers are
stated with `Nat`.

## Cedar behaviour the proofs have to account for

`in` treats a missing entity as one without parents. `inₑ` uses
`Entities.ancestorsOrEmpty`, so a principal with no entity is in no group.
The model relies on this and gives only approvers a user entity.

Reading an attribute of a missing entity, or one the entity lacks, raises an
error. `isAuthorized` then leaves that policy out of the decision: `satisfied`
is false and the policy is listed under `erroringPolicies`. An erroring permit
grants nothing, an erroring forbid forbids nothing, and the engine behaves the
same. Given a `Request` entity without `requester`, `cedar-wasm` 4.14.0 allows
a self-approval and reports P4 under `diagnostics.errors`.

Schema validation catches this in the engine. With the schema and
`validateRequest: true` in the same call, the engine rejects the entity with
"expected entity `Request::"0"` to have attribute `requester`". The
implementation in `impl/` does not pass the schema on each call, so planted
bug M4 runs unvalidated.

The Lean specification has no parser, so the policies are written as syntax
trees and exist a second time as text. Comparing the trees with the parsed
`policies.cedar`, through the engine's JSON policy format, would remove the
duplication.

## Open questions

Can a theorem be stated about a policy file instead of a hand-written syntax
tree? Cedar's own differential testing passes policies to Lean through
protobuf (`CedarProto`).

How stable are the bodies of the `Cedar.Spec` definitions across releases?
