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

end Kue
