import Kue.Builtin
import Kue.Format
import Kue.Lattice
import Kue.Runtime
import Kue.Tests.EvalTestHelpers

namespace Kue

def oneFieldStruct : Value :=
  mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []

theorem format_regular_struct :
    formatValue oneFieldStruct = "{a: 1}" := by
  native_decide

theorem format_non_regular_field_classes :
    formatValue
      (mkStruct [
          ⟨"a", .optional, .kind .int⟩,
          ⟨"b", .required, .kind .string⟩,
          ⟨"_c", .hidden, .prim (.bool true)⟩,
          ⟨"#D", .definition, .kind .bool⟩
        ] .regularOpen none [])
      = "{a?: int, b!: string, _c: true, #D: bool}" := by
  native_decide

theorem format_let_bindings_are_not_output_fields :
    formatValue
      (mkStruct [⟨"base", .letBinding, .prim (.int 2)⟩, ⟨"x", .regular, .prim (.int 2)⟩] .regularOpen none [])
      = "{x: 2}" := by
  native_decide

theorem meet_disjoint_regular_structs :
    meet
      (mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none [])
      (mkStruct [⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [])
      =
        mkStruct [
            ⟨"a", .regular, .prim (.int 1)⟩,
            ⟨"b", .regular, .prim (.string "x")⟩
          ] .regularOpen none [] := by
  rfl

theorem meet_same_regular_field :
    meet
      (mkStruct [⟨"a", .regular, .kind .int⟩] .regularOpen none [])
      (mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none [])
      = mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none [] := by
  rfl

theorem meet_conflicting_regular_field_bottoms_struct :
    meet
      (mkStruct [⟨"a", .regular, .prim (.string "a")⟩] .regularOpen none [])
      (mkStruct [⟨"a", .regular, .prim (.string "b")⟩] .regularOpen none [])
      = mkStruct [⟨"a", .regular, .bottomWith [.fieldConflict "a"]⟩] .regularOpen none [] := by
  rfl

theorem meet_optional_field_waits_when_absent :
    meet
      (mkStruct [⟨"a", .optional, .kind .int⟩] .regularOpen none [])
      (mkStruct [⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [])
      =
        mkStruct [
            ⟨"a", .optional, .kind .int⟩,
            ⟨"b", .regular, .prim (.string "x")⟩
          ] .regularOpen none [] := by
  rfl

theorem meet_optional_field_constrains_regular :
    meet
      (mkStruct [⟨"a", .optional, .kind .int⟩] .regularOpen none [])
      (mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none [])
      = mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none [] := by
  rfl

theorem meet_required_field_constrains_regular :
    meet
      (mkStruct [⟨"a", .required, .kind .int⟩] .regularOpen none [])
      (mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none [])
      = mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none [] := by
  rfl

theorem meet_conflicting_required_field_bottoms_struct :
    meet
      (mkStruct [⟨"a", .required, .kind .int⟩] .regularOpen none [])
      (mkStruct [⟨"a", .regular, .prim (.string "x")⟩] .regularOpen none [])
      = mkStruct [⟨"a", .regular, .bottomWith [.fieldConflict "a"]⟩] .regularOpen none [] := by
  rfl

theorem format_field_level_bottom :
    formatValue (mkStruct [⟨"a", .regular, .bottomWith [.fieldConflict "a"]⟩] .regularOpen none []) = "{a: _|_}" := by
  native_decide

/-- Optionality is a lattice, not a set of incompatible tags: `a? & a!` meets to `a!`
    (required dominates over optional; oracle-confirmed `cue v0.16.1` — the result is a
    required-but-not-present field, not a contradiction). The pre-orthogonality enum wrongly
    bottomed this combination. -/
theorem meet_optional_with_required_yields_required :
    meet
      (mkStruct [⟨"a", .optional, .kind .int⟩] .regularOpen none [])
      (mkStruct [⟨"a", .required, .kind .int⟩] .regularOpen none [])
      = mkStruct [⟨"a", .required, .kind .int⟩] .regularOpen none [] := by
  rfl

theorem meet_hidden_field_values :
    meet
      (mkStruct [⟨"_a", .hidden, .kind .int⟩] .regularOpen none [])
      (mkStruct [⟨"_a", .hidden, .prim (.int 1)⟩] .regularOpen none [])
      = mkStruct [⟨"_a", .hidden, .prim (.int 1)⟩] .regularOpen none [] := by
  rfl

theorem meet_definition_field_values :
    meet
      (mkStruct [⟨"#A", .definition, .kind .int⟩] .regularOpen none [])
      (mkStruct [⟨"#A", .definition, .prim (.int 1)⟩] .regularOpen none [])
      = mkStruct [⟨"#A", .definition, .prim (.int 1)⟩] .regularOpen none [] := by
  rfl

/-- Optional definition (`#x?`) meets the provided definition (`#x`) to a present
    definition carrying the value — the orthogonal axes compose (definition stays,
    optional → regular). The pre-orthogonality enum could not represent `#x?` at all and
    refused this merge. Oracle: `cue v0.16.1` `#D:{#x?:string}; y:#D&{#x:"hi"}` → `#x:"hi"`. -/
theorem meet_optional_definition_with_provided_definition :
    meet
      (mkStruct [⟨"#x", .field true false .optional, .kind .string⟩] .regularOpen none [])
      (mkStruct [⟨"#x", .definition, .prim (.string "hi")⟩] .regularOpen none [])
      = mkStruct [⟨"#x", .definition, .prim (.string "hi")⟩] .regularOpen none [] := by
  rfl

/-- Optional hidden (`_x?`) meets provided hidden (`_x`): hidden stays, optional →
    regular. Oracle: `cue v0.16.1` `{_x?:int} & {_x:5}` selects `_x` as `5`. -/
theorem meet_optional_hidden_with_provided_hidden :
    meet
      (mkStruct [⟨"_x", .field false true .optional, .kind .int⟩] .regularOpen none [])
      (mkStruct [⟨"_x", .hidden, .prim (.int 5)⟩] .regularOpen none [])
      = mkStruct [⟨"_x", .hidden, .prim (.int 5)⟩] .regularOpen none [] := by
  rfl

/-- Required definition (`#x!`) meets provided definition (`#x`): the regular conjunct
    discharges `!`, so the field becomes present. Oracle: `#y!:int` & `#y:3` → `#y:3`. -/
theorem meet_required_definition_discharged_by_value :
    meet
      (mkStruct [⟨"#y", .field true false .required, .kind .int⟩] .regularOpen none [])
      (mkStruct [⟨"#y", .definition, .prim (.int 3)⟩] .regularOpen none [])
      = mkStruct [⟨"#y", .definition, .prim (.int 3)⟩] .regularOpen none [] := by
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
      (mkStruct [⟨"a", .regular, .kind .int⟩] .defClosed none [])
      (mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none [])
      = mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .defClosed none [] [⟨["a"], []⟩] := by
  rfl

theorem meet_closed_left_rejects_extra_right_field :
    meet
      (mkStruct [⟨"a", .regular, .kind .int⟩] .defClosed none [])
      (mkStruct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [])
      =
        mkStruct [
            ⟨"a", .regular, .prim (.int 1)⟩,
            ⟨"b", .regular, .bottomWith [.fieldNotAllowed "b"]⟩
          ] .defClosed none [] [⟨["a"], []⟩] := by
  rfl

theorem meet_closed_struct_allows_hidden_and_definition_extra_fields :
    meet
      (mkStruct [⟨"a", .regular, .kind .int⟩] .defClosed none [])
      (mkStruct [
          ⟨"a", .regular, .prim (.int 1)⟩,
          ⟨"_h", .hidden, .prim (.string "secret")⟩,
          ⟨"#D", .definition, .kind .string⟩
        ] .regularOpen none [])
      =
        mkStruct [
            ⟨"a", .regular, .prim (.int 1)⟩,
            ⟨"_h", .hidden, .prim (.string "secret")⟩,
            ⟨"#D", .definition, .kind .string⟩
          ] .defClosed none [] [⟨["a"], []⟩] := by
  rfl

theorem meet_closed_right_rejects_extra_left_field :
    meet
      (mkStruct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [])
      (mkStruct [⟨"a", .regular, .kind .int⟩] .defClosed none [])
      =
        mkStruct [
            ⟨"a", .regular, .prim (.int 1)⟩,
            ⟨"b", .regular, .bottomWith [.fieldNotAllowed "b"]⟩
          ] .defClosed none [] [⟨["a"], []⟩] := by
  rfl

theorem meet_open_structs_accept_extra_field :
    meet
      (mkStruct [⟨"a", .regular, .kind .int⟩] .regularOpen none [])
      (mkStruct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [])
      =
        mkStruct [
            ⟨"a", .regular, .prim (.int 1)⟩,
            ⟨"b", .regular, .prim (.string "x")⟩
          ] .regularOpen none [] := by
  rfl

theorem format_typed_ellipsis :
    formatValue (mkStruct [⟨"a", .regular, .kind .int⟩] .defOpenViaTail (some (.kind .string)) [])
      = "{a: int, ...string}" := by
  native_decide

theorem format_untyped_struct_ellipsis :
    formatValue (mkStruct [⟨"a", .regular, .kind .int⟩] .defOpenViaTail (some .top) [])
      = "{a: int, ...}" := by
  native_decide

theorem format_string_pattern_constraint :
    formatValue (mkStruct [] .regularOpen none [((.kind .string), (.kind .int))]) = "{[string]: int}" := by
  native_decide

theorem format_exact_label_pattern_constraint :
    formatValue (mkStruct [] .regularOpen none [((.prim (.string "a")), (.kind .int))]) = "{[\"a\"]: int}" := by
  native_decide

theorem format_regex_label_pattern_constraint :
    formatValue (mkStruct [] .regularOpen none [((.stringRegex "^a$"), (.kind .int))]) = "{[=~\"^a$\"]: int}" := by
  native_decide

theorem format_multiple_pattern_constraints :
    formatValue
      (mkStruct [] .regularOpen none [(.stringRegex "^a", .kind .int), (.stringRegex "z$", .kind .string)])
      = "{[=~\"^a\"]: int, [=~\"z$\"]: string}" := by
  native_decide

theorem format_regular_field_label_requiring_quotes :
    formatValue (mkStruct [⟨"a.z", .regular, .prim (.int 1)⟩] .regularOpen none []) = "{\"a.z\": 1}" := by
  native_decide

theorem format_escaped_regex_label_pattern_constraint :
    formatValue (mkStruct [] .regularOpen none [((.stringRegex "^a\\.z$"), (.kind .int))])
      = "{[=~\"^a\\\\.z$\"]: int}" := by
  native_decide

theorem meet_typed_ellipsis_accepts_matching_extra_field :
    meet
      (mkStruct [⟨"a", .regular, .kind .int⟩] .defOpenViaTail (some (.kind .string)) [])
      (mkStruct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [])
      =
        mkStruct [
            ⟨"a", .regular, .prim (.int 1)⟩,
            ⟨"b", .regular, .prim (.string "x")⟩
          ] .defOpenViaTail (some (.kind .string)) [] := by
  rfl

theorem meet_typed_ellipsis_rejects_conflicting_extra_field :
    meet
      (mkStruct [⟨"a", .regular, .kind .int⟩] .defOpenViaTail (some (.kind .string)) [])
      (mkStruct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.int 2)⟩] .regularOpen none [])
      =
        mkStruct [
            ⟨"a", .regular, .prim (.int 1)⟩,
            ⟨"b", .regular, .bottomWith [.fieldConstraint "b"]⟩
          ] .defOpenViaTail (some (.kind .string)) [] := by
  rfl

