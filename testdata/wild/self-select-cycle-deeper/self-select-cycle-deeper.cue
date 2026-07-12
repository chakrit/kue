package repro

// Two-selector self-cycle `x.a.b` (nested case of SELF-SELECT-CYCLE-CROSSFRAME). The chain
// selects field `b` of the inner struct we are evaluating inside — `b` referencing itself
// through `x.a.b`, a reference cycle → top, leaving `b = 1 & _ = 1`. Resolved through the
// live-frame chain resolver (`selectChainId?`), so no intermediate struct is force-collapsed.
// Spec-adjudicated value (cue v0.16.1): {"x": {"a": {"b": 1}}}.
x: {a: {b: 1}}
x: {a: {b: x.a.b}}
