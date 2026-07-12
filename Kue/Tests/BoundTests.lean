import Kue.EvalOps
import Kue.Format
import Kue.Lattice
import Kue.Order

namespace Kue

theorem format_int_bounds :
    formatValue (.boundConstraint (.int 0 .number) .ge) = ">=0" ∧ formatValue (.boundConstraint (.int 10 .number) .le) = "<=10" := by
  native_decide

theorem format_strict_int_bounds :
    formatValue (.boundConstraint (.int 0 .number) .gt) = ">0" ∧ formatValue (.boundConstraint (.int 10 .number) .lt) = "<10" := by
  native_decide

theorem meet_lower_bound_with_satisfying_int :
    meet (.boundConstraint (.int 0 .number) .ge) (.prim (.int 1)) = .prim (.int 1) := by
  rfl

theorem meet_lower_bound_with_violating_int :
    meet (.boundConstraint (.int 0 .number) .ge) (.prim (.int (-1))) = .bottomWith [.boundConflict] := by
  rfl

theorem meet_strict_lower_bound_with_satisfying_int :
    meet (.boundConstraint (.int 0 .number) .gt) (.prim (.int 1)) = .prim (.int 1) := by
  rfl

theorem meet_strict_lower_bound_with_violating_int :
    meet (.boundConstraint (.int 0 .number) .gt) (.prim (.int 0)) = .bottomWith [.boundConflict] := by
  rfl

theorem meet_lower_bounds_keeps_stricter_bound :
    meet (.boundConstraint (.int 0 .number) .ge) (.boundConstraint (.int 5 .number) .ge) = .boundConstraint (.int 5 .number) .ge := by
  rfl

theorem meet_upper_bounds_keeps_stricter_bound :
    meet (.boundConstraint (.int 10 .number) .le) (.boundConstraint (.int 5 .number) .le) = .boundConstraint (.int 5 .number) .le := by
  rfl

theorem meet_lower_and_upper_bound_keeps_conjunction :
    meet (.boundConstraint (.int 0 .number) .ge) (.boundConstraint (.int 10 .number) .le) = .conj [.boundConstraint (.int 0 .number) .ge, .boundConstraint (.int 10 .number) .le] := by
  rfl

theorem meet_strict_lower_and_upper_bound_keeps_conjunction :
    meet (.boundConstraint (.int 0 .number) .gt) (.boundConstraint (.int 10 .number) .lt) = .conj [.boundConstraint (.int 0 .number) .gt, .boundConstraint (.int 10 .number) .lt] := by
  rfl

theorem meet_bound_conjunction_with_satisfying_int :
    (meet (.conj [.boundConstraint (.int 0 .number) .ge, .boundConstraint (.int 10 .number) .le]) (.prim (.int 7)) == .prim (.int 7)) = true := by
  native_decide

theorem meet_strict_bound_conjunction_with_satisfying_int :
    (meet (.conj [.boundConstraint (.int 0 .number) .gt, .boundConstraint (.int 10 .number) .lt]) (.prim (.int 7)) == .prim (.int 7)) = true := by
  native_decide

theorem meet_struct_field_bound_conjunction_with_satisfying_int :
    (meet
      (mkStruct [⟨"x", .regular, .conj [.boundConstraint (.int 0 .number) .ge, .boundConstraint (.int 10 .number) .le], false⟩] .regularOpen none [])
      (mkStruct [⟨"x", .regular, .prim (.int 7), false⟩] .regularOpen none [])
      == mkStruct [⟨"x", .regular, .prim (.int 7), false⟩] .regularOpen none []) = true := by
  native_decide

theorem meet_struct_field_strict_bound_conjunction_with_satisfying_int :
    (meet
      (mkStruct [⟨"x", .regular, .conj [.boundConstraint (.int 0 .number) .gt, .boundConstraint (.int 10 .number) .lt], false⟩] .regularOpen none [])
      (mkStruct [⟨"x", .regular, .prim (.int 7), false⟩] .regularOpen none [])
      == mkStruct [⟨"x", .regular, .prim (.int 7), false⟩] .regularOpen none []) = true := by
  native_decide

theorem lower_bound_subsumes_satisfying_int :
    subsumes (.boundConstraint (.int 0 .number) .ge) (.prim (.int 1)) = true := by
  native_decide

