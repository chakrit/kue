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

end Kue
