# RESUME HERE — B6-A2 (let-binding closedness) + B6-T1 (closedness pins) DONE (2026-06-19)

Supersedes `2026-06-19-b2b-structcomp-openness-landed.md`. Standing grant in effect (autonomy /
Lean-into-Lean-4 / commit-push freely / specs as restore point). Full record:
`docs/reference/implementation-log.md` ("B6-A2 + B6-T1" entry); plan: `docs/spec/plan.md` (B6-A2 +
B6-T1 marked DONE; the "Post-B2 re-ranking #7" slice-1 entry marked DONE).

## What landed

Two commits, one slice (the cheapest real correctness + the most regression-prone class hardened):

- **`27ddb96` B6-A2 — close a nested `#Def` under a `let`-bound field (CORRECTNESS).** B6's spine
  recursion in `normalizeFieldWithFuel` (`Normalize.lean`) skipped BOTH hidden AND `let`-bound field
  values. `let` over-skipped: `letBinding` is its OWN `FieldClass` kind (NOT the import-binding A2
  trap), so a `let`-bound value can safely recurse the spine and close its nested `#Def`s. Fix:
  dropped `|| Field.fieldClass field == .letBinding` from the skip guard so `let` joins the
  regular/optional/required arm; the `isHidden` skip (import-binding guard) stays.
  - Oracle cue v0.16.1: `let x = {#I: {y:int}}; out: x.#I & {extra}` → rejects `extra`. Kue now
    bottoms it (was admitting).
  - No over-close: open def (`...`) under a `let`, and a plain struct under a `let`, both stay open
    (cue-exact, pinned).
  - **This is the `let` arm of A2-followup's future 4-way `FieldClass` split**
    (importBinding/hidden/let/regular) — A2-followup folds it in; no rework.
  - Pins: 2 fixtures (`let_nested_def_closes`, `let_nested_def_open`) + 3 `native_decide`.

- **`aef25ac` B6-T1 — closedness regression pins (TEST-STRENGTH).** B6 is the class that bottomed
  `#ListenerSet`/cert-manager in the past. Pinned the Phase-A over-close-hunt shapes (6 fixtures + 6
  `native_decide`, each oracle-checked vs cue v0.16.1): (1) depth-2 nesting closes; (2)
  plain-struct-under-regular stays open; (4a) def-meet rejects unallowed; (4b) comprehension-bearing
  admits sibling; (4c) embedding-bearing admits siblings; (5) instantiated `(#D & {}).r & {extra}`
  re-opens/admits (cue-matching, the deferred-sub-gap boundary). Shape 3 (open `#Def` via `...`) was
  already pinned. The DIRECT def-path `#D.r & {extra}` (cue rejects, Kue wrongly admits) is the
  documented deferred gap and is deliberately UNpinned.

**Gate met:** `lake build` green (96 jobs incl. all `native_decide`), `scripts/check-fixtures.sh` →
`fixture pairs ok` ZERO byte-drift on all existing fixtures (import-binding sentinels +
`def_open_tail_addfield` byte-identical; the fix only drifted the new Part-2 fixtures, which didn't
exist before), `shellcheck` clean. No perf change (Normalize already walked regular-field spines;
`let` just joins that arm — no `kue-performance.md` edit). No CUE divergence (both gaps Kue-wrong).
Pushed to `gh:main`.

## Next step

1. **A2-followup (CORRECTNESS, representation change; BUNDLES B6-A1, FOLDS IN B6-A2's `let` arm).**
   The `importBinding` `FieldClass` marker (design is in `docs/spec/plan.md` — "A2-followup design
   (implementable)"). 1 slice / ~3 commits, LOW-MEDIUM risk. Adds `| importBinding` as a peer of
   `letBinding` (`Value.lean` `FieldClass`); `Module.bindImports` is the ONE producer
   (`FieldClass.hidden → FieldClass.importBinding` on the two `bindings.map` lines). Splits the
   3-way `normalizeFieldWithFuel` branch into 4 (`isDefinition` close / `importBinding` leave / the
   `let` arm B6-A2 just added / regular spine), and fixes the `Manifest.manifestFieldsWithFuel` deep
   reached-hidden bottom. Fixes the LAST two narrow correctness gaps (B6-A1 in-file-hidden nested-def
   closedness + the deep-hidden-bottom A2 gap) AND erases the `FieldClass.hidden` import-vs-in-file
   conflation from the type — a structural illegal-states win. B6-A2's edit just becomes the `let`
   arm of this split, confirmed not reworked. Full verify (cert-manager/argocd import sentinels MUST
   stay byte-identical).
2. **THEN PIVOT to item 7 — frame-id canonical identity (PERF wall, gates FULL real-app adoption).**
   Reclaims cert-manager (~92s) and unblocks the heavy `argo` sub-package (>200s). Audit-heavy and
   soundness-critical (independently-built frames must never falsely share); wants a clear runway,
   which A2-followup provides by clearing the last cheap correctness debt. Do NOT keep draining
   beyond A2-followup (the B6-deferred sub-gap + field-order #3 wait behind item 7 — diminishing
   real-app return).

**Audit cadence:** this is 1 slice since the last two-phase audit (#6, over the B6 + B2b batch,
`d1f537c`, which filed B6-A2/A1/T1). After A2-followup (slice 2), the two-phase audit is DUE again
(2 slices since #6). See `docs/guides/slice-loop.md` (run the procedure THERE, NOT `/ace-audit`).
