import Kue.Value

namespace Kue

def meetPrim (left right : Prim) : Value :=
  if left = right then
    .prim left
  else
    .bottomWith [.primitiveConflict left right]

def maxInt (left right : Int) : Int :=
  if left <= right then right else left

def minInt (left right : Int) : Int :=
  if left <= right then left else right

def meetIntGePrim (minimum : Int) (prim : Prim) : Value :=
  match prim with
  | .int value =>
      if minimum <= value then
        .prim prim
      else
        .bottomWith [.intBoundConflict]
  | _ => .bottomWith [.kindConflict .int (Prim.kind prim)]

def meetIntGtPrim (minimum : Int) (prim : Prim) : Value :=
  match prim with
  | .int value =>
      if minimum < value then
        .prim prim
      else
        .bottomWith [.intBoundConflict]
  | _ => .bottomWith [.kindConflict .int (Prim.kind prim)]

def meetIntLePrim (maximum : Int) (prim : Prim) : Value :=
  match prim with
  | .int value =>
      if value <= maximum then
        .prim prim
      else
        .bottomWith [.intBoundConflict]
  | _ => .bottomWith [.kindConflict .int (Prim.kind prim)]

def meetIntLtPrim (maximum : Int) (prim : Prim) : Value :=
  match prim with
  | .int value =>
      if value < maximum then
        .prim prim
      else
        .bottomWith [.intBoundConflict]
  | _ => .bottomWith [.kindConflict .int (Prim.kind prim)]

def meetIntRangePrim (minimum maximum : Int) (prim : Prim) : Value :=
  match prim with
  | .int value =>
      if minimum <= value && value <= maximum then
        .prim prim
      else
        .bottomWith [.intBoundConflict]
  | _ => .bottomWith [.kindConflict .int (Prim.kind prim)]

def meetStrictIntRangePrim (minimum maximum : Int) (prim : Prim) : Value :=
  match prim with
  | .int value =>
      if minimum < value && value < maximum then
        .prim prim
      else
        .bottomWith [.intBoundConflict]
  | _ => .bottomWith [.kindConflict .int (Prim.kind prim)]

def isBottom : Value -> Bool
  | .bottom => true
  | .bottomWith _ => true
  | _ => false

def combineMark : Mark -> Mark -> Mark
  | .default, _ => .default
  | _, .default => .default
  | .regular, .regular => .regular

def flattenAlternatives (alternatives : List (Mark × Value)) : List (Mark × Value) :=
  alternatives.foldr
    (fun alternative flattened =>
      match alternative with
      | (mark, .disj nested) =>
          nested.map (fun nestedAlternative =>
            (combineMark mark nestedAlternative.fst, nestedAlternative.snd)
          ) ++ flattened
      | alternative => alternative :: flattened)
    []

def normalizeDisj (alternatives : List (Mark × Value)) : Value :=
  let flattened := flattenAlternatives alternatives
  let live := flattened.filter fun alternative => !isBottom alternative.snd
  match live with
  | [] => .bottom
  | [(.regular, value)] => value
  | alternatives => .disj alternatives

def disjOfValues (left right : Value) : Value :=
  normalizeDisj [(.regular, left), (.regular, right)]

