# RESUME HERE — RX-2a DONE; regex corpus divergence-free; MED tail leads (2026-06-20)

Live START-HERE pointer; supersedes all prior breadcrumbs. Authoritative live roadmap:
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md)
§ Consolidated fix backlog (owns the ranked spec-conformance fixes) +
[`../spec/plan.md`](../spec/plan.md) (capabilities + non-spec roadmap).

**Latest (2026-06-20):** RX-2a landed → **the regex corpus is now divergence-free** (RX-1
trilogy + RX-2a/b/c all DONE). In-class `\D`/`\W`/`\S` now fold their set-complement into the
class union; `parseClassEscape`'s three `.error` arms became `complementRanges` folds (new total
`Regex.complementRanges` over the `[0, U+10FFFF]` `Char` domain). Representation decision: NO new
AST state — `cls ranges negated` was already precise, the complement is a range union that
composes through the ordinary union and is flipped by the whole-class `negated` flag for `[^…]`
(strictly better on the illegal-states axis than a signed-member type). CONFORMS (RE2-mandated,
cue-agreeing — no divergence/spec-gap). 26 `native_decide` pins + 1 `=~`/`!~` fixture. Leaf module,
no eval-cost change.

**Audit state — NOT due.** The D#2 two-phase audit already ran this session: Phase A `b5883f1`
(SOUND; +2 edge pins; AD2-1 filed) + Phase B `c03ebdb` (HEALTHY; AD2-1 ruled file-not-inline;
perf-guide updated), scoping D#2a + D#2b. **RX-2a is slice 1 of the new batch** → the next
Phase-A→Phase-B audit is due after ~2 more slices land. (Cadence/procedure: `slice-loop.md`; do
NOT invoke `/ace-audit`. Audit subagents MUST reset this audit-state note + clear any "due" flag
here when they finish, so the next slice doesn't double-count — that drift just happened once.)

## IMMEDIATE NEXT STEPS (design-first; the loop can just `Keep going`)

1. **The MED tail LEADS** — start with **D#1b / D#1c** (detailed just below). No audit now: the
   D#2 audit already ran (`b5883f1` + `c03ebdb`); RX-2a is slice 1 of the new batch, next audit
   after ~2 more slices. (No large designed levers remain after D#2 + the regex family.)
   - **D#1b / D#1c** — comprehension-guard classification. D#1a (bottom → propagate) is DONE;
     D#1b makes a genuinely INCOMPLETE/abstract guard DEFER, D#1c makes a CONCRETE non-bool guard
     (`if "x" {…}`, `if 3 {…}`) a TYPE ERROR (cue errors; Kue currently swallows to `{}`). Both
     in `Eval.lean expandClausesWithFuel`'s guard match; they split the residual `_ => pure (.ok
     [])` arm. Couple loosely with each other.
   - **D#3** — `let` clauses in comprehensions (parse + `Clause.letClause` + wire `let` = +1 in
     `descendClauses`; the for=+1/if=+0 frame model is spec-correct, B7-vindicated).
   - **SC-3 display-residual** (LOW/spec-gap) — cue's further display-collapse of a defaulted
     disjunction to its default (`*1|2`→`1`, `{…}|*null`→`null`). Kue deliberately does NOT
     collapse (unsound — loses the live arm a later meet needs); recorded as a spec-gap. A
     Format-layer projection rewriting ~7 fixtures; close only if the eval-display convention is
     revisited.
   - **BI-1** Unicode case-fold for `strings.ToUpper/ToLower` (currently ASCII-only → wrong on
     non-ASCII); **BI-2** `math.Pow/Sqrt`, `list.Sort/SortStable` (currently bottom on concrete
     input); **F-3** parse qualified import path `"location:identifier"` (currently unparsed).
3. Then the ranked tail in `spec-conformance-audit.md § Consolidated fix backlog`: **SC-4** (LOW,
   spec-check FIRST — cue is internally inconsistent here, don't reflexively match) · the 4
   spec-gap ratifications in `cue-spec-gaps.md` · **A#6** (`containsBottom` fuel cap 100,
   STANDALONE — D#2 confirmed it is NOT implicated by structural cycles; a real hardening item for
   deep NON-cyclic bottoms) · **DRY-1** (let-walker `walkFollowedLets` consolidation; schedule
   after Bug2-5 if that ever un-parks). **SC-1b** (closed×closed-pattern intersection) sits with
   this MED/hardening tail.
4. Plan-only roadmap (plan.md Live Backlog, NOT in audit.md): `truncate-primitive` (HIGH —
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
