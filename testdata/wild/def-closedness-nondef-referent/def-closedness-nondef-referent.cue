package repro

// A definition whose body INDIRECTS (a bare ref, selector, or index) to a
// NON-definition struct must still close: the value of a definition is closed
// regardless of how it is reached. cue v0.16.1 rejects `y.z` (`field not
// allowed`). kue LEAKS — it admits `z:9` — because closedness is only derived
// when the referent flatten-resolves to a DEFINITION; a non-def referent leaves
// `close` false and the body inlines OPEN.
//
// Sibling of DEF-CLOSEDNESS-REREF-DROP (`#X: #Y`, #Y a def), which IS fixed.
// The DEF-BODY-CLOSEDNESS-UNIFY provenance dispatch routes this body to the
// "sound side" (`some [body]`) but the routing is only inert when the referent
// carries no closedness — here the referent SHOULD carry definition closedness
// and does not, so the leak survives.
//
// Spec-adjudicated verdict: closed. `y.z` is a field not allowed on #X.
foo: {a: 1}
#X: foo
y: #X & {z: 9}
