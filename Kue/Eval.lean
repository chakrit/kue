import Kue.Normalize

namespace Kue

def findEvalField (label : String) : List Field -> Option Field
  | [] => none
  | field :: fields =>
      if Field.label field = label then
        some field
      else
        findEvalField label fields

def evalRefValue (fields : List Field) : Value -> Value
  | .ref label =>
      match findEvalField label fields with
      | some field => Field.value field
      | none => .bottomWith [.unresolvedReference label]
  | value => value

def evalFieldRefs (fields : List Field) (field : Field) : Field :=
  (Field.label field, Field.fieldClass field, evalRefValue fields (Field.value field))

def evalStructRefs (value : Value) : Value :=
  match normalizeDefinitions value with
  | .struct fields open_ => .struct (fields.map (evalFieldRefs fields)) open_
  | .structTail fields tail => .structTail (fields.map (evalFieldRefs fields)) tail
  | value => value

end Kue
