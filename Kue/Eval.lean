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
      (field : Field) : Field :=
    (Field.label field, Field.fieldClass field, evalValueWithFuel fuel fields bindings (Field.value field))

  def evalValueWithFuel : Nat -> List Field -> List (BindingId × Field) -> Value -> Value
    | 0, _, _, value => value
    | _ + 1, fields, _, .ref label =>
        match findEvalField label fields with
        | some field => Field.value field
        | none => .bottomWith [.unresolvedReference label]
    | _ + 1, _, bindings, .refId id =>
        match findBinding id bindings with
        | some field => Field.value field
        | none => .bottomWith [.unresolvedBinding id]
    | fuel + 1, fields, bindings, .conj constraints =>
        .conj (constraints.map (evalValueWithFuel fuel fields bindings))
    | fuel + 1, fields, bindings, .disj alternatives =>
        .disj (alternatives.map fun alternative =>
          (alternative.fst, evalValueWithFuel fuel fields bindings alternative.snd)
        )
    | fuel + 1, fields, bindings, .struct nestedFields open_ =>
        .struct (nestedFields.map (evalFieldRefsWithFuel fuel fields bindings)) open_
    | fuel + 1, fields, bindings, .structTail nestedFields tail =>
        .structTail
          (nestedFields.map (evalFieldRefsWithFuel fuel fields bindings))
          (evalValueWithFuel fuel fields bindings tail)
    | fuel + 1, fields, bindings, .list items =>
        .list (items.map (evalValueWithFuel fuel fields bindings))
    | fuel + 1, fields, bindings, .listTail items tail =>
        .listTail
          (items.map (evalValueWithFuel fuel fields bindings))
          (evalValueWithFuel fuel fields bindings tail)
    | _, _, _, value => value
end

def evalFieldRefs (fields : List Field) (bindings : List (BindingId × Field)) (field : Field) : Field :=
  evalFieldRefsWithFuel evalFuel fields bindings field

def evalStructRefs (value : Value) : Value :=
  match normalizeDefinitions value with
  | .struct fields open_ =>
      let bindings := buildBindingEnv fields
      .struct (fields.map (evalFieldRefs fields bindings)) open_
  | .structTail fields tail =>
      let bindings := buildBindingEnv fields
      .structTail (fields.map (evalFieldRefs fields bindings)) tail
  | value => value

end Kue
