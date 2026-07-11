import Kue.Builtin
import Kue.Decimal
import Kue.Regex

/-!
# Scalar operations

Pure scalar algebra for the evaluator: arithmetic (`evalAdd`/`evalSub`/`evalMul`/`evalDiv`),
comparison (`evalEq`/`evalNe`/`evalPrimitiveOrdering`), regex-match, boolean, and unary ops,
plus the `evalUnary`/`evalBinary` dispatchers and the disjunction-operand resolution
(`collapseDefaultDisjunction`/`resolveOperand`/`distributeUnary`/`distributeBinary`).

These functions take already-evaluated `Value` operands and never call back into the
recursive evaluator (`evalValueWithFuel`), which is what lets them sit below `Eval` as a
self-contained module. The integer-keyword ops (`div`/`mod`/`quo`/`rem`) reuse the builtin
implementations from `Builtin`.
-/

namespace Kue

/-- Classify a binary-arithmetic operand into its domain status, replacing the four ops'
    `_, _ => .binary` catch-all with a spec-faithful three-way decision. The CUE spec closes
    `+ - * /` over int/decimal (and `+`/`*` also over string/bytes); operand handling splits:
    - `prim` — a primitive: the existing `prim,prim` arms decide (a number/string/bytes match,
      or a same-arm mismatch like `1 + "x"` → `.bottom`). Returned so those arms run unchanged.
    - `concreteNonArith` — a fully-evaluated NON-prim shape (`.struct`/`.list`/`.listTail`/
      `.embeddedList`): outside EVERY arithmetic operator's domain ⇒ a TYPE ERROR (cue
      hard-errors, e.g. `Addition of lists is superseded by list.Concat`). Carries the offending
      type for the `nonArithmeticOperand` reason.
    - `incomplete` — an unresolved/abstract form (ref, kind, bound, unresolved disjunction, …):
      it may still resolve to a number, so the binary DEFERS (the `.binary` residual). This is
      the D#1b/c discipline (concrete-wrong → bottom; incomplete → defer), mirroring
      `classifyGuard`; enumerated with no catch-all so a new ctor forces a decision here. -/
inductive ArithOperandClass where
  | prim
  | concreteNonArith (type : ConcreteTypeName)
  | incomplete
deriving BEq

def classifyArithOperand : Value -> ArithOperandClass
  | .prim _ => .prim
  | .struct _ _ _ [] _ => .concreteNonArith .struct
  | .list _ => .concreteNonArith .list
  | .listTail _ _ => .concreteNonArith .list
  | .embeddedList _ _ _ => .concreteNonArith .list
  -- A scalar carrier classifies as its inner (terminal) scalar — `resolveOperand` unwraps it
  -- before arith, so this is the total fallback (recurses once onto a non-carrier scalar).
  | .embeddedScalar scalar _ => classifyArithOperand scalar
  -- Unresolved / abstract forms → DEFER (keep the binary residual); a pattern-bearing struct is a
  -- residual constraint, not yet concrete, so it too defers — the conservative choice, matching
  -- `classifyGuard`.
  | .struct _ _ _ (_ :: _) _ => .incomplete
  | .structComp _ _ _ => .incomplete
  | .top => .incomplete
  | .kind _ => .incomplete
  | .notPrim _ => .incomplete
  | .stringRegex _ => .incomplete
  | .boundConstraint _ _ _ => .incomplete
  | .lengthConstraint _ _ _ => .incomplete
  | .uniqueItems => .incomplete
  | .conj _ => .incomplete
  | .builtinCall _ _ => .incomplete
  | .unary _ _ => .incomplete
  | .binary _ _ _ => .incomplete
  | .ref _ => .incomplete
  | .refId _ => .incomplete
  | .thisStruct => .incomplete
  | .selector _ _ => .incomplete
  | .index _ _ => .incomplete
  | .disj _ => .incomplete
  | .comprehension _ _ => .incomplete
  | .listComprehension _ _ => .incomplete
  | .interpolation _ => .incomplete
  | .dynamicField _ _ _ => .incomplete
  | .closure _ _ => .incomplete
  -- Bottoms never reach here: every op's `.bottom`/`.bottomWith` arms precede the split.
  | .bottom => .incomplete
  | .bottomWith _ => .incomplete

