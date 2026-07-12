# Kue Documentation

Durable artifacts. **File by the gate below** — walk it top to bottom and stop at the
first yes. The bottom (`scratch/`) charges a toll, so nothing lands there by default.

## Where does this go?

1. A ruling you'd defend if someone reopened it? → [`decisions/`](decisions/) — dated,
   never edited.
2. Third-party facts you keep to look up (CUE's own semantics, an external API/CLI)? →
   [`vendor/`](vendor/) — link-first, mark provenance.
3. A how-to — using Kue *or* operating the repo (the slice loop, its guards)? →
   [`guides/`](guides/) — script repeatable operations; the guide holds the judgment.
4. How Kue is built or meant to work, including its own surface and behavior record? →
   [`spec/`](spec/).
5. None of the above — genuinely unsettled exploration → [`scratch/`](scratch/). Open
   with a one-line "not spec/decision because ___."

Each folder's README states its one test precisely. `CLAUDE.md` points here as the index.

Docs convention: when a doc references a CUE *language* feature, show a short CUE code
block of the construct (oracle-verified against `cue`); engine-internal references — perf,
memoization, refactors — get none. See [`guides/slice-loop.md`](guides/slice-loop.md).

## Project Documents

**Design & behavior record — [`spec/`](spec/):**

- [Architecture](spec/architecture.md) — implementation architecture, layering, module
  boundaries, and near-term milestones.
- [Compatibility Assumptions](spec/compat-assumptions.md) — assumptions and deliberately
  narrow choices made while matching CUE behavior.
- [Plan](spec/plan.md) — live roadmap: standing capabilities, the next slices, and the
  authoritative spec-conformance fix backlog.
- [Implementation Log](spec/implementation-log.md) — the full slice-by-slice record of
  completed work, retained for verification.
- [CUE Divergences](spec/cue-divergences.md) — where `cue` disagrees with the spec and Kue
  deliberately follows the spec; one row per divergence.
- [CUE Spec Gaps](spec/cue-spec-gaps.md) — where the spec is silent and Kue's principled
  choice is recorded, even when Kue matches `cue`.

**Third-party reference — [`vendor/`](vendor/):**

- [CUE Language Guide](vendor/cue-language-guide.md) — implementation-oriented map of CUE
  semantics: value lattice, unification, disjunction, defaults, bottom, closedness, cycles,
  comprehensions, modules, and compatibility risks.

**How-to — [`guides/`](guides/):**

- [Lean 4 Guide](guides/lean4-guide.md) — repo-local Lean 4 quickstart: Lake setup, module
  layout, proof workflow, and how to model CUE semantics in Lean.
- [Slice Loop](guides/slice-loop.md) — the per-slice ACE workflow: TDD, wild-fixture
  capture, verification, and the docs each slice must update.
- [Performance Guide](guides/kue-performance.md) — how to write CUE that Kue evaluates
  fast: which patterns are expensive in Kue, why, and the faster shapes.
- [Failure Modes & Guards](guides/failure-modes.md) — operational pitfalls hit running the
  autonomous loop (crashes, contention, stale docs), each with its guard; appended on the
  periodic resilience pass.

**Decisions — [`decisions/`](decisions/):** dated ADRs. The load-bearing ones:

- [Compatibility Target](decisions/2026-06-14-cue-compatibility-target.md) — why Kue
  targets *correct* CUE v0.15 semantics over bug-for-bug parity.
- [Correctness Over Performance](decisions/2026-06-18-correctness-over-performance.md) —
  why Kue never trades soundness for speed, while keeping basic cases usable.
- [Implementation Language: Lean 4](decisions/2026-06-17-implementation-language-lean4.md)
  — why Kue stays on Lean 4 over an OCaml/Haskell/Rust rewrite, and what would flip it.
- [Numeric Model: Exact Decimal, No Float](decisions/2026-06-22-numeric-model-exact-decimal-no-float.md)
  — why `math.Pow`/`math.Sqrt` cover their real domain in exact decimal; Float/NaN banned.
- [Oracle as Data Source](decisions/2026-06-20-oracle-as-data-source.md) — the `cue` binary
  may seed generated data for externally-standardized domains, never gate correctness.

See [`decisions/`](decisions/) for the full log (distribution, cgo spike, registry fetch).

## Human-facing

These design docs are the agent/developer record, read in-repo. The human-facing status
*site* is separate — a served HTML page at [`../www/index.html`](../www/index.html), not
part of this design record. Keep the two audiences apart.

## Reading Order

1. Read the [CUE language guide](vendor/cue-language-guide.md) to understand what Kue must
   preserve.
2. Read the [Lean 4 guide](guides/lean4-guide.md) to understand how this repo should model
   and prove those semantics.
3. Read the [architecture](spec/architecture.md) before adding implementation modules.
4. Check the [plan](spec/plan.md) for the current slice before editing code.
5. When matching CUE behavior, record narrow choices in
   [compatibility assumptions](spec/compat-assumptions.md).
