import Kue.Eval
import Kue.Format
import Kue.Lattice
import Kue.Parse
import Kue.Resolve
import Kue.Json
import Kue.Yaml

namespace Kue

/-- The Kue version string, reported by `kue version` / `kue --version`. Bumped by
    `scripts/release.sh` at release time; this is the single source of truth. -/
def version : String := "0.1.0-alpha"

def formatTopLevel : Value -> String
  -- A plain-struct-equivalent struct (no tail, no patterns) formats top-level fields directly;
  -- tail/pattern-bearing forms fall through to `formatValue` (legacy did the same).
  | .struct fields _ none [] _ => joinWith "\n" (formatStructFieldsWithFuel formatFuel fields)
  | value => formatValue value

def resolveAndEval (value : Value) : Value :=
  evalStructRefs (resolveStructRefs value)

/-- Resolve+eval and return the eval-work counters as a formatted line (for `KUE_PROFILE`
    stderr): core evals, memo hits, and final cache sizes. `fuelCacheSize=0` witnesses a
    fully-saturating program where the empty-`cache`-skip fast path elides the redundant
    fuel-cache probe on every core eval. -/
def resolveAndEvalProfileString (value : Value) : String :=
  let (_, evalCalls, cacheHits, satSize, fuelSize, forceSize) :=
    evalStructRefsProfile (resolveStructRefs value)
  s!"evalCalls={evalCalls} cacheHits={cacheHits} " ++
  s!"satCacheSize={satSize} fuelCacheSize={fuelSize} forceCacheSize={forceSize}"

def formatResolvedTopLevel (value : Value) : String :=
  formatTopLevel (resolveAndEval value)

def evalSourceToString (source : String) : Except ParseError String :=
  (parseSource source).map formatResolvedTopLevel

def parseSources : List String -> Except ParseError (List Value)
  | [] => .ok []
  | source :: sources => do
      let value ← parseSource source
      let values ← parseSources sources
      pure (value :: values)

def mergePackageNames (left right : Option String) : Except ParseError (Option String) :=
  match left, right with
  | none, packageName => pure packageName
  | packageName, none => pure packageName
  | some leftName, some rightName =>
      if leftName == rightName then
        pure (some leftName)
      else
        parseError [] "conflicting package names"

def checkSourcePackageNamesWith :
    Option String -> List String -> Except ParseError (Option String)
  | packageName, [] => pure packageName
  | packageName, source :: sources => do
      let sourceName ← sourcePackageName source
      let packageName ← mergePackageNames packageName sourceName
      checkSourcePackageNamesWith packageName sources

def checkSourcePackageNames (sources : List String) : Except ParseError (Option String) :=
  checkSourcePackageNamesWith none sources

def mergeSourceValues : List Value -> Value
  | [] => mkStruct [] .regularOpen none []
  | value :: values => values.foldl meet value

def evalSourcesToString (sources : List String) : Except ParseError String := do
  let _ ← checkSourcePackageNames sources
  let values ← parseSources sources
  pure (formatResolvedTopLevel (mergeSourceValues values))

/-- The output encoding selected by the `export` CLI mode. -/
inductive ExportFormat where
  | json
  | yaml
deriving Repr, BEq, DecidableEq

/-- A human-readable reason an `export` failed to produce concrete output, mirroring how
    `cue export` reports a non-concrete or contradictory value. -/
def formatManifestError : ManifestError -> String
  | .contradiction => "conflicting values (bottom)"
  | .incomplete value => s!"incomplete value: {formatValue value}"
  | .ambiguous _ => "ambiguous value: multiple non-default disjuncts remain"
  | .importedNotUsed imports =>
      "\n".intercalate (imports.map fun (path, alias) =>
        match alias with
        | none => s!"imported and not used: \"{path}\""
        | some name => s!"imported and not used: \"{path}\" as {name}")
  | .unsupportedBuiltinFunction name =>
      s!"unsupported builtin function \"{name}\": recognized but not yet implemented in kue"
  | .letClauseCycle label isMutual =>
      if isMutual then "cyclic references in let clause or alias"
      else s!"reference \"{label}\" not found"

/-- Look up a field by label on a resolved struct-like value, returning its value when
    present. Mirrors the decl-bearing cases of `selectEvaluatedField` but distinguishes a
    genuine absence (`none`) from a present field, so the `-e` selector can report a clean
    "field not found" rather than silently exporting bottom. Deliberately yields the RAW
    `Field.value` (no `selectedFieldValue` close) and an `Option` (no deferred `.selector`):
    a different operation from Eval's `selectFromDecls`, NOT shared across the module seam. -/
def lookupField? (base : Value) (label : String) : Option Value :=
  let fieldValue? (decls : List Field) := (findEvalField label decls).map Field.value
  match base with
  | .struct fields _ _ _ _ => fieldValue? fields
  | .embeddedList _ _ decls => fieldValue? decls
  | .embeddedScalar _ decls => fieldValue? decls
  | _ => none

/-- Evaluate `-e` field-path selection against an already-bound root value. Splits the
    expression on `.` and walks each segment, resolving/evaluating between steps so a
    nested field's own references are bound before the next lookup. A missing segment is a
    clean error mirroring `cue export -e`'s `reference "<seg>" not found`. Scope: dotted
    field paths only (no indices, slices, or arbitrary expressions). -/
def selectExprPath (root : Value) : List String -> Except String Value
  | [] => .ok root
  | segment :: rest =>
      let resolved := resolveAndEval root
      match lookupField? resolved segment with
      | some value => selectExprPath value rest
      | none => .error s!"reference \"{segment}\" not found"

/-- Split a dotted `-e` expression into its path segments. An empty segment (leading,
    trailing, or doubled dot) is a malformed path and yields `none`. -/
def parseExprPath (expr : String) : Option (List String) :=
  let segments := expr.splitOn "."
  if segments.any (·.isEmpty) then none else some segments

/-- Manifest and serialize an already-bound value in the chosen format. Shared by the
    source-list export path and the import-aware loader, which supplies a value whose
    imports are already resolved and bound. -/
def exportValue (format : ExportFormat) (value : Value) : Except String String :=
  let resolved := resolveAndEval value
  let serialized : Except ManifestError String :=
    match format with
    | .json => valueToJsonPretty resolved
    | .yaml => valueToYaml resolved
  serialized.mapError formatManifestError

/-- Like `exportValue`, but first selects the dotted field-path `expr` from the root (the
    `kue export -e <expr>` path). A malformed path or a missing segment is a clean error;
    a present-but-incomplete selection falls through to the usual manifest error. -/
def exportValueSelecting (format : ExportFormat) (expr : String) (value : Value) :
    Except String String := do
  match parseExprPath expr with
  | none => .error s!"invalid -e expression: {expr}"
  | some segments =>
      let selected ← selectExprPath value segments
      exportValue format selected

/-- Resolve, evaluate, manifest, and serialize the merged sources in the chosen format.
    Returns a positioned `ParseError` on parse failure (caught upstream by the CLI) or a
    `ManifestError` message when the value is not concrete — the CLI maps the latter to a
    non-zero exit. Output carries the trailing newline `cue export` emits. -/
def exportSourcesToString (format : ExportFormat) (sources : List String) :
    Except ParseError (Except String String) := do
  let _ ← checkSourcePackageNames sources
  let values ← parseSources sources
  pure (exportValue format (mergeSourceValues values))

end Kue
