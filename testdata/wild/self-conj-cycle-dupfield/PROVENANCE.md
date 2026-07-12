# self-conj-cycle-dupfield

- **Source:** SELF-CONJ-CYCLE-INDIRECT (2026-07-12 fix-slice; the minimal duplicate-field
  probe Phase B isolated).
- **Defect:** `x: 1` + `x: y` + `y: 1` yielded `_|_` in kue (`y` correctly `1`, yet `1 & y`
  bottomed) where cue produces `{x:1, y:1}`.
- **Observed root (instrumented):** the merged `x` body's `y` reference (`refId index 2`,
  authored against the raw 3-field layout) dangled after the two `x` slots collapsed to
  one, shifting `y` to canonical index 1 → `unresolvedBinding{index:2}` → bottom.
- **Fix:** resolve now indexes the deduplicated layout (`buildFrame` over
  `canonicalFieldLayout`), matching the evaluator's `canonicalizeFields` frame.
- **cue:** v0.16.1 ⇒ `{"x": 1, "y": 1}`. Status: GREEN (fixed).
