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

/-- The deferred-resolution message emitted for any import path that is not in-module —
    cross-module, registry, or vendored. Resolving these is B3c/B3d work. -/
def crossModuleDeferredError (path : String) : String :=
  s!"unresolved import: {path}: cross-module/registry not yet supported (B3c)"

/-- The standard-library import paths whose symbols are dispatched by `evalBuiltinCall`
    (call-form `pkg.fn(...)`), not bound as package values. The loader skips these so a
    builtin import never triggers module resolution; the existing dotted-call path handles
    them unchanged. The local bind names follow the last path element
    (`encoding/base64` → `base64`). -/
def builtinImportPaths : List String :=
  ["strings", "list", "math", "encoding/base64", "encoding/json", "encoding/yaml"]

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

/-- Build a package struct from its already-parsed files: check package-name consistency,
    then meet-merge the file bodies via the shared multi-file merge primitive. Returns the
    declared package name (`none` when every file omits a package clause) paired with the
    merged value. Pure — the parsing and disk listing happened upstream. -/
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

/-- Inject each `(localName, packageValue)` binding as a synthetic top-level regular field
    of the importing file's struct, prepended ahead of the body so a later same-named body
    field would shadow it (none occur in practice). Non-struct top-level values are wrapped
    so the bindings still land in scope. -/
def bindImports (bindings : List (String × Value)) : Value -> Value
  | .struct fields open_ =>
      .struct (bindings.map (fun b => (b.fst, FieldClass.hidden, b.snd)) ++ fields) open_
  | value =>
      .struct (bindings.map (fun b => (b.fst, FieldClass.hidden, b.snd)) ++ [("", FieldClass.regular, value)]) false

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

/-- Read and parse `cue.mod/module.cue`, returning the `module:` field's string value. The
    file is CUE, so reuse the parser and look the field up in the top-level struct. -/
def readModulePath (root : System.FilePath) : IO (Except String String) := do
  let source ← IO.FS.readFile (root / "cue.mod" / "module.cue")
  match parseSource source with
  | .error error => pure (.error s!"cue.mod/module.cue: parse error: {error.message}")
  | .ok value =>
      match moduleFieldValue value with
      | some path => pure (.ok path)
      | none => pure (.error "cue.mod/module.cue: missing string `module:` field")
where
  moduleFieldValue : Value -> Option String
    | .struct fields _ =>
        (fields.find? (fun f => f.fst == "module")).bind fun f =>
          match f.snd.snd with
          | .prim (.string path) => some path
          | _ => none
    | _ => none

/-- List the `*.cue` files in a package directory, sorted for deterministic merge order. -/
def listPackageFiles (dir : System.FilePath) : IO (List System.FilePath) := do
  let entries ← dir.readDir
  let cueFiles := entries.toList.filterMap fun entry =>
    if entry.path.extension == some "cue" then some entry.path else none
  pure (cueFiles.toArray.qsort (fun a b => a.toString < b.toString)).toList

/-- The directory holding the package at module-relative `subpath` (`""` ⇒ the module
    root). Joins each non-empty path segment onto `root`. -/
def subpathDir (root : System.FilePath) (subpath : String) : System.FilePath :=
  subpath.splitOn "/" |>.foldl (init := root) fun acc segment =>
    if segment.isEmpty then acc else acc / segment

mutual
  /-- Load a package directory into `(declaredName, mergedStruct)`, recursively resolving
      the package's own in-module imports. `visited` holds the directories already on the
      load stack (as strings) to detect cycles. All FS access is here; the merge is pure. -/
  partial def loadPackage
      (root : System.FilePath) (modPath : String)
      (visited : List String) (dir : System.FilePath) :
      IO (Except String (Option String × Value)) := do
    let dirKey := dir.toString
    if visited.contains dirKey then
      return .error s!"import cycle detected at {dirKey}"
    if !(← dir.pathExists) then
      return .error s!"package directory not found: {dirKey}"
    let files ← listPackageFiles dir
    if files.isEmpty then
      return .error s!"no .cue files in package directory: {dirKey}"
    match ← parseAndBindFiles (dirKey :: visited) root modPath files [] with
    | .error message => return .error message
    | .ok boundFiles =>
        match loadPackageFromParsed boundFiles with
        | .error error => return .error s!"package merge error: {error.message}"
        | .ok result => return .ok result

  /-- Parse each file, resolve and bind its own imports, accumulating `ParsedFile`s whose
      `value` is already import-bound (ready for the package merge). -/
  partial def parseAndBindFiles
      (visited : List String) (root : System.FilePath) (modPath : String)
      (files : List System.FilePath) (acc : List ParsedFile) :
      IO (Except String (List ParsedFile)) := do
    match files with
    | [] => return .ok acc.reverse
    | file :: rest =>
        let source ← IO.FS.readFile file
        match parseSourceFile source with
        | .error error => return .error s!"{file}: parse error: {error.message}"
        | .ok parsed =>
            match ← collectBindings visited root modPath parsed.imports [] with
            | .error message => return .error message
            | .ok bindings =>
                let bound := { parsed with value := bindImports bindings parsed.value }
                parseAndBindFiles visited root modPath rest (bound :: acc)

  /-- Resolve every in-module import path to its package value, in order, surfacing the
      deferred error for a cross-module path. Shared by package files and the top-level
      entry; the top-level call seeds `visited := []`. -/
  partial def collectBindings
      (visited : List String) (root : System.FilePath) (modPath : String)
      (imports : List Import) (acc : List (String × Value)) :
      IO (Except String (List (String × Value))) := do
    match imports with
    | [] => return .ok acc.reverse
    | imp :: rest =>
        if isBuiltinImport imp.path then
          -- A stdlib import binds no value; `evalBuiltinCall` dispatches its calls.
          collectBindings visited root modPath rest acc
        else
          match resolveImportSubpath modPath imp.path with
          | none => return .error (crossModuleDeferredError imp.path)
          | some subpath =>
              match ← loadPackage root modPath visited (subpathDir root subpath) with
              | .error message => return .error message
              | .ok (declaredName, value) =>
                  let bindName := importBindName imp declaredName
                  collectBindings visited root modPath rest ((bindName, value) :: acc)
end

/-- Load a top-level file, resolve and bind its in-module imports, and return the bound
    value for the existing pure resolve/eval pipeline. The single IO entry the CLI routes
    through; a file with no imports parses, binds nothing, and behaves exactly as before. -/
def loadFileBound (path : String) : IO (Except String Value) := do
  let source ← IO.FS.readFile (System.FilePath.mk path)
  match parseSourceFile source with
  | .error error => return .error s!"parse error: {error.line}:{error.column}: {error.message}"
  | .ok parsed =>
      -- A file with no imports — or only stdlib imports the builtin dispatch handles —
      -- needs no module context and behaves exactly as the pre-import pipeline.
      if parsed.imports.all (fun imp => isBuiltinImport imp.path) then
        return .ok parsed.value
      let dir := (System.FilePath.mk path).parent.getD (System.FilePath.mk ".")
      match ← findModuleRoot dir with
      | none => return .error "no cue.mod/module.cue found in any parent directory"
      | some root =>
          match ← readModulePath root with
          | .error message => return .error message
          | .ok modPath =>
              match ← collectBindings [] root modPath parsed.imports [] with
              | .error message => return .error message
              | .ok bindings => return .ok (bindImports bindings parsed.value)

end Kue
