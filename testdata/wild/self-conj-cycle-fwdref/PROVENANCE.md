# self-conj-cycle-fwdref

- **Source:** SELF-CONJ-CYCLE-INDIRECT (2026-07-12 fix-slice; generalization caught while
  pinning the root).
- **Defect:** `x: 1` + `x: 1` (duplicate) + `y: 5` + `z: y` yielded `_|_` — a PLAIN sibling
  reference `z: y`, not a conjunction, dangled because the collapsed duplicate `x` shifted
  `y`/`z` down one index each while `z`'s `y` reference kept its raw index.
- **Significance:** proves the defect is the resolve/eval index-layout mismatch, NOT
  confined to merged `.conj` bodies — ruling out a conj-only rebase as the fix.
- **cue:** v0.16.1 ⇒ `{"x": 1, "y": 5, "z": 5}`. Status: GREEN (fixed).
