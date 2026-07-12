import Kue.Eval
import Kue.Format
import Kue.Manifest
import Kue.Resolve
import Kue.Runtime
import Kue.Tests.EvalTestHelpers

namespace Kue

-- Float `*` threads the apd `(coefficient, exponent)` form (F4): coefficients multiply,
-- exponents ADD, matching cue's rendered GDA form. Scales add and the summed scale is
-- preserved verbatim: `1.5 * 2.0 = 3.00`, no trailing-zero trim. Assertions pin the RENDERED
-- output (`formatValue`), the observable behavior — the internal carrier `text` is an apd
-- anchor, not the display form. All oracle-confirmed against cue v0.16.1.
theorem eval_mul_two_floats :
    formatValue (evalMul (.prim (mkFloatText "1.5")) (.prim (mkFloatText "2.0"))) = "3.00" := by
  native_decide

-- Multiplication into a large-magnitude result renders in scientific form (positive exponent),
-- NOT the fully-expanded `600.0`: `2e2 * 3 = 6e+2`, `1.5e2 * 1e2 = 1.5e+4`, `1e2 * 1e2 = 1e+4`.
theorem eval_mul_scientific :
    formatValue (evalMul (.prim (mkFloatText "2e2")) (.prim (.int 3))) = "6e+2"
      ∧ formatValue (evalMul (.prim (mkFloatText "1.5e2")) (.prim (mkFloatText "1e2"))) = "1.5e+4"
      ∧ formatValue (evalMul (.prim (mkFloatText "1e2")) (.prim (mkFloatText "1e2"))) = "1e+4"
      ∧ formatValue (evalMul (.prim (.int 10)) (.prim (mkFloatText "1e2"))) = "1.0e+3" := by
  native_decide

-- Was a deferred-bottom pin; float÷float now evaluates through the decimal layer.
-- `/` always yields a float; `3.0 / 2.0 = 1.5` terminates cleanly (oracle-confirmed,
-- cue v0.16.1).
theorem eval_div_two_floats :
    formatValue (evalDiv (.prim (mkFloatText "3.0")) (.prim (mkFloatText "2.0"))) = "1.5" := by
  native_decide

-- Multiplication preserves the full summed scale: `1.0 * 1.0 = 1.00`.
theorem eval_mul_scale_preserved :
    formatValue (evalMul (.prim (mkFloatText "1.0")) (.prim (mkFloatText "1.0"))) = "1.00" := by
  native_decide

-- Mixed int×float promotes to float; int contributes scale 0.
theorem eval_mul_int_float :
    formatValue (evalMul (.prim (.int 2)) (.prim (mkFloatText "1.5"))) = "3.0" := by
  native_decide

-- float×int likewise.
theorem eval_mul_float_int :
    formatValue (evalMul (.prim (mkFloatText "1.5")) (.prim (.int 2))) = "3.0" := by
  native_decide

-- Negative operand carries through multiplication.
theorem eval_mul_negative :
    formatValue (evalMul (.prim (mkFloatText "-1.5")) (.prim (mkFloatText "2.0"))) = "-3.00" := by
  native_decide

-- int×int stays int (no float promotion).
theorem eval_mul_int_int :
    evalMul (.prim (.int 3)) (.prim (.int 4)) = .prim (.int 12) := by
  rfl

-- Float `+`/`-` thread the apd form (F4): the result exponent is `min(e₁,e₂)`, fixing the
-- rendered GDA form. A large-magnitude result renders scientific (`1e1 + 1e1 = 2e+1`,
-- `1.5e2 + 1e2 = 2.5e+2`, `1.5e3 - 1e3 = 5e+2`); a zero result KEEPS the min exponent
-- (`1e1 - 1e1 = 0e+1`); a small-magnitude result stays plain (`1e3 + 2 = 1002.0`).
theorem eval_add_sub_scientific :
    formatValue (evalAdd (.prim (mkFloatText "1e1")) (.prim (mkFloatText "1e1"))) = "2e+1"
      ∧ formatValue (evalAdd (.prim (mkFloatText "1.5e2")) (.prim (mkFloatText "1e2"))) = "2.5e+2"
      ∧ formatValue (evalSub (.prim (mkFloatText "1.5e3")) (.prim (mkFloatText "1e3"))) = "5e+2"
      ∧ formatValue (evalSub (.prim (mkFloatText "1e1")) (.prim (mkFloatText "1e1"))) = "0e+1"
      ∧ formatValue (evalAdd (.prim (mkFloatText "1e3")) (.prim (.int 2))) = "1002.0" := by
  native_decide

-- Trailing zeros survive via the min-exponent coefficient magnitude (no trim): `1.20 + 1.30
-- = 2.50`, `1.50 + 1.50 = 3.00`. A whole exponent-0 result renders `.0` in cue-native but bare
-- in JSON (`1.25e3 + 1 = 1251` under export) — pinned by the wild fixture.
theorem eval_add_trailing_zeros :
    formatValue (evalAdd (.prim (mkFloatText "1.20")) (.prim (mkFloatText "1.30"))) = "2.50"
      ∧ formatValue (evalAdd (.prim (mkFloatText "1.50")) (.prim (mkFloatText "1.50"))) = "3.00"
      ∧ formatValue (evalAdd (.prim (mkFloatText "1.25e3")) (.prim (.int 1))) = "1251.0" := by
  native_decide

