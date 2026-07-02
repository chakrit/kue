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
      (mkStruct [⟨"a", .regular, .kind .int⟩] .defClosed none [])
      (mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .defClosed none [])
      = true := by
  native_decide

theorem closed_struct_rejects_extra_field :
    subsumes
      (mkStruct [⟨"a", .regular, .kind .int⟩] .defClosed none [])
      (mkStruct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [])
      = false := by
  native_decide

theorem open_struct_accepts_extra_field :
    subsumes
      (mkStruct [⟨"a", .regular, .kind .int⟩] .regularOpen none [])
      (mkStruct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [])
      = true := by
  native_decide

theorem typed_tail_subsumes_matching_extra_field :
    subsumes
      (mkStruct [⟨"a", .regular, .kind .int⟩] .defOpenViaTail (some (.kind .string)) [])
      (mkStruct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [])
      = true := by
  native_decide

theorem typed_tail_rejects_conflicting_extra_field :
    subsumes
      (mkStruct [⟨"a", .regular, .kind .int⟩] .defOpenViaTail (some (.kind .string)) [])
      (mkStruct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.int 2)⟩] .regularOpen none [])
      = false := by
  native_decide

theorem string_pattern_subsumes_matching_regular_fields :
    subsumes
      (mkStruct [] .regularOpen none [((.kind .string), (.kind .int))])
      (mkStruct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.int 2)⟩] .regularOpen none [])
      = true := by
  native_decide

theorem string_pattern_rejects_conflicting_regular_field :
    subsumes
      (mkStruct [] .regularOpen none [((.kind .string), (.kind .int))])
      (mkStruct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [])
      = false := by
  native_decide

theorem exact_label_pattern_ignores_non_matching_regular_field :
    subsumes
      (mkStruct [] .regularOpen none [((.prim (.string "a")), (.kind .int))])
      (mkStruct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [])
      = true := by
  native_decide

