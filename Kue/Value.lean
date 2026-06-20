import Kue.Regex

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
  /-- A whole imported package bound into a struct (`Module.bindImports`). A peer kind
      of `letBinding`, NOT a point in the `(isDefinition, isHidden, optionality)` cube:
      it reads identically to `.hidden` at every consumer (hidden, ignores closedness,
      non-output) so it is behaviorally inert everywhere EXCEPT the two output-reachability
      sites that must keep an unreferenced import binding lazy while a real in-file hidden
      field gets cue's strict treatment (`Normalize`, `Manifest`). -/
  | importBinding
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
  | .importBinding => false

def isHidden : FieldClass -> Bool
  | .field _ h _ => h
  | .letBinding => false
  | .importBinding => true

def optionality : FieldClass -> Optionality
  | .field _ _ o => o
  | .letBinding => .regular
  | .importBinding => .regular

/-- A definition, hidden, or `let` field does not participate in closedness — its
    presence neither requires an allowing pattern nor is rejected by a closed struct.
    Orthogonal: a field that is *either* a definition or hidden ignores closedness,
    independent of its presence axis (so `#x?` and `_x?` both ignore it). -/
def ignoresClosedness : FieldClass -> Bool
  | .field d h _ => d || h
  | .letBinding => true
  | .importBinding => true

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
  | .importBinding => false

end FieldClass

/-- The openness of a struct, as three mutually exclusive states (the B2 target
    representation, replacing the conflated `open_ : Bool` + `hasTail : Bool` pair).
    `regularOpen` is a regular struct with no `...` tail — open by default. `defClosed`
    is a no-`...` definition body — closed. `defOpenViaTail` is a struct with an explicit
    `...` tail — open and tail-bearing. The three-way split makes the former illegal
    states (a closed struct that nonetheless has a `...`, or the ambiguous open-with-tail
    vs closed-with-tail pair) unrepresentable: tail presence is in lockstep with
    `defOpenViaTail`. -/
inductive StructOpenness where
  | regularOpen
  | defClosed
  | defOpenViaTail
deriving Repr, BEq, DecidableEq

namespace StructOpenness

/-- A struct is open (admits extra fields) unless it is a closed definition body. -/
def isOpen : StructOpenness -> Bool
  | .regularOpen => true
  | .defClosed => false
  | .defOpenViaTail => true

/-- Map the legacy `open_ : Bool` of a no-`...` struct onto the three-state openness:
    an open no-`...` struct is `regularOpen`, a closed one is `defClosed`. The `...`-tailed
    form is `defOpenViaTail`, never produced by this map (it has no `open_`-only encoding). -/
def ofBool : Bool -> StructOpenness
  | true => .regularOpen
  | false => .defClosed

/-- The def-body openness derivation: a definition is closed by default, and an explicit
    `...` (`defOpenViaTail`) keeps it open. A `regularOpen` no-`...` body CLOSES (the parser's
    open-by-default is irrelevant once it is a def body); a `defOpenViaTail` body stays open.
    Total over all three states (`defClosed` is a fixed point); replaces the legacy
    `open_ := hasTail` rule in `normalizeDefinitionValueWithFuel`. -/
def closeDefBody : StructOpenness -> StructOpenness
  | .regularOpen => .defClosed
  | .defClosed => .defClosed
  | .defOpenViaTail => .defOpenViaTail

/-- Meet on the openness lattice: closed dominates (a closed conjunct closes the meet),
    `defOpenViaTail` meeting any open stays tail-bearing-open, and two regular opens stay
    open. Matches the `meetOpenness` rule the B2.4 single meet arm will use. -/
def meet : StructOpenness -> StructOpenness -> StructOpenness
  | .defClosed, _ => .defClosed
  | _, .defClosed => .defClosed
  | .defOpenViaTail, _ => .defOpenViaTail
  | _, .defOpenViaTail => .defOpenViaTail
  | .regularOpen, .regularOpen => .regularOpen

