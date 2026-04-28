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

  def disjSubsumesWithFuel (fuel : Nat) (alternatives : List (Mark × Value)) (actual : Value) : Bool :=
    alternatives.any fun alternative => subsumesWithFuel fuel alternative.snd actual

  def subsumesWithFuel : Nat -> Value -> Value -> Bool
    | 0, _, _ => false
    | _ + 1, .top, _ => true
    | _ + 1, _, .bottom => true
    | _ + 1, _, .bottomWith _ => true
    | _ + 1, .kind expectedKind, .kind actualKind => expectedKind == actualKind
    | _ + 1, .kind expectedKind, .prim prim => expectedKind == Prim.kind prim
    | _ + 1, .prim expectedPrim, .prim actualPrim => expectedPrim == actualPrim
    | fuel + 1, .disj alternatives, value => disjSubsumesWithFuel fuel alternatives value
    | fuel + 1, .struct expectedFields expectedOpen, .struct actualFields _ =>
        structSubsumesWithFuel fuel expectedFields actualFields expectedOpen
    | _ + 1, _, _ => false
end

def subsumes (expected actual : Value) : Bool :=
  subsumesWithFuel orderFuel expected actual

end Kue
