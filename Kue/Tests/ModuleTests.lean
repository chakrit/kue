import Kue.Module

/-! Pin the pure module-resolution logic without touching disk: `resolveImportSubpath`
    (in-module hit, module-root path, cross-module miss) and `loadPackageFromParsed` merge
    order over in-memory `ParsedFile` lists. -/

namespace Kue

/-- An in-module subpath import strips the module prefix. -/
example : resolveImportSubpath "example.com" "example.com/defs" = some "defs" := by
  native_decide

/-- A nested in-module path keeps the full trailing subpath. -/
example : resolveImportSubpath "example.com" "example.com/defs/packs" = some "defs/packs" := by
  native_decide

/-- An import path equal to the module path resolves to the module root (`""`). -/
example : resolveImportSubpath "example.com" "example.com" = some "" := by
  native_decide

/-- A non-matching prefix is a cross-module import: `none`, to be deferred. -/
example : resolveImportSubpath "example.com" "other.org/defs" = none := by
  native_decide

/-- A path that shares a textual but not a path-segment prefix is still cross-module. -/
example : resolveImportSubpath "example.com" "example.computer/defs" = none := by
  native_decide

private def fileA : ParsedFile :=
  { value := mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []
    packageName := some "defs"
    imports := [] }

private def fileB : ParsedFile :=
  { value := mkStruct [⟨"b", .regular, .prim (.int 2)⟩] .regularOpen none []
    packageName := some "defs"
    imports := [] }

/-- Two files of the same package merge into one struct carrying both fields, in file
    order, and the declared name survives. -/
example :
    (match loadPackageFromParsed [fileA, fileB] with
     | .ok (some "defs", value) =>
         value == mkStruct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.int 2)⟩] .regularOpen none []
     | _ => false) = true := by
  native_decide

/-- Conflicting package names across a directory's files is rejected. -/
example :
    (loadPackageFromParsed [fileA, { fileB with packageName := some "other" }]).toOption.isNone = true := by
  native_decide

/-- A bare import binds under the package's declared name. -/
example : importBindName { path := "example.com/defs", alias := none } (some "defs") = "defs" := by
  native_decide

/-- An aliased import binds under the alias, ignoring the declared name. -/
example : importBindName { path := "example.com/defs", alias := some "d" } (some "defs") = "d" := by
  native_decide

/-- An explicit `:identifier` qualifier (F-3) outranks the package's declared name. -/
example :
    importBindName { path := "example.com/defs", packageName := some "foo" } (some "defs") = "foo" := by
  native_decide

/-- The `PackageName` alias prefix still wins over an explicit qualifier. -/
example :
    importBindName { path := "example.com/defs", packageName := some "foo", alias := some "d" }
      (some "defs") = "d" := by
  native_decide

/-- With no qualifier and no alias, a qualified-import path that was suffix-stripped at
    parse time binds under the loaded declared name exactly as a bare import does. -/
example :
    importBindName { path := "example.com/pkg-with-dash", packageName := some "pkg" } none = "pkg" := by
  native_decide

/-- `bindImports` prepends each binding as an `importBinding` top-level field, in scope for
    references but excluded from output (distinguished from a real in-file hidden field so
    the import binding stays output-reachability-lazy). -/
example :
    (bindImports [("defs", mkStruct [] .regularOpen none [])] (mkStruct [⟨"out", .regular, .top⟩] .defClosed none [])
      == mkStruct [⟨"defs", .importBinding, mkStruct [] .regularOpen none []⟩, ⟨"out", .regular, .top⟩] .defClosed none []) = true := by
  native_decide

/-- `dedupeBindings` keeps the FIRST binding per name and drops later duplicates — the same
    package imported in two sibling files must bind ONCE, not be `meet`-folded into a corrupt
    duplicate (the cert-manager `conflicting values` bug). First occurrence wins. -/
example :
    (dedupeBindings [("attr", mkStruct [⟨"a", .regular, .top⟩] .regularOpen none []),
                     ("strings", mkStruct [] .regularOpen none []),
                     ("attr", mkStruct [⟨"b", .regular, .bottom⟩] .regularOpen none [])]
      == [("attr", mkStruct [⟨"a", .regular, .top⟩] .regularOpen none []), ("strings", mkStruct [] .regularOpen none [])]) = true := by
  native_decide

/-- Distinct bind names (same path under two aliases, or two different packages) all survive —
    dedupe is by NAME, so no over-collapsing. -/
