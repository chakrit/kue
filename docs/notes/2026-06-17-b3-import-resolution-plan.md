# B3 — Module / Import Resolution: recon + sub-sliced plan

**Status:** design/implementation plan for the B3 subsystem (the roadmap's last, biggest
slice). Drives sub-slices B3a–B3d. From a read-only recon of the real prod9 modules +
kue's loader/resolver, 2026-06-17.

## Real prod9 layout (verified)

Modules use **CUE modules v0.15** schema (`module:` / `language.version: "v0.15.4"` /
`deps:`):

| Module dir | `module:` path | deps |
|---|---|---|
| `prod9/infra` | `prodigy9.co` | `prodigy9.co/defs@v0` → v0.3.19 |
| `prod9/infra-defs` | `prodigy9.co/defs` | none (`source: kind: git`) |
| `prod9/infra-stage9` | `stage9.dev` | `prodigy9.co/defs@v0` → v0.3.16 |

**Two resolution mechanisms:**
1. **In-module subdir** — import path `<module>/<subpath>` → `<moduleroot>/<subpath>`. Pure
   on-disk, **registry-free**. E.g. `infra/apps/keel.cue` imports `prodigy9.co/defaults` →
   `infra/defaults/` (3 files, `package defaults`). **← B3a target.**
2. **Cross-module via registry** — `prodigy9.co/defs*` is a *separate module*
   (`infra-defs`), fetched via `CUE_REGISTRY="prodigy9.co=ghcr.io/prod9"` into the cache
   `~/Library/Caches/cue/mod/extract/prodigy9.co/defs@v0.3.19/{packs,attr,parts,spec}/`.
   `infra/cue.mod/` vendors nothing. **← B3c/B3d.**

Import-path → dir (traced): `prodigy9.co/defaults`→`infra/defaults/` (3, `defaults`);
`prodigy9.co/defs`→`infra-defs/` root (32 files, `defs`); `/defs/packs`→`infra-defs/packs/`
(6, `packs`); `/defs/attr`→`attr/` (6); `/defs/parts`→`parts/` (11). **Multi-file merge is
central** — 32 `package defs` files merge into one namespace (`#Deployment`, `#Service`, …).

Reference forms in use: qualified selector no-call (`defs.#ServiceAccount`,
`packs.#WebApp`); aliased import (`planelib "prodigy9.co/apps/plane"` → `planelib.#X`);
grouped `import ( … )` blocks dominate; transitive (an in-module pkg imports a cross-module
one); no dot-imports.

## kue today (verified)

- **Loading (`Kue/Runtime.lean`):** `evalSourcesToString` checks package-name consistency,
  `parseSources`, then `mergeSourceValues = foldl meet`. **Imports never loaded from disk;
  no cue.mod awareness; no package-as-value.** But `mergeSourceValues` IS the multi-file
  merge primitive a package needs.
- **Parsing (`Kue/Parse.lean`):** `package` and `import` clauses are **consumed and
  discarded** (`consumePackageClauses`, `consumeImportClauses` ~line 1295). No import path/
  alias retained. First thing B3 must change.
- **Builtin dotted dispatch (collision surface):** `parseSelectorRest` turns `base.label(`
  (call-form, `base=.ref pkg`) into `.builtinCall "pkg.label"`; `evalBuiltinCall` routes six
  fixed prefixes (`strings.`/`list.`/`math.`/`base64.`/`json.`/`yaml.`). **No structural
  clash:** package symbols are *selectors on a bound name* (`defs.#Foo`, no call) → take the
  `.selector` path, never `evalBuiltinCall`. Only a user package literally named one of the
  six + call-form would collide (none in prod9; guard with a deferred error).
- **Scope/resolution (`Resolve.lean`+`Eval.lean`):** `.ref label`→`findInScopes` over
  `buildFrame` frames→`.refId {depth,index}`; `.selector (.refId id) label`→sibling or
  `selectEvaluatedField`. **Keystone:** bind an imported package as a struct value under its
  local name as a top-level field of the importing file → `defs.#X` resolves through the
  EXISTING path. No new selector/eval/resolution machinery.

## Architecture

**A loaded package = a struct value.** `loadPackage dir`: list `*.cue`, parse, check
package-name consistency, `meet`-merge top-level structs (reuse `mergeSourceValues`).
Definitions/fields become labels; `selectEvaluatedField` already selects `#`-labels.

**Resolution algorithm (B3a):**
1. cue.mod discovery: walk parents of the importing file's dir to `cue.mod/module.cue`;
   parse `module:` (e.g. `prodigy9.co`). Cache per-root.
2. path→dir: if import `P == module` or prefix `module + "/"`, strip prefix → subpath under
   module root (`""` → root dir). Non-matching prefix (cross-module) → deferred error.
