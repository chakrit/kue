# Breadcrumb — 2026-07-04 — TYPED-ELLIPSIS-PROBE (B2-A1): non-bug

## What this slice did

Probed the suspected typed struct ellipsis `{...T}` soundness gap (does kue drop a typed
tail and over-accept a wrong-typed extra field where cue bottoms?). **Verdict: NON-BUG on
every axis.** Landed two parse-rejection guard theorems + docs; no product-code change.

## Findings (cue v0.16.1 vs kue)

- **Struct `{...T}` is PARSE-REJECTED by BOTH.** `...int`/`..._`/`...string`: cue "missing
  ',' in struct literal"; kue "typed struct ellipsis is not supported yet"
  (`Parse.lean:1483`). Spec marks `...expr` reserved-but-unimplemented → both conform by
  rejecting. So a struct `tail` only ever carries bare `...` = `.top` from source; the
  hypothesized over-acceptance is UNREACHABLE (the syntax cannot be written).
- The old B2-A1 plan claim — "`applyEvaluatedStructN` DROPS `tail`" — was STALE. The code
  (`EvalBase.lean:342,350`) PRESERVES the tail; `meet` applies a typed tail soundly
  (rejects wrong-typed ADDITIONAL fields, exempts own explicit fields — `StructTests`
  `meet_typed_ellipsis_*`, proven `rfl`). Verified empirically for a pattern+typed-tail
  carrier: own explicit fields correctly exempt (cue-correct).
- **List `[...T]` IS parsed + enforced by BOTH, kue matches cue** (`[...int] & [1,"s"]` →
  bottom on both). No divergence.

## What landed

- `Kue/Tests/ParseTests.lean`: `parse_struct_typed_ellipsis_rejected`,
  `parse_struct_typed_top_ellipsis_rejected` (pin the parse rejection).
- `docs/spec/plan.md` — B2-A1 rewritten as RESOLVED-BY-PROBE (non-bug; stale premise
  corrected).
- `docs/reference/implementation-log.md` — TYPED-ELLIPSIS-PROBE slice entry.
- `docs/reference/cue-spec-gaps.md` — reserved-but-unimplemented status row.

## Verify

`./scripts/check.sh` GREEN. cert-manager canary EMPTY (kue == cue byte-identical).

## Next

B2-A1 is closed as a non-bug. Typed struct ellipsis SYNTAX remains a distinct unbuilt
feature (not a soundness debt) — implement only if a real config needs it, and only
alongside cue implementing it (currently cue rejects too). Resume the plan HIGH/MEDIUM
tail (B3d-6b network-gated registry; scalar-embed follow-ups; LOW timeless-comment sweep).
