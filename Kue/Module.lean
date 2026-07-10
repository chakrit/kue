import Kue.Parse
import Kue.Runtime
import Kue.Registry
import Kue.Semver
import Kue.Mvs
import Kue.OciFetch
import Kue.Zip
import Kue.Sha256

/-!
# Module / import resolution (B3a)

In-module import resolution, end-to-end. A loaded package is a struct value: list the
package directory's `*.cue`, parse each, check package-name consistency, and meet-merge
the top-level structs. The merged struct is bound as a synthetic top-level field on the
importing file under its declared name (or alias), so `pkg.#Symbol` resolves through the
existing selector path with no new evaluation machinery.

The pure resolution logic (`resolveImportSubpath`, `loadPackageFromParsed`, `bindImports`)
is total and disk-free — it operates on already-parsed file lists. All filesystem access
(`cue.mod` discovery, directory listing, file reads) lives behind the `IO` boundary in the
loader entry points, keeping `Eval`/`Resolve` and the merge core pure.
-/

namespace Kue

/-- Emitted when an import path matches no `deps` entry of the importing module — neither
    in-module nor any declared dependency. Fetching such a module would require the registry
    (B3d); here it is a clean deferral. -/
def unknownModuleError (path : String) : String :=
  s!"unresolved import: {path}: not in-module and matches no dependency in cue.mod/module.cue (registry fetch is B3d)"

/-- Emitted when a declared dependency's module is present in neither the importing
    module's vendor tree nor the local cue cache. B3c resolves an already-on-disk artifact;
    fetching it from the registry is B3d. -/
def moduleNotOnDiskError (path modPath version : String) : String :=
  s!"unresolved import {path}: module {modPath}@{version} not found in vendor or cue cache " ++
    "(run `cue mod tidy`/`cue export` once, or vendor it); registry fetch is B3d"

/-- Emitted for a stdlib import path kue recognizes structurally as a builtin package
    (dot-free first element) but does not yet implement. Distinguishes an unimplemented
    standard-library package from an external module: the latter carries a domain and is
    resolved from disk. Naming the package keeps the diagnostic actionable instead of the
    misleading `no cue.mod` disk-loader error. -/
def unimplementedBuiltinError (path : String) : String :=
  s!"unsupported builtin package \"{path}\": recognized as a CUE standard-library import " ++
    "but not yet implemented in kue"

/-- Resolve an import path to a subpath under the module root, purely from the module path.
    `importPath == modPath` ⇒ the module root (`""`); `importPath` under `modPath ++ "/"` ⇒
    the trailing subpath; anything else (a non-matching prefix) ⇒ `none`, signalling a
    cross-module import the caller must defer. -/
def resolveImportSubpath (modPath importPath : String) : Option String :=
  if importPath == modPath then
    some ""
  else
    let modPrefix := modPath ++ "/"
    if importPath.startsWith modPrefix then
      some (importPath.drop modPrefix.length).toString
    else
      none

/-- A resolved dependency: the module path (`prodigy9.co/defs`, the `@major` suffix
    stripped from the `deps` key) paired with the pinned full version (`v0.3.19`). -/
structure Dep where
  modPath : String
  version : String
deriving Repr, BEq, DecidableEq

/-- Drop the `@<major>` suffix CUE appends to a `deps` key, leaving the bare module path.
    `prodigy9.co/defs@v0` → `prodigy9.co/defs`; a key with no `@` is returned verbatim. -/
def depKeyModulePath (key : String) : String :=
  match (key.splitOn "@") with
  | first :: _ => first
  | [] => key

/-- Read the dependency table out of a parsed `cue.mod/module.cue` value: each `deps` entry
    `"<modpath>@<major>": { v: "<version>" }` becomes a `Dep`. Entries lacking a string `v`
    are skipped. Pure — operates on the already-parsed module-file value. -/
def parseDeps : Value -> List Dep
  | .struct fields _ _ _ _ =>
      match (fields.find? (fun f => f.label == "deps")).map (fun f => f.value) with
      | some (Value.struct entries _ _ _ _) =>
          entries.filterMap fun entry =>
            match versionOf entry.value with
            | some version => some { modPath := depKeyModulePath entry.label, version }
            | none => none
      | _ => []
  | _ => []
where
  versionOf : Value -> Option String
    | .struct fields _ _ _ _ =>
        (fields.find? (fun f => f.label == "v")).bind fun f =>
          match f.value with
          | .prim (.string version) => some version
          | _ => none
    | _ => none

/-- Whether `importPath` is `modPath` or lies under `modPath ++ "/"` — the same
    path-segment prefix test `resolveImportSubpath` applies, reused for dep matching. -/
def importUnderModule (modPath importPath : String) : Bool :=
  importPath == modPath || importPath.startsWith (modPath ++ "/")

/-- Find the dependency that owns `importPath`, by longest module-path prefix match (so a
    nested dep like `a.com/x/y` wins over `a.com/x` when both are declared). Returns the
    owning `Dep` paired with the module-relative subpath (`""` when the import names the
    module root). `none` when no dependency matches — an unknown, registry-only import. -/
def resolveCrossModule (deps : List Dep) (importPath : String) : Option (Dep × String) :=
  let owning := deps.filter (fun dep => importUnderModule dep.modPath importPath)
  match owning.foldl (fun best dep =>
    match best with
    | some b => if dep.modPath.length > b.modPath.length then some dep else best
    | none => some dep) none with
  | none => none
  | some dep =>
      let subpath := (resolveImportSubpath dep.modPath importPath).getD ""
      some (dep, subpath)

/-- Build a package struct from its already-parsed files: check package-name consistency,
    then meet-merge the file bodies via the shared multi-file merge primitive. Returns the
    declared package name (`none` when every file omits a package clause) paired with the
    merged value. Pure — the parsing and disk listing happened upstream.

    The file `value`s here are already REWRITTEN (each file's import references relabelled to its
    file-scoped labels by `parseAndBindFiles`) but not yet BOUND: `loadPackage` prepends the
    combined file-scoped binding set onto this merged body once, after the meet. File-scoped
    labels keep two files' same-named imports in distinct slots (no `meet`-to-bottom collision)
    while package FIELDS still merge and stay shared across files. -/
