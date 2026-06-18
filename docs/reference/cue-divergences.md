# CUE divergences

Cases where Kue's output **intentionally differs** from the reference `cue` binary
because `cue` is buggy, surprising, or under-specified and Kue does the correct thing.
This is a living reference: the continuous slice loop appends an entry whenever a slice's
oracle-check against `cue` surfaces a genuine divergence (see `CLAUDE.md` →
"Continuous slice loop").

This is **not** for behavior we haven't implemented yet (that's the plan's Later Slices)
nor for fixtures where Kue matches `cue` (the default — those need no entry). Only record
deliberate, defensible disagreement with the reference binary.

## How to record an entry

When a slice finds `cue` doing the wrong thing:

1. Confirm it is a real `cue` defect, not a Kue bug or a misread spec — check the CUE
   language spec and, where useful, the upstream `cue` issue tracker.
2. If Kue's behavior is the corrected one, **do not** edit the fixture `.expected` to match
   buggy `cue`. Encode the correct value, and add an entry below.
3. Keep the fixture pair as the executable record; this table is the human-readable index.

## Entry format

| Topic | `cue` ver | Claim / input | `cue` output | Kue output | Why Kue is right | Fixture |
|-------|-----------|---------------|--------------|------------|------------------|---------|

## Confirmed divergences

| Topic | `cue` ver | Claim / input | `cue` output | Kue output | Why Kue is right | Fixture |
|-------|-----------|---------------|--------------|------------|------------------|---------|
| `export -e` from stdin | v0.16.1 | `echo 'common: {name: "svc"}' \| <bin> export -e common` | `reference "common" not found` (exit 1) | `{"name": "svc"}` (exit 0) | The field `common` is present in the piped document, so selecting it must succeed. `cue` ignores stdin when `-e/--expression` is given — it resolves the expression against an empty scope, so every stdin selector fails; the same `-e common` works against identical content as a file. Kue binds the selector against the actually-loaded root in both file and stdin mode (parity). | CLI behavior; `Kue/CliTests.lean` stdin-`-e` cases |
| residual pattern in `eval` output | v0.16.1 | `eval` of `{[=~"x"]: string, xy: "hi"}` | `{xy: "hi"}` — the `[=~"x"]: string` pattern constraint is ELIDED from the printed value | `{xy: "hi", [=~"x"]: string}` — the residual pattern is shown | The pattern constraint is part of the struct's value (it still constrains any future field added by a meet), so printing it is the faithful rendering; `cue eval` drops it, hiding a live constraint. Values agree (cue applies the pattern — `xy: "hi"`, a conflicting one bottoms the field); only the surface syntax differs. Concrete `export`/JSON output (the primary observable) is identical, so no fixture drifts. | `Kue/Tests/EvalTests.lean` `eval_pattern_struct_*` |

Every slice through `8af9e2f` (comprehensions, dynamic fields + string interpolation,
struct-embedding scope, `strings`/`list` builtins, decimal-lift refactor) oracle-checked
clean against `cue` v0.16.1; the entry above is the first deliberate disagreement,
surfaced by the `kue export -e` slice.
