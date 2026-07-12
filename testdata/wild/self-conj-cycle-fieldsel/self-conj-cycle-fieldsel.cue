package repro

// Self-cycle via own-field selection (multi-declaration). `x: {a: 1}` + `x: {a: x.a}`
// merges to `x: {a: 1 & x.a}`; the inner `a: x.a` is `a` referencing itself through the
// enclosing struct — a REFERENCE cycle (a → a) that must truncate to top, leaving
// `a = 1 & _ = 1`. cue v0.16.1 yields {"x": {"a": 1}}.
// kue currently FABRICATES _|_: `x.a` eagerly forces the whole enclosing struct `x`
// (re-entering the in-progress `a` field) and the frame-relative `visited` cycle guard
// does NOT cross the depth-1 self-selection frame, so the re-entry bottoms structurally
// instead of collapsing to top. Distinct root from the sibling/dupfield shapes (which
// are a resolve/eval index-layout mismatch) — a cross-frame selector reference-cycle.
// Spec-adjudicated value: {"x": {"a": 1}}.
x: {a: 1}
x: {a: x.a}
