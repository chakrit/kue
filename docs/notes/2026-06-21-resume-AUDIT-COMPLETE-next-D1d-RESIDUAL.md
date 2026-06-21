# RESUME HERE — D#1d-RESIDUAL re-diagnosed + BLOCKED (2026-06-21); next code leader = AD2-1

Live START-HERE pointer; supersedes `2026-06-20-resume-DYN-DEF-1-done-AUDIT-DUE.md` (deleted).
Authoritative live roadmap: [`../spec/plan.md`](../spec/plan.md) (capabilities, ranked backlog,
audit verdicts) + [`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md)
§ Consolidated fix backlog.

## SLICE 1 (2026-06-21): D#1d-RESIDUAL attempted → RE-DIAGNOSED + BLOCKED (investigation, no code)

D#1d-RESIDUAL was attempted as the new-batch leader. Instrumented diagnosis (reverted clean, tree at
HEAD, build green — `git diff` empty) found Phase-B's caller-lift shape is NECESSARY-but-INSUFFICIENT
and the true blocker is one layer DOWN in the lattice:

- **The body lift is a ONE-LINER, not the multi-site `ClauseOutcome` arm Phase B sketched.** Routing a
  `.structComp` body to the existing `.deferred` outcome (`onExhausted` `_ =>` → `.structComp ..
  => .deferred`) HOLDS both witnesses byte-cue-faithfully. A payload arm carrying the EVALUATED
  residual would be WRONG (freezes the transient case).
- **The transient `add.#patch` case resolves WITHOUT the lift** — the embed-narrowing FORCE path
  (`meetEmbeddingsWithFuel`/`forceClosureWithConjunct`) re-evals the UNEVALUATED body with `kind`
  spliced concrete; the new arm never fires on the narrowed pass. The fixpoint converges; Phase-B's
  transient-vs-terminal worry is moot.
- **REAL BLOCKER: a held `.structComp` residual cannot survive a `meet`.** `meetCore`
  (`Lattice.lean:460-461`) bottoms any `.structComp`. The 7-TwoPassTests break is the UNNARROWED
  embed (`#Outer: {#Inner,…}` with no use-site `kind`) bottoming, not the narrowed `out`. Minimal:
  `a: {for k in [string] {(k):1}}; b: a & {x:2}` → kue `b: _|_`, cue `b: a & {x:2}` (held).
- **Filed prerequisite MEET-RESID-1** (defer-meet of an unresolved `.structComp` to `.conj`, two-pass
  re-resolution, gated to UNRESOLVED structComp only). D#1d-RESIDUAL DEMOTED behind it. Full detail:
  plan.md D#1d-RESIDUAL entry (★★ Re-diagnosis) + MEET-RESID-1 entry + the implementation-log
  investigation entry.

**Revised leader order: (1) AD2-1 → (2) MEET-RESID-1 (design first) → (3) D#1d-RESIDUAL (one-line
once MEET-RESID-1 lands) → (4) LOW tail.**

## Audit state — **COMPLETE. Counter = 0** (slice 1 was a no-code investigation; counter unmoved).
**Next audit after 2–3 NEW code slices** (AD2-1 will be slice 1 of code in the batch).

The two-phase audit for the A-EN3-DYN + DYN-DEF-1 dyn-field batch is **DONE** — both phases
landed, AUDIT-DUE is CLEARED:

