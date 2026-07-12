# self-conj-cycle

- **Source:** SCOPING-PROBE (2026-07-12 scoping / reference-resolution differential
  hunt vs cue v0.16.1).
- **Defect:** A multiply-declared field whose one declaration self-references inside a
  conjunction (`x: 1` + `x: x & int`) yields `_|_` in kue where cue resolves the
  self-reference to top (CUE reference-cycle rule) and produces `{x: 1}`. The
  single-declaration self-cycle form (`x: x & int` alone) already collapses to `int`
  correctly; the bug is specific to the multi-declaration merge path.
- **Spec basis:** CUE reference cycles — "a reference to a field within its own value is
  treated as top" — so `x & int` = `_ & int` = `int`, unified with `1` = `1`.
- **cue:** v0.16.1 ⇒ `{"x": 1}`. kue ⇒ `_|_` (wrong value).
- **Status:** QUARANTINED (`.known-red`). Mechanism is in the eval self-cycle / `visited`
  machinery interacting with same-name field merge; non-obvious, filed as a fix-slice
  (SELF-CONJ-CYCLE) rather than forced in the probe.
