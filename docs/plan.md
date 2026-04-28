# Kue Plan

This file tracks the near-term implementation plan. Keep it small, current, and
actionable. Prefer one focused slice at a time.

## Working Principles

- Use TDD where behavior is testable: write theorem checks or executable examples
  before implementation.
- Keep the semantic model simple before optimizing representation.
- Prefer total functions and explicit semantic values over hidden host-language
  failure.
- Avoid dependencies until they clearly remove more complexity than they add.
- Keep each commit small enough to review, revert, or extend safely.

## Completed Slice: First Semantic Core

Goal: replace the placeholder `Kue.Hello` module with the smallest useful CUE
semantic core.

### Steps

1. Add `Kue/Value.lean`. Completed in `84a2d45`.
   Define a deliberately small CUE value domain:
   - `top`;
   - `bottom`;
   - primitive concrete values;
   - basic kind constraints such as `int`, `string`, `bool`, and `null`.

2. Add tests first. Completed in the lattice slice.
   Use theorem checks and tiny executable examples for the initial laws:
   - `_ & v = v`;
   - `_|_ & v = _|_`;
   - `_|_ | v = v`;
   - `_ | v = _`;
   - identical primitive values meet to themselves;
   - conflicting primitive values meet to bottom.

3. Add `Kue/Lattice.lean`. Completed in the lattice slice.
   Implement first-pass `meet` and `join` over the small value domain.
   Until unresolved disjunctions exist, `join` should compute the least value
   available in the tiny abstract domain: identical values stay unchanged,
   primitive/kind joins widen to their kind when possible, and unrelated kinds
   widen to top. This is an explicit approximation to replace in the disjunction
   slice, not final CUE disjunction semantics.

4. Replace the hello executable. Completed in the smoke executable slice.
   Make `lake exe kue` print a small semantic smoke example, such as:

   ```text
   int & 1 => 1
   "a" & "b" => _|_
   ```

5. Keep verification minimal but real. Completed in the smoke executable slice.
   Run:

   ```sh
   lake build
   lake exe kue
   ```

## Completed Slice: Unresolved Disjunctions

Goal: represent CUE disjunctions directly instead of approximating every join in
the tiny kind lattice.

### Steps

1. Extend `Kue/Value.lean` with marked disjunction alternatives.
   Each alternative should carry a value and a marker for regular vs default.
   Keep this representation deliberately small; default selection belongs to a
   later manifestation/export slice. Completed in the disjunction slice.

2. Add tests first. Completed in the disjunction slice.
   Cover:
   - joining distinct primitive values retains both alternatives;
   - joining a value with bottom still returns the value;
   - meeting a disjunction distributes over its alternatives;
   - bottom alternatives are removed after distribution;
   - default markers survive through joins and distribution.
   Add real CUE fixtures under `testdata/cue/` with `.expected` files for the
   current Kue semantic phase, and port each fixture into Lean theorem checks
   against expected behavior from the docs/specs. Do not compare against the
   `cue` binary.

3. Update `Kue/Lattice.lean`. Completed in the disjunction slice.
   Replace join widening for distinct primitives with unresolved disjunctions.
   Implement the smallest normalization needed by the tests: flatten nested
   disjunctions, remove bottom alternatives, and collapse zero or one remaining
   alternatives.

4. Update formatting and smoke examples. Completed in the disjunction slice.
   Render unresolved disjunctions in a stable CUE-like form, preserving `*` on
   default alternatives.

5. Verify. Completed in the disjunction slice.

   ```sh
   lake build
   lake exe kue
   ```

## Completed Slice: Manifestation and Defaults

Goal: add the first export-like operation that selects defaults and rejects
incomplete or ambiguous values instead of forcing concreteness during lattice
evaluation.

### Steps

1. Add tests first. Completed in the manifestation slice.
   Cover:
   - manifesting a primitive succeeds;
   - manifesting a kind constraint fails as incomplete;
   - manifesting top fails as incomplete;
   - manifesting bottom fails as contradiction;
   - manifesting an unresolved non-default disjunction fails as ambiguous;
   - manifesting a disjunction with one default selects that default.

2. Add `Kue/Manifest.lean`. Completed in the manifestation slice.
   Use an explicit `ManifestError` type and return `Except ManifestError Prim`.
   Keep errors structural for now; diagnostic text can come later.

3. Add or update fixture ports. Completed in the manifestation slice.
   Keep core `.expected` files for evaluation-like output and add manifestation
   expectations only where defaults are intentionally selected.

4. Verify. Completed in the manifestation slice.

   ```sh
   lake build
   lake exe kue
   ```

## Completed Slice: Open Structs and Field Classes

Goal: introduce structs with explicit field classes before implementing
closedness, field-level bottom, or provenance-heavy diagnostics.

