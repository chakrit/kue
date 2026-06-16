# Claude Instructions

The single canonical instruction file for this repo.

## Project

This repository is for reimplementing the CUE language using more strongly typed,
mathematically grounded implementation languages and techniques. Treat CUE's semantics
as the primary subject matter: preserve behavioral compatibility where intentional,
and make type-system, constraint-solving, and proof-related tradeoffs explicit.

Prefer designs that are precise, testable, and amenable to formal reasoning over
loosely typed or ad hoc implementations.

## Working Agreement (standing — surface at the start of every fresh session)

Standing grant for this repo, given by chakrit 2026-06-14:

- **Autonomy.** Decide and proceed without the propose-then-wait gate, so long as the
  work inches Kue toward its goal (correct CUE v0.15 semantics). The ACE
  propose-and-confirm steps are relaxed here: pick the next slice, plan it, and
  implement it. Ask only when genuinely blocked; otherwise think and proceed.
- **Resolve forks by philosophy, don't ask.** A design fork is not a reason to stop.
  Default to the option that is most precise, testable, and amenable to formal reasoning
  — strongly typed over ad hoc, illegal-states-unrepresentable over convention, lexical
  over dynamic, total over partial. The repo's stated preferences (this file's Project
  section; `Lean into Lean 4` below) already decide most forks; apply them and proceed,
  noting the choice and its rationale in the spec/log rather than in a question. Surface a
  fork to the user only when the philosophy is genuinely silent or two options are
  equally principled *and* the choice is expensive to reverse.
- **Lean into Lean 4.** Use the language's facilities — dependent types, total
  functions, theorem checks, `structure`/`inductive` invariants — to make illegal states
  unrepresentable and push correctness into the type system wherever it buys real safety.
- **Commit/push freely.** Standing permission to commit and push (on the current
  branch, `main` included) without asking, as part of advancing the work.
- **Go fast.** Use every tool that genuinely speeds the work: subagents for parallel
  fan-out, batched/parallel tool calls, concurrent independent edits. Parallelize only
  when it actually helps — never when coordination overhead would make the whole slower.
- **Keep specs current as a restore point.** Treat `docs/spec/` (plan, architecture,
  compat-assumptions), `docs/reference/implementation-log.md`, decisions, and notes as
  the crash-safe source of truth. Update them as work lands — not in a batch at the end —
  so a session crash, machine failure, or `/clear` leaves a clean restore point and a
  fork point for subagents. A slice is not done until its spec/log entry is written.
- Autonomy covers direction and execution, not destruction. Two rules still bind, no
  exceptions: no working-tree-overwriting git (`checkout`/`restore`/`reset --hard`
  without asking), and **no environment mutation outside the project tree** (global
  installs, `~/.config`, shell rc, package managers, etc. — sandbox or ask).

At the start of every fresh session, state that this grant is in effect before
beginning work.

### Continuous slice loop ("Keep going")

Goal: from any fresh session — new machine, new clone, after `/clear` — a single
"Keep going" (or close variants: "keep it going", "keep going on Kue", "carry on")
re-enters this autonomous loop with no further setup. Treat the longer phrase as the
deliberate loop trigger; a bare "go"/"continue" stays an ordinary nudge.

The primary agent (you) is a thin orchestrator, not the implementer:

1. **Ensure auto-compact is on** so the loop survives long runs; the orchestrator only
   accumulates slice summaries, never the heavy work.
2. **Re-orient** from the durable record — breadcrumb (`docs/notes/…`), plan
   (`docs/spec/plan.md`), implementation-log (`docs/reference/implementation-log.md`).
   These are the only cross-session/cross-machine memory; trust them over conversation.
3. **Spawn one subagent per slice.** It runs the full ace workflow (plan → TDD → verify:
   `lake build` + `scripts/check-fixtures.sh` + `shellcheck` → commit/push → update the
   plan, implementation-log, and breadcrumb). It works in fresh context, so the heavy
   reads/edits never bloat the orchestrator. Two standing per-slice duties beyond the code:
   - **Tests are first-class.** Don't settle for one happy-path fixture — audit the
     slice's edge/error cases and expand coverage (fixtures + `native_decide` theorems)
     until the behavior is pinned. Strengthen weak existing tests you touch.
   - **Log CUE divergences.** While oracle-checking against `cue`, watch for cases where
     `cue` is buggy or surprising and Kue does the correct thing. Record each in
     `docs/reference/cue-divergences.md` (claim, `cue` output, Kue output, why Kue is
     right, `cue` version).
4. **Cheaply verify, don't re-do.** On return, confirm the slice landed — tree clean,
   pushed, build/fixtures green, log+breadcrumb updated — with a light check (git state,
   one build/fixture run). No full skill-compliance sweep; the subagent owns depth.
5. **Periodic `/ace-audit`.** Every ~3–4 landed slices, or at a family/milestone
   boundary, spawn a subagent running `/ace-audit` over the recently landed work — the
   per-slice cheap check is deliberately shallow; this is the depth pass for
   skill-compliance and implementation quality. Fold its findings into the plan as
   fix-slices. Cadence, not every iteration — don't let it stall forward motion.
6. **Loop or stop.** If verification passes and planned slices remain, spawn the next.
   Stop only at a genuine blocker, a failed verify the subagent couldn't fix, or an empty
   plan — and leave the breadcrumb pointing at the next step.

The subagent keeps specs current as it goes (grant above); the orchestrator's extra job
is the cheap done-check and re-spawn. No manual `/ace-save` or `/clear` between slices —
the subagent boundary gives fresh context, the breadcrumb gives continuity.

## Docs

Start with [docs/README.md](docs/README.md), the index for repo-local docs. `docs/`
holds usage docs (`guides/`, `reference/`; sorted by type) and a design record (`spec/`,
`decisions/`, `notes/`; sorted by permanence). Default new artifacts to `notes/`; see
`docs/README.md` and the per-directory READMEs for routing. The CUE language semantics,
architecture, compatibility assumptions, and implementation plan live under `spec/`; the
Lean 4 workflow guide under `guides/`.

## Agent Environment

This project's AI coding environment is managed by [ACE](https://github.com/prod9/ace).
Run `ace` to start a coding session. Run `ace setup` if not yet configured.

Agent skills and conventions are provided by the **PRODIGY9 Coding School** school
and are symlinked into the active agent environment. Skill edits go through symlinks
into the school clone; propose changes back to the school repo when ready. Run
`ace config` or `ace paths` to debug configuration issues.
