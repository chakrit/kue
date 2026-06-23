// missing-field-selection (soundness): a field supplied by a LATER conjunct must have been
// provisional, NEVER pre-bottomed. `x` merges `{a:1}` and `{b:2}` before selection, so `x.b` is
// PRESENT — `== _|_` false, `!= _|_` true. The absent rule fires only on FINAL absence. cue:
// `eq false, neq true`.
x: {a: 1}
x: {b: 2}
eq:  x.b == _|_
neq: x.b != _|_
