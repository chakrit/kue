import Init.Data.String.Search

namespace Kue

inductive Kind where
  | null
  | bool
  | number
  | int
  | float
  | string
  | bytes
deriving Repr, BEq, DecidableEq

inductive Prim where
  | null
  | bool (value : Bool)
  | int (value : Int)
  | float (value : String)
  | string (value : String)
  | bytes (value : String)
deriving Repr, BEq, DecidableEq

namespace Prim

def kind : Prim -> Kind
  | .null => .null
  | .bool _ => .bool
  | .int _ => .int
  | .float _ => .float
  | .string _ => .string
  | .bytes _ => .bytes

end Prim

inductive Mark where
  | regular
  | default
deriving Repr, BEq, DecidableEq

/-- An exact base-10 rational: `numerator / 10^scale`. The canonical numeric value used
    for decimal literals and bound limits, so comparison and arithmetic are total and
    exact (no float rounding). Lives here (rather than `Decimal.lean`) because
    `boundConstraint` carries one and `Value` must see the type. -/
structure DecimalValue where
  numerator : Int
  scale : Nat
deriving Repr, BEq, DecidableEq

def evalPow10 : Nat -> Nat
  | 0 => 1
  | exponent + 1 => 10 * evalPow10 exponent

def maxNat (left right : Nat) : Nat :=
  if left <= right then right else left

def scaleDecimalNumerator (targetScale : Nat) (value : DecimalValue) : Int :=
  value.numerator * Int.ofNat (evalPow10 (targetScale - value.scale))

def decimalCompareNumerators (left right : DecimalValue) : Int × Int :=
  let scale := maxNat left.scale right.scale
  (scaleDecimalNumerator scale left, scaleDecimalNumerator scale right)

def decimalEqValues (left right : DecimalValue) : Bool :=
  let compared := decimalCompareNumerators left right
  compared.fst == compared.snd

def decimalLtValues (left right : DecimalValue) : Bool :=
  let compared := decimalCompareNumerators left right
  compared.fst < compared.snd

def decimalLeValues (left right : DecimalValue) : Bool :=
  let compared := decimalCompareNumerators left right
  compared.fst <= compared.snd

/-- A whole-number decimal (scale 0). The lift used when an integer literal seeds a
    bound limit (`>0` ⇒ `intDecimal 0`). -/
def intDecimal (value : Int) : DecimalValue :=
  { numerator := value, scale := 0 }

def trimDecimalZerosWith : Int -> Nat -> DecimalValue
  | numerator, 0 => { numerator := numerator, scale := 0 }
  | numerator, scale + 1 =>
      if numerator % 10 == 0 then
        trimDecimalZerosWith (numerator / 10) scale
      else
        { numerator := numerator, scale := scale + 1 }

def decimalIntAbsNat (value : Int) : Nat :=
  if value < 0 then
    (-value).toNat
  else
    value.toNat

def repeatZeros : Nat -> String
  | 0 => ""
  | count + 1 => "0" ++ repeatZeros count

def leftPadZeros (width : Nat) (value : String) : String :=
  repeatZeros (width - value.toList.length) ++ value

def formatDecimalAtScale (value : DecimalValue) (forceFloat : Bool) : String :=
  let sign := if value.numerator < 0 then "-" else ""
  let abs := decimalIntAbsNat value.numerator
  match value.scale with
  | 0 =>
      let whole := sign ++ toString abs
      if forceFloat then whole ++ ".0" else whole
  | scale =>
      let divisor := evalPow10 scale
      let whole := abs / divisor
      let fraction := abs % divisor
      sign ++ toString whole ++ "." ++ leftPadZeros scale (toString fraction)

def formatFiniteDecimal (value : DecimalValue) (forceFloat : Bool) : String :=
  formatDecimalAtScale (trimDecimalZerosWith value.numerator value.scale) forceFloat

/-- Render a bound's decimal limit as CUE prints it inside a bound (`>0`, `>0.5`,
    `>-1.5`): the trimmed value at minimal scale, never force-floated (a whole limit
    prints as an integer, `>0` not `>0.0`). -/
def formatBoundLimit (value : DecimalValue) : String :=
  formatFiniteDecimal value false