/-- The shared spec gate for the four arithmetic ops, applied once both bottom arms have run.
    A type error fires ONLY when the ill-typed shape is DECIDABLE now: a concrete non-arithmetic
    operand whose partner is ALSO concrete (a `prim` or another concrete non-arith). If EITHER
    operand is incomplete, the whole expression defers (the `.binary` residual) — it may resolve
    to a valid operation once the incomplete side concretizes, exactly as cue holds `[1] + x`
    while `x: int` is abstract and errors only after `x` resolves. This is the D#1b/c discipline:
    concrete-wrong → bottom, anything-incomplete → defer. The `prim,prim` case is handled by each
    op before calling this, so a `.prim` operand here is always paired with a non-prim.

    `incomplete` is checked first so a concrete-nonarith × incomplete pair DEFERS, not errors. -/
def arithmeticDomainResult (op : BinaryOp) (left right : Value) : Value :=
  match classifyArithOperand left, classifyArithOperand right with
  | .incomplete, _ => .binary op left right
  | _, .incomplete => .binary op left right
  | .concreteNonArith ty, _ => .bottomWith [.nonArithmeticOperand op ty]
  | _, .concreteNonArith ty => .bottomWith [.nonArithmeticOperand op ty]
  | _, _ => .binary op left right

/-- String/bytes `*` int = repetition (`"ab" * 2 = "abab"`, `'ab' * 2 = 'abab'`), the cue
    behavior superseding `strings.Repeat`/`bytes.Repeat`. A negative count is a type error
    (cue: `cannot convert negative number to uint64`); a zero count yields the empty value. -/
def evalRepeatString (text : String) (count : Int) : Value :=
  if count < 0 then .bottomWith [.negativeRepeatCount count]
  else .prim (.string (String.join (List.replicate count.toNat text)))

/-- Byte-array analog of `evalRepeatString`: `'ab' * 2 = 'abab'` by array concatenation. -/
def evalRepeatBytes (bytes : Array UInt8) (count : Int) : Value :=
  if count < 0 then .bottomWith [.negativeRepeatCount count]
  else .prim (.bytes (List.replicate count.toNat bytes.toList).flatten.toArray)

def evalAdd (left right : Value) : Value :=
  match left, right with
  | .prim (.int left), .prim (.int right) => .prim (.int (left + right))
  | .prim (.string left), .prim (.string right) => .prim (.string (left ++ right))
  | .prim (.bytes left), .prim (.bytes right) => .prim (.bytes (left ++ right))
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
  | .prim left, .prim right =>
      match evalDecimalBinary? addDecimalValues left right with
      | some value => .prim value
      | none => .bottom
  | _, _ => arithmeticDomainResult .add left right

def evalSub (left right : Value) : Value :=
  match left, right with
  | .prim (.int left), .prim (.int right) => .prim (.int (left - right))
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
  | .prim left, .prim right =>
      match evalDecimalBinary? subDecimalValues left right with
      | some value => .prim value
      | none => .bottom
  | _, _ => arithmeticDomainResult .sub left right

def evalMul (left right : Value) : Value :=
  match left, right with
  | .prim (.int left), .prim (.int right) => .prim (.int (left * right))
  -- string/bytes `*` int = repetition (either operand order); cue supersedes strings/bytes.Repeat.
  | .prim (.string text), .prim (.int count) => evalRepeatString text count
  | .prim (.int count), .prim (.string text) => evalRepeatString text count
  | .prim (.bytes text), .prim (.int count) => evalRepeatBytes text count
  | .prim (.int count), .prim (.bytes text) => evalRepeatBytes text count
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
  | .prim left, .prim right =>
      match evalDecimalMultiply? left right with
      | some value => .prim value
      | none => .bottom
  | _, _ => arithmeticDomainResult .mul left right

def evalDiv (left right : Value) : Value :=
  match left, right with
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
  | .prim left, .prim right =>
      match evalDecimalDivide? left right with
      | .ok text => .prim (mkFloatText text)
      | .divByZero => .bottomWith [.divisionByZero]
      | .nonNumeric => .bottom
  | _, _ => arithmeticDomainResult .div left right

