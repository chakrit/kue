package repro

// A mutual `let` cycle: each name IS in scope for the other sibling let, so the
// references resolve, but evaluation detects a cycle spanning only `let` slots.
// cue v0.16.1 errors `cyclic references in let clause or alias`; kue matches.
let a = c
let c = a
b: a
