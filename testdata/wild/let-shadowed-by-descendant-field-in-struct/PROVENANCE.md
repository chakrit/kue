# let-shadowed-by-descendant-field-in-struct

**Source:** wild-caught 2026-07-04, probe matrix for the `let`/alias no-shadow rule.

**Adjudication:** cue v0.16.1 REJECTS a `let x` shadowed by a field `x` in a DESCENDANT
scope (here a list-element struct). REVERSE direction (ancestor `let`, descendant field);
kue enforces only the forward direction. Spec-adjudicated UNDER-rejection.

**Status:** RED (`.known-red`). See `docs/reference/cue-spec-gaps.md`.
