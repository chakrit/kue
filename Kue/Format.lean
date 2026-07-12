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

/-- A single lowercase hex digit for `n < 16`. -/
def hexDigitChar (n : Nat) : Char :=
  if n < 10 then Char.ofNat (n + '0'.toNat) else Char.ofNat (n - 10 + 'a'.toNat)

/-- Render one byte inside a byte literal: the common controls take their named escape
    (`\n\r\t`); `'` and `\` are backslash-escaped; a printable ASCII byte prints as itself;
    every other byte (control or ≥ 0x80) prints as a `\xNN` hex escape. Every case
    round-trips through `parseQuotedBytes`. -/
def formatByte (byte : UInt8) : String :=
  if byte == 0x0a then "\\n"
  else if byte == 0x0d then "\\r"
  else if byte == 0x09 then "\\t"
  else if byte == 0x27 then "\\'"
  else if byte == 0x5c then "\\\\"
  else if 0x20 <= byte && byte <= 0x7e then String.singleton (Char.ofNat byte.toNat)
  else "\\x" ++ String.ofList [hexDigitChar (byte.toNat / 16), hexDigitChar (byte.toNat % 16)]

/-- Render a byte value as a CUE byte literal (`'...'`), escaping non-printable/high bytes. -/
def formatBytesLiteral (bytes : Array UInt8) : String :=
  "'" ++ String.join (bytes.toList.map formatByte) ++ "'"

def formatPrim : Prim -> String
  | .null => "null"
  | .bool true => "true"
  | .bool false => "false"
  | .int value => toString value
  | .float _ text => renderFloatText cueFloatStyle text
  | .string value => s!"\"{escapeCueStringContent value}\""
  | .bytes value => formatBytesLiteral value

/-- Render a bound's ordered operand as CUE prints it after the comparator. A numeric limit
    prints as a trimmed finite decimal (`>0`, `>0.5`, never force-floated to `>0.0`); a
    string/bytes limit prints as its quoted literal (`<"m"`, `<'m'`). -/
def formatBoundOperand : Prim -> String
  | .int value => toString value
  | .float value _ => formatFiniteDecimal value false
  | prim => formatPrim prim

def joinWith (separator : String) : List String -> String
  | [] => ""
  | [value] => value
  | value :: values => value ++ separator ++ joinWith separator values

def formatUnaryOp : UnaryOp -> String
  | .boolNot => "!"
  | .numPos => "+"
  | .numNeg => "-"
  | .boundOp kind => kind.symbol
  | .neOp => "!="
  | .regexMatchOp => "=~"

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
        | .importBinding => none
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
    | _, .boundConstraint bound kind _ => kind.symbol ++ formatBoundOperand bound
    | _, .lengthConstraint kind bound limit =>
        let call := match kind, bound with
          | .fields, .min => "struct.MinFields"
          | .fields, .max => "struct.MaxFields"
          | .listItems, .min => "list.MinItems"
          | .listItems, .max => "list.MaxItems"
          | .runes, .min => "strings.MinRunes"
          | .runes, .max => "strings.MaxRunes"
        s!"{call}({limit})"
    | _, .uniqueItems => "list.UniqueItems()"
    | _, .stringFormat .duration => "time.Duration()"
    | _, .stringFormat .rfc3339 => "time.Time()"
    | _, .stringFormat .netIP => "net.IP()"
    | _, .stringFormat .netIPv4 => "net.IPv4()"
    | _, .stringFormat .netIPv6 => "net.IPv6()"
    | _, .stringFormat .netIPCIDR => "net.IPCIDR()"
    | _, .stringFormat .netLoopbackIP => "net.LoopbackIP()"
    | _, .stringFormat .netMulticastIP => "net.MulticastIP()"
    | _, .stringFormat .netInterfaceLocalMulticastIP => "net.InterfaceLocalMulticastIP()"
    | _, .stringFormat .netLinkLocalMulticastIP => "net.LinkLocalMulticastIP()"
    | _, .stringFormat .netLinkLocalUnicastIP => "net.LinkLocalUnicastIP()"
    | _, .stringFormat .netGlobalUnicastIP => "net.GlobalUnicastIP()"
    | _, .stringFormat .netUnspecifiedIP => "net.UnspecifiedIP()"
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
    | _, .refId id => s!"@{id.depth.val}.{id.index.val}"
    | _, .patternLabel name => name
    | _, .thisStruct => "@self"
    | fuel + 1, .selector base label =>
        formatValueWithFuel fuel base ++ "." ++ formatFieldLabel label
    | fuel + 1, .index base key =>
        formatValueWithFuel fuel base ++ "[" ++ formatValueWithFuel fuel key ++ "]"
    | fuel + 1, .disj alternatives =>
        joinWith " | " (alternatives.map (formatAlternativeWithFuel fuel))
    -- Fields, then patterns, then the optional `...` tail, all inside `{…}`.
    | fuel + 1, .struct fields _ tail patterns _ =>
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
    | fuel + 1, .embeddedScalar scalar decls =>
        let declText := formatStructFieldsWithFuel fuel decls
        let scalarText := formatValueWithFuel fuel scalar
        "{" ++ joinWith ", " (declText ++ [scalarText]) ++ "}"
    | fuel + 1, .comprehension clauses body =>
        joinWith " " (clauses.map (formatClauseWithFuel fuel)) ++ " " ++ formatValueWithFuel fuel body
    | fuel + 1, .listComprehension clauses body =>
        joinWith " " (clauses.map (formatClauseWithFuel fuel)) ++ " " ++ formatValueWithFuel fuel body
    | fuel + 1, .structComp fields comprehensions _ =>
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
    | fuel + 1, .letClause name value =>
        s!"let {name} = " ++ formatValueWithFuel fuel value
end

def formatStructFieldWithFuel (fuel : Nat) (field : Field) : String :=
  match formatStructFieldWithFuel? fuel field with
  | some text => text
  | none => ""

def formatValue (value : Value) : String :=
  formatValueWithFuel formatFuel value

end Kue