3. local name: alias if present, else declared package name (= last path element here).
4. load+bind: `loadPackage dir` → struct; inject synthetic top-level field
   `localName: <struct>` into the importing file *before* `resolveStructRefs`.
5. transitivity: `loadPackage` resolves the loaded files' own (in-module) imports
   recursively, visited-set on dirs to break cycles.

Selector resolution + builtin non-collision: unchanged (fall out of existing paths). FS
lives behind an IO boundary; the resolve/eval core stays pure (loader produces a fully-bound
`Value`, then the pure pipeline runs).

## Sub-slices (ordered, each shippable)

- **B3a — minimal local in-module import, end-to-end (FIRST).** cue.mod discovery; resolve
  one in-module import → dir; multi-file merge; bind by declared name; transitive in-module
  loads; synthetic top-level binding. Defer aliases, cross-module, vendoring, dot-imports.
  Ships against a self-contained 2-file fixture (real prod9 in-module chains often reach a
  cross-module import, needing B3c).
- **B3b — aliased imports + nested paths + grouped-import robustness.** Retain alias in AST;
  bind under alias; harden the import-clause parser (comments, trailing commas).
- **B3c — cross-module / vendored (the prod9 unlock).** Read `deps` in `cue.mod/module.cue`;
  locate module via vendored `cue.mod/pkg/<modpath>@v…/` or the extract cache
  `~/Library/Caches/cue/mod/extract/<modpath>@<ver>/`. Single pinned version from `deps`
  (no solving). Makes real `infra/apps/*.cue` resolve `defs.#X`.
- **B3d — registry fetch + version resolution (LAST, deferred per chakrit).** OCI fetch from
  `CUE_REGISTRY` (ghcr.io/prod9), MVS version selection, `cue.sum`. B3c assumes the artifact
  is already in cache/vendor (true on any machine that ran `cue` once).

## B3a detail

**Files:** `Kue/Parse.lean` (import-*collecting* parser → `List Import {path, alias?}`,
threaded into the parse result; keep package-name surfacing); `Kue/Value.lean` (`structure
Import` + a `ParsedFile` record carrying `imports`/`packageName`); **new `Kue/Module.lean`**
(`findModuleRoot`, parse `module:`, `resolveImportPath → Except _ (Option Dir)` where
`none`=deferred cross-module, `loadPackage` recursive+visited, `bindImports`);
`Kue/Runtime.lean` (IO loader entry doing discovery+load before the pure resolve/eval);
`Main.lean` (route file-mode + `export` file-mode through the loader).

**Algorithm:**
```
evalFileWithImports(path):
  root, modPath = findModuleRoot(dirOf path)
  mainAst       = parseFile(path)                 -- retains imports + pkgName
  bindings = [ (imp.alias ?? pkg.declaredName, pkg.value)
               | imp ← mainAst.imports
               , dir ← resolveImportPath(root, modPath, imp.path)   -- none ⇒ deferred err
               , pkg ← loadPackage(dir, visited={}) ]
  return resolveAndEval(injectTopLevel(bindings, mainAst.value))

loadPackage(dir, visited):
  if dir ∈ visited: error "import cycle"
  asts = listCueFiles(dir).map parseFile
  checkSourcePackageNames(asts)
  return { declaredName, value := mergeSourceValues (asts.map (bindImports·(visited∪{dir}))) }
```

**Test:** single-file stdin harness can't express a package dir → add a **multi-file fixture
mode**. `testdata/modules/local_defs/`: `cue.mod/module.cue` (`module: "example.com"`),
`defs/widget.cue` (`package defs`, `#Widget: {...}`), `main.cue` (`import "example.com/defs"`,
`out: defs.#Widget & {...}`). Oracle `cue export <dir>`; kue must match. Edge cases: missing
package, conflicting package names, def-vs-field selection, transitive import, import cycle
(error), unresolved cross-module path (deferred-error message). Lean-side `ModuleTests.lean`
pins `resolveImportPath` (in-module hit / root / cross-module miss→none) + `loadPackage`
merge order with in-memory file lists (no FS needed).

**Risks:** (1) fixture harness — `check-fixtures.sh` is single-file-stdin; add an additive
`check_module_fixtures()` iterating `testdata/modules/<name>/`, running kue in dir/file mode,
diffing `<name>.expected`; leave existing stages byte-identical. (2) keep IO out of
Eval/Resolve. (3) bind by *declared* package name (or alias), not dir name. (4) builtin-shadow
guard (deferred error).

## Oracle / test strategy

Oracle = `cue` v0.16.1 local (prod9 pins v0.15.4 via `cue.sh`; agree on module-resolution
semantics — log any divergence in `cue-divergences.md` with both versions). Extend
`check-fixtures.sh` with an additive module-fixture stage; reuse `cue fmt --check` over new
`.cue`. Existing single-file + export stages unchanged.
