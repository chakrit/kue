import Init.Data.String.Search
import Kue.Value

namespace Kue

structure ParseError where
  message : String
deriving Repr, BEq, DecidableEq, Inhabited

abbrev ParseResult (α : Type) := Except ParseError (α × List Char)

inductive ParsedField where
  | field (field : Field)
  | fieldAlias (alias : String) (field : Field)
  | pattern (labelPattern constraint : Value)
  | embedding (value : Value)
  | letBinding (name : String) (value : Value)
  | ellipsis (tail : Value)

structure ParsedFieldParts where
  fields : List Field
  patterns : List (Value × Value)
  embeddings : List Value
  tail : Option Value

def parseError (message : String) : Except ParseError α :=
  .error { message := message }

def parseOk (value : α) (rest : List Char) : ParseResult α :=
  .ok (value, rest)

def parseAsciiBetween (lower upper value : Char) : Bool :=
  lower.toNat <= value.toNat && value.toNat <= upper.toNat

def parseWhitespace (value : Char) : Bool :=
  value == ' ' || value == '\n' || value == '\r' || value == '\t'

def parseHorizontalWhitespace (value : Char) : Bool :=
  value == ' ' || value == '\t' || value == '\r'

def parseIdentifierStart (value : Char) : Bool :=
  parseAsciiBetween 'a' 'z' value
    || parseAsciiBetween 'A' 'Z' value
    || value == '_'
    || value == '#'

def parseIdentifierRest (value : Char) : Bool :=
  parseIdentifierStart value || parseAsciiBetween '0' '9' value

def parseDigit (value : Char) : Bool :=
  parseAsciiBetween '0' '9' value

def parseLowerHexLetter (value : Char) : Bool :=
  parseAsciiBetween 'a' 'f' value

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

partial def skipPostfixTrivia : List Char -> List Char
  | [] => []
  | value :: rest =>
      if parseHorizontalWhitespace value then
        skipPostfixTrivia rest
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

def parseQuotedBytes : List Char -> ParseResult String
  | '\'' :: rest => parseQuotedWith '\'' rest []
  | _ => parseError "expected byte literal"

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

partial def parsePackageClauseNames (chars : List Char) : Except ParseError (List String) :=
  let trimmed := skipTrivia chars
  if startsWithWord "package" trimmed then
    match dropPrefix? "package".toList trimmed with
    | some rest =>
        match parseIdentifier (skipTrivia rest) with
        | .ok (name, rest) => do
            let names ← parsePackageClauseNames (dropLine rest)
            pure (name :: names)
        | .error _ => parseError "expected package name"
    | none => .ok []
  else
    .ok []

def packageNamesMatch (name : String) : List String -> Bool
  | [] => true
  | other :: names => other == name && packageNamesMatch name names

def sourcePackageName (source : String) : Except ParseError (Option String) := do
  let names ← parsePackageClauseNames source.toList
  match names with
  | [] => pure none
  | name :: names =>
      if packageNamesMatch name names then
        pure (some name)
      else
        parseError "conflicting package clauses"

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

def stripNumericSeparators : List Char -> List Char
  | [] => []
  | '_' :: rest => stripNumericSeparators rest
  | value :: rest => value :: stripNumericSeparators rest

def digitSequenceValidAfterWith (isDigit : Char -> Bool) (previousWasDigit : Bool) : List Char -> Bool
  | [] => previousWasDigit
  | value :: rest =>
      if isDigit value then
        digitSequenceValidAfterWith isDigit true rest
      else if value == '_' then
        previousWasDigit && digitSequenceValidAfterWith isDigit false rest
      else
        false

def parseDigitOrSeparatorWith (isDigit : Char -> Bool) (value : Char) : Bool :=
  isDigit value || value == '_'

def parseDigitSequenceWith
    (context : String)
    (isDigit : Char -> Bool)
    (chars : List Char) : ParseResult String :=
  let digits := takeWhileChars (parseDigitOrSeparatorWith isDigit) chars []
  if digitSequenceValidAfterWith isDigit false digits.fst then
    parseOk (String.ofList (stripNumericSeparators digits.fst)) digits.snd
  else
    parseError s!"expected {context} digits"

