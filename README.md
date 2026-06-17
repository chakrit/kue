# Kue

A Lean 4 reimplementation of the [CUE language](https://cuelang.org/), focused on a
strongly-typed, mathematically-grounded core. CUE's value lattice, unification,
disjunction, defaults, and bottom are modeled as ordinary semantic values so that the
laws governing them can be executed, tested against the official `cue` binary, and
eventually proved.

## Installation

macOS (Apple Silicon) via Homebrew:

```sh
brew install chakrit/tap/kue
```

This pulls a prebuilt, self-contained binary (Lean's runtime is linked statically;
no toolchain install required). Other platforms — and Apple Silicon if you prefer —
build from source:

```sh
git clone https://github.com/chakrit/kue && cd kue
lake build kue            # produces .lake/build/bin/kue
```

`lake build` fetches the toolchain pinned by `lean-toolchain` via `elan` on first run.
The prebuilt macOS arm64 binary is attached to the
[GitHub releases](https://github.com/chakrit/kue/releases); other platforms build from
source as above. Releases are cut locally with [`scripts/release.sh`](scripts/release.sh).

## Repository Layout

- `Main.lean`, `Kue.lean` — executable entry point and library root.
- `Kue/` — Lean modules: `Value`, `Lattice`, `Order`, `Normalize`, `Eval`, `Resolve`,
  `Manifest`, `Format`, `Builtin`, plus `*Tests.lean` modules and CUE fixture ports.
- `testdata/cue/` — paired `.cue` source and `.expected` (or `.manifest.expected`)
  fixtures used for compatibility checks against `cue`, grouped into subsystem subdirs
  (`numeric/ bounds/ disjunctions/ structs/ definitions/ lists/ refs/ comprehensions/
  builtins/ multiline/ manifest/`); each pair's files sit together under one subdir.
- `scripts/check-fixtures.sh` — validates fixture pairs, regenerates Lean fixture
  ports, compares stdin CLI output, and runs `cue fmt --check`.
- `docs/` — durable docs (usage + design record). Start at [`docs/README.md`](docs/README.md).
- `lakefile.lean`, `lean-toolchain` — Lake build config (Lean `v4.29.1`).
- `CLAUDE.md`, `ace.toml` — AI agent environment config (managed by
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
`testdata/cue/`, compares `kue` stdin output against non-manifest expectations,
and verifies CUE source formatting.

## Documentation

Read in this order (see [`docs/README.md`](docs/README.md)):

1. [`docs/spec/cue-language-guide.md`](docs/spec/cue-language-guide.md) — CUE semantics
   Kue must preserve.
2. [`docs/guides/lean4-guide.md`](docs/guides/lean4-guide.md) — Lean 4 setup and proof
   workflow.
3. [`docs/spec/architecture.md`](docs/spec/architecture.md) — module layering and
   boundaries.
4. [`docs/spec/compat-assumptions.md`](docs/spec/compat-assumptions.md) — compatibility
   assumptions and deliberately narrow choices.
5. [`docs/spec/plan.md`](docs/spec/plan.md) — current implementation slice and TDD
   checkpoints.