theorem meet_typed_ellipsis_does_not_constrain_declared_field_by_tail :
    meet
      (mkStruct [⟨"a", .regular, .kind .int⟩] .defOpenViaTail (some (.kind .string)) [])
      (mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none [])
      = mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .defOpenViaTail (some (.kind .string)) [] := by
  rfl

theorem meet_nested_struct_field_uses_struct_meet :
    meet
      (mkStruct [⟨"x", .regular, mkStruct [⟨"a", .regular, .kind .int⟩] .regularOpen none []⟩] .regularOpen none [])
      (mkStruct [⟨"x", .regular, mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []⟩] .regularOpen none [])
      = mkStruct [⟨"x", .regular, mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []⟩] .regularOpen none [] := by
  rfl

theorem meet_string_pattern_constrains_regular_field :
    meet
      (mkStruct [] .regularOpen none [((.kind .string), (.kind .int))])
      (mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none [])
      = mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none [((.kind .string), (.kind .int))] := by
  rfl

theorem meet_string_pattern_rejects_conflicting_regular_field :
    meet
      (mkStruct [] .regularOpen none [((.kind .string), (.kind .int))])
      (mkStruct [⟨"a", .regular, .prim (.string "x")⟩] .regularOpen none [])
      = mkStruct [⟨"a", .regular, .bottomWith [.fieldConstraint "a"]⟩] .regularOpen none [((.kind .string), (.kind .int))] := by
  rfl

