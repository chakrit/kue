# self-select-cycle-deeper

- **Source:** SELF-SELECT-CYCLE-CROSSFRAME (2026-07-12) — nested (two-selector) probe of the
  cross-frame selector reference-cycle class.
- **Case:** `x: {a: {b: 1}}` + `x: {a: {b: x.a.b}}`. The chain `x.a.b` selects `b` of the inner
  struct being evaluated — `b` referencing itself → reference cycle → top → `b = 1 & _ = 1`.
- **Spec basis:** CUE reference cycles resolve to top. Resolved through the live-frame chain
  resolver `selectChainId?` (no intermediate struct force-collapse).
- **cue:** v0.16.1 ⇒ `{"x": {"a": {"b": 1}}}`. Status: FIXED (enforced).