theorem lower_bound_rejects_violating_int :
    subsumes (.boundConstraint (.int 0 .number) .ge) (.prim (.int (-1))) = false := by
  native_decide

theorem upper_bound_subsumes_satisfying_int :
    subsumes (.boundConstraint (.int 10 .number) .le) (.prim (.int 7)) = true := by
  native_decide

theorem strict_lower_bound_subsumes_satisfying_int :
    subsumes (.boundConstraint (.int 0 .number) .gt) (.prim (.int 1)) = true := by
  native_decide

theorem strict_lower_bound_rejects_boundary_int :
    subsumes (.boundConstraint (.int 0 .number) .gt) (.prim (.int 0)) = false := by
  native_decide

theorem bound_conjunction_subsumes_satisfying_int :
    subsumes (.conj [.boundConstraint (.int 0 .number) .ge, .boundConstraint (.int 10 .number) .le]) (.prim (.int 7)) = true := by
  native_decide

-- `int & >0` retains the `int` conjunct (oracle: `cue` v0.16.1 prints `int & >0`). A bare
-- `>0` admits floats in CUE, so the `int` kind is load-bearing and must survive the meet,
-- not collapse to the bound.
theorem meet_int_kind_with_strict_bound_retains_kind :
    (meet (.kind .int) (.boundConstraint (.int 0 .number) .gt) == .conj [.kind .int, .boundConstraint (.int 0 .number) .gt]) = true := by
  native_decide

theorem meet_strict_bound_with_int_kind_retains_kind :
    (meet (.boundConstraint (.int 0 .number) .gt) (.kind .int) == .conj [.kind .int, .boundConstraint (.int 0 .number) .gt]) = true := by
  native_decide

theorem format_int_kind_with_strict_bound :
    formatValue (meet (.kind .int) (.boundConstraint (.int 0 .number) .gt)) = "int & >0" := by
  native_decide

-- A `number`-kinded bound drops the redundant kind (a bound is implicitly number-typed):
-- `number & >0` → `>0`, matching `cue`.
theorem meet_number_kind_with_strict_bound_drops_kind :
    (meet (.kind .number) (.boundConstraint (.int 0 .number) .gt) == .boundConstraint (.int 0 .number) .gt) = true := by
  native_decide

-- The float-rejection the `int` conjunct buys: `(int & >0) & 1.5` is bottom (mismatched
-- int/float), where bare `>0 & 1.5` would otherwise admit the float in CUE.
theorem meet_int_strict_bound_rejects_float :
    (meet (meet (.kind .int) (.boundConstraint (.int 0 .number) .gt)) (.prim (mkFloatText "1.5")) == .bottomWith [.kindConflict .int .float]) = true := by
  native_decide

theorem meet_int_strict_bound_admits_satisfying_int :
    (meet (meet (.kind .int) (.boundConstraint (.int 0 .number) .gt)) (.prim (.int 5)) == .prim (.int 5)) = true := by
  native_decide

-- An `int`-kinded multi-bound range stays flat with the kind retained:
-- `int & >=0 & <=65535` → `int & >=0 & <=65535` (cue displays this as `uint16`; Kue keeps
-- the structural conjunction). Pins that the conjunction reduction does not nest or scramble
-- into bottom (the pre-fix multi-bound failure mode).
theorem meet_int_kind_with_range_stays_flat :
    (meet (meet (.kind .int) (.boundConstraint (.int 0 .number) .ge)) (.boundConstraint (.int 65535 .number) .le)
      == .conj [.kind .int, .boundConstraint (.int 0 .number) .ge, .boundConstraint (.int 65535 .number) .le]) = true := by
  native_decide

theorem meet_int_kind_range_admits_satisfying_int :
    (meet (meet (meet (.kind .int) (.boundConstraint (.int 0 .number) .ge)) (.boundConstraint (.int 65535 .number) .le)) (.prim (.int 8080))
      == .prim (.int 8080)) = true := by
  native_decide

-- Idempotent: meeting `int & >0` with itself is `int & >0`, not a duplicated or nested
-- conjunction.
theorem meet_int_strict_bound_idempotent :
    (meet (meet (.kind .int) (.boundConstraint (.int 0 .number) .gt)) (meet (.kind .int) (.boundConstraint (.int 0 .number) .gt))
      == .conj [.kind .int, .boundConstraint (.int 0 .number) .gt]) = true := by
  native_decide