def loadPackageFromParsed (files : List ParsedFile) : Except ParseError (Option String × Value) := do
  let names := files.map (·.packageName)
  let declared ← foldPackageNames none names
  pure (declared, mergeSourceValues (files.map (·.value)))
where
  foldPackageNames (acc : Option String) : List (Option String) -> Except ParseError (Option String)
    | [] => pure acc
    | name :: rest => do
        let merged ← mergePackageNames acc name
        foldPackageNames merged rest

/-- Deduplicate `(name, packageValue)` import bindings by bind NAME, first occurrence winning.
    The same package imported across sibling files resolves to the same package; keeping one
    binding avoids the meet-collision a duplicate hidden label causes. Distinct names (e.g. the
    same path under two aliases, or two different packages) all survive. Order-preserving.
    `seen` accumulates names already emitted; recursion is structural on the binding list. -/
def dedupeBindingsWith (seen : List String) :
    List (String × Value) -> List (String × Value)
  | [] => []
  | b :: rest =>
      if seen.contains b.fst then
        dedupeBindingsWith seen rest
      else
        b :: dedupeBindingsWith (b.fst :: seen) rest

def dedupeBindings (bindings : List (String × Value)) : List (String × Value) :=
  dedupeBindingsWith [] bindings

/-- A NUL byte, used only as the separator inside a file-scoped import label. NUL cannot occur
    in a CUE bare identifier (nor, in practice, a field label), so a label built from it is
    uncollidable with any user-written name. -/
def importLabelSep : String := "".push (Char.ofNat 0)

/-- The synthetic, per-file import-binding label that makes each sibling file's imports occupy
    a DISTINCT slot in the merged package struct (`file_scoped_import_*`). Two files importing
    the same local name get different labels (different `fileIdx`), so their bindings never
    meet-collide; a file's reference to its own import is rewritten to this label
    (`rewriteFileImportRefs`) and resolves to that one slot — preserving import SHARING (one slot
    per file-import) while keeping imports file-scoped. NUL-separated ⇒ uncollidable with user
    identifiers. -/
def fileScopedImportLabel (fileIdx : Nat) (name : String) : String :=
  s!"{importLabelSep}imp{importLabelSep}{fileIdx}{importLabelSep}{name}"

/-- Inject each `(localName, packageValue)` binding as a synthetic top-level
    `importBinding` field of the importing file's struct, prepended ahead of the body so a
    later same-named body field would shadow it (none occur in practice). An import binding
    reads as hidden everywhere (in scope for `pkg.#Symbol` references, excluded from output)
    but is distinguished from a real in-file hidden field so the two output-reachability
    sites can keep an unreferenced bound package lazy. Non-struct top-level values are
    wrapped so the bindings still land in scope. -/
def bindImports (bindings : List (String × Value)) : Value -> Value
  | .struct fields openness tail patterns closedClauses =>
      -- Import bindings are `importBinding` (ignore closedness), so the clauses' field-label
      -- sets need not list them; carry `closedClauses` through unchanged.
      .struct (bindings.map (fun b => ⟨b.fst, FieldClass.importBinding, b.snd, false⟩) ++ fields) openness tail patterns closedClauses
  | value =>
      mkStruct (bindings.map (fun b => ⟨b.fst, FieldClass.importBinding, b.snd, false⟩) ++ [⟨"", FieldClass.regular, value, false⟩]) .defClosed none []

/-- The name a bare/qualified import EXPECTS its target package to declare: the explicit
    `:identifier` qualifier when present, else the last path element. `cue` requires the loaded
    package's own `package` clause to equal this (a bare `import ".../foo"` demands `package foo`;
    a qualified `import ".../math-utils:math"` demands `package math`). The alias is irrelevant
    here — it renames the binding locally, it does not change which package the location names. -/
def expectedPackageName (imp : Import) : String :=
  imp.packageName.getD (lastPathElement imp.path)

/-- `cue`'s load error when an import's target directory holds no file declaring the expected
    package name (`import ".../foo"` where the dir declares `package bar`): cue rejects it with
    `no files in package directory with package name "foo"` and demands the `:bar` qualifier. -/
def packageNameMismatchError (expected : String) : String :=
  s!"no files in package directory with package name \"{expected}\""

/-- The redeclaration error `cue` raises when a file's top-level field reuses the local name
    an import binds in the file scope (A2-y). The import declaration binds `bindName` in the
    file block; a bare-identifier top-level field of the same name is a second declaration of
    that identifier in the one block — `cue`: `<name> redeclared as imported package name`. -/
def importRedeclarationError (bindName : String) : String :=
  s!"{bindName} redeclared as imported package name"

/-- Reject an import whose bound local name collides with a top-level bare-identifier field
    of the importing file (A2-y). `fieldNames` are that file's `topLevelFieldNames` — quoted
    labels, definitions, hidden fields, and `let`s already excluded, so a present collision is
    a genuine file-block redeclaration. `none` when there is no collision (the common case:
    a normal import, an alias/qualifier that does not match a field, a different-named field).
    Pure — the loader threads the per-file name set in. -/
def checkImportRedeclaration (bindName : String) (fieldNames : List String) :
    Except String Unit :=
  if fieldNames.contains bindName then
    .error (importRedeclarationError bindName)
  else
    .ok ()

/-- Run the A2-y redeclaration check over a list of (builtin) imports against one file's
    `fieldNames`, in order — used on the builtin-only fast path where no package is loaded,
    so each bind name comes from `importBindName` (alias > qualifier > last-path-element).
    The first collision errors; `ok ()` when none collide. -/
def checkBuiltinImportRedeclarations :
    List Import -> List String -> Except String Unit
  | [], _ => .ok ()
  | imp :: rest, fieldNames => do
      checkImportRedeclaration (importBindName imp) fieldNames
      checkBuiltinImportRedeclarations rest fieldNames

/-! ## IO loader boundary -/

/-- Resolve a (possibly relative) input path against the working directory to an absolute
    path. A relative path is joined onto `cwd`; an already-absolute path is returned as-is.
    Pure — the `cwd` lookup is the IO caller's job. Module discovery starts from this
    absolute path's directory, so the parent-walk climbs the real ancestor chain rather
    than dead-ending at a relative segment whose `.parent` is `none`. -/
def absolutePath (cwd : System.FilePath) (path : System.FilePath) : System.FilePath :=
  if path.isAbsolute then path else cwd / path