theorem meet_string_pattern_constrains_declared_pattern_field :
    meet
      (mkStruct [⟨"a", .regular, .kind .number⟩] .regularOpen none [((.kind .string), (.kind .int))])
      (mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none [])
      = mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none [((.kind .string), (.kind .int))] := by
  rfl

theorem meet_exact_label_pattern_skips_other_regular_fields :
    meet
      (mkStruct [] .regularOpen none [((.prim (.string "a")), (.kind .int))])
      (mkStruct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [])
      =
        mkStruct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [((.prim (.string "a")), (.kind .int))] := by
  rfl

theorem meet_exact_label_pattern_rejects_matching_conflict :
    meet
      (mkStruct [] .regularOpen none [((.prim (.string "a")), (.kind .int))])
      (mkStruct [⟨"a", .regular, .prim (.string "x")⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [])
      =
        mkStruct [⟨"a", .regular, .bottomWith [.fieldConstraint "a"]⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [((.prim (.string "a")), (.kind .int))] := by
  rfl

theorem meet_regex_label_pattern_skips_non_matching_regular_fields :
    (meet
      (mkStruct [] .regularOpen none [((.stringRegex "^a$"), (.kind .int))])
      (mkStruct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [])
      ==
        mkStruct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [((.stringRegex "^a$"), (.kind .int))]) = true := by
  native_decide

theorem meet_regex_label_pattern_rejects_matching_conflict :
    (meet
      (mkStruct [] .regularOpen none [((.stringRegex "^a$"), (.kind .int))])
      (mkStruct [⟨"a", .regular, .prim (.string "x")⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [])
      ==
        mkStruct [⟨"a", .regular, .bottomWith [.fieldConstraint "a"]⟩, ⟨"b", .regular, .prim (.string "x")⟩] .regularOpen none [((.stringRegex "^a$"), (.kind .int))]) = true := by
  native_decide

theorem meet_regex_wildcard_label_pattern_constrains_matching_field :
    (meet
      (mkStruct [] .regularOpen none [((.stringRegex "^a.*z$"), (.kind .int))])
      (mkStruct [⟨"abcz", .regular, .prim (.int 1)⟩, ⟨"abcy", .regular, .prim (.string "skip")⟩] .regularOpen none [])
      ==
        mkStruct [⟨"abcz", .regular, .prim (.int 1)⟩, ⟨"abcy", .regular, .prim (.string "skip")⟩] .regularOpen none [((.stringRegex "^a.*z$"), (.kind .int))]) = true := by
  native_decide

theorem meet_regex_wildcard_label_pattern_rejects_matching_conflict :
    (meet
      (mkStruct [] .regularOpen none [((.stringRegex "^a.*z$"), (.kind .int))])
      (mkStruct [⟨"abcz", .regular, .prim (.string "bad")⟩, ⟨"abcy", .regular, .prim (.string "skip")⟩] .regularOpen none [])
      ==
        mkStruct [
            ⟨"abcz", .regular, .bottomWith [.fieldConstraint "abcz"]⟩,
            ⟨"abcy", .regular, .prim (.string "skip")⟩
          ] .regularOpen none [((.stringRegex "^a.*z$"), (.kind .int))]) = true := by
  native_decide

theorem meet_regex_plus_label_pattern_requires_one_character :
    (meet
      (mkStruct [] .regularOpen none [((.stringRegex "^a.+z$"), (.kind .int))])
      (mkStruct [⟨"az", .regular, .prim (.string "skip")⟩, ⟨"abz", .regular, .prim (.int 2)⟩] .regularOpen none [])
      ==
        mkStruct [⟨"az", .regular, .prim (.string "skip")⟩, ⟨"abz", .regular, .prim (.int 2)⟩] .regularOpen none [((.stringRegex "^a.+z$"), (.kind .int))]) = true := by
  native_decide

theorem meet_regex_question_label_pattern_allows_zero_or_one_atom :
    (meet
      (mkStruct [] .regularOpen none [((.stringRegex "^colou?r$"), (.kind .int))])
      (mkStruct [
          ⟨"color", .regular, .prim (.string "bad")⟩,
          ⟨"colour", .regular, .prim (.int 2)⟩,
          ⟨"colouur", .regular, .prim (.string "skip")⟩
        ] .regularOpen none [])
      ==
        mkStruct [
            ⟨"color", .regular, .bottomWith [.fieldConstraint "color"]⟩,
            ⟨"colour", .regular, .prim (.int 2)⟩,
            ⟨"colouur", .regular, .prim (.string "skip")⟩
          ] .regularOpen none [((.stringRegex "^colou?r$"), (.kind .int))]) = true := by
  native_decide

theorem meet_regex_class_label_pattern_constrains_matching_fields :
    (meet
      (mkStruct [] .regularOpen none [((.stringRegex "^[ab]cz$"), (.kind .int))])
      (mkStruct [
          ⟨"acz", .regular, .prim (.int 1)⟩,
          ⟨"bcz", .regular, .prim (.int 2)⟩,
          ⟨"ccz", .regular, .prim (.string "skip")⟩
        ] .regularOpen none [])
      ==
        mkStruct [
            ⟨"acz", .regular, .prim (.int 1)⟩,
            ⟨"bcz", .regular, .prim (.int 2)⟩,
            ⟨"ccz", .regular, .prim (.string "skip")⟩
          ] .regularOpen none [((.stringRegex "^[ab]cz$"), (.kind .int))]) = true := by
  native_decide

theorem meet_regex_range_label_pattern_rejects_matching_conflict :
    (meet
      (mkStruct [] .regularOpen none [((.stringRegex "^a[0-9]z$"), (.kind .int))])
      (mkStruct [⟨"a5z", .regular, .prim (.string "bad")⟩, ⟨"axz", .regular, .prim (.string "skip")⟩] .regularOpen none [])
      ==
        mkStruct [
            ⟨"a5z", .regular, .bottomWith [.fieldConstraint "a5z"]⟩,
            ⟨"axz", .regular, .prim (.string "skip")⟩
          ] .regularOpen none [((.stringRegex "^a[0-9]z$"), (.kind .int))]) = true := by
  native_decide

theorem meet_escaped_regex_label_pattern_rejects_matching_conflict :
    (meet
      (mkStruct [] .regularOpen none [((.stringRegex "^a\\.z$"), (.kind .int))])
      (mkStruct [⟨"a.z", .regular, .prim (.string "bad")⟩, ⟨"abz", .regular, .prim (.string "skip")⟩] .regularOpen none [])
      ==
        mkStruct [
            ⟨"a.z", .regular, .bottomWith [.fieldConstraint "a.z"]⟩,
            ⟨"abz", .regular, .prim (.string "skip")⟩
          ] .regularOpen none [((.stringRegex "^a\\.z$"), (.kind .int))]) = true := by
  native_decide

theorem meet_regex_digit_shorthand_rejects_matching_conflict :
    (meet
      (mkStruct [] .regularOpen none [((.stringRegex "^a\\dz$"), (.kind .int))])
      (mkStruct [⟨"a5z", .regular, .prim (.string "bad")⟩, ⟨"adz", .regular, .prim (.string "skip")⟩] .regularOpen none [])
      ==
        mkStruct [
            ⟨"a5z", .regular, .bottomWith [.fieldConstraint "a5z"]⟩,
            ⟨"adz", .regular, .prim (.string "skip")⟩
          ] .regularOpen none [((.stringRegex "^a\\dz$"), (.kind .int))]) = true := by
  native_decide

theorem meet_regex_negated_digit_shorthand_rejects_matching_conflict :
    (meet
      (mkStruct [] .regularOpen none [((.stringRegex "^a\\Dz$"), (.kind .int))])
      (mkStruct [⟨"a5z", .regular, .prim (.string "skip")⟩, ⟨"adz", .regular, .prim (.string "bad")⟩] .regularOpen none [])
      ==
        mkStruct [
            ⟨"a5z", .regular, .prim (.string "skip")⟩,
            ⟨"adz", .regular, .bottomWith [.fieldConstraint "adz"]⟩
          ] .regularOpen none [((.stringRegex "^a\\Dz$"), (.kind .int))]) = true := by
  native_decide

theorem meet_regex_word_shorthand_rejects_matching_conflict :
    (meet
      (mkStruct [] .regularOpen none [((.stringRegex "^a\\wz$"), (.kind .int))])
      (mkStruct [⟨"a_z", .regular, .prim (.string "bad")⟩, ⟨"a-z", .regular, .prim (.string "skip")⟩] .regularOpen none [])
      ==
        mkStruct [
            ⟨"a_z", .regular, .bottomWith [.fieldConstraint "a_z"]⟩,
            ⟨"a-z", .regular, .prim (.string "skip")⟩
          ] .regularOpen none [((.stringRegex "^a\\wz$"), (.kind .int))]) = true := by
  native_decide

theorem meet_regex_negated_word_shorthand_rejects_matching_conflict :
    (meet
      (mkStruct [] .regularOpen none [((.stringRegex "^a\\Wz$"), (.kind .int))])
      (mkStruct [⟨"a_z", .regular, .prim (.string "skip")⟩, ⟨"a-z", .regular, .prim (.string "bad")⟩] .regularOpen none [])
      ==
        mkStruct [
            ⟨"a_z", .regular, .prim (.string "skip")⟩,
            ⟨"a-z", .regular, .bottomWith [.fieldConstraint "a-z"]⟩
          ] .regularOpen none [((.stringRegex "^a\\Wz$"), (.kind .int))]) = true := by
  native_decide

theorem meet_regex_space_shorthand_rejects_matching_conflict :
    (meet
      (mkStruct [] .regularOpen none [((.stringRegex "^a\\sz$"), (.kind .int))])
      (mkStruct [⟨"a z", .regular, .prim (.string "bad")⟩, ⟨"a_z", .regular, .prim (.string "skip")⟩] .regularOpen none [])
      ==
        mkStruct [
            ⟨"a z", .regular, .bottomWith [.fieldConstraint "a z"]⟩,
            ⟨"a_z", .regular, .prim (.string "skip")⟩
          ] .regularOpen none [((.stringRegex "^a\\sz$"), (.kind .int))]) = true := by
  native_decide

theorem meet_regex_negated_space_shorthand_rejects_matching_conflict :
    (meet
      (mkStruct [] .regularOpen none [((.stringRegex "^a\\Sz$"), (.kind .int))])
      (mkStruct [⟨"a z", .regular, .prim (.string "skip")⟩, ⟨"a_z", .regular, .prim (.string "bad")⟩] .regularOpen none [])
      ==
        mkStruct [
            ⟨"a z", .regular, .prim (.string "skip")⟩,
            ⟨"a_z", .regular, .bottomWith [.fieldConstraint "a_z"]⟩
          ] .regularOpen none [((.stringRegex "^a\\Sz$"), (.kind .int))]) = true := by
  native_decide

theorem meet_regex_exact_repetition_rejects_matching_conflict :
    (meet
      (mkStruct [] .regularOpen none [((.stringRegex "^a\\d{2}z$"), (.kind .int))])
      (mkStruct [⟨"a12z", .regular, .prim (.string "bad")⟩, ⟨"a1z", .regular, .prim (.string "skip")⟩] .regularOpen none [])
      ==
        mkStruct [
            ⟨"a12z", .regular, .bottomWith [.fieldConstraint "a12z"]⟩,
            ⟨"a1z", .regular, .prim (.string "skip")⟩
          ] .regularOpen none [((.stringRegex "^a\\d{2}z$"), (.kind .int))]) = true := by
  native_decide

theorem meet_regex_bounded_repetition_rejects_matching_conflict :
    (meet
      (mkStruct [] .regularOpen none [((.stringRegex "^a\\d{2,3}z$"), (.kind .int))])
      (mkStruct [
          ⟨"a12z", .regular, .prim (.int 2)⟩,
          ⟨"a123z", .regular, .prim (.string "bad")⟩,
          ⟨"a1z", .regular, .prim (.string "skip")⟩
        ] .regularOpen none [])
      ==
        mkStruct [
            ⟨"a12z", .regular, .prim (.int 2)⟩,
            ⟨"a123z", .regular, .bottomWith [.fieldConstraint "a123z"]⟩,
            ⟨"a1z", .regular, .prim (.string "skip")⟩
          ] .regularOpen none [((.stringRegex "^a\\d{2,3}z$"), (.kind .int))]) = true := by
  native_decide

theorem meet_regex_top_level_alternation_constrains_each_alternative :
    (meet
      (mkStruct [] .regularOpen none [((.stringRegex "^cat$|^dog$"), (.kind .int))])
      (mkStruct [
          ⟨"cat", .regular, .prim (.string "bad")⟩,
          ⟨"dog", .regular, .prim (.int 2)⟩,
          ⟨"cow", .regular, .prim (.string "skip")⟩
        ] .regularOpen none [])
      ==
        mkStruct [
            ⟨"cat", .regular, .bottomWith [.fieldConstraint "cat"]⟩,
            ⟨"dog", .regular, .prim (.int 2)⟩,
            ⟨"cow", .regular, .prim (.string "skip")⟩
          ] .regularOpen none [((.stringRegex "^cat$|^dog$"), (.kind .int))]) = true := by
  native_decide

theorem meet_regex_parenthesized_alternation_constrains_each_alternative :
    (meet
      (mkStruct [] .regularOpen none [((.stringRegex "^(cat|dog)$"), (.kind .int))])
      (mkStruct [
          ⟨"cat", .regular, .prim (.string "bad")⟩,
          ⟨"dog", .regular, .prim (.int 2)⟩,
          ⟨"cow", .regular, .prim (.string "skip")⟩
        ] .regularOpen none [])
      ==
        mkStruct [
            ⟨"cat", .regular, .bottomWith [.fieldConstraint "cat"]⟩,
            ⟨"dog", .regular, .prim (.int 2)⟩,
            ⟨"cow", .regular, .prim (.string "skip")⟩
          ] .regularOpen none [((.stringRegex "^(cat|dog)$"), (.kind .int))]) = true := by
  native_decide

theorem meet_multiple_pattern_constraints_remain_independent :
    (meet
      (mkStruct [] .regularOpen none [(.stringRegex "^a", .kind .int), (.stringRegex "z$", .kind .string)])
      (mkStruct [
          ⟨"az", .regular, .prim (.int 1)⟩,
          ⟨"ax", .regular, .prim (.int 2)⟩,
          ⟨"bz", .regular, .prim (.string "ok")⟩
        ] .regularOpen none [])
      ==
        mkStruct [
            ⟨"az", .regular, .bottomWith [.fieldConstraint "az"]⟩,
            ⟨"ax", .regular, .prim (.int 2)⟩,
            ⟨"bz", .regular, .prim (.string "ok")⟩
          ] .regularOpen none [(.stringRegex "^a", .kind .int), (.stringRegex "z$", .kind .string)]) = true := by
  native_decide

theorem close_value_marks_struct_pattern_closed :
    closeValue (mkStruct [] .regularOpen none [((.stringRegex "^a$"), (.kind .int))])
      = mkStruct [] .defClosed none [((.stringRegex "^a$"), (.kind .int))] := by
  rfl

theorem closed_pattern_rejects_non_matching_extra_regular_field :
    (meet
      (closeValue (mkStruct [] .regularOpen none [((.stringRegex "^a$"), (.kind .int))]))
      (mkStruct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.int 2)⟩] .regularOpen none [])
      ==
        mkStruct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .bottomWith [.fieldNotAllowed "b"]⟩] .defClosed none [((.stringRegex "^a$"), (.kind .int))] [⟨[], [.stringRegex "^a$"]⟩]) = true := by
  native_decide

