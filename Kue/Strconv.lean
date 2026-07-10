import Kue.Value

namespace Kue

/-! # `strconv` standard-library primitives

Pure `String`/`Int`/`Bool` conversions mirroring cue's `strconv` package (itself a mirror of
Go's). Every function is total: a non-parseable input or out-of-range value returns a
`.bottomWith` carrying the matching `strconv*` reason, never a wrong value.

**Base contract.** `FormatInt`/`FormatUint`/`ParseInt`/`ParseUint` accept base `2..36` (plus `0`
for the parse auto-detect). cue leaks `math/big`'s wider `2..62`; Kue follows Go's documented
`2..36` (see `docs/spec/cue-divergences.md`). All numeric parsing is arbitrary-precision (cue's
`Atoi("99999999999999999999999")` succeeds), matching Kue's exact `Int` core. -/

/-- The digit value of `c` in `base`, case-insensitive (`'F'`/`'f'` = 15). `none` when `c` is
    not a digit `< base`. Letters map `a/A → 10 … z/Z → 35`. -/
def strconvDigitVal? (base : Nat) (c : Char) : Option Nat :=
  let n := c.toNat
  let d :=
    if n ≥ 48 ∧ n ≤ 57 then some (n - 48)
    else if n ≥ 65 ∧ n ≤ 90 then some (n - 65 + 10)
    else if n ≥ 97 ∧ n ≤ 122 then some (n - 97 + 10)
    else none
  match d with
  | some v => if v < base then some v else none
  | none => none

/-- The lowercase base-36 digit character for value `d` (`0..9`, then `a..z`). Domain: `d < 36`.
    Used by `FormatInt`/`FormatUint`. -/
def strconvDigitChar (d : Nat) : Char :=
  if d < 10 then Char.ofNat (48 + d) else Char.ofNat (97 + (d - 10))

/-- Render `n` in `base` (fuel-bounded structural recursion; `fuel := n` bounds the digit count
    for `n ≥ 1`, `base ≥ 2`). Yields `""` for `n = 0`; the caller emits `"0"` at top level. -/
def strconvFormatMagAux (base : Nat) : Nat → Nat → String
  | 0, _ => ""
  | _, 0 => ""
  | Nat.succ fuel, n =>
      if n < base then String.singleton (strconvDigitChar n)
      else strconvFormatMagAux base fuel (n / base) ++ String.singleton (strconvDigitChar (n % base))

/-- `n` rendered in `base` (`2..36`), `"0"` for zero. -/
def strconvFormatMag (base : Nat) (n : Nat) : String :=
  if n == 0 then "0" else strconvFormatMagAux base n n

/-- `strconv.FormatInt(i, base)` / `strconv.FormatUint(i, base)` — identical in cue (both render
    the SIGNED value via `math/big`, so a negative `FormatUint` prints `-…`). Base outside `2..36`
    is `invalid base`. -/
def strconvFormatInt (i : Int) (base : Int) : Value :=
  if base < 2 ∨ base > 36 then
    .bottomWith [.strconvInvalidBase base]
  else
    let digits := strconvFormatMag base.toNat i.natAbs
    .prim (.string (if i < 0 then "-" ++ digits else digits))

/-- Whether `c` counts as a digit for Go's `underscoreOK` placement scan: `0..9`, plus `a..f`
    / `A..F` when a hex prefix is in effect. (Placement only — real digit validity is checked in
    `strconvParseMag`.) -/
def strconvUnderscoreDigit (hex : Bool) (c : Char) : Bool :=
  let n := c.toNat
  (n ≥ 48 ∧ n ≤ 57) ∨ (hex ∧ ((n ≥ 65 ∧ n ≤ 70) ∨ (n ≥ 97 ∧ n ≤ 102)))

/-- Go's `underscoreOK` scan over the post-sign, post-prefix tail. `saw` tracks the prior
    character class: `1` digit/prefix, `2` underscore, `3` other, `0` start. An underscore is legal
    only between digits (or right after a base prefix); a trailing underscore is illegal. -/
def strconvUnderscoreScan (hex : Bool) : Nat → List Char → Bool
  | saw, [] => saw ≠ 2
  | saw, c :: cs =>
      if strconvUnderscoreDigit hex c then strconvUnderscoreScan hex 1 cs
      else if c.toNat == 95 then
        if saw == 1 then strconvUnderscoreScan hex 2 cs else false
      else if saw == 2 then false
      else strconvUnderscoreScan hex 3 cs

/-- Go's `underscoreOK`: every `_` in a base-0 literal must separate successive digits (or follow
    the base prefix). Applied ONLY to base-0 `ParseInt`/`ParseUint`; other bases reject `_` as a
    plain non-digit. Strips an optional sign, seeds the scan with the prefix digit-state. -/
