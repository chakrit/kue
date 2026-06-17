import Kue.Json

namespace Kue

/-! # YAML serializer over `ManifestValue`

A total `manifestToYaml : ManifestValue → String` matching `cue export --out yaml`
(go-yaml v3 emitter) byte-for-byte on the infra-relevant core: 2-space block
indentation, `- ` sequence items, the scalar quoting rules `cue` actually emits, and
`|-` block scalars for strings containing newlines. Exotic go-yaml features (flow
style, anchors/aliases, complex keys, line-folding/wrapping, sexagesimal) are out of
scope — see `docs/spec/compat-assumptions.md`. -/

/-- Whether `c` is an ASCII decimal digit. -/
def yamlIsDigit (c : Char) : Bool := '0' ≤ c && c ≤ '9'

/-- Lowercase a single ASCII letter; pass everything else through. Used only for
    the case-insensitive YAML 1.1 null/bool token test. -/
def yamlAsciiLower (c : Char) : Char :=
  if 'A' ≤ c && c ≤ 'Z' then Char.ofNat (c.toNat + 32) else c

def yamlLowerString (s : String) : String :=
  String.ofList (s.toList.map yamlAsciiLower)

/-- The case-insensitive YAML 1.1 plain scalars that resolve to a bool or null and so
    must be quoted to stay a string. Matches the tokens go-yaml's resolver recognizes
    (`y/n/yes/no/true/false/on/off` for bool, `null/~` for null). -/
def yamlReservedWords : List String :=
  ["y", "n", "yes", "no", "true", "false", "on", "off", "t", "f", "null", "~", ""]

/-- Whether the whole string parses as a YAML 1.1 number that go-yaml would resolve to
    int/float — so the plain form would not round-trip as a string. Covers decimal
    ints (with `_` separators and sign), binary/octal/hex literals, and floats
    (`.`/`e` forms, `.inf`/`.nan`). Deliberately broad: a false positive only adds
    quotes, never corrupts. -/
def yamlLooksNumeric (s : String) : Bool := Id.run do
  if s.isEmpty then return false
  let cs := s.toList
  -- strip a leading sign
  let body := match cs with
    | '+' :: rest => rest
    | '-' :: rest => rest
    | _ => cs
  if body.isEmpty then return false
  let lower := yamlLowerString (String.ofList body)
  -- special floats
  if lower == ".inf" || lower == ".nan" then return true
  -- binary/octal/hex literals
  if String.ofList body |>.startsWith "0b" then return true
  if String.ofList body |>.startsWith "0o" then return true
  if String.ofList body |>.startsWith "0x" then return true
  -- decimal int or float: digits, with optional single '.', '_' separators, and an
  -- optional 'e'/'E' exponent. Require at least one digit, and only the allowed chars.
  let mut sawDigit := false
  for c in body do
    if yamlIsDigit c then sawDigit := true
    else if c == '.' || c == '_' || c == 'e' || c == 'E' || c == '+' || c == '-' then
      pure ()
    else
      return false
  return sawDigit

/-- A leading character that makes a plain scalar structurally ambiguous in YAML and
    so forces quoting (the YAML indicator set, minus `-`/`?`/`:` which are only
    special when followed by space — handled separately). -/
def yamlLeadingIndicator (c : Char) : Bool :=
  c == ',' || c == '[' || c == ']' || c == '{' || c == '}' ||
  c == '#' || c == '&' || c == '*' || c == '!' || c == '|' ||
  c == '>' || c == '\'' || c == '"' || c == '%' || c == '@' || c == '`'

/-- Whether the string contains a control character (< 0x20) that go-yaml renders with
    a double-quoted escape (`\n` is handled separately as a block scalar). -/
def yamlHasControl (s : String) : Bool :=
  s.toList.any fun c => c.toNat < 0x20