theorem closed_pattern_allows_hidden_and_definition_extra_fields :
    (meet
      (closeValue (mkStruct [] .regularOpen none [((.stringRegex "^a$"), (.kind .int))]))
      (mkStruct [
          ⟨"a", .regular, .prim (.int 1)⟩,
          ⟨"_h", .hidden, .prim (.string "secret")⟩,
          ⟨"#D", .definition, .kind .string⟩
        ] .regularOpen none [])
      ==
        mkStruct [
            ⟨"a", .regular, .prim (.int 1)⟩,
            ⟨"_h", .hidden, .prim (.string "secret")⟩,
            ⟨"#D", .definition, .kind .string⟩
          ] .defClosed none [((.stringRegex "^a$"), (.kind .int))] [⟨[], [.stringRegex "^a$"]⟩]) = true := by
  native_decide

theorem closed_multiple_patterns_allow_any_matching_regular_field :
    (meet
      (closeValue
        (mkStruct [] .regularOpen none [(.stringRegex "^a", .kind .int), (.stringRegex "z$", .kind .string)]))
      (mkStruct [
          ⟨"ax", .regular, .prim (.int 2)⟩,
          ⟨"bz", .regular, .prim (.string "ok")⟩,
          ⟨"m", .regular, .prim (.int 3)⟩
        ] .regularOpen none [])
      ==
        mkStruct [
            ⟨"ax", .regular, .prim (.int 2)⟩,
            ⟨"bz", .regular, .prim (.string "ok")⟩,
            ⟨"m", .regular, .bottomWith [.fieldNotAllowed "m"]⟩
          ] .defClosed none [(.stringRegex "^a", .kind .int), (.stringRegex "z$", .kind .string)] [⟨[], [.stringRegex "^a", .stringRegex "z$"]⟩]) = true := by
  native_decide

