package repro

// Unifying two floats that are the SAME value but written with a different
// representation (differing trailing zeros, scale, or scientific vs decimal)
// must succeed and yield that value — never bottom. cue keeps the LEFT operand's
// rendering. kue historically compared `Prim` structurally, so `1.0 & 1.00`
// (distinct strings) was read as a primitive conflict even though `1.0 == 1.00`
// is true — a self-inconsistency between `&` and `==`. Spec: unification of two
// equal values is that value (idempotent meet on the numeric lattice).
a: 1.0 & 1.00
b: 0.10 & 0.1
c: 1.5 & 1.50
d: 100.0 & 1e2