def parseDigitSequence (context : String) (chars : List Char) : ParseResult String :=
  parseDigitSequenceWith context parseDigit chars

def parseDigitValue? (value : Char) : Option Nat :=
  if parseDigit value then
    some (value.toNat - '0'.toNat)
  else if parseLowerHexLetter value then
    some (10 + value.toNat - 'a'.toNat)
  else
    none

def parseDigitForBase (base : Nat) (value : Char) : Bool :=
  match parseDigitValue? value with
  | some digit => digit < base
  | none => false

def digitsValueWithBase (base : Nat) : List Char -> Nat -> Option Nat
  | [], value => some value
  | digit :: digits, value =>
      match parseDigitValue? digit with
      | some next =>
          if next < base then
            digitsValueWithBase base digits (value * base + next)
          else
            none
      | none => none

def applyNumberSign (sign : String) (value : Nat) : Int :=
  if sign == "-" then
    -(Int.ofNat value)
  else
    Int.ofNat value

def parseBasedIntegerWithSign
    (sign : String)
    (base : Nat)
    (context : String)
    (chars : List Char) : ParseResult String :=
  match parseDigitSequenceWith context (parseDigitForBase base) chars with
  | .error error => .error error
  | .ok (digits, rest) =>
      match digitsValueWithBase base digits.toList 0 with
      | some value => parseOk (toString (applyNumberSign sign value)) rest
      | none => parseError s!"invalid {context} literal"

def parseExponentDigits (sign : String) (chars : List Char) : ParseResult String :=
  match parseDigitSequence "exponent" chars with
  | .ok (digits, rest) => parseOk ("e" ++ sign ++ digits) rest
  | .error error => .error error

def parseExponentSign : List Char -> ParseResult String
  | '+' :: rest => parseExponentDigits "+" rest
  | '-' :: rest => parseExponentDigits "-" rest
  | chars => parseExponentDigits "+" chars

def parseExponentToken : List Char -> ParseResult String
  | 'e' :: rest => parseExponentSign rest
  | 'E' :: rest => parseExponentSign rest
  | chars => parseOk "" chars

def parseNumberWithSign (sign : String) (chars : List Char) : ParseResult String :=
  match chars with
  | '0' :: 'x' :: rest => parseBasedIntegerWithSign sign 16 "hexadecimal" rest
  | '0' :: 'o' :: rest => parseBasedIntegerWithSign sign 8 "octal" rest
  | '0' :: 'b' :: rest => parseBasedIntegerWithSign sign 2 "binary" rest
  | _ =>
      match parseDigitSequence "number" chars with
      | .error error => .error error
      | .ok (whole, rest) =>
          match rest with
          | '.' :: afterDot =>
              match parseDigitSequence "fraction" afterDot with
              | .error error => .error error
              | .ok (fraction, rest) =>
                  match parseExponentToken rest with
                  | .error error => .error error
                  | .ok (exponent, rest) => parseOk (sign ++ whole ++ "." ++ fraction ++ exponent) rest
          | rest =>
              match parseExponentToken rest with
              | .error error => .error error
              | .ok (exponent, rest) => parseOk (sign ++ whole ++ exponent) rest

def parseNumberToken : List Char -> ParseResult String
  | '+' :: rest => parseNumberWithSign "" rest
  | '-' :: rest => parseNumberWithSign "-" rest
  | chars => parseNumberWithSign "" chars

def parseNumberValue (chars : List Char) : ParseResult Value :=
  match parseNumberToken chars with
  | .error error => .error error
  | .ok (token, rest) =>
      if token.contains '.' || token.contains 'e' then
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

def splitParsedFields : List ParsedField -> ParsedFieldParts
  | [] => { fields := [], patterns := [], embeddings := [], tail := none }
  | .field field :: rest =>
      let split := splitParsedFields rest
      { split with fields := field :: split.fields }
  | .fieldAlias alias field :: rest =>
      let split := splitParsedFields rest
      { split with fields := field :: (alias, .letBinding, .ref (Field.label field)) :: split.fields }
  | .pattern labelPattern constraint :: rest =>
      let split := splitParsedFields rest
      { split with patterns := (labelPattern, constraint) :: split.patterns }
  | .embedding value :: rest =>
      let split := splitParsedFields rest
      { split with embeddings := value :: split.embeddings }
  | .letBinding name value :: rest =>
      let split := splitParsedFields rest
      { split with fields := (name, .letBinding, value) :: split.fields }
  | .ellipsis tail :: rest =>
      let split := splitParsedFields rest
      { split with tail := some tail }

