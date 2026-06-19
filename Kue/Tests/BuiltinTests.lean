import Kue.Builtin
import Kue.Lattice

namespace Kue

theorem close_value_marks_struct_closed :
    closeValue (mkStruct [⟨"a", .regular, .kind .int⟩] .regularOpen none [])
      = mkStruct [⟨"a", .regular, .kind .int⟩] .defClosed none [] := by
  rfl

theorem close_value_rejects_extra_field_after_meet :
    meet
      (closeValue (mkStruct [⟨"a", .regular, .kind .int⟩] .regularOpen none []))
      (mkStruct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.int 2)⟩] .regularOpen none [])
      =
        mkStruct [
            ⟨"a", .regular, .prim (.int 1)⟩,
            ⟨"b", .regular, .bottomWith [.fieldNotAllowed "b"]⟩
          ] .defClosed none [] := by
  rfl

theorem close_value_is_shallow_for_nested_regular_structs :
    closeValue
      (mkStruct [⟨"a", .regular, mkStruct [⟨"b", .regular, .kind .int⟩] .regularOpen none []⟩] .regularOpen none [])
      = mkStruct [⟨"a", .regular, mkStruct [⟨"b", .regular, .kind .int⟩] .regularOpen none []⟩] .defClosed none [] := by
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
          ⟨"a", .regular, .prim (.int 1)⟩,
          ⟨"b", .optional, .prim (.int 2)⟩,
          ⟨"_c", .hidden, .prim (.int 3)⟩,
          ⟨"#D", .definition, .prim (.int 4)⟩
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

theorem strings_to_upper_lowercases :
    (evalBuiltinCall "strings.ToUpper" [.prim (.string "hello world")]
      == .prim (.string "HELLO WORLD")) = true := by
  native_decide

theorem strings_to_upper_already_upper :
    (evalBuiltinCall "strings.ToUpper" [.prim (.string "ABC")]
      == .prim (.string "ABC")) = true := by
  native_decide

theorem strings_to_upper_empty :
    (evalBuiltinCall "strings.ToUpper" [.prim (.string "")]
      == .prim (.string "")) = true := by
  native_decide

theorem strings_to_upper_digits_punct_unchanged :
    (evalBuiltinCall "strings.ToUpper" [.prim (.string "abc123!@#")]
      == .prim (.string "ABC123!@#")) = true := by
  native_decide

theorem strings_to_lower_uppercases :
    (evalBuiltinCall "strings.ToLower" [.prim (.string "Hello WORLD")]
      == .prim (.string "hello world")) = true := by
  native_decide

theorem strings_to_lower_already_lower :
    (evalBuiltinCall "strings.ToLower" [.prim (.string "abc")]
      == .prim (.string "abc")) = true := by
  native_decide

theorem strings_to_lower_empty :
    (evalBuiltinCall "strings.ToLower" [.prim (.string "")]
      == .prim (.string "")) = true := by
  native_decide

theorem strings_to_lower_digits_punct_unchanged :
    (evalBuiltinCall "strings.ToLower" [.prim (.string "ABC123!@#")]
      == .prim (.string "abc123!@#")) = true := by
  native_decide

/-- `ToTitle` is per-word capitalization — the first letter of each whitespace-delimited
    word — NOT "upper-case every letter". A multi-word lowercase input proves it. -/
theorem strings_to_title_capitalizes_each_word :
    (evalBuiltinCall "strings.ToTitle" [.prim (.string "hello world foo")]
      == .prim (.string "Hello World Foo")) = true := by
  native_decide

/-- Already-upper input is left as-is (ToTitle only upper-cases word-initial letters;
    it never lower-cases the rest, distinguishing it from a "capitalize" that downcases). -/
theorem strings_to_title_leaves_upper_word_as_is :
    (evalBuiltinCall "strings.ToTitle" [.prim (.string "HELLO WORLD")]
      == .prim (.string "HELLO WORLD")) = true := by
  native_decide

theorem strings_to_title_empty :
    (evalBuiltinCall "strings.ToTitle" [.prim (.string "")]
      == .prim (.string "")) = true := by
  native_decide

/-- Word boundary is whitespace ONLY: `-`, `.`, `_`, `/` do NOT start a new word,
    so the letter after them is not capitalized. -/
