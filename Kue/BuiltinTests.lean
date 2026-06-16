import Kue.Builtin
import Kue.Lattice

namespace Kue

theorem close_value_marks_struct_closed :
    closeValue (.struct [("a", .regular, .kind .int)] true)
      = .struct [("a", .regular, .kind .int)] false := by
  rfl

theorem close_value_rejects_extra_field_after_meet :
    meet
      (closeValue (.struct [("a", .regular, .kind .int)] true))
      (.struct [("a", .regular, .prim (.int 1)), ("b", .regular, .prim (.int 2))] true)
      =
        .struct
          [
            ("a", .regular, .prim (.int 1)),
            ("b", .regular, .bottomWith [.fieldNotAllowed "b"])
          ]
          false := by
  rfl

theorem close_value_is_shallow_for_nested_regular_structs :
    closeValue
      (.struct [("a", .regular, .struct [("b", .regular, .kind .int)] true)] true)
      = .struct [("a", .regular, .struct [("b", .regular, .kind .int)] true)] false := by
  rfl

theorem len_value_counts_string_utf8_bytes :
    (lenValue (.prim (.string "abc")) == .prim (.int 3))
      && (lenValue (.prim (.string "é")) == .prim (.int 2)) = true := by
  native_decide

theorem len_value_counts_list_items :
    lenValue (.list [.prim (.int 1), .prim (.int 2), .prim (.int 3)]) = .prim (.int 3) := by
  rfl

theorem len_value_counts_regular_struct_fields_only :
    lenValue
      (.struct
        [
          ("a", .regular, .prim (.int 1)),
          ("b", .optional, .prim (.int 2)),
          ("_c", .hidden, .prim (.int 3)),
          ("#D", .definition, .prim (.int 4))
        ]
        true)
      = .prim (.int 1) := by
  rfl

theorem len_value_preserves_incomplete_string_call :
    lenValue (.kind .string) = .builtinCall "len" [.kind .string] := by
  rfl

theorem and_values_meets_constraints :
    (andValues [.kind .int, .intGt 0, .prim (.int 7)] == .prim (.int 7)) = true := by
  native_decide

theorem and_values_empty_is_top :
    andValues [] = .top := by
  rfl

theorem or_values_joins_values :
    (orValues [.prim (.string "a"), .prim (.string "b")]
      == .disj [(.regular, .prim (.string "a")), (.regular, .prim (.string "b"))]) = true := by
  native_decide

theorem or_values_joins_numeric_kind :
    (orValues [.kind .number, .prim (.int 1)] == .kind .number) = true := by
  native_decide

theorem or_values_empty_preserves_builtin_call :
    orValues [] = .builtinCall "or" [.list []] := by
  rfl

theorem div_value_euclidean_negative_dividend :
    divValue (.prim (.int (-7))) (.prim (.int 3)) = .prim (.int (-3)) := by
  rfl

theorem mod_value_euclidean_negative_dividend :
    modValue (.prim (.int (-7))) (.prim (.int 3)) = .prim (.int 2) := by
  rfl

theorem div_value_euclidean_negative_divisor :
    divValue (.prim (.int 7)) (.prim (.int (-3))) = .prim (.int (-2)) := by
  rfl

theorem mod_value_euclidean_negative_divisor :
    modValue (.prim (.int 7)) (.prim (.int (-3))) = .prim (.int 1) := by
  rfl

theorem quo_value_truncates_toward_zero :
    quoValue (.prim (.int (-7))) (.prim (.int 3)) = .prim (.int (-2)) := by
  rfl

theorem rem_value_truncating_remainder_keeps_dividend_sign :
    remValue (.prim (.int (-7))) (.prim (.int 3)) = .prim (.int (-1)) := by
  rfl

theorem div_value_preserves_incomplete_int_call :
    divValue (.kind .int) (.prim (.int 3)) = .builtinCall "div" [.kind .int, .prim (.int 3)] := by
  rfl

theorem div_value_rejects_non_integer_argument :
    divValue (.prim (.string "x")) (.prim (.int 3)) = .bottomWith [.kindConflict .int .string] := by
  rfl

theorem div_value_rejects_division_by_zero :
    divValue (.prim (.int 7)) (.prim (.int 0)) = .bottomWith [.divisionByZero] := by
  rfl

theorem strings_index_is_byte_based :
    (evalBuiltinCall "strings.Index" [.prim (.string "héllo"), .prim (.string "llo")]
      == .prim (.int 3)) = true := by
  native_decide

theorem strings_index_missing_is_minus_one :
    (evalBuiltinCall "strings.Index" [.prim (.string "chicken"), .prim (.string "xyz")]
      == .prim (.int (-1))) = true := by
  native_decide