example :
    (dedupeBindings [("a", mkStruct [] .regularOpen none []), ("b", mkStruct [] .regularOpen none [])]
      == [("a", mkStruct [] .regularOpen none []), ("b", mkStruct [] .regularOpen none [])]) = true := by
  native_decide

/-! ## Cross-module dependency resolution (B3c, disk-free) -/

/-- A `deps` key carries an `@<major>` suffix that the module path drops. -/
example : depKeyModulePath "prodigy9.co/defs@v0" = "prodigy9.co/defs" := by
  native_decide

/-- A key with no `@` is its own module path. -/
example : depKeyModulePath "example.com" = "example.com" := by
  native_decide

/-! ## Self-module `@major` strip feeding in-module resolution (F-2)

The SAME `depKeyModulePath` strip applies to the importing module's OWN `module:` path, so
a self-import addresses the BARE path. Pinned as the composition the bug lived in: a verbatim
`ex.com/m@v0` modPath would make `resolveImportSubpath` reject `ex.com/m/sub`; the bare path
resolves it. -/

/-- The verbatim `@v0` modPath fails to resolve its own bare sub-import — the F-2 bug. -/
example : resolveImportSubpath "ex.com/m@v0" "ex.com/m/sub" = none := by
  native_decide

/-- Stripping the self modPath first resolves the bare sub-import to its subpath. -/
example : resolveImportSubpath (depKeyModulePath "ex.com/m@v0") "ex.com/m/sub" = some "sub" := by
  native_decide

/-- The module-root self-import (`ex.com/m`) resolves under the stripped path. -/
example : resolveImportSubpath (depKeyModulePath "ex.com/m@v0") "ex.com/m" = some "" := by
  native_decide

/-- No-suffix regression guard: a bare `module:` path is unchanged by the strip and still
    resolves its sub-imports exactly as before. -/
example : resolveImportSubpath (depKeyModulePath "ex.com/m") "ex.com/m/sub" = some "sub" := by
  native_decide

private def depsValue : Value :=
  mkStruct
    [⟨"module", .regular, .prim (.string "prodigy9.co")⟩,
     ⟨"deps", .regular,
       mkStruct [⟨"prodigy9.co/defs@v0", .regular, mkStruct [⟨"v", .regular, .prim (.string "v0.3.19")⟩] .regularOpen none []⟩,
          ⟨"other.org/lib@v1", .regular, mkStruct [⟨"v", .regular, .prim (.string "v1.2.0")⟩] .regularOpen none []⟩] .regularOpen none []⟩]
    .regularOpen none []

/-- `parseDeps` reads each `deps` entry into `(modPath, version)`, stripping the `@major`. -/
example :
    parseDeps depsValue
      = [{ modPath := "prodigy9.co/defs", version := "v0.3.19" },
         { modPath := "other.org/lib", version := "v1.2.0" }] := by
  native_decide

/-- A module value with no `deps` field yields an empty dependency table. -/
example : parseDeps (mkStruct [⟨"module", .regular, .prim (.string "x.com")⟩] .regularOpen none []) = [] := by
  native_decide

private def deps : List Dep :=
  [{ modPath := "prodigy9.co/defs", version := "v0.3.19" },
   { modPath := "prodigy9.co/defs/sub", version := "v0.4.0" }]

/-- A cross-module import resolves to its owning dep and the module root subpath (`""`). -/
example :
    resolveCrossModule deps "prodigy9.co/defs"
      = some ({ modPath := "prodigy9.co/defs", version := "v0.3.19" }, "") := by
  native_decide

/-- A subpath import maps to the trailing path under the owning dep. -/
example :
    resolveCrossModule deps "prodigy9.co/defs/packs"
      = some ({ modPath := "prodigy9.co/defs", version := "v0.3.19" }, "packs") := by
  native_decide

/-- Longest module-path prefix wins: the nested dep `prodigy9.co/defs/sub` is preferred
    over `prodigy9.co/defs` when the import lies under it. -/
example :
    resolveCrossModule deps "prodigy9.co/defs/sub/leaf"
      = some ({ modPath := "prodigy9.co/defs/sub", version := "v0.4.0" }, "leaf") := by
  native_decide

/-- An import matching no declared dependency is unresolved (`none`). -/
example : resolveCrossModule deps "unknown.org/x" = none := by
  native_decide

