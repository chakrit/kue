# single-closed-embed-extra-field  (root A family — GRADUATED 2026-07-03)

> **RETRACTION (2026-07-03, L5 slice 1).** The "Root cause (kue WRONG)" claim below is
> WRONG. The embed-close path is NOT mishandled: `{#A} & {p,r}` inline and `#M & {p,r}`
> (hidden def) both bottom CORRECTLY (cue: "field not allowed"), and the positive
> `{#A} & {p:1}` → `{p:1}` — verified against `cue` v0.16.1. It was already covered by the
> bug210 embed-close fixtures. The seed's original "incomplete value: int" was a
> MEASUREMENT artifact: `M` was a *regular exported* field = `{#A}` = `{p:int}`, whose own
> `int` is not concrete, so `M` errored at export BEFORE `out`'s correct bottom (`cue`
> reports `M.p: incomplete value int` identically). Corrected to a HIDDEN def (`#M`) so
> `out` is the observed result — now GREEN, `.known-red` removed, gate-enforced. No
> `Lattice.lean` change.


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
