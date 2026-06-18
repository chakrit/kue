import Init.Data.String.Search
import Kue.Value

namespace Kue

structure ParseError where
  message : String
  remaining : Nat := 0
  line : Nat := 0
  column : Nat := 0
deriving Repr, BEq, DecidableEq, Inhabited

abbrev ParseResult (α : Type) := Except ParseError (α × List Char)

inductive ParsedField where
  | field (field : Field)
  | fieldAlias (alias : String) (field : Field)
  | pattern (labelPattern constraint : Value)
  | embedding (value : Value)
  | letBinding (name : String) (value : Value)
  | ellipsis (tail : Value)
  | comprehension (clauses : List (Clause Value)) (body : Value)
  | dynamicField (label : Value) (fieldClass : FieldClass) (value : Value)

structure ParsedFieldParts where
  fields : List Field
  patterns : List (Value × Value)
  comprehensions : List Value
  tail : Option Value

def parseError (chars : List Char) (message : String) : Except ParseError α :=
  .error { message := message, remaining := chars.length }

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

/-- Drop characters up to and including the first `)`. Used to skip a grouped
    `import ( … )` block; imports are ignored since the package is implicit in the
    qualified builtin name (`strings.ToUpper`). -/
partial def dropToCloseParen : List Char -> List Char
  | [] => []
  | ')' :: rest => rest
  | _ :: rest => dropToCloseParen rest

/-- Consume any leading `import` declarations (single-line or grouped) and ignore
    them. Package-qualified builtins (`strings.*`) need no symbol binding, so the
    import is a no-op beyond syntactic acceptance. -/
partial def consumeImportClauses (chars : List Char) : List Char :=
  let trimmed := skipTrivia chars
  if startsWithWord "import" trimmed then
    match dropPrefix? "import".toList trimmed with
    | some rest =>
        match skipTrivia rest with
        | '(' :: grouped => consumeImportClauses (dropToCloseParen grouped)
        | line => consumeImportClauses (dropLine line)
    | none => trimmed
  else
    trimmed

def parseStringEscape : Char -> Char
  | 'n' => '\n'
  | 'r' => '\r'
  | 't' => '\t'
  | value => value

partial def parseQuotedWith (quote : Char) : List Char -> List Char -> ParseResult String
  | [], _ => parseError [] "unterminated string literal"
  | value :: rest, acc =>
      if value == quote then
        parseOk (String.ofList acc.reverse) rest
      else if value == '\\' then
        match rest with
        | [] => parseError [] "unterminated string escape"
        | escaped :: rest => parseQuotedWith quote rest (parseStringEscape escaped :: acc)
      else
        parseQuotedWith quote rest (value :: acc)

def parseQuotedString : List Char -> ParseResult String
  | '"' :: rest => parseQuotedWith '"' rest []
  | chars => parseError chars "expected string literal"

def parseQuotedBytes : List Char -> ParseResult String
  | '\'' :: rest => parseQuotedWith '\'' rest []
  | chars => parseError chars "expected byte literal"

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
        parseError (value :: rest) "expected identifier"
  | [] => parseError [] "expected identifier"

partial def parsePackageClauseNames (chars : List Char) : Except ParseError (List String) :=
  let trimmed := skipTrivia chars
  if startsWithWord "package" trimmed then
    match dropPrefix? "package".toList trimmed with
    | some rest =>
        match parseIdentifier (skipTrivia rest) with
        | .ok (name, rest) => do
            let names ← parsePackageClauseNames (dropLine rest)
            pure (name :: names)
        | .error _ => parseError [] "expected package name"
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
        parseError [] "conflicting package clauses"

/-- Parse one import spec: an optional bare identifier alias followed by a quoted import
    path. `import "example.com/defs"` yields `{path, alias := none}`;
    `import foo "example.com/defs"` yields `{path, alias := some "foo"}`. -/
def parseImportSpec (chars : List Char) : ParseResult Import :=
  let trimmed := skipTrivia chars
  match parseQuotedString trimmed with
  | .ok (path, rest) => parseOk { path := path, alias := none } rest
  | .error _ =>
      match parseIdentifier trimmed with
      | .error error => .error error
      | .ok (alias, rest) =>
          match parseQuotedString (skipTrivia rest) with
          | .error error => .error error
          | .ok (path, rest) => parseOk { path := path, alias := some alias } rest

/-- Collect the specs inside a grouped `import ( … )` block up to the closing `)`,
    skipping separators (newlines/commas/comments handled by `skipTrivia` plus an
    explicit comma drop). Returns the gathered imports and the chars after `)`. -/
partial def parseGroupedImports (acc : List Import) (chars : List Char) :
    ParseResult (List Import) :=
  match skipTrivia chars with
  | ')' :: rest => parseOk acc.reverse rest
  | ',' :: rest => parseGroupedImports acc rest
  | [] => parseError [] "unterminated import group"
  | trimmed =>
      match parseImportSpec trimmed with
      | .error error => .error error
      | .ok (imp, rest) => parseGroupedImports (imp :: acc) rest

/-- Collect every leading `import` clause (single-line or grouped) into a `List Import`,
    returning the remaining chars at the start of the file body. The collecting twin of
    `consumeImportClauses`, which discards instead. -/
partial def parseImportClauses (acc : List Import) (chars : List Char) :
    ParseResult (List Import) :=
  let trimmed := skipTrivia chars
  if startsWithWord "import" trimmed then
    match dropPrefix? "import".toList trimmed with
    | none => parseOk acc.reverse trimmed
    | some rest =>
        match skipTrivia rest with
        | '(' :: grouped =>
            match parseGroupedImports [] grouped with
            | .error error => .error error
            | .ok (imports, rest) => parseImportClauses (imports.reverse ++ acc) rest
        | line =>
            match parseImportSpec line with
            | .error error => .error error
            | .ok (imp, rest) => parseImportClauses (imp :: acc) rest
  else
    parseOk acc.reverse trimmed

def parseLabel : List Char -> ParseResult String
  | '"' :: rest => parseQuotedLabel ('"' :: rest)
  | chars => parseIdentifier chars

