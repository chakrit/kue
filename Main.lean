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

def main (args : List String) : IO UInt32 := do
  match args with
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
