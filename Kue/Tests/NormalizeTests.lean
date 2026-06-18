import Kue.Normalize

namespace Kue

theorem definition_struct_normalizes_closed :
    (normalizeDefinitions
      (.struct [⟨"#A", .definition, .struct [⟨"a", .regular, .kind .int⟩] true⟩] true)
      == .struct [⟨"#A", .definition, .struct [⟨"a", .regular, .kind .int⟩] false⟩] true) = true := by
  native_decide

theorem regular_struct_field_stays_open :
    (normalizeDefinitions
      (.struct [⟨"a", .regular, .struct [⟨"b", .regular, .kind .int⟩] true⟩] true)
      == .struct [⟨"a", .regular, .struct [⟨"b", .regular, .kind .int⟩] true⟩] true) = true := by
  native_decide

theorem definition_typed_tail_stays_typed_tail :
    (normalizeDefinitions
      (.struct [⟨"#A", .definition, .structTail [⟨"a", .regular, .kind .int⟩] (.kind .string)⟩] true)
      == .struct [⟨"#A", .definition, .structTail [⟨"a", .regular, .kind .int⟩] (.kind .string)⟩] true) = true := by
  native_decide

-- SWEEP fix (A1/B1 class): a definition field whose value is directly a `.list` (or comprehension/
-- embeddedList/dynamicField) carrying a nested `#Def` struct had its body SWALLOWED by the old
-- `| _, value => value` catch-all, so the nested def was never closed (admitting extra fields where
-- CUE rejects). The `.list` arm descends with the closing normalizer; nested `#Inner` closes.
theorem definition_list_value_closes_nested_definition :
    (normalizeDefinitions
      (.struct [⟨"#L", .definition,
        .list [.struct [⟨"#Inner", .definition, .struct [⟨"x", .regular, .kind .int⟩] true⟩] true]⟩] true)
      == .struct [⟨"#L", .definition,
        .list [.struct [⟨"#Inner", .definition, .struct [⟨"x", .regular, .kind .int⟩] false⟩] false]⟩] true)
        = true := by
  native_decide

-- A comprehension body that is a nested def inside a definition field is likewise closed (the
-- `.comprehension` arm; pre-fix the whole comprehension was swallowed).
theorem definition_comprehension_body_closes_nested_definition :
    (normalizeDefinitions
      (.struct [⟨"#C", .definition,
        .comprehension [.guard .top]
          (.struct [⟨"#Inner", .definition, .struct [⟨"x", .regular, .kind .int⟩] true⟩] true)⟩] true)
      == .struct [⟨"#C", .definition,
        .comprehension [.guard .top]
          (.struct [⟨"#Inner", .definition, .struct [⟨"x", .regular, .kind .int⟩] false⟩] false)⟩] true)
        = true := by
  native_decide

theorem nested_definition_struct_normalizes_closed :
    (normalizeDefinitions
      (.struct
        [
          ⟨
            "#A",
            .definition,
            .struct [⟨"#B", .definition, .struct [⟨"b", .regular, .kind .string⟩] true⟩] true
          ⟩
        ]
        true)
      ==
        .struct
          [
            ⟨
              "#A",
              .definition,
              .struct [⟨"#B", .definition, .struct [⟨"b", .regular, .kind .string⟩] false⟩] false
            ⟩
          ]
          true) = true := by
  native_decide

end Kue
