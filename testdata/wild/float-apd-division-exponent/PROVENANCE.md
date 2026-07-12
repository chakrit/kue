# float-apd-division-exponent

Source: F4 float-campaign division follow-up (manual probing of `cue eval` /
`cue export --out json`, cue v0.16.1), 2026-07-12.

The `+ - *` slice (float-apd-exponent-preservation) threaded the apd
`(coefficient, exponent)` form so arithmetic results render in cue's GDA
`to-scientific-string` form, but DIVISION was deferred: kue rendered the exact
quotient with the fully-expanded 34-digit-rounding decimal renderer, collapsing
the apd ideal exponent (`6e2 / 3` → `200.0` where cue gives `2.0E+2`). The value
was always correct; only the rendered FORM diverged.

Spec-adjudicated against the CUE spec's use of General Decimal Arithmetic
(apd / IEEE-754-2008 decimal). The DISPLAY form is spec-silent, so the tiebreak
is cue-compat (see docs/spec/cue-spec-gaps.md STDLIB-FLOAT-F4). The exact-division
ideal form depends ONLY on the quotient VALUE (verified: all operand-exponent
spellings of the same value render identically), pinned via `cue export --out json`
(JSON's empty whole-tail disambiguates a real trailing `.0` from an integer's
style suffix). For the exact value `±m·10^k` (minimal form, `m` trailing-zero-free,
`d = digits(m)`): an integer value (`k ≥ 0`) whose adjusted exponent
`k + d − 1 ≤ 32` (= apd precision 34 − 2) gains one trailing zero `(10·m, k−1)`
(forcing the `.0`/`X.0e+n` float form), otherwise the minimal form `(m, k)` is
kept. A zero numerator keeps the ideal exponent clamped to `0` (renders `0`) when
`e₁ − e₂ ≥ 0`, else `−1` (renders `0.0`). Non-terminating or >34-significant-digit
quotients keep the unchanged 34-digit rounding renderer, which already renders
correctly (it re-parses through the apd render anchor).
