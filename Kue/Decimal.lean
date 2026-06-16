import Kue.Value

namespace Kue

structure DecimalValue where
  numerator : Int
  scale : Nat
deriving Repr, BEq

def evalPow10 : Nat -> Nat
  | 0 => 1
  | exponent + 1 => 10 * evalPow10 exponent

def evalDigitValue? (value : Char) : Option Nat :=
  if '0'.toNat <= value.toNat && value.toNat <= '9'.toNat then
    some (value.toNat - '0'.toNat)
  else
    none

def parseEvalDigitsWithCount : List Char -> Nat -> Nat -> Option (Nat × Nat × List Char)
  | [], _, 0 => none
  | [], value, count => some (value, count, [])
  | char :: chars, value, count =>
      match evalDigitValue? char with
      | some digit => parseEvalDigitsWithCount chars (value * 10 + digit) (count + 1)
      | none =>
          if count == 0 then
            none
          else
            some (value, count, char :: chars)

def parseEvalDigits (chars : List Char) : Option (Nat × Nat × List Char) :=
  parseEvalDigitsWithCount chars 0 0

def parseDecimalMantissa (chars : List Char) : Option (DecimalValue × List Char) :=
  match parseEvalDigits chars with
  | none => none
  | some (whole, _, '.' :: rest) =>
      match parseEvalDigits rest with
      | none => none
      | some (fraction, fractionCount, rest) =>
          let scale := evalPow10 fractionCount
          some ({ numerator := Int.ofNat (whole * scale + fraction), scale := fractionCount }, rest)
  | some (whole, _, rest) => some ({ numerator := Int.ofNat whole, scale := 0 }, rest)

def parseDecimalExponent : List Char -> Option (Int × List Char)
  | '+' :: rest =>
      match parseEvalDigits rest with
      | some (exponent, _, rest) => some (Int.ofNat exponent, rest)
      | none => none
  | '-' :: rest =>
      match parseEvalDigits rest with
      | some (exponent, _, rest) => some (-(Int.ofNat exponent), rest)
      | none => none
  | chars =>
      match parseEvalDigits chars with
      | some (exponent, _, rest) => some (Int.ofNat exponent, rest)
      | none => none

def applyDecimalExponent (value : DecimalValue) (exponent : Int) : DecimalValue :=
  if exponent < 0 then
    { value with scale := value.scale + (-exponent).toNat }
  else
    let shift := exponent.toNat
    if value.scale <= shift then
      {
        numerator := value.numerator * Int.ofNat (evalPow10 (shift - value.scale)),
        scale := 0
      }
    else
      { value with scale := value.scale - shift }

def applyDecimalSign (negative : Bool) (value : DecimalValue) : DecimalValue :=
  if negative then
    { value with numerator := -value.numerator }
  else
    value

def parseUnsignedDecimalText (negative : Bool) (chars : List Char) : Option DecimalValue :=
  match parseDecimalMantissa chars with
  | none => none
  | some (mantissa, rest) =>
      let signed := applyDecimalSign negative mantissa
      match rest with
      | [] => some signed
      | 'e' :: rest =>
          match parseDecimalExponent rest with
          | some (exponent, []) => some (applyDecimalExponent signed exponent)
          | _ => none
      | 'E' :: rest =>
          match parseDecimalExponent rest with
          | some (exponent, []) => some (applyDecimalExponent signed exponent)
          | _ => none
      | _ => none

def parseDecimalText (value : String) : Option DecimalValue :=
  match value.toList with
  | '-' :: rest => parseUnsignedDecimalText true rest
  | '+' :: rest => parseUnsignedDecimalText false rest
  | chars => parseUnsignedDecimalText false chars

def decimalFromPrim? : Prim -> Option DecimalValue
  | .int value => some { numerator := value, scale := 0 }
  | .float value => parseDecimalText value
  | _ => none

def maxNat (left right : Nat) : Nat :=
  if left <= right then right else left

