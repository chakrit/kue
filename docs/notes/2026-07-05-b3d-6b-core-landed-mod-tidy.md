# Resume: B3d-6b core landed — `kue mod tidy` + MVS + cue.sum (2026-07-05)

**Where we are.** B3d-6b's substantive core LANDED in three commits on `main` (not pushed):

- `2a3afb8` `fix(mvs)` — `Mvs.solveChecked`: typed-error main-pin (discharges the main-pin rider).
- `04695c4` `feat(mod)` — `kue mod tidy`: transitive requirement-graph fetch (read-only GET) →
  MVS (`solveChecked`) → `cue.sum` WRITE. New `Kue/ModCmd.lean` (discharges the `ModuleFetch`
  carve rider). Offline gate `scripts/check-mod-tidy.lean` (diamond graph, max-of-mins →
  C@v1.3.0). Fixtures `testdata/ocifetch/modtidy/*.zip`.
- (this) `docs` — plan/compat/architecture/log reconciled to "core landed, two legs filed".

`./scripts/check.sh` GREEN. cert-manager canary unaffected (the export/import-resolution path was
NOT touched — that is leg4, below).

**What's next (the two FILED dependents — see `plan.md` § B3d track for full scope):**

1. **B3d-6b-leg4 — export-path MVS rewiring (MEDIUM, delicate, canary-risking; own attended
   slice).** Wire the MVS build list into `Module.lean`'s mutual loader so `kue export`/`eval`
   selects max-of-mins across the transitive graph, not the current lenient per-hop pin. Needs: a
   disk-first transitive graph builder (locate-or-fetch each dep, read module.cue — reuse
   `ModCmd.fetchGraph`'s shape but disk-first), `Mvs.solveChecked` → a version-override map
   threaded through `ModuleContext` (consulted in `resolveImportTarget` after `resolveCrossModule`
   — a NO-OP for single-version graphs, so the canary is provably unaffected), a NEW on-disk
   diamond-divergence fixture under `testdata/modules/` (per-hop picks the lower version, MVS the
   higher, oracle-matched export DIFFERS), and a cert-manager canary re-run. Kept separate so it
   is not rushed into an already-large slice.

2. **B3d-6b-leg2 — `mod get` + `.../tags/list` (MEDIUM; needs a CUE deps-block emitter).**
   `kue mod get <module>[@version]` mutates `cue.mod/module.cue` — needs emitting CUE for the deps
   block, a surface kue lacks. Fold in the OCI `.../tags/list` GET + `Semver.maxVersion`
   "latest"/major→concrete resolution (its only consumer). `parseMod` already reports get's
   deferral cleanly.

**Then** the loop returns to the eval-conformance / LOW-tail backlog (`plan.md` § Ranked OPEN
backlog: PRIM-FLOAT-PARSED, GDA-FLOAT-RENDER, BYTES-SLICE-MISSING/BYTE-INTERPOLATION, etc.).

**Live smoke (now allowed, read-only):** `registry.cue.works` reachable (`/v2/` → 200; real
`.../tags/list` JSON). Full manifest+blob fetch stays B3d-7-live-proven (ghcr). No gate depends on
the network — `check.sh` runs the whole pipeline OFFLINE against committed fixtures.
