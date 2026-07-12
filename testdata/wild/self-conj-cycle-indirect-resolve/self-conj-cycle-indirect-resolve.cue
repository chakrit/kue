package repro

// GUARD (over-truncation, one direction): a legitimate indirect resolve through a
// duplicate-field merge must STILL resolve — the cycle-truncation fix must not suppress
// a valid same-struct field selection. `x: {a: 1}` + `x: {b: x.a}` merges to
// `x: {a: 1, b: x.a}`; `x.a` reads `a` (no cycle) = 1.
// Spec-adjudicated value (cue v0.16.1): {"x": {"a": 1, "b": 1}}.
x: {a: 1}
x: {b: x.a}
