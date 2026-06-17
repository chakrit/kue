import Kue.Builtin
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

theorem format_let_bindings_are_not_output_fields :
    formatValue
      (.struct [("base", .letBinding, .prim (.int 2)), ("x", .regular, .prim (.int 2))] true)
      = "{x: 2}" := by
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
      = .struct [("a", .regular, .bottomWith [.fieldConflict "a"])] true := by
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
      = .struct [("a", .regular, .bottomWith [.fieldConflict "a"])] true := by
  rfl

theorem format_field_level_bottom :
    formatValue (.struct [("a", .regular, .bottomWith [.fieldConflict "a"])] true) = "{a: _|_}" := by
  native_decide

/-- Optionality is a lattice, not a set of incompatible tags: `a? & a!` meets to `a!`
    (required dominates over optional; oracle-confirmed `cue v0.16.1` — the result is a
    required-but-not-present field, not a contradiction). The pre-orthogonality enum wrongly
    bottomed this combination. -/
theorem meet_optional_with_required_yields_required :
    meet
      (.struct [("a", .optional, .kind .int)] true)
      (.struct [("a", .required, .kind .int)] true)
      = .struct [("a", .required, .kind .int)] true := by
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

/-- Optional definition (`#x?`) meets the provided definition (`#x`) to a present
    definition carrying the value — the orthogonal axes compose (definition stays,
    optional → regular). The pre-orthogonality enum could not represent `#x?` at all and
    refused this merge. Oracle: `cue v0.16.1` `#D:{#x?:string}; y:#D&{#x:"hi"}` → `#x:"hi"`. -/
theorem meet_optional_definition_with_provided_definition :
    meet
      (.struct [("#x", .field true false .optional, .kind .string)] true)
      (.struct [("#x", .definition, .prim (.string "hi"))] true)
      = .struct [("#x", .definition, .prim (.string "hi"))] true := by
  rfl

/-- Optional hidden (`_x?`) meets provided hidden (`_x`): hidden stays, optional →
    regular. Oracle: `cue v0.16.1` `{_x?:int} & {_x:5}` selects `_x` as `5`. -/
theorem meet_optional_hidden_with_provided_hidden :
    meet
      (.struct [("_x", .field false true .optional, .kind .int)] true)
      (.struct [("_x", .hidden, .prim (.int 5))] true)
      = .struct [("_x", .hidden, .prim (.int 5))] true := by
  rfl

/-- Required definition (`#x!`) meets provided definition (`#x`): the regular conjunct
    discharges `!`, so the field becomes present. Oracle: `#y!:int` & `#y:3` → `#y:3`. -/
theorem meet_required_definition_discharged_by_value :
    meet
      (.struct [("#y", .field true false .required, .kind .int)] true)
      (.struct [("#y", .definition, .prim (.int 3))] true)
      = .struct [("#y", .definition, .prim (.int 3))] true := by
  rfl

/-- A definition (`#x?`/`#x`) — optional or not — ignores closedness on both axes;
    a definition does not contribute to manifest output regardless of its presence rung;
    an optional definition is not output, but a provided (`regular`) definition is still
    non-output (it is a definition). -/
theorem optional_definition_axes :
    (FieldClass.isDefinition (.field true false .optional) == true
      && FieldClass.ignoresClosedness (.field true false .optional) == true
      && FieldClass.producesOutput (.field true false .optional) == false
      && FieldClass.producesOutput (.field true false .regular) == false) = true := by
  native_decide

/-- The optionality lattice: `regular` (present) dominates and discharges `required`;
    `required` dominates `optional`; `optional & optional` stays optional. -/
theorem optionality_meet_lattice :
    (Optionality.meet .regular .required == .regular
      && Optionality.meet .required .regular == .regular
      && Optionality.meet .required .optional == .required
      && Optionality.meet .optional .required == .required
      && Optionality.meet .optional .optional == .optional
      && Optionality.meet .regular .optional == .regular) = true := by
  native_decide

theorem meet_closed_struct_allows_matching_field :
    meet
      (.struct [("a", .regular, .kind .int)] false)
      (.struct [("a", .regular, .prim (.int 1))] true)
      = .struct [("a", .regular, .prim (.int 1))] false := by
  rfl