def evalDigitValue? (value : Char) : Option Nat :=
  if '0'.toNat <= value.toNat && value.toNat <= '9'.toNat then
    some (value.toNat - '0'.toNat)
  else
    none

def parseEvalDigitsWithCount : List Char -> Nat -> Nat -> Option (Nat × Nat × List Char)
  | [], _, 0 => none
  | [], value, count => some (value, count, [])
  | char :: chars, value, count =>
      match evalDigitValue? char with
      | some digit => parseEvalDigitsWithCount chars (value * 10 + digit) (count + 1)
      | none =>
          if count == 0 then
            none
          else
            some (value, count, char :: chars)

def parseEvalDigits (chars : List Char) : Option (Nat × Nat × List Char) :=
  parseEvalDigitsWithCount chars 0 0

def parseDecimalMantissa (chars : List Char) : Option (DecimalValue × List Char) :=
  match parseEvalDigits chars with
  | none => none
  | some (whole, _, '.' :: rest) =>
      match parseEvalDigits rest with
      | none => none
      | some (fraction, fractionCount, rest) =>
          let scale := evalPow10 fractionCount
          some ({ numerator := Int.ofNat (whole * scale + fraction), scale := fractionCount }, rest)
  | some (whole, _, rest) => some ({ numerator := Int.ofNat whole, scale := 0 }, rest)

def parseDecimalExponent : List Char -> Option (Int × List Char)
  | '+' :: rest =>
      match parseEvalDigits rest with
      | some (exponent, _, rest) => some (Int.ofNat exponent, rest)
      | none => none
  | '-' :: rest =>
      match parseEvalDigits rest with
      | some (exponent, _, rest) => some (-(Int.ofNat exponent), rest)
      | none => none
  | chars =>
      match parseEvalDigits chars with
      | some (exponent, _, rest) => some (Int.ofNat exponent, rest)
      | none => none

def applyDecimalExponent (value : DecimalValue) (exponent : Int) : DecimalValue :=
  if exponent < 0 then
    { value with scale := value.scale + (-exponent).toNat }
  else
    let shift := exponent.toNat
    if value.scale <= shift then
      {
        numerator := value.numerator * Int.ofNat (evalPow10 (shift - value.scale)),
        scale := 0
      }
    else
      { value with scale := value.scale - shift }

def applyDecimalSign (negative : Bool) (value : DecimalValue) : DecimalValue :=
  if negative then
    { value with numerator := -value.numerator }
  else
    value

def parseUnsignedDecimalText (negative : Bool) (chars : List Char) : Option DecimalValue :=
  match parseDecimalMantissa chars with
  | none => none
  | some (mantissa, rest) =>
      let signed := applyDecimalSign negative mantissa
      match rest with
      | [] => some signed
      | 'e' :: rest =>
          match parseDecimalExponent rest with
          | some (exponent, []) => some (applyDecimalExponent signed exponent)
          | _ => none
      | 'E' :: rest =>
          match parseDecimalExponent rest with
          | some (exponent, []) => some (applyDecimalExponent signed exponent)
          | _ => none
      | _ => none

def parseDecimalText (value : String) : Option DecimalValue :=
  match value.toList with
  | '-' :: rest => parseUnsignedDecimalText true rest
  | '+' :: rest => parseUnsignedDecimalText false rest
  | chars => parseUnsignedDecimalText false chars

def decimalFromPrim? : Prim -> Option DecimalValue
  | .int value => some { numerator := value, scale := 0 }
  | .float value => parseDecimalText value
  | _ => none

/-- The numeric domain a bound constrains. A bare bound (`>0`) is `number` — it admits
    both `int` and `float` operands, matching CUE (`>0 & 1.5` ⇒ `1.5`). Meeting with a
    `kind` narrows it: `int & >0` ⇒ `int`-domain (rejects floats), `float & >0` ⇒
    `float`-domain (rejects ints). A proper sum, not a flag, so the three states are the
    only representable ones. -/
inductive NumberDomain where
  | number
  | int
  | float
deriving Repr, BEq, DecidableEq

namespace NumberDomain

/-- The `Kind` this domain narrows to, used when meeting a bound's domain with a kind. -/
def kind : NumberDomain -> Kind
  | .number => .number
  | .int => .int
  | .float => .float

