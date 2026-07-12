# let-mutual-cycle-error

- **Source:** LET-CYCLE-ERROR (2026-07-12).
- **Defect class:** A pure-`let` cycle spanning several lets. cue v0.16.1 ⇒ `cyclic
  references in let clause or alias`; the reference cycle sits entirely on `letBinding`
  slots, so kue errors instead of collapsing to top.
- **Spec basis:** a `let` name is out of scope in its own RHS; a cycle composed only of
  lets is a load error, in contrast to a FIELD-anchored cycle (truncates to top).