### Steps

1. Extend the value domain with open structs. Completed in the struct slice.
   Represent fields as labels, field classes, and values. Include regular,
   optional, required, hidden, and definition classes even if the first lattice
   behavior only handles regular fields.

2. Add tests first. Completed in the struct slice.
   Cover:
   - formatting a regular-field struct;
   - meeting disjoint regular-field structs merges fields;
   - meeting the same regular field unifies field values;
   - conflicting same-label regular fields currently bottom the whole struct;
   - non-regular field classes are representable and format distinctly.

3. Update `Kue/Lattice.lean`. Completed in the struct slice.
   Implement open regular-field struct meet only. Leave optional/required/hidden
   class semantics, closedness, and field-level bottom as explicit later work.

4. Update fixtures and smoke examples with one simple struct case. Completed in
   the struct slice.

5. Verify. Completed in the struct slice.

   ```sh
   lake build
   lake exe kue
   ```

## Completed Slice: Field-Class Struct Semantics

Goal: give the explicit field classes their first semantic behavior without
adding closedness, field-level bottom, or export filtering yet.

### Steps

1. Add tests first. Completed in the field-class semantics slice.
   Cover:
   - optional fields constrain matching regular fields but stay optional when
     no regular field is present;
   - required fields constrain matching regular fields and become regular when
     satisfied;
   - conflicting optional or required constraints bottom the whole struct for now;
   - same-label hidden fields unify by value and remain hidden;
   - same-label definition fields unify by value and remain definitions.

2. Update `Kue/Lattice.lean`. Completed in the field-class semantics slice.
   Extend field merging with a small field-class combination function. Keep
   unsupported class combinations conservative by bottoming the whole struct.

3. Update fixtures or smoke examples only if they clarify behavior. No fixture
   changes needed; this slice only broadens struct meet behavior.

4. Verify. Completed in the field-class semantics slice.

   ```sh
   lake build
   lake exe kue
   ```

## Completed Slice: Field-Level Bottom

Goal: allow field conflicts to remain localized in the struct instead of
collapsing the whole struct to bottom.

### Steps

1. Add tests first. Completed in the field-level bottom slice.
   Cover:
   - conflicting regular fields produce a regular field with bottom value;
   - conflicting required-vs-regular fields produce a regular field with bottom
     value;
   - formatting a struct with a bottom field shows `_|_` at that field;
   - unsupported field-class combinations still bottom the whole struct.

2. Update `Kue/Lattice.lean`. Completed in the field-level bottom slice.
   Change supported same-label field merges to keep `.bottom` as the merged field
   value. Keep `none` only for unsupported field-class combinations.

3. Add a real CUE fixture port for a conflicting field. Completed in the
   field-level bottom slice.

4. Verify. Completed in the field-level bottom slice.

   ```sh
   lake build
   lake exe kue
   ```

## Completed Slice: Bottom Provenance

Goal: attach first-pass structural provenance to bottom values without changing
their lattice role or display form.

### Steps

1. Extend the value domain. Completed in the bottom provenance slice.
   Add a small `BottomReason` type and a provenance-carrying bottom value. Keep
   plain bottom available for law statements and unsupported whole-value errors.

2. Add tests first. Completed in the bottom provenance slice.
   Cover:
   - conflicting primitive values produce a bottom value with primitive conflict
     provenance;
   - conflicting kind values produce a bottom value with kind conflict
     provenance;
   - `isBottom` recognizes both plain and provenance-carrying bottom values;
   - formatting provenance-carrying bottom still renders `_|_`;
   - field conflicts attach field conflict provenance at the field value.

3. Update `Kue/Lattice.lean` and format/manifest helpers. Completed in the
   bottom provenance slice.
   Treat provenance bottom as bottom for normalization and manifestation.

4. Verify. Completed in the bottom provenance slice.

   ```sh
   lake build
   lake exe kue
   ```

## Completed Slice: Minimal Closedness

Goal: give the existing struct `open_` flag its first semantics before modeling
ellipsis values, definitions-as-closed, or provenance-rich diagnostics.

### Steps

1. Extend bottom provenance. Completed in the minimal closedness slice.
   Add a `fieldNotAllowed` reason for closed struct rejections.

2. Add tests first. Completed in the minimal closedness slice.
   Cover:
   - a closed struct allows matching fields to unify;
   - a closed left struct rejects extra right fields as field-level bottom;
   - a closed right struct rejects extra left fields as field-level bottom;
   - open structs still accept extra fields.

3. Update `Kue/Lattice.lean`. Completed in the minimal closedness slice.
   Apply closedness after regular field merging by marking fields absent from a
   closed counterpart as bottom-valued fields.

4. Add one CUE fixture port documenting the closed-extra-field case. Completed
   in the minimal closedness slice.

