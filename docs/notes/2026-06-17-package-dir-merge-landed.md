# Breadcrumb — package-dir merge at the entry landed (plan item 5)

## What landed

Multi-file-package apps now evaluate/export. `kue eval ./apps` / `kue export ./apps`
(and `-e <app> ./apps`) load the *directory* as a package and meet-merge all same-package
sibling `*.cue` before eval/export/select.

**Scope: contained-reuse, NOT a redesign.** The gap was purely the IO entry —
`loadFileBound` loaded one file with no sibling merge, while `loadPackage` already did the
full same-package merge for *imported* packages. Fix:

- `Kue/Module.lean`: `loadPackageDir` (discover module root+deps, then `loadPackage ctx []
  dir` — no duplicated merge logic) + `loadEntry` (branch on `FilePath.isDir`: dir ⇒
  `loadPackageDir`, file ⇒ `loadFileBound` unchanged).
- `Main.lean`: `runEvalFile` + `runExport` file branch route through `loadEntry`.
- No `Cli` change — the existing file-arg positional already accepts a directory.

## Oracle (cue v0.16.1) — the file-vs-dir contract

- **dir arg** `./apps` ⇒ merges same-package siblings (resolves cross-file refs).
- **bare file arg** `apps/argocd.cue` ⇒ does NOT merge; errors on a sibling-defined ref.
  **The directory is the package unit, not the file.** This is why the single-file/stdin
  entry stays byte-unchanged — a lone unique-package file merges only itself.
- `-e <app> ./apps` ⇒ merge then select.
- mixed named packages in a dir ⇒ cue errors `found packages "a" and "b"`; kue rejects via
  the conflicting-package-name fold (different message, both reject).

## Tests

`testdata/modules/package_dir/` — a `subpaths` fixture whose subpath is the `apps`
directory (common.cue defines `common`; portal.cue defines `portal` referencing `common` —
the real-world distinct-top-level-fields shape). `expected.apps` = oracle `cue export
--out json ./apps`, byte-matched. All existing single-file fixtures unchanged.

## Divergence (pre-existing, NOT this slice)

cue field-interleaves `x: ref & {own}` with the *own* fields first; kue's `meet` orders the
left struct first. Single-file `meet`-ordering issue, independent of package merge. Fixture
sidesteps it (distinct top-level fields per file). If pursued later: a `meet`/output-order
slice, not a loader slice.

## Real prod9 result + NEXT BLOCKER

`kue export -e portal <hatari infra/apps>` (read-only) now descends the whole package and
reaches import resolution — was previously stuck single-file. It surfaces the clean B3d
deferral: `unresolved import: prodigy9.co/defs/packs: not in-module and matches no
dependency in cue.mod/module.cue`. That module's `cue.mod/module.cue` has **no `deps`
block**, so the dep-table match finds nothing.

**Next blocker = item 6 (registry/module-cache import fetch, old B3d):** resolve
`prodigy9.co/defs/packs`-style imports when there's no explicit `deps` entry (cue
auto-resolves from the cache/registry). Largest remaining loader slice; required for any
real app importing prod9 defs.

## Audit cadence

**This is the 2nd slice since the last light audit (field-structure was 1st).** Per the
loop's ~3–4 cadence, **audit is due next** — orchestrator should spawn `/ace-audit` over
the recently landed work (field-structure consolidation + this package-dir merge) before
the next substantive slice.

## Standing facts (carry forward)

- Alpha cadence: ~1 datestamped alpha/day via `scripts/release.sh`, **NO CI**. Latest
  `v0.1.0-alpha.20260617.3`. Do NOT touch `scripts/release.sh`, `packaging/`, or the tap.
- External repos (go mod cache, prod9/hatari apps) are **read-only** oracles.
