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

- [CUE Language Guide](reference/cue-language-guide.md) — implementation-oriented map of
  CUE semantics: value lattice, unification, disjunction, defaults, bottom, closedness,
  cycles, comprehensions, modules, and compatibility risks.
- [Architecture](spec/architecture.md) — implementation architecture, layering, module
  boundaries, and near-term milestones.
- [Compatibility Assumptions](spec/compat-assumptions.md) — assumptions and deliberately
  narrow choices made while matching CUE behavior.
- [Plan](spec/plan.md) — live roadmap: standing capabilities and the next slices.
- [Spec-Conformance Audit](spec/spec-conformance-audit.md) — the spec-first re-audit of
  every `cue`-grounded behavior; owns the consolidated conformance fix backlog.
- [Implementation Log](reference/implementation-log.md) — the full slice-by-slice record
  of completed work, retained for verification.
- [CUE Divergences](reference/cue-divergences.md) — where `cue` disagrees with the spec
  and Kue deliberately follows the spec; one row per divergence.
- [CUE Spec Gaps](reference/cue-spec-gaps.md) — where the spec is silent and Kue's
  principled choice is recorded, even when Kue matches `cue`.
- [Failure Modes & Guards](reference/failure-modes.md) — operational pitfalls hit running
  the autonomous loop (crashes, contention, stale docs), each with its guard; appended on
  the periodic resilience pass.
- [Compatibility Target](decisions/2026-06-14-cue-compatibility-target.md) — why Kue
  targets *correct* CUE v0.15 semantics over bug-for-bug parity.
- [Correctness Over Performance](decisions/2026-06-18-correctness-over-performance.md) —
  why Kue never trades soundness for speed, while keeping basic cases usable.
- [Distribution: Prebuilt + Local Release](decisions/2026-06-16-distribution-prebuilt-local-release.md)
  — why Kue ships prebuilt arm64 binaries cut by a local script, not CI.
- [Implementation Language: Lean 4](decisions/2026-06-17-implementation-language-lean4.md)
  — why Kue stays on Lean 4 over an OCaml/Haskell/Rust rewrite, and what would flip it.
- [Oracle as Data Source](decisions/2026-06-20-oracle-as-data-source.md) — the `cue`
  binary may seed generated data for externally-standardized domains, never gate
  correctness.
- [Numeric Model: Exact Decimal, No Float](decisions/2026-06-22-numeric-model-exact-decimal-no-float.md)
  — why `math.Pow`/`math.Sqrt` cover their real domain in exact decimal; Float/NaN banned.
- [Lean Engine in Go via cgo](decisions/2026-06-25-lean-engine-embedded-in-go-via-cgo.md)
  — the Go-shell + Lean-engine FFI spike: feasibility-proven, REJECTED (leaky seam).
- [Registry Fetch via curl Subprocess](decisions/2026-06-25-registry-fetch-via-curl-subprocess.md)
  — why OCI module fetch shells out to `curl` instead of FFI or an HTTP library.
- [Lean 4 Guide](guides/lean4-guide.md) — repo-local Lean 4 quickstart: Lake setup,
  module layout, proof workflow, and how to model CUE semantics in Lean.
- [Performance Guide](guides/kue-performance.md) — how to write CUE that Kue evaluates
  fast: which patterns are expensive in Kue, why, and the faster shapes.

## Human-facing

These design docs are the agent/developer record, read in-repo. The human-facing status
*site* is separate — a served HTML page at [`../www/index.html`](../www/index.html), not
part of this design record. Keep the two audiences apart.

## Reading Order

1. Read the [CUE language guide](reference/cue-language-guide.md) to understand what Kue
   must preserve.
2. Read the [Lean 4 guide](guides/lean4-guide.md) to understand how this repo should
   model and prove those semantics.
3. Read the [architecture](spec/architecture.md) before adding implementation modules.
4. Check the [plan](spec/plan.md) for the current slice before editing code.
5. When matching CUE behavior, record narrow choices in
   [compatibility assumptions](spec/compat-assumptions.md).
