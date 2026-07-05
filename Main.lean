import Kue
import Kue.Cli
import Kue.ModCmd

/-- Process exit codes. Usage errors (bad subcommand/flag) are distinct from
    evaluation/parse failures so callers and scripts can tell them apart. -/
def evalErrorCode : UInt32 := 1
def usageErrorCode : UInt32 := 2

def printEvalResult (result : Except Kue.ParseError String) : IO UInt32 := do
  match result with
  | .ok output =>
      IO.println output
      pure 0
  | .error error =>
      IO.eprintln s!"kue: parse error: {error.line}:{error.column}: {error.message}"
      pure evalErrorCode

def readFileSources : List String -> IO (List String)
  | [] => pure []
  | path :: paths => do
      let source ← IO.FS.readFile (System.FilePath.mk path)
      let sources ← readFileSources paths
      pure (source :: sources)

/-- Print a bound-load result: a loader error (already human-readable) or the formatted
    value. -/
def printLoaded (loaded : Except String Kue.Value) : IO UInt32 := do
  match loaded with
  | .error message =>
      IO.eprintln s!"kue: {message}"
      pure evalErrorCode
  | .ok value =>
      IO.println (Kue.formatResolvedTopLevel value)
      pure 0

/-- Evaluate a single file through the import-aware loader, then format the bound value.
    A read failure (missing/unreadable file) is reported as a clean diagnostic rather than
    an uncaught exception. -/
def runEvalFile (path : String) : IO UInt32 := do
  match ← (Kue.loadEntry path).toBaseIO with
  | .error ioError =>
      IO.eprintln s!"kue: cannot read {path}: {ioError.toString}"
      pure evalErrorCode
  | .ok loaded => printLoaded loaded

/-- The `eval` path. No files reads stdin (empty input evaluates to the empty struct, like
    `cue eval -`); a single file routes through the import-aware loader; multiple files
    merge through the pure pipeline. Reached only via the explicit `kue eval` subcommand or
    the bare `kue <file…>` shorthand — never bare `kue`, which now prints help. -/
def runEval : List String -> IO UInt32
  | [] => do
      let stdin ← IO.getStdin
      let source ← stdin.readToEnd
      printEvalResult (Kue.evalSourceToString source)
  | [path] => runEvalFile path
  | paths => do
      let sources ← readFileSources paths
      printEvalResult (Kue.evalSourcesToString sources)

/-- Manifest a bound value to output, honoring an optional `-e` field-path selector. With
    a selector, a missing/invalid path is a clean error; without one, the whole root is
    exported as before. -/
def exportBoundValue (opts : Kue.Cli.ExportOpts) (value : Kue.Value) :
    Except String String :=
  match opts.expr with
  | some expr => Kue.exportValueSelecting opts.format expr value
  | none => Kue.exportValue opts.format value

/-- The `export` subcommand: read a single CUE input (file or stdin), evaluate it, apply an
    optional `-e` field-path selector, and print the manifested value as JSON (default) or
    YAML, matching `cue export`. File mode routes through the import-aware loader; stdin
    mode has no module context. -/
def runExport (opts : Kue.Cli.ExportOpts) : IO UInt32 := do
  match opts.file with
  | some path =>
      match ← (Kue.loadEntry path).toBaseIO with
      | .error ioError =>
          IO.eprintln s!"kue: cannot read {path}: {ioError.toString}"
          pure evalErrorCode
      | .ok (.error message) =>
          IO.eprintln s!"kue: {message}"
          pure evalErrorCode
      | .ok (.ok value) =>
          if (← IO.getEnv "KUE_PROFILE").isSome then
            IO.eprintln (Kue.resolveAndEvalProfileString value)
            pure 0
          else
          match exportBoundValue opts value with
          | .error message =>
              IO.eprintln s!"kue: export error: {message}"
              pure evalErrorCode
          | .ok output =>
              IO.print output
              pure 0
  | none =>
      let stdin ← IO.getStdin
      let source ← stdin.readToEnd
      match Kue.parseSources [source] with
      | .error parseError =>
          IO.eprintln s!"kue: parse error: {parseError.line}:{parseError.column}: {parseError.message}"
          pure evalErrorCode
      | .ok values =>
          match Kue.checkSourcePackageNames [source] with
          | .error parseError =>
              IO.eprintln s!"kue: parse error: {parseError.line}:{parseError.column}: {parseError.message}"
              pure evalErrorCode
          | .ok _ =>
              match exportBoundValue opts (Kue.mergeSourceValues values) with
              | .error message =>
                  IO.eprintln s!"kue: export error: {message}"
                  pure evalErrorCode
              | .ok output =>
                  IO.print output
                  pure 0

/-- The `mod tidy` subcommand: discover the module root from the cwd, resolve the requirement
    graph (transitive read-only registry GETs), run MVS, and write `cue.sum`. Prints the resolved
    build list; a resolution/fetch failure is a clean diagnostic. -/
def runModTidy : IO UInt32 := do
  let root ← IO.currentDir
  match ← Kue.findModuleRoot root with
  | none =>
      IO.eprintln "kue: no cue.mod/module.cue found in any parent directory"
      pure evalErrorCode
  | some moduleRoot =>
      let cueRegistry ← Kue.readCueRegistry
      match ← Kue.ModCmd.runTidy moduleRoot (Kue.ModCmd.ociEntryFetcher cueRegistry) with
      | .error message =>
          IO.eprintln s!"kue: mod tidy: {message}"
          pure evalErrorCode
      | .ok res =>
          IO.println s!"resolved {res.sumRows.length} dependencies; wrote cue.sum"
          for mvv in res.buildList do
            if !mvv.version.isEmpty then
              IO.println s!"  {mvv.basePath} {mvv.version}"
          pure 0

def runMod : Kue.Cli.ModOp -> IO UInt32
  | .tidy => runModTidy

def runCommand : Kue.Cli.Command -> IO UInt32
  | .eval files => runEval files
  | .export opts => runExport opts
  | .mod op => runMod op
  | .version => do
      IO.println Kue.version
      pure 0
  | .help topic => do
      IO.println (Kue.Cli.helpText topic)
      pure 0
  | .error message => do
      IO.eprintln s!"kue: {message}"
      IO.eprintln "run `kue --help` for usage"
      pure usageErrorCode

def main (args : List String) : IO UInt32 :=
  runCommand (Kue.Cli.parse args)
