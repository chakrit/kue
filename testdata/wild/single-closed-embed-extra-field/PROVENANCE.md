# single-closed-embed-extra-field  (root A family — QUARANTINED, .known-red)

- **Source:** logged 2026-06-29 in `.afk.log` as `root3` while isolating the root of the L4
  `disj-arm-list-embed-dropped` regression (found probing outside the planned slice, never
  fixtured at the time). Captured 2026-07-02 as part of hardening the wild gate. Still RED
  at capture: kue reports "incomplete value: int".
- **CUE construct at fault:** a single closed definition EMBEDDED in a plain struct —
  no disjunction at all (`#A: {p: int}`, `M: {#A}`, `out: M & {p: 1, r: 9}`).
- **Direction: WRONG-BOTTOM / MISDIAGNOSIS** — both reject, but for different reasons:
  cue/spec bottom because embedding a definition closes the host, so the undeclared `r`
  is a "field not allowed"; kue instead reports "incomplete value: int" (it appears to
  drop or mishandle the embedded def's fields/closedness rather than close the host and
  reject `r`). The embed-close path is mishandled even without any disjunction, isolating
  it from the distribution bug in `def-disj-closedness-extra-field`.
- **Root cause (kue WRONG):** the embed-close path adjacent to `Kue/Lattice.lean` ~1224
  does not carry the embedded definition's closedness (or its concrete meet result) into
  the host struct's meet — pinned during the 2026-06-29 root-A isolation (`.afk.log`).
- **Spec basis:** embedding a definition in a struct literal closes the resulting struct
  (CUE closedness); a closed struct rejects undeclared fields → `r` not allowed → bottom.
  `cue` v0.16.1 → "out.r: field not allowed" (exit 1) and is correct (NOT a cue bug). The
  pinned `.expected.err` substring is kue's stable bottom rendering
  ("conflicting values (bottom)").
