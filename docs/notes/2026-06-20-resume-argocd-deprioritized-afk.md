# RESUME HERE — D#1b/D#1c DONE; comprehension-guard catch-all DRAINED; D#3 leads (2026-06-20)

Live START-HERE pointer; supersedes all prior breadcrumbs. Authoritative live roadmap:
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md)
§ Consolidated fix backlog (owns the ranked spec-conformance fixes) +
[`../spec/plan.md`](../spec/plan.md) (capabilities + non-spec roadmap).

**Latest (2026-06-20):** D#1b + D#1c landed → **the comprehension `if`-guard catch-all is fully
drained** (D#1a bottom→propagate, D#1b incomplete→DEFER, D#1c concrete-non-bool→TYPE-ERROR; no
residual `_` arm). The guard match (struct + list twins) now reads a total `classifyGuard :
Value → GuardVerdict` that ENUMERATES every `Value` constructor (no catch-all). D#1c: a concrete
non-bool guard (`if "x"`/`if 3`/`if {…}`/`if [..]`/`if null`) is `.bottomWith [.nonBoolGuard ty]`
(new `BottomReason.nonBoolGuard` + precise `NonBoolGuardType` = `scalar Kind`/`struct`/`list`);
CONFORMS (cue agrees both modes). D#1b: an abstract guard (kind / unresolved disj / non-presence
comparison `x>5`) DEFERS — the comprehension stays a residual node via the new third protocol
outcome `ClauseExpansion`/`ListClauseExpansion` `.deferred` + `withDeferredComprehensions` re-wrap
(cue eval-holds; `kue export` errors `incomplete value`). The residual PRESENCE test `X !=/== _|_`
is CARVED OUT (stays a drop — cue eval drops it; this carve-out is load-bearing, found by
regression). Spec-gap recorded (D#1b defer mechanism); display divergence recorded (Kue renders
the held guard ref as `@d.i`, cue prints the name). 17 `native_decide` pins + 4 fixtures; 3
bug-replicating DROP pins corrected to the spec-correct HELD form; cert-manager content-identical.

**Audit state — NOT due (accurate).** The D#2 two-phase audit ran earlier this session (Phase A
`b5883f1` + Phase B `c03ebdb`, scoping D#2a/D#2b). The NEW batch since then: **RX-2a (slice 1) +
D#1b/D#1c (slice 2)** = 2 slices landed. The next Phase-A→Phase-B audit is due after **~1 more
slice** (the 3rd). Do NOT re-introduce a spurious "AUDIT DUE" flag now; do NOT invoke
`/ace-audit` — the procedure is in `slice-loop.md`. (Audit subagents MUST reset this note when they
run.)

## IMMEDIATE NEXT STEPS (design-first; the loop can just `Keep going`)

1. **The MED tail LEADS — start with D#3** (`let` clauses in comprehensions). No large designed
   levers remain. One more slice after this, THEN the two-phase audit is due.
   - **D#3** — `let` clauses in comprehensions: parse `let x = expr` as a comprehension clause,
     add `Clause.letClause`, and wire `let` = +1 frame in `descendClauses` (the for=+1/if=+0
     frame model is spec-CORRECT, B7-vindicated; `let` joins as +1). Currently `let`-in-
     comprehension is UNPARSEABLE — the last open D-area item.
   - **BI-1** Unicode case-fold for `strings.ToUpper/ToLower` (currently ASCII-only → wrong on
     non-ASCII); **BI-2** `math.Pow/Sqrt`, `list.Sort/SortStable` (currently bottom on concrete
     input); **F-3** parse qualified import path `"location:identifier"` (currently unparsed).
   - **SC-3 display-residual** (LOW/spec-gap) — cue's further display-collapse of a defaulted
     disjunction to its default (`*1|2`→`1`, `{…}|*null`→`null`). Kue deliberately does NOT
     collapse (unsound — loses the live arm a later meet needs); recorded as a spec-gap. A
     Format-layer projection rewriting ~7 fixtures; close only if the eval-display convention is
     revisited.
2. Then the ranked tail in `spec-conformance-audit.md § Consolidated fix backlog`: **SC-4** (LOW,
   spec-check FIRST — cue is internally inconsistent here, don't reflexively match) · the 4
   spec-gap ratifications in `cue-spec-gaps.md` · **A#6** (`containsBottom` fuel cap 100,
   STANDALONE — D#2 confirmed it is NOT implicated by structural cycles; a real hardening item for
   deep NON-cyclic bottoms) · **DRY-1** (let-walker `walkFollowedLets` consolidation; schedule
   after Bug2-5 if that ever un-parks). **SC-1b** (closed×closed-pattern intersection) sits with
   this MED/hardening tail.
3. Plan-only roadmap (plan.md Live Backlog, NOT in audit.md): `truncate-primitive` (HIGH —
   soundness hardening) · Regex/EvalOps module extractions · test/fixture-org pass ·
   field-order #3 · A2-x/A2-y loader corners · B3/B5 incompleteness. NOTE: plan-side **A-EN3**
   and audit-side **DRY-1** look like the same let-walker consolidation — reconcile when picked.

**argocd / Bug2-5: PARKED** — a stress-test finding, not on the critical path. Resolves as the
general semantics mature; do not chase it with app-specific narrowing.

## CANONICAL PATHS (ground-truth — a prior auditor got confused; do NOT re-litigate)

- prod9 stress-test targets: `/Users/chakrit/Documents/prod9/infra/apps/argocd.cue` and
  `.../cert-manager.cue` (cert-manager is fully correct; argocd parked).
- cue oracle: `/Users/chakrit/go/bin/cue` (v0.16.1) — READ-ONLY, cross-check only.
- kue binary: `.lake/build/bin/kue` (or `lake exe kue`).

## STANDING CONTEXT (durable; full detail in CLAUDE.md + guides/slice-loop.md)

- Kue autonomy grant in effect (decide/proceed; resolve forks by philosophy; commit/push on
  `main` when attended). **Spec is authority; `cue` is a fallible cross-check, never the
  gate.** Correctness-over-performance. **Unattended/AFK → commit, don't push** (CLAUDE.md).
- Orchestrator = thin re-spawner; one subagent per slice; two-phase audit (A then B) every
  2–3 slices. Per-slice duties: tests-first; log `cue-divergences.md`; flag
  `cue-spec-gaps.md`; keep `kue-performance.md` current.
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on the main tree.
- Loose end (low priority): compat-assumptions.md "Composition note (infra docker-config)"
  (~L503–510) may be stale — `_auths` hidden-field refs + `[string]:` label patterns now
  likely resolve; needs a targeted end-to-end check on `secret.cue` before trusting.
