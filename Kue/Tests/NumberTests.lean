import Kue.Format
import Kue.Lattice
import Kue.Order

namespace Kue

theorem format_number_kind :
    formatValue (.kind .number) = "number" := by
  rfl

theorem meet_number_kind_with_int_primitive :
    meet (.kind .number) (.prim (.int 1)) = .prim (.int 1) := by
  rfl

theorem meet_number_kind_with_float_primitive :
    meet (.kind .number) (.prim (.float "1.5")) = .prim (.float "1.5") := by
  rfl

theorem meet_number_kind_with_int_kind :
    meet (.kind .number) (.kind .int) = .kind .int := by
  rfl

theorem meet_float_kind_with_number_kind :
    meet (.kind .float) (.kind .number) = .kind .float := by
  rfl

theorem meet_number_kind_with_int_exclusion :
    meet (.kind .number) (.notPrim (.int 0)) = .notPrim (.int 0) := by
  rfl

theorem meet_number_kind_with_string_primitive_bottoms :
    meet (.kind .number) (.prim (.string "x")) = .bottomWith [.kindConflict .number .string] := by
  rfl

theorem number_kind_subsumes_int_primitive :
    subsumes (.kind .number) (.prim (.int 1)) = true := by
  native_decide

theorem number_kind_subsumes_float_primitive :
    subsumes (.kind .number) (.prim (.float "1.5")) = true := by
  native_decide

theorem number_kind_subsumes_int_kind :
    subsumes (.kind .number) (.kind .int) = true := by
  native_decide

theorem number_kind_subsumes_float_kind :
    subsumes (.kind .number) (.kind .float) = true := by
  native_decide

theorem number_kind_rejects_string_primitive :
    subsumes (.kind .number) (.prim (.string "x")) = false := by
  native_decide

theorem join_number_kind_with_int_kind_normalizes :
    join (.kind .number) (.kind .int) = .kind .number := by
  rfl

theorem join_float_kind_with_number_kind_normalizes :
    join (.kind .float) (.kind .number) = .kind .number := by
  rfl

theorem join_number_kind_with_int_primitive_normalizes :
    join (.kind .number) (.prim (.int 1)) = .kind .number := by
  rfl

theorem join_number_kind_with_string_kind_keeps_disjunction :
    (join (.kind .number) (.kind .string) ==
      .disj [(.regular, .kind .number), (.regular, .kind .string)]) = true := by
  native_decide

theorem meet_number_kind_with_integer_lower_bound :
    meet (.kind .number) (.boundConstraint (intDecimal 0) .ge .number) = .boundConstraint (intDecimal 0) .ge .number := by
  rfl

theorem meet_integer_upper_bound_with_number_kind :
    meet (.boundConstraint (intDecimal 10) .le .number) (.kind .number) = .boundConstraint (intDecimal 10) .le .number := by
  rfl

theorem meet_string_kind_with_integer_lower_bound_bottoms :
    meet (.kind .string) (.boundConstraint (intDecimal 0) .ge .number) = .bottomWith [.kindConflict .string .number] := by
  rfl

theorem join_number_kind_with_integer_strict_lower_bound_normalizes :
    join (.kind .number) (.boundConstraint (intDecimal 0) .gt .number) = .kind .number := by
  rfl

theorem join_integer_strict_upper_bound_with_number_kind_normalizes :
    join (.boundConstraint (intDecimal 10) .lt .number) (.kind .number) = .kind .number := by
  rfl

theorem number_kind_subsumes_integer_lower_bound :
    subsumes (.kind .number) (.boundConstraint (intDecimal 0) .ge .number) = true := by
  native_decide

-- Float unification compares by exact base-10 value, not by literal string, so two
-- renderings of the same value unify (keeping the left operand) instead of bottoming.
theorem meet_prim_float_trailing_zero_unifies :
    meetPrim (.float "1.0") (.float "1.00") = .prim (.float "1.0") := by
  rfl

theorem meet_prim_float_scientific_matches_decimal :
    meetPrim (.float "1e2") (.float "100.0") = .prim (.float "1e2") := by
  rfl

theorem meet_prim_float_distinct_values_bottoms :
    meetPrim (.float "1.0") (.float "2.0")
      = .bottomWith [.primitiveConflict (.float "1.0") (.float "2.0")] := by
  rfl

-- int-vs-float remains a type conflict even when the magnitudes coincide.
theorem meet_prim_int_float_same_magnitude_bottoms :
    meetPrim (.int 1) (.float "1.0")
      = .bottomWith [.primitiveConflict (.int 1) (.float "1.0")] := by
  rfl



-- COVERAGE TRIPWIRE (test-health). Anchors the last theorem of each section;
-- a swallowed section makes its anchor an unknown identifier and fails `#check`
-- elaboration.
#check @meet_prim_int_float_same_magnitude_bottoms

end Kue