theorem exact_label_pattern_rejects_matching_conflict :
    subsumes
      (mkStruct [] .regularOpen none [((.prim (.string "a")), (.kind .int))])
      (mkStruct [⟨"a", .regular, .prim (.string "x")⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [])
      = false := by
  native_decide

theorem regex_label_pattern_ignores_non_matching_regular_field :
    subsumes
      (mkStruct [] .regularOpen none [((.stringRegex "^a$"), (.kind .int))])
      (mkStruct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [])
      = true := by
  native_decide

theorem regex_label_pattern_rejects_matching_conflict :
    subsumes
      (mkStruct [] .regularOpen none [((.stringRegex "^a$"), (.kind .int))])
      (mkStruct [⟨"a", .regular, .prim (.string "x")⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [])
      = false := by
  native_decide

theorem regex_wildcard_label_pattern_ignores_non_matching_regular_field :
    subsumes
      (mkStruct [] .regularOpen none [((.stringRegex "^a.*z$"), (.kind .int))])
      (mkStruct [⟨"abcz", .regular, .prim (.int 1)⟩, ⟨"abcy", .regular, .prim (.string "skip")⟩] .regularOpen none [])
      = true := by
  native_decide

theorem regex_wildcard_label_pattern_rejects_matching_conflict :
    subsumes
      (mkStruct [] .regularOpen none [((.stringRegex "^a.*z$"), (.kind .int))])
      (mkStruct [⟨"abcz", .regular, .prim (.string "bad")⟩, ⟨"abcy", .regular, .prim (.string "skip")⟩] .regularOpen none [])
      = false := by
  native_decide

theorem regex_plus_label_pattern_requires_one_character :
    subsumes
      (mkStruct [] .regularOpen none [((.stringRegex "^a.+z$"), (.kind .int))])
      (mkStruct [⟨"az", .regular, .prim (.string "skip")⟩, ⟨"abz", .regular, .prim (.int 2)⟩] .regularOpen none [])
      = true := by
  native_decide

theorem regex_question_label_pattern_rejects_matching_conflict :
    subsumes
      (mkStruct [] .regularOpen none [((.stringRegex "^colou?r$"), (.kind .int))])
      (mkStruct [
          ⟨"color", .regular, .prim (.string "bad")⟩,
          ⟨"colour", .regular, .prim (.int 2)⟩,
          ⟨"colouur", .regular, .prim (.string "skip")⟩
        ] .regularOpen none [])
      = false := by
  native_decide

theorem regex_class_label_pattern_subsumes_matching_regular_fields :
    subsumes
      (mkStruct [] .regularOpen none [((.stringRegex "^[ab]cz$"), (.kind .int))])
      (mkStruct [
          ⟨"acz", .regular, .prim (.int 1)⟩,
          ⟨"bcz", .regular, .prim (.int 2)⟩,
          ⟨"ccz", .regular, .prim (.string "skip")⟩
        ] .regularOpen none [])
      = true := by
  native_decide

theorem regex_range_label_pattern_rejects_matching_conflict :
    subsumes
      (mkStruct [] .regularOpen none [((.stringRegex "^a[0-9]z$"), (.kind .int))])
      (mkStruct [⟨"a5z", .regular, .prim (.string "bad")⟩, ⟨"axz", .regular, .prim (.string "skip")⟩] .regularOpen none [])
      = false := by
  native_decide

theorem escaped_regex_label_pattern_rejects_matching_conflict :
    subsumes
      (mkStruct [] .regularOpen none [((.stringRegex "^a\\.z$"), (.kind .int))])
      (mkStruct [⟨"a.z", .regular, .prim (.string "bad")⟩, ⟨"abz", .regular, .prim (.string "skip")⟩] .regularOpen none [])
      = false := by
  native_decide

theorem regex_digit_shorthand_subsumes_digit_and_ignores_literal_d :
    subsumes
      (mkStruct [] .regularOpen none [((.stringRegex "^a\\dz$"), (.kind .int))])
      (mkStruct [⟨"a5z", .regular, .prim (.int 1)⟩, ⟨"adz", .regular, .prim (.string "skip")⟩] .regularOpen none [])
      = true := by
  native_decide

theorem regex_negated_digit_shorthand_subsumes_non_digit :
    subsumes
      (mkStruct [] .regularOpen none [((.stringRegex "^a\\Dz$"), (.kind .int))])
      (mkStruct [⟨"a5z", .regular, .prim (.string "skip")⟩, ⟨"adz", .regular, .prim (.int 1)⟩] .regularOpen none [])
      = true := by
  native_decide

theorem regex_word_shorthand_rejects_matching_conflict :
    subsumes
      (mkStruct [] .regularOpen none [((.stringRegex "^a\\wz$"), (.kind .int))])
      (mkStruct [⟨"a_z", .regular, .prim (.string "bad")⟩, ⟨"a-z", .regular, .prim (.string "skip")⟩] .regularOpen none [])
      = false := by
  native_decide

theorem regex_negated_word_shorthand_rejects_matching_conflict :
    subsumes
      (mkStruct [] .regularOpen none [((.stringRegex "^a\\Wz$"), (.kind .int))])
      (mkStruct [⟨"a_z", .regular, .prim (.string "skip")⟩, ⟨"a-z", .regular, .prim (.string "bad")⟩] .regularOpen none [])
      = false := by
  native_decide

theorem regex_space_shorthand_rejects_matching_conflict :
    subsumes
      (mkStruct [] .regularOpen none [((.stringRegex "^a\\sz$"), (.kind .int))])
      (mkStruct [⟨"a z", .regular, .prim (.string "bad")⟩, ⟨"a_z", .regular, .prim (.string "skip")⟩] .regularOpen none [])
      = false := by
  native_decide

theorem regex_negated_space_shorthand_rejects_matching_conflict :
    subsumes
      (mkStruct [] .regularOpen none [((.stringRegex "^a\\Sz$"), (.kind .int))])
      (mkStruct [⟨"a z", .regular, .prim (.string "skip")⟩, ⟨"a_z", .regular, .prim (.string "bad")⟩] .regularOpen none [])
      = false := by
  native_decide

theorem regex_exact_repetition_rejects_matching_conflict :
    subsumes
      (mkStruct [] .regularOpen none [((.stringRegex "^a\\d{2}z$"), (.kind .int))])
      (mkStruct [⟨"a12z", .regular, .prim (.string "bad")⟩, ⟨"a1z", .regular, .prim (.string "skip")⟩] .regularOpen none [])
      = false := by
  native_decide

theorem regex_bounded_repetition_rejects_matching_conflict :
    subsumes
      (mkStruct [] .regularOpen none [((.stringRegex "^a\\d{2,3}z$"), (.kind .int))])
      (mkStruct [
          ⟨"a12z", .regular, .prim (.int 2)⟩,
          ⟨"a123z", .regular, .prim (.string "bad")⟩,
          ⟨"a1z", .regular, .prim (.string "skip")⟩
        ] .regularOpen none [])
      = false := by
  native_decide

theorem regex_top_level_alternation_subsumes_each_alternative :
    subsumes
      (mkStruct [] .regularOpen none [((.stringRegex "^cat$|^dog$"), (.kind .int))])
      (mkStruct [
          ⟨"cat", .regular, .prim (.string "bad")⟩,
          ⟨"dog", .regular, .prim (.int 2)⟩,
          ⟨"cow", .regular, .prim (.string "skip")⟩
        ] .regularOpen none [])
      = false := by
  native_decide

theorem regex_parenthesized_alternation_subsumes_each_alternative :
    subsumes
      (mkStruct [] .regularOpen none [((.stringRegex "^(cat|dog)$"), (.kind .int))])
      (mkStruct [
          ⟨"cat", .regular, .prim (.string "bad")⟩,
          ⟨"dog", .regular, .prim (.int 2)⟩,
          ⟨"cow", .regular, .prim (.string "skip")⟩
        ] .regularOpen none [])
      = false := by
  native_decide

theorem multiple_patterns_subsume_fields_satisfying_each_independent_constraint :
    subsumes
      (mkStruct
        []
        .regularOpen
        none
        [(.stringRegex "^a", .kind .int), (.stringRegex "z$", .kind .string)])
      (mkStruct [
          ⟨"ax", .regular, .prim (.int 2)⟩,
          ⟨"bz", .regular, .prim (.string "ok")⟩
        ] .regularOpen none [])
      = true := by
  native_decide

theorem multiple_patterns_reject_field_matching_conflicting_constraints :
    subsumes
      (mkStruct
        []
        .regularOpen
        none
        [(.stringRegex "^a", .kind .int), (.stringRegex "z$", .kind .string)])
      (mkStruct [⟨"az", .regular, .prim (.int 1)⟩] .regularOpen none [])
      = false := by
  native_decide

theorem closed_regex_pattern_rejects_non_matching_regular_field :
    subsumes
      (mkStruct [] .defClosed none [((.stringRegex "^a$"), (.kind .int))])
      (mkStruct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.int 2)⟩] .regularOpen none [])
      = false := by
  native_decide

