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

def evalRefValue (fields : List Field) (bindings : List (BindingId × Field)) : Value -> Value
  | .ref label =>
      match findEvalField label fields with
      | some field => Field.value field
      | none => .bottomWith [.unresolvedReference label]
  | .refId id =>
      match findBinding id bindings with
      | some field => Field.value field
      | none => .bottomWith [.unresolvedBinding id]
  | value => value

def evalFieldRefs (fields : List Field) (bindings : List (BindingId × Field)) (field : Field) : Field :=
  (Field.label field, Field.fieldClass field, evalRefValue fields bindings (Field.value field))

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
