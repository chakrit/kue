# let-shadowed-by-field-in-def-body

**Source:** wild-caught 2026-07-04, probe matrix for the `let`/alias no-shadow rule.

**Adjudication:** cue v0.16.1 REJECTS a `let x` shadowed by a field `x` inside a nested
DEFINITION body. REVERSE direction (ancestor `let`, descendant field); kue enforces only
the forward direction. Spec-adjudicated UNDER-rejection.

**Status:** RED (`.known-red`). See `docs/reference/cue-spec-gaps.md`.
