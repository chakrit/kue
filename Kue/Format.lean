import Kue.Value

namespace Kue

def formatKind : Kind -> String
  | .null => "null"
  | .bool => "bool"
  | .number => "number"
  | .int => "int"
  | .float => "float"
  | .string => "string"
  | .bytes => "bytes"

def formatPrim : Prim -> String
  | .null => "null"
  | .bool true => "true"
  | .bool false => "false"
  | .int value => toString value
  | .float value => value
  | .string value => s!"\"{value}\""
  | .bytes value => "'" ++ value ++ "'"

def joinWith (separator : String) : List String -> String
  | [] => ""
  | [value] => value
  | value :: values => value ++ separator ++ joinWith separator values

def formatFuel : Nat :=
  100

mutual
  def formatAlternativeWithFuel : Nat -> Mark × Value -> String
    | 0, _ => "..."
    | fuel + 1, (.regular, value) => formatValueWithFuel fuel value
    | fuel + 1, (.default, value) => "*" ++ formatValueWithFuel fuel value

  def formatStructFieldWithFuel : Nat -> Field -> String
    | 0, _ => "..."
    | fuel + 1, field =>
        let label := Field.label field
        let value := formatValueWithFuel fuel (Field.value field)
        match Field.fieldClass field with
        | .regular => s!"{label}: {value}"
        | .optional => s!"{label}?: {value}"
        | .required => s!"{label}!: {value}"
        | .hidden => s!"{label}: {value}"
        | .definition => s!"{label}: {value}"

  def formatValueWithFuel : Nat -> Value -> String
    | 0, _ => "..."
    | _, .top => "_"
    | _, .bottom => "_|_"
    | _, .bottomWith _ => "_|_"
    | _, .prim prim => formatPrim prim
    | _, .kind kind => formatKind kind
    | _, .notPrim prim => "!=" ++ formatPrim prim
    | _, .stringRegex pattern => s!"=~\"{pattern}\""
    | _, .intGe minimum => s!">={minimum}"
    | _, .intGt minimum => s!">{minimum}"
    | _, .intLe maximum => s!"<={maximum}"
    | _, .intLt maximum => s!"<{maximum}"
    | fuel + 1, .conj constraints =>
        joinWith " & " (constraints.map (formatValueWithFuel fuel))
    | _, .ref label => label
    | _, .refId id => s!"@{id.index}"
    | fuel + 1, .disj alternatives =>
        joinWith " | " (alternatives.map (formatAlternativeWithFuel fuel))
    | fuel + 1, .struct fields _ =>
        "{" ++ joinWith ", " (fields.map (formatStructFieldWithFuel fuel)) ++ "}"
    | fuel + 1, .structTail fields tail =>
        let fieldText := fields.map (formatStructFieldWithFuel fuel)
        let tailText := "..." ++ formatValueWithFuel fuel tail
        "{" ++ joinWith ", " (fieldText ++ [tailText]) ++ "}"
    | fuel + 1, .structPattern fields labelPattern constraint =>
        let fieldText := fields.map (formatStructFieldWithFuel fuel)
        let patternText :=
          "[" ++ formatValueWithFuel fuel labelPattern ++ "]: " ++ formatValueWithFuel fuel constraint
        "{" ++ joinWith ", " (fieldText ++ [patternText]) ++ "}"
    | fuel + 1, .list items =>
        "[" ++ joinWith ", " (items.map (formatValueWithFuel fuel)) ++ "]"
    | fuel + 1, .listTail items tail =>
        let itemText := items.map (formatValueWithFuel fuel)
        let tailText := "..." ++ formatValueWithFuel fuel tail
        "[" ++ joinWith ", " (itemText ++ [tailText]) ++ "]"
end

def formatValue (value : Value) : String :=
  formatValueWithFuel formatFuel value

end Kue
