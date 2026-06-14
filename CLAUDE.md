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
  implement it. Ask only when genuinely blocked or at a real fork; otherwise think and
  proceed.
- **Lean into Lean 4.** Use the language's facilities — dependent types, total
  functions, theorem checks, `structure`/`inductive` invariants — to make illegal states
  unrepresentable and push correctness into the type system wherever it buys real safety.
- **Commit/push freely.** Standing permission to commit and push (on the current
  branch, `main` included) without asking, as part of advancing the work.
- **Go fast.** Use every tool that genuinely speeds the work: subagents for parallel
  fan-out, batched/parallel tool calls, concurrent independent edits. Parallelize only
  when it actually helps — never when coordination overhead would make the whole slower.
- Autonomy covers direction and execution, not destruction. Two rules still bind, no
  exceptions: no working-tree-overwriting git (`checkout`/`restore`/`reset --hard`
  without asking), and **no environment mutation outside the project tree** (global
  installs, `~/.config`, shell rc, package managers, etc. — sandbox or ask).

At the start of every fresh session, state that this grant is in effect before
beginning work.

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
