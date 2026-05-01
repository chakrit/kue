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

4. Keep typed-tail behavior covered by Lean theorem checks only.
   A later fixture audit removed the old `testdata/cue/typed_ellipsis.cue`
   sample because CUE v0.15.4 does not accept that struct ellipsis syntax.

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

## Completed Slice: Structured Manifestation

Goal: let manifestation/export produce concrete struct and list data instead of
only primitive values.

### Steps

1. Add tests first.
   Cover:
   - primitive manifestation still succeeds;
   - concrete lists manifest element-wise;
   - concrete structs manifest regular fields;
   - hidden, definition, and optional fields are excluded from output;
   - incomplete regular fields and unsatisfied required fields fail.
   Completed in the structured manifestation slice.

2. Add an explicit manifest data type for exportable primitives, structs, and
   lists.
   Completed in the structured manifestation slice.

3. Update manifestation helpers and fixture formatting to use manifest data.
   Completed in the structured manifestation slice.

4. Add one CUE fixture port for export field filtering.
   Completed in the structured manifestation slice.

5. Verify. Completed in the structured manifestation slice.

   ```sh
   lake build
   lake exe kue
   ```

## Completed Slice: Recursive Manifest Defaults

Goal: ensure manifestation selects defaults inside concrete structs and lists,
not only at the top level.

### Steps

1. Add tests first.
   Cover:
   - a regular struct field containing a default disjunction manifests to the
     selected default;
   - a list item containing a default disjunction manifests to the selected
     default.
   Completed in the recursive manifest defaults slice.

2. Add one CUE fixture port for a struct field default selected during
   manifestation.
   Completed in the recursive manifest defaults slice.

3. Verify. Completed in the recursive manifest defaults slice.

   ```sh
   lake build
   lake exe kue
   ```

## Completed Slice: Nested Reference Values

Goal: resolve and evaluate references nested inside compound values such as
lists, conjunctions, and disjunction alternatives.

### Steps

1. Add tests first.
   Cover:
   - resolving a reference inside a list item;
   - evaluating a resolved reference inside a list item;
   - resolving references inside conjunctions and disjunction alternatives.
   Completed in the nested reference values slice.

2. Update resolver traversal to recurse through the current compound value
   constructors.
   Completed in the nested reference values slice.

3. Update evaluator traversal to evaluate resolved references inside the same
   compound value constructors.
   Completed in the nested reference values slice.

4. Verify. Completed in the nested reference values slice.

   ```sh
   lake build
   lake exe kue
   ```

## Completed Slice: Nested Reference Fixture Port

Goal: add a real CUE fixture for references nested inside list values.

### Steps

1. Add a `.cue` fixture and expected output for a list item that references a
   definition in the same struct.
   Completed in the nested reference fixture port slice.

2. Port the fixture into `Kue/FixtureTests.lean`.
   Completed in the nested reference fixture port slice.

3. Verify. Completed in the nested reference fixture port slice.

   ```sh
   lake build
   lake exe kue
   ```

## Completed Slice: Direct Reference Cycles

Goal: handle the first CUE reference cycle case explicitly: a field that
directly references itself evaluates to top.

### Steps

1. Add tests first.
   Cover:
   - resolving `x: x` to a self binding reference;
   - evaluating that self binding reference to top;
   - unrelated binding references still evaluate normally.
   Completed in the direct reference cycles slice.

2. Thread the current binding id through field evaluation and treat a direct
   self-reference as top.
   Completed in the direct reference cycles slice.

3. Add one CUE fixture port for `x: x`.
   Completed in the direct reference cycles slice.

4. Verify. Completed in the direct reference cycles slice.

   ```sh
   lake build
   lake exe kue
   ```

## Completed Slice: Mutual Reference Cycles

Goal: handle the next small CUE reference cycle case: two fields that directly
reference each other evaluate to top.

### Steps

1. Add tests first.
   Cover:
   - `x: y, y: x` evaluates both fields to top after resolution;
   - non-cycle references still evaluate to their target value.
   Completed in the mutual reference cycles slice.

