# Numeric model: exact decimal, no Float (2026-06-22)

## Status

Accepted.

## Context

CUE numbers are arbitrary-precision. Kue's numeric core is exact base-10 rational/decimal
(`Kue/Decimal.lean`, apd-style). The `math` builtins forced the question of how to compute
irrational/transcendental results: `math.Sqrt`, and `math.Pow` with negative or fractional
exponents.

`cue` v0.16.1 is internally inconsistent here: `math.Pow` uses a 34-significant-digit apd
**decimal** context (`Pow(2, 0.5) = 1.414…209698`), but `math.Sqrt` uses IEEE-754 **float64**
(`Sqrt(2) = 1.4142135623730951`, ~17 digits, Go scientific-notation rendering, and
`NaN`/`Infinity` out of domain). So in `cue`, `Sqrt(2) ≠ Pow(2, 0.5)`.

## Decision

Kue stays **exact-rational/decimal for all numeric operations, including transcendentals**.
No `Float`, no `NaN`, no `Infinity`.

- `Decimal.sqrt` via fixed-iteration integer-Newton; `Decimal.exp`/`ln` via fixed-term Taylor
  series with range-reduction. Fixed counts ⇒ structurally total (no `partial`, axiom-clean),
  computed to a 34-significant-digit context. `Sqrt(x) = Pow(x, ½)` by construction
  (internally consistent — the property `cue` lacks).
- Out-of-domain (`Sqrt(neg)`, `Pow(0, neg)`, `Pow(neg, non-integer)`) → **bottom** (a lattice
  error), never `NaN`/`Infinity` — those are float artifacts, not lattice elements
  (illegal-states-unrepresentable).

`cue`'s float64 `Sqrt` is treated as the fallible reference it is: where Kue's decimal `Sqrt`
diverges from `cue`'s float64 in the low-order digits, Kue is more precise and self-consistent
— the divergence is recorded in `cue-divergences.md`, not matched.

## Alternatives rejected

- **Introduce a `Float`/`NaN`/`Infinity` model to match `cue`'s float64 `Sqrt` byte-for-byte.**
  Rejected: it contradicts the exact-rational core, introduces illegal states (`NaN`), and
  would chase a `cue` artifact (its own `Sqrt` ≠ `Pow`). "Byte-identical to `cue`" is never
  the correctness gate — `cue` is a fallible cross-check (see
  [`2026-06-14-cue-compatibility-target.md`](2026-06-14-cue-compatibility-target.md)).

## Consequences

- The `math` builtin family is complete in decimal: `Pow` over its full real domain, `Sqrt`,
  `exp`, `ln`.
- Kue's `Sqrt` / fractional `Pow` diverge from `cue`'s float64 `Sqrt` in low digits
  (documented); within Kue, `Sqrt` and `Pow` agree. Out-of-domain bottoms, vs `cue`'s NaN/Inf.
- Future math builtins needing transcendentals reuse the decimal `exp`/`ln`/`sqrt`; do NOT
  reach for `Float`. This is the ruling to cite if `Float` is ever proposed again.
