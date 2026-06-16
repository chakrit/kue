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

def formatFiniteDecimal (value : DecimalValue) (forceFloat : Bool) : String :=
  let trimmed := trimDecimalZerosWith value.numerator value.scale
  let sign := if trimmed.numerator < 0 then "-" else ""
  let abs := decimalIntAbsNat trimmed.numerator
  match trimmed.scale with
  | 0 =>
      let whole := sign ++ toString abs
      if forceFloat then whole ++ ".0" else whole
  | scale =>
      let divisor := evalPow10 scale
      let whole := abs / divisor
      let fraction := abs % divisor
      sign ++ toString whole ++ "." ++ leftPadZeros scale (toString fraction)

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