2. Extend binding evaluation with a bounded one-hop cycle check for resolved
   references.
   Completed in the mutual reference cycles slice.

3. Add one CUE fixture port for the mutual reference cycle.
   Completed in the mutual reference cycles slice.

4. Verify. Completed in the mutual reference cycles slice.

   ```sh
   lake build
   lake exe kue
   ```

## Completed Slice: Longer Reference Cycles

Goal: handle reference cycles beyond direct and one-hop mutual references.

### Steps

1. Add tests first. Completed in the longer reference cycles slice.
   Cover:
   - `x: y, y: z, z: x` evaluates all fields to top after resolution;
   - existing direct, mutual, and acyclic reference tests still pass.

2. Replace the one-hop cycle check with a visited binding path.
   Completed in the longer reference cycles slice.
   Resolved binding evaluation now walks reference chains with bounded fuel and
   returns top when a binding id is seen again.

3. Add one CUE fixture port for the three-field reference cycle.
   Completed in the longer reference cycles slice.

4. Verify. Completed in the longer reference cycles slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Strict Integer Bounds

Goal: add strict integer bounds for constraints such as `>0` and `<10`.

### Steps

1. Extend the value domain with strict lower and upper integer bound values.
   Completed in the strict integer bounds slice.

2. Add tests first.
   Cover:
   - formatting strict bounds;
   - meeting strict bounds with satisfying and violating integers;
   - meeting strict lower and upper bounds keeps both constraints;
   - subsumption recognizes strict bounds over concrete integers.
   Completed in the strict integer bounds slice.

3. Update lattice, order, format, and manifest helpers.
   Completed in the strict integer bounds slice.

4. Add one CUE fixture port for strict integer bounds.
   Completed in the strict integer bounds slice.

5. Verify. Completed in the strict integer bounds slice.

   ```sh
   lake build
   lake exe kue
   ```

## Completed Slice: General Nested Conjunction Meets

Goal: apply conjunction constraints consistently inside nested positions such as
struct fields and list elements.

### Steps

1. Add tests first.
   Cover a struct field constrained by a strict integer range and a concrete
   integer value.
   Completed in the general nested conjunction meets slice.

2. Route compound nested meet handling through the same conjunction fold used by
   top-level meet.
   Completed in the general nested conjunction meets slice.

3. Verify. Completed in the general nested conjunction meets slice.

   ```sh
   lake build
   lake exe kue
   ```

## Completed Slice: Default Override Selection

Goal: record the CUE rule that regular unification can override a default
alternative.

### Steps

1. Add tests first.
   Cover `(*"prod" | "dev") & "dev"` evaluating and manifesting to `"dev"`.
   Completed in the default override selection slice.

2. Add one CUE fixture port for default override selection.
   Completed in the default override selection slice.

3. Verify. Completed in the default override selection slice.

   ```sh
   lake build
   lake exe kue
   ```

## Completed Slice: Primitive Exclusion Constraints

Goal: add the first not-equal value constraint, such as `!=0`.

### Steps

1. Extend the value domain with a primitive exclusion constraint.
   Completed in the primitive exclusion constraints slice.

2. Add tests first.
   Cover:
   - formatting primitive exclusions;
   - meeting an exclusion with an allowed primitive returns the primitive;
   - meeting an exclusion with the forbidden primitive returns bottom with
     provenance;
   - subsumption recognizes exclusions over concrete primitives.
   Completed in the primitive exclusion constraints slice.

3. Update lattice, order, format, and manifest helpers.
   Completed in the primitive exclusion constraints slice.

4. Add one CUE fixture port for primitive exclusion.
   Completed in the primitive exclusion constraints slice.

5. Verify. Completed in the primitive exclusion constraints slice.

   ```sh
   lake build
   lake exe kue
   ```

## Completed Slice: Optional Field Defaults

Goal: record CUE's optional-field default behavior at manifestation.

### Steps

1. Add tests first.
   Cover:
   - an optional field with a default is excluded when no regular field exists;
   - when unified with a regular field, the optional default can be selected.
   Completed in the optional field defaults slice.

