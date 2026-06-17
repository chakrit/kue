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
  { value := .struct [("a", .regular, .prim (.int 1))] true
    packageName := some "defs"
    imports := [] }

private def fileB : ParsedFile :=
  { value := .struct [("b", .regular, .prim (.int 2))] true
    packageName := some "defs"
    imports := [] }

/-- Two files of the same package merge into one struct carrying both fields, in file
    order, and the declared name survives. -/
example :
    (match loadPackageFromParsed [fileA, fileB] with
     | .ok (some "defs", value) =>
         value == .struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.int 2))] true
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

/-- `bindImports` prepends each binding as a hidden top-level field, in scope for
    references but excluded from output. -/
example :
    (bindImports [("defs", .struct [] true)] (.struct [("out", .regular, .top)] false)
      == .struct [("defs", .hidden, .struct [] true), ("out", .regular, .top)] false) = true := by
  native_decide

/-! ## Cross-module dependency resolution (B3c, disk-free) -/

/-- A `deps` key carries an `@<major>` suffix that the module path drops. -/
example : depKeyModulePath "prodigy9.co/defs@v0" = "prodigy9.co/defs" := by
  native_decide

/-- A key with no `@` is its own module path. -/
example : depKeyModulePath "example.com" = "example.com" := by
  native_decide

private def depsValue : Value :=
  .struct
    [("module", .regular, .prim (.string "prodigy9.co")),
     ("deps", .regular,
       .struct
         [("prodigy9.co/defs@v0", .regular, .struct [("v", .regular, .prim (.string "v0.3.19"))] true),
          ("other.org/lib@v1", .regular, .struct [("v", .regular, .prim (.string "v1.2.0"))] true)]
         true)]
    true

/-- `parseDeps` reads each `deps` entry into `(modPath, version)`, stripping the `@major`. -/
example :
    parseDeps depsValue
      = [{ modPath := "prodigy9.co/defs", version := "v0.3.19" },
         { modPath := "other.org/lib", version := "v1.2.0" }] := by
  native_decide

/-- A module value with no `deps` field yields an empty dependency table. -/
example : parseDeps (.struct [("module", .regular, .prim (.string "x.com"))] true) = [] := by
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

end Kue
