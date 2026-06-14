# Agent Instructions

## Project

This repository is for reimplementing the CUE language using more strongly typed,
mathematically grounded implementation languages and techniques. Treat CUE's semantics
as the primary subject matter: preserve behavioral compatibility where intentional,
and make type-system, constraint-solving, and proof-related tradeoffs explicit.

Prefer designs that are precise, testable, and amenable to formal reasoning over
loosely typed or ad hoc implementations.

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
