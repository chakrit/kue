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

def evalFuel : Nat :=
  100

mutual
  def evalFieldRefsWithFuel
      (fuel : Nat)
      (fields : List Field)
      (bindings : List (BindingId × Field))
      (current : Option BindingId)
      (field : Field) : Field :=
    (Field.label field, Field.fieldClass field, evalValueWithFuel fuel fields bindings current (Field.value field))

  def evalValueWithFuel : Nat -> List Field -> List (BindingId × Field) -> Option BindingId -> Value -> Value
    | 0, _, _, _, value => value
    | _ + 1, fields, _, _, .ref label =>
        match findEvalField label fields with
        | some field => Field.value field
        | none => .bottomWith [.unresolvedReference label]
    | _ + 1, _, bindings, current, .refId id =>
        if some id == current then
          .top
        else
          match findBinding id bindings with
          | some field => Field.value field
          | none => .bottomWith [.unresolvedBinding id]
    | fuel + 1, fields, bindings, current, .conj constraints =>
        .conj (constraints.map (evalValueWithFuel fuel fields bindings current))
    | fuel + 1, fields, bindings, current, .disj alternatives =>
        .disj (alternatives.map fun alternative =>
          (alternative.fst, evalValueWithFuel fuel fields bindings current alternative.snd)
        )
    | fuel + 1, fields, bindings, current, .struct nestedFields open_ =>
        .struct (nestedFields.map (evalFieldRefsWithFuel fuel fields bindings current)) open_
    | fuel + 1, fields, bindings, current, .structTail nestedFields tail =>
        .structTail
          (nestedFields.map (evalFieldRefsWithFuel fuel fields bindings current))
          (evalValueWithFuel fuel fields bindings current tail)
    | fuel + 1, fields, bindings, current, .list items =>
        .list (items.map (evalValueWithFuel fuel fields bindings current))
    | fuel + 1, fields, bindings, current, .listTail items tail =>
        .listTail
          (items.map (evalValueWithFuel fuel fields bindings current))
          (evalValueWithFuel fuel fields bindings current tail)
    | _, _, _, _, value => value
end

def evalFieldRefs (fields : List Field) (bindings : List (BindingId × Field)) (field : Field) : Field :=
  evalFieldRefsWithFuel evalFuel fields bindings none field

def evalBindingField (fields : List Field) (bindings : List (BindingId × Field)) (binding : BindingId × Field) : Field :=
  evalFieldRefsWithFuel evalFuel fields bindings (some binding.fst) binding.snd

def evalStructRefs (value : Value) : Value :=
  match normalizeDefinitions value with
  | .struct fields open_ =>
      let bindings := buildBindingEnv fields
      .struct (bindings.map (evalBindingField fields bindings)) open_
  | .structTail fields tail =>
      let bindings := buildBindingEnv fields
      .structTail (bindings.map (evalBindingField fields bindings)) tail
  | value => value

end Kue
