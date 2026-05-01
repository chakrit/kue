import Kue.Value

namespace Kue

def meetPrim (left right : Prim) : Value :=
  if left = right then
    .prim left
  else
    .bottomWith [.primitiveConflict left right]

def kindAcceptsPrim (kind : Kind) (prim : Prim) : Bool :=
  kind == Prim.kind prim || (kind == .number && (Prim.kind prim == .int || Prim.kind prim == .float))

def kindAcceptsKind (expected actual : Kind) : Bool :=
  expected == actual || (expected == .number && (actual == .int || actual == .float))

def meetNotPrimPrim (forbidden prim : Prim) : Value :=
  if forbidden = prim then
    .bottomWith [.excludedValue forbidden]
  else
    .prim prim

def meetStringRegexPrim (pattern : String) (prim : Prim) : Value :=
  match prim with
  | .string value =>
      if stringRegexMatches pattern value then
        .prim prim
      else
        .bottom
  | _ => .bottomWith [.kindConflict .string (Prim.kind prim)]

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

def containsBottomFuel : Nat :=
  100

def containsBottomWithFuel : Nat -> Value -> Bool
  | 0, _ => false
  | _ + 1, .bottom => true
  | _ + 1, .bottomWith _ => true
  | fuel + 1, .conj constraints =>
      constraints.any (containsBottomWithFuel fuel)
  | fuel + 1, .builtinCall _ args =>
      args.any (containsBottomWithFuel fuel)
  | fuel + 1, .disj alternatives =>
      alternatives.any fun alternative => containsBottomWithFuel fuel alternative.snd
  | fuel + 1, .struct fields _ =>
      fields.any fun field => containsBottomWithFuel fuel (Field.value field)
  | fuel + 1, .structTail fields tail =>
      fields.any (fun field => containsBottomWithFuel fuel (Field.value field))
        || containsBottomWithFuel fuel tail
  | fuel + 1, .structPattern fields _ _ =>
      fields.any fun field => containsBottomWithFuel fuel (Field.value field)
  | fuel + 1, .list items =>
      items.any (containsBottomWithFuel fuel)
  | fuel + 1, .listTail items tail =>
      items.any (containsBottomWithFuel fuel) || containsBottomWithFuel fuel tail
  | _ + 1, _ => false

