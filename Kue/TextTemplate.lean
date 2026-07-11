import Kue.Value

namespace Kue.TextTemplate

/-! # `text/template` minimal core (STDLIB-TEXTTEMPLATE-T1)

A total, fuel-bounded lexer + parse-tree + tree-walk evaluator for the green subset of Go's
`text/template` that cue's `text/template.Execute` exposes, plus the two pure escapers
(`HTMLEscape`, `JSEscape`). A leaf module: it imports `Kue.Value` only (for `Prim`), operates
over its own already-forced `TemplateData` tree, and never touches eval/manifest/JSON.

Supported (T1): text passthrough; `{{.Field}}` / `{{.A.B}}` / `{{.}}`; `{{if}}…{{else}}…{{end}}`,
`{{range}}…{{else}}…{{end}}` (over list, over struct in KEY-SORTED order, over null ⇒ else),
`{{with}}…{{else}}…{{end}}` with Go truthiness; `{{/* comment */}}`; `{{-`/`-}}` whitespace
trimming; scalar/struct/list rendering in Go `fmt` shape (`map[k:v …]`, `[a b c]`); missing
field / null ⇒ `<no value>` at an action, `<nil>` when nested.

Deferred (T1) ⇒ `.unsupported` (the caller maps to `unsupportedBuiltin`): any builtin FUNC
(`and`/`len`/`eq`/…), pipelines `{{a|b}}`, variables `{{$x}}`, `printf`, `{{define}}`/
`{{template}}`/`{{block}}`, range over a scalar, and — in `JSEscape` — any non-ASCII rune
(needs the deferred `unicode.IsPrint` table). A malformed template (unclosed action, stray
`{{end}}`) ⇒ `.bottom`. FLOAT data is caught upstream in the caller's `TemplateData` bridge. -/

/-- The already-forced concrete data an `Execute` call walks. Float is deliberately
    UNREPRESENTABLE: the caller's `Value`→`TemplateData` bridge routes any float to
    `unsupportedBuiltin` rather than build one, so the renderer never faces a float. -/
inductive TemplateData where
  | null
  | bool (b : Bool)
  | int (i : Int)
  | str (s : String)
  | list (items : List TemplateData)
  | struct (fields : List (String × TemplateData))
deriving Repr, BEq

/-- A single command operand in an action or block header — the only pipeline shapes T1
    accepts. Anything else (function call, literal number/string, `$var`, `|`) is deferred. -/
inductive Operand where
  | dot
  | field (path : List String)
  | lit (value : TemplateData)
deriving Repr, BEq

inductive BlockKind where
  | ifB
  | rangeB
  | withB
deriving Repr, BEq

inductive Node where
  | text (s : String)
  | output (op : Operand)
  | block (kind : BlockKind) (src : Operand) (body elseBody : List Node)
deriving Repr, BEq

/-- The two failure modes of an `Execute`, distinct at the caller: `bottom` is a genuine
    template/eval error (malformed template, field access on a scalar) that cue also rejects;
    `unsupported` is a construct T1 recognizes but has not implemented, surfaced as an
    `unsupportedBuiltin` marker rather than a wrong result. -/
inductive TemplateError where
  | bottom
  | unsupported
deriving Repr, BEq

/-! ## Escapers -/

/-- Go's `text/template.HTMLEscape` replacement set: `< > & ' "` and NUL⇒U+FFFD; every other
    rune (including all non-ASCII and other control chars) passes through verbatim. -/
def htmlEscapeChar : Char → String
  | '<' => "&lt;"
  | '>' => "&gt;"
  | '&' => "&amp;"
  | '\'' => "&#39;"
  | '"' => "&#34;"
  | c => if c.toNat == 0 then String.singleton (Char.ofNat 0xFFFD) else String.singleton c

def htmlEscape (s : String) : String :=
  String.join (s.toList.map htmlEscapeChar)

