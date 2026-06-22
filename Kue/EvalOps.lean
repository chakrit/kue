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
def evalRepeat (text : String) (count : Int) (wrap : String -> Prim) : Value :=
  if count < 0 then .bottomWith [.negativeRepeatCount count]
  else .prim (wrap (String.join (List.replicate count.toNat text)))

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
  | .prim (.string text), .prim (.int count) => evalRepeat text count .string
  | .prim (.int count), .prim (.string text) => evalRepeat text count .string
  | .prim (.bytes text), .prim (.int count) => evalRepeat text count .bytes
  | .prim (.int count), .prim (.bytes text) => evalRepeat text count .bytes
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
      | .ok text => .prim (.float text)
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
  | other => other

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
  | _, _ => .binary .eq left right

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

def evalPrimitiveOrdering
    (decimalOp : DecimalValue -> DecimalValue -> Bool)
    (stringOp : String -> String -> Bool)
    (op : BinaryOp)
    (left right : Value) : Value :=
  match left, right with
  | .prim left, .prim right =>
      match evalDecimalCompare? decimalOp left right with
      | some value => .prim (.bool value)
      | none =>
          match left, right with
          | .string left, .string right => .prim (.bool (stringOp left right))
          | _, _ => .bottom
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
  | _, _ => .binary op left right

def evalRegexMatch (left right : Value) : Value :=
  match left, right with
  | .prim (.string value), .prim (.string pattern) =>
      match regexParseError? pattern with
      | some err => .bottomWith [.invalidRegex pattern err]
      | none => .prim (.bool (matchRegex pattern value))
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
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
  match left, right with
  | .prim (.bool left), .prim (.bool right) => .prim (.bool (boolOp left right))
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
  | .prim _, .prim _ => .bottom
  | _, _ => .binary op left right

def evalBoolNot (value : Value) : Value :=
  match value with
  | .prim (.bool value) => .prim (.bool (!value))
  | .bottom => .bottom
  | .bottomWith reasons => .bottomWith reasons
  | .prim _ => .bottom
  | _ => .unary .boolNot value

def negateFloatText (value : String) : String :=
  match value.toList with
  | '-' :: rest => String.ofList rest
  | _ => "-" ++ value

def evalNumPos (value : Value) : Value :=
  match value with
  | .prim (.int value) => .prim (.int value)
  | .prim (.float value) => .prim (.float value)
  | .bottom => .bottom
  | .bottomWith reasons => .bottomWith reasons
  | .prim _ => .bottom
  | _ => .unary .numPos value

def evalNumNeg (value : Value) : Value :=
  match value with
  | .prim (.int value) => .prim (.int (-value))
  | .prim (.float value) => .prim (.float (negateFloatText value))
  | .bottom => .bottom
  | .bottomWith reasons => .bottomWith reasons
  | .prim _ => .bottom
  | _ => .unary .numNeg value

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
  collapseDefaultDisjunction value

/-- Apply a unary op, resolving a disjunction operand to its default first. -/
def distributeUnary (op : UnaryOp) (value : Value) : Value :=
  evalUnary op (resolveOperand value)

/-- Apply a binary op, resolving each disjunction operand to its default first. No
    cross-product: CUE arithmetic/comparison forces each operand concrete independently. -/
def distributeBinary (op : BinaryOp) (left right : Value) : Value :=
  evalBinary op (resolveOperand left) (resolveOperand right)

end Kue