def containsBottom (value : Value) : Bool :=
  containsBottomWithFuel containsBottomFuel value

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
  let live := flattened.filter fun alternative => !containsBottom alternative.snd
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
      if kindAcceptsKind leftKind rightKind then
        .kind rightKind
      else if kindAcceptsKind rightKind leftKind then
        .kind leftKind
      else
        .bottomWith [.kindConflict leftKind rightKind]
  | .kind kind, .prim prim =>
      if kindAcceptsPrim kind prim then
        .prim prim
      else
        .bottomWith [.kindConflict kind (Prim.kind prim)]
  | .prim prim, .kind kind =>
      if kindAcceptsPrim kind prim then
        .prim prim
      else
        .bottomWith [.kindConflict (Prim.kind prim) kind]
  | .prim leftPrim, .prim rightPrim => meetPrim leftPrim rightPrim
  | .notPrim forbidden, .prim prim => meetNotPrimPrim forbidden prim
  | .prim prim, .notPrim forbidden => meetNotPrimPrim forbidden prim
  | .kind kind, .notPrim forbidden =>
      if kindAcceptsPrim kind forbidden then
        .notPrim forbidden
      else
        .kind kind
  | .notPrim forbidden, .kind kind =>
      if kindAcceptsPrim kind forbidden then
        .notPrim forbidden
      else
        .kind kind
  | .notPrim leftForbidden, .notPrim rightForbidden =>
      if leftForbidden = rightForbidden then
        .notPrim leftForbidden
      else
        .conj [.notPrim leftForbidden, .notPrim rightForbidden]
  | .builtinCall leftName leftArgs, .builtinCall rightName rightArgs =>
      if leftName = rightName && leftArgs == rightArgs then
        .builtinCall leftName leftArgs
      else
        .bottom
  | .stringRegex leftPattern, .stringRegex rightPattern =>
      if leftPattern = rightPattern then
        .stringRegex leftPattern
      else
        .conj [.stringRegex leftPattern, .stringRegex rightPattern]
  | .stringRegex pattern, .prim prim => meetStringRegexPrim pattern prim
  | .prim prim, .stringRegex pattern => meetStringRegexPrim pattern prim
  | .kind kind, .stringRegex pattern =>
      if kindAcceptsKind kind .string then
        .stringRegex pattern
      else
        .bottomWith [.kindConflict kind .string]
  | .stringRegex pattern, .kind kind =>
      if kindAcceptsKind kind .string then
        .stringRegex pattern
      else
        .bottomWith [.kindConflict .string kind]
  | .notPrim forbidden, .stringRegex pattern =>
      if Prim.kind forbidden = .string then
        .conj [.stringRegex pattern, .notPrim forbidden]
      else
        .stringRegex pattern
  | .stringRegex pattern, .notPrim forbidden =>
      if Prim.kind forbidden = .string then
        .conj [.stringRegex pattern, .notPrim forbidden]
      else
        .stringRegex pattern
  | .stringRegex _, .intGe _ => .bottomWith [.kindConflict .string .int]
  | .intGe _, .stringRegex _ => .bottomWith [.kindConflict .int .string]
  | .stringRegex _, .intGt _ => .bottomWith [.kindConflict .string .int]
  | .intGt _, .stringRegex _ => .bottomWith [.kindConflict .int .string]
  | .stringRegex _, .intLe _ => .bottomWith [.kindConflict .string .int]
  | .intLe _, .stringRegex _ => .bottomWith [.kindConflict .int .string]
  | .stringRegex _, .intLt _ => .bottomWith [.kindConflict .string .int]
  | .intLt _, .stringRegex _ => .bottomWith [.kindConflict .int .string]
  | .intGe minimum, .notPrim forbidden =>
      if Prim.kind forbidden = .int then .conj [.intGe minimum, .notPrim forbidden] else .intGe minimum
  | .notPrim forbidden, .intGe minimum =>
      if Prim.kind forbidden = .int then .conj [.intGe minimum, .notPrim forbidden] else .intGe minimum
  | .intGt minimum, .notPrim forbidden =>
      if Prim.kind forbidden = .int then .conj [.intGt minimum, .notPrim forbidden] else .intGt minimum
  | .notPrim forbidden, .intGt minimum =>
      if Prim.kind forbidden = .int then .conj [.intGt minimum, .notPrim forbidden] else .intGt minimum
  | .intLe maximum, .notPrim forbidden =>
      if Prim.kind forbidden = .int then .conj [.intLe maximum, .notPrim forbidden] else .intLe maximum
  | .notPrim forbidden, .intLe maximum =>
      if Prim.kind forbidden = .int then .conj [.intLe maximum, .notPrim forbidden] else .intLe maximum
  | .intLt maximum, .notPrim forbidden =>
      if Prim.kind forbidden = .int then .conj [.intLt maximum, .notPrim forbidden] else .intLt maximum
  | .notPrim forbidden, .intLt maximum =>
      if Prim.kind forbidden = .int then .conj [.intLt maximum, .notPrim forbidden] else .intLt maximum
  | .intGe minimum, .prim prim => meetIntGePrim minimum prim
  | .prim prim, .intGe minimum => meetIntGePrim minimum prim
  | .intGt minimum, .prim prim => meetIntGtPrim minimum prim
  | .prim prim, .intGt minimum => meetIntGtPrim minimum prim
  | .intLe maximum, .prim prim => meetIntLePrim maximum prim
  | .prim prim, .intLe maximum => meetIntLePrim maximum prim
  | .intLt maximum, .prim prim => meetIntLtPrim maximum prim
  | .prim prim, .intLt maximum => meetIntLtPrim maximum prim
  | .kind kind, .intGe minimum =>
      if kindAcceptsKind kind .int then .intGe minimum else .bottomWith [.kindConflict kind .int]
  | .intGe minimum, .kind kind =>
      if kindAcceptsKind kind .int then .intGe minimum else .bottomWith [.kindConflict .int kind]
  | .kind kind, .intGt minimum =>
      if kindAcceptsKind kind .int then .intGt minimum else .bottomWith [.kindConflict kind .int]
  | .intGt minimum, .kind kind =>
      if kindAcceptsKind kind .int then .intGt minimum else .bottomWith [.kindConflict .int kind]
  | .kind kind, .intLe maximum =>
      if kindAcceptsKind kind .int then .intLe maximum else .bottomWith [.kindConflict kind .int]
  | .intLe maximum, .kind kind =>
      if kindAcceptsKind kind .int then .intLe maximum else .bottomWith [.kindConflict .int kind]
  | .kind kind, .intLt maximum =>
      if kindAcceptsKind kind .int then .intLt maximum else .bottomWith [.kindConflict kind .int]
  | .intLt maximum, .kind kind =>
      if kindAcceptsKind kind .int then .intLt maximum else .bottomWith [.kindConflict .int kind]
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
  | .builtinCall _ _, _ => .bottom
  | _, .builtinCall _ _ => .bottom
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
  | .structPattern _ _ _, _ => .bottom
  | _, .structPattern _ _ _ => .bottom
  | .disj _, _ => .bottom
  | _, .disj _ => .bottom
  | .struct .., _ => .bottom
  | _, .struct .. => .bottom