/-- Does this domain admit a primitive of the given kind? `number` admits int and float;
    `int`/`float` admit only their own. Non-numeric kinds never match. -/
def admitsKind : NumberDomain -> Kind -> Bool
  | .number, .int => true
  | .number, .float => true
  | .int, .int => true
  | .float, .float => true
  | _, _ => false

/-- Narrow a bound's domain by meeting with a numeric kind. `number` (the bare default)
    yields to either `int` or `float`; the same domain is idempotent; an incompatible
    pair (`int` vs `float`) has no inhabitant — `none`. -/
def narrow : NumberDomain -> NumberDomain -> Option NumberDomain
  | .number, other => some other
  | other, .number => some other
  | .int, .int => some .int
  | .float, .float => some .float
  | _, _ => none

/-- A stable rank for canonical ordering. -/
def rank : NumberDomain -> Nat
  | .number => 0
  | .int => 1
  | .float => 2

end NumberDomain

/-- The comparator carried by a numeric bound constraint (`>=n`, `>n`, `<=n`, `<n`). The
    four CUE bound forms collapse to one `boundConstraint` parameterized over this kind, so
    the meet/format/order layers carry one bound arm with a per-kind comparator rather than
    four parallel constructors. `lower`/`upper` classify which side of a range a kind bounds;
    `strict` distinguishes `>`/`<` from `>=`/`<=`. -/
inductive BoundKind where
  | ge
  | gt
  | le
  | lt
deriving Repr, BEq, DecidableEq

namespace BoundKind

/-- Does this bound constrain values from below (`>=`/`>`)? -/
def lower : BoundKind -> Bool
  | .ge => true
  | .gt => true
  | .le => false
  | .lt => false

/-- Is this bound strict (`>`/`<`, exclusive) rather than inclusive (`>=`/`<=`)? -/
def strict : BoundKind -> Bool
  | .ge => false
  | .gt => true
  | .le => false
  | .lt => true

/-- The display prefix CUE writes for this bound. -/
def symbol : BoundKind -> String
  | .ge => ">="
  | .gt => ">"
  | .le => "<="
  | .lt => "<"

/-- A stable rank used to order bound kinds within a canonical conjunction; `>=`<`>`<`<=`<`<`,
    so lower bounds sort before upper bounds and inclusive before strict — matching CUE's
    display order (`>=0 & <=10`). -/
def rank : BoundKind -> Nat
  | .ge => 0
  | .gt => 1
  | .le => 2
  | .lt => 3

/-- Does `value` satisfy a bound of this kind against `limit`? Decimal-valued, comparing
    via the exact base-10 rational order (`decimalLtValues`/`decimalLeValues`) so a bound
    like `>0.5` admits `1.0` and rejects `0.25` without float rounding. -/
def admits (kind : BoundKind) (limit value : DecimalValue) : Bool :=
  match kind with
  | .ge => decimalLeValues limit value
  | .gt => decimalLtValues limit value
  | .le => decimalLeValues value limit
  | .lt => decimalLtValues value limit

end BoundKind

inductive UnaryOp where
  | boolNot
  | numPos
  | numNeg
deriving Repr, BEq, DecidableEq

inductive BinaryOp where
  | add
  | sub
  | mul
  | div
  | intDiv
  | intMod
  | intQuo
  | intRem
  | eq
  | ne
  | lt
  | le
  | gt
  | ge
  | regexMatch
  | regexNotMatch
  | boolAnd
  | boolOr
deriving Repr, BEq, DecidableEq

/-- The presence axis of a field: a plain field (`regular`), one that need not be
    present (`optional`, `x?`), or one that must be supplied (`required`, `x!`). These
    are the three rungs of one lattice; definition-ness and hidden-ness are *separate*
    axes (`FieldClass`). `required` is the strongest rung, `optional` the weakest. -/
inductive Optionality where
  | regular
  | optional
  | required
deriving Repr, BEq, DecidableEq

namespace Optionality

/-- Meet on the presence lattice. A `regular` conjunct *is* present and satisfies any
    requirement, so it dominates (`x! & x = x`, `x? & x = x`). Failing a present conjunct,
    a `required` one keeps the field required-but-absent (`x! & x! = x!`, `x! & x? = x!`).
    Only `optional & optional` stays optional. Total, matching CUE: providing a concrete
    field discharges `!`, but two `!`s never self-satisfy. -/
