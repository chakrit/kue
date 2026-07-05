# AUD-B3 landed — scalar-op residual dispatch enumerated

Phase-B MEDIUM rule violation discharged. `Kue/EvalOps.lean`: six functions matched on
`Value` and produced a residual `.binary`/`.unary` from a `| _ =>`/`| _, _ =>` catch-all
(banned — Value-producing match).

## Fix

One shared enumerated classifier `classifyScalarOperand : Value -> ScalarOperandClass`
(`prim`/`bottom`/`bottomReasons`/`defer`), NO `Value` catch-all — a new `Value` ctor forces
a classify decision, like `classifyArithOperand`. All six sites dispatch on the finite class
enum (a `_` on the enum is fine; the ban is on `Value` catch-alls):

- Filed four: `evalBoolBinary`, `evalBoolNot`, `evalNumPos`, `evalNumNeg`.
- Same-pattern two, converted in the same slice (migration Law): `evalPrimitiveOrdering`,
  `evalRegexMatch`.

Strictly behavior-preserving (defer covers every abstract form, exactly as before).
`evalAdd/Sub/Mul/Div` untouched — they already route through the enumerated
`arithmeticDomainResult`.

## Tests

14 `native_decide` residual-preservation pins in `EvalTests.lean`.

## Guard

No grep guard: the compliant fix emits `| _, _ => .binary …` on the CLASS enum —
syntactically identical to a banned `Value` catch-all and to `arithmeticDomainResult`.
Reviewer-enforced (like the `check-comments.sh` "no longer"/"previously" idioms).

## Next

Phase-B backlog: **AUD-B2** (LOW — modtidy zip generator) and **AUD-B4** (LOW —
`Value.textBytes` relocate + `base64Encode` carrier). Both cosmetic.
