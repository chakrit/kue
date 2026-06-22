# Failure Modes & Guards

Operational pitfalls hit while running Kue's autonomous slice loop, each paired with the
guard that prevents recurrence. Scanned — and appended to — on the periodic **resilience
pass** (see [`../guides/slice-loop.md`](../guides/slice-loop.md)). This file is for
*process/operational* failures; code-level bug findings live in the audit sections of
`plan.md` and the implementation log, not here.

Format per entry: **Symptom** (how it shows up) · **Seen** (concrete instance) · **Guard**
(what prevents it).

## Subagent crash / transient API error loses uncommitted work

- **Symptom:** a subagent dies mid-run (e.g. API "Overloaded") and returns only an error;
  everything it had not yet committed is gone.
- **Seen:** 2026-06-18 — an audit + perf-diagnosis subagent ran ~89 tool-uses (~17 min)
  then died on "Overloaded" at the final synthesis. Nothing was committed → total loss,
  re-run from scratch.
- **Guard:** commit at internal checkpoints, not only at the end (slice-loop "Commit at
  checkpoints"). Audits commit findings to `plan.md` *before* composing their summary. On a
  crash the orchestrator checks git state (clean? a partial commit?) before re-running, and
  re-runs only the lost remainder. Transient API errors → retry now, never wait it out.

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

## An audit's perf root-cause prediction proves wrong

- **Symptom:** an audit declares "the regression is REDUNDANT — a cheap fix reclaims most of
  it," the cheap fix lands sound, and the real app is unchanged.
- **Seen:** 2026-06-18 — the link-3/4 audit modeled Pass-2 per-field redundancy as the
  dominant cost and predicted a cheap selective-re-eval reclaims the cert-manager 31s→92s.
  The fix shipped (sound, byte-identical, helps many-unrelated-field defs) but cert-manager
  was statistically unchanged — the dominant cost was broader **frame-id divergence**, not
  the modeled redundancy.
- **Guard:** treat an audit's perf root-cause as a HYPOTHESIS, not a fact. Before building a
  "cheap fix" on it, confirm with a direct before/after wall-clock + eval-count measurement
  on the REAL target (not only a synthetic repro that exhibits the modeled effect). A fix
  validated against a synthetic repro may be correct yet not move the real app.

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
  `TwoPassTests` in `plan.md` item 3). Convention applies to ALL `Kue/Tests/*.lean`; flagged
  for `ace-school` as a test-file `general-coding` rule.
