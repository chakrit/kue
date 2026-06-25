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

/-- True when `dir` holds no `.tmp-` entry — proves the atomic publish left no orphan after a
    successful install. A missing `dir` trivially has none. -/
def noTmpDir (dir : System.FilePath) : IO Bool := do
  if !(← dir.pathExists) then
    pure true
  else
    let entries ← dir.readDir
    pure (entries.all fun e => !(e.fileName.startsWith ".tmp-"))

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

    -- B3d-A1 crash-window soundness: a leftover `.tmp-…` dir from an interrupted extract must
    -- NOT be mistaken for the real module. The `.tmp-` prefix excludes it from the exact
    -- `<esc>@<ver>` slot name `locateModuleDir` matches, so the read-path keys ONLY off the
    -- atomically-published slot. Confirm a partial `.tmp-…@…` sibling is ignored, and that no
    -- `.tmp-` dir lingers after the successful (atomic) install above.
    -- A crash leaves the exact temp shape `atomicExtractDir` builds: `.tmp-<slot-name>-<nonce>`
    -- in the slot's immediate parent (`extract/lib.example/`), where `<slot-name>` is the final
    -- dir's `fileName` (`defs@v0.1.0`) — NOT the full slashed module path.
    let slotName := (System.FilePath.mk authorityPath).fileName.getD "module"
    let extractParent := (System.FilePath.mk authorityPath).parent.getD (cacheRootDir / "mod")
    let partialTmp := extractParent / s!".tmp-{slotName}-crashnonce"
    IO.FS.createDirAll (partialTmp / "cue.mod")
    IO.FS.writeFile (partialTmp / "cue.mod" / "module.cue") "module: \"lib.example/defs\"\n"
    let stillSlot ← locateModuleDir importerRoot fixtureDep
    allOk ← expect "partial .tmp- extract dir is NOT loaded; locate still resolves the real slot"
      (stillSlot == some (System.FilePath.mk authorityPath)) allOk
    IO.FS.removeDirAll partialTmp

    -- Crash-window with NO real slot: a partial `.tmp-…` against an absent slot must leave the
    -- module unlocatable (no partial load), proving the read-path trusts only the published dir.
    let absentDep : Dep := { modPath := "lib.example/ghost", version := "v0.1.0" }
    let absentMv := Registry.mkModuleVersion absentDep.modPath absentDep.version
    let ghostSlotName := (System.FilePath.mk (Registry.extractCachePath ((cacheRootDir / "mod").toString) absentMv)).fileName.getD "module"
    let ghostParent := (System.FilePath.mk (Registry.extractCachePath ((cacheRootDir / "mod").toString) absentMv)).parent.getD (cacheRootDir / "mod")
    let ghostTmp := ghostParent / s!".tmp-{ghostSlotName}-crashnonce"
    IO.FS.createDirAll (ghostTmp / "cue.mod")
    IO.FS.writeFile (ghostTmp / "cue.mod" / "module.cue") "module: \"lib.example/ghost\"\n"
    let ghostLocated ← locateModuleDir importerRoot absentDep
    allOk ← expect "partial .tmp- dir for an ABSENT slot ⇒ module stays unlocatable (none)"
      ghostLocated.isNone allOk
    IO.FS.removeDirAll ghostTmp

    -- Idempotency / re-fetch: fetching when the final slot already exists must NOT crash on
    -- rename-over-existing — it discards the fresh temp and reuses the extant complete slot.
    let refetch ← fetchAndCacheModule "" importerRoot fixtureDep (fileZipFetcher zipPath)
    allOk ← expect "re-fetch over an existing slot succeeds (no rename-over-existing crash)"
      (refetch.toOption == some (System.FilePath.mk authorityPath)) allOk
    let afterRefetch ← locateModuleDir importerRoot fixtureDep
    allOk ← expect "slot still locatable + complete after re-fetch"
      (afterRefetch == some (System.FilePath.mk authorityPath)) allOk
    allOk ← expect "no lingering .tmp- dir after re-fetch"
      (← noTmpDir extractParent) allOk

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
