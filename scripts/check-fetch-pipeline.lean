import Kue.Module
import Kue.OciFetch
import Kue.Registry
import Kue.Sha256
import Kue.Zip

/-!
# Fetch → extract → cache-write → read-path pipeline check (B3d-5, offline)

Drives the B3d-5 wiring (`Kue.fetchAndCacheModule`) end to end WITHOUT a network: the `fetchZip`
step is a `file://`-equivalent reader over the committed `testdata/ocifetch/pipeline/module.zip`
(a real DEFLATE cue module zip for `lib.example/defs@v0.1.0`), and `CUE_CACHE_DIR` (set by the
shell wrapper to a repo-local temp dir) is where the cache-write lands — never the real
`~/Library/Caches/cue`. Proves: fetch → `readZip` → cache-write (download + extract layout) →
`locateModuleDir` finds the installed module; plus the integrity gate (a wrong `cue.sum` `h1:`
rejects, a matching one passes), the failure modes (transport failure, `none` registry), and the
B3d-5a unification (the read-path's located dir equals `Registry.extractCachePath`).

Argv: <abs testdata/ocifetch/pipeline dir>. The cache dir comes from `CUE_CACHE_DIR` (Lean has no
`setEnv`, so the shell sets it). The negative cases run FIRST, against the same empty cache, and
each is asserted to error AND leave nothing locatable — so a successful write can only be the
positive case. Run by `scripts/check-fixtures.sh`. No network; the cache dir is removed by the
wrapper. Exit 0 ⇒ all assertions pass.
-/

open Kue

/-- The dependency the fixture zip installs: `lib.example/defs@v0.1.0`. -/
def fixtureDep : Dep := { modPath := "lib.example/defs", version := "v0.1.0" }

/-- A `file://`-equivalent stand-in for `OciFetch.fetchModuleZip`: read the fixture zip bytes off
    disk (the OCI URL shape can't be a `file://`), so the cache-write + read-path is exercised
    offline. The bytes are the SAME verified zip the real fetch returns. -/
def fileZipFetcher (zipPath : String) : Registry.OciRef → IO (Except String ByteArray) :=
  fun _ => do pure (Except.ok (← IO.FS.readBinFile zipPath))

/-- A fetcher that always fails — to prove a fetch failure surfaces cleanly. -/
def failingFetcher : Registry.OciRef → IO (Except String ByteArray) :=
  fun _ => do pure (Except.error "simulated transport failure")

def isErr (r : Except String System.FilePath) : Bool :=
  match r with | .error _ => true | .ok _ => false

def expect (name : String) (ok : Bool) (allOk : Bool) : IO Bool := do
  if ok then
    IO.println s!"  ok: {name}"
    pure allOk
  else
    IO.eprintln s!"  FAIL: {name}"
    pure false

def main (args : List String) : IO UInt32 := do
  match args with
  | [pipelineDir] => do
    let mut allOk := true
    let zipPath := s!"{pipelineDir}/module.zip"
    let tmpRoot : System.FilePath := s!"{pipelineDir}/.b3d5-tmp"
    let importerRoot := tmpRoot / "importer"
    IO.FS.createDirAll (importerRoot / "cue.mod")
    IO.FS.writeFile (importerRoot / "cue.mod" / "module.cue")
      "module: \"app.example\"\nlanguage: version: \"v0.15.4\"\n"

    let mv := Registry.mkModuleVersion fixtureDep.modPath fixtureDep.version

    -- === Negative cases first, against the still-empty cache ===

    -- registry `none` ⇒ a clean "cannot fetch" error (never a successful empty install).
    let noneResult ← fetchAndCacheModule "none" importerRoot fixtureDep failingFetcher
    allOk ← expect "registry `none` ⇒ cannot-fetch error" (isErr noneResult) allOk

    -- A transport failure surfaces cleanly (no partial install).
    IO.FS.writeFile (importerRoot / "cue.sum") ""
    let failResult ← fetchAndCacheModule "" importerRoot fixtureDep failingFetcher
    allOk ← expect "fetch transport failure ⇒ error" (isErr failResult) allOk

    -- cue.sum integrity gate: a WRONG recorded h1: rejects the install.
    IO.FS.writeFile (importerRoot / "cue.sum")
      s!"{fixtureDep.modPath} {fixtureDep.version} h1:0000000000000000000000000000000000000000000=\n"
    let badResult ← fetchAndCacheModule "" importerRoot fixtureDep (fileZipFetcher zipPath)
    allOk ← expect "cue.sum mismatch REJECTS the install (integrity gate)" (isErr badResult) allOk

    -- After every negative case the module must STILL be unlocatable (nothing was written).
    let afterNeg ← locateModuleDir importerRoot fixtureDep
    allOk ← expect "negative cases left nothing in the cache" afterNeg.isNone allOk

    -- === Positive case: a matching cue.sum, the real install ===

    let entries := (Zip.readZip (← IO.FS.readBinFile zipPath)).toOption.getD []
    let realSum := Sha256.hash1 entries
    IO.FS.writeFile (importerRoot / "cue.sum")
      s!"{fixtureDep.modPath} {fixtureDep.version} {realSum}\n"
    let installResult ← fetchAndCacheModule "" importerRoot fixtureDep (fileZipFetcher zipPath)
    let extractRoot := installResult.toOption.getD "/nonexistent"
    allOk ← expect "fetchAndCacheModule succeeds (fetch → verify h1: → cache-write)"
      installResult.toOption.isSome allOk
    allOk ← expect "extract root exists on disk after install" (← extractRoot.pathExists) allOk
    allOk ← expect "extracted cue.mod/module.cue present"
      (← (extractRoot / "cue.mod" / "module.cue").pathExists) allOk
    allOk ← expect "extracted widget.cue present"
      (← (extractRoot / "widget.cue").pathExists) allOk

    -- The raw verified zip landed in the download cache layout.
    let cacheRootDir ← cacheRoot
    let downloadPath := System.FilePath.mk
      (Registry.downloadCachePath ((cacheRootDir / "mod").toString) mv "zip")
    allOk ← expect "raw zip written to mod/download/.../@v/<ver>.zip"
      (← downloadPath.pathExists) allOk

    -- The read-path now finds the installed module.
    let located ← locateModuleDir importerRoot fixtureDep
    allOk ← expect "locateModuleDir finds the freshly-installed module" located.isSome allOk

    -- B3d-5a: the located dir equals Registry.extractCachePath (read-path == write-path
    -- authority), byte-identical for this lowercase module path.
    let authorityPath := Registry.extractCachePath ((cacheRootDir / "mod").toString) mv
    allOk ← expect "located dir == Registry.extractCachePath (B3d-5a unification)"
      (located == some (System.FilePath.mk authorityPath)) allOk

    -- Cleanup the importer subtree (the cache dir itself is the shell's to remove).
    IO.FS.removeDirAll tmpRoot

    if allOk then
      IO.println "fetch pipeline ok"
      pure 0
    else
      IO.eprintln "fetch pipeline FAILED"
      pure 1
  | _ =>
    IO.eprintln "usage: lake env lean --run scripts/check-fetch-pipeline.lean <testdata/ocifetch/pipeline dir>"
    pure 1