def meet : Optionality -> Optionality -> Optionality
  | .regular, _ => .regular
  | _, .regular => .regular
  | .required, _ => .required
  | _, .required => .required
  | .optional, .optional => .optional

end Optionality

/-- A field's modifiers, modelled as **orthogonal** axes — exactly as CUE treats them.
    A field independently is/isn't a definition (`#x`), is/isn't hidden (`_x`), and sits
    on the presence lattice (`Optionality`). `letBinding` is a distinct kind (a `let`
    binding is not a field and composes with nothing), kept as its own constructor so the
    field axes never have to encode a non-field. This makes the formerly-illegal
    combinations — `#x?` (optional definition), `#x!` (required definition), `_x?`
    (optional hidden) — first-class and merge per-axis. -/
inductive FieldClass where
  | field (isDefinition : Bool) (isHidden : Bool) (optionality : Optionality)
  | letBinding
deriving Repr, BEq, DecidableEq

namespace FieldClass

/-- A plain output field: not a definition, not hidden, present. -/
def regular : FieldClass := .field false false .regular
/-- An optional field (`x?`): not a definition, not hidden, optional. -/
def optional : FieldClass := .field false false .optional
/-- A required field (`x!`): not a definition, not hidden, required. -/
def required : FieldClass := .field false false .required
/-- A hidden field (`_x`): not a definition, hidden, present. -/
def hidden : FieldClass := .field false true .regular
/-- A definition field (`#x`): a definition, not hidden, present. -/
def definition : FieldClass := .field true false .regular

def isDefinition : FieldClass -> Bool
  | .field d _ _ => d
  | .letBinding => false

def isHidden : FieldClass -> Bool
  | .field _ h _ => h
  | .letBinding => false

def optionality : FieldClass -> Optionality
  | .field _ _ o => o
  | .letBinding => .regular

/-- A definition, hidden, or `let` field does not participate in closedness — its
    presence neither requires an allowing pattern nor is rejected by a closed struct.
    Orthogonal: a field that is *either* a definition or hidden ignores closedness,
    independent of its presence axis (so `#x?` and `_x?` both ignore it). -/
def ignoresClosedness : FieldClass -> Bool
  | .field d h _ => d || h
  | .letBinding => true

/-- A class that contributes a concrete value to manifest output. A non-definition,
    non-hidden field on the `regular` or `required` rung does (an `optional` field carries
    no settled value; any definition/hidden/`let` field is non-output regardless of
    presence). Used to decide whether a struct embedding a list conflicts (an output field
    present) or becomes the list (only non-output members). -/
def producesOutput : FieldClass -> Bool
  | .field true _ _ => false
  | .field _ true _ => false
  | .field false false .regular => true
  | .field false false .required => true
  | .field false false .optional => false
  | .letBinding => false

end FieldClass

structure BindingId where
  depth : Nat
  index : Nat
deriving Repr, BEq, DecidableEq

inductive BottomReason where
  | primitiveConflict (left right : Prim)
  | kindConflict (left right : Kind)
  | fieldConflict (label : String)
  | fieldNotAllowed (label : String)
  | fieldConstraint (label : String)
  | unresolvedReference (label : String)
  | unresolvedBinding (id : BindingId)
  | invalidIndex (index : Int)
  | indexOutOfRange (index : Int) (length : Nat)
  | boundConflict
  | divisionByZero
  | excludedValue (value : Prim)
deriving Repr, BEq, DecidableEq

/--
A comprehension clause. `forIn` binds a value variable (and optionally a key
variable) over an iterable source; `guard` admits its body only when the condition
holds. Clauses chain left-to-right: each `forIn` pushes one lexical scope frame
holding its loop variables, so later clauses and the body resolve against them.
-/
inductive Clause (Value : Type) where
  | forIn (key : Option String) (value : String) (source : Value)
  | guard (condition : Value)
deriving Repr, BEq

mutual

