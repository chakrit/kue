import Kue.Normalize

namespace Kue

theorem definition_struct_normalizes_closed :
    (normalizeDefinitions
      (.struct [("#A", .definition, .struct [("a", .regular, .kind .int)] true)] true)
      == .struct [("#A", .definition, .struct [("a", .regular, .kind .int)] false)] true) = true := by
  native_decide

theorem regular_struct_field_stays_open :
    (normalizeDefinitions
      (.struct [("a", .regular, .struct [("b", .regular, .kind .int)] true)] true)
      == .struct [("a", .regular, .struct [("b", .regular, .kind .int)] true)] true) = true := by
  native_decide

theorem definition_typed_tail_stays_typed_tail :
    (normalizeDefinitions
      (.struct [("#A", .definition, .structTail [("a", .regular, .kind .int)] (.kind .string))] true)
      == .struct [("#A", .definition, .structTail [("a", .regular, .kind .int)] (.kind .string))] true) = true := by
  native_decide

theorem nested_definition_struct_normalizes_closed :
    (normalizeDefinitions
      (.struct
        [
          (
            "#A",
            .definition,
            .struct [("#B", .definition, .struct [("b", .regular, .kind .string)] true)] true
          )
        ]
        true)
      ==
        .struct
          [
            (
              "#A",
              .definition,
              .struct [("#B", .definition, .struct [("b", .regular, .kind .string)] false)] false
            )
          ]
          true) = true := by
  native_decide

end Kue
