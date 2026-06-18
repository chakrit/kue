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

def escapeCueStringChar : Char -> List Char
  | '"' => ['\\', '"']
  | '\\' => ['\\', '\\']
  | '\n' => ['\\', 'n']
  | '\r' => ['\\', 'r']
  | '\t' => ['\\', 't']
  | value => [value]

def escapeCueStringChars : List Char -> List Char
  | [] => []
  | value :: values => escapeCueStringChar value ++ escapeCueStringChars values

def escapeCueStringContent (value : String) : String :=
  String.ofList (escapeCueStringChars value.toList)

def asciiCharBetween (lower upper value : Char) : Bool :=
  lower.toNat <= value.toNat && value.toNat <= upper.toNat

def isCueIdentifierStart (value : Char) : Bool :=
  asciiCharBetween 'a' 'z' value
    || asciiCharBetween 'A' 'Z' value
    || value == '_'
    || value == '#'

def isCueIdentifierRest (value : Char) : Bool :=
  isCueIdentifierStart value || asciiCharBetween '0' '9' value

def allCueIdentifierRest : List Char -> Bool
  | [] => true
  | value :: values => isCueIdentifierRest value && allCueIdentifierRest values

def isCueBareLabel (label : String) : Bool :=
  match label.toList with
  | [] => false
  | value :: values => isCueIdentifierStart value && allCueIdentifierRest values

def formatFieldLabel (label : String) : String :=
  if isCueBareLabel label then label else s!"\"{escapeCueStringContent label}\""

def formatPrim : Prim -> String
  | .null => "null"
  | .bool true => "true"
  | .bool false => "false"
  | .int value => toString value
  | .float value => value
  | .string value => s!"\"{escapeCueStringContent value}\""
  | .bytes value => "'" ++ value ++ "'"

def joinWith (separator : String) : List String -> String
  | [] => ""
  | [value] => value
  | value :: values => value ++ separator ++ joinWith separator values

def formatUnaryOp : UnaryOp -> String
  | .boolNot => "!"
  | .numPos => "+"
  | .numNeg => "-"

def formatBinaryOp : BinaryOp -> String
  | .add => "+"
  | .sub => "-"
  | .mul => "*"
  | .div => "/"
  | .intDiv => "div"
  | .intMod => "mod"
  | .intQuo => "quo"
  | .intRem => "rem"
  | .eq => "=="
  | .ne => "!="
  | .lt => "<"
  | .le => "<="
  | .gt => ">"
  | .ge => ">="
  | .regexMatch => "=~"
  | .regexNotMatch => "!~"
  | .boolAnd => "&&"
  | .boolOr => "||"

def formatFuel : Nat :=
  100

