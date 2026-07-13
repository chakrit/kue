# export-error-bottom-precedence

- **Source:** DEF-CLOSEDNESS-INDIRECT-DISJ-CONJ fold (2026-07-13). Surfaced while
  graduating `def-closedness-disj-referent`: with a PLAIN exported `foo`, the closedness
  fix correctly bottoms `y`, but kue's export reported `foo`'s "ambiguous value" instead.
- **Defect:** kue's manifest (`manifestFieldsWithFuel`) walks top-level fields in SOURCE
  order and short-circuits on the FIRST field that errors. When an INCOMPLETE field
  (unresolved disjunction / abstract type) precedes a hard CONTRADICTION field, kue reports
  the incomplete error and MASKS the bottom.
- **Spec basis:** cue v0.16.1 reports a definite CONTRADICTION over an incomplete sibling
  regardless of source order — a hard bottom is the dominant export error.
- **cue:** `y.x: conflicting values 2 and 1`. **kue:** `ambiguous value: multiple
  non-default disjuncts remain` (source-first field masks the bottom).
- **Fix direction:** export error selection should prefer a `.contradiction` over an
  `.incomplete`/`.ambiguous` sibling (collect field errors, pick the contradiction) rather
  than short-circuiting on the first. Orthogonal to closedness — separate blast radius
  across error-message fixtures.
- **Status:** QUARANTINED (`.known-red`). Filed as backlog EXPORT-ERR-BOTTOM-PRECEDENCE.
