import Kue.Module

-- Pin the pure module-resolution logic without touching disk: `resolveImportSubpath`
-- (in-module hit, module-root path, cross-module miss) and `loadPackageFromParsed` merge
-- order over in-memory `ParsedFile` lists.

namespace Kue

-- An in-module subpath import strips the module prefix.
example : resolveImportSubpath "example.com" "example.com/defs" = some "defs" := by
  native_decide

-- A nested in-module path keeps the full trailing subpath.
example : resolveImportSubpath "example.com" "example.com/defs/packs" = some "defs/packs" := by
  native_decide

-- An import path equal to the module path resolves to the module root (`""`).
example : resolveImportSubpath "example.com" "example.com" = some "" := by
  native_decide

-- A non-matching prefix is a cross-module import: `none`, to be deferred.
example : resolveImportSubpath "example.com" "other.org/defs" = none := by
  native_decide

-- A path that shares a textual but not a path-segment prefix is still cross-module.
example : resolveImportSubpath "example.com" "example.computer/defs" = none := by
  native_decide

-- ### B3d-5a — unified cache-path authority (read-path == `Registry.extractCachePath`)
--
-- `locateModuleDir` now routes its extract-cache path through `Registry.extractCachePath`, so the
-- read-path and the B3d-5 write-path agree by construction. These pin the two facts that
-- unification rests on: for a real LOWERCASE module path the escaped form is byte-identical to
-- the bare segment-join (the canaries must not move), and for an upper-case path the two would
-- have DIVERGED (the latent bug the unification closes).

-- Canary: a real lowercase module path's `extractCachePath` is byte-identical to the bare
-- `<root>/extract/<modpath>@<ver>` join — so the read-path resolves identically
-- for every real module.
example :
    Registry.extractCachePath "/c/mod" (Registry.mkModuleVersion "lib.example/defs" "v0.1.0")
      = "/c/mod/extract/lib.example/defs@v0.1.0" := by
  native_decide

-- The escaping is identity on a lowercase path (`escapePath`/`escapeVersion`), so unifying the
-- read-path onto the escaped authority cannot move any real module's location.
example :
    Registry.escapePath "prodigy9.co/defs" = "prodigy9.co/defs"
      ∧ Registry.escapeVersion "v0.3.19" = "v0.3.19" := by
  native_decide

-- The divergence the unification closes: an (illegal-but-constructible) UPPER-case path escapes
-- to a `!`-lowercased on-disk form. The pre-B3d-5a read-path computed the BARE path here, missing
-- the cache — now both read- and write-path use this escaped authority.
example :
    Registry.extractCachePath "/c/mod" (Registry.mkModuleVersion "Foo.com/Bar" "v1")
      = "/c/mod/extract/!foo.com/!bar@v1" := by
  native_decide

private def fileA : ParsedFile :=
  { value := mkStruct [⟨"a", .regular, .prim (.int 1), false⟩] .regularOpen none []
    packageName := some "defs"
    imports := [] }

private def fileB : ParsedFile :=
  { value := mkStruct [⟨"b", .regular, .prim (.int 2), false⟩] .regularOpen none []
    packageName := some "defs"
    imports := [] }

-- Two files of the same package merge into one struct carrying both fields, in file
-- order, and the declared name survives.
example :
    (match loadPackageFromParsed [fileA, fileB] with
     | .ok (some "defs", value) =>
         value == mkStruct [⟨"a", .regular, .prim (.int 1), false⟩, ⟨"b", .regular, .prim (.int 2), false⟩] .regularOpen none []
     | _ => false) = true := by
  native_decide

-- Conflicting package names across a directory's files is rejected.
example :
    (loadPackageFromParsed [fileA, { fileB with packageName := some "other" }]).toOption.isNone = true := by
  native_decide

-- A bare import binds under the package's declared name.
example : importBindName { path := "example.com/defs", alias := none } (some "defs") = "defs" := by
  native_decide