def scaleDecimalNumerator (targetScale : Nat) (value : DecimalValue) : Int :=
  value.numerator * Int.ofNat (evalPow10 (targetScale - value.scale))

def addDecimalValues (left right : DecimalValue) : DecimalValue :=
  let scale := maxNat left.scale right.scale
  {
    numerator := scaleDecimalNumerator scale left + scaleDecimalNumerator scale right,
    scale := scale
  }

def subDecimalValues (left right : DecimalValue) : DecimalValue :=
  let scale := maxNat left.scale right.scale
  {
    numerator := scaleDecimalNumerator scale left - scaleDecimalNumerator scale right,
    scale := scale
  }

def decimalCompareNumerators (left right : DecimalValue) : Int × Int :=
  let scale := maxNat left.scale right.scale
  (scaleDecimalNumerator scale left, scaleDecimalNumerator scale right)

def decimalEqValues (left right : DecimalValue) : Bool :=
  let compared := decimalCompareNumerators left right
  compared.fst == compared.snd

def decimalLtValues (left right : DecimalValue) : Bool :=
  let compared := decimalCompareNumerators left right
  compared.fst < compared.snd

def trimDecimalZerosWith : Int -> Nat -> DecimalValue
  | numerator, 0 => { numerator := numerator, scale := 0 }
  | numerator, scale + 1 =>
      if numerator % 10 == 0 then
        trimDecimalZerosWith (numerator / 10) scale
      else
        { numerator := numerator, scale := scale + 1 }

def decimalIntAbsNat (value : Int) : Nat :=
  if value < 0 then
    (-value).toNat
  else
    value.toNat

def repeatZeros : Nat -> String
  | 0 => ""
  | count + 1 => "0" ++ repeatZeros count

def leftPadZeros (width : Nat) (value : String) : String :=
  repeatZeros (width - value.toList.length) ++ value

def formatDecimalAtScale (value : DecimalValue) (forceFloat : Bool) : String :=
  let sign := if value.numerator < 0 then "-" else ""
  let abs := decimalIntAbsNat value.numerator
  match value.scale with
  | 0 =>
      let whole := sign ++ toString abs
      if forceFloat then whole ++ ".0" else whole
  | scale =>
      let divisor := evalPow10 scale
      let whole := abs / divisor
      let fraction := abs % divisor
      sign ++ toString whole ++ "." ++ leftPadZeros scale (toString fraction)

def formatFiniteDecimal (value : DecimalValue) (forceFloat : Bool) : String :=
  formatDecimalAtScale (trimDecimalZerosWith value.numerator value.scale) forceFloat

/-- Render a decimal as CUE renders a numeric *builtin* result: collapse to an
    integer when the trimmed value is whole (`6.0 ⇒ 6`, `list.Sum([1.0,2.0,3.0])`),
    otherwise a float at minimal scale (`1.5`). This differs from literal float
    arithmetic, which preserves the operand scale verbatim — CUE's `list`/numeric
    builtins reduce integral results back to `int`-kind. -/
def collapseDecimalToValue (value : DecimalValue) : Value :=
  let trimmed := trimDecimalZerosWith value.numerator value.scale
  if trimmed.scale == 0 then
    .prim (.int trimmed.numerator)
  else
    .prim (.float (formatDecimalAtScale trimmed false))

/-- Multiplication is exact: numerators multiply, scales add. CUE preserves the
    summed scale verbatim (no trailing-zero trimming): `1.0 * 1.0 = 1.00`. -/
def mulDecimalValues (left right : DecimalValue) : DecimalValue :=
  {
    numerator := left.numerator * right.numerator,
    scale := left.scale + right.scale
  }

/-- 34 significant digits, matching CUE's apd context for `/`. -/
def divisionSigDigits : Nat :=
  34

/-- Fuel-bounded inner loop of `divisionDigits`. Recurses on `remainder` (modular,
    not structurally decreasing), so it carries an explicit `fuel : Nat` to stay
    total. Sound only when `fuel` cannot run out before the natural termination
    condition (`remainder = 0` or over-budget) fires — see `divisionDigitsFuel`. -/
