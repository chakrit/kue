import Kue.Format
import Kue.Lattice
import Kue.Order

namespace Kue

theorem format_float_kind_and_primitive :
    formatValue (.kind .float) = "float" ∧ formatValue (.prim (.float "1.5")) = "1.5" := by
  native_decide

theorem meet_float_kind_with_float_primitive :
    meet (.kind .float) (.prim (.float "1.5")) = .prim (.float "1.5") := by
  rfl

theorem meet_int_kind_with_float_primitive_bottoms :
    meet (.kind .int) (.prim (.float "1.5")) = .bottomWith [.kindConflict .int .float] := by
  rfl

theorem float_kind_subsumes_float_primitive :
    subsumes (.kind .float) (.prim (.float "1.5")) = true := by
  native_decide

theorem int_kind_rejects_float_primitive :
    subsumes (.kind .int) (.prim (.float "1.5")) = false := by
  native_decide

end Kue
