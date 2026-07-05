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

## Session resume state — VALIDATED FRONTIER (2026-07-04/05)

The autonomous *correctness* campaign is complete; consolidated run summary in `.afk.log`
(repo root). 51 commits on `main`, UNPUSHED (AFK), every one canary-byte-identical + audited.
Evidence the well is worked out (not a reflexive stop): 3 two-phase audit rounds this run all
HEALTHY + "substantially complete" verdict; 2 consecutive value-conformant probes (disjunctions,
comprehensions/embedding); every bounded unregistered builtin now registered.

**First human action:** `git push` the 51 commits + cut the owed alpha (`scripts/release.sh`).

**Remaining work — all attended-grade / deliberate / broad / blocked** (ranked in `plan.md`):
BYTE-ARRAY-REPR (0f, highest-leverage — fixes 3 byte bugs, unblocks byte-interp + byte-slice),
PATTERN-BOUND-REF-OPERAND, BI-EFF constraint-validator seam (MinRunes/MaxRunes/MinFields/
MaxFields + matchN/matchIf), STRUCT-EQ half-2, ARCH-QUOTED-STRIP (0c), PRIM-FLOAT-PARSED (0e),
BUILTIN-IMPORT-LENIENCY, diagnostic-message quality,
B3d-6b (network-gated). [RETRACTED 2026-07-05: NESTED-DISJ-MARK was NOT deferrable work — Kue
was already SPEC-CORRECT (spec rule M2); `cue` is buggy. Closed + reclassified to
`cue-divergences.md`.] 3 quarantined seeds, all filed: byte-literal-high-byte,
byte-literal-interpolation, pattern-bound-reference-operand.

## Pending school changes (for `ace-school` to propose — NOT applied to the school this run)

These operational lessons landed in this repo (`docs/reference/failure-modes.md`,
`docs/guides/slice-loop.md`) but are GENERIC to any ACE slice-loop project → propose upstream
to the `ace` / `ace-afk` skills:

- **Long builds are the orchestrator's job, not a subagent's.** A multi-minute build (toolchain
  bump, full rebuild, download) outlasts a subagent's turn — it stalls, re-notifies, burns tokens.
  Orchestrator runs it as `run_in_background` and owns that slice's verify.
- **Commit with an explicit pathspec, never bare.** `git commit -F msg -- <files>` — a bare commit
  sweeps a parallel peer's already-staged changes; `git add <paths>` alone is insufficient.
  Serialize/worktree parallel committers.
- **Treat any inherited root-cause pin as a hypothesis** — reproduce + bisect the minimal trigger
  BEFORE touching code (3 pins were red herrings this run).
- **A canary/oracle proves only what its corpus exercises** — it is NOT a substitute for a
  code-quality audit after an invasive/foundational-type change (a derived-`BEq` regression slipped
  the canary, caught only by the follow-up audit).
