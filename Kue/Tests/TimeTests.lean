import Kue.Builtin
import Kue.Tests.EvalTestHelpers

namespace Kue

-- STDLIB-TIME: the `time` package's exact/structural surface. Each theorem pins one behavior
-- against cue v0.16.1. The civil-calendar/epoch functions (`Unix`/`Parse`/`FormatString`/`Split`/
-- `FormatDuration`) and non-RFC3339 custom `Format` layouts are DEFERRED to `unsupportedBuiltin`;
-- `time.Date` is a nonexistent leaf and bottoms bare.

private def call (name : String) (args : List Value) : Value := evalBuiltinCall name args

-- ### `time.ParseDuration` — Go duration string → int64 nanoseconds

theorem pd_hours_minutes :
    (call "time.ParseDuration" [.prim (.string "1h30m")] == .prim (.int 5400000000000)) = true := by
  native_decide
theorem pd_millis :
    (call "time.ParseDuration" [.prim (.string "300ms")] == .prim (.int 300000000)) = true := by
  native_decide
theorem pd_negative :
    (call "time.ParseDuration" [.prim (.string "-2h")] == .prim (.int (-7200000000000))) = true := by
  native_decide
theorem pd_plus_sign :
    (call "time.ParseDuration" [.prim (.string "+3h")] == .prim (.int 10800000000000)) = true := by
  native_decide
theorem pd_fraction :
    (call "time.ParseDuration" [.prim (.string "1.5h")] == .prim (.int 5400000000000)) = true := by
  native_decide
theorem pd_combo :
    (call "time.ParseDuration" [.prim (.string "1h30m45s")] == .prim (.int 5445000000000)) = true := by
  native_decide
theorem pd_micros_us :
    (call "time.ParseDuration" [.prim (.string "100us")] == .prim (.int 100000)) = true := by
  native_decide
-- Both micro suffixes: µ (U+00B5) and μ (U+03BC).
theorem pd_micros_mu_sign :
    (call "time.ParseDuration" [.prim (.string "1µs")] == .prim (.int 1000)) = true := by native_decide
theorem pd_micros_greek_mu :
    (call "time.ParseDuration" [.prim (.string "1μs")] == .prim (.int 1000)) = true := by native_decide
theorem pd_nanos :
    (call "time.ParseDuration" [.prim (.string "10ns")] == .prim (.int 10)) = true := by native_decide
theorem pd_zero :
    (call "time.ParseDuration" [.prim (.string "0")] == .prim (.int 0)) = true := by native_decide
theorem pd_neg_zero :
    (call "time.ParseDuration" [.prim (.string "-0")] == .prim (.int 0)) = true := by native_decide
theorem pd_leading_dot :
    (call "time.ParseDuration" [.prim (.string ".5s")] == .prim (.int 500000000)) = true := by
  native_decide
theorem pd_trailing_dot :
    (call "time.ParseDuration" [.prim (.string "1.s")] == .prim (.int 1000000000)) = true := by
  native_decide
theorem pd_repeated_unit :
    (call "time.ParseDuration" [.prim (.string "5s3s")] == .prim (.int 8000000000)) = true := by
  native_decide
-- Sub-nanosecond fraction truncates toward zero (exact integer division).
theorem pd_subnano_truncates :
    (call "time.ParseDuration" [.prim (.string "0.0000000001s")] == .prim (.int 0)) = true := by
  native_decide
-- int64 max is the largest valid magnitude.
theorem pd_int64_max :
    (call "time.ParseDuration" [.prim (.string "2562047h47m16.854775807s")]
      == .prim (.int 9223372036854775807)) = true := by native_decide

-- Invalid / overflow ⇒ bottom (cue errors).
theorem pd_empty : isBottom (call "time.ParseDuration" [.prim (.string "")]) = true := by native_decide
theorem pd_bare_unit : isBottom (call "time.ParseDuration" [.prim (.string "h")]) = true := by
  native_decide
theorem pd_missing_unit : isBottom (call "time.ParseDuration" [.prim (.string "1")]) = true := by
  native_decide
theorem pd_unknown_unit : isBottom (call "time.ParseDuration" [.prim (.string "1x")]) = true := by
  native_decide
theorem pd_missing_unit_frac :
    isBottom (call "time.ParseDuration" [.prim (.string "1.5")]) = true := by native_decide
theorem pd_leading_space :
    isBottom (call "time.ParseDuration" [.prim (.string " 5s")]) = true := by native_decide
theorem pd_trailing_space :
    isBottom (call "time.ParseDuration" [.prim (.string "5s ")]) = true := by native_decide
theorem pd_uppercase_unit :
    isBottom (call "time.ParseDuration" [.prim (.string "5S")]) = true := by native_decide
theorem pd_sign_midstring :
    isBottom (call "time.ParseDuration" [.prim (.string "1h-30m")]) = true := by native_decide
theorem pd_overflow :
    isBottom (call "time.ParseDuration" [.prim (.string "2562048h")]) = true := by native_decide

