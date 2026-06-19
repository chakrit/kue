# F-2 landed — strip the self-module `@vN` major-version suffix in `readModuleInfo`

Supersedes `2026-06-19-sc1d-pattern-tail-stays-open-landed.md` as the live pointer. The 2nd
spec-first fix-slice since audit #10, and the last of the contained-HIGH one-file fixes the
re-ranked backlog front-loaded before the large rewrites. See
`docs/spec/spec-conformance-audit.md` (F-2 DONE).

## What landed

`readModuleInfo` (`Module.lean`) read the `module:` field VERBATIM, so a module declared
`module: "ex.com/m@v0"` got `ModuleContext.modPath = "ex.com/m@v0"`. An in-module import of the
BARE path `"ex.com/m/sub"` then prefix-matched against `"ex.com/m@v0/"` in
`resolveImportSubpath`/`importUnderModule` → NO match → "unresolved import". The `@major` strip
ALREADY applied to dependency KEYS (`depKeyModulePath` in `parseDeps`) but NOT to the importing
module's OWN path — that asymmetry was the bug. CUE modules contract: the `@vN` in `module:` is the
major version, not part of the addressable import path; imports name the BARE module path.

**Fix (DRY)** (`Module.lean` `readModuleInfo`, one line): reuse the existing `depKeyModulePath` on
the `module:` field —

    | some path => pure (.ok (depKeyModulePath path, parseDeps value))

No duplicated logic. Both `readModuleInfo` callers flow through it — `loadFileBound`/`loadPackageDir`
(self context) and `resolveImportTarget` (the cross-module dep-context hop) — so every `modPath`
consumer sees the bare path. `depKeyModulePath` is the identity on a no-`@` key, so the no-suffix
case is unchanged; the dep-strip path (`parseDeps`) is untouched.

## Behavior (cue v0.16.1 agrees)

- `module: "ex.com/m@v0"` + `import "ex.com/m/defs"` → resolves + exports the merged value (was
  "unresolved import"). **The fix.**
- `module: "ex.com/m"` (no suffix) + `import "ex.com/m/sub"` → resolves as before. **No regression.**
- A dependency (cross-module) import still resolves via the unchanged dep-key strip. **Dep path
  untouched.**

## Tests

4 `native_decide` pins in `ModuleTests` on the composition the bug lived in: verbatim
`resolveImportSubpath "ex.com/m@v0" "ex.com/m/sub" = none` (bug); stripped
`resolveImportSubpath (depKeyModulePath "ex.com/m@v0") "ex.com/m/sub" = some "sub"` (fix); stripped
module-root `= some ""`; no-suffix regression guard `… (depKeyModulePath "ex.com/m") … = some "sub"`.
Plus module fixture `modules/self_major_version_strip` (`module: "ex.com/m@v0"`, multi-file package,
root `main.cue` does `import "ex.com/m/defs"` + meets `defs.#Widget`) — end-to-end loader, diffed
byte-for-byte vs `cue export --out json` (oracle `expected`). `export_subdir` (no-suffix self) +
`crossmod*` (dep) are the no-regression guards on the unchanged paths.

## Verify

`lake build` green (96 jobs); `scripts/check-fixtures.sh` → `fixture pairs ok`; `shellcheck` clean.
**Real-app probe (READ-ONLY):** swept every `cue.mod/module.cue` under `prod9/` + `hatari/` — NO
self-module declares an `@vN` suffix today (all bare paths). So F-2 changes NO current real-app
resolution; it is the forward-looking fix for CUE's `@vN`-in-`module:` major-version form and can
ONLY help (a future `@vN` module's in-module imports resolve instead of erroring), never regress —
the no-suffix case is the `depKeyModulePath` identity. No in-repo cert-manager/argocd module fixture
and neither app uses `@vN`, so no `@vN` byte-identity surface to re-probe; the no-suffix self + dep
fixtures stayed green.

## Next step

**TWO-PHASE AUDIT DUE.** SC-1d + F-2 are the 2 spec-first fixes landed since audit #10 (2–3-slice
cadence reached). Before more feature/fix slices, run the two-phase audit per
`docs/guides/slice-loop.md` — do NOT invoke `/ace-audit`; the procedure is written down there. Run
SEQUENTIALLY: (A) code-quality audit (correctness, totality, illegal-states, DRY, test strength,
skill compliance over the SC-1/SC-1c/SC-1d/D#1a/F-1/F-2 batch), then (B) architecture/refactor/
cleanup audit (module boundaries, layering, dead code, test/fixture organization over the whole
module graph). Fold findings into the plan as fix-slices.

After the audit, resume the backlog (contained-HIGH exhausted; now the large/structural tail):

1. **RX-1 (HIGH, LARGE — 3 slices, worktree)** — replace the regex engine with an RE2-equivalent
   AST→NFA→Pike-VM. Highest real-app-correctness lever; design ready in the audit doc
   ("RX-1 design (implementable)"). RX-1a (AST+parser) → RX-1b (NFA+VM+rewire) → RX-1c
   (submatch+`ReplaceAll`).
2. **Bug2-3 / Gap-2b (HIGH)** — argocd disjunction under-pruning; the last argocd export blocker.
   Key on `.embeddedList`/list-meet-to-bottom, NOT a shape heuristic. Sequence with RX-1 by whichever
   worktree is freer.
3. **D#2** structural-cycle detection (large), then **SC-2** (closing-vs-instantiation, DIVERGE from
   cue, verify no regress), then the MED tail.

## Standing rules

- prod9 + cue caches READ-ONLY (eval/probe only). NO `git checkout`/`restore`/`reset --hard`.
  No env mutation outside the project tree.
- Audit cadence: SC-1d (1st) + F-2 (2nd) since audit #10 → **two-phase audit DUE now**
  (`docs/guides/slice-loop.md`).