-- Beyond the 34-digit apd context precision the exact sum rounds half-up and switches to
-- scientific: `1e33 + 1` stays exact (34 digits), `1e34 + 1` rounds to `1.000…000e+34`.
theorem eval_add_context_rounding :
    formatValue (evalAdd (.prim (mkFloatText "1e33")) (.prim (.int 1)))
        = "1000000000000000000000000000000001.0"
      ∧ formatValue (evalAdd (.prim (mkFloatText "1e34")) (.prim (.int 1)))
        = "1.000000000000000000000000000000000e+34"
      ∧ formatValue (evalAdd (.prim (mkFloatText "1e100")) (.prim (.int 1)))
        = "1.000000000000000000000000000000000e+100" := by
  native_decide

-- Exact-tie rounding is half-UP (ties away from zero), NOT half-even. `apdRoundToContext`'s
-- `2 * remainder >= divisor` rule rounds a dropped-part of exactly ½ up regardless of the kept
-- digit's parity. Guard: a 35-sig-digit float ending `…125` × 10³⁴ drops the trailing `5` on an
-- EXACT tie, and the kept 34th digit is `2` (EVEN) — half-up carries it to `3` (`…13`), whereas
-- half-even would keep the even `2` (`…12`). Pinned both signs (the rule is magnitude-symmetric via
-- `negative`); matches `cue` v0.16.1 (`1.000…013E+34`). Prior tie coverage was zero.
theorem eval_add_context_rounding_half_up_even_tie :
    formatValue (evalAdd (.prim (mkFloatText "1.0000000000000000000000000000000125e34")) (.prim (.int 0)))
        = "1.000000000000000000000000000000013e+34"
      ∧ formatValue (evalAdd (.prim (mkFloatText "-1.0000000000000000000000000000000125e34")) (.prim (.int 0)))
        = "-1.000000000000000000000000000000013e+34" := by
  native_decide

-- A terminating fractional quotient keeps its minimal form: `1.0 / 4.0 = 0.25`.
theorem eval_div_terminating :
    formatValue (evalDiv (.prim (mkFloatText "1.0")) (.prim (mkFloatText "4.0"))) = "0.25" := by
  native_decide

-- Clean division still yields a float, never an int: `4.0 / 2.0 = 2.0`.
theorem eval_div_clean_is_float :
    formatValue (evalDiv (.prim (mkFloatText "4.0")) (.prim (mkFloatText "2.0"))) = "2.0" := by
  native_decide

-- Mixed float÷int promotes; `3.0 / 2 = 1.5`.
theorem eval_div_float_int :
    formatValue (evalDiv (.prim (mkFloatText "3.0")) (.prim (.int 2))) = "1.5" := by
  native_decide

-- Mixed int÷float promotes; `2 / 4.0 = 0.5`.
theorem eval_div_int_float :
    formatValue (evalDiv (.prim (.int 2)) (.prim (mkFloatText "4.0"))) = "0.5" := by
  native_decide

-- Negative division carries the sign.
theorem eval_div_negative :
    formatValue (evalDiv (.prim (mkFloatText "-1.0")) (.prim (mkFloatText "4.0"))) = "-0.25" := by
  native_decide

-- Float division by zero is bottom with divisionByZero provenance.
theorem eval_div_float_by_zero :
    (evalDiv (.prim (mkFloatText "1.0")) (.prim (mkFloatText "0.0")) == .bottomWith [.divisionByZero]) = true := by
  native_decide

-- int÷int routes through the same decimal divider and yields a float: `6 / 2 = 3.0`.
theorem eval_div_int_int_is_float :
    formatValue (evalDiv (.prim (.int 6)) (.prim (.int 2))) = "3.0" := by
  native_decide

-- Division-result RENDER form (apd ideal exponent, F4-DIV) is pinned in `FloatTests`.

-- Repeating-decimal division renders at 34 significant digits, round-half-up.
-- `2.0 / 3.0 = 0.666…667` (34 sig digits). This is the apd-context subset that is
-- now reachable; see compat-assumptions for the rounding-tie boundary.
theorem eval_div_repeating :
    (evalDiv (.prim (mkFloatText "2.0")) (.prim (mkFloatText "3.0"))
      == .prim (mkFloatText "0.6666666666666666666666666666666667")) = true := by
  native_decide

-- Repeating division with an integer part rounds at 34 sig digits, not 34 frac
-- digits: `10.0 / 3.0 = 3.33…3` (33 frac digits). Pins the significant-digit rule
-- that the prior fixed-fraction int divider got wrong for quotients ≥ 1.
theorem eval_div_repeating_int_part :
    (evalDiv (.prim (mkFloatText "10.0")) (.prim (mkFloatText "3.0"))
      == .prim (mkFloatText "3.333333333333333333333333333333333")) = true := by
  native_decide

-- Rounding carries past 9s: `100.0 / 7.0 = 14.28…29`, last digit rounded up.
theorem eval_div_repeating_round_up :
    (evalDiv (.prim (mkFloatText "100.0")) (.prim (mkFloatText "7.0"))
      == .prim (mkFloatText "14.28571428571428571428571428571429")) = true := by
  native_decide

