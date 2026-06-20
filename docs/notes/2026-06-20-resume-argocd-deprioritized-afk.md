# RESUME HERE — D#3 DONE; D-area CLOSED; ⚠ TWO-PHASE AUDIT DUE (3 slices since `c03ebdb`) (2026-06-20)

Live START-HERE pointer; supersedes all prior breadcrumbs. Authoritative live roadmap:
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md)
§ Consolidated fix backlog (owns the ranked spec-conformance fixes) +
[`../spec/plan.md`](../spec/plan.md) (capabilities + non-spec roadmap).

**Latest (2026-06-20):** D#3 landed → **`let` clauses in comprehensions are now parseable +
correctly scoped; the D-area (comprehensions/scoping) is fully CLOSED.** `Clause.letClause (name,
value)` added to the comprehension clause sum (total, no catch-all). Frame model: **`let` = +1
frame** (spec: *"the `for` and `let` clauses each define a new scope"*; `if`/guard = +0) — wired in
the single authority `descendClauses` via a `.letClause` arm that routes the value through
`onSource` + pushes +1, so `clauseChainDepth` + all 4 frame-walkers handle it for free. Parse:
`parseLetClause` (`dropWord?`-bounded), reached only inside a clause chain, so a struct-field-head
`let` stays a struct-body binding (spec `StartClause = ForClause | GuardClause` excludes `let` —
a comprehension cannot START with `let`). Eval: bind the EVALUATED value into a one-slot frame
(`[⟨name, .regular, evaluatedValue⟩]`, like a `for` element) — alignment-correct (no residual
refIds), so a `for`
AFTER a `let` still resolves earlier bindings; an unreferenced binding's bottom sits unread (matches
cue for value-level bottoms). All 8 clause-match sites updated explicitly (no catch-all). 9
`native_decide` pins (incl. the `for`-after-`let` frame-accounting + shadowing + struct-form cases)
+ 6 fixtures (list + struct); cert-manager `export` content-identical (sorted-key). 1 cue-divergence
(unreferenced unresolved-ref `let` — cue errors, Kue tolerates; dead-binding-is-lattice-nothing) +
1 spec-gap (eager-into-frame eval order). See implementation-log + audit-history 2026-06-20.

**⚠ Audit state — AUDIT DUE (accurate; 3 slices since the last audit `c03ebdb`).** The D#2
two-phase audit ran earlier this session (Phase A `b5883f1` + Phase B `c03ebdb`, scoping
D#2a/D#2b). The batch since then: **RX-2a (slice 1) + D#1b/D#1c (slice 2) + D#3 (slice 3)** = 3
slices landed. **The two-phase audit (Phase A → Phase B) is now DUE — run it NEXT before any new
feature slice.** Run sequentially (A then B, both edit `plan.md`/this doc — parallel would collide);
follow [`../guides/slice-loop.md`](../guides/slice-loop.md), do NOT invoke `/ace-audit`. Scope: the
3-slice batch (RX-2a regex-complement + D#1b/c guard-classification + D#3 let-clauses) for Phase A;
whole module graph for Phase B. (Audit subagents MUST reset this note to NOT-due when they run.)

## IMMEDIATE NEXT STEPS (the loop can just `Keep going`)

1. **⚠ RUN THE TWO-PHASE AUDIT FIRST** (it is DUE — 3 slices landed since `c03ebdb`). Phase A
   (code-quality over the RX-2a + D#1b/c + D#3 batch), THEN Phase B (architecture/refactor/cleanup
   over the whole module graph). Sequential. Per `slice-loop.md`. Fold findings into the backlog as
   fix-slices. Then resume the MED tail below.
2. **The MED tail (no large designed levers remain; D-area CLOSED).** Lead with:
   - **BI-1** Unicode case-fold for `strings.ToUpper/ToLower` (currently ASCII-only → wrong on
     non-ASCII); **BI-2** `math.Pow/Sqrt`, `list.Sort/SortStable` (currently bottom on concrete
     input); **F-3** parse qualified import path `"location:identifier"` (currently unparsed).
   - **SC-3 display-residual** (LOW/spec-gap) — cue's further display-collapse of a defaulted
     disjunction to its default (`*1|2`→`1`, `{…}|*null`→`null`). Kue deliberately does NOT
     collapse (unsound — loses the live arm a later meet needs); recorded as a spec-gap. A
     Format-layer projection rewriting ~7 fixtures; close only if the eval-display convention is
     revisited.
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