theorem strings_split_empty_separator_splits_runes :
    (evalBuiltinCall "strings.Split" [.prim (.string "ab"), .prim (.string "")]
      == .list [.prim (.string "a"), .prim (.string "b")]) = true := by
  native_decide

theorem strings_count_empty_needle_is_rune_count_plus_one :
    (evalBuiltinCall "strings.Count" [.prim (.string "abc"), .prim (.string "")]
      == .prim (.int 4)) = true := by
  native_decide

theorem strings_join_non_string_element_is_bottom :
    (evalBuiltinCall "strings.Join" [.list [.prim (.int 1)], .prim (.string ",")]
      == .bottom) = true := by
  native_decide

theorem strings_repeat_negative_count_is_bottom :
    (evalBuiltinCall "strings.Repeat" [.prim (.string "a"), .prim (.int (-1))]
      == .bottom) = true := by
  native_decide

theorem strings_type_mismatch_is_bottom :
    (evalBuiltinCall "strings.Contains" [.prim (.int 5), .prim (.string "x")]
      == .bottom) = true := by
  native_decide

theorem strings_call_stays_unresolved_on_abstract_arg :
    (evalBuiltinCall "strings.Contains" [.kind .string, .prim (.string "x")]
      == .builtinCall "strings.Contains" [.kind .string, .prim (.string "x")]) = true := by
  native_decide

theorem list_concat_flattens_one_level :
    (evalBuiltinCall "list.Concat"
        [.list [.list [.prim (.int 1)], .list [.prim (.int 2), .prim (.int 3)]]]
      == .list [.prim (.int 1), .prim (.int 2), .prim (.int 3)]) = true := by
  native_decide

theorem list_flattenN_depth_one_keeps_inner_lists :
    (evalBuiltinCall "list.FlattenN"
        [.list [.list [.prim (.int 1), .list [.prim (.int 2)]]], .prim (.int 1)]
      == .list [.prim (.int 1), .list [.prim (.int 2)]]) = true := by
  native_decide

theorem list_flattenN_negative_depth_flattens_fully :
    (evalBuiltinCall "list.FlattenN"
        [.list [.prim (.int 1), .list [.list [.prim (.int 2)]]], .prim (.int (-1))]
      == .list [.prim (.int 1), .prim (.int 2)]) = true := by
  native_decide

theorem list_range_descending :
    (evalBuiltinCall "list.Range" [.prim (.int 5), .prim (.int 0), .prim (.int (-1))]
      == .list [.prim (.int 5), .prim (.int 4), .prim (.int 3), .prim (.int 2), .prim (.int 1)])
      = true := by
  native_decide

theorem list_range_zero_step_is_bottom :
    (evalBuiltinCall "list.Range" [.prim (.int 0), .prim (.int 5), .prim (.int 0)]
      == .bottom) = true := by
  native_decide

theorem list_slice_out_of_range_is_bottom :
    (evalBuiltinCall "list.Slice"
        [.list [.prim (.int 1), .prim (.int 2), .prim (.int 3)], .prim (.int 1), .prim (.int 5)]
      == .bottom) = true := by
  native_decide

theorem list_slice_inverted_bounds_is_bottom :
    (evalBuiltinCall "list.Slice"
        [.list [.prim (.int 1), .prim (.int 2), .prim (.int 3)], .prim (.int 2), .prim (.int 1)]
      == .bottom) = true := by
  native_decide

theorem list_repeat_negative_count_is_bottom :
    (evalBuiltinCall "list.Repeat" [.list [.prim (.int 1)], .prim (.int (-1))]
      == .bottom) = true := by
  native_decide

theorem list_take_negative_count_is_bottom :
    (evalBuiltinCall "list.Take" [.list [.prim (.int 1)], .prim (.int (-1))]
      == .bottom) = true := by
  native_decide

theorem list_sum_empty_is_zero :
    (evalBuiltinCall "list.Sum" [.list []] == .prim (.int 0)) = true := by
  native_decide

theorem list_sum_non_int_element_is_bottom :
    (evalBuiltinCall "list.Sum" [.list [.prim (.int 1), .prim (.string "x")]]
      == .bottom) = true := by
  native_decide

theorem list_min_empty_is_bottom :
    (evalBuiltinCall "list.Min" [.list []] == .bottom) = true := by
  native_decide

theorem list_max_empty_is_bottom :
    (evalBuiltinCall "list.Max" [.list []] == .bottom) = true := by
  native_decide

theorem list_contains_structural_element :
    (evalBuiltinCall "list.Contains"
        [.list [.list [.prim (.int 1)], .list [.prim (.int 2)]], .list [.prim (.int 1)]]
      == .prim (.bool true)) = true := by
  native_decide

theorem list_call_stays_unresolved_on_abstract_arg :
    (evalBuiltinCall "list.Sum" [.kind .number]
      == .builtinCall "list.Sum" [.kind .number]) = true := by
  native_decide

end Kue
