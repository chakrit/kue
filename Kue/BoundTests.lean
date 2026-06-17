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
    (meet (.conj [.intGe 0, .intLe 10]) (.prim (.int 7)) == .prim (.int 7)) = true := by
  native_decide

theorem meet_strict_bound_conjunction_with_satisfying_int :
    (meet (.conj [.intGt 0, .intLt 10]) (.prim (.int 7)) == .prim (.int 7)) = true := by
  native_decide

theorem meet_struct_field_bound_conjunction_with_satisfying_int :
    (meet
      (.struct [("x", .regular, .conj [.intGe 0, .intLe 10])] true)
      (.struct [("x", .regular, .prim (.int 7))] true)
      == .struct [("x", .regular, .prim (.int 7))] true) = true := by
  native_decide

theorem meet_struct_field_strict_bound_conjunction_with_satisfying_int :
    (meet
      (.struct [("x", .regular, .conj [.intGt 0, .intLt 10])] true)
      (.struct [("x", .regular, .prim (.int 7))] true)
      == .struct [("x", .regular, .prim (.int 7))] true) = true := by
  native_decide

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

/-- `int & >0` retains the `int` conjunct (oracle: `cue` v0.16.1 prints `int & >0`). A bare
    `>0` admits floats in CUE, so the `int` kind is load-bearing and must survive the meet,
    not collapse to the bound. -/
theorem meet_int_kind_with_strict_bound_retains_kind :
    (meet (.kind .int) (.intGt 0) == .conj [.kind .int, .intGt 0]) = true := by
  native_decide

theorem meet_strict_bound_with_int_kind_retains_kind :
    (meet (.intGt 0) (.kind .int) == .conj [.kind .int, .intGt 0]) = true := by
  native_decide

theorem format_int_kind_with_strict_bound :
    formatValue (meet (.kind .int) (.intGt 0)) = "int & >0" := by
  native_decide

/-- A `number`-kinded bound drops the redundant kind (a bound is implicitly number-typed):
    `number & >0` → `>0`, matching `cue`. -/
theorem meet_number_kind_with_strict_bound_drops_kind :
    (meet (.kind .number) (.intGt 0) == .intGt 0) = true := by
  native_decide

/-- The float-rejection the `int` conjunct buys: `(int & >0) & 1.5` is bottom (mismatched
    int/float), where bare `>0 & 1.5` would otherwise admit the float in CUE. -/
theorem meet_int_strict_bound_rejects_float :
    (meet (meet (.kind .int) (.intGt 0)) (.prim (.float "1.5")) == .bottomWith [.kindConflict .int .float]) = true := by
  native_decide

theorem meet_int_strict_bound_admits_satisfying_int :
    (meet (meet (.kind .int) (.intGt 0)) (.prim (.int 5)) == .prim (.int 5)) = true := by
  native_decide

/-- An `int`-kinded multi-bound range stays flat with the kind retained:
    `int & >=0 & <=65535` → `int & >=0 & <=65535` (cue displays this as `uint16`; Kue keeps
    the structural conjunction). Pins that the conjunction reduction does not nest or scramble
    into bottom (the pre-fix multi-bound failure mode). -/
theorem meet_int_kind_with_range_stays_flat :
    (meet (meet (.kind .int) (.intGe 0)) (.intLe 65535)
      == .conj [.kind .int, .intGe 0, .intLe 65535]) = true := by
  native_decide

theorem meet_int_kind_range_admits_satisfying_int :
    (meet (meet (meet (.kind .int) (.intGe 0)) (.intLe 65535)) (.prim (.int 8080))
      == .prim (.int 8080)) = true := by
  native_decide

/-- Idempotent: meeting `int & >0` with itself is `int & >0`, not a duplicated or nested
    conjunction. -/
theorem meet_int_strict_bound_idempotent :
    (meet (meet (.kind .int) (.intGt 0)) (meet (.kind .int) (.intGt 0))
      == .conj [.kind .int, .intGt 0]) = true := by
  native_decide

theorem join_lower_bounds_keeps_weaker_bound :
    join (.intGe 5) (.intGe 0) = .intGe 0 := by
  rfl

theorem join_strict_lower_bounds_keeps_weaker_bound :
    join (.intGt 5) (.intGt 0) = .intGt 0 := by
  rfl

theorem join_upper_bounds_keeps_weaker_bound :
    join (.intLe 5) (.intLe 10) = .intLe 10 := by
  rfl

theorem join_strict_upper_bounds_keeps_weaker_bound :
    join (.intLt 5) (.intLt 10) = .intLt 10 := by
  rfl

end Kue
