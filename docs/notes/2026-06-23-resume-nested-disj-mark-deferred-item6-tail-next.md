# RESUME — NESTED-DISJ-MARK adjudicated (DESIGNED-DEFERRAL); NEXT = item-6 LATENT tail / SC-3

(2026-06-23) Live START-HERE; supersedes
`2026-06-23-resume-embed-disj-audit-closed-nested-disj-mark-next.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md). Spec-conformance backlog:
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Genuinely-open.
Per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md). Failure modes:
[`../reference/failure-modes.md`](../reference/failure-modes.md). Served status page:
[`../../www/index.html`](../../www/index.html).

## Just adjudicated — NESTED-DISJ-MARK → DESIGNED-AND-DEFERRED (no behavior change)

The filed nested-disj-of-disj default-mark divergence is adjudicated to a **spec-verified two-tier
rule** and DEFERRED (correct outcome — a wrong mark change would broadly risk default-selection; the
slice's explicit STOP condition). NO eval/lattice behavior changed this slice.

**STEP-0 two-tier RULE (cue v0.16.1, probed).** The source `*( … )` form is a PARSE ERROR
(`preference mark not allowed at this position`); the shape only arises via a def/ref (`_O: *_I | _B`,
embedded `*_O | …`). A `*`-marked GROUP puts the WHOLE group in the OUTER default-set, the inner `*` a
PREFERENCE within it. After a narrowing prunes dead arms: (tier 1) inner-preferred survives ⇒ it wins
(`(*_I|9)&(>=1&<=5)` with `_I:*1|5` → `1`); (tier 2) inner default DIES ⇒ surviving inner arm INHERITS
the outer `*`, beats an outer-REGULAR survivor (`(*_#O|{c})&{b:"x"}`, `_#O:*_#I|_#B`, `_#I` killed by
closedness → cue `{b:"x"}`; scalar `(*_I|9)&>=5` → `5`). UNMARKED group does NOT inherit (→ ambiguous).

**Divergence (tier-2 only).** Kue eagerly flattens `(.default, .disj nested)` at EVAL time
(`Eval.lean:3410-3414` `.disj` → `normalizeEvaluatedDisj`/`normalizeDisj`/`flattenAlternatives`): the
inner non-default sub-arm goes `.regular`, losing the outer `*`; inner-default-death ⇒ export AMBIGUOUS
where cue picks the marked survivor. **Root: a flat 2-state `Mark` cannot encode tier-membership +
inner-preference.** Designed fix: (A) 3rd `Mark` state (8-file ripple) OR (B) keep the nested `.disj`
arm un-flattened to meet time + narrowing-aware distribute (ripples the flatness invariant). Both LARGE
+ delicate ⇒ DEFERRED. Full record: `cue-spec-gaps.md` NESTED-DISJ-MARK row + implementation-log
(Designed-Deferral entry) + `spec-conformance-audit.md` § Genuinely-open #2.

**Landed (record + guards only):** 5 `TwoPassTests` `nested_disj_mark_*` pins (tier-1 match, no-narrow
value match, unmarked-group ambiguous regression guard, + 2 `⚠ DEFERRAL WITNESS` pins via
`exportJsonBottoms = true` that FLIP when fixed) + a `#check` sentinel. Docs as above.

## Audit counter = 1

This slice is a designed-deferral (adjudication + record), not a code-quality-bearing change. Counter
ADVANCES to 1. Two-phase audit triggers at 2–3 per the normal cadence
([`../guides/slice-loop.md`](../guides/slice-loop.md)) — do NOT invoke `/ace-audit`, follow the guide.

## State — substantive backlog EXHAUSTED; only LATENT / CLEANUP + one DEFERRED divergence

Spec-conformance backlog: the lone open VALUE divergence is NESTED-DISJ-MARK (DESIGNED-DEFERRED above);
everything else is LATENT/CLEANUP or display-only (SC-3). argocd + cert-manager content-identical
drop-ins (jq -S diff = 0); per-eval perf frontier CLOSED. Latest release `v0.1.0-alpha.20260623`.

## 🚨 NEXT LEADER — item-6 LATENT tail, then SC-3 (NESTED-DISJ-MARK is deferred, not the leader)

Resolve by philosophy (precise/total/illegal-states-unrepresentable), don't ask:

- **item-6 LATENT tail** — `module-file-scoped-imports` (arch-sized; prod9 misses it); B2-A1 (latent
  `tail`-drop, pairs with typed-ellipsis) / B2-A2 (test-gap fill); DRY `selectEvaluatedField .disj`.
- **SC-3** — multi-arm-default display-gap (cosmetic Format-layer projection; the residual `*{…} | {…}`
  shown in `eval` is this gap — export is identical).
- **NESTED-DISJ-MARK** — DEFERRED; revisit only as a designed standalone (3rd `Mark` state or
  non-flattening nested-disj invariant) when a real config needs tier-2, NOT as a quick next slice.

Pick the next by philosophy, drive the loop.

## Verify on resume

`git status` clean, `HEAD == @{u}`, `lake build` green, `scripts/check-fixtures.sh` green.
Canaries (from `/Users/chakrit/Documents/prod9/infra`) jq-S=0 if a slice touched eval (this slice did
NOT — only test pins + docs).

## Release

`v0.1.0-alpha.20260623` is the latest cut. This slice is record-only (NO behavior change) ⇒ no fresh
alpha owed FOR IT. The prior embed-disj-arm-closedness BEHAVIOR change still owes the next auto-due
daily cut (attended) via `scripts/release.sh` (+ `scripts/release-linux.sh`).

## Live state end
