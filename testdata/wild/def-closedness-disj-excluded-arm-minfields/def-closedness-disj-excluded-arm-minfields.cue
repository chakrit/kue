package repro

import "struct"

// A `struct.MinFields` disjunction arm — a `.lengthConstraint` of kind `.fields` — is the
// SUBTLE case: it does NOT bottom against a struct literal, it COMPOSES with it
// (`{a:1,b:2} & struct.MinFields(2)` ⇒ the two-field struct with the residual satisfied). But
// the composed arm rides the def's CLOSED literal, so it carries NO NEW allowed field: the def
// distributes its literal, closes it around the `struct.MinFields(2)` arm, and the arm rejects a
// use-site extra exactly as the closed literal does. `#X: {a:1,b:2} & ({z:9} | struct.MinFields(2))`
// closes to `{a,b,z} | {a,b}`; a use-site `#X & {w:7}` adds an undeclared `w` → the `{a,b,z}` arm
// rejects it (w undeclared) and the `{a,b}` arm rejects it → the disjunction is empty → bottom.
// cue v0.16.1 ⇒ `y.w: field not allowed` (a CLOSED definition rejects the extra regardless of the
// `struct.MinFields` validator). Spec-adjudicated verdict: bottom.
#X: {a: 1, b: 2} & ({z: 9} | struct.MinFields(2))
y: #X & {w: 7}
