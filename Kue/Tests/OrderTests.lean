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
      (.structN [⟨"a", .regular, .kind .int⟩] .defClosed none [])
      (.structN [⟨"a", .regular, .prim (.int 1)⟩] .defClosed none [])
      = true := by
  native_decide

theorem closed_struct_rejects_extra_field :
    subsumes
      (.structN [⟨"a", .regular, .kind .int⟩] .defClosed none [])
      (.structN [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [])
      = false := by
  native_decide

theorem open_struct_accepts_extra_field :
    subsumes
      (.structN [⟨"a", .regular, .kind .int⟩] .regularOpen none [])
      (.structN [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [])
      = true := by
  native_decide

theorem typed_tail_subsumes_matching_extra_field :
    subsumes
      (.structN [⟨"a", .regular, .kind .int⟩] .defOpenViaTail (some (.kind .string)) [])
      (.structN [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [])
      = true := by
  native_decide

theorem typed_tail_rejects_conflicting_extra_field :
    subsumes
      (.structN [⟨"a", .regular, .kind .int⟩] .defOpenViaTail (some (.kind .string)) [])
      (.structN [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.int 2)⟩] .regularOpen none [])
      = false := by
  native_decide

theorem string_pattern_subsumes_matching_regular_fields :
    subsumes
      (.structN [] .regularOpen none [((.kind .string), (.kind .int))])
      (.structN [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.int 2)⟩] .regularOpen none [])
      = true := by
  native_decide

theorem string_pattern_rejects_conflicting_regular_field :
    subsumes
      (.structN [] .regularOpen none [((.kind .string), (.kind .int))])
      (.structN [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [])
      = false := by
  native_decide

theorem exact_label_pattern_ignores_non_matching_regular_field :
    subsumes
      (.structN [] .regularOpen none [((.prim (.string "a")), (.kind .int))])
      (.structN [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [])
      = true := by
  native_decide

theorem exact_label_pattern_rejects_matching_conflict :
    subsumes
      (.structN [] .regularOpen none [((.prim (.string "a")), (.kind .int))])
      (.structN [⟨"a", .regular, .prim (.string "x")⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [])
      = false := by
  native_decide

theorem regex_label_pattern_ignores_non_matching_regular_field :
    subsumes
      (.structN [] .regularOpen none [((.stringRegex "^a$"), (.kind .int))])
      (.structN [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [])
      = true := by
  native_decide

theorem regex_label_pattern_rejects_matching_conflict :
    subsumes
      (.structN [] .regularOpen none [((.stringRegex "^a$"), (.kind .int))])
      (.structN [⟨"a", .regular, .prim (.string "x")⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [])
      = false := by
  native_decide

theorem regex_wildcard_label_pattern_ignores_non_matching_regular_field :
    subsumes
      (.structN [] .regularOpen none [((.stringRegex "^a.*z$"), (.kind .int))])
      (.structN [⟨"abcz", .regular, .prim (.int 1)⟩, ⟨"abcy", .regular, .prim (.string "skip")⟩] .regularOpen none [])
      = true := by
  native_decide

theorem regex_wildcard_label_pattern_rejects_matching_conflict :
    subsumes
      (.structN [] .regularOpen none [((.stringRegex "^a.*z$"), (.kind .int))])
      (.structN [⟨"abcz", .regular, .prim (.string "bad")⟩, ⟨"abcy", .regular, .prim (.string "skip")⟩] .regularOpen none [])
      = false := by
  native_decide

theorem regex_plus_label_pattern_requires_one_character :
    subsumes
      (.structN [] .regularOpen none [((.stringRegex "^a.+z$"), (.kind .int))])
      (.structN [⟨"az", .regular, .prim (.string "skip")⟩, ⟨"abz", .regular, .prim (.int 2)⟩] .regularOpen none [])
      = true := by
  native_decide

theorem regex_question_label_pattern_rejects_matching_conflict :
    subsumes
      (.structN [] .regularOpen none [((.stringRegex "^colou?r$"), (.kind .int))])
      (.structN [
          ⟨"color", .regular, .prim (.string "bad")⟩,
          ⟨"colour", .regular, .prim (.int 2)⟩,
          ⟨"colouur", .regular, .prim (.string "skip")⟩
        ] .regularOpen none [])
      = false := by
  native_decide

theorem regex_class_label_pattern_subsumes_matching_regular_fields :
    subsumes
      (.structN [] .regularOpen none [((.stringRegex "^[ab]cz$"), (.kind .int))])
      (.structN [
          ⟨"acz", .regular, .prim (.int 1)⟩,
          ⟨"bcz", .regular, .prim (.int 2)⟩,
          ⟨"ccz", .regular, .prim (.string "skip")⟩
        ] .regularOpen none [])
      = true := by
  native_decide

theorem regex_range_label_pattern_rejects_matching_conflict :
    subsumes
      (.structN [] .regularOpen none [((.stringRegex "^a[0-9]z$"), (.kind .int))])
      (.structN [⟨"a5z", .regular, .prim (.string "bad")⟩, ⟨"axz", .regular, .prim (.string "skip")⟩] .regularOpen none [])
      = false := by
  native_decide

theorem escaped_regex_label_pattern_rejects_matching_conflict :
    subsumes
      (.structN [] .regularOpen none [((.stringRegex "^a\\.z$"), (.kind .int))])
      (.structN [⟨"a.z", .regular, .prim (.string "bad")⟩, ⟨"abz", .regular, .prim (.string "skip")⟩] .regularOpen none [])
      = false := by
  native_decide

theorem regex_digit_shorthand_subsumes_digit_and_ignores_literal_d :
    subsumes
      (.structN [] .regularOpen none [((.stringRegex "^a\\dz$"), (.kind .int))])
      (.structN [⟨"a5z", .regular, .prim (.int 1)⟩, ⟨"adz", .regular, .prim (.string "skip")⟩] .regularOpen none [])
      = true := by
  native_decide

theorem regex_negated_digit_shorthand_subsumes_non_digit :
    subsumes
      (.structN [] .regularOpen none [((.stringRegex "^a\\Dz$"), (.kind .int))])
      (.structN [⟨"a5z", .regular, .prim (.string "skip")⟩, ⟨"adz", .regular, .prim (.int 1)⟩] .regularOpen none [])
      = true := by
  native_decide

theorem regex_word_shorthand_rejects_matching_conflict :
    subsumes
      (.structN [] .regularOpen none [((.stringRegex "^a\\wz$"), (.kind .int))])
      (.structN [⟨"a_z", .regular, .prim (.string "bad")⟩, ⟨"a-z", .regular, .prim (.string "skip")⟩] .regularOpen none [])
      = false := by
  native_decide

theorem regex_negated_word_shorthand_rejects_matching_conflict :
    subsumes
      (.structN [] .regularOpen none [((.stringRegex "^a\\Wz$"), (.kind .int))])
      (.structN [⟨"a_z", .regular, .prim (.string "skip")⟩, ⟨"a-z", .regular, .prim (.string "bad")⟩] .regularOpen none [])
      = false := by
  native_decide

theorem regex_space_shorthand_rejects_matching_conflict :
    subsumes
      (.structN [] .regularOpen none [((.stringRegex "^a\\sz$"), (.kind .int))])
      (.structN [⟨"a z", .regular, .prim (.string "bad")⟩, ⟨"a_z", .regular, .prim (.string "skip")⟩] .regularOpen none [])
      = false := by
  native_decide

theorem regex_negated_space_shorthand_rejects_matching_conflict :
    subsumes
      (.structN [] .regularOpen none [((.stringRegex "^a\\Sz$"), (.kind .int))])
      (.structN [⟨"a z", .regular, .prim (.string "skip")⟩, ⟨"a_z", .regular, .prim (.string "bad")⟩] .regularOpen none [])
      = false := by
  native_decide

theorem regex_exact_repetition_rejects_matching_conflict :
    subsumes
      (.structN [] .regularOpen none [((.stringRegex "^a\\d{2}z$"), (.kind .int))])
      (.structN [⟨"a12z", .regular, .prim (.string "bad")⟩, ⟨"a1z", .regular, .prim (.string "skip")⟩] .regularOpen none [])
      = false := by
  native_decide

theorem regex_bounded_repetition_rejects_matching_conflict :
    subsumes
      (.structN [] .regularOpen none [((.stringRegex "^a\\d{2,3}z$"), (.kind .int))])
      (.structN [
          ⟨"a12z", .regular, .prim (.int 2)⟩,
          ⟨"a123z", .regular, .prim (.string "bad")⟩,
          ⟨"a1z", .regular, .prim (.string "skip")⟩
        ] .regularOpen none [])
      = false := by
  native_decide

theorem regex_top_level_alternation_subsumes_each_alternative :
    subsumes
      (.structN [] .regularOpen none [((.stringRegex "^cat$|^dog$"), (.kind .int))])
      (.structN [
          ⟨"cat", .regular, .prim (.string "bad")⟩,
          ⟨"dog", .regular, .prim (.int 2)⟩,
          ⟨"cow", .regular, .prim (.string "skip")⟩
        ] .regularOpen none [])
      = false := by
  native_decide

theorem regex_parenthesized_alternation_subsumes_each_alternative :
    subsumes
      (.structN [] .regularOpen none [((.stringRegex "^(cat|dog)$"), (.kind .int))])
      (.structN [
          ⟨"cat", .regular, .prim (.string "bad")⟩,
          ⟨"dog", .regular, .prim (.int 2)⟩,
          ⟨"cow", .regular, .prim (.string "skip")⟩
        ] .regularOpen none [])
      = false := by
  native_decide

theorem multiple_patterns_subsume_fields_satisfying_each_independent_constraint :
    subsumes
      (.structN
        []
        .regularOpen
        none
        [(.stringRegex "^a", .kind .int), (.stringRegex "z$", .kind .string)])
      (.structN [
          ⟨"ax", .regular, .prim (.int 2)⟩,
          ⟨"bz", .regular, .prim (.string "ok")⟩
        ] .regularOpen none [])
      = true := by
  native_decide

theorem multiple_patterns_reject_field_matching_conflicting_constraints :
    subsumes
      (.structN
        []
        .regularOpen
        none
        [(.stringRegex "^a", .kind .int), (.stringRegex "z$", .kind .string)])
      (.structN [⟨"az", .regular, .prim (.int 1)⟩] .regularOpen none [])
      = false := by
  native_decide

theorem closed_regex_pattern_rejects_non_matching_regular_field :
    subsumes
      (.structN [] .defClosed none [((.stringRegex "^a$"), (.kind .int))])
      (.structN [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.int 2)⟩] .regularOpen none [])
      = false := by
  native_decide

theorem closed_struct_subsumes_hidden_and_definition_extra_fields :
    subsumes
      (.structN [⟨"a", .regular, .kind .int⟩] .defClosed none [])
      (.structN [
          ⟨"a", .regular, .prim (.int 1)⟩,
          ⟨"_h", .hidden, .prim (.string "secret")⟩,
          ⟨"#D", .definition, .kind .string⟩
        ] .regularOpen none [])
      = true := by
  native_decide

theorem closed_regex_pattern_subsumes_hidden_and_definition_extra_fields :
    subsumes
      (.structN [] .defClosed none [((.stringRegex "^a$"), (.kind .int))])
      (.structN [
          ⟨"a", .regular, .prim (.int 1)⟩,
          ⟨"_h", .hidden, .prim (.string "secret")⟩,
          ⟨"#D", .definition, .kind .string⟩
        ] .regularOpen none [])
      = true := by
  native_decide

end Kue