/-- The directory to begin module discovery from, given `cwd` and the input path: the
    absolute file's parent (the file's own directory). -/
def discoveryStartDir (cwd : System.FilePath) (path : System.FilePath) : System.FilePath :=
  (absolutePath cwd path).parent.getD cwd

/-- Walk parent directories of `start` looking for `cue.mod/module.cue`; return the
    directory that contains `cue.mod` (the module root). `none` when no ancestor has one. -/
-- partial: recurses up an unbounded parent chain; terminates at the filesystem root
-- (the `parent == start` fixpoint), not on a structural measure Lean can see.
partial def findModuleRoot (start : System.FilePath) : IO (Option System.FilePath) := do
  let candidate := start / "cue.mod" / "module.cue"
  if ← candidate.pathExists then
    pure (some start)
  else
    match start.parent with
    | some parent =>
        if parent == start then pure none else findModuleRoot parent
    | none => pure none

/-- A module's identity for resolution: its on-disk root, declared module path, and the
    dependency table read from its `cue.mod/module.cue`. Cross-module resolution hops from
    one context to the target module's own context, so its transitive in-module and
    cross-module imports resolve against the right root and deps.

    `selected` is the MVS build-list version override (bare module path → selected version),
    computed once at load entry over the whole requirement graph and threaded UNCHANGED through
    every cross-module hop. When it pins a version for a path, that version governs the import's
    resolution instead of the intermediate module's own per-hop `deps` pin — so a diamond
    resolves to the max-of-mins version everywhere (B3d-6b-leg4), matching cue's MVS. Empty ⇒
    pure per-hop resolution (the fallback when the graph is not buildable off disk); a
    single-version graph selects each path's only version, so the override is then a no-op. -/
structure ModuleContext where
  root : System.FilePath
  modPath : String
  deps : List Dep
  selected : List (String × String) := []

/-- The MVS-selected version for `modPath`, if the build list pins one (`ctx.selected`); else
    `none`, leaving the per-hop `deps` version to stand. -/
def selectedVersion (selected : List (String × String)) (modPath : String) : Option String :=
  (selected.find? (fun s => s.fst == modPath)).map (·.snd)

/-- Read and parse `cue.mod/module.cue`, returning the `module:` path and the dependency
    table. The file is CUE, so reuse the parser and read the fields off the top-level
    struct. The `@<major>` suffix CUE appends to the `module:` declaration (e.g.
    `ex.com/m@v0`) is the major version, not part of the addressable module path, so it is
    stripped here via the same `depKeyModulePath` the dependency keys use — the returned
    `modPath` is the BARE path against which in-module imports (`ex.com/m/sub`) prefix-match. -/
def readModuleInfo (root : System.FilePath) : IO (Except String (String × List Dep)) := do
  let source ← IO.FS.readFile (root / "cue.mod" / "module.cue")
  match parseSource source with
  | .error error => pure (.error s!"cue.mod/module.cue: parse error: {error.message}")
  | .ok value =>
      match moduleFieldValue value with
      | some path => pure (.ok (depKeyModulePath path, parseDeps value))
      | none => pure (.error "cue.mod/module.cue: missing string `module:` field")
where
  moduleFieldValue : Value -> Option String
    | .struct fields _ _ _ _ =>
        (fields.find? (fun f => f.label == "module")).bind fun f =>
          match f.value with
          | .prim (.string path) => some path
          | _ => none
    | _ => none

/-- The CUE module cache root, from the resolved env vars and OS, mirroring Go's
    `os.UserCacheDir` (which `cue` uses): `CUE_CACHE_DIR` wins; else `XDG_CACHE_HOME/cue`;
    else the per-OS user cache — macOS `~/Library/Caches/cue`, other Unix `~/.cache/cue`.
    Pure so the precedence is `native_decide`-checkable; the IO wrapper only reads env+OS. -/
def cacheDirFor (cueCacheDir xdgCacheHome home : Option String) (isOSX : Bool) :
    System.FilePath :=
  match cueCacheDir with
  | some dir => System.FilePath.mk dir
  | none =>
      match xdgCacheHome with
      | some dir => System.FilePath.mk dir / "cue"
      | none =>
          let homeDir := System.FilePath.mk (home.getD "")
          if isOSX then homeDir / "Library" / "Caches" / "cue"
          else homeDir / ".cache" / "cue"

/-- The CUE module cache root: read the env vars and OS, then build the path purely via
    `cacheDirFor`. The extract tree lives under `<cacheRoot>/mod/extract/`. -/
def cacheRoot : IO System.FilePath := do
  let cueCacheDir ← IO.getEnv "CUE_CACHE_DIR"
  let xdgCacheHome ← IO.getEnv "XDG_CACHE_HOME"
  let home ← IO.getEnv "HOME"
  pure (cacheDirFor cueCacheDir xdgCacheHome home System.Platform.isOSX)

/-- Join a slash-separated module path onto a base directory, segment by segment. -/
def joinModulePath (base : System.FilePath) (modPath : String) : System.FilePath :=
  modPath.splitOn "/" |>.foldl (init := base) fun acc segment =>
    if segment.isEmpty then acc else acc / segment

/-- Locate a dependency module's root directory on disk, read-only, in priority order:
    a vendored copy under the importing module's `cue.mod/pkg/` (with the `@<ver>` suffix
    cue's newer layout uses, else the bare module-path layout), then the extract cache
    `<cacheRoot>/mod/extract/<modpath>@<ver>/`. `none` when none exists — a deferred,
    registry-only fetch (B3d). -/
def locateModuleDir (importerRoot : System.FilePath) (dep : Dep) : IO (Option System.FilePath) := do
  let pkgBase := importerRoot / "cue.mod" / "pkg"
  let vendoredVersioned := joinModulePath pkgBase s!"{dep.modPath}@{dep.version}"
  let vendoredBare := joinModulePath pkgBase dep.modPath
  -- B3d-5a: route the extract-cache path through `Registry.extractCachePath` — the SOLE
  -- cache-layout authority — so the read-path (here) and the write-path (`fetchAndCacheModule`)
  -- agree by construction, including the on-disk escaping of any upper-case module path.
  let cached := System.FilePath.mk (Registry.extractCachePath
    ((← cacheRoot) / "mod").toString (Registry.mkModuleVersion dep.modPath dep.version))
  let candidates := [vendoredVersioned, vendoredBare, cached]
  firstExisting candidates