inductive Value where
  | top
  | bottom
  | bottomWith (reasons : List BottomReason)
  | prim (value : Prim)
  | kind (kind : Kind)
  | notPrim (value : Prim)
  | stringRegex (pattern : String)
  /-- A numeric bound constraint (`>=n`, `>n`, `<=n`, `<n`). `kind` selects the comparator,
      `bound` is an exact decimal limit (so `>0.5` is representable), and `domain` is the
      numeric domain it admits: a bare bound is `number` (admits both int and float, e.g.
      `>0 & 1.5` ⇒ `1.5`), narrowed to `int`/`float` by meeting with the matching kind
      (`int & >0` rejects floats). -/
  | boundConstraint (bound : DecimalValue) (kind : BoundKind) (domain : NumberDomain)
  | conj (constraints : List Value)
  | builtinCall (name : String) (args : List Value)
  | unary (op : UnaryOp) (value : Value)
  | binary (op : BinaryOp) (left right : Value)
  | ref (label : String)
  | refId (id : BindingId)
  | thisStruct
  | selector (base : Value) (label : String)
  | index (base key : Value)
  | disj (alternatives : List (Mark × Value))
  | struct (fields : List Field) (open_ : Bool)
  | structTail (fields : List Field) (tail : Value)
  | structPattern
      (fields : List Field)
      (labelPattern constraint : Value)
      (open_ : Bool)
  | structPatterns
      (fields : List Field)
      (patterns : List (Value × Value))
      (open_ : Bool)
  | list (items : List Value)
  | listTail (items : List Value) (tail : Value)
  /--
  A list value carrying selectable non-output declarations. CUE: a struct whose only
  members are non-regular (hidden/definition/optional/let) plus an embedded list *is*
  that list — it manifests as the list, indexes as the list, yet its declarations stay
  selectable (`v.#x`). With any regular/required field present the struct/list embed
  conflicts (bottom) instead. `tail` carries an open-list tail (`[...]` → `some .top`);
  `none` is a closed list. `decls` are the surviving non-output fields.
  -/
  | embeddedList (items : List Value) (tail : Option Value) (decls : List Field)
  | comprehension (clauses : List (Clause Value)) (body : Value)
  | structComp (fields : List Field) (comprehensions : List Value) (open_ : Bool)
  /--
  A list-context comprehension, stored as a list ITEM (in `.list`/`.listTail`). It shares
  the `Clause Value` chain with the struct-comprehension forms, but `body` is the
  brace-block VALUE yielded as one list ELEMENT per innermost iteration (not a struct of
  fields to merge). The enclosing list's eval arm flattens each `.listComprehension` item
  into the zero-or-more elements it produces, preserving source order so plain items and
  comprehensions interleave (`[1, for x in xs {x}, 2]`).
  -/
  | listComprehension (clauses : List (Clause Value)) (body : Value)
  | interpolation (parts : List Value)
  | dynamicField (label : Value) (fieldClass : FieldClass) (value : Value)
  /--
  A deferred body paired with the env it must resolve against. Selecting an imported
  definition (`pkg.#Def`) yields its *unevaluated* body tagged with the captured package
  env, so a later `meet` with use-site fields can splice them in BEFORE the body's
  self-references collapse, while the body's own (depth>0) cross-package refs still resolve
  against the captured env. `capturedEnv` is the full id-stack (`List (Nat × List Field)`,
  defeq to `Eval.Env`); the ids keep two independently-captured closures from falsely
  sharing, exactly as frame ids do for the memo. The general lazy-cross-frame fix that
  generalizes the same-package lazy-conjunction merge across the import boundary.
  -/
  | closure (capturedEnv : List (Nat × List Field)) (body : Value)

/-- A single struct member: its `label`, its `fieldClass` (regular/optional/required/
    hidden/definition/let), and its `value`. A named record replacing the former positional
    triple so projections are explicit and misindexing is impossible. Defined mutually with
    `Value` because `Value`'s struct-bearing constructors carry `List Field`. -/
structure Field where
  label : String
  fieldClass : FieldClass
  value : Value

end

deriving instance Repr, BEq for Value, Field

namespace Field

def ignoresClosedness (field : Field) : Bool :=
  FieldClass.ignoresClosedness field.fieldClass

def regular (label : String) (value : Value) : Field :=
  { label, fieldClass := .regular, value }

