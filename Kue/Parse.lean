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
  /-- A labelled field. `quoted` records whether the label was written as a quoted string
      (`"dep": …`) rather than a bare identifier (`dep: …`); the two produce the same
      `Field` but only a bare identifier participates in the file-block identifier scope,
      so the import-name redeclaration check (A2-y) exempts the quoted form. -/
  | field (field : Field) (quoted : Bool)
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

partial def skipTrivia : List Char -> List Char
  | [] => []
  | '/' :: '/' :: rest => skipTrivia (dropLine rest)
  | value :: rest =>
      if parseWhitespace value then
        skipTrivia rest
      else
        value :: rest

/-- Skip same-line trivia when hunting for a trailing binary operator that would CONTINUE an
    expression: horizontal whitespace only, stopping at a newline, a line comment (`//`), or
    the next real token. A newline after a complete expression terminates it — CUE inserts an
    implicit comma there — so it is never crossed here; it is left in place for the
    field/element separator to observe. An operator found on the same line still continues
    onto the next line, since the operand parse skips full trivia after the operator. -/
partial def skipSameLineTrivia : List Char -> List Char
  | value :: rest =>
      if parseHorizontalWhitespace value then
        skipSameLineTrivia rest
      else
        value :: rest
  | [] => []

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


/-- Value of a single hex digit (`0-9a-fA-F`), else `none`. -/
def hexDigitVal? (c : Char) : Option Nat :=
  if parseAsciiBetween '0' '9' c then some (c.toNat - '0'.toNat)
  else if parseAsciiBetween 'a' 'f' c then some (c.toNat - 'a'.toNat + 10)
  else if parseAsciiBetween 'A' 'F' c then some (c.toNat - 'A'.toNat + 10)
  else none

/-- Value of a single octal digit (`0-7`), else `none`. -/
def octDigitVal? (c : Char) : Option Nat :=
  if parseAsciiBetween '0' '7' c then some (c.toNat - '0'.toNat) else none

/-- Read exactly `count` hex digits, folding MSB-first, or `none` if fewer are present. -/
def readHexDigits (count : Nat) (acc : Nat) : List Char -> Option (Nat × List Char)
  | chars =>
    match count, chars with
    | 0, chars => some (acc, chars)
    | _ + 1, [] => none
    | n + 1, c :: rest =>
        match hexDigitVal? c with
        | some d => readHexDigits n (acc * 16 + d) rest
        | none => none

/-- Read exactly three octal digits after the leading one (`d0`), or `none` if malformed.
    CUE octal byte escapes are exactly three digits (`\101`), not variable-length. -/
def readOctalRest (d0 : Nat) : List Char -> Option (Nat × List Char)
  | c1 :: c2 :: rest =>
      match octDigitVal? c1, octDigitVal? c2 with
      | some d1, some d2 => some (d0 * 64 + d1 * 8 + d2, rest)
      | _, _ => none
  | _ => none

/-- The UTF-8 bytes of a single character, for a plain (unescaped) byte-literal char or an
    unrecognized escape kept literally. -/
def charBytes (c : Char) : List UInt8 := (String.singleton c).toUTF8.toList

/-- The UTF-8 bytes of a Unicode codepoint (`\uNNNN`/`\UNNNNNNNN`), which encode to one or
    more bytes. Distinct from `\xNN`/`\NNN`, which name a single raw byte directly. -/
def codepointBytes (n : Nat) : List UInt8 := charBytes (Char.ofNat n)

