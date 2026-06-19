import Kue.Value
import Kue.Regex

namespace Kue

def orderFuel : Nat :=
  100

def findField (label : String) : List Field -> Option Field
  | [] => none
  | field :: fields =>
      if Field.label field = label then
        some field
      else
        findField label fields

def kindSubsumesPrim (kind : Kind) (prim : Prim) : Bool :=
  kind == Prim.kind prim || (kind == .number && (Prim.kind prim == .int || Prim.kind prim == .float))

def kindSubsumesKind (expected actual : Kind) : Bool :=
  expected == actual || (expected == .number && (actual == .int || actual == .float))

/-- Does the `expected` bound subsume the `actual` bound (every value the actual admits, the
    expected admits too)? Only same-comparator bounds are comparable here, matching the
    pre-fold arms: a looser lower bound (smaller limit) subsumes a tighter one; a looser
    upper bound (larger limit) subsumes a tighter one. Cross-comparator pairs are not
    subsumption-related (`false`). -/
def boundSubsumesBound (expectedBound : DecimalValue) (expectedKind : BoundKind)
    (actualBound : DecimalValue) (actualKind : BoundKind) : Bool :=
  if expectedKind != actualKind then false
  else if expectedKind.lower then decimalLeValues expectedBound actualBound
  else decimalLeValues actualBound expectedBound

