import Kue.Module
import Kue.Mvs
import Kue.Oci
import Kue.OciFetch
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
    (nodes : List (Registry.ModuleVersion × (List Dep × Hash1))) :
    List (String × String × Hash1) :=
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
    for every reachable module. A thin `Module.bfsRequirementGraphAux` call site: fuel-bounded BFS
    over the module graph, visited-guarded, so a cycle terminates and no `partial` is needed. `fuel`
    bounds total worklist steps; exhaustion is a typed error (a pathologically large/cyclic graph).
    The disk-side twin is `Module.buildDiskGraphAux`. -/
def fetchGraphAux (fetch : EntryFetcher) (fuel : Nat) (worklist : List Dep)
    (visited : List Registry.ModuleVersion)
    (acc : List (Registry.ModuleVersion × (List Dep × Hash1))) :
    IO (Except String (List (Registry.ModuleVersion × (List Dep × Hash1)))) :=
  bfsRequirementGraphAux
    (nodeOf := depToMV)
    (expand := fun dep => do
      match ← fetch dep with
      | .error e => pure (.error s!"fetch {dep.modPath}@{dep.version} failed: {e}")
      | .ok entries =>
          match depsFromEntries entries with
          | .error e => pure (.error s!"{dep.modPath}@{dep.version}: {e}")
          | .ok deps => pure (.ok (deps, (deps, Sha256.hash1 entries))))
    (fuelExhausted := "requirement-graph fetch exceeded fuel (graph too large or cyclic)")
    fuel worklist visited acc

/-- The fuel budget for the transitive fetch: a generous total-step bound so any realistic module
    graph completes and only a pathological one trips the guard. -/
def fetchFuel : Nat := 100000

/-- The `(node, (deps, h1))` table for a main module's transitive dependencies: seed the walk with
    `main` visited (so it is never fetched — it is not a registry artifact and has no digest) and its
    declared deps as the worklist. Every returned node is a FETCHED dependency, so each carries a real
    `Hash1`; the main module is deliberately absent (`runTidy` supplies main's own graph edge). This
    is what keeps the digest table honest — no sentinel digest for a node that never had one. -/
def fetchGraph (fetch : EntryFetcher) (main : Registry.ModuleVersion) (mainDeps : List Dep) :
    IO (Except String (List (Registry.ModuleVersion × (List Dep × Hash1)))) :=
  fetchGraphAux fetch fetchFuel mainDeps [main] []

/-- Atomically write `entries` to `<root>/cue.sum` (via `Module.atomicWriteBinFile`). -/
def writeCueSum (root : System.FilePath) (entries : List (String × String × Hash1)) : IO Unit :=
  atomicWriteBinFile (root / "cue.sum") (formatCueSum entries).toUTF8

/-- The result of `mod tidy`: the MVS build list (main first, then each selected dependency) and
    the `cue.sum` rows written. -/
structure TidyResult where
  buildList : List Registry.ModuleVersion
  sumRows : List (String × String × Hash1)
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
      | .ok depNodes =>
          -- `fetchGraph` returns only fetched deps; add the main module's own graph edge here (it
          -- has no digest, so it never belonged in the `cue.sum` node table).
          let graph := buildRequirementGraph ((main, deps) :: depNodes.map (fun n => (n.fst, n.snd.fst)))
          match Mvs.solveChecked main graph with
          | .error e => pure (.error e)
          | .ok buildList =>
              let rows := cueSumRows main buildList depNodes
              writeCueSum root rows
              pure (.ok { buildList, sumRows := rows })

/-! ## `cue mod get` — the deps-block emitter + tag "latest" resolution (B3d-6b-leg2)

`cue mod get <module>[@version]` adds or updates a dependency in `cue.mod/module.cue`. Two pure
capabilities plus one IO edge:

- **Deps-block emitter** — parse the existing module.cue for its deps, merge the target dep in
  (keyed on module path + major version, so distinct majors coexist), then re-render ONLY the
  `deps` block in cue's canonical tab-indented form, splicing it back in place of any existing
  block. Non-deps content is preserved verbatim (kue does NOT reformat the whole file the way
  `cue mod get` does — see `cue-spec-gaps.md`), so unknown/`source:`/comment content is never
  lost. Illegal-states-unrepresentable: if a deps field is present in the parse but the textual
  excision cannot locate it, we ERROR rather than emit a file with two conflicting deps blocks.
