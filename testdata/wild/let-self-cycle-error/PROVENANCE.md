# let-self-cycle-error

- **Source:** SCOPING-PROBE (2026-07-12).
- **Defect:** A struct-level `let a = a` self-references its own binding. CUE keeps a
  `let` name OUT of scope within its own RHS, so the reference is unresolved and errors.
  kue represents a struct-level `let` as a field in the shared scope frame, so the RHS
  self-resolves and the reference-cycle rule collapses it to top (`b: _`), masking the
  error. (Mutual let cycles — `let a = c; let c = a` — are the sibling case: cue errors
  `cyclic references in let clause or alias`, kue also collapses to top.)
- **Spec basis:** CUE scoping — a `let` clause introduces its binding for sibling/later
  fields and other lets, never for its own RHS; a self/mutual let cycle is an error, in
  contrast to a FIELD self-cycle (allowed, treated as top).
- **cue:** v0.16.1 ⇒ `reference "a" not found`. kue ⇒ `incomplete value: _` (wrong: no
  error, wrong reason). Expected-err substring pins the spec verdict; the exact kue text
  is the fixer's to align on graduation.
- **Status:** QUARANTINED (`.known-red`). Needs let-vs-field distinction in the scope
  model + let-cycle detection. Filed as fix-slice LET-CYCLE-ERROR.