def strconvUnderscoreOK (chars : List Char) : Bool :=
  let s := match chars with
    | c :: t => if c.toNat == 43 ∨ c.toNat == 45 then t else chars
    | [] => chars
  match s with
  | c0 :: c1 :: rest =>
      let hexPfx := c0.toNat == 48 ∧ (c1.toNat == 120 ∨ c1.toNat == 88)
      let binPfx := c0.toNat == 48 ∧ (c1.toNat == 98 ∨ c1.toNat == 66)
      let octPfx := c0.toNat == 48 ∧ (c1.toNat == 111 ∨ c1.toNat == 79)
      if hexPfx then strconvUnderscoreScan true 1 rest
      else if binPfx ∨ octPfx then strconvUnderscoreScan false 1 rest
      else strconvUnderscoreScan false 0 s
  | _ => strconvUnderscoreScan false 0 s

/-- Accumulate `digits` into a magnitude, base `base`; `_` is skipped iff `base0`. `none` on the
    first character that is not a valid digit `< base`. -/
def strconvParseMag (base : Nat) (base0 : Bool) (digits : List Char) : Option Nat :=
  digits.foldl (fun acc c =>
    match acc with
    | none => none
    | some n =>
        if base0 ∧ c.toNat == 95 then some n
        else match strconvDigitVal? base c with
          | some d => some (n * base + d)
          | none => none) (some 0)

/-- Whether `v` fits the range `bitSize` selects. `bitSize = 0` is unbounded (cue is
    arbitrary-precision; unsigned still rejects negatives); `bitSize < 0` admits nothing; a
    signed `bitSize = b > 0` bounds `[-2^(b-1), 2^(b-1)-1]`, unsigned `[0, 2^b-1]`. -/
def strconvRangeOk (signed : Bool) (bits : Int) (v : Int) : Bool :=
  if bits == 0 then (if signed then true else v ≥ 0)
  else if bits < 0 then false
  else
    let bn := bits.toNat
    if signed then
      let hi := (2 : Int) ^ (bn - 1)
      (- hi) ≤ v ∧ v ≤ hi - 1
    else
      let hi := (2 : Int) ^ bn
      0 ≤ v ∧ v ≤ hi - 1

/-- Core of `strconv.ParseInt`/`ParseUint`/`Atoi`. `signed` selects the range family. Handles an
    optional `+`/`-` sign, base-0 prefix auto-detect (`0x`/`0b`/`0o`/leading-`0` octal) with
    underscore separators, case-insensitive digits, and the `bitSize` range check. -/
def strconvParse (signed : Bool) (input : String) (base : Int) (bits : Int) : Value :=
  if base ≠ 0 ∧ (base < 2 ∨ base > 36) then
    .bottomWith [.strconvInvalidBase base]
  else
    let chars := input.toList
    match chars with
    | [] => .bottomWith [.strconvSyntax input]
    | _ =>
      if base == 0 ∧ ¬ strconvUnderscoreOK chars then
        .bottomWith [.strconvSyntax input]
      else
        let (neg, rest) := match chars with
          | '+' :: t => (false, t)
          | '-' :: t => (true, t)
          | _ => (false, chars)
        match rest with
        | [] => .bottomWith [.strconvSyntax input]
        | _ =>
          let (effBase, digits) : Nat × List Char :=
            if base ≠ 0 then (base.toNat, rest)
            else
              match rest with
              | '0' :: c :: d :: tl =>
                  let cn := c.toNat
                  if cn == 120 ∨ cn == 88 then (16, d :: tl)
                  else if cn == 98 ∨ cn == 66 then (2, d :: tl)
                  else if cn == 111 ∨ cn == 79 then (8, d :: tl)
                  else (8, rest)
              | '0' :: _ => (8, rest)
              | _ => (10, rest)
          match strconvParseMag effBase (base == 0) digits with
          | none => .bottomWith [.strconvSyntax input]
          | some mag =>
              let v : Int := if neg then -(Int.ofNat mag) else Int.ofNat mag
              if strconvRangeOk signed bits v then .prim (.int v)
              else .bottomWith [.strconvRange input]

/-- `strconv.Atoi(s)` — signed base-10 parse, arbitrary precision (no `bitSize` bound). -/
def strconvAtoi (input : String) : Value := strconvParse true input 10 0

/-- `strconv.ParseBool(s)` — Go's accepted set: `1 t T TRUE true True` / `0 f F FALSE false False`;
    anything else is `invalid syntax`. -/
def strconvParseBool (input : String) : Value :=
  match input with
  | "1" | "t" | "T" | "TRUE" | "true" | "True" => .prim (.bool true)
  | "0" | "f" | "F" | "FALSE" | "false" | "False" => .prim (.bool false)
  | _ => .bottomWith [.strconvSyntax input]

end Kue