theorem join_lower_bounds_keeps_weaker_bound :
    join (.boundConstraint (.int 5 .number) .ge) (.boundConstraint (.int 0 .number) .ge) = .boundConstraint (.int 0 .number) .ge := by
  rfl

theorem join_strict_lower_bounds_keeps_weaker_bound :
    join (.boundConstraint (.int 5 .number) .gt) (.boundConstraint (.int 0 .number) .gt) = .boundConstraint (.int 0 .number) .gt := by
  rfl

theorem join_upper_bounds_keeps_weaker_bound :
    join (.boundConstraint (.int 5 .number) .le) (.boundConstraint (.int 10 .number) .le) = .boundConstraint (.int 10 .number) .le := by
  rfl

theorem join_strict_upper_bounds_keeps_weaker_bound :
    join (.boundConstraint (.int 5 .number) .lt) (.boundConstraint (.int 10 .number) .lt) = .boundConstraint (.int 10 .number) .lt := by
  rfl

-- Commutativity of meet on the canonical form: the `.conj` member sort makes `a & b` and
-- `b & a` re-wrap to the same canonical value, so meet is commutative on these constraints.

theorem meet_bound_pair_commutes :
    (meet (.boundConstraint (.int 0 .number) .ge) (.boundConstraint (.int 10 .number) .le)
      == meet (.boundConstraint (.int 10 .number) .le) (.boundConstraint (.int 0 .number) .ge)) = true := by
  native_decide

theorem meet_strict_bound_pair_commutes :
    (meet (.boundConstraint (.int 0 .number) .gt) (.boundConstraint (.int 10 .number) .lt)
      == meet (.boundConstraint (.int 10 .number) .lt) (.boundConstraint (.int 0 .number) .gt)) = true := by
  native_decide

theorem meet_kind_bound_commutes :
    (meet (.kind .int) (.boundConstraint (.int 0 .number) .gt)
      == meet (.boundConstraint (.int 0 .number) .gt) (.kind .int)) = true := by
  native_decide

theorem meet_three_constraint_conj_commutes :
    (meet (meet (.kind .int) (.boundConstraint (.int 0 .number) .ge)) (.boundConstraint (.int 65535 .number) .le)
      == meet (meet (.boundConstraint (.int 65535 .number) .le) (.boundConstraint (.int 0 .number) .ge)) (.kind .int)) = true := by
  native_decide

theorem meet_bound_notprim_commutes :
    (meet (.boundConstraint (.int 0 .number) .ge) (.notPrim (.int 5))
      == meet (.notPrim (.int 5)) (.boundConstraint (.int 0 .number) .ge)) = true := by
  native_decide

theorem meet_canonical_conj_member_order :
    (meet (.boundConstraint (.int 10 .number) .le) (.boundConstraint (.int 0 .number) .ge)
      == .conj [.boundConstraint (.int 0 .number) .ge, .boundConstraint (.int 10 .number) .le]) = true := by
  native_decide

-- 2b: decimal-valued, number-domain bound semantics. A bare bound is number-domain (admits
-- floats); `int &` narrows via the kept kind conjunct; decimal limits compare exactly.

-- The 2b fix: a bare bound admits a float (`>0 & 1.5` ⇒ `1.5`), where the pre-2b int-only
-- bound bottomed.
theorem meet_bare_bound_admits_float :
    (meet (.boundConstraint (.int 0 .number) .gt) (.prim (mkFloatText "1.5")) == .prim (mkFloatText "1.5")) = true := by
  native_decide

-- `int & >0` still rejects a float — the kept `int` conjunct, not the bound, enforces it.
theorem meet_int_bound_rejects_float :
    (meet (meet (.kind .int) (.boundConstraint (.int 0 .number) .gt)) (.prim (mkFloatText "1.5"))
      == .bottomWith [.kindConflict .int .float]) = true := by
  native_decide

-- A `float`-domain bound rejects an int operand (`float & >0 & 1` ⇒ ⊥).
theorem meet_float_bound_rejects_int :
    (meet (meet (.kind .float) (.boundConstraint (.int 0 .number) .gt)) (.prim (.int 1))
      == .bottomWith [.kindConflict .float .int]) = true := by
  native_decide