theorem strings_to_title_non_whitespace_separators_dont_split :
    (evalBuiltinCall "strings.ToTitle" [.prim (.string "a-b a.b a_b a/b")]
      == .prim (.string "A-b A.b A_b A/b")) = true := by
  native_decide

/-- A digit is not a word separator: the letter following a digit mid-token is not
    capitalized; the letter after whitespace is. -/
theorem strings_to_title_digit_is_not_separator :
    (evalBuiltinCall "strings.ToTitle" [.prim (.string "3 abc a3bc")]
      == .prim (.string "3 Abc A3bc")) = true := by
  native_decide

theorem strings_to_title_leading_whitespace :
    (evalBuiltinCall "strings.ToTitle" [.prim (.string "  leading")]
      == .prim (.string "  Leading")) = true := by
  native_decide

/-- Non-ASCII deferral boundary (ToUpper): non-ASCII letters pass through unchanged
    (`Char.toUpper` is ASCII-only). Kue: "CAFé"; cue: "CAFÉ". Documented divergence. -/
theorem strings_to_upper_non_ascii_passthrough :
    (evalBuiltinCall "strings.ToUpper" [.prim (.string "café")]
      == .prim (.string "CAFé")) = true := by
  native_decide

/-- Non-ASCII deferral boundary (ToLower): non-ASCII letters pass through unchanged.
    Kue: "cafÉ"; cue: "café". Documented divergence. -/
theorem strings_to_lower_non_ascii_passthrough :
    (evalBuiltinCall "strings.ToLower" [.prim (.string "CAFÉ")]
      == .prim (.string "cafÉ")) = true := by
  native_decide

/-- Non-ASCII deferral boundary (ToTitle): a non-ASCII word-initial letter is not
    title-cased. Kue: "über alles" word `über` stays lowercase → "über Alles";
    cue: "Über Alles". Documented divergence. -/
theorem strings_to_title_non_ascii_passthrough :
    (evalBuiltinCall "strings.ToTitle" [.prim (.string "über alles")]
      == .prim (.string "über Alles")) = true := by
  native_decide

theorem strings_to_upper_abstract_arg_stays_unresolved :
    (evalBuiltinCall "strings.ToUpper" [.kind .string]
      == .builtinCall "strings.ToUpper" [.kind .string]) = true := by
  native_decide

theorem strings_to_title_non_string_is_bottom :
    (evalBuiltinCall "strings.ToTitle" [.prim (.int 1)]
      == .bottom) = true := by
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
          ⟨"b", .regular, .prim (.int 2)⟩,
          ⟨"a", .regular, .prim (.int 1)⟩,
          ⟨"c", .regular,
            mkStruct [⟨"z", .regular, .prim (.int 1)⟩, ⟨"y", .regular, .prim (.int 2)⟩] .regularOpen none []⟩
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
      [mkStruct [⟨"html", .regular, .prim (.string "<a>&\"b\\c\n\t")⟩] .regularOpen none []]
      == .prim (.string "{\"html\":\"<a>&\\\"b\\\\c\\n\\t\"}")) = true := by
  native_decide

theorem json_marshal_incomplete_is_bottom :
    (evalBuiltinCall "json.Marshal" [mkStruct [⟨"a", .regular, .kind .int⟩] .regularOpen none []]
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

-- A concrete deferred submatch/replace form (the engine cannot do these yet — RX-1)
-- yields a CLEAR unsupported signal, never a silent wrong answer.
theorem regexp_replaceall_is_unsupported_not_silent :
    (evalBuiltinCall "regexp.ReplaceAll"
        [.prim (.string "a"), .prim (.string "banana"), .prim (.string "X")]
      == .bottomWith [.unsupportedBuiltin "regexp.ReplaceAll"]) = true := by
  native_decide

-- A deferred form over an abstract arg stays unresolved for a later pass, not bottom.
theorem regexp_replaceall_stays_unresolved_on_abstract_arg :
    (evalBuiltinCall "regexp.ReplaceAll" [.ref "p", .prim (.string "s"), .prim (.string "r")]
      == .builtinCall "regexp.ReplaceAll" [.ref "p", .prim (.string "s"), .prim (.string "r")])
      = true := by
  native_decide

end Kue
