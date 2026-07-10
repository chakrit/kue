import Kue.ModCmd
import Kue.Zip
import Kue.Sha256

/-!
# `cue mod tidy` end-to-end pipeline check (B3d-6b, OFFLINE)

Drives `Kue.ModCmd.runTidy` end to end WITHOUT a network: the `EntryFetcher` is injected to read
the committed `testdata/ocifetch/modtidy/*.zip` fixtures (a diamond requirement graph) instead of
fetching from a registry, and `cue.sum` is written into a repo-local temp importer root — never a
real cache. Proves: transitive module.cue fetch → requirement-graph build → CHECKED MVS solve
(version conflict resolved by max-of-mins) → `cue.sum` WRITE with verified `h1:` digests. Plus the
error paths: a transport failure and a malformed dependency module.cue both surface typed errors.

Argv: <abs testdata/ocifetch/modtidy dir>. Run by `scripts/check-fixtures.sh`. No network; the
importer temp tree is removed at the end. Exit 0 ⇒ all assertions pass.
-/

open Kue
open Kue.Registry (ModuleVersion)

/-- Map a dependency to its committed fixture zip (by module path + version). An unmapped dep
    simulates a transport failure — used to prove the error path. -/
def fixtureZipFor (dep : Dep) : Option String :=
  match dep.modPath, dep.version with
  | "a.example/a", "v1.0.0" => some "a.zip"
  | "b.example/b", "v1.0.0" => some "b.zip"
  | "c.example/c", "v1.2.0" => some "c-1.2.0.zip"
  | "c.example/c", "v1.3.0" => some "c-1.3.0.zip"
  | _, _ => none

/-- The offline entry-fetcher: read the mapped fixture zip and unzip it (the same bytes the real
    registry GET would return). An unmapped dep is a simulated fetch failure. -/
def fixtureFetcher (dir : String) : ModCmd.EntryFetcher := fun dep => do
  match fixtureZipFor dep with
  | none => pure (.error s!"no fixture for {dep.modPath}@{dep.version} (simulated transport failure)")
  | some name => pure (Zip.readZip (← IO.FS.readBinFile s!"{dir}/{name}"))

/-- The `Hash1` of a fixture zip's entries — the expected `cue.sum` value for that module. -/
def fixtureH1 (dir : String) (name : String) : IO Hash1 := do
  match Zip.readZip (← IO.FS.readBinFile s!"{dir}/{name}") with
  | .ok entries => pure (Sha256.hash1 entries)
  | .error _ => pure (Hash1.parse "h1:ERR")

def isErr {α : Type} (r : Except String α) : Bool :=
  match r with | .error _ => true | .ok _ => false

def expect (name : String) (ok : Bool) (allOk : Bool) : IO Bool := do
  if ok then IO.println s!"  ok: {name}" ; pure allOk
  else IO.eprintln s!"  FAIL: {name}" ; pure false

/-- Write a main module.cue declaring the given deps into a fresh importer root. -/
def writeMain (root : System.FilePath) (depsBlock : String) : IO Unit := do
  IO.FS.createDirAll (root / "cue.mod")
  IO.FS.writeFile (root / "cue.mod" / "module.cue")
    s!"module: \"app.example@v0\"\nlanguage: version: \"v0.15.4\"\n{depsBlock}"

def main (args : List String) : IO UInt32 := do
  match args with
  | [dir] => do
    let mut allOk := true
    let fetch := fixtureFetcher dir
    let tmpRoot : System.FilePath := s!"{dir}/.tidy-tmp"

    -- === Diamond: main → A,B ; A → C@v1.2.0 ; B → C@v1.3.0 ; MVS selects C@v1.3.0 ===
    let importer := tmpRoot / "diamond"
    writeMain importer
      "deps: {\n\t\"a.example/a@v0\": v: \"v1.0.0\"\n\t\"b.example/b@v0\": v: \"v1.0.0\"\n}\n"
    match ← ModCmd.runTidy importer fetch with
    | .error e => allOk ← expect s!"diamond tidy succeeds (got error: {e})" false allOk
    | .ok res =>
        let expectedBuild : List ModuleVersion :=
          [⟨"app.example", ""⟩, ⟨"a.example/a", "v1.0.0"⟩, ⟨"b.example/b", "v1.0.0"⟩,
           ⟨"c.example/c", "v1.3.0"⟩]
        allOk ← expect "build list = [main, A, B, C@v1.3.0] (max-of-mins picks C v1.3.0)"
          (res.buildList == expectedBuild) allOk
        -- cue.sum written and re-parses to the three selected deps.
        let sumText ← IO.FS.readFile (importer / "cue.sum")
        let parsed := Kue.parseCueSumText sumText
        let h1a ← fixtureH1 dir "a.zip"
        let h1b ← fixtureH1 dir "b.zip"
        let h1c ← fixtureH1 dir "c-1.3.0.zip"
        let expectedSum : List (String × Hash1) :=
          [("a.example/a@v1.0.0", h1a), ("b.example/b@v1.0.0", h1b), ("c.example/c@v1.3.0", h1c)]
        allOk ← expect "cue.sum contains A, B, C@v1.3.0 with correct h1: digests"
          (parsed == expectedSum) allOk
        -- The UNSELECTED C@v1.2.0 must NOT appear in cue.sum.
        allOk ← expect "cue.sum excludes the unselected C@v1.2.0"
          (!(parsed.any (fun p => p.fst == "c.example/c@v1.2.0"))) allOk

    -- === Empty deps: build list is just main, cue.sum is empty ===
    let emptyRoot := tmpRoot / "empty"
    writeMain emptyRoot ""
    match ← ModCmd.runTidy emptyRoot fetch with
    | .error e => allOk ← expect s!"empty-deps tidy succeeds (got error: {e})" false allOk
    | .ok res =>
        allOk ← expect "empty deps ⇒ build list is just the main module"
          (res.buildList == [⟨"app.example", ""⟩]) allOk
        let sumText ← IO.FS.readFile (emptyRoot / "cue.sum")
        allOk ← expect "empty deps ⇒ empty cue.sum" (sumText == "") allOk

    -- === Transport failure: an undeclared/unfetchable dep errors cleanly ===
    let failRoot := tmpRoot / "fail"
    writeMain failRoot "deps: {\n\t\"z.example/z@v0\": v: \"v9.9.9\"\n}\n"
    let failRes ← ModCmd.runTidy failRoot fetch
    allOk ← expect "unfetchable dependency ⇒ typed error (no partial cue.sum)" (isErr failRes) allOk

    -- === Malformed dependency module.cue errors cleanly ===
    let badRoot := tmpRoot / "bad"
    writeMain badRoot "deps: {\n\t\"bad.example/bad@v0\": v: \"v1.0.0\"\n}\n"
    let badFetch : ModCmd.EntryFetcher := fun dep =>
      if dep.modPath == "bad.example/bad" then
        do pure (Zip.readZip (← IO.FS.readBinFile s!"{dir}/malformed.zip"))
      else fetch dep
    let badRes ← ModCmd.runTidy badRoot badFetch
    allOk ← expect "malformed dependency module.cue ⇒ typed error" (isErr badRes) allOk

    IO.FS.removeDirAll tmpRoot
    if allOk then IO.println "mod tidy pipeline ok" ; pure 0
    else IO.eprintln "mod tidy pipeline FAILED" ; pure 1
  | _ =>
    IO.eprintln "usage: lake env lean --run scripts/check-mod-tidy.lean <testdata/ocifetch/modtidy dir>"
    pure 1
