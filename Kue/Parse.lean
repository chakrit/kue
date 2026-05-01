import Init.Data.String.Search
import Kue.Value

namespace Kue

structure ParseError where
  message : String
deriving Repr, BEq, DecidableEq, Inhabited

abbrev ParseResult (α : Type) := Except ParseError (α × List Char)

def parseError (message : String) : Except ParseError α :=
  .error { message := message }

def parseOk (value : α) (rest : List Char) : ParseResult α :=
  .ok (value, rest)

def parseAsciiBetween (lower upper value : Char) : Bool :=
  lower.toNat <= value.toNat && value.toNat <= upper.toNat

def parseWhitespace (value : Char) : Bool :=
  value == ' ' || value == '\n' || value == '\r' || value == '\t'

def parseIdentifierStart (value : Char) : Bool :=
  parseAsciiBetween 'a' 'z' value
    || parseAsciiBetween 'A' 'Z' value
    || value == '_'
    || value == '#'

def parseIdentifierRest (value : Char) : Bool :=
  parseIdentifierStart value || parseAsciiBetween '0' '9' value

def parseDigit (value : Char) : Bool :=
  parseAsciiBetween '0' '9' value

def dropLine : List Char -> List Char
  | [] => []
  | '\n' :: rest => rest
  | _ :: rest => dropLine rest

def dropBlockComment : List Char -> List Char
  | [] => []
  | '*' :: '/' :: rest => rest
  | _ :: rest => dropBlockComment rest

partial def skipTrivia : List Char -> List Char
  | [] => []
  | '/' :: '/' :: rest => skipTrivia (dropLine rest)
  | '/' :: '*' :: rest => skipTrivia (dropBlockComment rest)
  | value :: rest =>
      if parseWhitespace value then
        skipTrivia rest
      else
        value :: rest

def dropPrefix? : List Char -> List Char -> Option (List Char)
  | [], rest => some rest
  | expected :: expectedRest, value :: rest =>
      if expected == value then dropPrefix? expectedRest rest else none
  | _ :: _, [] => none

def startsWithWord (word : String) (chars : List Char) : Bool :=
  match dropPrefix? word.toList chars with
  | some [] => true
  | some (value :: _) => !parseIdentifierRest value
  | none => false

partial def consumePackageClauses (chars : List Char) : List Char :=
  let trimmed := skipTrivia chars
  if startsWithWord "package" trimmed then
    consumePackageClauses (dropLine trimmed)
  else
    trimmed

def parseStringEscape : Char -> Char
  | 'n' => '\n'
  | 'r' => '\r'
  | 't' => '\t'
  | value => value

partial def parseQuotedWith (quote : Char) : List Char -> List Char -> ParseResult String
  | [], _ => parseError "unterminated string literal"
  | value :: rest, acc =>
      if value == quote then
        parseOk (String.ofList acc.reverse) rest
      else if value == '\\' then
        match rest with
        | [] => parseError "unterminated string escape"
        | escaped :: rest => parseQuotedWith quote rest (parseStringEscape escaped :: acc)
      else
        parseQuotedWith quote rest (value :: acc)

def parseQuotedString : List Char -> ParseResult String
  | '"' :: rest => parseQuotedWith '"' rest []
  | _ => parseError "expected string literal"

def parseQuotedLabel : List Char -> ParseResult String :=
  parseQuotedString

def takeWhileChars (predicate : Char -> Bool) : List Char -> List Char -> List Char × List Char
  | [], acc => (acc.reverse, [])
  | value :: rest, acc =>
      if predicate value then
        takeWhileChars predicate rest (value :: acc)
      else
        (acc.reverse, value :: rest)

def parseIdentifier : List Char -> ParseResult String
  | value :: rest =>
      if parseIdentifierStart value then
        let taken := takeWhileChars parseIdentifierRest rest [value]
        parseOk (String.ofList taken.fst) taken.snd
      else
        parseError "expected identifier"
  | [] => parseError "expected identifier"

def parseLabel : List Char -> ParseResult String
  | '"' :: rest => parseQuotedLabel ('"' :: rest)
  | chars => parseIdentifier chars

def parseFieldClass (label : String) (chars : List Char) : FieldClass × List Char :=
  match skipTrivia chars with
  | '?' :: rest => (.optional, rest)
  | '!' :: rest => (.required, rest)
  | rest =>
      if label.startsWith "#" then
        (.definition, rest)
      else if label.startsWith "_" then
        (.hidden, rest)
      else
        (.regular, rest)

def parseKindName? : String -> Option Kind
  | "null" => some .null
  | "bool" => some .bool
  | "number" => some .number
  | "int" => some .int
  | "float" => some .float
  | "string" => some .string
  | "bytes" => some .bytes
  | _ => none

