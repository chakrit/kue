import Kue.Format
import Kue.Lattice
import Kue.Order

namespace Kue

theorem format_float_kind_and_primitive :
    formatValue (.kind .float) = "float" ∧ formatValue (.prim (mkFloatText "1.5")) = "1.5" := by
  native_decide

theorem meet_float_kind_with_float_primitive :
    meet (.kind .float) (.prim (mkFloatText "1.5")) = .prim (mkFloatText "1.5") := by
  rfl

theorem meet_int_kind_with_float_primitive_bottoms :
    meet (.kind .int) (.prim (mkFloatText "1.5")) = .bottomWith [.kindConflict .int .float] := by
  rfl

theorem float_kind_subsumes_float_primitive :
    subsumes (.kind .float) (.prim (mkFloatText "1.5")) = true := by
  native_decide

theorem int_kind_rejects_float_primitive :
    subsumes (.kind .int) (.prim (mkFloatText "1.5")) = false := by
  native_decide


-- ── PRIM-FLOAT-PARSED (0e): the smart-constructed decimal representation ──
-- `mkFloatText` stores the exact base-10 value ALONGSIDE the verbatim source text.
-- These pin: (a) the stored decimal is correct and read WITHOUT re-parsing, (b) the
-- retained text round-trips rendering verbatim, and (c) derived `BEq` still reduces to
-- text-equality (the invariant that keeps fixtures/canary byte-stable across the change).

-- The stored decimal is the exact base-10 value of the source text, read directly
-- (no hot-path re-parse) — total for every float, so `decimalFromPrim?` never `none`s.
theorem float_stores_exact_decimal :
    decimalFromPrim? (mkFloatText "1.5") = some { numerator := 15, scale := 1 }
      ∧ decimalFromPrim? (mkFloatText "-2.5") = some { numerator := -25, scale := 1 }
      ∧ decimalFromPrim? (mkFloatText "1e+3") = some { numerator := 1000, scale := 0 }
      ∧ decimalFromPrim? (mkFloatText "1e-6") = some { numerator := 1, scale := 6 } := by
  native_decide

-- `1.0 & 1.00` unify by VALUE off the stored decimals — no `parseDecimalText` and no
-- `leftText == rightText` fallback branch (the illegal state 0e erased).
theorem float_unify_equal_by_stored_value :
    primsUnifyEqual (mkFloatText "1.0") (mkFloatText "1.00") = true
      ∧ primsUnifyEqual (mkFloatText "1.50") (mkFloatText "1.5") = true := by
  native_decide

-- The retained source text renders VERBATIM: trailing zeros and scientific-notation
-- exponents survive (GDA-FLOAT-RENDER's round-trip concern), so export is byte-stable.
theorem float_text_round_trips_verbatim :
    formatValue (.prim (mkFloatText "1.50")) = "1.50"
      ∧ formatValue (.prim (mkFloatText "1e+3")) = "1e+3"
      ∧ formatValue (.prim (mkFloatText "-2e+3")) = "-2e+3"
      ∧ formatValue (.prim (mkFloatText "0.000001")) = "0.000001" := by
  native_decide

-- Derived `BEq` on `Prim.float` still reduces to text-equality: distinct source texts
-- (even value-equal `1.0`/`1.00`) are structurally UNEQUAL, equal texts equal. This is
-- the load-bearing invariant — `value := parseDecimalText text` is a function of `text`,
-- so the decimal field cannot perturb any `Value` equality that text-equality decides.
theorem float_beq_reduces_to_text_equality :
    ((.prim (mkFloatText "1.0") : Value) == .prim (mkFloatText "1.00")) = false
      ∧ ((.prim (mkFloatText "1.5") : Value) == .prim (mkFloatText "1.5")) = true := by
  native_decide

-- Float behavior pinned: a `>=1.5` bound admits `1.5` (inclusive) and a `>1.5` bound
-- rejects it (strict) — the bound/decimal edge surface 0e's core-type change threads through.
theorem float_pinned_across_contexts :
    meet (.boundConstraint { numerator := 15, scale := 1 } .ge .number) (.prim (mkFloatText "1.5"))
        = .prim (mkFloatText "1.5")
      ∧ meet (.boundConstraint { numerator := 15, scale := 1 } .gt .number) (.prim (mkFloatText "1.5"))
        = .bottomWith [.boundConflict] := by
  exact ⟨rfl, rfl⟩


-- COVERAGE TRIPWIRE (test-health). Anchors the last theorem of each section;
-- a swallowed section makes its anchor an unknown identifier and fails `#check`
-- elaboration.
#check @int_kind_rejects_float_primitive
#check @float_pinned_across_contexts

end Kue
