import Kue.Format
import Kue.Lattice
import Kue.Order

namespace Kue

theorem format_number_kind :
    formatValue (.kind .number) = "number" := by
  native_decide

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
    join (.kind .number) (.kind .string) =
      .disj [(.regular, .kind .number), (.regular, .kind .string)] := by
  rfl

theorem meet_number_kind_with_integer_lower_bound :
    meet (.kind .number) (.boundConstraint 0 .ge) = .boundConstraint 0 .ge := by
  rfl

theorem meet_integer_upper_bound_with_number_kind :
    meet (.boundConstraint 10 .le) (.kind .number) = .boundConstraint 10 .le := by
  rfl

theorem meet_string_kind_with_integer_lower_bound_bottoms :
    meet (.kind .string) (.boundConstraint 0 .ge) = .bottomWith [.kindConflict .string .int] := by
  rfl

theorem join_number_kind_with_integer_strict_lower_bound_normalizes :
    join (.kind .number) (.boundConstraint 0 .gt) = .kind .number := by
  rfl

theorem join_integer_strict_upper_bound_with_number_kind_normalizes :
    join (.boundConstraint 10 .lt) (.kind .number) = .kind .number := by
  rfl

theorem number_kind_subsumes_integer_lower_bound :
    subsumes (.kind .number) (.boundConstraint 0 .ge) = true := by
  native_decide

end Kue
