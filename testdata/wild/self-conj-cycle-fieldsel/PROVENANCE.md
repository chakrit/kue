# self-conj-cycle-fieldsel

- **Source:** SELF-CONJ-CYCLE-INDIRECT (2026-07-12 fix-slice; shape 2 — QUARANTINED as a
  DISTINCT root from shapes 1/dupfield).
- **Defect:** `x: {a: 1}` + `x: {a: x.a}` yields `_|_` in kue; cue v0.16.1 gives
  `{x: {a: 1}}` (inner `a: x.a` = `a` referencing itself → reference cycle → top → a stays
  1).
- **Observed root (instrumented):** NOT the resolve/eval index mismatch (there is no
  forward-ref shift here). `x`'s two-declaration value is a `.conj`; `x.a` eagerly forces the
  WHOLE enclosing `x` and re-enters its in-progress body. A `.conj` body is not struct-like, so
  the `structStack` guard never fires — the re-entry recurses fuel-deep and bottoms. (A single
  `.struct` body instead bottoms via `structStack` as a false structural cycle.) The
  frame-relative `visited` cycle guard cannot carry slot identity across the frame crossing.
- **Fix (SELF-SELECT-CYCLE-CROSSFRAME):** resolve `x.label` to `label`'s slot in the LIVE
  enclosing frame — found by `pushFrame`'s deterministic `(parentIds, fields)` frame identity
  (`enclosingSelfSelectId?` / `selectChainId?`), not a label heuristic — so the self-selection
  inherits the depth-0 `slotVisited ⇒ truncate .top` reference-cycle rule. A cross-struct select
  whose frame is not live falls through to the ordinary force-then-select path.
- **Spec basis:** CUE reference cycles resolve to top; `a: a` → top, `1 & top = 1`.
- **cue:** v0.16.1 ⇒ `{"x": {"a": 1}}`. Status: FIXED (enforced, graduated 2026-07-12).
