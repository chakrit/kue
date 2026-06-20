# RESUME HERE — BI-2 DONE (math.Pow exact + list.Sort/SortStable); F-3 next; audit NOT due (BI-2 = slice 1 of new batch) (2026-06-20)

Live START-HERE pointer; supersedes all prior breadcrumbs. Authoritative live roadmap:
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md)
§ Consolidated fix backlog (owns the ranked spec-conformance fixes) +
[`../spec/plan.md`](../spec/plan.md) (capabilities + non-spec roadmap).

**Latest (2026-06-20):** BI-2 landed (SPLIT) → **`math.Pow` (exact domain) + `list.Sort`/
`list.SortStable` now return correct values; `math.Sqrt` + the apd-Pow tail are a filed residual
(BI-2-residual).** Key finding: the slice premise "cue math = Go float64" is FALSE — cue's
`math.Pow` uses an apd 34-sig-digit DECIMAL context (`Pow(2,0.5)=1.414…209698`), while `math.Sqrt`
uses IEEE-754 FLOAT64 (`Sqrt(2)=1.4142135623730951`, sci-notation render `Sqrt(100)=1e+1`). Kue's
numeric core is EXACT base-10 rationals — no `Float`, no `NaN`/`Infinity`, no sci-notation. So:
**`math.Pow` is computed EXACTLY only for a non-negative integer exponent** (incl. whole-float
`3.0`, since `Pow(3,2.0)=9`) via repeated exact decimal multiply (`mathPow?`/`decimalPowNat`),
byte-identical to cue (`Pow(2,10)=1024`, `Pow(1.5,3)=3.375`, `Pow(0.1,2)=0.01` unpadded); `Pow(0,0)`
bottoms (CONFORMS — cue errors). Outside that → bottom (honest, never a wrong value).
**`list.Sort`/`SortStable`** are intercepted at the EVAL layer (`.builtinCall` arm of
`evalValueCoreWithFuel`, NOT `evalBuiltinCall` — the comparator `{x,y,less}` must be MET with
`{x:a,y:b}` and EVALUATED per pair, which the pure `Builtin` layer can't do). Comparator passed
UNEVALUATED (so `less`'s `x`/`y` slot-refs survive the meet); per-pair compare =
`.selector (.conj [cmp, {x:a,y:b}]) "less"` → bool; a non-bool `less` (incomplete/incomparable) →
recorded in eval-scoped `EvalState.sortError` → sort bottoms. Sort = total stable monadic merge sort
(`sortValuesM`, bottom-up, outside the mutual block, comparator threads the only recursive call back
in). ONE stable sort serves both. `list.Ascending`/`Descending`/`Comparer` (no-call package VALUES)
emitted by new `stdlibPackageValue?` as inline `{x,y,less}` AST, wired into `parseSelectorRest`. 13
Pow pins (`BuiltinTests`) + 13 Sort pins (`EvalTests`, end-to-end via `evalSourceMatches`) + 2
fixtures (`builtins/math_pow`, `builtins/list_sort`). 2 spec-gaps (Pow precision; Sort stability +
comparator-value display); no cue-divergence (every Pow/Sort RESULT conforms). cert-manager/argocd
unaffected (use neither builtin). See implementation-log + audit-history 2026-06-20.

**Audit state — BI-2 is slice 1 of a NEW batch; NO audit due.** The two-phase audit closed at
**Phase A `7ee15d8`** + **Phase B `457a165`** (counter reset to 0). BI-2 is the FIRST slice of the
new batch ⇒ next two-phase audit DUE after **2-3 NEW slices** (BI-2 = 1; so after ~1-2 more). When
it comes: run sequentially (A then B, both edit `plan.md`/this doc — parallel collides); follow
[`../guides/slice-loop.md`](../guides/slice-loop.md), do NOT invoke `/ace-audit`. **Phase-B rulings
to carry forward (do not re-litigate):** walker dedups are THREE distinct families (AD4-1 `EvalM`
clause-drivers / A-EN3 pure `Value` folds / DRY-1 let-fixpoint walkers) + a separate normalizer pair
(AD2-1) — four mechanisms, NOT one; sequence AD4-1 → A-EN3+DRY-1 → AD2-1, all post-argocd, gated.
The bottom-payload newtype (AD3-4) is RULED OUT (over-engineering). Test-org + plan-hygiene passes
are DUE-but-non-blocking (do not preempt the feature tail).

## IMMEDIATE NEXT STEPS (the loop can just `Keep going`)

1. **No audit due** (BI-2 = slice 1 of the new post-`457a165` batch; counter at 1). **Next leader =
   F-3** (below). Run ~1-2 more slices, then the two-phase audit (Phase A → Phase B).
2. **F-3 — NEXT.** Parse qualified import path `"location:identifier"` (currently unparsed; latent).
   A parse-layer addition (the import-clause parser); check the CUE spec for the exact
   `ImportSpec`/`location:identifier` grammar before coding.
3. **BI-1 — AFTER F-3, picked up with a DATA-APPROACH SPIKE FIRST (do NOT slice blind).** Unicode
   case-fold for `strings.ToUpper/ToLower` (currently ASCII-only → wrong on non-ASCII). ⚠ This is an
   **envelope risk**: full Unicode case-mapping likely needs a generated case-folding TABLE = a data
   dependency / possible network fetch (the grant forbids fetching external data into the repo
   without explicit need — if a builtin would require vendoring, STOP and flag). BI-1's slice MUST
   first decide: vendored generated table (checked-in, no fetch) vs scoped coverage (common ranges
   only). Reordered AFTER F-3 (which is self-contained) for this reason.
4. Then: **SC-3 display-residual** (LOW/spec-gap — cue collapses `*1|2`→`1`, `{…}|*null`→`null`; Kue
   does NOT, unsound; Format-layer projection rewriting ~7 fixtures, close only if the display
   convention is revisited) · **BI-2-residual** (Sqrt float64 + apd-Pow tail — needs Float/`NaN`/
   `Infinity`/sci-notation or a decimal numeric-methods module; lower priority, no app needs it).
5. Then the ranked tail in `spec-conformance-audit.md § Consolidated fix backlog`: **SC-4** (LOW,
   spec-check FIRST — cue is internally inconsistent here, don't reflexively match) · the 4
   spec-gap ratifications in `cue-spec-gaps.md` · **A#6** (`containsBottom` fuel cap 100,
   STANDALONE — D#2 confirmed it is NOT implicated by structural cycles; a real hardening item for
   deep NON-cyclic bottoms) · **DRY-1** (let-walker `walkFollowedLets` consolidation; schedule
   after Bug2-5 if that ever un-parks). **SC-1b** (closed×closed-pattern intersection) sits with
   this MED/hardening tail.
6. Plan-only roadmap (plan.md Live Backlog, NOT in audit.md): `truncate-primitive` (HIGH —
   soundness hardening) · Regex/EvalOps module extractions · test/fixture-org pass ·
   field-order #3 · A2-x/A2-y loader corners · B3/B5 incompleteness. NOTE: plan-side **A-EN3**
   and audit-side **DRY-1** look like the same let-walker consolidation — reconcile when picked.

**argocd / Bug2-5: PARKED** — a stress-test finding, not on the critical path. Resolves as the
general semantics mature; do not chase it with app-specific narrowing.

## CANONICAL PATHS (ground-truth — a prior auditor got confused; do NOT re-litigate)

- prod9 stress-test targets: `/Users/chakrit/Documents/prod9/infra/apps/argocd.cue` and
  `.../cert-manager.cue` (cert-manager is fully correct; argocd parked).
- cue oracle: `/Users/chakrit/go/bin/cue` (v0.16.1) — READ-ONLY, cross-check only.
- kue binary: `.lake/build/bin/kue` (or `lake exe kue`).

## STANDING CONTEXT (durable; full detail in CLAUDE.md + guides/slice-loop.md)

- Kue autonomy grant in effect (decide/proceed; resolve forks by philosophy; commit/push on
  `main` when attended). **Spec is authority; `cue` is a fallible cross-check, never the
  gate.** Correctness-over-performance. **Unattended/AFK → commit, don't push** (CLAUDE.md).
- Orchestrator = thin re-spawner; one subagent per slice; two-phase audit (A then B) every
  2–3 slices. Per-slice duties: tests-first; log `cue-divergences.md`; flag
  `cue-spec-gaps.md`; keep `kue-performance.md` current.
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on the main tree.
- Loose end (low priority): compat-assumptions.md "Composition note (infra docker-config)"
  (~L503–510) may be stale — `_auths` hidden-field refs + `[string]:` label patterns now
  likely resolve; needs a targeted end-to-end check on `secret.cue` before trusting.
