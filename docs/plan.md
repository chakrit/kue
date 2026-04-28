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

## Later Slices

- Add ellipsis handling and definition-implied closedness.
- Expand the compatibility harness against more official CUE examples.
- Add resolver and cycle handling only after the core value operations are stable.