def parseNumberToken : List Char -> ParseResult String
  | '-' :: rest =>
      let digits := takeWhileChars parseDigit rest []
      if digits.fst.isEmpty then
        parseError "expected digits after '-'"
      else
        match digits.snd with
        | '.' :: afterDot =>
            let fraction := takeWhileChars parseDigit afterDot []
            if fraction.fst.isEmpty then
              parseOk (String.ofList ('-' :: digits.fst)) digits.snd
            else
              parseOk (String.ofList ('-' :: digits.fst ++ ('.' :: fraction.fst))) fraction.snd
        | rest => parseOk (String.ofList ('-' :: digits.fst)) rest
  | chars =>
      let digits := takeWhileChars parseDigit chars []
      if digits.fst.isEmpty then
        parseError "expected number"
      else
        match digits.snd with
        | '.' :: afterDot =>
            let fraction := takeWhileChars parseDigit afterDot []
            if fraction.fst.isEmpty then
              parseOk (String.ofList digits.fst) digits.snd
            else
              parseOk (String.ofList (digits.fst ++ ('.' :: fraction.fst))) fraction.snd
        | rest => parseOk (String.ofList digits.fst) rest

def parseNumberValue (chars : List Char) : ParseResult Value :=
  match parseNumberToken chars with
  | .error error => .error error
  | .ok (token, rest) =>
      if token.contains '.' then
        parseOk (.prim (.float token)) rest
      else
        match token.toInt? with
        | some value => parseOk (.prim (.int value)) rest
        | none => parseError s!"invalid integer literal {token}"

def parseIntBoundValue (mk : Int -> Value) (chars : List Char) : ParseResult Value :=
  match parseNumberToken (skipTrivia chars) with
  | .error error => .error error
  | .ok (token, rest) =>
      match token.toInt? with
      | some value => parseOk (mk value) rest
      | none => parseError "integer bound requires an integer literal"

def parseCommaOrSemicolon : List Char -> List Char
  | ',' :: rest => skipTrivia rest
  | ';' :: rest => skipTrivia rest
  | chars => chars

def parseFieldTerminator (terminator : Option Char) (chars : List Char) : Bool :=
  match terminator, chars with
  | some expected, value :: _ => value == expected
  | none, [] => true
  | _, _ => false

