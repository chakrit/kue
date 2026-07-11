# float-apd-exponent-preservation

Source: F4 float-campaign slice (manual probing of `cue eval`/`cue export`), 2026-07-11.

Kue normalized the apd exponent into `DecimalValue.numerator` at parse time, so float
`+ - *` results rendered the fully-expanded form (`2e2 * 3` → `600.0`) instead of cue's
GDA `to-scientific-string` form (`6E+2`). The value was always correct; only the rendered
FORM diverged. Adjudicated against the CUE spec's use of General Decimal Arithmetic
(apd / IEEE-754-2008 decimal): add/sub result exponent = min(operand exponents),
multiply = sum, both rounded half-up to the 34-digit apd context precision.

Division's ideal-exponent (subtler apd rule) is DEFERRED — see
docs/spec/cue-spec-gaps.md — so this fixture omits `/`.