- **Phase A** (`503955b`) — adversarial dyn-field probe: both batch fixes SOUND; FIXED 2 new
  wrong-results inline (D#1d comprehension-body tail/pattern drop; default-disjunction dyn-field
  label collapse); FILED 1 (D#1d-RESIDUAL).
- **Phase B** (`90f43f5`) — architecture/whole-graph: HEALTHY. **FOUR-classifier RULING:** kept the
  four verdict functions (`classifyArithOperand`/`classifyGuard`/`classifyDefinedness`/
  `classifyDynLabel`) SEPARATE (option a — the partition disagreement is WORSE at four; `.prim` now
  splits four ways), extracted ONLY the shared default-collapse pre-step `collapseDefaultDisjunction`
  inline (option b — was duplicated 4×: three named wrappers + one un-named inline guard match),
  rejected the shared concreteness partition (option c). Byte-identical; full gate green.

Scope audited: A-EN3-DYN (`4cd8fbe`) + DYN-DEF-1 (`46e9871`) + Phase-A inline fixes (`503955b`).
**Both dyn-field Violations (A-EN3-DYN, DYN-DEF-1) are DONE + audited sound.**

## NEXT — the next code leader (correctness-first; REVISED 2026-06-21 after the D#1d-RESIDUAL slice)

1. **AD2-1 (LOW-MED — disjunction-normalizer dedup; FILE as a slice, do NOT apply inline) — NEW
   LEADER.** Promoted because D#1d-RESIDUAL is blocked on MEET-RESID-1 (below). The SOLE remaining
   walker/normalizer-dedup-family member. Value-sound (display-only). Flips two NAMED theorem pins +
   the SC-3 display contract — a human signs off the contract rename. Couples with SC-3. Full spec:
   plan.md § walker-dedup, AD2-1.
2. **MEET-RESID-1 (MEDIUM — prerequisite for D#1d-RESIDUAL; DESIGN-FIRST).** A `meet`/`&`/embed of an
   UNRESOLVED `.structComp` residual must HOLD (defer to `.conj [left,right]`, re-resolved when the
   residual's blocker clears) instead of `.bottom`. cue holds `a & {x:2}` where `a` is a residual
   comprehension; kue bottoms it (`meetCore` `Lattice.lean:460-461`). Multi-site (`evalConjWithFuel`
   fold `Eval.lean:3123`, embed-meet, possibly `meetCore`), two-pass re-resolution, delicate soundness
   boundary (gate to UNRESOLVED `.structComp` only — never collapse a real struct-vs-nonstruct type
   error). Witnesses: `b: a & {x:2}` (a residual); the unnarrowed `#Outer: {#Inner,…}` embed. Full
   spec: plan.md MEET-RESID-1 entry.
3. **D#1d-RESIDUAL (MEDIUM wrong-result Violation) — BLOCKED behind MEET-RESID-1.** Once that lands,
   this collapses to a ONE-LINE `onExhausted` arm: `expandClausesWithFuel`'s struct `onExhausted`
   (`Eval.lean:~3611`) `| .structComp .. => .deferred` (re-emit the original `.comprehension` node) +
   fixtures (`for-abstract-key`, `for-nested-deferred-if` → held, `@d.i` display per D#1b) + the two
   resolve/hold pins. The Phase-B "lift via a new `ClauseOutcome` payload arm" sketch is SUPERSEDED —
   see the ★★ Re-diagnosis in plan.md. The LIST twin is already correct.

Then the LOW tail (plan item 6), **A#6** (`containsBottom` fuel cap, standalone), **EvalOps
extraction** (plan item 2, parallel-safe mechanical carve).

## CANONICAL PATHS (ground-truth — do NOT re-litigate)

- prod9 stress-test targets: `/Users/chakrit/Documents/prod9/infra/apps/argocd.cue` (PARKED) and
  `.../cert-manager.cue` (semantically identical to cue; byte-differs only in JSON key ordering —
  a pre-existing artifact, NOT a regression). **Run cert-manager from the infra MODULE dir**
  (`cd .../prod9/infra && {kue,cue} export ./apps/cert-manager.cue`); the bare absolute-path
  invocation errors `import failed: … no cue.mod` for BOTH binaries (a cue.mod-context artifact).
  Semantic compare: `/usr/bin/python3 -c "import json;print(json.load(open(a))==json.load(open(b)))"`.
- cue oracle: `/Users/chakrit/go/bin/cue` (v0.16.1) — READ-ONLY, cross-check only.
- kue binary: `.lake/build/bin/kue` (or `lake exe kue`). FixturePorts lives at
  `Kue/Tests/FixturePorts.lean` (NOT `Kue/FixturePorts.lean` — the guide's path is stale).
- **Python note:** a shell wrapper shadows `python3` with a broken `~/.venv`; use `/usr/bin/python3`
  by absolute path for any generator/oracle scripting.
- **Baseline-compare trick (no working-tree risk):** `git worktree add -d /tmp/kue-head HEAD` →
  `cd /tmp/kue-head && lake build` → compare its binary → `git worktree remove --force
  /tmp/kue-head` (run the remove from the kue repo dir, not prod9). Confirms a change did/didn't
  alter a prod-app output without touching the main tree.

## STANDING CONTEXT (durable; full detail in CLAUDE.md + guides/slice-loop.md)

- Kue autonomy grant in effect (decide/proceed; resolve forks by philosophy; commit/push on
  `main` when attended). **Spec is authority; `cue` is a fallible cross-check, never a gate** —
  EXCEPT the narrow oracle-as-data-source carve (data, never a gate).
  Correctness-over-performance. **Unattended/AFK → commit, don't push.**
- Orchestrator = thin re-spawner; one subagent per slice; two-phase audit (A then B) every 2–3
  slices — **counter now 0; next audit after 2–3 new slices.** Per-slice duties: tests-first; log
  `cue-divergences.md`; flag `cue-spec-gaps.md`; keep `kue-performance.md` current.
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on main tree.
- **argocd / Bug2-5: PARKED** — a stress-test finding, not on the critical path; may never un-park.
