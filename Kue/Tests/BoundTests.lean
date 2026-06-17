import Kue.Format
import Kue.Lattice
import Kue.Order

namespace Kue

theorem format_int_bounds :
    formatValue (.boundConstraint (intDecimal 0) .ge .number) = ">=0" ∧ formatValue (.boundConstraint (intDecimal 10) .le .number) = "<=10" := by
  native_decide

theorem format_strict_int_bounds :
    formatValue (.boundConstraint (intDecimal 0) .gt .number) = ">0" ∧ formatValue (.boundConstraint (intDecimal 10) .lt .number) = "<10" := by
  native_decide

theorem meet_lower_bound_with_satisfying_int :
    meet (.boundConstraint (intDecimal 0) .ge .number) (.prim (.int 1)) = .prim (.int 1) := by
  rfl

theorem meet_lower_bound_with_violating_int :
    meet (.boundConstraint (intDecimal 0) .ge .number) (.prim (.int (-1))) = .bottomWith [.boundConflict] := by
  rfl

theorem meet_strict_lower_bound_with_satisfying_int :
    meet (.boundConstraint (intDecimal 0) .gt .number) (.prim (.int 1)) = .prim (.int 1) := by
  rfl

theorem meet_strict_lower_bound_with_violating_int :
    meet (.boundConstraint (intDecimal 0) .gt .number) (.prim (.int 0)) = .bottomWith [.boundConflict] := by
  rfl

theorem meet_lower_bounds_keeps_stricter_bound :
    meet (.boundConstraint (intDecimal 0) .ge .number) (.boundConstraint (intDecimal 5) .ge .number) = .boundConstraint (intDecimal 5) .ge .number := by
  rfl

theorem meet_upper_bounds_keeps_stricter_bound :
    meet (.boundConstraint (intDecimal 10) .le .number) (.boundConstraint (intDecimal 5) .le .number) = .boundConstraint (intDecimal 5) .le .number := by
  rfl

theorem meet_lower_and_upper_bound_keeps_conjunction :
    meet (.boundConstraint (intDecimal 0) .ge .number) (.boundConstraint (intDecimal 10) .le .number) = .conj [.boundConstraint (intDecimal 0) .ge .number, .boundConstraint (intDecimal 10) .le .number] := by
  rfl

theorem meet_strict_lower_and_upper_bound_keeps_conjunction :
    meet (.boundConstraint (intDecimal 0) .gt .number) (.boundConstraint (intDecimal 10) .lt .number) = .conj [.boundConstraint (intDecimal 0) .gt .number, .boundConstraint (intDecimal 10) .lt .number] := by
  rfl

theorem meet_bound_conjunction_with_satisfying_int :
    (meet (.conj [.boundConstraint (intDecimal 0) .ge .number, .boundConstraint (intDecimal 10) .le .number]) (.prim (.int 7)) == .prim (.int 7)) = true := by
  native_decide

theorem meet_strict_bound_conjunction_with_satisfying_int :
    (meet (.conj [.boundConstraint (intDecimal 0) .gt .number, .boundConstraint (intDecimal 10) .lt .number]) (.prim (.int 7)) == .prim (.int 7)) = true := by
  native_decide

theorem meet_struct_field_bound_conjunction_with_satisfying_int :
    (meet
      (.struct [("x", .regular, .conj [.boundConstraint (intDecimal 0) .ge .number, .boundConstraint (intDecimal 10) .le .number])] true)
      (.struct [("x", .regular, .prim (.int 7))] true)
      == .struct [("x", .regular, .prim (.int 7))] true) = true := by
  native_decide

theorem meet_struct_field_strict_bound_conjunction_with_satisfying_int :
    (meet
      (.struct [("x", .regular, .conj [.boundConstraint (intDecimal 0) .gt .number, .boundConstraint (intDecimal 10) .lt .number])] true)
      (.struct [("x", .regular, .prim (.int 7))] true)
      == .struct [("x", .regular, .prim (.int 7))] true) = true := by
  native_decide

theorem lower_bound_subsumes_satisfying_int :
    subsumes (.boundConstraint (intDecimal 0) .ge .number) (.prim (.int 1)) = true := by
  native_decide

theorem lower_bound_rejects_violating_int :
    subsumes (.boundConstraint (intDecimal 0) .ge .number) (.prim (.int (-1))) = false := by
  native_decide

theorem upper_bound_subsumes_satisfying_int :
    subsumes (.boundConstraint (intDecimal 10) .le .number) (.prim (.int 7)) = true := by
  native_decide

theorem strict_lower_bound_subsumes_satisfying_int :
    subsumes (.boundConstraint (intDecimal 0) .gt .number) (.prim (.int 1)) = true := by
  native_decide

theorem strict_lower_bound_rejects_boundary_int :
    subsumes (.boundConstraint (intDecimal 0) .gt .number) (.prim (.int 0)) = false := by
  native_decide