mutual
  def formatAlternativeWithFuel : Nat -> Mark × Value -> String
    | 0, _ => "..."
    | fuel + 1, (.regular, value) => formatValueWithFuel fuel value
    | fuel + 1, (.default, value) => "*" ++ formatValueWithFuel fuel value

  def formatStructFieldWithFuel? : Nat -> Field -> Option String
    | 0, _ => some "..."
    | fuel + 1, field =>
        let label := formatFieldLabel (Field.label field)
        let value := formatValueWithFuel fuel (Field.value field)
        match Field.fieldClass field with
        | .letBinding => none
        | .field _ _ optionality =>
            let suffix :=
              match optionality with
              | .optional => "?"
              | .required => "!"
              | .regular => ""
            some s!"{label}{suffix}: {value}"

  def formatStructFieldsWithFuel : Nat -> List Field -> List String
    | 0, _ => ["..."]
    | _ + 1, [] => []
    | fuel + 1, field :: fields =>
        match formatStructFieldWithFuel? fuel field with
        | some text => text :: formatStructFieldsWithFuel fuel fields
        | none => formatStructFieldsWithFuel fuel fields

  def formatTailWithFuel : Nat -> Value -> String
    | 0, _ => "..."
    | _ + 1, .top => "..."
    | fuel + 1, tail => "..." ++ formatValueWithFuel fuel tail

  def formatUnaryOperandWithFuel : Nat -> Value -> String
    | 0, _ => "..."
    | fuel + 1, value =>
        match value with
        | .binary _ _ _ => "(" ++ formatValueWithFuel fuel value ++ ")"
        | _ => formatValueWithFuel fuel value

  def formatValueWithFuel : Nat -> Value -> String
    | 0, _ => "..."
    | _, .top => "_"
    | _, .bottom => "_|_"
    | _, .bottomWith _ => "_|_"
    | _, .prim prim => formatPrim prim
    | _, .kind kind => formatKind kind
    | _, .notPrim prim => "!=" ++ formatPrim prim
    | _, .stringRegex pattern => s!"=~\"{escapeCueStringContent pattern}\""
    | _, .boundConstraint bound kind _ => kind.symbol ++ formatBoundLimit bound
    | fuel + 1, .conj constraints =>
        joinWith " & " (constraints.map (formatValueWithFuel fuel))
    | fuel + 1, .builtinCall name args =>
        name ++ "(" ++ joinWith ", " (args.map (formatValueWithFuel fuel)) ++ ")"
    | fuel + 1, .unary op value =>
        formatUnaryOp op ++ formatUnaryOperandWithFuel fuel value
    | fuel + 1, .binary op left right =>
        formatValueWithFuel fuel left
          ++ " "
          ++ formatBinaryOp op
          ++ " "
          ++ formatValueWithFuel fuel right
    | _, .ref label => label
    | _, .refId id => s!"@{id.depth}.{id.index}"
    | _, .thisStruct => "@self"
    | fuel + 1, .selector base label =>
        formatValueWithFuel fuel base ++ "." ++ formatFieldLabel label
    | fuel + 1, .index base key =>
        formatValueWithFuel fuel base ++ "[" ++ formatValueWithFuel fuel key ++ "]"
    | fuel + 1, .disj alternatives =>
        joinWith " | " (alternatives.map (formatAlternativeWithFuel fuel))
    | fuel + 1, .struct fields _ =>
        "{" ++ joinWith ", " (formatStructFieldsWithFuel fuel fields) ++ "}"
    | fuel + 1, .structTail fields tail =>
        let fieldText := formatStructFieldsWithFuel fuel fields
        let tailText := formatTailWithFuel fuel tail
        "{" ++ joinWith ", " (fieldText ++ [tailText]) ++ "}"
    | fuel + 1, .structPattern fields labelPattern constraint _ =>
        let fieldText := formatStructFieldsWithFuel fuel fields
        let patternText :=
          "[" ++ formatValueWithFuel fuel labelPattern ++ "]: " ++ formatValueWithFuel fuel constraint
        "{" ++ joinWith ", " (fieldText ++ [patternText]) ++ "}"
    | fuel + 1, .structPatterns fields patterns _ =>
        let fieldText := formatStructFieldsWithFuel fuel fields
        let patternText := patterns.map fun pattern =>
          "[" ++ formatValueWithFuel fuel pattern.fst ++ "]: " ++ formatValueWithFuel fuel pattern.snd
        "{" ++ joinWith ", " (fieldText ++ patternText) ++ "}"
    -- B2.1 dead arm (no producer yet); filled in B2.3. Mirrors the four legacy struct
    -- arms above: fields, then patterns, then the optional `...` tail, all inside `{…}`.
    | fuel + 1, .structN fields _ tail patterns =>
        let fieldText := formatStructFieldsWithFuel fuel fields
        let patternText := patterns.map fun pattern =>
          "[" ++ formatValueWithFuel fuel pattern.fst ++ "]: " ++ formatValueWithFuel fuel pattern.snd
        let tailText :=
          match tail with
          | none => []
          | some t => [formatTailWithFuel fuel t]
        "{" ++ joinWith ", " (fieldText ++ patternText ++ tailText) ++ "}"
    | fuel + 1, .list items =>
        "[" ++ joinWith ", " (items.map (formatValueWithFuel fuel)) ++ "]"
    | fuel + 1, .listTail items tail =>
        let itemText := items.map (formatValueWithFuel fuel)
        let tailText := formatTailWithFuel fuel tail
        "[" ++ joinWith ", " (itemText ++ [tailText]) ++ "]"
    | fuel + 1, .embeddedList items tail decls =>
        let declText := formatStructFieldsWithFuel fuel decls
        let itemText := items.map (formatValueWithFuel fuel)
        let listInner :=
          match tail with
          | none => itemText
          | some t => itemText ++ [formatTailWithFuel fuel t]
        let listText := "[" ++ joinWith ", " listInner ++ "]"
        "{" ++ joinWith ", " (declText ++ [listText]) ++ "}"
    | fuel + 1, .comprehension clauses body =>
        joinWith " " (clauses.map (formatClauseWithFuel fuel)) ++ " " ++ formatValueWithFuel fuel body
    | fuel + 1, .listComprehension clauses body =>
        joinWith " " (clauses.map (formatClauseWithFuel fuel)) ++ " " ++ formatValueWithFuel fuel body
    | fuel + 1, .structComp fields comprehensions _ _ =>
        let fieldText := formatStructFieldsWithFuel fuel fields
        let compText := comprehensions.map (formatValueWithFuel fuel)
        "{" ++ joinWith ", " (fieldText ++ compText) ++ "}"
    | fuel + 1, .interpolation parts =>
        "\"\\(" ++ joinWith ")\\(" (parts.map (formatValueWithFuel fuel)) ++ ")\""
    | fuel + 1, .dynamicField label fieldClass value =>
        let suffix :=
          match FieldClass.optionality fieldClass with
          | .optional => "?"
          | .required => "!"
          | .regular => ""
        "(" ++ formatValueWithFuel fuel label ++ ")" ++ suffix ++ ": " ++ formatValueWithFuel fuel value
    | fuel + 1, .closure _ body =>
        -- a closure prints as its deferred body; the captured env is internal machinery,
        -- not surface syntax.
        formatValueWithFuel fuel body

  def formatClauseWithFuel : Nat -> Clause Value -> String
    | 0, _ => "..."
    | fuel + 1, .forIn (some key) value source =>
        s!"for {key}, {value} in " ++ formatValueWithFuel fuel source
    | fuel + 1, .forIn none value source =>
        s!"for {value} in " ++ formatValueWithFuel fuel source
    | fuel + 1, .guard condition =>
        "if " ++ formatValueWithFuel fuel condition
end

def formatStructFieldWithFuel (fuel : Nat) (field : Field) : String :=
  match formatStructFieldWithFuel? fuel field with
  | some text => text
  | none => ""

def formatValue (value : Value) : String :=
  formatValueWithFuel formatFuel value

end Kue