/-- An uppercase hex digit (`0-9A-F`) for the `\u00XX` escapes Go's `JSEscape` emits. -/
def hexUpper (n : Nat) : Char :=
  if n < 10 then Char.ofNat (48 + n) else Char.ofNat (65 + (n - 10))

/-- Go's `text/template.JSEscape` for one rune, or `none` for a non-ASCII rune (Go escapes it
    per `unicode.IsPrint`, the deferred Unicode-table dependency — see `cue-spec-gaps.md`). The
    ASCII surface is exact: `\ ' "` and `< > & =` get named escapes, control chars below 0x20
    become `\u00XX` (uppercase), and every other ASCII char (including 0x7F) passes through. -/
def jsEscapeChar : Char → Option String
  | '\\' => some "\\\\"
  | '\'' => some "\\'"
  | '"' => some "\\\""
  | '<' => some "\\u003C"
  | '>' => some "\\u003E"
  | '&' => some "\\u0026"
  | '=' => some "\\u003D"
  | c =>
      let n := c.toNat
      if n < 0x20 then
        some (String.ofList ['\\', 'u', '0', '0', hexUpper (n / 16), hexUpper (n % 16)])
      else if n < 0x80 then
        some (String.singleton c)
      else
        none

/-- Escape a string for JS, or `none` if it carries a non-ASCII rune (deferred, see above). -/
def jsEscape (s : String) : Option String :=
  (s.toList.mapM jsEscapeChar).map String.join

/-! ## Rendering (Go `fmt` shapes) -/

mutual
  /-- Go `%v` of a data value: structs as key-sorted `map[k:v …]`, lists as space-joined
      `[a b c]`, null as `<nil>` (the NESTED null; the top-level action null is `<no value>`). -/
  def renderGoValue : TemplateData → String
    | .null => "<nil>"
    | .bool b => if b then "true" else "false"
    | .int i => toString i
    | .str s => s
    | .list items => "[" ++ renderGoList items ++ "]"
    | .struct fields => "map[" ++ renderGoFields fields ++ "]"

  def renderGoList : List TemplateData → String
    | [] => ""
    | [x] => renderGoValue x
    | x :: rest => renderGoValue x ++ " " ++ renderGoList rest

  def renderGoFields : List (String × TemplateData) → String
    | [] => ""
    | [kv] => kv.fst ++ ":" ++ renderGoValue kv.snd
    | kv :: rest => kv.fst ++ ":" ++ renderGoValue kv.snd ++ " " ++ renderGoFields rest
end

/-- How an `{{action}}` renders its value: a bare null/missing field is `<no value>`; every
    other value uses the Go `%v` shape (whose nested nulls render `<nil>`). -/
def renderAction : TemplateData → String
  | .null => "<no value>"
  | d => renderGoValue d

/-- Go template truthiness: false for null, `false`, 0, empty string, empty list/struct. -/
def isTruthy : TemplateData → Bool
  | .null => false
  | .bool b => b
  | .int i => i != 0
  | .str s => s != ""
  | .list l => !l.isEmpty
  | .struct f => !f.isEmpty

/-- Resolve one field access. A struct yields the field or `null` (a missing field is nil, not
    an error); a null base stays null (chaining through a missing field is nil); any scalar or
    list base is a `bottom` (Go: "can't evaluate field … in type …"). -/
def lookupField : TemplateData → String → Except TemplateError TemplateData
  | .struct fields, name => .ok ((fields.lookup name).getD .null)
  | .null, _ => .ok .null
  | _, _ => .error .bottom

/-- Resolve an operand against the current dot. A field path folds `lookupField` left-to-right. -/
def resolveOperand (dot : TemplateData) : Operand → Except TemplateError TemplateData
  | .dot => .ok dot
  | .lit v => .ok v
  | .field path => path.foldlM (fun cur seg => lookupField cur seg) dot

/-! ## Data size (fuel bound) -/

