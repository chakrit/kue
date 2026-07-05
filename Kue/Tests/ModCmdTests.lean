import Kue.ModCmd

--
-- # `cue mod tidy` pure-layer tests (B3d-6b)
--
-- `native_decide` pins for the offline-deterministic pieces of the `mod tidy` pipeline: the
-- requirement-graph assembly, the `cue.sum` serializer/parser round-trip, `depsFromEntries` over a
-- module.cue zip entry, and `cueSumRows` over a solved build list. The transitive fetch + write is
-- driven end-to-end (offline) by `scripts/check-mod-tidy.lean`.
--

namespace Kue
namespace ModCmd

open Kue.Registry (ModuleVersion)

private def dep (p v : String) : Dep := { modPath := p, version := v }
private def mv (p v : String) : ModuleVersion := ⟨p, v⟩

-- ## Requirement-graph assembly: dep tables → MVS graph

example :
    buildRequirementGraph
        [ (mv "main" "", [dep "A" "v1.0.0", dep "B" "v1.0.0"]),
          (mv "A" "v1.0.0", [dep "C" "v1.2.0"]),
          (mv "B" "v1.0.0", [dep "C" "v1.3.0"]) ]
      = [ (mv "main" "", [mv "A" "v1.0.0", mv "B" "v1.0.0"]),
          (mv "A" "v1.0.0", [mv "C" "v1.2.0"]),
          (mv "B" "v1.0.0", [mv "C" "v1.3.0"]) ] := by
  native_decide

-- The assembled diamond feeds `solveChecked` to select C v1.3.0 (max-of-mins) end-to-end.
example :
    (Mvs.solveChecked (mv "main" "")
        (buildRequirementGraph
          [ (mv "main" "", [dep "A" "v1.0.0", dep "B" "v1.0.0"]),
            (mv "A" "v1.0.0", [dep "C" "v1.2.0"]),
            (mv "B" "v1.0.0", [dep "C" "v1.3.0"]) ])).toOption
      = some [mv "main" "", mv "A" "v1.0.0", mv "B" "v1.0.0", mv "C" "v1.3.0"] := by
  native_decide

-- ## cue.sum serialize/parse round-trip
--
-- `formatCueSum` is the inverse of `parseCueSumText`: writing rows then re-parsing recovers the
-- `(modpath@version, h1)` pairs. Sorted by (path, semver) so the file is deterministic.

example :
    parseCueSumText
        (formatCueSum
          [ ("b.com/y", "v2.0.0", "h1:BBB="), ("a.com/x", "v1.0.0", "h1:AAA=") ])
      = [ ("a.com/x@v1.0.0", "h1:AAA="), ("b.com/y@v2.0.0", "h1:BBB=") ] := by
  native_decide

-- Two versions of the SAME path sort by semver ascending (v1.2.0 before v1.10.0 — numeric).
example :
    formatCueSum [ ("m", "v1.10.0", "h1:B="), ("m", "v1.2.0", "h1:A=") ]
      = "m v1.2.0 h1:A=\nm v1.10.0 h1:B=\n" := by
  native_decide

-- ## depsFromEntries: read a dependency's deps out of its zip's cue.mod/module.cue

private def modCueText : String :=
  "module: \"a.com/x@v0\"\nlanguage: version: \"v0.15.4\"\ndeps: {\n\t\"c.com/z@v1\": v: \"v1.3.0\"\n}\n"

example :
    (depsFromEntries [("cue.mod/module.cue", modCueText.toUTF8), ("x.cue", "package x\n".toUTF8)]).toOption
      = some [dep "c.com/z" "v1.3.0"] := by
  native_decide

-- A zip with no module.cue entry is a typed error, never a silent empty dep list.
example :
    (depsFromEntries [("x.cue", "package x\n".toUTF8)]).toOption.isNone = true := by
  native_decide

-- ## cueSumRows: build list → cue.sum rows (main excluded, h1 looked up per node)

