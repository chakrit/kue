# PRIM-FLOAT-PARSED (plan 0e) — landed 2026-07-05

## What

`Prim.float` refined from raw `String` to `float (value : DecimalValue) (text : String)`. The exact
base-10 value is smart-constructed ONCE (lex/result-construction time) via the sole `mkFloatText`
constructor; `text` is retained verbatim for exact render round-trip.

Wins:
- `primsUnifyEqual` float arm is now a total `decimalEqValues` on the two stored decimals — the
  re-parse AND the unreachable `| _, _ => leftText == rightText` fallback are ERASED (the
  illegal-state the audit flagged).
- `decimalFromPrim?` float case total (`some value`, no parse). `mathAbs`/`mathRound` drop their
  per-call `parseDecimalText` + dead `none` arms.
- Hot meet/compare path no longer re-parses an unchanging value.

## Why behavior-preserving (no RED repro)

`value = parseDecimalText text` deterministically, so derived `BEq` on `Prim.float` reduces to
text-equality EXACTLY as the `String` rep did — no `Value` equality / dedup / disjunction / fixture
drift. Rendering reads `text` unchanged. This is a representation refactor, not a bug fix: the
by-value unification it builds on (`1.0 & 1.00`) already landed, and no current output was
lossy/wrong. Pinned the load-bearing BEq≡text invariant as a theorem so any future drift trips.

## Verify

`./scripts/check.sh` GREEN; cert-manager realworld canary byte-identical (float export is exactly
where this could regress — the net confirms it didn't). 5 new `native_decide`/`rfl` theorems in
`FloatTests.lean` (stored-decimal exactness+totality, by-value unify, verbatim text round-trip,
BEq≡text, bound edges). No spec-gap/divergence: numeric semantics unchanged and spec-conforming;
the choice is internal representation only.

## Next

Backlog per plan.md ranked OPEN: GDA-FLOAT-RENDER (couples naturally with this — both touch float
representation; the retained `text` is the round-trip anchor it will build on), BYTES-SLICE-MISSING,
BYTE-INTERPOLATION, BUILTIN-IMPORT-LENIENCY, B3d-6b (network-gated). **Two-phase audit now DUE** —
this closes the 2–3-slice window since the last (quoted-strip, byte-array-repr, this).