/-- Whether a plain (bare) scalar would be unsafe and so needs single-quoting, given it
    is neither resolver-ambiguous nor escape-requiring. Mirrors go-yaml: leading/trailing
    space, a leading indicator, a leading `-`/`?`/`:` followed by space (or alone), a
    `: ` (colon-space) anywhere, a ` #` (space-hash) anywhere, or a trailing `:`. -/
def yamlNeedsSingleQuote (s : String) : Bool := Id.run do
  let cs := s.toList
  match cs with
  | [] => return true
  | first :: _ =>
    if first == ' ' then return true
    if yamlLeadingIndicator first then return true
    -- leading '-'/'?'/':' is only special when at line start followed by space or alone
    if first == '-' || first == '?' || first == ':' then
      match cs with
      | _ :: ' ' :: _ => return true
      | [_] => return true
      | _ => pure ()
    -- trailing space
    if (cs.getLast? == some ' ') then return true
    -- trailing ':'
    if (cs.getLast? == some ':') then return true
    -- ": " or " #" anywhere
    let rec scan : List Char → Bool
      | a :: b :: rest =>
          if (a == ':' && b == ' ') || (a == ' ' && b == '#') then true
          else scan (b :: rest)
      | _ => false
    return scan cs

/-- A double-quoted YAML scalar, reusing the JSON string escaper (go-yaml's double-quote
    escaping coincides with JSON for the control/quote/backslash set; non-ASCII passes
    through, matching `cue`). -/
def yamlDoubleQuoted (s : String) : String := jsonString s

/-- A single-quoted YAML scalar: wrap in `'…'`, doubling each interior `'`. -/
def yamlSingleQuoted (s : String) : String :=
  let body := s.toList.foldl (fun acc c => if c == '\'' then acc ++ "''" else acc.push c) ""
  "'" ++ body ++ "'"

/-- Render a string as a YAML flow scalar (no newline). Picks bare / single-quoted /
    double-quoted exactly as `cue`'s go-yaml emitter does for the cases Kue supports. -/
def yamlScalarString (s : String) : String :=
  if yamlHasControl s then
    yamlDoubleQuoted s
  else if yamlReservedWords.contains (yamlLowerString s) || yamlLooksNumeric s then
    yamlDoubleQuoted s
  else if yamlNeedsSingleQuote s then
    yamlSingleQuoted s
  else
    s

/-- Render a manifested primitive as a single-line YAML scalar (no trailing newline).
    Strings with a `\n` are NOT handled here — the caller routes those to a block
    scalar. Numbers/bool/null render bare; bytes are base64 (as JSON does). -/
def yamlScalarPrim : Prim -> String
  | .null => "null"
  | .bool true => "true"
  | .bool false => "false"
  | .int value => toString value
  | .float value => value
  | .string value => yamlScalarString value
  | .bytes value => yamlScalarString (base64Encode value.toUTF8.toList)

/-- A YAML key. A plain-safe key is bare; otherwise it follows the same quoting rule as
    a string value (e.g. `f`, `n`, `y`, `true`, numeric-looking, special chars). -/
def yamlKey (key : String) : String := yamlScalarString key

/-- Indentation prefix of `n` spaces. -/
def yamlIndent (n : Nat) : String := String.ofList (List.replicate n ' ')

/-- Whether a manifest value is a "scalar" for layout purposes: a primitive that is NOT
    a multiline string (multiline strings render as block scalars, which are not inline).
    Empty struct/list also render inline (`{}` / `[]`). -/
def yamlIsInlineEmpty : ManifestValue -> Bool
  | .struct [] => true
  | .list [] => true
  | _ => false

/-- The line(s) of a block scalar `|-` for a string containing newlines: each source
    line is indented by `indent`, and `|-` strips the trailing newline (chomp). Matches
    `cue` (`|-` style; no final blank line). -/
