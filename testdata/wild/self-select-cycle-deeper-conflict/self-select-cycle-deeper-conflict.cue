package repro

// Over-truncation guard (nested): a REAL conflict through the two-selector cycle must STILL
// bottom. `x.a.b` truncates to top, so `b = 1 & (top & 2) = 1 & 2` — conflicting values.
// cue v0.16.1: `x.a.b: conflicting values 2 and 1`.
x: {a: {b: 1}}
x: {a: {b: x.a.b & 2}}
