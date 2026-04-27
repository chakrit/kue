# Kue Documentation

Start here when working in this repository.

## Project Guides

- [Lean 4 Guide for Kue](lean4-guide.md): repo-local Lean 4 quickstart for future agents, including Lake setup, suggested module layout, proof workflow, and how to model CUE semantics in Lean.
- [CUE Language Guide for Kue](cue-language-guide.md): implementation-oriented map of CUE semantics, including the value lattice, unification, disjunction, defaults, bottom, closedness, cycles, comprehensions, modules, and compatibility risks.
- [Kue Architecture](architecture.md): high-level implementation architecture, layering, module boundaries, and near-term milestones.
- [Kue Plan](plan.md): current implementation slice, TDD checkpoints, and later slices.

## Reading Order

1. Read the CUE language guide to understand what Kue must preserve.
2. Read the Lean 4 guide to understand how this repo should model and prove those semantics.
3. Read the architecture guide before adding implementation modules.
4. Check the plan for the current slice before editing code.
5. Return to this index when adding new design notes so the documentation remains discoverable from `AGENTS.md`.
