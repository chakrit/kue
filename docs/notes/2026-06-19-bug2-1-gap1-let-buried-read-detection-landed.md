# RESUME HERE — Bug2-1 (Gap-1 + A-EN1) landed; Gap-2 (Bug2-2) is the next argocd blocker (2026-06-19)

**START HERE.** Supersedes
[`2026-06-19-argocd-bug-pinned-comprehension-guard-embed-narrowing.md`](2026-06-19-argocd-bug-pinned-comprehension-guard-embed-narrowing.md)
as the current pointer. Standing grant in effect (autonomy / Lean-into-Lean-4 / commit-push freely /
specs as restore point).

## What this slice did (Bug2-1 — Gap-1 + A-EN1)

Landed the LOW-RISK first half of the argocd Bug #2 fix: **let-buried comprehension read-label
detection.** Bug #1 made the embed splice carry the regular siblings a comprehension's guard reads,
but the read-label analysis (`defFrameRefIndices`/`embedComprehensionReadLabels`, `Eval.lean`) treated
a `.refId` as a LEAF — it never followed a `letBinding` ref into its bound value. So a comprehension
buried under a `let` (`let _patch = {… for … if kind == … }`) reading the regular sibling `kind`
THROUGH the let was never detected → never spliced → the guard fired against the un-narrowed
`kind: string` → the body dropped (shapeA/shapeB wrong-output).

**Fix — follow `letBinding` refs transitively, cycle-bounded.** New `closeDefFrameReadIndices`
(`Eval.lean`) closes the detected def-frame index set over `let` slots: for each `let` slot in the
frontier it scans that let's bound value (at depth 0 — a let value is lexically a sibling, scanned
the same way the top-level `cs`/fields are; inner struct/comprehension wrappers thread `+1` so a ref
to the def frame matches) for more def-frame reads, then recurses on the newly-found lets. A
`visited`-set follows each let slot AT MOST ONCE → a self/mutually-referential `let` cannot loop
(TOTAL); a `fuel = fields.length` second bound keeps it structurally total. Covers BOTH the
`if`-guard read (Gap-1) and the `for`-SOURCE read (A-EN1, rides along — same additive detection).
Soundness identical to Bug #1 (only WIDENS the spliced-label set; a real conflict still bottoms via
merge-by-label).

### Tests (oracle-checked vs cue 0.16.1)

- Module fixtures `testdata/modules/{let_buried_guard_read,let_buried_two_lets,let_buried_for_source}`
  — shapeA (one let), shapeB (two nested lets), A-EN1 (`for … in items` source through a let). All now
  emit the patch/keys matching cue.
- `native_decide` pins in `TwoPassTests.lean`: one-let + two-let detection mechanism, A-EN1 end-to-end,
  positive + guard-false (no over-fire) + real-conflict-bottoms (SOUNDNESS via `exportJsonBottoms`) +
  no-over-splice + self-ref-cycle-terminates (totality).
- Verify: `lake build` green (96 jobs), `scripts/check-fixtures.sh` → `fixture pairs ok` ZERO drift
  (cert-manager content-identical ~30.5s, modulo field-order #3), `shellcheck` clean.

### argocd status

As EXPECTED for the Gap-1-only half: `kue export apps/argocd.cue` STILL bottoms (~88s). Gap-1 fixes
the shapes (shapeA/B + A-EN1) but does NOT clear shapeD or the app — that needs Gap-2.

## Next step

**Slice Bug2-2 — Gap-2 (force-tier disjunction-arm narrowing). The argocd unblock; GATED, riskier.**
Design is in `plan.md` "Bug #2 design (implementable)" → Gap-2. An embedded def `#M` containing a
discriminated disjunction selects the right arm when narrowed DIRECTLY (`#M & {narrow}`), but when
`#M` is itself embedded one layer down (`#U:{#M}` then `#U & {narrow}`), the outer narrowing does not
reach `#M`'s disjunction arms behind the force tier. **Mechanism:** in the force path, when a forced
embedded def body contains a default/discriminated disjunction embedding, distribute the spliced use
operands into each arm and PRUNE dead arms (`liveAlternatives`) — mirroring the
`meetEmbeddingsWithFuel` arm-distribution that works one tier up. **SOUNDNESS: GO-WITH-GATE** — this
is the regression-prone disjunction-arm family (link-5/A5/B6). Hard gate: **byte-identical
cert-manager MANDATORY**; gate Gap-2 to fire ONLY when a forced embedded def body contains a
disjunction embedding AND the outer narrowing selects among its arms (no disjunction embedding →
byte-identical). Never commit to the default arm first; a real conflict that kills ALL arms must
still bottom (the `error("…")` arm is itself a bottoming arm). **If it can't be gated off
cert-manager's bytes → STOP-AND-REPORT** (file the design + the hole; do NOT ship a cert-manager byte
drift). Repros: `/tmp/bug2/shapeD.cue` (the symptom), `probe_disj_inline`/`probe_disj_direct`
(isolate Gap-2 with zero let/comprehension noise), `probe_hidden_disj` (confirms Gap-2 orthogonal to
Gap-1). After Gap-2: **RE-MEASURE `kue export apps/argocd.cue`** — success signal (88s bottom →
expect non-bottom export, modulo field-order #3; residual is the item-7 PERF wall, no longer a
correctness bottom).

**Behind Bug2-2:** A-EN3 (the walker consolidation — fold `defFrameRefIndices` incl. its new
let-following + `selfReferencedLabels` + `refsSelfEmbeddedLabel` behind one generic frame-aware fold;
LOW, DRY not correctness) ↔ item-7-perf-guide reconciliation. Then item 7 (frame-id canonical
identity, the PERF wall), B6-deferred sub-gap, field-order #3, the other LOW items.

## Audit cadence

Bug2-1 is **1 code slice** since the last two-phase audit (the prior audit covered item 7 + Bug #1).
The audit is DUE at the 2-3-slice mark — likely AFTER Bug2-2 (which would be slice 2). Bug2-2 first,
then the two-phase audit if the cadence calls for it.

## Standing rules

- prod9 + cue caches READ-ONLY (eval/probe only). NO `git checkout`/`restore`/`reset --hard`. No env
  mutation outside the project tree.