2. Add one CUE fixture port for each observable behavior.
   Completed in the optional field defaults slice.

3. Verify. Completed in the optional field defaults slice.

   ```sh
   lake build
   lake exe kue
   ```

## Completed Slice: Required Field Defaults

Goal: record required-field default behavior at manifestation.

### Steps

1. Add tests first.
   Cover:
   - an unsatisfied required field with a default still fails manifestation;
   - when unified with a regular field, the required default can be selected.
   Completed in the required field defaults slice.

2. Add one CUE fixture port for the materialized required default behavior.
   Completed in the required field defaults slice.

3. Verify. Completed in the required field defaults slice.

   ```sh
   lake build
   lake exe kue
   ```

## Completed Slice: Hidden Field References

Goal: record that hidden fields participate in evaluation and reference
resolution, even though they are excluded from manifestation.

### Steps

1. Add tests first.
   Cover:
   - a regular field can reference a hidden field;
   - manifestation filters the hidden field but exports the regular reference
     result.
   Completed in the hidden field references slice.

2. Add one CUE fixture port for hidden field reference manifestation.
   Completed in the hidden field references slice.

3. Verify. Completed in the hidden field references slice.

   ```sh
   lake build
   lake exe kue
   ```

## Completed Slice: Bytes Kind

Goal: add bytes as a primitive value and kind distinct from string.

### Steps

1. Extend the value domain with a `bytes` kind and byte primitive represented
   as a Lean string payload for now.
   Completed in the bytes kind slice.

2. Add tests first.
   Cover:
   - formatting the bytes kind and a byte literal;
   - meeting `bytes` with a byte primitive succeeds;
   - meeting `string` with a byte primitive bottoms with kind provenance;
   - subsumption recognizes the bytes kind over byte primitives.
   Completed in the bytes kind slice.

3. Update lattice, order, format, and examples.
   Completed in the bytes kind slice.

4. Add one CUE fixture port for bytes kind unification.
   Completed in the bytes kind slice.

5. Verify. Completed in the bytes kind slice.

   ```sh
   lake build
   lake exe kue
   ```

## Completed Slice: Float Kind

Goal: add a first float primitive and kind distinct from int.

### Steps

1. Extend the value domain with a `float` kind and string-backed float literal.
   Completed in the float kind slice.

2. Add tests first.
   Cover:
   - formatting the float kind and a float literal;
   - meeting `float` with a float primitive succeeds;
   - meeting `int` with a float primitive bottoms with kind provenance;
   - subsumption recognizes the float kind over float primitives.
   Completed in the float kind slice.

3. Update lattice, order, format, manifest, and examples.
   Completed in the float kind slice.

4. Add one CUE fixture port for float kind unification.
   Completed in the float kind slice.

5. Verify. Completed in the float kind slice.

   ```sh
   lake build
   lake exe kue
   ```

## Completed Slice: Number Kind

Goal: add a first `number` kind that accepts both int and float primitives.

### Steps

1. Extend the value domain with a `number` kind.
   Completed in the number kind slice.

2. Add tests first.
   Cover:
   - formatting the number kind;
   - meeting `number` with int and float primitives succeeds;
   - meeting `number` with int and float kinds narrows to the specific kind;
   - meeting `number` with string bottoms with kind provenance;
   - subsumption recognizes number over int and float primitives.
   Completed in the number kind slice.

3. Update lattice, order, format, and examples.
   Completed in the number kind slice.

4. Add one CUE fixture port for number kind unification.
   Completed in the number kind slice.

5. Verify. Completed in the number kind slice.

   ```sh
   lake build
   lake exe kue
   ```

## Completed Slice: Number Join Normalization

Goal: make disjunction/join respect the new numeric kind hierarchy when one side
already subsumes the other.

### Steps

1. Add tests first.
   Cover:
   - `number | int` normalizes to `number`;
   - `float | number` normalizes to `number`;
   - `number | 1` normalizes to `number`;
   - unrelated kinds still remain an explicit disjunction.
   Completed in the number join normalization slice.