end StructOpenness

structure BindingId where
  depth : Nat
  index : Nat
deriving Repr, BEq, DecidableEq

/-- The concrete-but-non-`bool` type a comprehension `if` guard resolved to. CUE requires a
    guard to be of type `bool`; a concrete value of any other type is a type error
    (`cannot use "x" (type string) as type bool`). Scalars carry their `Kind`; `struct`/`list`
    have no scalar `Kind`, so they get their own arms. Spec basis: the `if` clause's expression
    "must be of type bool". -/
inductive NonBoolGuardType where
  | scalar (kind : Kind)
  | struct
  | list
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
  | unsupportedBuiltin (name : String)
  /-- A concrete regex pattern that RE2/cue reject as invalid (unbalanced groups, dangling
      escapes) or that Kue defers (flags, named captures). Carries the offending pattern and
      the structured parse error. Raised at every `=~`/`!~`/pattern-meet/`regexp.Match` site
      so an invalid pattern bottoms instead of silently matching false. -/
  | invalidRegex (pattern : String) (error : RegexParseError)
  /-- A structural cycle: a definition body whose field re-enters the SAME def frame through a
      struct layer (`#L: {next: #L}`, or mutual `#A`/`#B`), detected dynamically when forcing the
      def closure re-enters an in-progress force frame. The CUE spec mandates this be an error
      ("a node is valid if any of its conjuncts is not cyclic") — distinct from a bare REFERENCE
      cycle (`x: x`), which resolves to `_`. Raised on the def-body force path
      (`forceClosureWithConjunct`) when an ancestor force frame repeats. -/
  | structuralCycle
  /-- A comprehension `if` guard whose condition resolved to a CONCRETE value of non-`bool`
      type (`if "x" {…}`, `if 3 {…}`, `if {…} {…}`). The CUE spec requires the guard to be
      `bool`, so a concrete non-bool is a type error (cue: `cannot use … as type bool`), NOT a
      silent drop. Distinct from an INCOMPLETE guard (a ref/kind/unresolved disjunction), which
      DEFERS (keeps the comprehension residual) rather than erroring. Carries the offending
      type for provenance. -/
  | nonBoolGuard (type : NonBoolGuardType)
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
  /--
  The B2 normalized struct (target representation). Collapses the four legacy forms
  (`struct`/`structTail`/`structPattern`/`structPatterns`) into one: `fields` are the
  named members, `openness` is the three-state `StructOpenness`, `tail` is the optional
  `...` tail value (present iff `openness = .defOpenViaTail`, enforced by `mkStruct`),
  `patterns` are the `[pattern]: constraint` pairs (orthogonal to `tail`, which the old
  type could not carry together — the root of the missing `structPattern×structTail` meet
  arm), and `closingPatterns` are the label-predicates that participate in the CLOSED
  allowed-set (SC-1). A pattern closes iff it was declared by a closed struct: `#D: {a:int,
  [string]:int}` closes via `[string]` (so `#D & {z:9}` admits `z`), but meeting a closed
  `#C` with an OPEN pattern struct `P` keeps `P`'s pattern as a value-constraint (in
  `patterns`) WITHOUT adding it to the allowed-set (so `#C & P & {z:9}` still rejects `z`).
  `closingPatterns` is a subset of `patterns`' label-predicates; the meet threads it so an
  open conjunct's pattern never re-opens a closed result. Construction goes through the
  `mkStruct` smart constructor only. NOT produced by any eval/parse path in B2.1. -/
  | struct
      (fields : List Field)
      (openness : StructOpenness)
      (tail : Option Value)
      (patterns : List (Value × Value))
      (closingPatterns : List Value)
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
  /--
  A pre-eval struct carrying comprehensions/embeddings (`{a, if c {…}, #Base}`). `openness` is
  the three-state `StructOpenness` (B2b: replaces the legacy `(open_, hasTail)` two-bool). Unlike
  the unified `struct`, `structComp` carries NO tail VALUE — its `...` is a bare flag, so
  `defOpenViaTail` here means "open via a bare `...`, no stored tail value" (coherent: there is no
  `tail` field for the coherence invariant to relate it to). At parse a regular struct is open
  (`regularOpen` with no `...`, `defOpenViaTail` with `...`); the eager eval arm honors
  `openness.isOpen`. `normalizeDefinitionValueWithFuel` derives the def-body openness via
  `StructOpenness.closeDefBody` (a no-`...` body closes, a `...` body stays open) — the def is
  closed by default and `...` opens it. A distinct pre-eval ctor (NOT folded into the unified
  meet-bearing `struct`): it NEVER reaches meet — the eager arm expands it into `struct` first.
  -/
  | structComp (fields : List Field) (comprehensions : List Value) (openness : StructOpenness)
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

