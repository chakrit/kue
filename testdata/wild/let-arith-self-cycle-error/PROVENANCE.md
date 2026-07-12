# let-arith-self-cycle-error

- **Source:** LET-CYCLE-ERROR (2026-07-12).
- **Defect class:** A direct `let` self-cycle inside an arithmetic operand (`let a = a + 1`).
  A single-slot let cycle ⇒ cue `reference "a" not found`; kue matches.
- **Spec basis:** a `let` name is out of scope in its own RHS, so the self-reference is
  unresolved regardless of the surrounding expression.