mutual
  partial def parseExpression (chars : List Char) : ParseResult Value :=
    parseDisjunction chars

  partial def parseDisjunction (chars : List Char) : ParseResult Value :=
    match parseMarkedConjunction chars with
    | .error error => .error error
    | .ok (first, rest) => parseDisjunctionRest [first] rest

  partial def parseDisjunctionRest
      (alternatives : List (Mark × Value))
      (chars : List Char) : ParseResult Value :=
    match skipTrivia chars with
    | '|' :: rest =>
        match parseMarkedConjunction rest with
        | .error error => .error error
        | .ok (alternative, rest) => parseDisjunctionRest (alternatives ++ [alternative]) rest
    | rest =>
        match alternatives with
        | [(.regular, value)] => parseOk value rest
        | _ => parseOk (.disj alternatives) rest

  partial def parseMarkedConjunction (chars : List Char) : ParseResult (Mark × Value) :=
    match skipTrivia chars with
    | '*' :: rest =>
        match parseConjunction rest with
        | .error error => .error error
        | .ok (value, rest) => parseOk (.default, value) rest
    | rest =>
        match parseConjunction rest with
        | .error error => .error error
        | .ok (value, rest) => parseOk (.regular, value) rest

  partial def parseConjunction (chars : List Char) : ParseResult Value :=
    match parsePrimary chars with
    | .error error => .error error
    | .ok (first, rest) => parseConjunctionRest [first] rest

  partial def parseConjunctionRest (constraints : List Value) (chars : List Char) : ParseResult Value :=
    match skipTrivia chars with
    | '&' :: rest =>
        match parsePrimary rest with
        | .error error => .error error
        | .ok (constraint, rest) => parseConjunctionRest (constraints ++ [constraint]) rest
    | rest =>
        match constraints with
        | [value] => parseOk value rest
        | values => parseOk (.conj values) rest

  partial def parsePrimary (chars : List Char) : ParseResult Value :=
    match skipTrivia chars with
    | '(' :: rest =>
        match parseExpression rest with
        | .error error => .error error
        | .ok (value, rest) =>
            match skipTrivia rest with
            | ')' :: rest => parseOk value rest
            | _ => parseError "expected ')'"
    | '{' :: rest => parseStruct rest
    | '[' :: rest => parseList rest
    | '"' :: rest =>
        match parseQuotedString ('"' :: rest) with
        | .error error => .error error
        | .ok (value, rest) => parseOk (.prim (.string value)) rest
    | '_' :: '|' :: '_' :: rest => parseOk .bottom rest
    | '_' :: rest => parseOk .top rest
    | '!' :: '=' :: rest =>
        match parsePrimary rest with
        | .error error => .error error
        | .ok (value, rest) =>
            match value with
            | .prim prim => parseOk (.notPrim prim) rest
            | _ => parseError "!= currently requires a primitive literal"
    | '=' :: '~' :: rest =>
        match parseQuotedString (skipTrivia rest) with
        | .error error => .error error
        | .ok (pattern, rest) => parseOk (.stringRegex pattern) rest
    | '>' :: '=' :: rest => parseIntBoundValue .intGe rest
    | '>' :: rest => parseIntBoundValue .intGt rest
    | '<' :: '=' :: rest => parseIntBoundValue .intLe rest
    | '<' :: rest => parseIntBoundValue .intLt rest
    | '-' :: _ => parseNumberValue (skipTrivia chars)
    | value :: _ =>
        if parseDigit value then
          parseNumberValue (skipTrivia chars)
        else if parseIdentifierStart value then
          parseIdentifierValue (skipTrivia chars)
        else
          parseError s!"unexpected character '{value}'"
    | [] => parseError "expected expression"

  partial def parseIdentifierValue (chars : List Char) : ParseResult Value :=
    match parseIdentifier chars with
    | .error error => .error error
    | .ok (name, rest) =>
        match skipTrivia rest with
        | '(' :: rest => parseCall name rest
        | rest =>
            match name with
            | "true" => parseOk (.prim (.bool true)) rest
            | "false" => parseOk (.prim (.bool false)) rest
            | "null" => parseOk (.prim .null) rest
            | _ =>
                match parseKindName? name with
                | some kind => parseOk (.kind kind) rest
                | none => parseOk (.ref name) rest

  partial def parseCall (name : String) (chars : List Char) : ParseResult Value :=
    match parseExpressionListUntil ')' chars [] with
    | .error error => .error error
    | .ok (args, rest) => parseOk (.builtinCall name args) rest

  partial def parseList (chars : List Char) : ParseResult Value :=
    match parseExpressionListUntil ']' chars [] with
    | .error error => .error error
    | .ok (items, rest) => parseOk (.list items) rest

  partial def parseExpressionListUntil
      (terminator : Char)
      (chars : List Char)
      (items : List Value) : ParseResult (List Value) :=
    match skipTrivia chars with
    | value :: rest =>
        if value == terminator then
          parseOk items rest
        else
          let chars := value :: rest
          match parseExpression chars with
          | .error error => .error error
          | .ok (item, rest) =>
              parseExpressionListUntil terminator (parseCommaOrSemicolon (skipTrivia rest)) (items ++ [item])
    | [] => parseError s!"expected '{terminator}'"

  partial def parseStruct (chars : List Char) : ParseResult Value :=
    match parseFieldsUntil (some '}') chars [] with
    | .error error => .error error
    | .ok (fields, rest) => parseOk (.struct fields true) rest

  partial def parseFieldsUntil
      (terminator : Option Char)
      (chars : List Char)
      (fields : List Field) : ParseResult (List Field) :=
    let chars := skipTrivia chars
    if parseFieldTerminator terminator chars then
      match terminator, chars with
      | some _, _ :: rest => parseOk fields rest
      | none, [] => parseOk fields []
      | _, rest => parseOk fields rest
    else
      match parseField chars with
      | .error error => .error error
      | .ok (field, rest) =>
          parseFieldsUntil terminator (parseCommaOrSemicolon (skipTrivia rest)) (fields ++ [field])

  partial def parseField (chars : List Char) : ParseResult Field :=
    match parseLabel chars with
    | .error error => .error error
    | .ok (label, rest) =>
        let (fieldClass, rest) := parseFieldClass label rest
        match skipTrivia rest with
        | ':' :: rest =>
            match parseExpression rest with
            | .error error => .error error
            | .ok (value, rest) => parseOk (label, fieldClass, value) rest
        | _ => parseError "expected ':' after field label"
end

def parseDocument (chars : List Char) : Except ParseError Value :=
  let chars := consumePackageClauses chars
  match parseFieldsUntil none chars [] with
  | .error error => .error error
  | .ok (fields, rest) =>
      match skipTrivia rest with
      | [] => .ok (.struct fields true)
      | _ => parseError "unexpected trailing input"

def parseSource (source : String) : Except ParseError Value :=
  parseDocument source.toList

end Kue