-- High-fuel pin: a full-34-significant-digit repeating quotient with no leading
-- zeros. `1.0 / 7.0 = 0.142857…429` emits the maximum significant digits plus the
-- guard, so the `divisionDigitsFuel` ceiling must not be exhausted before the
-- over-budget exit. Reduces under `native_decide` ⇒ the bound is sufficient.
theorem eval_div_repeating_full_sig :
    (evalDiv (.prim (mkFloatText "1.0")) (.prim (mkFloatText "7.0"))
      == .prim (mkFloatText "0.1428571428571428571428571428571429")) = true := by
  native_decide

-- High-fuel pin exercising the leading-zero slack in the fuel bound: `1.0 / 700.0
-- = 0.001428…429` has two leading fractional zeros (non-emitting iterations) on
-- top of the 34 significant digits, so it leans on the `+ <den digit count>` term
-- of `divisionDigitsFuel`.
theorem eval_div_repeating_leading_zeros :
    (evalDiv (.prim (mkFloatText "1.0")) (.prim (mkFloatText "700.0"))
      == .prim (mkFloatText "0.001428571428571428571428571428571429")) = true := by
  native_decide

-- E#4 — arithmetic operator domain. The CUE spec closes `+ - * /` over int/decimal, and
-- additionally `+`/`*` over strings and bytes. A CONCRETE operand outside an op's domain is a
-- TYPE ERROR (`nonArithmeticOperand`), the same class as `1 + "x"`; an INCOMPLETE operand keeps
-- the binary DEFERRED (`.binary`) since it may still resolve to a number. These pin the unit
-- behavior of `evalAdd`/`evalSub`/`evalMul`/`evalDiv` directly, independent of display.

-- A concrete list operand bottoms `+` (was a held residual; cue: superseded-by-list.Concat).
theorem eval_add_list_is_type_error :
    (evalAdd (.list [.prim (.int 1)]) (.list [.prim (.int 2)])
      == .bottomWith [.nonArithmeticOperand .add .list]) = true := by
  native_decide

-- `-` over a list operand bottoms (cue: `cannot use [..] as type number`).
theorem eval_sub_list_is_type_error :
    (evalSub (.list [.prim (.int 1)]) (.prim (.int 3))
      == .bottomWith [.nonArithmeticOperand .sub .list]) = true := by
  native_decide

-- `*` over a list operand bottoms in either order (cue: superseded-by-list.Repeat).
theorem eval_mul_list_is_type_error :
    (evalMul (.prim (.int 3)) (.list [.prim (.int 1), .prim (.int 2)])
      == .bottomWith [.nonArithmeticOperand .mul .list]) = true := by
  native_decide

-- `/` over a list operand bottoms.
theorem eval_div_list_is_type_error :
    (evalDiv (.list [.prim (.int 1)]) (.prim (.int 3))
      == .bottomWith [.nonArithmeticOperand .div .list]) = true := by
  native_decide

-- A concrete (no-pattern) struct operand bottoms `+` with the `.struct` operand type.
theorem eval_add_struct_is_type_error :
    (evalAdd (mkStruct [⟨"a", .regular, .prim (.int 1), false⟩] .regularOpen none [])
        (mkStruct [⟨"b", .regular, .prim (.int 2), false⟩] .regularOpen none [])
      == .bottomWith [.nonArithmeticOperand .add .struct]) = true := by
  native_decide

-- A `.listTail` (open list) is also a concrete non-arithmetic operand → type error.
theorem eval_add_list_tail_is_type_error :
    (evalAdd (.listTail [.prim (.int 1)] (.kind .int)) (.prim (.int 2))
      == .bottomWith [.nonArithmeticOperand .add .list]) = true := by
  native_decide

-- Per-op asymmetry: `+` over two strings is concat (NOT a type error).
theorem eval_add_strings_concats :
    evalAdd (.prim (.string "a")) (.prim (.string "b")) = .prim (.string "ab") := by
  rfl

-- Per-op asymmetry: `-` over strings IS a type error (string ∉ `-` domain). The wrong-typed
-- prim pair routes through the existing decimal path to a plain `.bottom` (cue errors too).
theorem eval_sub_strings_is_bottom :
    evalSub (.prim (.string "a")) (.prim (.string "b")) = .bottom := by
  rfl

-- `*` over (string, int) is REPETITION (cue, superseding strings.Repeat): `"ab" * 2 = "abab"`.
theorem eval_mul_string_int_repeats :
    evalMul (.prim (.string "ab")) (.prim (.int 2)) = .prim (.string "abab") := by
  rfl

-- Repetition is order-agnostic: `2 * "ab" = "abab"`.
theorem eval_mul_int_string_repeats :
    evalMul (.prim (.int 2)) (.prim (.string "ab")) = .prim (.string "abab") := by
  rfl

-- `*` over (bytes, int) repeats the bytes: `'ab' * 2 = 'abab'`.
theorem eval_mul_bytes_int_repeats :
    evalMul (.prim (.bytes (textBytes "ab"))) (.prim (.int 2)) = .prim (.bytes (textBytes "abab")) := by
  rfl

-- A zero count yields the empty value (not an error).
theorem eval_mul_string_zero_is_empty :
    evalMul (.prim (.string "ab")) (.prim (.int 0)) = .prim (.string "") := by
  rfl

