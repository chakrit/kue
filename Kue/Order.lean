import Kue.Value

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
      | none => false

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

  def structPatternSubsumesWithFuel
      (fuel : Nat)
      (expectedFields actualFields : List Field)
      (labelPattern constraint : Value) : Bool :=
    let expectedSatisfied := allExpectedFieldsSubsumedWithFuel fuel expectedFields actualFields
    let patternSatisfied :=
      regularFieldsSatisfyPatternWithFuel fuel actualFields labelPattern constraint
    expectedSatisfied && patternSatisfied

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
    | _ + 1, .stringRegex pattern, .prim (.string value) => stringRegexMatches pattern value
    | _ + 1, .stringRegex expectedPattern, .stringRegex actualPattern =>
        expectedPattern == actualPattern
    | _ + 1, .kind expectedKind, .intGe _ => kindSubsumesKind expectedKind .int
    | _ + 1, .kind expectedKind, .intGt _ => kindSubsumesKind expectedKind .int
    | _ + 1, .kind expectedKind, .intLe _ => kindSubsumesKind expectedKind .int
    | _ + 1, .kind expectedKind, .intLt _ => kindSubsumesKind expectedKind .int
    | _ + 1, .intGe minimum, .prim (.int value) => minimum <= value
    | _ + 1, .intGe expectedMinimum, .intGe actualMinimum => expectedMinimum <= actualMinimum
    | _ + 1, .intGt minimum, .prim (.int value) => minimum < value
    | _ + 1, .intGt expectedMinimum, .intGt actualMinimum => expectedMinimum <= actualMinimum
    | _ + 1, .intLe maximum, .prim (.int value) => value <= maximum
    | _ + 1, .intLe expectedMaximum, .intLe actualMaximum => actualMaximum <= expectedMaximum
    | _ + 1, .intLt maximum, .prim (.int value) => value < maximum
    | _ + 1, .intLt expectedMaximum, .intLt actualMaximum => actualMaximum <= expectedMaximum
    | fuel + 1, .conj constraints, value => allConstraintsSubsumeWithFuel fuel constraints value
    | _ + 1, .ref expectedLabel, .ref actualLabel => expectedLabel == actualLabel
    | _ + 1, .refId expectedId, .refId actualId => expectedId == actualId
    | fuel + 1, .disj alternatives, value => disjSubsumesWithFuel fuel alternatives value
    | fuel + 1, .struct expectedFields expectedOpen, .struct actualFields _ =>
        structSubsumesWithFuel fuel expectedFields actualFields expectedOpen
    | fuel + 1, .structTail expectedFields tail, .struct actualFields _ =>
        structTailSubsumesWithFuel fuel expectedFields actualFields tail
    | fuel + 1, .structTail expectedFields tail, .structTail actualFields _ =>
        structTailSubsumesWithFuel fuel expectedFields actualFields tail
    | fuel + 1, .structPattern expectedFields labelPattern constraint, .struct actualFields _ =>
        structPatternSubsumesWithFuel fuel expectedFields actualFields labelPattern constraint
    | fuel + 1,
      .structPattern expectedFields labelPattern constraint,
      .structPattern actualFields actualLabel actualConstraint =>
        structPatternSubsumesWithFuel fuel expectedFields actualFields labelPattern constraint
          && subsumesWithFuel fuel labelPattern actualLabel
          && subsumesWithFuel fuel constraint actualConstraint
    | fuel + 1, .list expectedItems, .list actualItems =>
        listSubsumesWithFuel fuel expectedItems actualItems
    | fuel + 1, .listTail fixed tail, .list actualItems =>
        listTailSubsumesListWithFuel fuel fixed tail actualItems
    | _ + 1, _, _ => false
end

def subsumes (expected actual : Value) : Bool :=
  subsumesWithFuel orderFuel expected actual

end Kue
