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

def resolveFuel : Nat :=
  100

mutual
  def resolveFieldRefsWithFuel (fuel : Nat) (bindings : List (String × BindingId)) (field : Field) : Field :=
    (Field.label field, Field.fieldClass field, resolveValueWithFuel fuel bindings (Field.value field))

  def resolveValueWithFuel : Nat -> List (String × BindingId) -> Value -> Value
    | 0, _, value => value
    | _ + 1, bindings, .ref label =>
        match findLabelBinding label bindings with
        | some id => .refId id
        | none => .ref label
    | fuel + 1, bindings, .conj constraints =>
        .conj (constraints.map (resolveValueWithFuel fuel bindings))
    | fuel + 1, bindings, .disj alternatives =>
        .disj (alternatives.map fun alternative =>
          (alternative.fst, resolveValueWithFuel fuel bindings alternative.snd)
        )
    | fuel + 1, bindings, .struct fields open_ =>
        .struct (fields.map (resolveFieldRefsWithFuel fuel bindings)) open_
    | fuel + 1, bindings, .structTail fields tail =>
        .structTail
          (fields.map (resolveFieldRefsWithFuel fuel bindings))
          (resolveValueWithFuel fuel bindings tail)
    | fuel + 1, bindings, .structPattern fields labelPattern constraint =>
        .structPattern
          (fields.map (resolveFieldRefsWithFuel fuel bindings))
          (resolveValueWithFuel fuel bindings labelPattern)
          (resolveValueWithFuel fuel bindings constraint)
    | fuel + 1, bindings, .list items =>
        .list (items.map (resolveValueWithFuel fuel bindings))
    | fuel + 1, bindings, .listTail items tail =>
        .listTail
          (items.map (resolveValueWithFuel fuel bindings))
          (resolveValueWithFuel fuel bindings tail)
    | _, _, value => value
end

def resolveFieldRefs (bindings : List (String × BindingId)) (field : Field) : Field :=
  resolveFieldRefsWithFuel resolveFuel bindings field

def resolveStructRefs : Value -> Value
  | .struct fields open_ =>
      let bindings := buildLabelBindings fields
      .struct (fields.map (resolveFieldRefs bindings)) open_
  | .structTail fields tail =>
      let bindings := buildLabelBindings fields
      .structTail
        (fields.map (resolveFieldRefs bindings))
        (resolveValueWithFuel resolveFuel bindings tail)
  | .structPattern fields labelPattern constraint =>
      let bindings := buildLabelBindings fields
      .structPattern
        (fields.map (resolveFieldRefs bindings))
        (resolveValueWithFuel resolveFuel bindings labelPattern)
        (resolveValueWithFuel resolveFuel bindings constraint)
  | value => value

end Kue
