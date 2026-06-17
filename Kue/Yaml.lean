import Kue.Json
import Kue.Base64

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

/-! ## Would a bare scalar parse as a non-string?

The decision "must this string be quoted to survive as a string" is the **union of two
layers** `cue export --out yaml` actually composes, both verified against `cue` v0.16.1:

1. **cue's `shouldQuote`** (`internal/encoding/yaml/encode.go`): forces double-quote when
   the string is in a fixed YAML-1.1 legacy-token set, or matches a conservative
   date/time/base60/`0x`-hex regex. This catches loosely-shaped tokens go-yaml's resolver
   would *not* — e.g. `2024-13-40` (an out-of-range "date") is quoted purely by the regex.
2. **go-yaml v3's emitter** (`encode.go` `stringv`): when cue leaves the style unset, the
   emitter still quotes anything its resolver reads back as a non-string — a real
   int/float (decimal, `0b`/`0o`/`0x`), the bool/null token map, or YAML-1.1 old bools
   (`yes/no/on/off`) and base60 floats.

A multi-segment token (`34.142.159.249`, `1.2.3`, `10.0.0.0/8`, `nginx:1.25`) is none of
these — not a number, not a date (no all-`[-+0-9:. \t]` body with a separator), not a
token — so it stays **bare**, matching `cue`. This replaces the old over-broad
"any digit-dot-underscore run is numeric" check, which wrongly quoted IPs/versions/CIDRs. -/