theorem meet_closed_left_rejects_extra_right_field :
    meet
      (.struct [("a", .regular, .kind .int)] false)
      (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.string "x"))] true)
      =
        .struct
          [
            ("a", .regular, .prim (.int 1)),
            ("b", .regular, .bottomWith [.fieldNotAllowed "b"])
          ]
          false := by
  rfl

theorem meet_closed_struct_allows_hidden_and_definition_extra_fields :
    meet
      (.struct [("a", .regular, .kind .int)] false)
      (.struct
        [
          ("a", .regular, .prim (.int 1)),
          ("_h", .hidden, .prim (.string "secret")),
          ("#D", .definition, .kind .string)
        ]
        true)
      =
        .struct
          [
            ("a", .regular, .prim (.int 1)),
            ("_h", .hidden, .prim (.string "secret")),
            ("#D", .definition, .kind .string)
          ]
          false := by
  rfl

theorem meet_closed_right_rejects_extra_left_field :
    meet
      (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.string "x"))] true)
      (.struct [("a", .regular, .kind .int)] false)
      =
        .struct
          [
            ("a", .regular, .prim (.int 1)),
            ("b", .regular, .bottomWith [.fieldNotAllowed "b"])
          ]
          false := by
  rfl

theorem meet_open_structs_accept_extra_field :
    meet
      (.struct [("a", .regular, .kind .int)] true)
      (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.string "x"))] true)
      =
        .struct
          [
            ("a", .regular, .prim (.int 1)),
            ("b", .regular, .prim (.string "x"))
          ]
          true := by
  rfl

theorem format_typed_ellipsis :
    formatValue (.structTail [("a", .regular, .kind .int)] (.kind .string))
      = "{a: int, ...string}" := by
  native_decide

theorem format_untyped_struct_ellipsis :
    formatValue (.structTail [("a", .regular, .kind .int)] .top)
      = "{a: int, ...}" := by
  native_decide

theorem format_string_pattern_constraint :
    formatValue (.structPattern [] (.kind .string) (.kind .int) true) = "{[string]: int}" := by
  native_decide

theorem format_exact_label_pattern_constraint :
    formatValue (.structPattern [] (.prim (.string "a")) (.kind .int) true) = "{[\"a\"]: int}" := by
  native_decide

theorem format_regex_label_pattern_constraint :
    formatValue (.structPattern [] (.stringRegex "^a$") (.kind .int) true) = "{[=~\"^a$\"]: int}" := by
  native_decide

theorem format_multiple_pattern_constraints :
    formatValue
      (.structPatterns
        []
        [(.stringRegex "^a", .kind .int), (.stringRegex "z$", .kind .string)]
        true)
      = "{[=~\"^a\"]: int, [=~\"z$\"]: string}" := by
  native_decide

theorem format_regular_field_label_requiring_quotes :
    formatValue (.struct [("a.z", .regular, .prim (.int 1))] true) = "{\"a.z\": 1}" := by
  native_decide

theorem format_escaped_regex_label_pattern_constraint :
    formatValue (.structPattern [] (.stringRegex "^a\\.z$") (.kind .int) true)
      = "{[=~\"^a\\\\.z$\"]: int}" := by
  native_decide

theorem meet_typed_ellipsis_accepts_matching_extra_field :
    meet
      (.structTail [("a", .regular, .kind .int)] (.kind .string))
      (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.string "x"))] true)
      =
        .structTail
          [
            ("a", .regular, .prim (.int 1)),
            ("b", .regular, .prim (.string "x"))
          ]
          (.kind .string) := by
  rfl

theorem meet_typed_ellipsis_rejects_conflicting_extra_field :
    meet
      (.structTail [("a", .regular, .kind .int)] (.kind .string))
      (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.int 2))] true)
      =
        .structTail
          [
            ("a", .regular, .prim (.int 1)),
            ("b", .regular, .bottomWith [.fieldConstraint "b"])
          ]
          (.kind .string) := by
  rfl

theorem meet_typed_ellipsis_does_not_constrain_declared_field_by_tail :
    meet
      (.structTail [("a", .regular, .kind .int)] (.kind .string))
      (.struct [("a", .regular, .prim (.int 1))] true)
      = .structTail [("a", .regular, .prim (.int 1))] (.kind .string) := by
  rfl