def meetConjValueWith
    (meetValue : Value -> Value -> Value) (constraints : List Value) (value : Value) : Value :=
  constraints.foldl
    (fun current constraint =>
      if isBottom current then
        current
      else
        meetValue constraint current)
    value

def meetListPrefixTailWith
    (meetValue : Value -> Value -> Value) : List Value -> Value -> List Value -> Option (List Value)
  | [], tail, items => some (items.map (fun item => meetValue tail item))
  | expected :: expectedItems, tail, actual :: actualItems =>
      match meetListPrefixTailWith meetValue expectedItems tail actualItems with
      | some items => some (meetValue expected actual :: items)
      | none => none
  | _ :: _, _, [] => none

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

def mergeFieldValueWith (meetValue : Value -> Value -> Value) (left right : Field) : Option Field :=
  match mergeFieldClass (Field.fieldClass left) (Field.fieldClass right) with
  | some fieldClass =>
      let value := meetValue (Field.value left) (Field.value right)
      if isBottom value then
        some (fieldWithClass fieldClass (Field.label left) (.bottomWith [.fieldConflict (Field.label left)]))
      else
        some (fieldWithClass fieldClass (Field.label left) value)
  | none => none

def mergeFieldIntoWith
    (meetValue : Value -> Value -> Value) (fields : List Field) (field : Field) : Option (List Field) :=
  match fields with
  | [] => some [field]
  | current :: rest =>
      if Field.label current = Field.label field then
        match mergeFieldValueWith meetValue current field with
        | some merged => some (merged :: rest)
        | none => none
      else
        match mergeFieldIntoWith meetValue rest field with
        | some mergedRest => some (current :: mergedRest)
        | none => none

