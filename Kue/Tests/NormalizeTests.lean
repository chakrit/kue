import Kue.Normalize

namespace Kue

theorem definition_struct_normalizes_closed :
    (normalizeDefinitions
      (mkStruct [⟨"#A", .definition, mkStruct [⟨"a", .regular, .kind .int, false⟩] .regularOpen none [], false⟩] .regularOpen none [])
      == mkStruct [⟨"#A", .definition, mkStruct [⟨"a", .regular, .kind .int, false⟩] .defClosed none [], false⟩] .regularOpen none []) = true := by
  native_decide

theorem regular_struct_field_stays_open :
    (normalizeDefinitions
      (mkStruct [⟨"a", .regular, mkStruct [⟨"b", .regular, .kind .int, false⟩] .regularOpen none [], false⟩] .regularOpen none [])
      == mkStruct [⟨"a", .regular, mkStruct [⟨"b", .regular, .kind .int, false⟩] .regularOpen none [], false⟩] .regularOpen none []) = true := by
  native_decide

theorem definition_typed_tail_stays_typed_tail :
    (normalizeDefinitions
      (mkStruct [⟨"#A", .definition, mkStruct [⟨"a", .regular, .kind .int, false⟩] .defOpenViaTail (some (.kind .string)) [], false⟩] .regularOpen none [])
      == mkStruct [⟨"#A", .definition, mkStruct [⟨"a", .regular, .kind .int, false⟩] .defOpenViaTail (some (.kind .string)) [], false⟩] .regularOpen none []) = true := by
  native_decide

-- SWEEP fix (A1/B1 class): a definition field whose value is directly a `.list` (or comprehension/
-- embeddedList/dynamicField) carrying a nested `#Def` struct would have its body SWALLOWED by a
-- `| _, value => value` catch-all, leaving the nested def unclosed (admitting extra fields where
-- CUE rejects). The `.list` arm descends with the closing normalizer; nested `#Inner` closes.
theorem definition_list_value_closes_nested_definition :
    (normalizeDefinitions
      (mkStruct [⟨"#L", .definition,
        .list [mkStruct [⟨"#Inner", .definition, mkStruct [⟨"x", .regular, .kind .int, false⟩] .regularOpen none [], false⟩] .regularOpen none []], false⟩] .regularOpen none [])
      == mkStruct [⟨"#L", .definition,
        .list [mkStruct [⟨"#Inner", .definition, mkStruct [⟨"x", .regular, .kind .int, false⟩] .defClosed none [], false⟩] .defClosed none []], false⟩] .regularOpen none [])
        = true := by
  native_decide

-- A comprehension body that is a nested def inside a definition field is likewise closed (the
-- `.comprehension` arm; pre-fix the whole comprehension was swallowed).
theorem definition_comprehension_body_closes_nested_definition :
    (normalizeDefinitions
      (mkStruct [⟨"#C", .definition,
        .comprehension [.guard .top]
          (mkStruct [⟨"#Inner", .definition, mkStruct [⟨"x", .regular, .kind .int, false⟩] .regularOpen none [], false⟩] .regularOpen none []), false⟩] .regularOpen none [])
      == mkStruct [⟨"#C", .definition,
        .comprehension [.guard .top]
          (mkStruct [⟨"#Inner", .definition, mkStruct [⟨"x", .regular, .kind .int, false⟩] .defClosed none [], false⟩] .defClosed none []), false⟩] .regularOpen none [])
        = true := by
  native_decide

theorem nested_definition_struct_normalizes_closed :
    (normalizeDefinitions
      (mkStruct [
          ⟨
            "#A",
            .definition,
            mkStruct [⟨"#B", .definition, mkStruct [⟨"b", .regular, .kind .string, false⟩] .regularOpen none [], false⟩] .regularOpen none []
          , false⟩
        ] .regularOpen none [])
      ==
        mkStruct [
            ⟨
              "#A",
              .definition,
              mkStruct [⟨"#B", .definition, mkStruct [⟨"b", .regular, .kind .string, false⟩] .defClosed none [], false⟩] .defClosed none []
            , false⟩
          ] .regularOpen none []) = true := by
  native_decide



-- COVERAGE TRIPWIRE (test-health). Anchors the last theorem of each section;
-- a swallowed section makes its anchor an unknown identifier and fails `#check`
-- elaboration.
#check @nested_definition_struct_normalizes_closed

end Kue
