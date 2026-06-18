import Kue.Order

namespace Kue

theorem top_subsumes_primitive :
    subsumes .top (.prim (.int 1)) = true := by
  native_decide

theorem kind_subsumes_matching_primitive :
    subsumes (.kind .int) (.prim (.int 1)) = true := by
  native_decide

theorem kind_does_not_subsume_other_primitive :
    subsumes (.kind .int) (.prim (.string "x")) = false := by
  native_decide

theorem primitive_subsumes_identical_primitive :
    subsumes (.prim (.int 1)) (.prim (.int 1)) = true := by
  native_decide

theorem primitive_does_not_subsume_distinct_primitive :
    subsumes (.prim (.int 1)) (.prim (.int 2)) = false := by
  native_decide

theorem value_subsumes_bottom :
    subsumes (.kind .int) .bottom = true := by
  native_decide

theorem disjunction_subsumes_matching_alternative :
    subsumes
      (.disj [(.regular, .prim (.string "a")), (.regular, .prim (.string "b"))])
      (.prim (.string "b"))
      = true := by
  native_decide

theorem closed_struct_subsumes_matching_struct :
    subsumes
      (.struct [⟨"a", .regular, .kind .int⟩] .defClosed none [])
      (.struct [⟨"a", .regular, .prim (.int 1)⟩] .defClosed none [])
      = true := by
  native_decide

theorem closed_struct_rejects_extra_field :
    subsumes
      (.struct [⟨"a", .regular, .kind .int⟩] .defClosed none [])
      (.struct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [])
      = false := by
  native_decide

theorem open_struct_accepts_extra_field :
    subsumes
      (.struct [⟨"a", .regular, .kind .int⟩] .regularOpen none [])
      (.struct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [])
      = true := by
  native_decide

theorem typed_tail_subsumes_matching_extra_field :
    subsumes
      (.struct [⟨"a", .regular, .kind .int⟩] .defOpenViaTail (some (.kind .string)) [])
      (.struct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [])
      = true := by
  native_decide

theorem typed_tail_rejects_conflicting_extra_field :
    subsumes
      (.struct [⟨"a", .regular, .kind .int⟩] .defOpenViaTail (some (.kind .string)) [])
      (.struct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.int 2)⟩] .regularOpen none [])
      = false := by
  native_decide

theorem string_pattern_subsumes_matching_regular_fields :
    subsumes
      (.struct [] .regularOpen none [((.kind .string), (.kind .int))])
      (.struct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.int 2)⟩] .regularOpen none [])
      = true := by
  native_decide

theorem string_pattern_rejects_conflicting_regular_field :
    subsumes
      (.struct [] .regularOpen none [((.kind .string), (.kind .int))])
      (.struct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [])
      = false := by
  native_decide

theorem exact_label_pattern_ignores_non_matching_regular_field :
    subsumes
      (.struct [] .regularOpen none [((.prim (.string "a")), (.kind .int))])
      (.struct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [])
      = true := by
  native_decide

