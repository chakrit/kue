# Kue Plan

The live implementation roadmap. Kept small, current, and actionable — one focused slice
at a time. The full record of completed slices lives in
[`../reference/implementation-log.md`](../reference/implementation-log.md), retained for
verification; this file holds only where we are and what's next.

## North Star

Kue targets **CUE v0.15 semantics, done correctly**. Where the official `cue` v0.15
binary is buggy, Kue should implement the *correct* behavior, not replicate the bug. The
compatibility target is the language as specified, not bug-for-bug parity with the
reference implementation. See
[`../decisions/2026-06-14-cue-compatibility-target.md`](../decisions/2026-06-14-cue-compatibility-target.md).

## Working Principles

- Use TDD where behavior is testable: write theorem checks or executable examples
  before implementation.
- Keep the semantic model simple before optimizing representation.
- Prefer total functions and explicit semantic values over hidden host-language
  failure.
- Avoid dependencies until they clearly remove more complexity than they add.
- Keep each commit small enough to review, revert, or extend safely. One slice per
  commit; the commit subject mirrors the slice title.

## Implementation Status

The semantic core, evaluator, manifestation, a stdin/file CLI, and a broad expression
layer are in place. Summary of standing capabilities (detail per slice in the
implementation log):

- **Value domain** — top, bottom (with structural provenance), primitives
  (int/float/number/string/bytes/bool/null), kinds, integer bounds (incl. strict),
  primitive exclusions, disjunctions with default markers.
- **Lattice** — total `meet`/`join` with normalization; recursive compound meets through
  structs, lists, conjunctions, and disjunction alternatives; numeric-kind hierarchy in
  meet and join.
- **Structs** — regular/optional/required/hidden/definition field classes, field-level
  bottom, open/closed structs, typed and untyped tails, definition-implied closedness,
  `close` builtin, and string/exact/regex pattern constraints (incl. multiple independent
  patterns).
- **Lists** — closed lists and typed open-list tails, element-wise meet.
- **References & cycles** — same-struct and nested-scope resolution via binding ids,
  `let` bindings, static field aliases, and bounded cycle handling (direct, mutual,
  longer; constraints preserved across cycles).
- **Manifestation** — structured export with default selection (incl. nested),
  field-class filtering, and incompleteness/ambiguity rejection.
- **Builtins** — `close`, `len`, `and`, `or`, `div`, `mod`, `quo`, `rem`, with
  unresolved calls preserved as semantic values.
- **Parser/CLI** — recursive-descent parser over the supported subset; numeric literal
  spellings (non-decimal, separators, exponents, suffix multipliers); stdin and explicit
  multi-file evaluation with package-name consistency.
- **Expressions** — unary/additive/multiplicative/division/integer-keyword arithmetic,
  equality, ordering, numeric comparison across int/float, logical `&&`/`||`/`!`, and
  binary regex match `=~`/`!~`.

Known deliberate boundaries are tracked in [`compat-assumptions.md`](compat-assumptions.md).

## Later Slices

- Expand pattern constraints beyond the current string-label representation:
  non-string label patterns and fuller regular expression matching.
- Add remaining alias positions in a syntax layer instead of constructing
  semantic values directly.
- Add dynamic fields and comprehensions. The prerequisite — lexical binding
  identities represented for more than same-struct fields — has landed: `BindingId`
  now carries `(depth, index)` and resolution/evaluation thread a lexical scope chain
  (see the lexical scope chain slice). Comprehensions add one further scope kind (the
  `for` loop variable), which is not a struct field; dynamic fields add computed labels.
- Expand cycle handling for arithmetic cycles and richer validation behavior.
- Add remaining builtin functions beyond the implemented `close`, `len`, `and`,
  `or`, `div`, `mod`, `quo`, and `rem` helpers.
- Add imports and full module resolution after the syntax and resolver layers exist.
