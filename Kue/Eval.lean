import Kue.Builtin
import Kue.Lattice
import Kue.Normalize

namespace Kue

def findEvalField (label : String) : List Field -> Option Field
  | [] => none
  | field :: fields =>
      if Field.label field = label then
        some field
      else
        findEvalField label fields

def buildBindingEnvFrom (index : Nat) : List Field -> List (BindingId × Field)
  | [] => []
  | field :: fields => (⟨index⟩, field) :: buildBindingEnvFrom (index + 1) fields

def buildBindingEnv (fields : List Field) : List (BindingId × Field) :=
  buildBindingEnvFrom 0 fields

def findBinding (id : BindingId) : List (BindingId × Field) -> Option Field
  | [] => none
  | binding :: bindings =>
      if binding.fst == id then
        some binding.snd
      else
        findBinding id bindings

def bindingVisited (id : BindingId) : List BindingId -> Bool
  | [] => false
  | visited :: rest =>
      if visited == id then
        true
      else
        bindingVisited id rest

def evalFuel : Nat :=
  100

def applyEvaluatedStructPattern
    (fields : List Field)
    (labelPattern constraint : Value)
    (open_ : Bool) : Value :=
  meet (.structPattern [] labelPattern constraint open_) (.struct fields true)

def applyEvaluatedStructPatterns
    (fields : List Field)
    (patterns : List (Value × Value))
    (open_ : Bool) : Value :=
  meet (.structPatterns [] patterns open_) (.struct fields true)

def allRegularAlternatives : List (Mark × Value) -> Bool
  | [] => true
  | alternative :: alternatives =>
      alternative.fst == .regular && allRegularAlternatives alternatives

def joinValues : List Value -> Value
  | [] => .bottom
  | value :: values => values.foldl join value

def mergeEvaluatedFields (fields : List Field) : Option (List Field) :=
  mergeFieldListWith meet fields

def normalizeEvaluatedDisj (alternatives : List (Mark × Value)) : Value :=
  if allRegularAlternatives alternatives then
    joinValues (alternatives.map Prod.snd)
  else
    .disj alternatives

def selectEvaluatedField (base : Value) (label : String) : Value :=
  match base with
  | .struct fields _ =>
      match findEvalField label fields with
      | some field => Field.value field
      | none => .selector base label
  | .structTail fields _ =>
      match findEvalField label fields with
      | some field => Field.value field
      | none => .selector base label
  | .structPattern fields _ _ _ =>
      match findEvalField label fields with
      | some field => Field.value field
      | none => .selector base label
  | .structPatterns fields _ _ =>
      match findEvalField label fields with
      | some field => Field.value field
      | none => .selector base label
  | .bottom => .bottom
  | .bottomWith reasons => .bottomWith reasons
  | _ => .bottom

def getListValue? : Nat -> List Value -> Option Value
  | _, [] => none
  | 0, value :: _ => some value
  | index + 1, _ :: values => getListValue? index values

def selectEvaluatedListIndex (base key : Value) (items : List Value) : Value :=
  match key with
  | .prim (.int index) =>
      if index < 0 then
        .bottomWith [.invalidIndex index]
      else
        match getListValue? index.toNat items with
        | some item => item
        | none => .bottomWith [.indexOutOfRange index items.length]
  | .prim _ => .bottom
  | _ => .index base key

def selectEvaluatedListTailIndex (base key : Value) (items : List Value) : Value :=
  match key with
  | .prim (.int index) =>
      if index < 0 then
        .bottomWith [.invalidIndex index]
      else
        match getListValue? index.toNat items with
        | some item => item
        | none => .index base key
  | .prim _ => .bottom
  | _ => .index base key

def selectEvaluatedFieldIndex (base key : Value) (fields : List Field) : Value :=
  match key with
  | .prim (.string label) =>
      match findEvalField label fields with
      | some field => Field.value field
      | none => .index base key
  | .prim _ => .bottom
  | _ => .index base key

