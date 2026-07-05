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

end ModCmd
end Kue