def meetCore (left right : Value) : Value :=
  match left, right with
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
  | .top, value => value
  | value, .top => value
  | .kind leftKind, .kind rightKind =>
      if leftKind = rightKind then
        .kind leftKind
      else
        .bottomWith [.kindConflict leftKind rightKind]
  | .kind kind, .prim prim =>
      if Prim.kind prim = kind then
        .prim prim
      else
        .bottomWith [.kindConflict kind (Prim.kind prim)]
  | .prim prim, .kind kind =>
      if Prim.kind prim = kind then
        .prim prim
      else
        .bottomWith [.kindConflict (Prim.kind prim) kind]
  | .prim leftPrim, .prim rightPrim => meetPrim leftPrim rightPrim
  | .intGe minimum, .prim prim => meetIntGePrim minimum prim
  | .prim prim, .intGe minimum => meetIntGePrim minimum prim
  | .intGt minimum, .prim prim => meetIntGtPrim minimum prim
  | .prim prim, .intGt minimum => meetIntGtPrim minimum prim
  | .intLe maximum, .prim prim => meetIntLePrim maximum prim
  | .prim prim, .intLe maximum => meetIntLePrim maximum prim
  | .intLt maximum, .prim prim => meetIntLtPrim maximum prim
  | .prim prim, .intLt maximum => meetIntLtPrim maximum prim
  | .kind .int, .intGe minimum => .intGe minimum
  | .intGe minimum, .kind .int => .intGe minimum
  | .kind .int, .intGt minimum => .intGt minimum
  | .intGt minimum, .kind .int => .intGt minimum
  | .kind .int, .intLe maximum => .intLe maximum
  | .intLe maximum, .kind .int => .intLe maximum
  | .kind .int, .intLt maximum => .intLt maximum
  | .intLt maximum, .kind .int => .intLt maximum
  | .kind kind, .intGe _ => .bottomWith [.kindConflict kind .int]
  | .intGe _, .kind kind => .bottomWith [.kindConflict .int kind]
  | .kind kind, .intGt _ => .bottomWith [.kindConflict kind .int]
  | .intGt _, .kind kind => .bottomWith [.kindConflict .int kind]
  | .kind kind, .intLe _ => .bottomWith [.kindConflict kind .int]
  | .intLe _, .kind kind => .bottomWith [.kindConflict .int kind]
  | .kind kind, .intLt _ => .bottomWith [.kindConflict kind .int]
  | .intLt _, .kind kind => .bottomWith [.kindConflict .int kind]
  | .intGe leftMinimum, .intGe rightMinimum => .intGe (maxInt leftMinimum rightMinimum)
  | .intGt leftMinimum, .intGt rightMinimum => .intGt (maxInt leftMinimum rightMinimum)
  | .intGe minimum, .intGt strictMinimum => .conj [.intGe minimum, .intGt strictMinimum]
  | .intGt strictMinimum, .intGe minimum => .conj [.intGe minimum, .intGt strictMinimum]
  | .intLe leftMaximum, .intLe rightMaximum => .intLe (minInt leftMaximum rightMaximum)
  | .intLt leftMaximum, .intLt rightMaximum => .intLt (minInt leftMaximum rightMaximum)
  | .intLe maximum, .intLt strictMaximum => .conj [.intLe maximum, .intLt strictMaximum]
  | .intLt strictMaximum, .intLe maximum => .conj [.intLe maximum, .intLt strictMaximum]
  | .intGe minimum, .intLe maximum =>
      if minimum <= maximum then
        .conj [.intGe minimum, .intLe maximum]
      else
        .bottomWith [.intBoundConflict]
  | .intLe maximum, .intGe minimum =>
      if minimum <= maximum then
        .conj [.intGe minimum, .intLe maximum]
      else
        .bottomWith [.intBoundConflict]
  | .intGe minimum, .intLt maximum =>
      if minimum < maximum then
        .conj [.intGe minimum, .intLt maximum]
      else
        .bottomWith [.intBoundConflict]
  | .intLt maximum, .intGe minimum =>
      if minimum < maximum then
        .conj [.intGe minimum, .intLt maximum]
      else
        .bottomWith [.intBoundConflict]
  | .intGt minimum, .intLe maximum =>
      if minimum < maximum then
        .conj [.intGt minimum, .intLe maximum]
      else
        .bottomWith [.intBoundConflict]
  | .intLe maximum, .intGt minimum =>
      if minimum < maximum then
        .conj [.intGt minimum, .intLe maximum]
      else
        .bottomWith [.intBoundConflict]
  | .intGt minimum, .intLt maximum =>
      if minimum < maximum then
        .conj [.intGt minimum, .intLt maximum]
      else
        .bottomWith [.intBoundConflict]
  | .intLt maximum, .intGt minimum =>
      if minimum < maximum then
        .conj [.intGt minimum, .intLt maximum]
      else
        .bottomWith [.intBoundConflict]
  | .conj [.intGe minimum, .intLe maximum], .prim prim => meetIntRangePrim minimum maximum prim
  | .prim prim, .conj [.intGe minimum, .intLe maximum] => meetIntRangePrim minimum maximum prim
  | .conj [.intGt minimum, .intLt maximum], .prim prim => meetStrictIntRangePrim minimum maximum prim
  | .prim prim, .conj [.intGt minimum, .intLt maximum] => meetStrictIntRangePrim minimum maximum prim
  | .conj _, _ => .bottom
  | _, .conj _ => .bottom
  | .ref leftLabel, .ref rightLabel =>
      if leftLabel = rightLabel then
        .ref leftLabel
      else
        .bottom
  | .refId leftId, .refId rightId =>
      if leftId == rightId then
        .refId leftId
      else
        .bottom
  | .refId _, _ => .bottom
  | _, .refId _ => .bottom
  | .list _, .list _ => .bottom
  | .listTail _ _, _ => .bottom
  | _, .listTail _ _ => .bottom
  | .list _, _ => .bottom
  | _, .list _ => .bottom
  | .ref _, _ => .bottom
  | _, .ref _ => .bottom
  | .struct _ _, .struct _ _ => .bottom
  | .structTail _ _, _ => .bottom
  | _, .structTail _ _ => .bottom
  | .disj _, _ => .bottom
  | _, .disj _ => .bottom
  | .struct .., _ => .bottom
  | _, .struct .. => .bottom