def selectEvaluatedIndex (base key : Value) : Value :=
  match base with
  | .struct fields _ => selectEvaluatedFieldIndex base key fields
  | .structTail fields _ => selectEvaluatedFieldIndex base key fields
  | .structPattern fields _ _ _ => selectEvaluatedFieldIndex base key fields
  | .structPatterns fields _ _ => selectEvaluatedFieldIndex base key fields
  | .list items => selectEvaluatedListIndex base key items
  | .listTail items _ => selectEvaluatedListTailIndex base key items
  | .bottom => .bottom
  | .bottomWith reasons => .bottomWith reasons
  | _ => .bottom

def evalAdd (left right : Value) : Value :=
  match left, right with
  | .prim (.int left), .prim (.int right) => .prim (.int (left + right))
  | .prim (.string left), .prim (.string right) => .prim (.string (left ++ right))
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
  | .prim _, .prim _ => .bottom
  | _, _ => .binary .add left right

def evalSub (left right : Value) : Value :=
  match left, right with
  | .prim (.int left), .prim (.int right) => .prim (.int (left - right))
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
  | .prim _, .prim _ => .bottom
  | _, _ => .binary .sub left right

def evalMul (left right : Value) : Value :=
  match left, right with
  | .prim (.int left), .prim (.int right) => .prim (.int (left * right))
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
  | .prim _, .prim _ => .bottom
  | _, _ => .binary .mul left right

def decimalPrecision : Nat :=
  34

def joinStrings : List String -> String
  | [] => ""
  | value :: values => value ++ joinStrings values

def intAbsNat (value : Int) : Nat :=
  if value < 0 then
    (-value).toNat
  else
    value.toNat

def rationalIsNegative (numerator denominator : Int) : Bool :=
  (numerator < 0 && 0 < denominator) || (0 < numerator && denominator < 0)

def decimalFractionDigits : Nat -> Nat -> Nat -> List String
  | 0, _, _ => []
  | _, 0, _ => []
  | fuel + 1, remainder, denominator =>
      let scaled := remainder * 10
      let digit := scaled / denominator
      let next := scaled % denominator
      toString digit :: decimalFractionDigits fuel next denominator

def formatIntegerDivision (numerator denominator : Int) : String :=
  let numeratorAbs := intAbsNat numerator
  let denominatorAbs := intAbsNat denominator
  let quotient := numeratorAbs / denominatorAbs
  let remainder := numeratorAbs % denominatorAbs
  let sign := if rationalIsNegative numerator denominator then "-" else ""
  if remainder == 0 then
    sign ++ toString quotient ++ ".0"
  else
    sign ++ toString quotient ++ "." ++ joinStrings (decimalFractionDigits decimalPrecision remainder denominatorAbs)

def evalDiv (left right : Value) : Value :=
  match left, right with
  | .prim (.int _), .prim (.int 0) => .bottomWith [.divisionByZero]
  | .prim (.int left), .prim (.int right) => .prim (.float (formatIntegerDivision left right))
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
  | .prim _, .prim _ => .bottom
  | _, _ => .binary .div left right

def evalEq (left right : Value) : Value :=
  match left, right with
  | .prim left, .prim right => .prim (.bool (left == right))
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
  | _, _ => .binary .eq left right

def evalNe (left right : Value) : Value :=
  match evalEq left right with
  | .prim (.bool value) => .prim (.bool (!value))
  | .binary .eq left right => .binary .ne left right
  | value => value

def charsLt : List Char -> List Char -> Bool
  | [], [] => false
  | [], _ :: _ => true
  | _ :: _, [] => false
  | left :: leftRest, right :: rightRest =>
      if left.toNat == right.toNat then
        charsLt leftRest rightRest
      else
        left.toNat < right.toNat

def stringsLt (left right : String) : Bool :=
  charsLt left.toList right.toList

def evalPrimitiveOrdering
    (intOp : Int -> Int -> Bool)
    (stringOp : String -> String -> Bool)
    (op : BinaryOp)
    (left right : Value) : Value :=
  match left, right with
  | .prim (.int left), .prim (.int right) => .prim (.bool (intOp left right))
  | .prim (.string left), .prim (.string right) => .prim (.bool (stringOp left right))
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
  | .prim _, .prim _ => .bottom
  | _, _ => .binary op left right

