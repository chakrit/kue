import Kue.Builtin
import Kue.Tests.EvalTestHelpers

namespace Kue

-- STDLIB-C: `strconv` builtin dispatch. Each theorem pins one implemented function against
-- cue v0.16.1 on representative, boundary, and error inputs. Real-but-deferred functions
-- (`Quote`/`Unquote` family) route to `unsupportedBuiltin`; a
-- nonexistent leaf (`Itoa`, not a callable function in cue) bottoms bare, cue's own verdict.
--
-- `Value` is a mutual inductive (`BEq`, no `DecidableEq`), so theorems assert `(lhs == rhs) =
-- true`, matching the repo's existing builtin-test convention.

private def call (name : String) (args : List Value) : Value := evalBuiltinCall name args

-- Atoi: base-10, optional sign, leading zeros, arbitrary precision; non-numeric ⇒ syntax bottom.
theorem atoi_positive : (call "strconv.Atoi" [.prim (.string "42")] == .prim (.int 42)) = true := by
  native_decide
theorem atoi_negative :
    (call "strconv.Atoi" [.prim (.string "-7")] == .prim (.int (-7))) = true := by native_decide
theorem atoi_plus_sign :
    (call "strconv.Atoi" [.prim (.string "+7")] == .prim (.int 7)) = true := by native_decide
theorem atoi_leading_zeros :
    (call "strconv.Atoi" [.prim (.string "007")] == .prim (.int 7)) = true := by native_decide
theorem atoi_bignum :
    (call "strconv.Atoi" [.prim (.string "99999999999999999999999")]
      == .prim (.int 99999999999999999999999)) = true := by native_decide
theorem atoi_nonnumeric :
    (call "strconv.Atoi" [.prim (.string "abc")] == .bottomWith [.strconvSyntax "abc"]) = true := by
  native_decide
theorem atoi_empty :
    (call "strconv.Atoi" [.prim (.string "")] == .bottomWith [.strconvSyntax ""]) = true := by
  native_decide
theorem atoi_leading_space :
    (call "strconv.Atoi" [.prim (.string " 5")] == .bottomWith [.strconvSyntax " 5"]) = true := by
  native_decide
theorem atoi_no_underscores :
    (call "strconv.Atoi" [.prim (.string "1_000")] == .bottomWith [.strconvSyntax "1_000"]) = true := by
  native_decide

-- FormatInt / FormatUint: base 2..36, lowercase digits, `-` sign; base out of range ⇒ invalid base.
theorem formatint_hex :
    (call "strconv.FormatInt" [.prim (.int 255), .prim (.int 16)] == .prim (.string "ff")) = true := by
  native_decide
theorem formatint_neg_hex :
    (call "strconv.FormatInt" [.prim (.int (-255)), .prim (.int 16)] == .prim (.string "-ff")) = true := by
  native_decide
theorem formatint_zero :
    (call "strconv.FormatInt" [.prim (.int 0), .prim (.int 2)] == .prim (.string "0")) = true := by
  native_decide
theorem formatint_binary :
    (call "strconv.FormatInt" [.prim (.int 5), .prim (.int 2)] == .prim (.string "101")) = true := by
  native_decide
theorem formatint_base36 :
    (call "strconv.FormatInt" [.prim (.int 35), .prim (.int 36)] == .prim (.string "z")) = true := by
  native_decide
theorem formatint_base_too_low :
    (call "strconv.FormatInt" [.prim (.int 255), .prim (.int 1)]
      == .bottomWith [.strconvInvalidBase 1]) = true := by native_decide
theorem formatint_base_too_high :
    (call "strconv.FormatInt" [.prim (.int 255), .prim (.int 37)]
      == .bottomWith [.strconvInvalidBase 37]) = true := by native_decide
theorem formatuint_matches_formatint :
    (call "strconv.FormatUint" [.prim (.int 255), .prim (.int 16)] == .prim (.string "ff")) = true := by
  native_decide

-- ParseInt: explicit base, base-0 prefix auto-detect, underscores (base 0 only), bitSize range.
theorem parseint_hex :
    (call "strconv.ParseInt" [.prim (.string "ff"), .prim (.int 16), .prim (.int 64)]
      == .prim (.int 255)) = true := by native_decide
theorem parseint_hex_uppercase :
    (call "strconv.ParseInt" [.prim (.string "FF"), .prim (.int 16), .prim (.int 64)]
      == .prim (.int 255)) = true := by native_decide
theorem parseint_neg_hex :
    (call "strconv.ParseInt" [.prim (.string "-ff"), .prim (.int 16), .prim (.int 64)]
      == .prim (.int (-255))) = true := by native_decide