theorem bound_conjunction_subsumes_satisfying_int :
    subsumes (.conj [.boundConstraint (intDecimal 0) .ge .number, .boundConstraint (intDecimal 10) .le .number]) (.prim (.int 7)) = true := by
  native_decide

/-- `int & >0` retains the `int` conjunct (oracle: `cue` v0.16.1 prints `int & >0`). A bare
    `>0` admits floats in CUE, so the `int` kind is load-bearing and must survive the meet,
    not collapse to the bound. -/
theorem meet_int_kind_with_strict_bound_retains_kind :
    (meet (.kind .int) (.boundConstraint (intDecimal 0) .gt .number) == .conj [.kind .int, .boundConstraint (intDecimal 0) .gt .number]) = true := by
  native_decide

theorem meet_strict_bound_with_int_kind_retains_kind :
    (meet (.boundConstraint (intDecimal 0) .gt .number) (.kind .int) == .conj [.kind .int, .boundConstraint (intDecimal 0) .gt .number]) = true := by
  native_decide

theorem format_int_kind_with_strict_bound :
    formatValue (meet (.kind .int) (.boundConstraint (intDecimal 0) .gt .number)) = "int & >0" := by
  native_decide

/-- A `number`-kinded bound drops the redundant kind (a bound is implicitly number-typed):
    `number & >0` → `>0`, matching `cue`. -/
theorem meet_number_kind_with_strict_bound_drops_kind :
    (meet (.kind .number) (.boundConstraint (intDecimal 0) .gt .number) == .boundConstraint (intDecimal 0) .gt .number) = true := by
  native_decide

/-- The float-rejection the `int` conjunct buys: `(int & >0) & 1.5` is bottom (mismatched
    int/float), where bare `>0 & 1.5` would otherwise admit the float in CUE. -/
theorem meet_int_strict_bound_rejects_float :
    (meet (meet (.kind .int) (.boundConstraint (intDecimal 0) .gt .number)) (.prim (.float "1.5")) == .bottomWith [.kindConflict .int .float]) = true := by
  native_decide

theorem meet_int_strict_bound_admits_satisfying_int :
    (meet (meet (.kind .int) (.boundConstraint (intDecimal 0) .gt .number)) (.prim (.int 5)) == .prim (.int 5)) = true := by
  native_decide

/-- An `int`-kinded multi-bound range stays flat with the kind retained:
    `int & >=0 & <=65535` → `int & >=0 & <=65535` (cue displays this as `uint16`; Kue keeps
    the structural conjunction). Pins that the conjunction reduction does not nest or scramble
    into bottom (the pre-fix multi-bound failure mode). -/
theorem meet_int_kind_with_range_stays_flat :
    (meet (meet (.kind .int) (.boundConstraint (intDecimal 0) .ge .number)) (.boundConstraint (intDecimal 65535) .le .number)
      == .conj [.kind .int, .boundConstraint (intDecimal 0) .ge .number, .boundConstraint (intDecimal 65535) .le .number]) = true := by
  native_decide

theorem meet_int_kind_range_admits_satisfying_int :
    (meet (meet (meet (.kind .int) (.boundConstraint (intDecimal 0) .ge .number)) (.boundConstraint (intDecimal 65535) .le .number)) (.prim (.int 8080))
      == .prim (.int 8080)) = true := by
  native_decide

/-- Idempotent: meeting `int & >0` with itself is `int & >0`, not a duplicated or nested
    conjunction. -/
theorem meet_int_strict_bound_idempotent :
    (meet (meet (.kind .int) (.boundConstraint (intDecimal 0) .gt .number)) (meet (.kind .int) (.boundConstraint (intDecimal 0) .gt .number))
      == .conj [.kind .int, .boundConstraint (intDecimal 0) .gt .number]) = true := by
  native_decide

theorem join_lower_bounds_keeps_weaker_bound :
    join (.boundConstraint (intDecimal 5) .ge .number) (.boundConstraint (intDecimal 0) .ge .number) = .boundConstraint (intDecimal 0) .ge .number := by
  rfl

theorem join_strict_lower_bounds_keeps_weaker_bound :
    join (.boundConstraint (intDecimal 5) .gt .number) (.boundConstraint (intDecimal 0) .gt .number) = .boundConstraint (intDecimal 0) .gt .number := by
  rfl

theorem join_upper_bounds_keeps_weaker_bound :
    join (.boundConstraint (intDecimal 5) .le .number) (.boundConstraint (intDecimal 10) .le .number) = .boundConstraint (intDecimal 10) .le .number := by
  rfl

theorem join_strict_upper_bounds_keeps_weaker_bound :
    join (.boundConstraint (intDecimal 5) .lt .number) (.boundConstraint (intDecimal 10) .lt .number) = .boundConstraint (intDecimal 10) .lt .number := by
  rfl

-- Commutativity of meet on the canonical form: the `.conj` member sort makes `a & b` and
-- `b & a` re-wrap to the same canonical value, so meet is commutative on these constraints.

