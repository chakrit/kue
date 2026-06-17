import Kue.Format
import Kue.Lattice
import Kue.Order

namespace Kue

theorem format_int_bounds :
    formatValue (.boundConstraint 0 .ge) = ">=0" ∧ formatValue (.boundConstraint 10 .le) = "<=10" := by
  native_decide

theorem format_strict_int_bounds :
    formatValue (.boundConstraint 0 .gt) = ">0" ∧ formatValue (.boundConstraint 10 .lt) = "<10" := by
  native_decide

theorem meet_lower_bound_with_satisfying_int :
    meet (.boundConstraint 0 .ge) (.prim (.int 1)) = .prim (.int 1) := by
  rfl

theorem meet_lower_bound_with_violating_int :
    meet (.boundConstraint 0 .ge) (.prim (.int (-1))) = .bottomWith [.intBoundConflict] := by
  rfl

theorem meet_strict_lower_bound_with_satisfying_int :
    meet (.boundConstraint 0 .gt) (.prim (.int 1)) = .prim (.int 1) := by
  rfl

theorem meet_strict_lower_bound_with_violating_int :
    meet (.boundConstraint 0 .gt) (.prim (.int 0)) = .bottomWith [.intBoundConflict] := by
  rfl

theorem meet_lower_bounds_keeps_stricter_bound :
    meet (.boundConstraint 0 .ge) (.boundConstraint 5 .ge) = .boundConstraint 5 .ge := by
  rfl

theorem meet_upper_bounds_keeps_stricter_bound :
    meet (.boundConstraint 10 .le) (.boundConstraint 5 .le) = .boundConstraint 5 .le := by
  rfl

theorem meet_lower_and_upper_bound_keeps_conjunction :
    meet (.boundConstraint 0 .ge) (.boundConstraint 10 .le) = .conj [.boundConstraint 0 .ge, .boundConstraint 10 .le] := by
  rfl

theorem meet_strict_lower_and_upper_bound_keeps_conjunction :
    meet (.boundConstraint 0 .gt) (.boundConstraint 10 .lt) = .conj [.boundConstraint 0 .gt, .boundConstraint 10 .lt] := by
  rfl

theorem meet_bound_conjunction_with_satisfying_int :
    (meet (.conj [.boundConstraint 0 .ge, .boundConstraint 10 .le]) (.prim (.int 7)) == .prim (.int 7)) = true := by
  native_decide

theorem meet_strict_bound_conjunction_with_satisfying_int :
    (meet (.conj [.boundConstraint 0 .gt, .boundConstraint 10 .lt]) (.prim (.int 7)) == .prim (.int 7)) = true := by
  native_decide

theorem meet_struct_field_bound_conjunction_with_satisfying_int :
    (meet
      (.struct [("x", .regular, .conj [.boundConstraint 0 .ge, .boundConstraint 10 .le])] true)
      (.struct [("x", .regular, .prim (.int 7))] true)
      == .struct [("x", .regular, .prim (.int 7))] true) = true := by
  native_decide

theorem meet_struct_field_strict_bound_conjunction_with_satisfying_int :
    (meet
      (.struct [("x", .regular, .conj [.boundConstraint 0 .gt, .boundConstraint 10 .lt])] true)
      (.struct [("x", .regular, .prim (.int 7))] true)
      == .struct [("x", .regular, .prim (.int 7))] true) = true := by
  native_decide

theorem lower_bound_subsumes_satisfying_int :
    subsumes (.boundConstraint 0 .ge) (.prim (.int 1)) = true := by
  native_decide

theorem lower_bound_rejects_violating_int :
    subsumes (.boundConstraint 0 .ge) (.prim (.int (-1))) = false := by
  native_decide

theorem upper_bound_subsumes_satisfying_int :
    subsumes (.boundConstraint 10 .le) (.prim (.int 7)) = true := by
  native_decide

theorem strict_lower_bound_subsumes_satisfying_int :
    subsumes (.boundConstraint 0 .gt) (.prim (.int 1)) = true := by
  native_decide

theorem strict_lower_bound_rejects_boundary_int :
    subsumes (.boundConstraint 0 .gt) (.prim (.int 0)) = false := by
  native_decide

theorem bound_conjunction_subsumes_satisfying_int :
    subsumes (.conj [.boundConstraint 0 .ge, .boundConstraint 10 .le]) (.prim (.int 7)) = true := by
  native_decide

/-- `int & >0` retains the `int` conjunct (oracle: `cue` v0.16.1 prints `int & >0`). A bare
    `>0` admits floats in CUE, so the `int` kind is load-bearing and must survive the meet,
    not collapse to the bound. -/
theorem meet_int_kind_with_strict_bound_retains_kind :
    (meet (.kind .int) (.boundConstraint 0 .gt) == .conj [.kind .int, .boundConstraint 0 .gt]) = true := by
  native_decide

theorem meet_strict_bound_with_int_kind_retains_kind :
    (meet (.boundConstraint 0 .gt) (.kind .int) == .conj [.kind .int, .boundConstraint 0 .gt]) = true := by
  native_decide

