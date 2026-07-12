// apd (General Decimal Arithmetic) result-exponent preservation through float
// division `/`. Like `+ - *` (see float-apd-exponent-preservation), the exact
// quotient's apd ideal form drives cue's rendered form (scientific notation,
// trailing zeros, `.0` presence); kue collapsed it by rendering the fully-expanded
// decimal (`6e2 / 3` → `200.0` instead of `2.0E+2`). VALUE was always correct;
// only the rendered FORM diverged. Rule (empirically pinned against
// `cue export --out json`, spec-silent DISPLAY → cue-compat): for the exact value
// `±m·10^k` (minimal, `m` trailing-zero-free), an integer value (`k ≥ 0`) whose
// adjusted exponent `k + digits(m) − 1 ≤ 32` gains one trailing zero, else the
// minimal form is kept. Non-terminating / >34-significant-digit quotients use the
// unchanged 34-digit rounding renderer.
divSci:      6e2 / 3
divScale:    1000000 / 8
divWhole:    8 / 2
divTrail:    100 / 4
divFrac:     1 / 4
divFrac2:    5 / 2
divMid:      1e2 / 4
divBig:      1e34 / 1
divBigCap:   1e33 / 1
divSmallSci: 25 / 100000000
divNeg:      -6e2 / 3
divNegDen:   6e2 / -3
divExp:      1e10 / 5
divTens:     10 / 1
divHundred:  100 / 1
divInexact:  1 / 3
divInexBig:  1e10 / 3
divZeroInt:  0 / 3
divZeroFlt:  0e2 / 8e3