theorem closed_struct_subsumes_hidden_and_definition_extra_fields :
    subsumes
      (mkStruct [⟨"a", .regular, .kind .int⟩] .defClosed none [])
      (mkStruct [
          ⟨"a", .regular, .prim (.int 1)⟩,
          ⟨"_h", .hidden, .prim (.string "secret")⟩,
          ⟨"#D", .definition, .kind .string⟩
        ] .regularOpen none [])
      = true := by
  native_decide

theorem closed_regex_pattern_subsumes_hidden_and_definition_extra_fields :
    subsumes
      (mkStruct [] .defClosed none [((.stringRegex "^a$"), (.kind .int))])
      (mkStruct [
          ⟨"a", .regular, .prim (.int 1)⟩,
          ⟨"_h", .hidden, .prim (.string "secret")⟩,
          ⟨"#D", .definition, .kind .string⟩
        ] .regularOpen none [])
      = true := by
  native_decide

-- ## RX-2b — an invalid regex constraint subsumes nothing
--
-- `.stringRegex` with an invalid concrete pattern is an unsatisfiable (bottom) constraint;
-- the `.stringRegex`-vs-string subsumes arm guards on `regexParseError?` and returns `false`
-- before `matchRegex`. A VALID pattern still subsumes a matching string exactly as before.

theorem invalid_regex_constraint_subsumes_nothing :
    subsumes (.stringRegex "a(") (.prim (.string "x")) = false := by
  native_decide

theorem valid_regex_constraint_subsumes_match :
    (subsumes (.stringRegex "^a") (.prim (.string "abc")) == true
      && subsumes (.stringRegex "^a") (.prim (.string "zzz")) == false) = true := by
  native_decide



-- COVERAGE TRIPWIRE (test-health). Anchors the last theorem of each section;
-- a swallowed section makes its anchor an unknown identifier and fails `#check`
-- elaboration.
#check @closed_regex_pattern_subsumes_hidden_and_definition_extra_fields
#check @valid_regex_constraint_subsumes_match                              -- RX-2b — an invalid regex constraint subsumes nothing

end Kue