-- ### `time.Duration` validator (string-format, meet-participating)

theorem dur_validator_value :
    (call "time.Duration" [] == .stringFormat .duration) = true := by native_decide
-- Concrete conforming string passes through; non-conforming GROUND string bottoms.
theorem dur_concrete_valid :
    (meet (.prim (.string "1h30m")) (.stringFormat .duration) == .prim (.string "1h30m")) = true := by
  native_decide
theorem dur_concrete_invalid :
    isBottom (meet (.prim (.string "notaduration")) (.stringFormat .duration)) = true := by
  native_decide
-- ABSTRACT string RETAINS the validator (stays incomplete, never fabricated / bottomed).
theorem dur_abstract_retains :
    (meet (.kind .string) (.stringFormat .duration) == .stringFormat .duration) = true := by
  native_decide
theorem dur_abstract_not_bottom :
    isBottom (meet (.kind .string) (.stringFormat .duration)) = false := by native_decide
-- A non-string is a kind conflict.
theorem dur_int_conflict :
    isBottom (meet (.prim (.int 5)) (.stringFormat .duration)) = true := by native_decide
-- Function form: `time.Duration(s)` ⇒ true on valid, bottom on invalid.
theorem dur_fn_true :
    (call "time.Duration" [.prim (.string "1h")] == .prim (.bool true)) = true := by native_decide
theorem dur_fn_invalid :
    isBottom (call "time.Duration" [.prim (.string "bad")]) = true := by native_decide

-- ### `time.Time` / RFC3339 validator

theorem time_validator_value :
    (call "time.Time" [] == .stringFormat .rfc3339) = true := by native_decide
theorem time_valid_z :
    (meet (.prim (.string "2019-01-02T15:04:05Z")) (.stringFormat .rfc3339)
      == .prim (.string "2019-01-02T15:04:05Z")) = true := by native_decide
theorem time_valid_offset :
    (meet (.prim (.string "2019-01-02T15:04:05+07:00")) (.stringFormat .rfc3339)
      == .prim (.string "2019-01-02T15:04:05+07:00")) = true := by native_decide
theorem time_valid_frac :
    (meet (.prim (.string "2019-01-02T15:04:05.999Z")) (.stringFormat .rfc3339)
      == .prim (.string "2019-01-02T15:04:05.999Z")) = true := by native_decide
-- Out-of-range and structural failures bottom.
theorem time_bad_month :
    isBottom (meet (.prim (.string "2019-13-02T15:04:05Z")) (.stringFormat .rfc3339)) = true := by
  native_decide
theorem time_bad_day :
    isBottom (meet (.prim (.string "2019-01-32T15:04:05Z")) (.stringFormat .rfc3339)) = true := by
  native_decide
theorem time_bad_hour :
    isBottom (meet (.prim (.string "2019-01-02T25:04:05Z")) (.stringFormat .rfc3339)) = true := by
  native_decide
theorem time_bad_second :
    isBottom (meet (.prim (.string "2019-01-02T15:04:60Z")) (.stringFormat .rfc3339)) = true := by
  native_decide
theorem time_missing_offset :
    isBottom (meet (.prim (.string "2019-01-02T15:04:05")) (.stringFormat .rfc3339)) = true := by
  native_decide
theorem time_lowercase_t :
    isBottom (meet (.prim (.string "2019-01-02t15:04:05z")) (.stringFormat .rfc3339)) = true := by
  native_decide
theorem time_zero_month :
    isBottom (meet (.prim (.string "2019-00-02T15:04:05Z")) (.stringFormat .rfc3339)) = true := by
  native_decide
theorem time_offset_over_z :
    isBottom (meet (.prim (.string "2019-01-02T15:04:05Z07:00")) (.stringFormat .rfc3339)) = true := by
  native_decide
-- Leap-year calendar validation: Feb 29 rejected in a common year, accepted in a leap year.
theorem time_feb29_common :
    isBottom (meet (.prim (.string "2019-02-29T00:00:00Z")) (.stringFormat .rfc3339)) = true := by
  native_decide
theorem time_feb29_leap :
    (meet (.prim (.string "2020-02-29T00:00:00Z")) (.stringFormat .rfc3339)
      == .prim (.string "2020-02-29T00:00:00Z")) = true := by native_decide
theorem time_apr31 :
    isBottom (meet (.prim (.string "2019-04-31T00:00:00Z")) (.stringFormat .rfc3339)) = true := by
  native_decide
-- Abstract string retains.
theorem time_abstract_retains :
    (meet (.kind .string) (.stringFormat .rfc3339) == .stringFormat .rfc3339) = true := by
  native_decide
-- Function form.
theorem time_fn_true :
    (call "time.Time" [.prim (.string "2019-01-02T15:04:05Z")] == .prim (.bool true)) = true := by
  native_decide
