# def-disj-closedness-extra-field  (root A family — QUARANTINED, .known-red)

- **Source:** logged 2026-06-29 in `.afk.log` as `root2` while isolating the root of the L4
  `disj-arm-list-embed-dropped` regression (found probing outside the planned slice, never
  fixtured at the time). Captured 2026-07-02 as part of hardening the wild gate. Still RED
  at capture: kue reports "ambiguous value: multiple non-default disjuncts remain".
- **CUE construct at fault:** a disjunction of two definition *references*
  (`M: #A | #B` with `#A: {p: int}`, `#B: {q: int}`) met with an extra field
  (`M & {p: 1, r: 9}`). Definition closedness must survive being referenced into a
  disjunction and applied per arm.
- **Direction: SOUNDNESS / OVER-ACCEPT** — kue keeps BOTH arms alive (ambiguous) where
  cue/spec reject: `#A` (closed) rejects `r`, `#B` (closed) rejects `p` and `r`, so every
  arm bottoms and the empty disjunction is bottom. kue's ambiguity means a closed arm
  inside the disjunction admitted a field the same arm met directly rejects
  (control `#A & {p: 1, r: 9}` bottoms correctly).
- **Root cause (kue WRONG):** the `.disj alternatives, value` distribution
  (`Kue/Lattice.lean` ~1224) does not carry the referenced definitions' closedness into
  the per-arm `meetWithFuel`. Sibling of the fixed `def-closedness-thru-embedded-disj`
  (that one embeds the disjunction inside a definition; this one disjoins definition
  references directly — the fix for the former did not cover it).
- **Spec basis:** a definition closes its value; closedness applies wherever the
  definition is referenced; unification distributes over disjunction per arm; an
  all-bottom disjunction is bottom. `cue` v0.16.1 → "2 errors in empty disjunction: …
  field not allowed" (exit 1) and is correct (NOT a cue bug). The pinned `.expected.err`
  substring is kue's stable bottom rendering ("conflicting values (bottom)").