-- An aliased import binds under the alias, ignoring the declared name.
example : importBindName { path := "example.com/defs", alias := some "d" } (some "defs") = "d" := by
  native_decide

-- An explicit `:identifier` qualifier (F-3) outranks the package's declared name.
example :
    importBindName { path := "example.com/defs", packageName := some "foo" } (some "defs") = "foo" := by
  native_decide

-- The `PackageName` alias prefix still wins over an explicit qualifier.
example :
    importBindName { path := "example.com/defs", packageName := some "foo", alias := some "d" }
      (some "defs") = "d" := by
  native_decide

-- With no qualifier and no alias, a qualified-import path that was suffix-stripped at
-- parse time binds under the loaded declared name exactly as a bare import does.
example :
    importBindName { path := "example.com/pkg-with-dash", packageName := some "pkg" } none = "pkg" := by
  native_decide

-- `bindImports` prepends each binding as an `importBinding` top-level field, in scope for
-- references but excluded from output (distinguished from a real in-file hidden field so
-- the import binding stays output-reachability-lazy).
example :
    (bindImports [("defs", mkStruct [] .regularOpen none [])] (mkStruct [⟨"out", .regular, .top, false⟩] .defClosed none [])
      == mkStruct [⟨"defs", .importBinding, mkStruct [] .regularOpen none [], false⟩, ⟨"out", .regular, .top, false⟩] .defClosed none [] [⟨["out"], []⟩]) = true := by
  native_decide

-- `dedupeBindings` keeps the FIRST binding per name and drops later duplicates — the same
-- package imported in two sibling files must bind ONCE, not be `meet`-folded into a corrupt
-- duplicate (the cert-manager `conflicting values` bug). First occurrence wins.
example :
    (dedupeBindings [("attr", mkStruct [⟨"a", .regular, .top, false⟩] .regularOpen none []),
                     ("strings", mkStruct [] .regularOpen none []),
                     ("attr", mkStruct [⟨"b", .regular, .bottom, false⟩] .regularOpen none [])]
      == [("attr", mkStruct [⟨"a", .regular, .top, false⟩] .regularOpen none []), ("strings", mkStruct [] .regularOpen none [])]) = true := by
  native_decide

-- Distinct bind names (same path under two aliases, or two different packages) all survive —
-- dedupe is by NAME, so no over-collapsing.
example :
    (dedupeBindings [("a", mkStruct [] .regularOpen none []), ("b", mkStruct [] .regularOpen none [])]
      == [("a", mkStruct [] .regularOpen none []), ("b", mkStruct [] .regularOpen none [])]) = true := by
  native_decide

-- ## Cross-module dependency resolution (B3c, disk-free)

-- A `deps` key carries an `@<major>` suffix that the module path drops.
example : depKeyModulePath "prodigy9.co/defs@v0" = "prodigy9.co/defs" := by
  native_decide

-- A key with no `@` is its own module path.
example : depKeyModulePath "example.com" = "example.com" := by
  native_decide

-- ## Self-module `@major` strip feeding in-module resolution (F-2)
--
-- The SAME `depKeyModulePath` strip applies to the importing module's OWN `module:` path, so
-- a self-import addresses the BARE path. Pinned as the composition the bug lived in: a verbatim
-- `ex.com/m@v0` modPath would make `resolveImportSubpath` reject `ex.com/m/sub`; the bare path
-- resolves it.

-- The verbatim `@v0` modPath fails to resolve its own bare sub-import — the F-2 bug.
example : resolveImportSubpath "ex.com/m@v0" "ex.com/m/sub" = none := by
  native_decide

-- Stripping the self modPath first resolves the bare sub-import to its subpath.
example : resolveImportSubpath (depKeyModulePath "ex.com/m@v0") "ex.com/m/sub" = some "sub" := by
  native_decide

-- The module-root self-import (`ex.com/m`) resolves under the stripped path.
example : resolveImportSubpath (depKeyModulePath "ex.com/m@v0") "ex.com/m" = some "" := by
  native_decide

