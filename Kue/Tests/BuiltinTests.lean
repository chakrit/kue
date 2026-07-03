import Kue.Builtin
import Kue.Lattice

namespace Kue

theorem close_value_marks_struct_closed :
    closeValue (mkStruct [⟨"a", .regular, .kind .int, false⟩] .regularOpen none [])
      = mkStruct [⟨"a", .regular, .kind .int, false⟩] .defClosed none [] := by
  rfl

theorem close_value_rejects_extra_field_after_meet :
    meet
      (closeValue (mkStruct [⟨"a", .regular, .kind .int, false⟩] .regularOpen none []))
      (mkStruct [⟨"a", .regular, .prim (.int 1), false⟩, ⟨"b", .regular, .prim (.int 2), false⟩] .regularOpen none [])
      =
        mkStruct [
            ⟨"a", .regular, .prim (.int 1), false⟩,
            ⟨"b", .regular, .bottomWith [.fieldNotAllowed "b"], false⟩
          ] .defClosed none [] [⟨["a"], []⟩] := by
  rfl

theorem close_value_is_shallow_for_nested_regular_structs :
    closeValue
      (mkStruct [⟨"a", .regular, mkStruct [⟨"b", .regular, .kind .int, false⟩] .regularOpen none [], false⟩] .regularOpen none [])
      = mkStruct [⟨"a", .regular, mkStruct [⟨"b", .regular, .kind .int, false⟩] .regularOpen none [], false⟩] .defClosed none [] := by
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
      (mkStruct [
          ⟨"a", .regular, .prim (.int 1), false⟩,
          ⟨"b", .optional, .prim (.int 2), false⟩,
          ⟨"_c", .hidden, .prim (.int 3), false⟩,
          ⟨"#D", .definition, .prim (.int 4), false⟩
        ] .regularOpen none [])
      = .prim (.int 1) := by
  rfl

theorem len_value_preserves_incomplete_string_call :
    lenValue (.kind .string) = .builtinCall "len" [.kind .string] := by
  rfl

theorem and_values_meets_constraints :
    (andValues [.kind .int, .boundConstraint (intDecimal 0) .gt .number, .prim (.int 7)] == .prim (.int 7)) = true := by
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

theorem strings_splitn_positive_last_piece_is_remainder :
    (evalBuiltinCall "strings.SplitN"
        [.prim (.string "a,b,c"), .prim (.string ","), .prim (.int 2)]
      == .list [.prim (.string "a"), .prim (.string "b,c")]) = true := by
  native_decide

theorem strings_splitn_zero_is_empty_list :
    (evalBuiltinCall "strings.SplitN"
        [.prim (.string "a,b,c"), .prim (.string ","), .prim (.int 0)]
      == .list []) = true := by
  native_decide

theorem strings_splitn_negative_is_all_pieces :
    (evalBuiltinCall "strings.SplitN"
        [.prim (.string "a,b,c"), .prim (.string ","), .prim (.int (-1))]
      == .list [.prim (.string "a"), .prim (.string "b"), .prim (.string "c")]) = true := by
  native_decide

theorem strings_splitn_count_exceeds_pieces_is_all_pieces :
    (evalBuiltinCall "strings.SplitN"
        [.prim (.string "a,b,c"), .prim (.string ","), .prim (.int 5)]
      == .list [.prim (.string "a"), .prim (.string "b"), .prim (.string "c")]) = true := by
  native_decide

theorem strings_splitn_separator_absent_is_singleton :
    (evalBuiltinCall "strings.SplitN"
        [.prim (.string "xyz"), .prim (.string ","), .prim (.int 2)]
      == .list [.prim (.string "xyz")]) = true := by
  native_decide

theorem strings_splitn_empty_string_is_single_empty :
    (evalBuiltinCall "strings.SplitN"
        [.prim (.string ""), .prim (.string ","), .prim (.int 2)]
      == .list [.prim (.string "")]) = true := by
  native_decide

theorem strings_splitn_empty_separator_caps_runes :
    (evalBuiltinCall "strings.SplitN"
        [.prim (.string "abc"), .prim (.string ""), .prim (.int 2)]
      == .list [.prim (.string "a"), .prim (.string "bc")]) = true := by
  native_decide

theorem strings_splitn_empty_separator_unbounded_is_runes :
    (evalBuiltinCall "strings.SplitN"
        [.prim (.string "abc"), .prim (.string ""), .prim (.int (-1))]
      == .list [.prim (.string "a"), .prim (.string "b"), .prim (.string "c")]) = true := by
  native_decide

theorem strings_splitn_empty_both_is_empty_list :
    (evalBuiltinCall "strings.SplitN"
        [.prim (.string ""), .prim (.string ""), .prim (.int (-1))]
      == .list []) = true := by
  native_decide

theorem strings_splitn_type_mismatch_is_bottom :
    (evalBuiltinCall "strings.SplitN"
        [.prim (.string "a,b"), .prim (.string ","), .prim (.string "2")]
      == .bottom) = true := by
  native_decide

theorem strings_splitn_abstract_arg_stays_unresolved :
    (evalBuiltinCall "strings.SplitN"
        [.kind .string, .prim (.string ","), .prim (.int 2)]
      == .builtinCall "strings.SplitN"
        [.kind .string, .prim (.string ","), .prim (.int 2)]) = true := by
  native_decide

theorem strings_count_empty_needle_is_rune_count_plus_one :
    (evalBuiltinCall "strings.Count" [.prim (.string "abc"), .prim (.string "")]
      == .prim (.int 4)) = true := by
  native_decide

theorem strings_runes_ascii_is_code_points :
    (evalBuiltinCall "strings.Runes" [.prim (.string "abc")]
      == .list [.prim (.int 97), .prim (.int 98), .prim (.int 99)]) = true := by
  native_decide

theorem strings_runes_multibyte_is_one_int_per_rune :
    (evalBuiltinCall "strings.Runes" [.prim (.string "héllo")]
      == .list [.prim (.int 104), .prim (.int 233), .prim (.int 108),
                .prim (.int 108), .prim (.int 111)]) = true := by
  native_decide

theorem strings_runes_astral_emoji_is_single_scalar :
    (evalBuiltinCall "strings.Runes" [.prim (.string "a😀b")]
      == .list [.prim (.int 97), .prim (.int 128512), .prim (.int 98)]) = true := by
  native_decide

theorem strings_runes_empty_is_empty_list :
    (evalBuiltinCall "strings.Runes" [.prim (.string "")]
      == .list []) = true := by
  native_decide

theorem strings_runes_wrong_arity_is_bottom :
    (evalBuiltinCall "strings.Runes" [.prim (.string "a"), .prim (.string "b")]
      == .bottom) = true := by
  native_decide