/-- Decode one byte-literal escape body (the chars AFTER the `\`), returning the decoded
    raw bytes and the remainder, or `none` if the escape is unrecognized/malformed (the
    caller then keeps the escaped char literally, matching CUE's lenient string escapes for
    the simple cases). CUE byte literals additionally support `\xNN` (hex byte), `\NNN`
    (octal byte), `\uNNNN`/`\UNNNNNNNN` (unicode → UTF-8), and `\a\b\f\v` alongside the
    shared `\n\r\t\\\'\"`. A `\xNN`/`\NNN` names ONE raw byte — including NN ≥ 0x80, held
    exactly by the `Array UInt8` carrier; `\uNNNN`/`\UNNNNNNNN` names a codepoint and
    UTF-8-encodes to its byte sequence. `\(` is deliberately unhandled here: byte-context
    interpolation is not yet implemented, so it falls through to a literal `(`. -/
def decodeByteEscape : List Char -> Option (List UInt8 × List Char)
  | 'x' :: rest =>
      match readHexDigits 2 0 rest with
      | some (value, rest) => some ([UInt8.ofNat value], rest)
      | none => none
  | 'u' :: rest =>
      match readHexDigits 4 0 rest with
      | some (value, rest) => some (codepointBytes value, rest)
      | none => none
  | 'U' :: rest =>
      match readHexDigits 8 0 rest with
      | some (value, rest) => some (codepointBytes value, rest)
      | none => none
  | 'a' :: rest => some ([0x07], rest)
  | 'b' :: rest => some ([0x08], rest)
  | 'f' :: rest => some ([0x0c], rest)
  | 'v' :: rest => some ([0x0b], rest)
  | 'n' :: rest => some ([0x0a], rest)
  | 'r' :: rest => some ([0x0d], rest)
  | 't' :: rest => some ([0x09], rest)
  | '\\' :: rest => some ([0x5c], rest)
  | '\'' :: rest => some ([0x27], rest)
  | '"' :: rest => some ([0x22], rest)
  | c :: rest =>
      match octDigitVal? c with
      | some d0 =>
          match readOctalRest d0 rest with
          | some (value, rest) => some ([UInt8.ofNat value], rest)
          | none => none
      | none => none
  | [] => none

/-- Read `count` hex digits (`\uNNNN`/`\UNNNNNNNN`) and, if they name a valid Unicode code
    point, return it as a `Char` with the remainder. `none` if fewer digits are present, or
    the value is a surrogate / out of range — both are escape errors in `cue`
    (`unmatched surrogate pair`, `invalid Unicode code point`), not silent replacement. -/
def decodeUnicodeEscape (count : Nat) (chars : List Char) : Option (Char × List Char) :=
  match readHexDigits count 0 chars with
  | some (value, rest) => if value.isValidChar then some (Char.ofNat value, rest) else none
  | none => none

/-- Decode one CUE double-quoted string escape body (the chars AFTER the `\`), returning
    the decoded code point and the remainder, or `none` when the escape is unknown or
    malformed. A bad escape in a STRING is a hard parse error the caller raises. CUE strings
    admit the simple escapes `\a\b\f\n\r\t\v\\\/\"` and the Unicode escapes
    `\uNNNN`/`\UNNNNNNNN`. The byte escapes `\xNN`/`\NNN` are single-quote byte-literal only,
    and the escapable quote is context-sensitive: `\"` is the string's quote (valid here),
    while `\'` is byte-literal only — both are rejected, matching `cue`. -/
def decodeStringEscape : List Char -> Option (Char × List Char)
  | 'u' :: rest => decodeUnicodeEscape 4 rest
  | 'U' :: rest => decodeUnicodeEscape 8 rest
  | 'a' :: rest => some (Char.ofNat 0x07, rest)
  | 'b' :: rest => some (Char.ofNat 0x08, rest)
  | 'f' :: rest => some (Char.ofNat 0x0c, rest)
  | 'v' :: rest => some (Char.ofNat 0x0b, rest)
  | 'n' :: rest => some ('\n', rest)
  | 'r' :: rest => some ('\r', rest)
  | 't' :: rest => some ('\t', rest)
  | '\\' :: rest => some ('\\', rest)
  | '/' :: rest => some ('/', rest)
  | '"' :: rest => some ('"', rest)
  | _ => none

partial def parseQuotedWith (quote : Char) : List Char -> List Char -> ParseResult String
  | [], _ => parseError [] "unterminated string literal"
  | value :: rest, acc =>
      if value == quote then
        parseOk (String.ofList acc.reverse) rest
      else if value == '\\' then
        match decodeStringEscape rest with
        | some (decoded, rest) => parseQuotedWith quote rest (decoded :: acc)
        | none =>
            match rest with
            | [] => parseError [] "unterminated string escape"
            | _ => parseError rest "invalid escape sequence in string literal"
      else
        parseQuotedWith quote rest (value :: acc)

def parseQuotedString : List Char -> ParseResult String
  | '"' :: rest => parseQuotedWith '"' rest []
  | chars => parseError chars "expected string literal"

/-- Lex a single-quoted byte literal body, decoding CUE byte escapes (`\xNN`, `\NNN` octal,
    `\uNNNN`, `\UNNNNNNNN`, `\a\b\f\n\r\t\v\\\'\"`). Unrecognized escapes keep the escaped
    char literally (drops the `\`), matching the lenient string path; `\(` is thus left as a
    literal `(` since byte-context interpolation is not yet implemented. -/
partial def parseQuotedByteBody : List Char -> List UInt8 -> ParseResult (Array UInt8)
  | [], _ => parseError [] "unterminated byte literal"
  | '\'' :: rest, acc => parseOk acc.reverse.toArray rest
  | '\\' :: rest, acc =>
      match decodeByteEscape rest with
      | some (decoded, rest) => parseQuotedByteBody rest (decoded.reverse ++ acc)
      | none =>
          match rest with
          | escaped :: rest => parseQuotedByteBody rest ((charBytes escaped).reverse ++ acc)
          | [] => parseError [] "unterminated byte escape"
  | value :: rest, acc => parseQuotedByteBody rest ((charBytes value).reverse ++ acc)

def parseQuotedBytes : List Char -> ParseResult (Array UInt8)
  | '\'' :: rest => parseQuotedByteBody rest []
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

/-- The CUE spec reserves every identifier whose spelling begins with `__` (two
    underscores) as a language keyword, so a user identifier `__x` (field label, reference,
    package name, alias) is invalid in EVERY identifier position. The check is on the raw
    spelling: `#__x` begins with `#` and `_#__x` with `_#` (definition / hidden-definition
    prefixes), so neither is `__`-reserved; a single leading `_` (`_x`) is the valid
    hidden-field form. Quoted string labels never reach here, so `"__x": 1` stays valid. -/
def reservedDoubleUnderscore (name : String) : Bool :=
  name.startsWith "__"

def parseIdentifier : List Char -> ParseResult String
  | value :: rest =>
      if parseIdentifierStart value then
        let taken := takeWhileChars parseIdentifierRest rest [value]
        let name := String.ofList taken.fst
        if reservedDoubleUnderscore name then
          parseError (value :: rest) s!"identifiers starting with '__' are reserved: '{name}'"
        else
          parseOk name taken.snd
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

/-- Whether `name` is a well-formed CUE package qualifier: a non-empty identifier
    (`identifier_start` then `identifier_part`s) that is NOT a definition identifier (no
    leading `#`/`_#` — the spec forbids a definition identifier as a PackageName) and is not
    the lone blank identifier `_` (the top/hidden marker; cue rejects it as a qualifier —
    `_ is not a valid import path qualifier`). The `:identifier` suffix of an import path
    defaults the local package name, so it must obey this rule. -/
def isPackageIdentifier (name : String) : Bool :=
  match name.toList with
  | [] => false
  | ['_'] => false
  | '#' :: _ => false
  | '_' :: '#' :: _ => false
  | first :: rest => parseIdentifierStart first && rest.all parseIdentifierRest

/-- Split a parsed import-path string into its location and optional `:identifier`
    qualifier per the spec `ImportPath = '"' ImportLocation [ ":" identifier ] '"'`. An
    ImportLocation may not itself contain `:` (the spec's excluded-character set), so the
    sole `:` — when present — is the qualifier separator. The location must be non-empty
    (an empty location is not a valid ImportLocation; cue rejects `":foo"` / `""` as
    `invalid import path`). Returns `(location, some id)` with `id` validated as a package
    identifier, `(location, none)` when there is no `:`, or an error when the location is
    empty or the qualifier is empty/malformed. -/
def splitImportPath (raw : String) (errChars : List Char) :
    Except ParseError (String × Option String) :=
  match raw.splitOn ":" with
  | [location] =>
      if location.isEmpty then
        parseError errChars s!"invalid import path: '{raw}'"
      else
        .ok (location, none)
  | [location, qualifier] =>
      if location.isEmpty then
        parseError errChars s!"invalid import path: '{raw}'"
      else if isPackageIdentifier qualifier then
        .ok (location, some qualifier)
      else
        parseError errChars s!"invalid package identifier in import path: '{qualifier}'"
  | _ => parseError errChars s!"malformed import path '{raw}': multiple ':' qualifiers"

/-- Parse one import spec: an optional bare identifier alias (`PackageName`) followed by a
    quoted import path whose optional `:identifier` qualifier is split into `packageName`.
    `import "example.com/defs"` yields `{path := "example.com/defs"}`;
    `import "example.com/defs:foo"` yields `{path := "example.com/defs", packageName := some "foo"}`;
    `import bar "example.com/defs"` yields `{path := "example.com/defs", alias := some "bar"}`. -/
def parseImportSpec (chars : List Char) : ParseResult Import :=
  let trimmed := skipTrivia chars
  match parseQuotedString trimmed with
  | .ok (raw, rest) =>
      match splitImportPath raw trimmed with
      | .error error => .error error
      | .ok (location, packageName) =>
          parseOk { path := location, packageName := packageName } rest
  | .error _ =>
      match parseIdentifier trimmed with
      | .error error => .error error
      | .ok (alias, rest) =>
          match parseQuotedString (skipTrivia rest) with
          | .error error => .error error
          | .ok (raw, rest) =>
              match splitImportPath raw (skipTrivia rest) with
              | .error error => .error error
              | .ok (location, packageName) =>
                  parseOk { path := location, packageName := packageName, alias := some alias } rest

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
  -- hidden-only would drop its definition-ness, so a hidden-def embedding's sibling self-ref
  -- would not defer to a closure and would miss use-site narrowing.
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
        parseOk (.prim (mkFloatText token)) rest
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

/-- Scan the trivia after a parsed field for a field separator, reporting whether one was
    crossed and advancing to the next non-trivia token. CUE separates struct declarations by
    an explicit `,`/`;` or by a newline (a newline auto-inserts a comma). A line comment ends
    at a newline, so it counts. The `sawSep` accumulator carries the verdict across
    interleaved line comments and horizontal whitespace. -/
partial def fieldSeparatorAux (sawSep : Bool) : List Char -> Bool × List Char
  | [] => (sawSep, [])
  | '/' :: '/' :: rest => fieldSeparatorAux true (dropLine rest)
  | ',' :: rest => fieldSeparatorAux true rest
  | ';' :: rest => fieldSeparatorAux true rest
  | '\n' :: rest => fieldSeparatorAux true rest
  | value :: rest =>
      if parseWhitespace value then fieldSeparatorAux sawSep rest
      else (sawSep, value :: rest)

def fieldSeparator : List Char -> Bool × List Char :=
  fieldSeparatorAux false

def parseFieldTerminator (terminator : Option Char) (chars : List Char) : Bool :=
  match terminator, chars with
  | some expected, value :: _ => value == expected
  | none, [] => true
  | _, _ => false

/-- The bare-identifier, output-namespace labels declared at this struct's top level — the
    labels that occupy the file-block identifier scope and so can collide with an imported
    package's local name (A2-y). A label qualifies iff it was written as a BARE identifier
    (`quoted = false`; a quoted `"dep"` is a string label, not an identifier declaration) and
    its class is an ordinary field (definitions `#x` and hidden `_x` live in distinct
    namespaces — cue exempts both — and `let`/`importBinding`/pattern/embedding declare no
    output identifier here). All three presence rungs (`regular`/`optional`/`required`) count:
    cue's `redeclared as imported package name` fires on `dep:`, `dep?:`, and `dep!:` alike. -/
def bareIdentifierLabels : List ParsedField -> List String
  | [] => []
  | .field field false :: rest =>
      match field.fieldClass with
      | .field false false _ => field.label :: bareIdentifierLabels rest
      | _ => bareIdentifierLabels rest
  | _ :: rest => bareIdentifierLabels rest

def splitParsedFields : List ParsedField -> ParsedFieldParts
  | [] => { fields := [], patterns := [], comprehensions := [], tail := none }
  | .field field _ :: rest =>
      let split := splitParsedFields rest
      { split with fields := field :: split.fields }
  | .fieldAlias alias field :: rest =>
      let split := splitParsedFields rest
      { split with fields := field :: ⟨alias, .letBinding, .ref (Field.label field), false⟩ :: split.fields }
  | .pattern labelPattern constraint :: rest =>
      let split := splitParsedFields rest
      { split with patterns := (labelPattern, constraint) :: split.patterns }
  | .embedding value :: rest =>
      let split := splitParsedFields rest
      { split with comprehensions := value :: split.comprehensions }
  | .letBinding name value :: rest =>
      let split := splitParsedFields rest
      { split with fields := ⟨name, .letBinding, value, false⟩ :: split.fields }
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
  | [] => mkStruct fields .regularOpen none []
  | [pattern] => mkStruct fields .regularOpen none [(pattern.fst, pattern.snd)]
  | patterns => mkStruct fields .regularOpen none patterns

/-- The labels at THIS struct's top level that can collide with a `let`/alias of the same
    name (cue: `cannot have both alias and field with name X in same scope`). A label
    qualifies iff it was written as a BARE identifier (`quoted = false`) and its class is an
    ordinary field — regular/optional/required OR hidden (`_x`). Definitions (`#x`), quoted
    labels, dynamic `(expr)` labels, patterns, embeddings, and `let`/alias bindings declare
    no colliding output identifier here. Unlike `bareIdentifierLabels` (A2-y, import scope)
    this INCLUDES hidden fields: cue rejects `_x` reused by `let _x`. -/
def collidableLabels : List ParsedField -> List String
  | [] => []
  | .field field false :: rest =>
      match field.fieldClass with
      | .field false _ _ => field.label :: collidableLabels rest
      | _ => collidableLabels rest
  | _ :: rest => collidableLabels rest

-- Struct-member labels a value's lexical subtree contributes to the no-shadow check, selected
-- by `keep` (the `let`-binder side for FORWARD, the collidable-field side for REVERSE). ONE
-- traversal parameterised by the leaf predicate so the two directions can never structurally
-- drift. Comprehension `let` CLAUSES and `for` loop variables are NOT struct members — cue
-- accepts a field alongside a comprehension `let`/`for` of the same name — so their clause
-- binders are skipped (clause VALUES/bodies are still recursed, to catch struct-member decls
-- nested inside a comprehension). Produces `List String` (a collector, not a `Value`-dispatch),
-- so the leaf `| _` is a terminal, not a swallowed ctor.
mutual
  partial def collectMemberLabels (keep : Field -> Option String) : Value -> List String
    | .struct fields _ tail patterns _ =>
        fieldMemberLabels keep fields
          ++ (match tail with | some t => collectMemberLabels keep t | none => [])
          ++ patterns.flatMap (fun p => collectMemberLabels keep p.fst ++ collectMemberLabels keep p.snd)
    | .structComp fields comprehensions _ =>
        fieldMemberLabels keep fields ++ comprehensions.flatMap (collectMemberLabels keep)
    | .embeddedList items tail decls =>
        items.flatMap (collectMemberLabels keep)
          ++ (match tail with | some t => collectMemberLabels keep t | none => [])
          ++ fieldMemberLabels keep decls
    | .embeddedScalar scalar decls => collectMemberLabels keep scalar ++ fieldMemberLabels keep decls
    | .comprehension clauses body => clauseMemberLabels keep clauses ++ collectMemberLabels keep body
    | .listComprehension clauses body => clauseMemberLabels keep clauses ++ collectMemberLabels keep body
    | .list items => items.flatMap (collectMemberLabels keep)
    | .listTail items tail => items.flatMap (collectMemberLabels keep) ++ collectMemberLabels keep tail
    | .conj cs => cs.flatMap (collectMemberLabels keep)
    | .disj alts => alts.flatMap (fun a => collectMemberLabels keep a.snd)
    | .binary _ l r => collectMemberLabels keep l ++ collectMemberLabels keep r
    | .unary _ inner => collectMemberLabels keep inner
    | .selector base _ => collectMemberLabels keep base
    | .index base key => collectMemberLabels keep base ++ collectMemberLabels keep key
    | .builtinCall _ args => args.flatMap (collectMemberLabels keep)
    | .interpolation parts => parts.flatMap (collectMemberLabels keep)
    | .dynamicField label _ value => collectMemberLabels keep label ++ collectMemberLabels keep value
    | _ => []

  partial def fieldMemberLabels (keep : Field -> Option String) : List Field -> List String
    | [] => []
    | fl :: rest =>
        (match keep fl with | some n => [n] | none => [])
          ++ collectMemberLabels keep fl.value ++ fieldMemberLabels keep rest

  partial def clauseMemberLabels (keep : Field -> Option String) : List (Clause Value) -> List String
    | [] => []
    | .letClause _ value :: rest => collectMemberLabels keep value ++ clauseMemberLabels keep rest
    | .forIn _ _ source :: rest => collectMemberLabels keep source ++ clauseMemberLabels keep rest
    | .guard cond :: rest => collectMemberLabels keep cond ++ clauseMemberLabels keep rest
end

/-- Leaf predicate: a `let`/value-alias struct-member binder (`FieldClass.letBinding`, which
    also carries desugared value aliases `x=…`). -/
def letBinderLabel (field : Field) : Option String :=
  if field.fieldClass == .letBinding then some field.label else none

/-- Leaf predicate: a bare/hidden output-identifier field that can collide with a same-named
    `let`/alias — a non-quoted, non-definition field (regular/optional/required OR hidden). A
    quoted `"x"` label, a definition `#x`, and `let`/import binders declare no colliding
    identifier here, so are exempt (the over-rejection guard on the field side). -/
def collidableFieldLabel (field : Field) : Option String :=
  if field.quoted.value then none
  else match field.fieldClass with
    | .field false _ _ => some field.label
    | _ => none

/-- Every struct-member `let`/alias name bound in a value's lexical subtree. -/
def collectLetNames (value : Value) : List String := collectMemberLabels letBinderLabel value

/-- Every quoted-accurate bare/hidden field name declared in a value's lexical subtree — the
    REVERSE-direction dual of `collectLetNames`. Sound only because `Field.quoted` survives to
    the `Value` layer (a string `"x"` label is excluded), so an ancestor `let x` is not falsely
    reported colliding with a descendant `"x":`. -/
def collectFieldNames (value : Value) : List String := collectMemberLabels collidableFieldLabel value

/-- The `let`/value-alias names bound at THIS struct's top level (from `parsedFields`, before the
    value tree flattens them). A comprehension `let` CLAUSE lives inside a `.comprehension`
    parsed-field, not at top level, so it is naturally excluded — cue exempts clause binders. -/
def topLevelLetNames : List ParsedField -> List String
  | [] => []
  | .letBinding name _ :: rest => name :: topLevelLetNames rest
  | .fieldAlias alias _ :: rest => alias :: topLevelLetNames rest
  | _ :: rest => topLevelLetNames rest

/-- The no-shadow error cue raises when a `let`/alias and a field share a name in the same
    lexical scope (or across a comparable enclosing/nested scope pair). -/
def letFieldShadowError (name : String) : String :=
  s!"cannot have both alias and field with name \"{name}\" in same scope"

/-- Reject a struct where a `let`/alias and a bare/hidden field share a name across comparable
    lexical scopes (cue's load-time no-shadow rule). Runs at every struct scope, catching BOTH
    directions: a top-level FIELD colliding with a `let` anywhere in the subtree (FORWARD), and a
    top-level `let` colliding with a FIELD anywhere in the subtree (REVERSE). Both sides are
    quoted-accurate — `collidableLabels`/`collidableFieldLabel` exempt string labels and `let`
    names are never quoted — so a reported collision is exactly one cue rejects (no
    over-rejection; the cert-manager canary is the guard). Every descendant scope is comparable
    to the anchoring struct and incomparable cousins are anchored at distinct structs, so neither
    direction fires across incomparable scopes. -/
def checkLetFieldShadow (parsedFields : List ParsedField) (structValue : Value) :
    Except ParseError Unit :=
  let subtreeLets := collectLetNames structValue
  let subtreeFields := collectFieldNames structValue
  match (collidableLabels parsedFields).find? (fun label => subtreeLets.contains label) with
  | some name => .error { message := letFieldShadowError name }
  | none =>
    match (topLevelLetNames parsedFields).find? (fun name => subtreeFields.contains name) with
    | some name => .error { message := letFieldShadowError name }
    | none => .ok ()

def parsedFieldsValue (parsedFields : List ParsedField) : Except ParseError Value := do
  let parts := splitParsedFields parsedFields
  -- A parsed struct is open by default (the eager eval arm honors `openness.isOpen`; a
  -- non-definition struct stays open). `structCompOpenness` records an explicit `...` as
  -- `defOpenViaTail`, else `regularOpen`, for `normalizeDefinitionValueWithFuel`, which derives a
  -- def body's openness via `closeDefBody` (a no-`...` body closes, a `...` body stays open). A
  -- regular no-`...` struct (open) and a def no-`...` body (closed) parse to the same `regularOpen`
  -- node and are told apart only at normalize, never at the shared eager arm.
  let hasTail := parts.tail.isSome
  let structCompOpenness : StructOpenness := if hasTail then .defOpenViaTail else .regularOpen
  -- The plain-field+pattern base arm, openness/tail matched to whether a `...` is present (SC-1d).
  -- With a `...`, build the OPEN-via-tail node carrying both the tail value and the patterns
  -- (`mkStruct` forces `closingPatterns = []` since open); without, the parser-default base.
  let baseValue :=
    match parts.tail with
    | some tail => mkStruct parts.fields .defOpenViaTail (some tail) parts.patterns
    | none => parsedFieldsBaseValue parts.fields parts.patterns
  let declared :=
    match parts.comprehensions with
    | [] => baseValue
    | comprehensions =>
        match parts.patterns with
        | [] => .structComp parts.fields comprehensions structCompOpenness
        | _ => .conj [baseValue, .structComp parts.fields comprehensions structCompOpenness]
  -- `baseValue`/`structCompOpenness` already encode the `...` tail (SC-1d): the plain-field+pattern
  -- arm via `mkStruct … .defOpenViaTail (some tail) patterns` (tail + patterns co-represented; open ⇒
  -- `closingPatterns = []`), the comprehension/embedding arm via `structCompOpenness = .defOpenViaTail`
  -- (kept ONE node so a force-spliced def's `Self.<field>` self-refs see the embed-contributed fields —
  -- the argocd `#ListenerSet` regression). `...` and pattern constraints are orthogonal axes on the
  -- unified `Value.struct`; `declared` carries the right openness/tail/patterns in every combination.
  -- No-shadow validation (cue load rule): a bare/hidden field may not reuse a name a `let`/alias
  -- binds in this scope or any nested scope. Quoted-accurate on the field side (parse-time
  -- `parsedFields`), so it flags exactly cue's rejections.
  checkLetFieldShadow parsedFields declared
  .ok declared

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
  | .struct fields openness tail ps cps =>
      .struct (⟨name, .letBinding, .thisStruct, false⟩ :: fields) openness tail ps cps
  | .structComp fields cs openness =>
      .structComp (⟨name, .letBinding, .thisStruct, false⟩ :: fields) cs openness
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

/-- The comparator-struct VALUES the `list` package exposes as predefined constants (not
    functions): `list.Ascending` (`{x, y, less: bool & x < y}`), `list.Descending` (`x > y`),
    and the bare `list.Comparer` (`less: bool`). They appear WITHOUT a call (`list.Sort(x,
    list.Ascending)`), so — unlike `pkg.fn(...)` — the parser cannot route them through
    `parseCall`. Emitted as the same inline AST a user would write (`{x: _, y: _, less: …}`),
    so resolution and `list.Sort`'s per-pair comparator evaluation treat them identically to a
    hand-written comparator. The `x`/`y` field references resolve to the struct's own slots via
    the normal scope pass (string `.ref`s, slot-bound by `Resolve`). -/
def stdlibPackageValue? (pkg label : String) : Option Value :=
  -- `T`/`x`/`y` are independent `number | string` slots (verified: `Ascending & {x:1}` narrows
  -- neither `T` nor `y`), matching cue's definition; the `number | string` bound also makes
  -- sorting incomparable element types an error, as cue does.
  let numberOrString : Value := .disj [(.regular, .kind .number), (.regular, .kind .string)]
  let comparator (less : Value) : Value :=
    mkStruct
      [⟨"T", .regular, numberOrString, false⟩, ⟨"x", .regular, numberOrString, false⟩,
       ⟨"y", .regular, numberOrString, false⟩, ⟨"less", .regular, less, false⟩]
      .regularOpen none []
  -- cue's `less` is `bool & x < y`; the `bool &` is dropped because `x < y` already yields a
  -- bool, and Kue's `meet (bool) (unresolved <)` eagerly bottoms (a pre-existing divergence,
  -- reproducible without `list`) which would corrupt the standalone-comparator display. The Sort
  -- path is unaffected either way: a concrete pair makes `x < y` evaluate to a bool directly.
  match pkg, label with
  | "list", "Ascending" => some (comparator (.binary .lt (.ref "x") (.ref "y")))
  | "list", "Descending" => some (comparator (.binary .gt (.ref "x") (.ref "y")))
  | "list", "Comparer" => some (comparator (.kind .bool))
  -- `list.UniqueItems` is used both bare and called (`list.UniqueItems()`); the bare form is a
  -- validator VALUE, resolved here (the called form routes through `parseCall` → `evalListBuiltin`).
  | "list", "UniqueItems" => some .uniqueItems
  -- The `path` package's three OS selector constants — plain string values (`path.OS` is NOT a
  -- real cue constant; the package exposes only these three).
  | "path", "Unix" => some (.prim (.string "unix"))
  | "path", "Windows" => some (.prim (.string "windows"))
  | "path", "Plan9" => some (.prim (.string "plan9"))
  -- `time` package (STDLIB-TIME). The `Time`/`Duration` validators are used BARE (no call),
  -- so they resolve to their `.stringFormat` validator VALUE here (the called forms route
  -- through `parseCall` → `evalTimeBuiltin`). The Duration UNIT constants (int nanoseconds)
  -- and the format-LAYOUT string constants are plain values.
  | "time", "Time" => some (.stringFormat .rfc3339)
  | "time", "Duration" => some (.stringFormat .duration)
  | "time", "Nanosecond" => some (.prim (.int 1))
  | "time", "Microsecond" => some (.prim (.int 1000))
  | "time", "Millisecond" => some (.prim (.int 1000000))
  | "time", "Second" => some (.prim (.int 1000000000))
  | "time", "Minute" => some (.prim (.int 60000000000))
  | "time", "Hour" => some (.prim (.int 3600000000000))
  | "time", "ANSIC" => some (.prim (.string "Mon Jan _2 15:04:05 2006"))
  | "time", "UnixDate" => some (.prim (.string "Mon Jan _2 15:04:05 MST 2006"))
  | "time", "RubyDate" => some (.prim (.string "Mon Jan 02 15:04:05 -0700 2006"))
  | "time", "RFC822" => some (.prim (.string "02 Jan 06 15:04 MST"))
  | "time", "RFC822Z" => some (.prim (.string "02 Jan 06 15:04 -0700"))
  | "time", "RFC850" => some (.prim (.string "Monday, 02-Jan-06 15:04:05 MST"))
  | "time", "RFC1123" => some (.prim (.string "Mon, 02 Jan 2006 15:04:05 MST"))
  | "time", "RFC1123Z" => some (.prim (.string "Mon, 02 Jan 2006 15:04:05 -0700"))
  | "time", "RFC3339" => some (.prim (.string "2006-01-02T15:04:05Z07:00"))
  | "time", "RFC3339Nano" => some (.prim (.string "2006-01-02T15:04:05.999999999Z07:00"))
  | "time", "Kitchen" => some (.prim (.string "3:04PM"))
  | "time", "January" => some (.prim (.int 1))
  | "time", "February" => some (.prim (.int 2))
  | "time", "March" => some (.prim (.int 3))
  | "time", "April" => some (.prim (.int 4))
  | "time", "May" => some (.prim (.int 5))
  | "time", "June" => some (.prim (.int 6))
  | "time", "July" => some (.prim (.int 7))
  | "time", "August" => some (.prim (.int 8))
  | "time", "September" => some (.prim (.int 9))
  | "time", "October" => some (.prim (.int 10))
  | "time", "November" => some (.prim (.int 11))
  | "time", "December" => some (.prim (.int 12))
  | "time", "Sunday" => some (.prim (.int 0))
  | "time", "Monday" => some (.prim (.int 1))
  | "time", "Tuesday" => some (.prim (.int 2))
  | "time", "Wednesday" => some (.prim (.int 3))
  | "time", "Thursday" => some (.prim (.int 4))
  | "time", "Friday" => some (.prim (.int 5))
  | "time", "Saturday" => some (.prim (.int 6))
  -- `net` package (STDLIB-NET). The IP validators are used BARE (no call), resolving to
  -- their `.stringFormat` validator VALUE here; the called forms route through `parseCall`
  -- → `evalNetBuiltin`. `IPv4len`/`IPv6len` are plain int constants. `FQDN` is DEFERRED (full
  -- idna engine), so it is NOT resolved bare — a bare `net.FQDN` falls through to the
  -- unresolved path, and any call routes to `evalNetBuiltin`'s `unsupportedBuiltin`.
  | "net", "IP" => some (.stringFormat .netIP)
  | "net", "IPv4" => some (.stringFormat .netIPv4)
  | "net", "IPv6" => some (.stringFormat .netIPv6)
  | "net", "IPCIDR" => some (.stringFormat .netIPCIDR)
  | "net", "LoopbackIP" => some (.stringFormat .netLoopbackIP)
  | "net", "MulticastIP" => some (.stringFormat .netMulticastIP)
  | "net", "InterfaceLocalMulticastIP" => some (.stringFormat .netInterfaceLocalMulticastIP)
  | "net", "LinkLocalMulticastIP" => some (.stringFormat .netLinkLocalMulticastIP)
  | "net", "LinkLocalUnicastIP" => some (.stringFormat .netLinkLocalUnicastIP)
  | "net", "GlobalUnicastIP" => some (.stringFormat .netGlobalUnicastIP)
  | "net", "UnspecifiedIP" => some (.stringFormat .netUnspecifiedIP)
  | "net", "IPv4len" => some (.prim (.int 4))
  | "net", "IPv6len" => some (.prim (.int 16))
  | _, _ => none

mutual
  partial def parseExpression (chars : List Char) : ParseResult Value :=
    parseDisjunction chars

  partial def parseDisjunction (chars : List Char) : ParseResult Value :=
    match parseMarkedConjunction chars with
    | .error error => .error error
    | .ok (first, rest) => parseDisjunctionRest (skipTrivia chars) [first] rest

  partial def parseDisjunctionRest
      (start : List Char)
      (alternatives : List (Mark × Value))
      (chars : List Char) : ParseResult Value :=
    match skipSameLineTrivia chars with
    | '|' :: rest =>
        match parseMarkedConjunction rest with
        | .error error => .error error
        | .ok (alternative, rest) => parseDisjunctionRest start (alternatives ++ [alternative]) rest
    | _ =>
        match alternatives with
        | [(.regular, value)] => parseOk value chars
        -- The `*` default mark is valid ONLY on a disjunct that has siblings (`*1 | 2`):
        -- the spec marks an ELEMENT OF a disjunction, so a sole marked operand (`*(1|2)`,
        -- `*1`) has no alternatives to prefer and `cue` rejects it at parse. A marked
        -- disjunct with ≥2 elements stays valid (caught by the `_` arm below). `start`
        -- anchors the diagnostic at the leading `*`.
        | [(.default, _)] => parseError start "preference mark not allowed at this position"
        | _ => parseOk (.disj alternatives) chars

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
    match skipSameLineTrivia chars with
    | '&' :: rest =>
        match parseLogicalOr rest with
        | .error error => .error error
        | .ok (constraint, rest) => parseConjunctionRest (constraints ++ [constraint]) rest
    | _ =>
        match constraints with
        | [value] => parseOk value chars
        | values => parseOk (.conj values) chars

  partial def parseLogicalOr (chars : List Char) : ParseResult Value :=
    match parseLogicalAnd chars with
    | .error error => .error error
    | .ok (first, rest) => parseLogicalOrRest first rest

  partial def parseLogicalOrRest (left : Value) (chars : List Char) : ParseResult Value :=
    match skipSameLineTrivia chars with
    | '|' :: '|' :: rest =>
        match parseLogicalAnd rest with
        | .error error => .error error
        | .ok (right, rest) => parseLogicalOrRest (.binary .boolOr left right) rest
    | _ => parseOk left chars

  partial def parseLogicalAnd (chars : List Char) : ParseResult Value :=
    match parseComparison chars with
    | .error error => .error error
    | .ok (first, rest) => parseLogicalAndRest first rest

  partial def parseLogicalAndRest (left : Value) (chars : List Char) : ParseResult Value :=
    match skipSameLineTrivia chars with
    | '&' :: '&' :: rest =>
        match parseComparison rest with
        | .error error => .error error
        | .ok (right, rest) => parseLogicalAndRest (.binary .boolAnd left right) rest
    | _ => parseOk left chars

  partial def parseComparison (chars : List Char) : ParseResult Value :=
    match parseAdditive chars with
    | .error error => .error error
    | .ok (left, rest) =>
        match skipSameLineTrivia rest with
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
        | _ => parseOk left rest

  partial def parseAdditive (chars : List Char) : ParseResult Value :=
    match parseMultiplicative chars with
    | .error error => .error error
    | .ok (first, rest) => parseAdditiveRest first rest

  partial def parseAdditiveRest (left : Value) (chars : List Char) : ParseResult Value :=
    match skipSameLineTrivia chars with
    | '+' :: rest =>
        match parseMultiplicative rest with
        | .error error => .error error
        | .ok (right, rest) => parseAdditiveRest (.binary .add left right) rest
    | '-' :: rest =>
        match parseMultiplicative rest with
        | .error error => .error error
        | .ok (right, rest) => parseAdditiveRest (.binary .sub left right) rest
    | _ => parseOk left chars

  partial def parseMultiplicative (chars : List Char) : ParseResult Value :=
    match parseUnary chars with
    | .error error => .error error
    | .ok (first, rest) => parseMultiplicativeRest first rest

  partial def parseMultiplicativeRest (left : Value) (chars : List Char) : ParseResult Value :=
    match skipSameLineTrivia chars with
    | '*' :: rest =>
        match parseUnary rest with
        | .error error => .error error
        | .ok (right, rest) => parseMultiplicativeRest (.binary .mul left right) rest
    -- `//` opens a line comment, not two divisions (CUE has no unary `/`), so it terminates
    -- the expression rather than reading as a `/` operator.
    | '/' :: '/' :: _ => parseOk left chars
    | '/' :: rest =>
        match parseUnary rest with
        | .error error => .error error
        | .ok (right, rest) => parseMultiplicativeRest (.binary .div left right) rest
    | scanned =>
        match parseMultiplicativeKeywordOp? scanned with
        | some (op, rest) =>
            match parseUnary rest with
            | .error error => .error error
            | .ok (right, rest) => parseMultiplicativeRest (.binary op left right) rest
        | none => parseOk left chars

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
    match skipSameLineTrivia chars with
    | '.' :: rest =>
        match parseLabel (skipTrivia rest) with
        | .error error => .error error
        | .ok (label, rest) =>
            match skipSameLineTrivia rest with
            | '(' :: rest =>
                -- Package-qualified call, e.g. `strings.ToUpper(x)`. Only a single
                -- `pkg.fn(...)` shape is a builtin; deeper selectors stay field access.
                match base with
                | .ref pkg =>
                    match parseCall s!"{pkg}.{label}" rest with
                    | .error error => .error error
                    | .ok (call, rest) => parseSelectorRest call rest
                | _ => parseSelectorRest (.selector base label) rest
            | rest =>
                -- A no-call selector. A `pkg.Constant` the stdlib exposes as a VALUE
                -- (`list.Ascending`/`Descending`/`Comparer`) is left as a deferred selector
                -- and resolved by the import-aware post-parse pass, which gates it on the
                -- package being imported (matching a call-form builtin); a non-stdlib
                -- selector stays ordinary field access there too.
                parseSelectorRest (.selector base label) rest
    | '[' :: rest =>
        -- `[e]` indexes; `[lo:hi]` slices. Slice bounds are optional: an omitted low is
        -- `0`, an omitted high is `len(base)`. Slicing desugars to `list.Slice`, which
        -- already carries cue's bounds/negative/incomplete semantics (list-only operand,
        -- oob/lo>hi/negative → bottom, incomplete bound → residual defer).
        match skipTrivia rest with
        | ':' :: afterColon => parseSliceRest base (.prim (.int 0)) afterColon
        | afterBracket =>
            match parseExpression afterBracket with
            | .error error => .error error
            | .ok (first, rest) =>
                match skipTrivia rest with
                | ':' :: afterColon => parseSliceRest base first afterColon
                | ']' :: rest => parseSelectorRest (.index base first) rest
                | rest => parseError rest "expected ']' or ':' after '['"
    | rest => parseOk base rest

  /-- Parse the tail of a slice `base[low : …]` after the low bound and `:` are consumed:
      an optional high bound (default `len(base)`) then `]`. Desugars to the core `slice`
      builtin — a language operator distinct from the public, import-gated `list.Slice`, so
      slicing never requires `import "list"`. -/
  partial def parseSliceRest (base low : Value) (chars : List Char) : ParseResult Value :=
    match skipTrivia chars with
    | ']' :: rest =>
        parseSelectorRest
          (.builtinCall "slice" [base, low, .builtinCall "len" [base]]) rest
    | afterColon =>
        match parseExpression afterColon with
        | .error error => .error error
        | .ok (high, rest) =>
            match skipTrivia rest with
            | ']' :: rest =>
                parseSelectorRest (.builtinCall "slice" [base, low, high]) rest
            | rest => parseError rest "expected ']' after slice bounds"

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
    | '\\' :: rest =>
        match decodeStringEscape rest with
        | some (decoded, rest) => parseInterpolatedString rest (decoded :: acc) parts
        | none =>
            match rest with
            | [] => parseError [] "unterminated string escape"
            | _ => parseError rest "invalid escape sequence in string literal"
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
      | '\\' :: rest =>
          match decodeStringEscape rest with
          | some (decoded, rest) => parseMultilineBody quote strip false rest (decoded :: acc) parts
          | none =>
              match rest with
              | [] => parseError [] "unterminated string escape"
              | _ => parseError rest "invalid escape sequence in string literal"
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

  /-- Parse the content of a multiline byte literal (`'''…'''`) after the opening line's
      newline. Mirrors `parseMultilineBody`'s indentation-stripping and closing-line
      handling, but accumulates RAW bytes and decodes byte escapes (`\xNN`/`\NNN`/`\uNNNN`)
      via `decodeByteEscape` — so a high byte survives as one octet — rather than routing
      through the string escape lexer. Interpolation is rejected (byte-context interpolation
      is unimplemented). `strip` is the closing line's indentation, dropped from every line. -/
  partial def parseMultilineByteBody
      (strip : List Char) (atLineStart : Bool)
      (chars : List Char) (acc : List UInt8) : ParseResult (Array UInt8) :=
    if atLineStart then
      match dropPrefix? strip chars with
      | some afterStrip =>
          match multilineDelimiter? '\'' afterStrip with
          | some rest =>
              -- Drop the newline separating the last content line from the closing line.
              let trimmed := match acc with
                | byte :: rest => if byte == 0x0a then rest else byte :: rest
                | acc => acc
              parseOk trimmed.reverse.toArray rest
          | none => parseMultilineByteBody strip false afterStrip acc
      | none =>
          match chars with
          | '\n' :: rest => parseMultilineByteBody strip true rest (0x0a :: acc)
          | [] => parseError [] "unterminated multiline literal"
          | _ => parseError chars "invalid whitespace in multiline literal"
    else
      match chars with
      | [] => parseError [] "unterminated multiline literal"
      | '\n' :: rest => parseMultilineByteBody strip true rest (0x0a :: acc)
      | '\\' :: '(' :: _ =>
          parseError chars "interpolation in multiline bytes is not supported yet"
      | '\\' :: rest =>
          match decodeByteEscape rest with
          | some (decoded, rest) => parseMultilineByteBody strip false rest (decoded.reverse ++ acc)
          | none =>
              match rest with
              | escaped :: rest =>
                  parseMultilineByteBody strip false rest ((charBytes escaped).reverse ++ acc)
              | [] => parseError [] "unterminated byte escape"
      | value :: rest => parseMultilineByteBody strip false rest ((charBytes value).reverse ++ acc)

  partial def parseMultilineBytes (chars : List Char) : ParseResult Value :=
    match multilineStripPrefix? '\'' chars with
    | none => parseError chars "unterminated multiline literal"
    | some strip =>
        let afterWs := (splitLeadingHorizontalWhitespace chars).snd
        match afterWs with
        | '\n' :: rest =>
            match parseMultilineByteBody strip true rest [] with
            | .error error => .error error
            | .ok (bytes, rest) => parseOk (.prim (.bytes bytes)) rest
        | _ => parseError chars "expected newline after multiline quote"

  partial def parseIdentifierValue (chars : List Char) : ParseResult Value :=
    match parseIdentifier chars with
    | .error error => .error error
    | .ok (name, rest) =>
        match skipSameLineTrivia rest with
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
            let itemResult :=
              if startsWithWord "for" trimmed || startsWithWord "if" trimmed then
                parseListComprehension trimmed
              else
                parseExpression trimmed
            match itemResult with
            | .error error => .error error
            | .ok (item, rest) =>
                -- Elements are separated by the SAME rule as struct declarations: an explicit
                -- `,`/`;` or a newline (auto-inserted comma). `fieldSeparator` reports whether
                -- one was crossed; without a separator, adjacent same-line elements are a
                -- missing-comma error rather than being silently concatenated.
                let (sawSeparator, next) := fieldSeparator rest
                if parseFieldTerminator (some ']') next || sawSeparator then
                  parseListItems next (items ++ [item])
                else
                  parseError next "missing ',' in list literal"

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
    | .ok (fields, rest) =>
        match parsedFieldsValue fields with
        | .error error => .error error
        | .ok value => parseOk value rest

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
          let (sawSeparator, next) := fieldSeparator rest
          if parseFieldTerminator terminator next || sawSeparator then
            parseFieldsUntil terminator next (fields ++ [field])
          else
            parseError next "missing ',' in struct literal"

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

  /-- A `let <ident> = <expr>` comprehension clause (`LetClause = "let" identifier "="
      Expression`). Same surface as a struct-body `let` (`parseLetBinding`), but yields a
      `Clause.letClause` rather than a field. Reached only from `parseClause` inside a clause
      chain — a `let` at struct-field head still parses as a struct-body let, since the spec's
      `StartClause` excludes `let` (a comprehension cannot start with `let`). -/
  partial def parseLetClause (chars : List Char) : ParseResult (Clause Value) :=
    match dropWord? "let" (skipTrivia chars) with
    | none => parseError (skipTrivia chars) "expected let clause"
    | some rest =>
        match parseIdentifier (skipTrivia rest) with
        | .error error => .error error
        | .ok (name, rest) =>
            match skipTrivia rest with
            | '=' :: rest =>
                match parseExpression rest with
                | .error error => .error error
                | .ok (value, rest) => parseOk (.letClause name value) rest
            | rest => parseError rest "expected '=' in let clause"

  partial def parseClause (chars : List Char) : ParseResult (Clause Value) :=
    match parseForClause chars with
    | .ok parsed => .ok parsed
    | .error _ =>
        match parseIfClause chars with
        | .ok parsed => .ok parsed
        | .error _ => parseLetClause chars

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
        | .ok (inner, rest) =>
            match parsedFieldsValue [inner] with
            | .error error => .error error
            | .ok value => parseOk value rest
      else
        parseExpression chars

  partial def parseLabeledField (label : String) (rest : List Char) : ParseResult ParsedField :=
    let (fieldClass, rest) := parseFieldClass label rest
    match skipTrivia rest with
    | ':' :: rest =>
        match parseFieldValue rest with
        | .error error => .error error
        | .ok (value, rest) => parseOk (.field ⟨label, fieldClass, value, false⟩ false) rest
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
                    | .ok (value, rest) => parseOk (.fieldAlias alias ⟨label, fieldClass, value, false⟩) rest
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
                    | .prim (.string label) => parseOk (.field ⟨label, fieldClass, value, true⟩ true) rest
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

/-- Structural-recursion guard for the post-parse builtin-alias rewrite. A parsed body's
    nesting depth is bounded by the source size and never approaches this; it only makes the
    rewrite total without `partial`. -/
def builtinAliasFuel : Nat := 1000

/-- The local head a builtin import binds under (alias > `:identifier` qualifier >
    last-path-element), paired with its CANONICAL family name (always the last path element).
    The parser lowers `pkg.fn(...)` to `.builtinCall "pkg.fn"` off the LITERAL head it reads,
    so an aliased builtin (`import j "encoding/json"` ⇒ `j.Marshal` ⇒ `.builtinCall
    "j.Marshal"`) carries the alias, which `BuiltinFamily.ofName?` cannot classify. This pairs
    the as-written head with the canonical name so a post-parse pass can rewrite the call head
    back to the dispatchable form. -/
def builtinImportLocalNames : List Import -> List (String × String)
  | [] => []
  | imp :: rest =>
      let canonical := lastPathElement imp.path
      let asWritten :=
        match imp.alias with
        | some alias => alias
        | none => imp.packageName.getD canonical
      let here :=
        -- Only a BUILTIN path is dispatchable; a user import aliased to the same shape
        -- (`import f "ex.com/foo"; f.Bar`) must NOT be rewritten to a builtin. And a head
        -- already equal to its canonical name (the unaliased `import "encoding/json"`) needs
        -- no entry — it dispatches correctly as written.
        if isBuiltinImport imp.path && asWritten != canonical then [(asWritten, canonical)]
        else []
      here ++ builtinImportLocalNames rest

/-- Rewrite the head of a `pkg.fn` builtin-call name from a local alias to its canonical
    package name, leaving the leaf and any non-matching name untouched. `j.Marshal` with the
    map `[("j", "json")]` becomes `json.Marshal`; an unmapped head or a name with no `.` is
    returned verbatim. -/
def canonicalizeBuiltinCallName (aliasMap : List (String × String)) (name : String) : String :=
  match name.splitOn "." with
  | head :: leaf :: more =>
      match aliasMap.lookup head with
      | some canonical => String.intercalate "." (canonical :: leaf :: more)
      | none => name
  | _ => name

/-- Resolve/gate a no-call selector on a package head against the file's imports. When
    `(head, label)` names a stdlib CONSTANT (`list.Ascending`/`Descending`/`Comparer` —
    resolved via `stdlibPackageValue?` off the alias-canonical package), it yields that value
    ONLY if the package is imported (`aliasMap` covers aliased builtin imports, `importedPkgs`
    the canonical set); an un-imported reference is `reference "<head>" not found` (bottom),
    matching cue. A selector on a non-stdlib head is `none` — ordinary field access, untouched. -/
def resolveBuiltinConstSelector (aliasMap : List (String × String))
    (importedPkgs : List String) (head label : String) : Option Value :=
  let canonicalPkg := (aliasMap.lookup head).getD head
  match stdlibPackageValue? canonicalPkg label with
  | some value =>
      if importedPkgs.contains canonicalPkg then some value
      else some (.bottomWith [.unresolvedReference head])
  | none => none

/-- Gate an (already alias-canonicalized) `.builtinCall` head on its package being imported. A
    qualified head whose package is a builtin stdlib package (`strings.ToUpper`, `list.Slice`)
    requires that package in scope; an un-imported one is `reference "<pkg>" not found`
    (bottom), matching cue. Core builtins (`len`, the `slice` desugar — no package prefix) and
    non-builtin names are never gated. -/
def gateBuiltinImport (importedPkgs : List String) (name : String) (args : List Value) :
    Value :=
  match name.splitOn "." with
  | pkg :: _ :: _ =>
      if builtinPackageNames.contains pkg && !importedPkgs.contains pkg then
        .bottomWith [.unresolvedReference pkg]
      else .builtinCall name args
  | _ => .builtinCall name args

/-- Total structural rewrite that both canonicalizes aliased builtin heads to their dispatch
    form (`j.Marshal` → `json.Marshal`) and ENFORCES cue's import requirement: a qualified
    builtin reference (call `strings.ToUpper` or constant `list.Ascending`) resolves only when
    its package is imported (`importedPkgs`), otherwise it becomes `reference "<pkg>" not found`
    (bottom). A no-call `.selector` on a stdlib CONSTANT is resolved here (the parser defers it);
    every other node is rebuilt unchanged. Recursion is structural with `fuel` as a guard,
    matching the resolve/remap passes; the parsed forms never approach the bound. -/
def canonicalizeBuiltinCalls (aliasMap : List (String × String))
    (importedPkgs : List String) : Nat -> Value -> Value
  | 0, value => value
  | fuel + 1, value =>
      let rec' := canonicalizeBuiltinCalls aliasMap importedPkgs fuel
      match value with
      | .builtinCall name args =>
          gateBuiltinImport importedPkgs (canonicalizeBuiltinCallName aliasMap name) (args.map rec')
      | .conj constraints => .conj (constraints.map rec')
      | .unary op operand => .unary op (rec' operand)
      | .binary op left right => .binary op (rec' left) (rec' right)
      | .selector base label =>
          -- A stdlib CONSTANT (`list.Ascending`, aliased or not) survives parse as a deferred
          -- selector; resolve it here, gated on the package being imported. Otherwise fall
          -- through to ordinary field-access recursion (a user import's `f.Bar` → untouched).
          match base with
          | .ref head =>
              match resolveBuiltinConstSelector aliasMap importedPkgs head label with
              | some value => value
              | none => .selector (rec' base) label
          | _ => .selector (rec' base) label
      | .index base key => .index (rec' base) (rec' key)
      | .disj alternatives => .disj (alternatives.map (fun a => (a.fst, rec' a.snd)))
      | .struct fields openness tail patterns closedClauses =>
          .struct
            (fields.map (fun f => { f with value := rec' f.value }))
            openness
            (tail.map rec')
            (patterns.map (fun p => (rec' p.fst, rec' p.snd)))
            (closedClauses.map (ClosedClause.mapPatterns rec'))
      | .structComp fields comprehensions openness =>
          .structComp
            (fields.map (fun f => { f with value := rec' f.value }))
            (comprehensions.map rec')
            openness
      | .list items => .list (items.map rec')
      | .listTail items tail => .listTail (items.map rec') (rec' tail)
      | .embeddedList items tail decls =>
          .embeddedList
            (items.map rec')
            (tail.map rec')
            (decls.map (fun f => { f with value := rec' f.value }))
      | .embeddedScalar scalar decls =>
          .embeddedScalar
            (rec' scalar)
            (decls.map (fun f => { f with value := rec' f.value }))
      | .comprehension clauses body =>
          .comprehension
            (clauses.map (canonicalizeBuiltinClause aliasMap importedPkgs fuel)) (rec' body)
      | .listComprehension clauses body =>
          .listComprehension
            (clauses.map (canonicalizeBuiltinClause aliasMap importedPkgs fuel)) (rec' body)
      | .interpolation parts => .interpolation (parts.map rec')
      | .dynamicField label fieldClass value =>
          .dynamicField (rec' label) fieldClass (rec' value)
      | .closure capturedEnv body => .closure capturedEnv (rec' body)
      -- Leaves carry no nested `Value`, so the rewrite is the identity on them. Enumerated
      -- (not `_ => value`) so a NEW recursive `Value` constructor fails to compile here until
      -- its child-recursion arm is written, rather than being silently passed through.
      | .top => value
      | .bottom => value
      | .bottomWith _ => value
      | .prim _ => value
      | .kind _ => value
      | .notPrim _ => value
      | .stringRegex _ => value
      | .stringFormat _ => value
      | .boundConstraint _ _ _ => value
      | .lengthConstraint _ _ _ => value
      | .uniqueItems => value
      | .ref _ => value
      | .refId _ => value
      | .thisStruct => value
  where
    canonicalizeBuiltinClause (aliasMap : List (String × String))
        (importedPkgs : List String) (fuel : Nat) :
        Clause Value -> Clause Value
      | .forIn key value source =>
          .forIn key value (canonicalizeBuiltinCalls aliasMap importedPkgs fuel source)
      | .guard condition => .guard (canonicalizeBuiltinCalls aliasMap importedPkgs fuel condition)
      | .letClause name value =>
          .letClause name (canonicalizeBuiltinCalls aliasMap importedPkgs fuel value)

/-- The canonical package names (`encoding/json` → `json`) of the builtin stdlib packages a
    file imports — the set the import gate accepts a qualified builtin reference against. -/
def importedBuiltinPackages (imports : List Import) : List String :=
  imports.filterMap (fun imp =>
    if isBuiltinImport imp.path then some (lastPathElement imp.path) else none)

/-- Canonicalize aliased builtin heads AND enforce cue's import requirement against a parsed
    body: a qualified builtin reference resolves only when its package is imported, else it is
    `reference "<pkg>" not found` (bottom). Always walks (an un-imported builtin must be caught
    even with no aliases present), so it is not gated on the alias map being non-empty. -/
def applyBuiltinAliases (imports : List Import) (value : Value) : Value :=
  canonicalizeBuiltinCalls (builtinImportLocalNames imports)
    (importedBuiltinPackages imports) builtinAliasFuel value

/-- Every local identifier the parsed body references as a package head: the label of each
    `.ref` node (a selector base `pkg.field` parses as `.selector (.ref "pkg") …`, and a deferred
    stdlib constant as `.selector (.ref "pkg") "Const"`, so both surface here) plus the head
    segment of each `.builtinCall` name (`strings.ToUpper` → `strings`; an aliased `j.Marshal`
    → `j`, read off the AS-WRITTEN head BEFORE canonicalization rewrites it). This is the "used"
    set the unused-import check tests each import's local bind name against. Enumerated
    exhaustively (no catch-all) so a new recursive `Value` constructor forces an arm here — an
    import used only through an unhandled node would otherwise be mis-flagged unused. -/
def collectReferencedHeads : Nat -> Value -> List String
  | 0, _ => []
  | fuel + 1, value =>
    let rec' := collectReferencedHeads fuel
    match value with
    | .ref label => [label]
    | .builtinCall name args => (name.splitOn ".").headD "" :: args.flatMap rec'
    | .conj constraints => constraints.flatMap rec'
    | .unary _ operand => rec' operand
    | .binary _ left right => rec' left ++ rec' right
    | .selector base _ => rec' base
    | .index base key => rec' base ++ rec' key
    | .disj alternatives => alternatives.flatMap (fun a => rec' a.snd)
    | .struct fields _ tail patterns closedClauses =>
        fields.flatMap (fun f => rec' f.value)
          ++ (tail.map rec').getD []
          ++ patterns.flatMap (fun p => rec' p.fst ++ rec' p.snd)
          ++ closedClauses.flatMap (fun c => c.patterns.flatMap rec')
    | .structComp fields comprehensions _ =>
        fields.flatMap (fun f => rec' f.value) ++ comprehensions.flatMap rec'
    | .list items => items.flatMap rec'
    | .listTail items tail => items.flatMap rec' ++ rec' tail
    | .embeddedList items tail decls =>
        items.flatMap rec' ++ (tail.map rec').getD [] ++ decls.flatMap (fun f => rec' f.value)
    | .embeddedScalar scalar decls => rec' scalar ++ decls.flatMap (fun f => rec' f.value)
    | .comprehension clauses body =>
        clauses.flatMap (collectReferencedHeadsClause fuel) ++ rec' body
    | .listComprehension clauses body =>
        clauses.flatMap (collectReferencedHeadsClause fuel) ++ rec' body
    | .interpolation parts => parts.flatMap rec'
    | .dynamicField label _ value => rec' label ++ rec' value
    | .closure _ body => rec' body
    | .top => []
    | .bottom => []
    | .bottomWith _ => []
    | .prim _ => []
    | .kind _ => []
    | .notPrim _ => []
    | .stringRegex _ => []
    | .stringFormat _ => []
    | .boundConstraint _ _ _ => []
    | .lengthConstraint _ _ _ => []
    | .uniqueItems => []
    | .refId _ => []
    | .thisStruct => []
  where
    collectReferencedHeadsClause (fuel : Nat) : Clause Value -> List String
      | .forIn _ _ source => collectReferencedHeads fuel source
      | .guard condition => collectReferencedHeads fuel condition
      | .letClause _ value => collectReferencedHeads fuel value

/-- The imports a file declares but never references — cue's `imported and not used` set. An
    import counts as USED when its local bind name (`importBindName`) appears among
    `collectReferencedHeads` of the parsed body (a `pkg.field` selector, an aliased `p.Fn`
    builtin call, or a bare `pkg` ref). The bind name is fully lexical: the loader's bare-import
    package-name gate guarantees a bare import's declared name equals its last path element, so
    the parse-time name matches the loader's binder exactly. Detection only ever UNDER-reports
    (a body reference we don't model leaves the import counted as used), never over-reports, so a
    genuinely-used import is never mis-flagged. -/
def unusedImports (imports : List Import) (value : Value) : List Import :=
  let used := collectReferencedHeads builtinAliasFuel value
  imports.filter (fun imp => !used.contains (importBindName imp))

/-- Enforce cue's import requirements on a parsed body: FIRST reject any imported-but-unused
    package (`imported and not used` — a whole-file build error, so the document collapses to a
    bottom carrying one reason per unused import), otherwise canonicalize aliased builtin heads
    and gate un-imported builtin USES via `applyBuiltinAliases`. The two checks are the mirrored
    halves of cue's import contract (declared ⇒ used, used ⇒ declared). -/
def resolveImports (imports : List Import) (value : Value) : Value :=
  match unusedImports imports value with
  | [] => applyBuiltinAliases imports value
  | unused => .bottomWith (unused.map (fun imp => .importedNotUsed imp.path imp.alias))

def parseDocument (chars : List Char) : Except ParseError Value :=
  let afterPackage := consumePackageClauses chars
  match parseImportClauses [] afterPackage with
  | .error error => .error error
  | .ok (imports, afterImports) =>
      match parseFieldsUntil none afterImports [] with
      | .error error => .error error
      | .ok (fields, rest) =>
          match skipTrivia rest with
          | [] =>
              match parsedFieldsValue fields with
              | .error error => .error error
              | .ok value =>
                  .ok (resolveImports imports value)
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
          let value ← parsedFieldsValue fields
          pure { value := resolveImports imports value,
                 packageName := packageName, imports := imports,
                 topLevelFieldNames := bareIdentifierLabels fields }
      | rest => parseError rest "unexpected trailing input"

def parseSourceFile (source : String) : Except ParseError ParsedFile :=
  withPosition source.toList (parseDocumentFile source.toList)

end Kue