2. Update `Kue/Lattice.lean` join paths for kind-kind and kind-primitive pairs
   to use the same hierarchy predicates as meet.
   Completed in the number join normalization slice.

3. Add one CUE fixture port for redundant numeric disjunction normalization.
   Completed in the number join normalization slice.

4. Verify. Completed in the number join normalization slice.

   ```sh
   lake build
   lake exe kue
   ```

## Completed Slice: Fixture Pairing Check

Goal: make the real CUE fixture corpus mechanically checkable without relying on
the external `cue` binary.

### Steps

1. Add a shell fixture check.
   Cover:
   - every `testdata/cue/*.cue` file has at least one expected output file;
   - every `*.expected` or `*.manifest.expected` file has a matching `.cue`
     source file.
   Completed in the fixture pairing check slice.

2. Run the fixture check and `shellcheck`.
   Completed in the fixture pairing check slice.

3. Verify. Completed in the fixture pairing check slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Number With Integer Bounds

Goal: let the `number` kind accept the existing integer-bound constraints as
numeric constraints, while keeping the current int-backed bound representation.

### Steps

1. Add tests first.
   Cover:
   - `number & >=0` keeps the bound;
   - `<=10 & number` keeps the bound;
   - `number | >0` normalizes to `number`;
   - `number` subsumes integer bounds;
   - non-numeric kinds still conflict with integer bounds.
   Completed in the number with integer bounds slice.

2. Update `Kue/Lattice.lean` kind-bound meet and join paths to use the numeric
   hierarchy predicate.
   Completed in the number with integer bounds slice.

3. Update `Kue/Order.lean` so `number` subsumes integer-bound constraints.
   Completed in the number with integer bounds slice.

4. Add one CUE fixture port for `number & >=0 & 7`.
   Completed in the number with integer bounds slice.

5. Verify. Completed in the number with integer bounds slice.

   ```sh
   lake build
   lake exe kue
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Integer Bound Joins

Goal: make disjunction/join over same-direction integer bounds keep the weaker
bound instead of preserving redundant alternatives.

### Steps

1. Add tests first.
   Cover:
   - `>=5 | >=0` normalizes to `>=0`;
   - `>5 | >0` normalizes to `>0`;
   - `<=5 | <=10` normalizes to `<=10`;
   - `<5 | <10` normalizes to `<10`.
   Completed in the integer bound joins slice.

2. Update `Kue/Lattice.lean` join paths for same-direction integer bounds.
   Completed in the integer bound joins slice.

3. Add one CUE fixture port for a redundant integer-bound disjunction.
   Completed in the integer bound joins slice.

4. Verify. Completed in the integer bound joins slice.

   ```sh
   lake build
   lake exe kue
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Recursive Compound Meets

Goal: make nested compound values use the same meet semantics as top-level
values, so structs, lists, and disjunctions behave consistently inside fields
and list elements.

### Steps

1. Add tests first.
   Cover:
   - a struct field containing a nested struct unifies with another nested
     struct;
   - a struct field containing a closed list unifies element-wise;
   - a list element containing a disjunction distributes over the concrete
     element;
   - a disjunction of structs distributes through struct meet and removes the
     invalid alternative.
   Completed in the recursive compound meets slice.

2. Refactor `Kue/Lattice.lean` to route nested field, list, tail, conjunction,
   and disjunction meets through an explicit `meetWithFuel` recursion.
   Completed in the recursive compound meets slice.

3. Add recursive bottom detection for disjunction normalization so alternatives
   containing field-level or element-level bottom are removed.
   Completed in the recursive compound meets slice.

4. Add CUE fixture ports for nested struct meets, nested list meets, list-item
   disjunctions, and struct-disjunction meets.
   Completed in the recursive compound meets slice.

5. Verify. Completed in the recursive compound meets slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Broad String Pattern Constraints

Goal: add the first struct pattern constraint form, `[string]: T`, and keep it
distinct from typed ellipsis because CUE patterns constrain declared regular
fields as well as later fields.

### Steps

