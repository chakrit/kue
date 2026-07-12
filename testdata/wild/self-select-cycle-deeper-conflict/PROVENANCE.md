# self-select-cycle-deeper-conflict

- **Source:** SELF-SELECT-CYCLE-CROSSFRAME (2026-07-12) — over-TRUNCATION guard (nested): a real
  conflict through the two-selector cycle must STILL bottom.
- **Case:** `x: {a: {b: 1}}` + `x: {a: {b: x.a.b & 2}}`. `x.a.b` truncates to top, so
  `b = 1 & (top & 2) = 1 & 2` — conflicting values.
- **cue:** v0.16.1 ⇒ `x.a.b: conflicting values 2 and 1`. Status: FIXED (enforced).
