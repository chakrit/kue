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

end Kue