-- A negative repetition count is a type error (cue: cannot convert negative number to uint64).
theorem eval_mul_string_negative_count_is_error :
    evalMul (.prim (.string "ab")) (.prim (.int (-1))) = .bottomWith [.negativeRepeatCount (-1)] := by
  rfl

-- CRITICAL regression pin: a concrete list paired with an INCOMPLETE operand (abstract `int`
-- kind) DEFERS — it does NOT bottom, because the kind may still resolve to a number (cue holds
-- `[1] + x` while `x: int`). The concrete-nonarith side alone must not force a type error.
theorem eval_add_list_incomplete_partner_defers :
    evalAdd (.list [.prim (.int 1)]) (.kind .int) = .binary .add (.list [.prim (.int 1)]) (.kind .int) := by
  rfl

-- Symmetric: incomplete LEFT × concrete list RIGHT also defers.
theorem eval_mul_incomplete_partner_list_defers :
    evalMul (.kind .int) (.list [.prim (.int 1)]) = .binary .mul (.kind .int) (.list [.prim (.int 1)]) := by
  rfl

-- A bound-constraint operand is incomplete → arithmetic defers (it may concretize to a number).
theorem eval_add_bound_operand_defers :
    evalAdd (.boundConstraint (.int 0 .number) .gt) (.prim (.int 1))
      = .binary .add (.boundConstraint (.int 0 .number) .gt) (.prim (.int 1)) := by
  rfl

-- An unresolved ref operand is incomplete → defers (the pre-fix baseline, must stay).
theorem eval_add_ref_operand_defers :
    evalAdd (.refId ⟨0, 0⟩) (.prim (.int 1)) = .binary .add (.refId ⟨0, 0⟩) (.prim (.int 1)) := by
  rfl

-- ### Comparison / boolean / unary scalar-op pins (EvalOps)
--
-- Direct unit pins for `evalEq`/`evalNe`, the ordering ops (`evalPrimitiveOrdering` via
-- `evalBinary .lt/.le/.gt/.ge`), the boolean ops, and unary negation/not — the carve-set
-- functions that previously had only end-to-end fixture coverage. They fix the edge
-- behavior (incomparable-kind comparison, bool ordering, unary on non-numeric) at the
-- function level, independent of display.

-- `<` over two ints decides numerically.
theorem eval_lt_int_true :
    (evalBinary .lt (.prim (.int 1)) (.prim (.int 2)) == .prim (.bool true)) = true := by
  native_decide

-- `<` is lexicographic over strings.
theorem eval_lt_string_true :
    (evalBinary .lt (.prim (.string "a")) (.prim (.string "b")) == .prim (.bool true)) = true := by
  native_decide

-- `<=` is reflexive at equality.
theorem eval_le_int_equal_true :
    (evalBinary .le (.prim (.int 2)) (.prim (.int 2)) == .prim (.bool true)) = true := by
  native_decide

-- `>` over ints decides numerically.
theorem eval_gt_int_true :
    (evalBinary .gt (.prim (.int 5)) (.prim (.int 2)) == .prim (.bool true)) = true := by
  native_decide

-- `>=` over ints decides numerically.
theorem eval_ge_int_true :
    (evalBinary .ge (.prim (.int 5)) (.prim (.int 5)) == .prim (.bool true)) = true := by
  native_decide

-- Comparison over INCOMPARABLE kinds (int vs string) bottoms — cue: `invalid operands …
-- to '<'`. `primOrdCompare?` returns `none` for a cross-family pair ⇒ `.bottom`.
theorem eval_lt_incomparable_kinds_is_bottom :
    (evalBinary .lt (.prim (.int 1)) (.prim (.string "a")) == .bottom) = true := by
  native_decide

-- `bool` is NOT ordered: `true < false` bottoms (cue: `invalid operands … (type bool and bool)`).
theorem eval_lt_bool_unordered_is_bottom :
    (evalBinary .lt (.prim (.bool true)) (.prim (.bool false)) == .bottom) = true := by
  native_decide

-- An incomplete operand keeps an ordering comparison DEFERRED (residual `.binary`).
theorem eval_lt_incomplete_defers :
    (evalBinary .lt (.kind .int) (.prim (.int 2))
      == .binary .lt (.kind .int) (.prim (.int 2))) = true := by
  native_decide

-- BINARY-CMP-OPERAND. An ordered comparison (`< <= > >=`) requires BOTH operands to be
-- ordered scalars. A GROUND non-scalar (list/struct) meeting a ground/comparable operand
-- is a type error → ⊥, NOT a fabricated `.binary` residual — cue: `invalid operands …
-- (type int and list)`. The `.nonScalar` arm of `evalPrimitiveOrdering` replaces the
-- former retain-everything catch-all. Both operand positions + both list/struct shapes.

theorem eval_lt_list_operand_right_bottoms :
    (evalBinary .lt (.prim (.int 1)) (.list [.prim (.int 1), .prim (.int 2)])
      == .bottom) = true := by
  native_decide

theorem eval_gt_struct_operand_left_bottoms :
    (evalBinary .gt (.struct [⟨"a", .regular, .prim (.int 1), false⟩] .regularOpen none [] [])
        (.prim (.int 3))
      == .bottom) = true := by
  native_decide

