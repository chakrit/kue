# Session 2026-06-17 — `let` family diagnosed; `[...]` embedding parse landed

Latest resume breadcrumb. Supersedes
[`2026-06-17-b3c-cross-module-imports-landed.md`](2026-06-17-b3c-cross-module-imports-landed.md).

## Headline

The slice was scoped as "`let` declarations — the #1 real-file blocker." **Diagnosis
disproved that:** `let` was already fully implemented (parse + scope + non-output) in every
position prod9 uses. The breadcrumb's `unexpected character '='` was a *mis-attributed*
parser error — the real blocker was the **open-list `[...]` embedding** sitting inside the
`let` RHS struct. Landed the parse fix for `[...]`; eval semantics for it are the next slice.

## What was diagnosed

`let nsp = defaults.#Basics & { #name: "fx"; [...] }` (prod9 `fx.cue:11`). `parseField`
committed any `[`-led struct member to the `[label]: value` pattern form with **no
fallback**. The `[...]` failed to parse as a pattern, the parser backtracked, and the error
surfaced at the `let`'s `=` — making `let` look like the culprit. It wasn't.

Verified `let` works in all real positions, oracle-clean vs `cue` v0.16.1: file-scope,
in-struct, sibling-field ref, `let` referencing a prior `let`, inner-`let`-shadows-outer,
and `let` never emitted as output.

## What was done

- **Parser fix (`Kue/Parse.lean` `parseField`):** the `'[' :: _` case now tries
  `parsePatternField` and falls back to `parseEmbedding` on failure (mirrors the existing
  `'"'` / `'('` fallbacks). `[...]` and `[1,2,3]` as struct members parse as list
  embeddings; `[label]: value` patterns still win when valid. **Reuses the existing
  `.embedding` machinery** (embeddings flow into `structComp` comprehensions, `meet`-ed into
  the struct) — no new AST/value constructor.
- **Tests:** `ParseTests.lean` +6 theorems — two `parseSucceeds` for the `[...]`/list
  embedding parse, four pinning the already-working `let` scoping. Four
  `testdata/cue/let_*.{cue,expected}` fixture pairs + `FixturePorts.lean` entries (`cue
  fmt`-clean, oracle-matched).
- **Docs:** plan blocker ranking corrected (`let` is NOT a gap; `[...]` *eval* is now #1),
  `compat-assumptions.md` records `let` (all positions, + unreferenced-let leniency) and the
  `[...]` parse-vs-eval split, implementation-log slice entry.

## Real-file spot-check (READ-ONLY, prod9/infra)

**All 15/15 `infra/apps/*.cue` now parse + locally evaluate** (stdin `kue`), up from ~3/15.
The `[...]` parse barrier is gone. They do *not* yet produce cue-matching output: stdin mode
has no module context (imports → ⊥), and the `[...]` **eval** semantics are deferred.

## Next session — RANKED blockers

1. **Open-list `[...]` embedding EVAL — now the top blocker.** `cue` permits a list embedded
   in a struct with *no regular exported fields* (only `#hidden`/`_`/`let`): the value emits
   as the list while definitions stay selectable; with any regular field it conflicts. `cue`
   also tolerates the latent struct/list conflict **lazily** when the value is only selected
   into (`.#name`, `.#out`) and never emitted whole — which is exactly how prod9's
   `let nsp = #Basics & {…[...]}` is used. kue is **eager**: `meet(struct, list) = ⊥`.
   Closing this needs the embedding rule (hidden-only struct + list embed) and/or lazier
   selection. This is the gate to cue-matching output on the app files.
2. **`kue export <file>` module discovery** — did not find `infra/cue.mod/module.cue` from a
   sub-dir path arg (pre-existing, out of the `let`/`[...]` slice's scope). Needed for the
   full import-resolving export path on real files.
3. **Closedness enforcement under import/unification**, bare hidden-field references
   (`y: _a`), `[string]:` non-string label patterns — surface after the above.
4. **B3b syntax edges** (import comments/trailing commas) — still DEFERRED; real prod9
   grouped imports parse fine.
5. **B3d — registry fetch + MVS + `cue.sum`** — DEFERRED per chakrit.

## Audit cadence

`/ace-audit` over B3a+B3b+B3c was due at the import-family boundary and is still pending; the
`[...]`-parse slice is small and clean. Fold the audit in around the next 1–2 slices — don't
stall the `[...]`-eval work.

## Carry forward

- Alpha **v0.1.0 staged**; cut locally via **`scripts/release.sh`** on chakrit's command.
  **NO GitHub Actions (banned); no `.github` dir; do NOT touch `scripts/release.sh` /
  `packaging/` / release files.**
- External repos (prod9 tree + the cue cache) are **READ-ONLY** reference.
- Verify gate this slice: `lake build` exit 0, `scripts/check-fixtures.sh` ⇒ `fixture pairs
  ok`, `shellcheck` clean.