theorem meet_nested_struct_field_uses_struct_meet :
    meet
      (.struct [("x", .regular, .struct [("a", .regular, .kind .int)] true)] true)
      (.struct [("x", .regular, .struct [("a", .regular, .prim (.int 1))] true)] true)
      = .struct [("x", .regular, .struct [("a", .regular, .prim (.int 1))] true)] true := by
  rfl

theorem meet_string_pattern_constrains_regular_field :
    meet
      (.structPattern [] (.kind .string) (.kind .int) true)
      (.struct [("a", .regular, .prim (.int 1))] true)
      = .structPattern [("a", .regular, .prim (.int 1))] (.kind .string) (.kind .int) true := by
  rfl

theorem meet_string_pattern_rejects_conflicting_regular_field :
    meet
      (.structPattern [] (.kind .string) (.kind .int) true)
      (.struct [("a", .regular, .prim (.string "x"))] true)
      = .structPattern
          [("a", .regular, .bottomWith [.fieldConstraint "a"])]
          (.kind .string)
          (.kind .int)
          true := by
  rfl

theorem meet_string_pattern_constrains_declared_pattern_field :
    meet
      (.structPattern [("a", .regular, .kind .number)] (.kind .string) (.kind .int) true)
      (.struct [("a", .regular, .prim (.int 1))] true)
      = .structPattern [("a", .regular, .prim (.int 1))] (.kind .string) (.kind .int) true := by
  rfl

theorem meet_exact_label_pattern_skips_other_regular_fields :
    meet
      (.structPattern [] (.prim (.string "a")) (.kind .int) true)
      (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.string "x"))] true)
      =
        .structPattern
          [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.string "x"))]
          (.prim (.string "a"))
          (.kind .int)
          true := by
  rfl

theorem meet_exact_label_pattern_rejects_matching_conflict :
    meet
      (.structPattern [] (.prim (.string "a")) (.kind .int) true)
      (.struct [("a", .regular, .prim (.string "x")), ("b", .regular, .prim (.string "x"))] true)
      =
        .structPattern
          [("a", .regular, .bottomWith [.fieldConstraint "a"]), ("b", .regular, .prim (.string "x"))]
          (.prim (.string "a"))
          (.kind .int)
          true := by
  rfl

theorem meet_regex_label_pattern_skips_non_matching_regular_fields :
    (meet
      (.structPattern [] (.stringRegex "^a$") (.kind .int) true)
      (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.string "x"))] true)
      ==
        .structPattern
          [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.string "x"))]
          (.stringRegex "^a$")
          (.kind .int)
          true) = true := by
  native_decide

theorem meet_regex_label_pattern_rejects_matching_conflict :
    (meet
      (.structPattern [] (.stringRegex "^a$") (.kind .int) true)
      (.struct [("a", .regular, .prim (.string "x")), ("b", .regular, .prim (.string "x"))] true)
      ==
        .structPattern
          [("a", .regular, .bottomWith [.fieldConstraint "a"]), ("b", .regular, .prim (.string "x"))]
          (.stringRegex "^a$")
          (.kind .int)
          true) = true := by
  native_decide

theorem meet_regex_wildcard_label_pattern_constrains_matching_field :
    (meet
      (.structPattern [] (.stringRegex "^a.*z$") (.kind .int) true)
      (.struct [("abcz", .regular, .prim (.int 1)), ("abcy", .regular, .prim (.string "skip"))] true)
      ==
        .structPattern
          [("abcz", .regular, .prim (.int 1)), ("abcy", .regular, .prim (.string "skip"))]
          (.stringRegex "^a.*z$")
          (.kind .int)
          true) = true := by
  native_decide

theorem meet_regex_wildcard_label_pattern_rejects_matching_conflict :
    (meet
      (.structPattern [] (.stringRegex "^a.*z$") (.kind .int) true)
      (.struct [("abcz", .regular, .prim (.string "bad")), ("abcy", .regular, .prim (.string "skip"))] true)
      ==
        .structPattern
          [
            ("abcz", .regular, .bottomWith [.fieldConstraint "abcz"]),
            ("abcy", .regular, .prim (.string "skip"))
          ]
          (.stringRegex "^a.*z$")
          (.kind .int)
          true) = true := by
  native_decide