private def nodes : List (ModuleVersion × (List Dep × String)) :=
  [ (mv "main" "", ([dep "A" "v1.0.0"], "")),
    (mv "A" "v1.0.0", ([], "h1:AAA=")),
    (mv "C" "v1.3.0", ([], "h1:CCC=")) ]

example :
    cueSumRows (mv "main" "") [mv "main" "", mv "A" "v1.0.0", mv "C" "v1.3.0"] nodes
      = [ ("A", "v1.0.0", "h1:AAA="), ("C", "v1.3.0", "h1:CCC=") ] := by
  native_decide

--
-- # `cue mod get` pure layer (B3d-6b-leg2)
--
-- The deps-block emitter, tag "latest" resolution, and the end-to-end pure driver are all offline
-- and `native_decide`-checkable (the network only supplies the tag list). Emitter output is
-- cross-validated byte-identical against `cue mod get` v0.16.1 for the canonical (block-form) case.
--

-- ## depKey: dependency → its `deps` key `"<modpath>@v<major>"`

example : depKey "foo.example/bar" "v1.2.3" = some "foo.example/bar@v1" := by native_decide
example : depKey "z.example/m" "v0.3.1" = some "z.example/m@v0" := by native_decide
example : depKey "x" "not-a-version" = none := by native_decide

-- ## mergeDep: update the same-major entry in place; append a new major

example :
    mergeDep [dep "c.example/c" "v1.2.0"] (dep "c.example/c" "v1.3.0")
      = [dep "c.example/c" "v1.3.0"] := by native_decide

example :
    mergeDep [dep "c.example/c" "v1.2.0"] (dep "c.example/c" "v2.0.0")
      = [dep "c.example/c" "v1.2.0", dep "c.example/c" "v2.0.0"] := by native_decide

example :
    mergeDep [] (dep "a.example/a" "v1.0.0") = [dep "a.example/a" "v1.0.0"] := by native_decide

-- ## renderDepsBlock: canonical, tab-indented, keys sorted ascending (cue's exact form)

example :
    renderDepsBlock [dep "foo.example/bar" "v1.2.3"]
      = "deps: {\n\t\"foo.example/bar@v1\": {\n\t\tv: \"v1.2.3\"\n\t}\n}\n" := by native_decide

-- Two entries render sorted by key regardless of input order.
example :
    renderDepsBlock [dep "z.example/z" "v2.0.0", dep "a.example/a" "v1.0.0"]
      = "deps: {\n\t\"a.example/a@v1\": {\n\t\tv: \"v1.0.0\"\n\t}\n"
        ++ "\t\"z.example/z@v2\": {\n\t\tv: \"v2.0.0\"\n\t}\n}\n" := by native_decide

-- ## exciseTopLevelDeps: string/brace-aware removal of the top-level deps block

private def blockForm : String :=
  "module: \"app.example@v0\"\nlanguage: {\n\tversion: \"v0.15.4\"\n}\n"

-- No deps field present ⇒ nothing removed, `found = false`.
example : (exciseTopLevelDeps blockForm).2 = false := by native_decide
example : (exciseTopLevelDeps blockForm).1 = blockForm := by native_decide

-- A trailing deps block is removed cleanly (source minus the block), `found = true`.
example :
    exciseTopLevelDeps
        "module: \"m@v0\"\ndeps: {\n\t\"a@v1\": {\n\t\tv: \"v1.0.0\"\n\t}\n}\n"
      = ("module: \"m@v0\"\n", true) := by native_decide

-- A deps value containing nested braces AND a string with braces/`deps:` inside is matched to its
-- correct closing brace (the string content never trips the scanner).
example :
    (exciseTopLevelDeps
        "module: \"m@v0\"\ndeps: {\n\t\"a@v1\": {\n\t\tv: \"v1.0.0\"\n\t\tx: \"}deps: {\"\n\t}\n}\nsource: {\n\tkind: \"self\"\n}\n").1
      = "module: \"m@v0\"\nsource: {\n\tkind: \"self\"\n}\n" := by native_decide

