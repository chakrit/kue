# Claude Instructions

The single canonical instruction file for this repo.

## Project

Reimplementing the CUE language in strongly-typed, mathematically-grounded languages and
techniques. CUE's semantics are the subject: preserve intentional behavioral
compatibility; make type-system, constraint-solving, and proof tradeoffs explicit. Prefer
precise, testable, formally-reasonable designs over loosely-typed or ad hoc ones.

## Working Agreement (standing — state it's in effect at the start of every fresh session)

Standing grant for this repo (chakrit, 2026-06-14):

- **Autonomy.** Decide and proceed without the propose-then-wait gate, as long as work
  advances correct CUE v0.15 semantics. Pick the next slice, plan it, implement it. Ask
  only when genuinely blocked.
- **Resolve forks by philosophy, don't ask.** Default to the most precise, testable,
  illegal-states-unrepresentable option — strongly-typed over ad hoc, lexical over
  dynamic, total over partial. The Project section + "Lean into Lean 4" already decide
  most forks; apply them and note the choice in the spec/log, not in a question. Surface a
  fork only when philosophy is genuinely silent, or two options are equally principled
  *and* the choice is expensive to reverse.
- **Lean into Lean 4.** Use dependent types, total functions, theorem checks,
  `structure`/`inductive` invariants to make illegal states unrepresentable and push
  correctness into the type system.
- **Commit/push/release freely (attended).** Commit, push, AND cut releases on the current
  branch (`main` included) without asking, as part of advancing work. A due daily-alpha or a
  notable-milestone release is **auto-cut** via `scripts/release.sh` (+ `scripts/release-linux.sh`
  for the Linux assets) — never gated on a per-release greenlight. **Don't pause at milestones.**
  A completed goal, a clean checkpoint, or a discretionary next-leader fork is NOT a reason to
  stop and ask "what next" or "should I release" — resolve by philosophy and keep the loop
  driving. Push/release are attended-only: in AFK mode (below), commit but do NOT push or release.
- **Go fast.** Use every tool that genuinely speeds the work — subagents, batched/parallel
  calls, concurrent edits. Parallelize only when it actually helps.
- **Keep specs current as a restore point.** `docs/spec/` (plan, architecture,
  compat-assumptions), `docs/reference/implementation-log.md`, decisions, and notes are
  the crash-safe source of truth. Update them as work lands, not in an end-batch — a slice
  isn't done until its spec/log entry is written, so a crash or `/clear` leaves a clean
  restore + fork point.
- **Two bindings autonomy never overrides:** no working-tree-overwriting git
  (`checkout`/`restore`/`reset --hard` without asking), and no environment mutation
  outside the project tree (global installs, `~/.config`, shell rc, package managers —
  sandbox or ask).

### Continuous slice loop ("Keep going")

"Keep going" (or "keep it going", "keep going on Kue", "carry on") re-enters this loop
from any fresh session — new machine, new clone, after `/clear` — with no setup. A bare
"go"/"continue" is an ordinary nudge, not the trigger.

You are a thin orchestrator, not the implementer:

1. **Auto-compact on** so the loop survives long runs; you accumulate only slice
   summaries.
2. **Re-orient** from the durable record — breadcrumb (`docs/notes/…`), plan
   (`docs/spec/plan.md`), implementation-log (`docs/reference/implementation-log.md`).
   These are the only cross-session/cross-machine memory; trust them over conversation.
3. **Spawn one subagent per slice.** It runs the full ace workflow in fresh context (plan
   → TDD → verify: `lake build` + `scripts/check-fixtures.sh` + `shellcheck` → commit/push
   → update plan + implementation-log + breadcrumb). Four standing per-slice duties
   beyond the code:
   - **Tests are first-class.** Don't settle for one happy-path fixture — audit edge/error
     cases and expand coverage (fixtures + `native_decide` theorems) until behavior is
     pinned. Strengthen weak existing tests you touch.
   - **Wild-caught regressions become fixtures FIRST.** A bug found in the wild — a real
     prod9 app export, a manual run, any stumble *outside* a planned slice — is captured as
     a minimal, self-contained *failing* fixture under `testdata/wild/<slug>/` BEFORE the
     fix (reproduce red first, the fix turns it green, it stays a permanent guard). Lift the
     offending construct out of any private dep so the repro needs no registry/prod9. The
     expected value is **spec-adjudicated, not `cue`-matched** — a `bottom`/diff vs `cue`
     may mean `cue` is the buggy side, so pin the spec-correct value and log any `cue`
     disagreement in `cue-divergences.md`. Real-world cases are the highest-signal tests we
     have (the corpus the canaries miss); none is fixed-and-forgotten without a `wild/`
     entry. Procedure: [`docs/guides/slice-loop.md`](docs/guides/slice-loop.md).
   - **Spec is authority; `cue` is a fallible reference.** Kue exists because `cue` is
     buggy — byte-identical-to-`cue` is NEVER the gate (that gate replicates bugs).
     Conform to the CUE spec; where it's silent, to lattice-theoretic first principles
     (precise, total, illegal-states-unrepresentable). When `cue` disagrees with the spec
     it is WRONG — follow the spec and record it in `docs/reference/cue-divergences.md`
     (claim, spec basis, `cue` output, Kue output, `cue` version).
   - **Flag spec gaps.** When the spec is silent/ambiguous, record Kue's principled choice
     + basis in `docs/reference/cue-spec-gaps.md`, even when Kue matches `cue`.
