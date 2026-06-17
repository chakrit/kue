# Kue Architecture

How the implementation is layered today. The representation is still free to change; what
holds stable is the separation of concerns — parsing, resolution, semantic values, lattice
operations, evaluation, manifestation, and the compatibility harness stay distinct.

## Design Goal

Kue models CUE as a single semantic value domain where types, constraints, schemas, and
concrete data are all values. Unification is meet, disjunction is join, bottom is an
ordinary semantic value (not a thrown exception), and export/manifestation is a separate
phase that demands concreteness.

The target is **correct CUE v0.15 semantics** — the language as specified, not bug-for-bug
parity with the official `cue` binary (see
[`../decisions/2026-06-14-cue-compatibility-target.md`](../decisions/2026-06-14-cue-compatibility-target.md)).

The implementation optimizes for:

- explicit semantic invariants;
- total operations over the core value domain;
- small executable examples and fixture ports before broad syntax coverage;
- theorem statements for the laws that matter;
- mechanical compatibility checks against expected CUE behavior.

## Layers and Modules

Modules live under `Kue/`; `Kue.lean` is the library root that imports them (and every
`*Tests.lean`, so `lake build` exercises the suite at elaboration time). `Main.lean` is the
`kue` executable.

### 1. Surface syntax — `Parse.lean`

A narrow recursive-descent parser over the subset already backed by semantic values. It
keeps package clauses, fields, pattern fields, embeddings, lists, refs, defaults, bounds,
`let`, aliases, selectors, indices, numeric literal spellings, and the expression grammar
visible. Unsupported source forms fail with a parse error rather than being approximated.
Boundaries are tracked in [`compat-assumptions.md`](compat-assumptions.md).

### 2. Binding and resolution — `Resolve.lean`

Converts syntax-level label references into binding identities (`refId`) against a
field environment, including nested-struct local scopes. The evaluator consumes resolved
references instead of repeatedly searching strings in nested maps.

### 3. Semantic values — `Value.lean`

The core domain: top, bottom with structural provenance (`BottomReason`), primitives
(int, float, number, string, bytes, bool, null), kinds, integer bounds, primitive
exclusions, structs with field classes, lists and list tails, struct patterns,
disjunctions with default markers, references, selectors/indices, builtin calls, and
unary/binary expression nodes.

### 4. Order and lattice — `Order.lean`, `Lattice.lean`, `Normalize.lean`

`Order.lean` defines subsumption (`subsumes`). `Lattice.lean` implements total `meet`/
`join` with fuel-bounded recursion through compound values and the normalization the laws
need (flatten disjunctions, drop bottom alternatives, numeric-kind hierarchy).
`Normalize.lean` carries definition-implied closedness normalization. Target laws:
commutativity, associativity, idempotence, top/bottom identities, and distribution of
meet over finite disjunctions.

### 5. Evaluation — `Eval.lean`, `Builtin.lean`

`Eval.lean` resolves references, applies constraints, distributes meets, evaluates
expressions, and handles reference cycles explicitly with a visited-binding path and
bounded fuel (host-language recursion failure is not acceptable cycle semantics). It does
not require export-level concreteness — `int`, `string | int`, `>0 & <10` are valid
results. `Builtin.lean` holds the builtin helpers (`close`, `len`, `and`, `or`, `div`,
`mod`, `quo`, `rem`); `Eval` dispatches resolved builtin calls and preserves incomplete
ones as semantic values.

### 6. Manifestation and formatting — `Manifest.lean`, `Format.lean`

`Manifest.lean` is the export phase: it selects defaults (recursively), filters hidden/
definition/optional/`let` fields, and rejects unresolved or ambiguous values via an
explicit `ManifestError`, kept separate from evaluation to preserve CUE's `eval` vs
`export` distinction. `Format.lean` renders values in stable CUE-like text.

### 7. Runtime and compatibility harness — `Runtime.lean`, `FixturePorts.lean`, `Examples.lean`, tests

`Runtime.lean` centralizes the resolve → evaluate → format flow shared by the CLI and
fixtures, including multi-source merging with package-name consistency. The compatibility
corpus lives in `testdata/cue/` as paired `.cue` / `.expected` files, grouped into
subsystem subdirs (`numeric/ structs/ definitions/ lists/ refs/ …`); `FixturePorts.lean`
records each expected output as a computed Kue value keyed by its `<subdir>/<stem>`
relative subpath, and `scripts/check-fixtures.sh` discovers pairs recursively, generates
ports, diffs them, compares `kue` CLI output, and runs `cue fmt --check`.
`*Tests.lean` modules carry theorem-style and executable checks.

## Where We Are / What's Next

The semantic core, evaluator, manifestation, CLI, and a broad expression layer are
implemented. The live roadmap and the standing-capability summary are in
[`plan.md`](plan.md); the full slice-by-slice history is in
[`../reference/implementation-log.md`](../reference/implementation-log.md). Major
not-yet-modeled areas: comprehensions, dynamic fields, imports/module resolution,
full lexical binding scope, and a complete regex engine.

## Tooling

Use `elan` to install Lean and Lake; the Lean version is pinned in `lean-toolchain` so
builds don't depend on a globally floating toolchain. `cue` is required by the fixture
checker.
