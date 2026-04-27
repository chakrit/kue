# Kue Architecture

This document sketches the first implementation architecture for Kue. It is a
starting point, not a commitment to a final representation. The goal is to make
CUE's semantic laws executable and eventually provable while keeping parser,
evaluation, manifestation, and compatibility concerns separate.

## Design Goal

Kue should model CUE as a single semantic value domain where types, constraints,
schemas, and concrete data are all values. Unification is meet, disjunction is
join, bottom is an ordinary semantic value, and export/manifestation is a later
phase that demands concreteness.

The implementation should optimize for:

- explicit semantic invariants;
- total operations over the core value domain;
- small executable examples before broad syntax coverage;
- theorem statements for laws that matter;
- compatibility tests against official CUE behavior once the model can run.

## Layers

### 1. Surface Syntax

The syntax layer represents parsed CUE source without trying to solve semantic
questions. It should keep source locations, package declarations, imports,
fields, comprehensions, references, defaults, and embeddings visible.

Planned module:

```text
Kue/Syntax.lean
```

This layer should not decide closedness, resolve references by string lookup, or
force values to be concrete.

### 2. Binding and Resolution

The resolver converts syntax-level references into binding identities. CUE's
lexical scoping, field scopes, aliases, `let`, imports, and comprehension
variables should be handled here before evaluation.

Planned module:

```text
Kue/Resolve.lean
```

The evaluator should consume resolved references rather than repeatedly searching
strings in nested maps.

### 3. Semantic Values

The value layer is the core of Kue. It models top, bottom, primitive values,
kinds, bounds, structs, lists, disjunctions, defaults, and eventually provenance.

Planned modules:

```text
Kue/Value.lean
Kue/Default.lean
Kue/Closedness.lean
```

Bottom belongs in this layer as data. Diagnostics may attach to bottom, but
bottom itself should not be represented as a thrown exception.

### 4. Order and Lattice Operations

The order layer defines subsumption and the lattice operations that CUE relies
on. Early implementations can use simple constructors and normalization; later
iterations can replace the representation while preserving the same laws.

Planned modules:

```text
Kue/Order.lean
Kue/Lattice.lean
Kue/Normalize.lean
```

Target laws include commutativity, associativity, idempotence, identities for top
and bottom, and distribution of meet over finite disjunctions.

### 5. Evaluation

Evaluation computes constraints and references into semantic values. It should
not require export-level concreteness. Incomplete values such as `int`,
`string | int`, or `>0 & <10` are valid evaluation results.

Planned modules:

```text
Kue/Eval.lean
Kue/Cycle.lean
Kue/Builtin.lean
```

Cycles should be explicit in the evaluator design. Host-language recursion
failure is not an acceptable cycle semantics.

### 6. Manifestation and Export

Manifestation applies default selection where required, rejects unresolved
non-concrete values, and produces data suitable for JSON/YAML-style output.

Planned modules:

```text
Kue/Manifest.lean
Kue/Encode.lean
```

This phase is intentionally separate from evaluation so Kue can preserve CUE's
distinction between `cue eval` and `cue export`.

### 7. Compatibility Harness

Compatibility tests should compare selected Kue behavior with official CUE. Each
test should record its observable surface: eval, export, validation, or
diagnostic behavior.

Planned modules and directories:

```text
Kue/Examples.lean
Kue/Tests.lean
testdata/cue/
```

The first tests should target lattice behavior, defaults, closedness, optional
fields, cycles, comprehensions, and eval/export differences.

## Initial Repository Shape

The first Lean scaffold contains only a library and a tiny executable:

```text
lakefile.lean
lean-toolchain
Kue.lean
Kue/Hello.lean
Main.lean
```

Run it with:

```sh
lake exe kue
```

The executable currently prints a greeting. That is only a tooling smoke test;
the next meaningful implementation step is to replace `Kue.Hello` with the first
semantic value module.

## Near-Term Milestones

1. Define `Prim` and an intentionally small `Value` domain.
2. Add total `meet` and `join` functions for top, bottom, primitive equality,
   and basic kind constraints.
3. State and prove the easiest lattice laws for the initial domain.
4. Add unresolved disjunctions and default markers.
5. Add structs with explicit field classes before implementing closedness.
6. Add compatibility examples from the CUE guide as executable checks.

## Tooling

Use `elan` to install Lean and Lake. This repository pins its Lean version in
`lean-toolchain` so builds do not depend on a globally floating toolchain.
