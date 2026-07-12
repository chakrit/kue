# self-conj-cycle-conflict

- **Source:** SELF-CONJ-CYCLE-INDIRECT (2026-07-12 fix-slice; over-truncation guard).
- **Purpose:** GUARD that the fix does not SWALLOW a genuine conflict. `x: 1` + `x: y` +
  `y: 2` is `x = 1 & 2` = `_|_`; the cycle-truncation must not convert this to a resolve.
- **cue:** v0.16.1 ⇒ `x: conflicting values 2 and 1`. Status: GREEN (bottoms correctly).