-- A decimal bound literal compares exactly: `>0.5` admits `1.0`, rejects `0.25`.
theorem meet_decimal_bound_admits_and_rejects :
    (meet (.boundConstraint (mkFloatBound "0.5") .gt) (.prim (mkFloatText "1.0")) == .prim (mkFloatText "1.0")) = true
      ∧ (meet (.boundConstraint (mkFloatBound "0.5") .gt) (.prim (mkFloatText "0.25"))
          == .bottomWith [.boundConflict]) = true := by
  native_decide

-- A decimal bound prints with its fractional limit (`>0.5`), a whole limit without
-- (`>0` not `>0.0`).
theorem format_decimal_bound :
    formatValue (.boundConstraint (mkFloatBound "0.5") .gt) = ">0.5"
      ∧ formatValue (.boundConstraint (.int 0 .number) .gt) = ">0" := by
  native_decide

-- A negative decimal lower bound (`>-1.5`) admits `0`.
theorem meet_negative_decimal_bound_admits :
    (meet (.boundConstraint (mkFloatBound "-1.5") .gt) (.prim (.int 0)) == .prim (.int 0)) = true := by
  native_decide

-- Exact-scale comparison: a limit and a value that are numerically equal but written at
-- different scales (`>0.50` vs `0.5`) compare as equal, so the strict bound rejects and
-- the non-strict bound admits — no trailing-zero/precision artifact.
theorem meet_decimal_bound_trailing_zero_tie :
    (meet (.boundConstraint (mkFloatBound "0.50") .gt) (.prim (mkFloatText "0.5"))
        == .bottomWith [.boundConflict]) = true
      ∧ (meet (.boundConstraint (mkFloatBound "0.50") .ge) (.prim (mkFloatText "0.5"))
          == .prim (mkFloatText "0.5")) = true := by
  native_decide


-- ORDERED-TYPE BOUNDS (PATTERN-BOUND-OPERAND): a comparator bound applies to any ordered
-- type — strings lexically by code point, bytes by byte order — not only numbers.

-- A string upper bound admits a lexically-smaller string and rejects a larger one; both
-- directions pinned.
theorem meet_string_upper_bound_admits_and_rejects :
    (meet (.boundConstraint (.string "m") .lt) (.prim (.string "apple")) == .prim (.string "apple")) = true
      ∧ (meet (.boundConstraint (.string "m") .lt) (.prim (.string "zebra"))
          == .bottomWith [.boundConflict]) = true := by
  native_decide

-- A string lower bound (`>"m"`) admits a lexically-greater string.
theorem meet_string_lower_bound_admits :
    (meet (.boundConstraint (.string "m") .gt) (.prim (.string "zebra")) == .prim (.string "zebra")) = true := by
  native_decide

-- An inclusive string bound admits the boundary value itself (`<="m" & "m"` ⇒ `"m"`).
theorem meet_string_inclusive_bound_admits_boundary :
    (meet (.boundConstraint (.string "m") .le) (.prim (.string "m")) == .prim (.string "m")) = true := by
  native_decide

