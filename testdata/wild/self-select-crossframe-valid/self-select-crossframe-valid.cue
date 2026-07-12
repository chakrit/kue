package repro

// Over-suppression guard: `y.b: x.a` selects a field of a DIFFERENT struct `x` whose frame is
// NOT the live enclosing one — a genuine cross-struct select that must RESOLVE (not be mistaken
// for a self-cycle and truncated to top). The self-select cycle fix keys on frame IDENTITY, so
// `x`'s frame being absent from the stack leaves the ordinary force-then-select path in charge.
// Spec-adjudicated value (cue v0.16.1): {"x": {"a": 1}, "y": {"b": 1}}.
x: {a: 1}
y: {b: x.a}
