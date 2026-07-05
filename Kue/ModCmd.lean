import Kue.Module
import Kue.Mvs
import Kue.Semver
import Kue.Sha256
import Kue.Zip

/-!
# `cue mod get` / `cue mod tidy` command layer (B3d-6b)

The module-management commands, carved out of `Kue/Module.lean` (whose import-resolution IO edge
is a distinct responsibility). `mod tidy` builds the real requirement graph by fetching each
transitive dependency's `cue.mod/module.cue` over the read-only registry GET, runs the pure MVS
solver (`Kue/Mvs.lean`) to select versions (max-of-mins), and WRITES `cue.sum` with the verified
`h1:` digests. `mod get` resolves + verifies a single module@version.

The registry egress is READ-ONLY (GET each dep's module.cue); `cue.sum` is a LOCAL file write.
Everything routes through an injected `EntryFetcher` so the whole pipeline is exercised OFFLINE
against `file://`-style fixtures (a fetcher that reads committed zips) — the production fetcher
(`ociEntryFetcher`) is the only network user, and no gate depends on it.
-/

namespace Kue
namespace ModCmd

open Kue (Dep)

/-! ## Pure requirement-graph assembly -/

/-- A `Dep` (module path + pinned version) as an MVS `ModuleVersion` graph node. -/
def depToMV (dep : Dep) : Registry.ModuleVersion := ⟨dep.modPath, dep.version⟩

/-- Assemble an MVS requirement graph from per-module dep tables: each `(node, its direct deps)`
    becomes one graph edge `(node, deps-as-nodes)`. Pure — the transitive fetch produces the input. -/
def buildRequirementGraph (edges : List (Registry.ModuleVersion × List Dep)) :
    Mvs.RequirementGraph :=
  edges.map (fun (node, deps) => (node, deps.map depToMV))

/-- Read the `deps` table out of a module's zip entries: find the `cue.mod/module.cue` entry,
    decode + parse it, and read its dependency table via the shared `parseDeps`. A missing entry,
    invalid UTF-8, or a parse error is a typed error. -/
def depsFromEntries (entries : List (String × ByteArray)) : Except String (List Dep) :=
  match entries.find? (fun e => e.fst == "cue.mod/module.cue") with
  | none => .error "module zip has no cue.mod/module.cue entry"
  | some (_, bytes) =>
      match String.fromUTF8? bytes with
      | none => .error "cue.mod/module.cue is not valid UTF-8"
      | some text =>
          match parseSource text with
          | .error e => .error s!"cue.mod/module.cue parse error: {e.message}"
          | .ok value => .ok (parseDeps value)

/-- The `(path, version, h1)` `cue.sum` rows for a solved build list: each FETCHED node the build
    list selected (excluding the main module), paired with the `h1:` digest recorded when it was
    fetched. Rows are derived FROM the fetched nodes — each of which carries its own digest — so
    every row inherently has an `h1`; a selected version is a fetched node by construction (MVS only
    selects versions present in the graph, and the graph is built from these very nodes), so there is
    no build-list entry without a digest to drop. `cue.sum` is order-independent (`formatCueSum`
    sorts). Pure. -/
def cueSumRows (main : Registry.ModuleVersion) (buildList : List Registry.ModuleVersion)
    (nodes : List (Registry.ModuleVersion × (List Dep × String))) :
    List (String × String × String) :=
  nodes.filterMap fun (node, _, h1) =>
    if node.basePath != main.basePath && buildList.contains node then
      some (node.basePath, node.version, h1)
    else none

/-! ## IO edge — transitive graph fetch + cue.sum write -/

/-- Fetch a single dependency's module zip entries. Injected so the offline gate drives committed
    fixtures while production uses `ociEntryFetcher`. -/
abbrev EntryFetcher := Dep → IO (Except String (List (String × ByteArray)))

/-- Production entry-fetcher: resolve `dep` to its OCI ref via `CUE_REGISTRY`, fetch the
    digest-verified module zip (auth-capable via B3d-7), and unzip + CRC-verify it. A READ-ONLY
    registry GET. -/
def ociEntryFetcher (cueRegistry : String) : EntryFetcher := fun dep => do
  match Registry.resolveFromConfig cueRegistry dep.modPath dep.version with
  | .error e => pure (.error s!"invalid CUE_REGISTRY: {e}")
  | .noRegistry => pure (.error s!"cannot fetch {dep.modPath}@{dep.version}: registry is `none`")
  | .found ref =>
      match ← OciFetch.fetchModuleZip ref with
      | .error e => pure (.error e)
      | .ok zipBytes => pure (Zip.readZip zipBytes)

/-- Transitively fetch each dependency's `cue.mod/module.cue`, accumulating `(node, (deps, h1))`
    for every reachable module. Fuel-bounded BFS over the module graph, visited-guarded, so a
    cycle terminates and no `partial` is needed. `fuel` bounds total worklist steps; exhaustion is
    a typed error (a pathologically large/cyclic graph). Structural on `fuel`. -/
def fetchGraphAux (fetch : EntryFetcher) :
    Nat → List Dep → List Registry.ModuleVersion →
    List (Registry.ModuleVersion × (List Dep × String)) →
    IO (Except String (List (Registry.ModuleVersion × (List Dep × String))))
  | 0, _, _, _ =>
      pure (.error "requirement-graph fetch exceeded fuel (graph too large or cyclic)")
  | _, [], _, acc => pure (.ok acc)
  | fuel + 1, dep :: rest, visited, acc =>
      let node := depToMV dep
      if visited.contains node then
        fetchGraphAux fetch fuel rest visited acc
      else do
        match ← fetch dep with
        | .error e => pure (.error s!"fetch {dep.modPath}@{dep.version} failed: {e}")
        | .ok entries =>
            match depsFromEntries entries with
            | .error e => pure (.error s!"{dep.modPath}@{dep.version}: {e}")
            | .ok deps =>
                fetchGraphAux fetch fuel (deps ++ rest) (node :: visited)
                  (acc ++ [(node, (deps, Sha256.hash1 entries))])

/-- The fuel budget for the transitive fetch: a generous total-step bound so any realistic module
    graph completes and only a pathological one trips the guard. -/
def fetchFuel : Nat := 100000

/-- Build the full `(node, (deps, h1))` table for a main module + its declared deps: seed the main
    node (its `h1` unused — main is never a `cue.sum` entry), then transitively fetch every
    dependency's module.cue. -/
def fetchGraph (fetch : EntryFetcher) (main : Registry.ModuleVersion) (mainDeps : List Dep) :
    IO (Except String (List (Registry.ModuleVersion × (List Dep × String)))) := do
  match ← fetchGraphAux fetch fetchFuel mainDeps [main] [] with
  | .error e => pure (.error e)
  | .ok depNodes => pure (.ok ((main, (mainDeps, "")) :: depNodes))

/-- Atomically write `entries` to `<root>/cue.sum` (via `Module.atomicWriteBinFile`). -/
def writeCueSum (root : System.FilePath) (entries : List (String × String × String)) : IO Unit :=
  atomicWriteBinFile (root / "cue.sum") (formatCueSum entries).toUTF8

/-- The result of `mod tidy`: the MVS build list (main first, then each selected dependency) and
    the `cue.sum` rows written. -/
structure TidyResult where
  buildList : List Registry.ModuleVersion
  sumRows : List (String × String × String)
deriving Repr

/-- Run `cue mod tidy` for the module rooted at `root`, using `fetch` for registry GETs: read the
    main module's declared deps, transitively fetch the requirement graph, run the CHECKED MVS
    solver (`solveChecked` — a dep requiring a higher version of the main module's own path is a
    typed error, not a silent pin), then WRITE `cue.sum` with the build list's `h1:` digests.
    Returns the build list + written rows. Total `IO (Except …)`. The main module's own version is
    the empty sentinel (it is the MVS target, has no semver). -/
def runTidy (root : System.FilePath) (fetch : EntryFetcher) :
    IO (Except String TidyResult) := do
  match ← readModuleInfo root with
  | .error e => pure (.error e)
  | .ok (modPath, deps) =>
      let main : Registry.ModuleVersion := ⟨modPath, ""⟩
      match ← fetchGraph fetch main deps with
      | .error e => pure (.error e)
      | .ok nodes =>
          let graph := buildRequirementGraph (nodes.map (fun n => (n.fst, n.snd.fst)))
          match Mvs.solveChecked main graph with
          | .error e => pure (.error e)
          | .ok buildList =>
              let rows := cueSumRows main buildList nodes
              writeCueSum root rows
              pure (.ok { buildList, sumRows := rows })

end ModCmd
end Kue
