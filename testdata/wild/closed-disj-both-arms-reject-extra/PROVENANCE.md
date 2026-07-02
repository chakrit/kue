# closed-disj-both-arms-reject-extra  (root A family — closedness × disjunction)

- **Source:** logged 2026-06-29 in `.afk.log` as `cl2` while isolating the root of the L4
  `disj-arm-list-embed-dropped` regression (a bug found probing outside the planned slice,
  never fixtured at the time). Captured 2026-07-02 as part of hardening the wild gate. At
  logging time kue reported "ambiguous"; by capture time kue already bottoms (fixed en
  passant by the root-A closedness work), so this landed as an ENFORCED fixture, not
  quarantined — it pins the fix.
- **CUE construct at fault:** a disjunction of two `close()`d structs met with a field
  declared in neither arm (`(close({p: int}) | close({q: int})) & {p: 1, r: 9}`).
- **Direction (historical): SOUNDNESS / OVER-ACCEPT** — kue kept both arms alive
  ("ambiguous") where cue/spec reject: `close({p: int})` rejects `r`, `close({q: int})`
  rejects `p` and `r`, so every arm bottoms and the empty disjunction is bottom.
- **Root cause (kue, historical):** `close()` closedness was not carried into the per-arm
  meets under disjunction distribution (`Kue/Lattice.lean` ~1224 family) — a closed arm
  inside a residual disjunction admitted a field the same arm met directly rejects.
- **Spec basis:** closed structs reject undeclared fields; unification distributes over
  disjunction, so the meet applies per arm; a disjunction whose arms are all bottom is
  bottom. `cue` v0.16.1 → "2 errors in empty disjunction: … field not allowed" (exit 1)
  and is correct (NOT a cue bug). The pinned `.expected.err` substring is kue's stable
  bottom rendering ("conflicting values (bottom)"); the spec-adjudicated observable is
  the non-zero, bottom outcome, not cue's exact wording.