def parseFieldClass (label : String) (chars : List Char) : FieldClass × List Char :=
  let (optionality, rest) :=
    match skipTrivia chars with
    | '?' :: rest => (Optionality.optional, rest)
    | '!' :: rest => (Optionality.required, rest)
    | rest => (Optionality.regular, rest)
  -- CUE field-name axes are orthogonal: `#x` is a definition, `_x` is hidden, and `_#x` is
  -- BOTH (a hidden definition — closed AND excluded from output). Classifying `_#x` as
  -- hidden-only (the old `!isDefinition && …`) dropped its definition-ness, so a hidden-def
  -- embedding's sibling self-ref never deferred to a closure and missed use-site narrowing.
  let isDefinition := label.startsWith "#" || label.startsWith "_#"
  let isHidden := label.startsWith "_"
  (.field isDefinition isHidden optionality, rest)

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
    parseError chars s!"expected {context} digits"

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

def powNat (base : Nat) : Nat -> Nat
  | 0 => 1
  | exponent + 1 => base * powNat base exponent

def decimalDigitsValue? (digits : String) : Option Nat :=
  digitsValueWithBase 10 digits.toList 0

def parseNumberSuffix? : List Char -> Option (Nat × List Char)
  | 'K' :: 'i' :: rest => some (powNat 1024 1, rest)
  | 'M' :: 'i' :: rest => some (powNat 1024 2, rest)
  | 'G' :: 'i' :: rest => some (powNat 1024 3, rest)
  | 'T' :: 'i' :: rest => some (powNat 1024 4, rest)
  | 'P' :: 'i' :: rest => some (powNat 1024 5, rest)
  | 'K' :: rest => some (powNat 1000 1, rest)
  | 'M' :: rest => some (powNat 1000 2, rest)
  | 'G' :: rest => some (powNat 1000 3, rest)
  | 'T' :: rest => some (powNat 1000 4, rest)
  | 'P' :: rest => some (powNat 1000 5, rest)
  | _ => none

def applyNumericSuffix
    (sign : String)
    (whole fraction : String)
    (rest : List Char) : ParseResult String :=
  match parseNumberSuffix? rest with
  | none => parseOk "" rest
  | some (multiplier, rest) =>
      match decimalDigitsValue? whole, decimalDigitsValue? fraction with
      | some wholeValue, some fractionValue =>
          let scale := powNat 10 fraction.toList.length
          let numerator := wholeValue * scale + fractionValue
          let scaled := numerator * multiplier
          if scaled % scale == 0 then
            parseOk (toString (applyNumberSign sign (scaled / scale))) rest
          else
            parseError rest "number cannot be represented as int"
      | _, _ => parseError rest "invalid suffixed number"

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
      | none => parseError chars s!"invalid {context} literal"

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

def parseIntegerSuffixOrExponent (sign whole : String) (chars : List Char) : ParseResult String :=
  match applyNumericSuffix sign whole "" chars with
  | .error error => .error error
  | .ok ("", rest) =>
      match parseExponentToken rest with
      | .error error => .error error
      | .ok (exponent, rest) => parseOk (sign ++ whole ++ exponent) rest
  | .ok (token, rest) => parseOk token rest

def parseFractionSuffixOrExponent
    (sign whole fraction : String)
    (chars : List Char) : ParseResult String :=
  match applyNumericSuffix sign whole fraction chars with
  | .error error => .error error
  | .ok ("", rest) =>
      match parseExponentToken rest with
      | .error error => .error error
      | .ok (exponent, rest) => parseOk (sign ++ whole ++ "." ++ fraction ++ exponent) rest
  | .ok (token, rest) => parseOk token rest

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
              | .ok (fraction, rest) => parseFractionSuffixOrExponent sign whole fraction rest
          | rest => parseIntegerSuffixOrExponent sign whole rest

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
        | none => parseError chars s!"invalid integer literal {token}"

def parseBoundValue (kind : BoundKind) (chars : List Char) : ParseResult Value :=
  match parseNumberToken (skipTrivia chars) with
  | .error error => .error error
  | .ok (token, rest) =>
      match parseDecimalText token with
      | some value => parseOk (.boundConstraint value kind .number) rest
      | none => parseError chars "numeric bound requires a numeric literal"

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
  | [] => { fields := [], patterns := [], comprehensions := [], tail := none }
  | .field field :: rest =>
      let split := splitParsedFields rest
      { split with fields := field :: split.fields }
  | .fieldAlias alias field :: rest =>
      let split := splitParsedFields rest
      { split with fields := field :: ⟨alias, .letBinding, .ref (Field.label field)⟩ :: split.fields }
  | .pattern labelPattern constraint :: rest =>
      let split := splitParsedFields rest
      { split with patterns := (labelPattern, constraint) :: split.patterns }
  | .embedding value :: rest =>
      let split := splitParsedFields rest
      { split with comprehensions := value :: split.comprehensions }
  | .letBinding name value :: rest =>
      let split := splitParsedFields rest
      { split with fields := ⟨name, .letBinding, value⟩ :: split.fields }
  | .ellipsis tail :: rest =>
      let split := splitParsedFields rest
      { split with tail := some tail }
  | .comprehension clauses body :: rest =>
      let split := splitParsedFields rest
      { split with comprehensions := .comprehension clauses body :: split.comprehensions }
  | .dynamicField label fieldClass value :: rest =>
      let split := splitParsedFields rest
      { split with comprehensions := .dynamicField label fieldClass value :: split.comprehensions }

def parsedFieldsBaseValue (fields : List Field) : List (Value × Value) -> Value
  | [] => .struct fields true
  | [pattern] => .structPattern fields pattern.fst pattern.snd true
  | patterns => .structPatterns fields patterns true

