# self-conj-cycle-indirect-resolve

- **Source:** SELF-CONJ-CYCLE-INDIRECT (2026-07-12 fix-slice; over-truncation guard).
- **Purpose:** GUARD that the index-rebase / cycle-truncation fix does not SUPPRESS a
  legitimate indirect resolve. `x: {a: 1}` + `x: {b: x.a}` merges to `{a: 1, b: x.a}`;
  `x.a` reads a non-cyclic sibling and must resolve to 1.
- **cue:** v0.16.1 ⇒ `{"x": {"a": 1, "b": 1}}`. Status: GREEN.