/-- YAML-1.1 plain scalars that resolve to a bool or null (go-yaml's `resolveMap`) or that
    cue's `legacyStrings` force-quotes for 1.1 backward-compat, **plus** go-yaml's
    `isOldBool` set. Union of all three: any of these, bare, would read back as something
    other than the string — so quote. `""` is here (resolves to null) and as the empty
    structurally-unsafe case. -/
def yamlReservedWords : List String :=
  [ -- bool / null token map (with go-yaml's case variants)
    "true", "True", "TRUE", "false", "False", "FALSE",
    "", "~", "null", "Null", "NULL",
    ".nan", ".NaN", ".NAN", ".Nan",
    ".inf", ".Inf", ".INF", "+.inf", "+.Inf", "+.INF", "-.inf", "-.Inf", "-.INF",
    -- YAML 1.1 old bools (go-yaml `isOldBool` + cue `legacyStrings`)
    "y", "Y", "yes", "Yes", "YES", "n", "N", "no", "No", "NO",
    "on", "On", "ON", "off", "Off", "OFF",
    -- cue `legacyStrings` extras
    "t", "T", "f", "F" ]

/-- The cue-quote character class `[-+0-9:. \t]`: the only chars cue's date/time/base60
    regex admits outside the `t/T` separator and trailing `z/Z`. -/
def yamlCueDateChar (c : Char) : Bool :=
  yamlIsDigit c || c == '-' || c == '+' || c == ':' || c == '.' || c == ' ' || c == '\t'

/-- A separator atom for the cue date/time regex `([-:]|[tT])`. -/
def yamlCueDateSep (c : Char) : Bool :=
  c == '-' || c == ':' || c == 't' || c == 'T'

/-- cue's `useQuote`, branch 1: `^[-+0-9:. \t]+([-:]|[tT])[-+0-9:. \t]+[zZ]?$`. After an
    optional trailing `z`/`Z`, the body must split at some separator char into a nonempty
    all-date-char prefix and a nonempty all-date-char suffix. Trying every index as the
    separator mirrors the regex engine finding any valid split. -/
def yamlCueDateLike (s : String) : Bool := Id.run do
  let full := s.toList
  let body := match full.reverse with
    | 'z' :: rest => rest.reverse
    | 'Z' :: rest => rest.reverse
    | _ => full
  -- need at least sep plus one char on each side
  if body.length < 3 then return false
  let n := body.length
  for i in [1 : n - 1] do
    match body[i]? with
    | some c =>
        if yamlCueDateSep c then
          let pre := body.take i
          let post := body.drop (i + 1)
          if pre.all yamlCueDateChar && post.all yamlCueDateChar then
            return true
    | none => pure ()
  return false

/-- cue's `useQuote`, branch 2: `^0x[a-fA-F0-9]+$` (lowercase `0x` only). -/
def yamlCueHexLike (s : String) : Bool :=
  let cs := s.toList
  match cs with
  | '0' :: 'x' :: rest =>
      !rest.isEmpty && rest.all fun c =>
        yamlIsDigit c || ('a' ≤ c && c ≤ 'f') || ('A' ≤ c && c ≤ 'F')
  | _ => false

/-- cue's `shouldQuote` regex layer (`useQuote`): conservative date/time/base60-or-`0x`. -/
def yamlCueShouldQuote (s : String) : Bool :=
  yamlCueDateLike s || yamlCueHexLike s

/-- Drop `_` digit separators (go-yaml strips these before its int/float parse). -/
def yamlStripUnderscore (s : String) : String :=
  String.ofList (s.toList.filter (· != '_'))

/-- go-yaml's `yamlStyleFloat`: `^[-+]?(\.[0-9]+|[0-9]+(\.[0-9]*)?)([eE][-+]?[0-9]+)?$`.
    A hand NFA: optional sign, then a mantissa (`.` digits, or digits with optional `.`
    and fraction), then an optional `e`/`E` exponent with optional sign and ≥1 digit. -/
def yamlStyleFloat (s : String) : Bool := Id.run do
  let cs0 := s.toList
  let cs := match cs0 with
    | '+' :: rest => rest
    | '-' :: rest => rest
    | _ => cs0
  -- mantissa
  let afterMantissa : Option (List Char) :=
    match cs with
    | '.' :: rest =>
        let frac := rest.takeWhile yamlIsDigit
        if frac.isEmpty then none else some (rest.drop frac.length)
    | _ =>
        let intPart := cs.takeWhile yamlIsDigit
        if intPart.isEmpty then none
        else
          let afterInt := cs.drop intPart.length
          match afterInt with
          | '.' :: rest =>
              let frac := rest.takeWhile yamlIsDigit
              some (rest.drop frac.length)
          | _ => some afterInt
  match afterMantissa with
  | none => return false
  | some rest =>
    -- optional exponent
    match rest with
    | [] => return true
    | e :: erest =>
      if e != 'e' && e != 'E' then return false
      let esigned := match erest with
        | '+' :: r => r
        | '-' :: r => r
        | _ => erest
      let edigits := esigned.takeWhile yamlIsDigit
      return !edigits.isEmpty && (esigned.drop edigits.length).isEmpty

/-- go-yaml radix-literal ints: `^[-+]?0[xX][0-9a-fA-F]+$`, `…0[oO][0-7]+$`,
    `…0[bB][01]+$`. (Decimal and legacy-octal-shaped digit runs are already covered by
    `yamlStyleFloat`, since any `[0-9]+` parses as a float for go-yaml.) -/
def yamlRadixInt (s : String) : Bool :=
  let cs0 := s.toList
  let cs := match cs0 with
    | '+' :: rest => rest
    | '-' :: rest => rest
    | _ => cs0
  match cs with
  | '0' :: r :: rest =>
      let hexDigit := fun c => yamlIsDigit c || ('a' ≤ c && c ≤ 'f') || ('A' ≤ c && c ≤ 'F')
      let octDigit := fun c => '0' ≤ c && c ≤ '7'
      let binDigit := fun c => c == '0' || c == '1'
      if r == 'x' || r == 'X' then !rest.isEmpty && rest.all hexDigit
      else if r == 'o' || r == 'O' then !rest.isEmpty && rest.all octDigit
      else if r == 'b' || r == 'B' then !rest.isEmpty && rest.all binDigit
      else false
  | _ => false

/-- go-yaml's `isBase60Float`: `^[-+]?[0-9][0-9_]*(:[0-5]?[0-9])+(\.[0-9_]*)?$`, gated on a
    leading sign/digit and a `:` present. Sexagesimal (`1:30`, `+1:30:45.5`). -/
def yamlBase60Float (s : String) : Bool := Id.run do
  let cs0 := s.toList
  if !(s.toList.any (· == ':')) then return false
  let cs := match cs0 with
    | '+' :: rest => rest
    | '-' :: rest => rest
    | _ => cs0
  -- leading [0-9][0-9_]*
  match cs with
  | d :: _ =>
    if !yamlIsDigit d then return false
  | [] => return false
  let head := cs.takeWhile (fun c => yamlIsDigit c || c == '_')
  let mut rest := cs.drop head.length
  -- one-or-more (:[0-5]?[0-9])
  let mut groups := 0
  let isLowDigit := fun c => '0' ≤ c && c ≤ '5'
  while (rest.head? == some ':') do
    let afterColon := rest.drop 1
    match afterColon with
    | a :: b :: tl =>
        if isLowDigit a && yamlIsDigit b then
          groups := groups + 1; rest := tl
        else if yamlIsDigit a then
          groups := groups + 1; rest := b :: tl
        else
          return false
    | [a] =>
        if yamlIsDigit a then groups := groups + 1; rest := []
        else return false
    | [] => return false
  if groups == 0 then return false
  -- optional (.[0-9_]*)
  match rest with
  | '.' :: frac =>
      if frac.all (fun c => yamlIsDigit c || c == '_') then return true else return false
  | [] => return true
  | _ => return false

/-- Whether the bare form of `s` would parse as a YAML scalar **other than a plain
    string** — i.e. a number, bool, null, timestamp, base60 float, or YAML-1.1 legacy
    token — and so must be quoted to preserve its string-ness. The exact union of cue's
    `shouldQuote` and go-yaml v3's emitter (see the doc-block above). Total: every branch
    is a structural check, no parsing partiality. A multi-dot/segment token (IP, semver,
    CIDR, `name:tag`) satisfies none and stays bare, matching `cue`. -/
def wouldParseAsNonString (s : String) : Bool :=
  if s.isEmpty then true  -- resolves to null (`""` → `!!null`)
  else
    let plain := yamlStripUnderscore s
    yamlReservedWords.contains s          -- bool/null tokens + YAML-1.1 legacy bools
      || yamlCueShouldQuote s             -- cue date/time/base60/0x regex
      || yamlStyleFloat plain             -- decimal int / float (subsumes legacy octal)
      || yamlRadixInt plain               -- 0x / 0o / 0b literals
      || yamlBase60Float s                -- go-yaml isBase60Float (unstripped, has `:`)

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

/-- A scalar that opens with the YAML document-marker run `---` or `...` (go-yaml's
    emitter treats a `---`/`...` prefix as a leading indicator and quotes). The pure
    dash-runs `---`/`----` are already double-quoted upstream (`wouldParseAsNonString`
    via the date-like split), so this only needs to catch a `...` prefix or a `---`
    followed by a non-dash — exactly the forms `cue` single-quotes. -/
def yamlDocMarkerPrefix (cs : List Char) : Bool :=
  match cs with
  | '.' :: '.' :: '.' :: _ => true
  | '-' :: '-' :: '-' :: rest =>
      match rest with
      | '-' :: _ => false  -- pure dash-run; handled by the double-quote layer
      | _ => true
  | _ => false

/-- Whether a plain (bare) scalar would be unsafe and so needs single-quoting, given it
    is neither resolver-ambiguous nor escape-requiring. Mirrors go-yaml: leading/trailing
    space, a leading indicator, a leading `-`/`?`/`:` followed by space (or alone), a
    `---`/`...` document-marker prefix, a `: ` (colon-space) anywhere, a ` #` (space-hash)
    anywhere, or a trailing `:`. -/
def yamlNeedsSingleQuote (s : String) : Bool := Id.run do
  let cs := s.toList
  match cs with
  | [] => return true
  | first :: _ =>
    if first == ' ' then return true
    if yamlLeadingIndicator first then return true
    if yamlDocMarkerPrefix cs then return true
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
  else if wouldParseAsNonString s then
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

/-- Count the trailing `\n` characters of `s` (the run of newlines at the very end). -/
def yamlTrailingNewlines (s : String) : Nat :=
  let rec go : List Char -> Nat
    | '\n' :: rest => 1 + go rest
    | _ => 0
  go s.toList.reverse

/-- Indent one content line of a block scalar: an empty line stays empty (no trailing
    whitespace), a non-empty line gets the `pad` prefix. -/
def yamlBlockLine (pad : String) (line : String) : String :=
  if line.isEmpty then "" else pad ++ line

/-- A block scalar for a string containing newlines, matching `cue` (go-yaml v3) exactly,
    including the chomping indicator that encodes how many trailing newlines the string
    carries — `|-` (strip) for none, `|` (clip) for exactly one, `|+` (keep) for two or
    more — and the explicit indentation indicator `|2` when the first content line begins
    with a space (otherwise the block's indentation would be ambiguous). The indicator is
    the indent *increment* over the introducer line, which is a fixed 2 in this layout (it
    is NOT the absolute column). Content lines are indented by `indent`; getting the chomp
    wrong silently drops or adds trailing newlines, so a file body ending in `\n`
    round-trips losslessly. -/
def yamlBlockScalar (indent : Nat) (s : String) : String :=
  let pad := yamlIndent indent
  let trailing := yamlTrailingNewlines s
  let firstLineIndented := (s.toList.head? == some ' ')
  let indentTag := if firstLineIndented then "2" else ""
  if trailing == 0 then
    let body := joinWith "\n" ((s.splitOn "\n").map (yamlBlockLine pad))
    "|" ++ indentTag ++ "-\n" ++ body
  else if trailing == 1 then
    -- clip: one trailing newline is implied by the block, so drop the empty segment
    -- splitOn left at the end and emit no chomp indicator.
    let core := (s.dropEnd 1).toString
    let body := joinWith "\n" ((core.splitOn "\n").map (yamlBlockLine pad))
    "|" ++ indentTag ++ "\n" ++ body
  else
    -- keep: the block implies one trailing newline; the remaining `trailing - 1` newlines
    -- become explicit blank lines after the content.
    let core := (s.dropEnd trailing).toString
    let coreBody := joinWith "\n" ((core.splitOn "\n").map (yamlBlockLine pad))
    let blanks := String.ofList (List.replicate (trailing - 1) '\n')
    "|" ++ indentTag ++ "+\n" ++ coreBody ++ blanks

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
