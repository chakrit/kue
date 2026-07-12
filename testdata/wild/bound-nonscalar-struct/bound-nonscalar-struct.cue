package repro

// A comparator bound requires an ORDERED SCALAR operand (number, string, bytes). A
// ground struct operand is a type error, NOT an incomplete value. cue v0.16.1
// hard-errors; kue previously fabricated a residual `<{a: 1}` reported as
// "incomplete value" (soundness regression from slice a8e37e2). Spec-correct: ⊥.
x: <{a: 1}