def mergeStructFieldsWith
    (meetValue : Value -> Value -> Value) (leftFields rightFields : List Field) : Option (List Field) :=
  rightFields.foldl
    (fun merged field =>
      match merged with
      | some fields => mergeFieldIntoWith meetValue fields field
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

def applyTailToFieldWith
    (meetValue : Value -> Value -> Value)
    (declaredFields : List Field)
    (tail : Value)
    (field : Field) : Field :=
  if hasFieldLabel (Field.label field) declaredFields then
    field
  else
    let value := meetValue tail (Field.value field)
    if isBottom value then
      fieldWithClass (Field.fieldClass field) (Field.label field)
        (.bottomWith [.fieldConstraint (Field.label field)])
    else
      fieldWithClass (Field.fieldClass field) (Field.label field) value

def applyTailToExtrasWith
    (meetValue : Value -> Value -> Value) (declaredFields : List Field) (tail : Value) (fields : List Field) :
    List Field :=
  fields.map (applyTailToFieldWith meetValue declaredFields tail)

def labelMatchesPatternWith
    (meetValue : Value -> Value -> Value)
    (labelPattern : Value)
    (label : String) : Bool :=
  !containsBottom (meetValue labelPattern (.prim (.string label)))

def applyPatternToFieldWith
    (meetValue : Value -> Value -> Value)
    (labelPattern constraint : Value)
    (field : Field) : Field :=
  let isRegular := Field.fieldClass field == .regular
  let labelMatches := labelMatchesPatternWith meetValue labelPattern (Field.label field)
  if isRegular && labelMatches then
    let value := meetValue constraint (Field.value field)
    if isBottom value then
      fieldWithClass (Field.fieldClass field) (Field.label field)
        (.bottomWith [.fieldConstraint (Field.label field)])
    else
      fieldWithClass (Field.fieldClass field) (Field.label field) value
  else
    field

def applyPatternToFieldsWith
    (meetValue : Value -> Value -> Value)
    (labelPattern constraint : Value)
    (fields : List Field) : List Field :=
  fields.map (applyPatternToFieldWith meetValue labelPattern constraint)

def mergeStructTailWithStructWith
    (meetValue : Value -> Value -> Value)
    (tailFields : List Field)
    (tail : Value)
    (fields : List Field) : Value :=
  match mergeStructFieldsWith meetValue tailFields fields with
  | some mergedFields => .structTail (applyTailToExtrasWith meetValue tailFields tail mergedFields) tail
  | none => .bottom

def mergeStructPatternWithStructWith
    (meetValue : Value -> Value -> Value)
    (patternFields : List Field)
    (labelPattern constraint : Value)
    (fields : List Field) : Value :=
  match mergeStructFieldsWith meetValue patternFields fields with
  | some mergedFields =>
      .structPattern
        (applyPatternToFieldsWith meetValue labelPattern constraint mergedFields)
        labelPattern
        constraint
  | none => .bottom

def meetListWith (meetValue : Value -> Value -> Value) : List Value -> List Value -> Option (List Value)
  | [], [] => some []
  | left :: leftItems, right :: rightItems =>
      match meetListWith meetValue leftItems rightItems with
      | some items => some (meetValue left right :: items)
      | none => none
  | _, _ => none

def meetFuel : Nat :=
  100

def meetWithFuel : Nat -> Value -> Value -> Value
  | 0, left, right => meetCore left right
  | fuel + 1, left, right =>
    match left, right with
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
  | .top, value => value
  | value, .top => value
  | .conj constraints, value => meetConjValueWith (meetWithFuel fuel) constraints value
  | value, .conj constraints => meetConjValueWith (meetWithFuel fuel) constraints value
  | .struct leftFields leftOpen, .struct rightFields rightOpen =>
      match mergeStructFieldsWith (meetWithFuel fuel) leftFields rightFields with
      | some fields =>
          .struct
            (applyStructClosedness leftFields rightFields fields leftOpen rightOpen)
            (leftOpen && rightOpen)
      | none => .bottom
  | .structTail tailFields tail, .struct fields _ =>
      mergeStructTailWithStructWith (meetWithFuel fuel) tailFields tail fields
  | .struct fields _, .structTail tailFields tail =>
      mergeStructTailWithStructWith (meetWithFuel fuel) tailFields tail fields
  | .structTail leftFields leftTail, .structTail rightFields rightTail =>
      match mergeStructFieldsWith (meetWithFuel fuel) leftFields rightFields with
      | some mergedFields =>
          let tail := meetWithFuel fuel leftTail rightTail
          if isBottom tail then
            .bottom
          else
            .structTail
              (applyTailToExtrasWith
                (meetWithFuel fuel)
                leftFields
                leftTail
                (applyTailToExtrasWith (meetWithFuel fuel) rightFields rightTail mergedFields))
              tail
      | none => .bottom
  | .structPattern patternFields labelPattern constraint, .struct fields _ =>
      mergeStructPatternWithStructWith (meetWithFuel fuel) patternFields labelPattern constraint fields
  | .struct fields _, .structPattern patternFields labelPattern constraint =>
      mergeStructPatternWithStructWith (meetWithFuel fuel) patternFields labelPattern constraint fields
  | .structPattern leftFields leftLabel leftConstraint,
    .structPattern rightFields rightLabel rightConstraint =>
      match mergeStructFieldsWith (meetWithFuel fuel) leftFields rightFields with
      | some mergedFields =>
          let labelPattern := if leftLabel == rightLabel then leftLabel else disjOfValues leftLabel rightLabel
          let constraint := meetWithFuel fuel leftConstraint rightConstraint
          .structPattern
            (applyPatternToFieldsWith
              (meetWithFuel fuel)
              leftLabel
              leftConstraint
              (applyPatternToFieldsWith (meetWithFuel fuel) rightLabel rightConstraint mergedFields))
            labelPattern
            constraint
      | none => .bottom
  | .list leftItems, .list rightItems =>
      match meetListWith (meetWithFuel fuel) leftItems rightItems with
      | some items => .list items
      | none => .bottom
  | .listTail fixed tail, .list items =>
      match meetListPrefixTailWith (meetWithFuel fuel) fixed tail items with
      | some items => .list items
      | none => .bottom
  | .list items, .listTail fixed tail =>
      match meetListPrefixTailWith (meetWithFuel fuel) fixed tail items with
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
                  meetWithFuel fuel leftAlternative.snd rightAlternative.snd
                )
            paired ++ combined)
          []
      normalizeDisj alternatives
  | .disj alternatives, value =>
      let flatAlternatives := flattenAlternatives alternatives
      let distributed :=
        flatAlternatives.map fun alternative =>
          (alternative.fst, meetWithFuel fuel alternative.snd value)
      normalizeDisj distributed
  | value, .disj alternatives =>
      let flatAlternatives := flattenAlternatives alternatives
      let distributed :=
        flatAlternatives.map fun alternative =>
          (alternative.fst, meetWithFuel fuel value alternative.snd)
      normalizeDisj distributed
  | value, other => meetCore value other

