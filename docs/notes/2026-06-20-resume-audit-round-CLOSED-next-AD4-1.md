# RESUME HERE — two-phase AUDIT round CLOSED (2026-06-20); next code slice = **AD4-1**

Live START-HERE pointer; supersedes `2026-06-20-resume-e4-fix-done-AUDIT-DUE.md` (deleted).
Authoritative live roadmap: [`../spec/plan.md`](../spec/plan.md) (capabilities, ranked
backlog, audit verdicts) + [`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md)
§ Consolidated fix backlog (ranked spec-conformance fixes).

## Audit state — **COMPLETE. Counter = 0.** Next audit after 2–3 NEW slices.

The two-phase audit for the batch **truncate-primitive `7dfaadd` + ratifications `47ff318`
+ E#4-fix `02b8b9d`** is CLOSED:
- **Phase A `8be4457`** — all three slices SOUND, no code fix (E#4 per-operator domain +
  string/bytes repeat + concrete-vs-incomplete all oracle-verified; truncate single-choke-point
  + ratifications light-checks clean).
- **Phase B `6b51db1`** — architecture HEALTHY (whole graph acyclic, no `Builtin → Eval`
  back-edge); two rulings closed (below); one doc-staleness fix applied inline. No code change.

**Counter reset to 0.** The orchestrator's next action is a CODE slice (AD4-1), NOT another audit.

### The two Phase-B rulings (CLOSED — do not re-litigate)

1. **Three-parallel-classifiers DRY (`classifyArithOperand`/`classifyGuard`/`classifyDefinedness`)
   → LEAVE SEPARATE** (option a; the shared-concreteness-helper option b REJECTED). The three
   disagree on the PARTITION itself (`.disj`/`.structComp`/`.bottom`/`.prim`/`.binary` each land
   differently per classifier), so a shared helper factors out only the inert abstract tail = "the
   stuff they all do" = not a name (general-coding), while raising coupling + weakening the
   new-ctor-forces-a-decision guarantee. Recorded in plan § Resolved/ruled-out.
2. **Walker-dedup family gating → UNBLOCKED** (was "gated post-argocd"). The gate's sole rationale
   was walker-edit contention during active argocd debugging; argocd/Bug2-5 is now PARKED (off the
   critical path, may never un-park), so the contention is gone and the gate had degraded to
   "deferred forever." They are NOT correctness fixes (still never preempt a spec-conformance fix),
   but with the spec-conformance HIGH levers all DONE, **AD4-1 is now a strong schedulable leader.**
   Plan ranking/gating language updated (plan § walker-dedup family).

## NEXT CODE SLICE — **AD4-1 (comprehension-walker dedup), MEDIUM, the next-batch leader**

Why AD4-1 leads: spec-conformance HIGH levers are all DONE (only PARKED Bug2-5 remains); the
walker-dedups are now UNBLOCKED (ruling 2); AD4-1 is FIRST in the settled sequence (AD4-1 →
A-EN3+DRY-1 locality batch → AD2-1), the highest-value DRY cleanup, and the most self-contained
(one mutual block, no cross-module reach, no agreement-theorem surface). Full spec in
[`../spec/plan.md`](../spec/plan.md) § walker-dedup family — summary:

The four `expand*` comprehension clause-walkers (`expandClausesWithFuel`/`expandForPairsWithFuel`
→ `ClauseExpansion`; `expandListClausesWithFuel`/`expandListForPairsWithFuel` → `ListClauseExpansion`,
`Eval.lean` ~3541–3690) have BYTE-IDENTICAL `.guard`/`.letClause`/`.forIn` arms + identical
bottom/deferred short-circuit folds. `ClauseExpansion`/`ListClauseExpansion` are structurally
identical 3-ctor sums (`fields`/`items` ⊕ `bottom Value` ⊕ `deferred`) → collapse to one generic
`ClauseOutcome β` (β = `List Field` / `List Value`); the four public defs become thin β-instantiating
wrappers around one `expandClauseChain` + one `expandForPairs`, both generic in β.

**LOAD-BEARING asymmetry the refactor MUST preserve + PIN (verified this audit at the code):** the
struct `[]` arm (`Eval.lean` ~3553-3558) short-circuits a `.bottom`/`.bottomWith` body (D#1a); the
LIST `[]` arm (~3634-3636) does NOT — it wraps ANY body, incl. a bottom, as `.items [evaluatedBody]`
(a one-element list). `out: [for x in [1] {x & "s"}]` → Kue `[_|_]` (1-elem list, bottom element),
which cue renders as the SAME value (`out.0: conflicting values`). So `[_|_]` ≠ `_|_` is CORRECT CUE
list semantics. The combinator MUST take the WHOLE `[]`-arm body-handler as a parameter (a naive
"wrap the body" callback would wrongly make the list twin bottom-propagate). PIN both eval forms +
the export-errors. Gate: byte-identical fixtures + `termination_by` preserved + axiom-clean. Re-confirm
line-refs at slice start (eval region shifts ±tens of lines per slice).

## ALTERNATE leaders (if AD4-1 is set aside)

- **A#6** (`containsBottom` fuel cap 100, `Lattice.lean:146`) — STANDALONE soundness hardening,
  LOW/contained, never implicated in a shipped path.
- **SC-1b** (closed×closed-pattern, MED) / **SC-3** display-residual (LOW, spec-gap; couples AD2-1).
- After AD4-1: **A-EN3 + DRY-1** (locality batch — both call `defFrameRefIndices`), then **AD2-1**.
- **EvalOps extraction** (`Kue/EvalOps.lean`, plan item 2) — parallel-safe mechanical carve; fold the
  E#4 arith classifier/gate (`classifyArithOperand`/`arithmeticDomainResult`/`evalRepeat`) into it.

## CANONICAL PATHS (ground-truth — do NOT re-litigate)

- prod9 stress-test targets: `/Users/chakrit/Documents/prod9/infra/apps/argocd.cue` (PARKED) and
  `.../cert-manager.cue` (content-identical to cue). **Run cert-manager from the infra MODULE dir**
  (`cd .../prod9/infra && {kue,cue} export ./apps/cert-manager.cue`); the bare absolute-path
  invocation errors `import failed: … no cue.mod` for BOTH binaries (a cue.mod-context artifact).
- cue oracle: `/Users/chakrit/go/bin/cue` (v0.16.1) — READ-ONLY, cross-check only.
- kue binary: `.lake/build/bin/kue` (or `lake exe kue`).
- **Python note:** a shell wrapper shadows `python3` with a broken `~/.venv`; use `/usr/bin/python3`
  by absolute path for any generator/oracle scripting.

## STANDING CONTEXT (durable; full detail in CLAUDE.md + guides/slice-loop.md)

- Kue autonomy grant in effect (decide/proceed; resolve forks by philosophy; commit/push on `main`
  when attended). **Spec is authority; `cue` is a fallible cross-check, never a gate** — EXCEPT the
  narrow oracle-as-data-source carve (data, never a gate). Correctness-over-performance.
  **Unattended/AFK → commit, don't push.**
- Orchestrator = thin re-spawner; one subagent per slice; two-phase audit (A then B) every 2–3
  slices — **counter now 0, next audit after 2–3 NEW slices.** Per-slice duties: tests-first; log
  `cue-divergences.md`; flag `cue-spec-gaps.md`; keep `kue-performance.md` current.
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on main tree.
- **argocd / Bug2-5: PARKED** — a stress-test finding, not on the critical path; may never un-park.
