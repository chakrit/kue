# RESUME — CARRIER-STRUCT-MEET landed; counter=1; next = CARRIER-DECL-SELECT (2026-06-22)

Live START-HERE; supersedes
`2026-06-22-resume-after-audit-close-carrier-struct-meet-next.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md) +
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Genuinely-open
backlog. Full per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md).

## State — CARRIER-STRUCT-MEET DONE (slice 1 of the new batch)

The top-ranked soundness fix-slice landed. A scalar/list embedding carrier
(`.embeddedScalar`/`.embeddedList` — the carrier IS its scalar/list) met with a PURE
decls-only struct that has NO embed of its own WRONGLY MERGED the decls; now it BOTTOMS
(`{#a:1,5} & {#b:2}` is `5 & {#b:2}` = int-vs-struct `_|_`; spec + cue v0.16.1 agree). Kue
was MORE PERMISSIVE — that unsoundness is closed.

- **Fix:** mechanical DELETION at **4 sites** in `Lattice.lean` (the `.struct fields _
  none [] _` sub-case in each carrier's `none`-branch — `.embeddedList` left/right +
  `.embeddedScalar` left/right). Dropped the `else <merge decls>`; the `none`-branch now
  routes to `meetCore` → bottom (`carrier vs .struct` is `.bottom`). Applied UNIFORMLY to
  both carriers, by hand (Phase-B ruling: NO shared meet seam — the payload-meet step is
  irreducible; a callback combinator hits the lambda-hides-`fuel+1` trap).
- **Boundary held (oracle-confirmed v0.16.1):** carrier & carrier MERGES (untouched —
  partner branch); carrier & output-field-struct BOTTOMS (untouched —
  `structHasOutputField`); carrier & decls-only-struct-without-embed BOTTOMS (the fix).
  Verified in the binary for both carriers × both operand orders × multi-decl.
- **Source path:** `{#a:1,5}` is a `.structComp` (not a `conjStructOperand?`-eligible
  plain struct), so `lazyConjMergedFields` returns `none` and `evalConjStandard`'s
  deferral fold builds the carrier then `meet`s it against plain `{#b:2}` — hitting the
  fixed arm. (The one subtlety: the merge was NOT a pre-eval field-fusion; the meet arm
  was the right locus.)
- **Pins:** flipped `ListTests.meet_scalar_carrier_with_decls_struct` → `…_bottoms` (+
  symmetric + `.embeddedList` analogs); `EvalTests.WITNESS_*_wrongly_merges` → positive
  `meet_*_with_declsonly_struct_bottoms` (+ symmetric, multi-decl, list analogs,
  carrier&carrier-merge + carrier&output-field-bottom source-level pins). CORRECT pins
  (`meet_two_{scalar_carriers,embedded_lists}`, output-field bottom) kept green.
- **Verify:** `lake build` 110 jobs clean; `check-fixtures.sh` zero drift; `shellcheck`
  n/a. NO new cue-divergence (Kue now CONFORMS). `cue-spec-gaps.md` row 58 PARTLY →
  CONFORMING.

## NEXT STEP — leader = `CARRIER-DECL-SELECT` (DRY, LOW)

**Audit counter = 1** (CARRIER-STRUCT-MEET = slice 1 of the new batch; two-phase audit due
after 2–3 slices, per [`../guides/slice-loop.md`](../guides/slice-loop.md) — A then B,
sequential, NOT `/ace-audit`). Full diagnosis in `plan.md` (the CARRIER-DECL-SELECT
block). One-paragraph recap:

- The two carriers' decl-SELECTION seam is byte-identical and SHOULD share a helper.
  `selectEvaluatedField`'s `.embeddedList _ _ decls` / `.embeddedScalar _ decls` arms
  (`Eval.lean:618-621` / `:622-625`) are character-for-character identical — AND identical
  to the plain `.struct` arm above (`:615-617`). The same triple repeats in the
  disj-resolved sub-case (`:637-640` / `:641-644`); `Runtime.lookupField?` repeats the
  carrier pair (`Runtime.lean:87-88`).
- **Fix:** a tiny `selectFromDecls base label decls` helper (returns the field's
  `selectedFieldValue` or the deferred `.selector`) shared by the struct + both carrier
  arms at each of the two `Eval.lean` sites; collapse the `Runtime` pair to one
  decl-bearing pattern. LOW-risk, behavior-preserving. The meet-arm edits were in
  `Lattice.lean`, NOT `Eval.lean`, so the select arms are intact (no churn collision).
  Distinct from the FOUR-classifiers ruling: there the classifiers DISAGREE; here the
  three arms AGREE exactly, so this is real duplication, not false-sharing.

### After CARRIER-DECL-SELECT — the item-6 LOW list (none soundness-bearing)

`module-file-scoped-imports`, parser strictness (`*(1|2)`, `__x`), the DRY items
(`selectEvaluatedField .disj` 5-arm, `resolveEmbeddedDisjDefault`), B2-A1/A2, A2-x/y,
`scalar-embed` provenance follow-ups. See `plan.md` § item 6.

`Eval.lean` < ~4500 re-split watch (ruling stands). `EvalTests.lean` growing; test-org
re-carve not yet due.

## Release state — `v0.1.0-alpha.20260622` cadence-due (attended; NOT cut)

Last release `v0.1.0-alpha.20260621`. UNRELEASED since: SC-1e, AD2-1, BI-2-residual,
BI-2-§3, EvalOps, import-eager-closedness, the two-phase audit, TL-1, TL-2,
scalar-embed-with-decls + B3, **and now CARRIER-STRUCT-MEET**. Cut
`v0.1.0-alpha.20260622` via `scripts/release.sh 0.1.0-alpha.20260622` (attended —
push/publish; CI/GitHub Actions banned; clean tree first). **Awaiting user greenlight — do
NOT cut.**

## STANDING CONTEXT (full detail in CLAUDE.md + guides/slice-loop.md)

- Autonomy grant in effect; resolve forks by philosophy; commit/push on `main` (attended).
- Spec is authority; `cue` (`/Users/chakrit/go/bin/cue` v0.16.1) a fallible cross-check,
  never the gate. Correctness over byte-compat. kue binary: `.lake/build/bin/kue`.
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on main tree.
- Orchestrator = thin re-spawner; one subagent per slice; two-phase audit (A then B) every
  2-3 slices. Per-slice duties: tests-first; log `cue-divergences.md`; flag
  `cue-spec-gaps.md`.