-- `depsfoo` is NOT the deps field (token boundary).
example : (exciseTopLevelDeps "module: \"m@v0\"\ndepsfoo: 1\n").2 = false := by native_decide

-- Regression (audit d6dac7c..): the scanner is COMMENT-aware. A `//` line comment INSIDE the deps
-- block carrying an unbalanced `}` must not truncate the block early (it did before, splicing the
-- deps remnants into the file as top-level content — a silent corruption).
example :
    (exciseTopLevelDeps
        "module: \"m@v0\"\ndeps: {\n\t// nested } brace\n\t\"a@v1\": {\n\t\tv: \"v1.0.0\"\n\t}\n}\nsource: {\n\tkind: \"self\"\n}\n")
      = ("module: \"m@v0\"\nsource: {\n\tkind: \"self\"\n}\n", true) := by native_decide

-- A `/* */` block comment INSIDE deps, with braces AND an unterminated-looking quote, is inert.
example :
    (exciseTopLevelDeps
        "module: \"m@v0\"\ndeps: {\n\t/* }{ \"x */\n\t\"a@v1\": {\n\t\tv: \"v1.0.0\"\n\t}\n}\nx: 1\n").1
      = "module: \"m@v0\"\nx: 1\n" := by native_decide

-- A lone `\"` inside a line comment must NOT flip string state (it would swallow the real close).
example :
    (exciseTopLevelDeps
        "deps: {\n\t// a \" quote\n\t\"a@v1\": {\n\t\tv: \"v1.0.0\"\n\t}\n}\ny: 2\n").1
      = "y: 2\n" := by native_decide

-- A top-level comment carrying an unbalanced `{` must not raise brace depth (which would hide the
-- following top-level deps field from detection).
example :
    (exciseTopLevelDeps
        "// opening { comment\nmodule: \"m@v0\"\ndeps: {\n\t\"a@v1\": {\n\t\tv: \"v1.0.0\"\n\t}\n}\n")
      = ("// opening { comment\nmodule: \"m@v0\"\n", true) := by native_decide

-- End-to-end: a comment inside the deps block no longer corrupts the emitted module.cue.
example :
    (applyModGet
        "module: \"m@v0\"\ndeps: {\n\t// keep me sane }\n\t\"a@v1\": {\n\t\tv: \"v1.0.0\"\n\t}\n}\n"
        (dep "b.example/b" "v1.0.0")).toOption
      = some ("module: \"m@v0\"\ndeps: {\n\t\"a@v1\": {\n\t\tv: \"v1.0.0\"\n\t}\n"
          ++ "\t\"b.example/b@v1\": {\n\t\tv: \"v1.0.0\"\n\t}\n}\n") := by native_decide

-- ## parseVerSpec: constraint classification

example : parseVerSpec "latest" = some .latest := by native_decide
example : parseVerSpec "v1.2.3" = some (.exact "v1.2.3") := by native_decide
example : parseVerSpec "v1" = some (.major "1") := by native_decide
example : parseVerSpec "v1.2" = some (.majorMinor "1" "2") := by native_decide
example : parseVerSpec "v0" = some (.major "0") := by native_decide
example : parseVerSpec "v1.2.3-rc.1" = some (.exact "v1.2.3-rc.1") := by native_decide
example : parseVerSpec "banana" = none := by native_decide

-- ## resolveVerSpec: filter valid non-prerelease tags matching the constraint, take the max

private def tags : List String :=
  ["v1.0.0", "v1.3.2", "v2.0.0-rc.1", "v0.9.0", "v2.5.0", "not-a-tag"]

-- latest = max non-prerelease overall (the v2.0.0-rc.1 prerelease and junk tag are excluded).
example : (resolveVerSpec .latest tags).toOption = some "v2.5.0" := by native_decide