theorem exact_label_pattern_rejects_matching_conflict :
    subsumes
      (.struct [] .regularOpen none [((.prim (.string "a")), (.kind .int))])
      (.struct [⟨"a", .regular, .prim (.string "x")⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [])
      = false := by
  native_decide

theorem regex_label_pattern_ignores_non_matching_regular_field :
    subsumes
      (.struct [] .regularOpen none [((.stringRegex "^a$"), (.kind .int))])
      (.struct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [])
      = true := by
  native_decide

theorem regex_label_pattern_rejects_matching_conflict :
    subsumes
      (.struct [] .regularOpen none [((.stringRegex "^a$"), (.kind .int))])
      (.struct [⟨"a", .regular, .prim (.string "x")⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [])
      = false := by
  native_decide

theorem regex_wildcard_label_pattern_ignores_non_matching_regular_field :
    subsumes
      (.struct [] .regularOpen none [((.stringRegex "^a.*z$"), (.kind .int))])
      (.struct [⟨"abcz", .regular, .prim (.int 1)⟩, ⟨"abcy", .regular, .prim (.string "skip")⟩] .regularOpen none [])
      = true := by
  native_decide

theorem regex_wildcard_label_pattern_rejects_matching_conflict :
    subsumes
      (.struct [] .regularOpen none [((.stringRegex "^a.*z$"), (.kind .int))])
      (.struct [⟨"abcz", .regular, .prim (.string "bad")⟩, ⟨"abcy", .regular, .prim (.string "skip")⟩] .regularOpen none [])
      = false := by
  native_decide

theorem regex_plus_label_pattern_requires_one_character :
    subsumes
      (.struct [] .regularOpen none [((.stringRegex "^a.+z$"), (.kind .int))])
      (.struct [⟨"az", .regular, .prim (.string "skip")⟩, ⟨"abz", .regular, .prim (.int 2)⟩] .regularOpen none [])
      = true := by
  native_decide

theorem regex_question_label_pattern_rejects_matching_conflict :
    subsumes
      (.struct [] .regularOpen none [((.stringRegex "^colou?r$"), (.kind .int))])
      (.struct [
          ⟨"color", .regular, .prim (.string "bad")⟩,
          ⟨"colour", .regular, .prim (.int 2)⟩,
          ⟨"colouur", .regular, .prim (.string "skip")⟩
        ] .regularOpen none [])
      = false := by
  native_decide

theorem regex_class_label_pattern_subsumes_matching_regular_fields :
    subsumes
      (.struct [] .regularOpen none [((.stringRegex "^[ab]cz$"), (.kind .int))])
      (.struct [
          ⟨"acz", .regular, .prim (.int 1)⟩,
          ⟨"bcz", .regular, .prim (.int 2)⟩,
          ⟨"ccz", .regular, .prim (.string "skip")⟩
        ] .regularOpen none [])
      = true := by
  native_decide

theorem regex_range_label_pattern_rejects_matching_conflict :
    subsumes
      (.struct [] .regularOpen none [((.stringRegex "^a[0-9]z$"), (.kind .int))])
      (.struct [⟨"a5z", .regular, .prim (.string "bad")⟩, ⟨"axz", .regular, .prim (.string "skip")⟩] .regularOpen none [])
      = false := by
  native_decide

theorem escaped_regex_label_pattern_rejects_matching_conflict :
    subsumes
      (.struct [] .regularOpen none [((.stringRegex "^a\\.z$"), (.kind .int))])
      (.struct [⟨"a.z", .regular, .prim (.string "bad")⟩, ⟨"abz", .regular, .prim (.string "skip")⟩] .regularOpen none [])
      = false := by
  native_decide

theorem regex_digit_shorthand_subsumes_digit_and_ignores_literal_d :
    subsumes
      (.struct [] .regularOpen none [((.stringRegex "^a\\dz$"), (.kind .int))])
      (.struct [⟨"a5z", .regular, .prim (.int 1)⟩, ⟨"adz", .regular, .prim (.string "skip")⟩] .regularOpen none [])
      = true := by
  native_decide

theorem regex_negated_digit_shorthand_subsumes_non_digit :
    subsumes
      (.struct [] .regularOpen none [((.stringRegex "^a\\Dz$"), (.kind .int))])
      (.struct [⟨"a5z", .regular, .prim (.string "skip")⟩, ⟨"adz", .regular, .prim (.int 1)⟩] .regularOpen none [])
      = true := by
  native_decide

theorem regex_word_shorthand_rejects_matching_conflict :
    subsumes
      (.struct [] .regularOpen none [((.stringRegex "^a\\wz$"), (.kind .int))])
      (.struct [⟨"a_z", .regular, .prim (.string "bad")⟩, ⟨"a-z", .regular, .prim (.string "skip")⟩] .regularOpen none [])
      = false := by
  native_decide

theorem regex_negated_word_shorthand_rejects_matching_conflict :
    subsumes
      (.struct [] .regularOpen none [((.stringRegex "^a\\Wz$"), (.kind .int))])
      (.struct [⟨"a_z", .regular, .prim (.string "skip")⟩, ⟨"a-z", .regular, .prim (.string "bad")⟩] .regularOpen none [])
      = false := by
  native_decide

theorem regex_space_shorthand_rejects_matching_conflict :
    subsumes
      (.struct [] .regularOpen none [((.stringRegex "^a\\sz$"), (.kind .int))])
      (.struct [⟨"a z", .regular, .prim (.string "bad")⟩, ⟨"a_z", .regular, .prim (.string "skip")⟩] .regularOpen none [])
      = false := by
  native_decide

theorem regex_negated_space_shorthand_rejects_matching_conflict :
    subsumes
      (.struct [] .regularOpen none [((.stringRegex "^a\\Sz$"), (.kind .int))])
      (.struct [⟨"a z", .regular, .prim (.string "skip")⟩, ⟨"a_z", .regular, .prim (.string "bad")⟩] .regularOpen none [])
      = false := by
  native_decide

theorem regex_exact_repetition_rejects_matching_conflict :
    subsumes
      (.struct [] .regularOpen none [((.stringRegex "^a\\d{2}z$"), (.kind .int))])
      (.struct [⟨"a12z", .regular, .prim (.string "bad")⟩, ⟨"a1z", .regular, .prim (.string "skip")⟩] .regularOpen none [])
      = false := by
  native_decide

theorem regex_bounded_repetition_rejects_matching_conflict :
    subsumes
      (.struct [] .regularOpen none [((.stringRegex "^a\\d{2,3}z$"), (.kind .int))])
      (.struct [
          ⟨"a12z", .regular, .prim (.int 2)⟩,
          ⟨"a123z", .regular, .prim (.string "bad")⟩,
          ⟨"a1z", .regular, .prim (.string "skip")⟩
        ] .regularOpen none [])
      = false := by
  native_decide

theorem regex_top_level_alternation_subsumes_each_alternative :
    subsumes
      (.struct [] .regularOpen none [((.stringRegex "^cat$|^dog$"), (.kind .int))])
      (.struct [
          ⟨"cat", .regular, .prim (.string "bad")⟩,
          ⟨"dog", .regular, .prim (.int 2)⟩,
          ⟨"cow", .regular, .prim (.string "skip")⟩
        ] .regularOpen none [])
      = false := by
  native_decide

theorem regex_parenthesized_alternation_subsumes_each_alternative :
    subsumes
      (.struct [] .regularOpen none [((.stringRegex "^(cat|dog)$"), (.kind .int))])
      (.struct [
          ⟨"cat", .regular, .prim (.string "bad")⟩,
          ⟨"dog", .regular, .prim (.int 2)⟩,
          ⟨"cow", .regular, .prim (.string "skip")⟩
        ] .regularOpen none [])
      = false := by
  native_decide

theorem multiple_patterns_subsume_fields_satisfying_each_independent_constraint :
    subsumes
      (.struct
        []
        .regularOpen
        none
        [(.stringRegex "^a", .kind .int), (.stringRegex "z$", .kind .string)])
      (.struct [
          ⟨"ax", .regular, .prim (.int 2)⟩,
          ⟨"bz", .regular, .prim (.string "ok")⟩
        ] .regularOpen none [])
      = true := by
  native_decide

theorem multiple_patterns_reject_field_matching_conflicting_constraints :
    subsumes
      (.struct
        []
        .regularOpen
        none
        [(.stringRegex "^a", .kind .int), (.stringRegex "z$", .kind .string)])
      (.struct [⟨"az", .regular, .prim (.int 1)⟩] .regularOpen none [])
      = false := by
  native_decide

theorem closed_regex_pattern_rejects_non_matching_regular_field :
    subsumes
      (.struct [] .defClosed none [((.stringRegex "^a$"), (.kind .int))])
      (.struct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.int 2)⟩] .regularOpen none [])
      = false := by
  native_decide

theorem closed_struct_subsumes_hidden_and_definition_extra_fields :
    subsumes
      (.struct [⟨"a", .regular, .kind .int⟩] .defClosed none [])
      (.struct [
          ⟨"a", .regular, .prim (.int 1)⟩,
          ⟨"_h", .hidden, .prim (.string "secret")⟩,
          ⟨"#D", .definition, .kind .string⟩
        ] .regularOpen none [])
      = true := by
  native_decide

theorem closed_regex_pattern_subsumes_hidden_and_definition_extra_fields :
    subsumes
      (.struct [] .defClosed none [((.stringRegex "^a$"), (.kind .int))])
      (.struct [
          ⟨"a", .regular, .prim (.int 1)⟩,
          ⟨"_h", .hidden, .prim (.string "secret")⟩,
          ⟨"#D", .definition, .kind .string⟩
        ] .regularOpen none [])
      = true := by
  native_decide

end Kue
