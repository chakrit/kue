# B3d-6b-leg4 LANDED — export-path MVS rewiring (2026-07-05)

Import resolution is now MVS-governed: cross-module version selection is max-of-mins across the
whole requirement graph, not the older per-hop-lenient pin. Final leg of B3d-6b's core.

## What landed

- `ModuleContext` gains `selected : List (String × String)` (bare path → MVS-selected version),
  defaulting to `[]` (pure per-hop). Threaded UNCHANGED through every cross-module hop.
- `buildDiskRequirementGraph` / `buildDiskGraphAux` — a fuel-bounded, visited-guarded, root-threaded
  BFS that builds the MVS requirement graph OFF DISK (locate via `locateModuleDir`, read via
  `readModuleInfo`; no network). Total (structural on fuel), no `partial`.
- `solveVersionOverride` — build the disk graph, run `Mvs.solveChecked`, project the build list to
  the override map (drop main). Graph unbuildable ⇒ EMPTY override (per-hop fallback). Main-path
  conflict ⇒ typed error (never a silent pin).
- `resolveImportTarget` overrides each cross-module import's version with `selectedVersion`.
- Wired at both entry points (`loadPackageDir`, `loadFileBound`).

## Canary safety (proof)

Single-version graph → override == per-hop version (no-op). Unbuildable graph → empty override →
today's per-hop behavior (no regression into a build error; no new eager all-deps enforcement). The
cert-manager realworld canary re-ran byte-identical.

## Tests

`testdata/modules/crossmod_diamond` (on-disk): `a`→c@v0.1.0, `b`→c@v0.2.0; MVS picks v0.2.0 for both.
RED-first proved (override neutralized): per-hop gave `fromA`=c-v0.1.0. Fix → v0.2.0 both. Expected
is spec-adjudicated (MVS) AND cross-checked byte-identical against a flat cue-conformant copy under
`cue export` v0.16.1 (no divergence). 7 `native_decide` tests in `ModuleTests.lean`
(diamond/single/3-deep/main-conflict/`selectedVersion`).

## Scope boundary (what stays)

Flat-requirement *enforcement* (cue requires every transitive dep pinned in main) is deliberately
NOT in scope — kue discovers deps transitively. That bounded leniency stays; leg4 closed only the
multi-version *selection* divergence (`compat-assumptions.md` updated: CLOSED).

## Next

`./scripts/check.sh` GREEN, committed on `main`, NOT pushed. Remaining B3d-6b dependent: **leg2**
(`mod get` + `.../tags/list` "latest" resolution — needs a CUE deps-block emitter; `parseMod` in
`Kue/Cli.lean:83` returns the clean deferral). Current broader front stays eval-conformance
(`plan.md` § Current front).