def evalBoolBinary (op : BinaryOp) (boolOp : Bool -> Bool -> Bool) (left right : Value) : Value :=
  match left, right with
  | .prim (.bool left), .prim (.bool right) => .prim (.bool (boolOp left right))
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
  | .prim _, .prim _ => .bottom
  | _, _ => .binary op left right

def evalBinary (op : BinaryOp) (left right : Value) : Value :=
  match op with
  | .add => evalAdd left right
  | .sub => evalSub left right
  | .mul => evalMul left right
  | .div => evalDiv left right
  | .eq => evalEq left right
  | .ne => evalNe left right
  | .lt => evalPrimitiveOrdering (fun left right => left < right) stringsLt .lt left right
  | .le => evalPrimitiveOrdering (fun left right => left <= right) (fun left right => !stringsLt right left) .le left right
  | .gt => evalPrimitiveOrdering (fun left right => left > right) (fun left right => stringsLt right left) .gt left right
  | .ge => evalPrimitiveOrdering (fun left right => left >= right) (fun left right => !stringsLt left right) .ge left right
  | .boolAnd => evalBoolBinary .boolAnd (fun left right => left && right) left right
  | .boolOr => evalBoolBinary .boolOr (fun left right => left || right) left right

mutual
  def evalFieldRefsWithFuel
      (fuel : Nat)
      (fields : List Field)
      (bindings : List (BindingId × Field))
      (visited : List BindingId)
      (field : Field) : Field :=
    (Field.label field, Field.fieldClass field, evalValueWithFuel fuel fields bindings visited (Field.value field))

  def evalValueWithFuel : Nat -> List Field -> List (BindingId × Field) -> List BindingId -> Value -> Value
    | 0, _, _, _, value => value
    | _ + 1, fields, _, _, .ref label =>
        match findEvalField label fields with
        | some field => Field.value field
        | none => .bottomWith [.unresolvedReference label]
    | fuel + 1, fields, bindings, visited, .refId id =>
        if bindingVisited id visited then
          .top
        else
          match findBinding id bindings with
          | some field => evalValueWithFuel fuel fields bindings (id :: visited) (Field.value field)
          | none => .bottomWith [.unresolvedBinding id]
    | fuel + 1, fields, bindings, visited, .conj constraints =>
        let evaluated := constraints.map (evalValueWithFuel fuel fields bindings visited)
        evaluated.foldl (fun current constraint => meet current constraint) .top
    | fuel + 1, fields, bindings, visited, .builtinCall name args =>
        evalBuiltinCall name (args.map (evalValueWithFuel fuel fields bindings visited))
    | fuel + 1, fields, bindings, visited, .binary op left right =>
        evalBinary op
          (evalValueWithFuel fuel fields bindings visited left)
          (evalValueWithFuel fuel fields bindings visited right)
    | fuel + 1, fields, bindings, visited, .selector base label =>
        selectEvaluatedField (evalValueWithFuel fuel fields bindings visited base) label
    | fuel + 1, fields, bindings, visited, .index base key =>
        selectEvaluatedIndex
          (evalValueWithFuel fuel fields bindings visited base)
          (evalValueWithFuel fuel fields bindings visited key)
    | fuel + 1, fields, bindings, visited, .disj alternatives =>
        let evaluated := alternatives.map fun alternative =>
          (alternative.fst, evalValueWithFuel fuel fields bindings visited alternative.snd)
        normalizeEvaluatedDisj evaluated
    | fuel + 1, fields, _, _, .struct nestedFields open_ =>
        let nestedBindings := buildBindingEnv nestedFields
        let visibleFields := nestedFields ++ fields
        match mergeEvaluatedFields
          (nestedBindings.map fun binding =>
            evalFieldRefsWithFuel fuel visibleFields nestedBindings [binding.fst] binding.snd) with
        | some nestedFields => .struct nestedFields open_
        | none => .bottom
    | fuel + 1, fields, _, _, .structTail nestedFields tail =>
        let nestedBindings := buildBindingEnv nestedFields
        let visibleFields := nestedFields ++ fields
        match mergeEvaluatedFields
          (nestedBindings.map fun binding =>
            evalFieldRefsWithFuel fuel visibleFields nestedBindings [binding.fst] binding.snd) with
        | some nestedFields =>
            .structTail nestedFields (evalValueWithFuel fuel visibleFields nestedBindings [] tail)
        | none => .bottom
    | fuel + 1, fields, _, _, .structPattern nestedFields labelPattern constraint open_ =>
        let nestedBindings := buildBindingEnv nestedFields
        let visibleFields := nestedFields ++ fields
        match mergeEvaluatedFields
          (nestedBindings.map fun binding =>
            evalFieldRefsWithFuel fuel visibleFields nestedBindings [binding.fst] binding.snd) with
        | some nestedFields =>
            applyEvaluatedStructPattern
              nestedFields
              (evalValueWithFuel fuel visibleFields nestedBindings [] labelPattern)
              (evalValueWithFuel fuel visibleFields nestedBindings [] constraint)
              open_
        | none => .bottom
    | fuel + 1, fields, _, _, .structPatterns nestedFields patterns open_ =>
        let nestedBindings := buildBindingEnv nestedFields
        let visibleFields := nestedFields ++ fields
        match mergeEvaluatedFields
          (nestedBindings.map fun binding =>
            evalFieldRefsWithFuel fuel visibleFields nestedBindings [binding.fst] binding.snd) with
        | some nestedFields =>
            applyEvaluatedStructPatterns
              nestedFields
              (patterns.map fun pattern =>
                (
                  evalValueWithFuel fuel visibleFields nestedBindings [] pattern.fst,
                  evalValueWithFuel fuel visibleFields nestedBindings [] pattern.snd
                ))
              open_
        | none => .bottom
    | fuel + 1, fields, bindings, visited, .list items =>
        .list (items.map (evalValueWithFuel fuel fields bindings visited))
    | fuel + 1, fields, bindings, visited, .listTail items tail =>
        .listTail
          (items.map (evalValueWithFuel fuel fields bindings visited))
          (evalValueWithFuel fuel fields bindings visited tail)
    | _, _, _, _, value => value
