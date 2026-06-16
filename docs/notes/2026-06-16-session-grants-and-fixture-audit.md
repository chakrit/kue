# Session 2026-06-16 — standing grants + fixture-oracle audit

Latest resume breadcrumb. Supersedes the "Next session" section of
[`2026-06-14-session-ace-onboarding.md`](2026-06-14-session-ace-onboarding.md) (kept for
history). Resuming **implementation** next session.

## What was done

- **Single canonical instruction file.** Merged `AGENTS.md` into `CLAUDE.md` and deleted
  `AGENTS.md`; `CLAUDE.md` is now the only agent-instruction surface. README pointer
  updated. (`e0350a7`)
- **Standing grants recorded in `CLAUDE.md` → "Working Agreement".** Given by chakrit, in
  effect for this repo; CLAUDE.md says to restate them at the start of every fresh
  session:
  1. **Autonomy** — decide and proceed without the ACE propose-then-wait gate, so long as
     work advances Kue's goal. Ask only at genuine blocks/forks.
  2. **Lean into Lean 4** — push correctness into the type system (dependent types, total
     functions, invariants, theorem checks).
  3. **Commit/push freely** — current branch, `main` included, no permission needed.
  4. **Go fast** — subagents, batched/parallel calls, concurrent edits where they
     genuinely help.
  5. **Keep specs current as a restore point** — update `docs/spec`, implementation-log,
     decisions, notes as work lands; a slice isn't done until its entry is written.
  - Bans that still bind: no working-tree-overwriting git, no environment mutation outside
    the project tree.
- **Fixture-as-oracle audit — done.** Fanned out 4 subagents across all 82
  `testdata/cue/*` pairs; verdict: the `.expected` suite encodes correct intended CUE
  v0.15 semantics, no reference-binary bugs baked in. Full record in
  [`2026-06-14-fixture-oracle-audit.md`](2026-06-14-fixture-oracle-audit.md). Discharges
  the compatibility ADR's open consequence. (`7dd9498`) Fixtures are now trustworthy as a
  TDD oracle.

Tree clean, all pushed; `main` == `gh/main` at `7dd9498`. (Note: build/fixture suite was
green at the start of session; this session touched only docs + CLAUDE.md, no Lean code,
so no re-verify needed.)

## Next session — implementation focus

**Comprehensions / dynamic fields** (from `docs/spec/plan.md` → Later Slices). This is the
substantive next step; "remaining builtins" is thin without import/package infra (top-level
builtins are already done).

- **Prerequisite called out in the plan:** needs lexical binding identities represented for
  more than same-struct fields. Design that representation *first*, then drive the feature
  TDD.
- **Scope:** multi-module — touches `Kue/Resolve.lean`, `Kue/Eval.lean`, `Kue/Parse.lean`
  together. Cross-module reasoning → consider isolated agents per non-overlapping file
  group per the ACE TDD-execution sizing rule.
- **Discipline:** one slice per commit; subject mirrors slice title; append the completed
  slice to `docs/reference/implementation-log.md`; lean on the type system.

## Verify gate (unchanged)

`lake build` → `scripts/check-fixtures.sh` → `shellcheck scripts/check-fixtures.sh`. The
fixture script prints only `fixture pairs ok` on full success.

## Process note

Working directory persists between Bash calls — a `cd testdata/cue` earlier left a later
`git add` failing on a relative path. Use absolute paths or re-`cd` to repo root.
