# Kue

A Lean 4 reimplementation of the [CUE language](https://cuelang.org/), focused on a
strongly-typed, mathematically-grounded core. CUE's value lattice, unification,
disjunction, defaults, and bottom are modeled as ordinary semantic values so that the
laws governing them can be executed, tested against the official `cue` binary, and
eventually proved.

## Repository Layout

- `Main.lean`, `Kue.lean` — executable entry point and library root.
- `Kue/` — Lean modules: `Value`, `Lattice`, `Order`, `Normalize`, `Eval`, `Resolve`,
  `Manifest`, `Format`, `Builtin`, plus `*Tests.lean` modules and CUE fixture ports.
- `testdata/cue/` — paired `.cue` source and `.expected` (or `.manifest.expected`)
  fixtures used for compatibility checks against `cue`.
- `scripts/check-fixtures.sh` — validates fixture pairs, regenerates Lean fixture
  ports, and runs `cue fmt --check`.
- `docs/` — design docs. Start at [`docs/index.md`](docs/index.md).
- `lakefile.lean`, `lean-toolchain` — Lake build config (Lean `v4.29.1`).
- `AGENTS.md`, `ace.toml` — AI agent environment config (managed by
  [ACE](https://github.com/prod9/ace)).

## Requirements

- [`elan`](https://github.com/leanprover/elan) — installs the Lean toolchain pinned
  by `lean-toolchain`.
- [`cue`](https://cuelang.org/docs/install/) — required by `scripts/check-fixtures.sh`
  for fixture validation.

## Build & Run

```sh
lake build                # build the library and `kue` exe
lake exe kue              # run the smoke entry point
lake build Kue.Tests      # build the test aggregator module
printf 'x: int & 1\n' | lake exe kue
```

All test modules are imported from `Kue.lean`, so `lake build` exercises the full
suite at elaboration time.

When stdin contains CUE source, `kue` parses the supported subset, resolves same-file
references, evaluates known builtins, and writes the resolved Kue output to stdout.
With empty stdin it preserves the semantic smoke output for quick checks.

## Fixtures

```sh
./scripts/check-fixtures.sh
```

Diffs Lean-generated outputs against the canonical `.expected` files in
`testdata/cue/` and verifies CUE source formatting.

## Documentation

Read in this order (see [`docs/index.md`](docs/index.md)):

1. [`docs/cue-language-guide.md`](docs/cue-language-guide.md) — CUE semantics Kue
   must preserve.
2. [`docs/lean4-guide.md`](docs/lean4-guide.md) — Lean 4 setup and proof workflow.
3. [`docs/architecture.md`](docs/architecture.md) — module layering and boundaries.
4. [`docs/compat-assumptions.md`](docs/compat-assumptions.md) — compatibility
   assumptions and deliberately narrow choices.
5. [`docs/plan.md`](docs/plan.md) — current implementation slice and TDD checkpoints.
