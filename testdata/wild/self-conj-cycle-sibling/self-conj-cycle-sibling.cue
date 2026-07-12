package repro

// A field declared multiply where one declaration references a SIBLING that in turn
// references back (`x: 1` + `x: y & int` + `y: x`). The reference cycle x→y→x must
// truncate to top so the concrete conjunct dominates: `x = 1 & (y & int)` with `y`
// resolving through the cycle to top → `x = 1 & int = 1`, and `y = x = 1`.
// Spec-adjudicated value (cue v0.16.1): {"x": 1, "y": 1}.
x: 1
x: y & int
y: x
