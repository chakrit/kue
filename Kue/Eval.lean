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
    | fuel + 1, fields, bindings, visited, .selector base label =>
        selectEvaluatedField (evalValueWithFuel fuel fields bindings visited base) label
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
