package repro

// Self-cycle via own-field selection (multi-declaration). `x: {a: 1}` + `x: {a: x.a}`
// merges to `x: {a: 1 & x.a}`; the inner `a: x.a` selects field `a` of the enclosing
// struct `x` — `a` referencing itself, a REFERENCE cycle (a → a) that truncates to top,
// leaving `a = 1 & _ = 1`. The selection resolves DIRECTLY to `a`'s slot in the live
// enclosing frame (frame-identity match), inheriting the depth-0 reference-cycle rule.
// Spec-adjudicated value (cue v0.16.1): {"x": {"a": 1}}.
x: {a: 1}
x: {a: x.a}