-- RATIFIED spec-gap (`cue-spec-gaps.md`, area A): an un-narrowed struct-arm disjunction
-- with no unique default stays OPEN — `{a:int} | {b:string}` is kept as the two-arm join,
-- not collapsed or errored. Lattice basis: a join with no unique default IS the join;
-- erroring would over-commit. Identity under meet with `.top` confirms it is a settled
-- value, not an intermediate. (Spec is silent on open-vs-error here; `cue` agrees.)
theorem disj_struct_arms_no_default_stays_open :
    formatValue
      (.disj [
        (.regular, mkStruct [⟨"a", .regular, .kind .int⟩] .regularOpen none []),
        (.regular, mkStruct [⟨"b", .regular, .kind .string⟩] .regularOpen none [])])
      = "{a: int} | {b: string}" := by
  native_decide

theorem disj_struct_arms_no_default_is_meet_identity :
    meet
      (.disj [
        (.regular, mkStruct [⟨"a", .regular, .kind .int⟩] .regularOpen none []),
        (.regular, mkStruct [⟨"b", .regular, .kind .string⟩] .regularOpen none [])])
      .top
      = .disj [
        (.regular, mkStruct [⟨"a", .regular, .kind .int⟩] .regularOpen none []),
        (.regular, mkStruct [⟨"b", .regular, .kind .string⟩] .regularOpen none [])] := by
  rfl