mutual
  def dataSize : TemplateData → Nat
    | .null | .bool _ | .int _ | .str _ => 1
    | .list items => 1 + dataListSize items
    | .struct fields => 1 + dataFieldsSize fields

  def dataListSize : List TemplateData → Nat
    | [] => 0
    | x :: rest => dataSize x + dataListSize rest

  def dataFieldsSize : List (String × TemplateData) → Nat
    | [] => 0
    | kv :: rest => dataSize kv.snd + dataFieldsSize rest
end

mutual
  def nodeSize : Node → Nat
    | .text _ | .output _ => 1
    | .block _ _ body elseBody => 1 + nodeListSize body + nodeListSize elseBody

  def nodeListSize : List Node → Nat
    | [] => 0
    | x :: rest => nodeSize x + nodeListSize rest
end

/-! ## Evaluation (fuel-bounded tree walk) -/

mutual
  /-- Evaluate a node sequence against `dot`, threading a shared fuel budget so the whole walk
      (including range expansion) is bounded by one strictly-decreasing `Nat`. -/
  def evalSeq : Nat → TemplateData → List Node → Except TemplateError (String × Nat)
    | 0, _, _ => .error .bottom
    | fuel + 1, _, [] => .ok ("", fuel)
    | fuel + 1, dot, node :: rest => do
        let (s1, f1) ← evalNode fuel dot node
        let (s2, f2) ← evalSeq f1 dot rest
        .ok (s1 ++ s2, f2)

  def evalNode : Nat → TemplateData → Node → Except TemplateError (String × Nat)
    | 0, _, _ => .error .bottom
    | fuel + 1, _, .text s => .ok (s, fuel)
    | fuel + 1, dot, .output op => do
        let v ← resolveOperand dot op
        .ok (renderAction v, fuel)
    | fuel + 1, dot, .block .ifB src body elseBody => do
        let v ← resolveOperand dot src
        if isTruthy v then evalSeq fuel dot body else evalSeq fuel dot elseBody
    | fuel + 1, dot, .block .withB src body elseBody => do
        let v ← resolveOperand dot src
        if isTruthy v then evalSeq fuel v body else evalSeq fuel dot elseBody
    | fuel + 1, dot, .block .rangeB src body elseBody => do
        let v ← resolveOperand dot src
        match v with
        | .list items =>
            if items.isEmpty then evalSeq fuel dot elseBody else evalRange fuel body items
        | .struct fields =>
            if fields.isEmpty then evalSeq fuel dot elseBody
            else evalRange fuel body (fields.map Prod.snd)
        | .null => evalSeq fuel dot elseBody
        | _ => .error .unsupported

  def evalRange : Nat → List Node → List TemplateData → Except TemplateError (String × Nat)
    | 0, _, _ => .error .bottom
    | fuel + 1, _, [] => .ok ("", fuel)
    | fuel + 1, body, elem :: rest => do
        let (s1, f1) ← evalSeq fuel elem body
        let (s2, f2) ← evalRange f1 body rest
        .ok (s1 ++ s2, f2)
end

/-! ## Lexing -/

/-- Go's template whitespace set (`" \t\r\n"`), used for both `{{-`/`-}}` trimming and the
    action-body word split. Narrower than `Char.isWhitespace`, matching Go exactly. -/
def isSpaceChar (c : Char) : Bool :=
  c == ' ' || c == '\t' || c == '\n' || c == '\r'

/-- A raw lexeme: literal text, or an action with its trim flags and inner body string. -/
inductive RawItem where
  | text (s : String)
  | action (trimL trimR : Bool) (body : String)
deriving Repr, BEq

/-- Read an action body up to the closing `}}`, returning the body chars and the remainder.
    `none` on an unclosed action (input ends before `}}`). Fuel-bounded by the input length. -/
def readActionBody : Nat → List Char → Option (List Char × List Char)
  | 0, _ => none
  | _ + 1, [] => none
  | _ + 1, '}' :: '}' :: rest => some ([], rest)
  | fuel + 1, c :: rest => (readActionBody fuel rest).map (fun (b, r) => (c :: b, r))

/-- Strip a trailing `-}}` trim marker off a raw body: a body ending `<space>-` sets trimRight
    and drops the `-` (the space is trimmed later). -/