def yamlBlockScalar (indent : Nat) (s : String) : String :=
  let lines := s.splitOn "\n"
  let pad := yamlIndent indent
  let body := joinWith "\n" (lines.map fun line =>
    if line.isEmpty then "" else pad ++ line)
  "|-\n" ++ body

mutual
  /-- Serialize a manifested value at block `indent`, as the value following a `key:` or
      `- ` introducer. A scalar/empty/inline value is returned on the same logical line;
      a non-empty struct or list returns a leading newline then its indented block. The
      caller is responsible for emitting the introducer (`key:` or `-`). -/
  def yamlValue (indent : Nat) : ManifestValue -> String
    | .prim (.string s) =>
        if s.contains '\n' then " " ++ yamlBlockScalar (indent + 2) s
        else " " ++ yamlScalarPrim (.string s)
    | .prim p => " " ++ yamlScalarPrim p
    | .struct [] => " {}"
    | .list [] => " []"
    | .struct fields => "\n" ++ yamlFields (indent + 2) fields
    | .list items => "\n" ++ yamlItems (indent + 2) items

  /-- A block mapping: one `key:<value>` line per field at `indent`. -/
  def yamlFields (indent : Nat) : List (String × ManifestValue) -> String
    | [] => ""
    | [field] => yamlIndent indent ++ yamlKey field.fst ++ ":" ++ yamlValue indent field.snd
    | field :: rest =>
        yamlIndent indent ++ yamlKey field.fst ++ ":" ++ yamlValue indent field.snd
          ++ "\n" ++ yamlFields indent rest

  /-- A block sequence: one `- <item>` line per item at `indent`. A compound item's body
      indents two further spaces and the first line rides the `- ` introducer, so the
      leading newline `yamlValue` emits is dropped and the first body line is spliced in. -/
  def yamlItems (indent : Nat) : List ManifestValue -> String
    | [] => ""
    | [item] => yamlIndent indent ++ "-" ++ yamlItemBody indent item
    | item :: rest =>
        yamlIndent indent ++ "-" ++ yamlItemBody indent item
          ++ "\n" ++ yamlItems indent rest

  /-- The part of a sequence item after the `-` introducer. For scalars/empties it is a
      space then the inline value. For a non-empty struct/list, the block is rendered at
      `indent + 2` and its first line is placed right after `- ` (so the `-` and the first
      key share a line), with subsequent lines already correctly indented. -/
  def yamlItemBody (indent : Nat) : ManifestValue -> String
    | .prim (.string s) =>
        if s.contains '\n' then " " ++ yamlBlockScalar (indent + 4) s
        else " " ++ yamlScalarPrim (.string s)
    | .prim p => " " ++ yamlScalarPrim p
    | .struct [] => " {}"
    | .list [] => " []"
    | .struct fields =>
        let block := yamlFields (indent + 2) fields
        " " ++ (block.drop (indent + 2))
    | .list items =>
        let block := yamlItems (indent + 2) items
        " " ++ (block.drop (indent + 2))
end

/-- Serialize a manifested value to a full YAML document (no trailing newline). A
    top-level struct emits its fields at indent 0; a top-level list emits a block
    sequence; a top-level scalar emits the bare scalar. Matches `cue export --out yaml`
    (single document; top-level lists are a YAML sequence, NOT a `---` stream). -/
def manifestToYaml : ManifestValue -> String
  | .prim (.string s) =>
      if s.contains '\n' then yamlBlockScalar 0 s else yamlScalarPrim (.string s)
  | .prim p => yamlScalarPrim p
  | .struct [] => "{}"
  | .list [] => "[]"
  | .struct fields => yamlFields 0 fields
  | .list items => yamlItems 0 items

/-- Manifest `value` then serialize to a YAML document **with a trailing newline**, the
    form `cue`'s `yaml.Marshal` builtin and `cue export --out yaml` both emit. -/
def valueToYaml (value : Value) : Except ManifestError String :=
  (manifest value).map (fun mv => manifestToYaml mv ++ "\n")

end Kue