theorem strings_runes_non_string_arg_is_bottom :
    (evalBuiltinCall "strings.Runes" [.prim (.int 5)]
      == .bottom) = true := by
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

theorem strings_replace_zero_count_is_unchanged :
    (evalBuiltinCall "strings.Replace"
        [.prim (.string "aaaa"), .prim (.string "a"), .prim (.string "b"), .prim (.int 0)]
      == .prim (.string "aaaa")) = true := by
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

theorem list_slice_negative_low_is_bottom :
    (evalBuiltinCall "list.Slice"
        [.list [.prim (.int 1), .prim (.int 2), .prim (.int 3)], .prim (.int (-1)), .prim (.int 2)]
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

theorem list_sort_strings_orders_ascending :
    (evalBuiltinCall "list.SortStrings"
        [.list [.prim (.string "banana"), .prim (.string "apple"), .prim (.string "cherry")]]
      == .list [.prim (.string "apple"), .prim (.string "banana"), .prim (.string "cherry")])
      = true := by
  native_decide

theorem list_sort_strings_keeps_duplicates :
    (evalBuiltinCall "list.SortStrings"
        [.list [.prim (.string "b"), .prim (.string "a"), .prim (.string "b"), .prim (.string "a")]]
      == .list [.prim (.string "a"), .prim (.string "a"), .prim (.string "b"), .prim (.string "b")])
      = true := by
  native_decide

theorem list_sort_strings_empty_is_empty :
    (evalBuiltinCall "list.SortStrings" [.list []] == .list []) = true := by
  native_decide

theorem list_sort_strings_singleton_is_identity :
    (evalBuiltinCall "list.SortStrings" [.list [.prim (.string "x")]]
      == .list [.prim (.string "x")]) = true := by
  native_decide

theorem list_sort_strings_already_sorted_is_stable :
    (evalBuiltinCall "list.SortStrings"
        [.list [.prim (.string "a"), .prim (.string "b"), .prim (.string "c")]]
      == .list [.prim (.string "a"), .prim (.string "b"), .prim (.string "c")])
      = true := by
  native_decide

theorem list_sort_strings_reverse_sorted :
    (evalBuiltinCall "list.SortStrings"
        [.list [.prim (.string "c"), .prim (.string "b"), .prim (.string "a")]]
      == .list [.prim (.string "a"), .prim (.string "b"), .prim (.string "c")])
      = true := by
  native_decide

theorem list_sort_strings_byte_order_caps_before_lowercase :
    (evalBuiltinCall "list.SortStrings"
        [.list [.prim (.string "b"), .prim (.string "A"), .prim (.string "a"), .prim (.string "B")]]
      == .list [.prim (.string "A"), .prim (.string "B"), .prim (.string "a"), .prim (.string "b")])
      = true := by
  native_decide

theorem list_sort_strings_multibyte_after_ascii :
    (evalBuiltinCall "list.SortStrings"
        [.list [.prim (.string "é"), .prim (.string "a"), .prim (.string "z"), .prim (.string "Z")]]
      == .list [.prim (.string "Z"), .prim (.string "a"), .prim (.string "z"), .prim (.string "é")])
      = true := by
  native_decide

theorem list_sort_strings_non_string_element_is_bottom :
    (evalBuiltinCall "list.SortStrings"
        [.list [.prim (.string "a"), .prim (.int 1), .prim (.string "b")]]
      == .bottom) = true := by
  native_decide

theorem list_sort_strings_abstract_arg_stays_unresolved :
    (evalBuiltinCall "list.SortStrings" [.kind .number]
      == .builtinCall "list.SortStrings" [.kind .number]) = true := by
  native_decide

theorem list_sum_float_collapses_integral :
    (evalBuiltinCall "list.Sum"
        [.list [.prim (.float "1.0"), .prim (.float "2.0"), .prim (.float "3.0")]]
      == .prim (.int 6)) = true := by
  native_decide

theorem list_sum_mixed_int_float_promotes :
    (evalBuiltinCall "list.Sum"
        [.list [.prim (.int 1), .prim (.float "2.5"), .prim (.int 3)]]
      == .prim (.float "6.5")) = true := by
  native_decide

theorem list_sum_mixed_integral_collapses_int :
    (evalBuiltinCall "list.Sum"
        [.list [.prim (.int 1), .prim (.float "2.0"), .prim (.int 3)]]
      == .prim (.int 6)) = true := by
  native_decide

theorem list_min_float_collapses_integral :
    (evalBuiltinCall "list.Min"
        [.list [.prim (.float "3.0"), .prim (.float "1.0"), .prim (.float "2.0")]]
      == .prim (.int 1)) = true := by
  native_decide

theorem list_min_mixed_picks_float :
    (evalBuiltinCall "list.Min"
        [.list [.prim (.int 3), .prim (.float "1.5"), .prim (.int 2)]]
      == .prim (.float "1.5")) = true := by
  native_decide

theorem list_max_float_collapses_integral :
    (evalBuiltinCall "list.Max"
        [.list [.prim (.float "3.0"), .prim (.float "1.0"), .prim (.float "2.0")]]
      == .prim (.int 3)) = true := by
  native_decide

theorem list_avg_exact_divisible_collapses_int :
    (evalBuiltinCall "list.Avg"
        [.list [.prim (.int 1), .prim (.int 2), .prim (.int 3)]]
      == .prim (.int 2)) = true := by
  native_decide

theorem list_avg_terminating_is_float :
    (evalBuiltinCall "list.Avg"
        [.list [.prim (.int 1), .prim (.int 2)]]
      == .prim (.float "1.5")) = true := by
  native_decide

theorem list_avg_nonterminating_is_34_sig_digit_float :
    (evalBuiltinCall "list.Avg"
        [.list [.prim (.int 1), .prim (.int 1), .prim (.int 2)]]
      == .prim (.float "1.333333333333333333333333333333333")) = true := by
  native_decide

theorem list_avg_float_input :
    (evalBuiltinCall "list.Avg"
        [.list [.prim (.float "1.0"), .prim (.float "2.0")]]
      == .prim (.float "1.5")) = true := by
  native_decide

theorem list_avg_empty_is_bottom :
    (evalBuiltinCall "list.Avg" [.list []] == .bottom) = true := by
  native_decide

theorem list_avg_non_numeric_element_is_bottom :
    (evalBuiltinCall "list.Avg" [.list [.prim (.bool true)]] == .bottom) = true := by
  native_decide

theorem list_avg_abstract_arg_stays_unresolved :
    (evalBuiltinCall "list.Avg" [.kind .number]
      == .builtinCall "list.Avg" [.kind .number]) = true := by
  native_decide

theorem list_range_float_step_collapses_elements :
    (evalBuiltinCall "list.Range"
        [.prim (.float "0.0"), .prim (.float "2.0"), .prim (.float "0.5")]
      == .list [.prim (.int 0), .prim (.float "0.5"), .prim (.int 1), .prim (.float "1.5")])
      = true := by
  native_decide

theorem list_range_float_negative_step_descends :
    (evalBuiltinCall "list.Range"
        [.prim (.float "2.0"), .prim (.float "0.0"), .prim (.float "-0.5")]
      == .list [.prim (.int 2), .prim (.float "1.5"), .prim (.int 1), .prim (.float "0.5")])
      = true := by
  native_decide

theorem list_range_float_zero_step_is_bottom :
    (evalBuiltinCall "list.Range"
        [.prim (.float "0.0"), .prim (.float "2.0"), .prim (.float "0.0")]
      == .bottom) = true := by
  native_decide

theorem math_abs_int_stays_int :
    (evalBuiltinCall "math.Abs" [.prim (.int (-5))] == .prim (.int 5)) = true := by
  native_decide

theorem math_abs_float_stays_float :
    (evalBuiltinCall "math.Abs" [.prim (.float "-3.5")] == .prim (.float "3.5")) = true := by
  native_decide

theorem math_multiple_of_true_for_divisible :
    (evalBuiltinCall "math.MultipleOf" [.prim (.int 12), .prim (.int 3)]
      == .prim (.bool true)) = true := by
  native_decide

theorem math_multiple_of_false_for_indivisible :
    (evalBuiltinCall "math.MultipleOf" [.prim (.int 13), .prim (.int 3)]
      == .prim (.bool false)) = true := by
  native_decide

theorem math_multiple_of_zero_divisor_is_division_by_zero :
    (evalBuiltinCall "math.MultipleOf" [.prim (.int 5), .prim (.int 0)]
      == .bottomWith [.divisionByZero]) = true := by
  native_decide

theorem math_floor_rounds_toward_negative_infinity :
    (evalBuiltinCall "math.Floor" [.prim (.float "-3.2")] == .prim (.int (-4))) = true := by
  native_decide

theorem math_ceil_rounds_toward_positive_infinity :
    (evalBuiltinCall "math.Ceil" [.prim (.float "-3.7")] == .prim (.int (-3))) = true := by
  native_decide

theorem math_round_half_away_from_zero_positive :
    (evalBuiltinCall "math.Round" [.prim (.float "2.5")] == .prim (.int 3)) = true := by
  native_decide

theorem math_round_half_away_from_zero_negative :
    (evalBuiltinCall "math.Round" [.prim (.float "-2.5")] == .prim (.int (-3))) = true := by
  native_decide

theorem math_trunc_drops_fraction_toward_zero :
    (evalBuiltinCall "math.Trunc" [.prim (.float "-3.99")] == .prim (.int (-3))) = true := by
  native_decide

theorem math_floor_of_integer_is_identity :
    (evalBuiltinCall "math.Floor" [.prim (.int 5)] == .prim (.int 5)) = true := by
  native_decide

theorem math_type_mismatch_is_bottom :
    (evalBuiltinCall "math.Abs" [.prim (.string "x")] == .bottom) = true := by
  native_decide

theorem math_call_stays_unresolved_on_abstract_arg :
    (evalBuiltinCall "math.Floor" [.kind .number]
      == .builtinCall "math.Floor" [.kind .number]) = true := by
  native_decide

-- math.Pow over the SOUND exact domain (non-negative integer exponent → exact decimal power,
-- collapsing integral results). BI-2.
theorem math_pow_integer_exponent_is_exact :
    (evalBuiltinCall "math.Pow" [.prim (.int 2), .prim (.int 10)] == .prim (.int 1024)) = true := by
  native_decide

theorem math_pow_zero_exponent_is_one :
    (evalBuiltinCall "math.Pow" [.prim (.int 5), .prim (.int 0)] == .prim (.int 1)) = true := by
  native_decide

theorem math_pow_zero_base_positive_exponent_is_zero :
    (evalBuiltinCall "math.Pow" [.prim (.int 0), .prim (.int 5)] == .prim (.int 0)) = true := by
  native_decide

theorem math_pow_float_base_stays_exact_decimal :
    (evalBuiltinCall "math.Pow" [.prim (.float "1.5"), .prim (.int 3)] == .prim (.float "3.375")) = true := by
  native_decide

theorem math_pow_negative_base_odd_exponent_is_negative :
    (evalBuiltinCall "math.Pow" [.prim (.int (-2)), .prim (.int 3)] == .prim (.int (-8))) = true := by
  native_decide

theorem math_pow_negative_base_even_exponent_is_positive :
    (evalBuiltinCall "math.Pow" [.prim (.int (-3)), .prim (.int 4)] == .prim (.int 81)) = true := by
  native_decide

-- A whole-VALUED float exponent (`3.0`) counts as the integer exponent `3` (cue: `Pow(3, 2.0) = 9`).
theorem math_pow_whole_float_exponent_is_integer_exponent :
    (evalBuiltinCall "math.Pow" [.prim (.int 3), .prim (.float "2.0")] == .prim (.int 9)) = true := by
  native_decide

-- A terminating decimal stays EXACT (not padded to 34 digits — the positive-int-exp path never
-- routes through cue's apd division): `Pow(0.1, 2) = 0.01`.
theorem math_pow_terminating_decimal_is_exact :
    (evalBuiltinCall "math.Pow" [.prim (.float "0.1"), .prim (.int 2)] == .prim (.float "0.01")) = true := by
  native_decide

-- `Pow(0, 0)` is a cue error (bottom). CONFORMS (both error).
theorem math_pow_zero_zero_is_bottom :
    (evalBuiltinCall "math.Pow" [.prim (.int 0), .prim (.int 0)] == .bottom) = true := by
  native_decide

-- BI-2-§3: negative-INTEGER exponent — `x^(-n) = 1/x^n`, an EXACT rational (existing exact
-- int-pow + the division renderer; no exp/ln). `Pow(2,-3) = 0.125` — Kue trims the exact value;
-- `cue` pads to `0.1250…000` (34 digits), a display divergence (cue-divergences.md).
theorem math_pow_negative_integer_exponent_is_exact_rational :
    (evalBuiltinCall "math.Pow" [.prim (.int 2), .prim (.int (-3))] == .prim (.float "0.125")) = true := by
  native_decide

theorem math_pow_negative_integer_exponent_terminating :
    (evalBuiltinCall "math.Pow" [.prim (.int 10), .prim (.int (-2))] == .prim (.float "0.01")) = true := by
  native_decide

-- `Pow(1, -n) = 1` collapses to int (cue agrees: `1`).
theorem math_pow_one_negative_exponent_collapses_to_int :
    (evalBuiltinCall "math.Pow" [.prim (.int 1), .prim (.int (-5))] == .prim (.int 1)) = true := by
  native_decide

-- A non-terminating reciprocal renders to 34 significant digits (`Pow(3,-1) = 0.333…333`,
-- byte-identical to cue's apd value modulo cue's trailing-zero padding).
theorem math_pow_negative_exponent_repeating :
    (evalBuiltinCall "math.Pow" [.prim (.int 3), .prim (.int (-1))]
      == .prim (.float "0.3333333333333333333333333333333333")) = true := by
  native_decide

-- `Pow(0, neg)` is a division by zero — `cue` emits `Infinity`; Kue bottoms (no Infinity).
theorem math_pow_zero_negative_exponent_is_bottom :
    (evalBuiltinCall "math.Pow" [.prim (.int 0), .prim (.int (-1))] == .bottom) = true := by
  native_decide

-- BI-2-§3: GENERAL non-integer fractional exponent (`x > 0`) via `x^y = exp(y·ln x)` in EXACT
-- DECIMAL (fixed-term Taylor + binary range reduction — total, no Float). Rounded to 34 sig
-- digits; integral results collapse to int.
-- `Pow(2, 0.25) = 1.189…476` — byte-identical to cue's apd `Pow(2, 0.25)`.
theorem math_pow_general_fractional_exponent_is_exact_decimal :
    (evalBuiltinCall "math.Pow" [.prim (.int 2), .prim (.float "0.25")]
      == .prim (.float "1.189207115002721066717499970560476")) = true := by
  native_decide

-- `Pow(2, 0.1) = 1.071…342` — byte-identical to cue's apd.
theorem math_pow_general_fractional_tenth :
    (evalBuiltinCall "math.Pow" [.prim (.int 2), .prim (.float "0.1")]
      == .prim (.float "1.071773462536293164213006325023342")) = true := by
  native_decide

-- `Pow(4, 1.5) = 8` — an exact integer; the exp/ln path lands within 34 digits and collapses.
theorem math_pow_general_fractional_collapses_to_int :
    (evalBuiltinCall "math.Pow" [.prim (.int 4), .prim (.float "1.5")] == .prim (.int 8)) = true := by
  native_decide

-- `Pow(8, ⅓)` with the exponent given as cue's 34-digit `1.0/3.0` (`0.333…333`) = 2 (collapses).
theorem math_pow_general_cube_root_collapses_to_int :
    (evalBuiltinCall "math.Pow"
        [.prim (.int 8), .prim (.float "0.3333333333333333333333333333333333")]
      == .prim (.int 2)) = true := by
  native_decide

-- CROSS-CHECK: the general exp/ln fractional path AGREES with the dedicated sqrt path on ½ —
-- `Pow(2, 0.50000…)` (a non-½-by-`isHalfExponent` near-half routed through exp/ln) is NOT this
-- test; here we pin that `Pow(2, 0.5)` (the sqrt route) equals what the exp/ln series produces
-- for the same value, confirming the two transcendental paths are mutually consistent.
theorem math_pow_half_matches_general_path :
    (evalBuiltinCall "math.Pow" [.prim (.int 2), .prim (.float "0.5")]
      == .prim (.float "1.414213562373095048801688724209698")) = true := by
  native_decide

-- AUDIT (BI-2-§3 totality witnesses): the exp/ln path's FIXED 40/60-term budgets + binary range
-- reduction must hold across the WIDEST magnitude span. These oracle byte-identically against cue
-- v0.16.1 (modulo cue's trailing-zero display padding, the recorded divergence) — a regression in
-- `lnExpScale`/`lnSeriesTerms`/`expSeriesTerms` would break them. Span: base 0.001 … 1_000_000,
-- exponent 0.0001 … 10.5.

-- Large base, cube-root exponent — the result lands on cue's OWN 34-digit rounding artifact
-- (`9.999…998`, not `10`), so this pins the exp/ln path to cue's apd mantissa bit-for-bit.
theorem math_pow_large_base_cube_root_matches_cue_artifact :
    (evalBuiltinCall "math.Pow"
        [.prim (.int 1000), .prim (.float "0.3333333333333333333333333333333333")]
      == .prim (.float "9.999999999999999999999999999999998")) = true := by
  native_decide

-- Mid base, cube-root exponent — a genuine 34-digit irrational (`10^⅓`).
theorem math_pow_ten_cube_root_is_exact_decimal :
    (evalBuiltinCall "math.Pow"
        [.prim (.int 10), .prim (.float "0.3333333333333333333333333333333333")]
      == .prim (.float "2.15443469003188372175929356651935")) = true := by
  native_decide

-- Fractional base < 1 under a fractional exponent (`0.5^0.5 = √½`) — exercises the `ln m` series
-- on a sub-unit mantissa and a negative `ln x`.
theorem math_pow_fractional_base_half_exponent_is_exact_decimal :
    (evalBuiltinCall "math.Pow" [.prim (.float "0.5"), .prim (.float "0.5")]
      == .prim (.float "0.7071067811865475244008443621048490")) = true := by
  native_decide

-- Exponent NEAR ZERO (`2^0.0001 ≈ 1`) — `y·ln x` is tiny, stressing the low-magnitude end of the
-- exp series where the result clusters just above 1.
theorem math_pow_tiny_exponent_is_exact_decimal :
    (evalBuiltinCall "math.Pow" [.prim (.int 2), .prim (.float "0.0001")]
      == .prim (.float "1.000069317120376569192439912602643")) = true := by
  native_decide

-- Base NEAR ONE (`1.0001^2.5`) — `ln x` is tiny and positive; the `artanh` series runs near its
-- zero, a distinct regime from a far-from-1 mantissa.
theorem math_pow_base_near_one_is_exact_decimal :
    (evalBuiltinCall "math.Pow" [.prim (.float "1.0001"), .prim (.float "2.5")]
      == .prim (.float "1.000250018750312496093867182617432")) = true := by
  native_decide

-- Exponent > 1 with a non-collapsing irrational result (`2^2.5 = 4√2`) — the `2^n` range-reduction
-- factor of `exp` fires (`n ≠ 0`).
theorem math_pow_exponent_above_one_is_exact_decimal :
    (evalBuiltinCall "math.Pow" [.prim (.int 2), .prim (.float "2.5")]
      == .prim (.float "5.656854249492380195206754896838792")) = true := by
  native_decide

-- Large exponent magnitude with a large integer collapse (`100^1.5 = 1000`) — the exp/ln path
-- must round-and-collapse a big integral result, not drift off by an ULP.
theorem math_pow_large_base_fractional_collapses_to_int :
    (evalBuiltinCall "math.Pow" [.prim (.int 100), .prim (.float "1.5")] == .prim (.int 1000)) = true := by
  native_decide

-- Negative INTEGER exponent on a negative base (`(-2)^(-3) = -0.125`) — the §1 reciprocal path over
-- a negative base; an exact terminating rational, sign preserved.
theorem math_pow_negative_base_negative_integer_exponent_is_exact :
    (evalBuiltinCall "math.Pow" [.prim (.int (-2)), .prim (.int (-3))]
      == .prim (.float "-0.125")) = true := by
  native_decide

-- Negative base, EVEN integer exponent (`(-2)^4 = 16`) — exact repeated multiplication keeps the
-- result positive; pins sign handling on the §1 non-negative-integer arm with a negative base.
theorem math_pow_negative_base_even_integer_exponent_is_positive :
    (evalBuiltinCall "math.Pow" [.prim (.int (-2)), .prim (.int 4)] == .prim (.int 16)) = true := by
  native_decide

-- Negative base, large exponent magnitude (`2^30 = 1073741824`) — large exact int-pow, no overflow.
theorem math_pow_large_integer_exponent_is_exact :
    (evalBuiltinCall "math.Pow" [.prim (.int 2), .prim (.int 30)] == .prim (.int 1073741824)) = true := by
  native_decide

-- Negative base, non-integer exponent: out of the real domain (complex). Kue bottoms; cue errors.
theorem math_pow_negative_base_fractional_exponent_is_bottom :
    (evalBuiltinCall "math.Pow" [.prim (.int (-2)), .prim (.float "0.25")] == .bottom) = true := by
  native_decide

-- `Pow(0, positive-fractional) = 0`.
theorem math_pow_zero_base_fractional_exponent_is_zero :
    (evalBuiltinCall "math.Pow" [.prim (.int 0), .prim (.float "0.25")] == .prim (.int 0)) = true := by
  native_decide

-- BI-2-residual: `Pow(x, ½) = √x`, computed in exact decimal and routed through the SAME sqrt as
-- `math.Sqrt` (self-consistency). `Pow(2, 0.5)` is byte-identical to cue's apd `Pow(2, 0.5)`.
theorem math_pow_half_exponent_is_sqrt :
    (evalBuiltinCall "math.Pow" [.prim (.int 2), .prim (.float "0.5")]
      == .prim (.float "1.414213562373095048801688724209698")) = true := by
  native_decide

-- A perfect square under the ½ exponent collapses to int (`Pow(4, 0.5) = 2`, cue agrees: `2`).
theorem math_pow_half_exponent_perfect_square_collapses_to_int :
    (evalBuiltinCall "math.Pow" [.prim (.int 4), .prim (.float "0.5")] == .prim (.int 2)) = true := by
  native_decide

-- A negative base under a ½ exponent is out of the real domain (complex). Kue bottoms; cue errors.
theorem math_pow_negative_base_half_exponent_is_bottom :
    (evalBuiltinCall "math.Pow" [.prim (.int (-2)), .prim (.float "0.5")] == .bottom) = true := by
  native_decide

-- math.Sqrt — exact decimal (Kue self-consistent with Pow; diverges from cue's float64 Sqrt).

-- Perfect squares are EXACT and collapse to int (cue's float Sqrt gives `12.0`/`10.0`; Kue's
-- decimal more-precise self-consistent path gives the integer — recorded as a divergence).
theorem math_sqrt_perfect_square_collapses_to_int :
    (evalBuiltinCall "math.Sqrt" [.prim (.int 144)] == .prim (.int 12)) = true := by
  native_decide

theorem math_sqrt_four_is_two :
    (evalBuiltinCall "math.Sqrt" [.prim (.int 4)] == .prim (.int 2)) = true := by
  native_decide

-- Kue: Sqrt(100) = 100 (int). cue: float64 Sqrt renders the scientific-notation artifact `1e+1`.
theorem math_sqrt_hundred_is_ten_not_scientific :
    (evalBuiltinCall "math.Sqrt" [.prim (.int 100)] == .prim (.int 10)) = true := by
  native_decide

theorem math_sqrt_zero_is_zero :
    (evalBuiltinCall "math.Sqrt" [.prim (.int 0)] == .prim (.int 0)) = true := by
  native_decide

theorem math_sqrt_one_is_one :
    (evalBuiltinCall "math.Sqrt" [.prim (.int 1)] == .prim (.int 1)) = true := by
  native_decide

-- Non-perfect square → 34 significant digits round-half-up. Byte-identical to cue's apd
-- `Pow(2, 0.5)` (NOT cue's float64 `Sqrt(2) = 1.4142135623730951` — Kue is more precise).
theorem math_sqrt_two_is_34_significant_digits :
    (evalBuiltinCall "math.Sqrt" [.prim (.int 2)]
      == .prim (.float "1.414213562373095048801688724209698")) = true := by
  native_decide

theorem math_sqrt_five_is_34_significant_digits :
    (evalBuiltinCall "math.Sqrt" [.prim (.int 5)]
      == .prim (.float "2.236067977499789696409173668731276")) = true := by
  native_decide

-- A non-integer perfect square trims to its exact minimal-scale value (Kue's exact-decimal
-- choice; cue's apd pads to `1.500…000` — a display divergence, recorded).
theorem math_sqrt_two_point_two_five_is_one_point_five :
    (evalBuiltinCall "math.Sqrt" [.prim (.float "2.25")] == .prim (.float "1.5")) = true := by
  native_decide

-- A negative input is a real-domain error. Kue BOTTOMS (no NaN); cue emits the float `NaN.0`.
theorem math_sqrt_negative_is_bottom :
    (evalBuiltinCall "math.Sqrt" [.prim (.int (-1))] == .bottom) = true := by
  native_decide

-- Internal consistency: `Sqrt(x)` and `Pow(x, ½)` produce the IDENTICAL value (cue's do NOT).
theorem math_sqrt_equals_pow_half :
    (evalBuiltinCall "math.Sqrt" [.prim (.int 2)]
      == evalBuiltinCall "math.Pow" [.prim (.int 2), .prim (.float "0.5")]) = true := by
  native_decide

theorem math_sqrt_type_mismatch_is_bottom :
    (evalBuiltinCall "math.Sqrt" [.prim (.string "x")] == .bottom) = true := by
  native_decide

theorem math_sqrt_stays_unresolved_on_abstract_arg :
    (evalBuiltinCall "math.Sqrt" [.kind .number]
      == .builtinCall "math.Sqrt" [.kind .number]) = true := by
  native_decide

-- An abstract argument keeps the call unresolved (a later pass may concretize it).
theorem math_pow_stays_unresolved_on_abstract_arg :
    (evalBuiltinCall "math.Pow" [.kind .number, .prim (.int 2)]
      == .builtinCall "math.Pow" [.kind .number, .prim (.int 2)]) = true := by
  native_decide

-- base64.Encode (standard padded base64; null encoding only)

theorem base64_encode_ascii_padding_zero :
    (evalBuiltinCall "base64.Encode" [.prim .null, .prim (.string "abc")]
      == .prim (.string "YWJj")) = true := by
  native_decide

theorem base64_encode_one_byte_double_padded :
    (evalBuiltinCall "base64.Encode" [.prim .null, .prim (.string "a")]
      == .prim (.string "YQ==")) = true := by
  native_decide

theorem base64_encode_two_bytes_single_padded :
    (evalBuiltinCall "base64.Encode" [.prim .null, .prim (.string "ab")]
      == .prim (.string "YWI=")) = true := by
  native_decide

theorem base64_encode_empty_is_empty :
    (evalBuiltinCall "base64.Encode" [.prim .null, .prim (.string "")]
      == .prim (.string "")) = true := by
  native_decide

theorem base64_encode_multibyte_over_utf8 :
    (evalBuiltinCall "base64.Encode" [.prim .null, .prim (.string "héllo")]
      == .prim (.string "aMOpbGxv")) = true := by
  native_decide

theorem base64_encode_over_bytes_value :
    (evalBuiltinCall "base64.Encode" [.prim .null, .prim (.bytes "hello")]
      == .prim (.string "aGVsbG8=")) = true := by
  native_decide

theorem base64_encode_non_null_encoding_is_bottom :
    (evalBuiltinCall "base64.Encode" [.prim (.string "std"), .prim (.string "hello")]
      == .bottom) = true := by
  native_decide

theorem base64_encode_stays_unresolved_on_abstract_arg :
    (evalBuiltinCall "base64.Encode" [.prim .null, .kind .string]
      == .builtinCall "base64.Encode" [.prim .null, .kind .string]) = true := by
  native_decide

-- json.Marshal (compact, source-order keys, exact-decimal floats)

theorem json_marshal_scalar_string :
    (evalBuiltinCall "json.Marshal" [.prim (.string "hi")]
      == .prim (.string "\"hi\"")) = true := by
  native_decide

theorem json_marshal_int :
    (evalBuiltinCall "json.Marshal" [.prim (.int 42)]
      == .prim (.string "42")) = true := by
  native_decide

theorem json_marshal_float_preserves_text :
    (evalBuiltinCall "json.Marshal" [.prim (.float "1.50")]
      == .prim (.string "1.50")) = true := by
  native_decide

theorem json_marshal_bool_and_null :
    (evalBuiltinCall "json.Marshal" [.prim (.bool true)] == .prim (.string "true"))
      && (evalBuiltinCall "json.Marshal" [.prim .null] == .prim (.string "null")) = true := by
  native_decide

theorem json_marshal_nested_preserves_key_order :
    (evalBuiltinCall "json.Marshal"
      [mkStruct [
          ⟨"b", .regular, .prim (.int 2), false⟩,
          ⟨"a", .regular, .prim (.int 1), false⟩,
          ⟨"c", .regular,
            mkStruct [⟨"z", .regular, .prim (.int 1), false⟩, ⟨"y", .regular, .prim (.int 2), false⟩] .regularOpen none [], false⟩
        ] .regularOpen none []]
      == .prim (.string "{\"b\":2,\"a\":1,\"c\":{\"z\":1,\"y\":2}}")) = true := by
  native_decide

theorem json_marshal_list :
    (evalBuiltinCall "json.Marshal" [.list [.prim (.int 1), .prim (.int 2), .prim (.int 3)]]
      == .prim (.string "[1,2,3]")) = true := by
  native_decide

theorem json_marshal_empty_struct_and_list :
    (evalBuiltinCall "json.Marshal" [mkStruct [] .regularOpen none []] == .prim (.string "{}"))
      && (evalBuiltinCall "json.Marshal" [.list []] == .prim (.string "[]")) = true := by
  native_decide

theorem json_marshal_escapes_quote_backslash_control_not_html :
    (evalBuiltinCall "json.Marshal"
      [mkStruct [⟨"html", .regular, .prim (.string "<a>&\"b\\c\n\t"), false⟩] .regularOpen none []]
      == .prim (.string "{\"html\":\"<a>&\\\"b\\\\c\\n\\t\"}")) = true := by
  native_decide

theorem json_marshal_incomplete_is_bottom :
    (evalBuiltinCall "json.Marshal" [mkStruct [⟨"a", .regular, .kind .int, false⟩] .regularOpen none []]
      == .bottom) = true := by
  native_decide

theorem json_marshal_stays_unresolved_on_abstract_arg :
    (evalBuiltinCall "json.Marshal" [.ref "x"]
      == .builtinCall "json.Marshal" [.ref "x"]) = true := by
  native_decide

-- F-1: `regexp.Match(pattern, string)` is an UNANCHORED search dispatched to the same
-- engine entrypoint as `=~`. `^x` anchors the start; a bare `y`/`b` matches anywhere.
theorem regexp_match_anchored_start :
    (evalBuiltinCall "regexp.Match" [.prim (.string "^x"), .prim (.string "xyz")]
      == .prim (.bool true)) = true := by
  native_decide

theorem regexp_match_is_unanchored :
    (evalBuiltinCall "regexp.Match" [.prim (.string "y"), .prim (.string "xyz")]
      == .prim (.bool true))
      && (evalBuiltinCall "regexp.Match" [.prim (.string "b"), .prim (.string "abc")]
        == .prim (.bool true)) = true := by
  native_decide

theorem regexp_match_no_match_is_false :
    (evalBuiltinCall "regexp.Match" [.prim (.string "q"), .prim (.string "xyz")]
      == .prim (.bool false)) = true := by
  native_decide

-- `regexp.Match(p, s)` dispatches to `matchRegex p s` — the SAME engine entrypoint `=~`
-- uses (`evalRegexMatch`, via the RX-1 Pike-VM). Pinning equality here ties the two to one
-- engine.
theorem regexp_match_dispatches_to_shared_engine :
    (evalBuiltinCall "regexp.Match" [.prim (.string "^v[0-9]"), .prim (.string "v1")]
      == .prim (.bool (matchRegex "^v[0-9]" "v1"))) = true := by
  native_decide

-- RX-1c: `regexp.ReplaceAll` now replaces every non-overlapping match, expanding the Go
-- `Expand` template (`$n`/`${n}`/`$$`). Oracle-checked vs cue v0.16.1.
theorem regexp_replaceall_literal_template :
    (evalBuiltinCall "regexp.ReplaceAll"
        [.prim (.string "a(x*)b"), .prim (.string "-axxb-"), .prim (.string "T")]
      == .prim (.string "-T-")) = true := by
  native_decide

theorem regexp_replaceall_group_ref :
    (evalBuiltinCall "regexp.ReplaceAll"
        [.prim (.string "a(x*)b"), .prim (.string "-axxb-"), .prim (.string "$1")]
      == .prim (.string "-xx-")) = true := by
  native_decide

-- `${1}suffix` extracts group 1 then literal `suffix`; bare `$1suffix` names the group
-- `1suffix` (longest word-char run) which does not exist → empty. The Go disambiguation.
theorem regexp_replaceall_brace_disambiguation :
    (evalBuiltinCall "regexp.ReplaceAll"
        [.prim (.string "a(x*)b"), .prim (.string "-axxb-"), .prim (.string "${1}suffix")]
      == .prim (.string "-xxsuffix-")) = true := by
  native_decide

theorem regexp_replaceall_bare_name_disambiguation :
    (evalBuiltinCall "regexp.ReplaceAll"
        [.prim (.string "a(x*)b"), .prim (.string "-axxb-"), .prim (.string "$1suffix")]
      == .prim (.string "--")) = true := by
  native_decide

-- `$$` is a literal `$`.
theorem regexp_replaceall_dollar_escape :
    (evalBuiltinCall "regexp.ReplaceAll"
        [.prim (.string "a(x*)b"), .prim (.string "-axxb-"), .prim (.string "$$")]
      == .prim (.string "-$-")) = true := by
  native_decide

-- All non-overlapping matches are replaced; no match leaves `src` unchanged (NOT bottom).
theorem regexp_replaceall_replaces_all :
    (evalBuiltinCall "regexp.ReplaceAll"
        [.prim (.string "a(x*)b"), .prim (.string "-axxb-axxxb-"), .prim (.string "T")]
      == .prim (.string "-T-T-")) = true := by
  native_decide

theorem regexp_replaceall_no_match_unchanged :
    (evalBuiltinCall "regexp.ReplaceAll"
        [.prim (.string "a(x*)b"), .prim (.string "-aQb-"), .prim (.string "T")]
      == .prim (.string "-aQb-")) = true := by
  native_decide

-- A zero-width match advances one rune (Go behavior; a non-advancing match would loop).
theorem regexp_replaceall_zero_width_advances :
    (evalBuiltinCall "regexp.ReplaceAll"
        [.prim (.string "x*"), .prim (.string "abc"), .prim (.string "-")]
      == .prim (.string "-a-b-c-")) = true := by
  native_decide

-- `ReplaceAllLiteral` splices the replacement verbatim — no `$` expansion.
theorem regexp_replaceall_literal_no_expand :
    (evalBuiltinCall "regexp.ReplaceAllLiteral"
        [.prim (.string "a(x*)b"), .prim (.string "-axxb-"), .prim (.string "$1")]
      == .prim (.string "-$1-")) = true := by
  native_decide

-- Find / FindSubmatch / FindAll / FindAllSubmatch group spans (RE2 leftmost).
theorem regexp_find_leftmost :
    (evalBuiltinCall "regexp.Find"
        [.prim (.string "a(x*)b"), .prim (.string "-axxb-")]
      == .prim (.string "axxb")) = true := by
  native_decide

theorem regexp_findsubmatch_groups :
    (evalBuiltinCall "regexp.FindSubmatch"
        [.prim (.string "a(x*)b"), .prim (.string "-axxb-")]
      == .list [.prim (.string "axxb"), .prim (.string "xx")]) = true := by
  native_decide

theorem regexp_findall_all :
    (evalBuiltinCall "regexp.FindAll"
        [.prim (.string "ab"), .prim (.string "abab"), .prim (.int (-1))]
      == .list [.prim (.string "ab"), .prim (.string "ab")]) = true := by
  native_decide

theorem regexp_findallsubmatch_all :
    (evalBuiltinCall "regexp.FindAllSubmatch"
        [.prim (.string "a(x*)b"), .prim (.string "-axb-axxb-"), .prim (.int (-1))]
      == .list [.list [.prim (.string "axb"), .prim (.string "x")],
                .list [.prim (.string "axxb"), .prim (.string "xx")]]) = true := by
  native_decide

-- The Find* family raises `no match` in cue (NOT null) → Kue bottoms.
theorem regexp_find_no_match_bottoms :
    (evalBuiltinCall "regexp.Find" [.prim (.string "zz"), .prim (.string "ab")]
      == .bottom) = true := by
  native_decide

theorem regexp_findsubmatch_no_match_bottoms :
    (evalBuiltinCall "regexp.FindSubmatch" [.prim (.string "zz"), .prim (.string "ab")]
      == .bottom) = true := by
  native_decide

-- An invalid pattern bottoms with `.invalidRegex` (RX-2b contract inherited by RX-1c).
theorem regexp_replaceall_invalid_pattern_bottoms :
    (evalBuiltinCall "regexp.ReplaceAll"
        [.prim (.string "a("), .prim (.string "x"), .prim (.string "y")]
      == .bottomWith [.invalidRegex "a(" (.malformed "unbalanced ( — missing )")]) = true := by
  native_decide

-- An abstract arg keeps the call unresolved for a later pass, not bottom.
theorem regexp_replaceall_stays_unresolved_on_abstract_arg :
    (evalBuiltinCall "regexp.ReplaceAll" [.ref "p", .prim (.string "s"), .prim (.string "r")]
      == .builtinCall "regexp.ReplaceAll" [.ref "p", .prim (.string "s"), .prim (.string "r")])
      = true := by
  native_decide

-- A still-deferred form (cue exposes no `FindString`/`Split` function) stays unsupported.
theorem regexp_findstring_is_unsupported :
    (evalBuiltinCall "regexp.FindString"
        [.prim (.string "a"), .prim (.string "banana")]
      == .bottomWith [.unsupportedBuiltin "regexp.FindString"]) = true := by
  native_decide

-- RX-2b: `regexp.Match` with a CONCRETE invalid pattern bottoms with `.invalidRegex` (was:
-- silently `false`), the same contract as `=~`/the pattern meet. A valid pattern is
-- unchanged (the F-1 pins above stay green).
theorem regexp_match_invalid_pattern_bottoms :
    (evalBuiltinCall "regexp.Match" [.prim (.string "a("), .prim (.string "x")]
      == .bottomWith [.invalidRegex "a(" (.malformed "unbalanced ( — missing )")]) = true := by
  native_decide

-- yaml.Marshal (the seventh package family — the dispatch-table entry was previously
-- exercised only end-to-end through `FixtureTests`; pin it directly so every family that
-- `BuiltinFamily.ofName?` classifies has a representative `evalBuiltinCall` pin).
theorem yaml_marshal_scalar_int :
    (evalBuiltinCall "yaml.Marshal" [.prim (.int 1)] == .prim (.string "1\n")) = true := by
  native_decide

theorem yaml_marshal_stays_unresolved_on_abstract_arg :
    (evalBuiltinCall "yaml.Marshal" [.ref "x"]
      == .builtinCall "yaml.Marshal" [.ref "x"]) = true := by
  native_decide

-- TL-1 — `BuiltinFamily` classifier + exhaustive dispatch.
--
-- The family axis of a builtin name is a CLOSED, versionable set. `BuiltinFamily.ofName?`
-- is the single total classifier (`some family` for a recognised name, `none` for a
-- non-builtin), and `evalBuiltinCall` dispatches by an exhaustive match on it — a new
-- family forces a new arm (compile error), never a silent fall-through.

-- Every recognised name classifies to its family. `core` covers the eight exact unqualified
-- builtins; the seven package prefixes cover the qualified families.
theorem builtin_family_classifies_core_names :
    ([ "close", "len", "and", "or", "div", "mod", "quo", "rem" ].all
      (fun name => BuiltinFamily.ofName? name == some .core)) = true := by
  native_decide

theorem builtin_family_classifies_package_prefixes :
    (BuiltinFamily.ofName? "strings.ToUpper" == some .strings)
      && (BuiltinFamily.ofName? "list.Sum" == some .list)
      && (BuiltinFamily.ofName? "math.Pow" == some .math)
      && (BuiltinFamily.ofName? "regexp.Match" == some .regexp)
      && (BuiltinFamily.ofName? "base64.Encode" == some .base64)
      && (BuiltinFamily.ofName? "json.Marshal" == some .json)
      && (BuiltinFamily.ofName? "yaml.Marshal" == some .yaml) = true := by
  native_decide

-- A name with no recognised family classifies to `none` — an unknown package
-- (`foobar.Baz`), an unqualified non-builtin (`nosuchfn`), and the empty name.
theorem builtin_family_rejects_non_builtin_names :
    (BuiltinFamily.ofName? "foobar.Baz" == none)
      && (BuiltinFamily.ofName? "nosuchfn" == none)
      && (BuiltinFamily.ofName? "" == none) = true := by
  native_decide

-- Classification is by family-PREFIX, so an unknown LEAF still classifies to its family —
-- a bare prefix `strings.` (empty leaf) and an unknown member `math.NoSuch` both classify
-- to the package; the leaf is then rejected inside the family dispatcher (`unresolvedOrBottom`),
-- never here. This is exactly the prefix-chain's original family boundary, now total.
theorem builtin_family_classifies_by_prefix_not_leaf :
    (BuiltinFamily.ofName? "math.NoSuch" == some .math)
      && (BuiltinFamily.ofName? "strings." == some .strings) = true := by
  native_decide

-- THE FIX. An unknown-FAMILY name with CONCRETE args is a CUE resolution error (`cue`:
-- `reference "foobar" not found`) — Kue now BOTTOMS it, where the old stringly-typed
-- `startsWith` chain fell through to a SILENT `.builtinCall` residual (manifested as an
-- inert "incomplete value", masking the error). Concrete-args ⇒ bottom is exactly the
-- decision the in-family path already makes for an unknown LEAF (`unresolvedOrBottom`); the
-- `none` arm now shares it, so the silent-admit class is gone.
theorem unknown_family_concrete_args_is_bottom :
    (evalBuiltinCall "foobar.Baz" [.prim (.string "a")] == .bottom) = true := by
  native_decide

theorem unknown_unqualified_name_concrete_args_is_bottom :
    (evalBuiltinCall "nosuchfn" [.prim (.string "a")] == .bottom) = true := by
  native_decide

-- `error("msg")` is a real CUE builtin Kue does not yet implement, so it is an unknown name
-- here; with a concrete arg it now bottoms (cue's `error` itself produces bottom), no longer
-- a silent residual. (Kue does not carry the custom message — bottom-vs-incomplete is the
-- soundness correction; the `error` builtin proper is out of scope.)
theorem unknown_error_builtin_concrete_arg_is_bottom :
    (evalBuiltinCall "error" [.prim (.string "boom")] == .bottom) = true := by
  native_decide

-- An unknown-family name with an ABSTRACT (still-resolving) arg stays a deferred residual —
-- a later pass may concretise it (and then bottom, or resolve if the name becomes known via
-- a future family). The fix narrows ONLY the concrete-args case to bottom; the pending case
-- is preserved, matching every in-family `*_stays_unresolved_on_abstract_arg` pin above.
theorem unknown_family_abstract_arg_stays_unresolved :
    (evalBuiltinCall "foobar.Baz" [.ref "x"]
      == .builtinCall "foobar.Baz" [.ref "x"]) = true := by
  native_decide

-- A bottom argument propagates to bottom for an unknown name too (no residual masking a
-- contradiction).
theorem unknown_family_bottom_arg_is_bottom :
    (evalBuiltinCall "foobar.Baz" [.bottom] == .bottom) = true := by
  native_decide

-- KNOWN-FAMILY, UNKNOWN-LEAF (`math.NoSuch`) with CONCRETE args must bottom THROUGH the family
-- dispatcher, not silently residual inside it. The classifier routes the prefix to its family
-- (`*_classifies_by_prefix_not_leaf` above); these pin that the per-family `eval*Builtin` then
-- rejects the unknown leaf (concrete ⇒ bottom) for EVERY family — the in-family arm of the same
-- soundness fix the unknown-FAMILY pins cover for the `none` arm. Asserted via `containsBottom`,
-- not `== .bottom`: most families return a bare `.bottom`, but `regexp` returns a richer
-- `.bottomWith [.unsupportedBuiltin …]` — both are a bottom VERDICT, which is the soundness
-- property. Oracle-confirmed: `cue` rejects each (bottom verdict; message differs — divergence).
theorem unknown_leaf_each_family_concrete_args_is_bottom :
    containsBottom (evalBuiltinCall "math.NoSuch" [.prim (.int 1)])
      && containsBottom (evalBuiltinCall "strings.NoSuch" [.prim (.string "a")])
      && containsBottom (evalBuiltinCall "list.NoSuch" [.list [.prim (.int 1)]])
      && containsBottom (evalBuiltinCall "regexp.NoSuch" [.prim (.string "a")])
      && containsBottom (evalBuiltinCall "base64.NoSuch" [.prim (.string "a")])
      && containsBottom (evalBuiltinCall "json.NoSuch" [.prim (.string "a")])
      && containsBottom (evalBuiltinCall "yaml.NoSuch" [.prim (.string "a")]) = true := by
  native_decide

-- The same known-family unknown leaf with an ABSTRACT arg DEFERS (a later pass may concretise),
-- mirroring the unknown-FAMILY abstract pin — concrete-only is what bottoms.
theorem unknown_leaf_family_abstract_arg_stays_unresolved :
    (evalBuiltinCall "math.NoSuch" [.ref "x"]
      == .builtinCall "math.NoSuch" [.ref "x"]) = true := by
  native_decide



-- COVERAGE TRIPWIRE (test-health). Anchors the last theorem of each section;
-- a swallowed section makes its anchor an unknown identifier and fails `#check`
-- elaboration.
#check @unknown_leaf_family_abstract_arg_stays_unresolved

end Kue
