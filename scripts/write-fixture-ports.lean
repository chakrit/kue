import Kue.FixturePorts

def main (args : List String) : IO UInt32 := do
  match args with
  | [targetDir] =>
      Kue.writeFixturePorts (System.FilePath.mk targetDir)
      pure 0
  | _ =>
      IO.eprintln "usage: lean --run scripts/write-fixture-ports.lean <target-dir>"
      pure 1
