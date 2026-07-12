# self-conj-cycle-fieldsel

- **Source:** SELF-CONJ-CYCLE-INDIRECT (2026-07-12 fix-slice; shape 2 — QUARANTINED as a
  DISTINCT root from shapes 1/dupfield).
- **Defect:** `x: {a: 1}` + `x: {a: x.a}` yields `_|_` in kue; cue v0.16.1 gives
  `{x: {a: 1}}` (inner `a: x.a` = `a` referencing itself → reference cycle → top → a stays
  1).
- **Observed root (instrumented):** NOT the resolve/eval index mismatch (there is no
  forward-ref shift here). `x.a` is evaluated by eagerly forcing the WHOLE enclosing struct
  `x` via a depth-1 self-reference, re-entering the in-progress `a` field. The frame-relative
  `visited` cycle guard resets on the depth-1 frame crossing (child-frame slot indices are
  meaningless in the parent), so the self-selection cycle is not detected and bottoms
  structurally instead of truncating to top.
- **Why quarantined:** a cross-frame selector reference-cycle needs a mechanism the
  frame-relative `visited` set structurally cannot provide (it cannot carry slot identity
  across frames) — a separate fix-slice, not the index-layout fix that closed shapes 1 and
  the dupfield probe. Phase B's "one class, one root" framing was incorrect: two roots.
- **Spec basis:** CUE reference cycles resolve to top; `a: a` → top, `1 & top = 1`.
- **cue:** v0.16.1 ⇒ `{"x": {"a": 1}}`. Status: QUARANTINED (`.known-red`).