def parsedFieldsValue (parsedFields : List ParsedField) : Value :=
  let parts := splitParsedFields parsedFields
  let declared :=
    match parts.comprehensions with
    | [] => parsedFieldsBaseValue parts.fields parts.patterns
    | comprehensions =>
        match parts.patterns with
        | [] => .structComp parts.fields comprehensions true
        | _ => .conj [parsedFieldsBaseValue parts.fields parts.patterns, .structComp parts.fields comprehensions true]
  match parts.tail with
  | none => declared
  | some tail =>
      match parts.patterns, parts.comprehensions with
      | [], [] => .structTail parts.fields tail
      -- An open struct that ALSO has comprehensions/embeddings (`{ embed; if c {…}; … }`): the
      -- old `.conj [declared, .structTail fields tail]` split the embeds/comprehensions and the
      -- plain-field+tail into two OVERLAPPING-field arms. When such a body is force-spliced as an
      -- imported def, the `.structTail` arm's `Self.<field>` self-refs resolve in isolation —
      -- they never see the embedding-contributed fields (the embed lives in the OTHER arm), so a
      -- use-site narrowing collapses to `.bottom` (the argocd `#ListenerSet` `spec.parentRef.name:
      -- Self.#gateway_name` with `parts.#Metadata` embedded + a def-level `...`). Keep it ONE node:
      -- the comprehension form already carries `open_ = true`, which is exactly what the bare `...`
      -- (`.top` tail — the only supported tail) means. A standalone open struct with comprehensions
      -- stays open; a DEFINITION-context one is closed by `normalizeDefinitionValueWithFuel` like
      -- any `.structComp`, matching `{ embed; if c {…} }` without the redundant `...`.
      | _, _ => declared

def structEllipsisEndsHere : List Char -> Bool
  | [] => true
  | ',' :: _ => true
  | ';' :: _ => true
  | '}' :: _ => true
  | _ => false

def dropWord? (word : String) (chars : List Char) : Option (List Char) :=
  if startsWithWord word chars then
    dropPrefix? word.toList chars
  else
    none

/-- Skip a quoted token (string `"…"` or bytes `'…'`) for lookahead, returning the
    remainder after the closing quote. Honors `\`-escapes so an escaped quote does not
    end the token early. -/
def skipQuotedToken? (quote : Char) : List Char -> Option (List Char)
  | [] => none
  | '\\' :: _ :: rest => skipQuotedToken? quote rest
  | value :: rest =>
      if value == quote then some rest else skipQuotedToken? quote rest

/-- Skip a balanced parenthesized group for lookahead, returning the remainder after the
    matching `)`. `depth` tracks nesting so inner parens (e.g. a call) don't close early. -/
def skipBalancedParens (depth : Nat) : List Char -> Option (List Char)
  | [] => none
  | '(' :: rest => skipBalancedParens (depth + 1) rest
  | ')' :: rest => match depth with
      | 0 => some rest
      | d + 1 => skipBalancedParens d rest
  | _ :: rest => skipBalancedParens depth rest

/-- Skip the remainder after a single field-label token (identifier/definition, quoted
    string, or `(expr)` dynamic). `none` if the value position does not begin a label. -/
def skipLabelToken? : List Char -> Option (List Char)
  | '"' :: rest => skipQuotedToken? '"' rest
  | '(' :: rest => skipBalancedParens 0 rest
  | value :: rest =>
      if parseIdentifierStart value then
        some (takeWhileChars parseIdentifierRest rest [value]).snd
      else
        none
  | [] => none

/-- Skip a balanced bracket group `[ … ]` for lookahead, returning the remainder after
    the matching `]`. `depth` tracks nesting; quoted strings/bytes inside are skipped whole
    so a `]` in a literal does not close early. -/
partial def skipBalancedBrackets (depth : Nat) : List Char -> Option (List Char)
  | [] => none
  | '"' :: rest =>
      match skipQuotedToken? '"' rest with
      | some rest => skipBalancedBrackets depth rest
      | none => none
  | '\'' :: rest =>
      match skipQuotedToken? '\'' rest with
      | some rest => skipBalancedBrackets depth rest
      | none => none
  | '[' :: rest => skipBalancedBrackets (depth + 1) rest
  | ']' :: rest => match depth with
      | 0 => some rest
      | d + 1 => skipBalancedBrackets d rest
  | _ :: rest => skipBalancedBrackets depth rest

/-- Whether the value position begins a label-pattern field (`[<expr>]: …`), i.e. the
    colon-shorthand `f: [string]: T` form (= `f: {[string]: T}`). A balanced `[ … ]`
    immediately followed by `:` is a pattern; a bracket group NOT followed by `:`
    (`[1, 2, 3]`) is an ordinary list and parses as an expression. -/
def valuePositionStartsPatternField (chars : List Char) : Bool :=
  match skipTrivia chars with
  | '[' :: rest =>
      match skipBalancedBrackets 0 rest with
      | some afterBracket =>
          match skipTrivia afterBracket with
          | ':' :: _ => true
          | _ => false
      | none => false
  | _ => false

/-- Whether the value position begins another field (`label [?|!] :`), i.e. the
    colon-shorthand `a: b: …` form. Drives the desugaring recursion in `parseField`;
    a `false` verdict means the value position is an ordinary expression. -/
def valuePositionStartsField (chars : List Char) : Bool :=
  match skipLabelToken? (skipTrivia chars) with
  | none => false
  | some afterLabel =>
      let afterClass :=
        match skipTrivia afterLabel with
        | '?' :: rest => rest
        | '!' :: rest => rest
        | rest => rest
      match skipTrivia afterClass with
      | ':' :: _ => true
      | _ => false

/-- A value-position alias `X=value` (`#Def: Self={…}`). `none` unless the value position
    is an identifier followed by a single `=` (NOT `==`, which is equality). Returns the
    alias name and the remainder positioned at the aliased value expression. -/
def valueAliasHead? (chars : List Char) : Option (String × List Char) :=
  match skipLabelToken? (skipTrivia chars) with
  | some afterIdent =>
      match skipTrivia afterIdent with
      | '=' :: '=' :: _ => none
      | '=' :: rest =>
          match parseIdentifier (skipTrivia chars) with
          | .ok (name, _) => some (name, rest)
          | .error _ => none
      | _ => none
  | none => none