theorem parseint_base0_hex :
    (call "strconv.ParseInt" [.prim (.string "0x1F"), .prim (.int 0), .prim (.int 64)]
      == .prim (.int 31)) = true := by native_decide
theorem parseint_base0_binary :
    (call "strconv.ParseInt" [.prim (.string "0b101"), .prim (.int 0), .prim (.int 64)]
      == .prim (.int 5)) = true := by native_decide
theorem parseint_base0_octal_prefix :
    (call "strconv.ParseInt" [.prim (.string "0o17"), .prim (.int 0), .prim (.int 64)]
      == .prim (.int 15)) = true := by native_decide
theorem parseint_base0_leading_zero_octal :
    (call "strconv.ParseInt" [.prim (.string "017"), .prim (.int 0), .prim (.int 64)]
      == .prim (.int 15)) = true := by native_decide
theorem parseint_base0_underscores :
    (call "strconv.ParseInt" [.prim (.string "1_000"), .prim (.int 0), .prim (.int 64)]
      == .prim (.int 1000)) = true := by native_decide
theorem parseint_base0_prefix_underscore :
    (call "strconv.ParseInt" [.prim (.string "0x_ff"), .prim (.int 0), .prim (.int 64)]
      == .prim (.int 255)) = true := by native_decide
theorem parseint_base0_just_zero :
    (call "strconv.ParseInt" [.prim (.string "0"), .prim (.int 0), .prim (.int 64)]
      == .prim (.int 0)) = true := by native_decide
theorem parseint_base0_bare_prefix_syntax :
    (call "strconv.ParseInt" [.prim (.string "0x"), .prim (.int 0), .prim (.int 64)]
      == .bottomWith [.strconvSyntax "0x"]) = true := by native_decide
theorem parseint_base10_underscore_syntax :
    (call "strconv.ParseInt" [.prim (.string "1_000"), .prim (.int 10), .prim (.int 64)]
      == .bottomWith [.strconvSyntax "1_000"]) = true := by native_decide
theorem parseint_leading_underscore_syntax :
    (call "strconv.ParseInt" [.prim (.string "_5"), .prim (.int 0), .prim (.int 64)]
      == .bottomWith [.strconvSyntax "_5"]) = true := by native_decide
theorem parseint_trailing_underscore_syntax :
    (call "strconv.ParseInt" [.prim (.string "5_"), .prim (.int 0), .prim (.int 64)]
      == .bottomWith [.strconvSyntax "5_"]) = true := by native_decide
theorem parseint_double_underscore_syntax :
    (call "strconv.ParseInt" [.prim (.string "5__5"), .prim (.int 0), .prim (.int 64)]
      == .bottomWith [.strconvSyntax "5__5"]) = true := by native_decide
-- bitSize range: int64 boundary is in range, one past is out.
theorem parseint_int64_max :
    (call "strconv.ParseInt" [.prim (.string "9223372036854775807"), .prim (.int 10), .prim (.int 64)]
      == .prim (.int 9223372036854775807)) = true := by native_decide
theorem parseint_int64_overflow :
    (call "strconv.ParseInt" [.prim (.string "9223372036854775808"), .prim (.int 10), .prim (.int 64)]
      == .bottomWith [.strconvRange "9223372036854775808"]) = true := by native_decide
theorem parseint_bitsize0_unbounded :
    (call "strconv.ParseInt" [.prim (.string "99999999999999999999999"), .prim (.int 10), .prim (.int 0)]
      == .prim (.int 99999999999999999999999)) = true := by native_decide
theorem parseint_int8_range :
    (call "strconv.ParseInt" [.prim (.string "128"), .prim (.int 10), .prim (.int 8)]
      == .bottomWith [.strconvRange "128"]) = true := by native_decide
theorem parseint_int8_ok :
    (call "strconv.ParseInt" [.prim (.string "127"), .prim (.int 10), .prim (.int 8)]
      == .prim (.int 127)) = true := by native_decide
theorem parseint_neg_bitsize :
    (call "strconv.ParseInt" [.prim (.string "5"), .prim (.int 10), .prim (.int (-1))]
      == .bottomWith [.strconvRange "5"]) = true := by native_decide
theorem parseint_invalid_base :
    (call "strconv.ParseInt" [.prim (.string "ff"), .prim (.int 1), .prim (.int 64)]
      == .bottomWith [.strconvInvalidBase 1]) = true := by native_decide
theorem parseint_invalid_digit :
    (call "strconv.ParseInt" [.prim (.string "abc"), .prim (.int 10), .prim (.int 64)]
      == .bottomWith [.strconvSyntax "abc"]) = true := by native_decide