theorem meet_regex_plus_label_pattern_requires_one_character :
    (meet
      (.structPattern [] (.stringRegex "^a.+z$") (.kind .int) true)
      (.struct [("az", .regular, .prim (.string "skip")), ("abz", .regular, .prim (.int 2))] true)
      ==
        .structPattern
          [("az", .regular, .prim (.string "skip")), ("abz", .regular, .prim (.int 2))]
          (.stringRegex "^a.+z$")
          (.kind .int)
          true) = true := by
  native_decide

theorem meet_regex_question_label_pattern_allows_zero_or_one_atom :
    (meet
      (.structPattern [] (.stringRegex "^colou?r$") (.kind .int) true)
      (.struct
        [
          ("color", .regular, .prim (.string "bad")),
          ("colour", .regular, .prim (.int 2)),
          ("colouur", .regular, .prim (.string "skip"))
        ]
        true)
      ==
        .structPattern
          [
            ("color", .regular, .bottomWith [.fieldConstraint "color"]),
            ("colour", .regular, .prim (.int 2)),
            ("colouur", .regular, .prim (.string "skip"))
          ]
          (.stringRegex "^colou?r$")
          (.kind .int)
          true) = true := by
  native_decide

theorem meet_regex_class_label_pattern_constrains_matching_fields :
    (meet
      (.structPattern [] (.stringRegex "^[ab]cz$") (.kind .int) true)
      (.struct
        [
          ("acz", .regular, .prim (.int 1)),
          ("bcz", .regular, .prim (.int 2)),
          ("ccz", .regular, .prim (.string "skip"))
        ]
        true)
      ==
        .structPattern
          [
            ("acz", .regular, .prim (.int 1)),
            ("bcz", .regular, .prim (.int 2)),
            ("ccz", .regular, .prim (.string "skip"))
          ]
          (.stringRegex "^[ab]cz$")
          (.kind .int)
          true) = true := by
  native_decide

theorem meet_regex_range_label_pattern_rejects_matching_conflict :
    (meet
      (.structPattern [] (.stringRegex "^a[0-9]z$") (.kind .int) true)
      (.struct [("a5z", .regular, .prim (.string "bad")), ("axz", .regular, .prim (.string "skip"))] true)
      ==
        .structPattern
          [
            ("a5z", .regular, .bottomWith [.fieldConstraint "a5z"]),
            ("axz", .regular, .prim (.string "skip"))
          ]
          (.stringRegex "^a[0-9]z$")
          (.kind .int)
          true) = true := by
  native_decide

theorem meet_escaped_regex_label_pattern_rejects_matching_conflict :
    (meet
      (.structPattern [] (.stringRegex "^a\\.z$") (.kind .int) true)
      (.struct [("a.z", .regular, .prim (.string "bad")), ("abz", .regular, .prim (.string "skip"))] true)
      ==
        .structPattern
          [
            ("a.z", .regular, .bottomWith [.fieldConstraint "a.z"]),
            ("abz", .regular, .prim (.string "skip"))
          ]
          (.stringRegex "^a\\.z$")
          (.kind .int)
          true) = true := by
  native_decide

theorem meet_regex_digit_shorthand_rejects_matching_conflict :
    (meet
      (.structPattern [] (.stringRegex "^a\\dz$") (.kind .int) true)
      (.struct [("a5z", .regular, .prim (.string "bad")), ("adz", .regular, .prim (.string "skip"))] true)
      ==
        .structPattern
          [
            ("a5z", .regular, .bottomWith [.fieldConstraint "a5z"]),
            ("adz", .regular, .prim (.string "skip"))
          ]
          (.stringRegex "^a\\dz$")
          (.kind .int)
          true) = true := by
  native_decide

theorem meet_regex_negated_digit_shorthand_rejects_matching_conflict :
    (meet
      (.structPattern [] (.stringRegex "^a\\Dz$") (.kind .int) true)
      (.struct [("a5z", .regular, .prim (.string "skip")), ("adz", .regular, .prim (.string "bad"))] true)
      ==
        .structPattern
          [
            ("a5z", .regular, .prim (.string "skip")),
            ("adz", .regular, .bottomWith [.fieldConstraint "adz"])
          ]
          (.stringRegex "^a\\Dz$")
          (.kind .int)
          true) = true := by
  native_decide