1. Extend the value domain with `structPattern fields labelPattern constraint`.
   Completed in the broad string pattern constraints slice.
   This constructor later gained an openness flag in the closed pattern
   constraints slice.

2. Add tests first.
   Cover:
   - formatting `[string]: int`;
   - matching regular fields satisfy the pattern;
   - conflicting regular fields become field-level bottom;
   - declared fields in the patterned struct are still constrained by the
     pattern;
   - subsumption accepts or rejects actual structs by checking every regular
     field against the pattern;
   - manifestation emits regular fields and omits the pattern itself.
   Completed in the broad string pattern constraints slice.

3. Update lattice, order, manifestation, formatting, normalization, resolution,
   and evaluation traversal for `structPattern`.
   Completed in the broad string pattern constraints slice.

4. Add fixture ports for a matching `[string]: int` struct and a conflicting
   string-pattern field.
   Completed in the broad string pattern constraints slice.

5. Verify. Completed in the broad string pattern constraints slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Fixture Syntax Check

Goal: make the CUE fixture corpus mechanically parseable by the installed CUE
toolchain, not just paired by filename.

### Steps

1. Audit `testdata/cue/*.cue` with CUE v0.15.4.
   Completed in the fixture syntax check slice.

2. Remove the old `typed_ellipsis.cue` fixture from the CUE corpus because the
   installed CUE parser rejects that struct ellipsis syntax. Keep the semantic
   behavior covered in Lean struct tests.
   Completed in the fixture syntax check slice.

3. Run `cue fmt --files testdata/cue` to normalize the remaining CUE fixtures.
   Completed in the fixture syntax check slice.

4. Extend `scripts/check-fixtures.sh` to run `cue fmt --check --files
   testdata/cue`, catching invalid or unformatted CUE fixture files.
   Completed in the fixture syntax check slice.

5. Verify. Completed in the fixture syntax check slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Bytes Literal Compatibility

Goal: align Kue byte literal formatting and fixtures with CUE byte sequence
syntax.

### Steps

1. Add tests first by changing bytes formatting expectations from raw string
   syntax to byte literal syntax.
   Completed in the bytes literal compatibility slice.

2. Update `Kue/Format.lean` so `.bytes "abc"` renders as `'abc'`.
   Completed in the bytes literal compatibility slice.

3. Update bytes examples and the `bytes_kind` fixture to use CUE byte literal
   syntax.
   Completed in the bytes literal compatibility slice.

4. Verify. Completed in the bytes literal compatibility slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Pattern Label Values

Goal: represent pattern constraints with both semantic parts from the CUE spec:
the label pattern and the field-value constraint.

### Steps

1. Refactor `structPattern` from an implicit broad string pattern to
   `structPattern fields labelPattern constraint`.
   Completed in the pattern label values slice.
   This was later refined to carry an openness flag for `close` interactions.

2. Add tests for exact-label patterns such as `["a"]: int`.
   Cover:
   - exact-label pattern formatting;
   - non-matching fields are left unconstrained;
   - matching conflicts become field-level bottom;
   - subsumption checks only matching regular fields.
   Completed in the pattern label values slice.

3. Update lattice, order, formatting, manifestation, normalization, resolution,
   and evaluation traversal for the new pattern shape.
   Completed in the pattern label values slice.

4. Add a CUE fixture port for an exact-label pattern.
   Completed in the pattern label values slice.

5. Verify. Completed in the pattern label values slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Lean Fixture Port Comparison

Goal: make the real CUE fixture corpus mechanically compare each `.expected`
file against a Lean fixture port, not only check source/expected pairing.

### Steps

1. Add a Lean fixture registry.
   Completed in the Lean fixture port comparison slice.
   `Kue/FixturePorts.lean` now records every checked `.expected` and
   `.manifest.expected` file as a computed Kue output.

2. Add a small Lean writer entry point.
   Completed in the Lean fixture port comparison slice.
   `scripts/write-fixture-ports.lean` writes the registry into a generated
   directory for shell comparison without putting a `main` declaration in an
   imported library module.

