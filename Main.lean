import Kue

def main : IO Unit :=
  for line in Kue.smokeLines do
    IO.println line
