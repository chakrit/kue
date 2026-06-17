import Kue.Format
import Kue.Lattice
import Kue.Tests.BoundTests
import Kue.Tests.BuiltinTests
import Kue.Tests.BytesTests
import Kue.Tests.CliTests
import Kue.Tests.EvalTests
import Kue.Tests.ExclusionTests
import Kue.Tests.FixturePorts
import Kue.Tests.FixtureTests
import Kue.Tests.FloatTests
import Kue.Tests.ListTests
import Kue.Tests.ManifestTests
import Kue.Tests.ModuleTests
import Kue.Tests.NormalizeTests
import Kue.Tests.NumberTests
import Kue.Tests.OrderTests
import Kue.Tests.ParseTests
import Kue.Tests.PresenceTests
import Kue.Tests.ResolveTests
import Kue.Tests.RuntimeTests
import Kue.Tests.StructTests
import Kue.Tests.YamlTests

namespace Kue

theorem meet_top_left (value : Value) : meet .top value = value := by
  cases value <;> rfl

theorem meet_bottom_left (value : Value) : meet .bottom value = .bottom := by
  cases value <;> rfl

theorem join_bottom_left (value : Value) : join .bottom value = value := by
  cases value <;> rfl

theorem join_top_left (value : Value) : join .top value = .top := by
  cases value <;> rfl

theorem meetWithFuel_identical_prim (prim : Prim) :
    meetWithFuel 100 (.prim prim) (.prim prim) = .prim prim := by
  rw [meetWithFuel] <;> first | (unfold meetCore; simp [meetPrim]) | simp

theorem meet_identical_prim (prim : Prim) : meet (.prim prim) (.prim prim) = .prim prim := by
  rw [meet]
  exact meetWithFuel_identical_prim prim

theorem meet_conflicting_ints :
    meet (.prim (.int 1)) (.prim (.int 2))
      = .bottomWith [.primitiveConflict (.int 1) (.int 2)] := by
  rfl

theorem meet_conflicting_kinds_has_provenance :
    meet (.kind .int) (.kind .string)
      = .bottomWith [.kindConflict .int .string] := by
  rfl

theorem join_distinct_primitives_keeps_disjunction :
    join (.prim (.string "a")) (.prim (.string "b"))
      = .disj [(.regular, .prim (.string "a")), (.regular, .prim (.string "b"))] := by
  rfl

theorem meet_disjunction_distributes_and_removes_bottom :
    meet
      (.disj [(.regular, .prim (.string "a")), (.regular, .prim (.int 1))])
      (.kind .string)
      = .prim (.string "a") := by
  rfl

theorem meet_disjunction_preserves_default_marker :
    meet
      (.disj [(.default, .prim (.int 1)), (.regular, .prim (.string "a"))])
      (.kind .int)
      = .disj [(.default, .prim (.int 1))] := by
  rfl

theorem meet_struct_disjunction_distributes_with_struct_meet :
    meet
      (.disj
        [
          (.regular, .struct [⟨"kind", .regular, .prim (.string "web")⟩] true),
          (.regular, .struct [⟨"kind", .regular, .prim (.string "db")⟩] true)
        ])
      (.struct
        [⟨"kind", .regular, .prim (.string "web")⟩, ⟨"port", .regular, .prim (.int 80)⟩]
        true)
      =
        .struct
          [⟨"kind", .regular, .prim (.string "web")⟩, ⟨"port", .regular, .prim (.int 80)⟩]
          true := by
  rfl

#guard meet (.kind .int) (.prim (.int 1)) == .prim (.int 1)
#guard isBottom (meet (.prim (.string "a")) (.prim (.string "b")))
#guard formatValue (.bottomWith [.primitiveConflict (.string "a") (.string "b")]) == "_|_"
#guard join (.prim (.int 1)) (.prim (.int 2))
  == .disj [(.regular, .prim (.int 1)), (.regular, .prim (.int 2))]
#guard meet (.stringRegex "^a$") (.prim (.string "a")) == .prim (.string "a")
#guard isBottom (meet (.stringRegex "^a$") (.prim (.string "b")))
#guard join (.kind .string) (.stringRegex "^a$") == .kind .string
#guard formatValue (.builtinCall "len" [.kind .string]) == "len(string)"
#guard formatValue (.builtinCall "or" [.list []]) == "or([])"

end Kue