def meet (left right : Value) : Value :=
  meetWithFuel meetFuel left right

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
  | .intGe leftMinimum, .intGe rightMinimum => .intGe (minInt leftMinimum rightMinimum)
  | .intGt leftMinimum, .intGt rightMinimum => .intGt (minInt leftMinimum rightMinimum)
  | .intLe leftMaximum, .intLe rightMaximum => .intLe (maxInt leftMaximum rightMaximum)
  | .intLt leftMaximum, .intLt rightMaximum => .intLt (maxInt leftMaximum rightMaximum)
  | .kind leftKind, .kind rightKind =>
      if kindAcceptsKind leftKind rightKind then
        .kind leftKind
      else if kindAcceptsKind rightKind leftKind then
        .kind rightKind
      else
        disjOfValues (.kind leftKind) (.kind rightKind)
  | .kind kind, .prim prim =>
      if kindAcceptsPrim kind prim then
        .kind kind
      else
        disjOfValues (.kind kind) (.prim prim)
  | .prim prim, .kind kind =>
      if kindAcceptsPrim kind prim then
        .kind kind
      else
        disjOfValues (.prim prim) (.kind kind)
  | .kind kind, .intGe minimum =>
      if kindAcceptsKind kind .int then .kind kind else disjOfValues (.kind kind) (.intGe minimum)
  | .intGe minimum, .kind kind =>
      if kindAcceptsKind kind .int then .kind kind else disjOfValues (.intGe minimum) (.kind kind)
  | .kind kind, .intGt minimum =>
      if kindAcceptsKind kind .int then .kind kind else disjOfValues (.kind kind) (.intGt minimum)
  | .intGt minimum, .kind kind =>
      if kindAcceptsKind kind .int then .kind kind else disjOfValues (.intGt minimum) (.kind kind)
  | .kind kind, .intLe maximum =>
      if kindAcceptsKind kind .int then .kind kind else disjOfValues (.kind kind) (.intLe maximum)
  | .intLe maximum, .kind kind =>
      if kindAcceptsKind kind .int then .kind kind else disjOfValues (.intLe maximum) (.kind kind)
  | .kind kind, .intLt maximum =>
      if kindAcceptsKind kind .int then .kind kind else disjOfValues (.kind kind) (.intLt maximum)
  | .intLt maximum, .kind kind =>
      if kindAcceptsKind kind .int then .kind kind else disjOfValues (.intLt maximum) (.kind kind)
  | .kind kind, .stringRegex pattern =>
      if kindAcceptsKind kind .string then .kind kind else disjOfValues (.kind kind) (.stringRegex pattern)
  | .stringRegex pattern, .kind kind =>
      if kindAcceptsKind kind .string then .kind kind else disjOfValues (.stringRegex pattern) (.kind kind)
  | .stringRegex pattern, .prim prim =>
      if containsBottom (meetStringRegexPrim pattern prim) then
        disjOfValues (.stringRegex pattern) (.prim prim)
      else
        .stringRegex pattern
  | .prim prim, .stringRegex pattern =>
      if containsBottom (meetStringRegexPrim pattern prim) then
        disjOfValues (.prim prim) (.stringRegex pattern)
      else
        .stringRegex pattern
  | .stringRegex leftPattern, .stringRegex rightPattern =>
      if leftPattern = rightPattern then
        .stringRegex leftPattern
      else
        disjOfValues (.stringRegex leftPattern) (.stringRegex rightPattern)
  | .builtinCall leftName leftArgs, .builtinCall rightName rightArgs =>
      if leftName = rightName && leftArgs == rightArgs then
        .builtinCall leftName leftArgs
      else
        disjOfValues (.builtinCall leftName leftArgs) (.builtinCall rightName rightArgs)
  | .prim leftPrim, .prim rightPrim => joinPrim leftPrim rightPrim
  | .disj leftAlternatives, .disj rightAlternatives =>
      normalizeDisj (leftAlternatives ++ rightAlternatives)
  | .disj alternatives, value =>
      normalizeDisj (alternatives ++ [(.regular, value)])
  | value, .disj alternatives =>
      normalizeDisj ((.regular, value) :: alternatives)
  | value, other => disjOfValues value other

end Kue
