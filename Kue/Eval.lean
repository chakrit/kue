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
        .conj (constraints.map (evalValueWithFuel fuel fields bindings visited))
    | fuel + 1, fields, bindings, visited, .disj alternatives =>
        .disj (alternatives.map fun alternative =>
          (alternative.fst, evalValueWithFuel fuel fields bindings visited alternative.snd)
        )
    | fuel + 1, fields, bindings, visited, .struct nestedFields open_ =>
        .struct (nestedFields.map (evalFieldRefsWithFuel fuel fields bindings visited)) open_
    | fuel + 1, fields, bindings, visited, .structTail nestedFields tail =>
        .structTail
          (nestedFields.map (evalFieldRefsWithFuel fuel fields bindings visited))
          (evalValueWithFuel fuel fields bindings visited tail)
    | fuel + 1, fields, bindings, visited, .structPattern nestedFields labelPattern constraint =>
        .structPattern
          (nestedFields.map (evalFieldRefsWithFuel fuel fields bindings visited))
          (evalValueWithFuel fuel fields bindings visited labelPattern)
          (evalValueWithFuel fuel fields bindings visited constraint)
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
      .struct (bindings.map (evalBindingField fields bindings)) open_
  | .structTail fields tail =>
      let bindings := buildBindingEnv fields
      .structTail
        (bindings.map (evalBindingField fields bindings))
        (evalValueWithFuel evalFuel fields bindings [] tail)
  | .structPattern fields labelPattern constraint =>
      let bindings := buildBindingEnv fields
      .structPattern
        (bindings.map (evalBindingField fields bindings))
        (evalValueWithFuel evalFuel fields bindings [] labelPattern)
        (evalValueWithFuel evalFuel fields bindings [] constraint)
  | value => value

end Kue