-- Round-trip: ParseInt ∘ FormatInt over a hex value.
theorem parseint_formatint_roundtrip :
    (call "strconv.ParseInt"
      [call "strconv.FormatInt" [.prim (.int 48879), .prim (.int 16)], .prim (.int 16), .prim (.int 64)]
      == .prim (.int 48879)) = true := by native_decide

-- ParseUint: negative ⇒ out of range (not syntax); bitSize 64 upper boundary.
theorem parseuint_hex :
    (call "strconv.ParseUint" [.prim (.string "ff"), .prim (.int 16), .prim (.int 64)]
      == .prim (.int 255)) = true := by native_decide
theorem parseuint_negative_range :
    (call "strconv.ParseUint" [.prim (.string "-5"), .prim (.int 10), .prim (.int 64)]
      == .bottomWith [.strconvRange "-5"]) = true := by native_decide
theorem parseuint_neg_zero_ok :
    (call "strconv.ParseUint" [.prim (.string "-0"), .prim (.int 10), .prim (.int 64)]
      == .prim (.int 0)) = true := by native_decide
theorem parseuint_uint64_max :
    (call "strconv.ParseUint" [.prim (.string "18446744073709551615"), .prim (.int 10), .prim (.int 64)]
      == .prim (.int 18446744073709551615)) = true := by native_decide
theorem parseuint_uint64_overflow :
    (call "strconv.ParseUint" [.prim (.string "18446744073709551616"), .prim (.int 10), .prim (.int 64)]
      == .bottomWith [.strconvRange "18446744073709551616"]) = true := by native_decide

-- FormatBool / ParseBool.
theorem formatbool_true :
    (call "strconv.FormatBool" [.prim (.bool true)] == .prim (.string "true")) = true := by
  native_decide
theorem formatbool_false :
    (call "strconv.FormatBool" [.prim (.bool false)] == .prim (.string "false")) = true := by
  native_decide
theorem parsebool_true :
    (call "strconv.ParseBool" [.prim (.string "true")] == .prim (.bool true)) = true := by
  native_decide
theorem parsebool_one :
    (call "strconv.ParseBool" [.prim (.string "1")] == .prim (.bool true)) = true := by native_decide
theorem parsebool_T :
    (call "strconv.ParseBool" [.prim (.string "T")] == .prim (.bool true)) = true := by native_decide
theorem parsebool_false :
    (call "strconv.ParseBool" [.prim (.string "false")] == .prim (.bool false)) = true := by
  native_decide
theorem parsebool_zero :
    (call "strconv.ParseBool" [.prim (.string "0")] == .prim (.bool false)) = true := by
  native_decide
theorem parsebool_invalid :
    (call "strconv.ParseBool" [.prim (.string "yes")] == .bottomWith [.strconvSyntax "yes"]) = true := by
  native_decide

-- A nonexistent leaf (`Itoa` is not a callable function in cue v0.16.1 — `cannot call
-- non-function`) bottoms BARE, no `unsupportedBuiltin` marker: the marker is a positive
-- recognition claim, and a nonexistent leaf is a plain type error, matching cue's verdict.
theorem itoa_nonexistent_is_bottom :
    (call "strconv.Itoa" [.prim (.int 255)] == .bottom) = true := by
  native_decide
-- STDLIB-FLOAT-F2: IEEE float64/32 surface. ParseFloat's stored anchor is Go's shortest
-- SCIENTIFIC (`'e'`) string — the apd.SetFloat64 form cue re-renders (`"100"` ↦ `1E+2`); every
-- anchor is pinned against Go/cue v0.16.1, and its RENDER is pinned by `strconv_float` export.
theorem parsefloat_tenth :
    (call "strconv.ParseFloat" [.prim (.string "0.1"), .prim (.int 64)]
      == .prim (mkFloatText "1e-01")) = true := by native_decide
theorem parsefloat_hundred_scientific :
    (call "strconv.ParseFloat" [.prim (.string "100"), .prim (.int 64)]
      == .prim (mkFloatText "1e+02")) = true := by native_decide
theorem parsefloat_e23_shortest :
    (call "strconv.ParseFloat" [.prim (.string "1e23"), .prim (.int 64)]
      == .prim (mkFloatText "1e+23")) = true := by native_decide
theorem parsefloat_third_roundtrip :
    (call "strconv.ParseFloat" [.prim (.string "0.3333333333333333333"), .prim (.int 64)]
      == .prim (mkFloatText "3.333333333333333e-01")) = true := by native_decide
theorem parsefloat_min_subnormal :
    (call "strconv.ParseFloat" [.prim (.string "5e-324"), .prim (.int 64)]
      == .prim (mkFloatText "5e-324")) = true := by native_decide
theorem parsefloat_underflow_zero :
    (call "strconv.ParseFloat" [.prim (.string "1e-400"), .prim (.int 64)]
      == .prim (mkFloatText "0e+00")) = true := by native_decide