5. Verify. Completed in the minimal closedness slice.

   ```sh
   lake build
   lake exe kue
   ```

## Completed Slice: First Subsumption Predicate

Goal: add the first order-layer predicate so tests can state when one semantic
value is at least as general as another.

### Steps

1. Add tests first. Completed in the first order slice.
   Cover:
   - top subsumes every value in the initial domain;
   - every value subsumes bottom;
   - kind constraints subsume matching primitive values;
   - primitive values only subsume identical primitive values;
   - closed structs subsume matching structs but not structs with extra fields;
   - open structs subsume matching structs with extra fields.

2. Add `Kue/Order.lean`. Completed in the first order slice.
   Implement a conservative executable `subsumes expected actual : Bool`.
   Keep disjunction handling minimal: a disjunction subsumes a value when any
   alternative subsumes it.

3. Add `Kue/OrderTests.lean` and import both modules from `Kue.lean`.
   Completed in the first order slice.

4. Verify. Completed in the first order slice.

   ```sh
   lake build
   lake exe kue
   ```

## Completed Slice: Typed Ellipsis

Goal: model the first ellipsis form, `...T`, as an open struct tail constraint
that applies to extra regular fields.

### Steps

1. Extend the value domain. Completed in the typed ellipsis slice.
   Add a typed-tail struct representation for open structs with an additional
   field constraint. Keep plain open and closed structs as-is.

2. Add tests first. Completed in the typed ellipsis slice.
   Cover:
   - formatting typed ellipsis;
   - extra regular fields satisfying the tail constraint are preserved;
   - extra regular fields conflicting with the tail become field-level bottom;
   - declared fields are unified by their declared constraints, not by the tail;
   - subsumption treats typed tails as accepting matching extra fields and
     rejecting conflicting ones.

3. Update lattice, order, format, and manifest helpers. Completed in the typed
   ellipsis slice.
   Keep the first implementation limited to regular extra fields.

4. Add one CUE fixture port for a typed ellipsis struct. Completed in the typed
   ellipsis slice.

5. Verify. Completed in the typed ellipsis slice.

   ```sh
   lake build
   lake exe kue
   ```

## Completed Slice: Definition-Implied Closedness

Goal: add a small normalization layer for the CUE rule that definition structs
are closed, before implementing references to definitions.

### Steps

1. Add tests first. Completed in the definition normalization slice.
   Cover:
   - a definition field containing an open plain struct normalizes that struct
     to closed;
   - regular fields containing open structs remain open;
   - typed-tail structs in definitions stay typed-tail/open;
   - nested definition structs normalize recursively.

2. Add `Kue/Normalize.lean`. Completed in the definition normalization slice.
   Implement an executable `normalizeDefinitions : Value -> Value` with bounded
   recursion. Keep the function explicit and small; general normalization can
   grow in later slices.

3. Add `Kue/NormalizeTests.lean` and import both modules from `Kue.lean`.
   Completed in the definition normalization slice.

4. Add a CUE fixture port for definition-implied closedness. Completed in the
   definition normalization slice.

5. Verify. Completed in the definition normalization slice.

   ```sh
   lake build
   lake exe kue
   ```

## Completed Slice: Same-Struct References

Goal: introduce the first evaluation layer by resolving simple references within
the same struct, especially references to definition fields.

### Steps

1. Extend the value domain with a symbolic reference value. Completed in the
   same-struct references slice.
   Keep this temporary and explicit; a resolver with binding identities should
   replace string labels later.

2. Add tests first. Completed in the same-struct references slice.
   Cover:
   - a regular field referencing a definition field evaluates to the definition
     value;
   - references to missing fields produce bottom with reference provenance;
   - formatting unresolved references is stable;
   - manifestation treats unresolved references as incomplete.

3. Add `Kue/Eval.lean`. Completed in the same-struct references slice.
   Implement `evalStructRefs : Value -> Value` for one struct level. Resolve
   references against fields in that same struct after definition normalization.

4. Add one CUE fixture port for a field using a definition reference. Completed
   in the same-struct references slice.

5. Verify. Completed in the same-struct references slice.

   ```sh
   lake build
   lake exe kue
   ```

## Completed Slice: Resolved Binding References

Goal: introduce binding identities for references so evaluation can distinguish
resolution from later value lookup.

### Steps

1. Extend the value domain. Completed in the resolved binding slice.
   Add a small `BindingId` type and a resolved reference value. Keep `.ref String`
   as the unresolved, syntax-facing form for now.

2. Add tests first. Completed in the resolved binding slice.
   Cover:
   - resolved references evaluate by binding id;
   - missing binding ids produce bottom with reference provenance;
   - same label but different binding id resolves to the bound field, not a
     string lookup by label.

