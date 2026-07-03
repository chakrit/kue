# Breadcrumb — BI-3-RESIDUAL bounded subset landed (2026-07-04)

Slice **BI-3-RESIDUAL (bounded subset)** landed (AFK, committed on `main`, NOT pushed).
Registered the pure/bounded residual builtins from the BI-3 probe; validator + byte-repr
residuals stay filed (seam kue lacks — not forced).

## Landed (kue == cue v0.16.1 on the agreeing corpus)

Three builtins registered + implemented in `Kue/Builtin.lean` (helpers total — bounded/structural,
no `partial`), dispatch arms with no Value-producing catch-all:

- **`math.Mod`** (`mathMod`, arm in `evalMathBuiltin`) — Go float-remainder, sign of DIVIDEND;
  exact-decimal `x − trunc(x/y)·y`; `Mod(x,0)`⇒bottom. DIVERGES from cue's float64 on
  non-float64-exact remainders (`Mod(5.5,2.1)`=`1.3` vs cue `1.2999…998`) — recorded in
  `cue-divergences.md` (same posture as Sqrt/Pow).
- **`math.Signbit`** (`mathSignbit`) — `numerator < 0`; `Signbit(-0.0)`=false (cue parse-normalizes
  `-0.0`→`0.0`).
- **`strings.SliceRunes`** (`stringSliceRunes`, arm in `evalStringsBuiltin`) — half-open rune-indexed
  window on `Char` scalars; oob/neg/`lo>hi`⇒bottom.

Fixtures `builtins/math_mod_signbit`, `builtins/strings_slicerunes` (+ FixturePorts entries);
21 `native_decide` in `BuiltinTests.lean` (edges + divergence).

## Filed, NOT forced (seam kue lacks)

- **`strings.MinRunes`/`MaxRunes`, `struct.MinFields`/`MaxFields`** — CONSTRAINT validators. Need a
  `.builtinCall`-participates-in-`meet` seam; today `meet(scalar, .builtinCall)`⇒bottom
  (`Lattice.lean:481`). This is the unimplemented validator family (`matchN`/`matchIf`/`list.MatchN`)
  in `Eval.lean`'s BI-EFF EXTENSION RULE. cue semantics verified (`"ab" & MinRunes(3)`⇒⊥,
  `"abc"`⇒`"abc"`, bare⇒incomplete) but implementing needs the seam — filed in plan.md.
- **`strings.ByteAt`/`ByteSlice`** — byte-array-repr (DEPENDENT of BYTE-ARRAY-REPR).
- **`list.IsSorted`/`Sort`/`SortStable`** — effectful comparator seam BI-EFF.

## State

`./scripts/check.sh` GREEN. Canary EMPTY. Registered builtin inventory now: core(8), strings(24),
list(14), math(10), regexp(7), base64(1), json(1), yaml(1). `struct.*` still UNREGISTERED (validator
seam). BI-3-RESIDUAL pure/bounded subset is now EXHAUSTED — what remains all needs a seam:
the **validator/constraint seam** (MinRunes/MaxRunes/MinFields/MaxFields — the highest-value next
target, unlocks a whole builtin class), **BI-EFF** (list.Sort*/IsSorted), or **BYTE-ARRAY-REPR**
(ByteAt/ByteSlice, math byte/exp-ln residuals).

Next unblocked candidate: the validator seam (build `matchN`/`matchIf` + `.builtinCall` meet
participation) — it's the one that turns MinRunes/MaxRunes/MinFields/MaxFields from "filed" to
"trivial arms". Everything else is gated on BI-EFF or byte-repr.
