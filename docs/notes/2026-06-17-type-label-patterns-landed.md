# Session 2026-06-17 — `[string]:` kind/type label-pattern colon-shorthand parse landed

Latest resume breadcrumb. Supersedes
[`2026-06-17-export-module-discovery-landed.md`](2026-06-17-export-module-discovery-landed.md).

## Headline

Landed the canonical CUE open-map / constraint-key label pattern `[string]: T` (and the
general kind/bound/exact/regex bracket form) in **value position** — the bare
colon-shorthand `#labels?: [string]: string` (= `#labels?: {[string]: string}`). This was
the first real parse wall in the most-imported prod9 dep (`defs@v0.3.19/attr/metadata.cue`)
after module discovery was fixed.

## Diagnosis (root cause)

Not a semantic gap — the model was already complete. `structPattern`/`structPatterns` carry
an arbitrary `Value` label pattern, and `labelMatchesPatternWith` matches a field iff
`meetValue labelPattern (.string label)` is non-bottom, so `[string]:` already typed
string-labeled fields, and the **brace** form `{[string]: int}` already parsed+typed. The
only gap was surface syntax: `parseFieldValue` handled labeled-field colon-shorthand
(`a: b: …`) but had no case for a *pattern* field in value position, so `f: [string]: T`
fell through to `parseExpression` → `parseList`, which choked on the trailing `:`
("unexpected character ':'"). Confirmed: `{[string]: int}` (braces) worked before the fix;
bare `[string]: int` did not.

## What was done

- **Fix (`Kue/Parse.lean`):** `skipBalancedBrackets` (depth-tracked `[ … ]` lookahead,
  skips quoted literals whole) + `valuePositionStartsPatternField` (balanced bracket group
  immediately followed by `:`). `parseFieldValue` routes such a value position through
  `parseField` + `parsedFieldsValue`, identical to the labeled-shorthand path. `[`-in-value
  disambiguation: trailing `:` ⇒ pattern, else list embedding (`[1,2,3]`). Field-position
  `[`-handling (try `parsePatternField`, else `parseEmbedding`) untouched. Bracket value is
  an arbitrary `parseExpression`, so kind/exact/bound/regex all parse — **no deferral**.
- **Tests:** 4 fixtures (`string_kind_pattern`, `string_kind_pattern_mismatch`,
  `string_kind_pattern_only`, `type_label_colon_shorthand` = the defs shape) + FixturePorts
  entries; 2 `native_decide` EvalTests theorems (meet types a matching int field;
  `containsBottom` on a string field). Regression-checked `["a"]:`, `[=~"re"]:`, `[1,2,3]`
  embedding, and nested `a: b: c:` shorthand all still parse.
- **Docs:** plan focus item 5 + item 159 marked DONE w/ diagnosis; `compat-assumptions`
  updated (label patterns now general across both surface forms; only the regex *subset*
  bounds matching); implementation-log slice appended.

## Real-file spot-check (READ-ONLY, prod9/infra)

`defs@v0.3.19/attr/metadata.cue` now parses cleanly
(`#Metadata: {…, #labels?: {[string]: string}, #annotations?: {[string]: string}}`).
`kue export apps/argocd.cue` (from `/Users/chakrit/Documents/prod9/infra`) advances past the
`[string]:` wall to a **NEW** parse error one dep deeper:
`defs@v0.3.19/parts/pod_tolerations.cue: unexpected character '='` (an alias / `=` form).

## Next session — RANKED blockers

1. **Open-list `[...]` embedding EVAL — still the top *semantic* blocker.** `cue` permits a
   list embedded in a struct with only `#hidden`/`_`/`let` members (emits as the list,
   definitions stay selectable) and tolerates the latent struct/list conflict **lazily**
   when the value is only selected into (`.#name`, `.#out`), never emitted whole — exactly
   how prod9's `let nsp = #Basics & {…[...]}` is used. kue is **eager**:
   `meet(struct, list) = ⊥`. Closing this needs the embedding rule (hidden-only struct +
   list embed) and/or lazier selection. Gate to cue-matching output on the app *bodies*.
2. **NEW: `parts/pod_tolerations.cue` `'='` parse error.** Surfaced this slice on
   `apps/argocd.cue` once `[string]:` cleared. An alias / `=` form (likely a field/value
   alias shape not yet parsed, or `let`/`=` edge). Diagnose against the dep file; oracle
   v0.16.1. Probably small, in the same `parseField`/alias area.
3. **Closedness enforcement under import/unification**, bare hidden-field references
   (`y: _a`) — surface after the above.
4. **B3d — registry fetch + MVS + `cue.sum`** — DEFERRED per chakrit.

## Audit cadence

This is the **3rd slice since the Phase A/B audit** (export-discovery, this `[string]:`
slice, then `[...]` eval next). Per CLAUDE.md the orchestrator runs the next two-phase
`/ace-audit` **after the following slice** (`[...]` eval). Don't stall forward motion for
it; fold findings into the plan as fix-slices when it runs.

## Carry forward

- **Architecture fix-slices** still open in `plan.md`: base64-move, `testdata/` test-reorg
  (flat fixture dir → subsystem subdirs), Linux `cacheRoot` default.
- Alpha **v0.1.0 staged**; cut locally via **`scripts/release.sh`** on chakrit's command,
  ~1 datestamped alpha/day. **NO GitHub Actions / CI (banned); no `.github` dir; do NOT
  touch `scripts/release.sh` / `packaging/` / release files.**
- External repos (prod9 tree + the cue cache) are **READ-ONLY** reference.
- Verify gate this slice: `lake build` exit 0, `scripts/check-fixtures.sh` ⇒ `fixture pairs
  ok`, `shellcheck` clean — all green.