-- A bytes bound compares by byte order.
theorem meet_bytes_bound_admits_and_rejects :
    (meet (.boundConstraint (.bytes #[0x6d]) .lt) (.prim (.bytes #[0x61])) == .prim (.bytes #[0x61])) = true
      ∧ (meet (.boundConstraint (.bytes #[0x6d]) .lt) (.prim (.bytes #[0x7a]))
          == .bottomWith [.boundConflict]) = true := by
  native_decide

-- Two same-side string bounds tighten to the tighter limit (`>"a" & >"m"` ⇒ `>"m"`).
theorem meet_string_bounds_tighten :
    (meet (.boundConstraint (.string "a") .gt) (.boundConstraint (.string "m") .gt)
      == .boundConstraint (.string "m") .gt) = true := by
  native_decide

-- A `!=` forbidden string sits inside a string bound's domain, so both are retained.
theorem meet_string_bound_with_notprim_string_retains_both :
    (meet (.boundConstraint (.string "m") .lt) (.notPrim (.string "a"))
      == .conj [.boundConstraint (.string "m") .lt, .notPrim (.string "a")]) = true := by
  native_decide

-- A regex and a string bound are both string constraints, so they conjoin.
theorem meet_regex_with_string_bound_conjoins :
    (meet (.stringRegex "^a") (.boundConstraint (.string "m") .lt)
      == .conj [.stringRegex "^a", .boundConstraint (.string "m") .lt]) = true := by
  native_decide

-- A string bound meeting the redundant `string` kind drops the kind (`string & <"m"` ⇒ `<"m"`).
theorem meet_string_kind_with_string_bound_drops_kind :
    (meet (.kind .string) (.boundConstraint (.string "m") .lt)
      == .boundConstraint (.string "m") .lt) = true := by
  native_decide

-- A TYPE-MISMATCH bound conflicts: a string bound against a numeric prim, and a numeric
-- kind against a string bound, both bottom.
theorem meet_string_bound_type_mismatch_bottoms :
    (meet (.boundConstraint (.string "m") .lt) (.prim (.int 5))
        == .bottomWith [.kindConflict .string .int]) = true
      ∧ (meet (.kind .int) (.boundConstraint (.string "m") .lt)
        == .bottomWith [.kindConflict .int .string]) = true := by
  native_decide

-- Two bounds of different ordered families share no inhabitant (`>5 & >"m"` ⇒ ⊥).
theorem meet_cross_family_bounds_bottoms :
    (meet (.boundConstraint (.int 5 .number) .gt) (.boundConstraint (.string "m") .gt)
      == .bottomWith [.kindConflict .int .string]) = true := by
  native_decide

-- A string/bytes bound renders as its quoted literal after the comparator.
theorem format_string_and_bytes_bounds :
    formatValue (.boundConstraint (.string "m") .lt) = "<\"m\""
      ∧ formatValue (.boundConstraint (.bytes #[0x6d]) .ge) = ">='m'" := by
  native_decide

-- Numeric bounds are unchanged by the generalization (regression guard).
theorem meet_numeric_bound_unchanged :
    (meet (.boundConstraint (.int 0 .number) .gt) (.prim (mkFloatText "1.5")) == .prim (mkFloatText "1.5")) = true
      ∧ (meet (.boundConstraint (.int 0 .number) .gt) (.prim (.int 0)) == .bottomWith [.boundConflict]) = true := by
  native_decide

-- ILLEGAL BOUND-OPERAND STATES ARE UNREPRESENTABLE (BOUND-ORDEREDPRIM).
-- `OrderedPrim` structurally excludes a non-ordered (null/bool) bound operand and a
-- domain-bearing string/bytes operand. `ofPrim?` is the single trust boundary refining a
-- `Prim` into a bound operand; null/bool have none, so no bound can hold them.
theorem ordered_prim_rejects_null_and_bool :
    OrderedPrim.ofPrim? .null = none
      ∧ OrderedPrim.ofPrim? (.bool true) = none
      ∧ OrderedPrim.ofPrim? (.bool false) = none := by
  native_decide

-- An ordered prim lifts to a bare `number`-domain operand (numbers) or a domainless
-- string/bytes operand — the inverse `toPrim` reconstructs it exactly.
theorem ordered_prim_lifts_ordered :
    OrderedPrim.ofPrim? (.int 5) = some (.int 5 .number)
      ∧ OrderedPrim.ofPrim? (.string "m") = some (.string "m")
      ∧ (OrderedPrim.ofPrim? (mkFloatText "1.5")).map OrderedPrim.toPrim = some (mkFloatText "1.5") := by
  native_decide

-- A string/bytes bound carries no numeric domain — the concept is structurally absent from
-- those arms (`domain?` is `none`), while a numeric bound reports its domain.
theorem string_bytes_bounds_have_no_domain :
    OrderedPrim.domain? (.string "m") = none
      ∧ OrderedPrim.domain? (.bytes #[0x6d]) = none
      ∧ OrderedPrim.domain? (.int 0 .number) = some .number := by
  native_decide

-- The eval boundary bottoms a null/bool operand exactly as before (behavior preserved via
-- the `ofPrim?` trust point), while a non-ground operand still defers.
theorem eval_bound_rejects_non_ordered_operand :
    (evalBoundOp .gt (.prim .null) == .bottom) = true
      ∧ (evalBoundOp .lt (.prim (.bool true)) == .bottom) = true := by
  native_decide

-- COVERAGE TRIPWIRE (test-health). Anchors the last theorem of each section;
-- a swallowed section makes its anchor an unknown identifier and fails `#check`
-- elaboration.
#check @meet_decimal_bound_trailing_zero_tie
#check @meet_numeric_bound_unchanged
#check @eval_bound_rejects_non_ordered_operand

end Kue