/-- Bind a value-position alias `name` to `value` per CUE scoping: the alias is visible
    within `value` (and its descendants) and refers to the whole value. For a struct value
    this prepends a non-output `let`-binding whose value is `.thisStruct`, so `name.field`
    resolves against the enclosing struct (incl. siblings/hidden fields) and survives
    unification. For a non-struct value the alias is inert — a scalar cannot reference its
    own alias and siblings cannot see it, so the value passes through unchanged. -/
def bindValueAlias (name : String) : Value -> Value
  | .struct fields open_ => .struct (⟨name, .letBinding, .thisStruct⟩ :: fields) open_
  | .structTail fields tail => .structTail (⟨name, .letBinding, .thisStruct⟩ :: fields) tail
  | .structPattern fields lp c open_ =>
      .structPattern (⟨name, .letBinding, .thisStruct⟩ :: fields) lp c open_
  | .structPatterns fields ps open_ =>
      .structPatterns (⟨name, .letBinding, .thisStruct⟩ :: fields) ps open_
  | .structComp fields cs open_ =>
      .structComp (⟨name, .letBinding, .thisStruct⟩ :: fields) cs open_
  | value => value

/-- Three identical delimiter chars (`"""` or `'''`) at the head, else `none`. -/
def multilineDelimiter? (quote : Char) : List Char -> Option (List Char)
  | a :: b :: c :: rest =>
      if a == quote && b == quote && c == quote then some rest else none
  | _ => none

/-- Split the leading horizontal whitespace (spaces/tabs) of a line from its remainder. -/
def splitLeadingHorizontalWhitespace : List Char -> List Char × List Char
  | [] => ([], [])
  | value :: rest =>
      if value == ' ' || value == '\t' then
        let (ws, body) := splitLeadingHorizontalWhitespace rest
        (value :: ws, body)
      else
        ([], value :: rest)

/-- Find the closing-delimiter line's indentation prefix in a multiline literal body.
    `atLineStart` tracks whether the current position begins a line; `ws` accumulates the
    current line's leading horizontal whitespace (reversed). A line whose leading
    whitespace is immediately followed by the closing delimiter is the closing line, and
    that whitespace is the strip prefix applied to every content line. `none` if no such
    line exists (unterminated literal). Total: structural recursion on the char list. -/
def multilineStripPrefixGo (quote : Char) (atLineStart : Bool) (ws : List Char) :
    List Char -> Option (List Char)
  | [] => none
  | value :: rest =>
      if atLineStart && (multilineDelimiter? quote (value :: rest)).isSome then
        some ws.reverse
      else if atLineStart && (value == ' ' || value == '\t') then
        multilineStripPrefixGo quote true (value :: ws) rest
      else if value == '\n' then
        multilineStripPrefixGo quote true [] rest
      else
        multilineStripPrefixGo quote false ws rest

/-- The closing-delimiter line's indentation prefix, or `none` if unterminated. -/
def multilineStripPrefix? (quote : Char) (chars : List Char) : Option (List Char) :=
  multilineStripPrefixGo quote true [] chars