def divisionDigitsLoop (den : Nat) :
    Nat -> Nat -> Nat -> Bool -> List Nat -> List Nat × Bool
  | 0, _, _, _, acc => (acc.reverse, false)
  | fuel + 1, remainder, sigEmitted, sawSignificant, acc =>
      if remainder == 0 then
        (acc.reverse, true)
      else if sigEmitted > divisionSigDigits then
        (acc.reverse, false)
      else
        let scaled := remainder * 10
        let digit := scaled / den
        let nextSaw := sawSignificant || digit != 0
        let nextEmitted := if nextSaw then sigEmitted + 1 else sigEmitted
        divisionDigitsLoop den fuel (scaled % den) nextEmitted nextSaw (digit :: acc)

/-- Sound fuel ceiling for `divisionDigitsLoop`. The loop terminates naturally when
    `sigEmitted > divisionSigDigits`, which takes at most `divisionSigDigits + 1`
    significant-digit emissions. The only non-emitting iterations are leading
    fractional zeros (`!sawSignificant`), and those are bounded by the digit count
    of `den`: each leading-zero step multiplies the remainder by 10, so after that
    many steps `remainder * 10^k ≥ den` and the first significant digit fires. Hence
    `divisionSigDigits + 1 + <den digit count>` iterations always reach the over-
    budget exit, and the fuel can never be exhausted first — making this total form
    behaviorally identical to the prior `partial` one on all reachable inputs. -/
def divisionDigitsFuel (den : Nat) : Nat :=
  divisionSigDigits + 1 + (toString den).toList.length

/-- Decimal long division of `num / den` (both positive) producing the digit
    string and the position of the decimal point (number of integer digits).
    Generates `divisionSigDigits + 1` significant digits — the extra guard digit
    drives rounding. Leading zeros before the first significant digit do not count
    against the budget. Returns `(digits, intDigitCount, terminated)`. -/
def divisionDigits (num den : Nat) : List Nat × Nat × Bool :=
  let intPart := num / den
  let intDigits := (toString intPart).toList.length
  let intDigitCount := if intPart == 0 then 0 else intDigits
  let intList := if intPart == 0 then [] else (toString intPart).toList.map (fun c => c.toNat - '0'.toNat)
  let intSig := if intPart == 0 then 0 else intDigits
  let (fracDigits, terminated) :=
    divisionDigitsLoop den (divisionDigitsFuel den) (num % den) intSig (intPart != 0) []
  (intList ++ fracDigits, intDigitCount, terminated)

/-- Increment the least-significant digit of a little-endian digit list, carrying
    past 9s. Structurally recursive on the list, hence total. Returns the bumped
    little-endian list and a carry-out flag (a full run of 9s overflows). -/
def roundDigitsBump : List Nat -> List Nat × Bool
  | [] => ([], true)
  | d :: rest =>
      if d == 9 then
        let (bumped, carry) := roundDigitsBump rest
        (0 :: bumped, carry)
      else
        ((d + 1) :: rest, false)

/-- Round a big-endian digit list to `keep` significant digits using the guard
    digit at position `keep` (round-half-up; repeating expansions never tie).
    `sigStart` is the index of the first significant digit. Returns the rounded
    digit list and a carry-out flag (overflow grew the integer part). -/
def roundDigits (digits : List Nat) (sigStart keep : Nat) : List Nat × Bool :=
  let cutoff := sigStart + keep
  if digits.length <= cutoff then
    (digits, false)
  else
    let kept := digits.take cutoff
    let guard := digits.getD cutoff 0
    if guard < 5 then
      (kept, false)
    else
      let (bumpedRev, carry) := roundDigitsBump kept.reverse
      (bumpedRev.reverse, carry)

def digitsToString : List Nat -> String
  | [] => ""
  | d :: rest => toString d ++ digitsToString rest