theorem eval_le_both_nonscalar_bottoms :
    (evalBinary .le (.list [.prim (.int 1)]) (.list [.prim (.int 2)]) == .bottom) = true := by
  native_decide

-- BOTH-DIRECTION RETAIN GUARDS. `.incomplete` on EITHER side wins over `.nonScalar` — a
-- ground list compared against a genuinely-abstract operand still RETAINS (the abstract
-- side may refine to a comparable scalar), matching cue (`[1,2] < a`, a abstract, is kept).
-- Proves the fix bottoms only when BOTH sides are decided, never an abstract operand.

theorem eval_lt_nonscalar_vs_incomplete_retains :
    (evalBinary .lt (.list [.prim (.int 1), .prim (.int 2)]) (.kind .int)
      == .binary .lt (.list [.prim (.int 1), .prim (.int 2)]) (.kind .int)) = true := by
  native_decide

theorem eval_lt_incomplete_vs_nonscalar_retains :
    (evalBinary .lt (.kind .int) (.list [.prim (.int 1), .prim (.int 2)])
      == .binary .lt (.kind .int) (.list [.prim (.int 1), .prim (.int 2)])) = true := by
  native_decide

-- EQUALITY is TOTAL across types (never ⊥, never retain for ground operands): cross-type
-- `==` is `false`, `!=` is `true` — cue: `1 == [1,2]` ⇒ `false`, `1 != [1,2]` ⇒ `true`.
-- Pins that the ordered-comparison ⊥ fix does NOT leak into `==`/`!=`.

theorem eval_eq_int_vs_list_false :
    (evalEq (.prim (.int 1)) (.list [.prim (.int 1), .prim (.int 2)]) == .prim (.bool false))
      = true := by
  native_decide

theorem eval_ne_int_vs_list_true :
    (evalNe (.prim (.int 1)) (.list [.prim (.int 1), .prim (.int 2)]) == .prim (.bool true))
      = true := by
  native_decide

-- `==` over distinct ints is `false`.
theorem eval_eq_int_distinct_false :
    (evalEq (.prim (.int 1)) (.prim (.int 2)) == .prim (.bool false)) = true := by
  native_decide

-- `!=` is the negation of `==`.
theorem eval_ne_int_distinct_true :
    (evalNe (.prim (.int 1)) (.prim (.int 2)) == .prim (.bool true)) = true := by
  native_decide

-- AUDIT (EvalOps gap): `==` across DISTINCT KINDS (`1 == "1"`) is `false`, NOT bottom — cue
-- treats `==`/`!=` as total over concrete prims (it falls through `evalDecimalCompare?` to the
-- structural `left == right`, which differs across kinds). Oracle: cue `1 == "1"` ⇒ `false`.
theorem eval_eq_cross_kind_int_string_false :
    (evalEq (.prim (.int 1)) (.prim (.string "1")) == .prim (.bool false)) = true := by
  native_decide

-- AUDIT (EvalOps gap): `!=` across distinct kinds is `true` (the `==` complement).
theorem eval_ne_cross_kind_int_string_true :
    (evalNe (.prim (.int 1)) (.prim (.string "1")) == .prim (.bool true)) = true := by
  native_decide

-- AUDIT (EvalOps gap): string `<=` reads `Ordering.isLE` off `primOrdCompare?`
-- (`"b" <= "a"` ⇒ `false`, ordering `.gt`). Oracle: cue `"b" <= "a"` ⇒ `false`.
theorem eval_le_string_reverse_false :
    (evalBinary .le (.prim (.string "b")) (.prim (.string "a")) == .prim (.bool false)) = true := by
  native_decide

-- AUDIT (EvalOps gap): string `>=` reads `Ordering.isGE` off `primOrdCompare?`
-- (`"b" >= "a"` ⇒ `true`, ordering `.gt`). Oracle: cue `"b" >= "a"` ⇒ `true`.
theorem eval_ge_string_reverse_true :
    (evalBinary .ge (.prim (.string "b")) (.prim (.string "a")) == .prim (.bool true)) = true := by
  native_decide

-- AUDIT (EvalOps gap): string `<=` is reflexive at equality (`"a" <= "a"` ⇒ `true`) —
-- `primOrdCompare?` reports `.eq` and `Ordering.isLE .eq = true`.
theorem eval_le_string_reflexive_true :
    (evalBinary .le (.prim (.string "a")) (.prim (.string "a")) == .prim (.bool true)) = true := by
  native_decide

-- BINARY-CMP-BYTES. Bytes are an ORDERED type — `< <= > >=` compare bytes lexically by
-- byte value (cue v0.16.1: `'a' < 'b'` ⇒ `true`). kue previously bottomed every bytes
-- ordered comparison; `evalPrimitiveOrdering` now routes bytes through `primOrdCompare?`.
-- Covers both directions, `<=`/`>=` inclusive, byte-value order, multi-byte lexical, and
-- empty-vs-nonempty.

