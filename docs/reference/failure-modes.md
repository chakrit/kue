# Failure Modes & Guards

Operational pitfalls hit while running Kue's autonomous slice loop, each paired with the
guard that prevents recurrence. Scanned — and appended to — on the periodic **resilience
pass** (see [`../guides/slice-loop.md`](../guides/slice-loop.md)). This file is for
*process/operational* failures; code-level bug findings live in the audit sections of
`plan.md` and the implementation log, not here.

Format per entry: **Symptom** (how it shows up) · **Seen** (concrete instance) · **Guard**
(what prevents it).

## Subagent crash / transient API error loses uncommitted work

- **Symptom:** a subagent dies mid-run (e.g. API "Overloaded", a host-process exit, or a
  0-token / 0-tool-use rate-limit return) and yields no usable result; everything it had
  not yet committed is gone.
- **Seen:** 2026-06-18 — an audit + perf-diagnosis subagent ran ~89 tool-uses (~17 min)
  then died on "Overloaded" at the final synthesis. Nothing was committed → total loss,
  re-run from scratch. 2026-06-23 — the Claude Code HOST process exited mid-subagent (its
  in-process state lost), and separately a subagent returned 0 tokens / 0 tool-uses on a
  transient API rate-limit.
- **Guard:** commit at internal checkpoints, not only at the end (slice-loop "Commit at
  checkpoints"). Audits commit findings to `plan.md` *before* composing their summary.
  **Recover from GIT STATE, never from in-process memory** (which a host crash also
  destroys): compare `git rev-parse HEAD` to `@{u}` + `git status --porcelain` against the
  last known-good. Nothing committed since known-good AND tree clean → the slice never
  landed → **FULL re-run** (nothing to salvage). Partial commits exist → re-run ONLY the
  lost remainder. A 0-token / rate-limit / "Overloaded" return is the SAME class → **retry
  NOW** (re-spawn immediately); never wait-it-out, never "it'll pass once the limit ages".

## Parallel subagents on a shared working tree clobber each other

- **Symptom:** two concurrent subagents stage/commit each other's files, or race the git
  index lock.
- **Seen:** 2026-06-18 — docs subagents (status page, CUE snippets) run alongside a live
  implementation slice on the same tree.
- **Guard:** parallelize only on FILE-DISJOINT work; each subagent `git add`s ONLY its own
  paths (never `git add -A`) and commits promptly so windows don't overlap. Same-branch
  commits stack linearly (fast-forward push); the only real race is the index lock (retry).
  Use git-worktree isolation when disjointness can't be guaranteed.

## Byte-identical fixtures miss a latent bug at a different fuel / condition

- **Symptom:** the fixture gate is green, but a real bug hides at an unexercised fuel level
  or edge condition.
- **Seen:** 2026-06-18 — the fuel-saturation cache misclassified low-fuel-truncated values
  as saturated; fixtures (evaluated at fuel 100) never truncated there, so it shipped latent
  until an adversarial LOW-fuel probe in the next audit caught it (a real corruption).
- **Guard:** soundness audits probe the EDGE (low fuel, empty inputs, dying disjunction
  arms), not just the fixture happy path. A soundness argument must EXHAUSTIVELY enumerate
  its assumptions (e.g. *every* truncation source), never assert "these are the only ones"
  without checking.

## A catch-all `_` silently swallows a new Value / AST constructor

- **Symptom:** code compiles, but a new constructor falls into a wildcard arm and yields a
  wrong-but-not-crashing result.
- **Seen:** 2026-06-18 — `Value.listComprehension` was swallowed by a `Resolve` catch-all;
  every list comprehension bottomed until the explicit arm was added.
- **Guard:** Phase A checks every NEW constructor at EVERY match site with no swallowing
  catch-all (a standing audit item; reinforced here). Prefer exhaustive matches over `_`.

## A breadcrumb / handoff misdiagnoses the root cause

- **Symptom:** a slice built on a handed-down diagnosis chases the wrong fix.
- **Seen:** 2026-06-18 — "cross-def cache collision" (really a missing comprehension
  expansion); "force doesn't recurse" (really closedness + a parser misclassification).
  Both corrected by an independent audit/bisect *before* the wrong fix shipped.
- **Guard:** validate a root cause with an independent audit and a minimal OFFLINE bisect
  repro before a fix-slice builds on it. Never trust a recalled diagnosis over a fresh
  oracle check.

## Durable docs silt up / go stale

- **Symptom:** `plan.md` bloats with superseded audit sections; the status page or
  breadcrumbs drift from reality.
- **Seen:** 2026-06-18 — `plan.md` reached 4103 lines (distilled to ~180); the status page
  lagged the backlog; an early breadcrumb still claimed a resolved decision was open.
- **Guard:** the periodic plan-hygiene pass distills `plan.md` and refreshes
  `www/index.html`; each slice's breadcrumb supersedes the prior START-HERE; stale
  breadcrumbs get a one-line SUPERSEDED banner.

## A sound correctness fix regresses performance

- **Symptom:** a correct, byte-identical-output change makes a basic case markedly slower.
- **Seen:** 2026-06-18 — the link-3/4 parser collapse routed the dominant prod9 def shape
  through a heavier two-pass embed re-eval; cert-manager went ~31s → ~92s (output unchanged).
- **Guard:** correctness ships regardless (per the correctness-over-performance decision),
  but the regression is logged in `kue-performance.md` and filed as a perf fix-slice;
  re-probe a flagship real-app's wall-clock after any eval-path change so regressions are
  caught, not discovered later.

## A design-level prediction (perf OR correctness-depth) proves wrong against the real app

- **Symptom:** an audit / design subagent declares a depth estimate — "the regression is
  REDUNDANT, a cheap fix reclaims it" (perf) or "argocd is one fix away" / "the cross-package
  case is the same fix" (correctness) — from design-level analysis alone, and the real app
  falsifies it when actually run.
- **Seen:** 2026-06-18 — the link-3/4 audit modeled Pass-2 per-field redundancy as the
  dominant cost and predicted a cheap selective-re-eval reclaims the cert-manager 31s→92s.
  The fix shipped (sound, byte-identical, helps many-unrelated-field defs) but cert-manager
  was statistically unchanged — the dominant cost was broader **frame-id divergence**, not
  the modeled redundancy. 2026-06-23 — a design subagent TWICE predicted "argocd is one fix
  away" / "cross-package is the same fix"; both were empirically WRONG when the next slice
  actually ran `kue export apps/argocd.cue` (another layer sat behind the predicted one).
- **Guard:** treat ANY design-level depth/blocker claim — perf OR correctness — as a
  HYPOTHESIS, not a fact. Before building on it, confirm EMPIRICALLY by running the REAL app
  (canary export, not a synthetic repro that merely exhibits the modeled effect). An honest
  "one confirmed remaining layer; unknown if more behind it" beats a confident design
  estimate. A fix validated against a synthetic repro may be correct yet not move the real app.

## Theorems silently dead — build stays green, kernel never checks them

- **Symptom:** a block of `native_decide` theorems is never kernel-checked, yet `lake build`
  is GREEN. Coverage silently evaporates; a regression in the pinned mechanism would not be
  caught. Behavior may still be correct (independent fixtures pin it), masking the gap.
- **Seen:** 2026-06-23 (Phase A) — `TwoPassTests.lean` (1851 lines) had FOUR `/-- … -/` block
  doc-comments left UNTERMINATED (missing the closing `-/`). Lean's nested block comment runs
  to the next stray `-/`, so each unterminated header SWALLOWED every theorem until the next
  one — ~140 of ~150 theorems became comment text. Build stayed green (commented-out theorems
  aren't checked; dead theorems aren't errors). The `.cue/.expected` fixtures independently
  pinned the behavior, so the export was still correct — which is exactly why it went unnoticed.
- **Guard:** THREE layers, defense-in-depth (Phase B `0150095`): (1) **`--` LINE comments for
  test-file section headers**, never `/-- -/`/`/-! -/` block comments — a line comment
  self-terminates at EOL and structurally CANNOT swallow the next declaration. (2) An
  end-of-file **coverage tripwire**: `#check @<last-theorem-per-section>` for each section — a
  swallowed section makes its anchor an unknown identifier, so `#check` fails to ELABORATE = a
  hard build error, not a silent green. (3) A **size limit** on test modules — a file too large
  to eyeball hides this; split when it grows (the `slice-loop.md` test-org pass, scheduled for
  `TwoPassTests` in `plan.md` item 3). Flagged for `ace-school` as a test-file
  `general-coding` rule. **Honest coverage status (2026-07-02 audit):** the convention is
  binding for NEW and TOUCHED test files, but the repo-wide retrofit never happened — only
  ~4 of 37 `Kue/Tests/*.lean` files carry tripwires, and ~23 still use block-comment
  headers (build currently green; nothing swallowed today). The retrofit plus a machine
  gate (`scripts/check-test-health.sh`) is a filed fix-slice in `plan.md`'s Live Backlog;
  until it lands, the unprotected files have NO guard against a recurrence.

## Prose-only conventions rot; script-enforced gates hold

- **Symptom:** a convention declared "applies to ALL X" is honored only on new/touched
  files; the existing corpus never migrates, and the durable doc overstates the protection
  actually in force.
- **Seen:** 2026-07-02 audit — the TEST-HEALTH convention above was declared for ALL
  `Kue/Tests/*.lean` (Phase B `0150095`), but later agents applied it only to files they
  touched: ~4/37 files have coverage tripwires, ~23 retain block-comment headers, and no
  script checks any of it. The doc read as if the guard were repo-wide.
- **Guard:** land a convention WITH its migration in the same slice — a declared-for-ALL
  rule that ships without retrofitting the existing corpus is a wish, not a guard. Wire
  every such convention into a machine gate (`scripts/check-*.sh`) so drift fails the
  verify step instead of accumulating silently; prose in a doc binds only the agent that
  wrote it.

## prod9 canary mis-reported "absent" — it's a wrong-CWD artifact, not a missing corpus

- **Symptom:** a subagent runs a prod9 canary, gets "not found" / "no such file", and
  concludes the prod9 corpus is absent — abandoning the real-app cross-check.
- **Seen:** 2026-06-23 — subagents repeatedly reported the corpus absent. Root cause: CUE
  module resolution is CWD-sensitive; `kue export apps/cert-manager.cue` only resolves its
  module from `/Users/chakrit/Documents/prod9/infra`. Run from the Kue repo root (where
  `apps/...` doesn't exist), it 404s — the corpus is there, the cwd was wrong.
- **Guard:** ALWAYS run prod9 canaries from the infra root, in a subshell so cwd doesn't
  leak: `( cd /Users/chakrit/Documents/prod9/infra && kue export apps/<app>.cue )`. The
  corpus DOES exist there (READ-ONLY — never write into it). "Not found" means wrong cwd,
  NOT absent — fix the cwd, do not conclude the corpus is gone. Codified in slice-loop's
  canary convention + the subagent-prompt template.

## A subagent claims "pushed" when HEAD is still ahead of upstream

- **Symptom:** a slice subagent reports "pushed", but `git push` never ran or failed; HEAD
  is ahead of `@{u}` and the commit lives only in the local tree.
- **Seen:** 2026-06-23 — a subagent reported the slice pushed; the orchestrator's cheap
  done-check (`git rev-parse HEAD` vs `@{u}`) caught HEAD ahead of upstream.
- **Guard:** TWO layers. (1) The orchestrator's MANDATORY per-slice done-check: compare
  `git rev-parse HEAD` to `git rev-parse @{u}` — equal is the only "pushed"; never trust the
  subagent's word. (2) Slice subagents confirm the actual `git push` OUTPUT (the
  `<branch> -> <branch>` line, e.g. `main -> main`) before reporting "pushed" — a claim
  without that line is unverified.

## A milestone / soundness claim over-stated — orchestrator must independently re-verify

- **Symptom:** a subagent reports a high-stakes result ("argocd exports byte-identical",
  "the cache is sound", "released") that, if wrong, corrupts the durable record or ships a
  bug — and the report is the only evidence.
- **Seen:** 2026-06-23 — a milestone "argocd exports byte-identical" claim; the orchestrator
  re-ran the export + `jq -S` diff directly and confirmed (diff = 0) rather than trusting the
  report.
- **Guard:** the orchestrator INDEPENDENTLY re-verifies milestone-grade and soundness-grade
  claims, not just routine ones — re-run the canary/export, the build, the fixture gate.
  Claims that warrant direct orchestrator verification: **milestones** (byte-identical /
  content-identical real-app drop-ins), **soundness gates** (perf-fix byte-identity, cache
  correctness), **pushes** (HEAD==upstream, above), **releases** (asset published, formula
  patched). A subagent's high-stakes claim is a HYPOTHESIS the orchestrator cheaply confirms
  before it enters the durable record.