where
  firstExisting : List System.FilePath -> IO (Option System.FilePath)
    | [] => pure none
    | dir :: rest => do
        if ← dir.pathExists then pure (some dir) else firstExisting rest

/-- List the `*.cue` files in a package directory, sorted for deterministic merge order. -/
def listPackageFiles (dir : System.FilePath) : IO (List System.FilePath) := do
  let entries ← dir.readDir
  let cueFiles := entries.toList.filterMap fun entry =>
    if entry.path.extension == some "cue" then some entry.path else none
  pure (cueFiles.toArray.qsort (fun a b => a.toString < b.toString)).toList

/-- The directory holding the package at module-relative `subpath` (`""` ⇒ the module
    root) — the same segment-join as `joinModulePath`, named for the subpath use. -/
def subpathDir (root : System.FilePath) (subpath : String) : System.FilePath :=
  joinModulePath root subpath

/-! ## Disk-first requirement graph + MVS selection (B3d-6b-leg4)

    Build the MVS requirement graph off DISK (no registry egress), run the checked solver, and
    turn its build list into a per-path version override the loader threads through
    `ModuleContext.selected`. This is the disk-side twin of `ModCmd.fetchGraph` (which BUILDS the
    same graph shape from registry GETs for `mod tidy`): the algorithms match but the inputs
    differ — this walk locates each node ON DISK via `locateModuleDir` (root-threaded per hop, so
    a vendored transitive dep resolves against its own root) and carries no `h1:` digest (only
    `cue.sum` writes need one). The shared BFS skeleton is `bfsRequirementGraphAux`; each walk
    supplies its own `nodeOf`/`expand` leaf callback (the per-node effect that yields child
    worklist items + this node's payload). -/

/-- A generous total-step bound for the disk requirement-graph walk; only a pathological or
    cyclic graph trips it (the visited set already terminates real cycles). -/
def diskGraphFuel : Nat := 100000

/-- Generic fuel-bounded, visited-guarded BFS building a requirement graph. Recurses structurally
    on `fuel` (⇒ total, no `partial`). `expand` is a LEAF callback that must NOT recurse — it
    yields this node's child worklist items and its accumulated payload; keeping the recursion out
    of the callback is what preserves structural-recursion inference. `nodeOf` projects the visited
    key from a worklist item; `fuelExhausted` is the caller's exhaustion message. Both the disk walk
    (`buildDiskGraphAux`) and the registry fetch (`ModCmd.fetchGraphAux`) are thin call sites. -/
def bfsRequirementGraphAux {α β : Type}
    (nodeOf : α → Registry.ModuleVersion)
    (expand : α → IO (Except String (List α × β)))
    (fuelExhausted : String) :
    Nat → List α → List Registry.ModuleVersion → List (Registry.ModuleVersion × β) →
    IO (Except String (List (Registry.ModuleVersion × β)))
  | 0, _, _, _ => pure (.error fuelExhausted)
  | _, [], _, acc => pure (.ok acc)
  | fuel + 1, item :: rest, visited, acc =>
    let node := nodeOf item
    if visited.contains node then
      bfsRequirementGraphAux nodeOf expand fuelExhausted fuel rest visited acc
    else do
      match ← expand item with
      | .error e => pure (.error e)
      | .ok (children, payload) =>
          bfsRequirementGraphAux nodeOf expand fuelExhausted fuel
            (children ++ rest) (node :: visited) (acc ++ [(node, payload)])

/-- Fuel-bounded, visited-guarded BFS building the MVS requirement graph off disk. Each worklist
    item pairs a `Dep` with the root of the module that REQUIRES it (its importer), so the node is
    located exactly as the loader would locate it (vendored-under-importer first, then the global
    cache). A node absent from disk is a typed error — the caller treats that as "graph not
    buildable" and falls back to per-hop resolution, so a declared-but-unvendored dep never turns
    a currently-resolving load into a hard failure. A thin `bfsRequirementGraphAux` call site. -/
def buildDiskGraphAux (fuel : Nat) (worklist : List (System.FilePath × Dep))
    (visited : List Registry.ModuleVersion) (acc : Mvs.RequirementGraph) :
    IO (Except String Mvs.RequirementGraph) :=
  bfsRequirementGraphAux
    (nodeOf := fun (_, dep) => ⟨dep.modPath, dep.version⟩)
    (expand := fun (importerRoot, dep) => do
      match ← locateModuleDir importerRoot dep with
      | none => pure (.error s!"module {dep.modPath}@{dep.version} not found on disk")
      | some moduleRoot =>
          match ← readModuleInfo moduleRoot with
          | .error e => pure (.error e)
          | .ok (_, deps) =>
              let children := deps.map (fun d => (moduleRoot, d))
              let edge := deps.map (fun d => (⟨d.modPath, d.version⟩ : Registry.ModuleVersion))
              pure (.ok (children, edge)))
    (fuelExhausted := "disk requirement-graph walk exceeded fuel (graph too large or cyclic)")
    fuel worklist visited acc

/-- Assemble the full disk requirement graph for a main module: seed the walk with the main
    module's declared deps (rooted at `mainRoot`), then include the main node itself (bare path,
    empty-version MVS sentinel) as a root edge. -/
def buildDiskRequirementGraph (mainRoot : System.FilePath) (mainMod : String)
    (mainDeps : List Dep) : IO (Except String Mvs.RequirementGraph) := do
  let mainNode : Registry.ModuleVersion := ⟨depKeyModulePath mainMod, ""⟩
  let seed := mainDeps.map (fun d => (mainRoot, d))
  match ← buildDiskGraphAux diskGraphFuel seed [mainNode] [] with
  | .error e => pure (.error e)
  | .ok depEdges =>
      let mainEdge := (mainNode, mainDeps.map (fun d => (⟨d.modPath, d.version⟩ : Registry.ModuleVersion)))
      pure (.ok (mainEdge :: depEdges))