theorem meet_regex_word_shorthand_rejects_matching_conflict :
    (meet
      (.structPattern [] (.stringRegex "^a\\wz$") (.kind .int) true)
      (.struct [("a_z", .regular, .prim (.string "bad")), ("a-z", .regular, .prim (.string "skip"))] true)
      ==
        .structPattern
          [
            ("a_z", .regular, .bottomWith [.fieldConstraint "a_z"]),
            ("a-z", .regular, .prim (.string "skip"))
          ]
          (.stringRegex "^a\\wz$")
          (.kind .int)
          true) = true := by
  native_decide

theorem meet_regex_negated_word_shorthand_rejects_matching_conflict :
    (meet
      (.structPattern [] (.stringRegex "^a\\Wz$") (.kind .int) true)
      (.struct [("a_z", .regular, .prim (.string "skip")), ("a-z", .regular, .prim (.string "bad"))] true)
      ==
        .structPattern
          [
            ("a_z", .regular, .prim (.string "skip")),
            ("a-z", .regular, .bottomWith [.fieldConstraint "a-z"])
          ]
          (.stringRegex "^a\\Wz$")
          (.kind .int)
          true) = true := by
  native_decide

theorem meet_regex_space_shorthand_rejects_matching_conflict :
    (meet
      (.structPattern [] (.stringRegex "^a\\sz$") (.kind .int) true)
      (.struct [("a z", .regular, .prim (.string "bad")), ("a_z", .regular, .prim (.string "skip"))] true)
      ==
        .structPattern
          [
            ("a z", .regular, .bottomWith [.fieldConstraint "a z"]),
            ("a_z", .regular, .prim (.string "skip"))
          ]
          (.stringRegex "^a\\sz$")
          (.kind .int)
          true) = true := by
  native_decide

theorem meet_regex_negated_space_shorthand_rejects_matching_conflict :
    (meet
      (.structPattern [] (.stringRegex "^a\\Sz$") (.kind .int) true)
      (.struct [("a z", .regular, .prim (.string "skip")), ("a_z", .regular, .prim (.string "bad"))] true)
      ==
        .structPattern
          [
            ("a z", .regular, .prim (.string "skip")),
            ("a_z", .regular, .bottomWith [.fieldConstraint "a_z"])
          ]
          (.stringRegex "^a\\Sz$")
          (.kind .int)
          true) = true := by
  native_decide

theorem meet_regex_exact_repetition_rejects_matching_conflict :
    (meet
      (.structPattern [] (.stringRegex "^a\\d{2}z$") (.kind .int) true)
      (.struct [("a12z", .regular, .prim (.string "bad")), ("a1z", .regular, .prim (.string "skip"))] true)
      ==
        .structPattern
          [
            ("a12z", .regular, .bottomWith [.fieldConstraint "a12z"]),
            ("a1z", .regular, .prim (.string "skip"))
          ]
          (.stringRegex "^a\\d{2}z$")
          (.kind .int)
          true) = true := by
  native_decide

theorem meet_regex_bounded_repetition_rejects_matching_conflict :
    (meet
      (.structPattern [] (.stringRegex "^a\\d{2,3}z$") (.kind .int) true)
      (.struct
        [
          ("a12z", .regular, .prim (.int 2)),
          ("a123z", .regular, .prim (.string "bad")),
          ("a1z", .regular, .prim (.string "skip"))
        ]
        true)
      ==
        .structPattern
          [
            ("a12z", .regular, .prim (.int 2)),
            ("a123z", .regular, .bottomWith [.fieldConstraint "a123z"]),
            ("a1z", .regular, .prim (.string "skip"))
          ]
          (.stringRegex "^a\\d{2,3}z$")
          (.kind .int)
          true) = true := by
  native_decide