-- RATIFIED spec-gap (`cue-spec-gaps.md`, area C/F-4 — field order #3): a struct meet
-- emits fields in DECLARATION / first-seen-across-conjuncts order (`{b} & {a}` ⟹ `b, a`),
-- NOT sorted. Spec is silent (structs are unordered sets; output order is
-- implementation-defined). Kue picks the source/declaration order on principle.
-- NB: `cue` v0.16.1 SORTS cross-conjunct (`{b}&{a}` ⟹ `a, b`); Kue deliberately does not
-- inherit that — see the corrected `cue` behavior column in `cue-spec-gaps.md`.
theorem meet_struct_field_order_is_declaration_order :
    formatValue
      (meet
        (mkStruct [⟨"b", .regular, .prim (.int 1)⟩] .regularOpen none [])
        (mkStruct [⟨"a", .regular, .prim (.int 2)⟩] .regularOpen none []))
      = "{b: 1, a: 2}" := by
  native_decide

/-! ## SC-1b — closed × closed-pattern intersection (per-conjunct allowed-set provenance)

The meet of two CLOSED structs is closed to the INTERSECTION of their allowed-sets: a field
survives iff EVERY closed conjunct admits it (`label ∈ its fields` OR matches one of its
closing patterns). The pre-fix flat-union `closingPatterns` store admitted a field matching
ANY conjunct's pattern; `closedClauses` carries each conjunct's allowed-set as one clause and
AND-s them, so the lossy later-meet is gone. Each pin is oracle-confirmed against cue v0.16.1.
Spec basis: closedness guide ("which conjuncts introduced which patterns and closedness
constraints"); closing = adding `..._|_` (monotone/conjunctive). -/

-- WITNESS. Disjoint patterns `^x` / `^y`: a field matching ONE operand's pattern but not the
-- other's is rejected on a later meet — the bug the union-store missed. `x1` matches `^x`
-- (`#A`) but not `^y` (`#B`); cue rejects, and so must Kue.
theorem sc1b_disjoint_patterns_reject_one_sided_field :
    exportJsonBottoms
      "#A: {[=~\"^x\"]: int}\n#B: {[=~\"^y\"]: int}\nout: (#A & #B) & {x1: 5}\n" = true := by
  native_decide

theorem sc1b_disjoint_patterns_reject_other_sided_field :
    exportJsonBottoms
      "#A: {[=~\"^x\"]: int}\n#B: {[=~\"^y\"]: int}\nout: (#A & #B) & {y1: 5}\n" = true := by
  native_decide

-- A field matching BOTH patterns survives (the intersection is non-empty). `^x` ∩ `^xy`:
-- `xyz` matches both → admitted and unified.
theorem sc1b_overlapping_patterns_admit_doubly_matching_field :
    exportJsonMatches
      "#A: {[=~\"^x\"]: int}\n#B: {[=~\"^xy\"]: int}\nout: (#A & #B) & {xyz: 5}\n"
      "{\n    \"out\": {\n        \"xyz\": 5\n    }\n}\n" = true := by
  native_decide

-- A field matching the BROADER pattern but not the NARROWER is rejected (intersection is the
-- narrower). `^x` ∩ `^xy`: `xa` matches `^x` only → rejected.
theorem sc1b_narrower_pattern_rejects_broad_only_field :
    exportJsonBottoms
      "#A: {[=~\"^x\"]: int}\n#B: {[=~\"^xy\"]: int}\nout: (#A & #B) & {xa: 5}\n" = true := by
  native_decide

-- FIELD-SIDE (CRUX). A closed conjunct with NO patterns (allows only its declared fields)
-- rejects a later field that matches the OTHER conjunct's pattern. `#A` allows only `{a}`;
-- `x1` matches `#B`'s `^x` but not `#A` → rejected. The merged result over-approximates each
-- clause's field-set, so this needs the per-clause field-labels (not the merged `fields`).
theorem sc1b_field_only_clause_rejects_pattern_matched_field :
    exportJsonBottoms
      "#A: {a?: int}\n#B: {[=~\"^x\"]: int}\nout: (#A & #B) & {x1: 5}\n" = true := by
  native_decide

-- The `[string]`-broad clause narrowed by a `^x` clause: only `^x` labels survive. `y1`
-- rejected (fails `^x`), `x1` admitted (matches both).
theorem sc1b_broad_then_narrow_rejects_non_matching :
    exportJsonBottoms
      "#A: {[string]: int}\n#B: {[=~\"^x\"]: int}\nout: (#A & #B) & {y1: 5}\n" = true := by
  native_decide

theorem sc1b_broad_then_narrow_admits_matching :
    exportJsonMatches
      "#A: {[string]: int}\n#B: {[=~\"^x\"]: int}\nout: (#A & #B) & {x1: 5}\n"
      "{\n    \"out\": {\n        \"x1\": 5\n    }\n}\n" = true := by
  native_decide

-- THREE-way associativity: a field must match ALL THREE clauses. `a1` matches only `^a` → out.
theorem sc1b_three_way_intersection_rejects_partial_match :
    exportJsonBottoms
      ("#A: {[=~\"^a\"]: int}\n#B: {[=~\"^b\"]: int}\n#C: {[=~\"^c\"]: int}\n"
        ++ "out: (#A & #B & #C) & {a1: 5}\n") = true := by
  native_decide

-- NESTED closedness: the intersection rule applies at each depth. `sub.x1` matches `#A.sub`'s
-- `^x` but not `#B.sub`'s `^y` → rejected.
theorem sc1b_nested_closed_intersection :
    exportJsonBottoms
      ("#A: {sub: {[=~\"^x\"]: int}}\n#B: {sub: {[=~\"^y\"]: int}}\n"
        ++ "out: (#A & #B) & {sub: {x1: 5}}\n") = true := by
  native_decide

-- The DIRECT meet of two same-pattern closed defs with disjoint REQUIRED fields bottoms
-- (each required field is rejected by the other's closedness) — the at-this-meet marking,
-- already correct before SC-1b, preserved.
theorem sc1b_direct_meet_disjoint_required_bottoms :
    exportJsonBottoms
      "#A: {a: int, [=~\"^x\"]: int}\n#B: {b: int, [=~\"^x\"]: int}\nout: #A & #B\n" = true := by
  native_decide

-- close() is IDEMPOTENT on a meet-result: it must NOT collapse the per-conjunct clauses into
-- a single self-clause. `close(#A & #B)` still rejects a one-sided-pattern field.
theorem sc1b_close_preserves_conjunct_clauses :
    exportJsonBottoms
      "#A: {[=~\"^x\"]: int}\n#B: {[=~\"^y\"]: int}\nout: close(#A & #B) & {x1: 5}\n" = true := by
  native_decide

-- Closed-EMPTY meet: `close({}) & {x:1}` rejects (the closed-empty clause admits nothing — a
-- closed struct always carries ≥1 clause, never the open `[]`).
theorem sc1b_closed_empty_rejects_extra :
    exportJsonBottoms "out: close({}) & {x: 1}\n" = true := by
  native_decide

/-! ## SC-1e — closed × open-`...` keeps closedness (monotonicity under meet)

A CLOSED struct met with an open-`...` partner stays CLOSED: closedness is monotone under
meet, so the partner's bare `...` does NOT re-open the closed conjunct's allowed-set. The pre
-fix tail-bearing arms dropped `bothClauses` (passed `closedClauses = []`) and emitted a
`.defOpenViaTail` result, re-opening. The fix routes every tail arm through `closeTailResult`,
which collapses to a closed no-tail result carrying `bothClauses` when the meet is closed. Each
pin is oracle-confirmed against cue v0.16.1 (cue CORRECT here). Spec basis: closedness is a
monotone/conjunctive constraint; `...` is a no-op against an already-closed allowed-set. -/

-- WITNESS (pattern-closed, catch-all arm). `(#A & #B)` is closed to `^x ∩ ^y`; the open-`...`
-- partner must NOT re-open it. `x1` matches `^x` but not `^y` → rejected, exactly as the no-`...`
-- control `sc1b_disjoint_patterns_reject_one_sided_field`. Pre-SC-1e the `...` admitted `x1`.
theorem sc1e_pattern_closed_open_tail_rejects :
    exportJsonBottoms
      "#A: {[=~\"^x\"]: int}\n#B: {[=~\"^y\"]: int}\nout: (#A & #B) & {x1: 5, ...}\n" = true := by
  native_decide

-- Admit side: a field the closed allowed-set PERMITS still unifies; only the `...` is dropped.
-- `x1` matches `^x` → `x1: 5` survives. Guards that the fix rejects only forbidden extras.
theorem sc1e_pattern_closed_open_tail_admits_allowed :
    exportJsonMatches
      "#A: {[=~\"^x\"]: int}\nout: (#A & {x1: 5}) & {x1: 5, ...}\n"
      "{\n    \"out\": {\n        \"x1\": 5\n    }\n}\n" = true := by
  native_decide

-- FIELD-closed (the `struct × structTail` arm, NOT the catch-all). `#C: {a: int}` is field-closed
-- (no patterns); `b ∉ #C` → rejected, `...` dropped. Pins the fix across ALL tail arms, since the
-- breadcrumb's witness (pattern-closed) exercised only the catch-all.
theorem sc1e_field_closed_open_tail_rejects :
    exportJsonBottoms "#C: {a: int}\nout: #C & {a: 1, b: 2, ...}\n" = true := by
  native_decide

theorem sc1e_field_closed_open_tail_admits_allowed :
    exportJsonMatches "#C: {a: int}\nout: #C & {a: 1, ...}\n"
      "{\n    \"out\": {\n        \"a\": 1\n    }\n}\n" = true := by
  native_decide

-- REVERSED arm (`{...} & #C`, tail on the LEFT, closed on the right). Field-merge order is
-- reversed, but the closing rule is the same: `z ∉ #C` → rejected.
theorem sc1e_tail_left_closed_right_rejects :
    exportJsonBottoms "#C: {a: int}\nout: {z: 9, ...} & #C\n" = true := by
  native_decide

-- REGRESSION (open × open-`...`): with NO closed operand, `bothClauses = []` and the `...`
-- survives — the struct stays open and admits both fields. The fix must not over-close.
theorem sc1e_open_open_tail_stays_open :
    exportJsonMatches "out: {a: 1} & {b: 2, ...}\n"
      "{\n    \"out\": {\n        \"b\": 2,\n        \"a\": 1\n    }\n}\n" = true := by
  native_decide

/-! ## EMBED-CLOSE-1 — closedness preserved through embedding (kue spec-correct; cue self-contradicts)

kue rejects `y1` (∉ `#A`'s `^x`) in BOTH the embed form `{#A, y1}` and the meet form `#A & {y1}`.
cue SELF-CONTRADICTS: it admits the embed form but rejects the meet form (recorded in
cue-divergences.md). kue follows the closedness-monotonicity spec — embedding a closed def does
not drop its closedness — and stays consistent. Neither form carries a `...`, so the SC-1e
tail-arm fix leaves these untouched; the pins LOCK the existing-correct rejection so a future
closedness change cannot silently regress it. -/

theorem embed_close1_meet_form_rejects :
    exportJsonBottoms "#A: {[=~\"^x\"]: int}\nout: #A & {y1: 5}\n" = true := by
  native_decide

theorem embed_close1_embed_form_rejects :
    exportJsonBottoms "#A: {[=~\"^x\"]: int}\nout: {#A, y1: 5}\n" = true := by
  native_decide

end Kue