end Field

/-- A single `import "path"` or `alias "path"` clause retained from a parsed file. The
    `path` is the verbatim import string (e.g. `"example.com/defs"`); `alias` carries the
    optional local rename, `none` when the package binds under its own declared name. -/
structure Import where
  path : String
  alias : Option String
deriving Repr, BEq, DecidableEq

/-- The full result of parsing one `.cue` file: its top-level value (struct body), the
    declared `package` name (`none` when the file omits a package clause), and the imports
    it pulls in. Carries everything the loader needs to resolve and bind imports without
    re-parsing. -/
structure ParsedFile where
  value : Value
  packageName : Option String
  imports : List Import
deriving Repr, BEq

inductive RegexAtom where
  | literal (value : Char)
  | any
  | charClass (ranges : List (Char × Char)) (negated : Bool)
deriving Repr, BEq

def charInRegexRange (lower upper value : Char) : Bool :=
  lower.toNat <= value.toNat && value.toNat <= upper.toNat

def regexClassMatches (ranges : List (Char × Char)) (value : Char) : Bool :=
  ranges.any fun range => charInRegexRange range.fst range.snd value

def regexDigitRanges : List (Char × Char) :=
  [('0', '9')]

def regexWordRanges : List (Char × Char) :=
  [('0', '9'), ('A', 'Z'), ('_', '_'), ('a', 'z')]

def regexSpaceRanges : List (Char × Char) :=
  [(' ', ' '), ('\t', '\t'), ('\n', '\n'), ('\r', '\r')]

def regexDigitValue? (value : Char) : Option Nat :=
  if charInRegexRange '0' '9' value then
    some (value.toNat - '0'.toNat)
  else
    none

def parseRegexNatDigits : List Char -> Nat -> Bool -> Option (Nat × List Char)
  | [], _, _ => none
  | value :: rest, count, seen =>
      match regexDigitValue? value with
      | some digit => parseRegexNatDigits rest (count * 10 + digit) true
      | none => if seen then some (count, value :: rest) else none

def parseRegexRepeat : List Char -> Option (Nat × Nat × List Char)
  | '{' :: rest =>
      match parseRegexNatDigits rest 0 false with
      | some (minimum, '}' :: rest) => some (minimum, minimum, rest)
      | some (minimum, ',' :: rest) =>
          match parseRegexNatDigits rest 0 false with
          | some (maximum, '}' :: rest) =>
              if minimum <= maximum then some (minimum, maximum, rest) else none
          | _ => none
      | _ => none
  | _ => none

namespace RegexAtom

def matchesChar : RegexAtom -> Char -> Bool
  | .literal expected, value => expected == value
  | .any, _ => true
  | .charClass ranges false, value => regexClassMatches ranges value
  | .charClass ranges true, value => !regexClassMatches ranges value

end RegexAtom

def parseRegexClassRanges : List Char -> List (Char × Char) -> Option (List (Char × Char) × List Char)
  | [], _ => none
  | ']' :: rest, ranges => some (ranges.reverse, rest)
  | lower :: '-' :: upper :: rest, ranges => parseRegexClassRanges rest ((lower, upper) :: ranges)
  | value :: rest, ranges => parseRegexClassRanges rest ((value, value) :: ranges)

def parseRegexAtom : List Char -> Option (RegexAtom × List Char)
  | [] => none
  | '\\' :: 'd' :: rest => some (.charClass regexDigitRanges false, rest)
  | '\\' :: 'D' :: rest => some (.charClass regexDigitRanges true, rest)
  | '\\' :: 'w' :: rest => some (.charClass regexWordRanges false, rest)
  | '\\' :: 'W' :: rest => some (.charClass regexWordRanges true, rest)
  | '\\' :: 's' :: rest => some (.charClass regexSpaceRanges false, rest)
  | '\\' :: 'S' :: rest => some (.charClass regexSpaceRanges true, rest)
  | '\\' :: value :: rest => some (.literal value, rest)
  | ['\\'] => some (.literal '\\', [])
  | '[' :: '^' :: rest =>
      match parseRegexClassRanges rest [] with
      | some (ranges, rest) => some (.charClass ranges true, rest)
      | none => some (.literal '[', '^' :: rest)
  | '[' :: rest =>
      match parseRegexClassRanges rest [] with
      | some (ranges, rest) => some (.charClass ranges false, rest)
      | none => some (.literal '[', rest)
  | '.' :: rest => some (.any, rest)
  | value :: rest => some (.literal value, rest)