theorem parsefloat_float32 :
    (call "strconv.ParseFloat" [.prim (.string "16777217"), .prim (.int 32)]
      == .prim (mkFloatText "1.6777216e+07")) = true := by native_decide
theorem parsefloat_overflow_range :
    (call "strconv.ParseFloat" [.prim (.string "1e400"), .prim (.int 64)]
      == .bottomWith [.strconvRange "1e400"]) = true := by native_decide
theorem parsefloat_syntax :
    (call "strconv.ParseFloat" [.prim (.string "abc"), .prim (.int 64)]
      == .bottomWith [.strconvSyntax "abc"]) = true := by native_decide

-- FormatFloat: verb byte ('g'=103,'e'=101,'f'=102), prec (-1 shortest), bitSize.
theorem formatfloat_g_shortest :
    (call "strconv.FormatFloat"
        [.prim (mkFloatText "1234.5678"), .prim (.int 103), .prim (.int (-1)), .prim (.int 64)]
      == .prim (.string "1234.5678")) = true := by native_decide
theorem formatfloat_e_shortest :
    (call "strconv.FormatFloat"
        [.prim (mkFloatText "1234.5678"), .prim (.int 101), .prim (.int (-1)), .prim (.int 64)]
      == .prim (.string "1.2345678e+03")) = true := by native_decide
theorem formatfloat_g_big_exponent :
    (call "strconv.FormatFloat"
        [.prim (mkFloatText "1e20"), .prim (.int 103), .prim (.int (-1)), .prim (.int 64)]
      == .prim (.string "1e+20")) = true := by native_decide
theorem formatfloat_int_input :
    (call "strconv.FormatFloat"
        [.prim (.int 100), .prim (.int 103), .prim (.int (-1)), .prim (.int 64)]
      == .prim (.string "100")) = true := by native_decide
theorem formatfloat_f_fixed_prec :
    (call "strconv.FormatFloat"
        [.prim (mkFloatText "1234.5678"), .prim (.int 102), .prim (.int 2), .prim (.int 64)]
      == .prim (.string "1234.57")) = true := by native_decide
theorem formatfloat_f_round_half_even :
    (call "strconv.FormatFloat"
        [.prim (mkFloatText "2.5"), .prim (.int 102), .prim (.int 0), .prim (.int 64)]
      == .prim (.string "2")) = true := by native_decide
theorem formatfloat_verb_deferred :
    (call "strconv.FormatFloat"
        [.prim (mkFloatText "1.5"), .prim (.int 120), .prim (.int (-1)), .prim (.int 64)]
      == .bottomWith [.unsupportedBuiltin "strconv.FormatFloat (verb ∉ {e,E,f,F,g,G})"])
      = true := by native_decide

theorem quote_deferred :
    (call "strconv.Quote" [.prim (.string "hi")]
      == .bottomWith [.unsupportedBuiltin "strconv.Quote"]) = true := by native_decide

-- A concrete call to a deferred-but-recognized function renders a CLEAR CLI message naming the
-- unimplemented function (mirroring the unsupported-PACKAGE path), not the generic
-- `conflicting values (bottom)`. Pins the exact wording of the manifest→CLI render.
theorem quote_render_message :
    exportErrorMessage "import \"strconv\"\nx: strconv.Quote(\"hi\")\n"
      = "unsupported builtin function \"strconv.Quote\": recognized but not yet implemented in kue" := by
  native_decide

-- An IMPLEMENTED strconv call still exports concretely (the deferred-function diagnostic did not
-- regress the working dispatch).
theorem atoi_still_exports :
    exportJsonMatches "import \"strconv\"\nx: strconv.Atoi(\"42\")\n"
      "{\n    \"x\": 42\n}\n" = true := by native_decide

-- COVERAGE TRIPWIRE (test-health). Anchors the last theorem of each function group; a
-- swallowed group makes its anchor an unknown identifier and fails `#check` elaboration.
#check @atoi_no_underscores                 -- Atoi
#check @formatuint_matches_formatint        -- FormatInt / FormatUint
#check @parseint_formatint_roundtrip        -- ParseInt (base, prefix, underscore, bitSize)
#check @parseuint_uint64_overflow           -- ParseUint
#check @parsebool_invalid                   -- FormatBool / ParseBool
#check @parsefloat_syntax                   -- ParseFloat (F2: shortest, subnormal, over/underflow, f32)
#check @formatfloat_verb_deferred           -- FormatFloat (F2: verbs, prec, round-half-even, defer)
#check @quote_deferred                      -- deferred → unsupportedBuiltin
#check @atoi_still_exports                  -- render path (clear message + no regression)

end Kue