3. Update `Kue/Eval.lean`. Completed in the resolved binding slice.
   Build a simple field environment from struct order, assigning stable binding
   ids by field position. Resolve `.refId id` against that environment.

4. Verify. Completed in the resolved binding slice.

   ```sh
   lake build
   lake exe kue
   ```

## Completed Slice: Closed Lists

Goal: add the first list value representation and closed-list unification.

### Steps

1. Extend the value domain with closed lists. Completed in the closed list
   slice.

2. Add tests first. Completed in the closed list slice.
   Cover:
   - formatting closed lists;
   - same-length lists meet element-wise;
   - conflicting elements become element-level bottom;
   - different-length closed lists bottom for now;
   - subsumption checks list elements positionally.

3. Update lattice, order, format, manifest, and evaluation helpers. Completed
   in the closed list slice.
   Keep open lists and comprehensions out of scope.

4. Add one CUE fixture port for list unification. Completed in the closed list
   slice.

5. Verify. Completed in the closed list slice.

   ```sh
   lake build
   lake exe kue
   ```

## Completed Slice: Integer Bounds

Goal: add the first scalar bounds for integer constraints such as `>=0` and
`<=65535`.

### Steps

1. Extend the value domain with integer lower and upper bound constraints.
   Completed in the integer bounds slice.

2. Add tests first.
   Cover:
   - formatting integer bounds;
   - meeting a bound with a satisfying integer returns the integer;
   - meeting a bound with a violating integer returns bottom with bound
     provenance;
   - meeting two lower bounds keeps the stricter lower bound;
   - meeting lower and upper bounds keeps both constraints as a conjunction for
     now;
   - subsumption recognizes bounds over concrete integers.
   Completed in the integer bounds slice.

3. Update lattice, order, format, manifest, and examples.
   Keep non-integer numeric kinds out of scope.
   Completed in the integer bounds slice.

4. Add one CUE fixture port for integer bounds.
   Completed in the integer bounds slice.

5. Verify. Completed in the integer bounds slice.

   ```sh
   lake build
   lake exe kue
   ```

## Completed Slice: Open List Tails

Goal: add the first open-list representation for typed tails such as
`[int, ...string]`.

### Steps

1. Extend the value domain with an open list tail value that stores fixed prefix
   items and a tail constraint.
   Completed in the open list tail slice.

2. Add tests first.
   Cover:
   - formatting open list tails;
   - meeting a typed-tail list with a longer closed list applies the tail to
     extra elements;
   - conflicting extra elements become element-level bottom;
   - fixed prefix elements still unify positionally;
   - a closed list shorter than the fixed prefix bottoms;
   - subsumption accepts matching extra elements and rejects conflicting extras.
   Completed in the open list tail slice.

3. Update lattice, order, format, manifest, and examples.
   Keep list comprehensions and length arithmetic out of scope.
   Completed in the open list tail slice.

4. Add one CUE fixture port for an open list tail.
   Completed in the open list tail slice.

5. Verify. Completed in the open list tail slice.

   ```sh
   lake build
   lake exe kue
   ```

## Completed Slice: Nested Compound Meets

Goal: make compound constraints apply consistently when they appear inside
struct fields, not only as top-level values.

### Steps

1. Add tests first.
   Cover:
   - a field constrained by `>=0 & <=10` accepts a concrete integer field;
   - a field constrained by `[int, ...string]` accepts a longer concrete list;
   - conflicting extra list elements remain element-level bottom inside fields.
   Completed in the nested compound meets slice.

2. Refactor lattice field merging to use the same compound meet helper as
   top-level list-tail and integer-bound paths.
   Completed in the nested compound meets slice.

3. Verify. Completed in the nested compound meets slice.

   ```sh
   lake build
   lake exe kue
   ```

## Completed Slice: Syntax Reference Resolver

Goal: separate syntax-facing label references from evaluation-facing binding
ids.

### Steps

1. Add tests first.
   Cover:
   - resolving a same-struct label reference to the binding id of the matching
     field;
   - duplicate labels resolve by binding position, not by later string lookup;
   - missing labels remain syntax references so evaluation can report the
     unresolved reference provenance;
   - evaluation after resolution still produces the same value as direct label
     evaluation.
   Completed in the syntax reference resolver slice.

2. Add a resolver module that builds a label-to-binding environment from struct
   fields and rewrites `.ref` values to `.refId` values.
   Completed in the syntax reference resolver slice.

3. Update examples or fixture ports where this clarifies the evaluation path.
   Completed in the syntax reference resolver slice.

4. Verify. Completed in the syntax reference resolver slice.

   ```sh
   lake build
   lake exe kue
   ```

## Later Slices

- Expand the compatibility harness against more official CUE examples.
- Add resolver and cycle handling only after the core value operations are stable.
