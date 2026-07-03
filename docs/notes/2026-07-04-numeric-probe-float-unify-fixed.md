# Breadcrumb — 2026-07-04 — NUMERIC CONFORMANCE PROBE: float-unify bug fixed

## What this slice did

Bounded conformance probe over numeric literals/formatting/arithmetic + a stdlib-builtin
sampling (AFK, unattended). Found and fixed one SEMANTIC divergence; filed the rest.

## Fixed (kue ≠ spec)

**FLOAT-UNIFY-EQUAL.** Unifying two floats equal-in-value but distinct-in-string
(`1.0 & 1.00`, `0.10 & 0.1`, `100.0 & 1e2`, `1.5 & 1.50`) bottomed in kue while cue/spec
yield the value — contradicting kue's own `==` (`1.0 == 1.00` is `true`). `meetPrim`
(`Kue/Lattice.lean`) compared `Prim` structurally. New `primsUnifyEqual` compares
float-vs-float by exact base-10 value (`parseDecimalText`+`decimalEqValues`), keeps the LEFT
operand (cue's rule); other kinds structural; int-vs-float stays a type conflict.
Wild fixture `float-unify-equal-diff-representation` (ENFORCED) + `NumberTests` `meet_prim_float_*`.

## Filed (not bugs / dedicated slices) — detail in plan.md § NUMERIC/BUILTIN CONFORMANCE PROBE

- **GDA-FLOAT-RENDER** (formatting; value-equal, notation-different): kue emits the stored
  float string, not CUE's apd GDA `to-scientific-string` canonical form. Diverges on
  `1e+2` vs `1E+2`, small-exponent decimal expansion (`1e-2`→`0.01`), large-magnitude
  scientific switch (`1e40`→`1E+40`), and negative-zero normalization (`-0.0`→`0.0` literal;
  `0.0*-1`→`-0.0` arith). Own churny slice; not adoption-blocking.
- **STRINGS-RUNES-MISSING** (`strings.Runes` unregistered → silent bottom) and
  **LIST-SLICE-MISSING** (`x[lo:hi]` parser gap) — feature gaps, not wrong-value bugs.

## Probed CLEAN (kue == cue == spec)

`0.1+0.2`, `1.0/3.0`, huge bignum, int/float unify-reject, all bounds, `math.Round/Floor/
Ceil/Trunc` (+neg/.5), `div/mod/quo/rem` signs, `len(string)` bytes (ascii/multibyte/emoji),
`strings.Join/Split/ToUpper/TrimSpace/Replace/Contains`, `list.Concat/Range/Sort/FlattenN`.

## Verify

`./scripts/check.sh` GREEN. cert-manager canary EMPTY (kue == cue after `jq -S`). Committed
on `main`, NOT pushed (AFK envelope).

## Next

Attended: cut the GDA-FLOAT-RENDER slice (highest-value follow-up — makes float export
byte-match cue's canonical form and fixes negative-zero) or implement `strings.Runes` +
list slicing. Resume plan HIGH/MEDIUM tail (B3d-6b registry; scalar-embed; LOW timeless-
comment sweep).
