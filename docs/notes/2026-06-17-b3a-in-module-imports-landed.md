# Session 2026-06-17 — B3a in-module imports landed

**SUPERSEDED by
[`2026-06-17-b3c-cross-module-imports-landed.md`](2026-06-17-b3c-cross-module-imports-landed.md)**
— B3c landed cross-module resolution and `defs.#X` now resolves against the real cue
cache; the next blockers are parser gaps (`let`, `[...]`), not imports. This note is
retained for the B3a detail.

Supersedes
[`2026-06-17-b5-manifest-output-landed.md`](2026-06-17-b5-manifest-output-landed.md).

## What was done

Landed **B3a — minimal in-module import resolution, end-to-end**: the first increment of
B3, the roadmap's last subsystem. Full record in
[`../reference/implementation-log.md`](../reference/implementation-log.md) ⇒ "Completed
Slice: B3a". Design plan:
[`2026-06-17-b3-import-resolution-plan.md`](2026-06-17-b3-import-resolution-plan.md).
Summary:

- **AST:** `structure Import {path, alias?}` + `structure ParsedFile {value, packageName,
  imports}` in `Kue/Value.lean`.
- **Parser:** `parseImportClauses`/`parseGroupedImports`/`parseImportSpec` collect imports
  (the twin of the discard-only `consumeImportClauses`); `parseSourceFile` threads them
  into a `ParsedFile`. Body parse unchanged; `parseSource` untouched (stdin/multi-file
  still discard).
- **`Kue/Module.lean` (new):** pure `resolveImportSubpath` (in-module hit / module-root
  `""` / cross-module `none`), `loadPackageFromParsed` (name-consistency +
  `mergeSourceValues`), `bindImports` (each package → a **hidden** top-level field),
  `importBindName` (alias › declared name › last path element), `isBuiltinImport`. IO
  boundary: `findModuleRoot`, `readModulePath`, `listPackageFiles`, recursive
  `loadPackage`/`collectBindings` (visited-set cycle guard), entry `loadFileBound`.
  `Eval`/`Resolve` stay pure; the loader produces a fully-bound `Value`.
- **CLI:** `Kue.exportValue` factored out; `Main` routes single file-mode + `export`
  file-mode through `loadFileBound`. **No-flag stdin and multi-file CLI unchanged** — no
  fixture regression.
- **Keystone:** `defs.#Widget` resolves through the **existing** `.selector (.refId …)`
  path because the package is bound as a top-level field — no new selector/eval machinery.
- **Builtin non-regression:** `strings`/`list`/`math`/`encoding/{base64,json,yaml}` import
  paths are skipped by the loader (`isBuiltinImport`); the call-form dotted dispatch is
  untouched. A file with only builtin imports needs no `cue.mod`.
- **Tests:** 11 `Kue/ModuleTests.lean` `native_decide`/unit theorems (disk-free, in-memory
  file lists). 7 `testdata/modules/<name>/` fixtures via additive `check_module_fixtures()`
  in `check-fixtures.sh`: `local_defs`/`transitive`/`mixed_builtin` (byte-for-byte vs `cue
  export`); `cycle`/`crossmod`/`missingpkg`/`conflictpkg` (`expected.err` substring).

**Milestone proof:** `kue export --out json` on the three success fixtures is byte-identical
to `cue export <dir>` (oracle: `cue` v0.16.1). Verify gate green (`lake build` exit 0,
`fixture pairs ok`, `shellcheck` clean).

### Oracle notes (`cue` v0.16.1)

- A definition `#Base & {tag: string}` where `tag ∉ #Base` is **field-not-allowed in cue**
  (closed-definition enforcement). The first transitive-fixture draft hit this; it is a
  **kue closedness gap, NOT a cue divergence** — so it was *not* logged in
  `cue-divergences.md`; the fixture was rewritten to be valid CUE (def-reference, no
  illegal field add). Watch closed-definition enforcement under import/unification when it
  surfaces in real prod9 files.
- Embedding reorders output fields (embedded def first, then locals); kue's embedding-merge
  order differs. Avoided in the fixture; an embedding-order question for a later slice.

## Next session — implementation focus: B3b, then B3c

- **B3b — aliased imports + nested paths + grouped-import robustness.** Alias is already
  retained and bound (basic case works via `importBindName`). Harden the import-clause
  parser: comments inside `import ( … )` groups, trailing commas, blank-line separators;
  nested-path corner cases. Add fixtures for the alias and grouped-with-comments forms.
- **B3c — cross-module / vendored (the real prod9 unlock).** Read `deps` in
  `cue.mod/module.cue`; locate the module via vendored `cue.mod/pkg/<modpath>@v…/` or the
  extract cache `~/Library/Caches/cue/mod/extract/<modpath>@<ver>/`. Single pinned version
  from `deps` (no solving). Makes real `infra/apps/*.cue` resolve `defs.#X`.
- **B3d — registry fetch + version resolution (LAST, deferred per chakrit).**

### Carry-forward boundaries (still owed)

- **prod9/infra roadmap:** the real goal is replacing `cue` for `prod9/infra` (and
  `infra-defs`, `infra-stage9`). B3c is the actual unblock for the manifest-producing
  files. External repos (prod9/infra etc.) are **read-only** reference.
- **Surfaced candidate gaps (after B3 or interleaved):**
  - **Hidden-field references do not resolve** (`y: _a` where `_a` hidden → bottom; `cue`
    resolves it) — pre-existing reference-resolution gap. (Note: B3a binds imports as
    hidden fields and they *do* resolve via selectors — the gap is bare hidden-field
    *references*, a distinct path.)
  - **Closed-definition enforcement** under import/unification (see Oracle notes).
  - **Open-list `[...]` expressions** — parser gap (also blocks a top-level list literal).
  - **Non-string label patterns `[string]: string`** — parser gap (blocks `secret.cue`).
- **PENDING AUDIT — parser+alias batch** (`0795530`/`7ec51a4`/`f6c18b5`/`804f1ca`): a full
  `/ace-audit` over the B1/B2 batch is still owed (3× transient-500 false starts before;
  the parser+alias+multiline family was later audited clean — see plan). Re-run when due;
  don't let it block forward slices. Per the loop cadence, a `/ace-audit` over B3a + recent
  work is due around the next family boundary.
- **Separators stay permissive**; **no `list.Sort`/`SortStable`**; non-ASCII case folding
  passes through; multiline bytes interpolation deferred (B4).

## Alpha status

v0.1.0 staged; cut locally via **`scripts/release.sh`** on chakrit's "cut a slice" command
(**NO GitHub Actions — banned**; there is no `.github` dir, do not create one; release
tooling owned elsewhere — do **not** touch `scripts/release.sh` / `packaging/`).