-- No-suffix regression guard: a bare `module:` path is unchanged by the strip and still
-- resolves its sub-imports exactly as before.
example : resolveImportSubpath (depKeyModulePath "ex.com/m") "ex.com/m/sub" = some "sub" := by
  native_decide

private def depsValue : Value :=
  mkStruct
    [⟨"module", .regular, .prim (.string "prodigy9.co"), false⟩,
     ⟨"deps", .regular,
       mkStruct [⟨"prodigy9.co/defs@v0", .regular, mkStruct [⟨"v", .regular, .prim (.string "v0.3.19"), false⟩] .regularOpen none [], false⟩,
          ⟨"other.org/lib@v1", .regular, mkStruct [⟨"v", .regular, .prim (.string "v1.2.0"), false⟩] .regularOpen none [], false⟩] .regularOpen none [], false⟩]
    .regularOpen none []

-- `parseDeps` reads each `deps` entry into `(modPath, version)`, stripping the `@major`.
example :
    parseDeps depsValue
      = [{ modPath := "prodigy9.co/defs", version := "v0.3.19" },
         { modPath := "other.org/lib", version := "v1.2.0" }] := by
  native_decide

-- A module value with no `deps` field yields an empty dependency table.
example : parseDeps (mkStruct [⟨"module", .regular, .prim (.string "x.com"), false⟩] .regularOpen none []) = [] := by
  native_decide

private def deps : List Dep :=
  [{ modPath := "prodigy9.co/defs", version := "v0.3.19" },
   { modPath := "prodigy9.co/defs/sub", version := "v0.4.0" }]

-- A cross-module import resolves to its owning dep and the module root subpath (`""`).
example :
    resolveCrossModule deps "prodigy9.co/defs"
      = some ({ modPath := "prodigy9.co/defs", version := "v0.3.19" }, "") := by
  native_decide

-- A subpath import maps to the trailing path under the owning dep.
example :
    resolveCrossModule deps "prodigy9.co/defs/packs"
      = some ({ modPath := "prodigy9.co/defs", version := "v0.3.19" }, "packs") := by
  native_decide

-- Longest module-path prefix wins: the nested dep `prodigy9.co/defs/sub` is preferred
-- over `prodigy9.co/defs` when the import lies under it.
example :
    resolveCrossModule deps "prodigy9.co/defs/sub/leaf"
      = some ({ modPath := "prodigy9.co/defs/sub", version := "v0.4.0" }, "leaf") := by
  native_decide

-- An import matching no declared dependency is unresolved (`none`).
example : resolveCrossModule deps "unknown.org/x" = none := by
  native_decide

-- A textual-but-not-segment prefix does not match a dependency.
example : resolveCrossModule deps "prodigy9.com/defs" = none := by
  native_decide

-- ## `crossmod_nodeps` regression pins (testdata/modules/crossmod_nodeps)
--
-- A deps-less dependency module that imports its OWN subpackage. The app declares only
-- `example.com/lib@v0.1.0`; the lib module has an empty `deps` table yet imports
-- `example.com/lib/sub`. Both hops resolve purely: the app→lib hop is a cross-module
-- lookup, the lib→sub hop is a same-module subpath. Pins the topology the fixture's
-- oracle-matched export verifies end-to-end.

-- The app's cross-module import of the lib resolves to its dep at the module root.
example :
    resolveCrossModule [{ modPath := "example.com/lib", version := "v0.1.0" }]
        "example.com/lib/sub"
      = some ({ modPath := "example.com/lib", version := "v0.1.0" }, "sub") := by
  native_decide

-- The deps-less hop: the lib module resolving its own `/sub` subpackage maps to the
-- in-module subpath `sub` (no dep table consulted).
example : resolveImportSubpath "example.com/lib" "example.com/lib/sub" = some "sub" := by
  native_decide

