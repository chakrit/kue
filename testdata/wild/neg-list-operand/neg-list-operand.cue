package repro

// Unary negation (`-`) requires a numeric operand. A ground list operand is a type
// error ("invalid operation"), NOT an incomplete value. cue v0.16.1 hard-errors; kue
// previously fabricated a residual `-[1, 2]` reported as "incomplete value" (the
// pre-existing twin of the bound soundness regression, slice a8e37e2). Spec: ⊥.
x: -[1, 2]