mutual
  def regexMatchHereWithFuel : Nat -> Bool -> List Char -> List Char -> Bool
    | 0, _, _, _ => false
    | fuel + 1, anchoredEnd, pattern, value =>
        match parseRegexAtom pattern with
        | none => !anchoredEnd || value.isEmpty
        | some (atom, '*' :: rest) => regexMatchStarWithFuel fuel anchoredEnd atom rest value
        | some (atom, '?' :: rest) =>
            regexMatchHereWithFuel fuel anchoredEnd rest value
              || match value with
                 | [] => false
                 | current :: remaining =>
                     atom.matchesChar current
                       && regexMatchHereWithFuel fuel anchoredEnd rest remaining
        | some (atom, '+' :: rest) =>
            match value with
            | [] => false
            | current :: remaining =>
                atom.matchesChar current
                  && regexMatchStarWithFuel fuel anchoredEnd atom rest remaining
        | some (atom, rest) =>
            match parseRegexRepeat rest with
            | some (minimum, maximum, rest) =>
                regexMatchRepeatRangeWithFuel fuel anchoredEnd atom minimum maximum rest value
            | none =>
                match value with
                | [] => false
                | current :: remaining =>
                    atom.matchesChar current
                      && regexMatchHereWithFuel fuel anchoredEnd rest remaining

  def regexMatchStarWithFuel : Nat -> Bool -> RegexAtom -> List Char -> List Char -> Bool
    | 0, _, _, _, _ => false
    | fuel + 1, anchoredEnd, atom, rest, value =>
        regexMatchHereWithFuel fuel anchoredEnd rest value
          || match value with
             | [] => false
             | current :: remaining =>
                 atom.matchesChar current
                   && regexMatchStarWithFuel fuel anchoredEnd atom rest remaining

  def regexMatchAtMostWithFuel : Nat -> Bool -> RegexAtom -> Nat -> List Char -> List Char -> Bool
    | 0, _, _, _, _, _ => false
    | fuel + 1, anchoredEnd, _, 0, rest, value =>
        regexMatchHereWithFuel fuel anchoredEnd rest value
    | fuel + 1, anchoredEnd, atom, count + 1, rest, value =>
        regexMatchHereWithFuel fuel anchoredEnd rest value
          || match value with
             | [] => false
             | current :: remaining =>
                 atom.matchesChar current
                   && regexMatchAtMostWithFuel fuel anchoredEnd atom count rest remaining

  def regexMatchRepeatRangeWithFuel : Nat -> Bool -> RegexAtom -> Nat -> Nat -> List Char -> List Char -> Bool
    | 0, _, _, _, _, _, _ => false
    | fuel + 1, anchoredEnd, atom, 0, maximum, rest, value =>
        regexMatchAtMostWithFuel fuel anchoredEnd atom maximum rest value
    | fuel + 1, anchoredEnd, atom, minimum + 1, maximum + 1, rest, value =>
        match value with
        | [] => false
        | current :: remaining =>
            atom.matchesChar current
              && regexMatchRepeatRangeWithFuel fuel anchoredEnd atom minimum maximum rest remaining
    | _, _, _, _ + 1, 0, _, _ => false

  def regexMatchAnywhereWithFuel : Nat -> Bool -> List Char -> List Char -> Bool
    | 0, _, _, _ => false
    | fuel + 1, anchoredEnd, pattern, value =>
        regexMatchHereWithFuel fuel anchoredEnd pattern value
          || match value with
             | [] => false
             | _ :: remaining => regexMatchAnywhereWithFuel fuel anchoredEnd pattern remaining
end

