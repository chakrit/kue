import Kue.Value

namespace Kue

def meetPrim (left right : Prim) : Value :=
  if left = right then
    .prim left
  else
    .bottom

def isBottom : Value -> Bool
  | .bottom => true
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
  | .top, value => value
  | value, .top => value
  | .kind leftKind, .kind rightKind =>
      if leftKind = rightKind then
        .kind leftKind
      else
        .bottom
  | .kind kind, .prim prim =>
      if Prim.kind prim = kind then
        .prim prim
      else
        .bottom
  | .prim prim, .kind kind =>
      if Prim.kind prim = kind then
        .prim prim
      else
        .bottom
  | .prim leftPrim, .prim rightPrim => meetPrim leftPrim rightPrim
  | .struct _ _, .struct _ _ => .bottom
  | .disj _, _ => .bottom
  | _, .disj _ => .bottom
  | .struct .., _ => .bottom
  | _, .struct .. => .bottom

def mergeFieldValue (left right : Field) : Option Field :=
  if Field.fieldClass left == .regular && Field.fieldClass right == .regular then
    let value := meetCore (Field.value left) (Field.value right)
    if isBottom value then
      none
    else
      some (Field.regular (Field.label left) value)
  else
    none

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

def meet (left right : Value) : Value :=
  match left, right with
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .top, value => value
  | value, .top => value
  | .struct leftFields leftOpen, .struct rightFields rightOpen =>
      match mergeStructFields leftFields rightFields with
      | some fields => .struct fields (leftOpen || rightOpen)
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