-- ## Path resolution for module discovery
--
-- `absolutePath`/`discoveryStartDir` decide where the cue.mod parent-walk starts. The
-- bug they fix: a relative subpath's `.parent` dead-ends (`("sub" : FilePath).parent =
-- none`), so the walk never climbed into the cwd's real ancestors. Resolving against the
-- cwd first gives an absolute chain to walk. Compared on `.toString` for stable equality.

-- A relative path is joined onto the cwd to an absolute path.
example :
    (absolutePath "/home/me/proj" "sub/main.cue").toString
      = "/home/me/proj/sub/main.cue" := by
  native_decide

-- An already-absolute path is returned unchanged, ignoring the cwd.
example :
    (absolutePath "/home/me/proj" "/abs/sub/main.cue").toString
      = "/abs/sub/main.cue" := by
  native_decide

-- Discovery starts at the absolute *directory* of a relative file — the parent of the
-- cwd-joined path, where the upward cue.mod walk begins.
example :
    (discoveryStartDir "/home/me/proj" "sub/main.cue").toString
      = "/home/me/proj/sub" := by
  native_decide

-- A nested relative path resolves to its own deep directory.
example :
    (discoveryStartDir "/home/me/proj" "sub/deeper/main.cue").toString
      = "/home/me/proj/sub/deeper" := by
  native_decide

-- An absolute file's discovery dir is its own absolute parent, cwd untouched.
example :
    (discoveryStartDir "/home/me/proj" "/var/m/sub/main.cue").toString
      = "/var/m/sub" := by
  native_decide

-- ## Cache-root path resolution (per-OS, env-driven)
--
-- `cacheDirFor` mirrors Go's `os.UserCacheDir` precedence (`cue`'s cache discovery):
-- `CUE_CACHE_DIR` wins outright; else `XDG_CACHE_HOME/cue`; else the per-OS user cache.
-- The IO wrapper supplies `System.Platform.isOSX`; here we pin both OS branches.

-- `CUE_CACHE_DIR` is used verbatim, ignoring XDG, HOME, and OS.
example :
    (cacheDirFor (some "/explicit/cache") (some "/xdg") (some "/home/me") true).toString
      = "/explicit/cache" := by
  native_decide

-- With no `CUE_CACHE_DIR`, `XDG_CACHE_HOME/cue` wins over the per-OS fallback.
example :
    (cacheDirFor none (some "/xdg") (some "/home/me") false).toString
      = "/xdg/cue" := by
  native_decide

-- Neither env var on macOS: the `~/Library/Caches/cue` default.
example :
    (cacheDirFor none none (some "/Users/me") true).toString
      = "/Users/me/Library/Caches/cue" := by
  native_decide

-- Neither env var on Linux: the `~/.cache/cue` default (the bug this slice fixes).
example :
    (cacheDirFor none none (some "/home/me") false).toString
      = "/home/me/.cache/cue" := by
  native_decide

-- A missing `HOME` falls back to a root-relative cache dir rather than crashing.
example :
    (cacheDirFor none none none false).toString = "/.cache/cue" := by
  native_decide

-- ## A2-y — import-name redeclaration boundary
--
-- A top-level bare-identifier field whose name equals an import's bound local name is a
-- file-block redeclaration (cue: `<name> redeclared as imported package name`). The pure
-- pieces: `bareIdentifierLabels` extracts exactly the collision-eligible labels (bare,
-- output-namespace, all three presence rungs), exempting quoted labels, definitions,
-- hidden fields, and `let`s; `checkImportRedeclaration` flags a bound name present in that
-- set. Mirrors `Module.lean:160`'s loader gate without disk.

-- A bare regular field is collision-eligible — its label is in the set.
example :
    bareIdentifierLabels [.field ⟨"dep", .regular, .top, false⟩ false] = ["dep"] := by
  native_decide

-- Optional and required fields are eligible too (cue rejects `dep?:`/`dep!:` alike).
example :
    bareIdentifierLabels
      [.field ⟨"a", .optional, .top, false⟩ false, .field ⟨"b", .required, .top, false⟩ false]
      = ["a", "b"] := by
  native_decide

-- A QUOTED label (`"dep": …`) is NOT an identifier declaration — exempt (`quoted = true`).
example :
    bareIdentifierLabels [.field ⟨"dep", .regular, .top, false⟩ true] = [] := by
  native_decide

-- A definition (`#x`) and a hidden field (`_x`) live in distinct namespaces — exempt.
example :
    bareIdentifierLabels
      [.field ⟨"#dep", .definition, .top, false⟩ false, .field ⟨"_dep", .hidden, .top, false⟩ false]
      = [] := by
  native_decide