/-- The single authority for comprehension clause-chain frame-depth threading. A `forIn`
    source is handed back at the current depth and pushes one frame for the rest of the chain
    and the body; a `guard` condition is handed back at the current depth and pushes none; the
    body is handed back at the accumulated post-chain depth. Mirrors `resolveClausesWithFuel`'s
    `clauseLoopFrame :: scopes` push. Generic over the accumulator `α` with an `append` so the
    clause walkers instantiate it as `Bool` (`‖`), `List` (`++`), or a depth fold. The chain
    terminates in `onBody`, not an identity element — there is no empty case to fill, so the fold
    needs no monoid unit. Pure, total (structural on the clause list), `Value`-non-recursive: it
    threads depth only and defers each piece to the caller's `onSource`/`onGuard`/`onBody`. A
    walker descending a clause chain MUST route through this to get the body depth, so the
    `+1-per-forIn`/`+0-per-guard` rule lives in exactly one place and cannot be re-derived
    inconsistently. -/
def descendClauses {α : Type}
    (append : α → α → α)
    (onSource onGuard : Nat → Value → α)
    (onBody : Nat → α)
    (depth : Nat) : List (Clause Value) → α
  | [] => onBody depth
  | .forIn _ _ source :: rest =>
      append (onSource depth source)
        (descendClauses append onSource onGuard onBody (depth + 1) rest)
  | .guard condition :: rest =>
      append (onGuard depth condition)
        (descendClauses append onSource onGuard onBody depth rest)

/-- The frame depth a clause chain accumulates from `start`: `+1` per `forIn`, `+0` per `guard`.
    Recovered from `descendClauses` (identity body-handler returns the accumulated depth) so the
    body-depth shift and the per-clause threading derive from the SAME fold — replacing the former
    standalone `clauseFrameShift` and erasing the two-encodings-in-one-walker hazard. -/
def clauseChainDepth (start : Nat) (clauses : List (Clause Value)) : Nat :=
  descendClauses (α := Nat) (fun _ later => later) (fun _ _ => start) (fun _ _ => start)
    (fun reached => reached) start clauses

namespace Field

def ignoresClosedness (field : Field) : Bool :=
  FieldClass.ignoresClosedness field.fieldClass

/-- A regular OUTPUT field: not a `let` binding and not hidden/definitional. These are the only
    fields that participate in a use-site narrowing splice (the embed already declares them; they
    merge by label). The complement of `letBinding ∪ ignoresClosedness`. -/
def isRegularOutput (field : Field) : Bool :=
  field.fieldClass != .letBinding && !field.ignoresClosedness

def regular (label : String) (value : Value) : Field :=
  { label, fieldClass := .regular, value }

end Field

/-- Drop duplicate `(labelPattern, constraint)` pairs, keeping the first occurrence so
    order is stable and meet over patterns is confluent. Equality is structural `BEq` on
    the pair (the same equality `dedupAlternatives` uses for disjunction arms). -/