/-- The MVS version override for a load: build the disk requirement graph, run `solveChecked`,
    and project the build list to `(bare-path, selected-version)` pairs (dropping the main node).
    A graph that will not build off disk ⇒ an EMPTY override (per-hop fallback — canary-safe: a
    single-version load is byte-identical either way, and a currently-resolving lenient load is
    never regressed into a build error). A main-path conflict (a dep requiring a higher version of
    the main module's own path — the case cue rejects) surfaces as a typed error via
    `solveChecked`, exactly as `mod tidy` does. -/
def solveVersionOverride (mainRoot : System.FilePath) (mainMod : String) (mainDeps : List Dep) :
    IO (Except String (List (String × String))) := do
  match ← buildDiskRequirementGraph mainRoot mainMod mainDeps with
  | .error _ => pure (.ok [])
  | .ok graph =>
      let mainNode : Registry.ModuleVersion := ⟨depKeyModulePath mainMod, ""⟩
      match Mvs.solveChecked mainNode graph with
      | .error e => pure (.error e)
      | .ok buildList =>
          pure (.ok (buildList.filterMap fun mv =>
            if mv.basePath == mainNode.basePath then none else some (mv.basePath, mv.version)))

/-! ## Registry fetch-on-missing (B3d-5, IO edge)

    When a declared dependency is absent from disk, fetch it from its OCI registry, verify it,
    write it into the cue cache in the layout the read-path already consumes, and let the
    existing `locateModuleDir` take over. The OCI protocol core is pure (`Registry`/`Oci`/
    `Sha256`/`Zip`); only the `curl` GET + the cache writes are IO, confined here. -/

/-- Read the importer module's `CUE_REGISTRY` (empty/unset ⇒ the Central Registry default,
    handled purely by `Registry.parseConfig`). The sole env read of the fetch path. -/
def readCueRegistry : IO String := do
  pure ((← IO.getEnv "CUE_REGISTRY").getD "")

/-- Parse `cue.sum` text into `(modpath@version, Hash1)` pairs. Format mirrors Go's `go.sum`:
    whitespace-separated `<module> <version> h1:<base64>` lines; blank/short lines are skipped.
    The hash field crosses into the typed `Hash1` here — the `cue.sum` read boundary. Pure — the IO
    wrapper `readCueSum` only supplies the file text. -/
def parseCueSumText (text : String) : List (String × Hash1) :=
  text.splitOn "\n" |>.filterMap fun line =>
    match line.trimAscii.toString.splitOn " " |>.filter (·.length > 0) with
    | modPath :: version :: hash :: _ => some (s!"{modPath}@{version}", Hash1.parse hash)
    | _ => none

/-- One `cue.sum` line: `<modpath> <version> <h1>` + `\n`. The inverse of one `parseCueSumText`
    line; `Hash1.render` is the write boundary back to the file token. -/
def formatCueSumLine (modPath version : String) (h1 : Hash1) : String :=
  s!"{modPath} {version} {h1.render}\n"