-- A `let` binding declares no output identifier here — exempt.
example :
    bareIdentifierLabels [.letBinding "dep" .top] = [] := by
  native_decide

-- A pattern/embedding/comprehension declares no top-level name — exempt.
example :
    bareIdentifierLabels [.embedding .top, .comprehension [] .top] = [] := by
  native_decide

-- The diagnostic text matches cue's first error line.
example : importRedeclarationError "dep" = "dep redeclared as imported package name" := by
  native_decide

-- The check ERRORS (no `.ok`) when the bound name is among the field labels.
-- (`Except String Unit` has no `DecidableEq`, so pin via `.toOption`: error ⇒ `none`.)
example : (checkImportRedeclaration "dep" ["out", "dep"]).toOption = none := by
  native_decide

-- No collision when the bound name is absent (normal import, alias/qualifier mismatch,
-- different-named field) — the `.ok` path keeps loading (`some ()`).
example : (checkImportRedeclaration "dep" ["out", "other"]).toOption = some () := by
  native_decide

-- The builtin-fast-path batch check errors on the first colliding import — here `json`
-- collides with a top-level `json` field.
example :
    (checkBuiltinImportRedeclarations
      [{ path := "strings" }, { path := "encoding/json" }] ["json"]).toOption = none := by
  native_decide

-- The batch check is `ok` when no builtin bind name matches a field.
example :
    (checkBuiltinImportRedeclarations
      [{ path := "strings" }, { path := "encoding/json" }] ["out"]).toOption = some () := by
  native_decide

-- An alias renames the binding, so only the ALIAS name collides — a field equal to the
-- last path element does not (the bound name is the alias).
example :
    (checkImportRedeclaration
      (importBindName { path := "ex.com/dep", alias := some "d" } (some "dep")) ["dep"]).toOption
      = some () := by
  native_decide

