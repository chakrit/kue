# Breadcrumb — 2026-07-04 comprehension/embedding/pattern conformance probe

## Where the loop stands

Just landed: a bounded EVAL-CORE conformance probe over `for`/`if`/`let` comprehensions,
struct embedding, and pattern constraints (`[expr]: T`). **Area is spec-conformant at the
value level** — swept clean with guard theorems. One real divergence found + seeded; one
apparent divergence resolved to an already-ratified spec gap.

## What landed this slice

- **Guard theorems (conformance pins):** `ComprehensionTests`
  `listcomp_for_kv_skips_nonregular`, `structcomp_for_produces_fields`; `StructTests`
  `pattern_via_unification_constrains_added_field`, `pattern_explicit_field_must_satisfy`,
  `pattern_matches_dynamic_field`. All `native_decide`, cue v0.16.1-cross-checked.
- **Red seed (FILED, quarantined):** `testdata/wild/pattern-bound-reference-operand/`
  (`.known-red`). kue's parser rejects a REFERENCE/expression operand in bound/relational
  operators (`x: >k`, `{[=~_re]: int}`, `{[>k]: int}`) — only literals accepted. cue accepts
  all (grammar: `rel_op UnaryExpr`). kue over-restrictive → rejects valid CUE. NOT a
  cue-divergence (cue is spec-correct); a plain kue completeness bug.
- **plan.md + implementation-log.md:** probe section + slice entry recording swept-clean
  areas, the seeded gap, and the ratified-ordering recognition.

## The one open fix-slice (PATTERN-BOUND-REF-OPERAND)

Broad + soundness-core, DEFERRED under AFK (needs attended slice):
- bound `Value` repr must carry an UNRESOLVED operand expression (currently holds a literal
  value: `.boundConstraint value kind …`, `.stringRegex literal`);
- parser (`Kue/Parse.lean`, `parseBoundValue` + the `=~`/`!~`/`!=` arms near line 1315-1331)
  must parse a general `UnaryExpr` operand for every rel_op;
- evaluator must evaluate the operand, deferring on incomplete, before applying the relation.
Bounds are pervasive → own careful slice. Graduate the seed (`rm .known-red`) when fixed.

## Recognized + skipped (do NOT re-file)

Embed/comprehension field ORDER (`{ {a:1}, b:2 }` → kue `{b,a}`, cue `{a,b}`) = "Field
order #3", RATIFIED spec gap (spec: structs unordered; parity DECLINED; Kue keeps source
order). jq `-S` canary is order-insensitive.

## Verify

`./scripts/check.sh` GREEN; cert-manager canary EMPTY. Committed on `main` (explicit
pathspec), NOT pushed (AFK).

## Next

Pick the next unblocked slice from `plan.md` § Ranked OPEN backlog. The PATTERN-BOUND-REF-OPERAND
fix is attended-grade (broad parser+evaluator) — leave for an attended session.
