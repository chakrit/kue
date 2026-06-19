import Kue.Parse
import Kue.Runtime

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

/-- The standard-library import paths whose symbols are dispatched by `evalBuiltinCall`
    (call-form `pkg.fn(...)`), not bound as package values. The loader skips these so a
    builtin import never triggers module resolution; the existing dotted-call path handles
    them unchanged. The local bind names follow the last path element
    (`encoding/base64` → `base64`). -/
def builtinImportPaths : List String :=
  ["strings", "list", "math", "regexp", "encoding/base64", "encoding/json", "encoding/yaml"]

/-- Whether an import path names a built-in stdlib package the loader must leave to the
    call-form builtin dispatch rather than resolve from disk. -/
def isBuiltinImport (path : String) : Bool :=
  builtinImportPaths.contains path

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

    The file `value`s here are RAW bodies (imports NOT yet bound): the SAME package imported in
    two sibling files must bind ONCE, not once-per-file-then-meet. Binding per-file then
    `meet`-folding duplicates the hidden import label and `meet`s two independently-loaded copies
    of the same package struct, which corrupts the binding (→ bottom). So `loadPackage` binds the
    DEDUPED package-level binding set onto the merged body via `bindMergedImports`. -/
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

/-- Inject each `(localName, packageValue)` binding as a synthetic top-level
    `importBinding` field of the importing file's struct, prepended ahead of the body so a
    later same-named body field would shadow it (none occur in practice). An import binding
    reads as hidden everywhere (in scope for `pkg.#Symbol` references, excluded from output)
    but is distinguished from a real in-file hidden field so the two output-reachability
    sites can keep an unreferenced bound package lazy. Non-struct top-level values are
    wrapped so the bindings still land in scope. -/
def bindImports (bindings : List (String × Value)) : Value -> Value
  | .struct fields openness tail patterns closingPatterns =>
      .struct (bindings.map (fun b => ⟨b.fst, FieldClass.importBinding, b.snd⟩) ++ fields) openness tail patterns closingPatterns
  | value =>
      mkStruct (bindings.map (fun b => ⟨b.fst, FieldClass.importBinding, b.snd⟩) ++ [⟨"", FieldClass.regular, value⟩]) .defClosed none []

/-- The local name a package binds under: the import alias when present, else the
    package's declared name, else the last path element as a final fallback (a package
    whose files all omit a clause — rare; CUE infers the name from the path). -/
def importBindName (imp : Import) (declaredName : Option String) : String :=
  match imp.alias with
  | some alias => alias
  | none =>
      match declaredName with
      | some name => name
      | none => lastPathElement imp.path
where
  lastPathElement (path : String) : String :=
    (path.splitOn "/").getLast!

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
    cross-module imports resolve against the right root and deps. -/
structure ModuleContext where
  root : System.FilePath
  modPath : String
  deps : List Dep

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
  let extractBase := (← cacheRoot) / "mod" / "extract"
  let cached := joinModulePath extractBase s!"{dep.modPath}@{dep.version}"
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
      match ← locateModuleDir ctx.root dep with
      | none => return .error (moduleNotOnDiskError importPath dep.modPath dep.version)
      | some moduleRoot =>
          match ← readModuleInfo moduleRoot with
          | .error message => return .error message
          | .ok (depModPath, depDeps) =>
              let depCtx := { root := moduleRoot, modPath := depModPath, deps := depDeps }
              return .ok (depCtx, subpathDir moduleRoot subpath)
  | none =>
      match resolveImportSubpath ctx.modPath importPath with
      | some subpath => return .ok (ctx, subpathDir ctx.root subpath)
      | none => return .error (unknownModuleError importPath)

mutual
  /-- Load a package directory into `(declaredName, mergedStruct)`, recursively resolving
      the package's own imports. `ctx` is the module the directory belongs to (so the
      package's in-module and cross-module imports resolve against the right root/deps).
      `visited` holds the directories already on the load stack (as strings) to detect
      cycles — across module hops, since dirs are absolute. All FS access is here; the
      merge is pure. -/
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
    match ← parseAndBindFiles (dirKey :: visited) ctx files [] [] with
    | .error message => return .error message
    | .ok (rawFiles, bindings) =>
        match loadPackageFromParsed rawFiles with
        | .error error => return .error s!"package merge error: {error.message}"
        | .ok (declared, merged) =>
            -- Bind the DEDUPED package-level import set onto the MERGED body — once, after the
            -- sibling meet — so a package imported in two files is a single binding, not a meet of
            -- two copies. (Per-file binding then merge was the cert-manager `conflicting values`.)
            return .ok (declared, bindImports (dedupeBindings bindings) merged)

  /-- Parse each file and resolve its imports, accumulating the RAW parsed files (bodies NOT
      bound) alongside the combined import-binding set across all files. Binding is deferred to
      `loadPackage`, which dedupes and binds ONCE onto the merged body — so a package imported in
      multiple sibling files is a single binding, never a meet of per-file copies. -/
  partial def parseAndBindFiles
      (visited : List String) (ctx : ModuleContext)
      (files : List System.FilePath)
      (acc : List ParsedFile) (bindingAcc : List (String × Value)) :
      IO (Except String (List ParsedFile × List (String × Value))) := do
    match files with
    | [] => return .ok (acc.reverse, bindingAcc)
    | file :: rest =>
        let source ← IO.FS.readFile file
        match parseSourceFile source with
        | .error error => return .error s!"{file}: parse error: {error.message}"
        | .ok parsed =>
            match ← collectBindings visited ctx parsed.imports [] with
            | .error message => return .error message
            | .ok bindings =>
                parseAndBindFiles visited ctx rest (parsed :: acc) (bindingAcc ++ bindings)

  /-- Resolve every import path to its package value, in order. In-module paths load a
      subdirectory of `ctx.root`; otherwise the path is matched against `ctx.deps` and the
      owning module is loaded from vendor or the cue cache under its own context. A path
      that is neither in-module nor a known dependency, or a known dep absent from disk,
      surfaces a clean deferred error. -/
  partial def collectBindings
      (visited : List String) (ctx : ModuleContext)
      (imports : List Import) (acc : List (String × Value)) :
      IO (Except String (List (String × Value))) := do
    match imports with
    | [] => return .ok acc.reverse
    | imp :: rest =>
        if isBuiltinImport imp.path then
          -- A stdlib import binds no value; `evalBuiltinCall` dispatches its calls.
          collectBindings visited ctx rest acc
        else
          match ← resolveImportTarget ctx imp.path with
          | .error message => return .error message
          | .ok (loadCtx, dir) =>
              match ← loadPackage loadCtx visited dir with
              | .error message => return .error message
              | .ok (declaredName, value) =>
                  let bindName := importBindName imp declaredName
                  collectBindings visited ctx rest ((bindName, value) :: acc)
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
          let ctx := { root, modPath, deps }
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
      -- A file with no imports — or only stdlib imports the builtin dispatch handles —
      -- needs no module context and behaves exactly as the pre-import pipeline.
      if parsed.imports.all (fun imp => isBuiltinImport imp.path) then
        return .ok parsed.value
      let cwd ← IO.currentDir
      let dir := discoveryStartDir cwd (System.FilePath.mk path)
      match ← findModuleRoot dir with
      | none => return .error "no cue.mod/module.cue found in any parent directory"
      | some root =>
          match ← readModuleInfo root with
          | .error message => return .error message
          | .ok (modPath, deps) =>
              let ctx := { root, modPath, deps }
              match ← collectBindings [] ctx parsed.imports [] with
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