mutual
  def fieldSubsumesWithFuel (fuel : Nat) (expected actual : Field) : Bool :=
    Field.fieldClass expected == Field.fieldClass actual
      && subsumesWithFuel fuel (Field.value expected) (Field.value actual)

  def allExpectedFieldsSubsumedWithFuel
      (fuel : Nat)
      (expectedFields actualFields : List Field) : Bool :=
    expectedFields.all fun expectedField =>
      match findField (Field.label expectedField) actualFields with
      | some actualField => fieldSubsumesWithFuel fuel expectedField actualField
      | none => false

  def noExtraActualFields (expectedFields actualFields : List Field) : Bool :=
    actualFields.all fun actualField =>
      match findField (Field.label actualField) expectedFields with
      | some _ => true
      | none => Field.ignoresClosedness actualField

  def structSubsumesWithFuel
      (fuel : Nat)
      (expectedFields actualFields : List Field)
      (expectedOpen : Bool) : Bool :=
    let expectedSatisfied := allExpectedFieldsSubsumedWithFuel fuel expectedFields actualFields
    let noExtra := expectedOpen || noExtraActualFields expectedFields actualFields
    expectedSatisfied && noExtra

  def extraFieldsSatisfyTailWithFuel
      (fuel : Nat)
      (expectedFields actualFields : List Field)
      (tail : Value) : Bool :=
    actualFields.all fun actualField =>
      match findField (Field.label actualField) expectedFields with
      | some _ => true
      | none => subsumesWithFuel fuel tail (Field.value actualField)

  def structTailSubsumesWithFuel
      (fuel : Nat)
      (expectedFields actualFields : List Field)
      (tail : Value) : Bool :=
    let expectedSatisfied := allExpectedFieldsSubsumedWithFuel fuel expectedFields actualFields
    let extraSatisfied := extraFieldsSatisfyTailWithFuel fuel expectedFields actualFields tail
    expectedSatisfied && extraSatisfied

  def labelMatchesPatternWithFuel (fuel : Nat) (labelPattern : Value) (label : String) : Bool :=
    subsumesWithFuel fuel labelPattern (.prim (.string label))

  def regularFieldsSatisfyPatternWithFuel
      (fuel : Nat)
      (fields : List Field)
      (labelPattern constraint : Value) : Bool :=
    fields.all fun field =>
      let isRegular := Field.fieldClass field == .regular
      let labelMatches := labelMatchesPatternWithFuel fuel labelPattern (Field.label field)
      if isRegular && labelMatches then
        subsumesWithFuel fuel constraint (Field.value field)
      else
        true

  def regularFieldsSatisfyPatternsWithFuel
      (fuel : Nat)
      (fields : List Field)
      (patterns : List (Value × Value)) : Bool :=
    patterns.all fun pattern =>
      regularFieldsSatisfyPatternWithFuel fuel fields pattern.fst pattern.snd

  def fieldAllowedByPatternWithFuel
      (fuel : Nat)
      (expectedFields : List Field)
      (labelPattern : Value)
      (field : Field) : Bool :=
    (findField (Field.label field) expectedFields).isSome
      || Field.ignoresClosedness field
      || (Field.fieldClass field == .regular
        && labelMatchesPatternWithFuel fuel labelPattern (Field.label field))

  def fieldsAllowedByPatternWithFuel
      (fuel : Nat)
      (expectedFields actualFields : List Field)
      (labelPattern : Value) : Bool :=
    actualFields.all (fieldAllowedByPatternWithFuel fuel expectedFields labelPattern)

  def fieldAllowedByPatternsWithFuel
      (fuel : Nat)
      (expectedFields : List Field)
      (patterns : List (Value × Value))
      (field : Field) : Bool :=
    (findField (Field.label field) expectedFields).isSome
      || Field.ignoresClosedness field
      || (Field.fieldClass field == .regular
        && patterns.any fun pattern => labelMatchesPatternWithFuel fuel pattern.fst (Field.label field))

  def fieldsAllowedByPatternsWithFuel
      (fuel : Nat)
      (expectedFields actualFields : List Field)
      (patterns : List (Value × Value)) : Bool :=
    actualFields.all (fieldAllowedByPatternsWithFuel fuel expectedFields patterns)

  def structPatternSubsumesWithFuel
      (fuel : Nat)
      (expectedFields actualFields : List Field)
      (labelPattern constraint : Value)
      (open_ : Bool) : Bool :=
    let expectedSatisfied := allExpectedFieldsSubsumedWithFuel fuel expectedFields actualFields
    let patternSatisfied :=
      regularFieldsSatisfyPatternWithFuel fuel actualFields labelPattern constraint
    let closednessSatisfied :=
      open_ || fieldsAllowedByPatternWithFuel fuel expectedFields actualFields labelPattern
    expectedSatisfied && patternSatisfied && closednessSatisfied

  def structPatternsSubsumesWithFuel
      (fuel : Nat)
      (expectedFields actualFields : List Field)
      (patterns : List (Value × Value))
      (open_ : Bool) : Bool :=
    let expectedSatisfied := allExpectedFieldsSubsumedWithFuel fuel expectedFields actualFields
    let patternsSatisfied := regularFieldsSatisfyPatternsWithFuel fuel actualFields patterns
    let closednessSatisfied :=
      open_ || fieldsAllowedByPatternsWithFuel fuel expectedFields actualFields patterns
    expectedSatisfied && patternsSatisfied && closednessSatisfied

  def patternsSubsumeWithFuel
      (fuel : Nat)
      (expectedPatterns actualPatterns : List (Value × Value)) : Bool :=
    expectedPatterns.all fun expectedPattern =>
      actualPatterns.any fun actualPattern =>
        subsumesWithFuel fuel expectedPattern.fst actualPattern.fst
          && subsumesWithFuel fuel expectedPattern.snd actualPattern.snd

  def listSubsumesWithFuel (fuel : Nat) : List Value -> List Value -> Bool
    | [], [] => true
    | expected :: expectedItems, actual :: actualItems =>
        subsumesWithFuel fuel expected actual && listSubsumesWithFuel fuel expectedItems actualItems
    | _, _ => false

  def listTailSubsumesListWithFuel : Nat -> List Value -> Value -> List Value -> Bool
    | 0, _, _, _ => false
    | _ + 1, [], _, [] => true
    | _ + 1, _ :: _, _, [] => false
    | fuel + 1, [], tail, actual :: actualItems =>
        subsumesWithFuel fuel tail actual
          && listTailSubsumesListWithFuel fuel [] tail actualItems
    | fuel + 1, expected :: expectedItems, tail, actual :: actualItems =>
        subsumesWithFuel fuel expected actual
          && listTailSubsumesListWithFuel fuel expectedItems tail actualItems

  def allConstraintsSubsumeWithFuel (fuel : Nat) (constraints : List Value) (actual : Value) : Bool :=
    constraints.all fun constraint => subsumesWithFuel fuel constraint actual

  def disjSubsumesWithFuel (fuel : Nat) (alternatives : List (Mark × Value)) (actual : Value) : Bool :=
    alternatives.any fun alternative => subsumesWithFuel fuel alternative.snd actual

  /-- Merged `struct` subsumption, reproducing the legacy eight struct-family arms
      EXACTLY. Dispatch is on the EXPECTED side's tail/pattern shape, then the ACTUAL
      side's shape. Legacy ctor→`struct` mapping: `struct`/`structTail` carry no
      patterns (`structTail` carries a `some` tail); `structPattern`/`structPatterns`
      carry patterns and no tail; openness bools recover via `StructOpenness.isOpen`. -/
  def structNSubsumesWithFuel
      (fuel : Nat)
      (expectedFields : List Field) (expectedOpenness : StructOpenness)
      (expectedTail : Option Value) (expectedPatterns : List (Value × Value))
      (actualFields : List Field) (actualOpenness : StructOpenness)
      (actualTail : Option Value) (actualPatterns : List (Value × Value)) : Bool :=
    match expectedPatterns, expectedTail with
    | [], none =>
        match actualPatterns, actualTail with
        | [], none => structSubsumesWithFuel fuel expectedFields actualFields expectedOpenness.isOpen
        | _, _ => false
    | [], some tail =>
        match actualPatterns, actualTail with
        | [], none => structTailSubsumesWithFuel fuel expectedFields actualFields tail
        | [], some _ => structTailSubsumesWithFuel fuel expectedFields actualFields tail
        | _, _ => false
    | _ :: _, _ =>
        match actualPatterns with
        | [] =>
            match actualTail with
            | none =>
                structPatternsSubsumesWithFuel fuel
                  expectedFields actualFields expectedPatterns expectedOpenness.isOpen
            | some _ => false
        | _ :: _ =>
            structPatternsSubsumesWithFuel fuel
                expectedFields actualFields expectedPatterns expectedOpenness.isOpen
              && patternsSubsumeWithFuel fuel expectedPatterns actualPatterns
              && (expectedOpenness.isOpen || !actualOpenness.isOpen)

  def subsumesWithFuel : Nat -> Value -> Value -> Bool
    | 0, _, _ => false
    | _ + 1, .top, _ => true
    | _ + 1, _, .bottom => true
    | _ + 1, _, .bottomWith _ => true
    | _ + 1, .kind expectedKind, .kind actualKind => kindSubsumesKind expectedKind actualKind
    | _ + 1, .kind expectedKind, .prim prim => kindSubsumesPrim expectedKind prim
    | _ + 1, .kind expectedKind, .stringRegex _ => kindSubsumesKind expectedKind .string
    | _ + 1, .prim expectedPrim, .prim actualPrim => expectedPrim == actualPrim
    | _ + 1, .notPrim forbidden, .prim prim => forbidden != prim
    | _ + 1, .notPrim expectedForbidden, .notPrim actualForbidden => expectedForbidden == actualForbidden
    | _ + 1, .stringRegex pattern, .prim (.string value) =>
        (regexParseError? pattern).isNone && matchRegex pattern value
    | _ + 1, .stringRegex expectedPattern, .stringRegex actualPattern =>
        expectedPattern == actualPattern
    | _ + 1, .kind expectedKind, .boundConstraint _ _ domain => kindSubsumesKind expectedKind domain.kind
    | _ + 1, .boundConstraint bound kind domain, .prim prim =>
        domain.admitsKind (Prim.kind prim)
          && (match decimalFromPrim? prim with
              | some value => kind.admits bound value
              | none => false)
    | _ + 1, .boundConstraint expectedBound expectedKind _, .boundConstraint actualBound actualKind _ =>
        boundSubsumesBound expectedBound expectedKind actualBound actualKind
    | fuel + 1, .conj constraints, value => allConstraintsSubsumeWithFuel fuel constraints value
    | _ + 1, .builtinCall expectedName expectedArgs, .builtinCall actualName actualArgs =>
        expectedName = actualName && expectedArgs == actualArgs
    | fuel + 1, .unary expectedOp expectedValue, .unary actualOp actualValue =>
        expectedOp == actualOp && subsumesWithFuel fuel expectedValue actualValue
    | fuel + 1, .binary expectedOp expectedLeft expectedRight, .binary actualOp actualLeft actualRight =>
        expectedOp == actualOp
          && subsumesWithFuel fuel expectedLeft actualLeft
          && subsumesWithFuel fuel expectedRight actualRight
    | _ + 1, .ref expectedLabel, .ref actualLabel => expectedLabel == actualLabel
    | _ + 1, .refId expectedId, .refId actualId => expectedId == actualId
    | fuel + 1, .selector expectedBase expectedLabel, .selector actualBase actualLabel =>
        expectedLabel == actualLabel && subsumesWithFuel fuel expectedBase actualBase
    | fuel + 1, .index expectedBase expectedKey, .index actualBase actualKey =>
        subsumesWithFuel fuel expectedBase actualBase && subsumesWithFuel fuel expectedKey actualKey
    | fuel + 1, .disj alternatives, value => disjSubsumesWithFuel fuel alternatives value
    | fuel + 1, .struct expectedFields expectedOpenness expectedTail expectedPatterns _,
      .struct actualFields actualOpenness actualTail actualPatterns _ =>
        structNSubsumesWithFuel fuel
          expectedFields expectedOpenness expectedTail expectedPatterns
          actualFields actualOpenness actualTail actualPatterns
    | fuel + 1, .list expectedItems, .list actualItems =>
        listSubsumesWithFuel fuel expectedItems actualItems
    | fuel + 1, .listTail fixed tail, .list actualItems =>
        listTailSubsumesListWithFuel fuel fixed tail actualItems
    | _ + 1, _, _ => false
end

def subsumes (expected actual : Value) : Bool :=
  subsumesWithFuel orderFuel expected actual

end Kue