-- major v1 = max under v1 (v1.3.2).
example : (resolveVerSpec (.major "1") tags).toOption = some "v1.3.2" := by native_decide

-- major-minor v1.0 = max under v1.0 (only v1.0.0).
example : (resolveVerSpec (.majorMinor "1" "0") tags).toOption = some "v1.0.0" := by native_decide

-- exact is returned as-is, no tag lookup.
example : (resolveVerSpec (.exact "v9.9.9") []).toOption = some "v9.9.9" := by native_decide

-- A prerelease-only pool for a major ⇒ typed error (no non-prerelease match).
example : (resolveVerSpec (.major "2") ["v2.0.0-rc.1", "v2.1.0-beta"]).toOption = none := by
  native_decide

-- An empty / no-match tag list ⇒ typed error, never a silent pick.
example : (resolveVerSpec .latest []).toOption = none := by native_decide

-- ## modGetResolveAndApply: end-to-end (offline), re-parsing the emitted module.cue

-- Re-read the emitted module.cue's deps (round-trip through the real parser).
private def reDeps (src : String) : Option (List Dep) :=
  match parseSource src with
  | .ok v => some (parseDeps v)
  | .error _ => none

-- Add an exact dep to a deps-less module: byte-identical to `cue mod get` v0.16.1 (block form).
example :
    (modGetResolveAndApply blockForm "foo.example/bar@v1.2.3" []).toOption
      = some ("v1.2.3",
          "module: \"app.example@v0\"\nlanguage: {\n\tversion: \"v0.15.4\"\n}\n"
          ++ "deps: {\n\t\"foo.example/bar@v1\": {\n\t\tv: \"v1.2.3\"\n\t}\n}\n") := by
  native_decide

-- Bare `get` resolves `latest` against the tag list, then emits.
example :
    (modGetResolveAndApply blockForm "foo.example/bar" tags).toOption.map (·.1) = some "v2.5.0" := by
  native_decide

example :
    ((modGetResolveAndApply blockForm "foo.example/bar" tags).toOption.map (·.2)).bind reDeps
      = some [dep "foo.example/bar" "v2.5.0"] := by native_decide

private def existingV1 : String :=
  "module: \"a.example/a@v0\"\nlanguage: version: \"v0.15.4\"\ndeps: {\n\t\"c.example/c@v1\": v: \"v1.2.0\"\n}\n"

-- Update the same-major dep in place (one-line-form input preserved; deps re-rendered canonically).
example :
    ((modGetResolveAndApply existingV1 "c.example/c@v1.3.0" []).toOption.map (·.2)).bind reDeps
      = some [dep "c.example/c" "v1.3.0"] := by native_decide

-- Add a second major alongside the existing entry.
example :
    ((modGetResolveAndApply existingV1 "c.example/c@v2.0.0" []).toOption.map (·.2)).bind reDeps
      = some [dep "c.example/c" "v1.2.0", dep "c.example/c" "v2.0.0"] := by native_decide

-- No-op: requesting the version already pinned re-emits the same single entry.
example :
    ((modGetResolveAndApply existingV1 "c.example/c@v1.2.0" []).toOption.map (·.2)).bind reDeps
      = some [dep "c.example/c" "v1.2.0"] := by native_decide

-- Downgrade is permitted (get sets the requested version, MVS/tidy is a separate concern).
example :
    (modGetResolveAndApply existingV1 "c.example/c@v1.1.0" []).toOption.map (·.1) = some "v1.1.0" := by
  native_decide

-- Empty module path ⇒ typed error.
example : (modGetResolveAndApply blockForm "@v1.0.0" []).toOption = none := by native_decide

-- Unrecognized version constraint ⇒ typed error.
example : (modGetResolveAndApply blockForm "foo.example/bar@garbage" []).toOption = none := by
  native_decide

end ModCmd
end Kue
