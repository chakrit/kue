import Kue.Value

namespace Kue

def buildLabelBindingsFrom (index : Nat) : List Field -> List (String × BindingId)
  | [] => []
  | field :: fields => (Field.label field, ⟨index⟩) :: buildLabelBindingsFrom (index + 1) fields

def buildLabelBindings (fields : List Field) : List (String × BindingId) :=
  buildLabelBindingsFrom 0 fields

def findLabelBinding (label : String) : List (String × BindingId) -> Option BindingId
  | [] => none
  | binding :: bindings =>
      if binding.fst = label then
        some binding.snd
      else
        findLabelBinding label bindings

def resolveRefValue (bindings : List (String × BindingId)) : Value -> Value
  | .ref label =>
      match findLabelBinding label bindings with
      | some id => .refId id
      | none => .ref label
  | value => value

def resolveFieldRefs (bindings : List (String × BindingId)) (field : Field) : Field :=
  (Field.label field, Field.fieldClass field, resolveRefValue bindings (Field.value field))

def resolveStructRefs : Value -> Value
  | .struct fields open_ =>
      let bindings := buildLabelBindings fields
      .struct (fields.map (resolveFieldRefs bindings)) open_
  | .structTail fields tail =>
      let bindings := buildLabelBindings fields
      .structTail (fields.map (resolveFieldRefs bindings)) tail
  | value => value

end Kue