def parsedFieldsBaseValue (fields : List Field) : List (Value × Value) -> Value
  | [] => .struct fields true
  | [pattern] => .structPattern fields pattern.fst pattern.snd true
  | patterns => .structPatterns fields patterns true

def parsedFieldsValue (parsedFields : List ParsedField) : Value :=
  let parts := splitParsedFields parsedFields
  let declared := parsedFieldsBaseValue parts.fields parts.patterns
  let base :=
    match parts.tail with
    | none => declared
    | some tail =>
        match parts.patterns with
        | [] => .structTail parts.fields tail
        | _ => .conj [declared, .structTail parts.fields tail]
  match parts.embeddings with
  | [] => base
  | embeddings => .conj (embeddings ++ [base])

def structEllipsisEndsHere : List Char -> Bool
  | [] => true
  | ',' :: _ => true
  | ';' :: _ => true
  | '}' :: _ => true
  | _ => false

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
    match parsePrimaryAtom chars with
    | .error error => .error error
    | .ok (value, rest) => parseSelectorRest value rest

  partial def parseSelectorRest (base : Value) (chars : List Char) : ParseResult Value :=
    match skipPostfixTrivia chars with
    | '.' :: rest =>
        match parseLabel (skipTrivia rest) with
        | .error error => .error error
        | .ok (label, rest) => parseSelectorRest (.selector base label) rest
    | '[' :: rest =>
        match parseExpression rest with
        | .error error => .error error
        | .ok (key, rest) =>
            match skipTrivia rest with
            | ']' :: rest => parseSelectorRest (.index base key) rest
            | _ => parseError "expected ']' after index"
    | rest => parseOk base rest

  partial def parsePrimaryAtom (chars : List Char) : ParseResult Value :=
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
    | '\'' :: rest =>
        match parseQuotedBytes ('\'' :: rest) with
        | .error error => .error error
        | .ok (value, rest) => parseOk (.prim (.bytes value)) rest
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
    | '+' :: _ => parseNumberValue (skipTrivia chars)
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
        match skipPostfixTrivia rest with
        | '(' :: rest => parseCall name rest
        | _ =>
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
    parseListItems chars []

  partial def parseListTailEnd (value : Value) (chars : List Char) : ParseResult Value :=
    match parseCommaOrSemicolon (skipTrivia chars) with
    | ']' :: rest => parseOk value rest
    | _ => parseError "expected ']' after list tail"

  partial def parseListTail (items : List Value) (chars : List Char) : ParseResult Value :=
    match skipTrivia chars with
    | '.' :: '.' :: '.' :: rest =>
        match skipTrivia rest with
        | ']' :: rest => parseOk (.listTail items .top) rest
        | rest =>
            match parseExpression rest with
            | .error error => .error error
            | .ok (tail, rest) => parseListTailEnd (.listTail items tail) rest
    | _ => parseError "expected list tail"

  partial def parseListItems (chars : List Char) (items : List Value) : ParseResult Value :=
    match skipTrivia chars with
    | ']' :: rest => parseOk (.list items) rest
    | '.' :: '.' :: '.' :: _ => parseListTail items chars
    | value :: rest =>
        let chars := value :: rest
        match parseExpression chars with
        | .error error => .error error
        | .ok (item, rest) =>
            parseListItems (parseCommaOrSemicolon (skipTrivia rest)) (items ++ [item])
    | [] => parseError "expected ']'"

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
    | .ok (fields, rest) => parseOk (parsedFieldsValue fields) rest

  partial def parseFieldsUntil
      (terminator : Option Char)
      (chars : List Char)
      (fields : List ParsedField) : ParseResult (List ParsedField) :=
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

  partial def parsePatternField (chars : List Char) : ParseResult ParsedField :=
    match skipTrivia chars with
    | '[' :: rest =>
        match parseExpression rest with
        | .error error => .error error
        | .ok (labelPattern, rest) =>
            match skipTrivia rest with
            | ']' :: rest =>
                match skipTrivia rest with
                | ':' :: rest =>
                    match parseExpression rest with
                    | .error error => .error error
                    | .ok (constraint, rest) => parseOk (.pattern labelPattern constraint) rest
                | _ => parseError "expected ':' after pattern label"
            | _ => parseError "expected ']' after pattern label"
    | _ => parseError "expected pattern field"

  partial def parseLetBinding (chars : List Char) : ParseResult ParsedField :=
    let chars := skipTrivia chars
    if startsWithWord "let" chars then
      match dropPrefix? "let".toList chars with
      | some rest =>
          match parseIdentifier (skipTrivia rest) with
          | .error error => .error error
          | .ok (name, rest) =>
              match skipTrivia rest with
              | '=' :: rest =>
                  match parseExpression rest with
                  | .error error => .error error
                  | .ok (value, rest) => parseOk (.letBinding name value) rest
              | _ => parseError "expected '=' after let binding name"
      | none => parseError "expected let binding"
    else
      parseError "expected let binding"

  partial def parseStructEllipsis (chars : List Char) : ParseResult ParsedField :=
    match skipTrivia chars with
    | '.' :: '.' :: '.' :: rest =>
        if structEllipsisEndsHere (skipTrivia rest) then
          parseOk (.ellipsis .top) rest
        else
          parseError "typed struct ellipsis is not supported yet"
    | _ => parseError "expected struct ellipsis"

  partial def parseEmbedding (chars : List Char) : ParseResult ParsedField :=
    match parseExpression chars with
    | .error error => .error error
    | .ok (value, rest) => parseOk (.embedding value) rest

  partial def parseLabeledField (label : String) (rest : List Char) : ParseResult ParsedField :=
    let (fieldClass, rest) := parseFieldClass label rest
    match skipTrivia rest with
    | ':' :: rest =>
        match parseExpression rest with
        | .error error => .error error
        | .ok (value, rest) => parseOk (.field (label, fieldClass, value)) rest
    | _ => parseError "expected ':' after field label"

  partial def parseAliasedField (chars : List Char) : ParseResult ParsedField :=
    match parseIdentifier chars with
    | .error error => .error error
    | .ok (alias, rest) =>
        match skipTrivia rest with
        | '=' :: rest =>
            match parseLabel (skipTrivia rest) with
            | .error error => .error error
            | .ok (label, rest) =>
                let (fieldClass, rest) := parseFieldClass label rest
                match skipTrivia rest with
                | ':' :: rest =>
                    match parseExpression rest with
                    | .error error => .error error
                    | .ok (value, rest) => parseOk (.fieldAlias alias (label, fieldClass, value)) rest
                | _ => parseError "expected ':' after aliased field label"
        | _ => parseError "expected '=' after field alias"

  partial def parseField (chars : List Char) : ParseResult ParsedField :=
    match skipTrivia chars with
    | '[' :: _ => parsePatternField chars
    | '.' :: '.' :: '.' :: _ => parseStructEllipsis chars
    | chars =>
        match parseLetBinding chars with
        | .ok parsed => .ok parsed
        | .error _ =>
            match parseAliasedField chars with
            | .ok parsed => .ok parsed
            | .error _ =>
                match parseLabel chars with
                | .error _ => parseEmbedding chars
                | .ok (label, rest) =>
                    match skipTrivia rest with
                    | ':' :: _ => parseLabeledField label rest
                    | '?' :: _ => parseLabeledField label rest
                    | '!' :: _ => parseLabeledField label rest
                    | _ => parseEmbedding chars
end

def parseDocument (chars : List Char) : Except ParseError Value :=
  let chars := consumePackageClauses chars
  if startsWithWord "import" (skipTrivia chars) then
    parseError "imports are not supported yet"
  else
    match parseFieldsUntil none chars [] with
    | .error error => .error error
    | .ok (fields, rest) =>
        match skipTrivia rest with
        | [] => .ok (parsedFieldsValue fields)
        | _ => parseError "unexpected trailing input"

def parseSource (source : String) : Except ParseError Value :=
  parseDocument source.toList

end Kue
