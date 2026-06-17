import Kue

def printSmoke : IO Unit :=
  for line in Kue.smokeLines do
    IO.println line

def printEvalResult (result : Except Kue.ParseError String) : IO UInt32 := do
  match result with
  | .ok output =>
      IO.println output
      pure 0
  | .error error =>
      IO.eprintln s!"kue: parse error: {error.line}:{error.column}: {error.message}"
      pure 1

def readFileSources : List String -> IO (List String)
  | [] => pure []
  | path :: paths => do
      let source ← IO.FS.readFile (System.FilePath.mk path)
      let sources ← readFileSources paths
      pure (source :: sources)

/-- Parsed `export`-mode invocation: the chosen output format and the optional input
    file path (none = read stdin). `-e`/`--expression` sub-expression selection is
    deferred (documented in compat-assumptions). -/
structure ExportArgs where
  format : Kue.ExportFormat
  file : Option String
deriving Repr

/-- Parse `export` flags. Default format is JSON, matching `cue export`'s default. A
    bare positional argument is the input file; absence means stdin. -/
def parseExportArgs : List String -> Except String ExportArgs
  | [] => .ok { format := .json, file := none }
  | "--out" :: "json" :: rest => (parseExportArgs rest).map ({ · with format := .json })
  | "--out" :: "yaml" :: rest => (parseExportArgs rest).map ({ · with format := .yaml })
  | "--out" :: other :: _ => .error s!"unsupported --out format: {other} (expected json or yaml)"
  | "--out" :: [] => .error "missing value for --out"
  | arg :: rest =>
      if arg.startsWith "-" then
        .error s!"unknown export flag: {arg}"
      else
        (parseExportArgs rest).map fun parsed =>
          match parsed.file with
          | none => { parsed with file := some arg }
          | some _ => parsed

/-- The `export` subcommand: read a single CUE input (file or stdin), evaluate it, and
    print the manifested value as JSON (default) or YAML, matching `cue export`. Parse
    errors print a positioned diagnostic; a non-concrete value prints an export error.
    Both exit non-zero. -/
def runExport (rawArgs : List String) : IO UInt32 := do
  match parseExportArgs rawArgs with
  | .error message =>
      IO.eprintln s!"kue: export: {message}"
      pure 2
  | .ok args =>
      let source ← match args.file with
        | some path => IO.FS.readFile (System.FilePath.mk path)
        | none => do let stdin ← IO.getStdin; stdin.readToEnd
      match Kue.exportSourcesToString args.format [source] with
      | .error parseError =>
          IO.eprintln s!"kue: parse error: {parseError.line}:{parseError.column}: {parseError.message}"
          pure 1
      | .ok (.error message) =>
          IO.eprintln s!"kue: export error: {message}"
          pure 1
      | .ok (.ok output) =>
          IO.print output
          pure 0

def main (args : List String) : IO UInt32 := do
  match args with
  | "export" :: rest => runExport rest
  | [] =>
      let stdin ← IO.getStdin
      let source ← stdin.readToEnd
      if source.trimAscii.toString.isEmpty then
        printSmoke
        pure 0
      else
        printEvalResult (Kue.evalSourceToString source)
  | _ =>
      let sources ← readFileSources args
      printEvalResult (Kue.evalSourcesToString sources)
