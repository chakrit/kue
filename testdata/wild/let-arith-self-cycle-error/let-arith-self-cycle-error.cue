package repro

// An arithmetic self-cycle: the let's RHS references its own name inside an
// expression. cue keeps the name out of its own scope, so it is unresolved:
// cue v0.16.1 ⇒ `reference "a" not found`. kue matches (single-let cycle).
let a = a + 1
b: a
