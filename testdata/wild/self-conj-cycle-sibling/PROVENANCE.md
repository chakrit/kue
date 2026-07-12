# self-conj-cycle-sibling

- **Source:** SELF-CONJ-CYCLE-INDIRECT (2026-07-12 fix-slice; shape 1, isolated by the
  Phase B audit).
- **Defect:** `x: 1` + `x: y & int` + `y: x` yielded `_|_` in kue where cue resolves the
  x→y→x reference cycle to top and produces `{x:1, y:1}`.
- **Observed root (instrumented):** NOT a cycle-truncation gap. The two `x` declarations
  collapse into one canonical eval slot, shifting `y` down one index; the `y` reference
  inside `x`'s merged body was authored (by `resolveStructRefs`) against the RAW
  pre-collapse layout, so it dangled into an out-of-bounds `unresolvedBinding` → `meet(1,
  bottom) = bottom` BEFORE the existing `visited`-truncation could ever apply.
- **Fix:** `buildFrame` now indexes the DEDUPLICATED layout (`canonicalFieldLayout`,
  mirroring `canonicalizeFields`), so resolve and eval agree; the reference cycle then
  truncates via the existing depth-0 `slotVisited` guard.
- **Spec basis:** CUE reference cycles resolve to top; a concrete co-conjunct dominates.
- **cue:** v0.16.1 ⇒ `{"x": 1, "y": 1}`. Status: GREEN (fixed).
