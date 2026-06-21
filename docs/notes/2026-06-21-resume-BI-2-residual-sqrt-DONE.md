# RESUME HERE — BI-2-residual SPLIT: math.Sqrt + Pow(·,½) DONE in EXACT DECIMAL (2026-06-21)

Live START-HERE pointer; supersedes
`2026-06-21-resume-AD2-1-DONE-normalizer-dedup-CLOSED.md`. Authoritative live roadmap:
[`../spec/plan.md`](../spec/plan.md) (capabilities, ranked backlog) +
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md).

## ★ AUDIT STATE — counter = 3. **Two-phase audit is OVERDUE** (run BEFORE the next code slice).

It was already DUE at counter = 2 (SC-1e=1, AD2-1=2) per the prior breadcrumb; this
BI-2-residual sqrt slice is **slice 3** → counter = 3. Run the two-phase audit NOW over the
SC-1e + AD2-1 + BI-2-residual batch, BEFORE any new code slice — (A) code-quality, then (B)
architecture/refactor/cleanup over the module graph. Procedure:
[`../guides/slice-loop.md`](../guides/slice-loop.md) (NOT the `/ace-audit` skill). Reset the
counter to 0 after.

## ✦ THIS SLICE — math.Sqrt + math.Pow(·, ½) computed in EXACT DECIMAL (Float AVOIDED)

The prior "BI-2-residual needs a Float/NaN/Infinity model, USER-GATED" framing was WRONG and
is dropped. Kue is exact-rational, so the sound move is decimal, not IEEE.

- **`Decimal.sqrt` (`decimalSqrt`)** — FIXED-iteration integer-Newton square root
  (`isqrtNewton`/`isqrtNat`: `x' = (x + N/x)/2` on `Nat`, budget `2·digits + 8`, min-tracked
  to land EXACTLY on `⌊√N⌋`). Structurally recursive on the budget ⇒ TOTAL, no
  `termination_by`, no `partial`. `#print axioms` clean (standard axioms only; `isqrtNewton`
  has none). For `a = num/10^s`: `√a = ⌊√(num·10^(2P−s))⌋/10^P`, `P = max(40, ⌈s/2⌉)`.
  Perfect squares collapse to int, irrationals → 34 sig digits via the shared division
  renderer (DRY). `Sqrt(2) = 1.414…209698` byte-identical to cue's apd `Pow(2,0.5)`.
- **`math.Sqrt` + `math.Pow(·, ½)`** both route through `decimalSqrtSigned`, so
  `Sqrt(x) = Pow(x, ½)` by construction (cue's float64 `Sqrt` ≠ its apd `Pow` — cue is
  internally inconsistent; Kue is more precise + self-consistent).
- **Domain errors BOTTOM, never NaN/Infinity:** `Sqrt(neg)`, `Pow(neg, ½)` (complex).
  `Pow(0, neg)` stays in the open residual (also bottoms).
- 17 `BuiltinTests` pins + `builtins/math_sqrt` fixture (14 cases, full parse→eval on CLI +
  Lean port). 2 `cue-divergences.md` rows (Sqrt-vs-float64; NaN/Inf→bottom — kue-MORE-correct).
  `cue-spec-gaps.md` Pow row extended to Sqrt.

Gate: `lake build` green (108 jobs, axiom-clean — no `sorryAx`/`partial`);
`check-fixtures.sh` → `fixture pairs ok` (zero drift; 1 new pair); `shellcheck` n/a (no shell
touched). Additive at the builtin layer — cannot regress cert-manager/argocd (use neither).
Detail: implementation-log `## Completed Slice: BI-2-residual — math.Sqrt …`;
`spec-conformance-audit.md` BI-2-residual SPLIT entry.

## STATUS SNAPSHOT (post-BI-2-residual sqrt)

- **BI-2-residual: SPLIT.** sqrt + Pow(·,½) DONE in exact decimal (Float correctly avoided).
  Open residual-of-residual: a GENERAL negative/non-½ fractional `Pow` + `Pow(0,neg)` — needs
  `decimalExp`/`decimalLn` (fixed-term Taylor + arg reduction, still NO Float). Filed with
  full design in `spec-conformance-audit.md`. A cheaper FIRST sub-increment: negative-INTEGER
  exponents `x^(-n) = 1/x^n` (existing exact int-pow + division renderer, no exp/ln).
- **Walker/normalizer-dedup family: FULLY CLOSED** (AD4-1 + A-EN3 DONE, DRY-1 ruled out,
  AD2-1 resolved).
- **Genuinely-open backlog:** the BI-2-residual exp/ln increment (MED, autonomous — NOT
  user-gated; Float was avoided), EvalOps extraction (mechanical, autonomous, not urgent),
  SC-4 (LOW, spec-gap-first). PARKED: Bug2-5 (argocd residual). SC-3 is a recorded spec-gap
  only (multi-arm-default display).

## NEXT STEP

Run the **two-phase audit** (counter = 3, OVERDUE) over the SC-1e + AD2-1 + BI-2-residual
batch per `slice-loop.md`. After it (counter reset), the next autonomous slices are the
BI-2-residual neg-int-Pow sub-increment (cheapest, no exp/ln) then EvalOps extraction —
unless the audit surfaces a higher-priority fix-slice.
