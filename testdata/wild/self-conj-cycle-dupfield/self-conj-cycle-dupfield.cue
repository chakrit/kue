package repro

// Duplicate-field merge with a FORWARD reference across the collapsed slot
// (`x: 1` + `x: y` + `y: 1`). The two `x` declarations collapse to one canonical slot,
// shifting `y` down one index; `x`'s `y` reference must land on the shifted slot, not a
// stale higher index. `x = 1 & y = 1 & 1 = 1`, `y = 1`.
// Spec-adjudicated value (cue v0.16.1): {"x": 1, "y": 1}.
x: 1
x: y
y: 1
