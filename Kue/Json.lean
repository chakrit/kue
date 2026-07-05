import Kue.Manifest
import Kue.Base64

namespace Kue

/-- Lowercase hex nibble (0–15) for `\uXXXX` JSON escapes. -/
def jsonHexDigit (value : Nat) : Char :=
  if value < 10 then Char.ofNat ('0'.toNat + value)
  else Char.ofNat ('a'.toNat + (value - 10))

/-- Four-digit lowercase `\uXXXX` escape of a code point below 0x10000. -/
def jsonUnicodeEscape (code : Nat) : List Char :=
  ['\\', 'u',
    jsonHexDigit (code / 4096 % 16),
    jsonHexDigit (code / 256 % 16),
    jsonHexDigit (code / 16 % 16),
    jsonHexDigit (code % 16)]

/-- Escape one character for a JSON string body, matching `cue`'s `json.Marshal`
    (Go's encoder with HTML escaping disabled): `"` and `\` are backslash-escaped;
    `\b \f \n \r \t` use their short forms; every other control character below
    0x20 becomes `\uXXXX`; `<`, `>`, `&`, `/` and all non-control runes (including
    non-ASCII) pass through verbatim. -/
def escapeJsonChar : Char -> List Char
  | '"' => ['\\', '"']
  | '\\' => ['\\', '\\']
  | '\n' => ['\\', 'n']
  | '\r' => ['\\', 'r']
  | '\t' => ['\\', 't']
  | c =>
      if c == Char.ofNat 0x08 then ['\\', 'b']
      else if c == Char.ofNat 0x0c then ['\\', 'f']
      else if c.toNat < 0x20 then jsonUnicodeEscape c.toNat
      else [c]

def escapeJsonChars : List Char -> List Char
  | [] => []
  | c :: rest => escapeJsonChar c ++ escapeJsonChars rest

/-- A JSON string literal (including surrounding quotes) for `value`. -/
def jsonString (value : String) : String :=
  "\"" ++ String.ofList (escapeJsonChars value.toList) ++ "\""

/-- JSON rendering of a manifested primitive. A `.bytes` payload is base64-encoded as
    a JSON string (Go marshals `[]byte` to standard base64); a float is rendered from
    its exact stored decimal text verbatim (`cue` preserves `1.50`, `10.0`). -/
def manifestPrimToJson : Prim -> String
  | .null => "null"
  | .bool true => "true"
  | .bool false => "false"
  | .int value => toString value
  | .float _ text => text
  | .string value => jsonString value
  | .bytes value => jsonString (base64Encode value.toList)

mutual
  /-- Compact JSON of a manifested value: object keys in source order (`cue`/Go preserve
      insertion order, they do NOT sort), `,`/`:` separators with no spaces, matching
      `cue`'s `json.Marshal` byte-for-byte. Reused by B5's `--out json` mode. The mutual
      helpers fold the struct/list children structurally so the recursion stays total. -/
  def manifestToJson : ManifestValue -> String
    | .prim prim => manifestPrimToJson prim
    | .struct fields => "{" ++ jsonFields fields ++ "}"
    | .list items => "[" ++ jsonItems items ++ "]"

  def jsonFields : List (String × ManifestValue) -> String
    | [] => ""
    | [field] => jsonString field.fst ++ ":" ++ manifestToJson field.snd
    | field :: rest =>
        jsonString field.fst ++ ":" ++ manifestToJson field.snd ++ "," ++ jsonFields rest

  def jsonItems : List ManifestValue -> String
    | [] => ""
    | [item] => manifestToJson item
    | item :: rest => manifestToJson item ++ "," ++ jsonItems rest
end

/-- Manifest `value` (applying defaults/incompleteness rules) then serialize it to
    compact JSON. An incomplete or contradictory value surfaces as a `ManifestError`,
    which the `json.Marshal` builtin maps to bottom (`cue` errors). -/
def valueToJson (value : Value) : Except ManifestError String :=
  (manifest value).map manifestToJson

/-- Indentation prefix of `n` spaces for pretty JSON. -/
def jsonIndent (n : Nat) : String := String.ofList (List.replicate n ' ')

mutual
  /-- Pretty (4-space-indented) JSON of a manifested value, matching `cue export`'s
      DEFAULT output (and explicit `--out json`): keys in source order, `": "` between
      key and value, one element per line, closing brace/bracket dedented. An empty
      object/array is `{}`/`[]` on one line. `indent` is the current nesting depth's
      leading width. Distinct from the compact `manifestToJson` used by `json.Marshal`. -/
  def manifestToJsonPretty (indent : Nat) : ManifestValue -> String
    | .prim prim => manifestPrimToJson prim
    | .struct [] => "{}"
    | .list [] => "[]"
    | .struct fields => "{\n" ++ jsonPrettyFields (indent + 4) fields ++ "\n" ++ jsonIndent indent ++ "}"
    | .list items => "[\n" ++ jsonPrettyItems (indent + 4) items ++ "\n" ++ jsonIndent indent ++ "]"

  def jsonPrettyFields (indent : Nat) : List (String × ManifestValue) -> String
    | [] => ""
    | [field] => jsonIndent indent ++ jsonString field.fst ++ ": " ++ manifestToJsonPretty indent field.snd
    | field :: rest =>
        jsonIndent indent ++ jsonString field.fst ++ ": " ++ manifestToJsonPretty indent field.snd
          ++ ",\n" ++ jsonPrettyFields indent rest

  def jsonPrettyItems (indent : Nat) : List ManifestValue -> String
    | [] => ""
    | [item] => jsonIndent indent ++ manifestToJsonPretty indent item
    | item :: rest =>
        jsonIndent indent ++ manifestToJsonPretty indent item ++ ",\n" ++ jsonPrettyItems indent rest
end

/-- Manifest `value` then serialize to pretty JSON (the `cue export` default), with a
    trailing newline as `cue` emits. -/
def valueToJsonPretty (value : Value) : Except ManifestError String :=
  (manifest value).map (fun mv => manifestToJsonPretty 0 mv ++ "\n")

end Kue