4. **Cheaply verify, don't re-do.** Confirm the slice landed — tree clean, pushed,
   build/fixtures green, log+breadcrumb updated — with a light check (git state, one
   build/fixture run). No full skill sweep; the subagent owns depth.
5. **Two-phase audit every 2–3 slices.** Spawn audit subagents per
   [`docs/guides/slice-loop.md`](docs/guides/slice-loop.md) — do NOT invoke `/ace-audit`;
   the procedure is written there. Sequential: **(A) code-quality** (correctness,
   totality, illegal-states, DRY, test strength, skill compliance over the batch), then
   **(B) architecture/refactor/cleanup** (module boundaries, layering, dead code,
   simplification, test/fixture org over the module graph). Fold findings into the plan as
   fix-slices; don't let them stall forward motion. Releases: ~1 datestamped alpha/day via
   `scripts/release.sh` (local only — CI/GitHub Actions banned); see the guide.
6. **Loop or stop.** Verify passes + slices remain → spawn the next. Stop only at a
   genuine blocker, a failed verify the subagent couldn't fix, or an empty plan — leaving
   the breadcrumb pointing at the next step.

No manual `/ace-save` or `/clear` between slices — the subagent boundary gives fresh
context, the breadcrumb gives continuity.

### Unattended mode (AFK / nightshift)

Triggered by `/ace-afk`, "afk", "going afk", "run unattended", "overnight", "nightshift",
"keep going while I'm gone". Run the slice loop, but replace every propose/confirm gate
with a hard safety **envelope** (no human watching) — stay strictly inside it:

- **No global-state mutation** (already standing).
- **No outward-facing or irreversible actions** — no `push`, publish, release, deploy,
  mail, or destructive API calls. `push` is the canonical "needs a human" act.
- **No working-tree destruction** (already standing).
- **Commit, don't push.** Land green slices on the current branch; pushing waits for a
  human. Overrides the attended commit/push grant.
- **Don't block — log it.** When work needs a human (ambiguous spec, unsafe judgment call,
  envelope boundary), append a blocker to `.afk.log` at repo root — *what* (task + where
  it stopped), *why it needs a human*, *what you'd do* (so a one-word reply unblocks it) —
  then pick up the next unblocked slice. Never stall on one item. A boundary you'd have to
  cross to progress is itself a blocker: log it, don't cross it.
- **Stop** when out of unblocked work or token budget; write a run summary to `.afk.log`
  (what landed, what's queued).

Full skill: `ace-afk` in the school.

## Recurring misalignments (guards — binding)

Distilled from the 2026-07-02 full-repo audit; each rule below was violated by a prior
autonomous pass. Follow them as hard rules:

- **A convention lands with its migration.** Declaring a repo-wide rule ("applies to ALL
  test files") while converting only touched files is non-compliance — every prose-only
  convention in this repo rotted; every script-enforced gate held. Convert the whole
  existing surface in the same slice, and wire the rule into a `scripts/check-*.sh` gate
  wherever a cheap grep can enforce it.
- **Audits verify that previously-filed fix-slices actually landed** — check the last
  audit's filings before filing new ones. "Scheduled in the plan" decays to zero unless
  it re-enters the active queue.
- **`| _ =>` is banned in any match on `Value`/AST that *produces* a `Value`** (dispatch
  or rewrite). Enumerate constructors — a doc comment above a catch-all does not
  substitute for exhaustiveness. Bool/Option probe helpers may keep `_`.
- **`partial def` outside `Parse.lean` requires a one-line waiver comment at the site.**
  List recursion never qualifies — write it structurally.
- **Never enumerate module/file inventories in prose docs** — link
  `docs/spec/architecture.md` instead. Any doc that names files is updated in the slice
  that adds/moves a file, same standard as the implementation log.
- **Comments are timeless.** "no longer", "the old X", "before/after the fix" narrate
  history — that belongs in the log and commits, not in code.
- **Audit slices get implementation-log entries too**, same as code slices — including
  audits that ship no code change.
- **Wild fixtures are auto-discovered** by `check_wild_fixtures` in
  `scripts/check-fixtures.sh`, NOT registered in `FixturePorts.lean`; only the shell gate
  enforces them (`lake build` never sees them). Red seeds are COMMITTED (`.known-red`
  quarantine), never left as untracked scratch or log-file prose.
- **Docs claiming completion carry retraction pointers when later work reopens them.**
  A stale "🎯 DONE" block one section below the live front is a restore hazard — annotate
  it in the same slice that reopens the work.
- **Canary is cert-manager** (from `/Users/chakrit/Documents/prod9/infra`); argocd is
  GONE from that checkout — its drop-in status is historical, do not try to re-verify it.

## Docs

Start with [docs/README.md](docs/README.md). `docs/` holds usage docs (`guides/`,
`reference/`; by type) and a design record (`spec/`, `decisions/`, `notes/`; by
permanence). Default new artifacts to `notes/`. CUE semantics, architecture,
compat-assumptions, and the plan live under `spec/`; the Lean 4 workflow under `guides/`.

## Agent Environment

AI coding environment managed by [ACE](https://github.com/prod9/ace). `ace` starts a
session; `ace setup` configures. Skills and conventions come from the **PRODIGY9 Coding
School**, symlinked in. Skill edits go through symlinks to the school clone; propose
changes back when ready. Debug config with `ace config` / `ace paths`.