3. Extend `scripts/check-fixtures.sh`.
   Completed in the Lean fixture port comparison slice.
   The checker now builds the fixture registry, generates expected outputs into
   a temporary directory, diffs every checked file, and reports stale Lean ports
   or stale expected files.

4. Align fixture expected files with the generated Lean ports.
   Completed in the Lean fixture port comparison slice.
   This normalized older hand-formatted fixture outputs to Kue's current
   one-line formatter and made multi-top-level reference fixtures render as
   top-level fields.

5. Verify. Completed in the Lean fixture port comparison slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Regex Label Patterns

Goal: add the first regular-expression label pattern behavior for struct
patterns such as `[=~"^a$"]: int`.

### Steps

1. Extend the value domain.
   Completed in the regex label pattern slice.
   Add `.stringRegex pattern` as a semantic string-label constraint and render it
   in CUE-like form as `=~"pattern"`.

2. Add tests first. Completed in the regex label pattern slice.
   Cover:
   - formatting a regex label pattern;
   - meeting a regex pattern with matching and non-matching regular fields;
   - subsumption over matching and non-matching regular fields.

3. Update lattice and order behavior.
   Completed in the regex label pattern slice.
   Regex label matching currently supports a deliberately small literal subset:
   `^literal$`, `^prefix`, `suffix$`, and unanchored literal containment. A full
   regex engine remains later work.

4. Add a CUE fixture port for `[=~"^a$"]: int`.
   Completed in the regex label pattern slice.

5. Verify. Completed in the regex label pattern slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Shallow Close Builtin

Goal: add the first semantic builtin helper for CUE's `close`, using the existing
closed-struct representation.

### Steps

1. Add `Kue/Builtin.lean`.
   Completed in the shallow close builtin slice.
   `closeValue` marks regular structs as closed and leaves other values
   unchanged for now.

2. Add tests first. Completed in the shallow close builtin slice.
   Cover:
   - closing an open struct flips its open flag;
   - unifying a closed struct with an extra field marks the extra field bottom;
   - close is shallow for nested regular structs, matching CUE v0.15.4 behavior.

3. Route the existing closed-extra-field fixture port through `closeValue`.
   Completed in the shallow close builtin slice.

4. Verify. Completed in the shallow close builtin slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Concrete Len Builtin

Goal: add the first semantic helper for CUE's `len` builtin over concrete values.

### Steps

1. Extend `Kue/Builtin.lean`.
   Completed in the concrete len builtin slice.
   `lenValue` now evaluates:
   - concrete strings and bytes by UTF-8 byte length;
   - closed and open lists by their known fixed item count;
   - structs by counting regular fields only.
   Incomplete cases such as `len(string)` are now preserved by the later
   expression-level builtin call slice.

2. Add tests first. Completed in the concrete len builtin slice.
   Cover:
   - ASCII and non-ASCII string lengths;
   - list lengths;
   - struct lengths excluding optional, hidden, and definition fields.

3. Add a CUE fixture port for `len`.
   Completed in the concrete len builtin slice.

4. Verify. Completed in the concrete len builtin slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Finite And/Or Builtins

Goal: add semantic helpers for CUE's `and` and non-empty `or` builtins over
finite lists of existing Kue values.

### Steps

1. Extend `Kue/Builtin.lean`.
   Completed in the finite and/or builtin slice.
   `andValues` folds values with meet from top, matching `and([]) == _`.
   `orValues` folds non-empty values with join. Empty `or([])` is now preserved
   by the later expression-level builtin call slice.

2. Add tests first. Completed in the finite and/or builtin slice.
   Cover:
   - `and` meeting kind, bound, and concrete value constraints;
   - `and([])` returning top;
   - `or` retaining unresolved disjunction alternatives;
   - `or` respecting existing numeric join normalization.

3. Add a CUE fixture port for finite `and` and `or`.
   Completed in the finite and/or builtin slice.

4. Verify. Completed in the finite and/or builtin slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Expression-Level Builtin Calls

Goal: preserve unresolved builtin calls as semantic values instead of collapsing
them into approximations.

### Steps

