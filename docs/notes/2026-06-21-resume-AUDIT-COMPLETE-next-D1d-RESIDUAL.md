# RESUME HERE — two-phase AUDIT COMPLETE (2026-06-21); next code leader = D#1d-RESIDUAL

Live START-HERE pointer; supersedes `2026-06-20-resume-DYN-DEF-1-done-AUDIT-DUE.md` (deleted).
Authoritative live roadmap: [`../spec/plan.md`](../spec/plan.md) (capabilities, ranked backlog,
audit verdicts) + [`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md)
§ Consolidated fix backlog.

## Audit state — **COMPLETE. Counter = 0. Next audit after 2–3 NEW slices.**

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

## NEXT — the next code leader (correctness-first)

1. **D#1d-RESIDUAL (MEDIUM wrong-result Violation) — NEXT LEADER.** A comprehension body that
   evaluates to a HELD RESIDUAL (`.structComp` with a held dyn field on a non-concrete key, OR a
   nested deferred `if`/`for`) is silently dropped to `{}`; cue holds it under eval, errors incomplete
   under export. Witnesses (eval): `for-abstract-key`, `for-nested-deferred-if`. **Phase-B discriminator
   insight (READ before the slice):** the residual-vs-transient distinction is the two-pass FIXPOINT,
   NOT a flag on `.structComp` (a static phase tag would be an illegal-states hazard — the next pass
   could contradict it). The blanket `.structComp → .deferred` arm broke 7 TwoPassTests because
   `.structComp` is ALSO the transient two-pass carrier (`add.#patch` is transiently `.structComp` then
   concretes). **Principled fix:** do NOT teach `onExhausted` to discriminate (it runs at pass-1, can't
   see final resolvedness); LIFT the body residual into the ENCLOSING struct's
   `withDeferredComprehensions` deferred list at the CALLER of `expandClausesWithFuel`
   (`Eval.lean:~2935`/`~3482`, which see the enclosing frame + drive the two-pass) via a NEW
   `ClauseOutcome` deferred-payload arm. Multi-site (`ClauseOutcome` + both `onExhausted` handlers +
   both struct-eval call sites) → a real slice, FILED-not-inline. The LIST twin is already correct.
   Full spec: plan.md § walker-dedup, D#1d-RESIDUAL entry.
2. **AD2-1 (LOW-MED — disjunction-normalizer dedup; FILE as a slice, do NOT apply inline).** The
   SOLE remaining walker/normalizer-dedup-family member. Value-sound (display-only). Flips two NAMED
   theorem pins + the SC-3 display contract — a human signs off the contract rename. Couples with SC-3.
   Full spec: plan.md § walker-dedup, AD2-1.

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
