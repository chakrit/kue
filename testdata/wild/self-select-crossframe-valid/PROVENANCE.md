# self-select-crossframe-valid

- **Source:** SELF-SELECT-CYCLE-CROSSFRAME (2026-07-12) — over-SUPPRESSION guard (the dangerous
  direction): a valid cross-struct select must not be mistaken for a self-cycle.
- **Case:** `x: {a: 1}` + `y: {b: x.a}`. `x`'s frame is NOT the live enclosing one when `y.b`
  is evaluated, so the fix (which keys on frame IDENTITY) leaves the ordinary force-then-select
  path in charge and `y.b` resolves to `1`.
- **cue:** v0.16.1 ⇒ `{"x": {"a": 1}, "y": {"b": 1}}`. Status: FIXED (enforced).