/-- Collapse a value that is a DEFAULT disjunction to its default, identity on every other
    value. `resolveDisjDefault?` picks a unique marked default (or a sole live regular
    alternative) and leaves an AMBIGUOUS disjunction (no default, ≥2 live arms) untouched, so the
    caller's classifier/op still defers it. This single projection is shared by every site that
    forces a default in a concrete context — the dyn-label key, the `if` guard, the scalar/unary
    operand, the embedded-disjunction arm — each of which wraps it with its own context rationale
    below. -/
def collapseDefaultDisjunction : Value -> Value
  | .disj alternatives => (resolveDisjDefault? alternatives).getD (.disj alternatives)
  -- A shallow projection: only a default disjunction collapses; every other value is the
  -- identity. Enumerated (not `other => other`) so a NEW `Value` constructor forces a
  -- decision here — collapse-like or pass-through — rather than being silently identity.
  | value@(.top) => value
  | value@(.bottom) => value
  | value@(.bottomWith _) => value
  | value@(.prim _) => value
  | value@(.kind _) => value
  | value@(.notPrim _) => value
  | value@(.stringRegex _) => value
  | value@(.boundConstraint _ _ _) => value
  | value@(.lengthConstraint _ _ _) => value
  | value@(.uniqueItems) => value
  | value@(.conj _) => value
  | value@(.builtinCall _ _) => value
  | value@(.unary _ _) => value
  | value@(.binary _ _ _) => value
  | value@(.ref _) => value
  | value@(.refId _) => value
  | value@(.thisStruct) => value
  | value@(.selector _ _) => value
  | value@(.index _ _) => value
  | value@(.struct _ _ _ _ _) => value
  | value@(.list _) => value
  | value@(.listTail _ _) => value
  | value@(.embeddedList _ _ _) => value
  | value@(.embeddedScalar _ _) => value
  | value@(.comprehension _ _) => value
  | value@(.structComp _ _ _) => value
  | value@(.listComprehension _ _) => value
  | value@(.interpolation _) => value
  | value@(.dynamicField _ _ _) => value
  | value@(.closure _ _) => value

