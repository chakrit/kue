# RESUME — two-phase audit CLOSED; NEXT = the RESILIENCE / RETROSPECTIVE pass (OVERDUE) (2026-06-23)

Live START-HERE; supersedes `2026-06-23-resume-per-eval-floor-characterized.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md). Spec-conformance backlog:
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Genuinely-open.
Per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md). Failure modes:
[`../reference/failure-modes.md`](../reference/failure-modes.md). Served status page:
[`../../www/index.html`](../../www/index.html).

## Just closed — the two-phase audit (batch `e2d8868..4431597`)

Parser-strictness + release-tooling + per-eval empty-`cache`-skip. **Both phases HEALTHY:**

- **Phase A — HEALTHY (`4431597`).** Cache-skip SOUND (truncating-program byte-identical, cache
  populated only in the `.truncated` arm). Parser over-strictness ruled out. Release-tooling sound.
  3 truncation pins added. No findings filed.
- **Phase B — HEALTHY (this note).** Module graph ACYCLIC + layered, unchanged (the empty-`cache`-
  skip `Eval.lean:3127`, parser arms, `tap-push.sh` add no cross-module edge). `Eval.lean` = 4318
  (below the ~4500 carve watch). Tech-debt sweep clean. `KUE_PROFILE` instrument confirmed
  env-gated + zero-cost-when-off (separate entry point via `evalStructRefsProfile`, reached only
  when `IO.getEnv "KUE_PROFILE"`). Test files all under the ~2000 watch. `kue-performance.md`
  accurate (per-eval frontier CLOSED, floor-characterized). Verdict + the consolidated-complete
  state recorded inline in `plan.md` § Resolved/ruled-out.

**Audit counter RESET to 0.**

## State — the substantive backlog is EXHAUSTED (consolidated-complete)

Two axes complete simultaneously:

- **Spec-conformance backlog EMPTY** — every correctness item RESOLVED; argocd + cert-manager are
  content-identical drop-ins (jq -S diff = 0).
- **Per-eval perf frontier CLOSED** — floor-characterized (argocd ~52s ≈ 486K necessary core evals
  × the irreducible per-meet cost; cache/hash ~2-3%; cross-env frame-sharing a false-share,
  WON'T-FIX). Only remaining lever is user-controllable (flatten/shorten chains).

Released **`v0.1.0-alpha.20260623`** (3 platforms, race-safe tooling; formula live). What remains is
LATENT / CLEANUP only (item-6 tail + SC-3) — none soundness-bearing.

## 🚨 NEXT LEADER — the RESILIENCE / RETROSPECTIVE pass (OVERDUE)

`slice-loop.md` schedules this "every ~3-4 audit cycles, or once failures have accrued." This session
has run **~11 audit cycles (23 Phase-A/B commits) with ZERO retros**, and real operational learnings
have accrued. The NEXT slice is the retrospective: review what broke OPERATIONALLY this session,
record each with its guard in [`../reference/failure-modes.md`](../reference/failure-modes.md) (extend
it — it already holds 9 entries), then fold durable mitigations into `slice-loop.md` + the
subagent-prompt conventions.

**Accrued learnings to pick up (each → a failure-modes entry with its guard):**

1. **Host crash mid-subagent → orchestrator recovers from git state.** A clean tree means the slice
   never landed → full re-run; a partial commit → re-run only the remainder. (Partly covered by the
   existing "Subagent crash" entry — extend it with the orchestrator's clean-tree → full-re-run rule.)
2. **Transient API rate-limit on a subagent → retry NOW**, never wait it out. (Reinforce the existing
   entry's "retry now" guard — it recurred.)
3. **Subagents repeatedly mis-report the prod9 corpus as "absent" — it's a CWD issue.** Must `cd
   /Users/chakrit/Documents/prod9/infra` BEFORE `kue export apps/...`. Already partially mitigated by
   prompt wording; worth a DURABLE convention (a canary-path note in the subagent-prompt template +
   a failure-modes entry).
4. **Design-phase depth predictions falsified by running the real app TWICE.** Phase B "one fix away"
   / "cross-pkg is the same fix" were both wrong against the actual argocd run. Lesson: verify against
   the REAL app, don't trust design-level depth estimates. (Adjacent to the existing "audit perf
   root-cause prediction proves wrong" entry — generalize it to correctness-depth predictions too.)
5. **A subagent claimed "pushed" when it hadn't** — caught by the orchestrator's HEAD==upstream
   check. Codify that check as the standing post-slice verification (the orchestrator MUST compare
   `git rev-parse HEAD` to `@{u}`, never trust the subagent's "pushed" claim).
6. **The over-claim-then-orchestrator-verify pattern** (e.g. the argocd milestone claim verified
   directly by re-running the export). Codify: a milestone/completion claim from a subagent is a
   HYPOTHESIS the orchestrator cheaply re-verifies (git state + one build/fixture/export run) before
   trusting it.

**AFTER the resilience pass:** the item-6 LATENT tail (A2-x/y loader corners, B2-A1/A2 latent,
`module-file-scoped-imports`, `resolveEmbeddedDisjDefault` check, DRY `selectEvaluatedField .disj`) /
SC-3 (display-gap). None soundness-bearing — resolve by philosophy.

## Verify (this audit was doc-only)

No code touched. `plan.md` + this breadcrumb updated; tree was clean at HEAD `4431597` before the
edits. Re-confirm on resume: `git status` clean, HEAD == upstream, `lake build` green.

## Release

`v0.1.0-alpha.20260623` is the latest cut (3 platforms, formula live). Nothing new to ride a release
this round (doc-only audit close).

## Live state end
