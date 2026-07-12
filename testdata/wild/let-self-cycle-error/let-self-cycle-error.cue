package repro

// A `let` binding is NOT in scope within its own right-hand side: a `let`'s RHS
// sees sibling fields and OTHER (non-cyclic) lets, but never itself. A direct
// self-reference (`let a = a`) is therefore an unresolved reference, and cue
// v0.16.1 hard-errors `reference "a" not found`. (A mutual let cycle is the
// sibling error `cyclic references in let clause or alias`.)
// kue instead treats a struct-level `let` exactly like a field: its binding is
// in the shared frame, so the RHS self-resolves and the reference-cycle rule
// collapses it to top (`b: _`, incomplete) — masking the load error.
// Spec-adjudicated verdict: a reference error (the let name is out of scope in
// its own RHS), NOT an incomplete top.
let a = a
b: a
