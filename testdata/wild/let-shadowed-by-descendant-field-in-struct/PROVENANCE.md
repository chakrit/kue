# let-shadowed-by-descendant-field-in-struct

**Source:** wild-caught 2026-07-04, probe matrix for the `let`/alias no-shadow rule.

**Adjudication:** cue v0.16.1 REJECTS a `let x` shadowed by a field `x` in a DESCENDANT
scope (here a list-element struct). REVERSE direction (ancestor `let`, descendant field);
kue enforces only the forward direction. Spec-adjudicated UNDER-rejection.

**Status:** GREEN (graduated 2026-07-04). The REVERSE no-shadow direction landed by modeling `Field.quoted` on the `Value` layer; the descendant field is checked against ancestor `let`s.