-- ## B3d-6b-leg4 — export-path MVS version override
--
-- The loader threads `ModuleContext.selected` (the MVS build-list projection: bare path →
-- selected version) so a cross-module import resolves to the max-of-mins version across the whole
-- requirement graph, not the intermediate module's per-hop `deps` pin. These pin the pure pieces
-- the IO loader composes: `Mvs.solveChecked` over a disk-shaped graph, its projection to the
-- override map (exactly `solveVersionOverride`'s inner fold), and `selectedVersion`'s lookup.

-- The on-disk diamond of `testdata/modules/crossmod_diamond`: `pa` requires c@v0.1.0, `pb`
-- requires c@v0.2.0. MVS selects c@v0.2.0 for BOTH — the override map the loader threads pins
-- `c.example/pc` to v0.2.0, so `fromA` and `fromB` agree (per-hop lenient made `fromA` see v0.1.0).
private def diamondGraph : Mvs.RequirementGraph :=
  [(⟨"app.example", ""⟩, [⟨"a.example/pa", "v0.1.0"⟩, ⟨"b.example/pb", "v0.1.0"⟩]),
   (⟨"a.example/pa", "v0.1.0"⟩, [⟨"c.example/pc", "v0.1.0"⟩]),
   (⟨"b.example/pb", "v0.1.0"⟩, [⟨"c.example/pc", "v0.2.0"⟩]),
   (⟨"c.example/pc", "v0.1.0"⟩, []),
   (⟨"c.example/pc", "v0.2.0"⟩, [])]

-- The override map (drop the main node, keep `(basePath, version)`) — mirrors the projection in
-- `solveVersionOverride`. `c.example/pc` is pinned to the MAX (v0.2.0), the whole point.
example :
    (match Mvs.solveChecked ⟨"app.example", ""⟩ diamondGraph with
     | .ok bl => bl.filterMap (fun mv =>
         if mv.basePath == "app.example" then none else some (mv.basePath, mv.version))
     | .error _ => [])
      = [("a.example/pa", "v0.1.0"), ("b.example/pb", "v0.1.0"), ("c.example/pc", "v0.2.0")] := by
  native_decide

-- A single-version (no-conflict) graph selects each path's only version — so the override is a
-- pure no-op vs per-hop resolution (the canary-safety property: single-version loads never move).
private def singleGraph : Mvs.RequirementGraph :=
  [(⟨"app.example", ""⟩, [⟨"lib.example/defs", "v0.1.0"⟩]),
   (⟨"lib.example/defs", "v0.1.0"⟩, [])]

example :
    (match Mvs.solveChecked ⟨"app.example", ""⟩ singleGraph with
     | .ok bl => bl.filterMap (fun mv =>
         if mv.basePath == "app.example" then none else some (mv.basePath, mv.version))
     | .error _ => [])
      = [("lib.example/defs", "v0.1.0")] := by
  native_decide

-- Transitive (3-deep) diamond: `m → d1 → d2 → d3` and `d1 → d3` directly at a LOWER version.
-- MVS selects the max of d3 across the reachable graph (v0.3.0), pinning it three hops deep.
private def chain3Graph : Mvs.RequirementGraph :=
  [(⟨"m.example", ""⟩, [⟨"d1.example", "v1.0.0"⟩]),
   (⟨"d1.example", "v1.0.0"⟩, [⟨"d2.example", "v1.0.0"⟩, ⟨"d3.example", "v0.1.0"⟩]),
   (⟨"d2.example", "v1.0.0"⟩, [⟨"d3.example", "v0.3.0"⟩]),
   (⟨"d3.example", "v0.1.0"⟩, []),
   (⟨"d3.example", "v0.3.0"⟩, [])]

example :
    (match Mvs.solveChecked ⟨"m.example", ""⟩ chain3Graph with
     | .ok bl => bl.filterMap (fun mv =>
         if mv.basePath == "m.example" then none else some (mv.basePath, mv.version))
     | .error _ => [])
      = [("d1.example", "v1.0.0"), ("d2.example", "v1.0.0"), ("d3.example", "v0.3.0")] := by
  native_decide

-- A dependency that transitively requires a HIGHER version of the MAIN module's own path is the
-- case cue rejects — `solveChecked` surfaces a typed error (never a silent pin), and the loader
-- propagates it. The main node carries the empty-version sentinel, so any real version conflicts.
private def mainConflictGraph : Mvs.RequirementGraph :=
  [(⟨"app.example", ""⟩, [⟨"dep.example/x", "v0.1.0"⟩]),
   (⟨"dep.example/x", "v0.1.0"⟩, [⟨"app.example", "v1.0.0"⟩]),
   (⟨"app.example", "v1.0.0"⟩, [])]

example : (Mvs.solveChecked ⟨"app.example", ""⟩ mainConflictGraph).toOption.isNone = true := by
  native_decide

-- `selectedVersion` finds a pinned path (the override governs) …
example : selectedVersion [("c.example/pc", "v0.2.0")] "c.example/pc" = some "v0.2.0" := by
  native_decide

-- … and returns `none` for a path the build list does not pin (a dep whose path is absent from
-- the graph) — so the per-hop `deps` version stands, the override never inventing a version.
example : selectedVersion [("c.example/pc", "v0.2.0")] "other.example/y" = none := by
  native_decide

end Kue