theorem meet_bound_pair_commutes :
    (meet (.boundConstraint (intDecimal 0) .ge .number) (.boundConstraint (intDecimal 10) .le .number)
      == meet (.boundConstraint (intDecimal 10) .le .number) (.boundConstraint (intDecimal 0) .ge .number)) = true := by
  native_decide

theorem meet_strict_bound_pair_commutes :
    (meet (.boundConstraint (intDecimal 0) .gt .number) (.boundConstraint (intDecimal 10) .lt .number)
      == meet (.boundConstraint (intDecimal 10) .lt .number) (.boundConstraint (intDecimal 0) .gt .number)) = true := by
  native_decide

theorem meet_kind_bound_commutes :
    (meet (.kind .int) (.boundConstraint (intDecimal 0) .gt .number)
      == meet (.boundConstraint (intDecimal 0) .gt .number) (.kind .int)) = true := by
  native_decide

theorem meet_three_constraint_conj_commutes :
    (meet (meet (.kind .int) (.boundConstraint (intDecimal 0) .ge .number)) (.boundConstraint (intDecimal 65535) .le .number)
      == meet (meet (.boundConstraint (intDecimal 65535) .le .number) (.boundConstraint (intDecimal 0) .ge .number)) (.kind .int)) = true := by
  native_decide

theorem meet_bound_notprim_commutes :
    (meet (.boundConstraint (intDecimal 0) .ge .number) (.notPrim (.int 5))
      == meet (.notPrim (.int 5)) (.boundConstraint (intDecimal 0) .ge .number)) = true := by
  native_decide

theorem meet_canonical_conj_member_order :
    (meet (.boundConstraint (intDecimal 10) .le .number) (.boundConstraint (intDecimal 0) .ge .number)
      == .conj [.boundConstraint (intDecimal 0) .ge .number, .boundConstraint (intDecimal 10) .le .number]) = true := by
  native_decide

-- 2b: decimal-valued, number-domain bound semantics. A bare bound is number-domain (admits
-- floats); `int &` narrows via the kept kind conjunct; decimal limits compare exactly.

/-- The 2b fix: a bare bound admits a float (`>0 & 1.5` ⇒ `1.5`), where the pre-2b int-only
    bound bottomed. -/
theorem meet_bare_bound_admits_float :
    (meet (.boundConstraint (intDecimal 0) .gt .number) (.prim (.float "1.5")) == .prim (.float "1.5")) = true := by
  native_decide

/-- `int & >0` still rejects a float — the kept `int` conjunct, not the bound, enforces it. -/
theorem meet_int_bound_rejects_float :
    (meet (meet (.kind .int) (.boundConstraint (intDecimal 0) .gt .number)) (.prim (.float "1.5"))
      == .bottomWith [.kindConflict .int .float]) = true := by
  native_decide

/-- A `float`-domain bound rejects an int operand (`float & >0 & 1` ⇒ ⊥). -/
theorem meet_float_bound_rejects_int :
    (meet (meet (.kind .float) (.boundConstraint (intDecimal 0) .gt .number)) (.prim (.int 1))
      == .bottomWith [.kindConflict .float .int]) = true := by
  native_decide

/-- A decimal bound literal compares exactly: `>0.5` admits `1.0`, rejects `0.25`. -/
theorem meet_decimal_bound_admits_and_rejects :
    (meet (.boundConstraint { numerator := 5, scale := 1 } .gt .number) (.prim (.float "1.0")) == .prim (.float "1.0")) = true
      ∧ (meet (.boundConstraint { numerator := 5, scale := 1 } .gt .number) (.prim (.float "0.25"))
          == .bottomWith [.boundConflict]) = true := by
  native_decide

/-- A decimal bound prints with its fractional limit (`>0.5`), a whole limit without
    (`>0` not `>0.0`). -/
theorem format_decimal_bound :
    formatValue (.boundConstraint { numerator := 5, scale := 1 } .gt .number) = ">0.5"
      ∧ formatValue (.boundConstraint (intDecimal 0) .gt .number) = ">0" := by
  native_decide

/-- A negative decimal lower bound (`>-1.5`) admits `0`. -/
theorem meet_negative_decimal_bound_admits :
    (meet (.boundConstraint { numerator := -15, scale := 1 } .gt .number) (.prim (.int 0)) == .prim (.int 0)) = true := by
  native_decide

/-- Exact-scale comparison: a limit and a value that are numerically equal but written at
    different scales (`>0.50` vs `0.5`) compare as equal, so the strict bound rejects and
    the non-strict bound admits — no trailing-zero/precision artifact. -/
theorem meet_decimal_bound_trailing_zero_tie :
    (meet (.boundConstraint { numerator := 50, scale := 2 } .gt .number) (.prim (.float "0.5"))
        == .bottomWith [.boundConflict]) = true
      ∧ (meet (.boundConstraint { numerator := 50, scale := 2 } .ge .number) (.prim (.float "0.5"))
          == .prim (.float "0.5")) = true := by
  native_decide

end Kue