/-- Serialize resolved `(modpath, version, Hash1)` sums to `cue.sum` text — the inverse of
    `parseCueSumText`. Sorted by `(modpath, semver version)` for a deterministic file (mirroring
    Go's `module.Sort` over `go.sum`); one line per entry. Pure; `writeCueSum` supplies the IO. -/
def formatCueSum (entries : List (String × String × Hash1)) : String :=
  let sorted := entries.toArray.qsort (fun a b =>
    let (ma, va, _) := a
    let (mb, vb, _) := b
    if ma != mb then ma < mb else Semver.compare va vb < 0) |>.toList
  String.join (sorted.map (fun (m, v, h) => formatCueSumLine m v h))

/-- Parse an importer's `cue.sum` (when present) into `(modpath@version, h1-hash)` pairs.
    cue v0.16.1 ships NO `cue.sum` mechanism (the OCI blob digest is its live integrity gate —
    see `fetchAndCacheModule`), so this is a defensive, forward-compatible verifier: a sum present
    is enforced, an absent file is no error. -/
def readCueSum (importerRoot : System.FilePath) : IO (List (String × Hash1)) := do
  let path := importerRoot / "cue.sum"
  if !(← path.pathExists) then
    pure []
  else
    pure (parseCueSumText (← IO.FS.readFile path))

/-- The recorded `Hash1` for `dep` in a parsed `cue.sum`, if any (keyed `modpath@version`). -/
def lookupCueSum (sums : List (String × Hash1)) (dep : Dep) : Option Hash1 :=
  (sums.find? (fun s => s.fst == s!"{dep.modPath}@{dep.version}")).map (·.snd)

/-- A collision-resistant temp-name suffix for a single write attempt: monotonic-clock
    nanos paired with a random draw. The nanos give cross-process separation (two processes
    almost never start an attempt the same nanosecond), the `IO.rand` covers the residual and
    same-process same-nanos case. Total — both are ordinary `IO` reads, no `partial`. Used to
    name a sibling `.tmp-…` slot so a leftover from one attempt never collides with another. -/
def freshNonce : IO String := do
  let nanos ← IO.monoNanosNow
  let rand ← IO.rand 0 0xFFFFFF
  pure s!"{nanos}-{rand}"

/-- Atomic write of `bytes` to `path`: write to a sibling `<path>.tmp-<nonce>` under the same
    parent (⇒ same filesystem), then `IO.FS.rename` onto `path`. POSIX `rename(2)` is atomic,
    so `path` is only ever observed with its old contents or the full new contents — never a
    truncated partial from a crash mid-write. The parent dir is created first. Reusable
    primitive (B3d-6's `cue.sum`/lockfile writes will share it). -/
def atomicWriteBinFile (path : System.FilePath) (bytes : ByteArray) : IO Unit := do
  if let some parent := path.parent then
    IO.FS.createDirAll parent
  let nonce ← freshNonce
  let tmp := System.FilePath.mk s!"{path.toString}.tmp-{nonce}"
  IO.FS.writeBinFile tmp bytes
  IO.FS.rename tmp path

/-- Extract `entries` into the final directory slot `dest` atomically: unpack every entry into
    a sibling temp dir `<parent>/.tmp-<dest-name>-<nonce>/` (SAME parent ⇒ same filesystem),
    then `IO.FS.rename` that temp dir onto `dest`. POSIX directory `rename(2)` is atomic, so
    `dest` is only ever observed COMPLETE or ABSENT — a crash mid-extract leaves only an
    orphaned `.tmp-…` dir, which `locateModuleDir` never matches (it keys off the exact
    `<esc>@<ver>` slot name, and the `.tmp-` prefix excludes the temp dir from that name).
    Rename-over-existing race: if another process won and `dest` already exists when we go to
    rename, discard our temp work (`removeDirAll`) and keep the extant complete slot rather
    than risk a non-empty-target rename failure. Reusable primitive (B3d-6 reuses it). -/
def atomicExtractDir (dest : System.FilePath) (entries : List (String × ByteArray)) :
    IO Unit := do
  let parent := dest.parent.getD dest
  let destName := dest.fileName.getD "module"
  IO.FS.createDirAll parent
  let nonce ← freshNonce
  let tmp := parent / s!".tmp-{destName}-{nonce}"
  -- A fresh nonce makes a pre-existing temp of this exact name effectively impossible; clear
  -- one defensively so a (vanishingly unlikely) collision can't poison the extract.
  if ← tmp.pathExists then IO.FS.removeDirAll tmp
  IO.FS.createDirAll tmp
  for (name, contents) in entries do
    let entryPath := joinModulePath tmp name
    if let some entryParent := entryPath.parent then
      IO.FS.createDirAll entryParent
    IO.FS.writeBinFile entryPath contents
  -- Atomic publish. If a concurrent fetch already published the slot, drop our temp and use
  -- the extant complete copy (rename onto a non-empty dir would fail).
  if ← dest.pathExists then
    IO.FS.removeDirAll tmp
  else
    IO.FS.rename tmp dest

/-- Write the fetched module into the cue cache under the cache-layout authority
    (`Registry.{downloadCachePath,extractCachePath}`): the raw verified zip to
    `<root>/download/<esc-path>/@v/<esc-ver>.zip`, and the unpacked entries under
    `<root>/extract/<esc-path>@<esc-ver>/`. `root` is the `<cacheRoot>/mod` base both
    `Registry` cache-path builders expect (the dir holding `download/` and `extract/`).
    BOTH writes are atomic (temp-then-`rename`, via `atomicWriteBinFile`/`atomicExtractDir`):
    the extract slot is only ever observed complete-or-absent, so `locateModuleDir`'s bare
    `pathExists` is sound by construction; the `.zip` is whole-then-present for Go-modcache
    parity. A crash leaves only orphaned `.tmp-…` siblings, never a partial real slot.
    Returns the extract-root path. -/
def writeModuleToCache (root : System.FilePath) (mv : Registry.ModuleVersion)
    (zipBytes : ByteArray) (entries : List (String × ByteArray)) : IO System.FilePath := do
  let downloadPath := System.FilePath.mk (Registry.downloadCachePath root.toString mv "zip")
  atomicWriteBinFile downloadPath zipBytes
  let extractRoot := System.FilePath.mk (Registry.extractCachePath root.toString mv)
  atomicExtractDir extractRoot entries
  pure extractRoot

/-- Fetch a declared-but-missing dependency from its OCI registry, verify it, and install it
    into the cue cache so the read-path finds it. Steps: resolve `CUE_REGISTRY` + `dep` to an
    `OciRef` (a `none`/unset registry ⇒ a clear "cannot fetch" error); fetch the
    digest-verified module zip (`fetchZip`, injected so the offline test drives a `file://`
    source while production passes `OciFetch.fetchModuleZip`); unzip + CRC-verify the entries
    (`Zip.readZip`); verify the importer's `cue.sum` `h1:` when one is recorded (else proceed —
    cue v0.16.1 has no `cue.sum`, the OCI blob digest already gated the bytes); write the zip +
    entries into the cache. Returns the extract-root path. Total `IO (Except …)` — every failure
    is a typed error, never an exception. -/
def fetchAndCacheModule (cueRegistry : String) (importerRoot : System.FilePath) (dep : Dep)
    (fetchZip : Registry.OciRef → IO (Except String ByteArray)) :
    IO (Except String System.FilePath) := do
  let mv := Registry.mkModuleVersion dep.modPath dep.version
  match Registry.resolveFromConfig cueRegistry dep.modPath dep.version with
  | .error e =>
      pure (.error s!"cannot fetch {dep.modPath}@{dep.version}: invalid CUE_REGISTRY: {e}")
  | .noRegistry =>
      pure (.error
        s!"cannot fetch {dep.modPath}@{dep.version}: registry is `none` (no registry to fetch from)")
  | .found ref => do
      match ← fetchZip ref with
      | .error e => pure (.error s!"fetch {dep.modPath}@{dep.version} failed: {e}")
      | .ok zipBytes =>
          match Zip.readZip zipBytes with
          | .error e => pure (.error s!"unpacking {dep.modPath}@{dep.version} failed: {e}")
          | .ok entries =>
              let sums ← readCueSum importerRoot
              match lookupCueSum sums dep with
              | some recorded =>
                  let actual := Sha256.hash1 entries
                  if actual != recorded then
                    pure (.error <|
                      s!"cue.sum verification failed for {dep.modPath}@{dep.version}: " ++
                      s!"recorded {recorded}, computed {actual}")
                  else do
                    let extractRoot ← writeModuleToCache ((← cacheRoot) / "mod") mv zipBytes entries
                    pure (.ok extractRoot)
              | none => do
                  let extractRoot ← writeModuleToCache ((← cacheRoot) / "mod") mv zipBytes entries
                  pure (.ok extractRoot)

/-- Resolve a single non-builtin import path, within module `ctx`, to the context and
    directory its package loads from.

    A declared dependency wins over the in-module interpretation: in real modules the
    module path is a prefix of its dependency paths (`prodigy9.co` owns `prodigy9.co/defs@v0`
    as a dep), so a path matching a `deps` entry is the *dependency* module — loaded from
    vendor or the cue cache under its own context — even though it also textually lies under
    `ctx.modPath`. Only a path matching no dependency is treated as in-module, a subdir of
    `ctx.root`. Anything matching neither is an unknown, registry-only import.

    No package loading happens here — that stays in the recursive loader. -/
def resolveImportTarget (ctx : ModuleContext) (importPath : String) :
    IO (Except String (ModuleContext × System.FilePath)) := do
  match resolveCrossModule ctx.deps importPath with
  | some (dep, subpath) =>
      -- MVS override: the build list may pin a HIGHER version for this path than the per-hop
      -- `deps` entry (a diamond where another requirer demanded more). When it does, that
      -- version governs; absent an override (single-version graph, or a non-buildable graph
      -- ⇒ empty override), the per-hop version stands.
      let dep := { dep with version := (selectedVersion ctx.selected dep.modPath).getD dep.version }
      match ← locateModuleDir ctx.root dep with
      | none =>
          -- Declared dep absent from vendor + cache: fetch it from the registry, install it,
          -- and retry the locate (B3d-5). Only error if the fetch/verify fails or, after a
          -- successful install, the module still can't be located (a malformed cache write).
          let cueRegistry ← readCueRegistry
          match ← fetchAndCacheModule cueRegistry ctx.root dep OciFetch.fetchModuleZip with
          | .error _ =>
              -- Keep the existing clean deferral phrasing as the user-facing error: the dep is
              -- not on disk and the fetch could not supply it.
              return .error (moduleNotOnDiskError importPath dep.modPath dep.version)
          | .ok _ =>
              match ← locateModuleDir ctx.root dep with
              | none => return .error (moduleNotOnDiskError importPath dep.modPath dep.version)
              | some moduleRoot => loadDepContext moduleRoot subpath
      | some moduleRoot => loadDepContext moduleRoot subpath
  | none =>
      match resolveImportSubpath ctx.modPath importPath with
      | some subpath => return .ok (ctx, subpathDir ctx.root subpath)
      | none => return .error (unknownModuleError importPath)
where
  /-- Build the dependency module's context from its located root (read its own
      `module:`/`deps`) and return it paired with the package subdirectory. The hop into the
      dep's own context lets its transitive imports resolve against the right root/deps. -/
  loadDepContext (moduleRoot : System.FilePath) (subpath : String) :
      IO (Except String (ModuleContext × System.FilePath)) := do
    match ← readModuleInfo moduleRoot with
    | .error message => return .error message
    | .ok (depModPath, depDeps) =>
        -- Thread the SAME global MVS override into the dep's context: version selection is a
        -- whole-graph property, so every hop resolves each path to the one selected version.
        let depCtx := { root := moduleRoot, modPath := depModPath, deps := depDeps,
                        selected := ctx.selected }
        return .ok (depCtx, subpathDir moduleRoot subpath)

