import Kue.Value

namespace Kue

/-! # `time` standard-library primitives (STDLIB-TIME)

Pure, exact, calendar-free slices of cue's `time` package: the Go-duration lexer
(`time.ParseDuration` / `time.Duration` validator) and RFC3339 timestamp validation
(`time.Time` / `time.Format(RFC3339|RFC3339Nano)` validators). Every function is total —
a non-conforming input yields `none`/`false`, never a wrong value.

**Scope boundary.** Only the exact-integer / string-structural surface lands here. The
civil-calendar / epoch functions (`time.Unix`, `time.Parse`, `time.FormatString`,
`time.Split`, `time.FormatDuration`, arbitrary custom `Format` layouts) need a
date↔epoch engine or Go's format machinery and are DEFERRED at the dispatcher with an
`unsupportedBuiltin` marker (see `docs/spec/cue-spec-gaps.md`), never faked. -/

/-- `2^63 - 1`, the maximum magnitude of a Go `time.Duration` (int64 nanoseconds). Go
    accumulates the duration as a positive int64 and negates at the end, so `-2^63` is
    NOT reachable — the representable magnitude is capped at `2^63 - 1` for both signs.
    cue surfaces the overflow as an error, so Kue bottoms/rejects beyond this. -/
def durationMaxMag : Int := 9223372036854775807

/-- The nanosecond weight of a Go duration unit suffix, or `none` for an unknown suffix.
    Covers `ns`/`us`/`µs` (U+00B5 micro sign)/`μs` (U+03BC Greek mu)/`ms`/`s`/`m`/`h`,
    exactly Go's `unitMap`. -/
def durationUnit? (u : String) : Option Int :=
  match u with
  | "ns" => some 1
  | "us" => some 1000
  | "µs" => some 1000
  | "μs" => some 1000
  | "ms" => some 1000000
  | "s"  => some 1000000000
  | "m"  => some 60000000000
  | "h"  => some 3600000000000
  | _    => none

/-- Split off a leading run of decimal digits: the accumulated magnitude, the number of
    digits consumed, and the remainder. Structural on the char list, hence total. -/
def leadingDigits (chars : List Char) : Int × Nat × List Char :=
  match chars with
  | c :: rest =>
      if c.toNat ≥ 48 ∧ c.toNat ≤ 57 then
        let (v, n, tl) := leadingDigits rest
        ((Int.ofNat (c.toNat - 48)) * (10 ^ n) + v, n + 1, tl)
      else
        (0, 0, chars)
  | [] => (0, 0, chars)

/-- Split off the leading unit suffix: the maximal run of characters that are neither a
    digit nor a `.` (Go reads the unit as everything up to the next digit/dot). Structural,
    hence total. -/
def leadingUnit (chars : List Char) : String × List Char :=
  match chars with
  | c :: rest =>
      let isDigit := c.toNat ≥ 48 ∧ c.toNat ≤ 57
      if isDigit ∨ c == '.' then
        ("", chars)
      else
        let (u, tl) := leadingUnit rest
        (String.singleton c ++ u, tl)
  | [] => ("", chars)

/-- One `[digits][.digits]unit` term of a Go duration, accumulated into `acc` (a running
    positive-magnitude nanosecond total). `fuel` bounds the number of terms by the input
    length (each term consumes ≥ 1 char). Returns `none` on any malformed term (no digits,
    missing/unknown unit) or on int64 overflow. The fractional part contributes
    `⌊frac · unit / 10^fracDigits⌋` — computed EXACTLY (integer division), where Go uses a
    float64 approximation; the exact value is spec-correct (a duration is an exact integer
    nanosecond count) and any Go-float divergence is Go's artifact. -/
def parseDurationTerms (fuel : Nat) (acc : Int) : List Char → Option Int
  | [] => some acc
  | chars@(c :: _) =>
      match fuel with
      | 0 => none
      | fuel + 1 =>
          -- A term must start with a digit or a dot.
          if ¬ ((c.toNat ≥ 48 ∧ c.toNat ≤ 57) ∨ c == '.') then none
          else
            let (intPart, intDigits, afterInt) := leadingDigits chars
            let (fracPart, fracDigits, afterFrac) :=
              match afterInt with
              | '.' :: rest =>
                  let (f, n, tl) := leadingDigits rest
                  (f, n, tl)
              | _ => (0, 0, afterInt)
            -- At least one digit somewhere (`pre || post` in Go).
            if intDigits == 0 ∧ fracDigits == 0 then none
            else
              let (unitStr, afterUnit) := leadingUnit afterFrac
              match durationUnit? unitStr with
              | none => none
              | some unit =>
                  let whole := intPart * unit
                  let frac :=
                    if fracDigits == 0 then 0
                    else (fracPart * unit) / (10 ^ fracDigits)
                  let acc := acc + whole + frac
                  if acc > durationMaxMag then none
                  else parseDurationTerms fuel acc afterUnit

/-- Parse a Go duration string to its exact int64 nanosecond value (`time.ParseDuration`).
    Handles an optional leading `+`/`-`, the special bare `"0"`, repeated `[digits][.digits]unit`
    terms, and int64 overflow (⇒ `none`). `none` iff cue errors. -/
def parseGoDuration (s : String) : Option Int :=
  let chars := s.toList
  let (neg, rest) :=
    match chars with
    | '-' :: t => (true, t)
    | '+' :: t => (false, t)
    | _ => (false, chars)
  -- Special case: the whole (post-sign) input is exactly "0".
  if rest == ['0'] then some 0
  else if rest.isEmpty then none
  else
    match parseDurationTerms (rest.length + 1) 0 rest with
    | none => none
    | some mag => some (if neg then -mag else mag)