def splitRegexAlternativesWithState :
    List Char -> Bool -> List Char -> List (List Char) -> List (List Char)
  | [], _, current, alternatives => (current.reverse :: alternatives).reverse
  | '\\' :: value :: rest, inClass, current, alternatives =>
      splitRegexAlternativesWithState rest inClass (value :: '\\' :: current) alternatives
  | ['\\'], inClass, current, alternatives =>
      splitRegexAlternativesWithState [] inClass ('\\' :: current) alternatives
  | '[' :: rest, false, current, alternatives =>
      splitRegexAlternativesWithState rest true ('[' :: current) alternatives
  | ']' :: rest, true, current, alternatives =>
      splitRegexAlternativesWithState rest false (']' :: current) alternatives
  | '|' :: rest, false, current, alternatives =>
      splitRegexAlternativesWithState rest false [] (current.reverse :: alternatives)
  | value :: rest, inClass, current, alternatives =>
      splitRegexAlternativesWithState rest inClass (value :: current) alternatives

def splitRegexAlternativeChars (pattern : List Char) : List (List Char) :=
  splitRegexAlternativesWithState pattern false [] []

def splitRegexAlternatives (pattern : String) : List String :=
  (splitRegexAlternativeChars pattern.toList).map String.ofList

def parseRegexGroupBodyWithState : List Char -> Bool -> List Char -> Option (List Char × List Char)
  | [], _, _ => none
  | '\\' :: value :: rest, inClass, current =>
      parseRegexGroupBodyWithState rest inClass (value :: '\\' :: current)
  | ['\\'], _, _ => none
  | '[' :: rest, false, current =>
      parseRegexGroupBodyWithState rest true ('[' :: current)
  | ']' :: rest, true, current =>
      parseRegexGroupBodyWithState rest false (']' :: current)
  | ')' :: rest, false, current => some (current.reverse, rest)
  | value :: rest, inClass, current =>
      parseRegexGroupBodyWithState rest inClass (value :: current)

def findFirstRegexGroupWithState :
    List Char -> Bool -> List Char -> Option (List Char × List Char × List Char)
  | [], _, _ => none
  | '\\' :: value :: rest, inClass, leading =>
      findFirstRegexGroupWithState rest inClass (value :: '\\' :: leading)
  | ['\\'], inClass, leading =>
      findFirstRegexGroupWithState [] inClass ('\\' :: leading)
  | '[' :: rest, false, leading =>
      findFirstRegexGroupWithState rest true ('[' :: leading)
  | ']' :: rest, true, leading =>
      findFirstRegexGroupWithState rest false (']' :: leading)
  | '(' :: rest, false, leading =>
      match parseRegexGroupBodyWithState rest false [] with
      | some (body, suffix) => some (leading.reverse, body, suffix)
      | none => findFirstRegexGroupWithState rest false ('(' :: leading)
  | value :: rest, inClass, leading =>
      findFirstRegexGroupWithState rest inClass (value :: leading)

def expandRegexGroupAlternatives : List Char -> List (List Char) -> List Char -> List String
  | _, [], _ => []
  | leading, alternative :: alternatives, suffix =>
      String.ofList (leading ++ alternative ++ suffix)
        :: expandRegexGroupAlternatives leading alternatives suffix

def expandFirstRegexGroup (pattern : String) : Option (List String) :=
  match findFirstRegexGroupWithState pattern.toList false [] with
  | none => none
  | some (leading, body, suffix) =>
      some (expandRegexGroupAlternatives leading (splitRegexAlternativeChars body) suffix)

def stringRegexAlternativeMatches (pattern value : String) : Bool :=
  let anchoredStart := pattern.startsWith "^"
  let withoutStart := if anchoredStart then (pattern.drop 1).copy else pattern
  let anchoredEnd := withoutStart.endsWith "$"
  let body := if anchoredEnd then (withoutStart.dropEnd 1).copy else withoutStart
  let patternChars := body.toList
  let valueChars := value.toList
  let fuel := ((patternChars.length + 1) * (valueChars.length + 1) * 4) + 10
  if anchoredStart then
    regexMatchHereWithFuel fuel anchoredEnd patternChars valueChars
  else
    regexMatchAnywhereWithFuel fuel anchoredEnd patternChars valueChars

def stringRegexMatches (pattern value : String) : Bool :=
  let alternatives :=
    match expandFirstRegexGroup pattern with
    | some alternatives => alternatives
    | none => splitRegexAlternatives pattern
  alternatives.any fun alternative => stringRegexAlternativeMatches alternative value

end Kue