end

def evalFieldRefs (fields : List Field) (bindings : List (BindingId × Field)) (field : Field) : Field :=
  evalFieldRefsWithFuel evalFuel fields bindings [] field

def evalBindingField (fields : List Field) (bindings : List (BindingId × Field)) (binding : BindingId × Field) : Field :=
  evalFieldRefsWithFuel evalFuel fields bindings [binding.fst] binding.snd

def evalStructRefs (value : Value) : Value :=
  match normalizeDefinitions value with
  | .struct fields open_ =>
      let bindings := buildBindingEnv fields
      match mergeEvaluatedFields (bindings.map (evalBindingField fields bindings)) with
      | some fields => .struct fields open_
      | none => .bottom
  | .structTail fields tail =>
      let bindings := buildBindingEnv fields
      match mergeEvaluatedFields (bindings.map (evalBindingField fields bindings)) with
      | some fields => .structTail fields (evalValueWithFuel evalFuel fields bindings [] tail)
      | none => .bottom
  | .structPattern fields labelPattern constraint open_ =>
      let bindings := buildBindingEnv fields
      match mergeEvaluatedFields (bindings.map (evalBindingField fields bindings)) with
      | some fields =>
          applyEvaluatedStructPattern
            fields
            (evalValueWithFuel evalFuel fields bindings [] labelPattern)
            (evalValueWithFuel evalFuel fields bindings [] constraint)
            open_
      | none => .bottom
  | .structPatterns fields patterns open_ =>
      let bindings := buildBindingEnv fields
      match mergeEvaluatedFields (bindings.map (evalBindingField fields bindings)) with
      | some fields =>
          applyEvaluatedStructPatterns
            fields
            (patterns.map fun pattern =>
              (
                evalValueWithFuel evalFuel fields bindings [] pattern.fst,
                evalValueWithFuel evalFuel fields bindings [] pattern.snd
              ))
            open_
      | none => .bottom
  | value => value

end Kue
