package repro

// A PLAIN sibling reference (not a conjunction) crossing a collapsed duplicate slot:
// `x` is declared twice (collapsing to one slot), and a later field `z` references `y`,
// which sits after the collapse point. `z`'s reference must land on `y`'s canonical
// slot, not the raw pre-collapse index. Demonstrates the defect is the resolve/eval
// index-layout mismatch, independent of conjunction merging.
// Spec-adjudicated value (cue v0.16.1): {"x": 1, "y": 5, "z": 5}.
x: 1
x: 1
y: 5
z: y
