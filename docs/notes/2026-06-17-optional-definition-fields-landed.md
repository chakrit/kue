# 2c.5 landed — optional-definition fields via orthogonal `FieldClass`

**Status:** done, pushed to `gh:main`. Breadcrumb for the next slice.

## What landed (the last real-file blocker)

`FieldClass` was a flat enum that could not represent "optional AND definition", so `#x?`
never merged with a provided `#x`. Refactored to **orthogonal axes** (Option B,
type-system-first):

- `inductive Optionality | regular | optional | required` with a `meet` lattice: a present
  (`regular`) conjunct dominates and discharges `required` (`x! & x = x`); `required`
  dominates `optional` (`x! & x? = x!`); `optional & optional` stays optional.
- `inductive FieldClass | field (isDefinition isHidden : Bool) (optionality : Optionality) |
  letBinding`. `letBinding` kept distinct (a `let` is not a field).
- Legacy ctor names (`.regular`/`.optional`/`.required`/`.hidden`/`.definition`) kept as
  **smart constructors** over the structure → every construction/`==` site compiles
  unchanged. Only 5 *match* sites rewritten: `Manifest`/`Format`/`Eval.structPairs`/
  `Normalize` + `mergeFieldClass` (now merges per-axis: OR def/hidden, meet optionality).
- Parser `parseFieldClass` reads `?`/`!` (optionality) and `#`/`_` prefix (def/hidden)
  independently instead of `?`/`!` short-circuiting and dropping def-ness.

## Fixed (oracle-confirmed, cue v0.16.1)

- `#D: {#x?: string}; y: #D & {#x: "hi"}` → `#x: "hi"` present def (eval); `y` exports `{}`;
  `y.#x` selects `"hi"`. THE TARGET.
- `_x?` + `_x: 5` → present hidden, selects `5`. `#y!` + `#y: 3` → present (required
  discharged). Optional non-def + definition unchanged.
- **Flat-enum bug corrected:** `{a?:int} & {a!:int}` = `a!` (required-not-present), NOT `_|_`.
  Two tests encoded the old bug — both rewritten to oracle-correct (one to realistic distinct
  `#same`/`same` labels; the parser always keeps the `#`/`_` prefix, so same-string different-
  class fields are impossible post-parse and `mergeFieldClass` only ever sees same-prefix).
- Reduced argo-like optional-def shape (`#meta?` + nested `dest?`) exports byte-identical to
  cue. `def_meet_template` still byte-identical.

## Tests / verify

- +6 theorems (StructTests ×5, ParseTests ×1), +2 fixture pairs (CLI
  `optional_definition_field` with parse-driven FixturePort; export `optional_definition_field`
  byte-identical to `cue export`). **688 theorems total.**
- `lake build` green; `scripts/check-fixtures.sh` ⇒ `fixture pairs ok`; `shellcheck` clean.
  FULL existing suite UNCHANGED.

## Next blocker (read-only probe)

`int & >0` → kue collapses to `>0`; cue keeps `int & >0`. The known
`intGe/Gt/Le/Lt`→bound-collapse formatting issue (carry-forward item 3 / plan MEDIUM). Not a
2c.5 regression — pre-existing pure-meet formatting collapse. Open-list collapse (`[...int] &
[1,2]`) exports correctly. The optional-def path that gated richer real-file templates is
unblocked.

## NOTE for orchestrator

This is the **3rd slice since the Phase A/B audit** (2c.1, 2c.2, this 2c.5) — **a two-phase
audit is due**, and a **fresh datestamped alpha is warranted** after it (NO CI). Carry forward:
open-list-collapse-on-manifest, `intGe`→bound collapse, post-2c cleanup batch (base64-out-of-
Json, test/`testdata` reorg, `Field`→structure — note `FieldClass` is now already a structure),
test reorg. External repos (prod9, cue cache) READ-ONLY; revert only via Edit, never git
checkout.
