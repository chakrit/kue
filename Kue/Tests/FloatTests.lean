import Kue.Format
import Kue.Lattice
import Kue.Order
import Kue.EvalOps

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
-- `mkFloatText` stores the exact base-10 value ALONGSIDE the source text.
-- These pin: (a) the stored decimal is correct and read WITHOUT re-parsing, (b) the
-- retained text is the render anchor (GDA-FLOAT-RENDER derives canonical output from its apd
-- form; superseded: rendering is representation-preserving, NOT byte-verbatim), and (c)
-- derived `BEq` still reduces to text-equality (the invariant that keeps `BEq` text-stable).

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

-- The retained text is the render anchor: representation-preserving cases (trailing zeros,
-- already-canonical scientific/plain forms) render unchanged under cue-native GDA.
theorem float_render_preserves_representation :
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


-- ── GDA-FLOAT-RENDER: canonical decimal output via `to-scientific-string` ──
-- Rendering derives the apd `(coefficient, exponent)` form from the retained `text` (the
-- normalized `DecimalValue` can't — it collapses `1e2`/`1.00e2` and expands `1e40`), then
-- applies CUE's General-Decimal-Arithmetic rule per output style. Every row is
-- spec-adjudicated against `cue` v0.16.1.

-- apd extraction is representation-faithful: `1e2` keeps a positive exponent (coefficient 1),
-- `1.00e2` collapses to coefficient 100 exponent 0 (they are DISTINCT apd forms though equal
-- in value), `1.50` preserves the trailing zero as magnitude, `-0.0` normalizes its sign.
theorem float_apd_form_faithful :
    floatApdForm "1e+2" = (false, 1, 2)
      ∧ floatApdForm "1.00e+2" = (false, 100, 0)
      ∧ floatApdForm "1.50" = (false, 150, -2)
      ∧ floatApdForm "12345e-2" = (false, 12345, -2)
      ∧ floatApdForm "-2e+3" = (true, 2, 3)
      ∧ floatApdForm "-0.0" = (false, 0, -1) := by
  native_decide

-- JSON style: uppercase `E`, whole floats bare. Pins the full matrix + edges: small-exponent
-- expansion, `1e-6`/`1e-7` plain/scientific boundary, large-magnitude scientific, the
-- `1e2`≠`1.00e2` collapse, negative, high precision, negative-zero normalization.
theorem float_render_json :
    renderFloatText jsonFloatStyle "1.50" = "1.50"
      ∧ renderFloatText jsonFloatStyle "1e+2" = "1E+2"
      ∧ renderFloatText jsonFloatStyle "1e-2" = "0.01"
      ∧ renderFloatText jsonFloatStyle "12345e-2" = "123.45"
      ∧ renderFloatText jsonFloatStyle "1e+40" = "1E+40"
      ∧ renderFloatText jsonFloatStyle "1e-6" = "0.000001"
      ∧ renderFloatText jsonFloatStyle "1e-7" = "1E-7"
      ∧ renderFloatText jsonFloatStyle "1.234e+10" = "1.234E+10"
      ∧ renderFloatText jsonFloatStyle "1.00e+2" = "100"
      ∧ renderFloatText jsonFloatStyle "-0.0" = "0.0"
      ∧ renderFloatText jsonFloatStyle "-2e+3" = "-2E+3"
      ∧ renderFloatText jsonFloatStyle "100.0" = "100.0" := by
  native_decide

-- cue-native style: lowercase `e`, `.0` tail on whole floats. Same matrix.
theorem float_render_cue_native :
    renderFloatText cueFloatStyle "1e+2" = "1e+2"
      ∧ renderFloatText cueFloatStyle "1e-2" = "0.01"
      ∧ renderFloatText cueFloatStyle "12345e-2" = "123.45"
      ∧ renderFloatText cueFloatStyle "1e+40" = "1e+40"
      ∧ renderFloatText cueFloatStyle "1e-7" = "1e-7"
      ∧ renderFloatText cueFloatStyle "1.234e+10" = "1.234e+10"
      ∧ renderFloatText cueFloatStyle "1.00e+2" = "100.0"
      ∧ renderFloatText cueFloatStyle "2e+0" = "2.0"
      ∧ renderFloatText cueFloatStyle "-0.0" = "0.0" := by
  native_decide

-- YAML style: uppercase `E`, `.` tail on whole floats (go-yaml's whole-float form).
theorem float_render_yaml :
    renderFloatText yamlFloatStyle "1e+2" = "1E+2"
      ∧ renderFloatText yamlFloatStyle "1e-2" = "0.01"
      ∧ renderFloatText yamlFloatStyle "1.00e+2" = "100."
      ∧ renderFloatText yamlFloatStyle "2e+0" = "2."
      ∧ renderFloatText yamlFloatStyle "-1.00e+2" = "-100." := by
  native_decide

-- Division threads the apd IDEAL exponent (F4-DIV): an exact quotient renders in cue's GDA
-- form, NOT the fully-expanded decimal. For minimal `±m·10^k` (`m` trailing-zero-free,
-- `d = digits(m)`): an integer value (`k ≥ 0`) with adjusted exponent `k + d − 1 ≤ 32` gains
-- one trailing zero (`2.0e+2`, `25.0`, `10.0`, `1.0e+2`), forcing the `.0`/`X.0e+n` form; at
-- adjusted exponent 33 the cap keeps the minimal form (`1e+34`, `1e+33`), as does a
-- negative-scientific quotient (`2.5e-7`). Zero clamps the ideal exponent (`0.0`). A
-- non-terminating quotient stays on the 34-digit rounding path (`1/3`). Byte-identical to cue
-- v0.16.1 (see testdata/wild/float-apd-division-exponent for the JSON axis).
theorem float_div_apd_ideal_exponent :
    formatValue (evalDiv (.prim (mkFloatText "6e2")) (.prim (.int 3))) = "2.0e+2"
      ∧ formatValue (evalDiv (.prim (.int 1000000)) (.prim (.int 8))) = "1.250e+5"
      ∧ formatValue (evalDiv (.prim (mkFloatText "1e2")) (.prim (.int 4))) = "25.0"
      ∧ formatValue (evalDiv (.prim (.int 10)) (.prim (.int 1))) = "10.0"
      ∧ formatValue (evalDiv (.prim (.int 100)) (.prim (.int 1))) = "1.0e+2"
      ∧ formatValue (evalDiv (.prim (mkFloatText "-6e2")) (.prim (.int 3))) = "-2.0e+2"
      ∧ formatValue (evalDiv (.prim (mkFloatText "1e34")) (.prim (.int 1))) = "1e+34"
      ∧ formatValue (evalDiv (.prim (mkFloatText "1e33")) (.prim (.int 1))) = "1e+33"
      ∧ formatValue (evalDiv (.prim (.int 25)) (.prim (.int 100000000))) = "2.5e-7"
      ∧ formatValue (evalDiv (.prim (.int 0)) (.prim (.int 3))) = "0.0"
      ∧ formatValue (evalDiv (.prim (mkFloatText "0e2")) (.prim (mkFloatText "8e3"))) = "0.0"
      ∧ formatValue (evalDiv (.prim (.int 1)) (.prim (.int 3)))
          = "0.3333333333333333333333333333333333" := by
  native_decide

-- COVERAGE TRIPWIRE (test-health). Anchors the last theorem of each section;
-- a swallowed section makes its anchor an unknown identifier and fails `#check`
-- elaboration.
#check @int_kind_rejects_float_primitive
#check @float_pinned_across_contexts
#check @float_div_apd_ideal_exponent

end Kue
