import Lake
open Lake DSL

package workflow

-- Cedar's Lean specification, pinned to a fixed commit. The proofs in
-- Workflow/Thm/SodPolicy.lean and OnlyApprovers.lean unfold its definitions and
-- may need changes when the commit is moved.
require Cedar from git
  "https://github.com/cedar-policy/cedar-spec" @ "e619491a5bfb04970ef994dbe286df0bb9d0b73f" / "cedar-lean"

@[default_target]
lean_lib Workflow

@[default_target]
lean_exe runner where
  root := `Main
