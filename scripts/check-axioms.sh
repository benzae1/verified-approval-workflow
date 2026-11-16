#!/usr/bin/env bash
# Fails if one of the main theorems depends on an axiom other than Lean's three
# standard ones. Catches `sorry` (sorryAx) and `native_decide`
# (Lean.ofReduceBool, Lean.trustCompiler). Run after `lake build`.
set -euo pipefail
cd "$(dirname "$0")/../lean"

out=$(lake env lean Audit.lean)
echo "$out"

expected=6
count=$(echo "$out" | grep -c "depends on axioms\|does not depend on any axioms" || true)
if [ "$count" -ne "$expected" ]; then
  echo "error: expected $expected axiom reports, got $count" >&2
  exit 1
fi

extra=$(echo "$out" | grep -o '\[.*\]' | tr -d '[] ' | tr ',' '\n' \
  | grep -v -x -e propext -e Classical.choice -e Quot.sound -e '' || true)
if [ -n "$extra" ]; then
  echo "error: non-standard axioms in use:" >&2
  echo "$extra" | sort -u >&2
  exit 1
fi

if grep -rn --include='*.lean' -w -e sorry -e native_decide -e axiom Workflow Main.lean \
    | grep -v '^[^:]*:[0-9]*: *--' | grep -v 'Audit.lean' ; then
  echo "error: found sorry, native_decide or axiom in the sources" >&2
  exit 1
fi
echo "ok: only propext, Classical.choice, Quot.sound"
