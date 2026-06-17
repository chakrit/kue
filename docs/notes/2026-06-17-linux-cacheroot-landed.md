# Breadcrumb: Linux `cacheRoot` default — per-OS user cache (2026-06-17)

## What landed (plan item 4)

The B3c extract-cache root fell back to the macOS `~/Library/Caches/cue` on every OS absent
`$CUE_CACHE_DIR`/`$XDG_CACHE_HOME`, so a Linux dev/CI with neither set silently missed the
cache and cross-module imports failed to resolve. Now matches Go `os.UserCacheDir` (what
`cue` uses). Commit on `gh:main`.

- **`Module.lean`** — new pure `cacheDirFor (cueCacheDir xdgCacheHome home : Option String)
  (isOSX : Bool) : System.FilePath`: `CUE_CACHE_DIR` verbatim → `XDG_CACHE_HOME/cue` →
  per-OS fallback (macOS `~/Library/Caches/cue`, other Unix `~/.cache/cue`). `cacheRoot` is
  now a thin IO wrapper reading the three env vars + `System.Platform.isOSX`.
- OS detected via `System.Platform.isOSX` (compile-time extern `Bool`). It is opaque (won't
  reduce under `native_decide`), so the per-OS branch lives in the pure helper that takes
  `isOSX` as an explicit arg — theorems pass `true`/`false`.
- The two env-var branches were already cross-OS-correct; precedence unchanged.

## Verify gate (all green)

- `lake build` → 86 jobs, success.
- `scripts/check-fixtures.sh` → `fixture pairs ok` (module fixtures override `CUE_CACHE_DIR`,
  unaffected).
- `shellcheck scripts/check-fixtures.sh` → clean.
- 5 `native_decide` theorems in `Tests/ModuleTests.lean` pin: CUE_CACHE_DIR wins, XDG wins
  over fallback, macOS fallback, Linux fallback, missing-HOME → `/.cache/cue` (no crash).

## Next step

**AUDIT DUE FIRST.** This is the 3rd slice since the last `/ace-audit` (tests-reorg, base64,
cacheRoot — all small/mechanical). Spawn a **two-phase, light** audit over those three
before the next feature slice; fold findings into the plan as fix-slices.

Then the higher-value real-file-reach work:

1. **Package-dir merge (item 5)** — `kue export ./apps` merges all `package apps` files in a
   dir before manifesting (multi-file packages like `argocd.cue`). Needs a design pass;
   bigger than the cleanups. **Prefer this** over the low-value churn below.
2. **`Field`→structure (3e)** — named `structure { label, fieldClass, value }`, ~95-site
   churn. Low value, defer.
3. Largest loader slice: **registry/module fetch (item 6)**.

## Standing facts (carry forward)

- Alpha cadence: ~1 datestamped alpha/day via `scripts/release.sh`, **NO CI**. Latest
  `v0.1.0-alpha.20260617.3`. Do NOT touch `scripts/release.sh`, `packaging/`, or the tap.
- External repos (go mod cache, prod9 apps) are **read-only** oracles.