mutual
  /-- Load a package directory into `(declaredName, mergedStruct)`, recursively resolving
      the package's own imports. `ctx` is the module the directory belongs to (so the
      package's in-module and cross-module imports resolve against the right root/deps).
      `visited` holds the directories already on the load stack (as strings) to detect
      cycles — across module hops, since dirs are absolute. All FS access is here; the
      merge is pure. -/
  -- partial: mutually recursive with `parseAndBindFiles`/`collectBindings` over the
  -- filesystem import graph; termination rests on the `visited` cycle-guard, not a
  -- structural measure.
  partial def loadPackage
      (ctx : ModuleContext) (visited : List String) (dir : System.FilePath) :
      IO (Except String (Option String × Value)) := do
    let dirKey := dir.toString
    if visited.contains dirKey then
      return .error s!"import cycle detected at {dirKey}"
    if !(← dir.pathExists) then
      return .error s!"package directory not found: {dirKey}"
    let files ← listPackageFiles dir
    if files.isEmpty then
      return .error s!"no .cue files in package directory: {dirKey}"
    match ← parseAndBindFiles (dirKey :: visited) ctx files with
    | .error message => return .error message
    | .ok (rawFiles, bindings) =>
        match loadPackageFromParsed rawFiles with
        | .error error => return .error s!"package merge error: {error.message}"
        | .ok (declared, merged) =>
            -- Bind the FILE-SCOPED import set (each file's imports carry a distinct synthetic
            -- label, `fileScopedImportLabel`) onto the MERGED body — once, after the sibling meet.
            -- Distinct labels ⇒ a package imported in two files occupies two slots that never
            -- meet-collide, and each file's references were rewritten to its own label upstream,
            -- so imports stay file-scoped while package FIELDS remain shared across files.
            return .ok (declared, bindImports bindings merged)

  /-- Parse each file and resolve its imports, accumulating the parsed files (each body's own
      import references REWRITTEN to file-scoped labels) alongside the combined import-binding
      set across all files. Imports are FILE-SCOPED (CUE scopes an import to the file that
      declares it): each file `i` gets `fileScopedImportLabel i` labels — distinct slots that
      never meet-collide across siblings — and its body's references to those imports are
      rewritten to the matching labels (shadow-aware, `rewriteFileImportRefs`) before the merge.
      Per-file duplicate local names still first-win (`dedupeBindings` within the file); the
      cross-file set is NOT deduped — that would re-conflate two files' same-named imports, the
      very bug this scoping fixes. `loadPackage` then binds the combined set onto the merged body. -/
  -- partial: mutually recursive with `loadPackage` over the filesystem import graph;
  -- termination rests on the `visited` cycle-guard, not a structural measure. The file
  -- iteration itself is a total structural `for`.
  partial def parseAndBindFiles
      (visited : List String) (ctx : ModuleContext)
      (files : List System.FilePath) :
      IO (Except String (List ParsedFile × List (String × Value))) := do
    let mut rawFiles : Array ParsedFile := #[]
    let mut bindings : List (String × Value) := []
    let mut fileIdx : Nat := 0
    for file in files do
      let source ← IO.FS.readFile file
      match parseSourceFile source with
      | .error error => return .error s!"{file}: parse error: {error.message}"
      | .ok parsed =>
          match ← collectBindings visited ctx parsed.topLevelFieldNames parsed.imports with
          | .error message => return .error message
          | .ok fileBindings =>
              let deduped := dedupeBindings fileBindings
              let importNames := deduped.map (·.fst)
              let relabel := fileScopedImportLabel fileIdx
              let rewrittenValue := rewriteFileImportRefs importNames relabel parsed.value
              let scopedBindings := deduped.map (fun b => (relabel b.fst, b.snd))
              rawFiles := rawFiles.push { parsed with value := rewrittenValue }
              bindings := bindings ++ scopedBindings
              fileIdx := fileIdx + 1
    return .ok (rawFiles.toList, bindings)

  /-- Resolve every import path to its package value, in order. In-module paths load a
      subdirectory of `ctx.root`; otherwise the path is matched against `ctx.deps` and the
      owning module is loaded from vendor or the cue cache under its own context. A path
      that is neither in-module nor a known dependency, or a known dep absent from disk,
      surfaces a clean deferred error. -/
  -- partial: mutually recursive with `loadPackage` over the filesystem import graph;
  -- termination rests on the `visited` cycle-guard, not a structural measure. The import
  -- iteration itself is a total structural `for`.
  partial def collectBindings
      (visited : List String) (ctx : ModuleContext)
      (fieldNames : List String)
      (imports : List Import) :
      IO (Except String (List (String × Value))) := do
    let mut acc : Array (String × Value) := #[]
    for imp in imports do
      if isBuiltinImport imp.path then
        -- A stdlib import binds no value, but it still binds its local name in the file
        -- scope: `import "encoding/json"` + `json: {…}` redeclares `json` (A2-y, matching
        -- cue). The bind name follows alias > qualifier > last-path-element.
        match checkImportRedeclaration (importBindName imp) fieldNames with
        | .error message => return .error message
        | .ok () => pure ()
      else if isUnimplementedBuiltin imp.path then
        -- A dot-free stdlib path kue recognizes but has not implemented (`strconv`, `struct`,
        -- `time`, …): a builtin-layer concern, never a disk module. Fail clearly instead of
        -- routing it to `resolveImportTarget` and surfacing the misleading `no cue.mod` error.
        return .error (unimplementedBuiltinError imp.path)
      else
        match ← resolveImportTarget ctx imp.path with
        | .error message => return .error message
        | .ok (loadCtx, dir) =>
            match ← loadPackage loadCtx visited dir with
            | .error message => return .error message
            | .ok (declaredName, value) =>
                -- cue's bare/qualified-import package-name gate: the loaded package's own
                -- `package` clause must equal the name the import expects (qualifier, else last
                -- path element). A divergence (`import ".../foo"` where the dir says `package
                -- bar`) is a cue LOAD error demanding the `:bar` qualifier — not a silent bind
                -- under `bar`. Enforcing it here keeps `importBindName` purely lexical: a bound
                -- package's name always matches its last-path-element/qualifier, so the
                -- parse-time unused-import check (which has no declared name) can never mis-name
                -- a used import as unused. A clause-less package (`none`) cannot mismatch.
                match declaredName with
                | some declared =>
                    if declared != expectedPackageName imp then
                      return .error (packageNameMismatchError (expectedPackageName imp))
                | none => pure ()
                let bindName := importBindName imp
                match checkImportRedeclaration bindName fieldNames with
                | .error message => return .error message
                | .ok () => acc := acc.push (bindName, value)
    return .ok acc.toList