/-- A textual-but-not-segment prefix does not match a dependency. -/
example : resolveCrossModule deps "prodigy9.com/defs" = none := by
  native_decide

/-! ## `crossmod_nodeps` regression pins (testdata/modules/crossmod_nodeps)

    A deps-less dependency module that imports its OWN subpackage. The app declares only
    `example.com/lib@v0.1.0`; the lib module has an empty `deps` table yet imports
    `example.com/lib/sub`. Both hops resolve purely: the app→lib hop is a cross-module
    lookup, the lib→sub hop is a same-module subpath. Pins the topology the fixture's
    oracle-matched export verifies end-to-end. -/

/-- The app's cross-module import of the lib resolves to its dep at the module root. -/
example :
    resolveCrossModule [{ modPath := "example.com/lib", version := "v0.1.0" }]
        "example.com/lib/sub"
      = some ({ modPath := "example.com/lib", version := "v0.1.0" }, "sub") := by
  native_decide

/-- The deps-less hop: the lib module resolving its own `/sub` subpackage maps to the
    in-module subpath `sub` (no dep table consulted). -/
example : resolveImportSubpath "example.com/lib" "example.com/lib/sub" = some "sub" := by
  native_decide

/-! ## Path resolution for module discovery

    `absolutePath`/`discoveryStartDir` decide where the cue.mod parent-walk starts. The
    bug they fix: a relative subpath's `.parent` dead-ends (`("sub" : FilePath).parent =
    none`), so the walk never climbed into the cwd's real ancestors. Resolving against the
    cwd first gives an absolute chain to walk. Compared on `.toString` for stable equality. -/

/-- A relative path is joined onto the cwd to an absolute path. -/
example :
    (absolutePath "/home/me/proj" "sub/main.cue").toString
      = "/home/me/proj/sub/main.cue" := by
  native_decide

/-- An already-absolute path is returned unchanged, ignoring the cwd. -/
example :
    (absolutePath "/home/me/proj" "/abs/sub/main.cue").toString
      = "/abs/sub/main.cue" := by
  native_decide

/-- Discovery starts at the absolute *directory* of a relative file — the parent of the
    cwd-joined path, where the upward cue.mod walk begins. -/
example :
    (discoveryStartDir "/home/me/proj" "sub/main.cue").toString
      = "/home/me/proj/sub" := by
  native_decide

/-- A nested relative path resolves to its own deep directory. -/
example :
    (discoveryStartDir "/home/me/proj" "sub/deeper/main.cue").toString
      = "/home/me/proj/sub/deeper" := by
  native_decide

/-- An absolute file's discovery dir is its own absolute parent, cwd untouched. -/
example :
    (discoveryStartDir "/home/me/proj" "/var/m/sub/main.cue").toString
      = "/var/m/sub" := by
  native_decide

/-! ## Cache-root path resolution (per-OS, env-driven)

    `cacheDirFor` mirrors Go's `os.UserCacheDir` precedence (`cue`'s cache discovery):
    `CUE_CACHE_DIR` wins outright; else `XDG_CACHE_HOME/cue`; else the per-OS user cache.
    The IO wrapper supplies `System.Platform.isOSX`; here we pin both OS branches. -/

/-- `CUE_CACHE_DIR` is used verbatim, ignoring XDG, HOME, and OS. -/
example :
    (cacheDirFor (some "/explicit/cache") (some "/xdg") (some "/home/me") true).toString
      = "/explicit/cache" := by
  native_decide

/-- With no `CUE_CACHE_DIR`, `XDG_CACHE_HOME/cue` wins over the per-OS fallback. -/
example :
    (cacheDirFor none (some "/xdg") (some "/home/me") false).toString
      = "/xdg/cue" := by
  native_decide

/-- Neither env var on macOS: the `~/Library/Caches/cue` default. -/
example :
    (cacheDirFor none none (some "/Users/me") true).toString
      = "/Users/me/Library/Caches/cue" := by
  native_decide

/-- Neither env var on Linux: the `~/.cache/cue` default (the bug this slice fixes). -/
example :
    (cacheDirFor none none (some "/home/me") false).toString
      = "/home/me/.cache/cue" := by
  native_decide

/-- A missing `HOME` falls back to a root-relative cache dir rather than crashing. -/
example :
    (cacheDirFor none none none false).toString = "/.cache/cue" := by
  native_decide

end Kue