theorem time_fn_invalid :
    isBottom (call "time.Time" [.prim (.string "bad")]) = true := by native_decide

-- ### `time.Format` — RFC3339 layouts land, others defer

theorem format_rfc3339_validator :
    (call "time.Format" [.prim (.string "2006-01-02T15:04:05Z07:00")] == .stringFormat .rfc3339)
      = true := by native_decide
theorem format_rfc3339nano_validator :
    (call "time.Format" [.prim (.string "2006-01-02T15:04:05.999999999Z07:00")]
      == .stringFormat .rfc3339) = true := by native_decide
theorem format_rfc3339_fn_true :
    (call "time.Format" [.prim (.string "2019-01-02T15:04:05Z"), .prim (.string "2006-01-02T15:04:05Z07:00")]
      == .prim (.bool true)) = true := by native_decide
-- A non-RFC3339 layout defers with a clear unsupported marker.
theorem format_kitchen_deferred :
    (call "time.Format" [.prim (.string "3:04PM")]
      == .bottomWith [.unsupportedBuiltin "time.Format"]) = true := by native_decide

-- ### Deferred civil-calendar/epoch functions ⇒ `unsupportedBuiltin`; nonexistent leaf ⇒ bare

theorem unix_deferred :
    (call "time.Unix" [.prim (.int 1500000000), .prim (.int 0)]
      == .bottomWith [.unsupportedBuiltin "time.Unix"]) = true := by native_decide
theorem parse_deferred :
    (call "time.Parse" [.prim (.string "2006-01-02T15:04:05Z07:00"), .prim (.string "2019-01-02T15:04:05Z")]
      == .bottomWith [.unsupportedBuiltin "time.Parse"]) = true := by native_decide
theorem split_deferred :
    (call "time.Split" [.prim (.string "2019-01-02T15:04:05Z")]
      == .bottomWith [.unsupportedBuiltin "time.Split"]) = true := by native_decide
theorem formatduration_deferred :
    (call "time.FormatDuration" [.prim (.int 5400000000000)]
      == .bottomWith [.unsupportedBuiltin "time.FormatDuration"]) = true := by native_decide
-- `time.Date` is not a real cue leaf → bare bottom (no unsupported marker).
theorem date_nonexistent_bare :
    (call "time.Date" [.prim (.int 2019)] == .bottom) = true := by native_decide

-- ### End-to-end: constants resolve import-gated; validators/parsers flow through export

theorem e2e_hour_const :
    exportJsonMatches "import \"time\"\nx: time.Hour\n" "{\n    \"x\": 3600000000000\n}\n" = true := by
  native_decide
theorem e2e_nanosecond_const :
    exportJsonMatches "import \"time\"\nx: time.Nanosecond\n" "{\n    \"x\": 1\n}\n" = true := by
  native_decide
theorem e2e_rfc3339_const :
    exportJsonMatches "import \"time\"\nx: time.RFC3339\n"
      "{\n    \"x\": \"2006-01-02T15:04:05Z07:00\"\n}\n" = true := by native_decide
theorem e2e_january_const :
    exportJsonMatches "import \"time\"\nx: time.January\n" "{\n    \"x\": 1\n}\n" = true := by
  native_decide
theorem e2e_parseduration :
    exportJsonMatches "import \"time\"\nx: time.ParseDuration(\"1h30m\")\n"
      "{\n    \"x\": 5400000000000\n}\n" = true := by native_decide
-- Bare validator form (no call) resolves and validates a concrete string.
theorem e2e_duration_validator_bare :
    exportJsonMatches "import \"time\"\nx: \"1h30m\" & time.Duration\n"
      "{\n    \"x\": \"1h30m\"\n}\n" = true := by native_decide
theorem e2e_time_validator :
    exportJsonMatches "import \"time\"\nx: \"2019-01-02T15:04:05Z\" & time.Time()\n"
      "{\n    \"x\": \"2019-01-02T15:04:05Z\"\n}\n" = true := by native_decide
theorem e2e_duration_invalid_bottoms :
    exportJsonBottoms "import \"time\"\nx: \"notaduration\" & time.Duration()\n" = true := by
  native_decide
-- Abstract string & validator stays incomplete (manifest bottoms, but the value is retained).
theorem e2e_abstract_incomplete :
    exportJsonBottoms "import \"time\"\nx: string & time.Duration()\n" = true := by native_decide

-- Per-section coverage tripwire: an editing slip that drops a section fails the build here.
#check @pd_overflow             -- ParseDuration (units, signs, fractions, overflow, invalid)
#check @dur_fn_invalid          -- Duration validator (concrete/abstract/function forms)
#check @time_fn_invalid         -- Time / RFC3339 validator (ranges, leap-year, offset)
#check @format_kitchen_deferred -- Format (RFC3339 layouts land, others defer)
#check @date_nonexistent_bare   -- deferred functions + nonexistent leaf
#check @e2e_abstract_incomplete -- end-to-end export (constants, validators, incomplete)

end Kue
