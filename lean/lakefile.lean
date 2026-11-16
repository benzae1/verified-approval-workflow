import Lake
open Lake DSL

package workflow

-- Cedar's Lean specification, pinned to a fixed commit. Do not update casually:
-- the proofs in Workflow/Thm/SodPolicy.lean depend on its definitions.
require Cedar from git
  "https://github.com/cedar-policy/cedar-spec" @ "e619491a5bfb04970ef994dbe286df0bb9d0b73f" / "cedar-lean"

@[default_target]
lean_lib Workflow

@[default_target]
lean_exe runner where
  root := `Main
