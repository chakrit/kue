import Kue

def printSmoke : IO Unit :=
  for line in Kue.smokeLines do
    IO.println line

def main : IO Unit := do
  let stdin ← IO.getStdin
  let source ← stdin.readToEnd
  if source.trimAscii.toString.isEmpty then
    printSmoke
  else
    match Kue.evalSourceToString source with
    | .ok output => IO.println output
    | .error error =>
        IO.eprintln s!"kue: parse error: {error.message}"
        IO.Process.exit 1