/-- Count a struct's REGULAR OUTPUT fields (`.field false false .regular`) — the only ones
    CUE compares for `==`. Hidden/definition/`let`/import/optional/required fields are excluded
    (mirrors `Manifest`'s output-field filter). -/
def countOutputFields : List Field -> Nat
  | [] => 0
  | field :: rest =>
      (if field.fieldClass == FieldClass.regular then 1 else 0) + countOutputFields rest

/-- The value of the regular OUTPUT field named `label`, if present. Skips non-output fields
    (a `_label`/`#label`/optional/required same-string field is NOT this field). -/
def outputFieldValue? (label : String) : List Field -> Option Value
  | [] => none
  | field :: rest =>
      if field.fieldClass == FieldClass.regular && field.label == label then some field.value
      else outputFieldValue? label rest

/-- The element list a list-shaped value exposes for `==`: a plain list, an open-tailed list
    (`[1, ...]` — the tail is a constraint on absent elements, no output, so it is DROPPED:
    cue `[1, ...] == [1]` ⇒ `true`), or a struct-that-IS-a-list (`embeddedList`). Any other
    value is not list-shaped. -/
def listItems? : Value -> Option (List Value)
  | .list items => some items
  | .listTail items _ => some items
  | .embeddedList items _ _ => some items
  | _ => none

/- Full-concreteness guard for struct/list `==`. CUE holds `==` incomplete unless BOTH operands
   are fully concrete (`{a: 1} == {a: int}` stays incomplete, and an incomplete field defers even
   when another field already differs). Mirrors the manifest output-field filter: only REGULAR
   fields carry a settled value that must be concrete; hidden/definition/`let`/import/optional
   fields are non-output and ignored; a REQUIRED field is not settled (cue defers `{x!:1} == …`).
   `structComp`, disjunctions without a default, refs, bounds, kinds, and every other abstract form
   are non-concrete ⇒ DEFER. Structural over the finite `Value` (the `containsBottom` pattern). -/
mutual
def isConcrete : Value -> Bool
  | .prim _ => true
  | .struct fields _ _ _ _ => isConcreteFields fields
  | .list items => isConcreteList items
  | .listTail items _ => isConcreteList items
  | .embeddedList items _ _ => isConcreteList items
  | _ => false
  termination_by structural value => value

def isConcreteFields : List Field -> Bool
  | [] => true
  | ⟨_, fieldClass, value, _⟩ :: rest =>
      (if fieldClass == FieldClass.regular then isConcrete value
       else match FieldClass.optionality fieldClass with
            | .required => false
            | _ => true)
        && isConcreteFields rest
  termination_by structural fields => fields

def isConcreteList : List Value -> Bool
  | [] => true
  | value :: rest => isConcrete value && isConcreteList rest
  termination_by structural values => values
end

/- Concrete `==` on two operands the caller has already proven fully concrete and bottom-free.
   Structs compare ORDER-INDEPENDENTLY over regular output fields (equal output-field count AND
   every left field label-matched in the right with equal value); lists compare ORDER- and
   LENGTH-sensitively element-wise; primitives reuse the decimal-aware leaf equality (so
   `1 == 1.0`). Cross-shape pairs (struct vs list, prim vs struct, …) are `false`. Returns `Bool`,
   so a `_` probe arm is permitted (it produces no `Value`). Structural over the left operand. -/
mutual
def concreteEq : Value -> Value -> Bool
  | .prim left, .prim right => (evalDecimalCompare? decimalEqValues left right).getD (left == right)
  | .struct leftFields _ _ _ _, .struct rightFields _ _ _ _ =>
      countOutputFields leftFields == countOutputFields rightFields
        && concreteEqFields leftFields rightFields
  | .list items, right =>
      match listItems? right with | some rightItems => concreteEqList items rightItems | none => false
  | .listTail items _, right =>
      match listItems? right with | some rightItems => concreteEqList items rightItems | none => false
  | .embeddedList items _ _, right =>
      match listItems? right with | some rightItems => concreteEqList items rightItems | none => false
  | _, _ => false
  termination_by structural left => left

def concreteEqFields : List Field -> List Field -> Bool
  | [], _ => true
  | ⟨label, fieldClass, value, _⟩ :: rest, rightFields =>
      (if fieldClass == FieldClass.regular then
         match outputFieldValue? label rightFields with
         | some rightValue => concreteEq value rightValue
         | none => false
       else true)
        && concreteEqFields rest rightFields
  termination_by structural fields => fields

def concreteEqList : List Value -> List Value -> Bool
  | [], right => right.isEmpty
  | _ :: _, [] => false
  | left :: leftRest, right :: rightRest => concreteEq left right && concreteEqList leftRest rightRest
  termination_by structural values => values
end

/-- The `==` verdict for two non-`prim`, non-`bottom` operands, or `none` to DEFER. Yields a
    definite bool only when BOTH operands are fully concrete and free of any (even deeply hidden)
    bottom — the over-eager trap CUE avoids by keeping `==` incomplete on abstract operands. A
    present bottom anywhere DEFERS rather than folding to a bool (conservative: cue surfaces the
    bottom, kue holds the residual). -/
def structEqConcrete? (left right : Value) : Option Bool :=
  if containsBottom left || containsBottom right then none
  else if isConcrete left && isConcrete right then some (concreteEq left right)
  else none

def evalEq (left right : Value) : Value :=
  match left, right with
  | .prim left, .prim right =>
      match evalDecimalCompare? decimalEqValues left right with
      | some value => .prim (.bool value)
      | none => .prim (.bool (left == right))
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
  | left, right =>
      match structEqConcrete? left right with
      | some result => .prim (.bool result)
      | none => .binary .eq left right

def evalNe (left right : Value) : Value :=
  match evalEq left right with
  | .prim (.bool value) => .prim (.bool (!value))
  | .binary .eq left right => .binary .ne left right
  | value => value

def charsLt : List Char -> List Char -> Bool
  | [], [] => false
  | [], _ :: _ => true
  | _ :: _, [] => false
  | left :: leftRest, right :: rightRest =>
      if left.toNat == right.toNat then
        charsLt leftRest rightRest
      else
        left.toNat < right.toNat

def stringsLt (left right : String) : Bool :=
  charsLt left.toList right.toList

/-- A scalar-op operand, classified for the bool / numeric / comparison / regex ops. `prim`
    carries the leaf so the op can compute on it; `bottom`/`bottomReasons` propagate a bottom;
    every ABSTRACT form (ref, kind, bound, unresolved disjunction, struct, list, comprehension,
    …) is `defer` — the op holds a residual `.binary`/`.unary`. Fully enumerated over `Value`
    (no catch-all) so a new constructor forces a classify decision here, exactly as
    `classifyArithOperand` does for `+ - * /`. -/
inductive ScalarOperandClass where
  | prim (value : Prim)
  | bottom
  | bottomReasons (reasons : List BottomReason)
  | defer

/-- Classify a scalar-op operand. Shared by `evalPrimitiveOrdering`/`evalRegexMatch`/
    `evalBoolBinary`/`evalBoolNot`/`evalNumPos`/`evalNumNeg`, so each dispatches on the finite
    `ScalarOperandClass` (a `_` on the CLASS enum is permitted — the ban is on catch-alls over
    `Value`) instead of a `| _ =>` catch-all on `Value` itself. -/
def classifyScalarOperand : Value -> ScalarOperandClass
  | .prim value => .prim value
  | .bottom => .bottom
  | .bottomWith reasons => .bottomReasons reasons
  | .top => .defer
  | .kind _ => .defer
  | .notPrim _ => .defer
  | .stringRegex _ => .defer
  | .boundConstraint _ _ _ => .defer
  | .lengthConstraint _ _ _ => .defer
  | .uniqueItems => .defer
  | .conj _ => .defer
  | .builtinCall _ _ => .defer
  | .unary _ _ => .defer
  | .binary _ _ _ => .defer
  | .ref _ => .defer
  | .refId _ => .defer
  | .thisStruct => .defer
  | .selector _ _ => .defer
  | .index _ _ => .defer
  | .disj _ => .defer
  | .struct _ _ _ _ _ => .defer
  | .list _ => .defer
  | .listTail _ _ => .defer
  | .embeddedList _ _ _ => .defer
  | .embeddedScalar _ _ => .defer
  | .comprehension _ _ => .defer
  | .structComp _ _ _ => .defer
  | .listComprehension _ _ => .defer
  | .interpolation _ => .defer
  | .dynamicField _ _ _ => .defer
  | .closure _ _ => .defer

def evalPrimitiveOrdering
    (decimalOp : DecimalValue -> DecimalValue -> Bool)
    (stringOp : String -> String -> Bool)
    (op : BinaryOp)
    (left right : Value) : Value :=
  match classifyScalarOperand left, classifyScalarOperand right with
  | .prim left, .prim right =>
      match evalDecimalCompare? decimalOp left right with
      | some value => .prim (.bool value)
      | none =>
          match left, right with
          | .string left, .string right => .prim (.bool (stringOp left right))
          | _, _ => .bottom
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomReasons reasons, _ => .bottomWith reasons
  | _, .bottomReasons reasons => .bottomWith reasons
  | _, _ => .binary op left right

def evalRegexMatch (left right : Value) : Value :=
  match classifyScalarOperand left, classifyScalarOperand right with
  | .prim (.string value), .prim (.string pattern) =>
      match regexParseError? pattern with
      | some err => .bottomWith [.invalidRegex pattern err]
      | none => .prim (.bool (matchRegex pattern value))
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomReasons reasons, _ => .bottomWith reasons
  | _, .bottomReasons reasons => .bottomWith reasons
  | .prim _, .prim _ => .bottom
  | _, _ => .binary .regexMatch left right

def evalRegexNotMatch (left right : Value) : Value :=
  match evalRegexMatch left right with
  | .prim (.bool value) => .prim (.bool (!value))
  | .binary .regexMatch left right => .binary .regexNotMatch left right
  | value => value

def evalIntKeywordBinary
    (op : BinaryOp)
    (intEval : Value -> Value -> Value)
    (left right : Value) : Value :=
  match intEval left right with
  | .builtinCall _ _ => .binary op left right
  | value => value

def evalBoolBinary (op : BinaryOp) (boolOp : Bool -> Bool -> Bool) (left right : Value) : Value :=
  match classifyScalarOperand left, classifyScalarOperand right with
  | .prim (.bool left), .prim (.bool right) => .prim (.bool (boolOp left right))
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomReasons reasons, _ => .bottomWith reasons
  | _, .bottomReasons reasons => .bottomWith reasons
  | .prim _, .prim _ => .bottom
  | _, _ => .binary op left right

def evalBoolNot (value : Value) : Value :=
  match classifyScalarOperand value with
  | .prim (.bool value) => .prim (.bool (!value))
  | .prim _ => .bottom
  | .bottom => .bottom
  | .bottomReasons reasons => .bottomWith reasons
  | .defer => .unary .boolNot value

def negateFloatText (value : String) : String :=
  match value.toList with
  | '-' :: rest => String.ofList rest
  | _ => "-" ++ value

def evalNumPos (value : Value) : Value :=
  match classifyScalarOperand value with
  | .prim (.int value) => .prim (.int value)
  | .prim (.float value text) => .prim (.float value text)
  | .prim _ => .bottom
  | .bottom => .bottom
  | .bottomReasons reasons => .bottomWith reasons
  | .defer => .unary .numPos value

def evalNumNeg (value : Value) : Value :=
  match classifyScalarOperand value with
  | .prim (.int value) => .prim (.int (-value))
  | .prim (.float _ text) => .prim (mkFloatText (negateFloatText text))
  | .prim _ => .bottom
  | .bottom => .bottom
  | .bottomReasons reasons => .bottomWith reasons
  | .defer => .unary .numNeg value

def evalUnary (op : UnaryOp) (value : Value) : Value :=
  match op with
  | .boolNot => evalBoolNot value
  | .numPos => evalNumPos value
  | .numNeg => evalNumNeg value

def evalBinary (op : BinaryOp) (left right : Value) : Value :=
  match op with
  | .add => evalAdd left right
  | .sub => evalSub left right
  | .mul => evalMul left right
  | .div => evalDiv left right
  | .intDiv => evalIntKeywordBinary .intDiv divValue left right
  | .intMod => evalIntKeywordBinary .intMod modValue left right
  | .intQuo => evalIntKeywordBinary .intQuo quoValue left right
  | .intRem => evalIntKeywordBinary .intRem remValue left right
  | .eq => evalEq left right
  | .ne => evalNe left right
  | .lt => evalPrimitiveOrdering decimalLtValues stringsLt .lt left right
  | .le =>
      evalPrimitiveOrdering
        (fun left right => decimalEqValues left right || decimalLtValues left right)
        (fun left right => !stringsLt right left)
        .le
        left
        right
  | .gt => evalPrimitiveOrdering (fun left right => decimalLtValues right left) (fun left right => stringsLt right left) .gt left right
  | .ge =>
      evalPrimitiveOrdering
        (fun left right => decimalEqValues left right || decimalLtValues right left)
        (fun left right => !stringsLt left right)
        .ge
        left
        right
  | .regexMatch => evalRegexMatch left right
  | .regexNotMatch => evalRegexNotMatch left right
  | .boolAnd => evalBoolBinary .boolAnd (fun left right => left && right) left right
  | .boolOr => evalBoolBinary .boolOr (fun left right => left || right) left right

/-- Resolve a disjunction operand to the concrete value an arithmetic / comparison /
    unary op demands. CUE forces such operands to a *single* default (or lone live regular)
    BEFORE applying the scalar op — it does NOT distribute the op across the disjunction
    (`(int | *1) + 1 → 2`, not `int+1 | *2`). A disjunction that does not resolve (multiple
    distinct defaults, or multiple live regulars) is left untouched, so `evalBinary`/
    `evalUnary` returns a stuck node (`(1|2)+10 → (1 | 2) + 10`) — CUE's "unresolved
    disjunction" form, which manifest reports as incomplete. -/
def resolveOperand (value : Value) : Value :=
  match collapseDefaultDisjunction value with
  -- A scalar carrier (`{#a:1, 5}`) IS its scalar in any operator position — cue: `{#a:1,5} + 1`
  -- sees `5`. Unwrap to the inner terminal scalar before the op; the decls are not an operand.
  | .embeddedScalar scalar _ => scalar
  | resolved => resolved

/-- Apply a unary op, resolving a disjunction operand to its default first. -/
def distributeUnary (op : UnaryOp) (value : Value) : Value :=
  evalUnary op (resolveOperand value)

/-- Apply a binary op, resolving each disjunction operand to its default first. No
    cross-product: CUE arithmetic/comparison forces each operand concrete independently. -/
def distributeBinary (op : BinaryOp) (left right : Value) : Value :=
  evalBinary op (resolveOperand left) (resolveOperand right)

end Kue
