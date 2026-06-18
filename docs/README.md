# Kue Documentation

Start here when working in this repository. Durable artifacts live in two clusters that
sort on two different axes — on purpose.

## Usage — how to use what this repo produces (sorted by type)

- [`guides/`](guides/) — task-oriented how-to and getting-started. *How do I do X?*
- [`reference/`](reference/) — lookup facts: API, CLI, config, schemas, glossaries,
  links. *What exactly is X?*

## Design record — how and why this repo is built (sorted by permanence)

- [`spec/`](spec/) — design and architecture; intent and how-it-works. *What we intend,
  and how it fits together.* Living.
- [`decisions/`](decisions/) — dated ADRs. *What we decided, and why.* Frozen.
- [`notes/`](notes/) — research, drafts, exploration. *What we explored.* Disposable.

When unsure: understand-the-system prose → `spec/`; look-it-up facts → `reference/`;
do-a-task steps → `guides/`; a defended ruling → `decisions/`; everything else →
`notes/` (the default).

Docs convention: when a doc references a CUE *language* feature, show a short CUE code
block of the construct (oracle-verified against `cue`); engine-internal references — perf,
memoization, refactors — get none. See [`guides/slice-loop.md`](guides/slice-loop.md).

## Project Documents

- [CUE Language Guide](spec/cue-language-guide.md) — implementation-oriented map of CUE
  semantics: value lattice, unification, disjunction, defaults, bottom, closedness,
  cycles, comprehensions, modules, and compatibility risks.
- [Architecture](spec/architecture.md) — implementation architecture, layering, module
  boundaries, and near-term milestones.
- [Compatibility Assumptions](spec/compat-assumptions.md) — assumptions and deliberately
  narrow choices made while matching CUE behavior.
- [Plan](spec/plan.md) — live roadmap: standing capabilities and the next slices.
- [Status Page](www/index.html) — single human-scannable page: where Kue stands, what
  works, and what's next (a hand-rendered snapshot of the plan).
- [Implementation Log](reference/implementation-log.md) — the full slice-by-slice record
  of completed work, retained for verification.
- [Compatibility Target](decisions/2026-06-14-cue-compatibility-target.md) — why Kue
  targets *correct* CUE v0.15 semantics over bug-for-bug parity.
- [Correctness Over Performance](decisions/2026-06-18-correctness-over-performance.md) —
  why Kue never trades soundness for speed, while keeping basic cases usable.
- [Lean 4 Guide](guides/lean4-guide.md) — repo-local Lean 4 quickstart: Lake setup,
  module layout, proof workflow, and how to model CUE semantics in Lean.
- [Performance Guide](guides/kue-performance.md) — how to write CUE that Kue evaluates
  fast: which patterns are expensive in Kue, why, and the faster shapes.

## Reading Order

1. Read the [CUE language guide](spec/cue-language-guide.md) to understand what Kue must
   preserve.
2. Read the [Lean 4 guide](guides/lean4-guide.md) to understand how this repo should
   model and prove those semantics.
3. Read the [architecture](spec/architecture.md) before adding implementation modules.
4. Check the [plan](spec/plan.md) for the current slice before editing code.
5. When matching CUE behavior, record narrow choices in
   [compatibility assumptions](spec/compat-assumptions.md).