1. Extend the value domain.
   Completed in the expression-level builtin calls slice.
   Add `.builtinCall name args` and render it in function-call form, such as
   `len(string)` and `or([])`.

2. Thread builtin calls through core operations.
   Completed in the expression-level builtin calls slice.
   Formatting, manifestation incompleteness, bottom search, reference
   resolution, evaluation, normalization, meet/join equality, and subsumption now
   all handle builtin call values explicitly.

3. Update builtin helpers. Completed in the expression-level builtin calls slice.
   `lenValue` preserves incomplete calls such as `len(string)`, and `orValues []`
   preserves CUE's unresolved `or([])` display.

4. Add a CUE fixture port for unresolved builtin calls.
   Completed in the expression-level builtin calls slice.

5. Verify. Completed in the expression-level builtin calls slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Integer Quotient Builtins

Goal: add concrete predeclared integer quotient and remainder builtins.

### Steps

1. Extend `Kue/Builtin.lean`.
   Completed in the integer quotient builtin slice.
   Add helpers for `div`, `mod`, `quo`, and `rem`.
   `div`/`mod` use Euclidean division and modulus, matching CUE's behavior for
   negative dividends and negative divisors.
   `quo`/`rem` use truncating division and remainder.

2. Preserve incomplete calls.
   Completed in the integer quotient builtin slice.
   Non-concrete arguments that remain compatible with `int` are kept as
   `.builtinCall` values, such as `div(int, 3)`.

3. Add error behavior.
   Completed in the integer quotient builtin slice.
   Concrete division by zero now yields provenance-carrying bottom through
   `.divisionByZero`, and non-integer concrete arguments produce kind-conflict
   bottom values.

4. Add a CUE fixture port for integer builtins.
   Completed in the integer quotient builtin slice.

5. Verify. Completed in the integer quotient builtin slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Closed Pattern Constraints

Goal: make `close` interact with pattern-constrained structs.

### Steps

1. Extend `structPattern` with an openness flag.
   Completed in the closed pattern constraints slice.
   Open pattern structs keep current behavior: matching regular fields are
   constrained, while nonmatching regular fields remain allowed.

2. Update `closeValue`.
   Completed in the closed pattern constraints slice.
   Closing a pattern struct now flips the openness flag to false without
   recursively closing nested structs.

3. Apply pattern closedness during meet and subsumption.
   Completed in the closed pattern constraints slice.
   Declared fields and fields whose regular labels match the pattern are allowed.
   Nonmatching regular fields in a closed pattern struct are marked as
   `.fieldNotAllowed`.

4. Add a CUE fixture port for closed regex patterns.
   Completed in the closed pattern constraints slice.

5. Verify. Completed in the closed pattern constraints slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Hidden Definition Closedness

Goal: align closedness with CUE's treatment of hidden and definition fields.

### Steps

1. Add a field-class closedness exemption.
   Completed in the hidden definition closedness slice.
   Hidden fields and definition fields now ignore closedness checks, while
   regular fields remain subject to closed struct and closed pattern rules.

2. Apply the exemption in lattice meet.
   Completed in the hidden definition closedness slice.
   Closed structs and closed pattern structs now preserve undeclared hidden and
   definition fields instead of marking them as `.fieldNotAllowed`.

3. Apply the exemption in subsumption.
   Completed in the hidden definition closedness slice.
   Closed struct and closed pattern predicates now allow hidden and definition
   extras.

4. Add a CUE fixture port for closed hidden/definition fields.
   Completed in the hidden definition closedness slice.

5. Verify. Completed in the hidden definition closedness slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Constrained Reference Cycles

Goal: preserve non-cyclic constraints when a reference cycle contributes top.

### Steps

1. Add evaluator tests for constrained cycles.
   Completed in the constrained reference cycles slice.
   Cover a direct cycle such as `x: x & >=0` and a mutual cycle where one side
   contributes `>=0`.

2. Evaluate conjunctions through lattice meet.
   Completed in the constrained reference cycles slice.
   Evaluated conjunction constraints are folded with `meet` from top, so a cyclic
   reference evaluates to `_` while sibling constraints survive.

