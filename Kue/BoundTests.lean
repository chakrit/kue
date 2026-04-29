import Kue.Format
import Kue.Lattice
import Kue.Order

namespace Kue

theorem format_int_bounds :
    formatValue (.intGe 0) = ">=0" ∧ formatValue (.intLe 10) = "<=10" := by
  native_decide

theorem format_strict_int_bounds :
    formatValue (.intGt 0) = ">0" ∧ formatValue (.intLt 10) = "<10" := by
  native_decide

theorem meet_lower_bound_with_satisfying_int :
    meet (.intGe 0) (.prim (.int 1)) = .prim (.int 1) := by
  rfl

theorem meet_lower_bound_with_violating_int :
    meet (.intGe 0) (.prim (.int (-1))) = .bottomWith [.intBoundConflict] := by
  rfl

theorem meet_strict_lower_bound_with_satisfying_int :
    meet (.intGt 0) (.prim (.int 1)) = .prim (.int 1) := by
  rfl

theorem meet_strict_lower_bound_with_violating_int :
    meet (.intGt 0) (.prim (.int 0)) = .bottomWith [.intBoundConflict] := by
  rfl

theorem meet_lower_bounds_keeps_stricter_bound :
    meet (.intGe 0) (.intGe 5) = .intGe 5 := by
  rfl

theorem meet_upper_bounds_keeps_stricter_bound :
    meet (.intLe 10) (.intLe 5) = .intLe 5 := by
  rfl

theorem meet_lower_and_upper_bound_keeps_conjunction :
    meet (.intGe 0) (.intLe 10) = .conj [.intGe 0, .intLe 10] := by
  rfl

theorem meet_strict_lower_and_upper_bound_keeps_conjunction :
    meet (.intGt 0) (.intLt 10) = .conj [.intGt 0, .intLt 10] := by
  rfl

theorem meet_bound_conjunction_with_satisfying_int :
    meet (.conj [.intGe 0, .intLe 10]) (.prim (.int 7)) = .prim (.int 7) := by
  rfl

theorem meet_strict_bound_conjunction_with_satisfying_int :
    meet (.conj [.intGt 0, .intLt 10]) (.prim (.int 7)) = .prim (.int 7) := by
  rfl

theorem meet_struct_field_bound_conjunction_with_satisfying_int :
    meet
      (.struct [("x", .regular, .conj [.intGe 0, .intLe 10])] true)
      (.struct [("x", .regular, .prim (.int 7))] true)
      = .struct [("x", .regular, .prim (.int 7))] true := by
  rfl

theorem meet_struct_field_strict_bound_conjunction_with_satisfying_int :
    meet
      (.struct [("x", .regular, .conj [.intGt 0, .intLt 10])] true)
      (.struct [("x", .regular, .prim (.int 7))] true)
      = .struct [("x", .regular, .prim (.int 7))] true := by
  rfl

theorem lower_bound_subsumes_satisfying_int :
    subsumes (.intGe 0) (.prim (.int 1)) = true := by
  native_decide

theorem lower_bound_rejects_violating_int :
    subsumes (.intGe 0) (.prim (.int (-1))) = false := by
  native_decide

theorem upper_bound_subsumes_satisfying_int :
    subsumes (.intLe 10) (.prim (.int 7)) = true := by
  native_decide

theorem strict_lower_bound_subsumes_satisfying_int :
    subsumes (.intGt 0) (.prim (.int 1)) = true := by
  native_decide

theorem strict_lower_bound_rejects_boundary_int :
    subsumes (.intGt 0) (.prim (.int 0)) = false := by
  native_decide

theorem bound_conjunction_subsumes_satisfying_int :
    subsumes (.conj [.intGe 0, .intLe 10]) (.prim (.int 7)) = true := by
  native_decide

end Kue