/-- Format `num / den` (signed) as CUE renders `/`: always a float, exact when the
    expansion terminates, else 34 significant digits round-half-up. Returns `none`
    when `den == 0` so the caller can raise divisionByZero. -/
def divideDecimalRational? (num den : Int) : Option String :=
  if den == 0 then
    none
  else
    let negative := (num < 0) != (den < 0)
    let n := decimalIntAbsNat num
    let d := decimalIntAbsNat den
    let (digits, intDigitCount, _) := divisionDigits n d
    let sigStart := if intDigitCount == 0 then
        digits.takeWhile (· == 0) |>.length
      else 0
    let (rounded, carry) := roundDigits digits sigStart divisionSigDigits
    let (final, intCount) := if carry then (1 :: rounded, intDigitCount + 1) else (rounded, intDigitCount)
    let intCount := if intCount == 0 then 0 else intCount
    let intStr := digitsToString (final.take intCount)
    let fracStr := digitsToString (final.drop intCount)
    let sign := if negative then "-" else ""
    let wholePart := if intStr == "" then "0" else intStr
    let body := if fracStr == "" then wholePart ++ ".0" else wholePart ++ "." ++ fracStr
    some (sign ++ body)

/-- Multiplication of two decimal primitives, always yielding a float. The summed
    scale is preserved verbatim (no trailing-zero trim): `1.0 * 1.0 = 1.00`. -/
def evalDecimalMultiply? (left right : Prim) : Option Prim :=
  match decimalFromPrim? left, decimalFromPrim? right with
  | some left, some right =>
      some (.float (formatDecimalAtScale (mulDecimalValues left right) true))
  | _, _ => none

/-- Outcome of dividing two primitives: either an operand was not numeric, the
    divisor was zero, or division succeeded with a rendered float. A named sum so
    the three cases are unrepresentable as anything else and read clearly at the
    callsite. -/
inductive DecimalDivideResult where
  | nonNumeric
  | divByZero
  | ok (text : String)
deriving Repr, BEq

/-- Division of two decimal primitives, always yielding a float. `(n1/10^s1) /
    (n2/10^s2) = (n1 * 10^s2) / (n2 * 10^s1)`. -/
def evalDecimalDivide? (left right : Prim) : DecimalDivideResult :=
  match decimalFromPrim? left, decimalFromPrim? right with
  | some left, some right =>
      let num := left.numerator * Int.ofNat (evalPow10 right.scale)
      let den := right.numerator * Int.ofNat (evalPow10 left.scale)
      match divideDecimalRational? num den with
      | some text => .ok text
      | none => .divByZero
  | _, _ => .nonNumeric

/-- Exact-rational mean of a decimal `sum` over `count` elements. The value is
    `sum.numerator / (10^sum.scale * count)`; when that divides evenly the result
    collapses to an integer (`list.Avg([1,2,3]) = 2`), otherwise it is rendered as a
    float at 34 significant digits round-half-up via the shared division renderer
    (`list.Avg([1,1,2]) = 1.333…333`). `count == 0` (empty list) yields `none`. -/
def avgDecimalValue? (sum : DecimalValue) (count : Nat) : Option Value :=
  if count == 0 then
    none
  else
    let den := Int.ofNat (evalPow10 sum.scale * count)
    if sum.numerator % den == 0 then
      some (.prim (.int (sum.numerator / den)))
    else
      (divideDecimalRational? sum.numerator den).map (fun text => .prim (.float text))

def evalDecimalBinary?
    (op : DecimalValue -> DecimalValue -> DecimalValue)
    (left right : Prim) : Option Prim :=
  match decimalFromPrim? left, decimalFromPrim? right with
  | some left, some right => some (.float (formatFiniteDecimal (op left right) true))
  | _, _ => none

def evalDecimalCompare?
    (op : DecimalValue -> DecimalValue -> Bool)
    (left right : Prim) : Option Bool :=
  match decimalFromPrim? left, decimalFromPrim? right with
  | some left, some right => some (op left right)
  | _, _ => none

end Kue