def dedupPatterns (patterns : List (Value × Value)) : List (Value × Value) :=
  patterns.foldr
    (fun pattern kept => if kept.any (· == pattern) then kept else pattern :: kept)
    []

/-- Drop duplicate label-predicates, keeping the first occurrence. Structural `BEq`, the
    same shape as `dedupPatterns`; used to canonicalize a struct's `closingPatterns`. -/
def dedupValues (values : List Value) : List Value :=
  values.foldr
    (fun value kept => if kept.any (· == value) then kept else value :: kept)
    []

/-- Coerce a `(tail, openness)` pair into the one coherent shape the `struct`
    representation admits, erasing the never-constructable combinations
    (`Phase-A` finding item-8 / the B2 `open_`×`hasTail` nonsense state):

    * a `some` tail ⟹ `defOpenViaTail` (a struct WITH a `...` is open-and-tail-bearing),
      regardless of the openness the caller passed;
    * `defOpenViaTail` with NO tail ⟹ supply the bare-`...` default `some .top`;
    * any other openness (`regularOpen` / `defClosed`) forces `tail = none`.

    Post-condition (pinned in LatticeTests): `tail = some _ ↔ openness = .defOpenViaTail`. -/
def coherentTail : Option Value -> StructOpenness -> Option Value × StructOpenness
  | some tail, _ => (some tail, .defOpenViaTail)
  | none, .defOpenViaTail => (some .top, .defOpenViaTail)
  | none, openness => (none, openness)

/-- The B2 smart constructor for the normalized struct (`Value.struct`) — the ONLY
    sanctioned way to build the form. Enforces the representation invariants so illegal
    states are unconstructable:

    * **patterns canonicalized**: deduplicated (`dedupPatterns`), so meet over patterns is
      confluent (this subsumes `patternStructValue`'s length dispatch — one constructor for
      0/1/n patterns);
    * **tail/openness coherence** (`coherentTail`): `tail = some _ ↔ openness =
      .defOpenViaTail`, so the incoherent pairs (a `defOpenViaTail` with no tail; a tail
      with `regularOpen`/`defClosed`) are normalized away rather than represented.

    `closingPatterns` (SC-1) defaults to the struct's own pattern label-predicates WHEN the
    struct is closed (a closed def `#D: {[string]:int}` closes via `[string]`), and to `[]`
    when it is open — an open struct closes nothing, so it carries no closing patterns. The
    meet arms pass an explicit set when a closed result absorbs an OPEN conjunct's pattern,
    which must stay a value-constraint without re-opening the closed allowed-set.
    Deduplicated to track `patterns`.

    Field ordering is the caller's responsibility (callers run `canonicalizeFields` before
    constructing, exactly as they do today for `patternStructValue` — `canonicalizeFields`
    lives in `Eval`, downstream of this module, so it cannot be called here). Lives in
    `Value` so every construction site (`Parse`/`Normalize`/`Resolve`/`Eval`/`Lattice`) can
    reach the single sanctioned constructor without a Lattice dependency. -/
def mkStruct
    (fields : List Field)
    (openness : StructOpenness)
    (tail : Option Value)
    (patterns : List (Value × Value))
    (closingPatterns : List Value := if openness.isOpen then [] else patterns.map Prod.fst) :
    Value :=
  let (coherentTailValue, coherentOpenness) := coherentTail tail openness
  -- ENFORCE the SC-1 invariant (not merely default it): an OPEN struct closes nothing, so its
  -- `closingPatterns` is `[]` regardless of what the caller passed. Keying on the COHERENT
  -- openness (a `some tail` forces `defOpenViaTail` = open) makes the nonsense triple
  -- (closingPatterns non-empty + open) unconstructable through the only sanctioned constructor.
  let coherentClosing := if coherentOpenness.isOpen then [] else closingPatterns
  .struct fields coherentOpenness coherentTailValue (dedupPatterns patterns)
    (dedupValues coherentClosing)

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

end Kue
