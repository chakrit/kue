# Session 2026-06-17 — B3c cross-module imports landed

Latest resume breadcrumb. Supersedes
[`2026-06-17-b3a-in-module-imports-landed.md`](2026-06-17-b3a-in-module-imports-landed.md).
**Import resolution is now functionally complete for prod9** — `defs.#X` resolves against
the real cue cache. The next session resumes on **parser gaps**, not imports.

## What was done

Landed **B3c — cross-module / vendored import resolution**, the real prod9 unlock. Full
record in [`../reference/implementation-log.md`](../reference/implementation-log.md) ⇒
"Completed Slice: B3c". Design plan:
[`2026-06-17-b3-import-resolution-plan.md`](2026-06-17-b3-import-resolution-plan.md).
Summary:

- **`deps` parsing:** `parseDeps` reads each `deps."<modpath>@<major>": {v}` entry into
  `Dep{modPath, version}` (`@major` stripped by `depKeyModulePath`); `readModuleInfo`
  returns `(modPath, deps)` from one parse.
- **Cross-module mapping:** `resolveCrossModule` picks the owning dep by **longest
  module-path prefix**, returns `(dep, subpath)`.
- **Keystone — a declared dep wins over the in-module interpretation.**
  `resolveImportTarget` checks deps *first*; only a path matching no dep falls to in-module.
  Without this, `prodigy9.co/defs` was mis-resolved to a nonexistent `infra/defs/` subdir.
- **On-disk location (read-only):** `cacheRoot` honors `$CUE_CACHE_DIR` →
  `$XDG_CACHE_HOME/cue` → `~/Library/Caches/cue`; `locateModuleDir` tries vendored
  `cue.mod/pkg/<modpath>[@ver]/` then extract cache `mod/extract/<modpath>@<ver>/`.
- **`ModuleContext` {root, modPath, deps}** threads through the loader; a cross-module hop
  reads the *target* module's context so its own transitive imports resolve. Visited-set
  cycle guard spans hops. **Reuses B3a `loadPackage` — no new eval machinery.** IO stays in
  `Module.lean`; `Eval`/`Resolve` pure.
- **Deferred errors:** `unknownModuleError` (no matching dep), `moduleNotOnDiskError` (dep
  declared but absent from vendor + cache).
- **Tests:** +8 `ModuleTests.lean` `native_decide` theorems (disk-free). +4
  `testdata/modules/` fixtures: `crossmod_cache` + `crossmod_transitive` (committed
  `_cache/`, byte-for-byte vs `cue export` under `CUE_CACHE_DIR`), `crossmod_vendor`
  (legacy `cue.mod/pkg/` layout, kue-only — cue v0.16 ignores it), `crossmod_missing`
  (error). `check_module_fixtures` now points `CUE_CACHE_DIR` at a fixture's `_cache/` when
  present — **self-contained, never the user's real cache**.

**Milestone proof:** the two cache fixtures' `expected` are byte-identical to `cue export`
(oracle v0.16.1) run from inside the fixture dir with `CUE_CACHE_DIR=$PWD/_cache`. Verify
gate green (`lake build` exit 0, `fixture pairs ok`, `shellcheck` clean).

## Real-file spot-check (READ-ONLY, prod9/infra)

`kue export` on the real `infra/apps/*.cue`: **`defs.#X` resolves** — kue descends into
`~/Library/Caches/cue/mod/extract/prodigy9.co/defs@v0.3.19/` and loads its files. **Import
resolution is no longer the blocker.** Surveyed all 15 `infra/apps/*.cue`; remaining
distance is **parser gaps**.

## Next session — RANKED blockers to replace cue for infra

1. **`let` declarations (`let x = expr` in a struct) — 10/15 app files. TOP BLOCKER.**
   Parser hits `let version = "0.20.0"` / `let nsp = …` and fails with
   `unexpected character '='`. This blocks the app files *before* imports even matter, so
   it gates the most files. Do this first.
2. **Open-list `[...]` expression — pervasive.** In nearly every app file and in the
   cross-module `defs/parts/allow_listener_sets.cue` load (the 3/15 that get past `let`
   reach it: `argocd`, `cert-manager`, `stage9`). Parser: `expected ']' after pattern
   label` on `& [...] &`.
3. **Then the deeper semantic gaps** (surface only after the parser gaps clear): closedness
   enforcement under import/unification (see B3a oracle notes), bare hidden-field references
   (`y: _a`), `[string]:` non-string label patterns.
4. **B3b syntax edges (import comments/trailing commas)** — still DEFERRED; real prod9
   grouped imports parse fine, so don't spend on this until a real file needs it.
5. **B3d — registry fetch + MVS + `cue.sum`** — DEFERRED per chakrit; B3c assumes the
   artifact is already on disk (true on any machine that ran `cue` once).

### Design boundary (carry forward)

kue reads the *intermediate* module's `deps` per transitive cross-module hop; `cue` requires
every transitive dep pinned **flat** in the main module (MVS). Both resolve on-disk
artifacts. Not a divergence (kue is more lenient, not more correct) — recorded in
compat-assumptions, not cue-divergences. The transitive fixture pins flat to stay
oracle-clean.

### Audit cadence

A `/ace-audit` over B3a + B3b + B3c is due around this family boundary (per the loop
cadence). The earlier parser+alias+multiline batch audited clean (see plan). Don't let the
audit stall the `let`/`[...]` parser work.

## Alpha status

v0.1.0 staged; cut locally via **`scripts/release.sh`** on chakrit's "cut a slice" command
(**NO GitHub Actions — banned**; no `.github` dir, do not create one; release tooling owned
elsewhere — do **not** touch `scripts/release.sh` / `packaging/`). External repos (prod9
tree + the cue cache) are **read-only** reference.