end

/-- Load a package *directory* as the entry: discover its module, then merge all
    same-package sibling `*.cue` via `loadPackage` (package-name consistency, sibling
    meet-merge, and each file's imports bound — the same machinery imported packages use).
    Returns the merged package value; `cue` resolves cross-file definitions exactly this way
    when given a directory or package argument.

    Distinct from `loadFileBound`, which loads a single file with no sibling merge —
    matching `cue`'s contract that a bare file argument does *not* pull in its package
    siblings (`cue export apps/argocd.cue` errors on a sibling-defined reference, while
    `cue export ./apps` resolves it). -/
def loadPackageDir (path : String) : IO (Except String Value) := do
  let cwd ← IO.currentDir
  let dir := absolutePath cwd (System.FilePath.mk path)
  match ← findModuleRoot dir with
  | none => return .error "no cue.mod/module.cue found in any parent directory"
  | some root =>
      match ← readModuleInfo root with
      | .error message => return .error message
      | .ok (modPath, deps) =>
          match ← solveVersionOverride root modPath deps with
          | .error message => return .error message
          | .ok selected =>
              let ctx := { root, modPath, deps, selected }
              match ← loadPackage ctx [] dir with
              | .error message => return .error message
              | .ok (_, value) => return .ok value

/-- Load a top-level file, resolve and bind its in-module imports, and return the bound
    value for the existing pure resolve/eval pipeline. A file with no imports parses, binds
    nothing, and behaves exactly as the pre-import pipeline. Sibling files in the same
    package are *not* merged — that is `loadPackageDir`'s job, reached only via a directory
    argument, matching `cue`'s bare-file-vs-package contract. -/
def loadFileBound (path : String) : IO (Except String Value) := do
  let source ← IO.FS.readFile (System.FilePath.mk path)
  match parseSourceFile source with
  | .error error => return .error s!"parse error: {error.line}:{error.column}: {error.message}"
  | .ok parsed =>
      -- A recognized-but-unimplemented stdlib import (`strconv`, `struct`, …) is a builtin-layer
      -- concern with no module context; fail clearly here, before module-root discovery could
      -- surface the misleading `no cue.mod` disk-loader error for a dot-free stdlib path.
      if let some imp := parsed.imports.find? (fun imp => isUnimplementedBuiltin imp.path) then
        return .error (unimplementedBuiltinError imp.path)
      -- A file with no imports — or only stdlib imports the builtin dispatch handles —
      -- needs no module context and behaves exactly as the pre-import pipeline. A stdlib
      -- import still binds its local name in the file scope, so the A2-y redeclaration check
      -- runs here too (`import "encoding/json"` + `json: {…}` is a load error in cue).
      if parsed.imports.all (fun imp => isBuiltinImport imp.path) then
        match checkBuiltinImportRedeclarations parsed.imports parsed.topLevelFieldNames with
        | .error message => return .error message
        | .ok () => return .ok parsed.value
      let cwd ← IO.currentDir
      let dir := discoveryStartDir cwd (System.FilePath.mk path)
      match ← findModuleRoot dir with
      | none => return .error "no cue.mod/module.cue found in any parent directory"
      | some root =>
          match ← readModuleInfo root with
          | .error message => return .error message
          | .ok (modPath, deps) =>
              match ← solveVersionOverride root modPath deps with
              | .error message => return .error message
              | .ok selected =>
                  let ctx := { root, modPath, deps, selected }
                  match ← collectBindings [] ctx parsed.topLevelFieldNames parsed.imports with
                  | .error message => return .error message
                  | .ok bindings => return .ok (bindImports bindings parsed.value)

/-- The single IO entry the CLI routes through: a directory argument loads the package
    (sibling merge); a file argument loads that one file (no merge), exactly as before.
    The file-vs-directory split is `cue`'s own: a package is the directory's same-package
    `*.cue` files, and a bare file is just that file. -/
def loadEntry (path : String) : IO (Except String Value) := do
  if ← (System.FilePath.mk path).isDir then
    loadPackageDir path
  else
    loadFileBound path

end Kue