def meetConjValue (constraints : List Value) (value : Value) : Value :=
  constraints.foldl
    (fun current constraint =>
      if isBottom current then
        current
      else
        meetCore constraint current)
    value

def meetListPrefixTail : List Value -> Value -> List Value -> Option (List Value)
  | [], tail, items => some (items.map (fun item => meetCore tail item))
  | expected :: expectedItems, tail, actual :: actualItems =>
      match meetListPrefixTail expectedItems tail actualItems with
      | some items => some (meetCore expected actual :: items)
      | none => none
  | _ :: _, _, [] => none

def meetCompoundCore (left right : Value) : Value :=
  match left, right with
  | .conj constraints, value => meetConjValue constraints value
  | value, .conj constraints => meetConjValue constraints value
  | .listTail fixed tail, .list items =>
      match meetListPrefixTail fixed tail items with
      | some items => .list items
      | none => .bottom
  | .list items, .listTail fixed tail =>
      match meetListPrefixTail fixed tail items with
      | some items => .list items
      | none => .bottom
  | value, other => meetCore value other

def mergeFieldClass (left right : FieldClass) : Option FieldClass :=
  match left, right with
  | .regular, .regular => some .regular
  | .optional, .regular => some .regular
  | .regular, .optional => some .regular
  | .required, .regular => some .regular
  | .regular, .required => some .regular
  | .optional, .optional => some .optional
  | .required, .required => some .required
  | .hidden, .hidden => some .hidden
  | .definition, .definition => some .definition
  | _, _ => none

def fieldWithClass (fieldClass : FieldClass) (label : String) (value : Value) : Field :=
  (label, fieldClass, value)

def mergeFieldValue (left right : Field) : Option Field :=
  match mergeFieldClass (Field.fieldClass left) (Field.fieldClass right) with
  | some fieldClass =>
      let value := meetCompoundCore (Field.value left) (Field.value right)
      if isBottom value then
        some (fieldWithClass fieldClass (Field.label left) (.bottomWith [.fieldConflict (Field.label left)]))
      else
        some (fieldWithClass fieldClass (Field.label left) value)
  | none => none

def mergeFieldInto (fields : List Field) (field : Field) : Option (List Field) :=
  match fields with
  | [] => some [field]
  | current :: rest =>
      if Field.label current = Field.label field then
        match mergeFieldValue current field with
        | some merged => some (merged :: rest)
        | none => none
      else
        match mergeFieldInto rest field with
        | some mergedRest => some (current :: mergedRest)
        | none => none

def mergeStructFields (leftFields rightFields : List Field) : Option (List Field) :=
  rightFields.foldl
    (fun merged field =>
      match merged with
      | some fields => mergeFieldInto fields field
      | none => none)
    (some leftFields)

def hasFieldLabel (label : String) : List Field -> Bool
  | [] => false
  | field :: fields =>
      if Field.label field = label then
        true
      else
        hasFieldLabel label fields

def markDisallowedField (field : Field) : Field :=
  fieldWithClass (Field.fieldClass field) (Field.label field)
    (.bottomWith [.fieldNotAllowed (Field.label field)])

def applyClosednessFrom (allowedFields : List Field) (isOpen : Bool) (fields : List Field) : List Field :=
  if isOpen then
    fields
  else
    fields.map fun field =>
      if hasFieldLabel (Field.label field) allowedFields then
        field
      else
        markDisallowedField field

def applyStructClosedness
    (leftFields rightFields mergedFields : List Field)
    (leftOpen rightOpen : Bool) : List Field :=
  let checkedByLeft := applyClosednessFrom leftFields leftOpen mergedFields
  applyClosednessFrom rightFields rightOpen checkedByLeft

def applyTailToField (declaredFields : List Field) (tail : Value) (field : Field) : Field :=
  if hasFieldLabel (Field.label field) declaredFields then
    field
  else
    let value := meetCompoundCore tail (Field.value field)
    if isBottom value then
      fieldWithClass (Field.fieldClass field) (Field.label field)
        (.bottomWith [.fieldConstraint (Field.label field)])
    else
      fieldWithClass (Field.fieldClass field) (Field.label field) value