- **Tag "latest" resolution** — a bare `get <mod>`, `@latest`, or a partial `@v1`/`@v1.2`
  constraint resolves against the registry's `.../tags/list` (read-only) by filtering to valid
  NON-prerelease semver tags matching the constraint and taking the max (`Semver.maxVersion`).
- **IO edge** — `ociListTags` performs the read-only tags/list GET; the pure driver
  (`modGetResolveAndApply`) takes an in-memory tag list, so the whole resolve+emit pipeline is
  `native_decide`-checkable OFFLINE (no gate depends on the network).
-/

/-! ### Deps-block emitter (pure) -/

/-- The `deps` key CUE writes for a dependency: `"<modpath>@v<major>"`, the major being the parsed
    semver major of `version`. `none` when `version` is not a valid semver. -/
def depKey (modPath version : String) : Option String :=
  (Semver.parse version).map (fun p => s!"{modPath}@v{p.major}")

/-- `depKey` with a degenerate fall-back to the bare path (only reached for a non-semver version,
    which the caller rejects up front) — total, for use where a `String` key is required. -/
def depKeyOrPath (dep : Dep) : String :=
  (depKey dep.modPath dep.version).getD dep.modPath

/-- Add `target` to `existing`, or update the entry sharing its `deps` key (same module path AND
    major) in place; distinct majors of one path coexist as separate entries. Render sorts, so the
    append position is immaterial. -/
def mergeDep (existing : List Dep) (target : Dep) : List Dep :=
  let key := depKeyOrPath target
  if existing.any (fun d => depKeyOrPath d == key) then
    existing.map (fun d => if depKeyOrPath d == key then target else d)
  else
    existing ++ [target]

/-- One canonical `deps` entry, tab-indented exactly as cue v0.16.1 emits it:
    `\t"<key>": {\n\t\tv: "<version>"\n\t}\n`. -/
def renderDepEntry (key version : String) : String :=
  "\t\"" ++ key ++ "\": {\n\t\tv: \"" ++ version ++ "\"\n\t}\n"

