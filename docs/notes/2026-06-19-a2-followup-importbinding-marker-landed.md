# RESUME HERE — A2-followup `FieldClass.importBinding` marker DONE (2026-06-19)

Supersedes `2026-06-19-b6-a2-let-closedness-and-t1-pins-landed.md`. Standing grant in effect
(autonomy / Lean-into-Lean-4 / commit-push freely / specs as restore point). Full record:
`docs/reference/implementation-log.md` ("A2-followup" entry); plan: `docs/spec/plan.md` (A2,
A2-followup, B6-A1 marked DONE; B6-A2 subsumed; the `FieldClass.hidden` conflation is ELIMINATED).

## What landed

One structural-correctness slice, 3 commits, that fixes BOTH A2-followup and B6-A1 by eliminating the
conflation between import-bound packages and real in-file hidden fields:

- **`78ec47a` (commit 1) — add `FieldClass.importBinding`, inert everywhere.** New peer constructor
  alongside `letBinding` (NOT a `.field` bool, NOT a `Value` wrapper — both rejected by audit #7).
  Folded TOTALLY into the 4 helpers (`isDefinition=false`, `isHidden=true`, `optionality=.regular`,
  `ignoresClosedness=true`, `producesOutput=false`) + the compiler-surfaced match sites
  `Lattice.mergeFieldClass` (merges only with itself) and `Format` (omitted from output) — so it
  reads IDENTICALLY to `.hidden` at every consumer. Produced at the ONE site `Module.bindImports`
  (`.hidden → .importBinding`); `Parse.lean` in-file hidden stays `.hidden`. BYTE-IDENTICAL (zero
  fixture drift — marker inert until the splits land); ModuleTests `bindImports` pin updated.

- **`7a54ad6` (commit 2) — the two consumer splits + fixtures.**
  - **Normalize** 3-way if-chain → 4-way `FieldClass` match: definition close / `importBinding` skip
    (import-laziness guard, now PRECISELY scoped) / in-file `_x` + `let` + regular recurse the spine.
    Fixes **B6-A1** (in-file hidden nested-def closes), subsumes B6-A2 (the `let` arm).
  - **Manifest** in-file hidden/def arm recurses the SELECTED value's output spine and lifts a DEEP
    `.error .contradiction` (**A2-followup**: `{#u: {x: _|_}}` surfaces); deep INCOMPLETE stays
    skipped (non-output, tolerated). `.importBinding` arm keeps the shallow `isBottom` (lazy).
  - Inverted the obsolete `link5_..._does_not_overfire` pin → `infile_hidden_nested_conflict_surfaces`
    (it asserted clean export for an IN-FILE literal deep conflict, but cue ERRORS — it conflated
    in-file with import). New oracle-checked fixtures: `b6a1_infile_hidden_def_closes`,
    `b6a1_infile_hidden_def_open`, + 4 manifest theorems.

- **commit 3 (this) — negative import sentinel + docs.** New module fixture
  `unreferenced_import_conflict` (a `dep` with `#Probe: {cmd:string}&{cmd:int}`, unreferenced by
  `main`; `main` exports clean — oracle cue v0.16.1, Kue matches). Pins that an import binding stays
  LAZY: the deep Manifest recurse NEVER runs on a bound package, so the cert-manager trap cannot
  recur. The marker makes output-reachability laziness LOCAL by construction.

**Gate met:** `lake build` green (96 jobs), `scripts/check-fixtures.sh` → `fixture pairs ok` with
ZERO byte-drift on existing fixtures (only NEW fixtures appear; import-binding sentinels +
`dup_import_binding` + `def_open_tail_addfield` + B6-T1 pins byte-identical), `shellcheck` clean (no
script changed). No perf change (deep recurse runs only on reached in-file hidden/def fields; import
bindings keep the shallow check — no `kue-performance.md` edit). No CUE divergence (both gaps
Kue-wrong, not cue-buggy). Pushed to `gh:main`.

**Structural win:** the import-binding-vs-in-file-hidden ambiguity is GONE from the type. The
closedness/hidden-field correctness cluster is now CLOSED except the B6-deferred sub-gap
(closing-vs-instantiation re-open — parked BEHIND the perf wall by the re-rank).

## Next step

1. **TWO-PHASE AUDIT DUE FIRST.** This is the 2nd slice since the last two-phase audit (#6, over the
   B6 + B2b batch, `d1f537c`): slice 1 was B6-A2+T1, slice 2 was this A2-followup. The cadence
   (every 2–3 slices) fires NOW. Run BOTH phases sequentially per `docs/guides/slice-loop.md` (the
   procedure is written THERE — do NOT invoke `/ace-audit`): (A) code-quality audit over the recent
   batch (the marker + the two splits — correctness, totality, illegal-states, test strength, skill
   compliance), then (B) architecture/refactor/cleanup over the whole module graph. Fold findings
   into the plan as fix-slices. Do not let the audit stall forward motion.

2. **THEN PIVOT to item 7 — frame-id canonical identity (PERF wall, gates FULL real-app adoption).**
   The single biggest lever left. Reclaims cert-manager (~92s) and unblocks the heavy `argo`
   sub-package (>200s timeout). Audit-heavy and SOUNDNESS-CRITICAL ("independently-built frames must
   never falsely share") → **design-spike FIRST**, like B2b/B6/A2-followup. The cheap correctness
   debt is now fully drained (this slice was the last of it), so item 7 has the clear runway the
   re-rank planned for. The B6-deferred sub-gap + field-order #3 wait BEHIND item 7 — diminishing
   real-app return, do not displace the perf wall for them.