def stripRightTrim (b : List Char) : Bool × List Char :=
  match b.reverse with
  | '-' :: c :: _ => if isSpaceChar c then (true, b.dropLast) else (false, b)
  | _ => (false, b)

/-- Tokenize the template into `RawItem`s. `textAcc` accumulates the current text run in
    reverse; `out` is the emitted prefix. `{{` opens an action (with an optional `{{- ` left-trim
    marker); unclosed actions ⇒ `bottom`. Fuel-bounded by the remaining input length. -/
def lexTemplate : Nat → List Char → List RawItem → List Char → Except TemplateError (List RawItem)
  | 0, _, _, _ => .error .bottom
  | _ + 1, textAcc, out, [] =>
      let flushed := if textAcc.isEmpty then out else out ++ [.text (String.ofList textAcc.reverse)]
      .ok flushed
  | fuel + 1, textAcc, out, '{' :: '{' :: rest =>
      let out := if textAcc.isEmpty then out else out ++ [.text (String.ofList textAcc.reverse)]
      let (trimL, rest1) :=
        match rest with
        | '-' :: c :: r => if isSpaceChar c then (true, c :: r) else (false, rest)
        | _ => (false, rest)
      match readActionBody fuel rest1 with
      | none => .error .bottom
      | some (rawBody, rest2) =>
          let (trimR, body) := stripRightTrim rawBody
          lexTemplate fuel [] (out ++ [.action trimL trimR (String.ofList body)]) rest2
  | fuel + 1, textAcc, out, c :: rest =>
      lexTemplate fuel (c :: textAcc) out rest

/-- Apply the `{{-`/`-}}` trim flags to neighboring text: `prevTrimR` (the preceding action's
    right-trim) strips a text's leading whitespace; the following action's left-trim strips its
    trailing whitespace. -/
def applyTrims : Bool → List RawItem → List RawItem
  | _, [] => []
  | prevTrimR, .text s :: rest =>
      let afterL := if prevTrimR then String.ofList (s.toList.dropWhile isSpaceChar) else s
      let nextTrimL := match rest with | .action tl _ _ :: _ => tl | _ => false
      let afterR :=
        if nextTrimL then String.ofList ((afterL.toList.reverse.dropWhile isSpaceChar).reverse)
        else afterL
      .text afterR :: applyTrims false rest
  | _, .action tl tr body :: rest =>
      .action tl tr body :: applyTrims tr rest

/-! ## Parsing -/

/-- Whether `s` is a Go template field identifier (letter/underscore start, then alnum/`_`). -/
def isIdent (s : String) : Bool :=
  match s.toList with
  | [] => false
  | c :: rest => (c.isAlpha || c == '_') && rest.all (fun d => d.isAlphanum || d == '_')

/-- Parse a single command operand, or `none` if it is outside T1's accepted set. -/
def parseOperand (s : String) : Option Operand :=
  if s == "." then some .dot
  else if s == "true" then some (.lit (.bool true))
  else if s == "false" then some (.lit (.bool false))
  else if s == "nil" then some (.lit .null)
  else match s.toList with
    | '.' :: rest =>
        let segs := (String.ofList rest).splitOn "."
        if segs.all isIdent then some (.field segs) else none
    | _ => none

/-- Whether a trimmed body is a whole `{{/* … */}}` comment. -/
def isComment (b : List Char) : Bool :=
  b.length ≥ 4 && b.take 2 == ['/', '*'] && b.reverse.take 2 == ['/', '*']

/-- Split a body on whitespace runs into its command words. -/
def splitWords : List Char → List Char → List String
  | acc, [] => if acc.isEmpty then [] else [String.ofList acc.reverse]
  | acc, c :: rest =>
      if isSpaceChar c then
        (if acc.isEmpty then [] else [String.ofList acc.reverse]) ++ splitWords [] rest
      else splitWords (c :: acc) rest