/-- Render the whole `deps: { … }` block from `deps`, keys sorted ascending (cue's order). Empty
    `deps` still renders `deps: {\n}\n` (a get always supplies ≥1, so this is a defensive case). -/
def renderDepsBlock (deps : List Dep) : String :=
  let keyed := deps.map (fun d => (depKeyOrPath d, d.version))
  let sorted := (keyed.toArray.qsort (fun a b => a.fst < b.fst)).toList
  "deps: {\n" ++ String.join (sorted.map (fun (k, v) => renderDepEntry k v)) ++ "}\n"

/-- Whether the parsed module value carries a top-level field named `name`. -/
def hasTopLevelField : Value → String → Bool
  | .struct fields _ _ _ _, name => fields.any (fun f => f.label == name)
  | _, _ => false

/-- An identifier-continuation char, for token-boundary checks (`deps` vs `depsfoo`). -/
def isNameCont (c : Char) : Bool := c.isAlphanum || c == '_' || c == '$'

/-- Drop leading whitespace (space/tab/newline/CR). Structural. -/
def dropWs : List Char → List Char
  | c :: rest => if c == ' ' || c == '\t' || c == '\n' || c == '\r' then dropWs rest else c :: rest
  | [] => []

/-- Drop the leading identifier token (a run of name-continuation chars). Structural. -/
def dropName : List Char → List Char
  | c :: rest => if isNameCont c then dropName rest else c :: rest
  | [] => []

/-- Whether `chars` begins a top-level `deps` field: the token `deps` (a complete token — the next
    char is not name-continuation), then `:`, then `{`, whitespace-tolerant between. Pure
    lookahead. -/
def startsDepsField (chars : List Char) : Bool :=
  match chars with
  | 'd' :: 'e' :: 'p' :: 's' :: rest =>
      let boundary := match rest with | c :: _ => !isNameCont c | [] => true
      if !boundary then false
      else match dropWs rest with
        | ':' :: r2 => match dropWs r2 with | '{' :: _ => true | _ => false
        | _ => false
  | _ => false

/-- Lexer state for the module.cue textual scanners: normal code, inside a `"…"` string (tracking
    whether the last char was the escape `\`), or inside a `//` line comment. A sum type so the
    nonsense combination (escaped while not in a string) is unrepresentable, and so braces/quotes
    inside a string OR a line comment are inert to the brace scanner. Block comments (`/* */`) are
    not part of CUE, so a module.cue carrying one is rejected upstream at `parseSource` before any
    textual scan runs — there is no block state to track. -/
inductive Lex where
  | normal
  | str (escaped : Bool)
  | line

/-- Drop a balanced `{ … }` starting AT the `{`; return the remainder AFTER the matching `}`.
    String- and comment-aware (`"…"` with `\` escapes, `//` line comments; braces/quotes inside a
    string or line comment are inert) and brace-nested. Fuel-bounded; exhaustion returns `[]`. -/
def dropBalanced : Nat → Nat → Lex → List Char → List Char
  | 0, _, _, rest => rest
  | _, _, _, [] => []
  | fuel + 1, depth, .str escaped, c :: rest =>
      if escaped then dropBalanced fuel depth (.str false) rest
      else if c == '\\' then dropBalanced fuel depth (.str true) rest
      else if c == '"' then dropBalanced fuel depth .normal rest
      else dropBalanced fuel depth (.str false) rest
  | fuel + 1, depth, .line, c :: rest =>
      dropBalanced fuel depth (if c == '\n' then .normal else .line) rest
  | fuel + 1, depth, .normal, c :: rest =>
      match c, rest with
      | '/', '/' :: r2 => dropBalanced fuel depth .line r2
      | '"', _ => dropBalanced fuel depth (.str false) rest
      | '{', _ => dropBalanced fuel (depth + 1) .normal rest
      | '}', _ => if depth ≤ 1 then rest else dropBalanced fuel (depth - 1) .normal rest
      | _, _ => dropBalanced fuel depth .normal rest

/-- Given `chars` at the start of a top-level `deps` field, return the remainder AFTER the whole
    `deps: { … }` block and one trailing newline. -/
def afterDepsField (chars : List Char) : List Char :=
  let atBrace := dropWs (dropColon (dropWs (dropName chars)))
  dropNewline (dropBalanced (chars.length + 1) 0 .normal atBrace)
where
  dropColon : List Char → List Char
    | ':' :: r => r
    | r => r
  dropNewline : List Char → List Char
    | '\n' :: r => r
    | r => r

/-- The excision fold: walk `chars`, copying to `acc`, tracking brace depth + lexer state, and when
    a top-level (`depth == 0`, line-start) `deps` field starts, skip its whole block. Line comments
    are copied verbatim but their braces/quotes are inert (so a `}` in a comment cannot mis-close the
    deps block or a top-level brace). Returns the source with any top-level `deps` block removed,
    and whether one was found. Fuel-bounded. -/
def exciseAux : Nat → Nat → Lex → Bool → List Char → List Char → Bool → (List Char × Bool)
  | 0, _, _, _, rest, acc, found => (acc.reverse ++ rest, found)
  | _, _, _, _, [], acc, found => (acc.reverse, found)
  | fuel + 1, depth, .str escaped, _, c :: rest, acc, found =>
      if escaped then exciseAux fuel depth (.str false) false rest (c :: acc) found
      else if c == '\\' then exciseAux fuel depth (.str true) false rest (c :: acc) found
      else if c == '"' then exciseAux fuel depth .normal false rest (c :: acc) found
      else exciseAux fuel depth (.str false) false rest (c :: acc) found
  | fuel + 1, depth, .line, _, c :: rest, acc, found =>
      exciseAux fuel depth (if c == '\n' then .normal else .line) (c == '\n') rest (c :: acc) found
  | fuel + 1, depth, .normal, atLineStart, c :: rest, acc, found =>
      if depth == 0 && atLineStart && startsDepsField (c :: rest) then
        exciseAux fuel 0 .normal true (afterDepsField (c :: rest)) acc true
      else
        match c, rest with
        | '/', '/' :: r2 => exciseAux fuel depth .line false r2 ('/' :: '/' :: acc) found
        | '"', _ => exciseAux fuel depth (.str false) false rest (c :: acc) found
        | '{', _ => exciseAux fuel (depth + 1) .normal false rest (c :: acc) found
        | '}', _ => exciseAux fuel (depth - 1) .normal false rest (c :: acc) found
        | '\n', _ => exciseAux fuel depth .normal true rest (c :: acc) found
        | ' ', _ => exciseAux fuel depth .normal atLineStart rest (c :: acc) found
        | '\t', _ => exciseAux fuel depth .normal atLineStart rest (c :: acc) found
        | _, _ => exciseAux fuel depth .normal false rest (c :: acc) found

/-- Remove the top-level `deps: { … }` field from module.cue `source`, string/comment/brace-aware.
    Returns `(source-without-deps, wasFound)`. -/
def exciseTopLevelDeps (source : String) : String × Bool :=
  let cs := source.toList
  let (kept, found) := exciseAux (cs.length + 1) 0 .normal true cs [] false
  (String.ofList kept, found)

/-- Drop trailing whitespace (spaces, tabs, newlines) from `s` — so the rendered deps block joins
    onto the preceding content with exactly one separating newline. -/
def trimTrailingWs (s : String) : String :=
  String.ofList (s.toList.reverse.dropWhile
    (fun c => c == ' ' || c == '\t' || c == '\n' || c == '\r')).reverse

/-- Apply `cue mod get`'s edit to module.cue `source`: parse for existing deps, merge `target` in,
    and re-render the deps block, preserving all other content. `target.version` must be a concrete
    valid semver (resolution happened upstream). Errors — never a malformed file — on an unparseable
    source, an invalid target version, or a deps field the textual excision cannot locate. -/
def applyModGet (source : String) (target : Dep) : Except String String :=
  if !Semver.isValid target.version then
    .error s!"mod get: not a valid version: {target.version}"
  else match parseSource source with
    | .error e => .error s!"cue.mod/module.cue parse error: {e.message}"
    | .ok value =>
        let existing := parseDeps value
        let hadDeps := hasTopLevelField value "deps"
        let (stripped, found) := exciseTopLevelDeps source
        if hadDeps && !found then
          .error "cue.mod/module.cue: cannot locate the top-level deps block to update \
            (reformat it with `cue fmt` and retry)"
        else
          let merged := mergeDep existing target
          let base := trimTrailingWs stripped
          .ok (base ++ (if base.isEmpty then "" else "\n") ++ renderDepsBlock merged)

/-! ### Tag "latest" resolution (pure) -/

/-- A parsed `@version` constraint from a `cue mod get` argument. `latest` = the max non-prerelease
    tag; `exact` = a fully-pinned version (no tag lookup); `major`/`majorMinor` = the max
    non-prerelease tag under that prefix. -/
inductive VerSpec where
  | latest
  | exact (v : String)
  | major (m : String)
  | majorMinor (m minor : String)
deriving Repr, BEq, DecidableEq

/-- Parse a `@version` suffix (the text after `@`) into a `VerSpec`. `latest` is literal; a `v`-led
    version with a prerelease/build tail, or a full `vX.Y.Z`, is `exact`; `vX` / `vX.Y` are the
    partial major/major-minor constraints. `none` when it is not a recognizable version. -/
def parseVerSpec (s : String) : Option VerSpec :=
  if s == "latest" then some .latest
  else if !s.startsWith "v" then none
  else if (Semver.parse s).isNone then none
  else if s.any (fun c => c == '-' || c == '+') then some (.exact s)
  else match (s.drop 1).toString.splitOn "." with
    | [m] => some (.major m)
    | [m, minor] => some (.majorMinor m minor)
    | _ => some (.exact s)

/-- The max semver in `versions` (`Semver.maxVersion`-fold); `none` on an empty list. -/
def maxVersionOf : List String → Option String
  | [] => none
  | v :: rest => some (rest.foldl (fun acc x => Semver.maxVersion acc x) v)

/-- Resolve a `VerSpec` to a concrete version against the registry `tags`: `exact` is returned
    as-is (validated); the others filter `tags` to valid NON-prerelease semver matching the
    constraint and take the max. A no-match is a typed error. -/
def resolveVerSpec (spec : VerSpec) (tags : List String) : Except String String :=
  match spec with
  | .exact v => .ok v
  | .latest => pick (fun _ => true) "any release"
  | .major m => pick (fun p => p.major == m) s!"major v{m}"
  | .majorMinor m minor =>
      pick (fun p => p.major == m && p.minor == minor) s!"v{m}.{minor}"
where
  pick (keep : Semver.Parsed → Bool) (desc : String) : Except String String :=
    let cands := tags.filter fun t =>
      match Semver.parse t with
      | some p => p.prerelease.isEmpty && keep p
      | none => false
    match maxVersionOf cands with
    | some v => .ok v
    | none => .error s!"mod get: no non-prerelease version matching {desc} in the registry tag list"

/-- Split a `cue mod get` argument into `(modulePath, versionConstraint?)` on the first `@` (a
    module path never contains `@` — the major suffix is a separate concern). -/
def splitModuleArg (arg : String) : String × Option String :=
  match arg.splitOn "@" with
  | [p] => (p, none)
  | p :: rest => (p, some (String.intercalate "@" rest))
  | [] => (arg, none)

/-- The pure core of `cue mod get`: given the current module.cue `source`, the raw `<module>[@ver]`
    argument, and the registry `tags`, resolve the concrete version and produce the new module.cue
    text. Returns `(resolvedVersion, newSource)`. Fully offline — the network only supplies `tags`. -/
def modGetResolveAndApply (source arg : String) (tags : List String) :
    Except String (String × String) := do
  let (modPath, verArg) := splitModuleArg arg
  if modPath.isEmpty then .error "mod get: empty module path"
  else
    let spec ←
      match verArg with
      | none => .ok VerSpec.latest
      | some v =>
          match parseVerSpec v with
          | some s => .ok s
          | none => .error s!"mod get: unrecognized version constraint: @{v}"
    let concrete ← resolveVerSpec spec tags
    let newSource ← applyModGet source { modPath, version := concrete }
    .ok (concrete, newSource)

/-! ### IO edge — read-only tags/list GET (production only; no gate depends on it) -/

/-- Parse a `.../tags/list` response body (`{"tags": […]}`) into the tag list. Total over
    `Lean.Json.parse`. -/
def parseTagsList (text : String) : Except String (List String) := do
  let json ← Lean.Json.parse text
  let arr ← (← json.getObjVal? "tags").getArr?
  arr.toList.mapM (fun j => j.getStr?)

/-- List a module's tags via the read-only OCI `.../tags/list` GET (auth-capable via B3d-7). Only
    the production `mod get` path calls this; the offline gate drives `modGetResolveAndApply` with
    in-memory tags. -/
def ociListTags (cueRegistry modPath : String) : IO (Except String (List String)) := do
  match Registry.resolveFromConfig cueRegistry modPath "v0.0.0" with
  | .error e => pure (.error s!"invalid CUE_REGISTRY: {e}")
  | .noRegistry => pure (.error s!"cannot list tags for {modPath}: registry is `none`")
  | .found ref => do
      let cache ← OciFetch.TokenCache.fresh
      match ← OciFetch.authedGet cache ref.host (Oci.tagsListUrl ref) [] with
      | .error e => pure (.error e)
      | .ok bytes =>
          match String.fromUTF8? bytes with
          | none => pure (.error "tags/list response is not valid UTF-8")
          | some text => pure (parseTagsList text)

/-- Run `cue mod get <arg>` for the module rooted at `root`: read module.cue, fetch the registry
    tag list only when resolution needs it (a full `@vX.Y.Z` skips the network), resolve + emit via
    the pure core, then atomically write the updated module.cue. Returns the resolved
    `(modulePath, version)`. -/
def runModGet (root : System.FilePath) (arg cueRegistry : String) :
    IO (Except String (String × String)) := do
  let (modPath, verArg) := splitModuleArg arg
  let modFile := root / "cue.mod" / "module.cue"
  let source ← IO.FS.readFile modFile
  let needTags :=
    match verArg with
    | none => true
    | some v => match parseVerSpec v with | some (.exact _) => false | _ => true
  let tagsE ← if needTags then ociListTags cueRegistry modPath else pure (.ok [])
  match tagsE with
  | .error e => pure (.error e)
  | .ok tags =>
      match modGetResolveAndApply source arg tags with
      | .error e => pure (.error e)
      | .ok (version, newSource) => do
          atomicWriteBinFile modFile newSource.toUTF8
          pure (.ok (modPath, version))

end ModCmd
end Kue
