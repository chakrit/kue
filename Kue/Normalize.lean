import Kue.Value

namespace Kue

def normalizeFuel : Nat :=
  100

mutual
  def normalizeDefinitionValueWithFuel : Nat -> Value -> Value
    | 0, value => value
    | fuel + 1, .struct fields _ =>
        .struct (fields.map (normalizeFieldWithFuel fuel)) false
    | fuel + 1, .structPattern fields labelPattern constraint =>
        .structPattern
          (fields.map (normalizeFieldWithFuel fuel))
          (normalizeDefinitionValueWithFuel fuel labelPattern)
          (normalizeDefinitionValueWithFuel fuel constraint)
    | fuel + 1, .disj alternatives =>
        .disj (alternatives.map fun alternative =>
          (alternative.fst, normalizeDefinitionValueWithFuel fuel alternative.snd)
        )
    | fuel + 1, .builtinCall name args =>
        .builtinCall name (args.map (normalizeDefinitionValueWithFuel fuel))
    | _, value => value

  def normalizeFieldWithFuel : Nat -> Field -> Field
    | 0, field => field
    | fuel + 1, field =>
        if Field.fieldClass field == .definition then
          (Field.label field, Field.fieldClass field, normalizeDefinitionValueWithFuel fuel (Field.value field))
        else
          field

  def normalizeDefinitionsWithFuel : Nat -> Value -> Value
    | 0, value => value
    | fuel + 1, .struct fields open_ =>
        .struct (fields.map (normalizeFieldWithFuel fuel)) open_
    | fuel + 1, .structPattern fields labelPattern constraint =>
        .structPattern
          (fields.map (normalizeFieldWithFuel fuel))
          (normalizeDefinitionsWithFuel fuel labelPattern)
          (normalizeDefinitionsWithFuel fuel constraint)
    | fuel + 1, .disj alternatives =>
        .disj (alternatives.map fun alternative =>
          (alternative.fst, normalizeDefinitionsWithFuel fuel alternative.snd)
        )
    | fuel + 1, .builtinCall name args =>
        .builtinCall name (args.map (normalizeDefinitionsWithFuel fuel))
    | _, value => value
end

def normalizeDefinitions (value : Value) : Value :=
  normalizeDefinitionsWithFuel normalizeFuel value

end Kue