theorem eval_lt_bytes_true :
    (evalBinary .lt (.prim (.bytes #[0x61])) (.prim (.bytes #[0x62])) == .prim (.bool true)) = true := by
  native_decide

theorem eval_lt_bytes_reverse_false :
    (evalBinary .lt (.prim (.bytes #[0x62])) (.prim (.bytes #[0x61])) == .prim (.bool false)) = true := by
  native_decide

theorem eval_le_bytes_equal_true :
    (evalBinary .le (.prim (.bytes #[0x61])) (.prim (.bytes #[0x61])) == .prim (.bool true)) = true := by
  native_decide

theorem eval_ge_bytes_equal_true :
    (evalBinary .ge (.prim (.bytes #[0x61])) (.prim (.bytes #[0x61])) == .prim (.bool true)) = true := by
  native_decide

theorem eval_gt_bytes_true :
    (evalBinary .gt (.prim (.bytes #[0x62])) (.prim (.bytes #[0x61])) == .prim (.bool true)) = true := by
  native_decide

theorem eval_ge_bytes_false :
    (evalBinary .ge (.prim (.bytes #[0x61])) (.prim (.bytes #[0x62])) == .prim (.bool false)) = true := by
  native_decide

-- Byte VALUE order (not code-point): `\x01 < \x02`.
theorem eval_lt_bytes_byte_value_true :
    (evalBinary .lt (.prim (.bytes #[0x01])) (.prim (.bytes #[0x02])) == .prim (.bool true)) = true := by
  native_decide

-- Multi-byte LEXICAL: `'ab' < 'ac'` differs at the second byte.
theorem eval_lt_bytes_lexical_true :
    (evalBinary .lt (.prim (.bytes #[0x61, 0x62])) (.prim (.bytes #[0x61, 0x63]))
      == .prim (.bool true)) = true := by
  native_decide

-- Empty bytes is the least: `'' < 'a'`.
theorem eval_lt_bytes_empty_true :
    (evalBinary .lt (.prim (.bytes #[])) (.prim (.bytes #[0x61])) == .prim (.bool true)) = true := by
  native_decide

-- Prefix ordering: `'ab' > 'a'` (a proper extension is greater).
theorem eval_gt_bytes_prefix_true :
    (evalBinary .gt (.prim (.bytes #[0x61, 0x62])) (.prim (.bytes #[0x61])) == .prim (.bool true)) = true := by
  native_decide

-- CROSS-TYPE GUARD. Bytes ordered comparison stays WITHIN the bytes family. A bytes×string
-- or bytes×number pair is incomparable — `primOrdCompare?` returns `none` ⇒ ⊥ (cue:
-- `invalid operands … (type bytes and string/int)`). Both directions pin the guard.

theorem eval_lt_bytes_vs_string_bottoms :
    (evalBinary .lt (.prim (.bytes #[0x61])) (.prim (.string "a")) == .bottom) = true := by
  native_decide

theorem eval_lt_string_vs_bytes_bottoms :
    (evalBinary .lt (.prim (.string "a")) (.prim (.bytes #[0x61])) == .bottom) = true := by
  native_decide

theorem eval_lt_bytes_vs_int_bottoms :
    (evalBinary .lt (.prim (.bytes #[0x61])) (.prim (.int 1)) == .bottom) = true := by
  native_decide

theorem eval_gt_int_vs_bytes_bottoms :
    (evalBinary .gt (.prim (.int 1)) (.prim (.bytes #[0x61])) == .bottom) = true := by
  native_decide

-- Bytes EQUALITY is unaffected by the ordered-comparison change (routes through `evalEq`,
-- total across types): `'a' == 'a'` ⇒ `true`, `'a' == 'b'` ⇒ `false`.
theorem eval_eq_bytes_true :
    (evalEq (.prim (.bytes #[0x61])) (.prim (.bytes #[0x61])) == .prim (.bool true)) = true := by
  native_decide

theorem eval_eq_bytes_distinct_false :
    (evalEq (.prim (.bytes #[0x61])) (.prim (.bytes #[0x62])) == .prim (.bool false)) = true := by
  native_decide

-- `&&` over bools decides directly.
theorem eval_bool_and :
    (evalBinary .boolAnd (.prim (.bool true)) (.prim (.bool false)) == .prim (.bool false)) = true := by
  native_decide

-- `||` over bools decides directly.
theorem eval_bool_or :
    (evalBinary .boolOr (.prim (.bool false)) (.prim (.bool true)) == .prim (.bool true)) = true := by
  native_decide

-- `&&` over a NON-bool prim bottoms (cue: `cannot use … as bool`).
theorem eval_bool_and_non_bool_is_bottom :
    (evalBinary .boolAnd (.prim (.int 1)) (.prim (.bool true)) == .bottom) = true := by
  native_decide

-- Unary `!` negates a bool.
theorem eval_unary_not_bool :
    (evalUnary .boolNot (.prim (.bool true)) == .prim (.bool false)) = true := by
  native_decide

-- Unary `!` on a non-bool bottoms (cue: `invalid operation !3`).
theorem eval_unary_not_non_bool_is_bottom :
    (evalUnary .boolNot (.prim (.int 3)) == .bottom) = true := by
  native_decide

-- Unary `-` negates an int.
theorem eval_unary_neg_int :
    (evalUnary .numNeg (.prim (.int 5)) == .prim (.int (-5))) = true := by
  native_decide

-- Unary `-` on a non-numeric operand bottoms (cue: `invalid operation -"a"`).
theorem eval_unary_neg_non_numeric_is_bottom :
    (evalUnary .numNeg (.prim (.string "x")) == .bottom) = true := by
  native_decide

-- Unary `-` on an incomplete operand keeps the unary DEFERRED (residual `.unary`).
theorem eval_unary_neg_incomplete_defers :
    (evalUnary .numNeg (.kind .int) == .unary .numNeg (.kind .int)) = true := by
  native_decide

-- AUD-B3 residual-preservation guards. The `evalBoolBinary`/`evalBoolNot`/`evalNumPos`/
-- `evalNumNeg` (+ `evalPrimitiveOrdering`/`evalRegexMatch`) catch-alls were replaced with an
-- ENUMERATED `classifyScalarOperand` dispatch; these pins fix EXACTLY which constructors keep
-- producing the residual `.binary`/`.unary` so the enumeration cannot silently reroute one.

-- `&&` with an abstract operand DEFERS (residual `.binary`), it does not bottom.
theorem eval_bool_and_incomplete_defers :
    (evalBinary .boolAnd (.kind .bool) (.prim (.bool true))
      == .binary .boolAnd (.kind .bool) (.prim (.bool true))) = true := by
  native_decide

-- A `.ref` operand (a distinct abstract ctor) also defers — the enumeration routes every
-- non-prim/non-bottom shape to the residual, not just `.kind`.
theorem eval_bool_or_ref_defers :
    (evalBinary .boolOr (.ref "x") (.prim (.bool false))
      == .binary .boolOr (.ref "x") (.prim (.bool false))) = true := by
  native_decide

-- A `.bottom` operand BEATS a residual partner: `⊥ && <abstract>` is `⊥`, not deferred.
theorem eval_bool_and_bottom_beats_residual :
    (evalBinary .boolAnd .bottom (.kind .bool) == .bottom) = true := by
  native_decide

-- A `.bottomWith` on the RIGHT (with an abstract left) propagates its reasons, not a residual.
theorem eval_bool_and_right_bottomwith_propagates :
    (evalBinary .boolAnd (.kind .bool) (.bottomWith [.divisionByZero])
      == .bottomWith [.divisionByZero]) = true := by
  native_decide

-- Unary `!` on an abstract operand keeps the unary DEFERRED (residual `.unary`).
theorem eval_unary_not_incomplete_defers :
    (evalUnary .boolNot (.kind .bool) == .unary .boolNot (.kind .bool)) = true := by
  native_decide

-- Unary `+` is identity on int and float, bottoms a non-numeric prim, and defers an abstract.
theorem eval_unary_pos_int :
    (evalUnary .numPos (.prim (.int 5)) == .prim (.int 5)) = true := by
  native_decide

theorem eval_unary_pos_float :
    (evalUnary .numPos (.prim (mkFloatText "1.5")) == .prim (mkFloatText "1.5")) = true := by
  native_decide

theorem eval_unary_pos_non_numeric_is_bottom :
    (evalUnary .numPos (.prim (.string "x")) == .bottom) = true := by
  native_decide

theorem eval_unary_pos_incomplete_defers :
    (evalUnary .numPos (.kind .int) == .unary .numPos (.kind .int)) = true := by
  native_decide

-- Unary `-` negates a float via `negateFloatText`.
theorem eval_unary_neg_float :
    (evalUnary .numNeg (.prim (mkFloatText "1.5")) == .prim (mkFloatText "-1.5")) = true := by
  native_decide

-- Regex match on an abstract operand DEFERS (residual `.binary`), it does not bottom.
theorem eval_regex_match_incomplete_defers :
    (evalBinary .regexMatch (.kind .string) (.prim (.string "^a"))
      == .binary .regexMatch (.kind .string) (.prim (.string "^a"))) = true := by
  native_decide

-- Regex match over two NON-string prims bottoms (both concrete, wrong type).
theorem eval_regex_match_non_string_is_bottom :
    (evalBinary .regexMatch (.prim (.int 1)) (.prim (.int 2)) == .bottom) = true := by
  native_decide

-- ### Deferred relational-operator lowering (PATTERN-BOUND-OPERAND facet 2)
--
-- A comparator/`!=`/`=~` whose operand was NOT a literal parses to a `.unary` node; once the
-- operand evaluates to a ground value, `evalUnary` lowers it to the concrete validator. These
-- pin the lowering directly (the wild fixtures pin it end-to-end through a reference).

-- `>k` with `k` resolved to a string lowers to a string bound constraint.
theorem eval_bound_op_lowers_string_operand :
    (evalUnary (.boundOp .gt) (.prim (.string "m")) == .boundConstraint (.string "m") .gt) = true := by
  native_decide

-- `<k` with `k` resolved to a number lowers to a numeric bound constraint.
theorem eval_bound_op_lowers_numeric_operand :
    (evalUnary (.boundOp .lt) (.prim (.int 5)) == .boundConstraint (.int 5 .number) .lt) = true := by
  native_decide

-- `!=z` with `z` resolved to a prim lowers to a `notPrim` validator.
theorem eval_ne_op_lowers_operand :
    (evalUnary .neOp (.prim (.string "a")) == .notPrim (.string "a")) = true := by
  native_decide

-- `=~re` with `re` resolved to a string lowers to a `stringRegex` validator.
theorem eval_regex_op_lowers_string_operand :
    (evalUnary .regexMatchOp (.prim (.string "^a")) == .stringRegex "^a") = true := by
  native_decide

-- An UNRESOLVED operand keeps the deferred `.unary` node (incomplete, not lowered).
theorem eval_bound_op_defers_unresolved_operand :
    (evalUnary (.boundOp .lt) (.refId ⟨0, 0⟩) == .unary (.boundOp .lt) (.refId ⟨0, 0⟩)) = true := by
  native_decide

-- A NON-ORDERED operand (`>true`) is an invalid bound operand → ⊥.
theorem eval_bound_op_non_ordered_operand_bottoms :
    (evalUnary (.boundOp .gt) (.prim (.bool true)) == .bottom) = true := by
  native_decide

-- `=~` over a non-string operand is invalid → ⊥.
theorem eval_regex_op_non_string_operand_bottoms :
    (evalUnary .regexMatchOp (.prim (.int 1)) == .bottom) = true := by
  native_decide

-- NON-SCALAR OPERANDS (BOUND-OPERAND-CLASSIFY). A ground list/struct can never refine
-- into an ordered scalar, so the four ordering/bound/regex/unary-arith ops that demand
-- one REJECT it (⊥) rather than fabricate a residual `.unary`. Closes the coverage gap
-- where `eval_bound_op_non_ordered_operand_bottoms` above tested only `.bool`.

theorem eval_bound_op_list_operand_bottoms :
    (evalUnary (.boundOp .lt) (.list [.prim (.int 1), .prim (.int 2)]) == .bottom) = true := by
  native_decide

theorem eval_bound_op_struct_operand_bottoms :
    (evalUnary (.boundOp .lt) (.struct [⟨"a", .regular, .prim (.int 1), false⟩] .regularOpen none [] [])
      == .bottom) = true := by
  native_decide

theorem eval_bound_op_embedded_list_operand_bottoms :
    (evalUnary (.boundOp .gt) (.embeddedList [.prim (.int 1)] none []) == .bottom) = true := by
  native_decide

theorem eval_regex_op_list_operand_bottoms :
    (evalUnary .regexMatchOp (.list [.prim (.int 1)]) == .bottom) = true := by
  native_decide

theorem eval_regex_op_struct_operand_bottoms :
    (evalUnary .regexMatchOp (.struct [] .regularOpen none [] []) == .bottom) = true := by
  native_decide

theorem eval_num_pos_list_operand_bottoms :
    (evalUnary .numPos (.list [.prim (.int 1), .prim (.int 2)]) == .bottom) = true := by
  native_decide

theorem eval_num_pos_struct_operand_bottoms :
    (evalUnary .numPos (.struct [] .regularOpen none [] []) == .bottom) = true := by
  native_decide

theorem eval_num_neg_list_operand_bottoms :
    (evalUnary .numNeg (.list [.prim (.int 1), .prim (.int 2)]) == .bottom) = true := by
  native_decide

theorem eval_num_neg_struct_operand_bottoms :
    (evalUnary .numNeg (.struct [] .regularOpen none [] []) == .bottom) = true := by
  native_decide

-- BOTH-DIRECTION RETAIN GUARDS. The split must NOT over-reach: `!=` never rejects a
-- non-scalar (its `.nonScalar` arm is identical to `.incomplete`), and a genuinely
-- INCOMPLETE operand — top / unresolved disjunction / bound operand — stays a residual
-- `.unary`, NOT ⊥. These prove `.nonScalar`/`.incomplete` split correctness both ways.

-- `!=[1,2]` and `!={}` RETAIN the residual — neOp never rejects a non-scalar operand.
theorem eval_ne_op_list_operand_retains :
    (evalUnary .neOp (.list [.prim (.int 1), .prim (.int 2)])
      == .unary .neOp (.list [.prim (.int 1), .prim (.int 2)])) = true := by
  native_decide

theorem eval_ne_op_struct_operand_retains :
    (evalUnary .neOp (.struct [] .regularOpen none [] [])
      == .unary .neOp (.struct [] .regularOpen none [] [])) = true := by
  native_decide

-- `<_` (top operand) RETAINS — top is genuinely incomplete, may refine to a scalar.
theorem eval_bound_op_top_operand_retains :
    (evalUnary (.boundOp .lt) .top == .unary (.boundOp .lt) .top) = true := by
  native_decide

-- `<(1|2)` (unresolved disjunction operand) RETAINS — incomplete, may refine to a scalar.
theorem eval_bound_op_disj_operand_retains :
    (evalUnary (.boundOp .lt) (.disj [(.regular, .prim (.int 1)), (.regular, .prim (.int 2))])
      == .unary (.boundOp .lt) (.disj [(.regular, .prim (.int 1)), (.regular, .prim (.int 2))])) = true := by
  native_decide

-- COVERAGE TRIPWIRE (test-health). Anchors the LAST theorem of every section; a swallowed
-- section turns its anchor into an unknown identifier and `#check` fails to elaborate.
#check @eval_div_repeating_leading_zeros                     -- float mul/div/add-sub
#check @eval_add_ref_operand_defers                          -- arithmetic operator domain
#check @eval_regex_match_non_string_is_bottom                -- comparison / boolean / unary op pins
#check @eval_bound_op_disj_operand_retains                   -- deferred relational-operator lowering

end Kue