theorem meet_regex_top_level_alternation_constrains_each_alternative :
    (meet
      (.structPattern [] (.stringRegex "^cat$|^dog$") (.kind .int) true)
      (.struct
        [
          ("cat", .regular, .prim (.string "bad")),
          ("dog", .regular, .prim (.int 2)),
          ("cow", .regular, .prim (.string "skip"))
        ]
        true)
      ==
        .structPattern
          [
            ("cat", .regular, .bottomWith [.fieldConstraint "cat"]),
            ("dog", .regular, .prim (.int 2)),
            ("cow", .regular, .prim (.string "skip"))
          ]
          (.stringRegex "^cat$|^dog$")
          (.kind .int)
          true) = true := by
  native_decide

theorem meet_regex_parenthesized_alternation_constrains_each_alternative :
    (meet
      (.structPattern [] (.stringRegex "^(cat|dog)$") (.kind .int) true)
      (.struct
        [
          ("cat", .regular, .prim (.string "bad")),
          ("dog", .regular, .prim (.int 2)),
          ("cow", .regular, .prim (.string "skip"))
        ]
        true)
      ==
        .structPattern
          [
            ("cat", .regular, .bottomWith [.fieldConstraint "cat"]),
            ("dog", .regular, .prim (.int 2)),
            ("cow", .regular, .prim (.string "skip"))
          ]
          (.stringRegex "^(cat|dog)$")
          (.kind .int)
          true) = true := by
  native_decide

theorem meet_multiple_pattern_constraints_remain_independent :
    (meet
      (.structPatterns
        []
        [(.stringRegex "^a", .kind .int), (.stringRegex "z$", .kind .string)]
        true)
      (.struct
        [
          ("az", .regular, .prim (.int 1)),
          ("ax", .regular, .prim (.int 2)),
          ("bz", .regular, .prim (.string "ok"))
        ]
        true)
      ==
        .structPatterns
          [
            ("az", .regular, .bottomWith [.fieldConstraint "az"]),
            ("ax", .regular, .prim (.int 2)),
            ("bz", .regular, .prim (.string "ok"))
          ]
          [(.stringRegex "^a", .kind .int), (.stringRegex "z$", .kind .string)]
          true) = true := by
  native_decide

theorem close_value_marks_struct_pattern_closed :
    closeValue (.structPattern [] (.stringRegex "^a$") (.kind .int) true)
      = .structPattern [] (.stringRegex "^a$") (.kind .int) false := by
  rfl

theorem closed_pattern_rejects_non_matching_extra_regular_field :
    (meet
      (closeValue (.structPattern [] (.stringRegex "^a$") (.kind .int) true))
      (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.int 2))] true)
      ==
        .structPattern
          [("a", .regular, .prim (.int 1)), ("b", .regular, .bottomWith [.fieldNotAllowed "b"])]
          (.stringRegex "^a$")
          (.kind .int)
          false) = true := by
  native_decide

theorem closed_pattern_allows_hidden_and_definition_extra_fields :
    (meet
      (closeValue (.structPattern [] (.stringRegex "^a$") (.kind .int) true))
      (.struct
        [
          ("a", .regular, .prim (.int 1)),
          ("_h", .hidden, .prim (.string "secret")),
          ("#D", .definition, .kind .string)
        ]
        true)
      ==
        .structPattern
          [
            ("a", .regular, .prim (.int 1)),
            ("_h", .hidden, .prim (.string "secret")),
            ("#D", .definition, .kind .string)
          ]
          (.stringRegex "^a$")
          (.kind .int)
          false) = true := by
  native_decide

theorem closed_multiple_patterns_allow_any_matching_regular_field :
    (meet
      (closeValue
        (.structPatterns
          []
          [(.stringRegex "^a", .kind .int), (.stringRegex "z$", .kind .string)]
          true))
      (.struct
        [
          ("ax", .regular, .prim (.int 2)),
          ("bz", .regular, .prim (.string "ok")),
          ("m", .regular, .prim (.int 3))
        ]
        true)
      ==
        .structPatterns
          [
            ("ax", .regular, .prim (.int 2)),
            ("bz", .regular, .prim (.string "ok")),
            ("m", .regular, .bottomWith [.fieldNotAllowed "m"])
          ]
          [(.stringRegex "^a", .kind .int), (.stringRegex "z$", .kind .string)]
          false) = true := by
  native_decide

end Kue