def applyTailToExtras (declaredFields : List Field) (tail : Value) (fields : List Field) : List Field :=
  fields.map (applyTailToField declaredFields tail)

def mergeStructTailWithStruct (tailFields : List Field) (tail : Value) (fields : List Field) : Value :=
  match mergeStructFields tailFields fields with
  | some mergedFields => .structTail (applyTailToExtras tailFields tail mergedFields) tail
  | none => .bottom

def meetList : List Value -> List Value -> Option (List Value)
  | [], [] => some []
  | left :: leftItems, right :: rightItems =>
      match meetList leftItems rightItems with
      | some items => some (meetCompoundCore left right :: items)
      | none => none
  | _, _ => none

def meet (left right : Value) : Value :=
  match left, right with
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
  | .top, value => value
  | value, .top => value
  | .conj constraints, value => meetConjValue constraints value
  | value, .conj constraints => meetConjValue constraints value
  | .struct leftFields leftOpen, .struct rightFields rightOpen =>
      match mergeStructFields leftFields rightFields with
      | some fields =>
          .struct
            (applyStructClosedness leftFields rightFields fields leftOpen rightOpen)
            (leftOpen && rightOpen)
      | none => .bottom
  | .structTail tailFields tail, .struct fields _ =>
      mergeStructTailWithStruct tailFields tail fields
  | .struct fields _, .structTail tailFields tail =>
      mergeStructTailWithStruct tailFields tail fields
  | .structTail leftFields leftTail, .structTail rightFields rightTail =>
      match mergeStructFields leftFields rightFields with
      | some mergedFields =>
          let tail := meetCore leftTail rightTail
          if isBottom tail then
            .bottom
          else
            .structTail
              (applyTailToExtras leftFields leftTail (applyTailToExtras rightFields rightTail mergedFields))
              tail
      | none => .bottom
  | .list leftItems, .list rightItems =>
      match meetList leftItems rightItems with
      | some items => .list items
      | none => .bottom
  | .listTail fixed tail, .list items =>
      match meetListPrefixTail fixed tail items with
      | some items => .list items
      | none => .bottom
  | .list items, .listTail fixed tail =>
      match meetListPrefixTail fixed tail items with
      | some items => .list items
      | none => .bottom
  | .disj leftAlternatives, .disj rightAlternatives =>
      let flatLeft := flattenAlternatives leftAlternatives
      let flatRight := flattenAlternatives rightAlternatives
      let alternatives :=
        flatLeft.foldr
          (fun leftAlternative combined =>
            let paired :=
              flatRight.map fun rightAlternative =>
                (
                  combineMark leftAlternative.fst rightAlternative.fst,
                  meetCore leftAlternative.snd rightAlternative.snd
                )
            paired ++ combined)
          []
      normalizeDisj alternatives
  | .disj alternatives, value =>
      let flatAlternatives := flattenAlternatives alternatives
      let distributed :=
        flatAlternatives.map fun alternative =>
          (alternative.fst, meetCore alternative.snd value)
      normalizeDisj distributed
  | value, .disj alternatives =>
      let flatAlternatives := flattenAlternatives alternatives
      let distributed :=
        flatAlternatives.map fun alternative =>
          (alternative.fst, meetCore value alternative.snd)
      normalizeDisj distributed
  | value, other => meetCore value other

def joinPrim (left right : Prim) : Value :=
  if left = right then
    .prim left
  else
    disjOfValues (.prim left) (.prim right)

def join (left right : Value) : Value :=
  match left, right with
  | .top, _ => .top
  | _, .top => .top
  | .bottom, value => value
  | value, .bottom => value
  | .kind leftKind, .kind rightKind =>
      if leftKind = rightKind then
        .kind leftKind
      else
        disjOfValues (.kind leftKind) (.kind rightKind)
  | .kind kind, .prim prim =>
      if Prim.kind prim = kind then
        .kind kind
      else
        disjOfValues (.kind kind) (.prim prim)
  | .prim prim, .kind kind =>
      if Prim.kind prim = kind then
        .kind kind
      else
        disjOfValues (.prim prim) (.kind kind)
  | .prim leftPrim, .prim rightPrim => joinPrim leftPrim rightPrim
  | .disj leftAlternatives, .disj rightAlternatives =>
      normalizeDisj (leftAlternatives ++ rightAlternatives)
  | .disj alternatives, value =>
      normalizeDisj (alternatives ++ [(.regular, value)])
  | value, .disj alternatives =>
      normalizeDisj ((.regular, value) :: alternatives)
  | value, other => disjOfValues value other

end Kue