/-- Whether `s` is a valid Go duration (`time.Duration` validator). -/
def isValidDuration (s : String) : Bool := (parseGoDuration s).isSome

/-- Whether `y` is a Gregorian leap year. -/
def isLeapYear (y : Nat) : Bool :=
  (y % 4 == 0 ∧ y % 100 ≠ 0) ∨ y % 400 == 0

/-- Days in month `m` (1–12) of year `y`; `0` for an out-of-range month. -/
def daysInMonth (y m : Nat) : Nat :=
  match m with
  | 1 => 31
  | 2 => if isLeapYear y then 29 else 28
  | 3 => 31
  | 4 => 30
  | 5 => 31
  | 6 => 30
  | 7 => 31
  | 8 => 31
  | 9 => 30
  | 10 => 31
  | 11 => 30
  | 12 => 31
  | _ => 0

/-- Read exactly `n` decimal digits, returning their value and the remainder; `none` if
    fewer than `n` digits are available. Structural on `n`, hence total. -/
def readDigits (n : Nat) (chars : List Char) : Option (Nat × List Char) :=
  match n with
  | 0 => some (0, chars)
  | n + 1 =>
      match chars with
      | c :: rest =>
          if c.toNat ≥ 48 ∧ c.toNat ≤ 57 then
            match readDigits n rest with
            | some (v, tl) => some ((c.toNat - 48) * (10 ^ n) + v, tl)
            | none => none
          else none
      | [] => none

/-- Consume the single literal character `c`; `none` on mismatch. -/
def expectChar (c : Char) : List Char → Option (List Char)
  | d :: rest => if c == d then some rest else none
  | [] => none

/-- Validate the offset tail of an RFC3339 timestamp: either `Z`, or a sign followed by
    `HH:MM` (two digits, colon, two digits — Go does NOT range-check the offset, so any
    two-digit values pass). Must consume the whole remainder. -/
def validRFC3339Offset : List Char → Bool
  | ['Z'] => true
  | s :: rest =>
      if s == '+' ∨ s == '-' then
        match readDigits 2 rest with
        | some (_, afterH) =>
            match expectChar ':' afterH with
            | some afterColon =>
                match readDigits 2 afterColon with
                | some (_, []) => true
                | _ => false
            | none => false
        | none => false
      else false
  | [] => false

/-- Validate an RFC3339 timestamp string (`time.Time` / `time.Format(RFC3339|Nano)`):
    `YYYY-MM-DDTHH:MM:SS[.fraction](Z|±HH:MM)`, structural with calendar-aware ranges —
    month 1–12, day 1–daysInMonth (leap-year aware, so `2019-02-29` is rejected but
    `2020-02-29` accepted), hour 0–23, minute/second 0–59. The `T` and `Z` are uppercase.
    Fraction is `.` + one or more digits (any count). Mirrors Go's `time.Parse(RFC3339, s)`,
    which cue's `time.Time` uses. -/
def isValidRFC3339 (s : String) : Bool :=
  match readDigits 4 s.toList with
  | none => false
  | some (year, r0) =>
    match expectChar '-' r0 with
    | none => false
    | some r1 =>
      match readDigits 2 r1 with
      | none => false
      | some (month, r2) =>
        match expectChar '-' r2 with
        | none => false
        | some r3 =>
          match readDigits 2 r3 with
          | none => false
          | some (day, r4) =>
            match expectChar 'T' r4 with
            | none => false
            | some r5 =>
              match readDigits 2 r5 with
              | none => false
              | some (hour, r6) =>
                match expectChar ':' r6 with
                | none => false
                | some r7 =>
                  match readDigits 2 r7 with
                  | none => false
                  | some (minute, r8) =>
                    match expectChar ':' r8 with
                    | none => false
                    | some r9 =>
                      match readDigits 2 r9 with
                      | none => false
                      | some (second, r10) =>
                        -- Optional fractional seconds: '.' then ≥1 digit.
                        let afterFrac :=
                          match r10 with
                          | '.' :: rest =>
                              let (_, n, tl) := leadingDigits rest
                              if n == 0 then none else some tl
                          | _ => some r10
                        match afterFrac with
                        | none => false
                        | some rest =>
                          month ≥ 1 ∧ month ≤ 12 ∧
                          day ≥ 1 ∧ day ≤ daysInMonth year month ∧
                          hour ≤ 23 ∧ minute ≤ 59 ∧ second ≤ 59 ∧
                          validRFC3339Offset rest

/-- The `time.RFC3339` layout constant string. -/
def rfc3339Layout : String := "2006-01-02T15:04:05Z07:00"

/-- The `time.RFC3339Nano` layout constant string. -/
def rfc3339NanoLayout : String := "2006-01-02T15:04:05.999999999Z07:00"

/-- Whether `layout` is one of the two RFC3339 layouts Kue validates exactly. Any other Go
    reference layout is DEFERRED (`unsupportedBuiltin`) — arbitrary custom `Format` layouts
    need Go's full format machinery (see `docs/spec/cue-spec-gaps.md`). -/
def isRFC3339Layout (layout : String) : Bool :=
  layout == rfc3339Layout || layout == rfc3339NanoLayout

/-- Whether `value` satisfies the string-format validator `fmt`. The single predicate
    behind every `time.*` string validator's meet against a concrete string. -/
def stringFormatValid : StringFormat → String → Bool
  | .duration => isValidDuration
  | .rfc3339 => isValidRFC3339

end Kue