def parseMultiplicativeKeywordOp? (chars : List Char) : Option (BinaryOp × List Char) :=
  match dropWord? "div" chars with
  | some rest => some (.intDiv, rest)
  | none =>
      match dropWord? "mod" chars with
      | some rest => some (.intMod, rest)
      | none =>
          match dropWord? "quo" chars with
          | some rest => some (.intQuo, rest)
          | none =>
              match dropWord? "rem" chars with
              | some rest => some (.intRem, rest)
              | none => none

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
    match parseLogicalOr chars with
    | .error error => .error error
    | .ok (first, rest) => parseConjunctionRest [first] rest

  partial def parseConjunctionRest (constraints : List Value) (chars : List Char) : ParseResult Value :=
    match skipTrivia chars with
    | '&' :: rest =>
        match parseLogicalOr rest with
        | .error error => .error error
        | .ok (constraint, rest) => parseConjunctionRest (constraints ++ [constraint]) rest
    | rest =>
        match constraints with
        | [value] => parseOk value rest
        | values => parseOk (.conj values) rest

  partial def parseLogicalOr (chars : List Char) : ParseResult Value :=
    match parseLogicalAnd chars with
    | .error error => .error error
    | .ok (first, rest) => parseLogicalOrRest first rest

  partial def parseLogicalOrRest (left : Value) (chars : List Char) : ParseResult Value :=
    match skipTrivia chars with
    | '|' :: '|' :: rest =>
        match parseLogicalAnd rest with
        | .error error => .error error
        | .ok (right, rest) => parseLogicalOrRest (.binary .boolOr left right) rest
    | rest => parseOk left rest

  partial def parseLogicalAnd (chars : List Char) : ParseResult Value :=
    match parseComparison chars with
    | .error error => .error error
    | .ok (first, rest) => parseLogicalAndRest first rest

  partial def parseLogicalAndRest (left : Value) (chars : List Char) : ParseResult Value :=
    match skipTrivia chars with
    | '&' :: '&' :: rest =>
        match parseComparison rest with
        | .error error => .error error
        | .ok (right, rest) => parseLogicalAndRest (.binary .boolAnd left right) rest
    | rest => parseOk left rest

  partial def parseComparison (chars : List Char) : ParseResult Value :=
    match parseAdditive chars with
    | .error error => .error error
    | .ok (left, rest) =>
        match skipTrivia rest with
        | '<' :: '=' :: rest =>
            match parseAdditive rest with
            | .error error => .error error
            | .ok (right, rest) => parseOk (.binary .le left right) rest
        | '>' :: '=' :: rest =>
            match parseAdditive rest with
            | .error error => .error error
            | .ok (right, rest) => parseOk (.binary .ge left right) rest
        | '=' :: '~' :: rest =>
            match parseAdditive rest with
            | .error error => .error error
            | .ok (right, rest) => parseOk (.binary .regexMatch left right) rest
        | '!' :: '~' :: rest =>
            match parseAdditive rest with
            | .error error => .error error
            | .ok (right, rest) => parseOk (.binary .regexNotMatch left right) rest
        | '=' :: '=' :: rest =>
            match parseAdditive rest with
            | .error error => .error error
            | .ok (right, rest) => parseOk (.binary .eq left right) rest
        | '!' :: '=' :: rest =>
            match parseAdditive rest with
            | .error error => .error error
            | .ok (right, rest) => parseOk (.binary .ne left right) rest
        | '<' :: rest =>
            match parseAdditive rest with
            | .error error => .error error
            | .ok (right, rest) => parseOk (.binary .lt left right) rest
        | '>' :: rest =>
            match parseAdditive rest with
            | .error error => .error error
            | .ok (right, rest) => parseOk (.binary .gt left right) rest
        | rest => parseOk left rest

  partial def parseAdditive (chars : List Char) : ParseResult Value :=
    match parseMultiplicative chars with
    | .error error => .error error
    | .ok (first, rest) => parseAdditiveRest first rest

  partial def parseAdditiveRest (left : Value) (chars : List Char) : ParseResult Value :=
    match skipTrivia chars with
    | '+' :: rest =>
        match parseMultiplicative rest with
        | .error error => .error error
        | .ok (right, rest) => parseAdditiveRest (.binary .add left right) rest
    | '-' :: rest =>
        match parseMultiplicative rest with
        | .error error => .error error
        | .ok (right, rest) => parseAdditiveRest (.binary .sub left right) rest
    | rest => parseOk left rest

  partial def parseMultiplicative (chars : List Char) : ParseResult Value :=
    match parseUnary chars with
    | .error error => .error error
    | .ok (first, rest) => parseMultiplicativeRest first rest

  partial def parseMultiplicativeRest (left : Value) (chars : List Char) : ParseResult Value :=
    let chars := skipTrivia chars
    match chars with
    | '*' :: rest =>
        match parseUnary rest with
        | .error error => .error error
        | .ok (right, rest) => parseMultiplicativeRest (.binary .mul left right) rest
    | '/' :: rest =>
        match parseUnary rest with
        | .error error => .error error
        | .ok (right, rest) => parseMultiplicativeRest (.binary .div left right) rest
    | rest =>
        match parseMultiplicativeKeywordOp? rest with
        | some (op, rest) =>
            match parseUnary rest with
            | .error error => .error error
            | .ok (right, rest) => parseMultiplicativeRest (.binary op left right) rest
        | none => parseOk left rest

  partial def parseUnary (chars : List Char) : ParseResult Value :=
    match skipTrivia chars with
    | '!' :: '=' :: _ => parsePrimary chars
    | '!' :: rest =>
        match parseUnary rest with
        | .error error => .error error
        | .ok (value, rest) => parseOk (.unary .boolNot value) rest
    | '+' :: rest =>
        match parseUnary rest with
        | .error error => .error error
        | .ok (value, rest) => parseOk (.unary .numPos value) rest
    | '-' :: rest =>
        match parseUnary rest with
        | .error error => .error error
        | .ok (value, rest) => parseOk (.unary .numNeg value) rest
    | _ => parsePrimary chars

  partial def parsePrimary (chars : List Char) : ParseResult Value :=
    match parsePrimaryAtom chars with
    | .error error => .error error
    | .ok (value, rest) => parseSelectorRest value rest

  partial def parseSelectorRest (base : Value) (chars : List Char) : ParseResult Value :=
    match skipPostfixTrivia chars with
    | '.' :: rest =>
        match parseLabel (skipTrivia rest) with
        | .error error => .error error
        | .ok (label, rest) =>
            match skipPostfixTrivia rest with
            | '(' :: rest =>
                -- Package-qualified call, e.g. `strings.ToUpper(x)`. Only a single
                -- `pkg.fn(...)` shape is a builtin; deeper selectors stay field access.
                match base with
                | .ref pkg =>
                    match parseCall s!"{pkg}.{label}" rest with
                    | .error error => .error error
                    | .ok (call, rest) => parseSelectorRest call rest
                | _ => parseSelectorRest (.selector base label) rest
            | _ => parseSelectorRest (.selector base label) rest
    | '[' :: rest =>
        match parseExpression rest with
        | .error error => .error error
        | .ok (key, rest) =>
            match skipTrivia rest with
            | ']' :: rest => parseSelectorRest (.index base key) rest
            | rest => parseError rest "expected ']' after index"
    | rest => parseOk base rest

  partial def parsePrimaryAtom (chars : List Char) : ParseResult Value :=
    match skipTrivia chars with
    | '(' :: rest =>
        match parseExpression rest with
        | .error error => .error error
        | .ok (value, rest) =>
            match skipTrivia rest with
            | ')' :: rest => parseOk value rest
            | rest => parseError rest "expected ')'"
    | '{' :: rest => parseStruct rest
    | '[' :: rest => parseList rest
    | '"' :: '"' :: '"' :: rest => parseMultilineString rest
    | '\'' :: '\'' :: '\'' :: rest => parseMultilineBytes rest
    | '"' :: rest => parseInterpolatedString rest [] []
    | '\'' :: rest =>
        match parseQuotedBytes ('\'' :: rest) with
        | .error error => .error error
        | .ok (value, rest) => parseOk (.prim (.bytes value)) rest
    | '_' :: '|' :: '_' :: rest => parseOk .bottom rest
    | '_' :: next :: rest =>
        -- `_` is top only when it does not begin a longer identifier (`_x`,
        -- `_foo`, `__bar`). A following identifier-rest char means the whole
        -- token is a `_`-prefixed identifier; defer to the identifier path.
        if parseIdentifierRest next then parseIdentifierValue (skipTrivia chars)
        else parseOk .top (next :: rest)
    | '_' :: rest => parseOk .top rest
    | '!' :: '=' :: rest =>
        match parsePrimary rest with
        | .error error => .error error
        | .ok (value, rest) =>
            match value with
            | .prim prim => parseOk (.notPrim prim) rest
            | _ => parseError rest "!= currently requires a primitive literal"
    | '=' :: '~' :: rest =>
        match parseQuotedString (skipTrivia rest) with
        | .error error => .error error
        | .ok (pattern, rest) => parseOk (.stringRegex pattern) rest
    | '>' :: '=' :: rest => parseBoundValue .ge rest
    | '>' :: rest => parseBoundValue .gt rest
    | '<' :: '=' :: rest => parseBoundValue .le rest
    | '<' :: rest => parseBoundValue .lt rest
    | '+' :: _ => parseNumberValue (skipTrivia chars)
    | '-' :: _ => parseNumberValue (skipTrivia chars)
    | value :: rest =>
        if parseDigit value then
          parseNumberValue (skipTrivia chars)
        else if parseIdentifierStart value then
          parseIdentifierValue (skipTrivia chars)
        else
          parseError (value :: rest) s!"unexpected character '{value}'"
    | [] => parseError [] "expected expression"

  partial def interpolationResult (parts : List Value) (rest : List Char) : ParseResult Value :=
    match parts with
    | [] => parseOk (.prim (.string "")) rest
    | [.prim (.string value)] => parseOk (.prim (.string value)) rest
    | parts => parseOk (.interpolation parts) rest

  partial def appendStringSegment (acc : List Char) (parts : List Value) : List Value :=
    match acc with
    | [] => parts
    | acc => parts ++ [.prim (.string (String.ofList acc.reverse))]

  partial def parseInterpolatedString
      (chars : List Char)
      (acc : List Char)
      (parts : List Value) : ParseResult Value :=
    match chars with
    | [] => parseError [] "unterminated string literal"
    | '"' :: rest => interpolationResult (appendStringSegment acc parts) rest
    | '\\' :: '(' :: rest =>
        match parseExpression rest with
        | .error error => .error error
        | .ok (hole, rest) =>
            match skipTrivia rest with
            | ')' :: rest =>
                parseInterpolatedString rest [] (appendStringSegment acc parts ++ [hole])
            | rest => parseError rest "expected ')' to close interpolation"
    | '\\' :: escaped :: rest => parseInterpolatedString rest (parseStringEscape escaped :: acc) parts
    | ['\\'] => parseError [] "unterminated string escape"
    | value :: rest => parseInterpolatedString rest (value :: acc) parts

  /-- Parse the content of a multiline string/bytes literal after the opening delimiter.
      `prefix` is the closing line's indentation, stripped from every content line. At a
      line start: a line that is exactly `prefix ++ delimiter` ends the literal; a blank
      line (immediate newline) contributes an empty line; any other line must begin with
      `prefix` (else CUE's "invalid whitespace"). Within a line, `\(expr)` interpolations
      and backslash escapes work as in single-line strings. The leading newline after the
      opening delimiter and the trailing newline before the closing line are excluded. -/
  partial def parseMultilineBody
      (quote : Char)
      (strip : List Char)
      (atLineStart : Bool)
      (chars : List Char)
      (acc : List Char)
      (parts : List Value) : ParseResult Value :=
    if atLineStart then
      match dropPrefix? strip chars with
      | some afterStrip =>
          match multilineDelimiter? quote afterStrip with
          | some rest =>
              -- Drop the newline that separates the last content line from the closing
              -- line; it is the delimiter terminator, not part of the value.
              let trimmed := match acc with
                | '\n' :: acc => acc
                | acc => acc
              interpolationResult (appendStringSegment trimmed parts) rest
          | none => parseMultilineBody quote strip false afterStrip acc parts
      | none =>
          match chars with
          | '\n' :: rest => parseMultilineBody quote strip true rest ('\n' :: acc) parts
          | [] => parseError [] "unterminated multiline literal"
          | _ => parseError chars "invalid whitespace in multiline literal"
    else
      match chars with
      | [] => parseError [] "unterminated multiline literal"
      | '\n' :: rest => parseMultilineBody quote strip true rest ('\n' :: acc) parts
      | '\\' :: '(' :: rest =>
          match parseExpression rest with
          | .error error => .error error
          | .ok (hole, rest) =>
              match skipTrivia rest with
              | ')' :: rest =>
                  parseMultilineBody quote strip false rest [] (appendStringSegment acc parts ++ [hole])
              | rest => parseError rest "expected ')' to close interpolation"
      | '\\' :: escaped :: rest =>
          parseMultilineBody quote strip false rest (parseStringEscape escaped :: acc) parts
      | value :: rest => parseMultilineBody quote strip false rest (value :: acc) parts

  /-- The shared opening-line handling for multiline literals: the opening delimiter must
      be followed (after optional horizontal whitespace) by a newline — content on the
      opening line is rejected, matching CUE. Returns the literal's parsed value via
      `parseMultilineBody`, after locating the closing line's strip prefix. -/
  partial def parseMultilineOpen (quote : Char) (chars : List Char) : ParseResult Value :=
    match multilineStripPrefix? quote chars with
    | none => parseError chars "unterminated multiline literal"
    | some strip =>
        let afterWs := (splitLeadingHorizontalWhitespace chars).snd
        match afterWs with
        | '\n' :: rest => parseMultilineBody quote strip true rest [] []
        | _ => parseError chars "expected newline after multiline quote"

  partial def parseMultilineString (chars : List Char) : ParseResult Value :=
    parseMultilineOpen '"' chars

  partial def parseMultilineBytes (chars : List Char) : ParseResult Value :=
    match parseMultilineOpen '\'' chars with
    | .error error => .error error
    | .ok (value, rest) =>
        match value with
        | .prim (.string text) => parseOk (.prim (.bytes text)) rest
        | _ => parseError chars "interpolation in multiline bytes is not supported yet"

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
    | rest => parseError rest "expected ']' after list tail"

  partial def parseListTail (items : List Value) (chars : List Char) : ParseResult Value :=
    match skipTrivia chars with
    | '.' :: '.' :: '.' :: rest =>
        match skipTrivia rest with
        | ']' :: rest => parseOk (.listTail items .top) rest
        | rest =>
            match parseExpression rest with
            | .error error => .error error
            | .ok (tail, rest) => parseListTailEnd (.listTail items tail) rest
    | rest => parseError rest "expected list tail"

  partial def parseListItems (chars : List Char) (items : List Value) : ParseResult Value :=
    match skipTrivia chars with
    | ']' :: rest => parseOk (.list items) rest
    | '.' :: '.' :: '.' :: _ => parseListTail items chars
    | trimmed =>
        match trimmed with
        | [] => parseError [] "expected ']'"
        | _ =>
            -- A `for`/`if` clause head begins a list comprehension item (`[for x in xs {x}]`).
            -- Parse it with the SAME clause machinery the struct-comprehension form uses; the
            -- brace-block body value is yielded as list ELEMENTS at eval time. A bare `if`/`for`
            -- identifier cannot start a plain list expression, so this dispatch is unambiguous.
            if startsWithWord "for" trimmed || startsWithWord "if" trimmed then
              match parseListComprehension trimmed with
              | .error error => .error error
              | .ok (item, rest) =>
                  parseListItems (parseCommaOrSemicolon (skipTrivia rest)) (items ++ [item])
            else
              match parseExpression trimmed with
              | .error error => .error error
              | .ok (item, rest) =>
                  parseListItems (parseCommaOrSemicolon (skipTrivia rest)) (items ++ [item])

  /-- Parse a list-context comprehension `for…/if… {body}` into a `.listComprehension` item,
      reusing the shared clause parser. `parseComprehensionClauses` returns the clause chain
      plus the brace-block body value (the element yielded per innermost iteration). -/
  partial def parseListComprehension (chars : List Char) : ParseResult Value :=
    match parseClause chars with
    | .error error => .error error
    | .ok (clause, rest) =>
        match parseComprehensionClauses rest [clause] with
        | .error error => .error error
        | .ok ((clauses, body), rest) => parseOk (.listComprehension clauses body) rest

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
    | [] => parseError [] s!"expected '{terminator}'"

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
                | rest => parseError rest "expected ':' after pattern label"
            | rest => parseError rest "expected ']' after pattern label"
    | rest => parseError rest "expected pattern field"

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
              | rest => parseError rest "expected '=' after let binding name"
      | none => parseError chars "expected let binding"
    else
      parseError chars "expected let binding"

  partial def parseStructEllipsis (chars : List Char) : ParseResult ParsedField :=
    match skipTrivia chars with
    | '.' :: '.' :: '.' :: rest =>
        if structEllipsisEndsHere (skipTrivia rest) then
          parseOk (.ellipsis .top) rest
        else
          parseError (skipTrivia rest) "typed struct ellipsis is not supported yet"
    | rest => parseError rest "expected struct ellipsis"

  partial def parseForClause (chars : List Char) : ParseResult (Clause Value) :=
    match dropWord? "for" (skipTrivia chars) with
    | none => parseError (skipTrivia chars) "expected for clause"
    | some rest =>
        match parseIdentifier (skipTrivia rest) with
        | .error error => .error error
        | .ok (first, rest) =>
            match skipTrivia rest with
            | ',' :: rest =>
                match parseIdentifier (skipTrivia rest) with
                | .error error => .error error
                | .ok (value, rest) =>
                    match dropWord? "in" (skipTrivia rest) with
                    | none => parseError (skipTrivia rest) "expected 'in' in for clause"
                    | some rest =>
                        match parseExpression rest with
                        | .error error => .error error
                        | .ok (source, rest) => parseOk (.forIn (some first) value source) rest
            | rest =>
                match dropWord? "in" rest with
                | none => parseError rest "expected 'in' in for clause"
                | some rest =>
                    match parseExpression rest with
                    | .error error => .error error
                    | .ok (source, rest) => parseOk (.forIn none first source) rest

  partial def parseIfClause (chars : List Char) : ParseResult (Clause Value) :=
    match dropWord? "if" (skipTrivia chars) with
    | none => parseError (skipTrivia chars) "expected if clause"
    | some rest =>
        match parseExpression rest with
        | .error error => .error error
        | .ok (condition, rest) => parseOk (.guard condition) rest

  partial def parseClause (chars : List Char) : ParseResult (Clause Value) :=
    match parseForClause chars with
    | .ok parsed => .ok parsed
    | .error _ => parseIfClause chars

  partial def parseComprehensionClauses
      (chars : List Char)
      (clauses : List (Clause Value)) : ParseResult (List (Clause Value) × Value) :=
    match parseClause chars with
    | .ok (clause, rest) => parseComprehensionClauses rest (clauses ++ [clause])
    | .error _ =>
        match skipTrivia chars with
        | '{' :: rest =>
            match parseStruct rest with
            | .error error => .error error
            | .ok (body, rest) => parseOk (clauses, body) rest
        | rest => parseError rest "expected comprehension body struct"

  partial def parseComprehension (chars : List Char) : ParseResult ParsedField :=
    match parseClause chars with
    | .error error => .error error
    | .ok (clause, rest) =>
        match parseComprehensionClauses rest [clause] with
        | .error error => .error error
        | .ok ((clauses, body), rest) => parseOk (.comprehension clauses body) rest

  partial def parseEmbedding (chars : List Char) : ParseResult ParsedField :=
    match parseExpression chars with
    | .error error => .error error
    | .ok (value, rest) => parseOk (.embedding value) rest

  /-- Parse the value position of a field. If it begins another field (`a: b: …`),
      desugar the colon-shorthand chain into a nested single-field struct identical to
      the brace form (`a: {b: …}`) by recursing through `parseField` and the same
      `parsedFieldsValue` builder the brace path uses. Otherwise parse an expression. -/
  partial def parseFieldValue (chars : List Char) : ParseResult Value :=
    match valueAliasHead? chars with
    | some (name, rest) =>
        match parseFieldValue rest with
        | .error error => .error error
        | .ok (value, rest) => parseOk (bindValueAlias name value) rest
    | none =>
      if valuePositionStartsField chars || valuePositionStartsPatternField chars then
        match parseField chars with
        | .error error => .error error
        | .ok (inner, rest) => parseOk (parsedFieldsValue [inner]) rest
      else
        parseExpression chars

  partial def parseLabeledField (label : String) (rest : List Char) : ParseResult ParsedField :=
    let (fieldClass, rest) := parseFieldClass label rest
    match skipTrivia rest with
    | ':' :: rest =>
        match parseFieldValue rest with
        | .error error => .error error
        | .ok (value, rest) => parseOk (.field ⟨label, fieldClass, value⟩) rest
    | rest => parseError rest "expected ':' after field label"

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
                    match parseFieldValue rest with
                    | .error error => .error error
                    | .ok (value, rest) => parseOk (.fieldAlias alias ⟨label, fieldClass, value⟩) rest
                | rest => parseError rest "expected ':' after aliased field label"
        | rest => parseError rest "expected '=' after field alias"

  partial def parseDynamicField (chars : List Char) : ParseResult ParsedField :=
    match skipTrivia chars with
    | '(' :: rest =>
        match parseExpression rest with
        | .error error => .error error
        | .ok (label, rest) =>
            match skipTrivia rest with
            | ')' :: rest =>
                let (fieldClass, rest) :=
                  match skipTrivia rest with
                  | '?' :: rest => (FieldClass.optional, rest)
                  | '!' :: rest => (FieldClass.required, rest)
                  | rest => (FieldClass.regular, rest)
                match skipTrivia rest with
                | ':' :: rest =>
                    match parseFieldValue rest with
                    | .error error => .error error
                    | .ok (value, rest) => parseOk (.dynamicField label fieldClass value) rest
                | rest => parseError rest "expected ':' after dynamic field label"
            | rest => parseError rest "expected ')' after dynamic field label"
    | rest => parseError rest "expected dynamic field"

  /--
  A quoted field label. A plain string literal is a static label; one carrying an
  interpolation is a dynamic field whose label is computed from the enclosing scope.
  -/
  partial def parseQuotedLabelField (chars : List Char) : ParseResult ParsedField :=
    match skipTrivia chars with
    | '"' :: rest =>
        match parseInterpolatedString rest [] [] with
        | .error error => .error error
        | .ok (labelValue, rest) =>
            let (fieldClass, afterClass) :=
              match skipTrivia rest with
              | '?' :: rest => (FieldClass.optional, rest)
              | '!' :: rest => (FieldClass.required, rest)
              | rest => (FieldClass.regular, rest)
            match skipTrivia afterClass with
            | ':' :: afterColon =>
                match parseFieldValue afterColon with
                | .error error => .error error
                | .ok (value, rest) =>
                    match labelValue with
                    | .prim (.string label) => parseOk (.field ⟨label, fieldClass, value⟩) rest
                    | _ => parseOk (.dynamicField labelValue fieldClass value) rest
            | rest => parseError rest "expected ':' after quoted field label"
    | rest => parseError rest "expected quoted field label"

  partial def parseField (chars : List Char) : ParseResult ParsedField :=
    match skipTrivia chars with
    | '[' :: _ =>
        match parsePatternField chars with
        | .ok parsed => .ok parsed
        | .error _ => parseEmbedding chars
    | '.' :: '.' :: '.' :: _ => parseStructEllipsis chars
    | '"' :: _ =>
        match parseQuotedLabelField chars with
        | .ok parsed => .ok parsed
        | .error _ => parseEmbedding chars
    | '(' :: _ =>
        match parseDynamicField chars with
        | .ok parsed => .ok parsed
        | .error _ => parseEmbedding chars
    | chars =>
        if startsWithWord "for" chars || startsWithWord "if" chars then
          parseComprehension chars
        else
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
  let chars := consumeImportClauses (consumePackageClauses chars)
  match parseFieldsUntil none chars [] with
  | .error error => .error error
  | .ok (fields, rest) =>
      match skipTrivia rest with
      | [] => .ok (parsedFieldsValue fields)
      | rest => parseError rest "unexpected trailing input"

/-- 1-based line and column for a char offset into `source`. Walks the first `offset`
    chars, counting newlines; the column resets to 1 after each `'\n'`. Total: recurses
    structurally on the char list with `offset` as decreasing fuel. -/
def offsetToLineColumn (source : List Char) (offset : Nat) : Nat × Nat :=
  go source offset 1 1
where
  go : List Char -> Nat -> Nat -> Nat -> Nat × Nat
    | _, 0, line, col => (line, col)
    | [], _, line, col => (line, col)
    | c :: rest, fuel + 1, line, col =>
        if c == '\n' then go rest fuel (line + 1) 1
        else go rest fuel line (col + 1)

/-- Fill in `line`/`column` on a parse error from its `remaining` suffix length, using
    the original source to derive the offset. The error reason (`message`) is left as-is;
    callers print `line:column: message`. -/
def withPosition (source : List Char) : Except ParseError α -> Except ParseError α
  | .ok value => .ok value
  | .error error =>
      let offset := source.length - error.remaining
      let (line, column) := offsetToLineColumn source offset
      .error { error with line := line, column := column }

def parseSource (source : String) : Except ParseError Value :=
  withPosition source.toList (parseDocument source.toList)

/-- Parse a `.cue` file into a `ParsedFile`: collect its imports (rather than discarding
    them), record the declared package name, and parse the body exactly as `parseDocument`
    does. The body parse is unchanged from the no-import path — imports are stripped up
    front, leaving the same field stream `parseDocument` consumes. -/
def parseDocumentFile (chars : List Char) : Except ParseError ParsedFile := do
  let afterPackage := consumePackageClauses chars
  let (imports, afterImports) ← parseImportClauses [] afterPackage
  match parseFieldsUntil none afterImports [] with
  | .error error => .error error
  | .ok (fields, rest) =>
      match skipTrivia rest with
      | [] =>
          let packageName ← sourcePackageName (String.ofList chars)
          pure { value := parsedFieldsValue fields, packageName := packageName, imports := imports }
      | rest => parseError rest "unexpected trailing input"

def parseSourceFile (source : String) : Except ParseError ParsedFile :=
  withPosition source.toList (parseDocumentFile source.toList)

end Kue