theorem format_int_kind_with_strict_bound :
    formatValue (meet (.kind .int) (.boundConstraint 0 .gt)) = "int & >0" := by
  native_decide

/-- A `number`-kinded bound drops the redundant kind (a bound is implicitly number-typed):
    `number & >0` → `>0`, matching `cue`. -/
theorem meet_number_kind_with_strict_bound_drops_kind :
    (meet (.kind .number) (.boundConstraint 0 .gt) == .boundConstraint 0 .gt) = true := by
  native_decide

/-- The float-rejection the `int` conjunct buys: `(int & >0) & 1.5` is bottom (mismatched
    int/float), where bare `>0 & 1.5` would otherwise admit the float in CUE. -/
theorem meet_int_strict_bound_rejects_float :
    (meet (meet (.kind .int) (.boundConstraint 0 .gt)) (.prim (.float "1.5")) == .bottomWith [.kindConflict .int .float]) = true := by
  native_decide

theorem meet_int_strict_bound_admits_satisfying_int :
    (meet (meet (.kind .int) (.boundConstraint 0 .gt)) (.prim (.int 5)) == .prim (.int 5)) = true := by
  native_decide

/-- An `int`-kinded multi-bound range stays flat with the kind retained:
    `int & >=0 & <=65535` → `int & >=0 & <=65535` (cue displays this as `uint16`; Kue keeps
    the structural conjunction). Pins that the conjunction reduction does not nest or scramble
    into bottom (the pre-fix multi-bound failure mode). -/
theorem meet_int_kind_with_range_stays_flat :
    (meet (meet (.kind .int) (.boundConstraint 0 .ge)) (.boundConstraint 65535 .le)
      == .conj [.kind .int, .boundConstraint 0 .ge, .boundConstraint 65535 .le]) = true := by
  native_decide

theorem meet_int_kind_range_admits_satisfying_int :
    (meet (meet (meet (.kind .int) (.boundConstraint 0 .ge)) (.boundConstraint 65535 .le)) (.prim (.int 8080))
      == .prim (.int 8080)) = true := by
  native_decide

/-- Idempotent: meeting `int & >0` with itself is `int & >0`, not a duplicated or nested
    conjunction. -/
theorem meet_int_strict_bound_idempotent :
    (meet (meet (.kind .int) (.boundConstraint 0 .gt)) (meet (.kind .int) (.boundConstraint 0 .gt))
      == .conj [.kind .int, .boundConstraint 0 .gt]) = true := by
  native_decide

theorem join_lower_bounds_keeps_weaker_bound :
    join (.boundConstraint 5 .ge) (.boundConstraint 0 .ge) = .boundConstraint 0 .ge := by
  rfl

theorem join_strict_lower_bounds_keeps_weaker_bound :
    join (.boundConstraint 5 .gt) (.boundConstraint 0 .gt) = .boundConstraint 0 .gt := by
  rfl

theorem join_upper_bounds_keeps_weaker_bound :
    join (.boundConstraint 5 .le) (.boundConstraint 10 .le) = .boundConstraint 10 .le := by
  rfl

theorem join_strict_upper_bounds_keeps_weaker_bound :
    join (.boundConstraint 5 .lt) (.boundConstraint 10 .lt) = .boundConstraint 10 .lt := by
  rfl

-- Commutativity of meet on the canonical form: the `.conj` member sort makes `a & b` and
-- `b & a` re-wrap to the same canonical value, so meet is commutative on these constraints.

theorem meet_bound_pair_commutes :
    (meet (.boundConstraint 0 .ge) (.boundConstraint 10 .le)
      == meet (.boundConstraint 10 .le) (.boundConstraint 0 .ge)) = true := by
  native_decide

theorem meet_strict_bound_pair_commutes :
    (meet (.boundConstraint 0 .gt) (.boundConstraint 10 .lt)
      == meet (.boundConstraint 10 .lt) (.boundConstraint 0 .gt)) = true := by
  native_decide

theorem meet_kind_bound_commutes :
    (meet (.kind .int) (.boundConstraint 0 .gt)
      == meet (.boundConstraint 0 .gt) (.kind .int)) = true := by
  native_decide

theorem meet_three_constraint_conj_commutes :
    (meet (meet (.kind .int) (.boundConstraint 0 .ge)) (.boundConstraint 65535 .le)
      == meet (meet (.boundConstraint 65535 .le) (.boundConstraint 0 .ge)) (.kind .int)) = true := by
  native_decide

theorem meet_bound_notprim_commutes :
    (meet (.boundConstraint 0 .ge) (.notPrim (.int 5))
      == meet (.notPrim (.int 5)) (.boundConstraint 0 .ge)) = true := by
  native_decide

theorem meet_canonical_conj_member_order :
    (meet (.boundConstraint 10 .le) (.boundConstraint 0 .ge)
      == .conj [.boundConstraint 0 .ge, .boundConstraint 10 .le]) = true := by
  native_decide

end Kue
