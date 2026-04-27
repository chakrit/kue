import Kue.Format
import Kue.Lattice

namespace Kue

def oneFieldStruct : Value :=
  .struct [("a", .regular, .prim (.int 1))] true

theorem format_regular_struct :
    formatValue oneFieldStruct = "{a: 1}" := by
  native_decide

theorem format_non_regular_field_classes :
    formatValue
      (.struct
        [
          ("a", .optional, .kind .int),
          ("b", .required, .kind .string),
          ("_c", .hidden, .prim (.bool true)),
          ("#D", .definition, .kind .bool)
        ]
        true)
      = "{a?: int, b!: string, _c: true, #D: bool}" := by
  native_decide

theorem meet_disjoint_regular_structs :
    meet
      (.struct [("a", .regular, .prim (.int 1))] true)
      (.struct [("b", .regular, .prim (.string "x"))] true)
      =
        .struct
          [
            ("a", .regular, .prim (.int 1)),
            ("b", .regular, .prim (.string "x"))
          ]
          true := by
  rfl

theorem meet_same_regular_field :
    meet
      (.struct [("a", .regular, .kind .int)] true)
      (.struct [("a", .regular, .prim (.int 1))] true)
      = .struct [("a", .regular, .prim (.int 1))] true := by
  rfl

theorem meet_conflicting_regular_field_bottoms_struct :
    meet
      (.struct [("a", .regular, .prim (.string "a"))] true)
      (.struct [("a", .regular, .prim (.string "b"))] true)
      = .bottom := by
  rfl

theorem meet_optional_field_waits_when_absent :
    meet
      (.struct [("a", .optional, .kind .int)] true)
      (.struct [("b", .regular, .prim (.string "x"))] true)
      =
        .struct
          [
            ("a", .optional, .kind .int),
            ("b", .regular, .prim (.string "x"))
          ]
          true := by
  rfl

theorem meet_optional_field_constrains_regular :
    meet
      (.struct [("a", .optional, .kind .int)] true)
      (.struct [("a", .regular, .prim (.int 1))] true)
      = .struct [("a", .regular, .prim (.int 1))] true := by
  rfl

theorem meet_required_field_constrains_regular :
    meet
      (.struct [("a", .required, .kind .int)] true)
      (.struct [("a", .regular, .prim (.int 1))] true)
      = .struct [("a", .regular, .prim (.int 1))] true := by
  rfl

theorem meet_conflicting_required_field_bottoms_struct :
    meet
      (.struct [("a", .required, .kind .int)] true)
      (.struct [("a", .regular, .prim (.string "x"))] true)
      = .bottom := by
  rfl

theorem meet_hidden_field_values :
    meet
      (.struct [("_a", .hidden, .kind .int)] true)
      (.struct [("_a", .hidden, .prim (.int 1))] true)
      = .struct [("_a", .hidden, .prim (.int 1))] true := by
  rfl

theorem meet_definition_field_values :
    meet
      (.struct [("#A", .definition, .kind .int)] true)
      (.struct [("#A", .definition, .prim (.int 1))] true)
      = .struct [("#A", .definition, .prim (.int 1))] true := by
  rfl

end Kue