3. Add a CUE fixture port for constrained reference cycles.
   Completed in the constrained reference cycles slice.

4. Verify. Completed in the constrained reference cycles slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Builtin Call Evaluation

Goal: evaluate known builtin calls after their arguments are evaluated.

### Steps

1. Add evaluator tests for builtin calls with reference arguments.
   Completed in the builtin call evaluation slice.
   Cover `len(x)` and `div(n, 3)` where `x` and `n` are same-struct
   references.

2. Add a builtin call dispatcher.
   Completed in the builtin call evaluation slice.
   Known calls for `close`, `len`, `and`, `or`, `div`, `mod`, `quo`, and `rem`
   are routed through the existing helper semantics after argument evaluation.

3. Preserve incomplete calls.
   Completed in the builtin call evaluation slice.
   Calls such as `len(string)` still render as unresolved builtin-call values.

4. Add a CUE fixture port for builtin calls over references.
   Completed in the builtin call evaluation slice.

5. Verify. Completed in the builtin call evaluation slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Regex Quantifier Label Patterns

Goal: extend string-regex label matching beyond literal prefix/suffix matching.

### Steps

1. Add red tests for wildcard regex label patterns.
   Completed in the regex quantifier label patterns slice.
   Cover `^a.*z$` matching `abcz` while leaving `abcy` alone, including a
   matching-field conflict.

2. Replace the literal-only regex helper.
   Completed in the regex quantifier label patterns slice.
   `stringRegexMatches` now uses a small anchored matcher over character lists,
   supporting literal atoms, `.`, `*`, `+`, `^`, and `$`.

3. Add a CUE fixture port for wildcard regex patterns.
   Completed in the regex quantifier label patterns slice.

4. Verify. Completed in the regex quantifier label patterns slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Regex Character-Class Label Patterns

Goal: support common regex character classes in label pattern matching.

### Steps

1. Add red tests for character classes and ranges.
   Completed in the regex character-class label patterns slice.
   Cover `[ab]` matching two explicit characters and `[0-9]` matching digit
   labels while leaving nonmatching labels alone.

2. Refactor the matcher to parse regex atoms.
   Completed in the regex character-class label patterns slice.
   Regex atoms now include literals, `.`, and character classes with optional
   negation and simple ranges.

3. Add a CUE fixture port for class and range regex patterns.
   Completed in the regex character-class label patterns slice.

4. Verify. Completed in the regex character-class label patterns slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Escaped Regex Label Patterns

Goal: support escaped regex atoms in label pattern matching and render escaped
CUE strings/labels correctly for fixture output.

### Steps

1. Add red tests for escaped regex atoms.
   Completed in the escaped regex label patterns slice.
   Cover `^a\\.z$` matching the literal label `a.z` and rejecting a conflicting
   value, plus CUE string escaping for rendered regex patterns.

2. Parse backslash escapes as literal regex atoms.
   Completed in the escaped regex label patterns slice.
   Escaped atoms such as `\\.` now match the escaped literal character instead
   of treating `\\` as a normal pattern character.

3. Quote rendered field labels when CUE syntax requires it.
   Completed in the escaped regex label patterns slice.
   This keeps labels such as `a.z` valid in generated fixture output.

4. Add a CUE fixture port for escaped regex label patterns.
   Completed in the escaped regex label patterns slice.

5. Verify. Completed in the escaped regex label patterns slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Later Slices

- Expand pattern constraints beyond broad `[string]: T`: complete regular
  expression label matching beyond the current literal/dot/quantifier/class
  escape subset, and non-string label patterns.
- Add embeddings, aliases, and `let` bindings in a syntax layer instead of
  constructing semantic values directly.
- Add dynamic fields and comprehensions after lexical binding identities are
  represented for more than same-struct fields.
- Expand cycle handling for arithmetic cycles and richer validation behavior.
- Add remaining builtin functions beyond the implemented `close`, `len`, `and`,
  `or`, `div`, `mod`, `quo`, and `rem` helpers.
- Add package/file merging and imports after the syntax and resolver layers exist.
