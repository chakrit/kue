# RESUME HERE — BI-2 family COMPLETE; next leader = EvalOps (item 2) (2026-06-21)

Live START-HERE pointer; supersedes
`2026-06-21-resume-audit-round-CLOSED-next-BI-2-sec3.md` (deleted, with the two stale
`SC-1e`/`AD2-1` breadcrumbs the prior rotation failed to delete). Authoritative live
roadmap: [`../spec/plan.md`](../spec/plan.md) (capabilities, ranked backlog) +
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md).

## ★ AUDIT STATE — counter = 1 (slice 1 of the new batch landed). Next two-phase audit due after 2-3 slices.

The prior audit round closed (counter reset 0). BI-2-§3 is the FIRST slice of the new
batch ⇒ counter = 1. Run the two-phase audit (`docs/guides/slice-loop.md`, Phase A then B
— do NOT invoke `/ace-audit`) after 1-2 more slices land.

## ✦ JUST LANDED — BI-2-§3 (`cd2f0a9`): general math.Pow in EXACT DECIMAL

The **BI-2 family is now COMPLETE** — `math.Pow`/`math.Sqrt` cover their full real domain in
exact-precision decimal, no `Float`, axiom-clean:
- **§1** negative-INTEGER exponent: `x^(-n)=1/x^n` (exact rational, `reciprocalDecimalToValue`).
- **§2** general non-½ fractional (`x>0`): `x^y = exp(y·ln x)` via `decimalExpScaled`/
  `decimalLnScaled` (`Kue/Decimal.lean`) — fixed 40/60-term Taylor + binary range reduction,
  working scale 50, structurally total (zero axioms on the two transcendentals). Rounds to 34
  sig digits, collapses integral results. Mantissa byte-identical to cue's apd across 40 random
  + extreme cases; `Pow(2,0.5)=Sqrt(2)` cross-check holds.
- Domain edges (`Pow(neg,non-int)`, `Pow(0,0)`, `Pow(0,neg)`) → bottom (no `NaN`/`Infinity`).
- 13 BuiltinTests pins + 11 `math_pow` fixture cases. Divergences/spec-gaps recorded.

Verify on resume (cheap done-check): tree clean, pushed, `lake build` green (108 jobs),
`check-fixtures.sh` → `fixture pairs ok`.

## NEXT STEP — ranked (next leader = EvalOps, item 2)

1. **EvalOps extraction (NEXT) — plan item 2.** ~256 lines of pure scalar algebra carved to
   `Kue/EvalOps.lean`; mechanical, parallel-safe, lower-risk, not urgent (`Eval` under the
   ~4500 re-split threshold — 3702). Resolve the import shape: it calls the four decimal ops
   (`addDecimalValues`/`subDecimalValues`/`mulDecimalValues`/`evalDecimal*?`) from `Decimal`,
   so the carve must keep `EvalOps → Decimal` (no back-edge to `Eval`).
2. **item-6 LOW/opportunistic list** — scalar-embed-with-decls, import-eager-closedness,
   module-file-scoped-imports, parser strictness, B3, B2-A1/A2, A2-x/y, the
   `selectEvaluatedField .disj` DRY — none block adoption.

PARKED: **Bug2-5** (argocd residual, a stress-test finding — not on the critical path).

RESOLVED / ruled out (do not re-file): the BI-2 family (now COMPLETE), AD2-1 (unified),
DRY-1, SC-3 (recorded spec-gap convention only).

Re-enter the slice loop: spawn EvalOps as the next slice unless re-orientation surfaces a
higher priority. After it (+ maybe one more), run the two-phase audit.