/-- The classification of an action's body, dispatched by its leading keyword/operand. -/
inductive ActionClass where
  | comment
  | close
  | elseKw
  | open (kind : BlockKind) (src : Operand)
  | outputOp (op : Operand)
  | unsupported
  | parseErr
deriving Repr, BEq

def classifyAction (bodyStr : String) : ActionClass :=
  let body := (bodyStr.toList.dropWhile isSpaceChar).reverse.dropWhile isSpaceChar |>.reverse
  if isComment body then .comment
  else
    match splitWords [] body with
    | [] => .parseErr
    | w :: ws =>
        if w == "end" then (if ws.isEmpty then .close else .parseErr)
        else if w == "else" then (if ws.isEmpty then .elseKw else .unsupported)
        else if w == "if" || w == "range" || w == "with" then
          match ws with
          | [operand] =>
              match parseOperand operand with
              | some op =>
                  let kind := if w == "if" then BlockKind.ifB
                              else if w == "range" then BlockKind.rangeB else BlockKind.withB
                  .open kind op
              | none => .unsupported
          | [] => .parseErr
          | _ => .unsupported
        else if w == "define" || w == "template" || w == "block" then .unsupported
        else
          match ws with
          | [] =>
              match parseOperand w with
              | some op => .outputOp op
              | none => .unsupported
          | _ => .unsupported

/-- A parse's stop reason: end of input, or a top-level `{{else}}` / `{{end}}`. -/
inductive Term where
  | eof
  | elseT
  | endT
deriving Repr, BEq

/-- Parse a `RawItem` sequence into nodes up to the enclosing `{{else}}`/`{{end}}` (or EOF),
    returning the nodes, the stop reason, and the unconsumed items. Fuel-bounded by the item
    count; a deferred construct ⇒ `unsupported`, a malformed one ⇒ `bottom`. -/
def parseSeq : Nat → List RawItem → Except TemplateError (List Node × Term × List RawItem)
  | 0, _ => .error .bottom
  | _ + 1, [] => .ok ([], .eof, [])
  | fuel + 1, item :: rest =>
      match item with
      | .text s => do
          let (nodes, term, r) ← parseSeq fuel rest
          .ok (.text s :: nodes, term, r)
      | .action _ _ bodyStr =>
          match classifyAction bodyStr with
          | .comment => parseSeq fuel rest
          | .parseErr => .error .bottom
          | .unsupported => .error .unsupported
          | .close => .ok ([], .endT, rest)
          | .elseKw => .ok ([], .elseT, rest)
          | .outputOp op => do
              let (nodes, term, r) ← parseSeq fuel rest
              .ok (.output op :: nodes, term, r)
          | .open kind src => do
              let (body1, term1, r1) ← parseSeq fuel rest
              match term1 with
              | .endT => do
                  let (nodes, term, r) ← parseSeq fuel r1
                  .ok (.block kind src body1 [] :: nodes, term, r)
              | .elseT => do
                  let (body2, term2, r2) ← parseSeq fuel r1
                  match term2 with
                  | .endT => do
                      let (nodes, term, r) ← parseSeq fuel r2
                      .ok (.block kind src body1 body2 :: nodes, term, r)
                  | _ => .error .bottom
              | .eof => .error .bottom

/-- Lex, trim, parse, and tree-walk `tmpl` against `data`, producing the rendered string or a
    `TemplateError`. Total: every stage is fuel-bounded or structural. -/
def runTemplate (tmpl : String) (data : TemplateData) : Except TemplateError String := do
  let chars := tmpl.toList
  let items ← lexTemplate (chars.length + 1) [] [] chars
  let trimmed := applyTrims false items
  let (nodes, term, _) ← parseSeq (trimmed.length + 1) trimmed
  match term with
  | .eof =>
      let ds := dataSize data
      let fuel := (nodeListSize nodes + 1) * (ds + 1) * (ds + 1) + ds + 16
      (evalSeq fuel data nodes).map Prod.fst
  | _ => .error .bottom

end Kue.TextTemplate
