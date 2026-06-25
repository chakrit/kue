import Kue.Registry
import Kue.Semver

/-!
# Minimal Version Selection (B3d-6a, PURE)

A Lean-native, total port of Russ Cox's MVS — the algorithm `cue` (and Go) use to turn a module
requirement graph into a reproducible build list. PURE: the requirement graph is an explicit
finite value (no IO callback), so reachability and per-path maxima are deterministic and
termination is obvious.

Authoritative source (read-only, locally): cue v0.16.1
`internal/mod/mvs/{mvs.go,graph.go}` — `BuildList`/`buildList` (mvs.go) and `Graph.Require` /
`Graph.BuildList` / `Graph.sortVersions` (graph.go). The behaviours pinned here, mirroring it:

- **Selection = max of the mins.** For every module PATH reachable from the targets, the
  selected version is the MAXIMUM version that appears anywhere in the reachable graph
  (`Graph.Require`'s `selected[path] = max(selected[path], dep.version)`). "Minimal" names the
  per-requirement minimum each edge demands; MVS takes their max so all constraints hold while
  never jumping to "latest".
- **Reachability.** A node is in the graph iff it's transitively `Required` from a root; an
  unreachable module is excluded entirely. Cycles are legal and terminate (visited set).
- **Distinct majors are distinct PATHS.** `m` and `m/v2` carry different base paths, so they get
  independent `selected[path]` entries and coexist — never a conflict. (The caller encodes the
  major in the path, exactly as cue's `module.Version` does.)
- **Build-list order.** Target(s) first (the root paths' selected versions, in root order, deduped
  by path), then every other selected path sorted by `(path, version)` — `Graph.BuildList` +
  `sortVersions`, version tiebreak by the same `cmp` (semver `compare`).
- **Version comparison** is `Semver.compare`; the "none" bottom is modelled as the absence of a
  `selected` entry (a path with no requirement is simply not in the map).

Totality: graph is a finite `List`; the closure recurses on a `fuel` bound = node count, with a
visited set so cycles can't diverge. No `partial`, no `sorry`, no axioms.
-/

namespace Kue
namespace Mvs

open Kue.Registry (ModuleVersion)

/-- A requirement graph: each `ModuleVersion` maps to the list of modules it DIRECTLY requires
    (each with the minimum version that node demands). An explicit finite value — the entire
    graph is in hand, so MVS is a pure fold, not a network-driven traversal. A path may appear
    at several versions as distinct keys; that is the whole point (max-of-mins picks among them). -/
abbrev RequirementGraph := List (ModuleVersion × List ModuleVersion)

/-- Direct requirements of `mv` in `graph` (the FIRST matching key; a well-formed graph has at
    most one entry per `ModuleVersion`). A node absent from the graph requires nothing — it is a
    leaf, exactly like a module whose `module.cue` lists no deps. -/
def requiresOf (graph : RequirementGraph) (mv : ModuleVersion) : List ModuleVersion :=
  match graph.find? (fun (k, _) => k == mv) with
  | some (_, reqs) => reqs
  | none => []

/-- All distinct module@version nodes mentioned anywhere in the graph (keys + every requirement),
    used only as the fuel bound for the reachability closure. -/
def allNodes (graph : RequirementGraph) : List ModuleVersion :=
  (graph.flatMap (fun (k, reqs) => k :: reqs)).eraseDups

/-- Breadth-first reachable set from a worklist, accumulating visited nodes. `fuel` bounds the
    recursion (decremented each step); a node already in `visited` is skipped, so a cycle halts
    and the worklist shrinks to empty within `|allNodes|` expansions. Returns the visited set in
    discovery order. -/
def reachAux (graph : RequirementGraph) : Nat → List ModuleVersion → List ModuleVersion →
    List ModuleVersion
  | 0, _, visited => visited
  | _, [], visited => visited
  | fuel + 1, m :: rest, visited =>
    if visited.contains m then
      reachAux graph fuel rest visited
    else
      reachAux graph fuel (requiresOf graph m ++ rest) (visited ++ [m])

/-- The set of module@version nodes reachable from `targets` (inclusive), in discovery order.

    Fuel bounds TOTAL steps, not distinct expansions — a subtlety that bit the first version
    (fuel = `|allNodes| + |targets| + 1` silently TRUNCATED a high-fan-in graph, because each
    `m :: rest` step consumes fuel whether it expands or *skips* an already-visited node, and a
    node re-required by many parents is re-enqueued once per parent). Sound bound: let
    `N = |allNodes| + |targets|` over-approximate the distinct nodes ever visited. The worklist
    starts with `≤ N` items; each of the `≤ N` expansions appends `requiresOf` (`≤ |allNodes| ≤ N`
    items); so the total items ever enqueued — hence total pops/steps — is `≤ N + N·N ≤ (N+1)²`.
    Fuel `= (N+1)²` therefore cannot run out before the worklist drains, for ANY graph shape. -/
def reachable (graph : RequirementGraph) (targets : List ModuleVersion) : List ModuleVersion :=
  let n := (allNodes graph).length + targets.length + 1
  reachAux graph (n * n) targets []

/-- Fold a `path → max-version` association over the reachable nodes: for each node, keep the
    greater (by `Semver.compare`) of the version already recorded for its path and this node's
    version. The result is the selected version per path (`Graph.selected`). Represented as an
    assoc list keyed by `basePath`. -/
def selectMaxima (nodes : List ModuleVersion) : List (String × String) :=
  nodes.foldl (fun acc mv =>
    match acc.find? (fun (p, _) => p == mv.basePath) with
    | some _ =>
      acc.map (fun (p, v) =>
        if p == mv.basePath then (p, Semver.maxVersion v mv.version) else (p, v))
    | none => acc ++ [(mv.basePath, mv.version)]) []

/-- Sort non-root selections by `(path, version)` — path ascending (ASCII), version by
    `Semver.compare` as the tiebreak (`Graph.sortVersions`). Since each path appears once in the
    maxima, the version tiebreak is effectively unreachable, but it is included for fidelity. -/
def sortSelected (sel : List ModuleVersion) : List ModuleVersion :=
  sel.toArray.qsort (fun a b =>
    if a.basePath != b.basePath then a.basePath < b.basePath
    else Semver.compare a.version b.version < 0) |>.toList

/-- Solve MVS for a single main module. Returns the build list: `main` first, then the selected
    (max-of-mins) version of every OTHER reachable module path, sorted by `(path, version)`.

    `main`'s own path is pinned to `main` itself — cue requires the target to compare higher than
    any version of its path in the graph (`reqs.Max(target, v) == target`); we honour that by
    emitting `main.version` for `main.basePath` regardless of the maxima, and dropping the root
    path from the sorted remainder. Total: reachability and maxima are finite folds. -/
def solve (main : ModuleVersion) (graph : RequirementGraph) : List ModuleVersion :=
  let nodes := reachable graph [main]
  let maxima := selectMaxima nodes
  -- Selected versions for every path EXCEPT the root path (which is pinned to `main`).
  let others := (maxima.filter (fun (p, _) => p != main.basePath)).map
    (fun (p, v) => (⟨p, v⟩ : ModuleVersion))
  main :: sortSelected others

/-- Multi-target variant (cue's `BuildList` takes `targets []V`): roots first (deduped by path,
    in root order, each pinned to its own version), then the remaining selected paths sorted.
    Single-root `solve` is the common case; this covers a workspace with several main modules. -/
def solveMany (targets : List ModuleVersion) (graph : RequirementGraph) : List ModuleVersion :=
  let nodes := reachable graph targets
  let maxima := selectMaxima nodes
  -- Dedup roots by path, preserving order; collect their paths.
  let rootPaths := (targets.map (·.basePath)).eraseDups
  let roots := rootPaths.filterMap (fun p => (targets.find? (·.basePath == p)))
  let others := (maxima.filter (fun (p, _) => !rootPaths.contains p)).map
    (fun (p, v) => (⟨p, v⟩ : ModuleVersion))
  roots ++ sortSelected others

end Mvs
end Kue
