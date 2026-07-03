# Implementation Log

A chronological record of every completed implementation slice, retained for
**verification** — each entry states the intended behavior a slice added, so the Lean
implementation can be audited against its claims. This is history, not the live plan; the
current roadmap lives in [`../spec/plan.md`](../spec/plan.md).

Each slice here corresponds to a single commit (the commit subject mirrors the slice
title), so `git log` and this file stay in step. New slices are appended as they land.

---

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

## Completed Slice: Optional Regex Quantifier Label Patterns

Goal: support the `?` regex quantifier in label pattern matching.

### Steps

1. Add red tests for optional regex atoms.
   Completed in the optional regex quantifier label patterns slice.
   Cover `^colou?r$` matching both `color` and `colour`, while leaving
   `colouur` unconstrained.

2. Implement `?` beside the existing `*` and `+` quantifiers.
   Completed in the optional regex quantifier label patterns slice.
   The matcher now accepts either zero occurrences of the parsed atom or one
   matching occurrence before continuing with the rest of the pattern.

3. Add a CUE fixture port for optional regex quantifier label patterns.
   Completed in the optional regex quantifier label patterns slice.

4. Verify. Completed in the optional regex quantifier label patterns slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Regex Digit Shorthand Label Patterns

Goal: support digit shorthand character classes in label pattern matching.

### Steps

1. Add red tests for digit shorthand classes.
   Completed in the regex digit shorthand label patterns slice.
   Cover `\\d` matching a digit label segment while not matching literal `d`,
   and cover the negated `\\D` form.

2. Parse digit shorthands as regex class atoms.
   Completed in the regex digit shorthand label patterns slice.
   `\\d` now maps to `[0-9]`, and `\\D` maps to the negated digit class.

3. Add a CUE fixture port for digit shorthand label patterns.
   Completed in the regex digit shorthand label patterns slice.

4. Verify. Completed in the regex digit shorthand label patterns slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Top-Level Regex Alternation Label Patterns

Goal: support top-level `|` alternatives in regex label pattern matching.

### Steps

1. Add red tests for top-level alternation.
   Completed in the top-level regex alternation label patterns slice.
   Cover `^cat$|^dog$` constraining both matching labels while leaving
   nonmatching labels unconstrained.

2. Split regex patterns into top-level alternatives before matching.
   Completed in the top-level regex alternation label patterns slice.
   The splitter preserves escaped characters and character-class bodies, then
   applies the existing anchored matcher to each alternative.

3. Add a CUE fixture port for top-level alternation label patterns.
   Completed in the top-level regex alternation label patterns slice.

4. Verify. Completed in the top-level regex alternation label patterns slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Parenthesized Regex Alternation Label Patterns

Goal: support simple parenthesized alternatives in regex label pattern matching.

### Steps

1. Add red tests for parenthesized alternatives.
   Completed in the parenthesized regex alternation label patterns slice.
   Cover `^(cat|dog)$` constraining both `cat` and `dog`, while leaving
   nonmatching labels unconstrained.

2. Expand the first flat regex group before matching.
   Completed in the parenthesized regex alternation label patterns slice.
   The expansion preserves escapes and character classes inside the group body,
   then reuses the existing top-level alternative matcher.

3. Add a CUE fixture port for parenthesized alternation label patterns.
   Completed in the parenthesized regex alternation label patterns slice.

4. Verify. Completed in the parenthesized regex alternation label patterns
   slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Regex Word Shorthand Label Patterns

Goal: support word shorthand character classes in label pattern matching.

### Steps

1. Add red tests for word shorthand classes.
   Completed in the regex word shorthand label patterns slice.
   Cover `\\w` matching ASCII letters, digits, and underscore, and cover the
   negated `\\W` form for non-word label characters.

2. Parse word shorthands as regex class atoms.
   Completed in the regex word shorthand label patterns slice.
   `\\w` now maps to `[0-9A-Z_a-z]`, and `\\W` maps to the negated word class.

3. Add a CUE fixture port for word shorthand label patterns.
   Completed in the regex word shorthand label patterns slice.

4. Verify. Completed in the regex word shorthand label patterns slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Regex Whitespace Shorthand Label Patterns

Goal: support whitespace shorthand character classes in label pattern matching.

### Steps

1. Add red tests for whitespace shorthand classes.
   Completed in the regex whitespace shorthand label patterns slice.
   Cover `\\s` matching a space in a quoted label, and cover the negated `\\S`
   form for non-whitespace label characters.

2. Parse whitespace shorthands as regex class atoms.
   Completed in the regex whitespace shorthand label patterns slice.
   `\\s` now maps to common ASCII whitespace characters, and `\\S` maps to the
   negated whitespace class.

3. Add a CUE fixture port for whitespace shorthand label patterns.
   Completed in the regex whitespace shorthand label patterns slice.

4. Verify. Completed in the regex whitespace shorthand label patterns slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Exact Regex Repetition Label Patterns

Goal: support exact `{n}` repetition over regex atoms in label pattern matching.

### Steps

1. Add red tests for exact repetition.
   Completed in the exact regex repetition label patterns slice.
   Cover `^a\\d{2}z$` matching a two-digit label segment while leaving a
   one-digit label unconstrained.

2. Parse and match exact repetition quantifiers.
   Completed in the exact regex repetition label patterns slice.
   The matcher now parses `{digits}` after an atom and consumes exactly that
   many matching characters before continuing with the remaining pattern.

3. Add a CUE fixture port for exact repetition label patterns.
   Completed in the exact regex repetition label patterns slice.

4. Verify. Completed in the exact regex repetition label patterns slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Bounded Regex Repetition Label Patterns

Goal: support bounded `{m,n}` repetition over regex atoms in label pattern
matching.

### Steps

1. Add red tests for bounded repetition.
   Completed in the bounded regex repetition label patterns slice.
   Cover `^a\\d{2,3}z$` matching two- and three-digit label segments while
   leaving a one-digit label unconstrained.

2. Parse repetition quantifiers as minimum and maximum counts.
   Completed in the bounded regex repetition label patterns slice.
   Exact `{n}` now goes through the same range matcher as `{m,n}`.

3. Add range matching for repeated atoms.
   Completed in the bounded regex repetition label patterns slice.
   The matcher consumes required occurrences first, then tries up to the maximum
   allowed optional occurrences before continuing with the rest of the pattern.

4. Add a CUE fixture port for bounded repetition label patterns.
   Completed in the bounded regex repetition label patterns slice.

5. Verify. Completed in the bounded regex repetition label patterns slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Basic Stdin Parser CLI

Goal: make the `kue` executable usable on small real CUE snippets by parsing stdin
through the existing resolver and evaluator.

### Steps

1. Add parser tests first.
   Cover package clauses, top-level fields, definition references, lists, nested
   structs, builtin calls, defaults, and integer bounds.
   Completed in the basic stdin parser CLI slice.

2. Add a narrow recursive-descent parser.
   Completed in the basic stdin parser CLI slice.
   `Kue/Parse.lean` accepts the syntax already backed by semantic values and
   rejects unsupported CUE syntax with a parse error.

3. Add runtime helpers shared by fixtures and the CLI.
   Completed in the basic stdin parser CLI slice.
   `Kue/Runtime.lean` centralizes top-level formatting and resolve/eval flow.

4. Update `Main.lean` to read stdin.
   Completed in the basic stdin parser CLI slice.
   Non-empty stdin is parsed and resolved to stdout. Empty stdin keeps the
   existing semantic smoke output.

5. Document parser compatibility assumptions.
   Completed in the basic stdin parser CLI slice.
   See `docs/spec/compat-assumptions.md`.

6. Verify. Completed in the basic stdin parser CLI slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Parser Field Pattern Syntax

Goal: let stdin CUE source express the field pattern constraints that Kue's
semantic core already supports.

### Steps

1. Add parser tests first.
   Cover `[string]: int`, `["a"]: int`, and `[=~"^a$"]: int` inside a struct
   with matching and nonmatching regular fields.
   Completed in the parser field pattern syntax slice.

2. Parse pattern fields separately from regular fields.
   Completed in the parser field pattern syntax slice.
   `Kue/Parse.lean` now collects `[expr]: value` entries and lowers them to
   `structPattern` values with the surrounding regular fields.

3. Document the remaining representation caveat.
   Completed in the parser field pattern syntax slice.
   Multiple pattern fields still share the current single-pattern semantic
   representation and are tracked in `docs/spec/compat-assumptions.md`.

4. Verify. Completed in the parser field pattern syntax slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Parser List Ellipsis Syntax

Goal: let stdin CUE source express open list tails such as `[int, ...string]`,
which Kue already models as `listTail` values.

### Steps

1. Add parser tests first.
   Cover `[...int]` and `[int, ...string] & [1, "x", "y"]`.
   Completed in the parser list ellipsis syntax slice.

2. Specialize list parsing for ellipsis tails.
   Completed in the parser list ellipsis syntax slice.
   `Kue/Parse.lean` now recognizes typed `...T` entries in list position and
   requires the tail to be the final list element.

3. Update parser assumptions.
   Completed in the parser list ellipsis syntax slice.
   `docs/spec/compat-assumptions.md` now distinguishes supported list ellipses from
   unsupported struct ellipsis syntax.

4. Verify. Completed in the parser list ellipsis syntax slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Parser Byte Literals

Goal: let stdin CUE source express byte literals such as `'abc'`, matching the
existing bytes kind and byte primitive semantics.

### Steps

1. Add parser tests first.
   Cover a standalone byte literal field and `bytes & 'abc'`.
   Completed in the parser byte literals slice.

2. Parse single-quoted literals as bytes.
   Completed in the parser byte literals slice.
   `Kue/Parse.lean` now uses the quoted-literal helper for `'...'` and lowers
   the result to `.prim (.bytes value)`.

3. Update parser assumptions.
   Completed in the parser byte literals slice.
   Byte literals are no longer listed as unsupported in
   `docs/spec/compat-assumptions.md`.

4. Verify. Completed in the parser byte literals slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Evaluate Struct Pattern Fields

Goal: make parsed pattern structs constrain their own declared regular fields,
matching CUE's behavior for `{[string]: int, a: "bad"}`.

### Steps

1. Add failing tests first.
   Cover direct `structPattern` evaluation and stdin parsing of a conflicting
   pattern field.
   Completed in the evaluate struct pattern fields slice.

2. Apply patterns during evaluation.
   Completed in the evaluate struct pattern fields slice.
   `Kue/Eval.lean` now evaluates the fields, label pattern, and constraint,
   then uses the existing lattice meet to apply that pattern to the evaluated
   fields.

3. Verify. Completed in the evaluate struct pattern fields slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Nested Struct Reference Scopes

Goal: resolve references inside nested structs against their nearest local
struct fields, while preserving fallback to enclosing fields for currently
label-based outer references.

### Steps

1. Add failing tests first.
   Cover `x: {#A: int, x: #A}` through both the resolver/evaluator layer and
   stdin parsing.
   Completed in the nested struct reference scopes slice.

2. Give nested compound structs local binding environments.
   Completed in the nested struct reference scopes slice.
   `Kue/Resolve.lean` now resolves nested structs, struct tails, and pattern
   structs against their own fields instead of reusing the enclosing binding
   ids.

3. Preserve outer fallback during evaluation.
   Completed in the nested struct reference scopes slice.
   `Kue/Eval.lean` evaluates nested resolved references with local bindings,
   while unresolved labels see `nested ++ outer` visible fields.

4. Document the scoped-binding compromise.
   Completed in the nested struct reference scopes slice.
   See `docs/spec/compat-assumptions.md`.

5. Verify. Completed in the nested struct reference scopes slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Evaluated Disjunction Normalization

Goal: make parsed regular disjunctions use the same normalization already
implemented by `join`, so source such as `>=5 | >=0` evaluates to `>=0`.

### Steps

1. Add failing tests first.
   Cover evaluator normalization for integer-bound disjunctions and parser
   normalization for both `>=5 | >=0` and `number | 1`.
   Completed in the evaluated disjunction normalization slice.

2. Normalize all-regular evaluated disjunctions.
   Completed in the evaluated disjunction normalization slice.
   `Kue/Eval.lean` folds regular alternatives with `join` after evaluating
   them. Default-marked disjunctions stay explicit so manifestation semantics
   are unchanged.

3. Verify. Completed in the evaluated disjunction normalization slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: CLI Fixture Regression Check

Goal: make the current CUE fixture corpus mechanically guard the stdin parser
and runtime path, not only the hand-written Lean fixture ports.

### Steps

1. Extend the fixture checker.
   Completed in the CLI fixture regression check slice.
   `scripts/check-fixtures.sh` now builds the `kue` executable and compares
   `kue < fixture.cue` output against every non-manifest `.expected` file.

2. Update documentation.
   Completed in the CLI fixture regression check slice.
   `README.md` now describes CLI fixture comparison as part of fixture checks.

3. Verify. Completed in the CLI fixture regression check slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Parser Struct Embeddings

Goal: support common CUE schema composition forms such as `{#Base, a: 1}` by
lowering struct embeddings to existing conjunction and meet semantics.

### Steps

1. Add parser tests first.
   Cover embedding a definition reference and embedding an inline struct
   literal inside another struct.
   Completed in the parser struct embeddings slice.

2. Represent parsed embeddings.
   Completed in the parser struct embeddings slice.
   `Kue/Parse.lean` now tracks embedding entries separately from regular fields
   and pattern fields, then lowers them to a conjunction with the declared
   struct body.

3. Keep imports explicitly unsupported.
   Completed in the parser struct embeddings slice.
   Top-level `import` clauses now fail before normal field or embedding parsing.

4. Document the lowering assumption.
   Completed in the parser struct embeddings slice.
   See `docs/spec/compat-assumptions.md`.

5. Verify. Completed in the parser struct embeddings slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Independent Multiple Pattern Fields

Goal: preserve independent CUE pattern fields instead of collapsing them into a
single combined pattern constraint.

### Steps

1. Add failing parser and fixture tests first.
   Cover a struct with two regex pattern fields where one declared field matches
   both patterns, and other declared fields match only one pattern each.
   Completed in the independent multiple pattern fields slice.

2. Extend the value domain with `structPatterns`.
   Completed in the independent multiple pattern fields slice.
   The existing `structPattern` constructor remains for singleton patterns, while
   multiple pattern fields carry a list of independent label-pattern/constraint
   pairs.

3. Update lattice, order, formatting, manifestation, normalization, resolution,
   evaluation, and builtin traversal.
   Completed in the independent multiple pattern fields slice.
   Multiple pattern constraints are applied sequentially to matching regular
   fields, and closed pattern structs allow regular fields that match any one
   pattern.

4. Update compatibility assumptions.
   Completed in the independent multiple pattern fields slice.

5. Verify.
   Completed in the independent multiple pattern fields slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Parser Let Bindings

Goal: let stdin CUE source express ordinary `let` declarations so local helpers
can participate in reference resolution without appearing in output.

### Steps

1. Add failing parser and fixture tests first.
   Cover a top-level `let` binding and a nested struct `let` binding whose value
   is unified through a regular output field.
   Completed in the parser let bindings slice.

2. Represent `let` declarations as non-output binding fields.
   Completed in the parser let bindings slice.
   `Kue/Parse.lean` lowers `let name = expr` entries to `.letBinding` fields so
   the existing resolver and evaluator can reuse their binding-id path.

3. Filter `let` bindings from formatting and manifestation.
   Completed in the parser let bindings slice.
   `Kue/Format.lean` and `Kue/Manifest.lean` now skip `.letBinding` fields
   while still allowing them to resolve references.

4. Document the binding-model assumption.
   Completed in the parser let bindings slice.
   See `docs/spec/compat-assumptions.md`.

5. Verify.
   Completed in the parser let bindings slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Parser Untyped Struct Ellipsis

Goal: let stdin CUE source express untyped `...` declarations in structs,
preserving open-tail intent through parsing, formatting, and CLI fixtures.

### Steps

1. Add failing parser and formatter tests first.
   Cover formatting `.structTail ... .top`, parsing `{a: int, ...}`, and
   unifying an untyped ellipsis struct with an extra concrete field.
   Completed in the parser untyped struct ellipsis slice.

2. Parse untyped struct ellipses.
   Completed in the parser untyped struct ellipsis slice.
   `Kue/Parse.lean` now tracks an optional struct tail and lowers bare `...` to
   `.structTail fields .top`.

3. Render top tails as bare ellipses.
   Completed in the parser untyped struct ellipsis slice.
   `Kue/Format.lean` now prints `.structTail ... .top` as `...` instead of
   `..._`, which also applies to open list tails with top.

4. Document the typed-tail compatibility boundary.
   Completed in the parser untyped struct ellipsis slice.
   See `docs/spec/compat-assumptions.md`.

5. Verify.
   Completed in the parser untyped struct ellipsis slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Duplicate Field Unification

Goal: make multiple fields with the same label inside one parsed struct unify to
one evaluated field, matching CUE's struct literal semantics.

### Steps

1. Add failing parser and fixture tests first.
   Cover compatible duplicate fields (`int` and `1`) and conflicting duplicate
   fields that preserve field-level bottom.
   Completed in the duplicate field unification slice.

2. Add a reusable duplicate-field merge helper.
   Completed in the duplicate field unification slice.
   `Kue/Lattice.lean` now exposes `mergeFieldListWith` as a fold over the
   existing field merge rules.

3. Normalize evaluated struct fields.
   Completed in the duplicate field unification slice.
   `Kue/Eval.lean` now merges duplicate fields after evaluating references in
   structs, struct tails, and pattern structs.

4. Document the provenance boundary.
   Completed in the duplicate field unification slice.
   See `docs/spec/compat-assumptions.md`.

5. Verify.
   Completed in the duplicate field unification slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Static Field Aliases

Goal: support the common static field alias form `A="label": value`, so fields
whose labels are not valid identifiers can be referenced by an alias.

### Steps

1. Add failing parser and fixture tests first.
   Cover a static field alias for a quoted label and a regular field that
   references the alias.
   Completed in the static field aliases slice.

2. Parse aliased static fields.
   Completed in the static field aliases slice.
   `Kue/Parse.lean` now recognizes `identifier=label: value` and keeps the
   declared field plus a non-output alias binding.

3. Reuse existing binding resolution.
   Completed in the static field aliases slice.
   The alias lowers to a `.letBinding` reference to the aliased label, so no new
   evaluator path is needed for this narrow form.

4. Document unsupported alias positions.
   Completed in the static field aliases slice.
   See `docs/spec/compat-assumptions.md`.

5. Verify.
   Completed in the static field aliases slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

## Completed Slice: Explicit File-Argument Merging

Goal: let the executable evaluate multiple source files as one CUE package when those
files are passed explicitly on the command line.

### Steps

1. Add a failing runtime test first.
   Cover two `package demo` sources where one file constrains `a: int` and the
   other provides `a: 1` plus a reference `b: a`.
   Completed in the explicit file-argument merging slice.

2. Add a pure multi-source runtime helper.
   Completed in the explicit file-argument merging slice.
   `Kue.Runtime.evalSourcesToString` parses each source, unifies the parsed values,
   and then runs the existing resolve/evaluate/format path.

3. Wire executable file arguments to the helper.
   Completed in the explicit file-argument merging slice.
   `kue file1.cue file2.cue` now reads all given files and evaluates them together.

4. Document the package identity boundary.
   Completed in the explicit file-argument merging slice.
   Package names are still ignored and imports are still unsupported.

5. Verify.
   Completed in the explicit file-argument merging slice.

   ```sh
   lake build Kue.RuntimeTests
   lake build kue:exe
   .lake/build/bin/kue /tmp/kue-cue-merge-check/a.cue /tmp/kue-cue-merge-check/b.cue
   ```

## Completed Slice: Package Name Consistency

Goal: reject explicit multi-file evaluations that provide different package names,
matching the first package identity check exposed by `cue eval`.

### Steps

1. Add failing runtime tests first.
   Cover rejecting two explicit files with different package names, and keep the
   upstream-compatible case where a package-less file merges with a named package.
   Completed in the package name consistency slice.

2. Extract leading package clause names.
   Completed in the package name consistency slice.
   `Kue.Parse.sourcePackageName` reads leading `package` clauses using the current
   parser's identifier rules.

3. Check package names in the multi-source runtime path.
   Completed in the package name consistency slice.
   `Kue.Runtime.evalSourcesToString` rejects conflicting named packages before
   parsing and merging package bodies.

4. Document the remaining package boundary.
   Completed in the package name consistency slice.
   Imports and full module resolution remain unsupported.

5. Verify.
   Completed in the package name consistency slice.

   ```sh
   lake build Kue.RuntimeTests
   ```

## Completed Slice: Decimal Numeric Separators and Exponents

Goal: parse common decimal numeric literal spelling that CUE accepts, including
separator underscores and exponent notation in the tested CUE-compatible forms.

### Steps

1. Add failing parser and fixture tests first.
   Cover `1_000`, `1.25e3`, and `-2e3`, using expected output checked against
   `cue eval`.
   Completed in the decimal numeric separators and exponents slice.

2. Normalize numeric tokens at parse time.
   Completed in the decimal numeric separators and exponents slice.
   The parser strips `_` separators and inserts an explicit `+` sign for exponent
   literals that omit one.

3. Preserve the current semantic representation.
   Completed in the decimal numeric separators and exponents slice.
   Exponent values still store a float spelling string; full numeric
   canonicalization remains later work.

4. Document the numeric canonicalization boundary.
   Completed in the decimal numeric separators and exponents slice.
   See `docs/spec/compat-assumptions.md`.

5. Verify.
   Completed in the decimal numeric separators and exponents slice.

   ```sh
   lake build Kue.ParseTests Kue.FixtureTests
   ```

## Completed Slice: Static Field Selectors

Goal: support static selector expressions such as `base.inner` for declared struct
fields, using the existing resolver and evaluator pipeline.

### Steps

1. Add failing parser, evaluator, and fixture tests first.
   Cover a top-level `base.inner` selector where `base` is a struct containing
   `inner: 4`.
   Completed in the static field selectors slice.

2. Add a selector value form.
   Completed in the static field selectors slice.
   `Value.selector` carries the base expression and static label.

3. Parse selector postfixes.
   Completed in the static field selectors slice.
   `Kue.Parse` now parses repeated `.label` postfixes after primary expressions.

4. Resolve and evaluate selectors.
   Completed in the static field selectors slice.
   Selector bases are resolved recursively; evaluation selects declared fields from
   evaluated structs and leaves missing struct selectors incomplete.

5. Document the selector boundary.
   Completed in the static field selectors slice.
   Index selection, dynamic selection, and richer selector diagnostics remain later
   work at this point in the plan.

6. Verify.
   Completed in the static field selectors slice.

   ```sh
   lake build Kue.ParseTests Kue.EvalTests Kue.FixtureTests
   ```

## Completed Slice: Static Index Expressions

Goal: support common static index expressions such as `xs[1]` and `base["inner"]`
using the existing resolver and evaluator pipeline.

### Steps

1. Add failing parser, evaluator, and fixture tests first.
   Cover a closed-list index and a string-literal struct field index, with expected
   output checked against `cue eval`.
   Completed in the static index expressions slice.

2. Add an index value form.
   Completed in the static index expressions slice.
   `Value.index` carries the base expression and key expression so keys can resolve
   through existing bindings before selection.

3. Parse index postfixes.
   Completed in the static index expressions slice.
   `Kue.Parse` now parses `[expr]` postfixes after primary expressions alongside
   repeated `.label` selectors.

4. Resolve and evaluate indices.
   Completed in the static index expressions slice.
   Index bases and keys are resolved recursively. Evaluation selects concrete integer
   indices from closed lists, concrete string keys from declared struct fields, and keeps
   missing string fields incomplete. Closed-list out-of-range indices bottom out with
   first-pass provenance.

5. Document the index boundary.
   Completed in the static index expressions slice.
   Dynamic fields, comprehensions, selector diagnostics, and full open-list index
   reasoning remain later work.

6. Verify.
   Completed in the static index expressions slice.

   ```sh
   lake build Kue.ParseTests Kue.EvalTests Kue.FixtureTests
   scripts/check-fixtures.sh
   ```

## Completed Slice: Non-Decimal Integer Literals

Goal: parse common non-decimal integer spellings that `cue eval` accepts and
canonicalizes to decimal integers.

### Steps

1. Add failing parser and fixture tests first.
   Cover lowercase hexadecimal, octal, binary, negative hexadecimal, and separated binary
   integer literals, with expected output checked against `cue eval`.
   Completed in the non-decimal integer literals slice.

2. Refactor digit parsing by base.
   Completed in the non-decimal integer literals slice.
   `Kue.Parse` now shares separator validation across decimal and base-prefixed digit
   sequences, then canonicalizes `0x`, `0o`, and `0b` integer tokens to decimal strings
   before lowering to `Prim.int`.

3. Document the numeric boundary.
   Completed in the non-decimal integer literals slice.
   Numeric suffixes and broader float canonicalization remain later work.

4. Verify.
   Completed in the non-decimal integer literals slice.

   ```sh
   lake build Kue.ParseTests Kue.FixtureTests
   scripts/check-fixtures.sh
   ```

## Completed Slice: Unary Plus Numeric Literals

Goal: parse unary plus on numeric literals without treating it as binary addition.

### Steps

1. Add failing parser and fixture tests first.
   Cover unary plus on decimal integers, decimal floats, and base-prefixed integers,
   with expected output checked against `cue eval`.
   Completed in the unary plus numeric literals slice.

2. Reuse the number token path.
   Completed in the unary plus numeric literals slice.
   `Kue.Parse` now accepts a leading `+` in numeric primary expressions and strips it
   before decimal, float, or base-prefixed integer lowering.

3. Verify.
   Completed in the unary plus numeric literals slice.

   ```sh
   lake build Kue.ParseTests Kue.FixtureTests
   scripts/check-fixtures.sh
   ```

## Completed Slice: Unary Numeric Expressions

Goal: parse and evaluate expression-level unary numeric `+` and `-`, not only signed
numeric literals.

### Steps

1. Add failing parser and fixture tests first.
   Cover grouped arithmetic operands, unary plus, unary minus over a reference, and
   unary precedence before multiplication, with expected output checked against
   `cue eval`.
   Completed in the unary numeric expressions slice.

2. Extend the unary operator representation.
   Completed in the unary numeric expressions slice.
   `UnaryOp.numPos` and `numNeg` preserve non-literal sign syntax through the shared
   residual expression path.

3. Evaluate concrete numeric operands.
   Completed in the unary numeric expressions slice.
   The evaluator handles concrete integers and float spelling strings. Incomplete
   numeric operands remain residual unary expressions until invalid operand diagnostics
   are modeled.

4. Parse numeric signs at unary precedence.
   Completed in the unary numeric expressions slice.
   `Kue.Parse` folds `+` and `-` recursively before multiplicative expressions, so
   `-2 * 3` evaluates as `-6`.

5. Verify.
   Completed in the unary numeric expressions slice.

   ```sh
   lake build Kue.ParseTests Kue.EvalTests Kue.FixtureTests
   scripts/check-fixtures.sh
   ```

## Completed Slice: Numeric Suffix Multipliers

Goal: parse CUE's decimal and binary numeric suffix multipliers when they produce exact
integer values.

### Steps

1. Add failing parser and fixture tests first.
   Cover `K`, `Ki`, fractional decimal suffixes such as `1.5K` and `1.5Ki`, and a
   negative suffixed decimal. Also cover that an inexact product such as `0.1Ki` fails.
   Completed in the numeric suffix multipliers slice.

2. Add exact multiplier parsing.
   Completed in the numeric suffix multipliers slice.
   `Kue.Parse` now recognizes `K`, `M`, `G`, `T`, `P` and `Ki`, `Mi`, `Gi`, `Ti`,
   `Pi` after decimal integer and decimal fraction literals. It multiplies using
   natural-number arithmetic over the decimal numerator and scale, then rejects products
   that cannot be represented as an integer.

3. Document the suffix boundary.
   Completed in the numeric suffix multipliers slice.
   Exponent-plus-suffix forms remain unsupported because `cue eval` rejects them.

4. Verify.
   Completed in the numeric suffix multipliers slice.

   ```sh
   lake build Kue.ParseTests Kue.FixtureTests
   scripts/check-fixtures.sh
   ```

## Completed Slice: Additive Expressions

Goal: support the first infix expression layer without introducing the full arithmetic
and comparison system at once.

### Steps

1. Add failing parser, evaluator, and fixture tests first.
   Cover concrete integer addition, concrete integer subtraction, and string
   concatenation, with expected output checked against `cue eval`.
   Completed in the additive expressions slice.

2. Add an additive expression representation.
   Completed in the additive expressions slice.
   `Value.binary` carries a small `BinaryOp` for `+` and `-`, and traversal layers now
   resolve, normalize, format, manifest, and evaluate binary operands consistently.

3. Parse additive expressions between primary expressions and conjunction.
   Completed in the additive expressions slice.
   `Kue.Parse` now parses `+` and `-` as left-associative infix operators before `&`
   and `|` folding.

4. Document the arithmetic boundary.
   Completed in the additive expressions slice.
   Float arithmetic, list concatenation, multiplication/division operators,
   comparisons, and boolean operators remain later work.

5. Verify.
   Completed in the additive expressions slice.

   ```sh
   lake build Kue.ParseTests Kue.EvalTests Kue.FixtureTests
   scripts/check-fixtures.sh
   ```

## Completed Slice: Bytes Additive Expressions

Goal: support byte-sequence concatenation with `+`, matching CUE's additive behavior
for concrete byte literals.

### Steps

1. Add failing parser and fixture tests first.
   Cover simple byte concatenation and left-associative chained byte concatenation, with
   expected output checked against `cue eval`.
   Completed in the bytes additive expressions slice.

2. Extend additive evaluation.
   Completed in the bytes additive expressions slice.
   `evalAdd` now concatenates concrete `Prim.bytes` operands in addition to ints and
   strings.

3. Document the list arithmetic boundary.
   Completed in the bytes additive expressions slice.
   Local `cue eval` for v0.15.4 rejects list `+` with the `v0.11-list-arithmetic`
   diagnostic and points users to `list.Concat`, so list `+` is not a compatibility
   target for this operator.

4. Verify.
   Completed in the bytes additive expressions slice.

   ```sh
   lake build Kue.ParseTests Kue.EvalTests Kue.FixtureTests
   scripts/check-fixtures.sh
   ```

## Completed Slice: Float Additive Expressions

Goal: support finite decimal float addition and subtraction without introducing a full
numeric tower.

### Steps

1. Add failing parser and fixture tests first.
   Cover decimal addition, int-plus-float promotion, float subtraction, whole float
   output with `.0`, exponent spelling, and exact decimal `0.1 + 0.2`, with expected
   output checked against `cue eval`.
   Completed in the float additive expressions slice.

2. Add finite-decimal parsing.
   Completed in the float additive expressions slice.
   `Kue.Eval` now parses int and float primitive spellings into scaled integer decimal
   values, including `e`/`E` exponents.

3. Evaluate additive decimal arithmetic exactly.
   Completed in the float additive expressions slice.
   Add/sub align decimal scales, perform integer arithmetic, trim redundant fractional
   zeroes, and keep `.0` when a float operand produced a whole-number result.

4. Document the numeric boundary.
   Completed in the float additive expressions slice.
   Float multiplication/division and richer numeric equivalence remain later work.

5. Verify.
   Completed in the float additive expressions slice.

   ```sh
   lake build Kue.ParseTests Kue.EvalTests Kue.FixtureTests
   scripts/check-fixtures.sh
   ```

## Completed Slice: Multiplication Expressions

Goal: add the first multiplicative operator while preserving CUE's precedence over
additive expressions.

### Steps

1. Add failing parser, evaluator, and fixture tests first.
   Cover concrete integer multiplication, multiplication before addition, and
   left-associative chained multiplication, with expected output checked against
   `cue eval`.
   Completed in the multiplication expressions slice.

2. Extend the binary operator representation.
   Completed in the multiplication expressions slice.
   `BinaryOp.mul` reuses the same `Value.binary` traversal and formatting path as
   additive expressions.

3. Parse multiplication above additive expressions.
   Completed in the multiplication expressions slice.
   `Kue.Parse` now folds `*` left-associatively before additive folding, so
   `1 + 2 * 3` evaluates as `7`.

4. Document the division boundary.
   Completed in the multiplication expressions slice.
   `/` remains unsupported because CUE renders it as float output even for whole
   integer division, so it belongs with a deliberate float-canonicalization pass.

5. Verify.
   Completed in the multiplication expressions slice.

   ```sh
   lake build Kue.ParseTests Kue.EvalTests Kue.FixtureTests
   scripts/check-fixtures.sh
   ```

## Completed Slice: Division Expressions

Goal: support `/` separately from the existing integer `div` builtin because CUE renders
ordinary division as decimal float output.

### Steps

1. Add failing parser, evaluator, and fixture tests first.
   Cover `5 / 2`, whole integer division as `2.0`, a recurring decimal `1 / 3`, and a
   negative division. Also cover division by zero at the evaluator level.
   Completed in the division expressions slice.

2. Extend binary evaluation with decimal rational rendering.
   Completed in the division expressions slice.
   `BinaryOp.div` evaluates concrete integer operands to `Prim.float` text. Terminating
   decimals are trimmed to their significant fractional digits, whole results keep `.0`,
   and recurring decimals are rendered to the 34 fractional digits observed from
   `cue eval`.

3. Parse division with multiplication precedence.
   Completed in the division expressions slice.
   `Kue.Parse` folds `/` left-associatively with `*`.

4. Document the float operand boundary.
   Completed in the division expressions slice.
   Division over existing float literals remains later work because Kue still stores
   floats as spelling strings rather than normalized numeric values.

5. Verify.
   Completed in the division expressions slice.

   ```sh
   lake build Kue.ParseTests Kue.EvalTests Kue.FixtureTests
   scripts/check-fixtures.sh
   ```

## Completed Slice: Integer Keyword Expressions

Goal: support CUE's integer keyword operators `div`, `mod`, `quo`, and `rem` as infix
multiplicative expressions.

### Steps

1. Add failing parser and fixture tests first.
   Cover Euclidean `div`/`mod`, truncated `quo`/`rem`, and additive precedence after
   keyword integer operators, with expected output checked against `cue eval`.
   Completed in the integer keyword expressions slice.

2. Extend binary operator syntax.
   Completed in the integer keyword expressions slice.
   `BinaryOp.intDiv`, `intMod`, `intQuo`, and `intRem` preserve CUE's infix spelling
   for residual formatting.

3. Reuse existing integer builtin semantics.
   Completed in the integer keyword expressions slice.
   The evaluator delegates the keyword operators to `divValue`, `modValue`, `quoValue`,
   and `remValue`, keeping division-by-zero and incomplete integer handling aligned with
   the existing builtin tests.

4. Parse keyword operators at multiplicative precedence.
   Completed in the integer keyword expressions slice.
   `Kue.Parse` recognizes keyword operators only at word boundaries, so identifiers
   such as `divide` are not consumed as `div`.

5. Verify.
   Completed in the integer keyword expressions slice.

   ```sh
   lake build Kue.ParseTests Kue.EvalTests Kue.FixtureTests
   scripts/check-fixtures.sh
   ```

## Completed Slice: Equality Expressions

Goal: support concrete `==` and `!=` expressions as the first comparison layer.

### Steps

1. Add failing parser, evaluator, and fixture tests first.
   Cover integer equality, integer inequality, string equality, and additive precedence
   before equality, with expected output checked against `cue eval`.
   Completed in the equality expressions slice.

2. Extend binary evaluation with equality operators.
   Completed in the equality expressions slice.
   `BinaryOp.eq` and `BinaryOp.ne` evaluate concrete primitive operands to booleans.
   Incomplete and compound equality remains represented as a binary expression.

3. Parse equality after additive and multiplicative expressions.
   Completed in the equality expressions slice.
   `Kue.Parse` now parses `==` and `!=` after arithmetic parsing, so
   `1 + 1 == 2` evaluates as `true`.

4. Document the comparison boundary.
   Completed in the equality expressions slice.
   Ordering comparisons and logical operators remain later work.

5. Verify.
   Completed in the equality expressions slice.

   ```sh
   lake build Kue.ParseTests Kue.EvalTests Kue.FixtureTests
   scripts/check-fixtures.sh
   ```

## Completed Slice: Ordering Expressions

Goal: support concrete primitive ordering comparisons after additive and multiplicative
expressions.

### Steps

1. Add failing parser, evaluator, and fixture tests first.
   Cover `<`, `<=`, `>`, `>=`, string ordering, and additive precedence before ordering,
   with expected output checked against `cue eval`.
   Completed in the ordering expressions slice.

2. Extend binary evaluation with ordering operators.
   Completed in the ordering expressions slice.
   `BinaryOp.lt`, `le`, `gt`, and `ge` evaluate concrete integer operands and concrete
   string operands to booleans. Mixed primitive kinds bottom out for now.

3. Parse ordering at comparison precedence.
   Completed in the ordering expressions slice.
   `Kue.Parse` now parses ordering operators in the same comparison layer as equality
   after arithmetic parsing.

4. Document the ordering boundary.
   Completed in the ordering expressions slice.
   Float ordering and ordering over incomplete or compound values remain later work.

5. Verify.
   Completed in the ordering expressions slice.

   ```sh
   lake build Kue.ParseTests Kue.EvalTests Kue.FixtureTests
   scripts/check-fixtures.sh
   ```

## Completed Slice: Numeric Comparison Expressions

Goal: compare concrete ints and finite decimal floats as one numeric domain.

### Steps

1. Add failing parser and fixture tests first.
   Cover int/float ordering, trailing-zero equality, exponent ordering, and numeric
   equality/inequality, with expected output checked against `cue eval`.
   Completed in the numeric comparison expressions slice.

2. Reuse finite-decimal parsing for comparisons.
   Completed in the numeric comparison expressions slice.
   The evaluator aligns decimal scales before equality and ordering comparisons, so
   `1 == 1.0` and `1e3 > 999.9` match CUE behavior.

3. Keep string ordering unchanged.
   Completed in the numeric comparison expressions slice.
   Numeric operands use scaled decimal comparison, string operands use the existing
   lexicographic ordering, and mixed concrete primitive kinds still bottom out.

4. Document the remaining comparison boundary.
   Completed in the numeric comparison expressions slice.
   Bytes, incomplete values, compound values, and richer diagnostics remain later work.

5. Verify.
   Completed in the numeric comparison expressions slice.

   ```sh
   lake build Kue.ParseTests Kue.EvalTests Kue.FixtureTests
   scripts/check-fixtures.sh
   ```

## Completed Slice: Logical Expressions

Goal: support concrete boolean `&&` and `||` expressions with CUE's non-short-circuit
operand evaluation behavior.

### Steps

1. Add failing parser, evaluator, and fixture tests first.
   Cover concrete boolean conjunction/disjunction, comparison operands before logical
   operators, arithmetic before comparison, and explicit grouping.
   Completed in the logical expressions slice.

2. Extend binary evaluation with logical operators.
   Completed in the logical expressions slice.
   `BinaryOp.boolAnd` and `boolOr` evaluate concrete boolean operands to booleans.
   Non-boolean concrete primitive operands bottom out. Incomplete logical operands
   remain residual binary expressions until Kue models CUE's invalid operand diagnostics.

3. Parse logical expressions between comparison and CUE value combination.
   Completed in the logical expressions slice.
   `Kue.Parse` now folds `&&` above `||`; both bind tighter than CUE `&` and `|`
   value operators and looser than equality/ordering comparisons.

4. Document the diagnostic boundary.
   Completed in the logical expressions slice.
   Local `cue eval` checks show `&&` and `||` require concrete values and do not
   short-circuit division errors. Kue mirrors the eager operand evaluation but defers
   incomplete operand diagnostics.

5. Verify.
   Completed in the logical expressions slice.

   ```sh
   lake build Kue.ParseTests Kue.EvalTests Kue.FixtureTests
   scripts/check-fixtures.sh
   ```

## Completed Slice: Logical Not Expressions

Goal: support concrete boolean unary `!` without lowering it into equality syntax.

### Steps

1. Add failing parser and fixture tests first.
   Cover `!false`, a grouped comparison operand, and double negation, with expected
   output checked against `cue eval`.
   Completed in the logical not expressions slice.

2. Add an explicit unary expression node.
   Completed in the logical not expressions slice.
   `UnaryOp.boolNot` and `Value.unary` preserve residual syntax through formatting,
   resolving, normalization, manifest incompleteness, lattice bottom detection, and
   subsumption.

3. Evaluate concrete boolean negation.
   Completed in the logical not expressions slice.
   The evaluator negates concrete boolean operands, bottoms out concrete non-boolean
   primitive operands, and keeps incomplete operands as residual unary expressions.

4. Parse `!` at unary precedence.
   Completed in the logical not expressions slice.
   `Kue.Parse` folds `!` recursively before multiplicative expressions while leaving
   the existing `!=literal` primitive exclusion parser intact.

5. Verify.
   Completed in the logical not expressions slice.

   ```sh
   lake build Kue.ParseTests Kue.EvalTests Kue.FixtureTests
   scripts/check-fixtures.sh
   ```

## Completed Slice: Regex Match Expressions

Goal: support concrete binary `=~` and `!~` expressions using Kue's existing regex
matcher.

### Steps

1. Add failing parser and fixture tests first.
   Cover positive match, failed match, negative match, failed negative match, and string
   concatenation before regex comparison. Expected output was checked against `cue eval`.
   Completed in the regex match expressions slice.

2. Extend binary evaluation with regex operators.
   Completed in the regex match expressions slice.
   `BinaryOp.regexMatch` and `regexNotMatch` evaluate concrete string operands to
   booleans. Concrete non-string primitive operands bottom out, and incomplete operands
   remain residual binary expressions.

3. Parse regex match at comparison precedence.
   Completed in the regex match expressions slice.
   `Kue.Parse` now parses `=~` and `!~` with equality and ordering comparisons, after
   additive parsing, so string concatenation binds first.

4. Document the regex boundary.
   Completed in the regex match expressions slice.
   Binary regex matching reuses the regex subset already implemented for label patterns;
   full CUE/RE2 compatibility remains later work.

5. Verify.
   Completed in the regex match expressions slice.

   ```sh
   lake build Kue.ParseTests Kue.EvalTests Kue.FixtureTests
   scripts/check-fixtures.sh
   ```

## Completed Slice: Lexical Scope Chain

Goal: represent lexical binding identities for scopes beyond the immediately
containing struct — the prerequisite the plan named for comprehensions and dynamic
fields. Loop variables and outer-struct fields had no lexical representation; outer
references survived only via a dynamic name-lookup fallback at evaluation time, which
is not lexically correct (shadowing, scope discipline).

Design fork resolved by the repo philosophy (precise/testable/formal over ad hoc): a
de Bruijn-style scope chain, not a synthetic-binding patch over the dynamic fallback.

### Steps

1. Widen `BindingId` from `{ index : Nat }` to `{ depth, index : Nat }`.
   `depth` counts scope frames outward (0 = innermost); `index` is the slot within
   that frame. `Format` renders a resolved reference as `@depth.index`. All existing
   references are same-struct, hence depth 0 — a mechanical migration of literals.

2. Resolve against a scope stack (`Kue/Resolve.lean`).
   `resolveValueWithFuel` now carries `scopes : List (List (String × Nat))` — a stack
   of label→slot frames, innermost first. Entering any struct pushes that struct's
   frame instead of discarding the outer scope. A `ref` resolves by searching frames
   innermost-first; `depth` is the frame distance, `index` the slot. An in-scope outer
   reference now resolves to a `refId` with `depth > 0` rather than surviving as a bare
   `ref`.

3. Evaluate against a matching environment stack (`Kue/Eval.lean`).
   `evalValueWithFuel` carries `env : List (List Field)` mirroring the resolver's
   frames. `refId ⟨depth, index⟩` drops `depth` frames and selects slot `index`,
   evaluating that field's value in the env visible at its definition scope. Cycle
   detection tracks visited slot indices within the current frame; following an outer
   reference re-bases onto the outer stack (where a lexical cycle back into a deeper
   frame cannot form) and resets the visited set.

4. Remove the dynamic name-lookup fallback.
   `evalValueWithFuel` no longer resolves a bare `ref` by scanning visible field names;
   an unresolved `ref` reaching evaluation is now `bottom` with `unresolvedReference`.
   All in-scope references are resolved lexically by step 2. Two unit tests that fed an
   unresolved `ref` straight to evaluation were rerouted through the real
   resolve-then-eval pipeline; the full fixture suite confirmed nothing depended on the
   fallback.

5. Verify.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

   New unit tests lock the capability: an inner field referencing an outer field
   resolves to `refId ⟨1, 0⟩`, prefers the nearest scope on shadowing (`⟨0, 0⟩`), and
   evaluates through to the outer value. All 82 fixture pairs stay green.


## Completed Slice: Comprehensions

Goal: add `for` / `if` field comprehensions that desugar into fields merged into
the enclosing struct, introducing one new scope kind (the loop variable) on the
lexical scope chain built by the previous slice. Dynamic fields `(expr): v` are
deliberately out of scope (next slice).

### Steps

1. Extend the value domain. Completed in the comprehensions slice.
   Add a `Clause Value` inductive — `forIn (key : Option String) (value : String)
   (source : Value)` and `guard (condition : Value)` — and two `Value`
   constructors: `comprehension (clauses) (body)`, and `structComp (fields)
   (comprehensions) (open_)`. `structComp` is a struct body that carries its
   comprehension embeddings so they resolve and evaluate within the struct's own
   lexical frame (a plain `.conj`-of-embeddings would have lost that scope —
   confirmed against the reference binary, where a comprehension body sees its
   sibling fields).

2. Parser. Completed in the comprehensions slice.
   `parseComprehension` parses a chain of `for k, v in expr` / `for v in expr` /
   `if cond` clauses followed by a `{ body }` struct. Clauses are recognised by
   the `for`/`if` keywords with a word boundary (so `format:` is still a field).
   Comprehensions are split into their own `ParsedFieldParts.comprehensions` list;
   `parsedFieldsValue` emits a `structComp` when any are present.

3. Resolver. Completed in the comprehensions slice.
   `clauseLoopFrame` defines the loop-variable frame: a keyed `for k, v` binds
   `k` at index 0 and `v` at index 1; an unkeyed `for v` binds `v` at index 0.
   `resolveClausesWithFuel` resolves each clause's source/condition in the scope
   that precedes it, then pushes the loop frame for subsequent clauses and the
   body. `structComp` resolves its fields and comprehensions against
   `buildFrame fields :: scopes`, so loop vars and enclosing fields both resolve
   to `(depth, index)` binding ids.

4. Evaluator. Completed in the comprehensions slice.
   `structComp` evaluates its static fields, then expands each comprehension at
   eval time and merges the produced fields via the existing same-label meet
   (matching the reference binary, where two iterations emitting the same static
   label unify — and conflict to field-level bottom when their values differ).
   `comprehensionPairs` iterates lists as `(int index, element)` and structs as
   `(string label, value)` over regular fields. `expandClausesWithFuel` walks the
   clause chain: each `for` pushes a synthetic loop frame (`loopFrame`, mirroring
   `clauseLoopFrame`) per iteration; each `if` admits its remaining expansion only
   when the condition evaluates to `true`, else contributes nothing; with no
   clauses left, the body struct is evaluated in the current env and its fields
   emitted.

5. Totality plumbing. Completed in the comprehensions slice.
   Format renders the new constructors; Manifest treats both as incomplete (they
   evaluate away before manifestation); Lattice `meetCore` adds bottom-producing
   fallthroughs for the pre-eval forms. `meet_identical_prim` was reproved via an
   explicit `meetWithFuel`/`meetCore` rewrite chain — the enlarged `Value` match
   made the old full-unfold `simp` exceed the inner whnf heartbeat cap.

6. Fixtures and unit tests. Completed in the comprehensions slice.
   Oracle: `cue` v0.16.1. `comprehension_for` covers `for k, v` over a struct;
   `comprehension_guard` covers a list `for` plus `if true` / `if false` guards
   alongside a regular field. Lean Eval/Resolve theorems lock both loop-var forms,
   struct/list iteration, guard admit/drop, loop-var binding ids, and body
   references to sibling and outer fields.

7. Verify. Completed in the comprehensions slice.

   ```sh
   lake build
   scripts/check-fixtures.sh
   shellcheck scripts/check-fixtures.sh
   ```

   All fixture pairs stay green.

### Follow-up surfaced (not in this slice)

Plain struct embeddings (`{ … }` embedded directly, not via a comprehension)
still resolve their references against the embedded struct's own scope rather
than the enclosing struct — e.g. `out: { base: 7, {copy: base} }` yields a
bottom `copy` where the reference binary resolves it to `7`. The comprehension
path sidesteps this by carrying its bodies inside `structComp`; the general
embedding-scope fix is a separate slice.

---

## Completed Slice: Dynamic Fields

Commit `804ceff`. Computed field labels `(expr): v`, plus the string
interpolation `"\(expr)"` that is the common label form. Behavioral target: a
dynamic field's label is an expression evaluated against the enclosing struct's
scope; the canonical use is a comprehension body emitting distinct labels per
iteration — `for k, v in {a: 1, b: 2} {"\(k)": v}` => `{a: 1, b: 2}`.

### Representation

1. `Value.interpolation (parts : List Value)`. Literal segments are string prims,
   holes are exprs (alternating, but stored uniformly). Eval coerces each
   evaluated part to its CUE string rendering — string content verbatim;
   int/float/bool/null by literal spelling (`interpolationText?`) — and
   concatenates. A bottom hole propagates bottom; a hole with no string rendering
   (bytes, or an unresolved non-primitive) leaves the `.interpolation` residual.

2. `Value.dynamicField (label : Value) (fieldClass) (value : Value)`. Carried in
   `structComp`'s `comprehensions` list, so it resolves in the struct's own
   lexical frame (`buildFrame fields :: scopes`) exactly like static fields and
   `for`-loop variables, and composes with the `(depth, index)` scope chain. It
   expands at eval time: evaluate `label`; if it is a string prim, emit the single
   field `(name, fieldClass, eval value)`; otherwise the field is bottom / dropped.
   Same-label collisions meet through the existing `structComp` merge (verified:
   `{a: 1, (k): 1}` with `k: "a"` => `{a: 1}`).

### Parser

3. Interpolation-aware string scanner (`parseInterpolatedString`) splits a quoted
   literal on `\( … )`, recursing into `parseExpression` for each hole. No holes =>
   `.prim (.string …)` (unchanged behavior); holes => `.interpolation`.

4. `(expr): v` (with optional `?`/`!` class) parses to `.dynamicField`
   (`parseDynamicField`). A quoted label carrying interpolation
   (`parseQuotedLabelField`) becomes a dynamic field whose label is the
   interpolation value; a plain quoted label stays a static field. Both forms fall
   back to embedding on mismatch. `ParsedField.dynamicField` routes through the
   `comprehensions` bucket in `splitParsedFields`, so `parsedFieldsValue` builds a
   `structComp`.

### Totality plumbing

5. Format renders both new constructors (`"\(…)"` and `(label): value`). Resolve
   recurses into interpolation parts and the dynamic-field label/value in the
   current scope. Lattice `meetCore` and Manifest get arms for the two pre-eval
   forms (residual bottom / incomplete). `expandComprehensionWithFuel` was made
   fuel-destructuring so its new dynamic-field eval calls satisfy structural
   recursion.

### Fixtures

6. Oracle `cue` v0.16.1. `string_interpolation` (number-in-string),
   `dynamic_field` (direct `(k): 42`), `dynamic_field_comprehension` (the
   interpolated-label oracle). Both the CLI path and hand-built Lean-AST
   FixturePorts diff clean against the `.expected`.

### Verify

```sh
lake build
scripts/check-fixtures.sh
shellcheck scripts/check-fixtures.sh
```

`lake build` 66 jobs, `fixture pairs ok`, shellcheck clean.

### Note on commit granularity

Interpolation was the planned precursor, but its parser and the dynamic-field
representation are co-dependent (interpolated labels are *the* dynamic-field form),
and the edits interleave within the same hunks of `Value`/`Parse`/`Eval`. A clean
two-commit split would need interactive staging or a non-building intermediate, so
this landed as one atomic green commit covering both.

## Completed Slice: Struct-Embedding Scope

The general struct-embedding scope bug deferred during comprehensions and
re-confirmed during dynamic fields. A `{ … }` embedded directly in a struct
(`out: { base: 7, {copy: base} }`) resolved its body against the *embedded*
struct's lexical frame, so an inner reference to an enclosing field became bottom
(`copy: _|_`). Oracle `cue` v0.16.1 resolves `copy: 7`.

### Root cause

`parsedFieldsValue` (`Kue/Parse.lean`) emitted plain embeddings as a flat
`.conj (embeddings ++ [base])`. Resolution's `.conj` arm maps each member in the
*current* scope; an embedded `{copy: base}` is itself a `.struct`, whose Resolve
arm pushes only its own `buildFrame` — `base` is absent there, so it stayed an
unresolved `.ref` and evaluated to bottom. The comprehension and dynamic-field
paths never hit this because they ride `structComp`, whose Resolve/Eval arms push
the enclosing `buildFrame fields :: scopes` before touching the `comprehensions`
bucket.

### Fix (uniform: embeddings join the `structComp` bucket)

1. **Parser.** `splitParsedFields` routes `.embedding value` into the
   `comprehensions` bucket instead of a separate `embeddings` list (which is now
   removed from `ParsedFieldParts`, along with the trailing `match parts.embeddings`
   in `parsedFieldsValue`). Embeddings preserve source order alongside
   comprehensions/dynamic fields. A struct with any embedding is thus a
   `structComp`, resolved in its own frame.

2. **Eval.** The `structComp` arm splits the bucket: field-producing members
   (`.comprehension`, `.dynamicField`) expand to fields merged with the static
   fields as before; plain embeddings (`isEmbeddingValue`: anything not a
   comprehension or dynamic field) are evaluated in the enclosing `nested` env and
   `meet`-folded into the assembled `.struct`. So a struct embedding merges its
   fields (collisions meet — same value unifies, conflict → field bottom) and a
   non-struct embedding (`{ x: 1, 5 }`) conflicts to bottom — both via the lattice,
   both in the enclosing lexical frame. `expandComprehensionWithFuel`'s catch-all
   already returns `[]` for embeddings, so they never double-contribute fields.

No signature change to `structComp` or its Lattice/Manifest/Format arms — the
bucket stays opaque to them.

### Fixtures

Oracle `cue` v0.16.1. `struct_embedding_scope` (`{base: 7, {copy: base}}` =>
`copy: 7`), `struct_embedding_nested` (embedding referencing outer through a deeper
struct), `struct_embedding_siblings` (one embedding referencing two enclosing
fields). CLI path and hand-built Lean-AST FixturePorts both diff clean.
Regression-checked by hand against the oracle: comprehension+dynamic+embedding mix,
same-value collision merge, conflicting collision, and scalar embedding.

### Verify

```sh
lake build
scripts/check-fixtures.sh
shellcheck scripts/check-fixtures.sh
```

`lake build` 66 jobs, `fixture pairs ok`, shellcheck clean.

---

## Completed Slice: strings Builtins

Goal: add the first package-qualified builtin family — a coherent, oracle-verified
subset of CUE's `strings` package — and the dispatch infrastructure that
package-qualified calls (`strings.X(...)`) require, since none existed before.

### Dispatch infrastructure (the slice's core)

Package-qualified calls did not parse at all. `strings.ToUpper("x")` parsed as
`.ref "strings"` → `parseSelectorRest` made `.selector (.ref "strings") "ToUpper"`,
then hit `(` with no arm and left it unconsumed. Two parser changes:

1. **Call-on-selector.** `parseSelectorRest` gains a `'(' :: …` arm after reading a
   selector label: when the selector base is a bare `.ref pkg`, it parses the call
   and emits `.builtinCall "pkg.label" args` (the package name is folded into the
   builtin name, dotted). Deeper selectors (`a.b.c(...)`) stay ordinary field access
   — only the single `pkg.fn(...)` shape is a builtin, matching how `strings.*`
   resolves. No new `Value` constructor: qualified builtins reuse `.builtinCall` with
   a dotted name, so Resolve/Eval/Manifest/Format need no new arms.
2. **Imports accepted.** `import "strings"` and grouped `import ( … )` blocks are now
   consumed and ignored (`consumeImportClauses`, paralleling `consumePackageClauses`)
   instead of `parseError "imports are not supported yet"`. The package is implicit
   in the qualified builtin name, so no symbol binding is needed yet. The old
   `parse_imports_are_unsupported` test is replaced by two tests asserting single and
   grouped import clauses parse and are dropped.

### Dispatch + implementation

`evalBuiltinCall`'s catch-all routes any `name.startsWith "strings."` to a new
`evalStringsBuiltin`. Args arrive fully evaluated (Eval evaluates args before
dispatch), so arms match on concrete `.prim`/`.list` shapes. Implemented (Go/CUE
semantics, each oracle-checked against `cue` v0.16.1):

- `strings.Contains`, `strings.HasPrefix`, `strings.HasSuffix` — byte substring /
  prefix / suffix.
- `strings.Index` — **byte** offset of first match, `-1` if absent (Go semantics;
  `Index("héllo","llo") = 3`, the byte offset, confirmed against the oracle).
- `strings.Count` — non-overlapping count; empty needle ⇒ rune-count + 1.
- `strings.Split` — `splitOn`, keeping trailing empties; **empty separator splits
  per rune** (`Split("héllo","") = ["h","é","l","l","o"]`, not per byte).
- `strings.Join` — intercalate; any non-string element ⇒ bottom.
- `strings.Replace` — first `count` non-overlapping replacements, `count < 0` ⇒ all.
- `strings.Repeat` — `n` copies; negative `n` ⇒ bottom (CUE errors).
- `strings.TrimSpace` — strip leading/trailing unicode whitespace.
- `strings.Fields` — split on unicode-whitespace runs, dropping empties.

**Totality / illegal states.** An unmatched `strings.*` call is bottom iff its args
are all concrete (a genuine type error, e.g. `strings.Contains(5, "x")`); if any arg
is still abstract (`.kind`, `.ref`, an unresolved call) the call round-trips
unresolved as `.builtinCall`, so it can resolve once unified further. Bottom args
propagate to bottom.

**Deliberately deferred (noted as remaining):** `strings.ToUpper`/`ToLower`/`ToTitle`
need full unicode case folding — Lean's `String.toUpper`/`toLower` are ASCII-only
(`"héllo".toUpper = "HéLLO"`, diverging from CUE's `"HÉLLO"`). Implementing them would
require a unicode case table; left out to keep this slice oracle-exact. Also remaining:
`strings.SplitN`, `TrimPrefix`/`TrimSuffix`/`Trim`, `Title`, `Runes`, `MinRunes`/
`MaxRunes`, `ContainsAny`, `LastIndex`, etc.

### Fixtures + tests

`strings_builtin` fixture exercises all 11 implemented functions (incl. multibyte
index, per-rune empty-sep split, trailing-empty split, count-limited replace).
CLI path and hand-built FixturePort both diff clean against the oracle-derived
`.expected`. Eight `native_decide` unit theorems in `BuiltinTests` lock the edge
cases: byte-index, missing-index `-1`, per-rune split, empty-needle count, join
type-error bottom, negative-repeat bottom, concrete type-mismatch bottom, and
abstract-arg stays unresolved.

### Verify

```sh
lake build
scripts/check-fixtures.sh
shellcheck scripts/check-fixtures.sh
```

`lake build` 66 jobs, `fixture pairs ok`, shellcheck clean.

## Completed Slice: list Builtins

Goal: add a coherent, oracle-verified subset of CUE's `list` package, reusing the
package-qualified dispatch landed in the strings slice. No new infrastructure — an
`evalListBuiltin` helper plus a `name.startsWith "list."` catch-all route in
`evalBuiltinCall`.

### Dispatch + implementation

`evalBuiltinCall` now routes `list.*` to `evalListBuiltin`, mirroring the strings
arm (concrete-arg type-mismatch ⇒ bottom; all-concrete-but-unmatched ⇒ bottom;
abstract args keep the call unresolved). Args arrive fully evaluated. Implemented,
each oracle-checked against `cue` v0.16.1:

- `list.Concat([[…],…])` — concatenate sub-lists; a non-list element ⇒ bottom.
- `list.FlattenN(list, depth)` — flatten up to `depth` levels; `depth == 0` is a
  no-op, `depth < 0` flattens fully; non-list elements pass through.
  (`FlattenN([[1,[2]],[3]], 1) = [1,[2],3]`.)
- `list.Repeat(list, n)` — `n` copies concatenated; `n < 0` ⇒ bottom.
- `list.Range(start, limit, step)` — integer arithmetic sequence, half-open at
  `limit`; ascending for `step > 0`, descending for `step < 0`; `step == 0` ⇒
  bottom ("step must be non zero"). Element count computed by ceiling division so
  the off-by-one at the bound matches the oracle (`Range(0,5,2) = [0,2,4]`).
- `list.Slice(list, low, high)` — sub-slice; negative index or `high > len` or
  `low > high` ⇒ bottom (CUE distinguishes the messages; we collapse to bottom).
- `list.Take(list, n)` / `list.Drop(list, n)` — prefix / suffix; `n` past the end
  is clamped (Take all / Drop to empty); negative `n` ⇒ bottom.
- `list.Contains(list, x)` — structural `BEq` membership. Restricted to concrete
  `.prim`/`.list` needles so an abstract needle still routes to the unresolved arm.
- `list.Sum(list)` — integer sum, empty ⇒ 0; a non-integer element ⇒ bottom.
- `list.Min(list)` / `list.Max(list)` — integer min/max; empty ⇒ bottom; a
  non-integer element ⇒ bottom.

All helpers are total: error cases are explicit bottom, not partial matches. Only
`FlattenN` is `partial` (depth recursion); the rest are structural.

### Deferred (noted, not faked)

- **`list.Avg`** — CUE returns an *exact rational* mean, collapsing to `int` when the
  count divides the sum evenly (`Avg([1,2,3]) = 2`, `Avg([1,2]) = 1.5`) and otherwise
  a float printed with apd's 34-significant-digit context (`Avg([1,2,4]) = 2.333…`
  to 33 digits). kue's `/` operator always yields a `.0`-suffixed float, so Avg can't
  reuse it; matching the int-collapse + sig-digit rounding needs the shared decimal
  formatter. Deferred to avoid a non-oracle-exact approximation.
- **Float-domain `Sum`/`Min`/`Max` and float `list.Range`** — these need decimal
  arithmetic (`addDecimalValues`, decimal compare) which currently lives in `Eval`.
  `Builtin` cannot import `Eval` (Eval imports Builtin — a cycle), so the decimal
  machinery (`DecimalValue`, `addDecimalValues`, `formatFiniteDecimal`,
  `decimalFromPrim?`) must first be lifted into a lower module (`Lattice` or a new
  `Decimal` module) before the builtin layer can reuse it. Scoped as its own refactor
  slice. Integer domain is implemented and oracle-exact now.
- **`list.Sort` / `list.SortStable` / `list.SortStrings`** — `Sort` takes a *comparator
  struct* `{x: _, y: _, less: x < y}` (with `list.Ascending`/`list.Descending` being
  predefined such structs), not a plain function value. Evaluating `less` against
  per-pair `x`/`y` bindings is beyond what the builtin layer can express today; deferred
  rather than faked.

### Tests

`list_builtin` fixture exercises every implemented function incl. the no-op/negative
FlattenN depths, descending Range, over-range Take/Drop clamps, structural Contains,
and empty Sum. CLI path and hand-built FixturePort both diff clean against the
oracle-derived `.expected`. Sixteen `native_decide` theorems in `BuiltinTests` lock
the edges: Concat one-level, FlattenN depth-1 vs full, descending Range, zero-step
bottom, Slice out-of-range and inverted bottom, negative Repeat/Take bottom, Sum
empty = 0, Sum non-int bottom, Min/Max empty bottom, structural Contains, and
abstract-arg stays unresolved.

### Verify

```sh
lake build
scripts/check-fixtures.sh
shellcheck scripts/check-fixtures.sh
```

`lake build` 66 jobs, `fixture pairs ok`, shellcheck clean.

---

## Completed Slice: Decimal-Lift Refactor

Goal: break the `Builtin → Eval` import cycle so the builtin layer can do
exact-decimal arithmetic, comparison, and formatting — the blocker noted in the
`list` and `strings` slices for `list.Avg`, float-domain `Sum`/`Min`/`Max`, and float
`list.Range`. Pure structural move; **zero behavior change**.

### What moved

The entire decimal block left `Kue/Eval.lean` for a new `Kue/Decimal.lean`:

- **Type:** `DecimalValue` (exact `numerator : Int` / `scale : Nat` rational-of-ten).
- **Parsing:** `parseDecimalText`, `decimalFromPrim?`, and their helpers
  (`evalPow10`, `evalDigitValue?`, `parseEvalDigits`/`…WithCount`,
  `parseDecimalMantissa`, `parseDecimalExponent`, `applyDecimalExponent`,
  `applyDecimalSign`, `parseUnsignedDecimalText`).
- **Arithmetic:** `addDecimalValues`, `subDecimalValues`, `scaleDecimalNumerator`,
  `maxNat`.
- **Comparison:** `decimalCompareNumerators`, `decimalEqValues`, `decimalLtValues`.
- **Formatting:** `formatFiniteDecimal` and helpers (`trimDecimalZerosWith`,
  `decimalIntAbsNat`, `repeatZeros`, `leftPadZeros`).
- **Prim adapters:** `evalDecimalBinary?`, `evalDecimalCompare?`.

`Eval` keeps everything from `evalAdd` onward (the `Value`-level operators that consume
these); it now `import Kue.Decimal` and references the lifted symbols unchanged. Names
were kept stable — no rename churn.

### Layering

`Kue/Decimal.lean` imports only `Kue.Value`, so the new edge is `Value → Decimal`. This
is the lowest clean home: it has no dependency on `Eval`, `Builtin`, `Lattice`, or
`Normalize`, and both `Eval` and `Builtin` may import it without a cycle. Chosen over
folding into `Lattice` because the decimal machinery is an independent concern (numeric
representation/formatting), not lattice algebra — keeping it its own module honors the
illegal-states-unrepresentable / single-responsibility bias and keeps the import DAG
read as a clean layering rather than a grab-bag.

`Builtin` is **not** yet wired to import `Decimal` — that belongs to the slices that
actually consume it (no dead import). The unblock is purely that the DAG now permits it.

### Now unblocked

- **`list.Avg`** — exact-rational mean via `addDecimalValues` + `formatFiniteDecimal`
  (int-collapse when count divides sum, else apd-style float).
- **Float-domain `list.Sum` / `list.Min` / `list.Max`** — `addDecimalValues` and
  `decimalLtValues` are now importable from `Builtin`.
- **Float `list.Range`** — decimal stepping via the lifted arithmetic.
- **`math` family floats** — `Sqrt`, `Pow`, `Floor`/`Ceil`/`Round` (float-valued), etc.
  can format through `formatFiniteDecimal` instead of being stuck integer-only.

### Tests

No new fixture or theorem — a behavior-preserving refactor's safety net is that the
existing suite stays green with no `.expected` edits. It did.

### Verify

```sh
lake build
scripts/check-fixtures.sh
shellcheck scripts/check-fixtures.sh
```

`lake build` 68 jobs, `fixture pairs ok`, shellcheck clean. No `.expected` changed
(git status: only `Kue/Eval.lean` modified, `Kue/Decimal.lean` added).

---

## Completed Slice: Post-audit builtin hardening

Goal: close three findings from the periodic `/ace-audit` of `b92035b..8af9e2f` before
the `math` family lands. The first finding gates `math` directly — without it, the new
dispatcher would clone a duplicated helper triplet a third time.

### Finding 1 — DRY the builtin-dispatch fallback

`containsAnyBottom`, `argsFullyEvaluated`, and `isConcreteArg` were byte-identical
`where` helpers under both `evalListBuiltin` and `evalStringsBuiltin`. Extracted one
shared `isConcreteArg : Value → Bool` and one named `unresolvedOrBottom (name) (args)`
at module scope (above all dispatchers), capturing the rule once: a call matching no
known arm is bottom when any arg is bottom or all args are concrete (a real CUE type
error), else it stays unresolved as `.builtinCall name args`. Both dispatchers now call
`unresolvedOrBottom name args`; the `math` dispatcher will reuse the same helper rather
than re-duplicate. Behavior-preserving — extraction of identical logic, fixtures green,
no `.expected` edits.

### Finding 2 — Totalize the two `partial def`s

- `stringReplace` (was a fuel-free `while`/index-advance `Id.run` loop) now delegates to
  a structurally-recursive `stringReplaceLoop (fuel) (acc rest old new) (remaining)`.
  Fuel = source UTF-8 byte size, a sound upper bound: each replacement consumes ≥ 1 byte
  of `rest`, so the loop cannot outrun it. `remaining < 0` keeps the "replace all"
  semantics (no count cap); `remaining > 0` decrements. `partial` dropped.
- `listFlattenN` (was `partial`, recursing on `depth - 1` with negative depth = flatten
  fully) now routes through `listFlattenFuel (fuel : Nat) (items)`, which decrements one
  level per descent and is structurally terminating. The full-flatten path derives its
  fuel from a new `listNestingDepth : List Value → Nat` (the max `.list` nesting), a
  structural ceiling that guarantees complete flattening. `partial` dropped.

Both consistent with the `evalFuel`/`resolveFuel` fuel-bounded idiom used elsewhere.
Behavior-preserving — the existing `list.FlattenN` / `strings.Replace` fixtures and
theorems pass unchanged, no `.expected` edits.

### Finding 3 — Pin the deferred-boundary + edge tests

- `EvalTests.lean`: `eval_mul_two_floats_is_bottom_deferred` and
  `eval_div_two_floats_is_bottom_deferred` assert that float×float / float÷float
  currently collapse to `.bottom` (decimal arithmetic not yet wired into `evalMul` /
  `evalDiv`). Pinning makes the eventual transition to real float arithmetic a visible,
  test-breaking change instead of a silent one.
- `comprehension_loopvar_shadow.{cue,expected}` + `FixturePorts.lean` entry: a
  `for v in [10, 20]` body emits `"k\(v)": v` while a sibling `keep: v` sits outside the
  loop. Oracle-checked against `cue` v0.16.1: inside the loop `v` binds the loop var
  (10/20); `keep` resolves the sibling/outer `v` (`"sibling"`). Exercises the riskiest
  new machinery — the `(depth, index)` lexical scope chain — for shadowing correctness.
- `BuiltinTests.lean`: `strings_replace_zero_count_is_unchanged` (count == 0 returns the
  input verbatim) and `list_slice_negative_low_is_bottom` (negative low bound is a CUE
  error ⇒ bottom).

### Verify

```sh
lake build
scripts/check-fixtures.sh
shellcheck scripts/check-fixtures.sh
```

`lake build` 68 jobs, `fixture pairs ok`, shellcheck clean. No existing `.expected`
changed (the only new `.expected` is the `comprehension_loopvar_shadow` fixture);
findings 1 and 2 are behavior-preserving. Commit `1edc760`.

## Completed Slice: Math Builtin Family (rational-exact subset)

Goal: add the `math.*` builtin family, mirroring the `strings`/`list` dispatcher shape,
for every function whose result is rational-exact under Kue's existing `DecimalValue`
machinery. Functions whose results are irrational (need apd sig-digit context) or model
`NaN` are scoped to a documented follow-up rather than encoded with a guessed value.

### What landed

`Kue/Builtin.lean` now `import Kue.Decimal` (legal — `Builtin` may import `Decimal`, only
not `Eval`) and adds:

- `mathAbs : Prim → Value` — **domain-preserving** absolute value: `int → int`,
  `float → float`. Oracle-confirmed: `cue`'s `math.Abs(-5) = 5` stays int (unifies with
  `int`), `math.Abs(-3.5) = 3.5` stays float (does not unify with `int`). The float arm
  parses to `DecimalValue`, negates the numerator's sign, and re-formats via
  `formatFiniteDecimal _ true`.
- `mathMultipleOf (value divisor : Int) : Value` — `value % divisor == 0` as a bool; a
  zero divisor is `.bottomWith [.divisionByZero]`, mirroring `cue`'s
  "division by zero" error on `math.MultipleOf(_, 0)`.
- A `RoundMode` sum type (`floor`/`ceil`/`round`/`trunc`) + `roundDecimalToInt` +
  `mathRound : RoundMode → Prim → Value`. `Floor`/`Ceil`/`Round`/`Trunc` take a number
  and **return an int** (oracle-confirmed: all four unify with `int`; e.g.
  `math.Floor(3.7) = 3`, no `.0`). An int input is identity. A float is parsed to an
  exact decimal and reduced over `divisor = 10^scale`: floor = `Int.fdiv`, ceil =
  `-(Int.fdiv (-num) div)`, trunc = `Int.tdiv`, round = half-away-from-zero
  (`(|num| + div/2) / div`, sign reapplied; `div` is even for any `scale ≥ 1`, so
  `div/2` is exact). Oracle-confirmed `Round(2.5)=3`, `Round(-2.5)=-3`, `Round(0.5)=1`.
- `evalMathBuiltin : String → List Value → Value` with catch-all
  `| name, args => unresolvedOrBottom name args` (reuses the shared fallback from the
  post-audit hardening slice — no duplicated triplet), plus a `name.startsWith "math."`
  route in `evalBuiltinCall`.

### Deferred (documented, not encoded)

- `math.Sqrt` / `math.Pow`: irrational results need apd's sig-digit rounding context, and
  the two functions use *different* precisions in `cue` — `Sqrt(2) = 1.4142135623730951`
  (~17 digits) vs `Pow(2, 0.5) = 1.414…209698` (34 digits). `Sqrt(-1)` returns `NaN.0`
  rather than erroring, so `Sqrt` also needs a `NaN` value Kue does not model. Both need
  apd-context formatting before they can match the oracle exactly.
- The trig/log/`Exp` and constant (`Pi`, `E`) families: same apd-context requirement.

### Tests

- Fixture `math_builtin.{cue,expected}` (23 fields) + a hand-built `FixturePorts.lean`
  entry, oracle-checked against `cue` v0.16.1 (`cue fmt` clean, `cue export` matches Kue
  on every field). Covers int/float Abs, zero, `MultipleOf` true/false/negative-value/
  negative-divisor, and the four rounding modes on positive/negative/exact/integer inputs.
- 14 `native_decide` theorems in `BuiltinTests.lean`: domain preservation (int↔int,
  float↔float), `MultipleOf` truth + zero-divisor bottom, floor-toward-−∞,
  ceil-toward-+∞, round-half-away-from-zero (both signs), trunc-toward-zero,
  floor-of-int identity, string-arg type-mismatch ⇒ bottom, and abstract-arg ⇒ unresolved
  `.builtinCall`.

### Verify

```sh
lake build
scripts/check-fixtures.sh
shellcheck scripts/check-fixtures.sh
```

`lake build` 68 jobs, `fixture pairs ok`, shellcheck clean. No existing `.expected`
changed (only the new `math_builtin` pair). No CUE divergence logged — Kue matches the
oracle exactly on all 23 fields; the `Sqrt(-1)=NaN.0` non-erroring behavior is noted as a
deferral rationale, not a Kue-is-more-correct divergence (Kue does not yet evaluate it).

---

## Completed Slice: Float Multiplication and Division (decimal-lift wiring)

Flips the long-standing float-mul/div deferral: `evalMul` and `evalDiv` in `Kue/Eval.lean`
now route float and mixed int/float operands through exact-decimal helpers in
`Kue/Decimal.lean` rather than collapsing to `.bottom`. This was the alpha-gating gap —
basic float arithmetic a tester hits immediately.

### Behavior (all oracle-confirmed against cue v0.16.1)

- **Multiplication.** `int × int` stays `int`. Any float operand (incl. mixed `int×float`
  / `float×int`) promotes to float and is evaluated exactly: numerators multiply, scales
  add, and the summed scale is preserved **verbatim with no trailing-zero trim** —
  `1.0 * 1.0 = 1.00`, `1.5 * 2.0 = 3.00`, `0.1 * 0.2 = 0.02`, `-1.5 * 2.0 = -3.00`. New
  `mulDecimalValues` + `evalDecimalMultiply?` (uses `formatDecimalAtScale`, the no-trim
  renderer split out of `formatFiniteDecimal`).
- **Division.** `/` **always yields a float**, never an int (`4.0 / 2.0 = 2.0`,
  `6 / 2 = 3.0`); integer division remains the separate `div`/`quo` keywords. All four
  operand domains share one divider, `divideDecimalRational?`: it reduces the two decimals
  to a single rational `num/den` and renders. Terminating quotients render exactly
  (`1.0 / 4.0 = 0.25`); non-terminating quotients render at **34 significant digits** (apd
  context) with **round-half-up** on the guard digit (`2.0 / 3.0 = 0.666…667`,
  `100.0 / 7.0 = 14.28…29`). Round-half-up vs apd's nominal `ROUND_HALF_EVEN` is
  unobservable: a rational repeating expansion never yields an exact tie.
- **Division by zero** (any zero divisor, int or float) ⇒ `.bottomWith [.divisionByZero]`.

### Latent bug fixed at the source

The prior int-only `formatIntegerDivision` (with its `decimalPrecision`,
`decimalFractionDigits`, `joinStrings`, `rationalIsNegative`, `intAbsNat` helpers) emitted
a fixed 34 **fractional** digits, which is correct only for quotients < 1. For `10/3` it
produced 34 threes where cue gives 33 (34 *significant*), and it never rounded the last
digit. Rather than wire float-div alongside a buggy int-div, the int÷int path was migrated
onto the new shared significant-digit divider and the old helpers removed. The existing
`1/3` fixture (`< 1`, so 34 sig == 34 frac) is unaffected.

### Tests

- Two deferral pins flipped to positive assertions: `eval_mul_two_floats` (= `3.00`) and
  `eval_div_two_floats` (= `1.5`).
- 16 further `native_decide`/`rfl` theorems in `EvalTests.lean`: scale preservation,
  int×float / float×int promotion, negative mul, int×int stays int, terminating div,
  clean-div-is-float, float÷int / int÷float promotion, negative div, float-by-zero ⇒
  divisionByZero, int÷int routes through the new divider, and three repeating-division
  cases pinning the significant-digit rule and rounding (`2/3`, `10/3`, `100/7`).
- Fixture `float_muldiv_expressions.{cue,expected}` (10 fields) + a `FixturePorts.lean`
  entry; oracle-checked against cue v0.16.1 — Kue matches on every field.

### Deferred

None for mul/div. The full operand matrix and the 34-sig-digit repeating case land here;
there is no remaining division subset to defer.

### Verify

```sh
lake build
scripts/check-fixtures.sh
shellcheck scripts/check-fixtures.sh
```

`lake build` 68 jobs, `fixture pairs ok`, shellcheck clean. No existing `.expected`
changed (only the new `float_muldiv_expressions` pair). No CUE divergence logged — the
int-div correction is Kue fixing its own bug, not Kue diverging from a correct cue.

## Completed Slice: Float-Domain `list` Builtins

Goal: extend the integer-only `list.Sum`/`Min`/`Max`/`Range` arms to the float/decimal
domain and add `list.Avg`. Unblocked by the decimal-lift refactor and the float-mul/div
slice (`Kue/Decimal.lean` now carries add/sub/mul/div/compare/format).

### Semantics — CUE's integral-collapse rule

Oracle-checking against `cue` v0.16.1 surfaced the governing rule: CUE's numeric `list`
builtins **collapse an integral result back to `int`-kind**, unlike literal float
arithmetic which preserves the operand scale. Confirmed via `(expr & int) != _|_`:

- `list.Sum([1.0,2.0,3.0])` ⇒ `6` (int), `list.Sum([1,2.0,3])` ⇒ `6` (int),
  `list.Sum([1,2.5,3])` ⇒ `6.5` (float). Empty ⇒ `0`.
- `list.Min([3.0,1.0,2.0])` ⇒ `1` (int), `list.Min([3,1.5,2])` ⇒ `1.5` (float).
  `Max` symmetric.
- `list.Avg([1,2,3])` ⇒ `2` (int, exact divide), `list.Avg([1,2])` ⇒ `1.5`,
  `list.Avg([1,1,2])` ⇒ `1.333…333` (34 sig digits, round-half-up).
- `list.Range(0.0,2.0,0.5)` ⇒ `[0, 0.5, 1, 1.5]` (end exclusive; integral elements
  collapse to int); negative step descends; zero step ⇒ error.
- Empty `Avg`/`Min`/`Max` and zero-step `Range` are CUE errors; Kue renders `_|_`,
  matching its existing builtin error model.

### Implementation

- `Kue/Decimal.lean`: `collapseDecimalToValue` (trim → int if scale 0, else float) and
  `avgDecimalValue?` (exact divide via `sum.numerator / (10^scale * count)`; integral ⇒
  int, else `divideDecimalRational?`).
- `Kue/Builtin.lean`: `listToDecimals` / `listAllInts` helpers; `listSum` (all-int fast
  path preserved, else decimal accumulate via `addDecimalValues`), `listMin`/`listMax`
  (compare via `decimalLtValues`, collapse the chosen element), `listAvg`,
  `listRangeDecimal` (scale operands to a common denominator, reuse the integer count
  formula, collapse each element). Dispatch: `list.Sum`/`Min`/`Max` route to the new
  functions, new `list.Avg` arm, new float `list.Range` arm after the int one. Catch-all
  unchanged (`unresolvedOrBottom`).

### Tests

16 `native_decide` theorems in `BuiltinTests.lean`: float Sum collapse, mixed-int/float
Sum promotion (frac and integral), float Min/Max collapse, mixed Min, Avg exact-divisible
/ terminating / non-terminating-34-sig / float-input, Avg empty ⇒ bottom, Avg non-numeric
⇒ bottom, Avg abstract-arg ⇒ unresolved, float Range collapse, negative-step descend,
zero-step ⇒ bottom. Fixture `list_builtin_float.{cue,expected}` (15 fields) + a
`FixturePorts.lean` entry; oracle-checked — Kue matches cue on every field.

### Deferred

`list.Sort`/`SortStable`/`SortStrings` (comparator-struct evaluation) — the only remaining
`list` work.

### Verify

`lake build` 68 jobs, `fixture pairs ok`, shellcheck clean. No CUE divergence logged
(Kue's integral-collapse matches cue exactly).

## Completed Slice: Post-Audit Hardening 2 — Totalize Decimal `partial def`s

Commit `d6c54a5`. Closes the float-numeric audit fix-slices (audit 2026-06-16): two new
`partial def`s in `Kue/Decimal.lean` plus two borderline cleanups and a doc fix.

### Totalization

- **`divisionDigits`** — the inner `.loop` recursed on `remainder` (modular, not
  structurally decreasing) under the `sigEmitted > divisionSigDigits` budget. Lifted to a
  fuel-bounded total `divisionDigitsLoop (den) : fuel rem sig saw acc → …`, fuel supplied
  by `divisionDigitsFuel den = divisionSigDigits + 1 + (toString den).toList.length`. Sound
  bound: the only non-emitting iterations are leading fractional zeros, bounded by the den
  digit count (each multiplies the remainder by 10, so within that many steps the first
  significant digit fires); significant emission is hard-capped at `divisionSigDigits + 1`.
  Hence the over-budget exit always fires before fuel exhausts — the `fuel = 0` arm
  (returns `terminated = false`) is unreachable on real inputs, making the total form
  behaviorally identical to the prior partial one.
- **`roundDigits`** — `partial` was gratuitous (no self-recursion). Dropped it; the inner
  `bump` is lifted to a structural `roundDigitsBump : List Nat → List Nat × Bool`. Plain
  `def` type-checks via structural recursion.
- No `partial def` remains in `Kue/Decimal.lean`.

### Borderline cleanups

- **`rangeCount (start limit step : Int) : Int`** extracted from the verbatim ascending/
  descending count formula duplicated in `listRange` and `listRangeDecimal`
  (`Kue/Builtin.lean`); both now call it (decimal passes scaled-to-common-denominator
  ints). Behavior-preserving.
- **`DecimalDivideResult`** (`nonNumeric | divByZero | ok String`) replaces
  `evalDecimalDivide?`'s `Option (Option String)`; the `evalDiv` callsite in `Kue/Eval.lean`
  reads the three arms directly. Illegal states unrepresentable.
- Doc fix: `docs/notes/2026-06-16-float-muldiv-landed.md` no longer mis-attributes `partial`
  to `divideDecimalRational?`.

### Tests

All pre-existing division/avg `native_decide` theorems pass **unchanged** under the
totalized defs (the fuel/`Nat.rec` form still reduces under `native_decide`, confirming the
bound does not diverge). Added two high-fuel pins in `EvalTests.lean`:
`eval_div_repeating_full_sig` (`1.0/7.0` — full 34 sig digits, no leading zeros) and
`eval_div_repeating_leading_zeros` (`1.0/700.0` — 2 leading zeros, leaning on the
`+ <den digit count>` slack). Both oracle-checked against cue v0.16.1.

### Verify

`lake build` 68 jobs, `scripts/check-fixtures.sh` ⇒ `fixture pairs ok`, `shellcheck` clean.
No CUE divergence logged (pure refactor — no semantic change).

## Completed Slice: `list.SortStrings`

The comparator-free string sort — the last `list` function that needs no
comparator-struct evaluation. `Sort`/`SortStable` (which evaluate a `list.Ascending`-style
comparator struct) stay deferred.

### Semantics — oracle-driven (cue v0.16.1)

Ordering rule confirmed against `cue`: **byte-lexicographic** (Go's `sort.Strings`, i.e.
`<` on the raw UTF-8 bytes). For valid UTF-8 this coincides with Unicode codepoint order,
so capitals sort before lowercase (`"A"` 0x41 < `"a"` 0x61) and multibyte runes sort after
all ASCII (`"é"` 0xC3… > `"z"` 0x7A). Probed cases, all matching cue:

- `["banana","apple","cherry"] → ["apple","banana","cherry"]`
- duplicates kept: `["b","a","b","a"] → ["a","a","b","b"]`
- empty `[] → []`, single `["x"] → ["x"]`, already-sorted and reverse
- caps: `["b","A","a","B"] → ["A","B","a","b"]`
- multibyte: `["é","a","z","Z"] → ["Z","a","z","é"]`
- non-string element (`["a",1,"b"]`) ⇒ cue errors `invalid list element` ⇒ Kue bottom
- non-list arg (`"abc"`) ⇒ cue errors `cannot use … as list` ⇒ Kue bottom

### Implementation (`Kue/Builtin.lean`)

- `byteSeqLe : List UInt8 → List UInt8 → Bool` — total, structural lexicographic `≤` on
  UTF-8 byte sequences.
- `listSortStrings (items) : Value` — collects elements as strings (any non-string ⇒
  `none` ⇒ bottom), then `List.mergeSort` with `fun a b => byteSeqLe a.toUTF8.toList
  b.toUTF8.toList`. `List.mergeSort` is total (no `partial`) and stable, so equal strings
  keep input order (unobservable, since equal strings are identical).
- Dispatch arm `| "list.SortStrings", [.list items] => listSortStrings items` added to
  `evalListBuiltin`; the catch-all `unresolvedOrBottom` fallback is unchanged, so a
  non-list arg / abstract arg flows through it (bottom vs. preserved `.builtinCall`).

### Tests

11 `native_decide` theorems in `BuiltinTests.lean`: ascending, duplicates, empty,
singleton, already-sorted, reverse, caps-before-lowercase byte order, multibyte-after-ASCII,
non-string-element ⇒ bottom, abstract-arg ⇒ unresolved. New fixture
`testdata/cue/list_sort_strings.{cue,expected}` + a `FixturePorts.lean` entry covering the
eight clean (non-error) cases; the error cases are theorem-only (the CLI fixture path
diffs concrete output, and bottom rendering is already exercised elsewhere).

### Deferred

`list.Sort` / `list.SortStable` — both take a comparator struct (`{x:_, y:_, less: x<y}`,
e.g. `list.Ascending`) that must be evaluated per comparison; needs struct-evaluation
plumbing the builtin layer does not yet have. This was the only remaining `list` work.

### Verify

`lake build` 68 jobs, `scripts/check-fixtures.sh` ⇒ `fixture pairs ok`, `shellcheck` clean.
No CUE divergence logged (cue and Kue agree on every probed case).

## Completed Slice: `strings.ToUpper`/`ToLower`/`ToTitle` (ASCII)

The case-folding triple, landed for the **ASCII** subset with an explicit, documented
non-ASCII deferral. Pure `String → String` maps over the existing `strings.*` dispatch — no
new `Value` variants, no struct evaluation.

### Semantics — oracle-driven (cue v0.16.1)

- **`ToUpper`/`ToLower`:** ASCII letter case mapping. Digits and punctuation unchanged;
  empty string unchanged.
- **`ToTitle` is per-word capitalization, NOT "upper-case every letter".** This contradicts
  the common assumption that cue's `ToTitle` matches Go's `strings.ToTitle` (which does
  upper-case all letters). cue's `strings.ToTitle` upper-cases only the **first character of
  each whitespace-delimited word**, leaving the rest untouched. Probed exhaustively, all
  matching cue:
  - `ToTitle("hello world foo") → "Hello World Foo"`
  - `ToTitle("HELLO WORLD") → "HELLO WORLD"` (word-initial already upper; rest not lowered)
  - word separator is **whitespace ONLY**: `ToTitle("a-b a.b a_b a/b") → "A-b A.b A_b A/b"`
    (`-`, `.`, `_`, `/` do NOT start a word)
  - digit is not a separator: `ToTitle("3 abc a3bc") → "3 Abc A3bc"`
  - leading whitespace preserved: `ToTitle("  leading") → "  Leading"`
- **Non-ASCII deferral = passthrough.** Non-ASCII runes are emitted unchanged (Lean's
  `Char.toUpper`/`toLower` are ASCII-only). Chosen over bottoming for consistency with the
  other byte-faithful `strings.*` builtins and to stay total + ASCII-exact. Divergences (all
  non-ASCII): `ToUpper("café")` → Kue `"CAFé"` / cue `"CAFÉ"`; `ToLower("CAFÉ")` → Kue
  `"cafÉ"` / cue `"café"`; `ToTitle("über alles")` → Kue `"über Alles"` / cue `"Über Alles"`.
  Documented in `docs/spec/compat-assumptions.md` → "String case folding". **Not** logged in
  `cue-divergences.md` — cue is correct here; Kue is deliberately limited (that file is for
  cue defects).

### Implementation (`Kue/Builtin.lean`)

- `asciiToUpper`/`asciiToLower (value) : String` — `String.ofList (value.toList.map
  Char.toUpper/toLower)`.
- `asciiTitleSeparator (c) : Bool` — true for the six ASCII whitespace runes
  (`\t \n \v \f \r` and space); false otherwise, including all non-ASCII (so non-ASCII
  whitespace such as NBSP does not start a word — the deferral boundary). Spelled
  explicitly because Lean's `Char.isWhitespace` misses `\v`/`\f`.
- `asciiToTitle (value) : String` — single left-to-right pass; title-case a rune iff the
  previous rune was a separator (first rune counts as word-start).
- Three arms in `evalStringsBuiltin` (`strings.ToUpper`/`ToLower`/`ToTitle`, each
  `[.prim (.string s)]`); catch-all `unresolvedOrBottom` unchanged, so non-string / abstract
  args flow through it.

### Tests

19 `native_decide` theorems in `BuiltinTests.lean`: ToUpper/ToLower each over
lowercase/uppercase/empty/digits+punct; ToTitle per-word capitalization, leaves-upper-as-is,
empty, whitespace-only-separators, digit-not-separator, leading-whitespace; three non-ASCII
passthrough boundary theorems (ToUpper/ToLower/ToTitle); abstract-arg ⇒ unresolved;
non-string ⇒ bottom. New fixture `testdata/cue/strings_case.{cue,expected}` (14 ASCII cases)
+ a `FixturePorts.lean` entry. Non-ASCII cases are theorem-only (fixtures stay in the
supported ASCII domain).

### Deferred

Full Unicode case folding (Go `unicode.ToUpper`/`ToLower`/`ToTitle` + `x/text/cases`,
including ß / dotless ı / title-case digraphs) — needs a Unicode case-mapping table. An
alpha boundary alongside imports and `list.Sort`.

### Verify

`lake build` 68 jobs (all theorems pass), `scripts/check-fixtures.sh` ⇒ `fixture pairs ok`,
`shellcheck` clean. No CUE divergence logged (the non-ASCII gap is a documented deferral in
`compat-assumptions.md`, not a cue defect).

## Completed Slice: `strings.SplitN`

`strings.SplitN(s, sep, n)` — split `s` on `sep`, capped at `n` pieces. The cleanest of the
remaining `strings` functions; shares its splitting core with `strings.Split`.

### Crux — `n` semantics (oracle-confirmed, cue v0.16.1, matches Go)

Probed every case against `cue export … --out json` before encoding:

- `n == 0` ⇒ `[]` (empty list; JSON `[]`, kue `[]`).
- `n < 0` ⇒ all pieces, identical to `Split`.
- `n > 0` ⇒ at most `n` pieces; the first `n-1` are verbatim, the LAST is the unsplit
  remainder. `SplitN("a,b,c", ",", 2)` ⇒ `["a", "b,c"]`; `n == 1` ⇒ `[s]`.
- `n` larger than the piece count ⇒ all pieces, no padding.
- Empty `sep` ⇒ split into UTF-8 runes, then n-capped. `SplitN("abc", "", 2)` ⇒
  `["a", "bc"]` (the rejoin uses `sep == ""`, so the tail runes concatenate).
- Empty `s`, non-empty `sep` ⇒ `[""]`. Empty `s` and empty `sep` ⇒ `[]`.
- `sep` absent from `s` ⇒ `[s]`.

No deferral — empty-sep is cleanly supported; cue and Go agree on every probed case.

### Implementation (`Kue/Builtin.lean`)

- Factored the raw-string splitting core out of `stringSplit` into `stringSplitParts
  (value sep) : List String` (empty sep ⇒ per-rune; else `splitOn`). `stringSplit` now maps
  it to `Value`s — behavior identical to before.
- `stringSplitN (value sep) (n : Int) : List Value` — total, no recursion/fuel: `n == 0` ⇒
  `[]`; `n < 0` ⇒ `stringSplit`; `n > 0` ⇒ if `parts.length ≤ n` return all, else
  `parts.take (n-1) ++ [intercalate sep (parts.drop (n-1))]`. The rejoin reconstructs the
  remainder, including for empty sep.
- One arm in `evalStringsBuiltin` (`strings.SplitN`, `[.prim (.string s), .prim (.string
  sep), .prim (.int n)]`); catch-all `unresolvedOrBottom` unchanged, so non-string `s`/`sep`
  / non-int `n` (all-concrete) ⇒ bottom, abstract args ⇒ unresolved `.builtinCall`.

### Tests

11 `native_decide` theorems in `BuiltinTests.lean`: positive-remainder, `n==0`⇒`[]`,
`n<0`⇒all, count-exceeds-pieces, separator-absent, empty-string, empty-sep-capped,
empty-sep-unbounded, empty-both, type-mismatch (`n` as string)⇒bottom, abstract-arg
⇒unresolved. New fixture `testdata/cue/strings_splitn.{cue,expected}` (11 cases covering
every `n`-branch + empty-sep + empty-string) and a `FixturePorts.lean` entry.

### Verify

`lake build` 68 jobs (all theorems pass), `scripts/check-fixtures.sh` ⇒ `fixture pairs ok`,
`shellcheck` clean. No CUE divergence logged — cue is correct on all cases.

---

## Completed Slice: Source-position tracking + structured parse errors

Goal: make parse failures point at *where* they occurred. `ParseError` carried only a
`message` with no source location; this is the foundation for legible import/eval errors
later and the substantive remaining parser-completeness work after the form gap closed.

### `ParseError` shape (`Kue/Parse.lean`)

```
structure ParseError where
  message  : String
  remaining : Nat := 0   -- chars left in the suffix at the failure point
  line     : Nat := 0    -- 1-based, filled at the parseSource boundary
  column   : Nat := 0
deriving Repr, BEq, DecidableEq, Inhabited
```

### How position is threaded

The parser is recursive descent over `List Char` (no state monad), so position is
*how far into the suffix the parser got*. The lowest-churn total design:

- `parseError` gained a leading `chars : List Char` arg and records
  `remaining := chars.length`. Every throw site passes the most-local suffix
  representing where the parser is stuck (previously-discarded `| _ =>` arms were bound
  to `| rest =>` where the scrutinee was `skipTrivia …`; genuine EOF arms pass `[]` ⇒
  `remaining 0`). 48 sites in `Parse.lean` + 1 in `Runtime.lean` (`conflicting package
  names`, a non-cursor error, passes `[]` ⇒ reports `1:1`).
- A total `offsetToLineColumn (source : List Char) (offset : Nat) : Nat × Nat` walks the
  first `offset` chars (structural recursion with `offset` as decreasing fuel — no
  `partial`), `line+1`/`col:=1` on `'\n'`, else `col+1`. 1-based.
- `withPosition (source : List Char)` maps an error: `offset := source.length -
  remaining`, then stamps `(line, column)`. `parseSource` applies it, so BOTH
  `evalSourceToString` and the multi-file `parseSources` path (which call `parseSource`)
  get positioned errors.

### CLI print format (`Main.lean`)

`kue: parse error: <line>:<col>: <message>` (CUE-style `line:col`), e.g.
`kue: parse error: 2:4: unexpected character '@'`.

### Tests

7 new `native_decide` theorems in `ParseTests.lean` via a new `parseFailsAt source line
col` helper. Every asserted position empirically confirmed against the built binary:

- `@\n` → **1:1** (error on line 1, col 1)
- `name: 4 @ 5\n` → **1:9** (mid-line on line 1, col > 1)
- `foo: bar.@\n` → **1:10** (expected identifier after `.`)
- `a: 1\nb: @\n` → **2:4** (line increments past the newline)
- `x: {\n  a: 1\n  b: @\n}\n` → **3:6** (inside a multi-line struct)
- `a: 1\nb: 2\nx: [1, 2\n` → **4:1** (EOF, unclosed list, remaining 0)
- `a: "unterminated\n` → **2:1** (EOF, unterminated string)

`ParseError` BEq/DecidableEq derive over the new fields, but no existing test compares
whole `ParseError` values (all go through `parseOutputMatches`/`parseFails`, which inspect
the `.ok`/error tag only). Positive fixtures unchanged — no regressions.

### Note: separators stay permissive

The parser does not enforce field separators — `a: 1 b: 2\n` parses as two fields with no
newline/comma and no error — which is why the position tests use unambiguous failing
tokens (`@`, dangling `.`, unclosed `[`/`(`/`"`) rather than separator violations. This
confirms the standing permissive-separator assumption; strict CUE newline/semicolon
insertion remains unimplemented (next-step parser work, alongside non-field aliases).

### Verify

`lake build` 68 jobs (all theorems pass), `scripts/check-fixtures.sh` ⇒ `fixture pairs
ok`, `shellcheck scripts/check-fixtures.sh` clean. No CUE divergence logged.

## Completed Slice: B1 — Colon-Shorthand Nested Fields (`a: b: c: 1`)

Parser-only slice. CUE's most basic idiom `a: b: c: 1` is sugar for `a: {b: {c: 1}}`.
The prod9/infra gap analysis ranked this the #1 blocker (85/92 sampled real files failed
at the parser; `tests: namespace: [...]` → `parse error: unexpected character ':'`).

### Desugaring (recursion point)

`Kue/Parse.lean`, new `parseFieldValue` inside the parser's mutual block. After a field
label and its `:`, the value position is inspected by the pure lookahead
`valuePositionStartsField`: it skips one label token (`skipLabelToken?` — identifier/
definition, `"…"` quoted via `skipQuotedToken?`, or `(…)` dynamic via `skipBalancedParens`),
then an optional `?`/`!` class marker, and checks for a following `:`. On a hit,
`parseFieldValue` recurses into `parseField` and wraps the single resulting field via
`parsedFieldsValue [inner]` — the **same** builder the brace path (`parseStruct`) uses.
That is the brace-identity guarantee: `a: b: 1` constructs exactly what `a: {b: 1}`
constructs, so it unifies/closes/exports identically. On a miss, the value position falls
through to `parseExpression` unchanged (so `a: b` stays a reference, not a shorthand).

Routed through `parseFieldValue`: `parseLabeledField`, `parseAliasedField`,
`parseDynamicField`, `parseQuotedLabelField` — every `:`-introduced value position, so
shorthand chains through quoted and dynamic inner labels too (`a: "x/y": 1`, `a: ("k"): 1`).

### Label forms supported (oracle-checked vs `cue` v0.16.1)

Inner labels: plain identifiers, definitions (`#x: y: 1`), quoted strings (incl. dotted
`"prodigy9.co/app": "v"`), `(expr)` dynamic; each with optional `?`/`!` markers. Verified
identical export to the brace form for each. Definition/optional inner fields export empty
(hidden), required inner fields error as incomplete — all matching the brace equivalents.

### Tests

New fixture pair `colon_shorthand.{cue,expected}` + `FixturePorts.lean` entry. The port
builds the explicit-**brace** AST; the CLI port independently evaluates the **shorthand**
`.cue`. Both matching `.expected` pins the desugaring. Fixture exercises 2/3-level chains,
quoted dotted inner label, mixed shorthand+brace, and shorthand-sibling merge (`spec:`
twice).

13 new `native_decide` theorems in `ParseTests.lean`. KEY equality pins via new
`parseSameValue left right` (compares the two pre-resolution `Value` ASTs with `==`):
`a: b: 1` ≡ `a: {b: 1}`, 3-level, quoted-inner, mixed-with-brace, dynamic-inner — all
prove AST identity, not just equal output. Plus resolve-level pins (2/3-level, quoted,
sibling merge, alongside-sibling, prod9 `metadata: name:` snippet) and a regression pin
that `a: b` (no colon) stays an ordinary reference.

### Verify

`lake build` 68 jobs (all theorems pass), `scripts/check-fixtures.sh` ⇒ `fixture pairs
ok` (no regressions — brace forms still work), `shellcheck scripts/check-fixtures.sh`
clean. No CUE divergence logged (`cue` and Kue agree; `cue` even normalizes the brace
form back to shorthand on export).

---

## Completed Slice: B2 — Value/Field Aliases

Value-position aliases — `label: X=value`, especially the `#Def: Self={…}` self-reference
form (50/92 sampled real prod9/infra files; the `=` was a parser blocker:
`infra-defs/role.cue:7` `#Role: Self={` → `parse error: 7:12: unexpected character '='`).

### Parser

`parseFieldValue` (the single value-position chokepoint all field kinds route through)
first checks `valueAliasHead?`: a value alias is an identifier immediately followed by a
single `=`, NOT `==` (which is equality). The lookahead reuses `skipLabelToken?`, then
inspects the next non-trivia char — `'=' :: '=' :: _` ⇒ `none` (equality), `'=' :: rest`
⇒ the alias. On a hit, the aliased value is parsed (recursively, so colon-shorthand and
nested aliases compose) and lowered through `bindValueAlias name`.

`bindValueAlias` encodes CUE's value-alias scoping (oracle-confirmed vs `cue` v0.16.1: the
alias is visible only within its own value and its descendants — NOT to siblings or the
enclosing struct — and refers to the whole value). For a struct value it prepends a
non-output `(name, .letBinding, .thisStruct)` field; for a non-struct (scalar) value it is
inert (passthrough), since a scalar cannot reference its own alias and siblings cannot see
it.

### Resolver / eval

A new nullary `Value.thisStruct` marker is the binding target — illegal-states-
unrepresentable over re-inlining the struct (which would be an infinite term). It never
surfaces in output: it lives only as a `let`-binding value and is consumed during eval.
The resolver passes it through (catch-all); `Lattice.meet`, `Format`, and `Manifest` get
residual arms it never actually reaches in a final value.

`Self.field` is the load-bearing access. The eval `.selector (.refId id) label` arm calls
`thisStructFieldIndex?`: if `id` points at a `.thisStruct` binding, it finds `label`'s
index in that frame and rewrites the selection to `.refId ⟨id.depth, labelIndex⟩` — i.e.
`Self.field` evaluates exactly as an ordinary same-struct sibling reference to `field`.
This inherits the existing same-struct cycle guard for free, so self-reference cycles
bound to top rather than diverging. (The initial reconstruct-the-whole-struct encoding was
discarded — it re-evaluated every sibling per `Self.x`, blowing up exponentially across
multiple `Self` refs; the sibling-rewrite is O(1) per access.)

### Scope confirmed (oracle, `cue` v0.16.1)

- `#D: Self={x:1, y:Self.x}` then `#D & {x:5}`: `Self.x` resolves; cue gives `y:5`
  post-unification. Kue resolves the in-definition self-reference (`y:5` when `x` is
  concrete in the def) but, like every Kue reference, against the lexical frame not the
  post-unification merge — so `#D & {x:5}` leaves `y:int`. This is a pre-existing resolver
  boundary affecting plain sibling refs identically (`y: x` under unify), documented in
  compat-assumptions, not an alias-specific gap.
- Value alias visible within its value and all descendants (`inner: {q: Self.x}` resolves);
  NOT visible to siblings (`a: X=…; b: X` ⇒ `cue` "reference not found").
- Bare `Self` (whole-struct copy) is a structural-cycle error in `cue`; Kue emits the
  residual `@self`. Deferred — the real pattern is always `Self.field`.

### Tests

New fixture pair `value_aliases.{cue,expected}` + `FixturePorts.lean` entry (the port
builds the desugared `.thisStruct`-prepended AST; the CLI port parses/evaluates the alias
`.cue`; both match `.expected`). Fixture covers a `#Secret`-shaped `Self.#name` hidden
self-reference, a named non-`Self` alias referenced inside its value, and a `Self.port`
nested-via-colon-shorthand reference — all oracle-confirmed.

9 new `ParseTests.lean` theorems (self-reference, hidden self-reference, named alias,
deep-nested visibility, alias + colon-shorthand, bounded self-reference cycle, the
`a == b` equality regression asserted at Value level, and a malformed `X=` reporting
`2:1`). 2 new `EvalTests.lean` theorems pin the `.thisStruct` mechanism directly
(self-reference resolves; cycle bounds to top).

### Verify

`lake build` 68 jobs (all theorems pass), `scripts/check-fixtures.sh` ⇒ `fixture pairs
ok` (no regressions), `shellcheck scripts/check-fixtures.sh` clean. Cleared the `=` parse
barrier on real infra: `infra-defs/role.cue` now parses+evaluates (exit 0); 28/32
infra-defs files parse+evaluate (remaining 4 blocked on B4/B3). No CUE divergence logged —
the unreferenced-alias case is a Kue-permissiveness boundary (Kue does less), recorded in
compat-assumptions, not the divergence log.

## Completed Slice: B4 — Multiline Strings

Multiline string `"""…"""` and multiline bytes `'''…'''` literals — every form previously
evaluated to `_|_`. The bug was in **parse, not eval**: `parsePrimaryAtom` had no
triple-delimiter arm, so the lone `'"' :: rest` arm read the first two quotes as an empty
string `""` and mis-parsed the remainder. Infra uses these heavily for TLS certs/keys, RSA
app keys, dex config, and RBAC policy CSV (`apps/argocd.cue`, `apps/argo/stage9.cue`,
`infra-defs/secret.cue`).

### Dedent rule (oracle-confirmed, `cue` v0.16.1)

Content begins on the line after the opening delimiter; the closing delimiter sits on its
own line. The leading horizontal whitespace (spaces/tabs) preceding the closing delimiter
is the **strip prefix** removed from every content line. The newline immediately after the
opening delimiter and the one before the closing line are excluded; remaining lines join
with `\n`. Each non-blank content line must begin with the full strip prefix — a line with
some-but-insufficient leading whitespace is rejected (`cue`'s "invalid whitespace"); a
fully empty line (immediate newline) is exempt and contributes an empty line. Content on
the opening-delimiter line is rejected ("expected newline after multiline quote"). Tab
prefixes and zero-indent closing delimiters both work. Backslash escapes and `\(expr)`
interpolation apply inside `"""…"""` exactly as in single-line strings.

### Parser

Two total helpers below the mutual block: `multilineStripPrefixGo`/`multilineStripPrefix?`
(a structural single-pass scan tracking line-start + accumulated leading whitespace; finds
the closing line's indentation, total by structural recursion on the char list, no
`partial` and no `decreasing_by`), `splitLeadingHorizontalWhitespace`, and
`multilineDelimiter?`. New `parsePrimaryAtom` arms `'"' :: '"' :: '"' :: rest` and
`'\'' :: '\'' :: '\'' :: rest` (placed before the single-quote arms) route to
`parseMultilineOpen quote`, which finds the strip prefix, requires a newline after the
opening delimiter, then runs `parseMultilineBody quote strip atLineStart chars acc parts`.
The body parser: at a line start, drops the strip prefix and checks for the closing
delimiter (finish — trimming the trailing pre-closing `\n`), else (no prefix match) a bare
`\n` is an allowed blank line and anything else is "invalid whitespace"; mid-line it reuses
the same `\(expr)` interpolation and `\`-escape handling as `parseInterpolatedString`,
emitting `\n` at each line break. `parseMultilineString` wraps the result as-is;
`parseMultilineBytes` rewraps a `.prim (.string …)` into `.prim (.bytes …)` and **rejects**
an interpolated body (`'''…\(x)…'''`) — bytes interpolation is deferred (Kue's bytes value
is a plain string payload; the interpolation machinery yields a string, not bytes).

### Tests

6 new fixture pairs (`multiline_string`, `multiline_dedent`, `multiline_interpolation`,
`multiline_empty`, `multiline_cert`, `multiline_bytes`) with `FixturePorts.lean` entries —
each port hand-builds the expected dedented value, so the port-derived `.expected` and the
CLI's actual parse output are independent encodings diffed against the same file (a wrong
dedent would diverge them). 11 new `ParseTests.lean` theorems via `parseSameValue`
(multiline form parses to the same AST as the equivalent single-line literal) for
basic/indented-dedent/empty/no-indent/blank-line/escape/interpolation/bytes, plus `parseFails`
for the under-indented line and deferred bytes interpolation, and `parseFailsAt 1 7` for
content-on-opening-line.

### Verify

`lake build` 68 jobs (all theorems pass), `scripts/check-fixtures.sh` ⇒ `fixture pairs ok`
(no regressions), `shellcheck scripts/check-fixtures.sh` clean. No CUE divergence logged —
all observed `cue` behavior was correct; the bytes-interpolation deferral is a Kue-does-less
boundary in compat-assumptions, not a `cue` bug. Real-infra impact: the `"""` parser barrier
cleared on all four multiline-using prod9 files; `infra/apps/argocd.cue` now
parses+evaluates to exit 0 (the other three — `argo/bluepages.cue`, `argo/stage9.cue`,
`infra-defs/secret.cue` — now fail at separate, later parser gaps: open-list `[...]`
expressions and non-string label patterns `[string]: string`, not the multiline form).

---

## Completed Slice: B6 — Encoding Builtins (`base64.Encode`, `json.Marshal`)

Goal: implement the two `encoding` builtins the prod9/infra gap analysis found
load-bearing inside `#Secret`/`#ConfigMap` (the docker-config
`base64.Encode(null, json.Marshal({auths: …}))` chain). Both previously returned
unevaluated / bottom.

### What landed

- **New `Kue/Json.lean` — reusable, total JSON serializer.** `manifestToJson :
  ManifestValue → String` (mutual structural recursion over fields/items, no `partial`)
  emits compact JSON byte-for-byte matching `cue` v0.16.1: `,`/`:` separators with no
  spaces, **object keys in source/insertion order (NOT sorted)**, floats rendered from
  their exact stored decimal text verbatim (`1.0`→`"1.0"`, `1.50`→`"1.50"`), a bytes
  value as a base64 JSON string (Go `[]byte`), control chars `<0x20` as `\b\f\n\r\t` or
  `\uXXXX`, and `<>&/` plus non-ASCII passed through (cue disables Go's HTML escaping).
  `valueToJson : Value → Except ManifestError String` manifests first, then serializes.
  Factored as a standalone module (imports `Manifest`; `Builtin` imports it) so **B5
  reuses `manifestToJson` verbatim for `--out json`**. Also houses the standard padded
  base64 encoder `base64Encode : List UInt8 → String` (RFC 4648 alphabet + `=` padding,
  via `Id.run` array loop).
- **`Kue/Builtin.lean` dispatch.** Two new package dispatchers following the established
  pattern: `evalBase64Builtin` (`base64.Encode` with a `null` encoding selector over a
  string/bytes payload's UTF-8 bytes; non-null selector → bottom via the shared
  `unresolvedOrBottom`) and `evalJsonBuiltin` (`json.Marshal` → `valueToJson`; `.ok` →
  the JSON string, `.error` → bottom unless the arg is a still-pending reference form, in
  which case the call is preserved). Both routed from `evalBuiltinCall` by `base64.` /
  `json.` name prefix, each ending in the single shared `unresolvedOrBottom` fallback. A
  new `isPendingArg` predicate distinguishes a genuinely-incomplete concrete shape
  (`{a: int}` → bottom) from an unresolved `.ref`/`.selector`/`.index`/`.builtinCall`
  (preserved for a later pass).
- **Oracle-confirmed semantics (`cue` v0.16.1):** `base64.Encode(null, …)` = standard
  padded base64; non-null selector errors ("unsupported encoding"). `json.Marshal` keys
  preserve source order; output is compact; floats keep their exact spelling; bytes →
  base64 string; HTML chars are NOT escaped; incomplete value errors.

### Tests

- 3 fixture pairs + `FixturePorts.lean` AST ports (each AST port and the independent CLI
  evaluation of the `.cue` both diff-match the same `.expected`):
  `base64_encode` (ASCII/empty/multibyte, 0/1/2-byte padding, over-bytes, non-null →
  bottom), `json_marshal` (scalar/int/negInt/float/whole-float/bool/null, nested
  key-order, list, empty struct+list, escapes, incomplete → bottom), and
  `encoding_infra_chain` (the docker-config `base64.Encode(null, json.Marshal({auths:
  registry}))` shape, oracle-matched).
- 17 `BuiltinTests.lean` `native_decide` theorems pinning every base64 padding case,
  non-null → bottom, abstract-arg preservation, all json scalar/compound/escape cases,
  source-order keys, incomplete → bottom, and abstract-arg preservation.

### Boundaries (compat-assumptions)

- `base64.Encode` non-null encodings and `base64.Decode` deferred; `json.MarshalStream`
  / `Indent` / `Unmarshal` / `Validate` deferred.
- The infra chain evaluates byte-for-byte against `cue` when the inner fields resolve.
  The real `infra-defs/secret.cue` references a **hidden** field (`_auths`);
  hidden-field references do not yet resolve in Kue (pre-existing reference-resolution
  gap, separate from B6), and `secret.cue` is additionally blocked at the non-string
  label-pattern parser gap — the encoding builtins are not the blocker.

Verify gate green: `lake build` (70 jobs), `scripts/check-fixtures.sh` ⇒ `fixture pairs
ok`, `shellcheck` clean.

---

## Completed Slice: B5 — Manifest Output (YAML/JSON serializer + `cue export` CLI mode)

Goal: the first time Kue can EMIT a real manifest — `kue export` as the `cue export`
equivalent (prod9's pipeline is `cue export` → `k8s/*.yaml` → `kubectl apply`). A YAML
serializer over `ManifestValue`, a pretty-JSON path reusing B6's `Kue/Json.lean`, an
additive `export` CLI mode, and a `yaml.Marshal` builtin.

### Milestone proof

On a self-contained k8s-Deployment `.cue`, `kue export --out yaml` and `kue export
--out json` are **byte-identical to `cue export`** (oracle: `cue` v0.16.1). First true
end-to-end manifest.

### What landed

- **`Kue/Yaml.lean`** — total `manifestToYaml : ManifestValue → String` (mutual structural
  recursion, no `partial`) matching `cue`'s go-yaml v3 emitter on the infra core, plus
  `valueToYaml` (manifest-then-serialize, trailing newline). Block layout: 2-space nesting
  (`yamlValue` recurses children at `indent+2`); `- ` sequences where a compound item's
  first line rides the introducer (`yamlItemBody` renders the block at `indent+2` and drops
  that many leading-space chars), nested lists → `- - 1`; `|-` block scalars for strings
  with `\n` (chomped, lines indented under the key); empty `{}`/`[]` inline.
- **Scalar quoting** (`yamlScalarString`), oracle-pinned to cue's exact decision:
  double-quote (reusing JSON's `jsonString` escaper) when resolver-ambiguous — the YAML
  1.1 bool/null tokens `y n t f yes no on off true false null ~` (case-insensitive, via
  `yamlReservedWords`) or numeric-looking (`yamlLooksNumeric`: decimal int/float with
  `_`/sign/exponent, `0b`/`0o`/`0x`, `.inf`/`.nan`); single-quote (`yamlSingleQuoted`,
  doubling interior `'`) when structurally unsafe but not ambiguous (`yamlNeedsSingleQuote`:
  leading indicator char, leading `-`/`?`/`:` + space, `: `/` #` anywhere, trailing `:`,
  leading/trailing/all space); else bare. Keys use the same rule (`yamlKey`), so a `f`/`n`
  key is quoted.
- **`Kue/Json.lean`** — added `manifestToJsonPretty` (4-space indent, source-order keys,
  `": "`) + `valueToJsonPretty` (trailing newline), the `cue export` default. Distinct from
  the compact `manifestToJson` (`json.Marshal`).
- **`Kue/Builtin.lean`** — `evalYamlBuiltin` routed by the `yaml.` name prefix, reusing the
  shared `unresolvedOrBottom` / `isPendingArg` (no duplicated fallback). `yaml.Marshal`
  manifests then emits the YAML doc with a trailing newline; incomplete → bottom,
  unresolved-ref form preserved.
- **`Kue/Runtime.lean`** — `ExportFormat` (`json`/`yaml`), `formatManifestError`, and
  `exportSourcesToString : ExportFormat → List String → Except ParseError (Except String
  String)` (parse error outer, manifest-error message inner).
- **`Main.lean`** — additive `export` subcommand: `parseExportArgs` (default `--out json`,
  optional file arg else stdin, rejects unknown flags) + `runExport` (exit 0 ok / 1
  parse-or-export-error / 2 bad-flag). **The no-flag path is unchanged** — `kue < file` /
  `kue file…` still print the internal `formatValue`, so `check-fixtures.sh`'s
  internal-format CLI check does not regress.

### Oracle-confirmed semantics (`cue` v0.16.1)

- `cue export` default `--out` is **json**, pretty (4-space). `--out yaml` is go-yaml v3.
- **No `---` multi-doc**: a top-level list exports as a single YAML sequence; `---`
  framing comes only from `yaml.MarshalStream` (deferred). The plan's `---`-for-lists
  hypothesis was wrong; the oracle corrected it (cue-correct, not a divergence).
- `yaml.Marshal` and `cue export --out yaml` both emit a trailing newline.
- Scalar quoting matrix as encoded above (verified across ~40 string cases).

### Tests

- **`Kue/YamlTests.lean`** — 33 `native_decide` theorems on the serializers: scalars
  (int/float/bool/null), all three quoting branches (bare/single/double) incl. the
  bare-but-risky cases (`-x`, `comma,`), empty `{}`/`[]`, nested map (with quoted `f`
  key), list of scalars, list-of-maps multi (`- … - …`), nested list (`- - 1`), `|-`
  block scalar, bytes→base64, the full k8s Deployment (byte-for-byte vs cue),
  `yaml.Marshal` trailing-newline framing (struct + list), and pretty-JSON nested.
- **`testdata/export/`** — 4 CLI fixtures driven through the `kue export` binary and
  diffed against committed expected outputs (each oracle-matched to `cue export`):
  `deployment` (yaml + json), `scalars` (quoting matrix), `shapes` (empties, nested list,
  list-of-maps, block scalar). New `check_export_fixtures` in `check-fixtures.sh` runs
  `kue export --out <fmt>` per fixture — wholly separate from the protected internal-format
  path; the export `.cue` files are also `cue fmt --check`ed.

### Boundaries (compat-assumptions)

- `-e`/`--expression` selection deferred (serializes the whole evaluated root).
- `yaml.MarshalStream` (`---`), `yaml.Unmarshal`/`Validate`/`ValidatePartial` deferred.
- Exotic go-yaml surface deferred: flow style, anchors/aliases, complex keys, line
  folding/wrapping, `>` folded style, sexagesimal (cue treats `1:2:3` as a bare string,
  which Kue matches). Top-level bare scalar/list **literal** as a whole file is a
  pre-existing parser limitation, not an export-mode gap.

Verify gate green: `lake build` (74 jobs), `scripts/check-fixtures.sh` ⇒ `fixture pairs
ok`, `shellcheck` clean.

## Completed Slice: B3a — Minimal In-Module Import Resolution (end-to-end)

Goal: the first increment of B3, the roadmap's last subsystem — make a file with an
in-module import resolve `pkg.#Symbol` end-to-end by discovering its module, loading the
imported package from disk, merging the package's files, and binding it into scope. Plan:
`docs/notes/2026-06-17-b3-import-resolution-plan.md`.

### Steps

1. AST: `structure Import {path, alias?}` and `structure ParsedFile {value, packageName,
   imports}` in `Kue/Value.lean`.
2. Parser: `parseImportClauses`/`parseGroupedImports`/`parseImportSpec` collect imports
   (the twin of the discard-only `consumeImportClauses`); `parseSourceFile`/
   `parseDocumentFile` thread them into a `ParsedFile` with the declared package name.
   Body parse unchanged — imports are stripped up front, leaving the same field stream
   `parseDocument` consumes. `parseSource` is untouched (stdin/multi-file still discard).
3. `Kue/Module.lean` (new): pure `resolveImportSubpath` (in-module hit / module-root `""` /
   cross-module `none`), `loadPackageFromParsed` (package-name consistency check +
   `mergeSourceValues`), `bindImports` (prepend each package as a **hidden** top-level
   field), `importBindName` (alias › declared name › last path element), `isBuiltinImport`
   (stdlib paths the loader skips). IO boundary: `findModuleRoot` (walk parents),
   `readModulePath` (parse `cue.mod/module.cue`, read `module:`), `listPackageFiles`,
   the recursive `loadPackage`/`collectBindings` (visited-set cycle guard), and the single
   entry `loadFileBound`.
4. CLI: `Kue.exportValue` factored out of `exportSourcesToString`; `Main` routes single
   file-mode and `export` file-mode through `loadFileBound`. Stdin and multi-file CLI keep
   the discard path. A file with no imports — or only builtin imports — needs no module
   context and behaves exactly as before.
5. Tests: `Kue/ModuleTests.lean` (11 `native_decide`/unit theorems pinning
   `resolveImportSubpath`, `loadPackageFromParsed` merge order + conflict rejection,
   `importBindName`, `bindImports`) — all disk-free. Seven `testdata/modules/<name>/`
   fixtures driven by an additive `check_module_fixtures()` stage: `local_defs`
   (in-module `#Def` + 2-file merge), `transitive`, `mixed_builtin` (grouped builtin +
   in-module) → byte-for-byte vs `cue export`; `cycle`/`crossmod`/`missingpkg`/
   `conflictpkg` → `expected.err` substring on the failing run's stderr.

### Milestone proof

`kue export --out json testdata/modules/local_defs/main.cue` and `…/transitive` and
`…/mixed_builtin` are byte-identical to `cue export <dir>` (oracle: `cue` v0.16.1). The
selector `defs.#Widget` resolves through the existing `.selector (.refId …)` path with no
new eval machinery; the package binding is a hidden field, so it never appears in output.

### Boundaries (compat-assumptions)

- Cross-module / registry / vendored imports deferred (B3c/B3d): a non-matching prefix
  fails with `unresolved import: …: cross-module/registry not yet supported (B3c)`.
- Aliased-import edges, nested-path corners, grouped-import comment/trailing-comma
  robustness deferred (B3b); the basic alias and basic grouped import already work.
- Stdin and multi-file CLI still discard imports (pre-B3a behavior).

Verify gate green: `lake build` (exit 0), `scripts/check-fixtures.sh` ⇒ `fixture pairs
ok`, `shellcheck` clean.

## Completed Slice: B3c — Cross-Module / Vendored Import Resolution (the prod9 unlock)

**Intended behavior:** resolve an import path that names a *separate* module (declared in
the importing module's `deps`) to that module on disk — vendored or in the cue cache — and
bind it exactly as B3a binds in-module packages, so `defs.#X` from a real prod9
`infra/apps/*.cue` resolves. No new eval machinery; reuses B3a's `loadPackage`.

What it added (`Kue/Module.lean`):

- **Dep parsing (pure).** `structure Dep {modPath, version}`; `parseDeps` reads each
  `deps."<modpath>@<major>": {v: "<ver>"}` entry off the parsed `cue.mod/module.cue` value;
  `depKeyModulePath` strips the `@<major>` suffix. `readModulePath` became `readModuleInfo`,
  returning `(modPath, deps)` from one parse.
- **Cross-module mapping (pure).** `resolveCrossModule` picks the owning dep by **longest
  module-path prefix** and returns `(dep, subpath)`. `importUnderModule` is the shared
  path-segment prefix test.
- **A declared dep wins over the in-module interpretation.** `resolveImportTarget` checks
  `resolveCrossModule ctx.deps` **first**; only a path matching no dep falls to the
  in-module subpath. This is the keystone — `prodigy9.co/defs` is a dep of the `prodigy9.co`
  module, so it loads the separate `defs` module, not a nonexistent `infra/defs/` subdir.
- **On-disk location (IO, read-only).** `cacheRoot` honors `$CUE_CACHE_DIR` →
  `$XDG_CACHE_HOME/cue` → `~/Library/Caches/cue`. `locateModuleDir` tries vendored
  `cue.mod/pkg/<modpath>@<ver>/`, then bare `cue.mod/pkg/<modpath>/`, then the extract cache
  `<cacheRoot>/mod/extract/<modpath>@<ver>/`; first existing wins, else a clean deferred
  error.
- **`ModuleContext` threading.** `{root, modPath, deps}` flows through the loader; a
  cross-module hop reads the *target* module's `cue.mod/module.cue` for its own context, so
  its transitive in-module and cross-module imports resolve correctly. The visited-set
  cycle guard spans module hops (dirs are absolute).
- **Deferred-error messages.** `unknownModuleError` (path matches no dep) and
  `moduleNotOnDiskError` (dep declared but absent from vendor + cache; registry fetch is
  B3d).

IO stays in `Module.lean`; `Eval`/`Resolve`/the merge core stay pure and total.

**Tests:** 8 new `Kue/ModuleTests.lean` `native_decide` theorems (disk-free) pin
`depKeyModulePath`, `parseDeps` (incl. empty), and `resolveCrossModule` (root, subpath,
longest-prefix win, no-match, textual-not-segment prefix). Four new `testdata/modules/`
fixtures: `crossmod_cache` (cache-extract layout via a committed `_cache/`, byte-for-byte
vs `cue export` under `CUE_CACHE_DIR`), `crossmod_transitive` (app → mid → base, all
cached, oracle-matched), `crossmod_vendor` (legacy `cue.mod/pkg/` layout — kue-only, since
cue v0.16 ignores it), `crossmod_missing` (declared dep absent → `expected.err`). The
existing `crossmod` error fixture's message was updated to the new unknown-dependency text.
`check_module_fixtures` extended to point `CUE_CACHE_DIR` at a fixture's committed `_cache/`
when present — self-contained, never reads the user's real cache. Tests do **not** depend on
the real prod9 cache.

**Real-file spot-check (READ-ONLY, prod9/infra):** `defs.#X` **resolves** — kue descends
into `~/Library/Caches/cue/mod/extract/prodigy9.co/defs@v0.3.19/`. Import resolution is no
longer the blocker. Next blockers (ranked over 15 `infra/apps/*.cue`): (1) `let`
declarations, 10/15; (2) open-list `[...]`, pervasive incl. the `defs/parts` load, 3/15
reach it; then closedness / hidden-field / `[string]:` semantic gaps.

**Design boundary (not a divergence):** kue reads the intermediate module's `deps` per
transitive hop; `cue` requires flat MVS pinning in the main module. Both resolve on-disk
artifacts; the transitive fixture pins flat to stay oracle-clean. **Deferred (B3d):**
registry fetch, MVS solving, `cue.sum`.

Verify gate green: `lake build` (exit 0), `scripts/check-fixtures.sh` ⇒ `fixture pairs
ok`, `shellcheck` clean.

## Completed Slice: Open-List `[...]` Embedding Parse (the real `let`-family unblock)

Goal: unblock the prod9 `infra/apps/*.cue` files. Diagnosed first; the breadcrumb ranked
`let` as the #1 blocker, but `let` was already fully implemented.

### Diagnosis (the key finding)

`let` parses + scopes + stays out of output in every position prod9 uses (file-scope,
in-struct, sibling-ref, let-ref-let, shadowing) — all oracle-clean vs `cue` v0.16.1. The
breadcrumb's "`unexpected character '='` at `let nsp = …`" was *mis-attributed*:
`parseField` matched a `[`-led struct member straight to the `[label]: value` pattern form
**with no fallback**, so the `[...]` open-list embedding inside the `let` RHS struct failed
to parse and the parser backtracked, surfacing the error at the `let`'s `=`. **The actual
blocker was the `[...]` list embedding, not `let`.**

### Steps

1. Red tests. `ParseTests.lean`: `parse_open_list_embedding_in_struct`,
   `parse_list_literal_embedding_in_struct` (new `parseSucceeds` helper), plus four `let`
   scoping theorems pinning the already-working behavior
   (`parse_let_chain_references_prior_let`, `parse_let_inner_shadows_outer`,
   `parse_let_references_sibling_field`, `parse_let_not_emitted_in_output`).

2. Parser fix. `Parse.lean` `parseField`: the `'[' :: _` case now tries `parsePatternField`
   and falls back to `parseEmbedding` on failure (mirrors the existing `'"'` and `'('`
   fallbacks). A `[...]`/`[1,2,3]` struct member parses as a list embedding; `[label]: value`
   patterns are unaffected (pattern parse still wins when valid).

3. Fixtures. Four `testdata/cue/let_*.{cue,expected}` pairs (`let_chain`, `let_shadow`,
   `let_sibling`, `let_not_in_output`) + matching `FixturePorts.lean` entries. `cue
   fmt`-clean, oracle-matched vs `cue export`.

4. Verify. `lake build` (exit 0), `scripts/check-fixtures.sh` ⇒ `fixture pairs ok`,
   `shellcheck` clean.

### Real-file spot-check (READ-ONLY, prod9/infra)

All **15/15** `infra/apps/*.cue` now parse + locally evaluate (stdin `kue`), up from ~3/15.
The parser no longer trips on `[...]`. **Eval semantics for `[...]` embedding remain
DEFERRED** (now the #1 blocker): `cue` permits a list embedded in a struct with no regular
exported fields (emits as the list, definitions stay selectable) and tolerates the latent
struct/list conflict lazily when the value is only selected into; kue is eager and yields ⊥
for `meet(struct, list)`. So the prod9 `let nsp = #Basics & {…[...]}` values parse but
resolve to ⊥ under kue's eager strategy. See `docs/spec/compat-assumptions.md`. (Separately,
`kue export <file>` module discovery — fixed in the next slice below — did not find
`infra/cue.mod/module.cue` from a sub-dir

---

## Completed Slice: `kue export` cue.mod discovery from a subdir / relative path arg

**Intended behavior.** `kue export <path/to/file.cue>` (and any file-mode run that resolves
imports) must discover the module's `cue.mod/module.cue` by walking *up from the target
file's own directory*, for relative AND absolute path args alike — including a file several
levels below `cue.mod/`. A file with no `cue.mod` ancestor still exports plainly (no module,
no import resolution), as before.

### Diagnosis

The parent-walk in `loadFileBound` started from the path's directory taken verbatim. For a
relative arg (`sub/main.cue`, run from the module root), `.parent` is the relative segment
`sub`, and `("sub" : System.FilePath).parent = none` — so `findModuleRoot` checked `sub/`
(no cue.mod), then dead-ended instead of climbing into the cwd's real ancestors. Only
absolute path args worked, because their parent chain reaches the filesystem root. Confirmed
against the oracle: `cue export sub/main.cue` from the module root resolves the import; kue
errored `no cue.mod/module.cue found in any parent directory`.

### Steps

1. Tests first. `ModuleTests.lean` +5 `native_decide` theorems pinning the pure
   path→start-dir logic disk-free: `absolutePath` joins a relative path onto the cwd and
   passes an absolute path through; `discoveryStartDir` yields the absolute parent directory
   the cue.mod walk begins from (relative, nested-relative, and absolute cases).

2. Fix. `Kue/Module.lean`: new pure helpers `absolutePath (cwd path)` and
   `discoveryStartDir (cwd path)`. `loadFileBound` reads `IO.currentDir` at the IO boundary
   and derives the walk's start dir via `discoveryStartDir`, so `findModuleRoot` climbs an
   absolute ancestor chain. Pure core stays pure; FS/cwd stay at the loader boundary.

3. Fixtures. `testdata/modules/export_subdir/` — module `example.com/subm` with an entry
   package in `sub/` (and a deeper `sub/deeper/`) importing the in-module `defs` package. A
   `subpaths` file lists relative entry paths; `check-fixtures.sh` gained
   `check_module_subpaths`, which exports each subpath *from inside the fixture dir* (the
   relative-walk path the bug lived in) and diffs against `expected.<sanitized-subpath>`
   (oracle output, byte-for-byte). Covers path-arg-from-module-root and deeper-nested;
   no-cue.mod-still-exports is covered ad hoc (a plain file exports unchanged).

4. Verify. `lake build` (exit 0), `scripts/check-fixtures.sh` ⇒ `fixture pairs ok`,
   `shellcheck` clean.

### Real-file spot-check (READ-ONLY, prod9/infra)

With discovery fixed, `kue export apps/<app>.cue` run from `/Users/chakrit/Documents/prod9/
infra` now climbs to `infra/cue.mod`, reads the dep table, and resolves the
`prodigy9.co/defs@v0.3.19` dependency from the cue extract cache — uniformly across the apps
(argocd, keel, fx). The next wall is no longer discovery: it is a **parse error in the
dependency** — `defs@v0.3.19/attr/metadata.cue: unexpected character ':'` on
`#labels?: [string]: string`, i.e. the `[string]:` non-string-label *pattern constraint*
parse (tracked blocker). So real-file export is gated on (1) `[...]` embedding eval and (2)
`[string]:` pattern-constraint parse, not on module discovery.
— a pre-existing export-mode path issue, out of this slice's scope.)

---

## Completed Slice: `[string]:` kind/type label-pattern colon-shorthand parse

Goal: parse the canonical CUE open-map / constraint-key label pattern `[string]: T` (and
the general kind/bound/exact/regex bracket form) in **value position** — the bare
colon-shorthand `#labels?: [string]: string` (= `#labels?: {[string]: string}`) — which the
most-imported prod9 dep `defs@v0.3.19/attr/metadata.cue` uses and which blocked real-file
export.

### Diagnosis

The semantic model already supported it end-to-end: `structPattern`/`structPatterns` hold an
arbitrary `Value` label pattern, and `labelMatchesPatternWith` matches a field iff
`meetValue labelPattern (.string label)` is non-bottom — so `[string]:` (`.kind .string`)
already typed string-labeled fields, and the **brace** form `{[string]: int}` already
parsed+typed correctly. The sole gap was surface syntax: `parseFieldValue` recognized
labeled-field colon-shorthand (`a: b: …`) via `valuePositionStartsField`, but had no case for
a *pattern* field in value position. So `f: [string]: T` fell through to `parseExpression` →
`parsePrimaryAtom` `'['` → `parseList`, which parsed `string` then choked on the trailing `:`
("unexpected character ':'", the reported failure).

### Steps

1. Parser (`Kue/Parse.lean`). New `skipBalancedBrackets` (depth-tracked `[ … ]` lookahead,
   skipping quoted literals whole) and `valuePositionStartsPatternField` (a balanced bracket
   group immediately followed by `:`). `parseFieldValue` now routes such a value position
   through `parseField` + `parsedFieldsValue` — identical to the labeled-shorthand path —
   wrapping `[…]: T` into a single-pattern struct. Disambiguation order at `[` in value
   position: trailing `:` ⇒ pattern; otherwise list embedding (`[1,2,3]`). The existing
   field-position `[`-handling (try `parsePatternField`, else `parseEmbedding`) is unchanged,
   so `["a"]:`, `[=~"re"]:`, and `[...]` embedding all still parse. The bracket value is an
   arbitrary `parseExpression`, so kind (`[string]:`/`[int]:`/`[bool]:`), exact, bound
   (`[>0]:`), and regex forms all parse uniformly — no deferral.

2. Tests. 4 fixtures + `FixturePorts` entries: `string_kind_pattern` (`[string]: int` typing
   two concrete int fields via the `{…}&{…}` form), `string_kind_pattern_mismatch` (a string
   field → `_|_`), `string_kind_pattern_only` (pattern-only struct), and
   `type_label_colon_shorthand` (the defs shape `#labels?: [string]: string` via bare
   colon-shorthand under an optional definition). 2 `native_decide` EvalTests theorems:
   `string_kind_pattern_types_matching_field` (meet types a matching int field) and
   `string_kind_pattern_rejects_type_mismatch` (`containsBottom` on a string field).

3. Oracle (cue v0.16.1). `{[string]: int, a: 1}` → `a:1` int; `a: "x"` → conflict; pattern
   alone exports `{}` — all matched.

4. Verify. `lake build` (exit 0), `scripts/check-fixtures.sh` ⇒ `fixture pairs ok`,
   `shellcheck` clean.

### Real-file spot-check (READ-ONLY, prod9/infra)

`defs@v0.3.19/attr/metadata.cue` now parses (`#Metadata: {…, #labels?: {[string]: string},
…}`). `kue export apps/argocd.cue` advances past the `[string]:` wall to a **new** parse
error one dep deeper: `defs@v0.3.19/parts/pod_tolerations.cue: unexpected character '='` (an
alias/`=` form). That, plus the still-open `[...]` embedding eval laziness, are the next
real-file gates — neither is this slice.

---

## Completed Slice: `_`-prefixed identifier lexing (`_x`, not bare `_`)

Goal: clear the `defs@v0.3.19/parts/pod_tolerations.cue: unexpected character '='` parse
wall that blocked the `parts` package (imported by real apps) on `kue export
apps/argocd.cue`.

### Diagnosis

The `=` was a misleading symptom, not the cause. Bisecting the dep file reduced the
failure to `let X = { if _x != _|_ {…} }`, then to the standalone `a: _x != 1`
("expected ':' after field label" at the `!=`). Root cause: in `parsePrimaryAtom`,
`'_' :: rest => parseOk .top rest` matched a bare `_` greedily, consuming only the leading
`_` of a `_`-prefixed identifier (`_x`, `_parts`, `_base`) and leaving the rest as stray
input. Any expression starting with such an identifier broke (`_x != _|_`, `_x + 1`,
`value: _secret`); inside a `let X = {…}` body the resulting token misalignment propagated
out to the enclosing `let`'s `=`, surfacing as `unexpected character '='`. The `_|_`
(bottom) case at the preceding match arm was unaffected, which is why bottom literals
parsed but `_`-idents did not.

### Steps

1. Fix (`Kue/Parse.lean`, `parsePrimaryAtom`). Replaced the single `'_' :: rest => .top`
   arm with `'_' :: next :: rest`: if `next` is an identifier-rest char, defer to
   `parseIdentifierValue` (so `_x`/`_foo`/`__bar` parse as identifiers); otherwise bare `_`
   → top. The `_|_ → bottom` arm above it is untouched, and a trailing lone `_` still
   matches the final `'_' :: rest => .top`.

2. Tests. 2 fixtures + `FixturePorts` entries: `underscore_ident_reference` (a hidden
   `_base` referenced by `ref`, compared with `!=`/`==`, and used in `+`) and
   `underscore_top_bottom` (regression: `_|_ | 2` → bottom dropped to `2`, plus the B2
   value-position struct alias `X={n:1, m:X.n}` resolving its self-reference). 3
   `native_decide` theorems mirror both fixtures plus `fixture_underscore_top_unaffected`
   (bare `_` still means top).

3. Oracle (cue v0.16.1). `_base` reference → `5`, `_base != 3` → `true`, `_base + 1` → `6`,
   `_base == 5` → `true`, `_base != _base` → `false`; `_|_ | 2` → `2`; `X={n:1,m:X.n}` →
   `{n:1,m:1}` — all matched (cue hides `_base` in output; kue retains it in internal
   format, as designed).

4. Verify. `lake build` (exit 0), `scripts/check-fixtures.sh` ⇒ `fixture pairs ok`,
   `shellcheck` clean.

### Real-file spot-check (READ-ONLY, prod9/infra)

`defs@v0.3.19/parts/pod_tolerations.cue` now parses — `kue export` on it advances from a
parse error to an eval error (`conflicting values (bottom)`), which is the known
`meet(struct,list)=⊥` / `[...]` laziness eval blocker, not a parse gap. That eval blocker
is the next real-file gate.

## Completed Slice: Memoize Evaluation (fix the exponential re-eval blowup)

Goal: kill the exponential blowup that made `kue export apps/argocd.cue` hang (~2.6h at
`evalFuel=100`). Phase B diagnosed it as fuel-bounded *exponential re-evaluation*, not
non-termination: a `Self.#components.X` selector re-evaluated the entire `#components`
struct per selection, and three sibling selections in the `packs.#Argo` embedding
re-derived it multiplicatively per fuel level, with no memoization anywhere. The fix is a
behavior-preserving optimization — compute each binding/struct once and share it
(CUE's computed-once vertex model).

### Design

Threaded a memo cache through the evaluator as explicit `StateM` state. `evalValueWithFuel`
is now an `EvalM := StateM EvalState` action; `EvalState` holds the cache
(`Std.HashMap EvalKey Value`) plus a frame-id counter. Evaluation is a pure function of
`(fuel, env, visited, value)`, so caching on that tuple shares an already-computed result
rather than re-deriving it — same value, computed once.

The cost that the naive full-tuple key incurs is hashing/comparing the deep `env` on every
probe. To make the key cheap, each scope frame is tagged with a **process-unique id** when
pushed (`pushFrame` allocates from the state counter); the env becomes `Env := List (Nat ×
List Field)`. The cache key stores the frame **id stack** (`env.ids : List Nat`) instead of
the frame contents, so equality is O(depth) over `Nat`s. Frame ids track frame *identity*:
the depth-0 self-reference (`env` unchanged) and the `env.drop` rebase (a suffix) keep their
ids, so the three `Self.#components.X` selections thread the *same* frame ids and hit the
cache; independently-built frames get distinct ids and never falsely share. The hash is
deliberately *shallow* (`fuel`, `visited`, env depth, value's top constructor tag via
`valueTag`), so a probe never traverses the value subtree; structural `BEq` runs only on a
hash-bucket match.

**Cycle interaction (the load-bearing soundness point):** `visited` (the slot set that
drives cycle detection) is part of the key, so a binding caught mid-cycle (its slot in
`visited`) is keyed *separately* from the same binding reached fresh — a wrong mid-cycle
partial can never be cached and replayed where the cycle guard would not have fired. The
`.refId`/`slotVisited`/`⊤`-on-revisit logic is byte-identical to before; only its result is
now memoized under the exact `(fuel, env-ids, visited, value)` it was computed for.

### Steps

1. Cache plumbing (`Kue/Eval.lean`). Added `valueTag`, `Frame`/`Env`/`Env.ids`, `EvalKey`
   (+ custom shallow `Hashable`, derived `BEq`), `EvalState`, `EvalM`, `pushFrame`, and
   `runEval`. Rewrote the eval mutual block into `StateM`: split `evalValueWithFuel` into a
   thin cache wrapper + `evalValueCoreWithFuel`; converted the `.map`/`.foldl` fan-outs that
   call eval into monadic list helpers (`evalValuesWithFuel`, `evalFieldRefsListWithFuel`,
   `meetEmbeddingsWithFuel`, `expandComprehensionsWithFuel`, `expandForPairsWithFuel`); all
   frame pushes route through `pushFrame`; `.refId`/`thisStructFieldIndex?` read `frame.snd`.
   `evalStructRefs` runs the action with a fresh state via `runEval`.

2. Totality. The monadic split broke automatic structural-recursion inference, so each
   mutual function carries an explicit lexicographic `termination_by (fuel, phase, listLen)`:
   `fuel` decreases on the real recursion; `phase` orders the equal-fuel hops
   (folders 3 → field-refs 2 → wrapper 1 → core/leaf 0); `listLen` covers same-fuel
   self-recursion over shrinking lists. No `partial def`.

3. Tests. `shared_selection_fan` fixture (`.cue`/`.expected` + `FixturePorts` entry) pins
   the repeated-selection blowup shape (`components.X.who` selected three times,
   oracle-matched byte-for-byte to `cue export`). Two `EvalTests` `native_decide` theorems:
   `eval_shared_repeated_selection` (shared sub-struct selected twice) and
   `eval_cycle_with_repeated_selection` (`x: x & {p: 1}`, then `x.p` selected twice —
   proves the cache+`visited` interaction preserves bounded-cycle resolution;
   oracle-matched to `cue`).

4. Verify. `lake build` (all 574 theorems + every fixture pass UNCHANGED — behavior
   preserved), `scripts/check-fixtures.sh` ⇒ `fixture pairs ok`, `shellcheck` clean. The
   four committed cycle fixtures (direct/mutual/three/constrained) pass untouched.

### Timing / real-file (READ-ONLY, prod9/infra + cue cache)

Phase B's minimal repro (`packs.#Argo & {#name:"stage9"}`, `defs@v0.3.19`) went from a
30s+ timeout (extrapolating to ~2.6h at fuel 100) to **~7s** — and now *completes*. The
local `Self`-fan repro (the exact multiplicative shape) evaluates in **~0.006s**. Real
`kue export apps/argocd.cue` (was the ~2.6h hang) now **completes in ~57s**, returning
`conflicting values (bottom)` — the next blocker, the `[...]` open-list-embedding
`meet(struct,list)=⊥` eager-vs-lazy semantics (plan item 2), no longer masked by the hang.

---

## Completed Slice: List-Embedding-in-Struct Eval (`meet(struct, list)`)

Implemented the eval semantics of a list embedded in a struct — the construct behind the
real prod9 `#Argo: Self={ …hidden…, [Self.#components.repo, …] }` definitions. **Diagnosed
oracle-first against `cue` v0.16.1; the prior breadcrumb's "cue tolerates the conflict
lazily" hypothesis was measured WRONG.**

**Measured rule (eager, structural — not lazy):** a struct embedding a list IS that list
**iff the struct carries no output field** (output = `regular` or `required`; hidden `_x`,
definition `#x`, optional `a?:`, and `let` are all non-output). In that case the value
manifests and indexes as the list while its declarations stay selectable; with any output
field the struct/list embed is a genuine conflict (`⊥`). Oracle evidence: `{[1,2,3]}`→
`[1,2,3]`, `{#a:1,[1,2]}`→`[1,2]`, `{#a:1,[...]}`→`[]`, `{a:1,[1,2]}`→conflict,
`{a?:int,[1,2]}`→`[1,2]`, `{a:1}&[1,2]`→conflict; `v.#a`=1 and `v[0]`=10 both resolve on
the same `{#a:1,[10,20]}` value (genuinely dual-natured).

**Type-system-first model.** New `Value.embeddedList (items : List Value) (tail : Option
Value) (decls : List Field)` constructor: the list nature and the surviving non-output
declarations are one value (illegal-states-unrepresentable — no flagged struct). The
decision pivots on the new total `FieldClass.producesOutput` (true only for
`regular`/`required`). `Lattice.meetWithFuel` gains arms (placed before the struct arms so
a left `embeddedList` keeps its own decls): build it from `meet(only-non-output struct,
list)`; merge two embeddedLists (decls meet struct-wise, lists meet via the new
`meetListPairWith` over `(items, optional-tail)` shapes); meet one against a further
struct/list. `meetCore`'s fuel-0 fallback bottoms it conservatively. `Manifest` emits the
concrete items (decls + open tail dropped). `Eval.selectEvaluatedField` reads decls;
`selectEvaluatedIndex` indexes items (open tail → tail-index semantics). `containsBottom`
recurses into items/tail/decls, so a conflicting embedded element (`{#a:1,[1]} &
{#b:2,[9]}` → `x.0` conflict) surfaces and export errors — matching `cue`. `Format` formats
it as `{decls…, [items…]}`.

**Genuine conflicts preserved.** `{a:1} & [1,2]` and `{a:1, [1,2]}` still bottom (output
field present), oracle-matched.

**Tests.** 8 fixtures (`list_embedding_pure/hidden/open/regular_conflict/optional/meet_two/
select_index`, `list_struct_genuine_conflict`) each with a FixturePorts entry; 9
`ListTests` `native_decide` theorems pinning the build/merge/conflict/manifest behavior.
Theorem count 574 → 663 (includes prior slices' growth). Verify gate green: `lake build`,
`scripts/check-fixtures.sh` ⇒ `fixture pairs ok`, `shellcheck` clean.

**Next blocker (read-only check).** `kue export apps/argocd.cue` still returns `⊥` — but
this is NOT a list-embedding gap: the direct `packs.#Argo & {#name:…}` form errors in both
kue and `cue`; with the consuming struct's own `[...]` present `cue` proceeds and the next
gate is the `if Self.#x != _|_` presence-test comprehension guard (plan item 2b), confirmed
in isolation (`#D: Self={#x?:string, out:{if Self.#x != _|_ {val: Self.#x}}}; y: #D &
{#x:"hi"}` → `cue` `out.val:"hi"`, kue `out:{}`/`y:⊥`).

---

## Completed Slice: `== _|_` / `!= _|_` Presence Test (Definedness)

**Behavior.** `e == _|_` / `e != _|_` is CUE's *definedness test*, not value equality —
the engine behind the `if Self.#field != _|_ { … }` conditional-inclusion idiom. Oracle
(`cue` v0.16.1): evaluate the non-`_|_` operand and classify three-way.
- *Defined* — a resolved value (prim, struct, list, embeddedList): `!= _|_` → `true`,
  `== _|_` → `false`. (`1 != _|_` → true; `{x:1} != _|_` → true.)
- *Error* — an evaluated bottom (missing field on a known struct, a conflict): `== _|_` →
  `true`, `!= _|_` → `false`. (`_|_ == _|_` → true.)
- *Incomplete* — a residual/unresolved form (kind `int`, bound `>5`, unresolved ref/disj,
  `_`/top): the comparison itself stays incomplete and does not resolve to a bool —
  matching `cue`'s "non-concrete value in operand to ==" / "requires concrete value". In a
  comprehension guard the residual reads as not-true, so the guard drops.

**The bug.** `evalEq` blanket-propagated a bottom operand (`.bottom, _ => .bottom`), so
`a != _|_` on a concrete `a` produced `⊥` instead of `true`, and the present-field guard
never fired.

**Fix (type-system-first).** The presence test triggers only on the **syntactic `_|_`
literal** — which parses to bare `.bottom` — intercepted at the `.binary` dispatch in
`evalValueWithFuel` before generic operand evaluation. This is the only point where the
literal is distinguishable from an operand that merely *evaluated* to a bottom: keeping the
trigger syntactic preserves genuine error propagation for non-`_|_` operands (`(1/0) == 2`
→ the error, not `false` — oracle-confirmed). New `inductive Definedness`,
`classifyDefinedness : Value → Definedness`, and `evalPresenceTest`. An incomplete operand
yields a clean residual `e != _|_` (the `_|_` side normalized back to `.bottom`).

**Verified vs `cue`.** Concrete `!= _|_`→true / `== _|_`→false; `"a" == _|_`→false;
same-scope present guard fires (`if f != _|_ {seen:f}` → `seen: 3`); absent-field guard
drops (`if base.g != _|_ {…}` → empty) — observably identical to `cue` on every probed
case.

**Tightening flagged, deferred.** kue models a missing-field selection on a concrete closed
struct as a residual `.selector` (→ *incomplete*), where `cue` makes it a definite bottom.
Guard behavior agrees (both drop `if x.absent != _|_`); only a bare `x.absent == _|_`
outside a guard would differ. The principled fix (missing-field-on-closed-struct → bottom,
resolving the incomplete/bottom conflation) has broad blast radius and does not unblock the
argocd gate, so it is deferred (see compat-assumptions).

**Tests.** `presence_test_guard` fixture (+ FixturePorts entry): concrete `!=`/`==`,
string `==`, present-guard-fires, absent-guard-drops, ordinary `!=` regression. 12
`PresenceTests` `native_decide` theorems pinning the three-way classification, the
concrete/incomplete comparisons, guard fire/drop, and ordinary-`==`/`!=` unchanged.
Theorem count 663 → 675. Verify gate green: `lake build`, `scripts/check-fixtures.sh` ⇒
`fixture pairs ok`, `shellcheck` clean.

**Next blocker (read-only check).** `kue export apps/argocd.cue` is not present on this
host (external prod9 tree, remote-fs split), but the isolated real-shape repro still fails:
`#D: {#x?: string, out: {if Self.#x != _|_ {val: Self.#x}}}; y: #D & {#x:"hi"}` → kue
`out:{}` / `y:⊥`, `cue` `out.val:"hi"`. This is NOT the comparison — it is **lazy field
resolution through definition-meet** (plan slice 2c): kue eagerly evaluates a definition's
comprehension body + field refs against the definition's own pre-meet scope (`#x: string`),
rather than deferring until the meet supplies `#x: "hi"`. Confirmed orthogonal via
`if true {val: #x}` (no comparison): kue `out.val: string`, `cue` `out.val: "hi"`. That
lazy-meet-resolution layer is the live argocd gate.

## Completed Slice: In-struct duplicate-label canonicalization (2c.1)

Goal (plan slice 2c.1, lazy field resolution increment 1): a field body that references a
sibling label must see that label's FULLY-MERGED value, not the first conjunct. kue
evaluated bodies eagerly against the pre-merge slot list, so `{a: int, b: a, a: 1}` gave
`b: int` (cue `b: 1`). Approach (c) from the 2c plan: canonicalize the struct frame BEFORE
it is pushed, so the list the evaluator indexes is already deduplicated to first-occurrence.

**Mechanism.** New `joinUnevaluated l r := .conj [l, r]` and `canonicalizeFields : List
Field → List Field := (mergeFieldListWith joinUnevaluated fields).getD fields`
(`Eval.lean`). `mergeFieldListWith`'s foldl is merge-into-existing-else-append, so it
preserves first-occurrence order and shifts no earlier index — `b`'s `refId ⟨0,0⟩` still
lands on slot 0, now carrying the merged body. Bodies are NOT yet evaluated (field refs are
unresolved `BindingId`s), so they cannot be `meet`-ed; `.conj` re-evaluates them lazily once
the frame is in scope. Field class is combined via `mergeFieldClass` (the same logic
`mergeEvaluatedFields` uses); a class mismatch keeps the slots separate, matching merge
semantics. Total (foldl over a finite list; no new `partial def`).

**Applied at every frame push.** The 5 struct arms in `evalValueCoreWithFuel` (`.struct`,
`.structTail`, `.structPattern`, `.structPatterns`, `.structComp`) immediately before
`pushFrame`, AND the top-level arms in `evalStructRefsM` (`.struct`/`.structTail`/
`.structPattern`/`.structPatterns`) — the top-level path goes through `evalTopFieldsM`, not
the `.struct` arm, so it needed its own canonicalization. Exactly one canonicalize per arm;
id-allocation and memo logic untouched.

**Invariants preserved.** Memo cache: canonicalize before `pushFrame`, which allocates a
fresh id, so a canonicalized frame is a distinct object → fresh id → no stale `b:int` hit;
`nextFrameId`/`EvalKey` untouched. Cycles: a merged self-ref slot (`{a:a, a:1}` →
`.conj [a,1]` at slot 0) still hits the `slotVisited`→`.top` guard, collapsing to `1` rather
than looping (pinned by `eval_merged_self_ref_cycle`). FULL existing fixture suite + all
existing theorems pass UNCHANGED (zero `.expected` diffs).

**Scope correction to the 2c plan.** 2c.1 fixes in-struct duplicates and nested visibility,
but NOT the inlined-def case `d:{a:int,b:a}; y:d&{a:1}` the plan listed under 2c.1. That
case is a *meet* of two independently-evaluated structs (`{a:int,b:a}` evaluates `b` to
`int` before the meet brings in `a:1`), structurally identical to the referenced-`#D` path —
`meet` is pure `Value→Value→Value` over already-evaluated structs. Both are 2c.2 (meet must
wrap colliding bodies in `.conj` and re-evaluate). Verified: `{a:int,b:a}&{a:1}`,
`#D&{a:1}`, and `d&{a:1}` all still give `b:int` post-2c.1.

**Tests.** Four fixtures (`.cue`/`.expected` + FixturePorts entries): `in_struct_sibling_merge`
(`{a:int,b:a,a:1}`→`a:1,b:1`), `in_struct_sibling_conflict` (`{a:1,b:a,a:2}`→both bottom),
`nested_sibling_merge` (`{a:int,c:{e:a},a:1}`→`c.e:1`, proves 2c.3 free), `merged_self_ref_cycle`
(`{a:a,a:1}`→`a:1`, cycle guard). Four matching `native_decide` theorems in `EvalTests`
asserting the full evaluated struct. Verify gate green: `lake build`,
`scripts/check-fixtures.sh` ⇒ `fixture pairs ok`, `shellcheck` clean.

---

## Completed Slice: Lazy resolution through struct conjunction (2c.2)

Goal (plan slice 2c.2, lazy field resolution increment 2): a struct conjunction `&` must
merge its conjuncts' *declarations* into one scope BEFORE evaluating bodies, so a body
referencing a sibling that another conjunct narrows sees the narrowed value. 2c.1 fixed
in-struct dup labels; this extends the same mechanism across `&`. kue evaluated each `&`
operand independently then `meet`-ed the results, so `d:{a:int,b:a}; y:d&{a:1}` gave
`y.b:int` (cue `y.b:1`) — `b` captured `int` before the meet brought in `a:1`.

**Eval locus (NOT pure meet).** `d & {a:1}` parses to `.conj [.ref d, <struct>]`; the defect
is the `.conj` arm in `evalValueCoreWithFuel` (`Eval.lean`), which eval'd each constraint then
folded `meet`. `meet` is pure `Value→Value→Value` over already-evaluated structs
(`.refId _,_ => .bottom` makes refs opaque to it by design), so the fix lives in eval, before
the operands are evaluated — never in meet.

**Mechanism.** New `lazyConjMergedFields env constraints`: when *every* conjunct reduces to a
same-scope struct it builds one merged frame and evaluates it once; otherwise returns `none`
and the arm falls back to the original eval-then-`meet` fold.
- `conjStructOperand?` reduces an operand to `(declFields, open_)`, following ONLY depth-0
  sibling `refId`s to their struct bodies. `depth == 0` is the safety boundary: a sibling's
  body frame shares the conjunction site's enclosing scope, so its declarations splice without
  disturbing outer references. Non-structs / patterns / tails / disjunctions / outer refs →
  `none` → meet path (so `(a|b)&c`, `{a:1}&[1,2]`, `int&>0` are all unchanged).
- `remapConjRefs` (de-Bruijn-style total shift, structural fuel) rebases each conjunct's
  depth-0 sibling refs onto the merged frame's first-occurrence layout; refs at depth>0 are
  left untouched, since the merged frame sits exactly where each conjunct's own frame would.
- `applyConjClosedness` folds each conjunct's closedness over the merged fields, identical to
  binary meet's `applyStructClosedness` — so `#D & {extra}` still rejects the extra field and
  the conjunction-of-a-closed-def result stays closed. Then `canonicalizeFields` + one
  `pushFrame` + eval. Memo/cycle invariants preserved (canonicalize before fresh-id push;
  self-ref slot still hits `slotVisited`→`.top`). Total: no `partial`, explicit `termination_by`.

**What it fixes (oracle-confirmed, cue v0.16.1).** `d&{a:1}`→`b:1`; `{a:int,b:a}&{a:1}`→`b:1`;
`d&{a:>0}`→`b` tracks `a`; `#D&{#x:"hi"}` with nested `out:{val:#x}`→`out.val:"hi"`;
chained `{a:int,b:a,c:b}&{a:1}`→all `1`; closed `#D&{b:1}`→`b` bottoms. The reduced
`packs.#Argo` def-meet templating shape (`#Argo & {name,namespace}` with nested
`out.meta.{n,ns}` referencing the narrowed tops) exports **byte-identical to `cue export`** —
first green on the real-file pattern (`testdata/export/def_meet_template`).

**Known gap (NOT 2c.2): optional-definition class.** The `#x?` form of the hidden-def case
stays wrong because `FieldClass` cannot represent "optional definition" — `mergeFieldClass`
rejects `optional`+`definition`, so `#x?` and `#x` never merge and the nested `out.val` reads
the un-narrowed `string`. Orthogonal modeling slice (optionality as a separate axis on
`FieldClass`), not lazy resolution.

**CUE scoping preserved.** A cross-conjunct reference that CUE rejects (`{a:int,b:a}&{c:b}` —
`b` not in `{c:b}`'s lexical scope) still bottoms in kue: rebasing only touches refIds that
already resolved within their conjunct at resolve-time, so unresolved refs stay unresolved.

**Tests.** Seven fixtures (`.cue`/`.expected` + FixturePorts entries): `meet_lazy_sibling_ref`,
`meet_lazy_literal`, `meet_lazy_incomplete`, `meet_lazy_hidden_def`, `meet_lazy_chain`,
`meet_lazy_disj_operand`, plus export fixture `def_meet_template`. Four `native_decide`
theorems in `EvalTests` pinning the full evaluated struct for the sibling-ref, literal, chain,
and hidden-def cases. FULL existing suite + all existing theorems pass UNCHANGED. Verify gate
green: `lake build`, `scripts/check-fixtures.sh` ⇒ `fixture pairs ok`, `shellcheck` clean.

## Completed Slice: Optional-definition fields — orthogonal `FieldClass` (2c.5)

**Problem (type-system-first finding).** `#x?` (an optional definition field) could not merge
with a provided `#x`: `FieldClass` was a flat enum (`regular | optional | required | hidden |
definition | letBinding`) that admits no "optional AND definition" state. `mergeFieldClass`
returned `none` for `optional`+`definition`, so `#D: {#x?: string}; y: #D & {#x: "hi"}` left the
two `#x` slots unmerged. In CUE these are **orthogonal** modifiers — a field independently
is/isn't a definition, is/isn't hidden, and sits on a presence rung — so the flat enum was the
illegal-state-admitting design (`docs/guides/slice-loop.md` philosophy). The last real-file
blocker after 2c.2.

**Decision: Option B (orthogonal refactor), enabled by smart constructors.** Blast radius of the
*representation* change is ~28 files (every test constructs `.hidden`/`.regular`/… literally),
but only 5 sites *match* on the class (`Manifest`/`Format`/`Eval.structPairs`/`Normalize` +
`mergeFieldClass`). Keeping the legacy names as `def`s (smart constructors over the new
structure) leaves all construction/`==` sites compiling unchanged, so the real edit is just the
5 match sites — making B tractable and on-philosophy. Chose B over the minimal "add an
`optionalDefinition` variant" (A), which would re-create the can't-compose problem on the next
axis pair.

**Encoding.** `inductive Optionality | regular | optional | required` with a `meet` lattice
(present `regular` dominates and discharges `required`; `required` dominates `optional`;
`optional & optional` stays optional). `inductive FieldClass | field (isDefinition isHidden :
Bool) (optionality : Optionality) | letBinding` — `letBinding` stays a distinct constructor (a
`let` is not a field and composes with nothing), so the field axes never encode a non-field.
Smart ctors: `.regular = field false false regular`, `.optional`/`.required` shift optionality,
`.hidden = field false true regular`, `.definition = field true false regular`.
`ignoresClosedness = isDefinition || isHidden` (so `#x?`/`_x?` ignore closedness regardless of
presence); `producesOutput` true only for `field false false regular` and `field false false
required` (preserving the old enum's regular/required→output). `mergeFieldClass` ORs def/hidden
and meets optionality; `letBinding` merges only with `letBinding`.

**What it fixes (oracle-confirmed, cue v0.16.1).** `#D: {#x?: string}; y: #D & {#x: "hi"}` →
`#x: "hi"` present definition (eval), `y` exports `{}` (definitions non-output);
`y.#x` selects `"hi"`. `_x?` + `_x: 5` → `_x` present, selects `5`. `#y!` + `#y: 3` → present
(required discharged by the regular conjunct). An optional non-def and a definition behave
exactly as before. Also corrected a **flat-enum bug**: `{a?: int} & {a!: int}` is `a!` (required,
not present), NOT `_|_` — the old `mergeFieldClass` wrongly bottomed `optional & required`. Two
test fixtures encoded the old bug (`meet_unsupported_field_class_combination_bottoms_struct`,
and an artificial same-string `"same"`/`"same"` label collision in
`eval_binding_id_not_label_lookup`); both rewritten to the oracle-correct behavior (the second
to realistic distinct `#same`/`same` labels, since the parser always keeps the `#`/`_` prefix in
the label string — `#x` and `x` are distinct labels and never collide, so `mergeFieldClass` is
only ever called for same-prefix fields).

**Parser.** `parseFieldClass` now reads `?`/`!` into an `Optionality` and the `#`/`_` label
prefix into `isDefinition`/`isHidden` independently, instead of the `?`/`!` short-circuit that
dropped definition-ness. `#x?` → `field true false optional`. `#_x` → definition (def-prefix
wins over `_`), matching cue.

**Tests.** +6 theorems (`StructTests`: `meet_optional_with_required_yields_required`,
`meet_optional_definition_with_provided_definition`, `meet_optional_hidden_with_provided_hidden`,
`meet_required_definition_discharged_by_value`, `optional_definition_axes`,
`optionality_meet_lattice`; `ParseTests`: `parse_optional_definition_merges_when_provided`).
+2 fixture pairs: CLI `optional_definition_field.{cue,expected}` (+ FixturePort, parse-driven)
and export `optional_definition_field.{cue,json}` (byte-identical to `cue export`). 688 theorems
total; FULL existing suite passes UNCHANGED. Verify gate green: `lake build`,
`scripts/check-fixtures.sh` ⇒ `fixture pairs ok`, `shellcheck` clean. `def_meet_template` still
byte-identical. Reduced argo-like optional-def shape (`#meta?` + nested `dest?`) now exports
byte-identical to cue.

---

## Completed Slice: Retain `int` conjunct in `int & >0` (bound kind-retention)

Goal: fix the #1 known wrong-output on the supported subset — `int & >0` collapsed to `>0`,
dropping the load-bearing `int` kind (a bare `>0` admits floats in CUE, so `int &` is what
rejects them). Oracle: `cue` v0.16.1 prints `int & >0` for `x: int & >0`.

**Diagnosis (precise).** The drop was in MEET, not just format. `Lattice.meetCore`'s eight
`kind k & intGe/Gt/Le/Lt` arms returned the bare bound whenever `kindAcceptsKind k .int`,
discarding the kind. (Float rejection already worked incidentally, because kue's bounds are
*integer-restricted* — `intGt 0` itself rejects `1.5` — so `(int & >0) & 1.5` was already
`_|_`; only the displayed/structural `int` was lost.) A deeper, separate divergence surfaced
and was FOLDED: kue has no float/number bounds (`>0.5` is a parse error; bare `>0 & 1.5` →
`_|_` vs cue's `1.5`) — closing that needs decimal-valued, domain-tagged bounds (plan item 3).

**Fix.** New `meetKindWithIntBound (kind) (bound)`: `int` → `.conj [.kind .int, bound]`
(retains, formats `int & >0`); `number` → bare `bound` (a bound is implicitly number-typed —
cue drops it); else `kindConflict`. The eager conj-injection broke multi-bound int ranges:
`int & >=0 & <=65535` ping-ponged through `meetConjValueWith`'s left-fold into nested `.conj`,
which `meetCore`'s pairwise arms cannot collapse, bottoming the value. Rewrote conjunction
meet to reduce over a **flat constraint set**: `flattenConj` (recursively splice nested
`.conj`), `addConstraintWith` (meet a constraint pairwise into a reduced list — a single-value
simplification replaces + re-folds against the rest, a `.conj` result means no merge so append,
bottom short-circuits), and `meetConjValueWith` flattens both sides, folds, re-wraps. Order is
source-preserving; idempotent; flat.

**boundConstraint refactor (plan item 3) FOLDED** — 96 `intG*` refs in `Lattice` + ~70 in
tests = high blast radius; the plan sequences it as the consolidation-batch lead, and it now
also carries the decimal/domain generalization the deeper twin needs.

**Tests.** +9 `BoundTests` theorems (kind-retention both orders, `int & >0` format,
`number & >0` drop, float-rejection, int-admit, flat range, range-admit, idempotent). Four
pre-existing conj-meet theorems switched `rfl`→`native_decide` over `==` (the new meet body no
longer definitionally reduces; `Value` has `BEq` not `DecidableEq`, so equality is via `==`).
`testdata/cue/meet_lazy_incomplete.expected` updated `{a: >0, b: >0}` → `{a: int & >0, b: int &
>0}` — oracle-confirmed `cue` v0.16.1 produces exactly this (kue now MATCHES where it diverged).
706 theorems total; FULL existing suite passes UNCHANGED except that one oracle-confirmed fixture.
Verify gate green: `lake build` (80 jobs), `scripts/check-fixtures.sh` ⇒ `fixture pairs ok`,
`shellcheck` clean. CLI oracle-matched: `int & >0`, `>0 & int`, `(int&>0)&1.5`→`_|_`,
`(int&>0)&5`→`5`, `int & >0 & <10`, `#Port: int & >=0 & <=65535`, `number & >0`→`>0`,
`>0 & 5`→`5`.

## Completed Slice: Proper CLI — subcommands, `--help`, `version` (2026-06-17)

The CLI moved from ad-hoc argv branching in `Main.lean` to a type-system-first subcommand
dispatcher. New `Kue/Cli.lean` defines a pure `parse : List String → Command`, where
`Command` is a sum type: `eval (files : List String)`, `export (ExportOpts)`, `version`,
`help (Option HelpTopic)`, `error (message : String)`. `Main.runCommand` dispatches it
exhaustively — no stringly-typed flag soup past the single parse fold.

**Surface.** `kue eval [file…]` (explicit name for the historical default internal-format
path), `kue export [--out json|yaml] [file]` (unchanged behavior), `kue version` /
`--version` / `-V` (prints the new `Kue.version` constant in `Kue/Runtime.lean`,
`"0.1.0-alpha"`), `kue help [eval|export]` / `--help` / `-h` (top-level synopsis +
subcommand list + per-command usage in `helpText`).

**Back-compat by construction.** `parse` routes a first token that is not a recognized
subcommand or top-level flag to the eval positional list, so `kue < file`, `kue <file…>`,
and `kue export …` are byte-identical to pre-slice behavior. Confirmed: full
`check-fixtures.sh` (internal-format CLI fixtures, export yaml/json fixtures, module
fixtures, subpath fixtures) passes unchanged — `fixture pairs ok`.

**Error model.** Distinct exit codes — `2` for usage errors (unknown subcommand-flag,
bad/missing `--out`), `1` for eval/parse/manifest failures, `0` on success. Errors print
`kue: <message>` + `run \`kue --help\` for usage` to stderr. A missing/unreadable input
file now reports `kue: cannot read <path>: <io-error>` (via `(loadFileBound …).toBaseIO`)
instead of leaking an uncaught exception.

**Types.** `ExportFormat` gained `DecidableEq` (was `Repr, BEq`); `Command`/`ExportOpts`/
`HelpTopic` derive `Repr, BEq, DecidableEq` so the parse theorems are decidable.

**Tests.** 25 `CliTests.lean` `native_decide` theorems pin the argv→`Command` parse (bare
files, eval/export/version/help subcommands, all flag spellings, every error case).
`check-fixtures.sh` gained an additive `check_cli_behavior` stage: `--help` lists the
subcommands, `version`/`--version` print and agree, `eval` agrees byte-for-byte with the
bare path on a sample fixture, unknown-flag and bad-`--out` exit non-zero with the right
stderr substring. The in-repo `packaging/homebrew/kue.rb` `test do` block now also asserts
`kue version` matches a semver-shaped regex (in-repo copy only; tap repo + release.sh
untouched).

**Verify gate green:** `lake build` (84 jobs), `scripts/check-fixtures.sh` ⇒
`fixture pairs ok`, `shellcheck scripts/check-fixtures.sh` clean. Manual: `echo 'x: 1+2' |
kue` and `| kue eval` both `x: 3`; `kue version`/`-V`/`--version` ⇒ `0.1.0-alpha`;
`kue --help`/`kue help eval`; `kue export --out yaml <f>` and default-json; `kue --bogus`
⇒ exit 2; `kue export --out bogus` ⇒ exit 2; `kue nonexistent.cue` ⇒ clean read error,
exit 1.

## Completed Slice: Open-List Collapse on Manifest/Export

Goal: a bare open list manifests/exports as its concrete prefix, dropping the open/typed
tail, matching `cue export`. Was returning `.incomplete (.listTail …)`; the
struct-embedded list (`embeddedList`) already collapsed via the earlier list-embedding
slice — this closes the bare top-level / plain open-list gap (audit item 2).

### Oracle rule (cue v0.16.1)

On EXPORT, an open-list tail is always dropped and the concrete prefix is emitted as a
concrete list: `[1,...]`→`[1]`, `[...]`→`[]`, `[1,2,...int]`→`[1,2]`, `[1,...string]`→`[1]`.
No open-list shape is incomplete *because of* its tail. A non-concrete prefix *element* is
genuinely incomplete: `[int,...]`→`x.0: incomplete value int`, `[1,int,...]`→`x.1:
incomplete`. (`cue eval` agrees: `[1,...]`→`[1]`.)

### Steps

1. Tests first. `Kue/ManifestTests.lean` — six `rfl` theorems: `[1,...]`→`[1]`, `[...]`→
   `[]`, `[1,2,...int]`→`[1,2]`, `[1,...string]`→`[1]`, `[int,...]`→`.incomplete (.kind
   .int)`, and nested-in-struct `{xs:[10,...]}`→`{xs:[10]}`.
2. Fix `Kue/Manifest.lean` `listTail` arm: recurse via `manifestItemsWithFuel fuel items`
   (drop `tail`), mirroring the `embeddedList` arm. A non-concrete prefix element surfaces
   as `.incomplete` naturally through the recursion. INTERNAL `formatValue` representation
   of open lists left untouched (check-fixtures depends on `[1, ...]`).
3. Export fixture `testdata/export/open_lists.cue` + oracle-generated `.json` covering all
   five shapes plus a nested struct, byte-matched by `check_export_fixtures`.

### Verify

`lake build` (84 jobs, theorems `rfl`-checked), `scripts/check-fixtures.sh` →
`fixture pairs ok` (internal-format `list_embedding_open` fixture unchanged — no
regression), `shellcheck scripts/check-fixtures.sh` clean.

---

## Completed Slice: Test/fixture reorganization (consolidation item 3, partial) (2026-06-17)

Purely organizational — no `.cue`/`.expected` byte changes, no theorem content changes,
no semantic behavior change. The verify gate (every fixture pair + theorem still passing
from new locations) is the proof. Breadcrumb:
`../notes/2026-06-17-test-reorg-landed.md` (note pruned 2026-06-19; in git history).

### Steps

1. `testdata/cue/` flat→subsystem subdirs. All 141 fixture pairs `git mv`'d (history
   preserved) into 11 subdirs by dominant subsystem: `numeric/` (23), `definitions/` (25),
   `structs/` (24), `refs/` (15), `builtins/` (14), `lists/` (13), `disjunctions/` (7),
   `multiline/` (6), `comprehensions/` (5), `manifest/` (5), `bounds/` (4). Each pair's
   `.cue` + `.expected`(+`.manifest.expected`) sit together under one subdir.
   `testdata/export/` and `testdata/modules/` left untouched.
2. `scripts/check-fixtures.sh` discovery made recursive: the six flat `*.cue`/`*.expected`
   globs (lean-port diff both directions, CLI-output, the two main pairing loops) replaced
   by `find "${fixture_dir}" -name '*.{cue,expected}' -type f | sort` walks reading into a
   `while`. Basenames changed from `${f##*/}` to the path-relative `${f#"${fixture_dir}/"}`
   so subdir structure round-trips into the generated dir with no collisions; the CLI-output
   stage `mkdir -p`s the per-subdir parent. The hardcoded `check_cli_behavior` sample moved
   to `numeric/additive_expressions.cue`. `cue fmt --check --files "${fixture_dir}"` already
   recurses — left as-is. shellcheck clean.
3. `Kue/FixturePorts.lean`: every `FixturePort.fileName` rewritten from `<stem>.expected`
   to the `<subdir>/<stem>.expected` relative subpath (142 entries); `writeFixturePort` now
   `createDirAll`s the path's parent before writing so the subdir layout round-trips into
   the generated dir.
4. `Kue/Manifest.lean` (3f): `manifestFieldsWithFuel`'s `_ =>` catch-all over `FieldClass`
   replaced by explicit arms — `.field _ _ .regular` / `.field _ _ .optional` (non-output,
   skip) and `.letBinding` (skip), after the existing `.field false false .regular` (emit)
   and `.field _ _ .required` (incomplete). A new `Optionality` rung or `FieldClass` ctor
   now breaks the build at the emission site instead of silently being treated as
   non-output. Behavior unchanged (build + fixtures green).

### Deferred to a follow-up (still queued under item 3)

- Oversized-module splits (3d): `FixturePorts.lean` (2293), `FixtureTests.lean` (1033),
  `BuiltinTests.lean` (735) by family. Pure test-file moves, no behavior — deferred because
  splitting the single `def fixturePorts` list literal / interleaved theorem blocks requires
  re-emitting fragments with exact comma/bracket boundaries, and this session's shell-output
  filter was non-deterministically truncating listing output (the CLAUDE.md flip-flop),
  making mechanical text surgery unverifiable mid-stream. The subdir reorg already shrinks
  the navigation surface.
- `Field` tuple→`structure` (3e, ~95 sites) and base64-out-of-`Json` (3a) — independent
  mechanical sub-tasks, left for their own slices.

### Verify

`lake build` (84 jobs, all relocated theorems re-checked), `scripts/check-fixtures.sh` →
`fixture pairs ok` (141 pairs from new locations; export + module stages byte-identical;
pure renames confirmed — `git diff -M` shows zero content lines changed),
`shellcheck scripts/check-fixtures.sh` clean.

## Completed Slice: boundConstraint Fold + Canonical Conj Sort

Goal (plan authoritative items 1 + 2a): two paired type-system-first refactors, both
**behavior-preserving** — fold the four parallel integer-bound constructors into one
parameterized constructor, and canonicalize `.conj` member order so meet is commutative on
the canonical form. The decimal/number-domain bound *semantics* change (item 2b) is
explicitly NOT in this slice.

### Steps

1. `Kue/Value.lean`: add `inductive BoundKind = ge|gt|le|lt` with helpers
   `lower`/`strict`/`symbol`/`rank`/`admits`, and replace the four
   `intGe/intGt/intLe/intLt` constructors with one `boundConstraint (bound : Int) (kind :
   BoundKind)`. The shape is chosen extensible toward 2b (widen `bound` to `Decimal`, add a
   domain tag) without reshaping the meet/format/order arms.

2. `Kue/Lattice.lean`: collapse the `meetIntGe/Gt/Le/Lt`/range-prim family into
   `meetBoundPrim` (one `BoundKind.admits` comparator) + `meetRangePrim`; collapse the
   pairwise bound-meet arms into `meetTwoBounds` (`tightenSameSide` for same-side bounds,
   `rangeFeasible` + canonical `lower & upper` conj for opposite sides). `join` to one
   same-kind-widens arm. Add the canonical conj sort: `conjMemberKey` (kind by `kindRank`,
   then bounds by `(BoundKind.rank, limit)`, then `notPrim` by excluded-prim string, then
   `stringRegex` by pattern length-then-string, then residual) + `conjKeyLe` +
   `sortConjMembers`, applied in `meetConjValueWith`'s re-wrap.

3. `Kue/Order.lean`: `boundSubsumesBound` (same-comparator-only, matching the pre-fold
   arms); `Kue/Format.lean`: one `boundConstraint` arm using `BoundKind.symbol`;
   `Kue/Parse.lean`: `parseIntBoundValue` takes a `BoundKind`; `Kue/Manifest.lean`,
   `Kue/Eval.lean` (`valueTag`, renumbered contiguous), `Kue/Examples.lean` + all test refs
   migrated.

4. Tests: every existing bound/conj theorem migrated to `boundConstraint`/`BoundKind` with
   **identical values** (no value changed; no `rfl`→`native_decide` switch needed). Added
   commutativity theorems in `BoundTests.lean`: bound-pair, strict-pair, kind+bound, 3-way
   conj, bound+notPrim, plus a canonical-member-order check — all `native_decide` over the
   `==`/`= true` BEq form (`Value` has `BEq`, not `DecidableEq`).

### Verify

Coverage of the ~130 migration sites was established by **removing the old constructors
entirely and driving `lake build` to green** (the compiler errors on every unmigrated
site; iterate until clean) — robust against the session's flaky output filter. `lake
build` (84 jobs), `scripts/check-fixtures.sh` → `fixture pairs ok` (**no `.expected` file
changed** — the canonical sort matched cue's existing kind-first display order in every
observable fixture, so behavior-preserving held end-to-end), `shellcheck
scripts/check-fixtures.sh` clean.


## Completed Slice: Decimal/Domain-Tagged Bound Semantics (item 2b)

Closed the last known bound divergence: a bare `>0` is now a *number* bound (admits both
int and float, matching cue), decimal bound literals parse, and `int & >0` stays int-only.

### What changed

1. `Kue/Value.lean`: `boundConstraint` widened from `(bound : Int) (kind : BoundKind)` to
   `(bound : DecimalValue) (kind : BoundKind) (domain : NumberDomain)`. New `NumberDomain =
   number | int | float` (a proper sum — `kind`/`admitsKind`/`narrow`/`rank` helpers).
   `BoundKind.admits` now compares `DecimalValue`s via `decimalLeValues`/`decimalLtValues`
   (exact base-10 rational order, no float rounding). To let `Value` carry a `DecimalValue`,
   moved the decimal struct + its parse/compare/format helpers (`DecimalValue`, `evalPow10`,
   `maxNat`, `scaleDecimalNumerator`, `decimalCompare/Eq/Lt/LeValues`, the
   `parseDecimalText` chain, `trimDecimalZerosWith`→`formatFiniteDecimal`,
   `decimalFromPrim?`) from `Decimal.lean` into `Value.lean`; `Decimal.lean` keeps the
   arithmetic/division layer and re-uses them via the existing `import Kue.Value`. Added
   `intDecimal`, `formatBoundLimit`.

2. `Kue/Lattice.lean`: `meetBoundPrim`/`meetRangePrim` gate on the bound's `domain`
   (`domain.admitsKind (Prim.kind prim)`) then decimal-compare; `tightenSameSide`/
   `rangeFeasible`/`meetTwoBounds` over decimal limits (`meetTwoBounds` also narrows the two
   domains). `meetKindWithIntBound` → `meetKindWithBound`: `int`/`float` retain the kind
   conjunct (the load-bearing guard) WITHOUT narrowing the bound's domain — leaving the
   bound at `number` keeps meet commutative (a pairwise-reduced range can't narrow every
   member uniformly, and need not: the kept kind conjunct guards them all). `number` drops.
   `conjMemberKey`/`conjKeyLe` → `conjMemberLe` (a direct value comparator: bounds of equal
   kind compare by `decimalLeValues`, so different scales order correctly). `join` bound arm
   over decimals + domain. Removed now-dead `minInt`/`maxInt`.

3. `Kue/Parse.lean`: `parseIntBoundValue` → `parseBoundValue`, parses the limit via
   `parseDecimalText` (so `>0.5`/`>-1.5`/`<3.14` parse), domain defaults to `number`.
   `Kue/Format.lean`: bound arm prints `kind.symbol ++ formatBoundLimit bound`.
   `Kue/Order.lean`: `boundSubsumesBound` over decimals; the `.boundConstraint .prim` arm
   gates on `domain.admitsKind` + decimal-compares. `Kue/Manifest.lean`, `Kue/Eval.lean`
   (`valueTag`) + all test/example refs migrated (`.boundConstraint N kind` →
   `.boundConstraint (intDecimal N) kind .number`).

4. Tests/fixtures: 7 new `BoundTests.lean` theorems (bare-bound-admits-float,
   int-bound-rejects-float, float-bound-rejects-int, decimal-bound admits/rejects, decimal
   format, negative-decimal bound). 3 new fixtures (`bounds/number_bound_float` `>0 & 1.5`
   → `1.5`, `bounds/decimal_bound_float` `>0.5 & 1.0` → `1.0`, `bounds/number_range_float`
   `>=0 & <=10 & 5.5` → `5.5`), all cue-oracle-confirmed (v0.16.1). Pre-2b int-domain
   expectations (e.g. `int & >0`) left at `.number` domain — unchanged in value, since the
   kind conjunct (not the bound domain) does the narrowing.

### Verify

`lake build` (84 jobs), `scripts/check-fixtures.sh` → `fixture pairs ok` (**no existing
`.expected` changed** — no committed fixture exercised the over-strict bare-bound path;
the 3 new fixtures are net-new), `shellcheck scripts/check-fixtures.sh` clean. Every
probed oracle case matches cue v0.16.1 via the kue CLI.

---

## Completed Slice: `kue export -e <expr>` Expression Selector

**Intended behavior:** `kue export -e <path> <file>` (or `--expression`) evaluates the
input, selects the dotted field path from the root, and exports just that value (no
`{name: …}` wrapper) — byte-matching `cue export -e` for both JSON (default) and `--out
yaml`. Works in file mode and stdin mode. Closes Phase-B-audit item 1, the
highest-leverage real-file export unblock.

### Changes

1. `Kue/Cli.lean`: `ExportOpts` gains `expr : Option String`. `parseExport` gains a fourth
   curried arg and arms for `-e <v>` / `--expression <v>` (each `-e`/`--expression` with no
   value → `.error "missing value for -e"` / `…--expression`). `parse`'s `export` dispatch
   passes the new `expr := none`. Export help text documents the flag. `parse` stays
   total/exhaustive.

2. `Kue/Runtime.lean`: `lookupField?` (struct-variant field lookup distinguishing absence
   from presence, reusing `findEvalField`); `selectExprPath` walks the path, calling
   `resolveAndEval` between segments so a nested field's refs bind before the next lookup,
   and errors `reference "<seg>" not found` on a missing segment; `parseExprPath` splits on
   `.` and rejects empty segments (malformed path → `invalid -e expression`);
   `exportValueSelecting` ties parse+select+`exportValue` together.

3. `Main.lean`: `exportBoundValue` routes a bound value through `exportValueSelecting` when
   `opts.expr` is set, else the unchanged `exportValue`. `runExport`'s stdin path inlined to
   `parseSources`/`checkSourcePackageNames`/`mergeSourceValues` so the selector applies to
   the stdin root too (the whole-file stdin behavior is byte-identical when no `-e`).

4. Tests/fixtures: 7 new `CliTests.lean` theorems (`-e`/`--expression` short+long, with
   `--out yaml`, stdin, two missing-value errors). New export fixture
   `testdata/export/select_common.{cue,args,json,yaml}` — an `.args` sidecar convention
   (one arg per line, here `-e\ncommon`) passed by `check_export_fixtures` before
   `--out`/file; oracle outputs are `cue export -e common …`. New `check_cli_behavior`
   assertion: `-e nope_missing` exits non-zero with a "not found" stderr diagnostic.

### Scope / deferrals

Dotted field paths only (`common`, `a.b.c`). Deferred (each a clean later add): index/slice
selectors (`a[0]`), repeated `-e` → multi-doc output, arbitrary CUE expressions as the
selector. Recorded in compat-assumptions.

### Verify

`lake build` (84 jobs), `scripts/check-fixtures.sh` → `fixture pairs ok` (no existing
fixture changed; net-new `select_common` pair + CLI-behavior assertion),
`shellcheck scripts/check-fixtures.sh` clean. Oracle (cue v0.16.1): `-e common`,
`-e common.nested.a.b`, scalar `-e common.name`, `--out yaml`, missing→exit1,
incomplete→exit1, stdin — all match. **Real prod9 (read-only):**
`hatari/infra/apps/common.cue` `kue export -e common` and `-e common.domains` JSON-match
`cue` exactly. Pre-existing (non-`-e`) YAML divergence noted: kue quotes dotted-numeric
strings (`"34.142.159.249"`) where cue emits bare; JSON matches.

## Completed Slice: YAML Scalar Over-Quoting Fix (cue bare/quoted parity)

The `-e` slice's noted divergence: kue's YAML serializer quoted dotted-numeric strings
(IP `34.142.159.249`, semver `1.2.3`, CIDR `10.0.0.0/8`, image tag `nginx:1.25`) where
`cue export --out yaml` emits them **bare**. JSON matched; only YAML over-quoted. For k8s
YAML (full of IPs/versions/CIDRs) byte-parity matters. Diagnosed oracle-first against
`cue` v0.16.1 + the actual Go sources (read-only mod cache).

### Root cause and the real rule

cue's YAML quoting is the **union of two layers**, both reproduced exactly:

1. **cue `internal/encoding/yaml.shouldQuote`** — force double-quote when the string is in
   a fixed YAML-1.1 legacy-token set (`y/Y n/N t/T f/F yes no on off true false null ~`
   + `.inf/.nan` case variants — the *enumerated* set, NOT general case-insensitivity) OR
   matches a conservative date/time/base60/`0x`-hex regex
   `^[-+0-9:. \t]+([-:]|[tT])[-+0-9:. \t]+[zZ]?$ | ^0x[a-fA-F0-9]+$`. This regex quotes
   loosely-shaped tokens go-yaml's resolver would not (`2024-13-40` quotes despite being
   an invalid date — the regex is not range-checked).
2. **go-yaml v3 emitter `stringv`** — when cue leaves the style unset, the emitter still
   quotes anything its resolver reads back as a non-string: a real int/float
   (decimal/`0b`/`0o`/`0x`, `_`-separated), the bool/null token map, YAML-1.1 old bools
   (`yes/no/on/off`), or base60 floats.

A **multi-segment token** (`34.142.159.249`, `1.2.3`, `10.0.0.0/8`, `nginx:1.25`,
`1.2.3.4`) is none of these — not a number (multiple dots/colons fail every parse), not a
date (a `/` or letter breaks the all-`[-+0-9:. \t]` body), not a token — so it stays bare.
The old `yamlLooksNumeric` accepted any digit/dot/underscore run and wrongly quoted them.

### Changes (`Kue/Yaml.lean`, serializer-only)

Replaced `yamlLooksNumeric` + the lowercase-reserved-word path with a total
`wouldParseAsNonString : String → Bool` = the precise union: `yamlReservedWords` (token
set, exact case variants) ∨ `yamlCueShouldQuote` (`yamlCueDateLike` hand-NFA for the date
regex + `yamlCueHexLike`) ∨ `yamlStyleFloat` (hand-NFA for go-yaml's float regex, on the
underscore-stripped form — subsumes decimal/legacy-octal ints since any `[0-9]+` parses as
a float) ∨ `yamlRadixInt` (`0x`/`0o`/`0b`) ∨ `yamlBase60Float` (go-yaml `isBase60Float`).
Removed now-dead `yamlAsciiLower`/`yamlLowerString`. Single/double-quote selection for
genuinely-unsafe cases (`yamlNeedsSingleQuote`) unchanged. JSON (`Json.lean`), internal
`formatValue`, and non-YAML paths untouched. No `partial`; every branch is structural.

### Tests / fixtures

38 new `YamlTests.lean` theorems (`native_decide`): infra tokens now bare (IP, semver,
CIDR, image, multi-dot, `<<`, `inf`, `+inf`, `1e`, `0xZZ`); genuine numbers/bools/nulls/
dates/base60 still quoted. New `testdata/export/infra.{cue,yaml,json}` (IP/semver/CIDR/
image bare; `8080`/`true`/date quoted), oracle-matched. No existing `.expected`/theorem
needed flipping — the over-quoting was simply uncovered. A standalone 42-case Lean battery
checked `yamlScalarString` against the `cue` oracle: 0 failures.

### Verify

`lake build` (84 jobs) green; `scripts/check-fixtures.sh` → `fixture pairs ok` (net-new
`infra` pair); `shellcheck scripts/check-fixtures.sh` clean. **Real prod9 (read-only):**
whole-file `kue export --out yaml hatari/infra/apps/common.cue` is now **byte-identical**
to `cue` v0.16.1 (IPs bare) — `diff` empty.

## Completed Slice: tests-out reorg — `Kue/Tests/` (2c, tests-out part)

Purely organizational: separate engine from checks. Zero behavior/theorem-content change;
the verify gate (every theorem still elaborated under `lake build`, every fixture still
checked) is the proof.

### Changes

- `git mv` (history-preserving) of all 21 test/port modules `Kue/*.lean` → `Kue/Tests/*.lean`:
  `BoundTests BuiltinTests BytesTests CliTests EvalTests ExclusionTests FixturePorts
  FixtureTests FloatTests ListTests ManifestTests ModuleTests NormalizeTests NumberTests
  OrderTests ParseTests PresenceTests ResolveTests RuntimeTests StructTests YamlTests`.
  Their `namespace`/`module`-body code is unchanged (namespaces were already `Kue` /
  `Kue.Cli`, which are namespace decls, not file paths). Their `import` lines reference only
  engine modules (`Kue.Foo`), which did NOT move — so only `FixtureTests`'s
  `import Kue.FixturePorts` → `import Kue.Tests.FixturePorts` changed.
- `Kue/Tests.lean` (the pre-existing lattice-theorem module) repurposed as the aggregator:
  keeps its own theorems and now `import`s all 21 `Kue.Tests.*` modules.
- `Kue.lean`: ~20 direct test imports replaced by the single `import Kue.Tests`; 16 engine
  imports retained. Every test module stays transitively imported (`Kue → Kue.Tests → 21`),
  so no theorem silently stops elaborating.
- `scripts/write-fixture-ports.lean` and `scripts/check-fixtures.sh` rewired from
  `Kue.FixturePorts` → `Kue.Tests.FixturePorts` (`lake build` target + the `import`).
- 16 engine modules stay in `Kue/` (source-layering deferred per plan default).

### Scope / deferrals

Oversized-module splits (`FixturePorts` 2314 / `FixtureTests` 1033 / `BuiltinTests` 735)
DEFERRED — landed the SAFE-FAILURE partial (moves + rewire, fully green). `FixturePorts` is
one monolithic `def fixturePorts : List FixturePort` whose 145 entries are heavily
interleaved by subsystem (54 runs across 11 prefixes); a "by subsystem" split is brace-block
extraction + reorder of a generated list literal, not a contiguous cut — the interleaved-
surgery risk the slice flags, against a cosmetic-only payoff. Subsumes-3d remains open.

### Verify

`lake build` 84 jobs (unchanged vs baseline — file count unchanged since no split; every
`Kue.Tests.*` module shown elaborated in the build log → no silent test loss).
`scripts/check-fixtures.sh` → `fixture pairs ok` (145 fixture entries unchanged, no
`.expected` touched). `shellcheck scripts/check-fixtures.sh` clean.

---

## Completed Slice: base64 out of `Json.lean` → `Kue/Base64.lean`

Plan item 3a. Behavior-preserving consolidation: base64 is not JSON, so its defs no longer
live in `Json.lean`.

### Intended behavior

Identical base64 output to before — pure code move, no logic touched. `base64Encode`
(standard padded RFC 4648 / Go `base64.StdEncoding`) and its `base64Alphabet` table now live
in `Kue/Base64.lean`, a leaf module that imports nothing (depends only on
`List UInt8`/`Char`/`Array`/`String`). It sits at the bottom of the layer graph, below
`Manifest`/`Json`/`Yaml`/`Builtin`, so no import cycle is possible.

### Changes

- **New `Kue/Base64.lean`** — `base64Alphabet` + `base64Encode`, verbatim from `Json.lean`.
  No Kue imports.
- **`Json.lean`** — defs removed; added `import Kue.Base64`. `manifestPrimToJson`'s
  `.bytes` arm (bytes → base64 JSON string) unchanged.
- **`Yaml.lean`** — added explicit `import Kue.Base64` (bytes scalar uses `base64Encode`).
- **`Builtin.lean`** — added explicit `import Kue.Base64` (`base64.Encode` builtin).
- **`Kue.lean`** — added `import Kue.Base64` to the umbrella.
- **`Module.lean`** — untouched; its `encoding/base64` is a builtin-import *string* in the
  recognized-import list, not a call into `base64Encode`.

### Verify

`lake build` → 86 jobs, success. `scripts/check-fixtures.sh` → `fixture pairs ok` (no
`.expected` touched; base64/json/yaml fixtures — `base64_encode`, `encoding_infra_chain` —
unchanged). `shellcheck scripts/check-fixtures.sh` clean.

---

## Completed Slice: Linux `cacheRoot` default (per-OS user cache)

Plan item 4 (portability). The cross-module extract-cache root (B3c) fell back to the macOS
`~/Library/Caches/cue` on every OS absent `$CUE_CACHE_DIR`/`$XDG_CACHE_HOME`, so a Linux
dev/CI with neither set silently missed the cache and cross-module imports failed to resolve.

### Intended behavior

Match Go's `os.UserCacheDir` (what `cue` uses): `$CUE_CACHE_DIR` wins; else
`$XDG_CACHE_HOME/cue`; else the per-OS user cache — macOS `~/Library/Caches/cue`, other Unix
`~/.cache/cue`. The two env-var branches were already cross-OS-correct and are unchanged.

### Changes

- **`Module.lean`** — new pure `cacheDirFor (cueCacheDir xdgCacheHome home : Option String)
  (isOSX : Bool) : System.FilePath` holds the full precedence + per-OS branch. `cacheRoot`
  is now a thin IO wrapper: read the three env vars + `System.Platform.isOSX`, hand them to
  `cacheDirFor`. OS detected via Lean's `System.Platform.isOSX` (compile-time extern `Bool`);
  `isOSX` is opaque so it never reduces under `native_decide`, but the pure helper takes it
  as an explicit argument, so theorems pass literal `true`/`false`.
- **`Tests/ModuleTests.lean`** — 5 `native_decide` theorems: `CUE_CACHE_DIR` verbatim (wins
  over XDG/HOME/OS); `XDG_CACHE_HOME/cue` over per-OS fallback; macOS fallback; Linux
  fallback (the bug); missing-`HOME` → `/.cache/cue` (no crash; `FilePath.mk "" / ".cache"`
  normalizes to `/.cache`).

### Verify

`lake build` → 86 jobs, success. `scripts/check-fixtures.sh` → `fixture pairs ok` (module
fixtures override `CUE_CACHE_DIR`, so unaffected). `shellcheck scripts/check-fixtures.sh`
clean.

---

## Completed Slice: `Field` tuple → `structure` (consolidation 3e)

Goal: replace the positional triple `abbrev Field := String × FieldClass × Value` with a
named `structure` so projections are explicit and misindexing (`.2.1`) is impossible.
Type-system-first tightening per the repo philosophy; purely representational, zero
behavior change.

### Intended behavior

No behavior change. `Field` becomes `structure Field where label : String; fieldClass :
FieldClass; value : Value`, defined **mutually** with `Value`. The mutual block is forced:
`Value`'s struct-bearing constructors (`struct`/`structTail`/`structPattern`/
`structPatterns`/`embeddedList`/`structComp`) carry `List Field`, and the codebase already
typed dozens of signatures as `List Field`; once `Field` is a structure, `List Field` is no
longer defeq to `List (String × FieldClass × Value)`, so `Field` must be visible to
`Value`. Derived `Repr, BEq` (the only instances the tuple gave `Value`/`Field`) are
preserved via `deriving instance Repr, BEq for Value, Field` after the mutual block, so
`Value`'s `==`/`Repr` stay byte-identical — every `native_decide`/`rfl` theorem and every
fixture passes UNCHANGED, with **no** `rfl`→`native_decide` switch required.

### Changes

- **`Value.lean`** — `Value` wrapped in a `mutual` block with a new `structure Field`; the
  six struct-bearing constructors switched `List (String × FieldClass × Value)` → `List
  Field`; `deriving instance Repr, BEq for Value, Field`. The hand-written accessors
  `Field.label`/`fieldClass`/`value` are now the structure's auto-generated projections
  (so `Field.label field` still resolves); `Field.ignoresClosedness` and `Field.regular`
  rewritten against the projections / record syntax.
- **Engine + serializers** (`Eval`/`Parse`/`Resolve`/`Normalize`/`Lattice`/`Module`) —
  field tuple literals `(l, c, v)` → `⟨l, c, v⟩`; `Module`'s positional reads
  (`f.fst`/`f.snd.snd`) → `f.label`/`f.value`; two local `List (String × FieldClass ×
  Value)` signatures in `Lattice` → `List Field`. Non-Field tuples (`Mark × Value`
  disjunction alternatives, `Nat × List Field` frames, `Value × Value` pattern pairs,
  manifest `String × Value` output) left untouched.
- **Tests + examples** (`Examples`, `Tests`, 14 `Tests/*`) — ~60 struct-field tuple
  literals `("a", .regular, …)` → `⟨"a", .regular, …⟩` (a balanced-paren rewriter handled
  the multi-line and `.field _ _ _`-classed forms). No `.expected` fixture changed.

### Verify

`lake build` → 86 jobs, success (all theorems elaborate + pass; derived `BEq`/`Repr`
byte-identical confirmed by the suite). `scripts/check-fixtures.sh` → `fixture pairs ok`,
unchanged. `shellcheck scripts/check-fixtures.sh` clean.

---

## Completed Slice: Package-Dir Merge at the Entry (plan item 5)

Goal: multi-file-package apps (real `infra/apps/*.cue`, whose definitions span sibling
files in one package directory) must evaluate/export. The gap was at the IO entry only:
`loadFileBound` loaded a single file with no sibling merge, while `loadPackage` already
performed the full same-package meet-merge for *imported* packages.

### Oracle (cue v0.16.1)

- `cue export ./apps` (dir arg) merges all same-package `*.cue` siblings — resolves
  cross-file references. `cue export apps/argocd.cue` (bare file arg) does **not** merge —
  errors `reference "…" not found` on a sibling-defined symbol. So **the directory is the
  package unit, not the file.**
- `cue export -e <app> ./apps` = merge then field-select.
- A directory containing two differing named packages errors `found packages "a" and "b"`.
- A no-package-clause file evaluates standalone (`{}` / its fields).

### Steps

1. `Kue/Module.lean`: add `loadPackageDir` (discover module root + deps, then reuse
   `loadPackage ctx [] dir` for the same-package sibling merge — no duplicated merge logic)
   and `loadEntry` (branch on `System.FilePath.isDir`: directory ⇒ `loadPackageDir`,
   file ⇒ `loadFileBound` unchanged). `loadFileBound` doc clarified: it loads one file with
   no sibling merge, matching cue's bare-file contract.
2. `Main.lean`: route `runEvalFile` and `runExport`'s file branch through `loadEntry`
   instead of `loadFileBound`. Stdin and bare multi-file-arg paths untouched.
3. Fixture `testdata/modules/package_dir/`: a `subpaths` fixture whose subpath is the
   `apps` *directory* (common.cue defines `common`, portal.cue defines `portal` referencing
   `common` — the real-world distinct-top-level-fields shape). `expected.apps` is the
   `cue export --out json ./apps` oracle output, byte-matched.

### Scope finding

**Contained-reuse, not a redesign.** No package abstraction, no Cli change — the existing
file-arg positional already accepts a directory; the only change is the `isDir` branch at
the IO boundary. Single-file/stdin entry byte-unchanged (cue's own file-vs-dir contract
means a lone unique-package file merges only itself).

### Divergence note (pre-existing, out of scope)

cue interleaves fields for `x: ref & {own}` with the *own* fields first (`name` before the
referenced `replicas`/`image`); kue's `meet` orders the left struct first. This is a
single-file `meet`-ordering divergence independent of package merge — the fixture avoids it
by using distinct top-level fields per file.

### Verify

`lake build` → 86 jobs, success. `scripts/check-fixtures.sh` → `fixture pairs ok` (new
`package_dir` fixture green, all single-file fixtures unchanged). `shellcheck
scripts/check-fixtures.sh` clean. Real prod9 (read-only): `kue export -e portal <hatari
infra/apps>` now descends the whole package and reaches import resolution, surfacing the
clean B3d deferral on `prodigy9.co/defs/packs` — the merge is unblocked; next blocker is
the registry/dep-table fetch (item 6).

---

## Diagnosis Slice: Real-App Eval Blocker — Cross-Package Def-Meet (DEFERRED, no code)

Goal: find the ACTUAL current real-app eval blocker (post the import-resolution and
`[...]`/`[string]:`/presence/lazy-resolution/bound fixes), reduce it, oracle-diagnose, and
fix the construct — or, if deep, land a precise diagnosis breadcrumb (safe-failure path).

### Finding

Real prod9 apps (`kue export -e <app> <infra/apps>`, READ-ONLY) no longer hit a fast
`conflicting values`; they now **time out** (CPU-bound, 30–40s) where cue exports in <1s.
Bisection split the gap into TWO independent deep blockers:

1. **Cross-package def-meet laziness (correctness).** `pkg.#Def & {use-site}` evaluates the
   def body's own sibling/`Self` self-references prematurely — in the imported def's frame,
   before the use-site fields unify in. Minimal repro (2-package module): `parts.#M: {#name:
   string; out: #name}` + `t1: parts.#M & {#name: "keel"}` → kue `incomplete value: string`,
   cue v0.16.1 `{"out":"keel"}`. **Same-package is fine** (2c.2 lazy-conj fires). Root
   cause: `conjStructOperand?` deliberately refuses depth>0 operands (documented safety
   boundary), and `pkg.#Def` is a depth>0 selector into a hidden import binding, so the
   conjunction falls to eval-then-`meet`, which collapses the def body first. DEEP: a safe
   fix needs a frame-carrying deferral (closure/thunk Value, or a selector-into-import
   special case in the `.conj` arm) — out of 2c.2's flat-splice scope, which excluded
   depth>0 because the def's own cross-package refs (e.g. `attr.#Metadata` embed) would
   mis-resolve under a flat splice.
2. **Eval fan-out / perf hang (separate).** `defs.#Deployment`/`#ServiceAccount` alone burn
   30–40s CPU to timeout though their reduced shapes are instant — fan-out scaling with def
   size (the `Self.#components.X` re-eval the `EvalKey` memo comment names). Profile-first.

### Decision

No engine change. Both blockers are architectural; per the slice brief's safe-failure path,
this slice commits the diagnosis + reduced repros + recommended approach. Land blocker 1
(gating correctness bug, crispest repro) and blocker 2 (perf) as separate future slices.
When 1 lands, add `testdata/modules/crosspkg_defmeet/` pinning oracle JSON (the
module-fixture harness has no expected-failure mode, so the pin can't precede the fix).

### Artifacts

- Breadcrumb: `docs/notes/2026-06-17-realapp-eval-crosspkg-defmeet-diagnosis.md` (full
  repros, root cause, recommended approach for both blockers).
- `docs/spec/plan.md` next-work list + `docs/spec/compat-assumptions.md` eager-def-meet
  section updated with the cross-package variant and the perf blocker.

### Verify

`lake build` → success (no code touched). `scripts/check-fixtures.sh` → `fixture pairs ok`
(no fixture change). `shellcheck scripts/check-fixtures.sh` clean. Behavior-preserving by
construction — docs-only.

## Completed Slice: Loader Robustness — missing-file diagnostic + crossmod_nodeps pin

Goal: two cheap, behavior-safe loader items off the non-fork tail (NOT the surfaced
Value-model fork). (A) clean diagnostic for a missing file/dir arg on `export`; (B) a
self-contained regression fixture pinning the deps-less-module-imports-its-own-subpackage
resolution.

### Steps

1. **Item A — export missing-file diagnostic.** `runExport`'s file branch in `Main.lean`
   called `Kue.loadEntry path` bare, so a missing path threw an uncaught IO exception (ugly
   stack). `runEval` already wrapped it in `.toBaseIO`. Mirrored that: wrap in `.toBaseIO`,
   match `.error ioError` → `kue: cannot read <path>: <reason>` + exit 1, with the loader's
   own `.error message` still surfacing as `kue: <message>`. Both eval and export, file and
   missing-directory args, now give the clean diagnostic (both route through `loadEntry`).
   Caught at the IO boundary (not a `pathExists` guard) so mid-load read failures are
   covered too and the pure loader stays read-then-fail. Success paths byte-identical.

2. **Item B — `testdata/modules/crossmod_nodeps/`.** App `example.com/app` deps-on
   `example.com/lib@v0.1.0`; the lib module ships an empty `deps` table yet imports its OWN
   `example.com/lib/sub` subpackage; the app imports both `lib` and `lib/sub`. Self-contained
   committed `_cache/mod/extract/example.com/lib@v0.1.0/` (the `check_module_fixtures` stage
   points `CUE_CACHE_DIR` at it — never touches the real cue cache). `expected` is the
   byte-for-byte `cue export --out json` oracle (cue v0.16.1, `CUE_OFFLINE=1`). All cue files
   `cue fmt`-clean (the harness fmt-checks them). Concrete values only — deliberately steers
   clear of the cross-package def-meet bug (Value-model fork, surfaced to chakrit) so the
   fixture pins *resolution*, not eval.

3. **Theorems.** Two `native_decide` pins in `Kue/Tests/ModuleTests.lean`: the app→lib
   `resolveCrossModule [{example.com/lib, v0.1.0}] "example.com/lib/sub"` hop and the
   deps-less lib→sub `resolveImportSubpath "example.com/lib" "example.com/lib/sub" = some
   "sub"` hop.

### Verify

`lake build` → success (new theorems compile). `scripts/check-fixtures.sh` → `fixture pairs
ok` (crossmod_nodeps export matches oracle). `shellcheck scripts/check-fixtures.sh` clean.
Manually: `kue eval /no/such.cue` and `kue export /no/such.cue` both print `kue: cannot read
…` + exit 1 (no stack), as does a missing-dir arg.

---

## Completed Slice: Value.closure constructor (frontier #1, slice 1 — closure-ctor)

Goal: introduce the env-carrying `Value.closure` thunk and wire every exhaustive consumer
inertly, so the type change lands with ZERO behavior change — the foundation for the
cross-package def-meet fix (`parts.#M & {#name:"keel"}` → `out:"keel"`). chakrit-approved
churn; full slice sequence is `plan.md` "Value.closure work plan".

### Intended behavior

- New constructor `Value.closure (capturedEnv : List (Nat × List Field)) (body : Value)`
  in `Value.lean`. `capturedEnv` is *defeq* to `Eval.Env` (`abbrev Env := List (Nat ×
  List Field)`), so the eval layer threads it with zero coercion while `Value.lean` stays
  Kue-import-free (a closure could not carry an Eval `Frame` — that inverts the import
  graph; inlining the env as base-layer data is the layering-safe shape). Derived
  `Repr`/`BEq` extend automatically; the captured ids carry the "independently-built
  frames never falsely share" invariant into `BEq`.
- **Inert wiring** (the constructor has NO producer this slice — every new arm is dead
  code that only satisfies exhaustiveness): `valueTag` tag 29 (`Eval.lean`);
  `evalValueCoreWithFuel` passthrough (returns the closure unevaluated — forcing is slice
  2); `manifestWithFuel` → `.incomplete` (non-concrete); `formatValueWithFuel` prints the
  deferred body; `meetCore` → `.bottom` (unification is slice 4). The catch-all consumers
  (`subsumesWithFuel`, `normalize*`, Resolve, and `meetWithFuel`'s `meetCore` delegation)
  absorb it with no edit — the exhaustiveness checker confirmed the forced blast radius is
  exactly those five functions.

### Tests

Seven pins in `Kue/Tests/EvalTests.lean`: `closure_beq_self`, `closure_beq_distinct_env`
(distinct captured ids ⇒ unequal), `closure_beq_distinct_body`, `closure_valueTag` (= 29),
`closure_eval_passthrough` (core eval returns it unchanged), `closure_manifest_incomplete`,
`closure_meet_bottom`. Value-result equalities use `== … = true` (Value derives `BEq`, not
`DecidableEq`, so bare `=` is undecidable for `native_decide`).

### Verify

`lake build` → 86 jobs, success. `scripts/check-fixtures.sh` → `fixture pairs ok` (all
fixtures byte-unchanged — behavior preservation proven). No shell touched.

## Completed Slice: Value.closure eval arm (frontier #1, slice 2 — closure-eval)

Goal: make `evalValueCoreWithFuel`'s `.closure` arm real — force the deferred body against
the lexical scope it captured, instead of the slice-1 inert passthrough. Still no producer
⇒ dead code, but this is the semantic anchor slices 3-4 target.

### Intended behavior

- `evalValueCoreWithFuel`'s `.closure capturedEnv body` arm now evaluates `body` under
  `capturedEnv` via `evalValueWithFuel fuel capturedEnv [] body` — **lexical, not dynamic,
  scope**: a closure resolves against its definition site, so the call-site `env`/`visited`
  are discarded. `capturedEnv` is defeq to `Eval.Env`, so it threads into the recursive
  eval with zero coercion. `visited` resets to `[]` because the call-site slot markers index
  call-site frames, not the captured ones (mirrors the depth>0 ref arm, which resets visited
  when crossing into an outer frame). `fuel` decrements `fuel+1 → fuel` exactly as every
  other arm — never dropped (LOAD-BEARING in `EvalKey`). At `fuel = 0` the closure degrades
  through the generic `| 0, value => pure value` arm: passes through unforced, no crash/loop.
- Termination unchanged: the recursive call is `evalValueWithFuel fuel …` at strictly lower
  fuel, fitting the existing `termination_by (fuel, 0, 0)`.

### Tests

Six pins in `Kue/Tests/EvalTests.lean` (replaced slice-1's now-stale `closure_eval_passthrough`,
which asserted the inert behavior this slice overturns):
- `closure_eval_forces_captured_binding` — body `.refId ⟨0,0⟩` under a captured frame whose
  slot 0 is `int 42` forces to `int 42` (the body sees `capturedEnv`).
- `closure_eval_empty_captured_env` — empty captured env, scope-free literal body → the
  literal.
- `closure_eval_nested_closure` — body is itself a `.closure` carrying its own frame; the
  outer force drives the inner force (nested-force pin).
- `closure_eval_lexical_not_dynamic` — call-site env binds slot 0 to `"callsite"`, captured
  env to `"captured"`; result is `"captured"` (lexical-scope proof — dynamic scope would
  pick the call-site binding).
- `closure_eval_fuel_exhaustion` — `fuel = 0` passes the closure through unevaluated (graceful
  degradation, no crash).
Value-result equalities use `== … = true` (Value derives `BEq`, not `DecidableEq`).

### Verify

`lake build` → 86 jobs, success (`EvalTests` built ⇒ all `native_decide` pins pass).
`scripts/check-fixtures.sh` → `fixture pairs ok` (zero fixture drift — dead-code from the
producer's view, no real-eval behavior change). No shell touched.

## Completed Slice: Value.closure producer (frontier #1, slice 3 — closure-producer)

Goal: the FIRST behavior-changing closure slice — emit `.closure capturedPkgEnv defBody` at
the import-selector path instead of eagerly evaluating an imported definition whose body
self-references, which collapses the self-ref before a use-site `meet` (slice 4) narrows it.
Gated strictly to stay byte-identical on every committed fixture. Design sub-spike in
`plan.md` "Value.closure work plan" → "Slice-3 design sub-spike". Folded in the Phase-A
`closure-env-sync-guard` tripwire.

### Trigger (empirically traced, not guessed)

The collapse: `parts.#M` is `.selector (.refId ⟨0,parts⟩) "#M"` — a depth-0 ref to the
hidden import binding, then a selector. `conjStructOperand?` has no `.selector` arm, so
`parts.#M & {…}` falls to the `.conj` eval-then-`meet` fallback, which evaluates `parts.#M`
*first* (the whole package struct, collapsing `out:#name`→`string`) before the `meet`. The
base is fully evaluated → intercepting after base-eval is too late.

Producer lives in `evalValueCoreWithFuel`'s `.selector (.refId id) label` arm, in the
`thisStructFieldIndex? = none` else-branch, BEFORE the eager `base`-eval. `importDefClosureBody?
env id label` looks up the UNEVALUATED binding for `id`; it returns the def's unevaluated
body iff ALL hold: (1) the binding is a `.struct pkgFields _`; (2) `pkgFields` has a field
`label` that is a definition (`fieldClass.isDefinition`); (3) that def body has a sibling
self-ref (`defBodyHasSiblingSelfRef` → `hasDepth0Ref`, a `refId ⟨0,_⟩` reachable without
crossing a frame-pushing node). On `some (pkgFields, defBody)` the arm emits
`.closure (pushFrame pkgFields env) defBody` — full id-stack captured; otherwise it takes
the eager path unchanged.

### Why behavior-preserving (the gate is the exact collapse set)

Condition 3 is the precise line: a self-ref-free def body (`#Widget`={name,size,enabled},
`#Box`, `#Mid`, `#Atom`, `#Name` — *every* committed `pkg.#Def & {…}` fixture) evaluates to
the same struct eager or deferred, so it MUST stay eager (slice 4 isn't done; a closure there
would `meet`→`.bottom` and drift). A self-ref def body (`#M`={#name,out:#name}) is exactly
what errors today (`incomplete value`), so deferring it regresses no GREEN fixture. NOT the
(a)-narrowed trap: `capturedEnv` is always the full `pushFrame pkgFields env`, so a real
`#ServiceAccount` (self-refs AND depth>0 `attr.#Metadata` embeds) gets the whole package env;
condition 3 gates only *whether to defer*. Same-package `#M & {…}` is a `.refId`, not a
selector → handled by `conjStructOperand?`/`lazyConjMergedFields`, never enters the selector
arm → structurally untouched. Verified: cross-pkg repro changes from `incomplete value` to
`bottom` (closure forced → slice-1 inert `meet`; not a committed fixture); same-pkg stays
`{"out":"keel"}`; all committed fixtures byte-identical.

### Env-defeq tripwire (Phase-A finding `closure-env-sync-guard`, folded in)

`example : (List (Nat × List Field)) = Env := rfl` next to the `Env` abbrev — a build-time
guard that `Value.closure`'s `capturedEnv` rep stays defeq to `Eval.Env`, so a future
`Frame`/`Env` shape change fails the build instead of silently desyncing the no-coercion
thread. The producer is the first code to build a `capturedEnv` from a real `Env` → natural
home.

### Tests

Seven `native_decide` pins in `Kue/Tests/EvalTests.lean` (white-box — closures aren't
user-visible until slice 4):
- `closure_producer_emits_on_selfref_def` — the trigger fires: `parts.#M` (self-ref body)
  → `.closure` with `capturedEnv = (0, pkgFields) :: useSiteEnv` and the UNEVALUATED `#M`
  struct as body.
- `closure_producer_skips_selfref_free_def` — `#Widget` (no self-ref) stays eager → the
  evaluated struct, NOT a closure (the committed-fixture shape).
- `closure_producer_skips_non_definition` — a regular (non-`#`) field with a sibling ref
  stays eager (only definitions defer).
- `closure_producer_captures_full_id_stack` — a depth-2 use-site env retains BOTH outer
  frames beneath the pushed package frame in `capturedEnv` (the anti-(a)-trap pin).
- `closure_producer_nested_struct_ref_not_sibling` — `hasDepth0Ref` stops at frame-pushers:
  a `refId ⟨0,0⟩` inside a nested struct is NOT a sibling self-ref (gate doesn't over-fire).
- `closure_producer_direct_sibling_ref_detected` — positive companion: a direct sibling ref
  IS detected.
Result equalities use `== … = true` (Value derives `BEq`, not `DecidableEq`).

### Verify

`lake build` → 86 jobs, success (the env-defeq `rfl` passes ⇒ defeq holds; `EvalTests` built
⇒ all pins pass). `scripts/check-fixtures.sh` → `fixture pairs ok` (every committed fixture
byte-unchanged — slice is behavior-preserving). No shell touched. No CUE divergence this
slice (the `parts.#M` case is a kue limitation, not a cue bug — cue is correct).

---

## Completed Slice: Value.closure meet (frontier #1, slice 4 — closure-meet)

Goal: THE behavior-changing unlock. A forced closure (a deferred imported definition, slice 3)
met with a use-site struct must SPLICE the use-site in as an extra conjunct of the def body
BEFORE evaluating, so `defs.#M & {#name:"keel"}` (where `#M = {#name:string, out:#name}` is an
imported def) finally resolves to `out:"keel"` matching `cue`, instead of `incomplete value`
(slice-3 inert-meet `.bottom`). See `plan.md` "Value.closure work plan" slice 4.

### Force point + splice

The `.conj` eval-then-`meet` fallback `none` branch (`Eval.lean`) is the ONLY site a closure
currently meets a struct. There `evalValuesWithFuel` yields `[.closure capEnv defBody,
.struct useSite]`; instead of the inert `foldl meet` (→ `.bottom`), `firstClosure?` extracts
the closure and `forceClosureWithConjunct fuel capturedEnv body useOperands` forces it with the
OTHER conjuncts' evaluated struct fields (`evaluatedStructOperand?`) spliced into the def body's
frame. `meet` stays pure (no `EvalM`) — the eval lives in Eval, not `Lattice.meet`.

The splice reuses the same-package conjunction merge machinery, factored to a new pure
`mergeConjOperands (operands : List (List Field × Bool)) : List Field × Bool` shared by
`lazyConjMergedFields` and the force. The def's own fields and the use-site's EVALUATED fields
become two conjuncts of one merged frame (layout fixed by first-occurrence, sibling refs
rebased, label collisions deferred to `.conj`, closedness folded), pushed onto `capturedEnv`
and evaluated once — so `#name` becomes `string & "keel" → "keel"` and `out:⟨0,0⟩` resolves to
`"keel"` while the def's own depth>0 cross-package refs still resolve against `capturedEnv`.
Use-site operands are evaluated FIRST at the call site, so their refs are already resolved →
splicing them never leaks use-site scope into the def frame and rebasing them is a no-op.

Cycle handling derived from FIRST PRINCIPLES (not by analogy to the depth>0 ref arm): a forced
closure is a fresh eval entry (`visited := []`), so the ordinary `slotVisited` machinery on the
pushed merged frame catches a self-referential captured binding → `.top`, no loop. `fuel` stays
in `EvalKey` (load-bearing). The non-struct-def-body and multi-closure cases fall back to
`meet` (honest `.bottom` on genuine conflict), preserving slice-3 behavior where the splice
doesn't apply.

### Two correctness fixes folded in (latent bugs slice 4 exposes)

- **Imported-def closedness.** `normalizeDefinitions` only normalizes the TOP value's own `#`
  fields (line `Normalize.lean:51` gates on `isDefinition`), never the hidden IMPORT binding's,
  so an imported def body kept `open_` and a forced cross-package def wrongly admitted use-site
  fields it doesn't declare. Fix: `importDefClosureBody?` runs the captured body through
  `normalizeDefinitionValueWithFuel normalizeFuel` to close it (`open_ := false`, recursive) at
  capture. (The two slice-3 producer pins were updated for the now-closed body.)
- **Open-def (`.structTail`) support.** The slice-3 gate (`defBodyHasSiblingSelfRef`) and the
  force only handled `.struct`, so an OPEN self-ref imported def (`...` → `.structTail` body)
  collapsed (`incomplete value`) even with no extra use field. Extended `defBodyHasSiblingSelfRef`
  and added a `.structTail` arm to `forceClosureWithConjunct` (splice use fields, rebase + eval
  the open tail).

### Tests

Seven new `native_decide` pins in `Kue/Tests/EvalTests.lean` (slice-4 section) + one committed
module fixture:
- `closure_meet_splices_use_site` — THE unlock: forcing `parts.#M & {#name:"keel"}` →
  `{#name:"keel", out:"keel"}` (closed body), NOT slice-3 `.bottom`.
- `closure_meet_conflict_is_bottom` — use-site narrows `#name` to a value the def's own `#name`
  rejects → field-local `.bottomWith primitiveConflict` on `#name` AND `out` (export rejects).
- `closure_meet_empty_use_site` — `parts.#M & {}` == `parts.#M` (zero spliced fields).
- `closure_meet_self_ref_terminates` — a `loop: loop` field (`refId ⟨0,1⟩` at its own slot)
  resolves to `.top` via `slotVisited`, no divergence/fuel-exhaustion; `out` still `"keel"`.
- `closure_meet_open_def_admits_extra` — open (`.structTail`) def + use-site extra field: the
  extra appears, `out` still narrowed, body stays open.
- `closure_producer_detects_structtail_sibling` — gate now fires on `.structTail` bodies.
- `testdata/modules/crosspkg_defmeet/` — committed regression module fixture
  (`defs.#M & {#name:"keel"}` → `{"t":{"out":"keel"}}`, `expected` = cue-oracle JSON), runs
  through the import-aware loader harness.
Result equalities use `== … = true` (Value derives `BEq`).

### Verify

`lake build` → 86 jobs success. `scripts/check-fixtures.sh` → `fixture pairs ok` (every
PRE-EXISTING fixture byte-unchanged + the new module fixture passes). `shellcheck scripts/*.sh`
→ clean. Oracle: edge battery EC2-EC10 byte-match `cue` v0.16.1 (`/Users/chakrit/go/bin/cue`);
EC1 (open def + use-site extra) matches in VALUE but differs in field ORDER (frontier #3, out
of scope — the committed fixture avoids it). No CUE divergence (cue is correct in every probed
case). No shell/env mutation; prod9 + cue cache read-only.

### Real-app + perf probe (read-only prod9)

Probed `infra/apps/cert-manager.cue` (`defs.#ClusterIssuer & {…}`, smallest) and
`infra/apps/argocd.cue` (`defs.#Secret`/`#ConfigMap`/`#TLSRoute & {…}`). Slice 4's unlock works
on its target shape (bare depth-0 sibling self-ref) — fast (0.016s) and cue-exact. But real
prod9 defs use `#Def: Self={ parts.#Metadata; … Self.#x … }` value-alias defs embedding
cross-package defs — a DIFFERENT shape slice 4 does not target. Real apps do NOT export
end-to-end: cert-manager → `bottom` in 11.7s, argocd → `bottom` in 55s (cue: ~0.22s, correct).
Two independent next slices fall out (recorded in `plan.md`): **A. `closure-realapp-selfalias`**
(correctness — the embedded cross-package def `parts.#Metadata` doesn't resolve through the
closure capture; a minimal embed+Self repro returns `incomplete` fast) and **B. `closure-perf`
/ frame-id-sharing** (frontier #2 — the super-linear blowup is NOW REACHABLE; provably NOT the
closure path, which is 0.016s, but the eager embed/Self-alias graph re-allocating frame ids).
Sequence A before B. Frontier #2 confirmed reachable.

---

## Completed Slice: Value.closure slice A (closure-realapp-selfalias)

Goal: make the real-app value-alias-def-embedding-cross-package-def shape resolve cue-exact —
the multi-operand / package-sourced-struct / nested-self-ref splice failures the Phase-A audit
(`1f76347`) scoped into slice A.

### Root cause (empirically traced, read-only `/tmp` repros, cue v0.16.1 oracle)

Facet (b)/(c) was NOT "package-sourced struct" — it was `.structComp`. A def that EMBEDS another
value (`#Def: { parts.#Metadata; #x; spec: #x }`) parses to a `.structComp` (embeddings live in
`structComp.comprehensions`), which the slice-4 gate, force path, and embedding-meet all dropped.
Worse, building the fix surfaced the ACTUAL real-app blocker: the slice-4 gate (`hasDepth0Ref`)
only flagged TOP-LEVEL sibling self-refs, but real defs reference hidden fields from DEEP nested
positions (`spec: acme: email: Self.#email` → `refId ⟨3,_⟩`) and from comprehension GUARDS
(`if Self.#staging`). Without detection the producer never defers → eager collapse.

### Behavior

Six sub-fixes, one commit (all targeted shapes cue-exact, every existing fixture byte-unchanged):
- **A.1 Gate** — `defBodyHasSiblingSelfRef` gains a `.structComp` arm.
- **A.2 Force `.structComp`** — `forceClosureWithConjunct` splices use-operands into the static
  fields, then meet-folds the embeddings (mirroring the `.structComp` eval arm); the final
  closedness is the UNION of the def's own labels and each embedding's labels (embedding widens
  the closed set, CUE semantics), applied once over the open meet result.
- **A.3 Multi-operand fold** — the `.conj` fallback force-splices EVERY closure operand against
  the SHARED use-operand set (`allClosures` + `nonClosureNonStructOperands`), replacing the
  first-closure-only `firstClosure?`/`dropFirstClosure`/`leftover`. `#M & #N & {narrow}` resolves.
- **A.4 Embedding-meet closure splice** — `meetEmbeddingsWithFuel` FORCES an embedding that
  evaluated to a `.closure` (with the host's fields spliced + body OPENED so the embed's
  closedness does not reject host siblings), instead of plain `meet → .bottom`. Fuel-decremented
  so the force/meet-embeddings mutual recursion is well-founded.
- **A.5 `.structComp` closedness** — `normalizeDefinitionValueWithFuel` closes the static portion
  of a `.structComp` def body (`open_ := false`) but leaves embeddings untouched (they union, not
  restrict).
- **A.6 DEEP/nested self-ref detection** — replaced `hasDepth0Ref` with `hasSelfRefAtDepth
  (depth)`: descends every frame-pusher incrementing `depth`, flags `refId ⟨depth,_⟩` (the def's
  own frame), and scans comprehension guard/source conditions at their enclosing depth. The
  single largest unlock for the real-app `Self={…}` shape.

### Tests (7 new `native_decide` pins + 1 committed module fixture)

`closure_producer_detects_structcomp_sibling`, `closure_producer_detects_structcomp_embedding_sibling`,
`closure_meet_structcomp_embed_splices` (embed splice: `spec:#x`→narrowed, embed `kind` unioned),
`closure_meet_multi_operand_fold` (`#M & #N & {narrow}`), `closure_meet_captured_frame_cycle_terminates`
(GENUINE capture-level cycle: a captured-frame binding refs back into the def → terminates,
replacing the weak depth-0-slot pin), `closure_producer_deep_nested_self_ref_detected`
(`refId ⟨2,_⟩` 2 frames deep), `closure_producer_comprehension_guard_self_ref_detected`
(self-ref in an `if` guard). Committed `testdata/modules/crosspkg_embed_selfalias/` — a cross-pkg
self-ref-embed def, single regular output (`spec: "hello"`) so byte-order parity (#3) does not
bite; oracle JSON+YAML byte-identical, closedness rejects undeclared use fields.

### Verify

`lake build` → 86 jobs. `scripts/check-fixtures.sh` → `fixture pairs ok` (every existing fixture
byte-unchanged + the new module fixture). `shellcheck scripts/*.sh` → clean. Oracle: every new
behavior byte-matches `cue` v0.16.1 in JSON and YAML on its target shape. No CUE divergence found
(cue correct in every probed case). prod9 + cue cache read-only; no env/tree mutation.

### Real-app verdict (read-only prod9 — the headline)

Slice A is cue-exact on every shape it targets (multi-closure, single-level embed, `Self={…}`,
deep nested self-refs, concrete-condition comprehension guards), verified by minimal repros. BUT
cert-manager / argocd STILL return `bottom` (cert-manager ~9.6s — perf wall also unresolved). The
real defs chain THREE FURTHER, independent correctness shapes slice A does not cover, each its own
slice (recorded in `plan.md`): **C. `closure-default-in-guard`** (a guard over a `bool | *false`
default disjunction doesn't resolve the default — orthogonal to closures, reproduces with no def;
smallest), **D. `closure-presence-test-selfref`** (`if Self.#ns != _|_` presence-tests over a
spliced self-ref, + `len()`), **E. `closure-embed-chain`** (a multi-level embed chain
`#Outer{#Mid{#Inner}}` collapses — the inner embed's `Self.#name` → `_|_` when the outer force
re-forces the nested embedded closure; the real `#ClusterIssuer → parts.#Metadata → attr.#Metadata`
is 3-level). Then **B. `closure-perf`**. Honest: the remaining real-app gap is BOTH correctness
(C/D/E) AND perf (B), not perf-only.

## Completed Slice: Value.closure slice C (closure-default-in-guard)

Goal: a comprehension/field guard over a marked-default disjunction (`bool | *false`)
must resolve the default and fire the guard, matching `cue`. Orthogonal to closures —
reproduces with no def at all (`x: bool | *false; if !x {…}`).

### Root cause (empirically traced, read-only `/tmp` repros, cue v0.16.1 oracle)

TWO coupled gaps, both about disjunction defaults in a concrete context:

1. **Operations did not distribute over disjunctions.** `evalBoolNot`/`evalAdd`/… hit their
   `_ => .unary …`/`.binary …` fallback when an operand was a `.disj`, leaving `!x` as
   `.unary .boolNot (.disj …)` and `x+1` as `.binary .add (.disj …) …`. CUE distributes:
   `op(a | *b)` = `op(a) | *op(b)`, preserving marks. So `!(bool | *false)` should become
   `bool | *true`, and `(int | *1) + 1` should become `int+1 | *2`. kue left them stuck →
   `incomplete`, while cue resolved the default (`!x → true`, `x+1 → 2`). This is general (also
   hit top-level `z: !x` and `y: x + 1`), not guard-specific.
2. **The guard test did not collapse a defaulted-disjunction condition.** `expandClausesWithFuel`
   compared `evaluatedCondition` against `.prim (.bool true)` directly; a `.disj` condition (the
   direct `if x` with `x: bool | *true`) never matched, dropping the body.

### Fix (reused existing default machinery; new code is distribution + one guard collapse)

- **Consolidated default-resolution into `Lattice.lean`** (the leaf where `flattenAlternatives`/
  `containsBottom` already live): moved `liveAlternatives`/`defaultAlternatives` out of `Manifest`
  into `Lattice`, refactored `normalizeDisj` onto `liveAlternatives`, and added
  `resolveDisjDefault? : List (Mark × Value) → Option Value` — the exact CUE collapse rule (unique
  marked default wins; else unique regular; else `none`). `Manifest`'s `.disj` arm now calls it
  (one shared definition of "what a disjunction collapses to in a concrete context").
- **`distributeUnary`/`distributeBinary`** (`Eval.lean`, just after `evalUnary`/`evalBinary`): map
  the op across `.disj` alternatives preserving marks (`combineMark` for binary cross-product),
  re-normalizing via `normalizeEvaluatedDisj`. The `.unary`/general `.binary` eval arms now call
  these. Non-default disjunctions stay multi-alternative → still `incomplete` (no over-resolution).
- **Guard collapse** (`expandClausesWithFuel`): a `.disj` condition is run through
  `resolveDisjDefault?` before the `.prim (.bool true)` test; non-`.disj` values pass through, a
  non-default disjunction returns `none` and the guard stays unsatisfied.

### Tests (8 new `native_decide` pins + 1 committed fixture)

`resolve_default_disj_picks_marked_default`, `resolve_default_disj_non_default_stays_unresolved`,
`resolve_default_disj_multiple_defaults_stays_unresolved` (pin `resolveDisjDefault?` directly);
`distribute_not_over_default_disj` (`!(bool|*false) → bool | *true`),
`distribute_add_over_default_disj` (`(int|*1)+1 → int+1 | *2`);
`eval_comprehension_guard_negated_default_disj_admits` (the real `if !x` shape),
`eval_comprehension_guard_direct_default_disj_admits` (`if x` with `*true`),
`eval_comprehension_guard_non_default_disj_drops` (over-resolution guard: a NON-default disjunction
in a guard STAYS unsatisfied). Committed `testdata/cue/comprehensions/default_in_guard.{cue,expected}`
(+ `FixturePorts` entry) — `staging: bool | *false` with `if !staging`/`if staging` guards; JSON
export byte-identical to cue.

### Verify

`lake build` → 86 jobs. `scripts/check-fixtures.sh` → `fixture pairs ok` (every existing fixture
byte-unchanged). `shellcheck scripts/*.sh` → clean. Oracle: every new behavior byte-matches `cue`
v0.16.1 (JSON). No CUE divergence (cue correct in every probed case, incl. non-default `(1|2)+10`
staying `incomplete` and two-default `(int|*1|*2)+10` staying ambiguous — both reject, matching kue).
prod9 + cue cache read-only; no env/tree mutation.

### Real-app verdict (read-only prod9 — the headline)

C is cue-exact against the ACTUAL `#ClusterIssuer` default-in-guard shape: `#staging: bool | *false`
with `if Self.#staging`/`if !Self.#staging` inside a `Self={…}` closure now resolves byte-exact
(was `bottom` pre-C). cert-manager export still returns `bottom`, but the error has MOVED PAST C.
Probing the downstream blockers in isolation: **D (`closure-presence-test-selfref`) ALSO already
passes** — both `if Self.#ns != _|_` (presence-test over a self-ref) and `len(Self.#labels) > 0`
guards are cue-exact post-A/C, so D's scoped shapes need no dedicated slice. The live remaining
blocker is **E (`closure-embed-chain`)**: a 2-level embed chain (`#Outer{ #Inner & {…} }`, each a
`Self={…}` self-ref) still collapses to `bottom` in kue while cue yields `{iname, oname}`. Next
slice is E; the real `#ClusterIssuer → parts.#Metadata → attr.#Metadata` 3-level chain is what
still gates cert-manager. B (`closure-perf`, ~10s) remains downstream.

---

## Completed Slice: Value.closure slice E (closure-embed-chain)

Goal: a MULTI-LEVEL embedded-closure self-ref chain — a def that embeds a def that embeds a
def, each a `Self={…}` self-ref — must propagate a use-site narrowing through every embed level
instead of collapsing to `bottom`. The real shape is 3-level: `#ClusterIssuer → parts.#Metadata
→ attr.#Metadata`. 2-level repro pre-E: `#Outer{ #Inner & {#name: Self.#oname} } & {#oname:"z"}`
→ kue `bottom`, cue `{iname:"z", oname:"z"}`.

### Root cause (traced, read-only `/tmp` repros, cue v0.16.1 oracle) — THREE coupled gaps

The breadcrumb's "force doesn't recurse" framing was wrong. The real causes:

1. **Closedness leak (E1).** The eager `.structComp` eval arm and the non-closure branch of
   `meetEmbeddingsWithFuel` `meet`-ed an embedded struct WITHOUT opening its closedness. A closed
   embed (`#Plain: {pval}`) embedded into a host carrying a regular field `x` rejected `x` via
   `applyStructClosedness` (`x ∉ {pval}`) → `bottom`. Slice A dodged this because its only embed
   (`parts.#Metadata`) was HIDDEN-ONLY (`ignoresClosedness`); any embed contributing a REGULAR
   field — the real chain's `aname`/`mname` — trips it. Minimal: `out: { #Plain; x: "z" }` bottomed.
2. **Bare-ref / nested-ref producer gap (E2a).** `conjStructOperand?`'s lazy-merge (which splices
   a use-site narrowing into a def's frame) has no `.structComp` arm at ANY depth, and is
   depth-0-only for `.struct`/`.structTail`. So an embed-bearing def OR a NESTED self-ref def
   referenced from inside an embedding (one frame deeper) was evaluated EAGERLY, collapsing its
   self-ref before the narrowing arrived. A new producer (`refDefClosureBody?` + `conjDefClosure?`)
   defers these to `.closure`s the force-fold splices — fired in the `.refId` arm (forces
   STANDALONE for a bare ref with no use-site), the `.conj` fold, and `meetEmbeddingsWithFuel`.
3. **Cross-scope splice contamination (E2b).** Force-splicing the host's FULL `current` into an
   embedded closure carried (a) the host's `Self=`/`let` aliases — colliding with the embed's own
   `Self` and breaking its `Self.label` selections → `bottom`; and (b) the host's REGULAR output
   fields (`apiVersion`, `kind`) — which the embed then re-evaluated and conflicted on. Fix:
   `hiddenFieldsOnly` splices ONLY the host's hidden/definition fields (the shared `#name` the
   embed self-references), never aliases or regular fields. Regular fields unify at the outer
   `meet`, not via the splice.

### Fix (`Kue/Eval.lean`)

- **`closeEmbeddedOver`** (pure helper) + **`openStructValue`** in both embed-meet sites: meet
  embeddings OPEN against an OPEN host, then re-close ONCE over `def ∪ embed` labels. The single
  definition of CUE's embedding-closedness rule, shared by the eager `.structComp` eval arm and
  the `.structComp` closure-force arm (DRY'd from inline duplication).
- **`refDefClosureBody?` / `conjDefClosure?`** producers: defer a bare ref to an embed-bearing
  (`.structComp`, any depth) or NESTED (`depth > 0`) `.struct`/`.structTail` self-ref def to a
  `.closure`. Depth-0 `.struct`/`.structTail` stays on the lazy-merge path (no fixture drift).
- **`hiddenFieldsOnly`** filter on the embed-splice use-operands; **`stripLetBindings`** on the
  multi-operand `.conj` fold use-operands.

### Tests (8 new `native_decide` pins + 1 committed module fixture)

`close_embedded_over_unions_allowed_labels`, `eager_structcomp_embed_closed_keeps_host_field`
(E1); `embed_chain_two_level_narrows_through`, `embed_chain_two_level_standalone_forces`,
`embed_chain_inner_conflict_is_bottom` (chain narrows / standalone forces / inner conflict →
bottom); `ref_def_closure_skips_depth0_struct`, `ref_def_closure_fires_for_nested_struct`
(producer fires for the gap, not over-fires on depth-0). Committed
`testdata/modules/embed_chain_selfalias/` — the real 3-level PLAIN-embed cross-package shape
(`#ClusterIssuer → parts.#Metadata → attr.#Metadata`, implicit hidden-field flow), JSON export
byte-identical to cue.

### Verify

`lake build` → 86 jobs. `scripts/check-fixtures.sh` → `fixture pairs ok` (every existing fixture
byte-unchanged). `shellcheck` clean. Oracle: 2-level, 3-level, implicit plain-embed chains,
closed-def-host union, narrowing-through-chain, and inner-conflict→bottom all byte-match cue
v0.16.1. No CUE divergence found.

### Real-app verdict (read-only prod9 — HONEST)

A faithful hand-built replica of the FULL real `#ClusterIssuer` (3-level chain + `#staging: bool
| *false` guards + `privateKeySecretRef` interpolation + `solvers` list + presence/`len` guards +
the `_` embedding in `attr.#Metadata`) now exports byte-exact vs cue. BUT cert-manager (~11s) and
argocd (~54s) STILL return `bottom`. Bisected: the collapse is NOT in `#ClusterIssuer` itself — it
is triggered by a SIBLING def in the loaded `prodigy9.co/defs/parts` package, `#PodController`,
which embeds `attr.#Ports` (a `.structComp` with a bare-`#port` self-ref guard `if #port != _|_`).
The mere PRESENCE of `#PodController` in the package poisons the (unrelated) `#ClusterIssuer`
eval — a CROSS-DEF cache collision, a NEW correctness shape beyond E's scope (E is complete and
green on every chain shape in isolation). The long timings are a separate perf concern. Next
correctness blocker: **`closure-crossdef-cache-collision`** (a sibling structComp-with-guard def
poisoning an unrelated def's eval); perf B remains downstream.

---

## Completed Slice: F2 `structcomp-force-comprehension-loss` (the corrected B')

Goal (the LIVE cert-manager blocker, re-scoped by Phase-A audit `db5ee90` from the misdiagnosed
"cross-def cache collision"): a deferred-then-forced `.structComp` def silently DROPPED its
`if`/`for` comprehensions. `forceClosureWithConjunct`'s `.structComp` arm meet-folded only the
embeddings (`comprehensions.filter isEmbeddingValue`) and never expanded the conditional/loop
comprehensions, so a guard inside a forced def vanished. Repro (ONE def, no sibling, no cache):
`#M: {#x: int, if #x > 0 {y: #x}}` + `#M & {#x: 5}` → cue `{y: 5}`, kue `{}`. The same shape
inline/eager gave `{y: 5}` correctly, proving the loss was in the FORCE path.

### Fix (`Kue/Eval.lean`)

- **Site 1 (force arm `.structComp`).** Mirror the eager arm: `let expanded <-
  expandComprehensionsWithFuel fuel nested comprehensions` (embeddings expand to `[]` there and
  still flow to the embed-meet), `mergeEvaluatedFields (staticFields ++ expanded)`. The
  comprehension fields are computed against the POST-splice frame, so an `if #x > 0` guard sees
  the narrowed `#x`. Comprehension-introduced labels (`y`) join the closedness allow-set
  (`closeEmbeddedOver (defFields ++ expanded) …`) — a guard field is part of the def's declared
  shape, so re-closing must admit it.
- **Site 2 (non-def lazy-merge).** `M & {x: 5}` for a REGULAR comprehension struct dropped the
  guard the same way — `M` evaluated eagerly (guard dropped against `x: int`) then met. Fixed by
  relaxing the `refDefClosureBody?` gate to defer a NON-definition `.structComp` self-ref body too
  (left UNCLOSED — open closedness preserved so the use-site meet admits siblings as cue does).
- **Embed-chain generalization (`bodyNeedsDefer`).** A struct that EMBEDS a guard/self-ref def
  (`Outer: {#Inner}`, `#Inner` guard-bearing) is not a self-ref of `Outer`, so the direct
  `defBodyHasSiblingSelfRef` missed it and `Outer` collapsed `#Inner` before the use-site narrowing
  arrived. New env-aware `bodyNeedsDefer` resolves each embedding (`resolveEmbedDefBody?`) and
  recurses: defer iff the body OR any embed's referenced def needs deferral. Wired into both
  `refDefClosureBody?` and `importDefClosureBody?` (with the right placeholder-frame env so the
  embed's depth-1 refs resolve).
- **Conditional-embed-label closedness (`evalEmbeddingFieldsWithFuel` now takes `narrowing`).**
  The closed-allow-set computation forced each embed-closure WITHOUT the host narrowing, so a
  CONDITIONAL embed label (`ports` from `if #port > 0`) was absent from the allow-set and the host
  then rejected the field the actual embed-meet produced → spurious bottom. Now forces the embed
  with the host's hidden fields spliced, so conditional labels surface.
- **Standalone-selector-force leak (`pkg.#Def` selected OUTSIDE a conjunction).** The selector
  producer emitted a bare `.closure` that was never forced when `pkg.#Def` was selected standalone
  (`out: attr.#Ports`, or `{attr.#Ports}` with no narrowing) → leaked as `incomplete`. Now the
  selector arm FORCES standalone (empty use-operands, mirroring the `.refId` arm); the `.conj`
  fold re-produces the closure from the RAW selector (`importSelectorDef?` + in-monad `pushFrame`)
  for the met case, and both embed-meet sites defer selector embeddings the same way.

### Tests (4 new `native_decide` pins + 2 committed module fixtures; 2 slice-3 pins updated)

`f2_force_structcomp_guard_fires_post_meet` (THE headline → `{#x:5, y:5}`),
`f2_force_structcomp_guard_does_not_fire` (`#x:-1` → no `y`), `f2_body_needs_defer_through_embed`
(embed-chain defer detection), `f2_body_needs_defer_skips_plain_embed` (no over-fire). The two
slice-3 producer pins (`closure_producer_emits_on_selfref_def`, `…_captures_full_id_stack`) were
updated for the new standalone-force behavior (producer now forces, not emits a bare closure).
Committed `testdata/modules/structcomp_force_guard/` (forced cross-package def with BOTH an `if`-
guard and a `for`-comprehension → JSON+YAML byte-identical to cue) and
`testdata/modules/structcomp_lazymerge_guard/` (site 2, the non-def regular-struct lazy-merge).

### Verify

`lake build` → 86 jobs. `scripts/check-fixtures.sh` → `fixture pairs ok` (every existing fixture
byte-unchanged; embed_chain_selfalias regression caught mid-slice and fixed). `shellcheck` clean.
Oracle (cue v0.16.1): 12-case matrix (force-def guard fire/not-fire, `for` in forced def, non-def
lazy-merge, embed-in-def-met-at-use, standalone selector) all byte-match. No CUE divergence found.

### Real-app verdict (read-only prod9 — HONEST)

cert-manager / argocd STILL return `bottom` (~11s / ~54s — perf wall unchanged). The F2
comprehension loss is FIXED and the cert-manager error has moved PAST it to a DISTINCT, PRE-EXISTING
bug (verified on the HEAD `db5ee90` binary — NOT introduced by F2): **a def whose value is an
import-selector poisons sibling/own resolution**. Clean minimal repro: `#A: parts.#M` (def aliased
directly to `parts.#M`, no embed braces) + `defs.#A & {#name: "n"}` → kue `incomplete value:
string`, cue `{name: "n"}`. A second def referencing the `parts` import binding likewise poisons an
otherwise-resolving embed-form def (`#ClusterIssuer` resolves alone; adding any `#Foo` that
references `parts` collapses it). This is the import-selector-deferral-through-package-indirection
family — the NEXT correctness slice, gating cert-manager. The audit's "no cache collision" call was
right (a cache-bypass build still bottoms — it is deterministic eval contamination, not a memo
collision). Perf B remains downstream of it.

## Completed Slice: `closure-import-selector-alias` (the live cert-manager blocker — two sub-fixes)

Root-causing split this into TWO genuinely distinct bugs. Both landed; together they make the
isolated `#ClusterIssuer` AND the multi-import `parts` package cue-exact.

### Sub-fix 1 — alias-to-selector deferral (`Kue/Eval.lean`)

The producers (`importDefClosureBody?`, `refDefClosureBody?`) deferred a def to a `.closure` only
when its body was DIRECTLY a struct needing deferral. A def whose body is an import selector
(`#A: parts.#M`) or embeds one (`#A: {parts.#M}`) fell to the eager path: `parts.#M` resolved in the
`defs` frame BEFORE the use-site `& {#name}` narrowed → `name: #name` collapsed to `string`
(`incomplete value: string`). cue: `{name: "n"}`.

**Fix.** New `followAliasDefBody? (fuel) (frameEnv) (capturedFrame) : Value -> Option (List Field ×
Value)` follows the alias/import-selector indirection to the terminal struct-like body AND the
package frame that body's refs resolve against:
- `.selector (.refId baseId) label` — resolve `baseId` in `frameEnv` to a package `.struct`, find
  `label`, recurse with that package's fields as the new captured frame (so `parts.#M`'s body
  captures the `parts` frame, not `defs`).
- `.refId id` — resolve to a sibling/outer def and recurse (`#B: #A`, `#A: parts.#M` — two hops).
- terminal struct-like — return `(capturedFrame, body)` iff `bodyNeedsDefer`.
Fuel-bounded against cyclic alias chains (`#A: #B`, `#B: #A` terminates → `none`).

Wired in: `importDefClosureBody?` gained an alias-follow fallthrough (when the direct
`bodyNeedsDefer` check fails on a definition body, follow the chain and defer over the terminal
frame). New conjunct producers `refAliasDefClosure?` / `refAliasSelectorDef?` (the bare-ref analogue
of `importSelectorDef?`) thread the terminal frame into the `.conj` fold's closure splice and into
the `.refId` standalone-force arm. The eager/lazy-merge path is untouched for non-selector aliases
(`followAliasDefBody?` returns `none`), so no over-deferral.

### Sub-fix 2 — duplicate import-binding meet-collision (the REAL cert-manager blocker)

Bisecting the offline real-package repro (full `defs@v0.3.19` copied from the cue cache, import
paths sed-rewritten to a local module) proved the isolated `#ClusterIssuer` is cue-exact — the
bottom came from the FULL `defs` package and narrowed to **a SECOND file in the `parts` package
importing `attr`** (`parts/pod_controller.cue` alongside `parts/metadata.cue`, both `import attr`).
This is the breadcrumb's "second def referencing the shared import binding poisons" facet.

**Mechanism.** `bindImports` (Module.lean) prepends each file's resolved imports to THAT file's
struct value as hidden fields; `mergeSourceValues` (Runtime.lean) then `meet`-folds all sibling
files. Two files both `import attr` ⇒ the merged `parts` package struct carries the `attr` hidden
label TWICE, and `meet`-ing two INDEPENDENTLY-loaded copies of the same package struct corrupts the
binding (→ bottom). CUE binds imports file-scoped; the same package across files is ONE instance, not
a meet of two copies. Clean minimal repro: `parts` package with two files both `import attr`, then
`parts.#Metadata & {#name}` → was `conflicting values (bottom)`, now `{name: "n"}` cue-exact; the
control (one file imports `attr`) always worked.

**Fix (`Kue/Module.lean`).** Defer import binding to the package level. `parseAndBindFiles` now
returns the RAW parsed files plus the combined binding set across all files (no per-file
`bindImports`). `loadPackage` merges the raw bodies (`loadPackageFromParsed` / `mergeSourceValues`)
and then applies `bindImports (dedupeBindings bindings)` ONCE onto the merged value. New
`dedupeBindings` (structural `dedupeBindingsWith` over a seen-names accumulator) keeps the first
binding per bind name — the same package across files is a single binding, distinct names (aliases /
different packages) all survive. Resolution (`resolveStructRefs`) runs on the fully-assembled
top-level value AFTER binding, so the `.refId` indices are computed against the final
single-binding layout — no index skew.

### Tests (2 new `native_decide` pins + 1 committed module fixture)

- `dedupeBindings` keeps first-per-name / drops later dupes; distinct names all survive
  (`Kue/Tests/ModuleTests.lean`).
- `testdata/modules/dup_import_binding/`: a `parts` package with TWO files both `import attr`
  (`metadata.cue` + `other.cue`), `parts.#Metadata & {#name}` → `{name: "n"}`, byte-identical to
  `cue`. Was `conflicting values (bottom)` before the fix.

### Real-app verdict after BOTH sub-fixes (read-only prod9 — HONEST)

**Correctness for this blocker is COMPLETE; the frontier is now PERF (B `closure-perf`).** A
faithful BOUNDED offline repro carrying the exact duplicate-import trigger (`parts/metadata.cue` +
`parts/pod_controller.cue`, both `import attr`, feeding `#ClusterIssuer`) is now BYTE-EQUAL to `cue`
— the bottom is gone. The FULL real `cert-manager.cue` no longer bottoms but now **exceeds 120s and
even 300s** (was ~11s to reach the bottom): removing the short-circuiting bottom exposed the full
evaluation cost, which hits the unchanged perf wall. So the error has moved from a correctness
bottom to the perf wall. **Next slice: B `closure-perf` (frame-id sharing / memo — the ~minutes
wall on the full `defs` package).** F1 default-mark remains orthogonal and can interleave; it is no
longer gating cert-manager.

## Perf B `closure-perf` — frame-id sharing + force-memo (PARTIAL) — commit `4dbc62c` (2026-06-18)

Two SOUND, behavior-preserving memos for the perf wall (every fixture byte-identical; `fuel`
kept load-bearing in every key). Real wins, but the dominant real-app cost is a THIRD axis
(fuel) neither touches — so this is partial, not the unblock.

### What landed

1. **Canonical frame-id sharing.** `pushFrame` reuses the id of a structurally-identical earlier
   push under the same parent id-stack (`FrameKey = (parentIds, fields)`, shallow `Hashable`,
   derived `BEq`). The downstream `EvalKey` (keyed on `env.ids`) then hits the memo instead of
   re-deriving an identical subtree. SOUND: the key proves the two frames are contents-equal in
   identical scope, so the id is a canonical NAME for "this frame's contents in this scope," not
   an allocation token; reuse can only return the matching evaluation. Synthetic deep-INLINE
   `{a: B, b: B}` (each level inlines the same body twice): exponential → linear — depth 8
   `767 → 18` evals (42×), depth 10 `3071 → 22` (140×), depth 12 `12287 → 26` (472×).

2. **Closure-force memo.** `forceClosureWithConjunct` bypassed the `EvalKey` cache (it is called
   directly from the `.refId`/`.selector`/`.conj` arms), so a `pkg.#Def` referenced N times
   re-forced its body N times. Split into a cached wrapper + `forceClosureWithConjunctCore`,
   keyed on `ForceKey = (fuel, capturedEnv.ids, body, useOperands)` — the full pure-function
   input. `body` already carries closed-vs-open state (the producer closes imported def bodies at
   capture), satisfying audit constraint (b) without an extra key field.

### Tests (8 new `native_decide` pins, `Kue/Tests/EvalTests.lean`)

- Perf/value: `eval_deep_inline_sharing_is_linear` (depth 8 = 18 evals; 767 without sharing —
  42× tripwire), `_count_depth4/6`, `_value_correct`.
- Soundness: `frame_share_identical` (identical re-pushes SHARE), `frame_no_share_different_fields`
  (different fields → distinct id), `frame_no_share_different_parent` (different parent id-stack →
  distinct id), `frame_no_share_closed_vs_open` (`.definition` vs `.regular` → distinct id, the
  constraint-(b) closed/open case).

### Real-app verdict (HONEST — re-profiled cert-manager.cue, read-only prod9)

The value CONVERGES at fuel ~16: at fuel 16 cert-manager produces the CORRECT output, byte-
matching `cue` except field-ordering (#3, known orthogonal gap). But `evalFuel = 100` re-derives
that converged value across 84 wasted levels at ~1.35×/level → effectively infinite (full-fuel
run killed at 8 min CPU). The two memos cut ~30% (fuel 8: `84.5k → 60.3k` evals) but CANNOT
touch the fuel axis — `fuel` is in every key, load-bearing (263 fuel-truncation cases). **The
real blocker is fuel multiplication; the recon's frame-id-divergence story was incomplete (it is
ONE component, ~30%, not the whole).** Kue is NOT yet a drop-in `cue` for these apps. Next: the
**fuel-saturation caching** slice (design + soundness hole in `plan.md`'s Perf B section) — cache
fuel-INDEPENDENTLY any result whose subtree never hit `fuel = 0`. Own slice, own soundness spike;
do NOT fold into a sharing slice.

## Fuel-saturation caching — the fuel-multiplication fix (2026-06-18, this slice)

**The real-app PERF gate is LANDED. cert-manager now exports CORRECTLY at production fuel 100.**

### What it does

A result whose ENTIRE (transitive) eval never hit a `fuel = 0` base nor a cycle `.top` is
SATURATED — fuel-insensitive, identical at every higher fuel (more fuel cannot change an eval
that never ran out). Such results are cached FUEL-FREE (`satCache`, keyed `(envIds, visited,
value)`), so a converged value evaluated at fuel f and re-requested at any fuel ≥ f is served from
ONE entry — collapsing the per-fuel-level re-derivation. TRUNCATED results (the 263 fuel-
truncation cases) stay fuel-keyed in the existing `cache` (`EvalKey`, `fuel` retained) and are
NEVER served across fuel.

### The hole, closed BY CONSTRUCTION (bracketing, not a per-arm boolean)

The design's hole was "the saturated bit must thread through the ENTIRE eval-core return type; one
arm forgetting to propagate `unsaturated` silently caches a truncated value → corruption." Closed
by NOT threading a per-arm bit (12 functions = 12 forget-sites). Instead:

- `EvalState.truncCount` is a MONOTONIC counter bumped ONLY at the two truncation arms (`fuel = 0`
  base; cycle `.top`). `evalValueWithFuel` (the single cached wrapper) BRACKETS it: snapshot
  before/after the core eval; `saturated := (after == before)`. Every transitive truncation
  through ANY arm/helper flows through the counter, so the bracket sees them all — there is NO
  per-arm join to forget because no arm classifies.
- Cache value is `(Value × Saturation)`. Cache-hit honesty: a `truncated` hit re-bumps
  `truncCount` so the bracketing parent still classifies itself truncated; a `saturated` hit bumps
  nothing. Same discipline for `forceCache` (the force wrapper is bracketed identically).
- The fuel-free `satCache` is inserted ONLY in the `saturated` arm of the wrapper's bracket — the
  single insertion site — so a truncated value can never enter it (enforced by the `match sat`,
  not a check).

### Result — fuel multiplication → BOUNDED

cert-manager eval count is now FLAT across fuel instead of multiplicative:

| fuel | before (evalCalls) | after (evalCalls) |
|------|--------------------|--------------------|
| 16   | 583 020            | 287 993            |
| 18   | 800 769            | 298 167            |
| 20   | 1 053 422          | 313 582            |
| 100  | killed @ 8 min CPU | 290 427 (~30 s)    |

**REAL-APP HEADLINE: cert-manager exports the CORRECT value at production fuel 100 in ~30 s** (was
unbounded). JSON + YAML both byte-match `cue` modulo field-ordering #3 (`jq -S` IDENTICAL). Kue is
now a content drop-in for cert-manager. **argocd: still blocked, but by a SEPARATE correctness gap
— it produces `bottom` at EVERY fuel (8/12/16/20), `mlen=0` — a genuine eval gap, not fuel/perf,
not a saturation regression** (cert-manager stays correct, all fixtures byte-identical).

### Tests (9 new `native_decide` pins + 2 export fixtures, `Kue/Tests/EvalTests.lean`)

Saturation (5): `sat_converged_reused_across_fuel_is_free_and_correct` (a converged value re-
requested at higher fuel adds ZERO core evals AND equals the fresh high-fuel eval — the perf win +
correct reuse); `sat_truncated_not_served_across_fuel` (THE critical pin: a fuel-sensitive self-
ref value evaluated at fuel 3 then 20 must get the fuel-20 expansion, NOT the fuel-3 stump — the
corruption the slice prevents); `sat_low_fuel_truncates` (the hazard is genuine); `sat_truncated_
same_fuel_is_cached` (truncated stays fuel-keyed-cached, honest fuel axis).

Owed `perfb-soundness-pins` (audit #5, FOLDED IN — 4 E2E value pins + 2 export fixtures): `perfb_
force_memo_narrows_by_useOperands` (`#D&{x:1}` shares, `#D&{x:2}` distinct — force-memo `useOperands`
keying, asserts exported VALUE not id-coincidence); `perfb_frame_share_parent_disambiguates_value`
(identical inner body under different parents → different values — parentIds load-bearing E2E);
`perfb_closed_vs_open_distinct_values` (closed `#C` REJECTS extra `y: _|_`, open admits — through
REAL normalization, not the `.definition`/`.regular` proxy); `perfb_frame_id_does_not_leak`
(`valueTag`/`Format` ignore `capturedEnv` ids). Export fixtures `testdata/export/force_memo_narrow`
+ `frame_share_parent` byte-match `cue export`.

### Residual

cert-manager at 30 s is correct but not single-digit-seconds: the fuel axis is solved, the residual
is the absolute eval count (~290k) × the per-eval constant. Next perf lever is the per-eval cost,
not fuel. argocd's `bottom` is a correctness frontier (likely `module-file-scoped-imports` /
`import-eager-closedness` / field-ordering), independent of this slice.

---

## Completed Slice: Fuel-saturation soundness fix — comprehension/embedding helpers must bump `truncCount`

Goal: close a VIOLATION found by Phase-A audit #6 (2026-06-18) in the fuel-saturation
caching slice (`ed5f530`). The slice claimed `fuel=0` base + cycle `.top` were the ONLY
truncation sources, so the bracket over `truncCount` could never misclassify a truncated
result as saturated. That was false: four fuel-threaded helpers truncate independently.

### The bug

`expandClausesWithFuel`, `expandComprehensionWithFuel`, `evalEmbeddingFieldsWithFuel`, and
`meetEmbeddingsWithFuel` each have a `fuel=0` base case that returns an INCOMPLETE result
(drops comprehension/embedding fields) without bumping `truncCount`. A comprehension or
embedding truncated at low fuel mid-expansion yielded a smaller struct than at high fuel,
yet the bracketing `evalValueWithFuel` saw `truncCount` unmoved → classified it saturated →
inserted the truncated value into the fuel-free `satCache`. A higher-fuel same-key request
was then served the smaller (wrong) struct — a truncated value served fuel-free.

Repro: `.structComp [] [if true {x:1}] true` evaluates to `.struct [] true` at fuel 2
(dropping `x`, `truncCount` unmoved) but `.struct [{x:1}] true` at fuel 20; `evalTwiceAt 2 20`
served the fuel-2 `{}` stump at fuel 20.

### The fix

Bump `truncCount` at all four helper `fuel=0` arms (mirrors the two `evalValueCoreWithFuel`
arms). A strict tightening — classifications can only move saturated→truncated, never the
reverse, so the fix can never newly corrupt; worst case is a perf miss for configs that
exhaust fuel mid-comprehension. Every fixture stayed byte-identical (no current fixture hits
these arms at fuel=100 — the hole was latent, but latent-unsound is still a Violation per the
correctness-over-performance decision). Updated `Saturation`/`truncCount` doc comments: six
bump sites, not two.

### Tests (2 new `native_decide` pins, `Kue/Tests/EvalTests.lean`)

`sat_comprehension_truncation_not_served_across_fuel` (the third-truncation-source pin: the
`if true {x:1}` comprehension truncated at fuel 2 must NOT be served fuel-free at fuel 20 — the
exact corruption, failing pre-fix); `sat_comprehension_low_fuel_truncates` (the hazard is
genuine — fuel-2 drops `x`, fuel-20 keeps it). These close the gap the 5 original pins left:
they only exercised the two known arms, never a helper truncation.

---

## Completed Slice: argocd bisect — disjunction-selection + embedding-Self chain (3 of N)

Commit `83a8ac4`. Goal: bisect the argocd `bottom` (failing at every fuel — the last
probed prod9 app still failing) to a minimal repro and fix the actual cause.

### The bisect

`kue export apps/argocd.cue` (under prod9, read-only) bottoms at every fuel. Bisected by
isolating each top-level key offline (scratch module in `/tmp`, importing the pinned
`prodigy9.co/defs@v0.3.19` from the cue cache, read-only): `#ConfigMap` exported correctly,
`#Secret` bottomed. Minimized `#Secret` to a fully offline single-file repro (no
cross-package import) — so it is NEITHER suspected borderline finding
(`module-file-scoped-imports`: both bottom and ⊥ even single-file; `import-eager-closedness`:
no import involved). A THIRD distinct gap, as Phase B's note anticipated argocd might surface
a chain.

Minimal repros (all `cue` succeeds, `kue` bottomed pre-fix):
- `d: *{a:1,c:9} | {a:2}` then `out: {r: d.a}` → cue `{r:1}`.
- `out: Self={ (*{a:1} | {a:2}); r: Self.a }` → cue `{a:1, r:1}`.
- `_Base: {a:1}` then `out: Self={ _Base; r: Self.a }` → cue `{a:1, r:1}` (the broader
  facet — Self-into-embedding is not disjunction-specific).
- `#S: Self={ #name: string; (*{#type:"Opaque"} | {#type:"tls"}); type: Self.#type }`,
  `out: #S & {#name:"s"}` → cue `type:"Opaque"` (the closure-force path).

### Root cause + fix (one family, three facets)

1. **`selectEvaluatedField` had no `.disj` case** — selecting a field INTO a disjunction
   fell through to `.bottom`. CUE collapses the default arm first, then selects. Added a
   `.disj` case routing through the existing `resolveDisjDefault?` (the manifest/guard
   default-rule helper): a unique default (or lone regular) resolves and the field is
   selected from it; a non-default multi-arm disjunction stays a deferred `.selector` (no
   over-fire — manifest then reports the ambiguity, never a spurious `bottom` or silent pick).

2. **Embedded default disjunction never contributed its default arm's fields to the host.**
   Added `resolveEmbeddedDisjDefault` at the embedding-merge sites (`meetEmbeddingsWithFuel`
   + `evalEmbeddingFieldsWithFuel`): a default disjunction collapses to its arm before the
   merge, so its fields land as regular host fields and the closedness union admits them; a
   non-default disjunction passes through unchanged.

3. **`Self.<label>` where `<label>` is supplied by ANY embedding bottomed.** The host frame
   held only static labels, so `thisStructFieldIndex?` missed the embedded slot and the
   generic selector path hit `.thisStruct` → catch-all `.bottom`. Added a gated two-pass to
   BOTH the eager `.structComp` arm and the closure-force arm (`forceClosureWithConjunctCore`,
   which the `#Secret` def-ref path uses): re-evaluate the static fields against a frame
   augmented with the embedded labels not already declared static, so `Self.<embedded-label>`
   resolves. Gated by `needsEmbeddedSelfPass` (a fuel-bounded scan, `refsSelfEmbeddedLabel`)
   — fires ONLY when a static field actually selects `Self.<new-embedded-label>` through the
   host's `Self` alias. cert-manager embeds `parts.#Metadata` (supplies `metadata`) but never
   reads `Self.metadata`, so it stays single-pass: the un-gated two-pass cost cert-manager
   ~59s (2x), the gated version restored ~29s.

### Behavior preservation + real-app status

Every existing fixture byte-identical (`fixture pairs ok`). cert-manager re-probed: still a
content drop-in, `jq -S` identical to `cue`, ~29s — no regression. `#Secret` now exports its
structure correctly (apiVersion / kind / type:"Opaque" / metadata all match `cue`).

argocd is NOT yet a drop-in — this clears the FIRST chain link. Two further DEEP gaps remain
(both narrowing-into-embedded-arm, deeper than this slice):
- **secret `data:{}`**: `for k,v in Self.#data` in the embedded default arm `_#OpaqueSecret`
  runs against the arm's empty `#data` BEFORE the use-site `#data` narrowing reaches it —
  cue produces the populated payload. Minimal repro `w3` recorded in the breadcrumb.
- **`#TLSRoute` list guards**: `spec.parentRefs: [ if Self.#gateway_name != _|_ {…}, … ]` —
  list elements that are `if`-guard comprehensions over use-site-narrowed hidden fields —
  bottom. Minimal repro `lr` recorded in the breadcrumb.
- Plus the heavy `argo` sub-package perf wall (full argocd now evals past the early bottom
  and times out >200s on the larger sub-package; was 95s-to-bottom before).

### Tests

5 export fixtures (all byte-match `cue`): `disj_select_default`, `disj_select_default_only`,
`embed_self_disj`, `embed_self_plain`, `embed_self_disj_closed`. 8 `native_decide` pins in
`Kue/Tests/EvalTests.lean`: select-into-default-disjunction (fires) + non-default (defers),
embedded-default resolve + non-default passthrough, two-pass gate fire + skip×2.

---

## Completed Slice: F1 default-mark algebra (audit #3 Violation cleared)

Goal: fix CUE default-disjunction mark algebra, wrong in three coupled ways (filed audit
#3, baseline `db5ee90`). Root-cause split the fix along TWO operator classes that the audit
had conflated under one "combineMark OR→AND" framing — oracle probing (`cue` v0.16.1)
showed they are governed by different rules.

### Two operator classes, distinct semantics (the load-bearing finding)

- **Unification (`&`)** DOES cross-product with **mark-AND** over default *sets*, per the
  CUE spec rule `(v1,d1) & (v2,d2) = (v1&v2, d1&d2)`. The subtlety naive "AND" misses: a
  disjunction with NO `*` has its *whole* value set as its default set (`(1|*2) & (1|2|3) →
  2` needs the right operand's arms to all count as defaults, else the lone `*2` survivor
  loses its mark). Implemented as `withDefaultConvention` (promote a no-`*` operand's arms to
  default) applied to each operand BEFORE `combineMark` (now strict AND) crosses them. Empty
  default-intersection falls out automatically → ambiguous.
- **Arithmetic / comparison / unary (`+ - * / < == !` …)** do NOT distribute or cross-product
  at all. CUE forces each operand to a *single* default (or lone live regular) FIRST, then
  applies the scalar op (`(int | *1) + 1 → 2`, NOT `int+1 | *2`; `(1|2)+10` stays the stuck
  `(1|2)+10`, cue's "unresolved disjunction"). `distributeUnary`/`distributeBinary` rewritten
  to `resolveOperand` (= `resolveDisjDefault?`, else the operand) each side, then one
  `evalUnary`/`evalBinary` — the existing stuck-node convention (`evalAdd` returns `.binary`
  on non-concrete operands) yields cue's incomplete form for free. This REPLACED the old
  slice-C cross-product distribution (the actual source of spurious-default manufacture);
  slice-C pins `distribute_*_over_default_disj` updated to the resolve-first result.

### The three audit facets, all fixed

1. **`combineMark` OR→AND** (`Lattice.lean`) — default iff BOTH inputs default. Now used only
   by unification's cross product (arithmetic no longer crosses).
2. **`flattenAlternatives` two-level precedence** — a `.default`-marked outer arm wrapping a
   nested `.disj` carries the inner's *own* default set (`withDefaultConvention nested`); a
   `.regular` outer arm makes every inner arm regular. So `*d | 5` with `d:1|2` → inner has no
   `*` → both `1,2` become defaults, `5` stays regular → distinct defaults → ambiguous `1|2`
   (cue-exact); `d:*1|2` → only `1` carries → `1`. The OLD OR-flatten produced `*1 | 2 | 5`.
3. **Equal-default dedup** — new `dedupAlternatives` (in `liveAlternatives`) merges equal-
   VALUED arms (`combineMarkOr`: a value is default iff any occurrence is), so `*1|*1|2 → *1|2`
   → unique default `1`. Dedup is by value (`*1|1 → 1`, `1|1 → 1`); distinct defaults preserved.

### Behavior preservation + proof-form churn

Every existing fixture byte-identical (`fixture pairs ok`). `dedupAlternatives` introduced
`Value`-`==` on the manifest/normalize reduction path, which `rfl` cannot reduce (derived
`BEq`); 12 existing definitional-equality proofs (Manifest/Fixture/Number/Tests `rfl` on
disjunction/default results) converted to the repo-standard `(lhs == rhs) = true` +
`native_decide` (same propositions, proven by compiled evaluation). Added a total
`instance [BEq ε] [BEq α] : BEq (Except ε α)` in `Manifest.lean` (stdlib has none) to let
`manifest`/`formatManifestField` results compare with `==`.

### Tests

3 committed fixtures under `testdata/cue/disjunctions/` (`.cue` + `.expected` eval-form +
`.manifest.expected`, all byte-match `cue` JSON): `default_arithmetic_cross` (`(1|*2)+(10|*20)
→ 22`), `default_dedup` (`*1|*1|2 → 1`), `default_unify_cross` (`(1|*2)&(1|2|3) → 2`). 12
`native_decide` pins in `EvalTests.lean`: AND-cross resolve + two-survivor-ambiguous,
`combineMark` AND truth-table, equal-default dedup + distinct-stays-ambiguous, nested-flatten
carries-inner + resolve-ambiguous + inner-default-resolves + regular-outer-sheds, arithmetic
resolves-operands-first + no-default-stays-stuck, non-default-stays-non-default. Oracle: a
32-case JSON+YAML matrix byte-matches `cue` on every resolvable case; ambiguous cases differ
only in error-message text (kue "multiple non-default disjuncts" vs cue "incomplete value …")
— cosmetic, both correctly refuse.

### Note (out of scope)

`cue` REJECTS `*(1|2)` as a syntax error ("preference mark not allowed at this position");
kue's parser ACCEPTS it and mis-desugars to `*1 | 2`. Pre-existing parser laxity, unrelated to
the mark algebra (the legitimate ref form `*d` where `d:1|2` is correct). Logged for an
eventual parser-strictness pass, not sliced here.

---

## Completed Slice: list-comprehension-parse-eval

List comprehensions (`[for x in xs {…}]`, `[if cond {…}]`, `[for k, v in m {…}]`) were a HARD
PARSE ERROR — `parseListItems` had no `for`/`if` clause handling. Filed HIGH basic-case gap
(audit #9 finding 1, `9915d21`). This slice landed the full LIST comprehension surface, plus its
root prerequisite (scalar struct-embedding collapse). cue v0.16.1-exact across the whole surface.

### Root prerequisite: scalar struct-embedding collapse (`Lattice.lean`)

A CUE list-comp body is a `StructLit { … }`; the yielded element is that literal's VALUE. `[for x
in [1,2] {x}]` → `{x}` is a struct embedding the scalar `x`, which CUE collapses to the scalar
(`{5}`→`5`, `[{5},{6}]`→`[5,6]`). kue produced `bottom` — the embedding rule handled `struct ∩ list
→ embeddedList` but NOT `struct ∩ scalar → scalar`. Fix: extended the two `.struct fields _, …`
`meet` arms — when a struct has NO output field AND no non-output decls (`collapsesToScalarEmbed`,
i.e. the collapse is LOSSLESS — no scalar carrier for selectable decls), `struct ∩ <terminal>` IS
the embedded value. `<terminal>` is a positive allow-list (`prim`/`kind`/`notPrim`/`stringRegex`/
`boundConstraint`) so a closure/conj/unevaluated form stays inert (`meet closure (struct[])` stays
bottom — pins `closure_meet_bottom`). Disjunction embeds are handled by the earlier `.disj` meet
arms; `top`/`bottom` by identity/absorption. Rule pinned vs cue: `{a:1,5}`→conflict, `{5,5}`→`5`,
`{5,6}`→conflict, `{5,"x"}`→conflict, `{"hi"}`→`"hi"`, `{int}`→incomplete.

### List comprehension parse + eval

- **AST (`Value.lean`):** added ONE node `listComprehension (clauses : List (Clause Value)) (body :
  Value)`, stored as a list ITEM. Reuses the existing `Clause Value` chain (one comprehension-clause
  representation, two body contexts — illegal-states-unrepresentable). `body` is the brace-block
  VALUE yielded as one element per innermost iteration (NOT a struct of fields to merge).
- **Parser (`Parse.lean`):** `parseListItems` dispatches on a `for`/`if` clause head to new
  `parseListComprehension`, which reuses `parseClause` + `parseComprehensionClauses` (the SAME
  machinery the struct form uses; the body is the `{…}` block value). A bare `for`/`if` cannot start
  a plain list expression, so dispatch is unambiguous.
- **Resolve (`Resolve.lean`):** added a `.listComprehension` arm to `resolveValueWithFuel` mirroring
  `.comprehension` (via `resolveClausesWithFuel`). WITHOUT this the source/guard/body refs and the
  loop-var scope were never resolved to `.refId` (the catch-all silently passed them through), so
  refs failed at eval — this was the load-bearing wiring (a bare `[for x in [1,2,3] {x}]` bottomed
  until added).
- **Eval (`Eval.lean`):** `.list`/`.listTail` arms now flatten via new `evalListItemsWithFuel` —
  each `.listComprehension` item expands via `expandListClausesWithFuel` (mirrors
  `expandClausesWithFuel`, but collects the evaluated BODY value per iteration into `List Value`,
  not fields); plain items map to a singleton; concat preserves order → mixed `[1, for x in xs {x},
  2]` and multi/zero-yield fall out. The new `fuel=0` base BUMPS `truncCount` (audit #6 saturation
  invariant — an uncounted truncation source corrupts via the fuel-free `satCache`).
- **Totality fan-out:** `.listComprehension` arms added to `Format`, `Manifest` (→ incomplete),
  `meetCore` (→ bottom; never reached in practice — list-comp lives only inside list items), and
  `valueTag` (tag 30).

### Behavior preservation + tests

Every existing fixture byte-identical (`fixture pairs ok`). 7 new fixture pairs (6
`comprehensions/list_comprehension_*`, 1 `structs/scalar_embedding_collapse`) + `FixturePorts`
entries. 18 new `native_decide` pins in `EvalTests.lean`: 11 list-comp behavioral (for /
for-index / for-k,v / if / if-false-zero / for+if / nested / mixed-order / empty / multi-yield /
struct-body), 5 scalar-embedding (ref collapse, in-list collapse, output-field-conflict,
two-equal-unify, two-distinct-conflict), and 2 fuel-truncation/saturation guards
(`sat_list_comprehension_truncation_not_served_across_fuel` — fuel-1 `[]` must not poison fuel-20
`[9,9,9]` via the fuel-free cache — and `sat_list_comprehension_low_fuel_truncates`). Oracle: the
full surface byte-matches `cue` v0.16.1 in BOTH JSON and YAML (26/26 across 13 cases).

### Real-app re-probe

cert-manager: content-identical to cue (`jq -S`), modulo the tracked field-ordering #3 — NO
regression (~28s, single-pass). argocd: still bottoms (~92s) on the SAME link-2 struct-comp
narrowing (`for k,v in Self.#data` into an embedded default arm) — NOT moved by this slice (a LIST
form). But: list comprehensions in argocd's transitive deps (stage9, rabbitmq, plane) now PARSE
cleanly (a whole class of parse errors eliminated repo-wide), and the link-3 list-guard shape (`[if
#a != _|_ {name: #a}]` with use-site narrowing) is byte-exact in isolation — the language-level
capability link 3 needs is in place; it is just not independently reachable while argocd bottoms
earlier on link 2.

---

## Completed Slice: argocd-secret-data sub-slice 1 (hidden-def field-class classification)

Goal: clear the argocd link-2 plain-embedding facet — a HIDDEN DEFINITION (`_#OpaqueSecret`)
embedded into a host whose use-site narrows a hidden field (`#data`). The embedded def's
sibling self-ref (`data: #data`, or `for k,v in #data`) ran against the def's own ABSTRACT
`#data` before the use-site narrowing reached it → empty output (`mapped: {}`) where cue
populates the map.

### Root cause (a PARSER misclassification, not an eval-timing bug)

`Parse.lean parseFieldClass` classified field-name axes as MUTUALLY EXCLUSIVE:
`isDefinition := label.startsWith "#"`; `isHidden := !isDefinition && label.startsWith "_"`.
So `_#x` (a HIDDEN DEFINITION in CUE — both closed AND excluded from output) was tagged
hidden-ONLY, dropping its definition-ness. The def-deferral path
(`refDefClosureBody?`/`conjDefClosure?`) gates on `isDef := defField.fieldClass.isDefinition`,
so for a `_#x` embedding it returned `none` → the arm evaluated STANDALONE (collapsing
`copy: #x` to the abstract `string`) BEFORE `meetEmbeddingsWithFuel` could force-splice the
host's narrowing. The `FieldClass` model already had orthogonal `isDefinition`/`isHidden` axes
(designed for exactly `_#x`/`#x?`); only the parser failed to populate them.

### Fix

`isDefinition := label.startsWith "#" || label.startsWith "_#"`; `isHidden :=
label.startsWith "_"`. `_#x` is now BOTH a definition and hidden; `#x` and `_x` unchanged. No
eval-path change — the existing slice-A/E closure-deferral machinery handles the narrowing once
the embedding is correctly recognized as a definition.

This also corrected a SECOND latent gap with the same root: `_#C` is now CLOSED (rejects
undeclared fields, `_#C & {a:1,b:2}` → `b: _|_`), matching cue's "field not allowed"; pre-fix
it was wrongly OPEN (hidden-only).

### Tests + behavior preservation

Every existing fixture byte-identical (`fixture pairs ok`); no `_#` appeared in any prior
fixture, so zero drift risk. 3 new parser-classification pins (`parse_field_class_definition`
/`_hidden`/`_hidden_definition` — the per-axis truth table). 6 new eval pins in `EvalTests.lean`:
the headline `for k,v in #data` comprehension narrows post-meet
(`hidden_def_embed_comprehension_narrows`), scalar sibling-self-ref narrows
(`hidden_def_embed_sibling_narrows`), empty-narrow → empty map (no over-population,
`hidden_def_embed_comprehension_empty`), hidden-def closedness accept+reject (`hidden_def_is_closed`),
no-over-defer regression on plain `#Base` (`plain_def_embed_sibling_narrows`), and a concrete-source
comprehension still eager (`hidden_def_embed_concrete_source`). 4 new export fixtures
(`embed_hidden_def_sibling`, `embed_hidden_def_comprehension`, `_comprehension_empty`,
`hidden_def_closed`), each cue v0.16.1-exact in JSON.

### Real-app re-probe

cert-manager: content-identical to cue (`jq -S`), ~28s single-pass — NO regression (its defs
are plain `#x`, untouched by the `_#x` widening). argocd: STILL bottoms (~91s) — the argocd
`#OpaqueSecret` lives in an embedded DEFAULT DISJUNCTION arm `(*_#A|_#B)`, whose default-arm
collapse evaluates the arm standalone BEFORE the use-site narrowing distributes in. That is a
DISTINCT fix (the disjunction-arm deferral), tracked as sub-slice 2 below. Sub-slice 1 fixes
the plain-embedding facet in isolation (verified by minimal repros `s1`/`emb`/`emb2`).

---

## Completed Slice: argocd-secret-data sub-slice 2 (embedded default disjunction arm narrowing)

Goal: clear the argocd link-2 DISJUNCTION facet — the actual `defs.#Secret` shape. The hidden
def `_#OpaqueSecret` lives in an embedded DEFAULT DISJUNCTION arm `(*_#OpaqueSecret |
_#DockerConfigSecret | _#TLSSecret)`, and its `data: {for k,v in Self.#data {...}}` comprehension
is narrowed by the use-site (`#Secret & {#data: …}`). Sub-slice 1 (hidden-def classification)
fixed the PLAIN embedding; this fixes the DISJUNCTION-arm path.

### Root cause

A disjunction's arms are evaluated EAGERLY when the disjunction is evaluated — the default arm
`_#OpaqueSecret`, now correctly a deferrable def (sub-slice 1), is forced STANDALONE with NO
use-operands, collapsing its `for`/sibling-self-ref against the def's own abstract `#data`
BEFORE the use-site narrowing distributes in. The collapse happens in two places: the `.conj`
fold (which evaluated the disjunction ref standalone then met it) and the embedded-disjunction
merge in `meetEmbeddingsWithFuel` (`resolveEmbeddedDisjDefault` picked the already-collapsed
default arm). Additionally, a struct embedding a `(*_#A|_#B)` disjunction did not even DEFER —
`bodyNeedsDefer`/`resolveEmbedDefBody?` had no `.disj` case, so the host evaluated eagerly.

### Fix — distribute the narrowing into the arms at the UNEVALUATED level

1. **`.conj` fold (`evalConjStandard` + `splitDisjConjunct`/`conjDisjArms?`).** Extracted the
   standard conj fold into `evalConjStandard`; the `.conj` arm first tries disjunction
   distribution: a depth-0 (or literal) disjunction conjunct with a deferral-needing arm becomes
   `*(_#A & {narrow}) | (_#B & {narrow})`, each arm-meet re-entering the fold so the post-ss1
   def-deferral force-splices the narrowing. `conjDisjArms?` returns `none` for a plain
   scalar/struct disjunction → standard distribute-at-meet path (no over-defer).
2. **Embedded-disjunction merge (`meetEmbeddingsWithFuel`).** When the embedding is a disjunction
   with a deferral-needing default arm, collapse to the default arm (`conjDisjArms?` +
   `resolveDisjDefault?`) BEFORE deferral, so the arm defers to a closure and force-splices the
   host's `current` narrowing — instead of `resolveEmbeddedDisjDefault` picking the collapsed value.
3. **Deferral detection (`resolveEmbedDefBody?` + `bodyNeedsDefer`).** Added a `.disj` case to
   `resolveEmbedDefBody?` that resolves through to the default arm's def body, so `bodyNeedsDefer`
   recurses into it and a struct embedding `(*_#A|_#B)` defers when the default arm needs it.

### Tests + behavior preservation

Every existing fixture byte-identical (`fixture pairs ok`) — the `evalConjStandard` extraction and
distribution gate are behavior-preserving on all current fixtures. 3 new export fixtures
(`embed_disj_default_sibling`, `_comprehension`, `_comprehension_empty`), cue v0.16.1-exact in
JSON+YAML. 6 new eval pins: headline comprehension narrows through the disjunction
(`disj_default_embed_comprehension_narrows`), scalar sibling narrows
(`disj_default_embed_sibling_narrows`), empty-narrow (`disj_default_embed_comprehension_empty`),
no-over-defer scalar (`disj_scalar_no_over_defer`) + struct (`disj_struct_no_over_defer`)
disjunctions, and a fuel-zero saturation guard on `conjDisjArms?` (`conj_disj_arms_fuel_zero_declines`
— the new scan declines to distribute at `fuel=0` rather than dropping fields, so it is not a
truncation source and need not bump `truncCount`; audit-#6 invariant honored by construction).

### Real-app re-probe (the headline)

- **cert-manager: NO regression.** Content-identical to cue (`jq -S`), ~29s single-pass.
- **`defs.#Secret` link-2 blocker CLEARED.** The exact argocd `#Secret` (with `#data`) now
  evaluates CORRECTLY: `data` is the populated, base64-encoded map matching cue byte-for-byte
  (modulo field-order #3), ~3s. `argo_secret` (the live argocd secret with `webhook.github.secret`)
  is content-identical to cue. This is the argocd link-2 correctness gap, closed.
- **Full argocd export still bottoms (~94s) — but on link 3, NOT link 2.** Bisected to
  `defs.#TLSRoute` (`route.yaml`/`listener.yaml`): `spec.parentRefs` is a list whose elements are
  `if Self.#gateway_name != _|_ {…}` guards over use-site-narrowed hidden fields → kue bottom,
  cue resolves both. This is the tracked `argocd-tlsroute-list-guard` (link 3) — a DISTINCT slice,
  fast-failing (~3s in isolation), not the perf wall. The argo sub-package perf wall remains beyond
  it. argocd is NOT yet a drop-in; the NEXT correctness link is link 3.

---

## Completed Slices: audit-#10 HIGH Violations cleared — `scalar-embed-collapse-provenance` + `embed-disj-arm-fallthrough`

Two HIGH correctness Violations from audit #10 (`87b597b`), both wrong VALUES on basic shapes,
both cleared. Commits `52b64dc` (V1) and `b2b558f` (V2).

### V1 — `scalar-embed-collapse-provenance` (`52b64dc`)

The `{5}`→`5` scalar-embedding collapse lived in `meet` (`collapsesToScalarEmbed`, in the
`.struct fields _, listLike` arms of `meetWithFuel`). At meet time an empty struct `{}` is
indistinguishable from `{5}`'s residual `.struct []` — the embedded-scalar provenance is gone —
so the rule wrongly absorbed any scalar an empty/decl-free struct met: `{} & 5` → `5`, `5 & {}`
→ `5`, `{} & "s"` → `"s"`, `true & {}` → `true`, `out:{}` + `out:5` → `5`. cue gives a type
conflict (mismatched types struct/scalar) in every case.

Fix: move the collapse into `meetEmbeddingsWithFuel` (embed-eval), where the host struct is
KNOWN to be embedding a scalar. The non-closure arm collapses to the resolved scalar when the
host is output-free and decl-free (`collapsesToScalarEmbed`) and the embedding resolved to a
terminal scalar; the fold continues with the scalar so `{5,5}` unifies and `{5,6}` conflicts.
The Lattice meet arms revert to `meetCore`, restoring the cue conflict for a genuine `{}` ∩
scalar (`.struct .., _ => .bottom`). List comprehensions rely on the collapse (a `[{x} for…]`
body is a struct embedding a scalar) and stay green — they evaluate each body through the same
`.structComp` → `meetEmbeddingsWithFuel` path. Preserved cue-exact: `{5}`→5, `[{5},{6}]`→[5,6],
`{5,5}`→5, `{5,6}`→conflict. The LOW borderline `{#a:1, 5}` still bottoms (unchanged, NOT
widened — that is the unsound direction).

5 new pins (empty/decl-free struct ∩ int/string/bool conflicts, both meet orders, two-field-decl
`out:{}` + `out:5` shape). Existing scalar-embed + list-comp pins unchanged.

### V2 — `embed-disj-arm-fallthrough` (`b2b558f`)

`meetEmbeddingsWithFuel` committed an embedded default disjunction to its default arm BEFORE the
host narrowing spliced in, with no fall-through when the narrowing KILLED the default arm.
`(*_#A{v:int} | _#B{v:string})` met with `{v:"s"}` bottomed the dead default and discarded the
surviving `_#B`, so kue gave bottom where cue gives `{kind:"b",v:"s"}`.

Two manifestations, both fixed by DISTRIBUTING the host narrowing into EVERY arm + pruning
bottoms (`normalizeDisj` via `liveAlternatives`, NOT `normalizeEvaluatedDisj` which does not
prune):
1. `conjDisjArms?` path (arms needing deferral — argocd `#OpaqueSecret`): per-arm sub-fold
   `meetEmbeddingsWithFuel current [arm]` at a dropped fuel tier so each arm re-enters the
   deferral/force-splice machinery, then `normalizeDisj`.
2. PLAIN embedded-disjunction path (the plan's repro — arms with no sibling self-ref, so
   `conjDisjArms?` declines): when the evaluated embedding is a `.disj`, meet the OPENED host
   into each arm, then `normalizeDisj`. This is the manifestation the plan's repro actually hits;
   path 1 (the `conjDisjArms?` collapse the plan described) only fires for deferral-needing arms.

A dead default falls through to a surviving arm; a live default still wins; all arms dying is a
conflict; a single-arm disjunction narrows unchanged. The disjunction residual is now kept
(`*{default} | {other}`) instead of collapsed to the default — the faithful CUE representation;
manifest picks the default, cue-exact.

4 new pins (dead-default fall-through, live-default kept, all-arms-die conflict, single-arm). 3
existing ss2 pins updated to the (correct) distributed residual — their MANIFESTED JSON is
byte-unchanged and cue-exact, only the internal disjunction residual string differs.

### Verify (both)

`lake build` 86 jobs green, `fixture pairs ok` (zero drift, existing export fixtures
byte-unchanged), shellcheck untouched (no script changes). Real-app re-probe: cert-manager
content-identical to cue (~31s), argocd link-2 `defs.#Secret` `data` populated base64
content-identical (the 3-arm disjunction still resolves to the `_#OpaqueSecret` default). argocd
full export still bottoms on link 3 (`defs.#TLSRoute` / `argocd-tlsroute-list-guard`) — pre-existing,
NOT a regression from either fix. Next correctness link remains link 3.

---

## Docs: plan.md distilled to live roadmap (2026-06-18)

Not a code slice. `docs/spec/plan.md` had accumulated ~10+ audit sections (several
`SUPERSEDED by #N`), the long-resolved `DECISION NEEDED` Value.closure fork (resolved +
fully implemented this session), and many completed fix-slice diagnoses — ~4100 lines.
Distilled back to the live roadmap (~175 lines): North Star + Working Principles, a
consolidated **Standing Capabilities** section, a ranked **Live Backlog** of every open
item, and **Pointers**. No open finding was dropped — the backlog is a superset of every
open item across the old plan (argocd-tlsroute-list-guard, truncate-primitive, regex/EvalOps/
test-org extractions, field-ordering #3, per-eval perf, and the borderline/LOW set incl.
scalar-embed-with-decls, module-file-scoped-imports, import-eager-closedness, parser
strictness, the dead-OR-branch + selectEvaluatedField DRY cleanups, and the next-audit
resolveEmbeddedDisjDefault confirm). All dropped history is preserved here (this log) + git.
Also added a periodic "plan-hygiene pass" bullet to `docs/guides/slice-loop.md`. This log is
now the canonical completed-work record; the lean plan is the authority for what is next.

---

## Slice: argocd-tlsroute-list-guard → link 3 + link 4 (2026-06-18)

The slice's named target (`#TLSRoute` list-element `if`-guards) was mis-diagnosed: the
minimal list-guard repro already passed (landed `3e0c84f`). Bisecting the REAL `defs.#TLSRoute`
bottom against `cue` (oracle `/Users/chakrit/go/bin/cue` v0.16.1) found TWO distinct root
causes, neither in the list-element guard machinery. Both are narrowing-timing bugs in the
embedding-`Self` two-pass gate and the open-struct parser representation.

### Root cause 1 — two-pass gate missed DEEP + LIST-COMPREHENSION self-refs (`Kue/Eval.lean`)

`refsSelfEmbeddedLabel` (the `needsEmbeddedSelfPass` gate) hard-matched `id.depth == 0` and
recursed into nested structs WITHOUT incrementing the depth it looked for — so a
`Self.<embedded-label>` read from a NESTED struct (`spec: { hostnames: Self.#hosts }`, depth 1)
was invisible, Pass 2 never fired, and the nested ref resolved against the un-augmented frame
→ `.bottom` (`#TLSRoute.spec.hostnames`, `#ListenerSet.spec.parentRef.name`). It ALSO had no
`.listComprehension` arm at all, so a list-comp SOURCE (`listeners: [for h in Self.#hosts {…}]`)
was unscanned → the comprehension iterated the un-narrowed (empty) embedded field and dropped
every element. Fix: thread a `depth` parameter (incremented on struct descents, mirroring
`hasSelfRefAtDepth`), match `id.depth == depth`, and add a `.listComprehension` arm to BOTH
`refsSelfEmbeddedLabel` and `hasSelfRefAtDepth`. This fully fixed `#TLSRoute` (all three real
test cases — basic, cross-ns gateway, listenerset — content-match cue).

### Root cause 2 — open struct (`...`) WITH embeddings split into a harmful `.conj` (`Kue/Parse.lean`)

`parsedFieldsValue` emitted `.conj [.structComp(embeds), .structTail(fields, tail)]` whenever a
struct had BOTH comprehensions/embeddings AND a `...` open marker. The two arms carry OVERLAPPING
fields; a `Self.<field>` self-ref landed in the `.structTail` arm, which never saw the
embedding-contributed fields, so a use-site narrowing collapsed to `.bottom`. This is the real
`defs.#ListenerSet` blocker (`parts.#Metadata` embedded + a def-level `...`). Fix: keep it ONE
node — the comprehension form already carries `open_ = true`, which is exactly what the bare `...`
(`.top` tail, the only supported tail) means; a definition-context one is closed by
`normalizeDefinitionValueWithFuel` like any `.structComp`. Dropped the `.conj` split for the
comprehension/pattern case (the plain-fields case keeps its `.structTail`).

### Tests

3 committed module fixtures (`testdata/modules/`): `open_embed_selfref_guard` (open def +
embed + nested `Self` read, cross-package), `listcomp_embed_selfref` (list-comp over embedded
field, narrowed), `listcomp_embed_selfref_empty` (guard-false → empty, no fabrication). All
cue v0.16.1-exact (whole-module JSON). 8 `Kue/Tests/EvalTests.lean` pins: 4 `needsEmbeddedSelfPass`
gate pins (deep self-select fires, listcomp source fires, nested listcomp source fires, nested
UNRELATED label does NOT fire — no over-defer) + 3 source-level cue-exact behavior pins (listcomp
narrows, guard-false stays empty, open-embed narrows) + the existing gate pins unchanged.

### Verify

`lake build` 86 jobs green, `fixture pairs ok` (zero drift, existing fixtures byte-unchanged),
shellcheck untouched. Real-app re-probe (read-only, prod9 `/Users/chakrit/Documents/prod9`):
- **cert-manager: STILL content-identical to cue** (`jq -S`). NO correctness regression.
- **argocd `defs.#Secret` (link 2): still content-matches cue.** No regression.
- **argocd `defs.#TLSRoute` (link 3): now content-correct vs cue** (all 3 cases, modulo
  field-order #3 — `metadata` ordering).
- **argocd `defs.#ListenerSet` (link 4): now content-correct vs cue** (`rt`/`ls` resources
  both match).
- **Full `kue export apps/argocd.cue` STILL bottoms — on a NEW link 5: `packs.#Argo`** (the
  `argo_.{stage9,…}.configs` sub-package). `packs.#Argo & {…}` bottoms in isolation (~36s, also
  perf-wall-adjacent). Distinct, deeper root cause (nested `defs.#ArgoRepo`/`#ArgoProject`/
  `#ArgoApp` embeds + their own guards). argocd is NOT a drop-in yet.

### Perf regression (recorded, SOUND — correctness-over-performance)

Both fixes increased eval cost: cert-manager ~31s → ~92s; `defs.#TLSRoute` ~4s → ~9s;
`defs.#Secret` ~3s → ~13s. Cause: the parser collapse routes `{embed; …; ...}` defs through the
single-`.structComp` two-pass path (more embed re-evaluation than the old `.conj` split), and the
two-pass gate now fires on more (deeper) refs. The change is SOUND (byte-identical fixtures +
correctness gain), so it ships per `docs/decisions/2026-06-18-correctness-over-performance.md`,
but it pushes more shapes toward the per-eval perf wall — folded into backlog item 7 (per-eval-cost
perf) as a now-more-urgent frontier.

---

## Completed Slice: def-open-tail-closedness (fix-slice 0 — HIGH correctness)

Goal: fix the link-3/4 audit's HIGH-severity Violation (`fc25a71`/`faf38b7`) — the parser
collapse silently CLOSED an OPEN definition that carries comprehensions/embeddings. `#D: {e, ...}`
(or `#D: {if c {b}, ...}`) then `#D & {extra}` bottomed; cue accepts (`...` opens the def).

### Root cause

A `.structComp` (the comprehension/embed-bearing struct node) carried a single `open_ : Bool`
that conflated TWO independent facts a definition vs a regular struct disagree on:
- a REGULAR struct is OPEN by default (the eager eval arm honors `open_`), and
- a DEFINITION is CLOSED by default, opened only by an explicit `...`.

The parser set `open_ = true` for every comprehension struct (regular default), and
`normalizeDefinitionValueWithFuel` (the def-context pass) hard-`false`d the `.structComp` arm to
close defs — but that ALSO closed a `...`-bearing def, because the `...`-presence was lost in the
collapse. One bool cannot encode three states (regular-open, def-open-via-`...`, def-closed); the
plain path avoids it with distinct node types (`.struct` vs `.structTail`), but the comprehension
path collapses both into `.structComp`.

### Fix (illegal-states-unrepresentable)

Added a second flag `hasTail : Bool` to `.structComp` (`Kue/Value.lean`). `open_` keeps its
meaning (regular host openness; the parser sets `true`, the eager arm honors it). `hasTail` records
whether the source had an explicit `...` (`parsedFieldsValue` sets `parts.tail.isSome`).
`normalizeDefinitionValueWithFuel` now sets the def body's openness from `hasTail`
(`open_ := hasTail`) instead of hard-`false` — so a def WITH `...` stays open and a def WITHOUT
`...` closes, exactly as cue. A regular struct never passes through normalize, so its `open_=true`
survives and it stays open regardless of `hasTail`. Threaded the new field through all 42
`.structComp` match sites (`Eval`, `Resolve`, `Format`, `Manifest`, `Lattice`, `Normalize`,
`Parse`) and the test literals (`EvalTests`, `FixturePorts`, `ResolveTests`, `PresenceTests`).

### Tests

New module fixture `testdata/modules/def_open_tail_addfield` (open def + embed + `if`-guard +
`...`, use site ADDS `added` past `...` → admitted; cue v0.16.1-exact whole-module JSON). 3 new
`Kue/Tests/EvalTests.lean` source-level pins (`evalSourceMatches`, full parse→normalize→eval):
`fix0_open_def_embed_comp_admits_added_field` (the regressed shape now works), `fix0_closed_def_
embed_comp_rejects_added_field` (NO over-open — same shape minus `...` rejects), `fix0_regular_
comp_struct_stays_open` (a regular comprehension struct stays open). The 6 EvalTests def-body
literals that modelled no-`...` defs were corrected from the old `open_=true` regular-default to
`open_=false` (they are closed defs).

### Verify

`lake build` 86 jobs green; `fixture pairs ok` (zero byte-drift — all existing fixtures
unchanged); shellcheck clean. Real-app re-probe (read-only, prod9): cert-manager STILL
content-identical to cue (`python3 -m json sort_keys`), ~88s wall. argocd link 3 (`#TLSRoute`)
resolves and is BYTE-IDENTICAL between the pre-fix HEAD binary and the FIX-1 binary (git-worktree
bisect at `e902553`) — FIX 1 introduces no link-2/3/4 regression. Full argocd still blocks on
link 5 `packs.#Argo` (unchanged).

---

## Completed Slice: Pass-2 selective re-eval (perf — embedding-`Self` two-pass)

Goal: reclaim the audit PART-B "+8/field redundant recompute" — the embedding-`Self` two-pass
(`.structComp` eager + force arms) re-evaluated EVERY static field against the Pass-2 augmented
frame, so a field that never reads `Self.<embedded-label>` was recomputed for nothing (a fresh
frame id → no Pass-1 `cache`/`satCache` hit).

### Fix

Added `embeddedSelfPassFieldIndices` (and a `selfReferencedLabels` collector) returning WHICH static
field indices the Pass-2 frame change can alter — the TRANSITIVE closure: a field is included iff it
reads `Self.<embedded>` directly, OR reads `Self.<L>` for a static label `L` whose own field is
included (fixpoint, bounded by field count). Both Pass-2 sites now feed ONLY the selected `(index,
field)` entries to `evalFieldRefsListWithFuel` (preserving each field's slot index so refs still
resolve against the full augmented frame), and splice the re-evaluated values back at their indices
over the reused Pass-1 list.

### Soundness

A field NOT in the closure does not depend, even transitively, on any embedded label, so its value
is identical under the Pass-2 frame (only the frame id differs, and frame id never enters a value —
only a memo key). The transitive closure is what makes this sound by construction: a field reading a
sibling that reads the embed IS included. The byte-identical fixture gate (`fixture pairs ok`, zero
drift) + byte-identical cert-manager output confirm it empirically. `fuel`/`truncCount` discipline
untouched (no new `fuel=0` path).

### Tests

6 `Kue/Tests/EvalTests.lean` pins on the audit's shape (open `{embed; …; ...}` def, 1 `dep: Self.et`
+ N `u_i: Self.base + i`): `selpass_reevaluates_only_dependent_field` (selection == `[2]` regardless
of N), `selpass_skips_static_sibling_reader` (a `Self.<static>` reader is NOT selected),
`selpass_eval_count_n2`/`_n6` (eval count 21/41 — LINEAR at +5/unrelated-field; pre-fix +10/field,
so a re-broadening regression trips them), `selpass_value_correct` (`Self.et` still resolves, the
unrelated fields keep their Pass-1 values).

### Verify + the honest perf finding

`lake build` 86 jobs; `fixture pairs ok` (zero byte-drift — HARD gate for a perf change); shellcheck
clean. Eval-count micro-benchmark: on the audit shape the per-unrelated-field Pass-2 cost dropped
+10 → +5 (n=8: 94 → 51 core evals, ~46%) — the modeled redundancy IS eliminated.

BUT the cert-manager wall-clock did NOT drop: ~88-104s across samples (FIX-2) vs ~94-111s
(FIX-1-only) — the ±15-20s run-to-run variance swamps any difference; cert-manager content stays
byte-identical to cue. So the cheap fix is SOUND and removes the modeled redundancy, but it does NOT
reclaim the 31s→92s regression — cert-manager's cost is dominated by something else (the broader
frame-id divergence, backlog item 7's deeper lever — canonical frame identity), not the per-field
Pass-2 recompute. The cheap, local win ships (it helps any def with many unrelated fields + few
`Self.<embed>` reads, e.g. `packs.#Argo`-class shapes), but the headline cert-manager regression
needs the frame-id-canonicalization lever, which remains item 7's open work.

## argocd-packs-argo — link 5 (`packs.#Argo`) unblocked: a 4-link correctness chain (2026-06-18)

Commits `8ce2462`, `6436d08`, `14994e6`, `7898cff`. The live real-app blocker: full
`kue export apps/argocd.cue` bottomed on `packs.#Argo` (the `argo_.{stage9,…}.configs`
sub-package). Bisected with FAST offline repros (a `/tmp` scratch module pointing `deps` at
`prodigy9.co/defs@v0.3.19` in the real cache — never the ~36s app). `packs.#Argo & {[...]; …}`
bottomed in isolation; the bottom was a CHAIN of four independent root causes, each fixed and
pinned as its own commit. Result: `packs.#Argo` and all three components (`#ArgoRepo`/`#ArgoApp`/
`#ArgoProject`) now content-identical to cue (sorted-key, modulo field-order #3).

### Sub-fix 1 (`8ce2462`) — list-embed use-site narrowing
A def whose only manifested content is a trailing LIST embed reading `Self.<hidden>` (so it
manifests AS that list). The use site `#Argo & {[...]; #name: "web"}` is a struct-embedding-an-open-
list operand; it evaluates to an `.embeddedList` whose `decls` carry the narrowing (`#name:"web"`).
The conjunction-deferral fold built `useOperands` via `evaluatedStructOperand?`, which returns
`none` for an `.embeddedList` — so the narrowing was DROPPED and the def's list embed read the def
default. Fix: `spliceNarrowingOperand?` (deferral-fold-only) surfaces `.embeddedList` decls for the
splice; the list still unifies at the value `meet`. Pins: module `list_embed_self_narrowing` +
3 EvalTests (`link5_list_embed_*`).

### Sub-fix 2 (`6436d08`) — hidden-bottom propagation + optional-aware arm pruning
The `defs.#ArgoRepo` disjunction-of-defs embed `(_#ArgoRepoGitHubApp | _#ArgoRepoPAT | error)`,
each arm declaring the OTHER arm's selector impossible (`#username?: _|_`). Two coupled causes:
(1) `containsBottom` counted an UNSET impossible OPTIONAL field (`#u?: _|_`) as bottoming its arm,
pruning BOTH arms → `_|_` (cue keeps both). Fix: `fieldBottomCounts` skips OPTIONAL fields in the
struct bottom-check — only a PRESENT field's bottom bottoms the struct. (2) Manifest dropped a
hidden present field's bottom silently. Fix: propagate a hidden field's bottom at manifest. Pins:
module `disj_arm_kill_impossible_field` + 4 FixtureTests + 2 EvalTests (`link5_disj_*`).

### Sub-fix 3 (`14994e6`) — REGRESSION fix for sub-fix 2's manifest recurse
Sub-fix 2's manifest check used `manifestWithFuel` to recurse the WHOLE hidden-field subtree, which
over-fired and bottomed `kue export apps/cert-manager.cue` (regression vs `8ce2462`): an imported-
PACKAGE binding (`defs`/`parts`) is a hidden field whose package struct carries `tests`/unreferenced
definitions with isolated conflicts cue is LAZY on and never evaluates. Fix: the hidden-bottom check
is SHALLOW (`isBottom` on the field value, no recursion) — SOUND (never a false error → no
regression), catches explicit-bottom/conflict-that-propagates + the arm-kill (which prunes at EVAL
anyway). A nested-non-propagating hidden bottom (`{#u: {#c: string & int}}`, which cue bottoms) is a
KNOWN incompleteness (needs imported-package laziness, not eager deep checking — deferred).
cert-manager byte-identical to the `8ce2462` baseline. Pin: `link5_hidden_nested_conflict_does_not_overfire`.

### Sub-fix 4 (`7898cff`) — presence test over a disjunction is present
`#ArgoRepo` then exported but was MISSING `metadata.namespace: "argocd"`: the `parts.#Metadata`
guard `if Self.#ns != _|_ {namespace: Self.#ns}` over `#ns: *"argocd" | string` never fired.
`classifyDefinedness` (the `!= _|_` presence test) classified a `.disj` as `.incomplete`. Fix:
a `.disj` is `.defined` (present) — cue: `(*"argocd"|string) != _|_` is `true`; an all-bottom
disjunction never reaches the classifier (`liveAlternatives` prunes). Pins: module
`disj_presence_guard` + 2 EvalTests (`link5_presence_test_*`).

### Verify
`lake build` 86 jobs across all four; `fixture pairs ok` (zero drift, every existing fixture
byte-unchanged); shellcheck clean. cert-manager byte-identical to baseline (no regression).
`packs.#Argo` (scratch) content-identical to cue (6179 bytes, ~71s — perf-wall-adjacent, the queued
frame-id-canonicalization work, plan item 7). The L3 inline-`Self=`-disjunction-collapse shape I
bisected en route is NOT on the `packs.#Argo` path (the real arms read host-supplied `Self.#url` via
the proper embed-Self mechanism); logged as a separate latent shape, not a blocker.

---

## Completed Slice: catch-all soundness hardening sweep (A1 + B1 + Normalize)

Goal: close two HIGH soundness holes of one class (a catch-all over `Value` silently
swallowing compound constructors a recursive function MUST descend into), then grep the
whole `Kue/` graph for siblings. Audit fix-slices A1 + B1, plus a graph-wide sweep.

### A1 + B1 (`80df01e`) — `Eval.lean` self-ref scanners + conj remap
`selfReferencedLabels` / `refsSelfEmbeddedLabel` ended in `| _ => []` / `| _ => false`,
swallowing `builtinCall`/`embeddedList`/`structPattern`/`structPatterns` — so a
`Self.<embedded-label>` read inside a builtin arg (`count: len(Self.#x)`) was invisible to
the Pass-2 gate AND the selective-re-eval selection set, leaving the builtin-wrapped field
on its stale Pass-1 value after `2d87b8e`. Added arms to BOTH: `builtinCall` args at the
enclosing depth; `embeddedList` items/tail at depth, decls at depth+1; `structPattern`/
`structPatterns` fields/labelPattern/constraint/patterns at depth+1. The residual catch-all
now only catches scalar leaves + `closure` (captured-env body, not the host `Self` frame).

`remapConjRefs` (the conj-frame-remap rebasing a conjunct's `.refId`s onto a merged frame)
ended in `| _, value => value`, swallowing `.structComp` (the dominant `{embed;…;...}`
`#Def` conjunct shape), `.comprehension`, `.listComprehension`, `.embeddedList`,
`.dynamicField` — a swallowed conjunct kept STALE frame indices after a field-reindexing
merge → wrong resolution or spurious bottom. Added recursing arms (structComp fields +
comprehensions at frameDepth+1; comprehension/listComprehension clause sources/guards +
body at frameDepth via a new `remapConjClauses` mutual helper; embeddedList items/tail at
frameDepth, decls at frameDepth+1; dynamicField label+value). `closure` stays in the
catch-all — its body's refs live in the captured-env coordinate space, not the conjunction
frame, so remapping would corrupt them.

Pins (native_decide, EvalTests): the gate fires / the selection set includes a
`len(Self.x)`-wrapped read (direct + nested), with a no-over-fire negative on an unrelated
label; `selfReferencedLabels` descends a builtin arg; structComp / structComp-comprehension
/ bare-comprehension / dynamicField conjuncts reindex their inner `.refId`s across a
field-reindexing merge. End-to-end (oracle-checked vs cue 0.16.1): `count: len(Self.#hosts)`
over a use-site-narrowed embedded label refreshes to the narrowed count (`1`, not the
un-narrowed `0`).

### Sweep finding (`a7b2724`) — `Normalize.lean` def normalizers
The graph-wide grep for the same class found two more unsound catch-alls.
`normalizeDefinitionValueWithFuel` (closes def bodies) and `normalizeDefinitionsWithFuel`
(spine-walks normalizing def fields) both ended in `| _, value => value`, swallowing
`.list`/`.listTail`/`.embeddedList`/`.comprehension`/`.listComprehension`/`.interpolation`/
`.dynamicField` (and `.structComp` for the spine walker). So a definition FIELD whose value
is directly a list/comprehension carrying a nested `#Def` never had that nested def closed
(admitted extra fields where CUE rejects). CUE closes nested struct literals within a
definition body (verified: `#D: {l: [{a:1}]}` then `#D.l[0] & {b}` is rejected), so the new
`normalizeDefinitionValueWithFuel` arms descend with the CLOSING normalizer; comprehension
clause sources / dynamicField labels / interpolation parts are expressions where closing a
non-struct is a no-op. The spine walker descends with itself (non-closing). Both catch-alls
now catch only scalar leaves + `closure`. Pins (native_decide, NormalizeTests): a def field
whose value is a `.list` / `.comprehension` body carrying a nested `#Def` now closes it
(`open_` false). Oracle-confirmed a def-field list nested def now bottoms an extra field
(`#D.#L[0].#Inner & {bad}` → bottom, matching cue).

This sweep surfaced a SEPARATE, larger downstream gap, filed as plan item **B6** (not fixed
here): `normalizeFieldWithFuel` descends ONLY definition fields, so a nested `#Def` under a
REGULAR field is never normalized; and the eager nested-selector path does not enforce a
closed nested def's closedness even once normalize closes it (`import-eager-closedness`
family). Both reachable, both a behavior change with def-open-tail regression risk → own
design-spike slice.

### Defensible catch-alls (swept, left, noted)
`resolveValueWithFuel:145` + `evalValueCoreWithFuel:2181` (pre-cleared, re-confirmed);
`meetWithFuel` (delegates to exhaustive `meetCore`); `subsumesWithFuel` (false on
non-matching pairs is correct for a partial order); `selectEvaluatedField`/`lookupField?`/
`closeValue` (struct-specific by design); `Format`/`Manifest` (no Value catch-all — fully
enumerated).

### Verify
`lake build` 86 jobs green (both commits); `fixture pairs ok` (zero byte-drift, every
existing fixture unchanged); no shell scripts changed (shellcheck N/A). Pushed `gh:main`
(`adf7caf..a7b2724`).

---

## Completed Slice: A2 + A3 audit fix-slices (disj-definedness; hidden-bottom gap deferred)

Goal: clear the two remaining MEDIUM Phase-A correctness findings. A3 landed; A2's
proposed fix proved unsound and was reverted to the sound baseline with the proper
design filed.

### A3 — classify a disjunction's definedness by its LIVE arms (`96bef05`)

`classifyDefinedness` (Eval.lean) classified `.disj _ => .defined`, sound only under the
runtime invariant "an evaluated disj has ≥1 live arm" (`liveAlternatives` prunes bottom
arms). The invariant is NOT type-enforced: a `.disj []` / `.disj [all-bottom]` slipping
past pruning into a presence test (`X != _|_`) would misclassify an absent value as
`.defined` (wrongly `true`). Fix: classify by the LIVE alternatives — no live arm ⇒
`.error` (the disjunction IS bottom), ≥1 live arm ⇒ `.defined` — checking the invariant
at the one site soundness depends on it.

Chose this defensive classification over option (a), a blanket smart `mkDisj` routing all
eval-time disj constructions through `normalizeDisj`: several sites build a `.disj` where
pruning would be WRONG (`remapConjAlternatives` rebuilding a disjunction during
alpha-renaming; the conj-distribution sites), so a universal prune is not
semantics-preserving in one slice. The live-arm classification is total, representation-free,
and sound regardless of how the disj was constructed.

Pins (PresenceTests, native_decide): live disj `.defined`; empty disj `.error`; all-bottom
disj `.error`; presence test over an all-bottom disj reports absent (`!= _|_` = false).
Regression-checked the live default/plain disj guard (`#ns: *"argocd" | string` then
`if #ns != _|_ {namespace}`) still fires, byte-identical to cue v0.16.1.

### A2 — hidden-field deep bottom: UNSOUND fix reverted, design filed (`46bd161`)

A2 asked to propagate a hidden-field bottom REACHED in the selected value
(`{#u: {x: _|_}}` → error, matching cue) while keeping cue's laziness on unreferenced
imported-package content (the cert-manager need). Implemented the diagnosed output-spine
recurse, then disproved it: a 3-file local repro (a `main` importing a `dep` package whose
unreferenced fields carry BOTH a derived conflict AND an explicit `_|_` literal) shows cue
exports `main` cleanly — cue's laziness tracks OUTPUT-REACHABILITY (referenced via
`pkg.#X`), NOT field class, and is equally lazy on an explicit `_|_` literal as on a derived
conflict. `bindImports` (Module.lean:160) binds each imported package as an ordinary
`FieldClass.hidden` field, indistinguishable from a real in-file `#u`; the output-spine
recurse re-bottomed cert-manager and the repro. The reached-vs-unreferenced predicate is NOT
locally reconstructible at manifest with the current representation.

Per correctness-over-performance (no possibly-wrong value), reverted to the SOUND shallow
`isBottom` check (never a false error; catches `{#u: _|_}`, knowingly misses
`{#u: {x: _|_}}`) and rewrote the comment to record the hole. Filed **A2-followup** in
plan.md: add an import-binding marker (a distinct `FieldClass` axis / value wrapper on the
synthetic hidden field) so manifest can treat bound packages as cue-lazy while still
recursing real in-file hidden fields. That unblocks the `{#u: {x: _|_}}` → error fix
(+ fixture). No fixture asserting the wrong current behavior was added.

### Verify
`lake build` 86 jobs green (both commits); `fixture pairs ok` (zero byte-drift); no shell
scripts changed (shellcheck N/A); cert-manager import laziness confirmed unchanged via the
local repro (kue exports `{out:{ok:1}}` = cue). Two-phase audit now DUE (2 slices since the
last: A1+B1 sweep, this A2+A3).

## Completed Slice: A5 — comprehension-body frame-depth regression (3 walkers)

**Commit:** `c3d0089`. A5 fix-slice (top of the live backlog; B1 `80df01e` regression).

**Root cause.** A comprehension BODY lives `#forClauses` frames deeper than the
comprehension node (`for` pushes a frame, `guard` does not) — the single authority is
`resolveClausesWithFuel` (`Resolve.lean:52-67`). Three walkers re-derived this by hand and
recursed the body at FLAT depth, so a body ref to the deeper frame (at `depth+#for`) was
compared `== depth` and missed:

1. **A5 proper (wrong VALUE).** `remapConjRefs`/`remapConjClauses` (`Eval.lean`) remapped a
   comprehension-conjunct body at flat `frameDepth` on the lazy-conjunction-merge path,
   leaving a body ref to a merged-conjunction sibling at its stale conjunct-local slot.
   Repro `t: {s:{p:10,q:20}} & {s:{a:{for v in [1] {out: zz}}, zz:99}}`: cue 0.16.1 →
   `s.a.out: 99`, kue → `20`.
2. **Sibling — `selfReferencedLabels`** (Pass-2 selection seed): same flat scan → a
   `Self.<embedded>` read inside a `for` body not collected → field skipped in Pass-2.
3. **Gate — `refsSelfEmbeddedLabel`**: same flat scan. The old comment claimed too-shallow
   only over-fires (perf); BACKWARDS — too-shallow compares a deep read against the wrong
   depth, MISSES it, returns false, SKIPS the two-pass = stale-value miss. Fixed too.

**Fix.** New `clauseFrameShift : List (Clause Value) → Nat` (+1 per `for`, +0 per `guard`)
as the shared shift; `remapConjClauses` increments `frameDepth` per `for` clause (clause N's
source at `frameDepth + #for-before-N`) and the comprehension arms remap the body at
`frameDepth + clauseFrameShift clauses`. The two scanners gained depth-threading helpers
(`selfReferencedLabelsClauses`, `refsSelfEmbeddedLabelClauses`) mirroring resolution; both
parent defs became `mutual` blocks. B7 (typed frame coordinate) remains the structural fix
that would make all 4 walkers consume one authority and a recurrence a compile error.

**Pins.** Replaced the misleading `remap_comprehension_conjunct_reindexes_source_and_body`
(hand-built a body ref at depth 0 — UNREACHABLE after real `for` resolution, so it passed
while the behavior was broken) with realistically-resolved native_decide pins: body one/two
frames deep, multi-`for` depth threading, guard-no-frame, and a `clauseFrameShift` authority
pin. Added an end-to-end source fixture `testdata/cue/comprehensions/comprehension_conj_body_remap`
(+ FixturePort, parse-driven) oracle-checked vs cue 0.16.1, plus unit pins for the two sibling
walkers' deep-read detection.

**KNOWN-FOLLOWUP (A5-followup, filed in plan).** The OBSERVABLE wrong value — a static field
reading `Self.<embedded>` inside a `for` body, narrowed at the use site (`#R & {#t:"y"}`) —
does NOT yet flip with these depth fixes alone: the field is selected and the gate fires, but
Pass-2 re-eval does not refresh the comprehension-valued field's body against the augmented
frame (it keeps the Pass-1 expansion). That is a distinct Pass-2 re-eval gap, filed as
A5-followup; the depth fixes are its sound prerequisite. No fixture asserting the still-wrong
value was added.

### Verify
`lake build` 86 jobs green; `scripts/check-fixtures.sh` → `fixture pairs ok` (zero
byte-drift — the cert-manager/argocd-derived module fixtures `open_embed_selfref_guard`,
`structcomp_lazymerge_guard`, `listcomp_embed_selfref`, etc. all byte-identical = the
correctness regression gate). No shell scripts changed (shellcheck N/A). Real-app exports
(cert-manager, fx, keel, n8n via `kue export -e <app> ./apps`, READ-ONLY) all hit the
documented PERF WALL (timeout, exit 124) regardless of this change — not a correctness
regression; module fixtures are the completing correctness signal.

---

## Completed Slice: A5-followup — comprehension-body self-ref deferral gate

Goal: flip the OBSERVABLE wrong value left by A5 — a static field whose value is a
comprehension reading `Self.<embedded>` inside a `for` body, narrowed at the use site,
kept its stale Pass-1 value. Landed in `e00c3de`.

```
#H: {#t: string | *"def"}
#R: Self={#H, out: [for x in [1] {v: Self.#t}]}
v: #R & {#t: "y"}   # cue v0.16.1 → v.out[0].v: "y"; kue (pre-fix) → string | *"def"
```

### Mechanism (the A5-followup plan diagnosis was the symptom, not the cause)

The plan filed this as a "Pass-2 re-eval gap" — Pass-2 selective re-eval not refreshing the
comprehension-valued field's body. Tracing showed that was the *symptom*. The real defect is
in the DEFERRAL GATE, one layer earlier: `#R & {#t: "y"}` never reached the Pass-2 arms at
all. It took the eager-then-meet path.

`hasSelfRefAtDepth` (the gate `defBodyHasSiblingSelfRef`/`bodyNeedsDefer`/the `.conj` fold use
to decide whether a self-ref def DEFERS to a closure) scanned a comprehension BODY at the
comprehension node's own `depth`, ignoring the loop frame each `for` pushes. A `Self.#t` read
in the body resolves to `refId ⟨depth + #forClauses, _⟩`; scanned at `depth` it compared
unequal and was MISSED. So `#R` was judged to have no sibling self-ref → the conj evaluated
`#R` eagerly STANDALONE (producing the embedding default `string | *"def"`), then met with
`{#t: "y"}`. The meet narrows the scalar `#t` field but cannot re-expand the comprehension —
hence the stale `out`. The closure-FORCE path (taken when the gate fires) splices the
use-site narrowing into the frame BEFORE the body is evaluated, so the comprehension resolves
against the narrowed `#t`; it is the already-correct, already-perf-optimized arm. Routing the
conj to it is the entire fix — Pass-2 selective re-eval is untouched, no full-re-eval
regression.

This is the FOURTH frame-depth walker in the A5 family. A5 fixed `remapConj*`,
`selfReferencedLabels`, `refsSelfEmbeddedLabel`; this one (`hasSelfRefAtDepth`) was missed.
The old arm comment claimed scanning the body at `depth` "over-detects only, never misses" —
false: a too-shallow body scan UNDER-detects every loop-deep self-ref (the miss observed here).

### Fix

`hasSelfRefAtDepth` became a `mutual` block with `hasSelfRefAtDepthClauses`, which threads
the frame depth through the clause chain exactly as `resolveClausesWithFuel` and the three
A5 walkers do (+1 per `for`, +0 per `guard`). The `.comprehension`/`.listComprehension` arms
route through it; the body self-ref at `depth + #forClauses` is now detected. B7 (typed
frame coordinate) remains the structural fix that would have made this a compile error — five
walkers now re-derive the shift by hand.

### Pins

End-to-end fixture `testdata/cue/comprehensions/comprehension_embed_self_narrow_body` (parse-
driven FixturePort, oracle cue v0.16.1 → `v.out: [{v: "y"}]`, `v.#t: "y"`) — the pin A5
deliberately did not ship because it would have failed. `native_decide` gate pins: list-comp
body self-ref detected; loopvar-ref boundary (no over-detection); multi-`for` (depth+2);
`guard` adds no body frame; struct-context clause helper. Edge cases (guard / multi-for /
nested comprehension / a body reading a DIFFERENT embedded label than the narrowed one)
oracle-confirmed during development — no over/under-refresh.

### Verify

`lake build` 86 jobs green (native_decide pins build-checked); `scripts/check-fixtures.sh` →
`fixture pairs ok` (zero byte-drift — the A5 module fixtures `open_embed_selfref_guard`,
`structcomp_lazymerge_guard`, `listcomp_embed_selfref`, `list_embed_self_narrowing` all
byte-identical = the no-regression gate; spot-checked byte-equal to the live `cue` oracle).
No shell scripts changed (shellcheck N/A). cert-manager/argocd hit the documented perf wall
(timeout) as before — module fixtures are the completing correctness signal.

---

## Completed Slice: B7 — unify the five frame-depth clause walkers behind one authority

Commits `bbb00b2` (1/4), `c5cbb0e` (2/4), `aa5518c` (3/4), this commit (4/4). Behavior-
PRESERVING refactor: the comprehension clause-chain frame-depth rule (`+1` per `forIn`,
`+0` per `guard`, body at the accumulated depth) was hand-re-derived at five walkers. The
bug had recurred FOUR times (A1's sibling, A5, A5-followup, the #3 backwards-reasoning
walker) — each independent re-derivation a fresh chance to get the de Bruijn shift wrong.
B7 collapses the rule to ONE authority so a sixth walker physically cannot re-derive it.

### Design (option (b) — a shared fold, NOT a `Depth` newtype)

`descendClauses {α} (empty append onSource onGuard onBody depth) : List (Clause Value) → α`
in `Value.lean` (the leaf where `Clause` is defined, imported by both Resolve and Eval).
Pure, total, structural on the clause list, `Value`-non-recursive: it threads depth only
and hands each piece back to the caller's `onSource`/`onGuard`/`onBody`, generic over the
accumulator with a monoid-like `(empty, append)`. A thin `clauseChainDepth start clauses`
(the fold with an identity body-handler) recovers the post-chain depth, replacing the
former standalone `clauseFrameShift`. The `Depth` newtype (option (a)) was rejected: ~24
arm rewrites + `DecidableEq`/kernel cost on the hot resolve path for zero new guarantee —
the recurring bug is the per-walker *re-derivation*, not a raw `+1`.

### Migration (four fixture-gated commits)

1. `bbb00b2` — introduce `descendClauses` + `clauseChainDepth` in `Value.lean`; add two
   `native_decide` agreement theorems (`descend_clauses_chain_depth_counts_only_for`,
   `descend_clauses_frame_count_matches_resolve` — the latter ties the fold to
   `resolveClausesWithFuel`'s scope-push count without coupling their code). Pure addition.
2. `c5cbb0e` — migrate the three scanners (`refsSelfEmbeddedLabelClauses`,
   `selfReferencedLabelsClauses`, `hasSelfRefAtDepthClauses`) to one-line `descendClauses`
   instantiations (Bool ‖/false, List ++/[]). They are no longer self-recursive; the mutual
   blocks shrink. Existing A5/A5-followup pins are the regression gate.
3. `aa5518c` — `remapConjRefs`'s `.comprehension`/`.listComprehension` body shift now uses
   `clauseChainDepth frameDepth clauses`; **`clauseFrameShift` DELETED**. It was the second,
   inequivalent encoding of the rule living only in `remapConjRefs` (the sharpest recurrence
   hazard). New pin `descend_clauses_agrees_remapConjClauses` ties the body fold to the
   clause-list rebuild.
4. (this commit) — final verify + docs.

### The fifth walker stays the reference

`resolveClausesWithFuel` (`Resolve.lean`) threads a *scopes stack*, not a `Nat`, and is
`mutual` with `resolveValueWithFuel`. Forcing it through the `Nat` fold is churn for no
safety; instead `descend_clauses_frame_count_matches_resolve` proves the fold and the
reference agree (the body depth resolve reaches == `clauseChainDepth`). So the "single
authority" is `descendClauses` for the four migrated Eval walkers, with a theorem tying it
to resolve.

### New guarantee

Future drift between the fold and any walker / the resolver is now a build /`native_decide`
failure rather than a silent wrong value — the structural pin this slice buys. No new
behavioral fixture (nothing behavioral changed).

### Verify

`lake build` 86 jobs green; `scripts/check-fixtures.sh` → `fixture pairs ok` (ZERO byte-
drift across all four commits — the whole correctness gate for a behavior-preserving
refactor). The two B7-relevant fixtures (`comprehension_conj_body_remap` → `s.a.out: 99`;
`comprehension_embed_self_narrow_body` → `v.out: [{v: "y"}]`) spot-checked content-identical
to live `cue` v0.16.1. No shell scripts changed (shellcheck N/A). Pure refactor, no eval-path
change → perf unchanged (no `kue-performance.md` edit).

## Completed Slice: test-org pass (EvalTests split) + B4 LatticeTests (2026-06-19)

Two-part slice landing the overdue test/fixture-organization pass (plan item 5, flagged by
Phase-B #3) and a dedicated `LatticeTests` (B4) that de-risks the headline B2
struct-constructor refactor by pinning the `meet`/`join` arms B2 will collapse.

### Part 1 — `EvalTests.lean` split (behavior- and coverage-preserving)

`EvalTests.lean` had grown to ~3022 lines. Split it into per-subsystem modules mirroring
`Kue/`'s structure, cutting at the existing section seams (each block already clustered by
topic with its own local helpers). The hard constraint was coverage preservation: every
theorem/`native_decide` that ran before must still run.

New modules (line counts approximate):

- `Kue/Tests/EvalTestHelpers.lean` (~20) — the shared source-oracle helpers.
  `evalSourceMatches` (used 54× across the original file, so it cannot live in any one
  split module) plus the new `exportJsonMatches` (JSON `export` observable, added for
  LatticeTests). Imported by all the split modules.
- `Kue/Tests/EvalPerfTests.lean` (~470) — frame-id sharing, Pass-2 selective re-eval,
  fuel-saturation caching, perf-B memo false-share pins (orig lines 114–577; owns the
  `deepInline*`/`selPass*`/`sat*`/`twoPushIds`/`evalTwiceAt`/`evalOnceAt` helpers).
- `Kue/Tests/ClosureTests.lean` (~762) — `Value.closure` ctor/eval/producer/meet,
  multi-level embed chains, structcomp-force, import-selector aliases (orig lines
  1671–2417; owns the `pkgEnvWith`/`selfRefM`/`chain*`/`alias*` helpers).
- `Kue/Tests/TwoPassTests.lean` (~611) — two-pass self-ref gate, B1/A1/A5 `remapConjRefs`,
  B7 `descendClauses` agreement theorems, hidden-def + embed-disj narrowing (orig
  2418–3021).
- `Kue/Tests/EvalTests.lean` (slimmed, ~1210) — ref/selector/cycle eval,
  arithmetic/ordering/ unary, list-comprehension parse+eval, scalar-embed collapse, F1
  default-mark algebra, refs/aliases, lazy-chain merge (orig lines 9–113 + 578–1670).

All four new modules wired into `Kue/Tests.lean`. Coverage verified exactly pre/post by
counting test constructs across the five files: theorem 256→256, native_decide 253→253,
def 28→28. `testdata/` left untouched (clean, no churn risk). NOT split this pass (future
test-org ride-along): `FixturePorts` (generated — leave whole), `FixtureTests`,
`StructTests`, `BuiltinTests`.

Helper locality was verified before cutting: all per-block helpers are referenced only
within their block; `evalSourceMatches` was the sole cross-cutting helper, so it (and the
def of `exportJsonMatches`) moved to `EvalTestHelpers`. The first cut attempt mis-placed a
leading `/--` doc comment (the doc for the next block's first theorem) at a module
boundary, which broke the build (dangling token before `end`); fixed by cutting at the
theorem-end seam, not the doc-comment seam.

### Part 2 — `Kue/Tests/LatticeTests.lean` (B4 + B2 regression gate)

Dedicated `meet`/`join` algebra pins (27 theorems): lattice laws (top/bottom identity +
absorption), scalars, kinds, bounds, regex, lists, disjunctions, and — the de-risking
focus — the struct-shape arms B2 collapses.

Two pinning layers, chosen by what survives the B2 refactor:

- **Scalar/kind/bound/regex/list/disjunction** — pinned at the `meet`/`join` constructor
  level (RHS values touch no struct constructor, so B2 cannot change them).
- **Struct-shape arms** — pinned at the SOURCE level via the new `exportJsonMatches` (JSON
  `export`), NOT via the internal `.structTail`/`.structPattern` constructor RHS. B2
  collapses those five constructors, so a constructor-RHS pin would break by construction
  (false regression). The JSON export shows only concrete fields — B2 must preserve those.
  (The CUE-syntax `eval` output keeps `...`/`[string]: T` decoration that B2 re-renders,
  so it was the wrong observable; the first draft used `evalSourceMatches` against eval
  output and the struct pins failed — switched to `exportJsonMatches`.) Covered:
  struct×struct (open merge + closed-def reject), structTail×structTail,
  structPattern×structPattern, structPattern×structPatterns,
  structPatterns×structPatterns. `StructTests` already covers tail×struct and
  pattern×struct at the constructor level, so those are not duplicated.

**B2-target missing arms (option b — documented, NOT pinned).** `meetWithFuel` is missing
`structPattern×structTail` and `structPatterns×structTail` (both orders): they fall
through the catch-all `| value, other => meetCore …` (`Lattice.lean:1151`) to `meetCore`,
which bottoms all struct combos. Oracle-confirmed Kue bug vs cue v0.16.1: `{[string]: int}
& {a: 5, ...}` → cue `{a: 5}`, kue `_|_`. Per the A2 rule (never pin wrong behavior with a
passing test) and because the Lean harness has no expected-fail/xfail marker (a `theorem`
is an all-or-nothing build check), these are documented in the `LatticeTests.lean` module
header and in the plan's B2 entry rather than given a passing wrong-behavior test. NOT
recorded in `cue-divergences.md` — that file is for cases where cue is wrong and Kue is
right; this is the opposite (Kue wrong). The plan's stale "`structPattern×structPatterns`
also missing" claim was corrected: that cross-arm is implemented
(`Lattice.lean:1015-1034`) and is now pinned as a B2 regression gate.

### Verify

`lake build` 96 jobs green (all 256+27 theorems / 253+13 `native_decide` build-checked);
`scripts/check-fixtures.sh` → `fixture pairs ok` (ZERO byte-drift) after BOTH parts. No
shell scripts changed (shellcheck N/A). The split is a pure test-reorg (no `Kue/` source
change), so perf is unchanged (no `kue-performance.md` edit). Struct-arm expectations
oracle-checked against `cue` v0.16.1.

## Completed Slice: B2.1 — introduce `StructOpenness` + `Value.structN` + `mkStruct` (2026-06-19)

First step of the B2 struct-unification refactor (5-slice plan in `plan.md` B2 entry).
Introduces the target representation WITHOUT migrating any behavior — `structN` has no
producer, so all fixtures stay byte-identical.

### What landed

- **`StructOpenness`** (`Value.lean`, before `BindingId`): `regularOpen | defClosed |
  defOpenViaTail`, `deriving Repr, BEq, DecidableEq`. Three mutually-exclusive states erase
  the conflated `open_`/`hasTail` nonsense pair. Helpers: `isOpen`, `ofBool` (= the
  design's `boolOpen`), `meet` (= `meetOpenness`: closed dominates, `defOpenViaTail`
  preserved against any open, two opens stay open).
- **`Value.structN fields openness tail patterns`** added after `structPatterns`. Carries
  `tail : Option Value` and `patterns : List (Value × Value)` TOGETHER — the orthogonality
  the old four forms could not express (root of the missing `structPattern×structTail`
  meet arm). `valueTag` = 31. Named `structN` to coexist with the old `struct`; B2.4 deletes
  the four old forms and renames `structN → struct`.
- **`mkStruct` in `Lattice.lean`** (beside `patternStructValue`), the only sanctioned
  builder. Enforces two invariants locally: pattern dedup (`dedupPatterns`, first-occurrence
  kept, `BEq`) + tail/openness coherence (`coherentTail`: `tail = some _ ↔ openness =
  .defOpenViaTail`; a `some` tail forces `defOpenViaTail`; bare `defOpenViaTail` defaults
  `some .top`; non-tail openness forces `none`).
  - **Divergence from the design (resolved by philosophy):** the design had `mkStruct` call
    `canonicalizeFields`, but that lives in `Eval` (downstream of `Value` AND `Lattice`) — a
    layering violation. Kept field ordering as the CALLER's job (callers already canonicalize
    before `patternStructValue` today); `mkStruct` owns only what it can enforce without an
    upward dependency. B2.2 preserves the caller-canonicalize contract.
  - The design's `meetTail` helper is a B2.4 merge concern — NOT added dead in B2.1.

### Dead arms (5 sites — `structN` has no producer in B2.1)

Every exhaustive `Value` match WITHOUT a catch-all forced an explicit `.structN` arm (no `_`
per the type-first rule); each is dead-but-required and tagged `-- B2.1 dead arm … filled in
B2.3`. B2.3 must revisit each:
- `Lattice.meetCore` → `.bottom` (the bottoms-everything fallthrough; the real
  `structN×structN` merge is ONE arm in `meetWithFuel` in B2.4).
- `Format.formatValueWithFuel` → `{` fields ++ patterns ++ optional tail `}` (mirrors the
  four legacy struct arms).
- `Manifest.manifestWithFuel` → manifest fields only, tail/patterns/openness dropped
  (mirrors legacy — those never appear in output).
- `Eval.classifyDefinedness` → `.defined` (like `struct`/`structTail`). **B2.3 caveat:** old
  `structPattern`/`structPatterns` classify `.incomplete`, so a PURE pattern-struct `structN`
  (no fields) must be reconciled when producers land.
- `Eval.valueTag` → 31 (total tag table, not behavioral).

Every OTHER struct-family match site already uses a catch-all and needed NO change —
confirming the B2.1/B2.3 boundary is clean (the new-arm work did NOT bleed into B2.3).

### Theorems (`LatticeTests.lean`, `native_decide`)

All pin via `BEq` `==` — `Value` has no `DecidableEq` (the perf carve-out), so propositional
`=` is undecidable. `mkStruct_some_tail_forces_defOpenViaTail`, `_some_tail_closed_coerced`,
`_defOpenViaTail_no_tail_defaults_top`, `_regularOpen_stays_tailless`, `_defClosed_stays_tailless`,
`_always_coherent` (all six openness×tail inputs via `structNTailCoherent`), `_dedups_patterns`,
`_dedup_idempotent`, `_keeps_distinct_patterns`; `openness_meet_closed_dominates`,
`_tail_preserved`, `_open_idempotent`.

### Verify

`lake build` green (all new theorems build-checked); `scripts/check-fixtures.sh` → `fixture
pairs ok` (ZERO byte-drift — nothing behavioral changed). No shell scripts changed
(shellcheck N/A). Perf unchanged (no producer on any hot path; no `kue-performance.md` edit).

## Completed Slice: B2.3 + B2.4 — structN consumer arms + the single meet merge (2026-06-19)

Commits `b3881c6` (consumers + meet merge + `mkStruct` move) and `eff5627` (eval/force/module
consumer arms). Both byte-identical (`structN` still UNPRODUCED).

### Design-ordering correction (consume-before-produce)

The plan's listed B2.2→B2.3→B2.4 order is UNSAFE: producing `structN` before consumers handle
it makes catch-all arms + the `meetCore` `.bottom` dead-arm mishandle live `structN` → fixture
drift. Re-sequenced to **consume-before-produce** — land the match sites (B2.3) and the single
meet arm (B2.4) FIRST, with `structN` unproduced so every arm is dead and byte-identity is
trivial; production (B2.2) flips last.

### What landed

- **`mkStruct`/`dedupPatterns`/`coherentTail` moved `Lattice` → `Value`.** B2.1 put `mkStruct`
  in `Lattice`, but `Parse`/`Normalize`/`Resolve` import only `Kue.Value` and need to construct
  `structN` at B2.2 — they can't reach a Lattice def. The defs have no Lattice dependency (B2.1
  made field ordering the caller's job), so they belong with the type. Layering-correct.
- **Consumer `.structN` arms** at every struct-family match site (full list in `plan.md` B2.3).
  Each reproduces EXACTLY the legacy form it maps from. Notable:
  - `classifyDefinedness`: split `structN _ _ _ [] ⇒ .defined` (struct/structTail) vs
    `structN _ _ _ (_::_) ⇒ .incomplete` (the old pattern forms).
  - `Normalize.normalizeDefinitionValueWithFuel` (highest-risk): `defOpenViaTail` returned
    VERBATIM (the legacy `structTail` had no arm → unchanged, the `...` keeps a def OPEN);
    no-pattern struct-equiv CLOSES (`→ .defClosed`); pattern-equiv keeps openness.
  - `evaluatedStructOperand?`: `defOpenViaTail ⇒ false` (matching `structTail`'s `false`),
    else `openness.isOpen`.
  - Plain-struct-only sites (`conjStructOperand?`, `openStructValue`, `closeEmbeddedOver`,
    `meetEmbeddingsWithFuel`, the package-binding lookups, the `embeddedList` inner matches,
    `formatTopLevel`): matched the plain-struct-equivalent `.structN _ _ none []` so the
    post-flip plain struct still hits the right path; tail/pattern forms fall through (legacy
    bottomed / passed through).
- **`mergeStructN` (the single meet arm).** ONE `.structN, .structN` arm in `meetWithFuel`
  delegates to `mergeStructN`, reproducing all 12 legacy arms by dispatching on tail/pattern
  shape. Preserves each arm's field-merge ORDER — including `struct × structTail` merging
  `rf ++ lf` REVERSED (the legacy arm passed the tail-side as the merge-left) and pattern-side
  always merge-left — and the exact `applyTailToExtrasWith`-on-both-sides + closedness marking.
  Emits `structN` via `mkStruct`. The legacy-missing `structPattern/structPatterns × structTail`
  (and any tail+pattern mix) stays `.bottom` — preserved for B2.5 to flip. `.structN × listLike`
  embedding arms added (plain-struct-equiv only; tail/pattern → meetCore → bottom, as legacy).
- **`applyEvaluatedStructN`** + the `structN` eval arm + `evalStructRefsM` structN arm: re-emit
  an evaluated normalized struct, routing patterns through `meet` exactly as the legacy
  `applyEvaluatedStructPattern(s)` did.

### Blocker (B2.2 production flip)

The production flip is written + semantically validated (every `testdata/cue` fixture, incl.
`struct_embedding_*` and all `modules/*`, produces correct output via direct `kue` runs — after
adding `structN` arms to `Module`'s `module.cue` field-extractors). It CANNOT land green: the
flip changes the internal `Value` representation, and ~17 test files / ~940 sites pin the OLD
representation (`== .struct […] true`) — `lake build` and `check-fixtures.sh` (which builds
`Kue.Tests.FixturePorts`) both fail. B2.2 is therefore inseparable from the test-representation
migration; the next slice combines B2.2 + CP3 (ctor delete + `structN→struct` rename) + the
test migration. The rename changes `Value.struct`'s arity (2→4), making the migration
compile-error-driven (safe, not silent) but large; `ManifestValue.struct` (different type, same
spelling) forbids a blind sed-rename. See `plan.md` B2.2 for the revised sequencing.

### Verify

`lake build` green (no warnings); `scripts/check-fixtures.sh` → `fixture pairs ok` (ZERO
byte-drift). No shell changed. Perf unchanged (no producer on any hot path).

---

## Completed Slice: B2.2/CP3-pre — test-only pre-migration to structN

Commits `b79af85`..`8923b51` on `main` (2026-06-19). The SAFE half of the B2.2/CP3
megaslice: migrate the CONSTRUCTED-INPUT test literals to `Value.structN` while production
still emits the old `.struct` (no producer flip, no ctor delete, no rename). This turns
~360 inspection-only consumer-arm sites into TEST-GATED ones before the risky flip, and
exercises `mergeStructN` / `closeValue` / `formatValue` / `manifest` / `subsumes` on the
`structN` representation for the first time.

### What landed

- **`Order.subsumes` merged structN arm (must-fix item 1).** The eight legacy struct-family
  subsumption arms (`struct`/`structTail`/`structPattern`/`structPatterns` crosses) replaced
  by one `.structN, .structN` arm delegating to a new `structNSubsumesWithFuel`. It dispatches
  on the EXPECTED side's tail/pattern shape, then the ACTUAL side's, reproducing every legacy
  arm EXACTLY: plain×plain → `structSubsumes` (openness via `StructOpenness.isOpen`); tail vs
  plain|tail → `structTailSubsumes`; patterns vs plain → `structPatternsSubsumes`; patterns vs
  patterns → `structPatternsSubsumes && patternsSubsume && (eo || !ao)`; every other cross-shape
  → `false`. `subsumes` has NO production caller (only tests use it — grep-confirmed), so the
  structN-only arm changes no production behavior.
- **Constructed-input test migration.** OrderTests (58 subsumes inputs), StructTests (all
  meet/format inputs and value-compared `rfl` expecteds — the first real exercise of the
  `mergeStructN` meet path; nested struct field-values migrated recursively), FixturePorts
  (90 ctors across the 43 producer-free ports — pure `meet`/`closeValue`/`formatField`/
  `formatManifestFieldResult` inputs, string-compared and representation-invariant), and
  ManifestTests/YamlTests/ListTests/BuiltinTests (83 inputs). The `ManifestValue.struct`
  collision (1-arg, no openness bool, different type) is guarded: only `Value.struct` (carries
  an openness bool) migrates; `ManifestValue.struct` heads left untouched.
- **Dedicated `mergeStructN` pins (must-fix item 2)**, now that the arms are test-live:
  `struct×structTail`/`structTail×struct` field-order reversal (tail-side fields first,
  `[c,b,a]`), `structTail×structTail` `applyTailToExtrasWith`-on-both-sides, arm-7 pattern
  dedup (`{[=~"a"]:int} & {[=~"a"]:int}` → ONE pattern, oracle-checked vs cue v0.16.1 which
  collapses to `{}`) plus a distinct-pattern concat pin, and the still-`.bottom` cross-combos
  (pattern×tail, both orders, single + multi-pattern) pinned AS `.bottom` for NOW — correct
  per this slice (no legacy arm); B2.5's bottom→unify flip will diff against them.

### Validation

NO migrated test went red ⟹ the structN meet / subsumes / close / format / manifest consumer
arms are byte-identical to the legacy forms on every reachable case (this was the de-risking
the slice existed to obtain). Produced-output sites (~95 `== .struct` LHS-of-resolver/eval in
ClosureTests/EvalTests/ResolveTests/FixtureTests/Normalize/TwoPass/Presence/Bound, plus the
85 FixturePorts producer ports / 147 ctors) correctly LEFT for the CP3-flip — production still
emits old `.struct`, so a structN expected there would mismatch. Must-fix item 3
(`applyEvaluatedStructN` end-to-end pin) is flip-only.

### Verify

`lake build` green (no warnings) and `scripts/check-fixtures.sh` → `fixture pairs ok` (ZERO
byte-drift) at EVERY commit (testdata untouched; the migrated inputs render identical strings).
No shell changed.

## Completed Slice: B2.2/CP3-flip — production flip + ctor delete + rename

The irreversible landing of the family-1 struct collapse, done in an isolated worktree
(`worktree-agent-a73190051b5458ad4`, commits `ee7dfe5`..`3f5bbbe`) because the codebase is RED
mid-flip and only green at the end. After this, the four legacy struct ctors are gone — one
`Value.struct fields openness tail patterns` remains (plus `structComp`, separate = B2b).

### Steps

1. **Producers → `mkStruct`.** Every construction site that built an old struct ctor now builds
   the normalized form via `mkStruct`, mapping the parser's `open_`/`hasTail` onto
   `StructOpenness`: a no-`...` struct ⇒ `.regularOpen`, an explicit `...` ⇒ `.defOpenViaTail
   (some tail)`. Sites: `Parse.parsedFieldsBaseValue`/`parsedFieldsValue` (the headline parser
   producer), `Runtime.mergeSourceValues` empty default, `Module.bindImports`, and all `Eval`
   re-emit points — comprehension result, `dynamicField`, `evalConjStandard`, the `.structComp`
   eval-arm host meet, and `forceClosureWithConjunct`'s use-operand fold. `applyEvaluatedStructN`
   (dead since B2.1) is now the live evaluated-struct re-emit, including its pattern arm.
2. **Delete 4 ctors + dead arms.** Removed `struct`/`structTail`/`structPattern`/`structPatterns`
   from `Value`. The vanishing 2-arg `Value.struct` turned every stale site into a compile error
   (the collision guard: `ManifestValue.struct` is a different 1-arg type, never errored). Fixed
   per-error, module by module — Lattice's 12-arm meet matrix + the 5 legacy merge helpers
   (`patternStructValue`, `mergeStruct{Tail,Pattern,Patterns}With*`) collapsed to the single
   `mergeStructN` arm; every other module's legacy match arms (already shadowed by a live structN
   arm during CP3-pre) deleted.
3. **Rename `Value.structN → Value.struct`** (arity 2→4) by word-boundary token replace of
   `structN` — collision-free since `ManifestValue.struct` is already `.struct` (not `.structN`)
   and the helper names contain capital-`StructN` (`mergeStructN`, `applyEvaluatedStructN`,
   `structNSubsumes`, `structNTailCoherent`), which the `\bstructN\b` match skips.
4. **Migrate produced-output tests.** The ~95 `== .struct`/`.structTail`/`.structPattern(s)`
   produced-output literals CP3-pre left (production then emitted old `.struct`) + the ~85
   FixturePorts producer ports + nested literals across ClosureTests/EvalTests/FixtureTests/
   ResolveTests/NormalizeTests/TwoPassTests/PresenceTests/BoundTests/EvalPerfTests/ModuleTests
   rewritten to the 4-arg `.struct fields openness tail patterns` (mapping: `true`→`.regularOpen`,
   `false`→`.defClosed`, `tail`→`.defOpenViaTail (some t)`, `[pattern]`→`[(lp,c)]`). Done with a
   balanced-bracket parser (only old forms rewritten; already-4-arg `.struct` and `ManifestValue`
   sites untouched).
5. **Pin `applyEvaluatedStructN` pattern path (must-fix item 3).** Two end-to-end EvalTests pins
   exercising an evaluated pattern-struct, oracle-checked vs cue v0.16.1: a field matching
   `[=~"x"]` is constrained (`string & "hi" = "hi"`; `int & "str"` bottoms it), a non-matching
   field is left untouched.

### Divergence (this slice's authorized improvement)

`mkStruct`/`dedupPatterns` deduplicates repeated equal `[pattern]: constraint` pairs. The legacy
`structPatterns` accumulated them per meet (no dedup), so the four TwoPassTests embed-narrowing
pins asserted `[string]: string` repeated 3×. cue v0.16.1 collapses to ONE — oracle-confirmed —
so the expected strings were corrected to the deduped (cue-matching) form, NOT smuggled back to
the buggy legacy output. A second, surface-only divergence (cue elides residual `[pattern]: c`
from `eval` output; Kue shows it — values + concrete export identical) is recorded in
`cue-divergences.md`.

### Verify

`lake build` green (no warnings/`sorry`), `scripts/check-fixtures.sh` → `fixture pairs ok` with
ZERO byte-drift on all testdata `.expected` (the representation changed; the observable values
did not — the whole correctness argument), shellcheck clean.

## Completed Slice: B2.5 — pattern×tail cross-combination fix (bottom → unify) (2026-06-19)

The payoff of the B2 family-1 collapse: the cross-combinations the collapse deliberately
preserved as `.bottom` (a pattern-bearing struct meeting a tail-bearing struct, either order)
now UNIFY, matching cue v0.16.1. The legacy five-constructor type could not co-represent a tail
AND patterns, so `structPattern×structTail` had no meet arm and fell to `.bottom`; the unified
`Value.struct (fields, openness, tail, patterns)` carries both axes, so the merge composes them.
This is the only behavioral (non-byte-identical) slice of B2 — a surgical correctness win.

### The `mergeStructN` change (`Lattice.lean`)

Replaced the residual `| _, _, _, _ => .bottom` catch-all with a general composition arm. It is
reached only when at least one side carries a tail AND the case wasn't a pure-tail arm (arms 2-4)
— i.e. the tail×pattern cross-combos and any tail+patterns mix. Composition:
- **base = the tail-bearing side's fields** (its fields come first, matching cue's output order;
  when both carry a tail the left is base, as in the tail×tail arm). `mergeStructFieldsWith base other`.
- **tail**: meet both if both `some` (`meet .top .top` for two bare `...`), else propagate the one
  present; bottom if the tail-meet bottoms. Each present tail is applied to the OTHER side's extras
  via `applyTailToExtrasWith` (declaredFields = that tail-side's own fields), exactly as the
  tail×tail arm.
- **patterns**: `leftPatterns ++ rightPatterns`, applied to the merged fields via
  `applyPatternsToFieldsWith` (each pattern constrains only its matching fields, incl. tail-admitted
  extras). Both axes RETAINED in the result.
- result: `mkStruct withPatterns .defOpenViaTail (some tail) allPatterns` — open via tail, patterns
  kept so future extras stay constrained.

No existing arm (1-7) touched. The trailing `mergedTail = none` branch is defensively `.bottom`
(unreachable: the arm is only entered with ≥1 tail).

### Tests

- **Flipped 4 LatticeTests pins** (`mergeStructN_*_is_bottom_for_now` → `*_unifies`): single +
  multi-pattern, both orders. cue-correct unified value: `{[=~"a"]: int} & {a: 1, ...}` →
  `.struct [a:1] .defOpenViaTail (some .top) [(=~"a", int)]` (cue v0.16.1 → `{a: 1}` open).
- **2 new edge pins**: pattern VIOLATION bottoms the matched FIELD only (`{[=~"a"]: int} &
  {a: "x", ...}` → `a: _|_`, struct survives — cue errors on field `a` only); compositional
  re-meet of an already-unified (tail+patterns) value with a tail-struct (`({[=~"a"]: int} &
  {a: 5, ...}) & {b: 9, ...}` → `{a: 5, b: 9}` open — exercises the both-tails `meet .top .top`
  path + patterns-retained-across-remeet).
- **2 new end-to-end fixtures** (`testdata/cue/definitions/{pattern_tail,multi_pattern_tail}_unify`
  + FixturePorts entries): `{[string]: int} & {a: 5, ...}` and a two-pattern variant. Concrete
  `kue export` byte-identical to `cue export` for both.
- Updated the LatticeTests module header (the "B2-TARGET known-incomplete" section → "B2.5 FIXED").

### Verify

`lake build` green (96 jobs, no warnings/`sorry`), `scripts/check-fixtures.sh` → `fixture pairs ok`.
The ONLY fixture drift is the two NEW pairs — every existing `.expected` unchanged, confirming no
existing fixture relied on the buggy `.bottom`. shellcheck clean. Oracle-checked every flipped/new
pin and both fixtures against cue v0.16.1 (concrete exports identical; the internal-format residual
`[pattern]`/`...` display is the pre-existing eval-output divergence already in cue-divergences.md).

---

## Completed Slice: B6 — def-body closedness through a regular field (gaps 1+2; partial)

Commits `3b2beb6` (design-spike), `7da65d8` (implementation). One of the two B6 sub-gaps
landed sound; the other (a separate mechanism) was deferred per correctness-over-performance.

### Behavior added

A closed `#Def` nested under a REGULAR field now reaches the use-site meet still closed, so an
undeclared field is rejected — matching cue v0.16.1 (`a: {#Inner: {x:int}}; a.#Inner & {x:1,
extra:2}` → `out.extra: field not allowed`). The eager nested-selector form (`x.#Inner & {extra}`)
is fixed by the SAME change. An OPEN nested def (`#Inner: {x:int, ...}`) still admits the extra (no
over-close).

### Mechanism

`normalizeDefinitions` (the top-value SPINE walker) runs at eval. Its field handler
`normalizeFieldWithFuel` routed ONLY `isDefinition` fields into the closing normalizer and returned
every other field UNCHANGED — so a `#Inner` under a regular field `a` was never visited and reached
the meet as `.regularOpen`, where `applyStructClosedness` (Lattice) found `leftOpen=true` and marked
nothing. The eager selector `selectEvaluatedField` returns `Field.value` verbatim, so gap 2 was
downstream of gap 1, not a distinct defect.

Fix (one edit, `Normalize.lean`): in `normalizeFieldWithFuel`, a non-hidden/non-let
regular/optional/required field now recurses its value through the SPINE walker
(`normalizeDefinitionsWithFuel`), which preserves the host struct's own openness (an instantiated
regular struct stays open — cue keeps `(#D & {}).r` open) while closing any nested `#Def` reached
inside it. HIDDEN fields are left untouched so import-package bindings (`Module.lean`) stay cue-lazy
— recursing them would re-close unreferenced nested defs and re-bottom cert-manager/argocd (the A2
trap). This decouples B6 from A2-followup.

### Deferred sub-gap (filed, NOT forced)

Selecting a nested REGULAR-field struct through a NON-instantiated def literal (`#D.l[0] & {b}`,
`#D.r & {b}`) — cue closes those on the direct def-path but RE-OPENS them on any
instantiation/binding (oracle-confirmed: `#D.r & {a:1,b:2}` rejects `b`; both `(#D & {}).r` and
`(y: #D).r` admit `b`). Enforcing it requires the closing-vs-instantiation distinction in
`mergeStructN`'s closedness composition (the meet must re-open nested regular structs on `&`), which
is larger than one slice and risks over-close. Left for a dedicated design-slice (see plan B6).

### Tests

- 2 fixtures: `testdata/cue/definitions/nested_def_under_regular_field` (closed → `extra: _|_`),
  `…/nested_def_open_under_regular_field` (open via `...` → admits `extra`); both with FixturePorts.
- 3 `native_decide` pins (EvalTests): closed-def-under-regular rejects extra, eager-selector form
  rejects extra, open form admits.

### Verify

`lake build` green (96 jobs), `scripts/check-fixtures.sh` → `fixture pairs ok` (only the 2 new pairs
as drift; def_open_tail_addfield over-close sentinel + all import/def-meet module fixtures
byte-identical), pins oracle-checked vs cue v0.16.1.

## Completed Slice: B2b — structComp two-bool → StructOpenness (2026-06-19)

Collapsed the LAST `(open_, hasTail)` two-bool in `Value` — the pre-eval `structComp`'s — into a
single `StructOpenness`, completing the B2 struct-family unification. `structComp` stays a DISTINCT
pre-eval ctor (NOT folded into the meet-bearing `struct`; the audit's option (a)): it never reaches
meet — the eager eval arm expands it into the unified `struct` first — so adding a `comprehensions`
field to `struct` (option (b)) would re-introduce a `comprehensions=[]`-on-evaluated-struct nonsense
state and destroy the pre-eval/evaluated boundary. `structComp` carries NO tail VALUE, so its
`defOpenViaTail` means "open via a bare `...`, no stored tail" — coherent, no `tail` field to relate.

### Steps

1. **Arity 4→3 + the one semantic site.** `Value.structComp (fields) (comprehensions) (open_ : Bool)
   (hasTail : Bool)` → `(fields) (comprehensions) (openness : StructOpenness)`. The arity change
   turned every site into a compile error, fixed in dependency order (Value → Lattice → Normalize →
   Resolve → Format → Manifest → Eval → Parse). The ONE semantic site:
   `normalizeDefinitionValueWithFuel`'s `open_ := hasTail` (close a def body unless `...`) became
   the total `StructOpenness.closeDefBody` (`regularOpen ↦ defClosed`, `defOpenViaTail` fixed,
   `defClosed ↦ defClosed`). Parse maps `hasTail` → `if hasTail then .defOpenViaTail else
   .regularOpen` (`open_` was always `true` at parse, now implied — both parse states are open). The
   two eval consumers (eager arm `Eval.lean:2129`, force arm `:2483`) pass `openness.isOpen` where
   they passed `open_`/`defOpen` to `closeEmbeddedOver` (kept its `Bool` param — shared with
   non-structComp logic, minimal-touch). All match arms that `_`-ignored both bools collapsed to one.
2. **Migrate test literals.** 62 `structComp` two-bool literals across 7 test files (FixturePorts 28,
   ClosureTests 12, EvalTests 9, ResolveTests 4, TwoPassTests 4, EvalPerfTests 3, PresenceTests 2)
   rewritten `true false → .regularOpen`, `false false → .defClosed`, `true true → .defOpenViaTail`.
   Compiler-driven (arity change errors every stale literal). A balanced anchor on `.structComp`
   guarded against the same-shape `.field (hidden definition)` two-bool collision (10 `.field` pairs
   in Struct/ParseTests left untouched). Added `closeDefBody` (3 arms) + a `normalizeDefinitionValue`
   end-to-end pin to `LatticeTests` — the one semantic site pinned at the type level.

### Verify

`lake build` green (96 jobs incl. all `native_decide` tests), `scripts/check-fixtures.sh` →
`fixture pairs ok` ZERO byte-drift on all existing fixtures (byte-identical by construction — the
reachable two-bool states map 1:1 onto the three `StructOpenness` states), `shellcheck` clean. Pure
representation change, no eval-path change → perf unchanged (no `kue-performance.md` edit; cert-
manager/`packs.#Argo` covered by the zero-drift fixture suite). ALL `open_`/`hasTail` two-bools now
gone from the codebase (residual `open_` identifiers are `isOpen : Bool` locals in
`Order`/`Lattice`/`Eval`, unrelated to the struct two-bool). B2 (entire struct-family unification:
5 original ctors → 1 unified `struct` + 1 pre-eval `structComp`, both on `StructOpenness`) COMPLETE.

---

## Completed Slice: B6-A2 (let-binding closedness) + B6-T1 (closedness regression pins)

Commits: `27ddb96` (B6-A2), `aef25ac` (B6-T1). Two-part correctness + test-strength slice that
also de-risks A2-followup (B6-A2's edit is that slice's `let` arm).

### B6-A2 — close a nested `#Def` under a `let`-bound field

The B6 spine recursion in `normalizeFieldWithFuel` (`Normalize.lean`) skipped BOTH hidden AND
`let`-bound field values to protect import bindings (the A2 trap). `let` over-skipped: `letBinding`
is its OWN `FieldClass` kind, distinct from the `hidden` fields `Module.bindImports` uses for
package bindings, so a `let`-bound value can safely recurse the spine walker and close its nested
`#Def`s. Fix: dropped `|| Field.fieldClass field == .letBinding` from the skip guard so `let` joins
the regular/optional/required arm (`normalizeDefinitionsWithFuel`); the `isHidden` skip (the
import-binding guard — A2-followup's concern) stays.

- Oracle cue v0.16.1: `let x = {#I: {y: int}}; out: x.#I & {extra}` → `out.extra: field not
  allowed` (closed def). Kue admitted `extra` before, now bottoms it.
- No over-close (oracle-confirmed + pinned): an open def (`...`) under a `let` admits `extra`, and a
  plain/regular struct under a `let` admits `extra` — both stay open, cue-exact.
- This is the `let` arm of A2-followup's future 4-way `FieldClass` split
  (importBinding/hidden/let/regular); A2-followup folds it in with no rework.

Pins: 2 parse-driven fixtures (`let_nested_def_closes`, `let_nested_def_open`) + 3 `native_decide`
EvalTests (closes, open-admits, plain-stays-open).

### B6-T1 — pin the closedness regression class

B6 closedness is the most regression-prone class (prior changes bottomed
`#ListenerSet`/cert-manager). Pinned the shapes the Phase-A 8-probe over-close hunt exercised, each
oracle-checked vs cue v0.16.1, as both a `.cue`/`.expected` fixture (+ FixturePorts entry,
parse-driven) and a `native_decide` EvalTests pin:

1. depth-2 nesting `a.b.#Inner & {extra}` CLOSES (`extra: _|_`).
2. plain (non-def) struct under a regular field stays OPEN (admits `extra`).
3. open `#Def` via `...` under a regular field admits `extra` (already pinned by the existing
   `nested_def_open_under_regular_field` fixture).
4. def-meet `#D & {c}` rejects the unallowed field (`c: _|_`); a comprehension-bearing AND an
   embedding-bearing regular field each admit their legit siblings.
5. instantiated def field `(#D & {}).r & {extra}` re-opens / ADMITS — matching cue on the
   INSTANTIATION path. This pins CURRENT behavior at the boundary of the deferred sub-gap.

Deliberately NOT pinned: the DIRECT def-path `#D.r & {extra}` (cue rejects, Kue wrongly admits) —
the documented deferred open gap. No known-wrong behavior is pinned as correct.

### Verify

`lake build` green (96 jobs, incl. all new `native_decide`), `scripts/check-fixtures.sh` →
`fixture pairs ok` with ZERO byte-drift on all existing fixtures (cert-manager/argocd import-binding
sentinels + `def_open_tail_addfield` byte-identical — the B6-A2 fix only drifts the new Part-2
fixtures), `shellcheck` clean (no script changed). No `kue-performance.md` edit (no eval-cost
change — Normalize already walked regular-field spines; `let` just joins that existing arm). No
CUE divergence (both gaps are Kue-wrong, not cue-buggy).

## Completed Slice: A2-followup — `FieldClass.importBinding` marker (2026-06-19)

Commits: `78ec47a` (marker), `7a54ad6` (consumer splits + fixtures), commit 3 (negative sentinel +
docs). One structural-correctness slice that fixes A2-followup (deep reached-hidden bottom) AND
B6-A1 (in-file hidden nested-def closes), and eliminates the `FieldClass.hidden` conflation between
import-bound packages and real in-file hidden fields.

### The conflation

`Module.bindImports` bound a whole imported package as a `FieldClass.hidden` field — structurally
identical to a real in-file `_x` parsed at `Parse.lean`. Two consumer sites had to treat the two
KINDS oppositely (an UNREFERENCED import's interior conflict stays cue-lazy; a REACHED in-file
hidden field's bottom/closedness is enforced), but the type gave them no way to tell apart. Both
sites were forced to under-approximate: Normalize skipped ALL hidden fields (B6-A1 escape), Manifest
used a shallow `isBottom` only (A2 deep-bottom miss).

### The marker (option a — a new `FieldClass` constructor)

Added `| importBinding` as a peer of `letBinding` — NOT a fourth `.field` bool (would widen the
product to nonsense + force ~25 match sites to carry a positional bool), NOT a `Value` wrapper
(would add an arm at every meet/manifest/eval site). Folded TOTALLY into the 4 helpers
(`isDefinition=false`, `isHidden=true`, `optionality=.regular`, `ignoresClosedness=true`,
`producesOutput=false`) + the compiler-surfaced match sites in `Lattice.mergeFieldClass`
(merges only with itself, like `letBinding`) and `Format` (omitted from output, like `letBinding`).
So an `importBinding` reads IDENTICALLY to `.hidden` at every consumer — behaviorally inert except
at the two sites that branch on import-vs-in-file. Produced at the ONE site `Module.bindImports`;
the in-file hidden producer (`Parse.lean`) stays `.hidden`. (Commit 1 was byte-identical: zero
fixture drift, the marker inert until the consumer splits land.)

### The two consumer splits

- **Normalize.normalizeFieldWithFuel** — replaced the 3-way if-chain with a 4-way `FieldClass`
  match: definition → close; `importBinding` → skip (import-laziness guard, now PRECISELY scoped to
  bound packages); in-file hidden (`_x`) / `let` / regular → recurse the spine walker. Fixes B6-A1
  (in-file hidden nested-def now closes) and subsumes B6-A2 (the `let` arm).
- **Manifest.manifestFieldsWithFuel** — the real in-file hidden/def `.field _ _ .regular` arm now
  recurses the SELECTED value's manifest output spine and lifts a DEEP `.error .contradiction`
  (`{#u: {x: _|_}}` surfaces); a non-contradiction error (incomplete) stays skipped (hidden/def
  fields are non-output). The `.importBinding` arm keeps the shallow `isBottom` — the deep recurse
  NEVER runs on a bound package, so the cert-manager trap cannot recur.

### Why sound (the trap)

The reverted A2 attempt did a blanket deep-recurse and re-bottomed cert-manager's unreferenced
import bindings. The marker makes output-reachability laziness LOCAL: an `importBinding` field IS
the unreferenced-import case by construction. Pinned by the `unreferenced_import_conflict` negative
module sentinel (a `dep` package with `#Probe: {cmd:string}&{cmd:int}`, unreferenced by `main`;
`main` exports clean — oracle-confirmed cue v0.16.1, Kue matches).

### Tests

New oracle-checked fixtures (vs cue v0.16.1): `b6a1_infile_hidden_def_closes` (reject extra),
`b6a1_infile_hidden_def_open` (open via `...` admits extra — no over-close), the
`unreferenced_import_conflict` module sentinel, and 4 `FixtureTests` manifest theorems
(deep-def-bottom, deep-in-file-`_x`-bottom, deep-incomplete-tolerated, in-file-nested-conflict).
Inverted the obsolete `link5_..._does_not_overfire` pin → `infile_hidden_nested_conflict_surfaces`:
it asserted clean export for an IN-FILE literal deep conflict, but cue ERRORS there — the test
conflated an in-file literal with an import binding (exactly the conflation the marker fixes); the
genuine lazy-import guard is now the `dup_import_binding` + `unreferenced_import_conflict` module
fixtures.

### Verify

`lake build` green (96 jobs), `scripts/check-fixtures.sh` → `fixture pairs ok` with ZERO byte-drift
on existing fixtures (only NEW fixtures appear; cert-manager/argocd import-binding sentinels +
`dup_import_binding` + `def_open_tail_addfield` + B6-T1 pins byte-identical), `shellcheck` clean (no
script changed). No `kue-performance.md` edit (no eval-cost change — the Manifest deep-recurse runs
only on reached in-file hidden/def fields, which are rare and shallow in practice; import bindings
keep the shallow check). No CUE divergence (both gaps are Kue-wrong, not cue-buggy).

---

## Completed Slice: Cache-Key Hash Digest (item 7 — the O(N²) memo-lookup wall)

**Intended behavior:** kill the O(N²) memo-lookup cost on deep real apps without changing any
value. The `EvalKey`/`SatKey` `Hashable` instances hashed on `valueTag` (the top constructor tag,
0–31, no subtree traversal) + `envIds.LENGTH`. At a deep app's steady state the cache population is
overwhelmingly `.struct`/`.selector` at the same ceiling fuel and the same env depth → every
distinct value collided into ONE hash bucket → each `cache.get?` ran derived structural `BEq` over
the full value tree against every colliding entry → O(N) per lookup, O(N²) total (cert-manager
exported correctly but in ~119s vs `cue` 0.03s).

### The fix (`Eval.lean`)

- **`valueDigest : Nat → Value → UInt64`** — a TOTAL, fuel-free, BOUNDED-DEPTH structural digest.
  Structural recursion on `depth` (the measure strictly decreases; no `partial`, no fuel): at
  `depth = 0` it returns `valueTag` alone; at `depth+1` it mixes the constructor tag with each
  child's digest at `depth` and the constructor's scalar payload (field labels, `prim` value,
  `refId` depth/index, selector label, struct field count, etc.). `DIGEST_DEPTH = 3` — deep enough
  to separate the field-name + nested-value shape of k8s resources (a struct of a few fields whose
  values are themselves shallow structs/scalars), shallow enough that per-key cost stays O(1).
- Swapped `valueDigest DIGEST_DEPTH key.value` for `valueTag key.value` in BOTH the `Hashable
  EvalKey` and `Hashable SatKey` instances, and widened `envIds.length` → `hash envIds` (matching
  the existing `ForceKey` hash).
- **`BEq` UNCHANGED** for all keys; `valueTag` semantics, fuel, and all eval logic untouched.
- **`FrameKey` left shallow (profiled).** Deepening its hash to the same `valueDigest` showed ZERO
  cert-manager wall-clock change (canonical frame sharing + `parentIds` already discriminate the
  frame table), so it was reverted with a note — no unjustified `valueDigest` on the hot
  `pushFrame` path. If a future workload makes the frame table the wall, the same sound swap applies.

### Why sound (unconditional)

The change is hash-only. In `Std.HashMap` the hash only selects a bucket; `BEq` (derived-structural,
UNCHANGED) is the SOLE arbiter of whether `get?` returns an entry. A lossy/colliding digest can
therefore only cause a recompute-miss (a hit was possible but the keys hashed apart — slower) or a
collide-scan (more keys share a bucket — slower), never a value computed for a different key. The
two same-key-different-value hazards that DO threaten Kue (fuel-truncation across levels;
closed-vs-open) live entirely in `BEq` field membership and are untouched. The correctness witness
is the byte-identical fixture gate (zero drift).

### Tests (`EvalPerfTests.lean`)

Bucket-distribution `native_decide` pins (the right witness — eval COUNT is unchanged, the win is
per-lookup time): `digest_separates_k8s_population` (1000 distinct k8s-shaped structs → 1000 distinct
buckets at depth 3), `valueTag_collapses_k8s_population` (the old hash → 1 bucket, pinning the
contrast), `digest_depth0_collapses_like_tag` (depth 0 degenerates to `valueTag` — pins depth is
load-bearing), `digest_total_on_deep_value` (totality/determinism on a deeply-nested value).

### Verify + measure

`lake build` green (96 jobs), `scripts/check-fixtures.sh` → `fixture pairs ok` with ZERO byte-drift,
`shellcheck` clean (no script changed). **Measured (READ-ONLY oracle: `/Users/chakrit/Documents/
prod9/infra`):** cert-manager `kue export apps/cert-manager.cue --out yaml` **119s → ~30.6s (~3.9×)**,
content-identical to `cue export` (only field order differs — known #3). Full `apps/argocd.cue` is
much faster (>7.5min/killed → ~88s) but STILL bottoms (`conflicting values (bottom)`) on the fuel
ceiling — the separate fuel-exhaustion-at-scale limit, not a hash problem. No CUE divergence.

---

## Spike (no code landed): argocd bottom RE-DIAGNOSED — real conflict, not fuel

**Intended outcome:** confirm whether full `apps/argocd.cue`'s `conflicting values (bottom)` is a
spurious fuel-truncation bottom (→ a perf wall, fixable by reducing eval cost) or a real value
conflict (→ a correctness bug). **Finding: real conflict.** No production code changed — this is a
diagnostic spike whose output is the durable finding in `plan.md` ("Perf-spike → CORRECTNESS
finding") and `kue-performance.md`. A debug-only env-gated value dump was added to `Main`/`Runtime`
to read bottom reasons, then REVERTED; the working tree is back to baseline.

**Evidence (against READ-ONLY prod9 `/Users/chakrit/Documents/prod9/infra`, oracle `cue` 0.16.1):**
- `evalFuel` swept 100→200→600: app bottoms at every level (wall 88s→131s→301s, scales ~linearly,
  bottom never clears). `resolveFuel`/`remapFuel`→100000 on a fast repro: still bottoms. NOT
  truncation at any ceiling.
- Bisected to `defaults.#ListenerSet` / `defs.#TLSRoute`; each bottoms standalone on valid CUE
  `cue` exports. Resolved tree: `listener.yaml: [.bottom]` (bare) co-occurring with `fieldConflict
  #args/#from/#to` from UNREFERENCED `defs` workload siblings.
- A single-module vendor of the same `defs.#ListenerSet` (correctly referenced) evaluates CLEANLY →
  the bug is in the cross-MODULE loader path (consumer `prodigy9.co` → dep `prodigy9.co/defs`),
  hypothesis: an import-laziness gap letting an unreferenced conflicting dep sibling pollute the
  selected value. Follow-up slice (a CORRECTNESS slice, ahead of the perf items) detailed in
  `plan.md`. Build green (96 jobs) at baseline. No CUE divergence (the divergence is Kue-wrong).

---

## argocd bottom PINNED — comprehension-guard / embed-narrowing (Bug #1 fixed, Bug #2 open)

**Intended outcome:** pin and fix the `apps/argocd.cue` `conflicting values (bottom)`. The prior
spike's cross-module / import-laziness hypothesis is **DISPROVEN** — the bug reproduces SAME-MODULE
and the `#args/#from/#to` `fieldConflict` was a red herring. Minimizing `defaults.#ListenerSet`
(`defs.#ListenerSet & parts.#UseCertManager & {…}`) down to `parts.#Mixin` pinned the real shape: a
comprehension guard `for _, add in Self.#additions { if kind == add.#kind { add.#patch } }` that
reads the def's REGULAR sibling `kind`, narrowed at the use site. cue defers the comprehension until
`kind` is concrete and emits the matched patch; Kue forced the embedded def with only HIDDEN fields
spliced, so the guard fired against the un-narrowed `kind: string`, stayed incomplete, and the
guarded body dropped (the outer `meet` cannot re-fire a collapsed comprehension).

**Two bugs at different nesting depths:**

- **Bug #1 — single-embed comprehension-guard splice (FIXED).** `#Outer` embeds `#Inner` whose guard
  is a DIRECT top-level comprehension; the use site narrows the regular sibling. Added
  `defFrameRefIndices` (collects the def-frame slot indices a value reads, threading frame depth
  through every frame-pusher incl. a comprehension's `+1`-per-`for` clause chain) →
  `embedComprehensionReadLabels` (the labels a body's comprehensions read at the def frame) →
  `spliceOperandForEmbed` (the splice operand = `hiddenFieldsOnly` PLUS the host's REGULAR fields a
  comprehension reads). Wired into the two `forceClosureWithConjunct` splice sites
  (`evalEmbeddingFieldsWithFuel`, `meetEmbeddingsWithFuel`) replacing the bare `hiddenFieldsOnly`.
  The extra regulars merge BY LABEL into the embed's own declarations (the same `meet` the outer fold
  does, early enough for the guard) — no new label, no closedness change.

- **Bug #2 — let-buried multi-embed narrowing (OPEN, the actual argocd blocker).** In the real
  `parts.#Mixin` the comprehension is buried under `let _patch` → `let structShape` → embed, AND
  wrapped in `listShape | structShape | error(…)`. The use-site narrowing must propagate down several
  `let`/embed layers (and through the disjunction arm) to reach the guard; the single-level splice
  does not thread that far (with the disjunction → bottom; without → drops the patch). A
  narrowing-propagation architectural slice — diagnosed + repro'd, deferred per
  `correctness-over-performance`. Detailed in `plan.md` ("PINNED" section).

**Tests:** `crossmod_embed_guard` module fixture (oracle-checked: a cross-module dep `example.com/mix`
with the `#Inner`/`#Outer` embed-guard shape; Kue export == cue export). `native_decide` pins in
`TwoPassTests.lean`: `embed_comprehension_reads_guarded_regular_sibling` (the mechanism — `["Self",
"kind"]`), `embed_comprehension_guard_emits_matched_patch` (positive), `embed_comprehension_guard_
false_drops_body` (no over-fire), `embed_comprehension_guard_real_conflict_bottoms` (soundness — a
real conflict still bottoms).

**Verify + measure:** `lake build` green (96 jobs), `scripts/check-fixtures.sh` → `fixture pairs ok`
ZERO byte-drift (only the new fixture appears; cert-manager/argocd sentinels + A2-followup import
sentinels byte-identical), `shellcheck` clean (no script changed). Full `apps/argocd.cue` re-measured
**88.85s, STILL bottoms** (Bug #2 open). cert-manager unaffected. No CUE divergence (Bug #1 was
Kue-wrong, now fixed).

## Bug2-1 — let-buried comprehension read-label detection (Gap-1) + A-EN1 (for-source variant)

The LOW-RISK first half of the argocd Bug #2 fix. Bug #1 made the embed splice carry the regular
siblings a comprehension's guard reads, but `defFrameRefIndices`/`embedComprehensionReadLabels`
(`Eval.lean`) treated a `.refId` as a LEAF — they did not follow a `letBinding` ref into its bound
value. So when the comprehension is buried under a `let` (`let _patch = {… for … if kind == … }`),
the regular sibling `kind` it reads THROUGH the let was never detected → never spliced → the guard
saw the un-narrowed `kind: string` and the body dropped (shapeA/shapeB: wrong-output, dropping the
patch). The spike's `probe_hidden` proved the let-indirection itself does NOT block propagation (a
HIDDEN sibling, already spliced by `hiddenFieldsOnly`, works byte-exact) — so the gap is purely
DETECTION (finding the read label through the let), not re-expansion.

**The fix — follow `letBinding` refs transitively, cycle-bounded.** Added `closeDefFrameReadIndices`
(`Eval.lean`): given the def-frame `fields` and a frontier of detected def-frame slot indices, for
each frontier index naming a `let` slot it scans that let's bound value with `defFrameRefIndices …
0` (the let value is lexically a sibling, scanned at depth 0 like the top-level `cs`/fields — the
inner `.structComp`/comprehension wrappers thread `+1` so a ref to the def frame matches) for further
def-frame reads, then recurses on the newly-found lets. A `visited`-set follows each `let` slot AT
MOST ONCE → a self/mutually-referential `let` (`let a = a`, `let a = b; let b = a`) cannot loop
(TOTAL); a `fuel = fields.length` second bound keeps the recursion structurally total.
`embedComprehensionReadLabels` now seeds with `defFrameRefIndices` and closes via
`closeDefFrameReadIndices` before mapping index → label. This only WIDENS the spliced-label set —
soundness identical to Bug #1 (a real conflict still bottoms via merge-by-label; the over-splice
hunt cleared 13 probes). Covers BOTH the `if`-guard read (Gap-1) and the `for`-SOURCE read (A-EN1,
which rides along — same additive detection, no separate machinery).

**Tests (oracle-checked vs cue 0.16.1).** Module fixtures (auto-discovered `testdata/modules/*`):
`let_buried_guard_read` (shapeA, one let), `let_buried_two_lets` (shapeB, two nested lets),
`let_buried_for_source` (A-EN1, bare `for … in items` source through a let) — all now emit the
matched patch/expanded keys, matching cue (before the fix Kue dropped them). `native_decide` pins in
`TwoPassTests.lean`: `let_buried_guard_reads_regular_sibling` (one-let mechanism — detects `kind`
through `_patch`), `two_lets_buried_guard_reads_regular_sibling` (nested — `structShape → _patch →
kind`), `let_buried_for_source_expands` (A-EN1 end-to-end), `let_buried_guard_emits_matched_patch`
(positive) + `let_buried_guard_false_drops_body` (no over-fire) + `let_buried_guard_real_conflict_
bottoms` (SOUNDNESS — `exportJsonBottoms` positively witnesses the bottom), `let_buried_no_regular_
read_no_over_splice` (a let reading no regular sibling pulls no regular into the splice),
`let_self_ref_cycle_terminates` (totality — a `let a = a` returns a finite set).

**Verify + measure:** `lake build` green (96 jobs), `scripts/check-fixtures.sh` → `fixture pairs ok`
ZERO byte-drift (cert-manager content-identical ~30.5s, modulo field-order #3; all existing fixtures
incl. `crossmod_embed_guard` + the link-5/A5 pins unchanged), `shellcheck` clean. As EXPECTED for the
Gap-1-only half: `kue export apps/argocd.cue` STILL bottoms (~88s) — **Gap-2 (Bug2-2) remains the
argocd blocker** (the force-tier disjunction-arm narrowing, GATED next slice). Did NOT clear shapeD
(needs Gap-2). No CUE divergence (Bug2-1 was Kue-wrong, now fixed → not an entry).

## Bug2-2 — force-tier disjunction-arm narrowing (Gap-2): clears shapeD + the probes; argocd has a residual DIFFERENT conflict (Gap-2b)

Gap-2 of the argocd Bug #2 fix — the regression-prone disjunction-arm class. An embedded def `#M`
carrying a discriminated disjunction (`{shape:"struct",…} | {shape:"list",…} | error`) selects the
right arm when narrowed DIRECTLY (`#M & {shape:"struct"}`, the `meetEmbeddingsWithFuel`
`conjDisjArms?` distribution one tier up), but when `#M` is itself embedded one layer down
(`#U:{#M}`, then `#U & {shape:"struct"}`) it BOTTOMED. Root cause (pinned by instrumenting the
`.closure` force-splice in `meetEmbeddingsWithFuel`): when `#M`'s closure is force-spliced, the
splice operand was `hiddenFieldsOnly` + the regular siblings a comprehension READS
(`embedComprehensionReadLabels`). The disjunction's DISCRIMINATOR `shape` is a regular sibling the
arms MATCH (declare `shape:"struct"`/`"list"`), not one they READ — so it was dropped from the
splice. `#M` was then forced with `shape` un-narrowed, every arm survived (`nLive=2`), and the outer
meet conflicted → bottom. (Direct narrowing works because it never takes this embed-closure path —
the `.conj` fold distributes into arms one tier up.)

**The fix — `embedDisjArmDeclLabels` (`Eval.lean`), gated.** A new analysis returns the regular
labels an embed body's embedded disjunction's ARMS DECLARE that are ALSO top-level regular fields of
the body — the genuine discriminators the host narrows. It follows a `.refId ⟨0,i⟩` arm into the
body's own `let` slot at index `i` (the shapeD `structShape | listShape | error` form, where arms are
let-refs to `{shape:"struct",…}`/`{shape:"list",…}`). `spliceOperandForEmbed` now adds these labels
alongside the comprehension-read labels, so the host's narrowed discriminator reaches `#M` and its
force-time `conjDisjArms?` distribution prunes the dead arms exactly as a direct `#M & {narrow}` does
— the SAME `liveAlternatives` pruning, re-driven behind the force tier. **MANDATORY GATE (the
cert-manager byte-identity guard):** `embedDisjArmDeclLabels` returns `[]` unless the body's `cs`
holds a `.disj` embedding — no disjunction embedding → no extra splice → byte-identical. Verified by
construction: instrumenting the splice site, cert-manager fires the gate **0 times** (no embedded def
body in cert-manager has a disjunction embedding); shapeD fires it 6 times.

**Soundness.** The spliced value is the SAME use-site narrowing, merged BY LABEL — not a broadened
one; no arm over-narrows into surviving. A real conflict on the discriminator that kills ALL
structural arms still bottoms (the `error(…)` arm is itself a bottoming arm; if every structural arm
dies the disjunction is bottom, cue-exact) — pinned by `disj_embed_one_layer_real_conflict_bottoms`
(`shape:"other"` → no survivor → `exportJsonBottoms`). The direct-narrowing case is UNCHANGED
(`disj_direct_narrow_unchanged`). The other arm is not over-pruned (`disj_embed_one_layer_selects_
list_arm`).

**Tests (oracle-checked vs cue 0.16.1).** Module fixtures: `disj_embed_one_layer` (inline arms —
struct/list selection + the `outDirect` unchanged-direct case + `outBottom` real-conflict-falls-back,
byte-identical to cue) and `disj_embed_force_narrow` (the shapeD repro — disjunction + buried let +
comprehension, selects the struct arm AND emits the matched `#patch`, content-identical to cue modulo
field-order #3). `native_decide` pins in `TwoPassTests.lean`: `embed_disj_arm_decl_labels_inline`
(mechanism, inline arms → `["shape"]`), `embed_disj_arm_decl_labels_let_refs` (follows `.refId` arms
into let slots), `embed_disj_arm_decl_labels_no_disj_gate` (GATE — no `.disj` embedding → `[]`),
`disj_embed_one_layer_selects_struct_arm`/`_selects_list_arm` (both arms, no over-prune),
`disj_direct_narrow_unchanged` (the direct case stays put), `disj_embed_one_layer_real_conflict_
bottoms` (SOUNDNESS — all arms killed → bottom), `disj_embed_force_narrow_emits_patch` (shapeD
end-to-end).

**Verify + measure:** `lake build` green (96 jobs), `scripts/check-fixtures.sh` → `fixture pairs ok`
ZERO byte-drift on ALL fixtures (cert-manager content-identical at 30.52s = baseline — the GATE PASS;
the two new fixtures + `crossmod_embed_guard` + link-5/A5 pins green), `shellcheck` clean.

**argocd: NOT YET unblocked — a residual DIFFERENT conflict (Gap-2b).** `kue export apps/argocd.cue`
still bottoms (~88s, exit 1), but the cause is now a SEPARATE gap, not shapeD's. The spike's
shapeD/`probe_disj_inline` used a REGULAR discriminator field (`shape`), and Gap-2 clears that class.
The REAL `defs/parts.#Mixin` (cue cache `prodigy9.co/defs@v0.3.19/parts/mixin.cue`) discriminates
STRUCTURALLY, not by a regular field:
- `listShape = { #components: [string]: _patch; [...] }` — a LIST-shaped arm (the `[...]` list-embed)
  keyed on the HIDDEN `#components`.
- `structShape = { _patch; ... }` — a plain struct arm, declaring NO concrete discriminator.

There is no regular discriminator label for `embedDisjArmDeclLabels` to surface, so the gate doesn't
fire on it. Minimized repro (`/tmp/kprobe/struct_disc.cue`, oracle: cue selects `structShape`, emits
`meta:"yes"`): Kue bottoms. Instrumenting the `conjDisjArms?` distribution shows `nLive=2` — the
LIST-shaped `listShape` arm is NOT pruned against the STRUCT host (`{kind:"ListenerSet", …}`) when the
arm carries the spliced `_patch` comprehension, so a 2-arm `struct | list` disjunction survives and
bottoms downstream. (Without `_patch` the structural pruning works — `/tmp/kprobe/sd5.cue` selects
`structShape` correctly — so the gap is the list-arm-vs-struct-host pruning INTERACTING with the
spliced comprehension patch behind the force tier.) **Gap-2b = structural (list-vs-struct,
presence-of-`#components`) disjunction-arm pruning behind force**, distinct from Gap-2's
regular-discriminator class and beyond the spike's GO-WITH-GATE scope. Filed as the next argocd
blocker in `plan.md`. No CUE divergence (both Gap-2 and Gap-2b are Kue-wrong-vs-cue; Gap-2 now fixed,
Gap-2b open).

---

## SC-1 — closed struct re-opened by a pattern-struct meet (closedness soundness)

First spec-first fix-slice from the consolidated backlog. `mergeStructN`'s pattern arms (5/6)
set the result openness to ONLY the pattern side's openness and applied closedness over the
pattern side alone, dropping the PLAIN side's `StructOpenness` and closedness. So a closed
`#Def` met with an open pattern struct was silently re-opened: `#C & P & {z:9}` admitted `z`,
where the CUE spec (closedness is conjunctive/monotone — "closing = adding `..._|_`") and cue
v0.16.1 both reject (`out.z: field not allowed`).

**The representation refinement (illegal-states-unrepresentable).** The naive "meet the
openness + apply both sides' closedness" is INSUFFICIENT on its own, because the meet result
retains the open side's pattern, and a single `patterns` list cannot say whether a stored
pattern CLOSES (widens the allowed set) or only CONSTRAINS values. Three oracle-confirmed
constraints force the split: (a) `#D:{a,[string]}` — a closed def's OWN pattern admits matching
fields (`#D & {z:9}` admits `z`); (b) `#C & P` (P open) — P's pattern does NOT widen `#C`'s
closed set (`& {z:9}` rejects `z`); (c) P's pattern STILL constrains values across later meets
(`(#C & P) & {a:50}` with `P:[=~"^a"]:<10` rejects `a:50`). A pattern's closing role is intrinsic
to whether its declaring struct is closed. So `Value.struct` gained `closingPatterns : List Value`
(the label-predicates that participate in the closed allowed-set; a subset of `patterns`'
predicates), built through `mkStruct` (default: the struct's own pattern predicates when closed,
`[]` when open — an open struct closes nothing) and threaded through every struct
rebuild/eval/resolve/normalize site. New `applyClosingPatternsWith` keys the closedness check on
the closing subset, not all patterns.

**Meet composition.** `mergeStructN` now: result openness = `StructOpenness.meet leftOpenness
rightOpenness`; closedness applied from BOTH sides (`applyClosingPatternsWith` per side — each
side's allowed set = its fields + its CLOSING patterns; an open side admits everything); result
`closingPatterns` = union of both sides' (so a later meet still closes). Arm 1 (plain×plain) is
behavior-preserving (both sides have no closing patterns ⟹ identical to the old
`applyStructClosedness`). The B2.5 tail×pattern catch-all is unchanged (always `defOpenViaTail` —
open, closes nothing). `closeValue` and the def-body normalize path keep all-patterns-closing
(the patterns are the struct's own).

**Tests.** 4 `native_decide` pins in `LatticeTests`: closed×open-pattern stays closed (empty
closing set); `(#C & P) & {z:9}` rejects `z` (`fieldNotAllowed`); closed def's own pattern admits
a matching field; open struct met with a pattern stays open (no over-close). Fixture +
`FixturePorts` port: `definitions/sc1_closed_meets_pattern_stays_closed` (`#C & P & {a:1, z:9}` →
`a:1` allowed, `z: _|_`).

**Verify.** `lake build` green (96 jobs); `scripts/check-fixtures.sh` → `fixture pairs ok` (all
existing fixtures held — cue agrees with the stricter behavior, so nothing relied on the bug; no
pin/fixture encoded the re-open); `shellcheck` clean. cert-manager re-probed READ-ONLY: exports
clean (exit 0), no regression. argocd untouched (still the Gap-2b perf/pruning wall).

**Follow-up filed (SC-1b, MED).** The `closingPatterns` union carry-forward is lossy for two
CLOSED defs with disjoint explicit fields but overlapping patterns — the correct forward
allowed-set is the INTERSECTION (`#A:{a,[=~"^x"]} & #B:{b,[=~"^x"]}` → `a`/`b` rejected on a later
meet, `x1` admitted). The at-this-meet marking is correct (sequential closedness); only the stored
forward set over-admits. Pre-existing (not introduced by SC-1) and broader; needs an
intersection-aware closed allowed-set. Recorded in `spec-conformance-audit.md`. No CUE divergence
(cue is correct here too).

## D#1a — bottom comprehension guard propagates instead of vanishing (soundness)

Second spec-first fix-slice from the backlog. `expandClausesWithFuel` / `expandListClausesWithFuel`
matched the guard as `.prim (.bool true) => continue | _ => pure []`; the catch-all swallowed
EVERYTHING non-`true`, so a guard evaluating to BOTTOM (`if (1/0 > 0) {…}`) silently produced an
empty struct — the div-by-zero error vanished (a soundness hole). Spec: an `if` guard "terminates
the current iteration if it evaluates to false"; *false* is the only drop. A bottom guard is an
error, and bottom propagates recursively. cue errors on a bottom guard.

**Mechanism.** The six expansion helpers in the mutual block —
`expandClausesWithFuel`/`expandForPairsWithFuel`/`expandComprehensionWithFuel`/
`expandComprehensionsWithFuel` and the two list twins — changed return type from
`EvalM (List …)` to `EvalM (Except Value (List …))`. `Except.error b` carries the actual bottom
value (preserving `.bottomWith reasons`, e.g. `divisionByZero`) and short-circuits every concat in
the for-pairs / multi-comprehension recursion (explicit `.error → propagate` / `.ok → continue`
matches, total, no monad-transformer). The guard match is now ENUMERATED, no catch-all swallow:
`.bool true` → continue, `.bool false` → `[]` (the spec drop), `.bottom`/`.bottomWith` →
`.error testCondition`, residual `_` → still `[]` (with a comment that D#1b makes the incomplete
case DEFER). Three call sites re-surface the error as the result bottom: the `.comprehension` eval
arm, the eager + forced `.structComp` arms (`match (<- expand…) with | .error bot => pure bot |
.ok expanded => …`), and `evalListItemsWithFuel`.

**Second swallow found + fixed.** The clauses-exhausted `[] =>` arm evaluates the body struct and
had `| .struct fields _ none [] _ => pure fields | _ => pure []`. When a bottom guard sits one
level deeper (inside a `for`-body struct, `for k in … { if (1/0>0) {…} }`), the body evaluates to
`.bottom` and was dropped by that catch-all. Added `.bottom`/`.bottomWith` body → `.error`, so the
nested-bottom case propagates too. (The list twin's `[evaluatedBody]` already preserves a bottom
body as an element — no swallow there.)

**Granularity.** Struct guard → whole comprehension/struct becomes the bottom (`out: _|_`) — the
guard fails before any field exists, so the bottom can only attach at the comprehension-value
level. List guard → the bottom lands in the element slot (`[_|_]`), matching Kue's pre-existing
`[1/0]` → `[_|_]` and `{a: 1/0}` → `{a: _|_}` convention (bottoms are positioned, not collapsed at
eval/render). cue addresses these as `out` vs `out.0` errors respectively; both are "error". The
soundness fix is that the bottom is PRESERVED (caught by `containsBottom`), never swallowed.

**Tests.** 4 `native_decide` pins in `PresenceTests` (bottom guard propagates; bottom-from-sibling
propagates; `false` still drops; `true` still yields) + 3 fixtures
(`comprehensions/guard_bottom_propagates` → `out: _|_`, `list_guard_bottom_propagates` →
`out: [_|_]`, `guard_bottom_from_sibling` → both `_|_`) with `FixturePorts` ports.

**Verify.** `lake build` green (96 jobs); `scripts/check-fixtures.sh` → `fixture pairs ok` (all
existing fixtures held — none carries a bottom guard); `shellcheck` clean. cert-manager re-probed
READ-ONLY: exports clean (exit 0, ~34s), no regression (it has no bottom guards). D#1b
(incomplete-guard deferral) still OPEN — larger, couples with D#2 structural cycles.

## F-1 — `regexp` builtin import + `regexp.Match` call-form dispatch (2026-06-19)

**Problem.** Real prod9 apps `import "regexp"` but Kue rejected the import outright
(`unresolved import: regexp`) — `"regexp"` was absent from `builtinImportPaths`, even though a
regex engine already backs `=~`. A real-app blocker (audit F-1, HIGH).

**Fix.** Two contained changes plus a deferral-signal: (1) add `"regexp"` to `builtinImportPaths`
(`Module.lean`) so the loader leaves it to the call-form dispatch like `strings`/`list`/`math`;
the bare `regexp` ref then stays unresolved-as-package exactly as the other stdlib names. (2) add
`evalRegexpBuiltin` (`Builtin.lean`) and wire it into `evalBuiltinCall`'s prefix dispatch.
`regexp.Match(pattern, string) -> bool` calls `stringRegexMatches pattern s` — the SAME engine
entrypoint `=~` (`evalRegexMatch`) uses, so the two agree by construction. (3) add
`BottomReason.unsupportedBuiltin (name)` (`Value.lean`).

**Match semantics — UNANCHORED, confirmed.** `regexp.Match` matches if the pattern occurs ANYWHERE
in the string (`stringRegexMatches` runs `regexMatchAnywhereWithFuel` unless the pattern is
`^`-anchored), identical to Go's `regexp.MatchString` and CUE's `=~`. Cross-checked vs `cue`
v0.16.1: `^x`/`y`/`b`/`q`/`z$`/`[0-9]` all byte-identical (`y`/`b` match mid-string → unanchored
confirmed).

**Deferrals (RX-1).** The engine is a boolean matcher only — no submatch extraction, no
substitution. So `ReplaceAll`, `ReplaceAllLiteral`, `Find`/`FindSubmatch`/`FindAll*`, and every
other capture/substitution form are DEFERRED: a CONCRETE call yields
`.bottomWith [.unsupportedBuiltin name]` (a clear unsupported signal, NOT a silent wrong answer); an
ABSTRACT-arg call stays an unresolved `.builtinCall` for a later pass. The new bottom reason
collapses to `.contradiction` in the manifest (line 77, `.bottomWith _` is reason-agnostic), so it
exports as an error with no manifest behavior change. ⚠ prod9
(honda-obs/lemonsure/ssw `defs/filters/regexp.cue`) uses ONLY `regexp.ReplaceAll` with `${n}`
backrefs — F-1 unblocks the import but NOT those apps' exports; they need RX-1. **F-1's dispatch
inherits RX-1's pending engine limits** (grouped quantifiers, `\b`, lazy quantifiers, multi-group,
invalid-pattern-treated-as-literal — the engine has no validity check). RX-1 fixes both `=~` and
`regexp.*`.

**Tests.** 7 `native_decide` pins in `BuiltinTests` (anchored-start; unanchored mid-string;
no-match; shared-engine dispatch; ReplaceAll-unsupported-not-silent; ReplaceAll-stays-unresolved-on-
abstract-arg) + fixture `builtins/regexp_match` (six Match forms, `FixturePorts` port) + module
fixture `modules/regexp_import` (end-to-end loader: `import "regexp"` resolves + dispatch runs).

**Verify.** `lake build` green (96 jobs); `scripts/check-fixtures.sh` → `fixture pairs ok`;
`shellcheck` clean. cert-manager re-probed READ-ONLY: exports clean (~34s), no regression. prod9
probe: the `defs/filters` package no longer errors on `import "regexp"` — it now advances to a
*different* unimplemented builtin (`text/template`), proving the regexp import is unblocked.

## SC-1d — parser preserves the `...` tail when a struct also has patterns (over-close regression fix, 2026-06-19)

**Problem.** `Parse.parsedFieldsValue` dropped the `...` tail at PARSE time whenever the struct
ALSO declared pattern constraints. The `some tail` branch's `| _, _ => declared` arm returned
`declared` (built from `parsedFieldsBaseValue`, which forces `.regularOpen` + `none` tail) the
moment patterns were present, discarding the `...`. Harmless while pattern-defs never closed; once
SC-1c made a no-`...` pattern def CLOSE, a def written `#A: {x, [=~"^a"], ...}` parsed WITHOUT its
`...`, so normalize closed it and it wrongly REJECTED extra fields the `...` should admit (an
over-close — a wrong REJECTION). Spec: a `...` makes the struct OPEN for all regular fields
regardless of pattern constraints (the two are orthogonal axes on the unified `Value.struct`,
which carries both tail/openness AND patterns/closingPatterns — Area-C).

**Fix.** Co-represent tail + patterns at parse time. Introduced one tail-aware `baseValue`:

    let baseValue :=
      match parts.tail with
      | some tail => mkStruct parts.fields .defOpenViaTail (some tail) parts.patterns
      | none => parsedFieldsBaseValue parts.fields parts.patterns

and routed EVERY `declared` arm through it (plain base, comprehension-only via `structCompOpenness`,
and the comprehension+pattern `.conj` whose base arm is now `baseValue`). `mkStruct` with
`.defOpenViaTail` enforces the ILL-1 coherence: the tail is kept, the patterns are retained as
value-constraints, and `closingPatterns = []` (open ⇒ closes nothing). The whole trailing
`match parts.tail with | none => declared | some tail => …` dispatch then collapsed to a bare
`declared` — fully redundant once `baseValue` encodes the tail in all four pattern×comprehension
combinations.

**Behavior (cross-checked vs cue v0.16.1, they agree — `...` opens).**
- `#A: {x: int, [=~"^a"]: int, ...} & {x: 1, extra: 5}` → admits `extra` (OPEN via `...`), output
  retains the `...`. This is the fixed case.
- `#A: {x: int, [=~"^a"]: int} & {x: 1, z: 9}` (NO `...`) → REJECTS `z` (`z: _|_`). SC-1c closing
  still holds — the fix did not re-open the no-`...` pattern def.
- `#A: {x: int, [=~"^a"]: int, ...} & {x: 1, abc: "no"}` → `abc` matches the pattern, so the value
  is constrained: `"no"` vs `int` → bottom. `...` admits the LABEL; the pattern constrains the VALUE.

**Tests.** 4 `native_decide` pins in `ParseTests` (`parse_pattern_tail_stays_open`,
`parse_pattern_notail_closes`, `parse_pattern_tail_value_constrains`, and
`parse_pattern_tail_node_is_open_via_tail` — inspects the parsed node directly:
`openness = .defOpenViaTail` ∧ `tail.isSome` ∧ `closingPatterns = []`) + 3 fixtures
(`definitions/sc1d_pattern_tail_stays_open`, `…_notail_closes`, `…_tail_value_constrains`) with
`FixturePorts` ports.

**Verify.** `lake build` green (96 jobs); `scripts/check-fixtures.sh` → `fixture pairs ok`;
`shellcheck` clean. cert-manager re-probed READ-ONLY: exports clean (exit 0, ~32s), no regression
(the remaining diff vs cue is the known field-ORDER gap #3 — same keys/values). argocd still bottoms
on the PRE-EXISTING Bug2-3/perf wall, NOT an SC-1d/SC-1c over-close. No prod9 file combines a
`[pattern]:` with `...` in one struct, so SC-1c had not over-closed a live `{patterns, ...}` shape —
SC-1d is the forward-looking fix for the regression SC-1c could cause, not a recovery of a live one.
SC-1d is purely additive to openness (preserves `...`), so it can only make a struct MORE open,
never more closed — it cannot regress the real apps.

## F-2 — strip the self-module `@vN` major-version suffix in `readModuleInfo` (2026-06-19)

**Problem.** `readModuleInfo` (`Module.lean`) read the `module:` field VERBATIM into
`ModuleContext.modPath`, so a module declared `module: "ex.com/m@v0"` yielded
`modPath = "ex.com/m@v0"`. An in-module import of the BARE path `"ex.com/m/sub"` then prefix-matched
against `"ex.com/m@v0/"` in `resolveImportSubpath`/`importUnderModule` → NO match → "unresolved
import". The `@major` suffix was ALREADY stripped for dependency KEYS (`depKeyModulePath`, applied in
`parseDeps`) but NOT for the importing module's OWN path — that asymmetry was the bug. CUE modules
contract: the `@vN` in `module:` is the major version, addressed separately; import paths name the
BARE module path. So the self `modPath` used for in-module resolution must be bare.

**Fix (DRY — reuse the existing strip).** Apply the existing `depKeyModulePath` to the `module:`
field in `readModuleInfo`'s success arm: `pure (.ok (depKeyModulePath path, parseDeps value))`. One
line, no duplicated logic. Both `readModuleInfo` callers route through it — `loadFileBound` /
`loadPackageDir` (the importing module's own context) and `resolveImportTarget` (the cross-module
hop into a dependency's own context) — so every `modPath` consumer (`resolveImportSubpath`,
`importUnderModule`, `resolveCrossModule`) now sees the bare path. `depKeyModulePath` is the identity
on a key with no `@` (`first :: _` returns the whole string), so the no-suffix case is unchanged. The
dep-strip path is untouched (deps strip their own keys in `parseDeps`).

**Behavior (cross-checked vs cue v0.16.1, they agree).**
- `module: "ex.com/m@v0"` + `import "ex.com/m/defs"` → resolves the in-module subdir and exports the
  merged value (was "unresolved import" before). **The fix.**
- `module: "ex.com/m"` (no suffix) + `import "ex.com/m/sub"` → resolves exactly as before. **No
  regression.**
- A dependency (cross-module) import still resolves via the unchanged `parseDeps`/`depKeyModulePath`
  dep-key strip. **Dep path untouched.**

**Tests.** 4 `native_decide` pins in `ModuleTests` pinning the composition the bug lived in:
verbatim `resolveImportSubpath "ex.com/m@v0" "ex.com/m/sub" = none` (the bug), stripped
`resolveImportSubpath (depKeyModulePath "ex.com/m@v0") "ex.com/m/sub" = some "sub"` (the fix),
stripped module-root `= some ""`, and the no-suffix regression guard
`resolveImportSubpath (depKeyModulePath "ex.com/m") "ex.com/m/sub" = some "sub"`. Plus module fixture
`modules/self_major_version_strip` (`module: "ex.com/m@v0"`, multi-file package, root `main.cue` does
`import "ex.com/m/defs"` and meets `defs.#Widget`), exercised end-to-end by the loader and diffed
byte-for-byte against `cue export --out json` (oracle output committed as `expected`). The existing
`export_subdir` (no-suffix self-import) and `crossmod*` (dep import) fixtures are the no-regression
guards on the unchanged paths.

**Verify.** `lake build` green (96 jobs); `scripts/check-fixtures.sh` → `fixture pairs ok`;
`shellcheck` clean. **Real-app probe (READ-ONLY):** swept every `cue.mod/module.cue` under
`prod9/` and `hatari/` — NO self-module declares an `@vN` suffix today (all bare: `prodigy9.co`,
`sawaddee.com`, `honda.co.th`, `prodigy9.co/defs`, …). So F-2 changes NO current real-app
resolution; it is the forward-looking fix for CUE's `@vN`-in-`module:` major-version form. It can
ONLY help (a future `@vN` module's in-module imports resolve instead of erroring), never regress —
the no-suffix case is the `depKeyModulePath` identity. No in-repo cert-manager/argocd module
fixture, and neither real app uses `@vN`, so there was no `@vN` byte-identity surface to re-probe;
the no-suffix self + dep fixtures stayed green, which is the relevant regression surface.

## SC-2 — nested def-body closedness via a closing field-walker twin (2026-06-19)

The closedness cluster's last fix (after SC-1/1c/1d). A referenced closed def closed only its
TOP struct; nested PLAIN-struct field values stayed `regularOpen`, so `#A: {a: {b: int}} & {a:
{b: 1, extra: 5}}` ADMITTED `extra` while the spec + cue REJECT it ("referencing a def
recursively closes it anywhere within the definition"). Two faces, one root: SC-2a (the
single-meet over-open above, cue+spec AGREE — plain correctness) and SC-2b (`(#D & {}).r & {b}`,
where cue RE-OPENS on the no-op `& {}` instantiation but the spec says closedness is monotone
through meet — Kue DIVERGES). Spike-confirmed they are NOT separable: Kue stores closedness on the
value and meet is monotone (no shed-on-`&` code), so closing the nested value once (SC-2a)
preserves it through instantiation (SC-2b) for free.

**Root cause.** The CLOSING walker `normalizeDefinitionValueWithFuel`'s `.struct` arms set the
struct's OWN openness to `defClosed` but descended fields via the SHARED `normalizeFieldWithFuel`,
whose regular arm recurses the SPINE walker `normalizeDefinitionsWithFuel` — which preserves
openness and closes only nested `#Def`s, never nested plain-struct VALUES.

**Fix (Normalize-only).** Added `normalizeDefinitionFieldWithFuel`, a CLOSING twin of
`normalizeFieldWithFuel` whose regular/optional/required arm recurses the CLOSING walker
(`normalizeDefinitionValueWithFuel`) instead of the spine; the DEFINITION arm keeps recursing the
CLOSING walker (a nested `#Def` body still closes); `importBinding` SKIP and `letBinding`/hidden
`_x` SPINE arms are UNCHANGED. The CLOSING walker's no-pattern `.struct`, `.structComp`, and
pattern-bearing `.struct` arms now map this twin over their fields. A separate function (not a
`closing : Bool` flag) keeps the call site's intent encoded in WHICH function it calls
(illegal-states philosophy). No `Lattice`/`Eval` edit — `mergeStructN`/`applyStructClosedness`
enforce the nested `defClosed` at every meet and preserve it through instantiation (monotone).

**Trap defence (the soundness obligations, all oracle-checked vs cue v0.16.1).**
1. A referenced closed def's nested field REJECTS an extra, recursively at any depth — oracle #1
   (`#A:{a:{b:int}}`), #2 (fully concrete `b: int | *0`), #3 (depth-2 `a.b.c`), #6 (direct selector
   `#D.r & {b}`). The twin sets `defClosed` on the nested value; `mergeStructN` rejects. ✓
2. A PLAIN (non-def) nested struct STAYS OPEN — oracle #5 (`A:{a:{b}}` admits `extra`). A plain
   struct never reaches the closing walker (it goes through the spine / no normalization-close), so
   the twin cannot touch it. ✓
3. A nested `...` STAYS OPEN — oracle #4. The CLOSING walker returns a `defOpenViaTail` struct
   unchanged, so depth-recursion respects a nested `...` for free. ✓
4. A def's HIDDEN-field nested struct STAYS OPEN — oracle #8 (`#A:{_h:{x:int}}` ; `x._h & {extra}`
   admits). The hidden arm stays on the SPINE (untouched). ✓
   An unreferenced IMPORT binding stays lazy — the `importBinding` arm is untouched (SKIP), so
   cert-manager/argocd cannot re-bottom (the A2 trap; the `FieldClass.importBinding` marker scopes
   the skip precisely to bound packages).

**SC-2b divergence (recorded in cue-divergences.md).** `(#D & {}).r & {x:1, extra:2}` → cue admits
`extra` (re-opened by the `& {}` instantiation), Kue rejects (`extra: _|_`). cue is internally
inconsistent — the DIRECT path `#D.r & {extra}` rejects (cue+Kue agree). The `& {}` meets with the
top struct (identity on closedness), so it cannot lattice-logically add openness → cue's re-open is
an eval-strategy artifact. Kue preserves closedness on both paths.

**Tests.** 4 `native_decide` soundness pins in `EvalTests` (`eval_sc2_nested_def_field_closes`,
`…_plain_nested_struct_stays_open`, `…_nested_tail_stays_open`, `…_hidden_field_nested_stays_open`);
the flipped `eval_sc2b_instantiated_def_field_stays_closed` (was `eval_b6_instantiated_def_field_reopens`,
which asserted cue's re-open ADMIT — now asserts the spec-correct REJECT); 5 `sc2a_*` fixtures with
`FixturePorts` entries (`sc2a_nested_def_field_closes`, `…_closes_concrete`, `…_depth2`,
`…_tail_stays_open`, `sc2a_direct_selector_closes`); the renamed
`sc2b_instantiated_def_field_stays_closed` fixture (the one intentional drift). Updated
`eval_meet_lazy_hidden_def` — `#D`'s nested regular field `out` (a plain struct within the def body)
now normalizes to `.defClosed` (spec-correct; formatted output unchanged, closedness is invisible in
`eval` display).

**Verify.** `lake build` green (96 jobs); `scripts/check-fixtures.sh` → `fixture pairs ok` (all
existing fixtures byte-identical except the one flipped SC-2b fixture); `shellcheck` clean.
**Real-app probe (READ-ONLY, from `prod9/infra`):** cert-manager `kue export --out yaml` exit 0
(~32s), diff vs `cue export` is the known field-ORDER gap #3 only (same keys/values, no `_|_`, no
key added/removed) → content-identical. argocd `kue export` still exits 1 on the pre-existing
Bug2-3 (`conflicting values (bottom)`, a `fieldConflict` — NOT a `field not allowed`/closedness
bottom, ~91s) → no new closedness regression. Closedness cluster drained to zero; next-step → RX-1.

---

## Completed Slice: RX-1a — regex AST + parser (additive, byte-identical)

Goal: first of three RX-1 slices replacing the non-RE2 hand-rolled regex matcher in
`Value.lean` (which expands only the first group, lacks `\b`/lazy quantifiers, and has an
unsound anchoring-dependent substring fallback — silently mis-validating real grouped /
semver / DNS patterns). RX-1a adds the AST + parser ONLY; NO engine wiring, so behavior is
byte-identical (the new module is unused by any eval path). RX-1b adds the NFA + Pike-VM and
rewires the 3 dispatch sites + deletes the old engine; RX-1c adds submatch + `ReplaceAll`.

**New leaf module `Kue/Regex.lean`.** Depends only on `Char`/`String` — no `Value`/`Eval`
import (a true leaf in the import graph; also lets `Value.lean` shed the old engine in
RX-1b). Imported by `Kue.lean` and `Kue/Tests/RegexTests.lean` so it compiles + its
theorems run, but by NO eval path.

**`Regex` AST.** RE2-subset, illegal-states-unrepresentable: `empty` / `lit` / `cls`
(ranges + `negated`) / `any` / `anchorStart` / `anchorEnd` / `wordBoundary (negated)` /
`concat` / `alt` / `star` / `plus` / `opt` / `«repeat» (min) (max : Option Nat)` /
`group (index : Option Nat)`. **Greediness is a `Bool` field on each quantifier**, not a
separate lazy constructor (match-priority logic stays in one place for RX-1b). `repeat`'s
`max : Option Nat` makes `{m,}` representable without a sentinel. `group.index` is `none`
for non-capturing `(?:…)`, `some i` for a capturing group (numbered left-to-right from 1).
Derives `Repr, BEq` only — Lean cannot auto-derive `DecidableEq` through the nested
`List Regex` recursion, so pins compare with `==`/`Bool` (the suite's `… = true` shape).

**`parseRegex : String → Except RegexParseError Regex`.** Recursive-descent
(`alt → concat → quantified → atom`, mutually recursive through `group`), TOTAL via
input-length fuel (the standing parser exception) — no `partial`, no `sorry`; each mutual
edge strips exactly one fuel from a matched `fuel+1`, `termination_by fuel` per function.
Char-class body + `{m,n}` digit-runs are separately fuel-bounded. **Invalid pattern →
`.error`, NEVER a silent literal-fallback** (the old engine's unsound behavior). Errors are
typed: `.malformed` (unbalanced `(`/`)`, dangling `\`, nothing-to-repeat, bad `{m,n}`),
`.backreference c` (RE2 has no backrefs — `\1` rejected, distinct from `ReplaceAll`'s
`${n}` template, an RX-1c concern), `.unsupportedRegex feature` for DEFERRED constructs
(flags `(?i)`, named captures `(?P<…>)`, `\A`/`\z`/`\Q`, POSIX `[[:alpha:]]`, Unicode
`\p{…}`, and `\D`/`\W`/`\S` inside a class which would need set-complement) —
stub-not-silent-wrong.

**CUE divergence found.** `a{5,2}` (m>n): cue/RE2 reject as `invalid repeat count`. Kue's
`parseRepeatSuffix` distinguishes a well-formed-but-bad brace (`.invalid` → parse error)
from a non-quantifier `{` (`.notQuant` → literal `{`), matching RE2 — not a silent literal
fallback.

**Tests (`Kue/Tests/RegexTests.lean`, all `native_decide`).** The 7 audit repros pin the
EXACT AST: `^(ab)+$`/`^(ab)*$` (quantifier binds the GROUP, not trailing `b`),
`^([a-z0-9]+(-[a-z0-9]+)*)$` (nested + multi group, indices 1/2),
`^(v[0-9]+)(\.[0-9]+)*$` (multi-group, `\.` literal dot), `a(b|x)(c|y)d` (two alt groups,
left-to-right indices), `\bdog\b` (`\b` as anchor both ends, not literal `b`), `a+?` (lazy
plus, not opt-of-`a`). Plus: greedy-vs-lazy across `* ? `; `{3}`/`{2,}`/`{2,5}`/`{2,5}?`
shapes; non-capturing group doesn't consume an index; negated class + perl-class atoms +
`.`; invalid patterns error (unbalanced open/close, dangling `\`, `a{5,2}`, `*abc`);
`\1` → `.backreference '1'` specifically; deferred constructs `(?i)`/`\p{L}`/`(?P<…>)`/
`[[:alpha:]]` → `.unsupportedRegex`.

**Verify.** `lake build` green (96+ jobs, new module + theorems check);
`scripts/check-fixtures.sh` → `fixture pairs ok` (ZERO byte-drift — new module unused by
eval); `shellcheck` clean. Next-step → RX-1b (Thompson compile + Pike-VM + rewire the 3
dispatch sites `Eval.evalRegexMatch` / `Lattice.meetStringRegexPrim` / `Builtin.regexp.Match`
+ delete the old `Value.lean` engine ~L771-1012; gated by the 7 repros matching correctly +
existing simple-pattern fixtures staying green).

## Completed Slice: RX-1b — Thompson NFA + Pike-VM, engine LIVE, old engine deleted (2026-06-19)

Goal: make the RX-1a AST/parser the LIVE regex engine and remove the old backtracking
matcher. This is the BEHAVIOR CHANGE — the old `Value.lean` engine silently mis-validated
grouped quantifiers, nested/multi groups, `\b`, lazy quantifiers, and had an unsound
anchoring-dependent substring fallback. The gate is conformance to RE2/spec (cross-checked
against cue v0.16.1), NOT byte-identity to the old (buggy) engine.

**Engine added to `Kue/Regex.lean` (the leaf module — still no `Value`/`Eval` import).**

- `Inst` — a flat instruction program (RE2/Pike style): `char (ranges) (negated) (next)` /
  `any (next)` / `split (a) (b)` / `jmp (next)` / `save (slot) (next)` / `assert (kind)
  (next)` / `accept`. `split`-arm ORDER encodes greediness (arm `a` tried first). `AssertKind`
  = `start`/`end`/`wordBoundary`/`notWordBoundary`. `NFA` = `{ insts, start, slots }`.
- `compile : Regex → NFA` — Thompson construction in a continuation-passing style
  (`compileFrag prog re cont` returns the extended program + this fragment's entry pc, so
  forward/backward references are exact). Bounded `{m,n}` is **desugared before compile** by a
  total `desugar : Regex → Regex` pass (each child desugared first, then `expandRepeat`
  rewrites `{m}`→exact copies, `{m,}`→copies+`star`, `{m,n}`→copies+nested-opts), so the VM
  never sees a counter. `compileFrag`/`compileSeq`/`compileAlt` are a mutual block, total by
  `sizeOf` of the (finite, repeat-free) AST. `save 2i`/`save 2i+1` bracket capturing group i;
  `save 0`/`save 1` bracket the whole match.
- `NFA.run : NFA → List Char → Option (Array (Option Nat))` — a TOTAL Pike-VM. The outer
  `loop` is structural recursion on the input `List Char`. At each position the ε-closure
  (`addThread`) follows `split`/`jmp`/`save`/`assert` deduped by pc over the FIXED program
  (`visited` array), parking threads on `char`/`any`; fuel = `insts.size` is exact (each pc
  enters the closure at most once) and never spuriously hit — a `split`/`jmp` cycle is cut by
  `visited`, not fuel. No backtracking → linear in `input.length × insts.size`. **Priority /
  greediness:** the closure preserves arm order; the first `accept` in a closure CUTS all
  lower-priority threads reached after it; a match found at a LATER position overrides the
  earlier one (the surviving thread was higher priority). Leftmost-start comes from the
  unanchored prefix `.*?` being lazy. This removes the old engine's soundness hole
  (fuel-exhaustion-as-non-match).
- `matchRegex : String → String → Bool` — the unanchored RE2 `Match`/CUE `=~` boolean.
  Prepends an implicit lazy `.*?` (`star false any`) so one linear pass scans every start
  position. Invalid/deferred pattern → `false` (conservative). `regexParseError?` exposes the
  parse error for dispatch sites that want to distinguish an invalid pattern from a non-match.

**Rewired FOUR dispatch sites** (the audit named 3; `Order.subsumesWithFuel`'s `.stringRegex`
arm — the subsumption twin of `meetStringRegexPrim` — was the 4th, found by grep):
`Eval.evalRegexMatch`, `Order.subsumesWithFuel`, `Lattice.meetStringRegexPrim`,
`Builtin.regexp.Match` now call `matchRegex`. Each module gained `import Kue.Regex`.

**Deleted the old engine** — `Value.lean` ~L771-1011 (`RegexAtom`, `stringRegexMatches`,
`stringRegexAlternativeMatches`, `parseRegexAtom`, the `regexMatch*WithFuel` mutual block,
`expandFirstRegexGroup`, `splitRegexAlternatives*`, `parseRegexGroupBody*`,
`findFirstRegexGroup*`, et al.). Dropped the now-unused `import Init.Data.String.Search` from
`Value.lean` (`Parse.lean` keeps its own copy; it was the only other user).

**Gate met (behavior change toward the spec).** All 7 repros now match cue v0.16.1:
`^(ab)+$ ~ "abab"`=true (and `~ "aba"`=false); `^([a-z0-9]+(-[a-z0-9]+)*)$ ~ "foo-bar-baz"`
=true; `^(v[0-9]+)(\.[0-9]+)*$ ~ "v1.2.3"`=true; `a(b|x)(c|y)d ~ "axyd"`=true; `\bdog\b ~
"cat dog"`=true (and `~ "dogcat"`=false); `a+? ~ "aaa"`=true; the unsound-fallback case
`(foo|bar)+ ~ "xfoobarx"`=true (now a consistent anywhere-search). NO existing regex fixture
flipped — the old engine got the simple anchored/class/`{m,n}` patterns right and the new
engine reproduces every one (`scripts/check-fixtures.sh` → zero drift). Cross-checked
edge cases vs cue (empty pattern, `^$`, nested star `^(a*)*$` — terminates, no ε-blowup).

**Tests.** New `native_decide` pins in `RegexTests.lean`: the 7 repros as `matchRegex` bools
(match + non-match each), all simple-pattern fixtures as bools, greedy-vs-lazy priority +
group submatch spans read directly off `run`'s capture array (`(a+)(b+)` over "aabbb" →
whole [0,5)/g1 [0,2)/g2 [2,5); `a.*c` greedy [0,6) vs `a.*?c` lazy [0,3)) — proving the
capture slots are live and correct for RX-1c. New fixture `numeric/regex_re2_repros`
(`.cue`/`.expected` + `FixturePorts` port), oracle-checked vs cue. Updated the BuiltinTests
shared-engine pin to `matchRegex`.

**Verify.** `lake build` green (100 jobs); `scripts/check-fixtures.sh` → `fixture pairs ok`
(only the new fixture added, everything else byte-identical); `shellcheck` clean. Totality:
`#print axioms` on `matchRegex`/`compile`/`run` shows only `propext`/`Classical.choice`/
`Quot.sound` (no `sorryAx`). prod9 probe (READ-ONLY): cert-manager exports content-identical
to cue (field-order-insensitive, ~32s); argocd unchanged (still its pre-existing Bug2-3
bottom). Next-step → RX-1c (expose the capture array; `regexp.ReplaceAll` + `Expand` template
grammar + `Find*`/`FindSubmatch`; remove the `unsupportedBuiltin` deferral arms — unblocks
prod9's `regexp.ReplaceAll` filter packages).

## RX-2b — invalid/deferred regex pattern bottoms at every regex site (soundness, 2026-06-19)

**Bug (pre-existing, carried from the old engine).** `matchRegex` (`Regex.lean`) collapses a
`parseRegex` error to `false`, so an invalid (`a(`) or deferred (`(?i)a`) pattern silently
became a NON-MATCH at every dispatch site: `=~` → `false`, `!~` → `true`, the lattice pattern
meet bottomed a VALID string against the invalid pattern, and a `[=~"a("]:` label predicate
silently failed to constrain. RE2/cue ERROR on an invalid pattern (`invalid regexp`). A
soundness hole at every regex site.

**Fix.** The already-defined-and-unused `regexParseError? : String → Option RegexParseError`
became the shared decision. New `BottomReason.invalidRegex (pattern : String) (error :
RegexParseError)` carries the offending pattern + the structured parse error (strongly-typed,
not a stringly message — `Value.lean` gained `import Kue.Regex`; Regex stays an import-less
leaf, no cycle). Each site guards on `some err → .bottomWith [.invalidRegex pattern err]`
BEFORE matching:

- `Eval.evalRegexMatch` — concrete-string arm bottoms; the abstract operand still hits the
  `.binary .regexMatch` residual arm (deferred, NOT bottom — same discipline as F-1's
  `regexp.Match` deferral).
- `Eval.evalRegexNotMatch` — delegates to `evalRegexMatch`; its `.bottomWith` flows through the
  `value => value` arm, so `!~` bottoms (NOT silently `true`). No separate guard needed.
- `Lattice.meetStringRegexPrim` — invalid pattern bottoms before the prim match (was: a valid
  string bottomed against the invalid pattern).
- `Order.subsumesWithFuel` `.stringRegex`-vs-string arm — `(regexParseError? pattern).isNone &&
  matchRegex …`: an invalid constraint is unsatisfiable, subsumes nothing.
- `Builtin.regexp.Match`.

**A FIFTH consumer the audit's "exactly 4 sites" sweep missed.** The pattern-LABEL application
path: `Lattice.labelMatchesPatternWith` wraps the label×predicate meet in `!containsBottom`, so
the new `.invalidRegex` bottom would be swallowed back into a non-match (the invalid pattern
silently fails to constrain any field). Fixed at the `Eval.applyEvaluatedStructN` chokepoint:
a new `patternsRegexError?` scans the struct's label predicates (`labelPatternRegexError?`
handles a `.stringRegex` and a `.conj`-wrapped one; an ABSTRACT predicate — a `.ref`/`.kind` —
does not trip), and the whole struct bottoms before any pattern application. Contained to the
re-emit chokepoint; the closedness machinery (SC-1/SC-2) is untouched.

**Divergences from cue (recorded, Kue is spec-correct).** (1) cue tolerates an invalid pattern
with NO field-to-match (`{[=~"a("]: int}` → `{}`) — it only errors when a field is matched
against the pattern (lazy eval-strategy artifact). Kue bottoms eagerly: an invalid regex literal
is ill-formed per RE2 regardless of application (illegal-states-unrepresentable). (2) Deferred
RE2 constructs (`(?i)`, `\p{…}`, etc.) bottom in Kue but cue/RE2 SUPPORT them — this is the
RX-2a not-yet-implemented feature surfaced honestly (stub-not-silent-wrong), not a Kue-correct
divergence; RX-2a will implement them. Both in `cue-divergences.md`.

**Tests.** 4 `regexParseError?` helper pins (RegexTests); 9 dispatch-site pins (LatticeTests:
`evalRegexMatch`/`evalRegexNotMatch` invalid+deferred bottom, valid unchanged, abstract residual;
`meetStringRegexPrim` invalid bottom + valid unchanged; `applyEvaluatedStructN` label invalid
bottom + abstract-does-not-trip); 2 (OrderTests: invalid subsumes nothing, valid subsumes match);
1 (BuiltinTests: `regexp.Match` invalid bottom; the F-1 valid pins stay green). 2 fixtures:
`numeric/regex_invalid_patterns` (`=~`/`!~`/deferred bottom + valid match/negate),
`definitions/regex_invalid_pattern_label` (invalid label bottoms the struct) — both with
`FixturePorts` ports, oracle-checked.

**Verify.** `lake build` green (100 jobs); `scripts/check-fixtures.sh` → `fixture pairs ok` (only
the 2 new fixtures added, everything else byte-identical — no valid-pattern regression);
`shellcheck` clean. Axiom-clean: `#print axioms` on `evalRegexMatch`/`meetStringRegexPrim`/
`applyEvaluatedStructN`/`labelPatternRegexError?` = `{propext, Classical.choice, Quot.sound}`
(no `sorryAx`, no `partial`). prod9 probe (READ-ONLY): cert-manager content-identical to cue
(`jq -S`, exit 0, ~32s — valid-pattern apps unaffected). Next-step → RX-1c (submatch +
`regexp.ReplaceAll`/`Find*` — now lands correct-by-construction; every new capture-dispatch arm
inherits the invalid→bottom contract instead of re-introducing the swallow).

## RX-1c — submatch / `regexp.ReplaceAll`/`Find*` over the Pike-VM capture array (2026-06-19)

**Slice.** Completes the regex trilogy. RX-1a/b landed the RE2 Pike-VM which already FILLS a
capture array (`NFA.run`); F-1 stubbed the capture/replace `regexp.*` forms as
`unsupportedBuiltin`; RX-2b made an invalid pattern bottom at every regex site. RX-1c exposes
the capture array and wires the substitution/find forms, inheriting RX-2b's `invalidRegex`
contract by construction.

**Engine layer (the Regex leaf, pure `String → … → Option`).** `findSubmatch`/`find`/`findAll`/
`findAllSubmatch` return leftmost (RE2) match group spans, rune-indexed (the VM iterates `Char`,
matching cue's `=~` rune semantics; spans extracted via `List.extract`/`String.ofList`).
`replaceAll`/`replaceAllLiteral` substitute every non-overlapping match — the former expanding
the Go `Expand` replacement template, the latter splicing verbatim. Two design points that bite:

- **Leftmost match START.** The program's own whole-match slots 0/1 are PINNED to offset 0 by
  the implicit lazy `.*?` unanchored prefix, so they cannot report the true match start. Fix:
  wrap a group-bumped `re` in an explicit whole-match group (`bumpGroups` shifts every group
  index +1), read the wrapper group's slots (2/3) as the true span, drop the prefix-pinned 0/1.
- **Zero-width advance.** `allMatches` iterates non-overlapping leftmost matches; a zero-width
  match (end ≤ its own start) ADVANCES one rune (Go behavior) — otherwise `x*` over `"abc"`
  loops forever. Total: fuel = input length + 2 (one match consumes ≥1 rune of progress).

**Go `Expand` template grammar (NOT regex backreferences).** `$name`/`${name}`/`$n`/`${n}`
interpolate a capture group; `$$` → literal `$`. The LONGEST-NAME rule: a bare `$1suffix` names
group `1suffix` (longest `[0-9A-Za-z_]` run) which does not exist → empty; `${1}suffix` is group
1 then literal `suffix`. Numeric-only names resolve by index; unknown/non-participating → empty.
Named-group references (`$g`) would need `(?P<…>)` which the parser defers, so only numeric
references resolve.

**Dispatch (`evalRegexpBuiltin`, Builtin.lean).** Removed the `unsupportedBuiltin` arms for the
implemented forms. `Find*` family BOTTOMS on no-match (cue v0.16.1 raises `no match`, NOT Go's
nil — oracle-confirmed); `ReplaceAll*` never bottoms on a valid pattern (no-match → `src`
unchanged). `FindAll(p,s,n)`: `n<0` = all, `n≥0` = take n; empty result → bottom. Invalid pattern
→ `.invalidRegex` (RX-2b); abstract arg → residual `.builtinCall`. KEPT `unsupportedBuiltin`:
`FindString*`/`FindAllString*`/`Split` (cue v0.16.1 exposes NO such function — calling them is a
non-function error there) and `FindNamedSubmatch`/`FindAllNamedSubmatch` (need deferred named
captures). Honest signal, not silent-wrong.

**Pre-existing RX-1b bug fixed (newline crossing).** The unanchored-search prefix was
`.star false .any`, but RE2's `.` (`Inst.any`) EXCLUDES `\n` — so `=~`/`Match`/`Find*`/
`ReplaceAll` could not match anywhere after a newline (`matchRegex "two" "one\ntwo"` was false;
cue returns true). Surfaced by the prod9 multiline filter `([^\n]+)--two\n`. Fixed at the cause
with a shared `unanchoredPrefix = .star false (.cls [] true)` (lazy star over a negated-EMPTY
class = matches every char incl `\n`) in both `matchRegex` and `findFrom`; the body's own `.`
is untouched (still RE2-correct, excludes `\n`).

**Tests.** 27 `native_decide` RegexTests (engine layer — submatch spans incl. non-participating
group, find/findAll, ReplaceAll Expand-template incl. `$$`/`${0}`/disambiguation/unknown-group/
multi/no-match/zero-width/empty-pattern, ReplaceAllLiteral, invalid→none, prod9 simple +
multiline, 3 cross-newline regressions) + 19 BuiltinTests (dispatch — every form, no-match
bottoms, invalid→`.invalidRegex`, abstract→residual, `FindString` stays unsupported). New
fixture `builtins/regexp_submatch` (.cue/.expected + FixturePorts port) — Kue output
byte-identical to cue across all 14 fields incl. nested-list `FindAllSubmatch`. Every `expected`
oracle-checked vs cue v0.16.1.

**Verify.** `lake build` green (100 jobs); `check-fixtures.sh` → `fixture pairs ok` (only the new
fixture pair added — zero drift); `shellcheck` clean. Axiom-clean (`replaceAll`/`findSubmatch` =
`{propext, Classical.choice, Quot.sound}`, no `sorryAx`/`partial`). prod9 (READ-ONLY):
cert-manager content-identical to cue (`jq -S`, exit 0, ~32s); argocd unchanged (still its
pre-existing Bug2-3 `conflicting values` bottom, ~94s — NOT a regex error). **prod9 HONEST:** the
`#Regexp` filter (`regexp.ReplaceAll`) now exports cue-exact for both the simple `${1}ly` case
and the multiline `${0}${1}--insert\n` case, but the `filters` PACKAGE as a whole still does NOT
export — its sibling `#Template` filter uses `text/template`'s `template.Execute`, which is
unimplemented (not even in the import allowlist). So RX-1c unblocks the regexp filter, NOT the
full prod9 filters package.

**Regex family status: COMPLETE except RX-2a** (in-class `\D`/`\W`/`\S` set-complement). The
`(?i)` deferred-construct categorization was re-checked: cue matches `"ABC" =~ "(?i)abc"` (true),
Kue bottoms — this is **Kue-incomplete (RX-2a-adjacent), NOT a cue-bug**, and is correctly NOT
recorded in `cue-divergences.md` (no miscategorization). Next-step → **two-phase audit DUE**
(RX-2b + RX-1c since audit #12), then Bug2-3 / D#2.

Files: `Kue/Regex.lean`, `Kue/Builtin.lean`, `Kue/Tests/RegexTests.lean`,
`Kue/Tests/BuiltinTests.lean`, `Kue/Tests/FixturePorts.lean`, `testdata/cue/builtins/regexp_submatch.{cue,expected}`.

## Bug2-3 / Gap-2b — structural list-arm-vs-struct-host disjunction prune (2026-06-19, `d9f66ca`)

**The bug (cue CORRECT, spec-grounded; Kue under-pruned).** A def embedding a STRUCTURAL
disjunction (`listShape | structShape`, discriminated by list-vs-struct SHAPE not a regular
label), embedded one layer down (`#U: {#M}`) and force-narrowed by a sibling regular OUTPUT field
the arms lack: the host's regular fields reached the disjunction only as a SIBLING, never met INTO
the list arm as a value, so the sound `list & {regular fields} = ⊥` prune never fired → both arms
survived → ambiguous bottom (the argocd `.error (.ambiguous)`). Spec basis: unification distributes
over disjunction; a list meets a struct carrying regular fields = bottom.

**Diagnosis (instrumented).** The disjunction is distributed at `meetEmbeddingsWithFuel`'s
`conjDisjArms?`-defer arm, where `current` (the host the arms meet against) was the def body WITHOUT
the host's regular field (`kind`/`meta`): `spliceOperandForEmbed` strips regular fields when
splicing the host narrowing into the embedded def, keeping only hidden + comprehension-read /
discriminator labels. The reduced `meet ([elist|struct]) {kind}` PROVES the prune works when the
host field is present (the elist arm bottoms via the existing `meet`-over-`.disj` primitive); the
gap was purely that the host field never reached the arms.

**Fix (the design's lever, GATED).** `embedBodyEmbedsDisj` detects a disjunction-embedding body (a
`.disj` in `cs`, or a depth-0 `.refId` to a let slot holding a `.disj`). When it fires,
`spliceOperandForEmbed` routes ALL the host's regular OUTPUT fields into the embedded arms. The
existing distribution then prunes a list-shaped arm against the struct host via the SOUND
type-conflict meet; a struct-compatible arm survives untouched (meet idempotent on a field it
already carries). The prune is the meet primitive, NOT a shape heuristic.

**Verify.** `lake build` 100 jobs; `check-fixtures.sh` → `fixture pairs ok` (zero drift); shellcheck
clean. cert-manager (prod9, READ-ONLY) content-identical to cue v0.16.1 (`jq -S`, exit 0) — the gate
holds. 6 `native_decide` pins + fixture `testdata/modules/disj_embed_struct_disc`. Soundness: all
four obligations verified vs cue (struct-arm survives; real-conflict bottoms; directly-narrowed
unchanged; struct|struct stays ambiguous, not falsely pruned).

**argocd NOT unblocked — a SEPARATE pre-existing bug surfaced (Bug2-4).** The structural prune now
works (guard-free repro exports content-identical to cue), but `kue export apps/argocd.cue` still
bottoms (~104s). Cause: a two-level-embedded `let _patch` comprehension guard does not see the host
narrowing. `#U: {#M}`, `#M` embeds `let _patch = { kind: string, for _, add in Self.#additions { if
kind == add.#kind { add.#patch } } }`; the host's narrowed `kind` reaches `#U` but
`embedComprehensionReadLabels` follows let-comprehension reads only ONE level, so `kind` is stripped
before reaching `_patch`'s frame and the guard never fires → the matched `#patch` (`meta:"yes"`) is
dropped. Reproduces with NO disjunction (`/tmp/kue-patch4.cue`); confirmed identical on clean HEAD
`2ab5c84` (not a regression). → **Bug2-4** (transitive comprehension-read-splice) is the new
single argocd blocker.

Files: `Kue/Eval.lean` (`embedBodyEmbedsDisj`, `spliceOperandForEmbed`),
`Kue/Tests/TwoPassTests.lean`, `testdata/modules/disj_embed_struct_disc/`.

## Bug2-4 — let-LOCAL declare-and-read narrowing (2026-06-19, `3f7a761`)

**The bug (NOT a transitive read).** Bug2-1 already followed lets transitively
(`closeDefFrameReadIndices` is a fixpoint). The real argocd blocker is the shape where the read
sibling is DECLARED INSIDE the same let that buries the comprehension — `defs/parts.#Mixin`'s `let
_patch = { kind: string; for … { if kind == add.#kind {…} } }`. The guard's `kind` resolves to
`_patch`'s OWN frame, where `kind` is also declared, so NO embed-def index names it; a host narrowing
spliced at the def frame lands as a SIBLING the guard never reads, the comprehension fires against
`string`, and the matched patch drops. `kue export /tmp/kue-patch4.cue` → cue `{kind, meta}`, Kue
`{kind}` only.

**Fix — two helpers, both total (visited-set + structural fuel, cycle-safe) and sound (only meets the
host narrowing into a field the host narrows anyway — never invents a value, never over-splices; same
envelope as Bug2-1/Gap-1, which the Phase-A 13-probe over-splice hunt cleared):**
- `letPromotedReadLabels` (fixpoint over followed lets): the regular labels a let's OWN comprehension
  reads from its OWN frame — labels the let promotes to the embed on embedding, so the host's
  narrowing splices toward the def. Wired into `embedComprehensionReadLabels` via the shared
  `embedReadLabelsClosing` helper alongside the existing `closeDefFrameReadIndices` set.
- `injectLetLocalNarrowings` (in `forceClosureWithConjunctCore`'s `.structComp` arm): meets the
  use-operand's regular narrowings INTO any let-local that declares-and-reads the label, before the
  comprehension expands — matching cue's lazy promote-then-narrow.

**Verify.** `lake build` 100 jobs; `check-fixtures.sh` → `fixture pairs ok` (zero drift); shellcheck
clean; cert-manager (prod9, READ-ONLY) content-identical to cue v0.16.1 (`jq -S`, exit 0) — the gate
holds. 7 `native_decide` pins (label surfaced; unread not surfaced; cycle terminates; disj
end-to-end matched patch; real-conflict bottoms; guard-false drops) + fixture
`testdata/modules/mixin_let_local_narrowing`.

**argocd STILL bottoms — Bug2-5 (DISTINCT, pre-existing).** `kue export apps/argocd.cue` still
bottoms (~153s). Residual shape, faithfully reproduced (`/tmp/kue-ls-shape.cue`): `defaults.#ListenerSet
= defs.#ListenerSet & parts.#UseCertManager & {…}` — `defs.#ListenerSet` declares `kind:
"ListenerSet"` at ITS def frame and CO-EMBEDS `#UseCertManager` (→ `#Mixin`). The Mixin's
`_patch.kind` must be narrowed by the SIBLING def's `kind`, not by a use-operand. Because `#Mixin`'s
body is the `listShape | structShape | error` DISJUNCTION, the embed resolves on the `.disj` arm of
`meetEmbeddingsWithFuel` (each arm `meet`s the host AFTER the arm and `_patch`'s comprehension have
evaluated), so the narrowing arrives too late and `injectLetLocalNarrowings` (force `.structComp` arm
only) never runs. This narrowing-injection into a disjunction-arm-referenced let-local on the
eager/disj path is a deeper mechanism than read-label following — filed as Bug2-5. (CLI `kue export`
and the in-Lean `exportJsonMatches` harness take different embed paths for the same def-host source;
both correct, but the divergence is flagged for the architecture audit.)

Files: `Kue/Eval.lean` (`letPromotedReadLabels`, `injectLetLocalNarrowings`,
`embedComprehensionReadLabels`/`embedReadLabelsClosing`, `forceClosureWithConjunctCore`),
`Kue/Tests/TwoPassTests.lean`, `testdata/modules/mixin_let_local_narrowing/`.

## D#2a — structural-cycle DETECTION (2026-06-20)

**Spec-mandated, was MISSING.** The CUE spec requires dynamic detection of STRUCTURAL cycles —
a definition or field whose body re-enters the same struct through a struct layer
(`#L: {next: #L}`, mutual `#A`/`#B`) — as an error, DISTINCT from a bare REFERENCE cycle
(`x: x` → `_`). Before this slice Kue unrolled the cyclic body fuel-deep to a truncated
`{..., ...}` garbage tree (oracle #1/#2/#3); now the re-entry bottoms with `.structuralCycle`.

**The designed lever was WRONG as built — redesigned by first principles (recorded).** The
audit's D#2a design put an ancestor force-stack on `forceClosureWithConjunct`, keyed on the
fuel-free `ForceKey` triple `(envIds, body, useOperands)`, on the premise that `next: #L`
re-enters that force one fuel tier down with a REPEATING triple (frame-sharing canonicalizes
`envIds`). Instrumentation falsified both halves: (1) `#L` reaches `forceClosureWithConjunct`
exactly ONCE — the recursion unrolls inside `evalValueCoreWithFuel`'s `.refId` arm
(`refDefClosureBody?` returns `none` on every re-entry, so the force branch is never re-taken);
(2) the `.refId` re-eval allocates FRESH frame ids each level (`[1,0]`→`[2,0]`→`[2,1,0]`→…), so
`envIds` never repeats — no force-triple-based identity can ever fire. The force path is simply
not where the cycle recurses.

**Correct lever (struct-body re-entrancy on the `.refId` path).** A structural cycle is a struct
VALUE whose evaluation requires its own evaluation to complete — i.e. the SAME struct body
re-entered while still in progress. The stable identity is the body `Value` itself (frame ids are
not stable; the body is). Added `structStack : List Value` to `EvalState`; the `.refId` eval arm's
re-eval branches (depth-0-non-visited and depth>0), when the resolved `Field.value` is struct-like
(`isStructLikeBody`: `.struct`/`.structComp`), push the body before re-evaluating and RESTORE the
saved stack after (restore, not bare pop — a divergent inner return cannot leak a stale ancestor).
A body already on the stack at re-entry is the cycle → `.bottomWith [.structuralCycle]` instead of
unrolling. Identity is exact `Value` `BEq` (never a hash — a collision would be a false cycle).

**Why this is sound + total.** (a) Reference cycle preserved (`x: x` → `_`): a bare self-ref's
resolved body is a `.refId`, not struct-like → never pushed; the depth-0 `visited` slot check
handles it unchanged. The struct layer between re-entries is exactly what makes a cycle STRUCTURAL,
not referential. (b) No false-positive on finite-deep nesting (`#D: {a:{b:{c:{d}}}}`): each layer
is a DISTINCT body, pushed-then-popped; only genuine re-entrancy puts a body on the stack twice.
(c) List-tail recursion NOT flagged (`#L: {kids: [...#L]}`): an open list tail is a deferred
constraint yielding `[]` (the recursive-tree idiom), confirmed against cue — `isStructLikeBody`
excludes lists, and a concrete finite use (`x: #T & {v:1, kids:[{v:2}]}`) exports byte-identical to
cue. (d) Totality: the check is a `List.contains` guard before the existing same-fuel
`evalValueWithFuel` call (wrapped in a local closure), so the `termination_by` measure is unchanged;
fuel becomes a pure backstop, never the deciding bound for a cyclic program.

**Detection is class-AGNOSTIC (a correctness win beyond the audit's scope).** The lever keys on
struct-body re-entrancy, so a structural cycle through a REGULAR (non-definition) field
(`a: {n: int, next: a}`) is detected too — cue agrees (`a.next: structural cycle`). The audit's
oracle table only probed def cycles; the principled lever covers both for free.

**`BottomReason.structuralCycle`** (bare arm — `Value.lean`): a parameterless arm is the honest v1
(no def-label/path is cheaply available at the `.refId` re-eval site, and a never-populated path
field would be an illegal state). `isBottom`/`containsBottom`/`liveAlternatives` treat `.bottomWith`
generically, so the cycle bottom propagates through manifest (export bottoms) and will prune
correctly in D#2b. No exhaustive `BottomReason` consumer exists, so no new match site; Format and
Manifest render all bottoms uniformly (`_|_` / `.contradiction`).

**Value verdict CONFORMS to cue; eval-display differs (recorded in cue-spec-gaps).** Every oracle
probe matches cue's error-vs-terminated VALUE verdict (def #1, mutual #3 error; finite #4, ref #5,
list-tail terminate). The eval DISPLAY differs: cue prints `#L.next: structural cycle` with a source
span; Kue shows nested `next: _|_` (its standard nested-bottom convention — same family as the
"residual pattern in eval output" divergence). `export` bottoms on a clean cycle (`#L: {n: 1, next:
#L}` → `conflicting values (bottom)`), the observable verdict.

**Tests.** 8 `native_decide` pins in `EvalTests.lean` (`structural_cycle_self_ref_detected` via a new
`evalSourceDetectsStructuralCycle` helper that asserts the `.structuralCycle` REASON, not merely
"some bottom"; `_export_bottoms`; `_mutual_detected`; `_regular_field_detected`;
`reference_cycle_unchanged`; `constrained_reference_cycle_unchanged`; `finite_deep_struct_no_false_cycle`;
`recursive_list_tail_finite_use_exports` byte-identical to cue). New helpers in `EvalTestHelpers.lean`
(`valueHasStructuralCycle` fuel-bounded spine-walker + `evalSourceDetectsStructuralCycle`). 2 eval
fixtures `refs/structural_cycle_struct`, `refs/structural_cycle_mutual` (+ FixturePorts ports, the
`parseSource`-pipeline form per the `sc2a` precedent — the nested-bottom value is impractical to
hand-build).

**Verify.** `lake build` green (100 jobs); `check-fixtures.sh` → `fixture pairs ok` (zero drift on
the full corpus — the lever sits on the hot `.refId` path but changes nothing for non-cyclic
programs); no shell touched. prod9 (READ-ONLY): cert-manager content-identical to cue (`jq -S`, exit
0) — detection never false-fires on production infra (ZERO self-ref defs); argocd still its
pre-existing Bug2-5 `conflicting values (bottom)`, NOT a new structuralCycle (unchanged).

**Next — D#2b (terminating-disjunct).** `#List | *null` must take the `*null` arm once the cyclic
`#List` arm bottoms. The cyclic arm ALREADY bottoms with `.structuralCycle` (verified: `#List | *null`
eval shows `tail: {…} | *null` with the cyclic arm carrying `_|_`); D#2b must confirm
`liveAlternatives`/`resolveDisjDefault?` PRUNE that bottom arm and collapse `tail` to `null` (oracle
#2 — cue gives `tail: null`, Kue currently keeps `{…} | *null`). Check the A#6 `containsBottom` fuel
cap (100) does not hide a deep `.structuralCycle` bottom from `liveAlternatives`; raise or
special-case if it does.

Files: `Kue/Value.lean` (`BottomReason.structuralCycle`), `Kue/Eval.lean` (`isStructLikeBody`,
`EvalState.structStack`, the `.refId` re-eval cycle bracket), `Kue/Tests/EvalTestHelpers.lean`,
`Kue/Tests/EvalTests.lean`, `Kue/Tests/FixturePorts.lean`,
`testdata/cue/refs/structural_cycle_{struct,mutual}.{cue,expected}`.

## D#2b — terminating-disjunct (2026-06-20)

**Spec-mandated, the second half of D#2.** The CUE spec's "a node is valid if any of its
conjuncts is not cyclic" rule: a recursive def in a disjunction (`#List: {head, tail: #List |
*null}`) must TERMINATE by taking the non-cyclic arm once the cyclic arm bottoms. D#2a already
made the cyclic arm carry `.structuralCycle`; D#2b makes the disjunction algebra prune that
bottom arm so the surviving (default or sole) arm wins.

**Re-diagnosis vs the handoff — the gap was NARROWER than the audit framed it.** The audit/
breadcrumb said "Kue keeps the unresolved `{…} | *null`" as a value bug needing
`liveAlternatives`/`resolveDisjDefault?` to prune. Instrumentation (`kue export`/`eval` on the
oracle cases) refined this:
- **VALUE resolution was ALREADY correct after D#2a.** `kue export` gave `tail: null` for the
  canonical case via the EXISTING `resolveDisjDefault?` → `liveAlternatives` (which already
  filters `containsBottom` arms). The `.structuralCycle` arm was already pruned at manifest.
- **The A#6 `containsBottom` fuel cap (100) was NEVER implicated.** D#2a detects at recursion
  depth ~2 (the second struct-body re-entry), so the bottom sits ~2 struct-levels deep — far
  below 100. A wide-body probe (5 concrete fields) confirms the cap needs NO change. (A#6
  remains a standalone low/hardening item for genuinely-deep NON-cyclic bottoms; D#2b does not
  fold it in — there was nothing to fold.)
- **The residual gap was the EVAL value path** (`normalizeEvaluatedDisj`, the SC-3 root): on a
  non-all-regular (has-`*`) disjunction it emitted `.disj alternatives` RAW, so the
  `.structuralCycle` arm lingered in the eval value (`tail: _|_ | *null`) instead of being
  pruned. `export` resolved correctly only because the manifest path runs `resolveDisjDefault?`.

**The fix (one function, `Kue/Eval.lean` `normalizeEvaluatedDisj`).** The has-default branch now
applies `liveAlternatives` (flatten + drop-`containsBottom` + dedup) instead of emitting raw:
a `[]`→`.bottom`, a lone surviving arm→its value (mark-agnostic), multi-arm→`.disj live` with
marks PRESERVED. This prunes the dead `.structuralCycle` arm from the eval value and folds in
**SC-3** (`*1 | *1 | 2` eval now `*1 | 2`, deduped). The all-regular branch (`joinValues`, the
lattice union which already sheds top-level `.bottom`) is unchanged.

**Soundness — why this does NOT collapse the default into the value (the load-bearing decision).**
cue's `eval` shows `a: 1` for `*1 | 2` but `b: 2` for `b: a & 2` — proving cue's default-collapse
is a DISPLAY projection, not a value rewrite: the live `2` arm is still there for the meet.
Collapsing `*1 | 2` to the value `1` in `normalizeEvaluatedDisj` would make `b: a & 2 = 1 & 2 =
_|_`, diverging from cue's `2`. So `normalizeEvaluatedDisj` NEVER collapses a multi-live-arm
defaulted disjunction — it only (a) prunes `containsBottom` arms (a dead arm is dead in every
meet, so removing it is value-preserving) and (b) collapses a SOLE surviving arm (the only
inhabited value). Default *selection* stays a manifest/force projection via `resolveDisjDefault?`.

**Eval-display divergence (recorded, NOT a value bug).** Because Kue does not collapse the
default into the value, its `eval` shows the full `{…} | *null` (and `*1 | 2`), where cue's `eval`
display-collapses to `null` (and `1`). This is the SAME established Kue convention as
`disjunctions/default_disjunction.expected` (Kue `*"prod" | "dev"` vs cue `"prod"`) — eval shows
the marked disjunction, the VALUE verdict (`export`) matches cue. Recorded in `cue-spec-gaps.md`
(new D#2b/SC-3 row). The full cue-style display-collapse (a Format-layer projection) would
require rewriting ~7 existing `.expected` fixtures and is a settled-against convention — out of
scope; the residual cosmetic piece stays under SC-3.

**Tests.** 8 `native_decide` pins in `EvalTests.lean`: `terminating_disj_default_arm` (oracle #2,
byte-identical export `tail: null`); `_nonnull_default_arm` (`#Tree | *{v:0}` → `child: {v:0}`);
`_cyclic_arm_nondefault` (`*null | #List`, order-independent); `_no_survivor_bottoms` (all-cyclic
`#A | #B` → export bottoms); `_wide_body_pruned` (A#6 fuel-cap probe, wide cyclic body still
shallow-detected, cue-exact); `_default_arm_stays_meetable` (soundness — the live default struct
survives `r.child & {v:9}` → `{v:9, child:{v:0}}`, NOT collapsed); `sc3_eval_dedups_equal_defaults`
(`*1|*1|2` eval → `*1 | 2`); `sc3_default_not_collapsed_into_value` (`a: *1|2; b: a&2` → `b: 2`,
the load-bearing soundness regression). 3 byte-identical-to-cue export fixtures
`testdata/export/terminating_disj_{default,nonnull_default,cyclic_nondefault}.{cue,json}`. Updated
`disjunctions/default_dedup.expected` + its `FixturePorts` eval port to the deduped `*1 | 2` form
(the manifest port stays `x: 1`).

**Verify.** `lake build` green (100 jobs); `check-fixtures.sh` → `fixture pairs ok` (zero drift on
the full corpus — only the intended `default_dedup` eval form changed, port + expected updated in
lockstep; 3 new export pairs added); no shell touched. Axiom-clean (`normalizeEvaluatedDisj` =
`{propext, Classical.choice, Quot.sound}`, `liveAlternatives`/`resolveDisjDefault?` = `{propext}`;
no `sorryAx`/`partial`). prod9 (READ-ONLY, run from the infra module root): cert-manager
content-identical to cue (`jq -S`, both exit 0, 1448 bytes) — the disjunction hot-path change does
NOT regress production infra; argocd still its pre-existing Bug2-5 (unchanged, parked).

**D#2 (structural cycles) is now COMPLETE** — detection (D#2a) + terminating-disjunct (D#2b).

**Next — RX-2a** (`\D`/`\W`/`\S` inside a `[…]` char class, the lone regex-corpus divergence;
needs class-level set-complement in `parseClassEscape`), then the MED tail (D#1b/c, D#3, SC-3
residual display, BI-1/2, F-3).

Files: `Kue/Eval.lean` (`normalizeEvaluatedDisj`), `Kue/Tests/EvalTests.lean`,
`Kue/Tests/FixturePorts.lean`, `docs/reference/cue-spec-gaps.md`,
`testdata/cue/disjunctions/default_dedup.expected`,
`testdata/export/terminating_disj_{default,nonnull_default,cyclic_nondefault}.{cue,json}`.

---

## Completed Slice: RX-2a — negated shorthand classes inside `[…]` (set-complement fold) (2026-06-20)

Goal: the lone remaining regex-corpus divergence — `\D`/`\W`/`\S` (negated perl shorthands)
INSIDE a `[…]` character class. They were honest stubs (`parseClassEscape` returned
`.unsupportedRegex "\\D inside character class"`); RE2 (the CUE-mandated regex syntax) folds
each as its full COMPLEMENT set into the class union. `[\D]` = non-digits, `[\D5]` = non-digits
∪ {5}, `[\d\D]` = every char, `[^\D]` = digits (whole-class negation applied AFTER the member
folds). `\D\W\S` OUTSIDE a class already worked (`parseAtomEscape` — single positive range +
the whole-atom `negated` flag); this slice closes only the in-class case.

**The representation decision (first-principles).** Took the MINIMAL, most-precise route: NO new
AST constructor and NO "signed member" type. `Regex.cls (ranges) (negated)` — a union of
code-point ranges, optionally whole-negated — is ALREADY the precise, total,
illegal-states-unrepresentable representation; the only defect was that `parseClassEscape` gave
up instead of computing the complement. A negated shorthand folds to the **set-complement of its
positive ranges over the whole `Char` domain `[0, U+10FFFF]`**, which is itself a union of ranges,
so it composes with other class members through the ordinary range union and is then flipped by
the existing whole-class `negated` flag for `[^…]`. This adds ZERO new states (the alternative
signed-member representation would have ADDED an ambiguous "negated member inside a maybe-negated
class" state — strictly worse on the illegal-states axis). Everything downstream
(`Inst.char`/`classMatches`, `compileFrag`) is untouched.

**New helper `Regex.complementRanges : List (Char × Char) → List (Char × Char)`** (+ `maxCodePoint
:= 0x10FFFF`). Total: `mergeSort` the ranges by lower bound (in `Nat`), fold once emitting the gap
before each covered span (a nested/overlapping range advances the cursor by `Nat.max`, so a gap is
never inverted), then the tail gap up to `maxCodePoint`; rebuild endpoints with `Char.ofNat`. The
ASCII perl sets put every gap boundary on a valid scalar — the only complement range crossing the
surrogate hole `[U+D800, U+DFFF]` is the upper `[hi+1, U+10FFFF]` whose endpoints are valid, and
no input `Char` is ever a surrogate, so spanning the hole is harmless (`Char.ofNat` clamps invalid
inputs to `\x00`, but no boundary here lands on one). `parseClassEscape`'s three `.error` arms
become `.ok (complementRanges digitRanges, rest)` etc.

**Spec authority + oracle.** RE2 semantics are spec-mandated and UNAMBIGUOUS for this construct, so
this is CONFORMS (spec speaks; Kue matches it AND `cue` v0.16.1 matches) — NO cue-divergence and NO
spec-gap to record. Every behavior was first derived from RE2 (ASCII-only shorthands; `\D` covers
below `'0'`, above `'9'`, and all non-ASCII incl. `\n`; `\S` excludes `\n`), then cross-checked
read-only against `cue` (all 25 probes agreed: `[\D]` vs `a`=T/`5`=F/space=T/`\n`=T; `[\D5]` vs
`7`=F; `[^\D]` vs `5`=T/`a`=F; `[\W]` vs `é`=T but `[\w]` vs `é`=F).

**Tests.** 26 `native_decide` pins in `RegexTests.lean` (new RX-2a section): each of
`[\D]`/`[\W]`/`[\S]` matching + non-matching a representative char, the below-`'0'`/`\n`/non-ASCII
edges, union `[\D5]`/`[a\W]` (incl. the `7`-rejected and `b`-rejected discriminators), everything
`[\d\D]`, whole-class-over-negated-member `[^\D]` (both polarities), positive-`[\d]` regression
guards, an AST-shape pin (`[\D]` → the two complement ranges with `negated = false`), and a
`regexParseError? "[\D5]" = none` (no longer deferred). Plus the end-to-end `=~`/`!~` fixture
`testdata/cue/numeric/regex_in_class_negated.{cue,expected}` (11 fields incl. one `!~`) with its
`FixturePorts` entry — byte-identical to `cue export`.

**Verify.** `lake build` green (100 jobs; all pins checked at build time); `check-fixtures.sh` →
`fixture pairs ok` (zero drift on the full corpus; one new fixture pair added); no shell touched
(shellcheck clean on `check-fixtures.sh`). Leaf module, no `Value`/`Eval` import — no eval-cost
change, perf guide untouched.

**The regex corpus is now divergence-free.** Remaining regex work: none on the RX backlog (RX-1
trilogy + RX-2a/b/c all DONE).

**Next — the MED tail** (D#1b/c incomplete/non-bool guard, D#3 `let`-clauses, SC-3 residual
display, BI-1 Unicode case-fold, BI-2 `math.Pow`/`list.Sort`, F-3 qualified import), then SC-4
(LOW, spec-gap-first), the spec-gap ratifications, A#6, DRY-1. ⚠ A two-phase audit is DUE
(D#2a + D#2b + RX-2a = 3 landed since the last audit).

Files: `Kue/Regex.lean` (`complementRanges`, `maxCodePoint`, `parseClassEscape`),
`Kue/Tests/RegexTests.lean`, `Kue/Tests/FixturePorts.lean`,
`testdata/cue/numeric/regex_in_class_negated.{cue,expected}`.

---

## Completed Slice: D#1b + D#1c — comprehension-guard classification (defer / type-error) (2026-06-20)

Goal: the comprehension `if <guard> {…}` clause classified guards too coarsely. D#1a had split
out `true`→expand / `false`→drop / bottom→propagate, but everything else fell into a residual
`_ => pure (.ok [])` arm that WRONGLY swallowed two distinct cases to empty: a CONCRETE non-bool
guard (a type error per spec) and an INCOMPLETE guard (which must defer). This slice splits that
arm, exhaustively, with no catch-all.

**The classifier — an explicit sum type (illegal-states).** Introduced `GuardVerdict`
(`concreteTrue` / `concreteFalse` / `bottom Value` / `nonBool NonBoolGuardType` / `incomplete`)
and a total `classifyGuard : Value → GuardVerdict` that **enumerates EVERY `Value` constructor**
(no `_`), so a future arm forces a decision. The guard match (struct twin `expandClausesWithFuel`
+ list twin `expandListClausesWithFuel`) now reads `classifyGuard` and routes each verdict; the
two twins share the one classifier (DRY — they previously duplicated the bool match).

**D#1c — concrete non-bool → TYPE ERROR.** A fully-concrete present value of non-`bool` type
(`if "x"`, `if 3`, `if {…}`, `if [..]`, `if null`) is a `.bottomWith [.nonBoolGuard ty]` that
PROPAGATES (cue: `cannot use … as type bool`). New `BottomReason.nonBoolGuard (type :
NonBoolGuardType)` + a precise `NonBoolGuardType` (`scalar (kind : Kind)` / `struct` / `list` —
`Kind` has no struct/list arm, so they get their own; carries the offending type for provenance).
CONFORMS — cue+Kue agree both modes.

**D#1b — incomplete → DEFER.** A genuinely-abstract guard (a `.kind`, bound, unresolved
disjunction — even all-bool `true | false` — or a NON-presence comparison `x > 5`) cannot be
decided, so the comprehension is kept RESIDUAL rather than dropped. The result protocol gained a
third outcome (the repo's "sum type over the two-channel `Except`"): `ClauseExpansion`
(`fields`/`bottom`/`deferred`) + the list analogue `ListClauseExpansion`. `deferred` is nullary —
the outermost caller (`.comprehension` arm, `.structComp` eager+force arms via the new
`expandComprehensionsWithFuel : … → (List Field × List Value)` accumulator, list-item arm) re-emits
the ORIGINAL node it still holds. New helper `withDeferredComprehensions` re-wraps a resolved
`.struct` carrying deferred comprehensions back into a `.structComp` (embeddings already meet in;
they never defer — `isEmbeddingValue` excludes `if`/`for`). Whole-comprehension deferral, not
per-iteration (cue holds the entire `for … if y {…}`, confirmed): a `for`-pairs walk short-circuits
on the first `.deferred` like it does on `.bottom`.

**The presence-test carve-out (the subtle part).** A residual presence test `X != _|_` / `X == _|_`
(the shape `evalPresenceTest` emits for an incomplete operand — `if base.g != _|_` with `g` absent,
or `if y != _|_` with abstract `y`) is NOT a defer: cue eval DROPS it (`out: {}`), and the existing
`classifyDefinedness` design already (correctly) treats it as not-satisfied. So `classifyGuard`
routes the `eq`/`ne`-against-`.bottom` shape to `.concreteFalse` (drop), preserving pre-D#1b
behavior; every OTHER `.binary` (e.g. `x > 5`) defers. This was found by regression: an early
attempt deferred presence tests too, breaking `PresenceTests`/`TwoPassTests`. Confirmed against
`cue` eval across 7 boundary probes (`if x` bool/disj/`x>5` HOLD; `if y!=_|_`/`if base.g!=_|_` DROP;
`if y!=_|_` y=3 admit; `if y==_|_` y:int admit). An earlier exploration also tried fixing
absent-field selection (`selectEvaluatedField` → bottom) upstream; REVERTED — it leaked unresolved
`@d.i` refids and bottomed def bodies (`#R: _|_`), far too broad. The presence-test carve-out is the
correctly-scoped fix.

**Mode behavior (Kue is finalizing-eval-style).** `kue` (default, eval-style — it HOLDS incompletes
like a held `x: int`) shows the held comprehension; `kue export` surfaces it as an incompleteness
(`incomplete value: bool`, via `Manifest`'s pre-existing `.comprehension → incomplete` arm) — both
matching cue's eval/export split. A non-bool guard bottoms in BOTH modes.

**Spec authority.** D#1c CONFORMS (spec: the `if` guard must be `bool`; cue+Kue agree — no
divergence/gap). D#1b: the spec is silent on the DEFER mechanism for an incomplete guard (a
finalization-mode choice); recorded in `cue-spec-gaps.md` (Kue defers/holds in eval, errors in
export — both match cue's value verdict). The held residual renders the guard ref as `@d.i` (Kue's
`BindingId` resolution has no source name to print) where cue prints the name — a display-only
divergence recorded in `cue-divergences.md`, same family as the residual-pattern and D#2a/b rows.

**Bug-replicating tests corrected.** Three existing pins asserted the OLD wrong DROP and were
updated to the spec-correct HELD form (cue agrees): `EvalTests.eval_comprehension_guard_non_default_disj_drops`
→ `…_defers` (the `x: true|false` guard); `EvalPerfTests.fix0_{open,closed}_def_embed_comp_*` (the
`if port > 0` def-body comprehension now held standalone, force-resolved at the use site — `out`
unchanged). `PresenceTests.guard_drops_on_absent` and the two `TwoPassTests.listcomp_embed_*` now
pass via the presence-test carve-out (no edit needed).

**Tests.** New `PresenceTests` block: 12 `classify_guard_*` unit pins (concrete bool, the 5 D#1c
non-bool types with their `NonBoolGuardType`, the 3 D#1b abstract defers, both presence-test
polarities) + 5 end-to-end pins (D#1c struct/list bottoms, D#1b held-residual value, D#1b
not-dropped). 4 fixture pairs + `FixturePorts` entries: `comprehensions/{guard_nonbool_string,
guard_nonbool_int,list_guard_nonbool,guard_incomplete_defers}`. (`GuardVerdict` derives `BEq` not
`DecidableEq` — its `.bottom` arm carries a `Value` — so unit pins assert via `==`, the `Value`
convention.)

**Verify.** `lake build` green (100 jobs; all pins checked at build); `check-fixtures.sh` →
`fixture pairs ok` (zero drift; 4 new pairs); shellcheck clean (no shell touched). cert-manager
export content-identical to `cue` (modulo the standing field-order divergence) — the eval-hot-path
change (a new bottom arm + a residual-emit, no deletion) does not regress real-app output. prod9
has no incomplete-guard def shape that reaches the new defer path.

**Next — the MED tail continues:** D#3 (`let`-clauses in comprehensions), then BI-1 (Unicode
case-fold) / BI-2 (`math.Pow`/`list.Sort`) / F-3 (qualified import); SC-3 display-residual
(LOW/spec-gap), SC-4, the spec-gap ratifications, A#6, DRY-1. ⚠ Audit cadence: RX-2a + D#1b/c = 2
slices since the last two-phase audit — ONE more slice, then Phase A→B is due.

Files: `Kue/Value.lean` (`NonBoolGuardType`, `BottomReason.nonBoolGuard`), `Kue/Eval.lean`
(`GuardVerdict`/`classifyGuard`, `ClauseExpansion`/`ListClauseExpansion`,
`withDeferredComprehensions`, the two clause-walkers + `expandComprehensions/WithFuel` +
4 caller arms), `Kue/Tests/PresenceTests.lean`, `Kue/Tests/EvalTests.lean`,
`Kue/Tests/EvalPerfTests.lean`, `Kue/Tests/FixturePorts.lean`,
`testdata/cue/comprehensions/{guard_nonbool_string,guard_nonbool_int,list_guard_nonbool,guard_incomplete_defers}.{cue,expected}`,
`docs/reference/cue-divergences.md`, `docs/reference/cue-spec-gaps.md`.

## Completed Slice: D#3 — `let` clauses in comprehensions (2026-06-20)

Goal: make `let <ident> = <expr>` parseable and correctly scoped as a comprehension clause. It
was the **last open D-area item** — previously UNPARSEABLE. CUE allows `let` clauses interleaved
with `for`/`if` in a comprehension's clause chain, binding a name in the comprehension's scope for
subsequent clauses and the body:

```cue
out: [for x in [1, 2, 3] let y = x*2 {a: y}]   // → [{a: 2}, {a: 4}, {a: 6}]
```

**Spec basis (authoritative — the gate).** The CUE spec grammar: `Clauses = StartClause { [ "," ]
Clause }`, `StartClause = ForClause | GuardClause`, `Clause = StartClause | LetClause`,
`LetClause = "let" identifier "=" Expression`. Two mandates fall out: (1) a `let` clause is a
non-start `Clause` — a comprehension CANNOT start with `let` (so a struct-field-head `let` stays a
struct-body `let`, never a comprehension); (2) scope: *"The `for` and `let` clauses each define a
new scope in which new values are bound to be available for the next clause."* This is the spec
basis for the frame model: **`let` = +1 frame** (joins `for`; `if`/`guard` = +0, B7-vindicated).

**AST.** `Clause.letClause (name : String) (value : Value)` added to the comprehension clause sum
type (now 3 arms, total, no catch-all). Each `let` clause binds exactly one name to one expr —
illegal-states-unrepresentable.

**Frame accounting (the subtle part) — routed through the single authority.** `descendClauses`
(`Value.lean`, the sole place the per-clause frame-shift rule lives) gained a `.letClause` arm
that hands the bound value to `onSource` and pushes +1 — a `for` source and a `let` value are the
SAME shape to every walker (a `Value` read at the pre-push depth that then pushes one frame). This
single addition makes `clauseChainDepth` and all four `descendClauses`-based walkers
(`refsSelfEmbeddedLabelClauses`, `selfReferencedLabelsClauses`, `defFrameRefIndicesClauses`,
`hasSelfRefAtDepthClauses`) handle `let` for free — the `+1`-per-frame rule cannot be re-derived
inconsistently. `Resolve.resolveClausesWithFuel` resolves the let value in the pre-push `scopes`
(symmetric with the `for` source), then pushes `clauseLoopFrame none name` = `[(name, 0)]`; a
`.refId ⟨0,0⟩` from a later clause/body lands on it. The subtle case — a `for` AFTER a `let`
(`letcomp_for_after_let`) — resolves earlier bindings correctly across the intervening let frame
(verified `[{v:11},{v:12},{v:12},{v:13}]`, cue-exact).

**Eval — bind into a frame like a `for` element (eager-into-frame).** `expandClausesWithFuel` /
`expandListClausesWithFuel` gained a `.letClause` arm: evaluate the value in the pre-push `env`
(its resolve-time scope), then `pushFrame [⟨name, .regular, evaluatedValue⟩]` (a one-slot frame,
the eval analogue of `Resolve`'s `clauseLoopFrame none name`) and recurse the rest of the chain +
body. Binding the EVALUATED value (not the raw expr) keeps the frame's refs
aligned exactly as `loopFrame` does for a `for` element — an evaluated value carries no residual
refIds to misalign. An UNREFERENCED binding's value sits unread in the frame, so a bottom it would
carry never propagates unless the body selects it (the `.refId`-on-select path is the only force).
This matches cue for a value-level bottom (`let bad = div(1,0)` unused → no error; referenced →
division-by-zero error). All 8 clause-match sites updated with an explicit `.letClause` arm (no
catch-all): `descendClauses`, `resolveClausesWithFuel`, `remapConjClauses`,
`expandClausesWithFuel`, `expandListClausesWithFuel`, `formatClauseWithFuel`,
`normalizeClauseWithFuel`, `normalizeDefinitionsClauseWithFuel`.

**Parse.** New `parseLetClause` (`let <ident> = <expr>` → `.letClause`, `dropWord?`-bounded so it
never misfires on `letterbox`), wired into `parseClause` AFTER `for`/`if`. Reached only from a
clause chain (`parseComprehension`/list-comprehension head + `parseComprehensionClauses`
continuation), so a struct-field-head `let` still parses as a struct-body binding (`parseLetBinding`)
— honoring the spec's `StartClause` exclusion. The comprehension head dispatch (`startsWithWord
"for"/"if"`) stays unchanged (a `let` cannot start a comprehension).

**Divergences / spec gaps recorded.** `cue-divergences.md` (D#3 row): an UNREFERENCED `let` whose
value is an unresolved REFERENCE (`let unused = someUndef`, never read) — cue ERRORS, Kue tolerates
(a dead binding contributes nothing — lattice-correct; the referenced case errors in both); self-ref
`let y = y` resolves as a reference cycle (`_`) under Kue, cue errors. `cue-spec-gaps.md` (D#3 row):
the eval-order basis — the spec fixes `let`'s SCOPE but is silent on WHEN the value evaluates;
eager-into-frame reuses the proven `for`-element machinery and matches cue for the value-level-bottom
unreferenced case.

**Tests.** 9 `native_decide` pins in `EvalTests` (`letcomp_basic`, `letcomp_in_guard`,
`letcomp_multiple`, `letcomp_for_after_let` [frame accounting], `letcomp_shadows_outer`,
`letcomp_struct_form`, `letcomp_referenced_bottom_propagates`, `letcomp_unreferenced_bottom_drops`,
`letcomp_let_not_start_clause`), each cue v0.16.1-cross-checked, driven through the full
parse→resolve→eval→format chain via `evalSourceMatches`. 6 fixture pairs + `FixturePorts` entries:
`comprehensions/{list_let_basic, list_let_in_guard, list_let_multiple, list_let_for_after,
let_shadows_outer, struct_let_basic}` (covering list + struct comprehension forms; the
FixturePorts entries hand-build the `Value` with `.letClause` and must format-match the CLI parse).

**Verify.** `lake build` green (100 jobs; all pins checked at build, no non-exhaustive-match
warning ⇒ every clause site is exhaustive); `check-fixtures.sh` → `fixture pairs ok` (zero drift;
6 new pairs); shellcheck clean (no shell touched). cert-manager `export` CONTENT-IDENTICAL to `cue`
(sorted-key compare) — the eval-hot-path change is additive (`let` clauses fire only on actual `let`
clauses, which cert-manager has none of) so it cannot regress real-app output.

**The D-area is now CLOSED** (comprehensions/scoping: guards drained D#1a/b/c, structural cycles
D#2a/b, `let`-clauses D#3). **Next leader — the MED tail:** BI-1 (Unicode case-fold for
`strings.ToUpper/ToLower`), BI-2 (`math.Pow/Sqrt`, `list.Sort/SortStable`), F-3 (qualified import
path `"location:identifier"`); then SC-3 display-residual (LOW/spec-gap), SC-4, the spec-gap
ratifications, A#6, DRY-1. ⚠ **Audit cadence: RX-2a + D#1b/c + D#3 = 3 slices since the last
two-phase audit (`c03ebdb`) — the two-phase audit (Phase A → Phase B) is now DUE.**

Files: `Kue/Value.lean` (`Clause.letClause`, `descendClauses` `.letClause` arm), `Kue/Parse.lean`
(`parseLetClause` + `parseClause` wiring), `Kue/Resolve.lean` (`resolveClausesWithFuel` arm),
`Kue/Eval.lean` (`remapConjClauses` + `expandClausesWithFuel` + `expandListClausesWithFuel` arms),
`Kue/Normalize.lean` (two clause arms), `Kue/Format.lean` (`formatClauseWithFuel` arm),
`Kue/Tests/EvalTests.lean` (9 pins), `Kue/Tests/FixturePorts.lean` (6 entries),
`testdata/cue/comprehensions/{list_let_basic,list_let_in_guard,list_let_multiple,list_let_for_after,let_shadows_outer,struct_let_basic}.{cue,expected}`,
`docs/reference/cue-divergences.md`, `docs/reference/cue-spec-gaps.md`.

---

## Completed Slice: BI-2 — math.Pow exact domain + list.Sort / list.SortStable

Goal: implement four builtins that previously BOTTOMED on concrete input — `math.Pow`,
`math.Sqrt`, `list.Sort`, `list.SortStable`. Landed as a SPLIT (`math.Pow` exact-domain +
`list.Sort`/`SortStable` fully; `math.Sqrt` + the apd-Pow tail deferred as a residual fix-slice).

**Precision investigation (the design fork).** The slice premise — "cue's math mirrors Go float64"
— is FALSE for Pow. Oracle (cue v0.16.1): `math.Pow` uses an apd DECIMAL context (34 sig digits):
`Pow(2, 0.5) = 1.414213562373095048801688724209698`, `Pow(3, -1) = 0.3333…3333` (padded);
`math.Sqrt` uses IEEE-754 FLOAT64: `Sqrt(2) = 1.4142135623730951` (= Python `math.sqrt(2)`), and Go
float formatting incl. scientific notation (`Sqrt(100) = 1e+1`, `Sqrt(1000000) = 1e+3`), with
`Sqrt(-1) = NaN.0`, `Sqrt(0) = 0.0`. Kue's numeric core is EXACT base-10 rationals (`DecimalValue` =
numerator/scale) — NO `Float`, no `NaN`/`Infinity`, no scientific-notation formatter. So the
prompt's "decimal↔Float bridge" does not exist and building it for Sqrt would be a large numeric +
formatting subproject that also produces values colliding with Kue's exact-decimal renderer.

**`math.Pow` — the SOUND exact sub-domain (`Builtin.lean`).** A POSITIVE-INTEGER exponent (incl. a
whole-valued float like `3.0`, since cue's `Pow(3, 2.0) = 9`) keeps the result a finite base-10
rational — exactly representable. `mathPow?`/`decimalPowNat` compute it by repeated exact
`mulDecimalValues` (numerators multiply, scales add), collapsing integral results to int via
`collapseDecimalToValue`. Byte-identical to cue across the whole domain: `Pow(2,10)=1024`,
`Pow(1.5,3)=3.375`, `Pow(-2,3)=-8`, `Pow(2.5,4)=39.0625`, `Pow(0.1,2)=0.01` (UNPADDED — the
positive-int-exp path never routes through cue's apd division), `Pow(10,20)`=exact 21-digit int.
`Pow(0,0)` bottoms — CONFORMS (cue errors `invalid operation`). The exponent's wholeness is decided
by trimming trailing zeros (`trimDecimalZerosWith` reduces `3.0`→scale 0; a residual non-zero scale
is a genuine fraction). Outside this domain (`mathPow? ⇒ none`) the call falls through to bottom — an
honest "not computed", NEVER a wrong value (the grant: never ship a wrong value).

**`list.Sort` / `list.SortStable` — comparator evaluation at the EVAL layer (`Eval.lean`,
`Parse.lean`).** cue's comparator is a `{x, y, less}` struct (`list.Ascending` =
`{T,x,y: number|string, less: bool & x < y}`); deciding `a < b` MEETS the comparator with `{x:a, y:b}`
and EVALUATES its `less` field to a bool — an effectful comparison the pure `Builtin` layer CANNOT do
(layering `Builtin → Lattice`, never `→ Eval`). So `list.Sort`/`SortStable` are intercepted in the
`.builtinCall` arm of `evalValueCoreWithFuel`, NOT in `evalBuiltinCall`. The comparator is passed
UNEVALUATED — `less`'s references to the `x`/`y` slots must survive into the per-pair meet (an
evaluated comparator collapses `less` to a residual `_ < _` with the slot links lost). Per pair, the
comparator evaluates `.selector (.conj [cmp, {x: a, y: b}]) "less"` and reads a `.prim (.bool _)`; a
`less` that does not reduce to a concrete bool (incomplete/incomparable comparator — a cue error) is
recorded in the eval-scoped `EvalState.sortError` and surfaced as the call's bottom. The sort itself
is a total, stable, fuel-bounded monadic merge sort (`sortValuesM` + `mergeRunsM`/`mergePassM`/
`mergeRunsLoopM`) — bottom-up, structurally total, parameterized by `Value → Value → EvalM Bool`, so
it lives OUTSIDE the eval mutual block and the comparator closure supplies the only recursive call
back into `evalValueWithFuel fuel` (a valid `(fuel,1,0) < (fuel,6,0)` decrease). ONE stable sort
serves both `Sort` and `SortStable` (a stable result is a valid `Sort` result; stability is the
strictly-stronger, illegal-states-fewer choice). The predefined comparator VALUES
`list.Ascending`/`Descending`/`Comparer` (which appear WITHOUT a call, so the parser cannot route
them through `parseCall`) are emitted by a new `stdlibPackageValue?` as the same inline `{x,y,less}`
AST a user would write, wired into `parseSelectorRest`'s no-call selector branch — so resolution and
the per-pair eval treat them identically to a hand-written comparator. The `bool &` is dropped from
the emitted `less` (`x < y` already yields bool, and Kue's `meet(bool)(unresolved <)` eagerly
bottoms — a pre-existing unrelated divergence that would corrupt the standalone display; the sort is
unaffected since a concrete pair makes `x < y` a real bool).

**RESIDUAL fix-slice filed (see `plan.md`/this audit's backlog — `BI-2-residual`):** `math.Sqrt`
(needs Float + `NaN`/`Infinity` + Go scientific-notation float formatting) and `math.Pow` with a
negative/fractional exponent or `Pow(0, neg)=Infinity` (needs an apd-equivalent 34-sig-digit decimal
Pow + Infinity model). Both DEFERRED rather than shipped wrong; Kue bottoms on these inputs today.

**Divergences / spec gaps recorded.** `cue-spec-gaps.md`: (BI-2 Pow row) the precision model — cue's
apd-decimal Pow / float64 Sqrt are library artifacts the spec does not pin; Kue computes the exact
positive-int-exp domain (byte-identical) and defers the rest. (BI-2 Sort row) Sort STABILITY — the
spec leaves tie order unspecified (cue docs: `Sort` "not guaranteed stable"); Kue uses one stable
sort for both, matching cue's observable order; plus the standalone comparator-value `less` display
(Kue `number|string < number|string` vs cue `bool & x < y`, display-only — the sort RESULT is
byte-identical). No `cue-divergences.md` entry — every Pow/Sort RESULT conforms to cue.

**Tests.** Pow: 13 `native_decide` pins in `BuiltinTests` (`math_pow_*` — integer/zero/base-zero/
float-base/neg-base odd+even/whole-float-exp/terminating-decimal exact cases; `Pow(0,0)` bottom;
negative- + fractional-exponent residual bottoms; abstract-arg unresolved). Sort: 13 `native_decide`
pins in `EvalTests` (`eval_list_sort_*` + `eval_list_ascending_*` — ascending/descending/already-
sorted/empty/single/duplicates/strings/inline-comparator/by-field; `SortStable` tie-stability with a
discriminating fixture; incomparable→bottom; standalone comparator-value display), each driven
end-to-end (parse→resolve→eval) via `evalSourceMatches` and cue v0.16.1-cross-checked. 2 fixture
pairs + `FixturePorts` entries: `builtins/math_pow` (11 cases) and `builtins/list_sort` (12 cases,
incl. `list.Ascending`/`Descending`, inline + by-field comparators, SortStable stability) — the
`list_sort` port reuses `stdlibPackageValue?` to build `list.Ascending`/`Descending` (DRY).

**Verify.** `lake build` green (100 jobs; all pins checked at build; no non-exhaustive-match
warning); `check-fixtures.sh` → `fixture pairs ok` (zero drift; 2 new pairs, both CLI + Lean-port
paths); shellcheck clean (no shell touched). Eval-hot-path change is additive (Sort interception
fires only on `list.Sort`/`SortStable`; cert-manager/argocd use neither) so it cannot regress
real-app output.

**Next leader — F-3** (parse qualified import path `"location:identifier"`). NOTE: **BI-1**
(Unicode case-fold for `strings.ToUpper/ToLower`) is REORDERED to AFTER F-3 — it likely needs Unicode
case-mapping tables (a data dependency / possible network fetch = an envelope risk), so BI-1's slice
must FIRST decide the data approach (vendored generated table vs scoped coverage) before any code.

Files: `Kue/Builtin.lean` (`decimalPowNat`, `mathPow?`, `evalMathBuiltin` `math.Pow` arm),
`Kue/Eval.lean` (`EvalState.sortError`; `mergeRunsM`/`mergePassM`/`mergeRunsLoopM`/`sortValuesM`;
`sortWithComparator` in the mutual block; `list.Sort`/`SortStable` interception in the `.builtinCall`
eval arm), `Kue/Parse.lean` (`stdlibPackageValue?` + `parseSelectorRest` no-call selector branch),
`Kue/Tests/BuiltinTests.lean` (13 Pow pins), `Kue/Tests/EvalTests.lean` (13 Sort pins),
`Kue/Tests/FixturePorts.lean` (2 entries),
`testdata/cue/builtins/{math_pow,list_sort}.{cue,expected}`, `docs/reference/cue-spec-gaps.md`.

## Completed Slice: F-3 — parse qualified import path `"location:identifier"` (2026-06-20)

Goal: make the CUE import-path package qualifier parse. Per the spec grammar
`ImportPath = '"' ImportLocation [ ":" identifier ] '"'`, the `:identifier` qualifier lives
INSIDE the quoted string and names the package within the location (defaulting the local
binding name). Kue previously read the whole quoted string into `Import.path` verbatim, so the
unstripped `:id` polluted every downstream path consumer — directory resolution failed with
`package directory not found: …/lib/math-utils:math`, the dash-dir case the qualifier exists to
serve. The bug was latent (no real-app import uses the qualifier), but it is a KUE-VIOLATES per
the F-area audit.

**Modeling (illegal-states-unrepresentable).** Split the qualifier out of the location at parse
time. `Import.path` becomes the LOCATION only (suffix stripped), and a new field
`packageName : Option String` carries the EXPLICIT qualifier (`none` = "default the package name
to the last path element"). This keeps `path` directly usable by every existing consumer
(`isBuiltinImport`, `resolveImportTarget`, `resolveImportSubpath`, `lastPathElement`) unchanged —
they all want the location — while making the explicit-vs-defaulted distinction representable.
The defaulting itself stays a single function over the location in `importBindName`. (The
alternative — a dedicated explicit/defaulted sum — was rejected: the defaulted value IS the last
path element, already derivable; an `Option` qualifier plus the existing `path` is the minimal
precise shape with no redundant stored state.)

**Parse (`Kue/Parse.lean`).** New `splitImportPath` splits the parsed string on `:` (an
ImportLocation may not itself contain `:` — it is in the spec's excluded-character set — so the
sole `:` is the qualifier separator) into `(location, Option qualifier)`. New
`isPackageIdentifier` validates the qualifier as a well-formed CUE identifier (identifier-start
then identifier-parts) that is NOT a definition identifier (`#`/`_#` rejected — the spec forbids a
definition identifier as a PackageName), erroring on empty / digit-led / definition forms.
`parseImportSpec` routes both the bare-path and the alias-prefix (`import foo "…"`) arms through
the split, populating `path` + `packageName` (+ `alias`).

**Bind-name wiring (`Kue/Module.lean`).** `importBindName` precedence is now alias > explicit
qualifier > declared package name > last path element. The qualifier outranks the declared name
because it is the importer's chosen package name within the location.

**Scope: parse + bind-name; one resolution residual.** A `"location:identifier"` import now PARSES
and resolves where it previously failed; the qualifier is recorded and honored as the binding name,
never dropped. The STRICTER spec obligation — that the qualifier must MATCH the loaded package's
declared `package` clause (cue errors `no files in package directory with package name "other"`) —
is NOT yet enforced; it needs the loaded declared name and is a load-time gate beyond parsing. A
qualifier that mis-names an existing package currently binds under the qualifier without verifying
equality (recorded as a resolution residual in `cue-spec-gaps.md`).

**Tests.** 8 `native_decide` parse pins (`Kue/Tests/ParseTests.lean`): bare location; explicit
qualifier split; dash-last-element-needs-qualifier; alias + qualifier; underscore qualifier;
digit-led / definition-id / empty qualifier → error; plus an `isPackageIdentifier` boundary pin.
4 `native_decide` pins (`Kue/Tests/ModuleTests.lean`): qualifier outranks declared name; alias
outranks qualifier; suffix-stripped path binds under the declared name as a bare import does. 4
module fixtures (`testdata/modules/qualified_import{,_bare,_mixed,_invalid_id}`): the headline
dash-dir explicit-`:math` case, the bare-path defaulting case, a grouped import mixing both forms,
all three byte-identical to the `cue` oracle; plus the invalid-identifier `expected.err` error
fixture.

**Divergences / spec gaps recorded.** `cue-divergences.md` (F-3 row): Kue rejects a malformed
`:identifier` at PARSE (`invalid package identifier`); cue accepts any suffix text and defers to a
load-time failure — Kue is more spec-conformant (the grammar mandates `identifier`).
`cue-spec-gaps.md` (F-3 row): the identifier-validity boundary (`_foo` admitted, `#foo`/empty
rejected) and the parse-only resolution scope (suffix-vs-declared-name mismatch gate deferred).

**Verify.** `lake build` green (100 jobs; all pins checked at build; no non-exhaustive-match
warning). `check-fixtures.sh` → `fixture pairs ok` (zero drift on the full corpus; 4 new module
fixtures auto-discovered, no `FixturePorts` entry needed — those are for `testdata/cue/*` only).
`shellcheck` clean (no shell touched). The change is additive at the import layer; cert-manager/
argocd use no path qualifier, so it cannot regress real-app output.

**Next candidates:** BI-1 (Unicode case-fold — spike the data approach first) or a periodic
plan-hygiene / test-org pass (both DUE-but-non-blocking per the last Phase B; a periodic pass is the
cleanest pre-audit slice). Audit cadence: BI-2 = slice 1, F-3 = slice 2 of the new post-`457a165`
batch — two-phase audit due after ~1 more slice.

Files: `Kue/Value.lean` (`Import.packageName` field + doc), `Kue/Parse.lean` (`isPackageIdentifier`,
`splitImportPath`, `parseImportSpec`), `Kue/Module.lean` (`importBindName` precedence),
`Kue/Tests/ParseTests.lean` (8 pins), `Kue/Tests/ModuleTests.lean` (4 pins),
`testdata/modules/qualified_import{,_bare,_mixed,_invalid_id}/*`, `docs/reference/cue-divergences.md`,
`docs/reference/cue-spec-gaps.md`, `docs/spec/spec-conformance-audit.md`.

## Completed Slice: Test-org pass — carve EvalTests into Comprehension + Sort modules

**Organizational only — ZERO behavior change.** `EvalTests.lean` had grown to 1593 lines, nearing
the self-imposed ~1800 re-split ceiling (Phase B flagged the periodic test-org pass; this is slice 1
of the post-audit batch). Carved two cohesive subsystems out into focused modules; no test body
edited, no assertion/fixture/expected-output changed.

**What moved.** `Kue/Tests/ComprehensionTests.lean` (NEW, 280 lines, 29 pins): the `listcomp_*`
list-comprehension end-to-end pins (11), the `letcomp_*` D#3 let-clause pins (9), and the AST-level
`eval_comprehension_*` pins (9 — six `.structComp` shape pins plus the three Slice-C/D#1b
comprehension-guard end-to-end pins). `Kue/Tests/SortTests.lean` (NEW, 96 lines, 13 pins): the BI-2
`eval_list_sort_*` / `eval_list_ascending_is_comparator_struct` `list.Sort`/`SortStable` pins.
EvalTests retains the core eval pins (format/ref/cycle, structural-cycle D#2a, terminating-disjunct
D#2b + SC-3, scalar-embedding collapse, arithmetic/comparison/logical, reference resolution,
sibling-merge, F1 default-mark algebra, float mul/div, pattern-struct/B6/SC-2 closedness) and drops
to 1246 lines (−347).

**Deliberate scope correction vs the slice sketch.** The sketch named a `GuardTests` carve for the
`classify_guard_*` + D#1b/c guard-classification pins — but those guard-*classifier* unit pins
(`classifyGuard`, 14 of them) already live in `PresenceTests.lean`, not in EvalTests. EvalTests'
only guard pins are the *comprehension-guard* end-to-end shapes (`eval_comprehension_guard_*`), which
cohere with comprehension evaluation; a separate `GuardTests` would fragment one subsystem across
two files and duplicate PresenceTests' home. Folded them into `ComprehensionTests` and skipped the
spurious `GuardTests` module (resolve-by-philosophy: coherent subsystem grouping over the literal
name list). The `resolve_default_disj_*` / `distribute_*` pins (disjunction-default algebra, tied to
F1) stayed in EvalTests — they are not comprehension pins despite sitting between the moved blocks.

**Fixture regroup DEFERRED (not done).** The sketch also proposed sub-grouping
`testdata/cue/{definitions (50), comprehensions (27)}` into nested subdirs. Deferred as a remaining
sub-item: `Kue/Tests/FixturePorts.lean` (3049 lines) is hand-maintained, not generated — it is the
SOURCE whose hardcoded `fileName := "subdir/stem.expected"` strings + inline `content` are emitted by
`scripts/write-fixture-ports.lean` and diffed against the committed `.expected` files. A fixture move
therefore requires a multi-file `git mv` (`.cue`/`.expected`/`.manifest.expected`/`.args`) PLUS an
exact `fileName`-string edit in FixturePorts, per fixture, across ~77 fixtures — high blast radius
where one typo silently breaks the diff. Per the slice's hard constraint ("if the port wiring makes
a fixture move risky, DEFER rather than break discovery"), deferred in favor of the clean EvalTests
carve. The existing layout is already subsystem-grouped one level deep, and `definitions/` is
internally name-prefixed (`sc1*`/`sc2*`/`b6*`/`regex_*`/`string_*`), so the win is marginal.

**Verify.** `lake build` green (104 jobs — up from 100: +2 source +2 `.o` targets for the new
modules; `Built Kue.Tests.ComprehensionTests`/`SortTests` confirm both compiled, `Built Kue.Tests`
confirms the aggregator imports them so every moved `native_decide` pin is checked at build).
Pin-count conserved EXACTLY: 179 theorems before → 137 (EvalTests) + 29 (Comprehension) + 13 (Sort)
= 179 after, none lost. `check-fixtures.sh` → `fixture pairs ok` (zero drift; no `testdata/` or
FixturePorts touched). `shellcheck` N/A (no shell touched).

Files: `Kue/Tests/ComprehensionTests.lean` (NEW), `Kue/Tests/SortTests.lean` (NEW),
`Kue/Tests/EvalTests.lean` (−347 lines), `Kue/Tests.lean` (aggregator: +2 imports).

## Completed Slice: BI-1 — Unicode case mapping for `strings.ToUpper`/`ToLower` (2026-06-20)

`strings.ToUpper`/`ToLower` were ASCII-only (`Char.toUpper`/`toLower`), wrong on every
non-ASCII letter (`ToUpper("café")` → `"CAFé"` vs cue `"CAFÉ"`). Now they map the full BMP
cased set via an oracle-derived table. **CONFORMS to cue across the BMP.**

### Data-approach spike (done FIRST, committed `6065380` before any code)

Envelope-safe: NO network. Weighed three approaches against the local `cue` oracle queried
over the whole BMP:
- **(a) existing Lean Unicode support — UNAVAILABLE.** `lake-manifest.json` has ZERO external
  packages (no Std/Batteries/Mathlib); Lean core `Char.toUpper`/`toLower` are ASCII-only, no
  Unicode case tables in core.
- **(b) algorithmic range rules — REJECTED as a clean slice.** The oracle shows the mapping is
  overwhelmingly IRREGULAR: 1190 ToUpper / 1173 ToLower differing BMP code points collapse to
  only 674/658 fixed-offset runs, of which **632/617 are SINGLETONS**; just ~13 contiguous
  regular runs (ASCII, Latin-1 supplement, Greek, Cyrillic, Armenian, fullwidth…). A (b)
  covering only the regular runs leaves all of Latin Extended-A/B (the even/odd ±1 letter pairs
  + hundreds of one-offs like `µ`→`Μ` +743, `ÿ`→`Ÿ` +121) WRONG — a weak partial on very common
  European text; covering the full set algorithmically = hand-transcribing ~650 rules as code,
  strictly worse than a table.
- **(c) oracle-generated table — CHOSEN.** Generate a BMP **simple 1:1** case-mapping table
  from the local oracle, embed as a Lean source file, commit generator + table + provenance.

### Semantics — simple mapping (verified)

cue's `strings.ToUpper`/`ToLower` are Go's `unicode.ToUpper`/`ToLower`: pure rune-wise
**simple** mapping. Verified by round-tripping the entire BMP through the oracle — the result
is 1:1 in code points (length-in-code-points preserved), i.e. NO length-changing
special-casing: `ToUpper("ß") == "ß"` (German ß does NOT expand to `SS`; full folding would),
`ToUpper("ﬁ") == "ﬁ"`. So a 1:1 table is faithful. Deferred long tail = full case folding
(`ß`→`SS`, title-case digraphs), locale (Turkish `ı`/`İ`), Greek final sigma, astral-plane
letters — recorded as a spec-gap.

### Implementation

- **`scripts/gen-case-table.py` (generator, committed).** Queries `/Users/chakrit/go/bin/cue`
  (READ-ONLY, no network) over the BMP via one `cue export` round-trip per map, emits the
  differing `(src, dst)` pairs sorted ascending into `Kue/CaseTable.lean`. Idempotent (re-run =
  zero diff). Skips code points illegal in a CUE string literal (NUL, BOM) and C0/C1 controls —
  none of which have case mappings. Python, not shell: the data transform is python-shaped; no
  shell touched (so no shellcheck obligation).
- **`Kue/CaseTable.lean` (GENERATED data, "DO NOT EDIT").** `upperEntries` (1190 pairs) +
  `lowerEntries` (1173 pairs), each `Array (UInt32 × UInt32)` sorted by src. Emitted as
  128-element CHUNK arrays `++`-joined — a single 1190-element `#[…]` literal overflows
  elaboration recursion (`maxRecDepth`; the literal desugars to nested `List.cons`), but small
  chunks elaborate fine and `Array.append` builds the whole iteratively. (Tried a `maxRecDepth`
  bump first — even 8000 wasn't enough and it slows elaboration; chunking is the clean fix.)
- **`Kue/Builtin.lean`.** `caseTableSearch` — TOTAL binary search (`termination_by hi - lo`, no
  `partial`); `caseTableLookup` wraps it over `[0, size)`; `caseMapChar table c` returns the
  mapped `Char` on a hit, identity on miss; `unicodeToUpper`/`unicodeToLower` map a string
  rune-wise. The table is the single authority — ASCII (`a`→`A` at offset −32) is IN the table,
  so the old `asciiToUpper`/`asciiToLower` are deleted (one mechanism, not two). The two
  dispatch arms now call `unicodeToUpper`/`unicodeToLower`.

### Scope: ToTitle stays ASCII (NOT folded in)

BI-1 is scoped to ToUpper/ToLower. `ToTitle` keeps its ASCII title-casing this slice: its
mapping is Unicode **title-case**, distinct from upper (`ǆ`→`ǅ`, not `Ǆ` — confirmed via
oracle), and its word boundary is `unicode.IsSpace` (broader than ASCII whitespace); both need
their own table + predicate — a separate slice. So `ToTitle("über alles")` → Kue `"über
Alles"` vs cue `"Über Alles"` remains the ONE case-builtin divergence (Kue does less; in
compat-assumptions + spec-gaps, not cue-divergences — not a cue bug).

### Tests

New `Kue/Tests/StringsTests.lean` (test tree was just reorganized; case-folding warrants its
own module). Moved all `strings_to_{upper,lower,title}_*` pins out of `BuiltinTests.lean` and
ADDED Unicode coverage: ASCII regression (8 unchanged pins); Latin/Greek/Cyrillic upper↔lower
round-trips (`é`↔`É`, `αβγ`↔`ΑΒΓ`, `я`↔`Я`); irregular singletons (`µ`→`Μ`, `ÿ`→`Ÿ` — the
table's justification over ranges); `ß`-unchanged (simple-mapping boundary, CONFORMS); CJK +
symbol unchanged (deliberate identity boundary); mixed ASCII+multi-script strings (both
directions); empty; the flipped ToTitle non-ASCII boundary; arg guards; and two
`case_table_lookup_*` unit pins (hit + miss arms of the binary search). Every covered mapping
cross-checked against the oracle. New fixture `testdata/cue/builtins/strings_case_unicode.{cue,
expected}` (13 cases, `.expected` = Kue's output verbatim — byte-identical to cue except the
documented `titleNonAscii`) + a `FixturePorts.lean` entry.

### Verify

`lake build` green (108 jobs; `Built Kue.CaseTable` + `Built Kue.Tests.StringsTests` + relink
`kue:exe`). `check-fixtures.sh` → `fixture pairs ok` (zero drift on the full corpus). No shell
touched (generator is python) → `shellcheck` N/A. Generator re-run is idempotent.

Files: `scripts/gen-case-table.py` (NEW), `Kue/CaseTable.lean` (NEW, generated),
`Kue/Tests/StringsTests.lean` (NEW), `Kue/Builtin.lean` (table lookup + Unicode maps, ASCII
maps deleted, 2 dispatch arms), `Kue/Tests/BuiltinTests.lean` (case pins moved out),
`Kue/Tests/FixturePorts.lean` (+1 fixture entry), `Kue/Tests.lean` (+1 import),
`testdata/cue/builtins/strings_case_unicode.{cue,expected}` (NEW).

---

## Completed Slice: truncate-primitive Step 1 — fuse the fuel-truncation drop+bump into one primitive

Soundness hardening (plan item 1, HIGH — the illegal-states-unrepresentable reason-to-be).
NOT a CUE-semantics change: every value is byte-identical. Localizes a disciplinary invariant
to one choke point.

### The invariant being hardened

A `fuel=0` helper that DROPS fields/elements/meets MUST bump `EvalState.truncCount`, so the
bracketing `evalValueWithFuel`/`forceClosureWithConjunct` classifies the result `truncated`
and never serves it from the fuel-free `satCache` as if complete. This is the exact corruption
audit-#6 (2026-06-18) caught latent. Before this slice the bump was hand-written at every drop
site (a future site that forgot would be a latent soundness Violation).

### Count reconciliation — SEVEN sites, not six (and NO latent bug found)

The plan/breadcrumb said "six sites." The actual current count is **seven**: the two
`evalValueCoreWithFuel` arms (`fuel=0` base → passes the value through; depth-0 cycle → `.top`)
plus five expansion helpers (`evalEmbeddingFieldsWithFuel`, `meetEmbeddingsWithFuel`,
`expandComprehensionWithFuel`, `expandClausesWithFuel`, `expandListClausesWithFuel`). The "six"
predates the list-comprehension slice, which added the seventh (`expandListClausesWithFuel`)
with its own correct bump by discipline. **Audited all seven before rewriting: every one
already bumped — NO drop-without-bump existed.** This was a refactor that LOCALIZES a sound
invariant, not a bug fix. (The two `+ bump` cache-rebump sites — `cache`/`forceCache` truncated
hits — are the bracketing-honesty logic, NOT drop sites; left untouched.)

### Step 1 (DONE) — the `EvalState.truncate` primitive

`def EvalState.truncate {α : Type} (result : α) : EvalM α` bumps `truncCount` then returns
`result`, fusing the two so no drop site can split them out of sync. Polymorphic because each
arm drops a different incomplete shape (`Value`, `List Field`, `Except Value (List Field × List
Value)`, the clause-expansion sums). All seven sites rewritten from the hand-written
`modify (…truncCount + 1) ; pure <dropped>` to `EvalState.truncate <dropped>`. After this,
dropping without bumping is no longer expressible AT those sites — the invariant is structural
at one choke point instead of replicated across seven.

### Step 2 (ATTEMPTED, RULED OUT — not deferred)

A `withFuel (fuel) (truncated) (onFuel : Nat → EvalM α)` dispatch routing the `fuel=0` arm
through `truncate` — so a NEW helper physically cannot reach its zero arm without bumping — was
implemented and built against `expandListClausesWithFuel`. It BREAKS the mutual block's
well-founded `termination_by`: routing the dispatch through a lambda hides the `| fuel + 1 =>`
pattern, so Lean loses the definitional `fuel = next + 1` equation and the recursive call's
decrease (`fuel < fuel✝`) becomes unprovable (`failed to prove termination`). This is precisely
the risk the plan flagged ("eval hot path + `termination_by` measure"). Full type-level
unrepresentability would require re-architecting saturation off the monotonic-counter+bracket —
the design the audit-#6 fix deliberately chose over per-arm bit-threading (12 forget-sites).
Not worth it. Reverted to Step 1; recorded the residual routing-discipline as an invariant note
at the primitive and on the `truncCount` field doc. **Item CLOSED.**

### Tests (3 new structural pins, `Kue/Tests/EvalPerfTests.lean`)

The behavior-preserving property is proven END-TO-END by the byte-identical full corpus + the
existing cross-fuel hazard pins (`sat_*_truncation_not_served_across_fuel` for the comprehension
/list-comp/self-ref shapes — they exercise the drop sites' truncate+bump behaviorally). NEW pins
check the PRIMITIVE'S contract at build, so a future edit that breaks the fusion fails to compile:
`truncate_bumps_truncCount_by_one` (advances `truncCount` by exactly 1 from an ARBITRARY start —
pins the increment, not a `:= 0`/`:= 1` constant); `truncate_returns_its_argument` (polymorphic
`rfl` — the dropped result passes through verbatim at every `α`); `truncate_bumps_for_every_
dropped_shape` (the bump fires identically at `Value`/`List Field`/`ListClauseExpansion`, the
concrete dropped shapes — a type-specialized regression trips it).

### Verify

`lake build` green (108 jobs; the 3 new pins check at build — `native_decide` + `rfl`).
`check-fixtures.sh` → `fixture pairs ok` (byte-identical / zero drift on the full corpus — the
behavior-preserving proof). cert-manager `export` content-identical to `cue` (`jq -S`, 984 bytes
each) — the hot-path refactor did not perturb it. No shell touched → `shellcheck` N/A.

Files: `Kue/Eval.lean` (the `EvalState.truncate` primitive + invariant note; seven drop sites
rewritten; `truncCount` field doc refreshed), `Kue/Tests/EvalPerfTests.lean` (`runTruncate`
helper + 3 structural pins).

---

## Completed Slice: Spec-gap ratifications (4 gaps) — 3 RATIFIED, 1 ESCALATED

Goal: formally close the 4 pending spec-gap ratifications (the lower-confidence open
questions where the CUE spec is silent and Kue made a principled choice). Ratification =
re-derive each choice from the spec + first principles, verify current code still behaves
as recorded, and elevate from lower-confidence to a settled, test-pinned decision — or, if
review shows the choice is wrong, escalate rather than rubber-stamp. This was slice 2 of
the new batch (truncate-primitive = slice 1).

The 4 gaps (per the `spec-conformance-audit.md` backlog, distinct from the newer rows
several session slices added): (1) import-binding laziness B#2/F-5; (2) `A|B` un-narrowed
struct disjunction (area A); (3) field order #3 (C/F-4); (4) E#4 list `+`/`*`.

### Verdicts

1. **Import-binding laziness — RATIFIED.** Spec re-checked: genuinely silent (only a
   *referenced* `_|_` must propagate, which Kue honors). Tolerating an unreferenced bottom
   def in an imported package is ratified on an OPERATIONAL-LAZINESS basis (CUE's value
   model is demand-driven; the `FieldClass.importBinding` marker keeps the package shallow
   by construction so the deep-bottom recurse never fires). The lattice-purist
   "bottom-is-bottom-whether-selected-or-not" reading is acknowledged and DECLINED as
   contrary to the demand-driven model. Re-verified current behavior: the
   `unreferenced_import_conflict` module exports `{"out":{"name":"ok"}}`. Pinned by that
   fixture (runs via `check-fixtures.sh`) + `LatticeTests.rx2b_label_pattern_invalid_bottoms`
   (the recategorized field-less RX-2b sub-case).

2. **`A|B` un-narrowed struct disjunction — RATIFIED.** Spec silent (default rules govern
   selection at concretization, not the open form). Keep open: a join with no unique
   default IS the join — a settled lattice value, not an incompleteness or error.
   **Verified meet-identity vs `.top`**, confirming it is a settled value. Corrected the
   prior entry's "`incomplete`" mischaracterization. NEW pins
   `StructTests.disj_struct_arms_no_default_stays_open` + `_is_meet_identity`.

3. **Field order #3 — RATIFIED.** Spec silent (structs are unordered sets; output order is
   implementation-defined). Keep Kue's declaration / first-seen-across-conjuncts order
   (`{b}&{a}` → `b,a`): total, deterministic, one trivial rule, mirrors program text.
   **Corrected the cue-behavior record:** re-probed v0.16.1 shows cue's cross-conjunct
   order is an undocumented internal-graph artifact, NOT the "first-introduced" rule the
   docs once claimed — separate one-field literals sort (`{z}&{a}&{m}` → `a,m,z`,
   `{b,d}&{a,c}` → `a,b,c,d`) while a def-ref meet interleaves by introduction
   (`#Def:{kind,zfield} & {own,afield}` → `kind,own,afield,zfield`). Chasing that is
   reverse-engineering a presentation artifact the spec does not mandate; parity DECLINED
   (supersedes plan item #4). NEW pin
   `StructTests.meet_struct_field_order_is_declaration_order` (the existing
   `meet_disjoint_regular_structs` + `LatticeTests.mergeStructN_struct_tail_reverses_field_order`
   already lock the rule).

4. **E#4 list `+`/`*` — ⚠ MIS-FILED → ESCALATED (not ratified).** The gap claimed the spec
   was silent. It is NOT: the spec MANDATES the operator domain — *"The four standard
   arithmetic operators (+, -, *, /) apply to integer and decimal floating-point types; +
   and * also apply to strings and bytes."* Lists are excluded, so a list operand to
   `+`/`*` is a **type error → `_|_`**, the same class as `1 + "x"` (which Kue already
   bottoms). `cue` is spec-correct here (it hard-errors `… superseded by
   list.Concat/Repeat …`). **Kue is WRONG:** `evalAdd`/`evalMul`/`evalSub`/`evalDiv`
   (`Eval.lean:787-839`) reach the type-error `.bottom` arm only when both operands are
   `.prim`; a `.list` operand falls through `_,_ => .binary …`, leaving a held residual
   (`kue eval` shows `[1,2]+[3,4]` raw; `kue export` says `incomplete value`). An incomplete
   value claims "may resolve" — two concrete lists with `+` never can. Per the ratification
   protocol this is a STOP-and-flag, not a silent ratify: filed as **E#4-fix** (plan item #6
   + `spec-conformance-audit.md` MED tail) with the fix sketch (add an explicit ill-typed
   arm to the four ops) and a correct-behavior pin plan. Recorded in `cue-spec-gaps.md` as
   the ⚠ MIS-FILED row — NOT a `cue-divergence` (cue is correct, not buggy). No pin added
   for the current wrong residual (would bless the defect); the correct pin lands with the
   fix-slice.

### No new ADR

None of the four rises to a cross-cutting project-level decision (unlike the
oracle-as-data-source ADR): gaps 1–3 are narrow, self-contained, and well-served by the
RATIFIED entries + pins; E#4 is a bug to fix, not a settled decision. The
`cue-spec-gaps.md` rows are the durable record.

### Verify

`lake build` green (108 jobs; 3 new `native_decide`/`rfl` pins check at build).
`check-fixtures.sh` → `fixture pairs ok` (zero drift — this slice changed only docs + added
pins, no eval-path code). No shell touched → `shellcheck` N/A. All gap probes run against
`kue` (`.lake/build/bin/kue`) + the `cue` oracle (`/Users/chakrit/go/bin/cue` v0.16.1,
READ-ONLY).

Files: `Kue/Tests/StructTests.lean` (3 ratification pins), `docs/reference/cue-spec-gaps.md`
(rows 1–3 → RATIFIED with corrected bases; new ⚠ MIS-FILED E#4 row),
`docs/spec/spec-conformance-audit.md` (4-ratifications item closed; E#4-fix added to the MED
tail), `docs/spec/plan.md` (backlog line updated; item #4 RATIFIED-closed; E#4-fix added as
item #6 bullet).

---

## Completed Slice: E#4-fix — arithmetic operator domain (type-error + string/bytes repeat)

Goal: conform the four binary arithmetic ops to the CUE spec's operator domain. The spec
closes `+ - * /` over integer and decimal, and additionally `+`/`*` over strings and bytes;
a CONCRETE operand outside an op's domain is a type error (the same class as `1 + "x"`).
**Kue was WRONG**: `evalAdd`/`evalSub`/`evalMul`/`evalDiv` reached the type-error `.bottom`
arm only for `prim,prim`; a concrete `.list`/`.struct` operand fell through the
`_,_ => .binary` catch-all and left a **held residual** (`kue eval` showed `[1,2] + [3,4]`
raw; `kue export` said `incomplete value`). An incomplete value claims "may still resolve,"
but two concrete lists with `+` never can. This was slice 3 of the batch (truncate-primitive
= slice 1, ratifications = slice 2) → the two-phase audit is now DUE.

### The operator domain (verified spec + oracle, cue v0.16.1)

Probed every operator × wrong-type combination against the oracle:
- **list/struct/bool/null** operand to ANY of `+ - * /` (and string/bytes to `- /`) → type
  error. cue hard-errors (`Addition of lists is superseded by list.Concat`, `cannot use [..]
  as type number`, `invalid operands … to '+'`). Kue left a residual — the core bug.
- **`+`/`*` asymmetry:** `"a" + "b"` = concat (OK), `"a" - "b"` = type error.
- **`*` over (string\|bytes, int) = REPETITION** (either operand order): `"ab" * 2 = "abab"`,
  `'ab' * 2 = 'abab'`, `"x" * 0 = ""`, negative count → error (`cannot convert negative
  number to uint64`). This is cue's documented behavior superseding strings/bytes.Repeat.
  Kue silently wrong-bottomed it (the `prim,prim` arm's `evalDecimalMultiply?` returned
  `none`). Fixed as a sibling, since leaving a wrong-bottom in the very operator being
  conformed would be incoherent.

### The fix (`Kue/Eval.lean`, `Kue/Value.lean`)

- **`classifyArithOperand : Value → ArithOperandClass`** — splits an operand into `prim` /
  `concreteNonArith ty` (a fully-evaluated `.struct`/`.list`/`.listTail`/`.embeddedList`, with
  `ty : NonBoolGuardType` reused for provenance) / `incomplete` (ref/kind/bound/unresolved-disj
  /comprehension/…). Enumerates EVERY `Value` ctor with no catch-all (mirrors `classifyGuard`),
  so a new ctor forces a domain decision at compile time.
- **`arithmeticDomainResult (op) (left) (right) : Value`** — the shared gate the four ops call
  in place of `_,_ => .binary`. **Incomplete is checked FIRST**: if either operand is
  incomplete the binary DEFERS (`.binary op left right`) — it may still resolve to a number, so
  bottoming now would be unsound (cue holds `[1] + x` while `x: int` and errors only after `x`
  resolves to `5`). Otherwise a concrete-nonarith operand (preferring the left) yields
  `.bottomWith [.nonArithmeticOperand op ty]`. This is the D#1b/c concrete-vs-incomplete
  discipline: concrete-wrong → bottom, anything-incomplete → defer.
- **`evalMul` string/bytes repetition** — four new arms before the bottom/defer split:
  `(string,int)`/`(int,string)` and `(bytes,int)`/`(int,bytes)` → `evalRepeat`, which errors a
  negative count (`.bottomWith [.negativeRepeatCount n]`) else replicates.
- **New `BottomReason`s:** `nonArithmeticOperand (op : BinaryOp) (operand : NonBoolGuardType)`
  and `negativeRepeatCount (count : Int)`. Both manifest as `.error .contradiction` in export
  (the generic "conflicting values (bottom)" — content-identical to how `1 + "x"` already
  errors); the ctor payload is provenance for `Repr`/theorems. No `Manifest` change needed.

The `prim,prim` arms are UNTOUCHED — `1 + "x"`, `"a" - "b"`, `"ab" * 2.0`, `null - null`,
`true * false` all still bottom exactly as before (verified). The final `_,_ => .binary`
fallback inside `arithmeticDomainResult` is now structurally `prim,prim` (each op handles its
prim pair first), kept as the safe total residual that can never wrongly bottom.

### Tests

- **3 eval fixtures** (`testdata/cue/numeric/`, each + `FixturePort`):
  `list_arithmetic_type_error` (list/struct/bool/null × all four ops → `_|_`),
  `string_repeat_multiplication` (repeat both orders + zero + the `+`/`-` asymmetry),
  `arithmetic_incomplete_operand_defers` (the critical regression: `int + [1]` defers, and
  `resolved + 3 = 8` once the abstract `int` concretizes).
- **~19 `EvalTests` `native_decide`/`rfl` theorems** pinning the unit behavior independent of
  display: each op's concrete-nonarith → `nonArithmeticOperand` bottom; `.listTail` operand;
  the string/bytes repeat (incl. zero + negative-count error); and the incomplete-defers cases
  — concrete-list × incomplete kind (both orders), bound operand, ref operand → `.binary`.

No pre-existing fixture relied on the old wrong residual (none broke). NOT a `cue-divergence`
(cue was spec-correct); `cue-spec-gaps.md` E#4 row flipped MIS-FILED → ✅ RESOLVED/CONFORMING.
The only residual display delta is the pre-existing D#1b-family one (a deferred residual shows
the resolved ref by value, `int + [1]` vs cue's `x + [1]`) — value verdict identical.

### Verify

`lake build` green (108 jobs; the new theorems + FixturePorts check at build).
`check-fixtures.sh` → `fixture pairs ok` (zero drift on the full corpus; the 3 new pairs pass
on both the FixturePort-AST and `kue`-CLI paths, cue-fmt clean). cert-manager exports
content-identical to cue from the module context (625 bytes, modulo the pre-existing
field-order #3 — the bare-file "import failed" is a cue.mod-context artifact, not this fix).
No shell touched → `shellcheck` N/A. Oracle: `/Users/chakrit/go/bin/cue` v0.16.1, READ-ONLY.

Files: `Kue/Eval.lean` (classifier + gate + repeat), `Kue/Value.lean` (2 `BottomReason`s),
`Kue/Tests/EvalTests.lean` (~19 pins), `Kue/Tests/FixturePorts.lean` (3 ports),
`testdata/cue/numeric/{list_arithmetic_type_error,string_repeat_multiplication,
arithmetic_incomplete_operand_defers}.{cue,expected}`, `docs/reference/cue-spec-gaps.md`
(E#4 row → RESOLVED), `docs/spec/spec-conformance-audit.md` + `docs/spec/plan.md` (E#4-fix DONE).

## Completed Slice: AD4-1 — unify the comprehension clause-walker twins behind one generic driver

Behavior-PRESERVING DRY refactor (byte-identical fixtures are the proof). The struct and list
comprehension clause-walkers (`expandClausesWithFuel`/`expandForPairsWithFuel` →
`ClauseExpansion`; `expandListClausesWithFuel`/`expandListForPairsWithFuel` → `ListClauseExpansion`)
had byte-identical `.guard`/`.letClause`/`.forIn` arms and identical bottom/deferred short-circuit
folds; the two result sums were structurally identical 3-ctor types. The duplication was a standing
drift hazard — a fix to one twin's clause handling could silently skip the other.

### What unified

- **One generic outcome type.** The two sums collapse to `inductive ClauseOutcome (β : Type)` with
  ctors `payload β | bottom Value | deferred`. `ClauseExpansion`/`ListClauseExpansion` are now
  `abbrev`s (`ClauseOutcome (List Field)` / `ClauseOutcome (List Value)`), so existing return-type
  annotations and prose stay valid; the per-twin `.fields`/`.items` ctors become the shared
  `.payload`.
- **One generic driver pair**, both inside the existing mutual block, generic in `β` with
  `[EmptyCollection β] [Append β]` (a comprehension payload IS an appendable collection with an
  empty — `∅` for the drop/truncate/empty-`for` cases, `++` for concatenating iterations):
  `expandClauseChain` (the clause-chain walk) + `expandForPairs` (the per-`for`-iteration fold).
  The four old defs reduce to **two thin β-instantiating wrappers** — `expandClausesWithFuel`
  (struct) and `expandListClausesWithFuel` (list) — each supplying only the differing piece.
- **The two `*ForPairsWithFuel` defs were DROPPED as dead code.** Once the `for` recursion goes
  through the generic `expandForPairs`, nothing called the per-twin pairs walkers. Net: four
  near-identical walkers → two generic combinators + two one-line wrappers.

### The load-bearing `[_|_]`≠`_|_` asymmetry — preserved AND newly pinned

The struct and list `[]`-arms (clause chain exhausted, body evaluated) are the ONE genuine
difference, and it is VERIFIED-CORRECT CUE semantics, not an accident:
- STRUCT short-circuits a bare-`.bottom`/`.bottomWith` body to `.bottom` (D#1a — the bottom
  propagates, the enclosing struct becomes it).
- LIST wraps ANY body — including a bottom — as the one-element payload `.payload [body]`. A bottom
  list ELEMENT (`[_|_]`) is not the list being bottom; `cue eval` renders the same value and errors
  on it only under concrete `export`.

So the combinator takes the WHOLE `[]`-arm body→outcome map as its sole `onExhausted` parameter —
NOT a naive "wrap the body in `β`" shim, which would wrongly make the list twin bottom-propagate.
Four new `native_decide` pins in `ComprehensionTests` lock the asymmetry so the dedup can never
silently merge the handlers: `out: {for x in ["s"] {x, a: 1}}` → `_|_` (struct short-circuits);
`out: [for x in [1] {x & "s"}]` → `[_|_]` (list wraps); and both → `export` error
(`exportJsonBottoms`). The existing D#1a/b/c guard/let pins (`PresenceTests`, `ComprehensionTests`)
all pass unchanged.

### Termination preserved (the truncate-primitive Step-2 trap avoided)

The four walkers live in the big mutual block with a well-founded `(fuel, tag, sub)` measure.
truncate-primitive's Step 2 broke termination by routing a `fuel`-matching arm through a lambda
that hid the `| fuel+1 =>` pattern. Here the generic combinators keep their own
`match fuel with | 0 => … | fuel+1 => …` skeleton and recursive self-calls (`expandClauseChain …
fuel …`, `expandForPairs …`) LEXICALLY visible — `onExhausted` is pure and non-recursive, so it
hides no fuel/recursion pattern. `expandClauseChain` keeps tag 0 and `expandForPairs` keeps
`(fuel, 3, pairs.length)` (the old walkers' roles). The two thin wrappers, now non-self-recursive
but still in the SCC (they call into it), carry measure tag **2** — strictly between the tag-0
chain they call at equal fuel (`0 < 2`) and the tag-3 `evalListItemsWithFuel` that calls them at
equal fuel (`2 < 3`); their other callers decrement fuel. No `partial def`, no `sorryAx`.

### Verify

`lake build` green (all theorems incl. the 4 new pins). `scripts/check-fixtures.sh` →
`fixture pairs ok` (ZERO byte-drift — the behavior-preservation proof). `#print axioms` on all four
generic/wrapper defs: only `propext`/`Classical.choice`/`Quot.sound` (the well-founded baseline) —
axiom-clean. cert-manager `export` (run from the infra module dir) content-identical to `cue`
v0.16.1 (1448 bytes, modulo field-order #3) — no real-app regression on the comprehension/eval hot
path. No shell touched → `shellcheck` N/A. Pure refactor, no eval-path cost change → no
`kue-performance.md` edit.

Files: `Kue/Eval.lean` (`ClauseOutcome` + the two combinators + two wrappers; three call-site match
arms `.fields`/`.items` → `.payload`), `Kue/Tests/ComprehensionTests.lean` (4 asymmetry pins),
`Kue/Tests/EvalPerfTests.lean` (the polymorphic-truncate pin's `.items` → `.payload`),
`docs/spec/plan.md` (AD4-1 DONE; A-EN3+DRY-1 now leads the dedup family).

## Completed Slice: A-EN3 — unify the three def-frame `Value`-folds; DRY-1 ruled out

Behavior-PRESERVING DRY refactor (byte-identical fixtures + re-run `native_decide` pins are the
proof). Slice 2 of the new batch (AD4-1 was slice 1). Bundled A-EN3 + DRY-1 by edit-locality (both
families touch `defFrameRefIndices`); A-EN3 landed, DRY-1 ruled out empirically.

### A-EN3 — one combinator, three thin instantiations (commit `5652717`)

`refsSelfEmbeddedLabel` (monoid `Bool`/`||`), `selfReferencedLabels` (`List String`/`++`), and
`defFrameRefIndices` (`List Nat`/`++`) were three hand-copied structural recursions over the full
`Value` ctor tree threading frame depth (`+1` per frame-pusher; `descendClauses` for comprehension
arms), differing ONLY in (a) the monoid, (b) which constructor is the leaf, and (c) the depth
threaded into a `.dynamicField`'s value. They collapse to thin instantiations of one generic
`foldValueWithDepth (combine) (empty) (leaf : Nat → Value → Option β) (dynValShift : Nat)`:

- The `leaf` hook is PRE-ORDER: `some x` makes the node a leaf contributing `x` (no descent),
  `none` recurses structurally. `refsSelfEmbeddedLabel`/`selfReferencedLabels` fire the leaf on
  `.selector (.refId id) label`; `defFrameRefIndices` on a bare `.refId id`. The fold's default
  `.selector base _ => recurse base` arm handles the non-leaf selectors uniformly.
- The three `*Clauses` helpers (`refsSelfEmbeddedLabelClauses` etc.) were DROPPED — the fold's
  single `descendClauses`-based clause handler (`foldValueWithDepthClauses`) subsumes all three, so
  the `+1-per-for`/`+0-per-guard` clause-depth rule lives in exactly one place.
- n-ary positions use `List.foldl combine empty` where the originals used `flatMap`/`any` — value-
  identical for the `++`/`[]` and `||`/`false` monoids (List `++` associativity makes the
  left-folded list equal the flatMap'd one; `foldl (·||·)` = `any`).

**Termination preserved STRUCTURALLY** (no `termination_by`, matching the originals). The recursive
self-call stays lexically visible inside the combinator's own `match fuel with | 0 => empty | f+1 =>
foldValueWithDepth … f …` (wrapped in a `let rec'` local whose body keeps the `f+1` destructure +
recursive call in the SAME definition — the structural checker sees through it). `#print axioms`:
`propext` + `Quot.sound` only — axiom-clean, no `sorryAx`/`partial`.

**Proof surface preserved by RE-RUN, not hand re-proof.** Every two-pass agreement theorem (the B7
`descendClauses` pins, the A5 `selfReferencedLabels`/`refsSelfEmbeddedLabel` depth pins) and the
Bug2-1..2-4 soundness pins (`embedComprehensionReadLabels`, `letPromotedReadLabels`,
`injectLetLocalNarrowings`, in `TwoPassTests`/`EvalPerfTests`) are `native_decide` — they recompute
the function outputs against the deduped instantiations and matched, i.e. the instantiations are
definitionally/computationally equal to the originals on every pinned input. No proof script
changed. +3 new combinator pins in `TwoPassTests` (empty-monoid degeneracy, leaf short-circuit, the
`dynValShift` divergence witness).

**Latent finding surfaced (NOT fixed — fixing breaks byte-identical):** `defFrameRefIndices` scans a
`.dynamicField`'s VALUE at `depth+1` (`dynValShift=1`); the resolver pushes NO frame for a dynamic
field (`Resolve.lean:139` resolves key + value in the same scope), so this is an over-deep scan that
systematically misses def-frame refs buried in a dynamic-field value (`let _x = {(dyn): if defSib ==
…}`). Unreachable in the corpus, preserved byte-identically here, flagged at the `foldValueWithDepth`
docstring + pinned by `fold_value_dynfield_shift_divergence`. Filed as schedulable fix-slice
**A-EN3-DYN** (reconcile to 0, add a witnessing fixture, flip the pin). LOW — a corner prod9 doesn't
hit, and a behavior change does not belong in a no-behavior-change DRY slice.

> **Phase-A audit correction (this batch's audit):** the "unreachable" claim above is true only of
> the COMMITTED FIXTURES, not of constructible input. A-EN3-DYN is in fact a REACHABLE WRONG-RESULT:
> `#Add: {#kind: string, kind: string, out: [for x in ["a"] {("k"): kind}]}` + `patch: {#kind:
> "specific", kind: "specific", #Add}` gives kue `patch.out == [{k: string}]` where cue gives
> `[{k: "specific"}]` — the narrowed `kind` never reaches the dyn-field value because the over-deep
> scan misses it. A STATIC `{k: kind}` body field evaluates correctly (clean control), isolating the
> bug to `dynValShift=1`. The DRY slice's preservation was still CORRECT (the bug pre-dates it at
> `f9c1e56`); only the severity was understated. Re-classified in `plan.md` to a spec-conformance
> Violation (bumped above AD2-1). A distinct dyn-field-in-definition drop (DYN-DEF-1) was also found
> while probing.

Gate: `lake build` (108 jobs, all theorems incl. the 3 new pins), `scripts/check-fixtures.sh` →
`fixture pairs ok` (ZERO drift), cert-manager `export` (from the infra module dir) content-identical
to `cue` v0.16.1 (key-order-insensitive, modulo field-order #3). No shell touched. Pure refactor, no
eval-path cost change → no `kue-performance.md` edit.

Files: `Kue/Eval.lean` (`foldValueWithDepth` + `foldValueWithDepthClauses`; three folds → thin
instantiations; three `*Clauses` helpers dropped), `Kue/Tests/TwoPassTests.lean` (3 combinator pins +
two historical-comment name updates).

### DRY-1 — RULED OUT (attempted, reverted; no behavior change shipped)

The filed plan was ONE `walkFollowedLets` combinator with `closeDefFrameReadIndices` /
`letPromotedReadLabels` / `injectLetLocalNarrowings` as thin instantiations. It is the DRY trap, on
three independent grounds:

1. **`closeDefFrameReadIndices` shares nothing mechanically.** It recurses on a `List Nat` worklist
   (visited-set `List Nat` via `slotVisited`, lets followed BY INDEX via `nthField`/`defFrameRefIndices`),
   never destructuring a `Value`. Different carrier, visited-set, and follow mechanism from the two
   `Value`-recursive walkers — it cannot share their combinator at all.
2. **Collect vs rewrite.** `letPromotedReadLabels : Value → List String` is a catamorphism;
   `injectLetLocalNarrowings : Value → Value` is an endo-REWRITE that must reconstruct the exact
   `.structComp`/`.struct` preserving openness/tail/patterns. A combinator that does the struct-
   dispatch DISCARDS that metadata, so the rewrite can only be expressed by handing the whole `v`
   back to a callback that re-dispatches — zero leverage.
3. **Termination (empirically confirmed).** A scratch `walkFollowedLets` routing the nested-let
   recursion through a `step` callback failed Lean's structural-recursion inference (`failed to
   eliminate recursive application … Could not find a decreasing measure`) — the same
   lambda-hides-`fuel+1` trap that ruled out truncate-primitive Step 2.

The contrast with the SUCCESSFUL AD4-1 dedup is the lesson recorded for the family: AD4-1's variation
point (`onExhausted`) was a PURE non-recursive leaf, so the combinator could own the recursion;
DRY-1's variation point (the per-walker nested-let step) IS itself the recursion, so it can't be a
pure callback. The genuinely-shared skeleton is ~4 lines between only TWO of the three walkers, not
worth an indirection that worsens the code — mirrors the Phase-A ruling on the analogous
`classifyArith/Guard/Defined` trio. `injectLetLocalNarrowings` already reuses `letPromotedReadLabels`
— the two are factored at the right seam. Do NOT re-file. Plan + spec-conformance backlog updated to
RULED OUT.

---

## Completed Slice: A-EN3-DYN — dyn-field value depth reconciled to the resolver (Violation fix)

Goal: fix a REACHABLE wrong result where a comprehension inside an embedded def reads a regular def
sibling SOLELY through a DYNAMIC field's value, and the sibling is narrowed at the use site. Witness
(cue v0.16.1 correct, kue wrong pre-fix):

```
#Add: {#kind: string, kind: string, out: [for x in ["a"] {("k"): kind}]}
patch: {#kind: "specific", kind: "specific", #Add}
# cue → patch.out == [{k: "specific"}]
# kue (pre-fix) → export error "incomplete value: string"  (kind never narrowed)
```

A STATIC body field (`{k: kind}`) already evaluated correctly — clean static-vs-dynamic isolation.

**Root cause — TWO parallel occurrences of the same depth-mirror bug.** A `.dynamicField` pushes NO
resolver frame (`Resolve.lean` resolves both key and value in the parent scope), so a fold/scan must
read the value at the SAME depth as the field, not `depth + 1`. Two functions violated this:

1. **`foldValueWithDepth` / `defFrameRefIndices`** (the splice-seed scanner via
   `embedComprehensionReadLabels`) carried a `dynValShift = 1` knob that scanned the dyn-field value
   one frame too deep, so `kind` was MISSED as a seed → the use-site narrowing was never spliced into
   the def frame. This was the documented A-EN3-DYN locus.

2. **`hasSelfRefAtDepth`** (the deferral gate via `defBodyHasSiblingSelfRef`) had the IDENTICAL `+1`
   on the dyn-field value, AND dropped the key entirely. So `defBodyHasSiblingSelfRef` returned
   `false` for the witness → the def took the EAGER eval path (which resolves `out` against
   `kind: string` and caches it) instead of the deferral/closure-force path that re-evaluates against
   the narrowed frame. This second site was NOT in the original diagnosis — it was found by
   instrumenting the eval after the first fix alone did not move the end-to-end result.

Both fixes were necessary; neither alone fixed the witness. The seed fix decides WHICH labels to
splice; the gate fix decides WHETHER the deferral path fires at all.

**Changes.**
- `foldValueWithDepth`/`foldValueWithDepthClauses`: dropped the now-dead `dynValShift` parameter
  (all three instantiations passed `0` after the fix — `refsSelfEmbeddedLabel` and
  `selfReferencedLabels` already did, `defFrameRefIndices` was the lone `1`). The `.dynamicField` arm
  inlines `rec' depth inner` (was `rec' (depth + dynValShift) inner`). A one-value knob is noise
  (illegal-states-unrepresentable).
- `hasSelfRefAtDepth` `.dynamicField` arm: `hasSelfRefAtDepth fuel (depth + 1) value` →
  `hasSelfRefAtDepth fuel depth key || hasSelfRefAtDepth fuel depth value`. Now scans the KEY too (a
  dynamic key `(kind): …` reads `kind`, a sibling the deferral must catch) — strictly-more-correct,
  matching the resolver which resolves the key in the parent scope.

**Tests.** Four `testdata/cue/comprehensions/` fixtures + `FixturePorts` entries: the witness
(`dynfield_comprehension_narrowed_sibling`), the static control (`static_comprehension_narrowed_sibling`,
regression), a multi-level variant exercising both the key scan and a nested-value scan
(`dynfield_comprehension_key_and_nested_value`), and an unaffected dyn-field reading only the loop var
(`dynfield_comprehension_no_sibling_read`, guards against over-broadening). All four cross-checked
against cue v0.16.1 (`export`). The A-EN3 combinator pin `fold_value_dynfield_shift_divergence` —
which LOCKED the buggy over-scan — was REPLACED by `fold_value_dynfield_value_scanned_at_parent_depth`
asserting the corrected resolver-aligned behavior (the two arms swapped: `⟨0,5⟩ → [5]`, `⟨1,5⟩ → []`).
The two empty-monoid/leaf-short-circuit combinator pins updated for the dropped positional arg.

**Conformance.** This CONFORMS kue to the CUE spec (lexical scoping — a dynamic field's key and value
resolve in the field's own scope, no extra frame); cue was already correct, so NO `cue-divergences.md`
entry. Verify gate green: `lake build` (108 jobs), `scripts/check-fixtures.sh` → `fixture pairs ok`
(full corpus byte-identical except the now-correct buggy case), shellcheck clean, cert-manager
byte-identical to the pre-fix HEAD baseline (confirmed via a throwaway worktree build) and
semantically identical to cue.

## Completed Slice: DYN-DEF-1 — defer (not drop) a dynamic field with a non-concrete key (Violation fix)

Goal: fix a dropped-field wrong result where a dynamic field `(expr): v` whose label `expr` is NOT
a concrete string was silently DISCARDED instead of held as a residual. cue v0.16.1 holds the field
under `eval` (`(kind): "m"`) and errors under `export` (`key value of dynamic field must be
concrete`); kue dropped it, so a definition's pending dynamic field vanished from the def's own
display and any abstract-keyed struct exported `{}` rather than erroring.

```
#Add: {kind: string, (kind): "m"}
x: #Add
# cue eval → x: {kind: string, (kind): "m"}    kue (pre-fix) → x: {kind: string}  (DROPPED)
# cue export → errors "key value of dynamic field must be concrete"   kue (pre-fix) → x: {}
```

**Diagnosis (instrumented; the A-EN3-DYN two-site lesson applied — checked BOTH dyn-field loci
before assuming one).** The orchestrator's sketch ("specific to definitions; the dyn field is lost
in the def-splice / `hiddenFieldsOnly`/`spliceOperandForEmbed`") was WRONG on two counts, found by
running the witness on HEAD first:
1. The NARROWED witness (`#Add & {kind: "specific"}`) ALREADY re-keyed correctly on HEAD — the
   A-EN3-DYN slice's `hasSelfRefAtDepth` change (now scans the dyn-field KEY) had repaired the
   deferral gate that routes the narrowing through the closure-force path. So the def-splice path
   was not the bug.
2. The bug was NOT def-specific: a PLAIN struct with an abstract key (`s: string`, `(s): "m"`)
   dropped the field identically. The real locus was a pair of **silent-drop arms keyed on a
   non-string label**, both with a `_ =>`-drop catch-all:
   - `expandComprehensionWithFuel` `.dynamicField` arm (struct-member path, `Eval.lean`): a
     non-string label → `pure (.ok ([], []))` — the field contributed nothing and was not held.
   - the standalone `.dynamicField` eval arm: a non-string label → `pure .bottom` — dropped to a
     bare bottom (and additionally lost the field's `fieldClass`, hardcoding `.regular`).

These are the SAME drop expressed twice (the two-site pattern). cue-cross-checked the boundary
cases: a concrete non-string key (`(3)`/`(true)`/`({})`) is a TYPE error (`invalid index … (invalid
type …)`); a bottom key (`(1 & 2)`) propagates the conflict; an abstract key of ANY kind (int OR
string) HOLDS under eval and ERRORS under export — cue does not distinguish int-abstract from
string-abstract, both are "not concrete yet".

**Fix — one exhaustive classifier at both sites (illegal-states-unrepresentable).** New
`classifyDynLabel : Value -> DynLabelVerdict` (`Eval.lean`, adjacent to `classifyGuard`, which it
mirrors: every `Value` ctor enumerated, NO catch-all). Verdicts:
- `concreteString name` → re-key the field to `name` (the existing correct path, untouched).
- `bottom v` → propagate `v` (the conflict surfaces; never a silent drop).
- `nonString ty` → type error `BottomReason.nonStringLabel ty` (a concrete non-string can never be
  a label).
- `incomplete` → DEFER: hold the UNEVALUATED `.dynamicField label fieldClass value` as a residual
  (in `expandComprehensionWithFuel`, as the `deferredComps` payload `[.dynamicField …]`, exactly
  like the incomplete-comprehension arm; in the standalone arm, return the node itself). Unevaluated
  so a later struct re-eval against a narrowed frame re-resolves the key and re-keys — which is why
  the narrowed witness works (the residual re-keys once the frame narrows). The abstract `string`
  kind lands here — the heart of the bug: it MAY still narrow to a concrete string at a use site.

Both eval sites now call `classifyDynLabel`; the standalone arm additionally preserves `fieldClass`
(was hardcoded `.regular` — a latent loss of optional/required dynamic fields). The held-vs-dropped
state is explicit in the residual representation, not an accident of eval order.

**Supporting rename.** `NonBoolGuardType → ConcreteTypeName` (`Value.lean`): the type was already
shared by `nonBoolGuard`, `nonArithmeticOperand`, and `concreteNonArith` — the guard-specific name
was already a misnomer. Now also carried by `nonStringLabel`. Five mechanical references updated.

**Tests.** `classifyDynLabel` unit pins in `PresenceTests.lean` (concrete-string; abstract-defer for
string-kind, int-kind, ref, unresolved-disj; concrete-non-string by type for int/bool/null/struct/
list; bottom-propagates). End-to-end `dyndef_*` pins in `ComprehensionTests.lean`: witness re-key,
multi-dynamic-field, transitive (key reads a sibling that reads the narrowed field), concrete-key
regression — all export-level JSON (display-independent); abstract-key-held (def + plain struct),
concrete-non-string-key, bottom-key — via `exportJsonBottoms` (the precise held-vs-dropped witness:
a HELD residual fails export, a DROPPED field would export `{}` successfully). Three
`testdata/cue/definitions/dyndef_*` fixtures (+ `FixturePorts` entries), each cue v0.16.1
oracle-checked. The A-EN3-DYN fixture `dynfield_comprehension_key_and_nested_value.expected` was
corrected from the BUG-REPLICATING `out: [{}]` (dropped) to the now-held residual
`out: [{(@2.0): {label: @3.1}}]` — its def-display had baked in the drop.

**Conformance.** CONFORMS kue to the CUE spec (a field label must be a string; a non-concrete label
is incomplete → held under eval, error under export); cue was already correct, so NO
`cue-divergences.md` CORRECTNESS entry. The held residual's key renders as `@depth.index` (vs cue's
source name `kind`) — the SAME pre-existing Resolve→Format limitation already documented for
deferred comprehensions (D#1b); that divergence row was folded to cover dynamic-field labels too,
rather than adding a redundant row. Verify gate green: `lake build` (108 jobs),
`scripts/check-fixtures.sh` → `fixture pairs ok` (full corpus byte-identical except the one
corrected A-EN3 fixture), shellcheck clean (no shell touched), cert-manager export byte-identical to
the pre-fix HEAD baseline (throwaway-worktree build) and semantically equal to cue.

**Audit state.** A-EN3-DYN (slice 1) + DYN-DEF-1 (slice 2) → the two-phase audit (A then B, per
`docs/guides/slice-loop.md`) is **DUE** — the two dyn-field-correctness fixes are a coherent batch to
audit together. Next code leader after the audit: **AD2-1** (the sole remaining dedup-family member).

---

## Investigation (no code): D#1d-RESIDUAL re-diagnosed — BLOCKED on a lattice prerequisite (MEET-RESID-1)

Goal: fix D#1d-RESIDUAL (a comprehension body that evaluates to a HELD RESIDUAL — a `.structComp`
with an abstract-keyed dyn field or a nested deferred `if`/`for` — is silently dropped to `{}`; cue
HOLDS it). Outcome: **the comprehension-body lift is a one-liner that works for the witnesses, but the
held residual cannot survive a `meet` — a NEWLY-FOUND lattice gap that gates this fix.** Reverted clean
(tree at HEAD, build green); filed the prerequisite **MEET-RESID-1** and demoted D#1d-RESIDUAL behind
it. No commit beyond docs.

### Oracle-confirmed witnesses (cue v0.16.1)

- `x: {for k in [string] {(k):1}}` — cue eval HOLDS the block; export errors `key value of dynamic
  field must be concrete`. kue (HEAD) drops to `x: {}`.
- `x: {for _ in [1] {if g {y:1}}}`, `g: bool` — cue eval HOLDS; export errors `incomplete value bool`.
  kue (HEAD) drops to `x: {}`.
- Concrete-key control `x: {for k in ["a"] {(k):1}}` → both resolve to `{x:{a:1}}` (must stay).

### What the instrumented slice attempt established

1. **The simplest fix HOLDS the witnesses byte-cue-faithfully.** `expandClausesWithFuel`'s struct
   `onExhausted` (`Eval.lean:~3611`) drops a `.structComp` body via its `_ => .payload []` catch-all.
   Adding `| .structComp .. => .deferred` (re-emit the original `.comprehension` node — what every
   caller already does for `.deferred`) makes both witnesses hold: `x: {for k in [string] {(@1.0):1}}`
   / `x: {for _ in [1] {if @3.0 {y:1}}}` (the `@d.i` label is the documented D#1b display limit). So
   the body lift is ONE LINE, NOT the multi-site `ClauseOutcome` payload-arm Phase B sketched — and a
   payload arm carrying the EVALUATED residual would be WRONG (it freezes the transient case).
2. **The transient `add.#patch` case resolves WITHOUT the lift.** Guard-trace instrumentation
   (`kind == add.#kind`) shows the embed-narrowing FORCE path
   (`meetEmbeddingsWithFuel`/`forceClosureWithConjunct`, `Eval.lean:3172-3174`) re-evaluates the
   embed's UNEVALUATED body with `kind` spliced concrete → inner `if` concrete-true → the outer
   for-body resolves to a plain `.struct`, so the new `.structComp` arm never fires on the narrowed
   pass. Phase-B's "the caller can't tell transient from terminal" is MOOT: it needn't — the force
   path handles transient via re-eval-from-source; the two-pass fixpoint converges.
3. **THE REAL BLOCKER: a held `.structComp` residual cannot survive a `meet`.** The 7-TwoPassTests
   break is NOT the narrowed `out` (resolves to `{kind,meta}`). It is the UNNARROWED embed `#Outer:
   {#Inner, #additions:…}` (no use-site `kind`): `#Inner` now holds as a `.structComp` residual, and
   embedding it BOTTOMS (`#Outer: _|_`) → `out: #Outer & {kind:…}` = `_|_`. cue HOLDS the unnarrowed
   embed (eval) and errors `non-concrete value string in operand to ==` (export). Minimal proof, no
   embed: `a: {for k in [string] {(k):1}}; b: a & {x:2}` → kue `b: _|_`, cue `b: a & {x:2}` (held).
   Root: `meetCore` (`Lattice.lean:460-461`) `| .structComp _ _ _, _ => .bottom`; the eval-time
   conjunction fold `evalConjWithFuel` (`Eval.lean:3123`) and the embed-close path both reach it.

### Filed: MEET-RESID-1 (prerequisite)

Make a `meet` whose operand is an UNRESOLVED `.structComp` residual HOLD (defer to `.conj
[left,right]`, the established residual-meet seam — cf. `conjDefClosure?`/`.closure` deferral and the
`.conj` lazy-merge at `Eval.lean:345-347`) instead of bottoming, and re-resolve that `.conj` once the
residual's blocker clears (capability-3: a `.conj` carrying a `.structComp` member must re-drive it
through `withDeferredComprehensions`). Multi-site, two-pass re-resolution, delicate soundness boundary
(gate to UNRESOLVED `.structComp` only — never collapse a genuine struct-vs-nonstruct type error to a
hold). NOT forced this slice (the "no workarounds / STOP at soundness boundaries" grant). Once it
lands, D#1d-RESIDUAL collapses to the one-line `onExhausted` arm + fixtures/pins.

### Conformance / gate

No code shipped; tree reverted to HEAD, `lake build` green (108 jobs), `git diff` empty. No
`cue-divergences.md`/`cue-spec-gaps.md` change (cue is correct on every witness; the held-`@d.i`
display is the already-documented D#1b row). Next live leader: **AD2-1** (D#1d-RESIDUAL blocked behind
MEET-RESID-1).

## MEET-RESID-1 + D#1d-RESIDUAL: held `.structComp` residual survives a meet; comprehension-body lift

Both landed in one commit (MEET-RESID-1 unblocks D#1d-RESIDUAL's one-liner). A held `.structComp`
residual — a comprehension whose dynamic key / `if` / `for` is non-concrete — now (a) is HELD when it
is a comprehension BODY (D#1d-RESIDUAL), and (b) SURVIVES a `meet`/`&` against a struct (MEET-RESID-1),
where HEAD dropped it to `{}` then bottomed it. Witnesses oracle-confirmed vs cue v0.16.1.

### The soundness gate (the crux — structural, not a runtime predicate)

The defer must NEVER mask a real conflict. It rests on an INVARIANT, not a heuristic:

> **A `.structComp` is, by construction, ALWAYS an unresolved residual whose `fields` are already
> conflict-free.** A resolved conflict is `.bottom`, never a `.structComp` — that state is
> unrepresentable.

Exhaustive over the two production sites (`grep '.structComp ' Kue/*.lean`): (1) `withDeferred-
Comprehensions` (`Eval.lean:1280`) emits a `.structComp` ONLY when `deferred ≠ []` AND the static
merge SUCCEEDED (`mergeEvaluatedFields` returned `some` — a field conflict returns `pure .bottom`
FIRST, `Eval.lean:2997`/`3415`); the `fields` are fully-evaluated, conflict-free, the `deferred` are
genuinely pending. (2) `Parse.lean:584/585/713` + `Normalize.lean:21` — the UNEVALUATED pre-eval form,
also unresolved-by-construction (the eager arm expands it to `.struct` before any meet). No third
site, none storing a resolved conflict. So "unresolved held residual" and "is `.structComp`" are the
SAME SET; the gate's predicate is just the constructor tag and can never fire on a resolved conflict.
Illegal-states-unrepresentable does the gate's work.

### The reduction (`meetWithFuel`, `Lattice.lean`)

A new arm (symmetric in both operand orders), placed ABOVE the struct/embeddedList arms (so a
`.structComp` is never first swallowed by a `listLike`/`leftLike` catch that would `meetCore`-bottom
it), BELOW `.top`:

- `other` reduces (`asResidualMergeOperand?`) to a plain struct operand (`.struct rf ro none [] _` or
  another `.structComp rf rcomps ro` contributing `rf` + `rcomps`) → merge the RESOLVED fields via the
  proven `mergeStructN (meetWithFuel fuel) lf … rf …`. A genuine field conflict (`a:{x:1,for…} &
  {x:2}`) returns `.bottom` THERE (surfaced inline as `x: _|_`, the kue convention; export errors —
  NOT masked). Else re-wrap `.structComp merged (lcomps ++ rcomps) mo`: the residual survives carrying
  merged fields + ALL deferred comps.
- `other` is NOT a plain struct (`a & 5`) → `asResidualMergeOperand?` is `none` → fall through to
  `meetCore` → `.bottom` (a real struct-vs-nonstruct type error, unchanged). The `.structComp`
  openness is a bare `...` flag (no tail value), collapsed via `StructOpenness.ofBool …isOpen`.

`meetCore`'s `.structComp` arms stay `.bottom` (the fuel-0 floor + genuine-type-error fall-through).

### Two-pass re-resolution (capability-3 — already satisfied, NO new machinery)

The witness `b: a & {x:2}` parses to `.conj [ref a, {x:2}]` (`&` → `.conj`, `Parse.lean:844`).
`evalConjStandard` (`Eval.lean:3078`): `conjStructOperand?` returns `none` for the `.structComp`
(`Eval.lean:1703`, no `.structComp` arm) → the deferral fold re-evaluates `ref a` FROM SOURCE
(`evalValueWithFuel`, `Eval.lean:3116`), retrying its comprehensions, then `evaluated.foldl meet .top`
(`Eval.lean:3124`) calls the new `meet` arm. If the comp resolves on re-eval the result is a plain
`.struct` (the new arm never fires); if it stays unresolved the arm re-wraps a `.structComp` and the
next `.conj` re-eval retries — the FIXPOINT. The transient `add.#patch` case resolves via the
embed-narrowing FORCE path (re-eval-from-source with `kind` spliced), independent of this arm.
Double-meet (`c: b & {y:3}`) converges (accumulates `x:2, y:3`, holds the `for`).

### D#1d-RESIDUAL one-liner (`Eval.lean:~3622`)

`expandClausesWithFuel`'s `onExhausted` gained `| .structComp .. => .deferred` — a comprehension whose
BODY evaluates to a held `.structComp` re-emits the original `.comprehension` (held) instead of
`.payload []` (→ `{}`). Unblocked by MEET-RESID-1 (the held body now survives the meet/embed). A
transient body resolves on the force pass before reaching here, so this arm fires only on a genuinely-
undecidable residual.

### Tests (adversarial on the gate) + verify

8 `native_decide` theorems in `TwoPassTests.lean`, all source-level (full parse→eval→meet→format,
oracle-cross-checked) — STRONGER than a CLI fixture (FixturePorts is hand-built AST only, no
source-string port; the theorems test the in-process pipeline a fixture cannot): the witness
(`residual_survives_meet_with_struct`); the held body (`residual_comprehension_body_held`); the
SOUNDNESS TRIPWIRES — field conflict still bottoms (`residual_meet_field_conflict_bottoms` + its
export-bottoms twin), scalar meet bottoms (`residual_meet_scalar_bottoms`); the no-over-fire controls
(compatible field held; concrete-key still resolves). Gate: `lake build` green (108 jobs);
axiom-clean (`propext`/`Classical.choice`/`Quot.sound` only — no `sorryAx`/`partial`);
`scripts/check-fixtures.sh` → `fixture pairs ok` (all existing byte-identical; the 7 TwoPassTests stay
green); **cert-manager export BYTE-IDENTICAL to the pre-fix HEAD baseline** (`90071b4`, via throwaway
worktree) AND semantically identical to cue — meetWithFuel is THE hot path, no regression. No
`cue-divergences.md` change (CONFORMS to cue on every witness). No `cue-spec-gaps.md` change (the
held-`@d.i` display is the already-documented D#1b row; cue is correct and matched). Next leader:
**AD2-1**.

---

## Completed Slice: A#6 — `containsBottom` made TOTAL/structural (fuel-cap soundness hardening)

Goal: close the `containsBottom` fuel cap (100). `containsBottom` checks whether a `Value` contains a
present `.bottom`/`.bottomWith`; it is the predicate `liveAlternatives` uses to PRUNE dead disjunction
arms (and `labelMatchesPatternWith` + the builtin boundary use it too). Capped at fuel=100, a
`.bottom` nested deeper than 100 levels was MISSED → a dead arm survived the prune → a WRONG value (an
unresolved `.disj` where the answer should have collapsed to the live arm). Standalone: D#2b confirmed
structural cycles are NOT the cause — D#2a detection fires at recursion depth ~2, so a
`.structuralCycle` bottom is always shallow. The hole was for genuinely-deep NON-cyclic bottoms.

### The fix — remove the fuel; total structural recursion (`Lattice.lean:160`)

`Value` is a FINITE well-founded inductive: its `refId`/`closure` ids are leaf data, never back-edges
into a `Value`, so `containsBottom` recursing over the structure is naturally terminating with NO
depth bound. The fuel was a defensive artifact that CREATED the hole. Rewrote as a `mutual` block —
`containsBottom` plus four list-helpers (`containsBottomList`/`Alts`/`Fields`/`Patterns`, one per
nested-`List` child type) — elaborated via **`termination_by structural`**.

Two properties had to hold together, and `structural` is what delivers both:
- **TOTAL, no depth bound** — a `.bottom` at ANY depth (150, 500, …) is found. This IS the soundness
  win; illegal-states/totality replaces the bug-prone bound.
- **`rfl`/`decide`-reducible** — a `sizeOf` WELL-FOUNDED measure (the first thing I tried) makes the
  function irreducible in the kernel, which broke ~12 existing `meet`/manifest `rfl` proofs across 6
  test modules (they unfold through `containsBottom` via `liveAlternatives`). `termination_by
  structural` elaborates via the nested-inductive recursor, which DOES reduce by `rfl` — so those
  proofs keep working. (Confirmed structural ⇒ `rfl`-reducible with a standalone probe before
  committing to it.) The list-of-pair / list-of-field helpers DESTRUCTURE their element in the match
  (`(_, value)`, `⟨_, fieldClass, value⟩`, `(labelPattern, constraint)`) so the recursed-on subterm is
  a syntactic component the structural checker accepts (an opaque `.fst`/`.snd`/callback projection was
  rejected).

`fieldBottomCounts` (the old optional-skip helper, which took `containsBottom` as a callback only to
dodge mutual recursion under the fuel design) is DELETED — its rule (an OPTIONAL field's bottom does
NOT bottom the struct; `#u?: _|_` stays live until `#u` is supplied) is folded inline into
`containsBottomFields`, where the destructured `value` keeps the recursion structural. One place, no
callback indirection. The pre-eval/deferred constructors (`comprehension`, `structComp`,
`listComprehension`, `interpolation`, `dynamicField`, `closure`) remain UN-descended (catch-all
`false`), byte-for-byte the same behavior as the fuel version — they never sit on the
disjunction-pruning path as a resolved value.

### Tests (8 adversarial `native_decide` pins, `LatticeTests.lean`) + verify

`nestList n` wraps a seed in `n` levels of `.list [·]` (exercising the `containsBottomList` helper at
depth): a depth-150 bottom IS detected (`a6_deep_bottom_detected_past_old_cap` — the headline; this
returned `false` under fuel=100, the latent wrong-value); depth-500 (`a6_very_deep_bottom_detected`);
shallow regression (`a6_shallow_bottom_detected`); deep no-bottom → false (`a6_deep_no_bottom_false`);
deep `.bottomWith` (`a6_deep_bottomWith_detected`); deep OPTIONAL-skip still composes
(`a6_deep_optional_bottom_skipped` → false); and the END-TO-END disjunction-pruning path —
`liveAlternatives` drops the deep-bottom arm (`a6_live_alternatives_prunes_deep_bottom_arm`) and
`normalizeDisj` collapses to the survivor (`a6_normalize_disj_collapses_past_deep_bottom`). Pre-fix the
last two would have kept the dead arm → a spurious 2-arm `.disj`.

Gate: `lake build` green (108 jobs); axiom-clean — `containsBottom` + all four helpers depend on
`propext` ONLY (no `sorryAx`/`partial`/`Classical.choice`; structural recursion is fully
constructive); `scripts/check-fixtures.sh` → `fixture pairs ok` (ZERO drift — removing the cap only
affects pathologically-deep cases absent from the corpus); `shellcheck` clean (no shell touched);
**cert-manager export BYTE-IDENTICAL to the pre-fix HEAD baseline `3f085e1`** (throwaway worktree) AND
semantically identical to cue — `containsBottom` is on the disjunction hot path, no regression. No
observable behavior changed on any existing case (only latent deep-bottom cases flip from wrong to
right). No `cue-divergences.md` change (removes a latent wrong-value, not a cue divergence); no
`cue-spec-gaps.md` / `kue-performance.md` change (structural walk cost on deep values is negligible;
no corpus value moved). **This is slice 2 since the audit counter reset (MEET-RESID-1 = slice 1) — the
two-phase audit is now DUE.** Next leader after the audit: **AD2-1** (deferred/surface) or SC-1b /
BI-2-residual.

## Spec-review slice: RESID-MASK-2 — disjunction eager-prune-of-definitely-bottom is SOUND; recorded as a cue-spec-gap (2026-06-21)

The sole open masking site from the Phase-B `39e8af4` sweep. A non-default disjunction prunes a
definitely-bottom arm (a held `.structComp` residual whose RESOLVED fields carry a TERMINAL inline
conflict, e.g. `a & {x:2}` with `a.x:1` ⇒ `x:1 & x:2 = _|_`) and commits to a surviving arm that is
itself STILL INCOMPLETE; cue HOLDS the whole disjunction. No code change — this was a
soundness-verification + spec-conformance slice. **MEET-RESID-1 ripple family CLOSED.**

### SOUNDNESS VERDICT — CLEAN (the prune fires only on a definitely/terminal bottom)

The prune gate is `liveAlternatives` → `containsBottom` (`Lattice.lean:307/178`): an arm is dropped
iff `containsBottom arm.snd`, which returns `true` ONLY on a MATERIALIZED `.bottom`/`.bottomWith`
node already present in the value tree. Such a node arises only from a conflict that has already
REDUCED to bottom — concrete-vs-concrete (`x:1 & x:2`), concrete-vs-bound (`x:1 & x:>5`), or
disjoint-bound (`x:>5 & x:<3`) — every one of which is TERMINAL (cannot un-bottom under any later
refinement, since refinement only narrows). It does NOT fire on a merely-incomplete arm: an arm
bottom-NOW only because an abstract operand has not resolved carries no bottom node, so it is NOT
pruned. Adversarial confirmation (oracle cue v0.16.1):
- `(a & {x:2}) | (a & {x:3,ok:true})` with `a.x:int` ABSTRACT → kue KEEPS BOTH arms (`{x:2,…} |
  {x:3,…}`); the `x:2` arm is `{x:2}`, not bottom. The unsound move would be pruning it (it could
  become viable); kue does not.
- the same, then `& {x:2}` → arm 1 wins (`{x:2,…}`), arm 2 (`x:3 & x:2`) dies → kue commits to the
  genuinely-correct survivor: the abstract arm was reachable, not prematurely killed.
- both arms incomplete, NO conflict (`(a&{y:2}) | (a&{z:3})`) → BOTH survive (the held `for`
  comprehension is never frozen into a bottom; incompleteness alone never prunes).
- `({x:>5} | {x:<0,ok}) & {x:7}` → `{x:7}`, cue AGREES — kue did NOT prune `>5` while abstract; both
  prune the dead `<0` arm only after the `x:7` meet makes it a terminal bottom.

There is no construction where kue prunes an arm that could later become viable. **No unsoundness;
no fix needed.**

### SPEC-CONFORMANCE — eager prune is spec-consonant; cue's hold is permitted lazy eval

The CUE spec (`docs/reference/cue-language-guide.md` Disjunction) mandates *"distribute the unification
over the alternatives and **eliminate bottom alternatives**"* (`("a"|"b") & "c" == _|_`) and treats
`_|_` as the identity for `|`. Eager elimination of a DEFINITELY-bottom arm is therefore spec-correct
and the more precise lattice move. The spec does NOT pin the *timing* — it also says *"Evaluation can
retain unresolved disjunctions"* — so cue's conservative hold (it doesn't evaluate the residual arm
far enough to see the concrete conflict) is permitted laziness, NOT a spec violation. Hence a
**`cue-spec-gap`**, not a `cue-divergence`: kue is MORE precise; cue is less precise but not wrong.
Recorded in `cue-spec-gaps.md` (RESID-MASK-2 row) with kue's behavior PINNED so it cannot regress to
cue's hold.

### Tests (8 `native_decide` pins, `TwoPassTests.lean`) + verify

New `### RESID-MASK-2` section: the witness (`resid_mask2_witness_eager_prune_commits_to_incomplete_survivor`);
the four adversarial SOUNDNESS pins (`_sound_abstract_operand_arm_not_pruned`,
`_sound_incomplete_arm_resolves_correctly_after_narrowing`, `_sound_both_incomplete_no_conflict_both_survive`,
`_sound_bound_arm_survives_until_concrete_conflict`); the precision witness (kue exports `{plain:5}`
where cue errors entirely — `_precision_terminal_residual_arm_pruned_for_concrete_survivor`); and two
`_|_`-identity regressions (`_bottom_identity_collapses_to_concrete_arm`,
`_terminal_conflict_arm_sheds_for_concrete_survivor`). Also CORRECTED the stale NOTE at the
RESID-MASK-1 pins (it claimed a non-default residual-conflict arm "survives as a spurious arm" — that
was FALSIFIED on current HEAD: kue eager-prunes it; RESID-MASK-1 already closed that path).

Gate: `lake build` green (108 jobs, all pins `native_decide`); `scripts/check-fixtures.sh` →
`fixture pairs ok` (ZERO drift — no code change); `shellcheck` n/a (no shell); cert-manager export
SEMANTICALLY identical to cue on the disjunction path. No `cue-divergences.md` change. **Audit counter
= 1 (this is slice 1 of the new batch; audit due after 2–3).** Next leader: **SC-1b** (closed×closed-
pattern); the remaining tail is increasingly user-input-gated (AD2-1 display contract, SC-3 coupled
with it, BI-2-residual = the Float/NaN/Infinity numeric-model undertaking).

---

## Completed Slice: SC-1b — closed × closed-pattern intersection (per-conjunct provenance)

Goal: fix the closed allowed-set so the meet of two CLOSED structs is closed to the
INTERSECTION of their allowed-sets (a field survives iff EVERY closed conjunct admits it),
not the union.

### The bug

The struct's closed allowed-set was stored as `closingPatterns : List Value` — a FLAT list
of label-predicates checked with `any` ("matches ANY stored predicate"). That is a UNION.
The meet of two closed structs carried `leftClosingPatterns ++ rightClosingPatterns`, so a
later meet against the result admitted a field matching EITHER operand's pattern. CUE's rule
is the INTERSECTION: closedness is conjunctive/monotone ("closing = adding `..._|_`"), so a
field must satisfy each closed conjunct independently. A flat predicate list cannot express
this — "matches `^x`" ∩ "matches `^y`" is not a single regex.

The original audit witness (same pattern `^x` on both, disjoint *explicit* fields `a`/`b`)
was MASKED: the disjoint required fields materialize in the result and get poisoned
(`fieldNotAllowed`), which independently rejects any later re-introduction — so the
union-store's lossiness was unobservable there. The REAL witnesses use DIFFERENT patterns:
`#A:{[=~"^x"]} & #B:{[=~"^y"]}` then `& {x1: 5}` — `x1` matches `^x` but not `^y`, must be
rejected. Pre-fix Kue admitted it; cue rejects (oracle v0.16.1). Field-side too (CRUX): a
field-only closed clause `#A:{a?}` met with `#B:{[=~"^x"]}` must reject a later `x1` (matches
`#B`'s pattern but not `#A`'s `{a}` allowed-set) — the merged `fields` list over-approximates
each clause's own field-set, so per-clause field-labels are required.

### The fix — `closedClauses : List ClosedClause` (provenance, illegal-states-unrepresentable)

Replaced `closingPatterns : List Value` on `Value.struct` with `closedClauses : List
ClosedClause`, where `ClosedClause = {fieldLabels : List String, patterns : List Value}` is
ONE closed conjunct's allowed-set. A field is admitted iff it `ignoresClosedness` OR EVERY
clause admits it (`label ∈ clause.fieldLabels` OR matches one of `clause.patterns`). An empty
clause list = open. Invariant (enforced in `mkStruct`): `closedClauses = [] ↔ open`; a closed
struct ALWAYS carries ≥1 clause (even `close({})` → one all-empty clause, admitting nothing).
A self-closed struct gets one clause `{fields.map .label, patterns.map .fst}`; a meet
CONCATENATES the conjuncts' clauses (the conjunction). This is exactly the provenance the
CUE closedness guide mandates ("you will likely need provenance: which conjuncts introduced
which patterns and closedness constraints").

- `Value.lean`: new mutual-block `structure ClosedClause`; `struct` ctor field renamed/retyped;
  `mkStruct` default = single self-clause when closed, `[]` when open; `dedupClauses` /
  `canonicalizeClause` / `dedupStrings` / `ClosedClause.mapPatterns` helpers.
- `Lattice.lean`: `fieldAllowedByClauseWith` (one clause), `fieldAllowedByClausesWith`
  (conjunction = `all`), `applyClausesWith` (single pass); `mergeStructN` now threads
  `leftClauses`/`rightClauses`, carries `bothClauses = leftClauses ++ rightClauses` forward,
  and applies the conjunction at the meet (replacing the two sequential per-side passes).
- `Builtin.lean` `closeValue`: idempotent on an already-closed struct (returns it unchanged —
  must NOT collapse a meet-result's clauses to a single self-clause); only OPEN structs get
  the default self-clause.
- `Eval`/`Resolve`/`Normalize`/`Module`: recursion sites map over each clause's `patterns`
  (via `ClosedClause.mapPatterns`); the `Normalize` closed-no-pattern arm routed through
  `mkStruct` (was a raw `.struct … []`, now clause-less-closed is unconstructable).

### Tests (17 `native_decide` pins + 1 fixture pair) + verify

`StructTests` `### SC-1b` (12 source-level `exportJson{Bottoms,Matches}`): disjoint-pattern
one-sided reject (both directions), overlapping-pattern double-match admit, narrower-pattern
broad-only reject, field-only-clause reject (CRUX), broad-then-narrow reject+admit, 3-way
associativity, nested closedness, direct-meet-disjoint-required bottom, `close()`-idempotence,
closed-empty reject. `LatticeTests` `### SC-1b` (5 clause-logic units): `fieldAllowedByClausesWith`
is conjunction (`all` not `any`) — single-match reject, double-match admit, field-clause reject,
empty=open, ignoresClosedness escape. Fixture pair `definitions/sc1b_closed_pattern_intersection`.
All migrated existing closedness pins (`Struct`/`Lattice`/`Builtin`/`Module`/`Parse`Tests) updated
for the clause representation. Every case oracle-confirmed vs cue v0.16.1.

Gate: `lake build` green (108 jobs); `scripts/check-fixtures.sh` → `fixture pairs ok` (zero drift +
the new SC-1b pair); `shellcheck` clean (no shell touched); **cert-manager export SEMANTICALLY
identical to cue** (closedness is the def-meet hot path — prod9 uses closed defs heavily). No
`cue-divergences.md`/`cue-spec-gaps.md` change (Kue now MATCHES cue; the spec mandates the
provenance, so no gap).

### Newly diagnosed during this slice: SC-1e (closed × open-`...`) — pre-existing, NOT fixed

A CLOSED struct met with an OPEN-via-`...` struct must STAY closed (the `...` from the open
operand does not re-open the closed conjunct — monotonicity). cue rejects `#A:{[=~"^x"]} &
{b:1, ...}`'s `b`; Kue admits (verified against the `f0613e5` baseline → PRE-EXISTING, not an
SC-1b regression). Root: the B2.5 tail×patterns arm in `mergeStructN` produces a
`defOpenViaTail` result with empty clauses, dropping the closed operand's clause. Two closed
structs never reach that arm (closed ⇒ no tail), so it is strictly closed×open-tail, disjoint
from SC-1b. Filed in audit § SC-1e with a fix sketch (when either operand is closed, produce a
closed no-tail result carrying `bothClauses`; the open `...` is vacuous against closedness).
Its own slice. **Audit counter = 2 (RESID-MASK-2 = 1, SC-1b = 2); two-phase audit DUE after
this.**

## Completed Slice: SC-1e — closed × open-`...` keeps closedness (monotonicity) + EMBED-CLOSE-1 pin (2026-06-21)

**The closedness family is now FULLY CLOSED** (SC-1/1b/1c/1d/1e + SC-2 all DONE; EMBED-CLOSE-1
pinned). cue is CORRECT here; kue was wrong (re-opened a closed struct).

### The bug — broader than the single-arm diagnosis

A CLOSED struct met with an open-`...` partner wrongly re-opened: the result admitted fields the
closed operand forbids and emitted a trailing `...`. Witness `(#A & #B) & {x1: 5, ...}` with
`#A: {[=~"^x"]}`, `#B: {[=~"^y"]}` → kue admitted `x1` (cue rejects `field not allowed`); the
no-`...` control already rejected. Root: every tail-bearing arm of `mergeStructN` hardcoded
`mkStruct … .defOpenViaTail (some tail) []`, passing `closedClauses = []` and DROPPING
`bothClauses`. The phase-B breadcrumb diagnosed only the tail×patterns CATCH-ALL arm (1009),
because its pattern-closed witness routed there. **Instrumenting found the bug is wider:** a
FIELD-closed def (`#C: {a: int}`, no patterns) routes through the `struct × structTail` arm
(`none, [], some tail, []`) — `#C & {a:1, b:2, ...}` admitted `b` (cue rejects). Arms 2, 3, AND
the catch-all all dropped the clause; arm 4 (tail×tail) is safe (both operands open ⇒
`bothClauses = []`). Recorded as a refinement to the audit diagnosis (single-arm → all-tail-arms).

### The fix — one `closeTailResult` helper, driven by `closedOpenness`

`StructOpenness.meet` already computes the result openness correctly (`defClosed` dominates
`defOpenViaTail`), so the fix needs no new openness logic — only to USE it. Added a local
`closeTailResult (mergedFields) (tail) (patterns)` in `mergeStructN` that branches on
`closedOpenness.isOpen`:
- **open** (every operand open, `bothClauses = []`): keep the open tail —
  `mkStruct mergedFields closedOpenness (some tail) patterns []`.
- **closed**: collapse to a closed no-tail result —
  `mkStruct (applyBothClosedness mergedFields) closedOpenness none patterns bothClauses`. The
  partner's bare `...` is vacuous against a closed allowed-set; forbidden extras become `_|_` via
  `applyBothClosedness` (= `applyClausesWith bothClauses`), exactly as the no-`...` control does.

All four tail arms (2/3/4/catch-all) route through the single helper — the carry rule lives in
one place (DRY at a meaningful name: "finalize a tail-bearing meet honoring closedness
monotonicity"). The `closedClauses = [] ↔ open` invariant holds: the open branch passes `[]` with
an open openness, the closed branch passes `bothClauses` (non-empty when a closed operand is
present) with `defClosed`. `Lattice.lean:907-922` (helper) + the four arm callsites.

### EMBED-CLOSE-1 — pin-only, no code change

kue already rejects `y1 ∉ #A`'s `^x` in BOTH the embed form `{#A, y1}` and the meet form
`#A & {y1}` (closedness preserved through embedding — monotone, same theme). cue self-contradicts
(admits the embed form, rejects the meet form; `cue-divergences.md` row already filed by phase-A,
now `pinned`). Neither form carries a `...`, so the SC-1e tail fix leaves them untouched; the pins
LOCK the existing-correct rejection against a future closedness regression.

### Tests (9 `native_decide` pins + 4 fixture pairs) + verify

`StructTests` `### SC-1e` (7 end-to-end `exportJson{Bottoms,Matches}`): pattern-closed reject
(witness) + admit-allowed, field-closed reject (arm 3, the wider bug) + admit-allowed,
reversed-arm reject, open×open-`...` stays-open REGRESSION. `### EMBED-CLOSE-1` (2 pins): meet-form
+ embed-form reject. Fixture pairs `definitions/sc1e_closed_open_tail_rejects`,
`sc1e_closed_open_tail_admits`, `sc1e_field_closed_open_tail_rejects`, `embed_close1_pin` (each
with a FixturePorts Lean port). Every case oracle-confirmed vs cue v0.16.1.

Gate: `lake build` green (108 jobs); `scripts/check-fixtures.sh` → `fixture pairs ok` (zero drift +
4 new pairs); `shellcheck` n/a (no shell touched); **cert-manager export semantically = cue AND
byte-identical to the pre-fix HEAD baseline** (worktree-compared — the fix is a pure no-op on that
workload, which has no closed×open-`...` meet, confirming the change is surgical). One
`cue-divergences.md` row updated to `pinned` (EMBED-CLOSE-1); no new divergence/gap (kue MATCHES cue
on SC-1e; cue is correct there).

## Completed Slice: AD2-1 — disjunction-normalizer lone-arm rule UNIFIED (lone-default marker is vacuous) (2026-06-21)

Resolved the last walker/normalizer-dedup member by SOUNDNESS ANALYSIS (the prior audits
deferred it as "USER-GATED", over-cautious about a pin rename — the real question was
autonomous). **Verdict: the lone-default lattice-marker is NON-load-bearing (vacuous).**

The two disjunction normalizers differed only on the lone-arm rule: `normalizeEvaluatedDisj`
(eval path) collapses a lone arm mark-agnostically (`*v`-lone → `v`); `normalizeDisj`
(lattice/meet path) kept a lone DEFAULT arm as `*v`. The question: is a lone-default node
ever distinct in VALUE from the bare value in any meet chain?

**Proof (no, never).** A lone default has no alternative, so the mark is vacuous — a default
among one option IS that option. The mark cannot leak in the meet algebra: `combineMark` is
AND (a result arm is default iff BOTH crossed inputs were), and `withDefaultConvention` only
synthesizes a default set for an operand with NO `*` at all. So a lone `*v` met with a real
default never beats it nor manufactures a spurious one. Lean-level cross-check across the
mark algebra: `meet (*1-lone) rhs == meet 1 rhs` for `rhs ∈ {1|2, *1|2, *2|1, *1|*2, int, 1,
2|3}` — every case value-identical (the structural differences are exactly the cases where
the lone node keeps a `.disj [(.default, v)]` wrapper that `resolveDisjDefault?` yields `v`
from). Sharpest witness: `*1`-lone `& (*2|1)` → `1`, NOT `2` (the vacuous default does NOT
win against the real `*2`). Adversarial oracle cross-check vs cue v0.16.1: residual-lone-
default met onward (default-containing / -absent / marked / conflict-marked / nested) — every
`export` byte-identical, and cue's *display* also collapses the lone `*v` → `v`, so the fix
moves Kue TOWARD cue.

FIX: `normalizeDisj`'s lone-arm collapse is now mark-agnostic (`[(_, value)] => value`),
matching `normalizeEvaluatedDisj`. The eval path keeps its `joinValues` all-regular branch
(a genuinely distinct subsumption op — `int | 1` → `int`), so it is NOT folded wholesale;
only the divergent lone-arm rule is unified. The two now agree on every lone-arm case.

Tests: two named pins RENAMED to the corrected behavior
(`meet_disjunction_collapses_vacuous_lone_default` in `Tests.lean`,
`lattice_meet_disjunction_collapses_vacuous_lone_default` in `LatticeTests.lean`) — the old
names (`*_preserves_default_marker`) were pinning the display artifact, not a soundness
property. Added non-load-bearing witnesses in `LatticeTests`:
`lattice_lone_default_vacuous_vs_plain_disj`, `_loses_to_real_default` (the sharp `*2|1`
case), `_vs_kind_and_scalar`, and `lattice_multi_arm_default_marker_preserved` (the boundary:
a MULTI-arm default mark IS load-bearing and must NOT be over-collapsed).
`TwoPassTests.embed_disj_live_default_kept` expected display updated (lone-default residual
`*{kind:"a",v:1}` → `{kind:"a",v:1}`, now matching cue).

Spec record: SC-3 / `cue-spec-gaps.md` D#2b/SC-3 row scope narrowed — the "keep marked
disjunction in eval display" contract now applies ONLY to MULTI-arm live defaults (where the
mark IS load-bearing). The lone-default half is gone (collapsed, matches cue). No new
divergence.

Gate: `lake build` green (108 jobs), axiom-clean (standard `propext`/`Classical.choice`/
`Quot.sound` + `native_decide` reflection); `scripts/check-fixtures.sh` → `fixture pairs ok`
(byte-identical — NO fixture display changed, since none currently render a lone-default
residual); `shellcheck` n/a (no shell touched); adversarial export sweep vs cue v0.16.1 all
MATCH; cert hot-path (`multiline_cert`) unchanged. The walker/normalizer-dedup family is now
FULLY CLOSED (AD4-1 + A-EN3 DONE, DRY-1 ruled out, AD2-1 resolved).

## Completed Slice: BI-2-residual — math.Sqrt + math.Pow(·, ½) in EXACT DECIMAL (Float avoided) (2026-06-21)

Goal: implement the math builtins that previously BOTTOMED — `math.Sqrt` and the fractional
`math.Pow(·, ½)` — WITHOUT introducing Float/NaN/Infinity. The prior BI-2 slice filed this as
"needs a Float/NaN/Infinity model"; that framing was WRONG. Kue is exact-rational by design, so
the principled move is to compute in EXACT DECIMAL and record the divergence from cue's fallible
float artifacts. SPLIT: sqrt + Pow-½ SHIPPED; the general negative/non-½ fractional Pow (needs
`decimalExp`/`decimalLn`) is filed-with-design as the residual-of-the-residual.

**The reframe (settled, not re-litigated).** cue's `math.Pow` already uses a 34-digit apd DECIMAL
context for the ½ exponent (`Pow(2,0.5) = 1.414…209698`), so Kue matches it in decimal. cue's
`math.Sqrt` uses float64 (`Sqrt(2) = 1.4142135623730951`, only 17 digits) — a fallible ARTIFACT:
inside cue, `Sqrt(2) ≠ Pow(2, ½)` (two numeric libraries for the same operation — cue is
INTERNALLY INCONSISTENT). Kue is CONSISTENT: `Sqrt(x) = Pow(x, ½)` computed in decimal. The
low-digit + scientific-notation divergence (`Sqrt(100)`: cue `1e+1`, Kue `10`) is recorded as a
kue-MORE-correct divergence. `Sqrt(neg)`/`Pow(neg, ½)` BOTTOM (real-domain/complex error) instead
of cue's `NaN` — an exact-rational lattice has no `NaN`/`Infinity` element to manufacture.

**`Decimal.sqrt` design (totality via FIXED iteration count — the key trick).** `isqrtNewton`
(`Kue/Decimal.lean`): integer Newton `x' = (x + N/x)/2` on `Nat`, iterated a FIXED `fuel` times —
structurally recursive on `fuel`, so total with NO `termination_by` and NO `partial`. From an
over-estimate seed `10^⌈d/2⌉` (`d` = decimal digit count, always ≥ √N since N < 10^d), the iterate
decreases monotonically to `⌊√N⌋` then may bounce up by one; a running `best` MINIMUM captures the
exact floor regardless. `isqrtNat` budgets `2·d + 8` iterations — dwarfs the ~log₂(bits) Newton
needs at its quadratic rate, scales with the input (no fixed-magic ceiling), and over-iterating is
harmless (best is monotone). Verified EXACT (`r² ≤ N < (r+1)²`) exhaustively on 0..5000 and on the
34-sig-digit scaled inputs. `decimalSqrt`: for `a = num/10^s`, `√a = ⌊√(num·10^(2P−s))⌋/10^P` with
`P = max(40, ⌈s/2⌉)` (the `max` keeps `2P ≥ s` even for a deeper-than-guard input fraction).
Perfect squares (`r² = radicand`) → exact `r/10^P` collapsed to int via `collapseDecimalToValue`
(`Sqrt(144)=12`, `Sqrt(2.25)=1.5`); irrationals → 34 sig digits round-half-up via the shared
`divideDecimalRational?` (DRY — reuses the existing division renderer, so the precision context is
the SAME 34-digit one as `/`). `Sqrt(2)=1.414…209698` is BYTE-IDENTICAL to cue's apd `Pow(2,0.5)`,
`Sqrt(3)`/`Sqrt(5)` match `bc` to 34 sig figs.

**Wiring (`Kue/Builtin.lean`).** `decimalSqrtSigned` (negative → `.bottom`, else `decimalSqrt`)
is SHARED by `math.Sqrt` (`mathSqrt?`) and `mathPow?`'s ½-route (`isHalfExponent`: `2·num =
10^scale`, so `0.5`/`0.50`/… all qualify), so `Sqrt(x)` and `Pow(x, ½)` are the IDENTICAL value by
construction. `math.Sqrt` arm added to `evalMathBuiltin` (dispatch is by `math.` prefix — no name
registration needed). `Pow(neg, ½)` bottoms (complex). General neg/non-½ fractional exponents still
return `none` → bottom (the open residual).

**Axiom-clean / totality confirmed.** `#print axioms` on `decimalSqrt`/`isqrtNat`/`mathSqrt?`/
`mathPow?`/`evalMathBuiltin` → only `[propext, Classical.choice, Quot.sound]` (the standard Lean
axioms); `isqrtNewton`/`isHalfExponent` depend on NO axioms. NO `sorryAx`, NO `partial` — the
fixed-iteration functions elaborated as fully total.

**Tests (17 `BuiltinTests` pins + 1 fixture, 14 cases).** Sqrt: perfect-square→int (4→2, 144→12),
`Sqrt(100)=10` (NOT `1e+1`), `Sqrt(0)=0`, `Sqrt(1)=1`, `Sqrt(2)`/`Sqrt(5)` 34-digit pinned,
`Sqrt(2.25)=1.5`, `Sqrt(-1)→bottom`, type-mismatch→bottom, abstract-arg stays unresolved. Pow-½:
`Pow(2,½)=Sqrt(2)` (34-digit), `Pow(4,½)=2` (collapse), `Pow(-2,½)→bottom`. Consistency:
`math_sqrt_equals_pow_half` pins `Sqrt(2) == Pow(2, 0.5)` (cue's do NOT agree). The two prior
residual-bottom pins were retargeted: `Pow(2,0.5)` now equals √2 (positive pin); the still-deferred
bottoms are `Pow(2,-3)` (general neg) and `Pow(2,0.25)` (non-½ fractional). Fixture
`builtins/math_sqrt` (`.cue` + `.expected` + `FixturePorts` port) drives all 14 through the full
parse→resolve→eval path on BOTH the CLI and the Lean port. The `.expected` holds KUE's values (the
harness compares Kue↔Kue, never Kue↔cue), so the float-Sqrt divergence is captured as Kue's.

**Divergences / spec gaps recorded.** `cue-divergences.md`: (a) `math.Sqrt` exact decimal vs cue's
float64 (Kue more precise + self-consistent; cue `Sqrt ≠ Pow(·,½)`); (b) `Sqrt(neg)`/`Pow(0,neg)`
→ Kue bottoms vs cue `NaN`/`Infinity` (float artifacts, not lattice elements). `cue-spec-gaps.md`:
the BI-2 Pow precision-model row extended to cover Sqrt (precision/format spec-silent; exactness +
self-consistency is the principled choice; general fractional tail deferred).

**Open residual (filed with design).** General negative/non-½ fractional `Pow` + `Pow(0,neg)`:
`x^y = exp(y·ln x)` via `decimalExp`/`decimalLn` (fixed-term Taylor + argument reduction — both
total, NO Float). Negative-INTEGER exponents are a cheaper sub-increment (`x^(-n) = 1/x^n` via
existing exact int-pow + division renderer, no exp/ln). See `spec-conformance-audit.md`
BI-2-residual entry for the full design. No real app needs it.

**Verify.** `lake build` green (108 jobs; all pins checked at build); `check-fixtures.sh` →
`fixture pairs ok` (zero drift; 1 new pair on both CLI + Lean-port paths); `shellcheck` n/a (no
shell touched). Additive at the builtin layer (only `math.Sqrt`/`Pow(·,½)` newly resolve; cert-
manager/argocd use neither) — cannot regress real-app output.

Files: `Kue/Decimal.lean` (`decimalDigitCount`, `isqrtNewton`, `isqrtNat`, `sqrtGuardScale`,
`decimalSqrt`), `Kue/Builtin.lean` (`decimalSqrtSigned`, `mathSqrt?`, `isHalfExponent`, `mathPow?`
½-route, `math.Sqrt` arm + deferral docstring), `Kue/Tests/BuiltinTests.lean` (17 pins),
`Kue/Tests/FixturePorts.lean` (math_sqrt port), `testdata/cue/builtins/math_sqrt.{cue,expected}`,
`docs/reference/cue-divergences.md` (2 rows), `docs/reference/cue-spec-gaps.md` (Pow/Sqrt row),
`docs/spec/spec-conformance-audit.md` + `docs/spec/plan.md` (BI-2-residual SPLIT, "USER-GATED"
dropped, Float-avoided noted).

## Completed Slice: BI-2-§3 — general math.Pow (neg-int + non-½ fractional) in EXACT DECIMAL (2026-06-21)

**What.** Closed the BI-2 family. `math.Pow` now covers its FULL real domain in exact-precision
decimal, no `Float`. Two sub-increments:

- **§1 negative-INTEGER exponent** — `x^(-n) = 1 / x^n`, an EXACT rational. `reciprocalDecimalToValue`
  computes `1/p` over `decimalPowNat`'s result (`1/(pn/10^ps) = 10^ps / pn`): collapses to `int`
  when whole (`Pow(1,-5)=1`), renders the exact terminating expansion (`Pow(2,-3)=0.125`,
  `Pow(10,-2)=0.01`), else 34 sig digits (`Pow(3,-1)=0.333…333`). `Pow(0,neg)` → bottom.
- **§2 general non-½ fractional exponent** (`x>0`) — `x^y = exp(y·ln x)`. New decimal transcendentals
  in `Decimal.lean`, all scaled-`Int` at working scale 50 (16 guard digits past the 34-sig render
  context): `decimalLnScaled` range-reduces `x = m·2^k`, `m ∈ [⅔,4/3)`, `ln x = k·ln2 + ln m`,
  `ln m = 2·artanh((m−1)/(m+1))` as a FIXED 40-odd-term series; `decimalExpScaled` range-reduces
  `z = n·ln2 + r`, `|r| ≤ ln2/2`, `exp z = 2ⁿ·exp r`, `exp r = Σ rᵏ/k!` as a FIXED 60-term series
  (running factorial threaded). Result rounds to 34 sig digits and collapses to `int` when integral
  (`Pow(4,1.5)=8`, `Pow(8,⅓)=2`). ½ still routes through `decimalSqrt`.

**Totality / axioms.** Both series and both binary range-reduction loops run a FIXED budget ⇒
structurally recursive, total, no `partial`/`sorry`. `#print axioms` confirms
`decimalExpScaled`/`decimalLnScaled` depend on ZERO axioms; the full Pow path only on
`propext`/`Quot.sound`/`Classical.choice` (standard String/Int lemmas — no `sorryAx`).

**Precision / cross-check.** Mantissa byte-identical to cue's apd `Pow` across the corpus: 40 random
fractional cases + extreme magnitudes (`Pow(0.000000001,0.25)`, `Pow(123456789,0.7)`,
`Pow(1.0000001,0.5)`) all mantissa-exact. `Pow(2,0.5)` via the sqrt route equals `Sqrt(2)`
(self-consistency cross-check holds). `Pow(2,0.25)=1.189…476`, `Pow(2,0.1)=1.071…342` — exact match.

**Domain edges → bottom** (no `NaN`/`Infinity` — exact-rational lattice has no float specials):
`Pow(neg, non-integer)` (complex; cue errors), `Pow(0,0)`, `Pow(0,neg)` (cue → `Infinity`).
`Pow(0,positive)=0`.

**Divergences.** `cue-divergences.md` new row: cue's apd PADS terminating expansions to fixed width
and uses Go scientific notation for small/large magnitudes; Kue trims + renders plain (value-identical,
same family as `Sqrt(100)=10` not `1e+1`). `cue-spec-gaps.md` BI-2 Pow row extended (clause (c)):
the exp/ln 34-sig precision choice is spec-silent — match cue's apd context, render exact-rational.

**Verify.** `lake build` green (108 jobs; all pins checked at build); `check-fixtures.sh` →
`fixture pairs ok` (zero drift; 11 new `math_pow` cases on both CLI + Lean-port paths);
`shellcheck` n/a (no shell touched). Additive at the builtin layer — cannot regress real-app output.

Files: `Kue/Decimal.lean` (`lnExpScale`/`lnExpUnit`/`ln2Scaled`/`mulScaled`/`divScaled`/`lnSeriesTerms`
/`lnArtanhSeries`/`lnMantissa`/`lnRangeReduce{Up,Down}`/`lnRangeReduceFuel`/`decimalLnScaled`
/`expSeriesTerms`/`expTaylorSeries`/`applyPow2Scaled`/`decimalExpScaled`/`intSigDigits`
/`roundScaledToSigDigits`/`decimalPowGeneral`), `Kue/Builtin.lean` (`reciprocalDecimalToValue`,
rewired `mathPow?`), `Kue/Tests/BuiltinTests.lean` (13 pins), `Kue/Tests/FixturePorts.lean`
(math_pow port +11), `testdata/cue/builtins/math_pow.{cue,expected}`,
`docs/reference/cue-divergences.md` (1 row), `docs/reference/cue-spec-gaps.md` (Pow row clause c),
`docs/spec/spec-conformance-audit.md` + `docs/spec/plan.md` (BI-2 family COMPLETE). Commit `cd2f0a9`.

---

## Completed Slice: EvalOps extraction — carve pure scalar algebra out of Eval.lean (2026-06-22)

Goal: a behavior-preserving module split (plan item 2). Carve the self-contained pure scalar
algebra out from under the recursive evaluator into a new `Kue/EvalOps.lean`, shrinking
`Eval.lean` and giving the scalar ops a clear home below `Eval`.

**What moved (verbatim, no logic change).** `ArithOperandClass` + `classifyArithOperand`
+ `arithmeticDomainResult` + `evalRepeat` + `evalAdd`/`evalSub`/`evalMul`/`evalDiv`; and
`collapseDefaultDisjunction` + `evalEq`/`evalNe` + `charsLt`/`stringsLt`
+ `evalPrimitiveOrdering` + `evalRegexMatch`/`evalRegexNotMatch` + `evalIntKeywordBinary`
+ `evalBoolBinary`/`evalBoolNot` + `negateFloatText` + `evalNumPos`/`evalNumNeg`
+ `evalUnary`/`evalBinary` + `resolveOperand` + `distributeUnary`/`distributeBinary`.

**Extraction premise verified.** The carve set sits entirely ABOVE the evaluator's `mutual`
block — none of these functions back-edge into `evalValueWithFuel`. They take already-evaluated
`Value` operands and decide scalar results. Confirmed independent of the
`classifyDefinedness`/`classifyGuard`/`classifyDynLabel`/`evalPresenceTest` classifier block
(801–1016 in the old file), which is NOT scalar algebra and STAYS in `Eval.lean`.
`resolveDynLabelDefault` stays in `Eval.lean` and now reaches `collapseDefaultDisjunction`
through the import.

**Import-shape decision — option (a): `EvalOps` imports `{Builtin, Decimal, Regex}`.** The
ops call `divValue`/`modValue`/`quoValue`/`remValue`, which live in `Builtin.lean`. Option (b)
(move those four into EvalOps so it imports only `{Value, Decimal}`) was REJECTED: the four
ALSO back the `div`/`mod`/`quo`/`rem` builtins at `Builtin.lean:892`, so relocating them would
force a NEW `Builtin → EvalOps` edge — strictly worse than `EvalOps → Builtin` (they are
genuinely Builtin-owned, not Eval-private; option (b)'s premise was wrong). Graph stays acyclic:
`EvalOps → {Builtin, Decimal, Regex}`, and nothing those import reaches back to EvalOps (build
ordering confirms: Builtin → EvalOps → Eval).

**Tests — 18 `native_decide` pins ADDED** (`EvalTests.lean`), closing a real coverage gap: the
comparison ops (`evalPrimitiveOrdering` via `evalBinary .lt/.le/.gt/.ge`), `evalEq`/`evalNe`,
the boolean ops, and unary negation/not previously had ONLY end-to-end fixture coverage (no
direct function-level pin except two `evalEq` in `PresenceTests`). New pins cover the edge cases
the slice flagged: comparison on incomparable kinds (`int < "a"` → bottom; cue: `invalid
operands`), bool unordered (`true < false` → bottom), `&&` over a non-bool prim → bottom, unary
`!` on a non-bool → bottom, unary `-` on a non-numeric → bottom, plus the incomplete-operand
defer for both binary and unary. Cross-checked the bottom cases against `cue` v0.16.1 (all error,
Kue agrees). The div/mod/quo/rem direct pins already in `BuiltinTests.lean` (neg-operand,
incomplete-defer, kind-conflict, div-by-zero) stay valid (ops unmoved).

**Behavior-preserving.** No logic edited — only relocated. All pre-existing `native_decide`
pins + every fixture stay green; pin-count conserved (an org move, +18 new edge pins on top).
No divergence introduced (`cue-divergences.md` unchanged); no spec gap hit
(`cue-spec-gaps.md` unchanged).

**Verify.** `lake build` green (110 jobs, no new warnings/errors, no `sorry`/axiom);
`check-fixtures.sh` → `fixture pairs ok` (zero drift); `shellcheck` n/a (no shell touched).

`Eval.lean` 3701 → 3377 (−324). Files: `Kue/EvalOps.lean` (new, 346),
`Kue/Eval.lean` (carve removed + `import Kue.EvalOps`), `Kue.lean` (register `Kue.EvalOps`),
`Kue/Tests/EvalTests.lean` (18 pins), `docs/spec/plan.md` (item 2 DONE),
`docs/notes/` (breadcrumb rotated).

---

## Completed Slice: import-eager-closedness — eager selector closes a selected def body (single source of truth) (2026-06-22)

**The soundness bug (SILENT-ADMIT).** An imported plain closed def (`#Closed`), selected via
the EAGER selector path and met with an undeclared field, SILENTLY ADMITTED the extra. The force
path closed correctly, so the two paths DISAGREED about closedness — the eager path was unsound.
Reproduced on a clean pre-fix binary (`out: lib.#Closed & {extra}` exported all fields incl.
`extra`; cue v0.16.1 rejects `extra: field not allowed`).

**Root cause.** An imported package's def bodies are NOT closed at load: `bindImports`
(`Module.lean`) tags the package `.importBinding`, and `normalizeFieldWithFuel`'s `.importBinding`
arm SKIPS a bound package wholesale (deliberately — recursing it would re-close UNREFERENCED
nested defs and re-bottom cert-manager/argocd; the A2 trap). So a bound package's def bodies sit
UNCLOSED (`regularOpen` as stored). The force path compensated: `importDefClosureBody?` /
`refDefClosureBody?` run the plucked body through `normalizeDefinitionValueWithFuel` — but ONLY
when the def has a sibling self-ref (`bodyNeedsDefer`), the deferral trigger. A plain self-ref-free
closed def took the EAGER fallback (`selectEvaluatedField base label`), which plucked
`Field.value field` RAW — open. The meet then admitted extras (and never consulted the def's own
patterns).

**INCOMPLETE-MASK facet.** With an ABSTRACT def (`port: int`), the pre-fix open body also masked
the violation behind incompleteness: an open struct accepts the extra outright, and an export saw
only the `incomplete value: int`. Closedness is structural (not gated on concreteness), so the
violation must fire regardless — and post-fix it does (the field is `.fieldNotAllowed`); only the
error *message* still leads with the incompleteness it reaches first (a recorded display-only
cue-divergence — value agrees).

**Fix chosen — option (b), structurally unified (NOT two paths patched to agree).** Routed every
eager pluck through a NEW single function `selectedFieldValue (field : Field) : Value` (`Eval.lean`):
a DEFINITION field's body is closed with `normalizeDefinitionValueWithFuel normalizeFuel`; any
other field is yielded raw. All four pluck sites in `selectEvaluatedField` (struct, embeddedList,
and both disjunction-default arms) call it. This makes the SINGLE closing decision the force path's
producers ALREADY use the one the eager path uses too — the two paths CANNOT disagree about
closedness because they share the rule, not because they were tuned to coincide. Option (a) (close
imported def bodies at load) was REJECTED: it is the A2 trap — closing the whole bound package
re-closes unreferenced nested defs (the precise reason `normalizeFieldWithFuel`'s `.importBinding`
arm skips it). Option (b) closes ONLY the def that is actually selected and used, never the
package, so the trap cannot fire (cert-manager/argocd cross-package fixtures byte-identical:
`crosspkg_defmeet`/`alias_import_selector`/`dup_import_binding` all MATCH).

**Soundness properties.** Closing is IDEMPOTENT for a same-file def (already closed at load —
`normalizeDefinitions` closes a top `#` field) and LOAD-BEARING for an imported one. It does NOT
over-close: a `...` / `defOpenViaTail` body is returned UNCHANGED by
`normalizeDefinitionValueWithFuel`, so an open def keeps admitting use-site fields; a closed
PATTERN-bearing def keeps its patterns into `closedClauses` so the check consults them (match
admitted, non-match rejected). A NON-definition field stays raw (a regular field's struct value
stays open, as cue keeps it). `selectedFieldValue` depends only on `propext` — no `sorry`, no new
axiom.

**Tests (TDD — bug demonstrated FIRST on a clean pre-fix binary).** 7 `native_decide` pins in
`ClosureTests.lean` `### import-eager-closedness`: 2 UNIT (`selected_field_value_closes_definition`,
`…_leaves_regular_open`); FACET 1 silent-admit (`eager_closed_import_def_rejects_extra` — concrete,
`extra` → `.fieldNotAllowed`, `defClosed`); FACET 2 incomplete-mask
(`…_rejects_extra_when_abstract` — closedness fires despite abstract fields); OVER-CLOSE GUARD
(`eager_open_import_def_admits_extra` — `...` def stays open); PATTERN EDGE admit + reject
(`eager_closed_pattern_import_def_admits_match` / `…_rejects_nonmatch`). Updated 1 pre-existing pin
(`closure_producer_skips_selfref_free_def`) whose expected `regularOpen` ENCODED the old bug → now
`defClosed`. 2 module fixtures (`testdata/modules/import_open_def_addfield`,
`import_closed_def_pattern`) pin the over-close guard + pattern-admit end-to-end through the real
import loader (both byte-identical to cue; the rejection facets live in the pins, mirroring
`def_open_tail_addfield`'s convention — eval mode emits `extra: _\|_` and exits 0, so an error
fixture cannot witness a field-level closedness bottom). All oracle-confirmed vs cue v0.16.1.

**1 cue-divergence recorded** (incomplete-mask error-message selection — value agrees, both
bottom). No spec gap (closed-def-rejects-extra is core CUE closedness; spec is clear).

**Verify.** `lake build` green (110 jobs, no new warning/`sorry`/axiom); `check-fixtures.sh` →
`fixture pairs ok` (zero drift; 2 new module fixtures are expected additions); `shellcheck` n/a
(no shell touched). Files: `Kue/Eval.lean` (`selectedFieldValue` + 4 pluck sites),
`Kue/Tests/ClosureTests.lean` (7 pins + 1 corrected), `testdata/modules/import_open_def_addfield/`
+ `import_closed_def_pattern/` (new), `docs/reference/cue-divergences.md` (1 row),
`docs/spec/spec-conformance-audit.md` + `docs/spec/plan.md` (resolved), `docs/notes/` (breadcrumb).

---

## Completed Slice: TL-1 — closed `BuiltinFamily` enum replaces stringly-typed builtin dispatch (2026-06-22)

**The smell (illegal-state-made-representable + a masked error).** `evalBuiltinCall`
dispatched the builtin FAMILY axis off a bare `String`: an 8-way exact-name match
(`close`/`len`/`and`/`or`/`div`/`mod`/`quo`/`rem`) then a 7-way `name.startsWith "strings."/…`
prefix chain, **falling through to a silent `.builtinCall name args` residual** when nothing
matched. A name with no recognised family (`foobar.Baz`, `nosuchfn`, the real-but-unimplemented
`error("…")`) — even with fully CONCRETE args — produced an inert residual (manifested as
`incomplete value: …`) instead of an error. That fall-through is an unknown/misclassified family
made representable, and it masked a CUE resolution error as incompleteness.

**The enum (FAMILY axis closed; LEAF stays `String`).** New `BuiltinFamily` in `Builtin.lean`
(the only consumer — no new import edge): `core` (the 8 exact unqualified builtins) +
`strings`/`list`/`math`/`regexp`/`base64`/`json`/`yaml` (the 7 qualified stdlib packages). The
within-family leaf (`math.Pow`, `strings.ToUpper`) stays a `String` — genuinely many-valued,
still string-dispatched inside each `eval*Builtin`. The family axis IS a closed, versionable set,
so it earns a sum type; the leaf is not, so it does not.

**Classification point + exhaustive dispatch.** A single total classifier
`BuiltinFamily.ofName? : String → Option BuiltinFamily` interprets the name at the one place it
is interpreted as a builtin (the parser CANNOT classify earlier — it cannot distinguish
`strings.X` from a user `pkg.X`; both parse to `.builtinCall`, and the family is only knowable
once the name is read as a builtin, i.e. in `evalBuiltinCall`). `evalBuiltinCall` now matches
`ofName? name` EXHAUSTIVELY — every `some family` has an arm, NO catch-all over `BuiltinFamily`
(a new family forces a new constructor → a missing-arm compile error at the dispatch site). The
8 `core` arms moved to a small `evalCoreBuiltin` (reached only for a `.core` classification; its
final arm is unreachable-by-contract and routes through `unresolvedOrBottom` to stay total).

**The unknown-builtin correction (soundness-adjacent — verified vs spec + `cue` v0.16.1).** The
`none` arm (genuinely non-builtin name) routes through `unresolvedOrBottom name args` — the SAME
concrete⇒bottom / pending⇒residual decision the in-family path already uses for an unknown LEAF
(`math.NoSuch`). So an unknown name with **concrete args now BOTTOMS** (was: silent residual),
and with ABSTRACT args still defers (a later pass may concretise it). This conforms to CUE: an
unknown member of a known package is `cannot call non-function … (type _\|_)` (bottom); an
unknown package / unqualified name is `reference … not found` (a resolution error). The
silent-admit was masking that error as incompleteness; making it bottom is strictly more correct.
Recorded as a **cue-divergence** (Kue bottoms with the generic `(bottom)` reason where `cue`
gives a NAME-SPECIFIC resolution message — value agrees, both reject) and a **spec-gap** (the
CUE spec does not prescribe the diagnostic for an unimplemented builtin name; lattice first
principles — an unresolved builtin is bottom, never a silent pass-through — decide it, and `cue`
agrees on the bottom verdict).

**Behavior-preserving for KNOWN builtins (how confirmed).** The pre-existing `BuiltinTests.lean`
net (≥1 representative `evalBuiltinCall` pin per family + the core ops, ~140 pins) is the
characterization net; it stays byte-identical green. Added a yaml-family representative
(`yaml.Marshal`, previously exercised only end-to-end through `FixtureTests`) so every family
`ofName?` classifies has a direct pin. End-to-end binary spot-checks: `strings.ToUpper`/`math.Pow`/
`len` unchanged; `foobar.Baz("a")` and `error("boom")` now bottom.

**Tests (TDD — corrected behavior asserted first, failed red on the old code).** 11 new
`native_decide` pins in `BuiltinTests.lean`: classifier contract (`core` names → `.core`; the 7
prefixes → their family; non-builtin / empty → `none`; prefix-not-leaf so `math.NoSuch`/`strings.`
classify to their package); THE FIX (`unknown_family_concrete_args_is_bottom`,
`unknown_unqualified_name_concrete_args_is_bottom`, `unknown_error_builtin_concrete_arg_is_bottom`);
edge preservation (`unknown_family_abstract_arg_stays_unresolved`, `unknown_family_bottom_arg_is_bottom`);
+ 2 yaml family pins.

**Verify.** `lake build` green (110 jobs, no new warning/`sorry`/axiom; `evalBuiltinCall` depends
only on `propext`/`Classical.choice`/`Quot.sound`); `check-fixtures.sh` → `fixture pairs ok`
(zero drift); `shellcheck` n/a (no shell touched). Files: `Kue/Builtin.lean` (`BuiltinFamily` +
`ofName?` + `evalCoreBuiltin` + rewritten `evalBuiltinCall`), `Kue/Tests/BuiltinTests.lean`
(13 pins), `docs/reference/cue-divergences.md` + `docs/reference/cue-spec-gaps.md` (1 row each),
`docs/spec/plan.md` + `docs/notes/` (resolved + breadcrumb).

---

## Completed Slice: TL-2 — `Depth`/`FieldIndex` newtypes replace bare `Nat` in `BindingId`

Type-leverage tightening (illegal-states-unrepresentable), behavior-preserving.
`BindingId` carried two bare `Nat` fields — `depth` (lexical frame offset) and `index`
(field slot) — orthogonal domains that compiled if transposed. A `⟨index, depth⟩` swap was
a type-correct bug the compiler could not catch.

**The fix.** Two single-field `structure`s in `Value.lean` (zero-cost erasure over `Nat`):

```
structure Depth where val : Nat   deriving Repr, BEq, DecidableEq
structure FieldIndex where val : Nat   deriving Repr, BEq, DecidableEq
instance : OfNat Depth n := ⟨⟨n⟩⟩
instance : OfNat FieldIndex n := ⟨⟨n⟩⟩
structure BindingId where depth : Depth; index : FieldIndex   deriving Repr, BEq, DecidableEq
```

`Depth` and `FieldIndex` are now DISTINCT nominal types — a `Depth` cannot be passed where
a `FieldIndex` is expected (verified: `BindingId.mk i d` with the args reversed is a
compile error). The transposition class is unrepresentable.

**Why `OfNat` (load-bearing).** The ~300 test sites construct `BindingId` via the
anonymous constructor `.refId ⟨0, 0⟩`. Lean does NOT auto-flatten numeric literals into
nested single-field structures (`⟨0, 0⟩` tries `0 : Depth` directly), so without
`OfNat Depth`/`OfNat FieldIndex` every literal would need rewriting to `⟨⟨0⟩, ⟨0⟩⟩`. With
the instances, `⟨0, 0⟩` elaborates as `⟨(0 : Depth), (0 : FieldIndex)⟩` and ALL existing
literals stay byte-identical — zero test churn for the literal sites. (`BEq Depth` +
`OfNat` also keep the literal comparisons `id.depth == 0` / `id.depth != 0` working
unchanged.)

**Boundary discipline (`.val`).** Consumers that need the raw `Nat` for frame arithmetic
(`env.drop id.depth.val`) or slot arithmetic (`nthField id.index.val`) unwrap with `.val`
at the call — the controlled, explicit boundary. No `Coe Depth Nat` (an implicit widening
would reopen the swap). `Hashable` was NOT derived: the one hash site (`valueDigest`)
hashes through `.val`, so a derived instance would be dead code.

**Sites touched (~57, all mechanical).** ONE construction site (`findInScopes` in
`Resolve.lean`, `⟨⟨depth⟩, ⟨index⟩⟩` — the sole producer of `BindingId` values). In
`Eval.lean`: 48 `.val` projection-unwraps across the resolver/def-deferral tier + core
`.refId` eval arm, and 2 reconstruction-wraps (`⟨id.depth, ⟨mergedIndex⟩⟩` in
`thisStructFieldIndex?`/the merge-remap).
`Format.lean`: the residual-`refId` render `s!"@{id.depth.val}.{id.index.val}"` (kept
byte-identical — without `.val` it would print `@{ val := 0 }.…`). Tests: 4 sites where a
COMPUTED `Nat` (`bodyDepth`/`clauseChainDepth`) feeds a `BindingId` literal or a `.depth`
comparison.

**Behavior-preserving (how confirmed).** `lake build` green (110 jobs, no new
warning/`sorry`/axiom); full suite (every `native_decide` pin compiles) green;
`check-fixtures.sh` → `fixture pairs ok`, zero drift; pin-count conserved (a pure type
tightening — no semantic change). No CUE divergence or spec gap surfaced (a mechanical
refactor shouldn't, and didn't).

**Pins added (5, `ResolveTests.lean`).** The transposition guard itself is COMPILE-time
(not a runtime `native_decide`), so the pins lock the surviving runtime contract:
`tl2_bindingId_literal_matches_explicit_mk` (the `OfNat` literal ≡ explicit
`.mk ⟨2⟩ ⟨5⟩`), `tl2_bindingId_val_roundtrips` (`.depth.val`/`.index.val` round-trip), and
the bug-class
witnesses `tl2_bindingId_swapped_coordinates_distinct` (`⟨2,5⟩ ≠ ⟨5,2⟩`) +
`tl2_depth_distinguishes_underlying_nat` / `tl2_fieldIndex_distinguishes_underlying_nat`.

**Verify.** `lake build` green; `check-fixtures.sh` zero drift; `shellcheck` n/a (no shell
touched). Files: `Kue/Value.lean` (newtypes + `OfNat` + `BindingId`), `Kue/Resolve.lean`
(construction), `Kue/Eval.lean` (~50 projection/reconstruction sites), `Kue/Format.lean`
(render), `Kue/Tests/ResolveTests.lean` (5 pins) + `Kue/Tests/TwoPassTests.lean`
(4 fixups),
`docs/spec/plan.md` + `docs/notes/` (DONE + breadcrumb).

---

## Completed Slice: scalar-embed-with-decls — `.embeddedScalar` carrier + B3 embedded-list iteration (2026-06-22)

**Goal.** Close two ride-along incompleteness gaps in the struct-embedding area, with a
hard soundness boundary: (1) `scalar-embed-with-decls` — a struct embedding a scalar PLUS
non-output decls (`{#a:1, 5}`) should manifest as the scalar `5` while keeping `.#a`
selectable (cue does this); Kue bottomed. (2) **B3** — `for x in {#a:1,[1,2]}` should
iterate the embedded list `[1,2]`; `comprehensionPairs` iterated zero times.

**The carrier (new ctor).** Added `Value.embeddedScalar (scalar : Value) (decls : List
Field)` — the direct scalar analog of the existing `.embeddedList (items) (tail) (decls)`.
The scalar is the manifested terminal value; the decls ride alongside and stay selectable.
Built at embed-eval in `meetEmbeddingsWithFuel` (the producer — same site the pure `{5}`
collapse lives), gated on: host has NO output field, host HAS decls (else the pure collapse
fires), and the embedding resolved to a terminal scalar (`isTerminalScalar`, factored out of
`collapsesToScalarEmbed`).

**Soundness boundary — pure collapse UNTOUCHED.** `collapsesToScalarEmbed` (no output, NO
decls) still drops `{5}`→`5` unchanged. The carrier is a SEPARATE branch for the
decls-present case; widening the collapse to admit decls is the unsound direction (it would
DROP the decls). A genuine scalar conflict with decls (`{#a:1,5,6}`) produces an INLINE
bottom in the carrier (`{#a:1, _|_}`, the RESID-MASK convention `.embeddedList` uses for
conflicting elements), which `containsBottom` flags → export rejects, matching cue's
whole-value reject (selecting `.#a` off it also rejects — no masking).

**New-constructor discipline — every match site, no catch-all swallow.** `.embeddedScalar`
handled explicitly at: Lattice (`meetWithFuel` carrier-meet arms via `scalarCarrierPartner?`;
`meetCore` `.bottom` arms; `containsBottom`), Eval (`selectEvaluatedField` + its `.disj`
arm; `classifyDefinedness`; `classifyGuard`/`classifyDynLabel` — recurse onto the inner
terminal scalar, matching cue treating the carrier AS its scalar for guards/labels;
`valueTag` 32; `valueDigest`; `comprehensionPairs` — non-iterable → `none`;
`spliceNarrowingOperand?`; the `foldValueWithDepth` + `remapConjRefs` walkers),
EvalOps (`classifyArithOperand` recurse; `resolveOperand` UNWRAPS the carrier to its scalar
before any arith/comparison op, so `{#a:1,5}+1` sees `5` — cue-exact), Format (renders
`{#a: 1, 5}`), Manifest (manifests the scalar, drops decls), Normalize×2 (recurse scalar +
decls so def-body closedness propagates — NOT left to the passthrough catch-all), Runtime
(`lookupField?` for `-e` selection). `hasSelfRefAtDepth` correctly leaves it to the
catch-all (post-eval carrier never appears in a raw def body — same as `.embeddedList`).

**B3.** Added `.embeddedList items _ _ => some (listPairsFrom 0 items)` to
`comprehensionPairs` — `for x in {#a:1,[1,2]}` now iterates `[1,2]`. A scalar carrier
(`{#a:1,5}`) is non-iterable (its value is an int) → zero-iter via the `_ => none`
catch-all, Kue's standing non-iterable handling (cue type-errors there — a tracked
divergence, NOT widened in this slice).

**The `.#a` contract pinned.** Hidden/definition fields ARE selectable in-scope (`x.#a → 1`
where `x: {#a:1,5}`) — confirmed against cue v0.16.1, both eval and JSON export. Multiple
decls (`{#a:1,#b:2,5}`), optional decls (`{a?:int,5}`), the carrier inside a larger
unification (`{#a:1,5} & {#b:2,int}` → `5`, both decls kept), and conflicting-scalar
unification (`{#a:1,5} & {#b:2,6}` → bottom) all pinned.

**Tests (first-class).** `EvalTests` (11): the soundness net (`soundness_pure_scalar_collapse_unchanged`,
`soundness_scalar_with_decls_distinct_conflicts`, `soundness_scalar_with_decls_conflict_select_rejects`,
`scalar_embed_with_output_field_still_conflicts`) + the targets/edges
(`scalar_embed_with_decls_exports_scalar`/`_decl_selectable`/`_multiple`/`_in_unification`/
`_conflicting_unify`/`_equal_unify`, `scalar_embed_with_optional_decl`). `ComprehensionTests`
(2): `listcomp_for_embedded_list` (B3) + `listcomp_for_scalar_carrier_zero`. `ListTests` (5):
lattice-level `meet_scalar_carrier_*` + `manifest_scalar_carrier_is_scalar`. 4 fixtures
(`.cue`/`.expected` + `FixturePorts` entries via `parseSource`/`formatResolvedTopLevel`):
`structs/scalar_embedding_{with_decls,decl_select,multiple_decls}`,
`comprehensions/for_over_embedded_list`.

**Verify.** `lake build` green (110 jobs, no new warning/`sorry`/axiom; axiom-clean — the
standard 3 only); `check-fixtures.sh` → `fixture pairs ok`, zero drift (4 expected
additions); `shellcheck` n/a (no shell touched). 1 cue-divergence (non-iterable `for`
zero-iter, PRE-EXISTING) + 1 spec-gap (`{#a:1,5}` carrier semantics) recorded.

**Files.** `Kue/Value.lean` (ctor), `Kue/Lattice.lean` (carrier meet arms +
`isTerminalScalar`/`scalarCarrierPartner?` + `containsBottom`/`meetCore` arms),
`Kue/Eval.lean` (producer + ~10 match sites), `Kue/EvalOps.lean` (`resolveOperand` unwrap +
`classifyArithOperand`), `Kue/Format.lean`, `Kue/Manifest.lean`, `Kue/Normalize.lean`,
`Kue/Runtime.lean`, `Kue/Tests/{EvalTests,ComprehensionTests,ListTests,FixturePorts}.lean`,
4 `testdata/cue/` fixture pairs, `docs/reference/{cue-divergences,cue-spec-gaps,implementation-log}.md`,
`docs/spec/plan.md`, `docs/notes/` (breadcrumb).

---

## Completed Slice: CARRIER-STRUCT-MEET — carrier & decls-only struct bottoms, not merges (soundness) (2026-06-22)

Goal: close the soundness gap the prior slice's carrier introduced — a scalar/list embedding
carrier (`.embeddedScalar`/`.embeddedList`, the carrier IS its scalar/list) met with a PURE
decls-only struct that has NO embed of its own WRONGLY MERGED the decls instead of conflicting.
`{#a:1,5} & {#b:2}` is `5 & {#b:2}` = int-vs-struct bottom by the spec (unifying different types
is `_|_`); Kue admitted `{#a:1,#b:2,5}` — MORE PERMISSIVE than the spec, a genuine unsoundness.
cue v0.16.1 is spec-conformant here and rejects, so the fix moves Kue toward BOTH spec and cue.

**The fix (mechanical DELETION at 4 sites in `Lattice.lean`).** Each carrier's `none`-branch
(reached when the right/left operand is not a list-/scalar-shaped meet partner) carried a
`.struct fields _ none [] _` sub-case that, when `!structHasOutputField fields`, MERGED the
decls and kept the payload. Dropped that sub-case entirely — the `none`-branch now routes
straight to `meetCore`, which bottoms `carrier` vs `.struct` (`_, .struct .. => .bottom` /
`.struct .., _ => .bottom`). Applied UNIFORMLY to all four arms (`.embeddedList` left + right,
`.embeddedScalar` left + right), by hand, per the Phase-B ruling that the carriers do NOT share a
meet seam (the skeletons are isomorphic but the payload-meet step is irreducible; a 3-callback
combinator would hit the lambda-hides-`fuel+1` trap). The fix is a deletion routing to an existing
bottom path, not new logic — so 4× by hand is the correct cost.

**Boundary (oracle-confirmed v0.16.1, all three cases pinned before AND after).** (1) carrier &
carrier (`{#a:1,5} & {#b:2,5}`, `{#a:1,[1,2]} & {#b:2,[1,2]}`) — still MERGES, untouched (routes
via the `scalarCarrierPartner?` / `asListPair` partner branch, never the deleted sub-case);
(2) carrier & output-field struct (`{#a:1,5} & {b:2}`) — still BOTTOMS via `structHasOutputField`
(the `b` output field), unchanged; (3) carrier & decls-only struct without embed (`{#a:1,5} &
{#b:2}`) — now BOTTOMS (the fix). The precise discriminator the deleted sub-case matched:
`.struct fields _ none [] _` = a struct with `embed=none`, `patterns=[]`, any openness/tail-coherent
form — i.e. a plain decls-or-output struct with no embed of its OWN. A struct that should merge
(has its own embed) is an `.embeddedScalar`/`.embeddedList`, NOT a `.struct`, so it never fell into
this arm; the only thing the sub-case ever matched was the bug.

**Source-level path verified.** `{#a:1,5} & {#b:2}` parses as `.conj [structComp[#a:1][5],
struct[#b:2]]` — a `{…,5}` embedding is a `.structComp`, NOT a `conjStructOperand?`-eligible plain
struct, so `lazyConjMergedFields` returns `none` and `evalConjStandard` falls to the deferral fold,
which builds the carrier (`.embeddedScalar 5 [#a:1]`) then `meet`s it against the plain `{#b:2}` —
hitting the fixed arm → bottom. Confirmed in the binary (`kue export`, exit 1) for both carriers,
both operand orders, and a multi-decl carrier; carrier&carrier and carrier&output-field unchanged.

**Tests.** Flipped the bug-enshrining pins to positive bottom assertions:
`ListTests.meet_scalar_carrier_with_decls_struct` → `…_bottoms` (+ symmetric
`meet_decls_struct_with_scalar_carrier_bottoms` + `.embeddedList` analogs
`meet_embedded_list_with_decls_struct_bottoms` + symmetric);
`EvalTests.WITNESS_scalar_carrier_meet_{plain_decls_struct,lone_hidden_struct}_wrongly_merges`
→ `meet_scalar_carrier_with_{declsonly_struct,lone_hidden_struct}_bottoms` (+ symmetric `B&A`,
multi-decl carrier, list-carrier analogs both orders). Kept the CORRECT pins green and unchanged:
`meet_two_scalar_carriers` / `meet_two_embedded_lists` (carrier&carrier merge),
`scalar_carrier_meet_output_field_struct_bottoms` / `scalar_carrier_three_way_meet_keeps_all_decls`;
added source-level `{scalar,list}_carrier_meet_carrier_keeps_all_decls` +
`{scalar,list}_carrier_meet_output_field_struct_bottoms` to lock the boundary at the source level
for the under-covered list cases.

**Verify.** `lake build` clean (110 jobs, no `sorry`/axiom/new warning); `check-fixtures.sh`
→ `fixture pairs ok`, ZERO drift (no `testdata` fixture asserted the old merge — it lived only in
`native_decide` pins); `shellcheck` n/a (no shell touched). NO new cue-divergence (the fix makes
Kue CONFORM — spec + cue agree on bottom). `cue-spec-gaps.md` row 58 (scalar-embed-with-decls)
updated PARTLY → CONFORMING: the over-merge divergence is resolved; the carrier itself stays a
recorded spec-silent combination.

**Files.** `Kue/Lattice.lean` (4 meet-arm deletions + 2 doc-comment corrections),
`Kue/Tests/{EvalTests,ListTests}.lean` (pins flipped + boundary pins added),
`docs/reference/{cue-spec-gaps,implementation-log}.md`, `docs/spec/plan.md`, `docs/notes/`
(breadcrumb).

---

## Completed Slice: CARRIER-DECL-SELECT (share `selectFromDecls` across carrier arms)

Goal (DRY, behavior-preserving — filed by the Phase-B 2026-06-22 audit): collapse the
byte-identical decl-SELECTION logic that `selectEvaluatedField`'s three decl-bearing carrier
shapes (`.struct` / `.embeddedList` / `.embeddedScalar`) repeated. The triple
(`match findEvalField label <list> with | some f => selectedFieldValue f | none =>
.selector base label`) appeared SIX times in `Eval.lean` — once per shape at the top level AND
again inside the `.disj`-resolved sub-case — and a related carrier pair in `Runtime.lookupField?`.

**Arms confirmed truly identical (Eval side).** Read all six character-by-character: the only
difference across them is the binder NAME (`fields` for `.struct`, `decls` for the two carriers)
— the body is identical. All route a found field through `selectedFieldValue` (the single closing
decision) and a miss to the deferred `.selector base label`. Genuine dedup, the three shapes AGREE
exactly (distinct from the four-classifiers ruling, where they DISAGREE). The disj sub-case's three
arms are the same triple again.

**Fix (Eval).** Extracted `selectFromDecls (base) (label) (decls) : Value` — `findEvalField` →
`selectedFieldValue` / `.selector base label`. Routed all SIX sites through it: top-level
`.struct`/`.embeddedList`/`.embeddedScalar` (`Eval.lean:618-620`) + the three `resolveDisjDefault?`
sub-case arms (`:625-627`). `Eval.lean` 3442 → ~3424.

**Home — `Eval.lean`, NO new edge.** The helper is wanted in both `Eval` and `Runtime`. `Runtime`
already `import`s `Eval` (line 1), so `Eval` is the lowest module both see — the helper lives there,
reachable from `Runtime` with zero new import edges and no cycle. (The graph stays
`Eval → {Builtin, EvalOps, Decimal, Lattice, Regex, Normalize}`; `Runtime` sits ABOVE `Eval`.)

**Runtime — a DIFFERENT operation, NOT shared across the seam.** `Runtime.lookupField?`'s carrier
arms looked like the same triple but are NOT: they yield the RAW `Field.value` (no
`selectedFieldValue` close) and return `Option Value` (a miss is `none`, the genuine-absence
distinction the `-e` "field not found" diagnostic needs — never a deferred `.selector`). Routing
`Runtime` through Eval's `selectFromDecls` would change its behavior (close definition bodies it
keeps raw, lose the `none`-vs-present distinction) — exactly the silent behavior-change a DRY
collapse must avoid, and a banned cross-module DRY besides. Collapsed only the WITHIN-Runtime
triplication: a 1-line local `fieldValue? decls := (findEvalField label decls).map Field.value`
shared by all three arms; doc-comment updated to record why it stays distinct from `selectFromDecls`.

**Tests (+2 `native_decide`, pin-count conserved + 2).** The thin path was selection off a DEFAULTED
disjunction whose default arm is a CARRIER (the `.disj` sub-case's carrier arms had no direct pin —
the `.struct`-via-disj arm was already covered by `select_into_default_disjunction`). Added
`TwoPassTests.select_into_default_disjunction_{scalar,list}_carrier`, locking `selectFromDecls`'s
routing for both carrier shapes through the disj sub-case. Top-level carrier selection already
covered: `.embeddedScalar` (`EvalTests.scalar_embed_with_decls_decl_selectable` + `_multiple` +
`_in_unification`), `.embeddedList` (fixture `lists/list_embedding_select_index.cue`), `.struct`
(ubiquitous).

**Verify.** `lake build` clean (110 jobs, no `sorry`/axiom/new warning); `check-fixtures.sh`
→ `fixture pairs ok`, ZERO drift; `shellcheck` n/a (no shell touched). Behavior-preserving — every
pre-existing pin + fixture green, pin-count conserved (+2 new). NO cue-divergence, NO spec-gap
(pure refactor).

**Files.** `Kue/Eval.lean` (helper + 6 sites), `Kue/Runtime.lean` (within-module collapse +
doc-comment), `Kue/Tests/TwoPassTests.lean` (+2 pins), `docs/spec/plan.md`,
`docs/reference/implementation-log.md`, `docs/notes/` (breadcrumb).

## 2026-06-22 — release `v0.1.0-alpha.20260622` cut (attended)

`scripts/release.sh 0.1.0-alpha.20260622` from clean HEAD `b3f7cd9` (Darwin/arm64): built
`kue` (110 jobs), staged `kue-aarch64-apple-darwin`
(sha256 `9858907c861d773c363fd89007c24291c8677e7c9260c67f514303e3bc5c4cc2`), pushed tag
`v0.1.0-alpha.20260622`, published the GitHub release, bumped + pushed the homebrew-tap
formula (`chakrit/homebrew-tap` `bca1e1c..e7a8eaa`). Bundles everything since
`v0.1.0-alpha.20260621`: the BI-2 family tail, EvalOps, import-eager-closedness, TL-1/TL-2,
scalar-embed-with-decls + B3, CARRIER-STRUCT-MEET, CARRIER-DECL-SELECT, and two full
two-phase audit rounds. arm64-macOS-only asset (host build; Lean static-links its runtime,
only `/usr/lib` system dynamic deps).

## 2026-06-22 — Bug2-5: transitive-embed disj-path narrowing injection (`5fca57e`)

**Goal.** Resolve the Bug2-5 argocd blocker: a co-embedding sibling def's static field
(`kind: "ListenerSet"`) must narrow a mixin let-local (`_patch.kind`) buried inside a
disjunction-bodied def (`#Mixin: listShape | structShape | error`), so the
`if kind == add.#kind` guard fires and the matched `#patch` surfaces. cue emits the patch
field; pre-fix kue DROPPED it.

**The diagnosis was sharper than the sketch (and Bug2-5 was NOT the final argocd blocker).**
Reconstructed the faithful argocd `#ListenerSet` shape self-contained from the prod9 oracle
cache (`defs@v0.3.19` — `#ListenerSet` co-embeds `#UseCertManager` → `#Mixin`). Bisection
isolated the actual break ONE level deeper than the original sketch predicted: `kind` is
declared on the OUTER def (`#ListenerSet`) and `#Mixin` is embedded TRANSITIVELY
(`#ListenerSet` → `#UseCertManager` → `#Mixin`). The host's `spliceOperandForEmbed` into the
MIDDLE def (`#UseCertManager`) dropped `kind`, because `embedBodyEmbedsDisj` is a ONE-level
check and the middle def neither reads `kind` nor DIRECTLY embeds a disjunction (the
disjunction is one more level down, inside `#Mixin`). So the Gap-2b "splice ALL regular
fields" gate never fired, `kind` never reached the disjunction-arm path, the guard fired
against the un-narrowed `kind: string`, and the patch dropped. (Critically: once `kind`
DOES reach the splice, the existing narrowing flows correctly — the bug was purely the GATE
missing the transitive disjunction, NOT the `.disj`-distribution injection the sketch
predicted.)

**Fix (general, not app-specific).** `embedBodyEmbedsDisjDeep (env) (fuel) (body)` — follows
the embed chain (resolving each embedding via `resolveEmbedDefBody?`, mirroring
`bodyNeedsDefer`'s transitive recursion) so a TRANSITIVELY-embedded disjunction still
triggers the regular-field splice. `spliceOperandForEmbed` takes the precomputed
`embedsDisjDeep : Bool` (stays pure; the two callsites in `meetEmbeddingsWithFuel` have
`env` and compute it). The splice it gates is the SAME sound Gap-2b mechanism — meet is
idempotent on a field an arm already carries, a real conflict still bottoms — so widening
the GATE through the embed chain never over-narrows. Fuel-bounded against embed cycles
(`termination_by fuel`); structurally total, no `partial`/`sorry`/new axiom.

**4th-walker question (walker-dedup ruling).** Did NOT add a `.disj`-path walker. The fix is
a transitive extension of the EXISTING `embedBodyEmbedsDisj` gate (the deep variant calls it
as the `||` base case), threaded to the EXISTING `spliceOperandForEmbed`. No new
classifier-family member; the deep walker mirrors the proven `bodyNeedsDefer` template
(transitive embed recursion via `resolveEmbedDefBody?`) — a shared structural shape, not a
forced merge. Net: one new total function, two call-site changes.

**Tests.** 4 `native_decide` mechanism/control pins (`embedBodyEmbedsDisjDeep`
transitive-true / no-disj-false / direct-true) + 4 end-to-end source pins (transitive emit,
real-conflict bottoms, guard-false drops, direct-embed no-regression) in `TwoPassTests`
Bug2-5 section. Export fixture `testdata/export/bug25_disj_arm_let_local_narrowing.{cue,json,args}`
(the self-contained two-level repro; cue emits `meta:"yes"`, pre-fix kue dropped it, now
identical — oracle-confirmed vs cue v0.16.1).

**Verify.** `lake build` clean (110 jobs, no `sorry`/axiom/new warning);
`check-fixtures.sh` → `fixture pairs ok`, ZERO drift; cert-manager (prod9, READ-ONLY)
content-identical to cue (`jq -S`, exit 0) — the canary holds, the deep gate never
false-fires on production infra. `shellcheck` n/a (no shell touched).

**argocd STILL bottoms — Bug2-6 (DISTINCT, pre-existing, the REAL final blocker).**
`kue export apps/argocd.cue` now bottoms in ~60s (down from 153s) but is still wrong.
Bisection past Bug2-5 uncovered a FUNDAMENTAL definition-merge bug, unrelated to
disjunctions/mixins. **Minimal repro:** `#Foo: {a: 1}` + `#Foo: {c: 3}` (two SEPARATE
declarations of one definition path) → cue unifies the bodies BEFORE closing → `{a:1, c:3}`;
kue closes each decl's body SEPARATELY (`defClosed` at load), `canonicalizeFields` conjoins
them (`.conj [defClosed{a}, defClosed{c}]`), the meet mutually rejects → `{a: _|_, c: _|_}`.
Confirmed top-level, nested, and in the argocd `#UseCertManager` (three separate
`#additions:` hidden-field decls). Spec basis: repeated decls of one definition unify field
SETS and close ONCE over the union (same union-not-intersect rule as embedding closedness).
Soundness constraint (why it is NOT a one-line fix): `#A: {a}; #B: {c}` then `#A & #B` must
STILL reject (distinct defs; cue + kue both correctly reject) — but by the time it is a meet
of two closed structs, the "same def path, repeated decl" provenance is LOST, so a naive
"union closed sets on meet" would wrongly admit `#A & #B`. The fix must distinguish
same-label def-decl merge (in `canonicalizeFields`/`joinUnevaluated`, where the provenance
IS present) from use-site def-meet — a provenance-carrying change in the definition-merge
core. PARKED for a dedicated slice per the guardrails (correctness-first; an unsound fix is
worse than the parked bottom). Full detail in `spec-conformance-audit.md` Live-slice detail.

**Files.** `Kue/Eval.lean` (`embedBodyEmbedsDisjDeep` + `spliceOperandForEmbed` signature +
2 callsites), `Kue/Tests/TwoPassTests.lean` (Bug2-5 section, 8 pins),
`testdata/export/bug25_disj_arm_let_local_narrowing.{cue,json,args}`,
`docs/spec/spec-conformance-audit.md`, `docs/spec/plan.md`, `docs/reference/cue-divergences.md`,
`docs/notes/` (breadcrumb).

---

## Completed Slice: Bug2-6 — definition multi-declaration close-once (`ef824cb`, 2026-06-23)

Goal: two SEPARATE declarations of one definition path (`#Foo: {a:1}` + `#Foo: {c:3}`) must
UNIFY their field-sets and close ONCE over the union (cue v0.16.1: `{a:1,c:3}`), the standard
union-not-intersect CUE definition-merge rule. Kue formerly `.conj`-ed two SEPARATELY-closed
bodies, so the meet mutually rejected → `{a:_|_, c:_|_}` (the parked Bug2-6, the residual argocd
blocker uncovered while fixing Bug2-5).

**Mechanism (provenance carrier — STRUCTURAL, per the Phase-B design note).** The carrier is a
merged def body vs a `.conj`, NOT a flag on `.conj`. `canonicalizeFields` is the one seam that
knows two bodies are repeated decls of the SAME def-path label; it now folds via a new
`mergeUnevaluatedFieldInto` that selects the value-merge by the MERGED `FieldClass`:
- merged class `isDefinition` ⇒ `mergeDefinitionDecls` (close-once UNION): union the decl bodies'
  fields (`mergeFieldListWith joinUnevaluated (fa ++ fb)`, so a SHARED label's values still
  `.conj`-meet — `#Foo:{a:1}`+`#Foo:{a:2}` keeps the conflict), union patterns, union openness
  (`unionDefOpenness`, OPEN dominating — if ANY decl is open via `...` the union is open, the DUAL
  of `StructOpenness.meet`), and let `mkStruct` re-derive the SINGLE union `closedClauses` clause
  when the result is closed. Handles `.struct × .struct` (the primary closed-body shape post-
  `normalizeDefinitions`) and `.structComp × .structComp` (embed/comprehension-bearing);
  `.conj` fallback for shapes that cannot cleanly union (a def body that is a ref/disj/selector,
  or a mixed pair).
- every other class ⇒ plain `joinUnevaluated` (`.conj`), `meet`-ing lazily once the frame is in
  scope. A class mismatch keeps the slots separate (matching the evaluated path).

**Soundness preserved.** `#A & #B` (distinct closed defs) STILL rejects: the use-site `meet`
CONCATENATES `closedClauses` (conjunction → reject extras) and NEVER routes through
`mergeDefinitionDecls` — the two paths are disjoint in code. `mergeConjFields` (the conj-of-EMBEDS
path) deliberately keeps plain `joinUnevaluated`: a host's `#data` meeting an embedded mixin's
`#data` is a genuine cross-conjunct meet that must `.conj` (unioning there wrongly re-opened a
closed pattern def — `#data: [string]: string` gained a stray `...`, a cert-manager mixin
regression caught during the slice and reverted).

**Tests.** 13 `native_decide` pins (`TwoPassTests` Bug2-6): target close-once (`{a:1,c:3}`) +
3-decl argocd shape + nested (`out:{#m:{a:1};#m:{c:3}}`); close-once rejects a use-site extra,
admits a union field; same-def CONFLICT (`#Foo:{a:1};#Foo:{a:2}`) still bottoms; one-decl
open-via-`...` opens the union (admits extra); 4 distinct-closed-def soundness guards (reject
extra, conflict bottoms, plain reject, same-field admit). 3 fixture pairs
(`definitions/bug26_same_def_multi_decl_close_once`, `…_three_decl_close_once_rejects_extra`,
`…_distinct_closed_defs_still_reject`) + FixturePorts entries. All oracle-confirmed vs cue v0.16.1.
Axiom-clean (`propext` only — `#print axioms mergeDefinitionDecls`/`canonicalizeFields`), total
(structural). `lake build` clean; `check-fixtures.sh` → fixture pairs ok (zero unintended drift);
cert-manager content-identical (jq-normalized diff EMPTY; the 15-line raw diff is field-order #3,
the ratified spec gap).

**argocd milestone: STILL bottoms (~61s wall) — Bug2-6 was NOT the final blocker.** Localized via
bisection to `route.yaml`/`listener.yaml` (the `defaults.#ListenerSet = defs.#ListenerSet &
parts.#UseCertManager & {…}` composition; `#UseCertManager` declares `#additions` THREE times).
It now hits **Bug2-7** (filed, parked): same-def multi-decl close-once is correct on DIRECT
selection (this fix) but LOST when the merged def is REFERENCED through a sibling (`vis: #additions`)
— the def-deferral/force-fold reconstruction (`mergeConjOperands`/`mergeConjFields`) rebuilds the
body from the original decls via plain `.conj` and re-closes each SEPARATELY, so each clause rejects
the other decl's fields (`{cert_gw:_|_, cert_ing:_|_}`). Minimal repro + tripwire pin
`bug27_WITNESS_multi_decl_def_ref_wrongly_bottoms`. The sound fix carries same-decl provenance
through `mergeConjOperands` (within-operand repeated decls vs cross-operand conjuncts) — a larger
design change, PARKED; a naive `mergeConjFields` union is unsound (re-opens the cert-manager mixin
pattern, verified). Perf frontier #7 stays GATED (argocd does not resolve).

**Files.** `Kue/Eval.lean` (`unionDefOpenness`, `mergeDefinitionDecls`, `mergeUnevaluatedFieldInto`,
`canonicalizeFields` rewritten onto it; `mergeConjFields` doc updated to note the deliberate
plain-`.conj` divergence), `Kue/Tests/TwoPassTests.lean` (Bug2-6 section: 13 pins; Bug2-7 tripwire),
`Kue/Tests/FixturePorts.lean` (3 entries), `testdata/cue/definitions/bug26_*.{cue,expected}`,
`docs/spec/spec-conformance-audit.md`, `docs/spec/plan.md`, `docs/notes/` (breadcrumb).

---

## Completed Slice: Bug2-7 — def multi-decl close-once on the reference / force-fold path (`3361699`, 2026-06-23)

Goal: same-def multi-declaration close-once (Bug2-6) is correct on DIRECT selection
(`out: #Foo`) but was LOST when the merged def lives inside a DEFINITION wrapper
selected/referenced through a sibling — `#Use: {#additions:…; #additions:…; vis: #additions}`
then `#Use.vis` → kue `{cert_gw:_|_, cert_ing:_|_}` (cue v0.16.1: `{cert_gw:{}, cert_ing:{}}`).
The deeper argocd blocker uncovered after Bug2-6 landed.

**Root.** A def wrapper with a sibling self-ref (`vis: #additions`) defers to a `.closure`; the
force-fold reconstruction `forceClosureWithConjunctCore` (its three struct arms — `.structComp`,
`.struct .defOpenViaTail`, `.struct openness none []`) rebuilds the body via `mergeConjOperands`.
That function ran `mergeConjFields` (plain `joinUnevaluated`/`.conj`) over each operand's fields
to build the layout + merged frame BEFORE the downstream `canonicalizeFields mergedFields` could
run — so the two within-operand `#additions` decls were `.conj`-collapsed into one slot and the
later `canonicalizeFields` had a single already-`.conj`'d slot to act on, never reaching
`mergeDefinitionDecls`. The `.conj` of two separately-closed bodies mutually rejected. (Discriminator
confirmed empirically: the SAME multi-decl-plus-sibling-ref shape works when the outer wrapper is a
REGULAR struct — direct-eval `.struct` arm canonicalizes correctly — and bottoms only when it is a
`#`-definition routed through the force-fold path.)

**Mechanism (within-operand vs cross-operand — the soundness boundary).** `mergeConjOperands` now
`canonicalizeFields`-es each operand's OWN fields up-front
(`let operands := operands.map fun op => (canonicalizeFields op.fst, op.snd)`), so two repeated
DEFINITION-class decls of one path declared WITHIN a single struct body (one operand) UNION via
`mergeDefinitionDecls` — the Bug2-6 close-once lever, reused unchanged. The CROSS-operand merge
(`mergeConjFields`, plain `.conj`) is UNTOUCHED, so a host's `#data` meeting an EMBED's `#data`
(DISTINCT operands) still `.conj`-MEETs — never unions. The within-operand-vs-cross-operand split
IS the disjointness: the close-once union fires only for decls inside one operand; a genuine
cross-conjunct meet is never reached by the canonicalize. Per-operand canonicalization preserves
first-occurrence layout for every slot at-or-before a collapsed duplicate (the `vis` ref
`refId ⟨0,0⟩` still lands on the merged `#additions` slot 0), so the `mergedMap` rebuilt from the
canonicalized operands + the label-driven `rebaseConjunctFields` remap stay coherent — exactly the
direct-eval `.struct` arm's treatment, now applied per-operand on the force path. Axiom-clean
(`propext`/`Quot.sound` — `#print axioms mergeConjOperands`), total.

**Tests.** 8 `native_decide` pins (`TwoPassTests` Bug2-7): target close-once via ref (FLIPPED the
Bug2-7 witness) + 3-decl argocd shape + ref-and-direct-select-both + nested ref + def-ref-after-meet;
soundness guards via a reference — `#A & #B` distinct closed defs reject, same-def conflict bottoms,
close-once rejects a use-site extra. 3 fixture pairs (`definitions/bug27_multi_decl_def_ref_close_once`,
`…_same_def_conflict_via_ref_bottoms`, `…_distinct_closed_defs_via_ref_reject`) + FixturePorts. All
oracle-confirmed vs cue v0.16.1. `lake build` clean; `check-fixtures.sh` → fixture pairs ok (zero
unintended drift); cert-manager content-identical (jq-normalized diff EMPTY; 15-line raw diff =
field-order #3, the ratified gap — the closed `#data: [string]: string` pattern is NOT re-opened).

**argocd milestone: STILL bottoms (~58s wall) — Bug2-7 was NOT the final blocker.** It now hits
**Bug2-8** (filed, parked): same-def multi-decl close-once ACROSS AN EMBED boundary.
`apps/argocd.cue`'s `#UseCertManager` EMBEDS `#Mixin` and adds its OWN `#additions:
{cert_gw, cert_ing, cert_ls}` decls, so the `#additions` decls of the ONE def path span the embed
boundary (host operand + embed operand) — cross-operand, so Bug2-7's within-operand canonicalize
does not reach them, yet cue close-once-UNIONS them. Minimal repro: `#A: {#m: {a:1}}` then
`#Use: {#A; #m: {c:3}; vis: #m}` → cue `{a:1,c:3}`, kue bottoms. Tripwire pin
`bug28_WITNESS_embed_cross_decl_close_once_wrongly_bottoms` + the boundary pin
`bug28_embed_closed_pattern_field_stays_meet` (the cert-manager `#data` pattern must stay
closed-MEET — a naive cross-operand union re-opens it, verified). Distinguishing same-def-PATH-decl
(union) from cross-conjunct VALUE-meet across an embed needs def-path provenance threaded THROUGH
the embed merge — a larger change, PARKED. Perf frontier #7 stays GATED (argocd does not resolve).

**Files.** `Kue/Eval.lean` (`mergeConjOperands` — per-operand `canonicalizeFields` + doc),
`Kue/Tests/TwoPassTests.lean` (Bug2-7 section: 8 pins, witness flipped; Bug2-8 tripwire + boundary
pin), `Kue/Tests/FixturePorts.lean` (3 entries), `testdata/cue/definitions/bug27_*.{cue,expected}`,
`docs/spec/spec-conformance-audit.md`, `docs/spec/plan.md`, `docs/notes/` (breadcrumb).

---

## Completed Slice: Bug2-8 — same-def multi-decl close-once across an embed boundary (`2332aff`, 2026-06-23)

**Goal.** When a def declares `#m` once and EMBEDS another def that also declares `#m`
(`#A: {#m:{a}}` then `#Use: {#A; #m:{c}; vis:#m}`), the two `#m` decls are repeated declarations
of the ONE def path `#m` spanning the embed boundary — cue close-once-UNIONS them (`{a:1, c:3}`).
kue formerly `.conj`-met them across the embed → each clause re-closed separately → mutual reject →
bottom; the `-e out` projection (`#Use.vis`) dropped `a`. The hardest layer of the argocd blocker
chain — within-operand-vs-cross-operand (Bug2-7's lever) no longer separates union from meet, since
both `#m` decls are cross-operand yet must UNION.

**Mechanism (provenance carried in the TYPE — illegal-states-unrepresentable).** New
`inductive DeclProvenance := ownDecl | embeddedDecl` (`Value.lean`) on a named `structure
ConjOperand (fields, open_, provenance)` replacing the `(List Field × Bool)` operand tuple that
`mergeConjOperands` threads (`ConjOperand.ofPair` lifts a legacy pair to `ownDecl`). A SUM, not a
Bool: the discriminator is "do two same-label decls name the ONE def path" — `ownDecl ×
embeddedDecl` is exactly that pair, and only it close-once-UNIONs. Two threading points:

- **Static fold (eager `.structComp` eval arm + force `forceClosureWithConjunctCore` `.structComp`
  arm).** A PLAIN embedding's same-def-path decls — `embedSameDefPathDecls` resolves each embed
  body via `resolveEmbedDefBody?`, takes its `bodyDefinitionFields`, keeps those whose label is in
  the host's own DEFINITION labels — are folded into the static frame as an `embeddedDecl`-provenance
  operand BEFORE static eval. `mergeConjOperands`'s provenance-aware cross-operand merge
  (`mergeConjOperandFields`) close-once-UNIONS the host `ownDecl #m` × embed `embeddedDecl #m` pair
  via `mergeDefinitionDecls` (the Bug2-6 lever). The `#m` SLOT holds the union AND a sibling
  `vis: #m` (evaluated on the static frame) resolves against it — fixing both the whole-file bottom
  and the `-e out` drop. The fold is GATED to plain embeds (`!bodyNeedsDefer && !embedBodyEmbedsDisjDeep`)
  so a comprehension/disjunction-bearing embed keeps its existing narrowing machinery (Bug2-4/2-5).
- **Embed meet-fold (`meetEmbeddingsWithFuel`'s struct `_` arm).** Since the static fold already
  unioned `#m` into the host, `meetEmbedUnioningDefDecls` STRIPS the embed's matching same-def-path
  `#m` so the generic `meet` does not re-meet the union against the embed's narrower arm (which would
  re-close-REJECT the host's other labels, or double an equal shared field to `1 & 1`). The embed's
  OTHER fields/patterns/tail still meet (kept on the opened embed-rest). The deferral-bearing closure
  arm keeps the plain meet (its decls flow through the splice narrowing, not the static union).

**Soundness boundary (the discriminator that keeps the canary a MEET).** `isSameDefPathLabel`
requires BOTH sides to declare the label DEFINITION-class AND both values to be field/pattern-bearing
structs (`isUnionableDefValue` — a scalar/kind def value `#x: string` is left to the ordinary meet,
else its `.conj` doubles the display `string & string`; this fixed the 599
`disj_default_embed_sibling_narrows` near-regression). The cert-manager `data: [string]: string` is a
REGULAR field — never enters the DEFINITION union, stays a closed-pattern MEET. A DEFINITION pattern
field (`#data: [string]:string`) DOES union, but `mergeDefinitionDecls` unions patterns alongside
fields, so a host int field still bottoms against `string` (pattern preserved).

**Guards (8 `native_decide` pins TwoPassTests Bug2-8, all oracle-confirmed vs cue v0.16.1).** Witness
close-once-unions (whole-file AND `-e out` both `{a:1,c:3}`, the witness FLIPPED); 3-decl
host+two-embeds (argocd `#additions` shape); two-mixin same path; DEFINITION pattern across embed
admits string + rejects int; same-def CONFLICT across embed bottoms; two DISTINCT closed defs
`#A.#m & #B.#m` reject; cert-manager REGULAR closed-pattern canary stays MEET. 3 fixture pairs
(`bug28_*`) + FixturePorts. cert-manager FULL export content-identical (jq -S diff = 0; raw diff = 15
= ratified field-order #3). Axiom-clean (`propext`/`Quot.sound`/`Classical.choice`), total.

**argocd milestone: STILL bottoms (~55s) — Bug2-8 was NOT the final blocker.** The Bug2-8 union
itself handles the cert-manager `#additions` shape (a comprehension over the pattern+field-unioned
`#additions` across the embed matches cue). The residual is **Bug2-9** (PARKED): use-site narrowing
of a REFERENCED multi-conjunct def whose conjuncts include the cert-manager mixin — `ls =
defaults.#ListenerSet & {#name,#ns,#passthrough_hosts}` where `defaults.#ListenerSet =
defs.#ListenerSet & parts.#UseCertManager & {…}`. kue bottoms; cue produces the full manifest. The
INLINED 3-way meet with all use fields supplied directly WORKS, so the bug is specific to narrowing a
referenced NAMED multi-conjunct def. ~11s to repro in isolation. Perf frontier #7 stays GATED.

**Files.** `Kue/Value.lean` (`DeclProvenance`, `ConjOperand` + `ofPair`), `Kue/Eval.lean`
(`mergeConjOperandFields`, `mergeConjOperands` over `ConjOperand`, `isUnionableDefValue`/
`isSameDefPathLabel`/`meetEmbedUnioningDefDecls`, `bodyDefinitionFields`/`embedSameDefPathDecls`,
the static fold in both `.structComp` arms, `lazyConjMergedFields`), `Kue/Tests/TwoPassTests.lean`
(Bug2-8 section: 8 pins, witness flipped + renamed), `Kue/Tests/FixturePorts.lean` (3 entries),
`testdata/cue/definitions/bug28_*.{cue,expected}`, `docs/spec/spec-conformance-audit.md`,
`docs/spec/plan.md`, `docs/notes/` (breadcrumb).

---

## Completed Slice: Bug2-9 — use-site narrowing of a referenced named multi-conjunct def (`5d9cf8f`, 2026-06-23)

**Goal.** Fix the argocd residual where a use-site narrowing of a REFERENCED NAMED multi-conjunct
def bottoms/incompletes while the INLINED 3-way meet works. `ls = defaults.#ListenerSet & {#name,
#ns, #passthrough_hosts}` where `defaults.#ListenerSet = defs.#ListenerSet & parts.#UseCertManager &
{…}` — the referenced def's BODY is itself a `.conj`.

**Root cause.** `#ListenerSet`'s body is a `.conj`. The use-site `#LS & {narrow}` gives the outer
`.conj [refId(#LS), {narrow}]`. The lazy-merge reducer `conjStructOperand?` follows a `.refId` only
to a plain `.struct` body — a `.conj` body hits its `_` catch-all → the lazy-merge aborts → the
`.refId` eval arm forces `#LS`'s `.conj` body STANDALONE (no use-operands). A conjunct's sibling
self-ref (`vis: #name`) collapses to its abstract `string` BEFORE the use-site narrowing arrives;
`& {narrow}` then meets too late (`incomplete value: string`). The INLINED form works because all
conjuncts sit in ONE `.conj` and fold together.

**Mechanism (`flattenConjDefRef`, total, axiom-clean — propext only).** In the `.conj` eval arm,
FLATTEN a depth-0 ref to a `.conj`-bodied def into its constituent conjuncts BEFORE the fold:
`#LS & {narrow}` → `#A & #B & {…} & {narrow}` operand-wise, byte-identical to the inlined meet, which
the existing lazy-merge + closure-deferral path already evaluates correctly. The flatten is applied
once at the top of the arm (`rawConstraints.flatMap (flattenConjDefRef env evalFuel)`), so it feeds
both `splitDisjConjunct` and `evalConjStandard`. A non-`.refId`-to-`.conj` constraint is returned
unchanged, so non-multi-conjunct-def conjuncts keep their path.

**Frame safety + termination.** Depth-0-bounded: a top-level def and its use site share the package
frame, so the spliced conjuncts' depth-0 refs (and package-SELECTOR conjuncts like
`defs.#ListenerSet`, which re-resolve their own import binding) stay valid in place; an outer
(`depth > 0`) ref is left unflattened. Fuel-bounded against alias cycles (`#A: #A & {…}`). Recurses
through a chain of named multi-conjunct defs (`#C: #B & …`, `#B: #A & …`).

**Soundness (oracle-confirmed v0.16.1 on the FAITHFUL prod9 `defs.#ListenerSet` shape via the
vendored `defs@v0.3.19` cache).** named-ref-narrowed == inlined == cue; a real conflict still bottoms
(`val:1` vs `val:2`); closedness preserved (use-site `notallowed` rejected). cert-manager canary
content-identical (jq -S diff = 0; raw diff = 15 = ratified field-order #3). 5 fixture pairs
(`bug29_*`) + FixturePorts + 5 `native_decide` pins (TwoPassTests Bug2-9): 2/3-conjunct +
nested-chain narrowing, conflict-bottoms + closed-rejects-extra guards.

**argocd status: STILL bottoms (~53s) — Bug2-9 was NOT the final blocker.** With the named-ref
flatten landed, the faithful `ls` now produces a manifest but DROPS `metadata.name`/
`metadata.annotations` — the deeper residual **Bug2-10** (PARKED): use-site narrowing of a host that
EMBEDS a def with a sibling self-ref does NOT flow into the embedded self-ref. Self-contained repro
`{#Meta} & {#name:"x"}` (`#Meta: {#name: string, metadata: name: #name}`) → kue `incomplete value:
string`, cue `{metadata:{name:"x"}}`; the DIRECT `#Meta & {#name}` works. The Bug2-4/2-5 narrowing
family (`meetEmbeddingsWithFuel` closure-force-splice). The breadcrumb's prior "INLINED 3-way meet
WORKS in kue" discriminator meant "does not BOTTOM" — the inlined form ALSO dropped the annotation
(content-incorrect); Bug2-9 made named == inlined, exposing this shared Layer-B defect. Perf
frontier #7 stays GATED.

**Files.** `Kue/Eval.lean` (`flattenConjDefRef`, wired into the `.conj` eval arm),
`Kue/Tests/TwoPassTests.lean` (Bug2-9 section: 5 pins), `Kue/Tests/FixturePorts.lean` (5 entries),
`testdata/cue/definitions/bug29_*.{cue,expected}`, `docs/spec/spec-conformance-audit.md`,
`docs/spec/plan.md`, `docs/notes/` (breadcrumb).

---

## Audit Slice: Phase-A code-quality audit (Bug2-8 + Bug2-9 batch, `9b78c3d`..`0f5af8e`)

Two-phase audit counter = 2 (Bug2-8 = slice 1, Bug2-9 = slice 2). Phase A only (Phase B
follows). Commits `0109bb4` (test-suite revival) + `5b6943f` (over-fire pins + filed findings).

**Batch soundness verdict: HEALTHY.** Both introduced mechanisms are sound.

- **Bug2-8 (`DeclProvenance`/`ConjOperand`) — new-type discipline CLEAN.** Grepped every
  match/construction site: NO catch-all `_` over either new type (the only `DeclProvenance`
  comparison is `prov != incomingProv` via derived `DecidableEq`). Every construction tags the
  right provenance — `.ownDecl` for host/use operands (directly or via `ConjOperand.ofPair`),
  `.embeddedDecl` only at the two static-fold `embedSameDefPathDecls` sites. Union-vs-meet sound on
  all four attacks (oracle v0.16.1): cert-manager `[string]:string` regular pattern stays MEET
  (canary jq -S=0); `#A.#m & #B.#m` distinct closed defs reject; same-def conflict across embed
  bottoms; scalar def `#x:string` across embed stays MEET (`isUnionableDefValue`=false).

- **Bug2-9 (`flattenConjDefRef`) — never over-fires, terminating, closedness+conflict preserved.**
  Over-fire witnesses (oracle v0.16.1): alias cycle `#A: #A & #B` narrowed TERMINATES (fuel
  strictly decreases, not partial) == cue; depth>0 nested-scope ref NOT flattened but still narrows
  == cue; package-qualified `defs.#LS & {#name}` correctly DECLINED by the depth-0 guard (no
  over-fire — see Bug2-11). named==inlined==cue on the passing edges; conflict bottoms; closed
  rejects use-site extra. Axiom-clean — `#print axioms` confirms only the standard 3
  (propext/Quot.sound/Classical.choice), `flattenConjDefRef` = propext only.

**🚨 Major finding (FIXED inline, `0109bb4`): ~140 of 150 TwoPassTests theorems were DEAD.**
Four top-of-file `/-- … -/` doc comments (lines 10/21/31/40) were missing their closing `-/` and
ran prose straight into `theorem <name> :`. Lean nests `/-`, so the unclosed opens swallowed every
declaration from line 13 down to three stray `-/` at the end of the Bug2-8 section — including the
PRIMARY Bug2-8 witness `bug28_embed_cross_decl_close_once_unions`. Only the final 10 theorems were
elaborated. Proven via `#check` → unknown identifier + corrupting a dead theorem's expected value to
a false statement kept the build green. Fix: add the 4 missing `-/`, remove the 5 now-orphaned stray
`-/`. With all theorems live, 3 revived Bug2-8 pins failed `native_decide` on field ORDER only (kue
union insertion order vs cue's order) — reconciled to kue's actual output (semantics oracle-equal,
jq -S=0; ratified field-order #3). The behavior was always correct (independently pinned by the
`.cue/.expected` fixtures); this is pure test-coverage recovery. The log's prior "Bug2-8 section: 8
pins" / "Bug2-9 section: 5 pins" claims are now ACCURATE (were silently 5/0 before).

**Findings FILED (PARKED, not batch regressions):** Bug2-11 (MEDIUM — cross-package narrowing of a
package-qualified multi-conjunct def, same family as Bug2-9, distinct frame), Bug2-12 (LOW/spec-check
— self-recursive closed def admits an undeclared extra; pre-existing, the inlined form leaks
identically so it is NOT flattenConjDefRef's fault). See `spec-conformance-audit.md` PARKED list.

**Coverage added (`5b6943f`):** 3 new oracle-confirmed `native_decide` pins —
`bug29_depth_gt0_nested_scope_narrows`, `bug29_alias_cycle_narrow_terminates`,
`bug28_scalar_def_across_embed_stays_meet`.

**Gate:** `lake build` clean (all ~143 TwoPassTests theorems now native_decide-green),
`check-fixtures.sh` green, cert-manager FULL canary held (jq -S diff = 0; raw = 15 = field-order #3).
No shell touched. Phase B still DUE (architecture of the new types + Bug2-10 design note).

**Files.** `Kue/Tests/TwoPassTests.lean` (comment-terminator fixes + 3 field-order reconciliations +
3 new pins), `docs/spec/spec-conformance-audit.md` (Bug2-11/2-12 filed), this log.

---

## Completed Slice: Bug2-10 — deliver use-site narrowing into a structComp host's embedded self-ref (`aa4172b`, 2026-06-23)

**Behavior added.** `{#Meta} & {#name:"x"}` — where the host `{#Meta}` is a `.structComp` embedding a
self-ref def (`#Meta: Self={#name: string, metadata: name: Self.#name}`) — now narrows the embedded
`Self.#name` to the use-site value (`{metadata: {name: "x"}}`), matching cue and the DIRECT
`#Meta & {#name:"x"}` form. Pre-fix kue left `metadata.name: string` frozen → `incomplete value:
string`.

**Root cause (the conjunct-deferral gate).** `conjDefClosure?` defers ONLY a bare `.refId` conjunct
into the shared-`useOperands` fold; a `.structComp` host bypasses it and evaluates STANDALONE through
the `.structComp` eval arm with no use-operands, so its embed's self-ref collapses to abstract before
the sibling narrowing arrives. The DIRECT form works because the bare `#Meta` ref IS deferred.

**Fix (delivery, approach A — the splice was already correct).** `conjStructCompDefer?` (`Eval.lean`)
defers a `.structComp` host whose embed body has a sibling self-ref (`bodyNeedsDefer`, evaluated over a
placeholder body-frame `(0,[]) :: env` so the embed ref resolves exactly as the standalone arm's
`pushFrame fields env`) to its `.closure (env, hostBody)`. It then joins the SAME closure fold the
bare-ref path runs — `forceClosureWithConjunctCore`'s `.structComp` arm splices the use-operands and
meet-folds the embed, delivering the narrowing before the self-ref collapses. Gated at the call site on
a narrowing sibling existing (`conjNarrowingSibling?` — a struct/structComp/embeddedScalar/embeddedList
carrying ≥1 field); a no-narrowing `{#Meta}` is never a `.conj` (never reaches `evalConjStandard`) and
a no-self-ref host yields `bodyNeedsDefer = false`, so both stay byte-identical. Composes with the
Bug2-5 transitive embed chain (`embedChainAny`) and `injectLetLocalNarrowings` (already in the spliced
operand set). Did NOT touch `meetEmbeddingsWithFuel`'s internals.

**Plus a pre-existing embed-meet closedness leak (fixed on the same path).** Embedding a CLOSED def
into a no-`...` host must close the result over `host ∪ embed` labels (CUE rule), so a later MEET
rejects an undeclared extra. `{#Meta} & {b}` (closed `#Meta`, NO self-ref) formerly ADMITTED `b` — the
leak, reproducible with no deferral, so genuinely pre-existing. Fixed via `embeddingClosesHost` /
`embeddingFieldIsDefinition`: a definition-class embed (closed even when its UNEVALUATED body is still
`regularOpen` — definitions close at normalize/eval, not parse) overrides the host's `regularOpen` in
`closeEmbeddedOver`'s openness arg — ONLY for `regularOpen` (an explicit `...`/`defOpenViaTail` host
stays open, pinned by `EvalPerfTests` fix0). The embed-FORM `{#Meta, b}` still ADMITS the sibling `b`
(same-literal declaration, not a meet). Wired into both the eager `.structComp` arm and the
`.structComp` force arm.

**Soundness (all oracle-confirmed v0.16.1).** embedded == direct == cue; transitive embed + deep
nested self-ref narrow; a real conflict still bottoms (`val: 1 & 2`); closed-rejects-extra; embed-form
sibling admitted; over-fire negatives (no-narrowing, no-self-ref) byte-identical. cert-manager FULL
canary content-identical (jq -S diff = 0; raw = 15 = field-order #3). Full `lake build` green (all
sentinels resolve); `check-fixtures.sh` zero drift; axiom-clean (`propext`/`Quot.sound`), total. 9
`native_decide` pins (TwoPassTests `### Bug2-10` + the `#check @bug210_no_self_ref_unchanged` sentinel)
+ 7 fixture pairs (`bug210_*`) + FixturePorts.

**argocd: advanced from `incomplete value: string` to `conflicting values` (~54s) — NOT exported.**
Landing Bug2-10 revealed the REAL on-path blocker is **Bug2-11** (a TWO-LEVEL cross-package def-of-def
selector — `defaults.#ListenerSet = defs.#ListenerSet & {…}`, a cross-pkg def whose body refs the
cross-pkg `defs.#ListenerSet`, which embeds `parts.#Metadata`). The use-site narrowing never reaches
the embedded self-ref → `metadata: {name: string}` un-narrowed; the standalone force also collapses a
sibling disjunction (`#passthrough_hosts: [...string] | *[]` → `*[]`) → conflict with the use-site
list. Self-contained 3-package repro confirms; a single-level cross-pkg selector narrows fine. **This
CORRECTS the prior Phase-B claim that "argocd is same-frame, Bug2-11 off-path"** — empirically wrong;
`defaults.#ListenerSet` IS a cross-package selector and Bug2-11 IS the argocd blocker. Perf frontier #7
stays gated until argocd actually exports.

**Files.** `Kue/Eval.lean` (`conjStructCompDefer?`, `conjNarrowingSibling?`, `embeddingClosesHost`,
`embeddingFieldIsDefinition`, call-site gate in `evalConjStandard`'s `none` branch, `closeEmbeddedOver`
openness in both the eager + force `.structComp` arms), `Kue/Tests/TwoPassTests.lean` (`### Bug2-10`
section + sentinel), `Kue/Tests/FixturePorts.lean` (7 `bug210_*` entries), `testdata/cue/definitions/
bug210_*.{cue,expected}` (7 pairs), `docs/spec/{spec-conformance-audit,plan}.md`, this log.

## 2026-06-23 — Bug2-11: deliver use-site narrowing into a cross-package def-of-def selector (`bdced40`)

**Slice.** Use-site narrowing of a TWO-LEVEL cross-package def-of-def selector. `defaults.#ListenerSet
& {#name, #passthrough_hosts}` where `defaults.#ListenerSet = defs.#ListenerSet & {…}` (a cross-pkg
def whose BODY refs the cross-pkg `defs.#ListenerSet`, which embeds the self-ref `parts.#Meta`). The
narrowing never reached the embedded `metadata.name` (froze at `string`) AND a sibling default
disjunction (`[...string] | *[]`) collapsed to `*[]`, conflicting with the use-site list → kue
bottomed (`conflicting values`). cue v0.16.1 narrows. A SINGLE-level cross-pkg selector narrows fine;
the failure needs the def-OF-def indirection — the exact argocd `ls` shape.

**Root cause.** `defaults.#ListenerSet`'s body is a `.conj`. No deferral machinery
(`bodyNeedsDefer` via `embedChainAny`, `followAliasDefBody?`) recursed into a `.conj` body, so
`importDefClosureBody?` returned `none` and the use-site conjunct forced STANDALONE (no use-operands)
through the `.selector` eager arm — collapsing the embedded `Self.#name` before the narrowing arrived.
`flattenConjDefRef` correctly DECLINES the cross-package selector (depth-0-only, sound — a naive
flatten into the use-site frame would mis-resolve the inner `defs.#LS` import); Bug2-9 deliberately
left this declined case as Bug2-11.

**Fix (delivery, right-frame — three seams, `Kue/Eval.lean`).**
- `resolveSelectorDefBody?` — resolve a selector/ref arm to its def body (ANY shape, incl. a further
  `.conj`) paired with the package frame its refs resolve against; the building block for the
  recursive deferral check.
- `conjBodyHasDeferringArm fuel frameEnv capturedFrame` — a `.conj` def-of-def body DEFERS iff an arm
  `followAliasDefBody?`-resolves to a deferral-needing struct, OR resolves to a FURTHER `.conj`
  def-of-def with a deferring arm (the 3-level `defaults2 → defaults → defs` chain). Fuel-bounded
  against alias cycles.
- `importDefClosureBody?` — when the def body is a `.conj` with a deferring arm, capture the RAW
  `.conj` over `pkgFields` (the def's OWN package frame), UNNORMALIZED (each arm carries its own
  closedness through the re-fold; the `.conj` is not a flat struct to close).
- `forceClosureWithConjunctCore` — new `.conj arms` arm: re-fold `arms ++ (useOperands as structs)`
  via `evalValueWithFuel fuel capturedEnv [] (.conj …)`. This re-enters the `.conj` fold so a
  cross-pkg arm (`defs.#LS`) resolves its OWN import binding and defers correctly — exactly the
  inlined `defs.#LS & {…} & {narrow}` meet — instead of forcing the `.conj` standalone. Each arm
  keeps its OWN package frame because `capturedEnv` is the def's frame, NOT the use-site's.

**Wrong-frame hazard PINNED.** `crosspkg_defofdef_wrongframe_witness`: defs-local `_region:"US"` vs
defaults-local `_region:"EU"`; the inner selector's `zone: _region` MUST resolve in defs' frame. kue
now yields `zone:"US"` — a use-site-frame splice would mis-resolve to "EU"/bottom. Confirms each
conjunct resolves in its own package frame.

**Soundness.** narrowed == inlined == cue (oracle-confirmed on the `example.com` 3-package module +
the inlined same-file form); a real conflict still bottoms (`kind:"Other"` vs the def's fixed
`"ListenerSet"` → `_|_`); closedness survives the re-fold (a use-site extra the closed def-of-def does
not declare is rejected). cert-manager canary content-identical (jq -S diff = 0; the WHOLE
Bug2-4..2-11 delivery/closedness machinery is live, high blast radius — green). Axiom-clean
(`propext`/`Classical.choice`/`Quot.sound`), total (no `partial`/`sorry`/new axioms).

**Tests.** 4 module fixtures (`testdata/modules/crosspkg_defofdef_{narrowed,chain,wrongframe_witness}`
+ `crosspkg_singlelevel_narrowed` control) + 3 inlined `testdata/cue/definitions/bug211_defofdef_*`
(narrowed / rejects-extra / conflict) + FixturePorts entries + 4 `native_decide` pins (TwoPassTests
`### Bug2-11`: def-of-def + sibling-disj narrows, rejects-extra, conflict-bottoms, single-level
control) + the `#check @bug211_singlelevel_narrowed` sentinel.

**argocd — THE MILESTONE: still bottoms (~54s, `conflicting values`); NOT exported.** But the fix is
confirmed effective on the REAL app: the `defaults.#ListenerSet` `listener.yaml` subtree now FULLY
narrows (`metadata.name "argocd-ls"`, `#passthrough_hosts ["argo.prodigy9.co"]`, all `#additions`
resolved). The SOLE remaining `_|_` is in `route.yaml` (`rt = defs.#TLSRoute & {…}`): `#service_port:
_|_` (+ `#listenerset_name: _|_` downstream). Root, minimally diagnosed + FILED as **Bug2-13**: a
presence-test (`#opt == _|_` / `!= _|_`) on an UNSET OPTIONAL field returns the WRONG polarity — kue
fires the `if #service != _|_` arm in `attr.#ServiceRef` (instead of `if #service == _|_`), evaluating
`#service.#ports[0]` = `[...int][0]` (out-of-bounds on the empty list TYPE), which bottoms when met
with the use-site `443`. Self-contained 2-line repro: `x: {#opt?: {a:int}, eq: #opt == _|_, neq: #opt
!= _|_}` — cue `eq true, neq false`; kue the opposite. **HONEST depth read: ONE empirically-confirmed
remaining on-path layer (Bug2-13); whether a further bug hides behind it is unknown until it's fixed
and argocd re-run** (no "one fix away" over-claim — Bug2-13 is the only layer I have empirically
verified). Perf frontier #7 stays GATED.

**Files.** `Kue/Eval.lean` (`resolveSelectorDefBody?`, `conjBodyHasDeferringArm`, `.conj`-body capture
in `importDefClosureBody?`, `.conj` force-fold arm in `forceClosureWithConjunctCore`),
`Kue/Tests/TwoPassTests.lean` (`### Bug2-11` section + sentinel), `Kue/Tests/FixturePorts.lean` (3
`bug211_defofdef_*` entries), `testdata/cue/definitions/bug211_defofdef_*.{cue,expected}` (3 pairs),
`testdata/modules/crosspkg_{defofdef_narrowed,defofdef_chain,defofdef_wrongframe_witness,singlelevel_narrowed}/`,
`docs/spec/{spec-conformance-audit,plan}.md` (Bug2-11 RESOLVED + Bug2-13 filed), this log.

---

## Completed Slice: Bug2-13 — unset optional selection reads as ABSENT (`7e69e43`)

Goal: a presence-test (`#opt == _|_` / `#opt != _|_`) on an UNSET OPTIONAL field must read the
field as ABSENT (`_|_`), matching cue. kue returned the WRONG polarity — it resolved an unset
optional field reference to its declared TYPE (a present `.struct`/`.prim`), so
`classifyDefinedness` read `.defined` → `== _|_` wrongly false / `!= _|_` wrongly true, and a
`if #opt != _|_ {…}` comprehension arm fired when it must not. CUE's model: an optional
declaration is a CONSTRAINT, not a value; until unification SUPPLIES the field it is absent, and a
reference/presence-test against it is `_|_`. The 4th remaining argocd `route.yaml` blocker
(`#service_port` in `attr.#ServiceRef`).

### The fix

The design note predicted the polarity bug lives in field SELECTION (not the classifier) and named
`selectedFieldValue` as the candidate seam. That was HALF right: the eager `.selector` pluck
(`selectedFieldValue`, fixed) handles a DIRECT select `x.#opt`, but the presence-test operand
`#opt` is a SIBLING reference that resolves through the `.refId` eval arm
(`evalValueCoreWithFuel`) — which reads `Field.value field` (and the `refDefClosureBody?` /
`refAliasDefClosure?` producers) with NO optionality check. So the fix is TWO sites, both producing
the value the classifier sees:

- `selectedFieldValue` — `match field.fieldClass.optionality with | .optional => .bottom | _ => …`
  (the existing def-close / raw-yield logic). Covers the direct-select path.
- the `.refId` eval arm — right after `nthField` finds the field, `match
  field.fieldClass.optionality with | .optional => pure .bottom | _ => …` (the existing producer
  chain). Covers the sibling-reference / presence-test path.

The discriminator is the `.optional` presence rung ITSELF — structural, not a heuristic. Supplying a
regular conjunct (`#opt: v`) downgrades optionality to `.regular` through `mergeFieldClass`'s
`lo.meet ro` (`optional.meet regular = regular`), so a SET optional is no longer `.optional` and
keeps resolving to its value; the over-fire guard needs no separate "is it set" test. Presence, not
concreteness: a concrete-typed unset optional (`#opt?: 5`) is still `.optional`, hence still absent,
matching cue. This is the selection-time analog of `containsBottomFields`'s optional-skip
(`Lattice.lean`) — an unset optional, when read, is absent.

### Tests

7 `native_decide` pins (`TwoPassTests.lean` `### Bug2-13` section + sentinel
`bug213_def_meet_set_optional_present`): unset optional FLIPPED to `eq true/neq false`; SET optional
UNCHANGED `eq false/neq true` (over-fire guard); non-def optional (generality); concrete-typed unset
(presence-not-concreteness); comprehension-guard fires the ABSENT arm (the argocd `attr.#ServiceRef`
shape); def-meet unset/set fork (both halves through a `#D & {…}` meet). 4 export fixture pairs
(`testdata/export/bug213_*.{cue,json}`, self-validating via `check_export_fixtures`, no FixturePorts
entry needed). All oracle-confirmed vs cue v0.16.1. Spec-grounded — no `cue-divergence` or spec-gap
to record (kue now matches cue exactly; no residual). Axiom-clean, total. cert-manager
content-identical (jq -S diff = 0).

### Soundness + argocd milestone

Unset optional == cue on all 6 design-note witnesses; SET optional + required byte-identical;
cert-manager content-identical. Bug2-13 CLEARED `route.yaml`'s `#service_port: _|_` (the
`attr.#ServiceRef` arm now fires correctly). **argocd — THE MILESTONE: STILL bottoms (~54s,
`conflicting values`); NOT exported.** The SOLE remaining `_|_` is now `route.yaml`'s
`#listenerset_name: _|_` (= `ls.#name`). Root, minimally diagnosed + FILED as **Bug2-14**: field
selection from a `.structComp` bottoms — `selectEvaluatedField` has no `.structComp` arm, and `ls =
defaults.#ListenerSet & {…}` resolves to a `.structComp` whose `#UseCertManager`/`#Mixin`
`for`-comprehension is left UNDRAINED (cue drains it to a plain struct), so `ls.#name` → `_|_` (every
field select on `ls` bottoms; `ls` itself exports fine in `listener.yaml`). 5-package repro; the
inline single-file collapse does NOT reproduce (needs the cross-pkg def-of-def + mixin disjunction).
**HONEST depth read: ONE empirically-confirmed remaining on-path layer (Bug2-14); whether a further
bug hides behind it is unknown until it's fixed and argocd re-run** — no "one fix away" over-claim.
Perf frontier #7 stays GATED (argocd does not yet export). A separate, lower-pri observation surfaced
while pinning: `x.a.missing != _|_` on a genuinely-MISSING field of a regular struct → kue
`incomplete value` vs cue `false` (distinct from the unset-optional case; not on the argocd path;
noted for a future missing-field-selection slice).

### Files

`Kue/Eval.lean` (`selectedFieldValue` optional arm + the `.refId` eval-arm optional guard),
`Kue/Tests/TwoPassTests.lean` (`### Bug2-13` section + sentinel),
`testdata/export/bug213_{unset_optional_absent,set_optional_present,nondef_optional_absent,comprehension_guard_absent}.{cue,json}`
(4 pairs), `docs/spec/{spec-conformance-audit,plan}.md` (Bug2-13 RESOLVED + Bug2-14 filed), this log.

---

## Completed Slice: Bug2-14 RE-DIAGNOSIS (no code shipped — sound fix is on the embed-merge tier, PARKED)

Goal: fix the on-path argocd blocker filed as Bug2-14 (field select from a `.structComp` bottoms).
Outcome: the FILED root-cause was wrong; the tried fix was unsound and REVERTED; the TRUE root is
re-diagnosed + filed; tree clean, NO code shipped. A negative result with a precise diagnosis.

### What was tried (and reverted)

The filing blamed `selectEvaluatedField`'s missing `.structComp` arm (`| _ => .bottom`). Implemented
a `drainStructCompForSelect` (re-eval the `.structComp` base before selecting, reusing the
`.structComp` eval arm as the single drain path) + a defer arm for a surviving residual. It fixed the
static selects (`ls.#name` → `"argocd-ls"`, the `route.yaml` `#listenerset_name` symptom; faithful
5-package repro export-identical to cue for the static fields). BUT it proved UNSOUND: re-evaluating
`ls` forces the residual `.structComp` to a plain `.struct` that DROPS comprehension-contributed
content — `ls.metadata` then yields `{name:…}` MISSING `metadata.annotations.issuer` (cue:
`{annotations:{issuer:…}, name:…}`). Trading `_|_` for a silently-wrong-complete value violates
correctness-first → fully REVERTED (tree back to `3e0f396`, `git diff` empty).

### The TRUE root (empirically pinned)

When a struct EMBEDS a block declaring a field ABSTRACTLY which the HOST declares CONCRETELY, and the
embed carries a comprehension reading that field, the comprehension's sibling-field ref binds to the
EMBED-LOCAL abstract value, not the merged host-concrete value → guard incomplete → never drains.
Minimal 6-line "case D": `host: { bk:"X", { bk:string, for k,v in {p:1} { if bk=="X" {hit:true} } } }`
— cue `{bk:"X", hit:true}`; kue eval leaves the `for` residual. Isolation (all oracle-confirmed):
embed-comprehension reading an embed-OWN concrete field DRAINS; reading a HOST-only field DRAINS;
reading a field in BOTH (embed-abstract × host-concrete) does NOT. This is exactly the argocd `#Mixin`
shape (`let _patch` declares `kind: string`; the host `defs.#ListenerSet` declares `kind:
"ListenerSet"`; the `for _, add in Self.#additions { if kind == add.#kind {…} }` guard reads the
embed-local abstract `kind`). TWO compounding layers: (1) the embed-merge frame-binding (case D,
general — but a DIRECT inline embed still drains under export's re-eval); (2) the CROSS-PACKAGE
DEF-OF-DEF FORCE path (`forceClosureWithConjunct`) produces a residual that can't drain even on export
→ bare `ls` exports silently-incomplete, `[ls]` (the `listener.yaml` shape) → `conflicting values`
via `Manifest`'s `.structComp` `containsBottomFields` arm. cert-manager (same `#UseCertManager`/`#Mixin`,
direct struct-shape) stays content-identical and DOES materialize `_patch` annotations — so the meet
machinery is right in the direct case; only the def-of-def force path leaks.

### Fix seam (PARKED for a dedicated slice)

Re-bind / re-expand the embed-contributed comprehension against the POST-MERGE host frame so its
sibling-field refs see the host-narrowed values — on the `forceClosureWithConjunct` /
`meetEmbeddingsWithFuel` / `.structComp`-fold tier, likely via the existing `remapConjValues` /
`remapConjRefs` ref-rebase facility. NOT a `selectEvaluatedField` change (selection is downstream;
select-time materialization is unsound). Full re-diagnosis + repros in `spec-conformance-audit.md`
Bug2-14 RE-DIAGNOSED block.

### argocd milestone

`kue export apps/argocd.cue` STILL bottoms (~54s, `conflicting values`) — NOT exported. Perf frontier
#7 STAYS GATED. cert-manager remains the only real-app drop-in.

### Files

`docs/spec/{spec-conformance-audit,plan}.md` (Bug2-14 RE-DIAGNOSED), `docs/notes/` (breadcrumb
rotated), this log. NO `Kue/*.lean` or `testdata/` changes (the only sound change found was a non-fix).

---

## Completed Slice: Bug2-14 — re-base embed-body sibling/comprehension reads onto host-narrowed value (case-D PLAIN-EMBED half)

Commit `e404b21` (2026-06-23). The general "case D" embed-merge frame-binding bug, RESOLVED for the
PLAIN-EMBED path. NOT the terminal argocd blocker — a distinct 2nd layer (Bug2-14b, below) remains.

### Behavior added

An embed that declares a label ABSTRACTLY (`bk: string`) which the host declares CONCRETELY
(`bk: "X"`) left the embed body's sibling read (`echo: bk`) or comprehension guard (`if bk == "X"`)
bound to the EMBED-LOCAL frame — the embed is its own frame, so the read is depth-0 into its own slot,
never the host's. The host's narrowing reached the embed-output only via the later `meet host (embed)`,
too late for the captured read: the plain ref exported `string`, the guard never fired (the
comprehension deferred → export incomplete). Now BOTH case-D forms resolve against the host-narrowed
value (`echo: "X"`, `hit: true`), == cue v0.16.1.

### Mechanism

`injectEmbedSiblingNarrowings` (`Eval.lean`, a standalone fuel-total def) is applied at
`meetEmbeddingsWithFuel`'s plain-embed eval (the `| none => evalValueWithFuel … embedding` arm): the
host's (`current`'s) regular-output `(label, value)` narrowing (`hostNarrowingPairs`) is MET into the
embed body's same-label read-and-declared slot BEFORE the body evaluates, so the read sees the merged
value. The analog of `injectLetLocalNarrowings` (Bug2-4) for an embed body rather than a let-local;
reuses `embedComprehensionReadLabels` for the read-label set (it captures a plain depth-0 sibling ref
AND a comprehension guard/source read). Recurses into nested embeds (multi-level) and let bodies.

### Soundness boundary

Re-base IFF the label is BOTH embed-declared (a regular-output field of the embed body) AND
host-narrowed (present in `current`'s regular fields). A label the embed declares but the host does NOT
narrow (`other: string` read by `echo: other`) is not in `hostNarrowingPairs` → untouched, stays
embed-local and incomplete — the over-rebase guard (pinned). A real conflict still bottoms
(`int & "X"` = ⊥; never a silent merge). The injection only MEETS the host narrowing into a field the
host narrows anyway — never invents a value, never widens past the use-site meet. General, not keyed to
argocd identifiers.

### Tests

8 `native_decide` pins (`Bug2xTests.lean` Bug2-14 section, tripwire anchor
`bug214_conflicting_type_bottoms`): plain sibling-ref, comprehension guard, multi-level embed, nested
comprehension, embed-own-concrete stays-drained, host-only stays-drained, over-rebase guard, conflict
bottoms. 2 export fixtures (`testdata/export/bug214_embed_{plain_sibling_ref,comprehension_guard}.{cue,json}`,
oracle-generated, `cue fmt`-clean). cert-manager content-identical (jq -S = 0). Full suite + fixtures
green; no new warning/`sorry`/axiom.

### Bug2-14b filed (the actual on-path argocd blocker — PARKED)

The design's "the cross-package def-of-def force-path is the SAME fix" read was EMPIRICALLY WRONG —
argocd STILL bottoms (`conflicting values`, ~53s) after the plain-embed fix. The on-path shape is a
STRUCTURAL DISJUNCTION (`listShape | structShape | error`) embedding a `let _patch` whose `for…if
kind==…` guard reads a host-narrowed sibling `kind`; on the CROSS-PACKAGE FORCE path
(`forceClosureWithConjunctCore`) the host's `kind` does not reach `_patch.kind` through the disjunction
arm → the comprehension defers → `metadata.annotations` drops. The single-level cross-package use
already drops it (NOT def-of-def-specific); the direct inline form drains. Fix is let-local
narrowing-through-structural-disjunction on the force path (Bug2-4 × Bug2-5 × Bug2-11), a dedicated
embed-merge slice. Self-contained 4-package repro + filing in `spec-conformance-audit.md` Bug2-14b.

### argocd milestone

`kue export apps/argocd.cue` STILL bottoms (`conflicting values`, ~53s wall) — NOT exported. The 5-pkg
def-of-def force path does NOT drain post-fix (Bug2-14b is a genuinely distinct 2nd layer). Perf
frontier #7 STAYS GATED. cert-manager remains the only real-app content-identical drop-in (~12.6s).

### Files

`Kue/Eval.lean` (`injectEmbedSiblingNarrowings`, `hostNarrowingPairs`, the
`meetEmbeddingsWithFuel` plain-embed injection), `Kue/Tests/Bug2xTests.lean` (8 pins + tripwire),
`testdata/export/bug214_embed_*` (2 fixture pairs), `docs/spec/{spec-conformance-audit,plan}.md`,
`docs/reference/implementation-log.md`, `docs/notes/` (breadcrumb rotated).

---

## Completed Slice: Bug2-14b + Bug2-14c — disjunction-arm let-local narrowing on the force path (argocd EXPORTS)

Goal: deliver the host's `kind` narrowing into a `let _patch` living inside the surviving arm of a
structural disjunction (`listShape | structShape | error`) on the cross-package FORCE path — the last
two on-path argocd blockers. **MILESTONE: `kue export apps/argocd.cue` now exports CONTENT-IDENTICAL to
cue (jq -S diff = 0, 37230 bytes both, ~53s wall) — argocd is the 2nd prod9 real-app content-identical
drop-in after cert-manager.**

### Empirical diagnosis (traced, not designed)

The design's predicted lever (disjunction-arm distribution) was again falsified by trace. TWO distinct
on-path layers, isolated by `dbg_trace` over the faithful self-contained repro (`/tmp/argols`, REAL
`prodigy9.co/defs@v0.3.19` from cache):

- **Bug2-14b — wrong-frame disjunction-deep gate.** `embedBodyEmbedsDisjDeep` was evaluated against the
  OUTER meet-fold / conj-fold `env`, but a closure body's OWN embed-refs (`#Use: { #Mixin; … }`'s
  `#Mixin` is a `.refId depth:=1`) are relative to the def frame `forceClosureWithConjunctCore` PUSHES.
  Against the bare outer `env` the ref resolved to the WRONG frame (trace: `#Mixin` resolved to the
  string `"ListenerSet"` — the Bug2-11 wrong-frame hazard), so the transitively-embedded disjunction was
  missed, the gate returned `false`, and `spliceOperandForEmbed` dropped the host's regular `kind` →
  never reached `_patch.kind`. The single-closure repro (`#LS: { kind; parts.#Use }`) dropped annotations
  silently; `[ls]` → `conflicting values`.

- **Bug2-14c — cross-conjunct regular narrowing in the multi-closure `.conj` fold.** The Bug2-14b fix
  alone did NOT drain argocd: the real `defaults.#ListenerSet = defs.#ListenerSet & parts.#UseCertManager
  & {…}` is a MULTI-CLOSURE conjunction where `kind` lives in closure A (`defs.#ListenerSet`) but the
  `#Mixin` disjunction + `_patch` live in closure B (`parts.#UseCertManager`). The `.conj` fold
  (`allClosures` path) forced each closure independently with only the plain-struct operands as shared
  `useOperands` — so closure B never saw closure A's regular `kind`. Trace: `CONJ-FOLD nClosures=2`,
  closure A `[…, kind, spec]`, closure B `[…, _patch, #additions]`, shared `useOpLabels` carried the
  hidden `#…` fields but NOT `kind`.

### Implementation

- `bodyForceFrameEnv (capturedEnv body) := (0, body-statics) :: capturedEnv` helper (DRY), applied at
  all THREE `embedBodyEmbedsDisjDeep` body-gate sites (the `meetEmbeddingsWithFuel` closure-force, the
  `evalEmbeddingFieldsWithFuel` closure-force, the multi-closure fold). This is the Bug2-14b fix.
- A TWO-PASS multi-closure fold (Bug2-14c): pass 1 forces each closure with the base operands and
  collects its forced REGULAR-output fields; pass 2 re-forces ONLY a `embedBodyEmbedsDisjDeep`-bearing
  closure with the SIBLING closures' regular fields spliced as an extra operand (dropping its own
  labels). Sound: the spliced operand is the SAME Gap-2b regular-field route a single-closure embed gets,
  idempotent on a field an arm already carries; a real conflict still bottoms; a no-disjunction closure
  keeps its pass-1 result (byte-identical — no re-force).

### Soundness (verified)

force-path == direct-inline == cue (the faithful repro byte-matches). Arm selection stays correct (the
`structShape` arm wins, `listShape`/`error` prune — `DISJ-DISTRIB` trace `[BOT, struct[…metadata…],
BOT]`). Incomplete-guard (abstract `kind`) DEFERS as `incomplete value`, does NOT force-drain (cue picks
the `error` arm — both correctly NON-drain; recorded in `cue-spec-gaps.md`). Real conflict BOTTOMS.
cert-manager content-identical (jq -S = 0). Frame correctness pinned by the cross-package module fixtures.

### Tests

Module fixtures `testdata/modules/bug214b_disjarm_letlocal_force` (single-closure embed chain) +
`bug214c_disjarm_letlocal_crossconj` (multi-closure conjunction, the argocd shape) — both `kue == cue`
via `check-fixtures.sh`. Inline `native_decide` pins `Bug2xTests` `bug214b_disj_arm_{drains,
incomplete_guard_defers, conflict_bottoms}` + tripwire anchor. Full build clean (112 jobs), fixtures +
shellcheck green.

### argocd milestone

`kue export apps/argocd.cue` → CONTENT-IDENTICAL to cue (jq -S diff = 0, 37230 bytes, ~53s wall). Perf
frontier #7 UN-GATED (argocd's last on-path correctness blocker cleared; the ~53s is now pure perf). A
fresh alpha is flagged as a NOTABLE-milestone release worth the user's greenlight.

### Files

`Kue/Eval.lean` (`bodyForceFrameEnv` helper; the three gate-site fixes; the two-pass `.conj` fold),
`Kue/Tests/Bug2xTests.lean` (3 pins + tripwire), `testdata/modules/bug214{b,c}_*` (2 module fixtures),
`docs/spec/{spec-conformance-audit,plan}.md`, `docs/reference/{implementation-log,cue-spec-gaps}.md`,
`docs/notes/` (breadcrumb rotated).

---

## Completed Slice: perf #7 — self-evaluating-leaf fast path + saturated-only satCache

Goal: attack the FLAT per-eval setup constant that makes argocd export in ~53s where `cue`
takes 0.03s. Profiling first (the gate: a precise profile is a valid outcome), then a
SOUND, value-preserving optimization only if the profile reveals one.

### The profile (the bankable finding)

Instrumented `evalValueWithFuel` over a full `kue export apps/argocd.cue` run (832K-eval
top-level eval). The decisive numbers:

- `evalCalls=832338` core (cache-miss) evals, `satHits=125319`, **`evalCacheHits=0`** — the
  fuel-keyed `cache` NEVER hits on this app; every re-served value comes from the fuel-free
  `satCache` (everything reachable is saturated). The `cache` was pure overhead (832K inserts
  read zero times).
- **`distinctShapes=4763`** (distinct value subtrees at digest-depth 8) vs 832338 core evals
  → a **~175× re-evaluation factor**: the SAME value subtree is core-evaluated ~175× because
  it is reached under ~175 distinct frame envs, and the cache keys on `env.ids`. This is the
  root shape — frame-id divergence preventing cross-scope sharing, NOT a fuel-axis problem,
  NOT an O(N²) hash-bucket problem (DIGEST_DEPTH 1 vs 3 measured FLAT in wall-time, so the
  item-7 hash is well-tuned and the digest cost is not the wall).
- Tag histogram of the 832K core evals: `.prim` 185306, `.struct` 128644, `.kind` 123425,
  `.refId` 108199, `.binary` 65935, `.conj` 48528, `.selector` 39098, `.list` 34753.
  **`.prim`+`.kind` = 308731 ≈ 37%** of all core evals are ENV-INDEPENDENT self-evaluating
  constants re-keyed per distinct env.
- `forceCalls=45746`, `forceSize=30103` — the force memo is small and NOT the wall (the
  item-7 lens applied to the SETUP closure: force-cache is fine; the cost is the leaf/struct
  re-eval count × the per-eval hash+map constant).

The flat-per-field signature is reproduced: selecting any single field (`-e "…"`) fires the
identical 832338-eval line — `selectExprPath` does `resolveAndEval root` (the whole-root eval)
before the lookup, so a 484-byte field costs the full root eval.

### The optimizations (two, both provably value-preserving)

1. **Self-evaluating-leaf fast path.** `evalValueWithFuel` short-circuits — returns the value
   directly, no cache touch, no `truncCount` move — for `selfEvaluatingLeaf?`: the constructors
   (`.prim`/`.kind`/`.top`/`.bottom`/`.bottomWith`/`.notPrim`/`.stringRegex`/`.boundConstraint`/
   `.thisStruct`) that fall through `evalValueCoreWithFuel`'s trailing `| _, value => pure value`
   arm, which reads none of `fuel`/`env`/`visited`. **Soundness:** for these, core eval is the
   IDENTITY at every fuel ≥ 1; at fuel = 0 the core only adds a SPURIOUS truncation (`| 0, value
   => truncate value`) for a value that was never fuel-sensitive, so skipping it removes only
   FALSE `truncated` classifications a fuel-0 leaf would inject, never a genuine one (a subtree
   that truly needs fuel bottoms on a `.refId`/struct-unroll — NOT a leaf — and still truncates).
   The predicate is a strict subset of the core's catch-all set (conservative: a constructor the
   core handles non-trivially is never listed; one omitted merely keeps the sound slow path).

2. **Saturated-only `satCache` insert.** A saturated result is now stored ONLY in the fuel-free
   `satCache`, never in the fuel-keyed `cache`. **Soundness:** `evalValueWithFuel` checks
   `satCache` FIRST; a saturated value is therefore always served from `satCache` before
   `cache.get?` is reached, so its `cache` entry was provably dead (read zero times — confirmed by
   `evalCacheHits=0`). `cache` now holds only the fuel-TRUNCATED (fuel-sensitive) population, which
   must stay fuel-keyed. `cache` is read/written at exactly one site each (both inside
   `evalValueWithFuel`), so no other path depends on saturated entries living there.

Neither weakens `BEq`/digest soundness; the `Value` `DecidableEq` carve-out is untouched. The
hash only selects a bucket; `BEq` remains the sole equality arbiter.

### Measured

argocd `kue export` **~53.4s → ~50.3s user** (~6%), jq -S diff = 0 (51178 bytes, byte-identical
to cue). cert-manager **~12.6s → ~11.7s**, jq -S diff = 0 (1448 bytes). Full `native_decide`
suite + `check-fixtures.sh` green, ZERO fixture drift. The win is modest because the fast path
eliminates the per-eval hash+map cost of the 37%-of-count leaves, but each leaf is trivial work,
so the wall-time slice is small; the dominant cost is the ~175× re-eval of env-DEPENDENT shapes
(structs/refs/conjunctions under divergent frames), which a leaf bypass does not touch.

### Designed next step (deferred — not a one-slice safe change)

The remaining ~50s is the ~175× re-evaluation of env-DEPENDENT value shapes. The principled fix
is sharing those evaluations across frame envs — either more aggressive frame canonicalization
(so structurally-identical def bodies forced under different resource scopes collapse to one
frame id, hitting the env-keyed satCache) or content-addressing def-body closures independent of
the capturing frame. Both touch the soundness core of frame identity (the `FrameKey`/`ForceKey`
proxy argument) and need their own soundness proof + a no-false-share boundary — a dedicated
slice, gated, not foldable into this one.

### Tests

The 5 `evalStructRefsCalls` perf pins in `EvalPerfTests.lean` shifted to their new (lower) counts
— a pure metric move from no longer counting env-independent leaves as core evals; the COMPANION
VALUE pins (`eval_deep_inline_value_correct`, `selpass_value_correct`) are UNCHANGED and green,
witnessing value-preservation. `deepInlineRoot` slope `2·depth+2 → 2·depth+1`; `selPass` slope
`+5 → +3`/field, base `21 → 12` at n2.

### Files

`Kue/Eval.lean` (`selfEvaluatingLeaf?` predicate; the fast-path guard in `evalValueWithFuel`; the
saturated-only `satCache` insert), `Kue/Tests/EvalPerfTests.lean` (5 perf-pin counts + 2 comments),
`docs/guides/kue-performance.md`, `docs/spec/plan.md`, `docs/reference/implementation-log.md`,
`docs/notes/` (breadcrumb rotated).

## 2026-06-23 — Plan-hygiene pass (docs-only; distill the design record to the live roadmap)

Periodic plan-hygiene pass (slice-loop guide), DUE after the Bug2-5..2-14c chain (10 fixes)
+ ~7 two-phase audit rounds + perf #7 landed the argocd content-identical drop-in (2nd prod9
real app). DOCS-ONLY — no `Kue/`/`testdata/`/`scripts/` touched; `lake build` +
`check-fixtures.sh` re-confirmed green.

**`docs/spec/plan.md` 1121 → 710 lines (shed ~411).** Shed (now in this log + git): the
Bug2-5..2-14c blow-by-blow in Standing Capabilities + Live Backlog; the ~7 closed Phase-A/B
audit-round HEALTHY verdicts (collapsed to ONE per-round-history summary that preserves the
recurring whole-graph invariants — acyclic strict layering, the cleanliness sweep, test-health
— plus the `Eval.DefDeferral` carve-trigger); the superseded perf-#7 dump. Kept (live): North
Star, Working Principles, Standing Capabilities (argocd = drop-in #2 ~50.3s, cert-manager
~11.7s, Bug2-x CLOSED), the ranked OPEN backlog with perf #7 frame-sharing as the proof-first
GATED leader, ALL durable rulings (inject-family / resolveDefField? / mergeFieldsWith /
embedChainAny / CARRIER share-no-share / escape-helper / AD2-1 / DRY-1 / BI-EFF / F-CASE-ARCH /
FOUR-classifiers / AD3-x / Order.lean), Pointers. All links resolve.

**`docs/spec/spec-conformance-audit.md` 1236 → 607 lines (shed ~629).** Marked the whole
Bug2-5..2-14c family RESOLVED — compressed to a per-fix one-liner summary + a log/git pointer;
dropped the Live-slice mechanism blocks (Bug2-5..2-10 full diagnoses) and the Bug2-x DESIGN
NOTES. Re-ranked the genuinely-open backlog: perf #7 (leader) · SC-4 · Bug2-12
(cycle-closedness leak, still open) · missing-field-selection · item-6 LOW tail. Kept the
HIGH/MED SHIPPED spec-conformance records (BI-2, SC-1b/1e, D#2, …) and the SC-4 open entry.
Fixed a dangling "SUPERSEDED banner" reference.

**`www/index.html` refreshed** (served human-facing status, OUTSIDE the design-record): argocd
flipped Parked → Done (2nd content-identical drop-in, jq -S = 0, ~50.3s); cert-manager ~11.7s;
math.Pow/Sqrt full-real-domain in exact decimal; the live frontier is perf #7 frame-sharing
(proof-first, gated); footer date 2026-06-23, release 20260622. All 6 illustrative CUE blocks
unchanged; the self-contained ones re-vet clean in `cue`.

No live backlog item or durable ruling dropped; all internal doc links verified resolving.
Breadcrumb rotated → `docs/notes/2026-06-23-resume-plan-hygiene-argocd-milestone.md`. Files:
`docs/spec/plan.md`, `docs/spec/spec-conformance-audit.md`, `www/index.html`,
`docs/reference/implementation-log.md`, `docs/notes/` (breadcrumb rotated).

## 2026-06-23 — perf #7 frame-sharing: DESIGNED-AND-DEFERRED → WON'T-FIX

The dedicated, proof-first, GATED slice for perf #7's residual root — the ~175× re-evaluation of
env-DEPENDENT value shapes (`evalCalls≈832K` for `distinctShapes≈4763` at digest-depth 8, the cache
keying on `env.ids` so the same shape under ~175 frame envs re-evaluates ~175×). The designed fix:
collapse structurally-identical def bodies forced under different resource scopes to one canonical
frame identity (or content-address the def-body closure key), so the cache keys on CONTENT not on an
allocation-divergent frame id, enabling cross-scope `satCache` sharing.

### The no-false-share invariant (established BEFORE any code)

The whole memo system is sound because **`env.ids` is a sound proxy for env CONTENTS**: the
`FrameKey = (parentIds, fields)` canonicalization proves two envs sharing an id stack are
contents-equal frame-by-frame (inductively over `parentIds`). So `EvalKey`/`SatKey`/`ForceKey`
keying on `env.ids` never returns a value computed for a different env. Two forces of a def body are
**share-equivalent** iff their captured envs agree on EVERYTHING the body can OBSERVE — i.e. the
reachable captured bindings up to the body's free-variable set (the depth-indexed `refId` reach).
Canonicalizing two frames that DISAGREE on an observable binding = a FALSE SHARE = a silent wrong
value = a Violation. The proof obligation: bound the observable-frame set and prove the merged
frames agree on it.

### Why DEFERRED-as-WON'T-FIX, not shipped, and not "proof too hard"

Rather than wrestle the (genuinely subtle) observable-depth bound — the producers' captured env is
`pushFrame pkgFields env` over the FULL resource `env`, while the body is authored against
`env.drop(id.depth+1)`, so the observable depth cannot be statically bounded at ≤1 in one slice — I
**measured the win ceiling first** with a zero-risk instrument: a content-addressed SHADOW of
`satCache` keyed on the FULL env CONTENTS (`(env, visited, value)` compared by derived structural
`BEq`, hashed via `valueDigest`-over-frames), counting how many `satCache`-miss core evals a
content-addressed env key would COLLAPSE — i.e. envs that are content-identical but id-distinct,
exactly the frames a sound canonicalization could merge. The shadow is never read by the result
path (correctness untouched); it only counts.

Whole-root export measurement (counts exact + deterministic; the shadow's extra hashing inflated
wall-time, irrelevant to the counts):

| app          | core evals (satMisses) | content-collapsible | ceiling |
|--------------|-----------------------:|--------------------:|--------:|
| cert-manager |                317,788 |                 144 |  0.045% |
| argocd       |                486,773 |                 288 |  0.059% |

**The ~175× re-eval is REAL but NOT content-redundant.** `distinctShapes≈4763` measured SHAPE
similarity at digest-depth 8; the cache correctly keys on CONTENT (via the sound ids-as-content
proxy). When the same shape is reached under ~175 frame envs, those envs carry ~175
GENUINELY-DIFFERENT observable bindings (distinct resource fields, distinct use-site narrowings) —
distinct evaluations that share a top shape but not a resolved value. Collapsing them is a FALSE
SHARE (serve one resource's value for another → wrong value), which is exactly why the ceiling is
~0%: there are almost no id-distinct-but-content-identical envs to recover. So no sound
frame-sharing widening (aggressive canonicalization OR content-addressed closure key) can reclaim
the ~175× — it is the IRREDUCIBLE cost of genuinely-distinct content, not id-divergence waste. The
proof obligation is moot: the share it would license is empirically almost empty AND unsound where
non-empty.

### Outcome

NOTHING SHIPPED (no `Kue/` change; the instrument was fully reverted, tree clean, build green). This
is the correct STOP outcome the correctness-over-performance decision codifies — except the stop is
backed by hard data, not a deferred-proof punt. perf #7's frame-sharing leg is CLOSED as won't-fix.
The live perf frontier rotates to the per-eval CONSTANT / eval COUNT over a genuinely-large distinct
population (item-6 LOW tail or a future per-eval-cost slice); the residual ~50s argocd / ~12s
cert-manager is addressable only by lowering per-eval cost or eval count (flatten/shorten chains —
the user-controllable lever), NOT by cross-env sharing.

DOCS + measurement only — no behavior change, so no fixture/canary drift possible; `lake build`
green on the reverted tree, both canaries jq -S = 0 (unchanged from baseline). Files:
`docs/guides/kue-performance.md` (perf-#7 frame-sharing DESIGNED-AND-DEFERRED block + ceiling table),
`docs/spec/plan.md` (leader block + item 5 → won't-fix), `docs/reference/implementation-log.md`,
`docs/notes/` (breadcrumb rotated).

---

## Completed Slice: Bug2-12 — self-recursive closed def must still reject use-site extras

### Goal

Close a closedness SOUNDNESS leak on the structural-cycle path. `#X: #X & {a:1}` (a SELF-recursive
CLOSED definition) then `out: #X & {b:2}` ADMITTED `b` (`{a:1,b:2}`); `cue` v0.16.1 REJECTS
(`out.b: field not allowed`). The inlined form `(#X & {a:1}) & {b:2}` leaked identically, confirming
the gap is in the cycle/closedness interaction, not a flatten-specific path.

### Spec basis (verified FIRST)

`cue` is SPEC-CORRECT here. Closedness is a property of the definition, independent of how its body
self-references; self-recursion does NOT re-open it. Cross-checked the consistency: `#A & #B` (distinct
closed-def meet) rejects both sides in BOTH kue and cue; the one-way `#A: #B & {a}`, `#B: {b}`
(non-recursive) rejects `#A.a` in both — cue's closed-meet rule is internally consistent. So the
self-recursive reject IS spec-mandated, not a cue artifact → FIX (not record-and-match).

### Root cause

The def body `#X & {a:1}` parses to a `.conj [#X, {a:1}]`. Two closing paths skip it:
- `refDefClosureBody?` only fires for a struct-LIKE body (`.struct`/`.structComp`); a `.conj` body
  returns `none`, so the standalone bare-ref path resolves via the structural-cycle `recurseBody`
  WITHOUT closing.
- The def-body closer `normalizeDefinitionValueWithFuel` had NO `.conj` arm — a `.conj` body hit the
  `| _, value => value` tail UNCHANGED.

So `#X`'s self-recursion terminated (`structStack` bottoms the inner `#X` with `.structuralCycle`) and
the surviving `{a:1}` was OPEN. At the use site, `flattenConjDefRef` unrolled `#X & {b:2}` into open
`{a:1}` literals + `{b:2}`, merging to an open struct that admitted `b`.

### Fix (`flattenConjDefRef`, `Eval.lean`)

When expanding a DEFINITION field whose `.conj` body is genuinely SELF-REFERENTIAL — a depth-0
conjunct refs the SAME slot index being expanded — close each expanded conjunct via
`normalizeDefinitionValueWithFuel`. The struct literals close (`{a:1}` → `defClosed`, rejecting a
use-site extra); the self-ref `.refId` conjunct is left UNCHANGED by the closer (no `.refId` arm), so
the structural-cycle path bottoms it identically — cycle DETECTION/termination is untouched (the fix
runs at the flatten, never on `structStack`).

The self-ref guard is the soundness boundary: a NON-self-recursive multi-conjunct def (`#LS: #Base &
{#extra}`, Bug2-6..9 — `#Base` is a DIFFERENT slot, not a back-ref) is NOT self-referential, so its
narrowing conjuncts stay OPEN and the close-once-via-`closedClauses` fold is preserved unchanged. (An
earlier attempt — a blanket `.conj` arm in `normalizeDefinitionValueWithFuel` — over-closed: it broke
6 Bug2-6..9 pins by closing the `{#extra}`/`{#q}` narrowing structs of distinct-def meets at load.
Reverted in favor of the self-ref-gated flatten fix.)

### Boundaries (all == cue v0.16.1)

- REJECT: `#X: #X & {a:1}`, `out: #X & {b:2}` → `b: _|_`; the inlined form rejects identically; a
  non-matching pattern extra (`[=~"^p"]` def, `out: #X & {q1:5}`) rejects; a nested extra
  (`sub: {extra}`) rejects at depth.
- ADMIT (no over-close): a declared field (`a: int` & `a: 5` → `a: 5`); a pattern-MATCHING field
  (`p1: 5` under `[=~"^p"]`); an `...`-open-tail def admits any extra (`defOpenViaTail` preserved); a
  declared nested field admits.

### MUTUAL tail (recorded OPEN, NOT fixed)

Mutual recursion `#A: #B & {a}`, `#B: #A & {b}` is a DISTINCT leak: kue admits (`{a:1,b:2}`), cue
rejects even the def's OWN field (`#A.a: field not allowed`) under its closed-meet reading. cue's
mutual reading is lattice-questionable (a def rejecting a field it itself declares); the fix would need
transitive back-ref detection AND a decision on that questionable semantics, so it is recorded as an
OPEN spec-gap (`cue-spec-gaps.md` Bug2-12 MUTUAL row) rather than blindly matched — deferred as a
future fix-slice (guardrail #5: scoped to avoid over-reaching the cycle machinery).

### Tests + verify

11 `native_decide` pins in `Bug2xTests.lean` (`### Bug2-12` section): the 4 reject boundaries, 4 admit
boundaries (declared / pattern-match / open-tail / nested), + 2 D#2 GUARDRAILS re-pinned end-to-end
in this file (`#L:{n,next:#L}` still bottoms `.structuralCycle`; `#List | *null` still terminates on
`*null`). 4 fixtures (`testdata/cue/definitions/bug212_selfrec_{closed_rejects_extra,admits_declared,
opentail_admits,pattern_admits}.{cue,expected}` + `FixturePorts.lean` entries). Coverage tripwire
sentinel added. `lake build` clean (no new warning/`sorry`/axiom — `flattenConjDefRef` depends only on
`propext`); `scripts/check-fixtures.sh` → fixture pairs ok (only the 4 intended new fixtures);
cert-manager + argocd jq -S = 0 (prod9 has zero recursive defs, so the self-ref guard never fires).
LatticeTests/EvalTests D#2 pins green.

---

## Completed Slice: missing-field-selection — a missing field of a concrete struct reads as ABSENT

A presence-test on a genuinely-MISSING (never-declared) field of a concrete struct gave the WRONG
state. `x: {a: 1}` then `x.b == _|_` / `x.b != _|_` errored `incomplete value` under `export`; cue
v0.16.1 treats the missing field as ABSENT (`x.b == _|_` true, `x.b != _|_` false). The selection-time
analog and same family as Bug2-13 (`7e69e43`): a deferral was masking a final absence.

### Root cause

`selectFromDecls` (`Eval.lean`) plucks a label from an evaluated carrier's decls; on a MISS it returned
`.selector base label` — a deferred selection node. `classifyDefinedness` maps `.selector _ _ →
.incomplete`, so the presence-test comparison stayed unresolved and `export` reported `incomplete
value`. Only the SHALLOW case was observably broken: the audit's noted deep form `x.a.missing` was
ALREADY correct because the intermediate (`x.a = 1`) is a NON-struct prim, so the select hit
`selectEvaluatedField`'s `_ => .bottom` catch-all (not `selectFromDecls`). A field missing from a deep
STRUCT (`x.a.c` where `x.a = {b:1}`) was equally broken.

### The discriminator (spec-verified vs cue v0.16.1 — the crux)

The fix must bottom ONLY the final-absent case and never a provisional one. Established by oracle:

- **Concrete struct, field absent** → ABSENT (`x.b == _|_` true). Holds even for an OPEN `...` struct
  (`x: {a:1, ...}`): cue does NOT make a not-yet-declared field provisional at selection time.
- **Later conjunct supplies the field** (`x: {a:1}` ; `x: {b:2}`) → PRESENT. The conjuncts MERGE into
  one struct value BEFORE selection runs (kue's two-pass unifies at the struct level; `x: base & extra`
  likewise supplies `b` at unification), so `findEvalField` finds `b` — the field was never a miss.
- **Narrow-elsewhere** (`z: x & {b:2}`) → `x.b` stays absent, `z.b` present. Absence is per-struct-value,
  not leaked across a sibling meet.
- **Unresolved disjunction, no unique default** (`x: {a:1} | {a:1, b:2}`) → PROVISIONAL: a later arm
  could supply the field, so it must NOT be bottomed. cue reports the whole value `incomplete`.

The discriminator is therefore STRUCTURAL, not a heuristic: **whatever reaches `selectFromDecls` is an
already-evaluated concrete struct/embed carrier (or a resolved disjunction DEFAULT arm), so a miss is
FINAL.** The PROVISIONAL case never reaches `selectFromDecls` — `selectEvaluatedField`'s `.disj` arm only
routes there once `resolveDisjDefault?` picks a concrete arm, and otherwise keeps the deferred
`.selector base label` in its `_ =>` arm (untouched).

### Fix

One line in `selectFromDecls`: the `none` (miss) arm yields `.bottom` instead of `.selector base label`.
`classifyDefinedness .bottom = .error`, so `x.b == _|_` is true and `x.b != _|_` is false. With `base`
no longer used in the miss arm it became a dead parameter and was dropped from `selectFromDecls`'s
signature (4 call sites updated). No other path touched; the `.disj` provisional deferral and the
non-struct-carrier `_ => .bottom` catch-all in `selectEvaluatedField` are unchanged.

Free wins from the same fix: a comprehension guard over a missing field now RESOLVES (the absent field
reads `.error`, firing the `== _|_` arm; pre-fix both arms dropped to `{}`), and a select through a
resolved-default disjunction reads absent.

### Tests + verify

10 `native_decide` pins in `Bug2xTests.lean` (new `### missing-field-selection` section): the target
(concrete missing absent), deep-into-a-struct missing, present-field over-fire guard, open-`...`-tail
missing, the two SOUNDNESS cases (later-conjunct-supplies / narrow-elsewhere — must NOT pre-bottom),
the comprehension-guard arm, the disjunction-default select, and the PROVISIONAL unresolved-disjunction
boundary (stays deferred/non-export). 5 export fixtures (`testdata/export/mfs_*.{cue,json}`, each
oracle-generated from `cue export` and confirmed byte-identical to kue). Coverage tripwire sentinel
added (`#check @mfs_unresolved_disj_stays_provisional`). `lake build` clean (no new warning/`sorry`/
axiom). `scripts/check-fixtures.sh` → fixture pairs ok (only the 5 intended new fixtures). cert-manager
+ argocd jq -S = 0 (not on the argocd path — zero drift). One message-only divergence recorded
(`cue-divergences.md`): a missing field used as a VALUE (`y: x.b`) — cue `undefined field: b`, kue
generic bottom; both reject, and the presence-test observable now byte-matches cue.

---

## Audit (Phase A — code-quality, batch `fccab69..889e86f`)

Audited the two selection/closedness slices: Bug2-12 (`eb086ce`, self-rec closed def rejects use-site
extras) and missing-field-selection (`889e86f`, concrete-struct miss → absent). Adversarial review of the
two highest-risk soundness claims + the full gate.

### Discriminator claim (missing-field-selection) — CONFIRMED

The fix rests on: everything reaching `selectFromDecls` is already-concrete, so a miss is FINAL-absent;
the only PROVISIONAL case (unresolved no-default disjunction) never reaches `selectFromDecls`. Enumerated
every path into `selectFromDecls` (both `evalValueWithFuel` call sites at `Eval.lean` 3231/3233 evaluate
`base` BEFORE selection; `selectEvaluatedField`'s struct/embed arms + the `.disj` arm gated by
`resolveDisjDefault?`). Attacked with a 29-witness oracle battery vs cue v0.16.1: resolved-default-arm
(supplies AND misses), UNRESOLVED no-default disjunction, later-conjunct-supplies, open-`...`-tail miss,
comprehension guards (true/false/INCOMPLETE), let-deferred, for-comp (concrete + incomplete source),
two-pass embedded-self, embed carriers, chained-after-deferral, required/incomplete fields. EVERY witness
matched cue at the JSON level. The decisive case: an unresolved no-default disjunction (`x: {a:1} |
{a:1,b:2}`, select `x.b`) does NOT bottom — kue defers the whole disjunction ("ambiguous value"), exactly
as cue defers ("unresolved disjunction"). `resolveDisjDefault?` returns `some` only for a unique marked
default or a sole live regular arm, so a provisional field never reaches the miss arm. **Claim sound.**

### Bug2-12 self-ref gate — EXACT, but found a NEW regression (Bug2-12b)

The `field.fieldClass.isDefinition && isSelfRef` gate is precise: `isSelfRef` requires a depth-0 conjunct
`.refId` whose index equals the flattened slot's, so it fires ONLY on genuine self-reference. Confirmed
the negatives: non-self-rec multi-conjunct (`#X: #Y & {c}`, `#Y` a different slot) is NOT closed by this
path; two distinct self-rec defs in one scope are distinguished by index; mutual recursion (neither
depth-0-same-index) is left to its existing path (the documented MUTUAL under-close spec-gap, accurate).
Over-close negatives hold: open-`...`-tail, pattern-tail, and declared-field-narrow all still admit; D#2
(`#L:{n,next:#L}` structural-cycle, `#List | *null` termination) unchanged.

**NEW FINDING — Bug2-12b, TOP soundness over-close (OPEN, filed, NOT fixed inline).** The closer
`expanded.map (normalizeDefinitionValueWithFuel …)` closes EACH struct-literal conjunct SEPARATELY. A
self-rec def whose literals are SPLIT across `&` (`#X: #X & {a:1} & {c:3}`) becomes two independently-
`defClosed` structs; a use-site re-declaring an existing field (`out: #X & {c:3}`) wrongly BOTTOMS where
cue ADMITS `{a:1,c:3}` — an over-close on a field the def itself declares. ISOLATED: single-literal
(`#X: #X & {a:1,c:3}`), non-self-rec multi-conjunct, and the genuine-extra-reject case all conform. Root:
conjuncts must close over their COMBINED allowed-set (the Bug2-7 close-once principle), not individually.
NOT fixed inline — the correct fix merges struct-literal conjuncts before closing, touching the
soundness-critical conjunct-merge machinery (the path whose first Bug2-12 attempt broke 6 Bug2-6..9
pins); needs its own TDD slice. Filed as `spec-conformance-audit.md` item 0 (ranked above perf #7).

### Other categories

Totality: no new `partial`/`sorry`/axiom (Bug2-12 `propext`-only; missing-field one-line). Illegal-states:
the `.bottom` miss arm and the self-ref gate are precise, no `_`-swallow. DRY: the Bug2-12 self-ref-gated
closing duplicates the close-each shape that should share the Bug2-7 close-once union — noted for Phase B
(it is the same root as Bug2-12b). Spec accuracy: the missing-field message-only divergence and the
Bug2-12 mutual-tail spec-gap entries are accurate; `plan.md`/`spec-conformance-audit.md`/log match the
code.

### Coverage added + verify

4 new `native_decide` pins in `Bug2xTests.lean`: `mfs_disj_default_supplies_field` (default arm SUPPLIES
the field → present, complement of the existing default-missing pin), `mfs_chained_selection_missing_absent`
(select through a selector-result base → absent), `bug212_singleliteral_redeclare_admits` (the CONFORMING
close-over-union boundary), and `bug212_multiconjunct_redeclare_OVERCLOSE` (pins the CURRENT WRONG Bug2-12b
behavior with a flip target for the fix-slice). All oracle-confirmed vs cue v0.16.1; tripwire sentinel
updated. Full gate green: `lake build` clean, `check-fixtures.sh` ok, cert-manager + argocd jq -S = 0,
shellcheck clean. **Batch verdict: HEALTHY for both shipped claims; one new contained over-close
(Bug2-12b) filed as the ranked-leader fix-slice.**

---

## Completed Slice: Bug2-12b — close a self-rec def's split literals over the COMBINED allowed-set

Goal: fix the contained over-close the Bug2-12 fix introduced. A self-recursive closed def whose
struct literals are SPLIT across `&` (`#X: #X & {a:1} & {c:3}`) closed each literal SEPARATELY, so a
use-site re-declaring the def's OWN field (`out: #X & {c:3}`) wrongly bottomed where cue ADMITS
`{a:1,c:3}` — an over-close on a field the def itself declares.

### Root cause

`flattenConjDefRef`'s `close == true` branch ran `expanded.map (normalizeDefinitionValueWithFuel …)`,
closing each split-literal conjunct independently. For `#X: #X & {a:1} & {c:3}`, `expanded` carried two
struct literals; each became a `defClosed` struct with its OWN single self-clause (`{a}`, `{c}`). Their
downstream `.conj`-meet CONCATENATES the `closedClauses` (SC-1b conjunction semantics), so a field must
be in BOTH allowed-sets — `c` rejected against `{a}`, and a use-site `& {c:3}` re-declaring `c`
bottomed. Close-each is wrong exactly as Bug2-7's close-each was: the literals are repeated decls of ONE
def path (the def body split across `&`) and must close ONCE over their COMBINED allowed-set.

### Fix (reuse the Bug2-6/2-7 close-once primitive on the flatten path)

In the `close == true` branch, partition `expanded` into the union-able def-body literals
(`isUnionableDefValue` — `.struct`/`.structComp` bodies) vs the rest (the self-ref `.refId` + any
deferred conjunct, left UNTOUCHED). `foldl mergeDefinitionDecls` the literals into ONE body, close that
SINGLE merged body once via `normalizeDefinitionValueWithFuel`, and re-emit `rest ++ [closed]`.
`mergeDefinitionDecls` (`Eval.lean:385`) unions fields (a shared label still `.conj`-meets, so a real
conflict survives), unions patterns, and unions openness via `unionDefOpenness` (`defOpenViaTail`
dominates — a split `...` keeps the union open); `mkStruct` re-derives the SINGLE `closedClauses` over
the merged field-set (no per-literal clause concatenation). The self-clause is now over `{a,c}` →
admits `a`, `c`, and a re-declared `c`; rejects `b`.

**The close-each-first subtlety (the one trap hit and corrected during the slice).** The literals are
UNEVALUATED at flatten time — a `{a:1}` literal is `regularOpen` (parser open-by-default), and the
recursive `flattenConjDefRef` over the self-ref produces additional already-`defClosed` literals. A raw
fold would feed `unionDefOpenness` a mix of `regularOpen` (read as OPEN) and `defClosed`, opening the
union (`unionDefOpenness defClosed regularOpen = defOpenViaTail`) and silently re-opening the def. Fix:
close EACH literal FIRST (`literals.map (normalizeDefinitionValueWithFuel …)`) so its def-body openness
is settled (`regularOpen → defClosed`, an explicit `...` stays `defOpenViaTail`) BEFORE the fold; then
`unionDefOpenness defClosed defClosed = defClosed` and `defClosed ∪ defOpenViaTail = defOpenViaTail`.
This does NOT re-introduce the close-each `closedClauses` defect: `mergeDefinitionDecls` DROPS each
input's `closedClauses` and re-derives a SINGLE clause via `mkStruct` over the union — so it is still
"close ONCE over the combined set", just with each input's openness pre-normalized.

`isUnionableDefValue` (a trivial 3-arm predicate) was moved up to before `flattenConjDefRef` so the
branch can reach it.

### Trap avoidance (the first Bug2-12 attempt broke 6 Bug2-6..9 pins — not repeated)

The branch stays GATED `field.fieldClass.isDefinition && isSelfRef`, firing ONLY for a genuinely
self-recursive closed def `.conj` body. It touches ONLY the `isUnionableDefValue` literal conjuncts; the
self-ref `.refId` sits in the untouched `rest` partition, so cycle DETECTION/termination (D#2a) and
self-ref bottoming are unchanged. A non-self-rec multi-conjunct def (`#LS: #Base & {#extra}`, `#Base` a
different slot) is NOT `isSelfRef` → `close == false`, so the whole Bug2-6..9 close-once-via-`closedClauses`
fold is bypassed; those pins never reach this arm.

### Coverage added + verify

Flipped `bug212_multiconjunct_redeclare_OVERCLOSE` → `bug212_multiconjunct_redeclare_admits`
(`exportJsonMatches … {a:1,c:3}`). 7 new `native_decide` pins in `Bug2xTests.lean`:
`bug212_multiconjunct_genuine_extra_rejects`, `bug212_multiconjunct_opentail_admits`,
`bug212_multiconjunct_conflict_bottoms`, `bug212_multiconjunct_threeway_admits`,
`bug212_multiconjunct_threeway_extra_rejects`, `bug212_multiconjunct_split_pattern_admits`,
`bug212_multiconjunct_split_pattern_rejects`. 3 byte-exact `cue export` fixtures
(`testdata/export/bug212b_multiconjunct_{redeclare,threeway,split_pattern}`) + 4 internal-format fixture
pairs (`testdata/cue/definitions/bug212b_multiconjunct_{redeclare_admits,genuine_extra_rejects,
opentail_admits,conflict_bottoms}`) with matching `FixturePorts.lean` entries. The open-tail export case
is inline-pin-only (field-order spec-gap: kue keeps source order `c,b`, cue emits `b,c` — value-identical).

The single-literal boundary (`bug212_singleliteral_redeclare_admits`), the 5 Bug2-6 close-once + 7 Bug2-9
multiconjunct pins, and D#2 guardrails (`bug212_struct_cycle_still_bottoms`,
`bug212_list_disj_still_terminates`) all STAY GREEN. All oracle-confirmed vs cue v0.16.1.

`flattenConjDefRef` depends only on `propext` (within the standard 3); total, no `partial`/`sorry`. Full
gate green: `lake build` clean (no new warning/axiom), `check-fixtures.sh` ok. Canaries: the change is a
provable no-op on cert-manager/argocd — the arm fires only for self-recursive def `.conj` bodies and
prod9 has zero recursive defs, so the corpus (off this machine, read-only prod9 cache) is byte-unchanged;
jq -S = 0 carried from the `6f77bfe` checkpoint. Bug2-12b is kue-was-wrong → conforms once fixed; no new
divergence, no residual spec-gap (the open-tail field-order is the pre-existing ratified #3 gap).

---

## Completed Slice: Bug2-12 MUTUAL — mutual-recursion closed-def closedness (adjudicate + conform)

Goal: adjudicate and conform the mutual-recursion closed-def closedness gap (`#A: #B & {a:1}`,
`#B: #A & {b:2}`) to the lattice-principled answer, NOT to a buggy `cue`.

### The adjudication (the principled answer + basis)

A definition's closed allowed-set is the TRANSITIVE union of every mutually-reachable cycle member's
declared labels. Transitive expansion fixes it: `#A = #B & {a} = (#A & {b}) & {a} = #A & {a,b}` ⟹
`allowed(#A) = {a,b}` (symmetrically `#B`; 3-way → `{a,b,c}`). Closedness BOUNDS the additions a use-site
may meet in — it NEVER rejects a label the definition itself declares (a def rejecting its own field
contradicts the closedness invariant). So the principled behavior: `#A & {a:1,b:2}` → ADMIT; `#A & {c:3}`
(`c` ∉ {a,b}) → REJECT; bare `#A` → `{a:1,b:2}`.

`cue` v0.16.1 OVER-REJECTS even the def's OWN declared field (`#A.a: field not allowed`) — it closes `#B`
PREMATURELY mid-cycle, mis-reading `#A`'s `{a}` as a use-site add to a finished `#B`. This is a cue BUG,
internally inconsistent with its correct ACYCLIC behavior (a def's declared field is never rejected). It is
recorded as a cue-divergence ("Mutual-recursion closed def rejects its OWN declared field"), NOT matched.

### Kue's pre-fix behavior + root cause (case (b): under-close)

Pre-fix probes: `#A & {a:1,b:2}` ADMIT (correct); bare `#A` → `{a:1,b:2}` (correct); but `#A & {c:3}`
ADMITTED `c` (UNDER-CLOSE bug). Root cause: the cross-def back-ref bottoms `#B` via the D#2 structural-cycle
path, dropping `#B`'s closedness, so `#B & {a}` resolves to an OPEN body — and an open struct admits anything.
The Bug2-12 self-rec fix gates its `close` on a DIRECT self-ref (`isSelfRef`: a depth-0 conjunct refs the
SAME slot); a mutual `#A`'s body refs `#B` (a different slot), so `isSelfRef` is false and the close never
fired.

### Fix

New total helper `defSlotInClosedCycle (fuel) (frame) (start) (seen) : List Nat → Bool` (above
`flattenConjDefRef`, `Eval.lean`): walks the same-frame def→def reference graph from `start`, following each
slot's depth-0 def-ref conjuncts (`defConjRefSlots`, a small companion helper), and reports `true` once the
walk returns to `start` after ≥1 hop. `seen` (visited slots) + `fuel` (= field count) bound it total. The
`flattenConjDefRef` `close` gate becomes `field.fieldClass.isDefinition && (isSelfRef || inCycle)` where
`inCycle := defSlotInClosedCycle (frame.snd).length frame.snd id.index.val [] [id.index.val]`.

The transitive flatten (`cs.flatMap (flattenConjDefRef env fuel)`, fuel-bounded) already pulls every cycle
member's literals into `expanded` (with duplicates). Once `close` fires, the EXISTING Bug2-12b machinery —
partition `expanded` into `isUnionableDefValue` literals vs `rest` (the back-ref `.refId`s, untouched),
close each literal first, `foldl mergeDefinitionDecls` into ONE union body, close once, re-emit
`rest ++ [closed]` — fixes the allowed-set to the transitive union `{a,b}`. No new closure mechanism; the
fix is purely the gate widening + the cycle detector. The back-ref `.refId`s stay in `rest`, so D#2 cycle
detection/bottoming is unchanged. A NON-cyclic def chain (`#A: #B & {a}`, `#B: {b}`) is not a cycle —
`defSlotInClosedCycle` returns false (the walk reaches `#B`, which has no def-ref conjunct, and never
returns to `start`) — so it stays on its existing distinct-meet path.

### Coverage added + verify

8 new `native_decide` pins in `Bug2xTests.lean` (`### Bug2-12 MUTUAL` section + sentinel
`bug212_mutual_oneway_nonrec_rejects`): `bug212_mutual_admits_transitive_declared`,
`bug212_mutual_rejects_genuine_extra`, `bug212_mutual_base_admits_declared`,
`bug212_mutual_threeway_admits`, `bug212_mutual_threeway_rejects_extra`,
`bug212_mutual_opentail_admits_extra`, `bug212_mutual_oneway_nonrec_rejects`. 3 internal-format fixture
pairs (`testdata/cue/definitions/bug212_mutual_{admits_transitive,genuine_extra_rejects,opentail_admits}`)
+ matching `FixturePorts.lean` entries.

All self-rec Bug2-12 pins, the Bug2-12b split pins, the 5 Bug2-6 + 7 Bug2-9 close-once pins, and D#2
guardrails (`bug212_struct_cycle_still_bottoms`, `bug212_list_disj_still_terminates`) STAY GREEN. D#2 probe
`#L:{n,next:#L}` still bottoms; a no-literal mutual cycle (`#A:#B`, `#B:#A`) still yields `_` (no `.conj`
literals → close does not fire). All conform to the lattice-principled answer (oracle-cross-checked vs cue
v0.16.1: cue over-rejects, recorded as a divergence).

`defSlotInClosedCycle`/`defConjRefSlots` are total (structural recursion bounded by `fuel`), no
`partial`/`sorry`/new axiom. Full gate green: `lake build` clean (no new warning/axiom), `check-fixtures.sh`
ok. Canaries: cert-manager + argocd jq -S = 0 (run from `prod9/infra`) — prod9 has zero recursive defs, so
the mutual-cycle change is provably neutral (the cycle gate never fires on the corpus). The under-close was
kue-was-wrong → fixed; cue's over-reject is a NEW recorded cue-divergence.

---

## Completed Slice: PERF — bound the multi-ref-cyclic flatten fan-out (`flattenConjDefRef` visited-path)

Goal: the Bug2-12-mutual fix made a closed cycle whose head conjoins ≥2 back-referencing defs CORRECT
but it TIMED OUT (>40s). Bound the re-expansion so each cycle member is collected ONCE, byte-identical
to the (correct-but-slow) result. The correctness-over-perf gate is ABSOLUTE: same value, just fast.

### The blow-up

`flattenConjDefRef` flattens a depth-0 ref to a `.conj`-bodied def into its constituent conjuncts
(Bug2-9), recursing through each member's body. For a closed cycle with k back-refs in the head
(`#A: #B & #C & {a}`, `#B: #A & {b}`, `#C: #A & {c}`), flattening `#A` expands `#B` AND `#C`, each of
which re-references `#A`, re-expanding `#B` and `#C` again — the work multiplies along the
cross-product of expansion paths, bounded only by `evalFuel = 100` levels of recursion. A SINGLE-ref
cycle of any depth is LINEAR (one path) and was already fast (~0.12s); the k≥2 fan-out is the
exponential. Measured: the 3-line repro ran **>40s (killed)** while `single` ran ~0.12s.

### Fix

Thread an `expanding : List Nat` (the def slots already on the current expansion PATH) through
`flattenConjDefRef`. New signature `flattenConjDefRef (env) (fuel) (expanding) (constraint)`; the entry
call site (`.conj` arm, `Eval.lean:3216`) passes `[]`, and the recursive `cs.flatMap` adds
`id.index.val` to `expanding`. A depth-0 ref to a slot ALREADY in `expanding` returns `[constraint]`
(the bare `.refId`) WITHOUT re-expanding — its literals are already being collected by the ancestor
that put it on the path. The `close`-branch Bug2-12b union machinery is UNCHANGED.

### Soundness argument (byte-identity)

The cycle's literal set is FINITE. Whether a member is reached once or many times, `mergeDefinitionDecls`
UNIONS its literal idempotently (re-collecting `{b}` unions to itself), so the merged allowed-set is the
same regardless of repetition. The bare `.refId` returned for an already-visited slot is EXACTLY the leaf
the unbounded recursion bottoms to at fuel exhaustion (`flattenConjDefRef 0 _ = [constraint]`), and those
back-refs land in `rest`, where D#2a structural-cycle detection bottoms them idempotently (`.conj`-meet of
a ref with itself is the ref) — so the `rest` set's contribution is identical. Therefore the literal
UNION and the `rest` ref set are the SAME finite sets, the allowed-set and value are byte-identical, and
the self-ref `.refId` bottoming + D#2 path are untouched. The bound only drops REDUNDANT re-expansions
that stabilize to the same fixpoint. The one observable byte change is field ORDER on a multi-HOP chain
(the 3-way chain canonicalizes from the pre-bound interleaving `a,c,b` to reverse-declaration `c,b,a`,
now consistent with the 4-way `d,c,b,a`) — an unordered-map detail, not correctness (per
`kue-performance.md` field-ordering; `cue` over-rejects the case so it is no oracle here).

### Coverage added + verify

6 new fast `native_decide` pins in `Bug2xTests.lean` (`### Multi-ref cyclic flatten-fan-out BOUND`
section + 2 sentinels): `bug212_multiref_threeway_admits`, `bug212_multiref_threeway_rejects_extra`,
`bug212_multiref_fourway_admits`, `bug212_multiref_opentail_admits_extra`,
`bug212_multiref_split_literal_admits`, `bug212_multiref_dup_backref_admits` — the multi-ref cases that
PREVIOUSLY could not be pinned (the `native_decide` never finished). `bug212_mutual_threeway_admits`
updated for the canonicalized `c,b,a` field order (value unchanged). All other Bug2-12 family
(self-rec + 2-12b + mutual single-ref) + D#2 guardrails STAY GREEN.

`flattenConjDefRef` stays total (no `partial`/`sorry`/new axiom; `expanding.contains` + the existing
fuel bound). Full gate green: `lake build` clean (no new warning/axiom), `check-fixtures.sh` ZERO drift.
Canaries from `prod9/infra`: cert-manager jq -S = 0 (~12.4s), argocd jq -S = 0 (~54s) — UNCHANGED (the
bound fires only on closed multi-ref cycle re-entry, which the real apps do not hit). **Measured
before→after: the 3-line repro >40s (killed) → ~0.01s warm / ~0.55s cold; single-ref cycle
byte-identical before→after.** No value change → no `cue-divergences`/`cue-spec-gaps` entry.

---

## Completed Slice: SC-4 — nested HIDDEN/LET plain-struct closedness on a direct def-meet

Goal: adjudicate + conform SC-4. A def's nested PLAIN-struct value carried by a HIDDEN field
(`#A: {_h: {x: int}}`) or read from a LET binding (`#A: {let _t = {x: int}, v: _t}`) did NOT close on
a direct def-meet — `#A & {_h: {x: 1, extra: 2}}` (and the let analog) ADMITTED `extra` — while a
nested REGULAR value already closed (SC-2). Adjudication outcome: **case (b)** — kue under-closed; fix
to the lattice-principled behavior.

### Adjudication (the principled answer FIRST, then cue cross-check)

**Principled answer: REJECT the extra.** Closedness is a PROPERTY OF THE DEFINITION and is MONOTONE
under meet (spec: referencing a def closes it "anywhere within the definition"; `&` cannot remove a
constraint). A `_h: {x: int}` declared in a closed `#A` with no `...` is itself a CLOSED struct — the
visibility of the carrying field (`_h` hidden vs `h` regular) and the carrier (let-bound vs regular
field) do NOT change whether the nested value is closed. This is the exact basis SC-2 established for
regular nested fields and SC-2b for instantiation, applied to the hidden/let carrier.

**cue v0.16.1 cross-check (the prior "internally inconsistent" framing was STALE).** Pinned on the
SC-4 shape + adjacent shapes:
- `#A & {_h: {x: 5, extra: 2}}` (direct meet) → cue REJECTS (`_h.extra: field not allowed`).
- `#A._h & {extra: 2}` (direct select then meet) → cue REJECTS.
- `y: #A; y._h & {extra: 2}` (BOUND-then-select) → cue ADMITS.
So cue is CONSISTENT on direct-meet vs direct-select (BOTH close); it only re-opens when selection
crosses a regular binding `y` — the SAME SC-2b-family eval-strategy artifact (closedness lost crossing
a plain field), not a spec mandate. The old "oracle #8" admit (`x._h & {extra}`) was exactly this
bound-select path, mis-generalized in the SC-2 design to "a def's hidden-field nested struct admits
extras". Verified the regular control (`#A & {h: {extra}}`) closes in both, the `#h`-def-field nested
value closes in both, and a nested `...` opens in both.

### Fix (Normalize-only, one-arm-each-twin)

`Kue/Normalize.lean`, `normalizeDefinitionFieldWithFuel` (the CLOSING field-walker twin, SC-2): the
`.field false true _` (in-file hidden `_x`) arm and the `.letBinding` arm now recurse the CLOSING
walker `normalizeDefinitionValueWithFuel` (closes nested plain-struct values) instead of the SPINE
`normalizeDefinitionsWithFuel` (preserves openness) — matching the regular `.field false false _` arm.
The `importBinding` SKIP arm is UNCHANGED (the A2 trap defence: a bound package is never recursed, so
cert-manager/argocd cannot re-bottom). The SPINE twin `normalizeFieldWithFuel` (the non-closing
context) is UNCHANGED — a plain (non-def) struct never reaches the closing twin, so a plain
`A: {_h: {x: 5}}` stays open. A nested `...` still returns `defOpenViaTail` unchanged (stays open); a
NEW use-site hidden field is still admitted (`ignoresClosedness = isDefinition || isHidden` — a
separate, orthogonal axis). The hidden-read-into-a-regular-field case (`#A: {_h: {x: 5}, v: _h}`)
closes for free (the hidden field's OWN value is now closed; `v: _h` resolves to it).

### Soundness boundaries (all oracle-checked vs cue v0.16.1; MATCH = same accept/reject)

- hidden nested CLOSES (direct meet, concrete + abstract) — MATCH; depth-2 hidden→regular — MATCH.
- hidden nested with `...` STAYS OPEN — MATCH. NEW use-site hidden field ADMITTED + selectable — MATCH.
- let-read nested CLOSES (closed def) — MATCH; let-read with `...` STAYS OPEN — MATCH; let-read in a
  PLAIN struct STAYS OPEN — MATCH (the spine, not the closing twin).
- regular nested CLOSES — MATCH (SC-2 control, unchanged); plain non-def nested STAYS OPEN — MATCH;
  `#h`-def-field nested CLOSES — MATCH; new regular field REJECTED — MATCH.
- closedness family + D#2 regressions all MATCH: multi-decl close-once, distinct-def-meet reject,
  struct-cycle bottoms.

### Divergence recorded

One residual: `cue-divergences.md` "nested closedness shed via a hidden-field binding (SC-4)" — cue
re-opens the nested hidden value when selected through a regular binding (`y: #A; y._h & {extra}`
ADMITS), the same SC-2b-family eval artifact; Kue preserves closedness monotonically on every path.
The direct-meet path (the headline fixture) matches cue. No `cue-spec-gaps` entry — the spec speaks
(closedness is monotone) and cue agrees on the direct paths, so this is a cue bug on one spelling, not
a spec gap.

### Coverage added + verify

7 `EvalTests` `eval_sc4_*` pins (new `### SC-4` section): `eval_sc4_hidden_field_nested_closes` (the
former obligation-4 pin `eval_sc2_hidden_field_nested_stays_open` FLIPPED — the stale bound-select
admit became the direct-meet REJECT), `_hidden_field_nested_tail_stays_open`, `_new_hidden_field_admitted`,
`_hidden_field_nested_depth2`, `_let_read_nested_closes`, `_let_read_plain_stays_open`. 4 `sc4_*`
fixtures with `FixturePorts` entries (`sc4_hidden_nested_closes`, `…_tail_stays_open`, `…_depth2`,
`sc4_let_read_nested_closes`). `normalizeDefinitionFieldWithFuel` stays total (no `partial`/`sorry`/new
axiom). Full gate: `lake build` clean (112 jobs, no warning/axiom), `check-fixtures.sh` ZERO drift.
Canaries from `prod9/infra`: cert-manager jq -S = 0 (~11.7s), argocd jq -S = 0 (~50s) — UNCHANGED (the
nested-hidden/let-under-closed-def shape is off the real-app path).

---

## Completed Slice: parser-strictness — reject `__`-reserved identifiers + sole-marked `*` default

Goal (plan item-6 LOW): the parser ACCEPTED two spec-INVALID forms `cue` rejects at parse. Spec-verify
FIRST (the risk is OVER-strictness — rejecting VALID syntax), then add the two rejection rules.

### Spec basis (both SPEC-MANDATED, verified against the CUE spec, not the binary)

1. **`__`-prefix reserved.** Spec: "CUE reserves all identifiers starting with `__` (double underscores)
   as keywords." A reserved keyword is not a valid identifier in ANY position, so a user `__x` (field
   label, reference, alias) is spec-invalid. The reservation is on the RAW SPELLING beginning with `__`:
   `#__x` begins with `#` and `_#__x` with `_#` (definition / hidden-def prefixes), so neither is reserved
   (`cue` accepts + resolves both); a single leading `_` (`_x`) is the valid hidden-field form; a quoted
   `"__x"` is a string label, not an identifier.
2. **`*` default mark valid ONLY on a disjunct with siblings.** Spec: the `*` marks "any element of a
   disjunction" — `a | (b | *c | d)` is "an unmarked disjunction of two terms" (the `*c` is valid because
   it is an element of the INNER disjunction). So `*X` is legal only as one of `… | *X | …` with ≥2
   disjuncts. A SOLE marked operand — `*(1|2)` (mark on a parenthesized group), `*1` (single disjunct) — has
   no alternatives to prefer; `cue` rejects it `preference mark not allowed at this position`.

### Fix (parser-only, two minimal rejection rules)

- **`reservedDoubleUnderscore (name) := name.startsWith "__"`** checked at `parseIdentifier`
  (`Kue/Parse.lean`) — the ONE identifier-lexing chokepoint every identifier position routes through
  (labels, refs, aliases, package names). `#`/`_#`-prefixed names and quoted labels never trip it (their
  spelling does not begin with `__`; quoted labels skip `parseIdentifier` entirely). No internal
  `__`-identifier exists in the codebase, so the chokepoint is safe.
- **Sole-marked-disjunct guard** in `parseDisjunctionRest`: when the finalized `alternatives` list is a
  single `.default`-marked element → `parseError … "preference mark not allowed at this position"`. A
  `start` param (the disjunction's pre-parse position) anchors the diagnostic at the leading `*` (col
  matches `cue`). The `[(.regular, value)]` single-regular and `≥2`-element marked cases are untouched, so
  `*1 | 2`, `(*1 | 2)`, `*(1|2) | 3` (a marked group WITH a sibling — `cue` parse-accepts; its
  incompleteness is a downstream EVAL concern) all still parse.

### cue cross-check + divergence

`cue` is INTERNALLY INCONSISTENT on `__`: it rejects `__x` everywhere EXCEPT the inline shorthand
`a: __x: 1` (a parser inconsistency — accepts `{"a": {}}`). Kue rejects on every spelling, conforming to
the spec; recorded as a cue-divergence (`cue-divergences.md`: "`__`-prefixed field label via the inline
shorthand"). The out-of-scope package-name / import-qualifier `__` corner (cue accepts `package __pkg`,
rejects `import __bar`) is murky in both spec and binary — recorded as a spec-gap, deliberately NOT
tightened (`isPackageIdentifier` unchanged; prod9 never hits it).

### Coverage + verify

18 `native_decide` parse pins in `ParseTests.lean` (two new `--` line-comment sections + 3 `#check`
tripwires): rejects (`__x` ref / field / inline-nested / bare `__` / triple `___x` / position;
`*(1|2)` / string+struct group variants / `*1` single / `*(1)` / position) + the VALID boundary (`_x`
hidden, `_` blank, `#__x`/`_#__x` defs, `"__x"` quoted; `*1 | 2`, `*"a"|"b"`, `*[1]|[2]`, `(*1 | 2)`,
`*(1|2) | 3` parse-accept). A parse-REJECT has no `.expected` output, so the `native_decide` parse pins
are the appropriate test form (no `testdata` pair). Parser stays within the standing `partial def`
exception (rejection rules only, no new recursion); no `sorry`/axiom. Full gate: `lake build` clean (112
jobs, no warning), `check-fixtures.sh` ZERO drift (no corpus fixture uses the now-rejected forms; valid
`*` defaults in the corpus still parse). Canaries from `prod9/infra`: cert-manager jq -S = 0 (~11.4s),
argocd jq -S = 0 (~54s) — UNAFFECTED (real configs use no `__`/`*(…)` invalid syntax).

---

## Completed Slice: release tooling — race-safe tap push + release-linux dirty-tree guard

Goal (plan item-6 LOW ×2, now relevant because releases AUTO-CUT): harden the release scripts
against the auto-release flow, where `release.sh` (macOS) and `release-linux.sh` (Linux) may run
concurrently against the SAME tap clone. Two audit findings: (1) both did `pull --ff-only` +
`commit` + `push` with no retry → a concurrent run races the index/push (lost commits, rejected
push); (2) `release-linux.sh` lacked the clean-tree precondition `release.sh` has → could ship a
Linux asset built from uncommitted changes (`COPY . /src`) diverging from the committed macOS asset.

### Mechanism — retry-on-reject with re-fetch + re-patch (NO lock)

`flock` is unavailable on macOS (the release host), so a lock would silently no-op there. Instead
a new shared `scripts/tap-push.sh` (sourced by both scripts, DRY alongside the already-shared
`patch-formula-block.sh`) exposes `tap_push <tap_dir> <commit_msg> <repatch_fn>`. Each attempt:
resolve the remote from the branch's upstream (the tap remote is `gh`, not `origin` — never assume
a name); `fetch` + `reset --hard <remote>/<branch>` to a clean base at the remote tip (which now
contains any sibling block the concurrent run pushed); re-apply OUR patch via the caller's callback;
commit-if-changed; push. On a push REJECT (a concurrent push landed first) LOOP from the fetch, up
to `TAP_PUSH_RETRIES` (default 5) with `TAP_PUSH_BACKOFF` (default 2s) backoff, then `die`. The loop
serializes safely WITHOUT a lock and also absorbs transient push failures.

The callback (`repatch_macos` / `repatch_linux`) re-runs the script's own `patch_formula_*` calls,
which are **idempotent + block-scoped**: the patcher keys on the asset-suffixed url line
(`…/kue-aarch64-apple-darwin"`), invariant across version bumps, so re-patching reliably finds and
rewrites the SAME block; and it touches ONLY that asset's block, so the sibling block brought in by
the re-fetch is preserved. (`patch-formula-block.sh` unchanged — verified idempotent for realistic
asset-suffixed urls and block-scoped by direct test.) `reset --hard` here is scoped to the tap clone
and only ever discards this script's own regenerable patch — it never touches the kue working tree.

### Dirty-tree guard

`release-linux.sh` gains the same precondition `release.sh` has:
`[ -z "$(git -C "$REPO_ROOT" status --porcelain)" ] || die "working tree dirty …"`, placed with the
other preconditions before the Docker build, so the Linux asset is built from a committed tree
matching the macOS asset.

### Verify

`shellcheck` 0.11.0 clean on all four scripts (release.sh, release-linux.sh, patch-formula-block.sh,
tap-push.sh). Concurrency DRY-RUN: a throwaway bare remote + two clones running `repatch_macos` and
`repatch_linux` truly concurrently (12-round stress + a `gh`-named-remote round) — every round landed
BOTH the macOS block AND both Linux blocks + the version bump with ZERO lost updates; the loser of the
race observed a real push rejection, re-fetched the winner's commit, re-patched its own block on top,
and pushed. Retry-exhaustion path tested under perpetual contention → clean `die` after N, nonzero
exit. No Lean change; `lake build` clean (112 jobs), `check-fixtures.sh` ZERO drift. The published
`v0.1.0-alpha.20260623` release/assets/formula were NOT touched — change affects only FUTURE runs.

---

## Completed Slice: perf — per-eval-constant PROFILED + empty-`cache`-skip fast path (floor characterized)

Goal (plan perf item — the per-eval CONSTANT, argocd ~52.8s the one remaining user-visible
issue): profile where each of the ~486K (argocd) / ~318K (cert-manager) NECESSARY core evals
spends its time, then either land a sound byte-identical micro-opt or definitively characterize
the floor. (The eval COUNT is content-irreducible — perf #7 proved the ~175× re-eval is
genuinely-distinct content, frame-sharing WON'T-FIX ~0.05% ceiling. The only lever left is the
per-eval CONSTANT.)

### Profile (instrumented `evalValueWithFuel` cache-probe path; `KUE_PROFILE=1` stderr dump)

Added transient hit/miss/insert counters to every cache probe in the eval wrapper, ran the
whole-root export of both prod9 apps. Decisive numbers:

| app          | evalCalls | satMisses | satInserts | fuelHits | fuelInserts | forceMisses |
|--------------|----------:|----------:|-----------:|---------:|------------:|------------:|
| cert-manager |   317,768 |   317,768 |    317,768 |        0 |           0 |      19,538 |
| argocd       |   486,741 |   486,741 |    486,741 |        0 |           0 |      30,103 |

The shape: **`satMisses == evalCalls`** (every core eval is a satCache miss — the satCache hits
are re-reaches of already-converged values, a separate population) and **`fuelInserts == fuelHits
== 0`** — the fuel-keyed `cache` is NEVER inserted into and NEVER read across the entire run.
These apps are FULLY SATURATING: zero fuel-truncated results, so every result lands in the
fuel-free `satCache` and the fuel-keyed `cache` stays permanently empty. Yet on EVERY satCache
miss the wrapper built an `EvalKey` (an allocation) and probed `cache.get? key`, which recomputes
`valueDigest DIGEST_DEPTH value` — the SAME depth-3 digest the satCache probe just computed on the
same `value` — only to look it up in a provably-empty map and miss. That is one redundant full
digest traversal + one `EvalKey` allocation + one HashMap probe per core eval, ~486K times.

### The micro-opt — empty-`cache`-skip (sound, byte-identical, ZERO downside)

On a satCache miss, probe the fuel-keyed `cache` ONLY when `cache.isEmpty` is false. An empty
`HashMap` provably contains no key (`cache.get? key = none` for every key), so the `none` branch
is taken either way — value-identical AND saturation-identical (the skipped probe could only ever
have returned `none`). Skipping it elides the redundant `valueDigest` recomputation + the
`EvalKey` allocation + the HashMap probe on every core eval of a fully-saturating program. The
`EvalKey` is now built ONLY in the `.truncated` insert arm (the sole place a fuel-cache entry is
created), so a fully-saturating run constructs zero `EvalKey`s. A program WITH truncation is
unchanged: once `cache` is non-empty the probe runs exactly as before. `cache.isEmpty` is
`@[inline]` and O(1) (reads the stored size), so the guard is free.

**Soundness (byte-identity argument).** The change is a pure dead-branch elimination: it replaces
`cache.get? key` with `if cache.isEmpty then none else cache.get? key`, and `cache.isEmpty = true →
cache.get? key = none` is a HashMap invariant. So the value threaded to the `none`/`some` match is
identical for every input; no `valueDigest`/`BEq`/saturation behavior is touched (digest is still
only a bucket selector; `BEq` is still the sole equality arbiter). The satCache path, the
truncCount bracketing, and the saturated/truncated gating are all unchanged. Witnessed by zero
fixture byte-drift, full `native_decide` suite green, and both canaries jq -S = 0.

### Measured — the win is at the noise floor; this is a FLOOR CHARACTERIZATION

Before→after wall-times (`/usr/bin/time -p`, user seconds): **argocd ~52.8s → ~51.8–52.3s (~1–2%,
noise-band)**; **cert-manager ~11.4s → ~11.8s (flat/noise)**. Both jq -S = 0, byte-identical to
`cue` (argocd 51178 B, cert-manager content-identical). The optimization is correct and removes
provably-dead work, but the MEASURED wall win is marginal — which is itself the finding.

**The per-eval constant is dominated by genuine `evalValueCoreWithFuel` work, NOT the cache/hash
machinery.** Eliminating one of the two per-eval `valueDigest` traversals moved the wall ~2%, so
the digest+probe+alloc cache machinery is ~2-3% of per-eval cost (corroborating the earlier
"DIGEST_DEPTH 1 vs 3 measured FLAT" finding — digest depth was never the wall). The remaining
~97% is the meet/merge/resolve/force work in the core: the tag histogram (`.struct` 129K, `.refId`
108K → force-closure path, `.conj` 49K → meet path, `.selector` 39K) is genuine reduction over a
genuinely-distinct-content population (~175× re-eval of env-DEPENDENT shapes carrying distinct
observable bindings — perf #7). **argocd ~52s ≈ ~486K necessary core evals × the irreducible
per-meet cost; cert-manager ~11.4s ≈ ~318K × same.** No sound per-eval win exists without reducing
the eval COUNT, which is content-irreducible (cross-env sharing is a false-share, WON'T-FIX). This
definitively closes the per-eval-constant perf frontier: the floor is the genuine meet work, not
recoverable cache/hash overhead. The user-controllable lever (flatten / shorten chains → fewer
evals, `kue-performance.md`) remains the only way to move it.

### Verify

`lake build` clean (112 jobs, full `native_decide` suite green incl. `EvalPerfTests` count +
cross-fuel saturation pins — the empty-`cache`-skip changes the probe path, not the eval COUNT or
the satCache cross-fuel serving, so all pins hold unchanged). `check-fixtures.sh` ZERO drift. Both
canaries from `prod9/infra` jq -S = 0 (argocd 51178 B ~52s, cert-manager content-identical
~11.8s). `KUE_PROFILE=1` (env-gated stderr counter dump, no default-output change) retained as a
permanent diagnostic. No `partial`/`sorry`/axiom; `BEq`/digest soundness + the `Value`
`DecidableEq` carve-out untouched. No shell touched. No `cue-divergences`/`cue-spec-gaps` entry
(no value change).

## Resilience / Retrospective Pass (2026-06-23)

Process-hardening pass — OVERDUE (~11 audit cycles this session, zero retros). DOCS/PROCESS
only; no Lean/scripts/testdata change. Reviewed what broke OPERATIONALLY this session and
recorded each with its guard in `failure-modes.md` (9 → 12 entries), folding durable
mitigations into `slice-loop.md`.

### Six operational learnings recorded

1. **Host crash mid-subagent.** The Claude Code host process exited, destroying in-process
   state. STRENGTHENED the existing "Subagent crash" entry: recover from GIT STATE (not
   memory) — clean tree + nothing committed since known-good → FULL re-run; partial commits
   → re-run only the lost remainder.
2. **Transient API rate-limit (0-token / 0-tool-use return).** Same "Subagent crash" entry,
   reinforced: retry-NOW, never wait-it-out — folded the 0-token-return symptom in.
3. **prod9 canary mis-reported "absent" — wrong-CWD artifact.** NEW entry. `kue export
   apps/<app>.cue` resolves its module only from `/Users/chakrit/Documents/prod9/infra`;
   run from repo root it 404s. Guard: always `( cd .../prod9/infra && kue export ... )`.
4. **Design-level depth prediction falsified by the real app, twice** ("argocd one fix away"
   / "cross-package is the same fix"). GENERALIZED the "audit perf root-cause prediction
   proves wrong" entry to cover correctness-depth: any design-level depth claim is a
   hypothesis — verify EMPIRICALLY by running the canary.
5. **Subagent claimed "pushed" with HEAD ahead of upstream.** NEW entry. Guard: orchestrator
   MANDATORY `HEAD == @{u}` done-check; subagents confirm the `main -> main` push output.
6. **Over-claim-then-orchestrator-verify** (milestone "argocd byte-identical"). NEW entry.
   Guard: orchestrator INDEPENDENTLY re-verifies milestone / soundness / push / release
   claims (re-run canary + `jq -S`, build, fixture gate) before they enter the durable record.

### Guide mitigations folded into `slice-loop.md`

- "Commit at checkpoints" paragraph — crash recovery from git state, incl. host-exit + the
  clean-tree → FULL re-run case + 0-token retry-now.
- NEW "Subagent-prompt conventions" subsection under "Slice (per subagent)" — prod9 canary
  CWD subshell, confirm-the-push, real-app depth is empirical-not-design.
- "Notes" / orchestrator done-check — mandatory `HEAD == @{u}` check + independent
  re-verification of high-stakes (milestone / soundness / push / release) claims.

### Verify

`lake build` + `scripts/check-fixtures.sh` green (docs-only → unaffected). No canaries
(no code change). Tree clean before edits at `890d453`.

---

## Completed Slice: A2-y — reject a top-level field colliding with an import's local name

Goal: close the last latent loader-strictness gap. A top-level bare-identifier field whose
name equals an imported package's bound local name (`import ".../dep"` + `dep: {…}`) is a
LOAD error in `cue`; Kue silently kept BOTH the import binding and the field — and worse,
resolved a reference `out: dep` to the imported PACKAGE rather than the user's field (a
latent SOUNDNESS bug, not just leniency).

### Spec-verify FIRST (the crux — over-strictness was the risk)

Oracle-pinned `cue` v0.16.1's exact behavior on the collision. `cue` errors at LOAD with
`<name> redeclared as imported package name` (a two-line diagnostic: the message + a
`previous declaration at <file>:<line>` back-reference). Fires whether or not the import is
referenced elsewhere. This is **SPEC-MANDATED, not a binary quirk**: the CUE spec's
declaration rule — "No identifier may be declared twice in the same block" — combined with
"an import declaration binds the package name in the file block". A same-name bare-identifier
top-level field is a second declaration of that identifier in the one file block. So Kue
CONFORMS to the spec; it does not merely match the binary.

The exact COLLISION BOUNDARY, fully oracle-pinned:
- **Collides** (cue rejects): a top-level field whose label equals the import's BOUND local
  name, on any presence rung — `dep:`, `dep?:`, `dep!:`. The bound name is what matters: the
  ALIAS name under `import d "…"` (`d` collides, `dep` does not), the QUALIFIER name under
  `import "…:foo"` (`foo` collides, the last path element does not), and a builtin import's
  bind name (`import "encoding/json"` + `json: {…}` collides too — a stdlib import still binds
  its local name in the file scope).
- **Exempt** (cue accepts): a QUOTED-string label `"dep": …` (a string label, not an
  identifier declaration in the block); a DEFINITION `#dep` or HIDDEN `_dep` (distinct
  namespaces); a NESTED `dep` (different scope); a DIFFERENT-named field. The aliased-field
  corner `x=dep: 1` is a genuine SILENT spec gap — cue short-circuits on its own
  `unreferenced alias` error first, so its redeclaration verdict there is unobservable.

### Steps

1. **Preserve quoted-vs-bare through to the loader.** `Field.label` strips quotes, so a
   quoted `"dep"` and a bare `dep` were indistinguishable downstream — a label-string-only
   check would over-reject the quoted form cue accepts. Added `(quoted : Bool)` to the
   `ParsedField.field` constructor (`Parse.lean`) — the bare-label site sets `false`, the
   quoted-static-label site `true`. `bareIdentifierLabels : List ParsedField → List String`
   collects exactly the collision-eligible labels (bare `quoted=false`, class `.field false
   false _` — all three rungs; quoted/`#`/`_`/`let`/embedding/pattern excluded). Carried on
   `ParsedFile.topLevelFieldNames` (`Value.lean`), populated in `parseDocumentFile`.

2. **The LOAD-time check, IO-confined in `Module.lean`.** Pure `checkImportRedeclaration
   (bindName) (fieldNames) : Except String Unit` flags a bound name present in the file's
   field-name set, erroring `importRedeclarationError bindName` (= cue's first line). Threaded
   `fieldNames` through `collectBindings` (applied to BOTH the builtin-skip path and the
   resolved path, using `importBindName imp <declaredName>` for the bound name). The
   builtin-only fast path in `loadFileBound` (which returns before `collectBindings`) runs the
   batch `checkBuiltinImportRedeclarations` so `import "encoding/json"` + `json: {}` errors too.
   Per-FILE (file-scope): each file's imports vs that same file's field names, so a cross-file
   sibling `dep` does NOT falsely collide (oracle-confirmed both cue + Kue accept that).
   `Eval`/`Resolve` stay pure; all IO in `Module.lean`. Total, no `sorry`/axiom.

3. **Tests + fixtures.** +13 `native_decide` pins in `ModuleTests` (`bareIdentifierLabels`
   eligibility across bare/optional/required + the quoted/`#`/`_`/`let`/pattern exemptions;
   `checkImportRedeclaration`/`checkBuiltinImportRedeclarations` collide-vs-ok; the
   diagnostic text; the alias-no-collision via `importBindName`). Two module fixtures:
   `modules/import_name_redeclaration` (`expected.err` — the collision errors at load) +
   `modules/import_name_no_collision` (the valid boundary — quoted/`#`/`_`/different-name all
   load, byte-identical to cue).

### Verify

`lake build` clean (112 jobs). `scripts/check-fixtures.sh` zero-drift (existing module/import
corpus + the 2 new fixtures green). **Canaries jq -S = 0** from `/Users/chakrit/Documents/prod9/infra`:
cert-manager (~11.7s) + argocd (~50.8s) UNAFFECTED — prod9 never hits the collision, confirming
no over-rejection. No shell touched. Full collision/valid boundary re-oracled against cue: every
case matches (5 collide, 7+ exempt).

### Records

1 cue-divergence (single-line vs two-line diagnostic — verdict + first line AGREE). 1 spec-gap
(exemption boundary; the aliased-field-label corner deliberately exempted as the no-over-reject
choice). `plan.md` item-6 A2-y struck (RESOLVED); A2-x noted as STAYS-unobservable (its merge is
only reachable via the collision A2-y now rejects at load).

## Completed Slice: Aliased-builtin call resolution (item-6 LATENT, surfaced by A2-y audit)

Goal: close the latent wrong-value gap an aliased stdlib import exposed. `import j
"encoding/json"` + `out: j.Marshal({a: 1})` returned `incomplete value: j.Marshal(...)` where
`cue` v0.16.1 marshals to `{"a":1}`. Pre-existing (reproduces with no field present), prod9
canaries unaffected (they use UNALIASED builtin imports) — but a real wrong value for aliased
imports.

### Spec-verify FIRST

`cue` v0.16.1 resolves an aliased builtin import IDENTICALLY to the unaliased form — an import
alias is just a local rebinding of the package name, and member access through it resolves the
same. Oracle-pinned: `import j "encoding/json"; j.Marshal(x)` == `import "encoding/json";
json.Marshal(x)`; `import s "strings"; s.ToUpper` == `strings.ToUpper`; `import m "math"; m.Pow`
== `math.Pow`. Clean spec-correct fix, no surprise — no `cue`-divergence to record.

### Root cause + the seam

The parser lowers a `pkg.fn(...)` member-access call to `.builtinCall "pkg.fn" args` off the
LITERAL head it reads (`Parse.lean` `parseSelectorRest`, `s!"{pkg}.{label}"`). For an aliased
import the head is the alias (`j`), so `evalBuiltinCall` sees `.builtinCall "j.Marshal"`, which
`BuiltinFamily.ofName?` classifies as `none` (no `j.` prefix) → never dispatched. The fix had to
map the alias back to the canonical package name BEFORE that dispatch.

Seam analysis ruled out the obvious candidates: the parser's expression core is deliberately
context-free (40-fn mutual block, threading an alias map is invasive and breaks the separation);
`Resolve`/`Eval` have no import context; a stdin program never reaches the `Module.lean` loader
(`Main.runEval`/`runExport` stdin paths call `parseSource`/`parseSources` directly), so a
Module-only fix would miss stdin (and the test corpus runs via stdin). The ONE place with both
the imports and full coverage of stdin + file + package loads is the **parse completion step**:
`parseDocument` (stdin) and `parseDocumentFile` (file) both already parse the import clauses
before the body.

### Implementation

A post-parse alias canonicalization in `Parse.lean`, applied to the parsed body in BOTH document
parsers:

- `builtinImportLocalNames : List Import → List (String × String)` — `(asWritten, canonical)`
  pairs, ONLY for a builtin import (`isBuiltinImport imp.path`) aliased to a non-canonical head
  (alias > `:identifier` qualifier > last-path-element vs `lastPathElement imp.path`). A user
  import (non-builtin path) contributes nothing — the boundary that prevents misdispatching an
  aliased USER package as a builtin.
- `canonicalizeBuiltinCallName` — splits a builtin-call name on the first `.`, swaps a mapped
  head for its canonical package, leaves the leaf + any unmapped/dotless name untouched.
- `canonicalizeBuiltinCalls` — total fuel-bounded structural `Value` rewrite (modeled on
  `resolveValueWithFuel`/`remapConjRefs`) touching ONLY `.builtinCall` names; every other node
  rebuilt unchanged. `applyBuiltinAliases` is a no-op when no import aliases a builtin (the common
  case), so the unaliased path is untouched.
- `parseDocument` now collects imports (via the existing `parseImportClauses`) instead of
  discarding them (`consumeImportClauses`), so the stdin path gets the rewrite too.

To avoid duplicating the builtin-path list across the Parse/Module boundary (DRY — banned),
`builtinImportPaths`/`isBuiltinImport`/`lastPathElement` moved DOWN to `Value.lean` (the shared
base both import); `Module.lean`'s copies deleted and its `importBindName` `where`-local
`lastPathElement` folded into the shared one.

### Verify

`lake build` clean (112 jobs, all `native_decide` green). `scripts/check-fixtures.sh` — `fixture
pairs ok`, zero unintended drift (the 2 new fixtures + module fixture green). **Canaries jq -S =
0** from `/Users/chakrit/Documents/prod9/infra`: cert-manager (~11.5s) + argocd (~50.7s)
UNAFFECTED. No shell touched. All six families oracle'd == cue (`json`/`strings`/`math`/`list`/
`base64`/`yaml`); unaliased unchanged; an aliased USER import (`import f "ex.com/foo"; f.Bar`)
resolves to the user package (a deferred selector), NOT a builtin. The comprehension-loop-var →
`json.Marshal` corner errors in BOTH kue and cue (pre-existing, alias-independent) — out of scope.

### Tests

4 ParseTests theorems: `builtin_import_local_names_maps_only_aliased_builtins` (the alias map +
the user-import boundary), `canonicalize_builtin_call_name_rewrites_only_mapped_head` (the head
rewrite), `parse_aliased_builtin_call_resolves_like_unaliased` (per-family e2e), and
`parse_unaliased_builtin_and_aliased_user_import_unchanged` (the boundary). 1 Bug2xTests EXPORT
pin `aliased_builtin_call_marshals_like_unaliased` (export observable — a regression to
`incomplete`/bottom fails). Fixtures: `testdata/cue/builtins/aliased_builtin.{cue,expected}` (all
six families; the dual CUE-port witness builds the CANONICAL AST in `FixturePorts.lean` while the
CLI port parses the ALIASED `.cue` — both matching `.expected` proves the canonicalization) and
multi-file module fixture `testdata/modules/alias_builtin_call/` (loader path).

### Records

No `cue`-divergence (kue conforms once fixed) and no spec-gap (an alias is an unambiguous local
rebinding — spec-clear). `plan.md` item-6 aliased-builtin entry struck (RESOLVED);
`spec-conformance-audit.md` item-6 tail updated.

## Completed Slice: Aliased-stdlib-CONSTANT resolution (item-6 LATENT, the no-call analog of the calls fix)

Goal: close the latent wrong-value gap the aliased-builtin-CALLS slice (`ebaafc4`) flagged for stdlib
CONSTANTS reached via member access. `import l "list"` + `out: l.Sort([3,1,2], l.Ascending)` returned
`conflicting values (bottom)` where `cue` v0.16.1 sorts to `[1,2,3]`. Pre-existing, prod9 canaries
unaffected (they use UNALIASED imports) — but a real wrong value for aliased imports.

### Spec-verify FIRST

`cue` v0.16.1 resolves an aliased stdlib CONSTANT IDENTICALLY to the unaliased form — an import alias is a
local rebinding, and member access through it resolves the same. Oracle-pinned: `import l "list";
l.Sort([3,1,2], l.Ascending)` == `import "list"; list.Sort(..., list.Ascending)` ([1,2,3]); `l.Descending`
== `list.Descending` ([3,2,1]); standalone bare `l.Comparer` == `list.Comparer` (the same incomplete
comparator struct). Clean spec-correct fix — no `cue`-divergence to record.

### Root cause + the seam (cleanly the SAME pattern as the calls fix)

Unlike a `pkg.fn(...)` CALL — which the parser lowers to a deferred `.builtinCall "alias.fn"` node the
post-parse `canonicalizeBuiltinCalls` pass rewrites — a stdlib CONSTANT is resolved INLINE during parse
(`Parse.lean` `parseSelectorRest`, the no-call selector arm calls `stdlibPackageValue? pkg label` and
splices the comparator struct on the spot). For an aliased import the head is the alias (`l`), so
`stdlibPackageValue? "l" "Ascending"` → `none` and the node survives as `.selector (.ref "l") "Ascending"`
— a deferred field access that resolves to bottom (`l` is an import, not a struct), bottoming `Sort`.

The fix is the no-call analog of the calls fix and reuses its machinery rather than threading the parser:
the post-parse pass already walks every node and already has the `builtinImportLocalNames` alias map. Its
`.selector base label` case is the seam — when `base` is `.ref alias` and the alias maps to a canonical
builtin AND `(canonical, label)` names a stdlib constant, re-resolve to the comparator struct; otherwise
fall through to ordinary field-access recursion.

### Implementation

- `canonicalizeBuiltinConst? (aliasMap) (head label) : Option Value` — `aliasMap.lookup head` →
  `stdlibPackageValue? canonical label`; `none` for a non-builtin alias (absent from the map, so a user
  import's `f.Ascending` is untouched) or a non-constant label.
- `canonicalizeBuiltinCalls`'s `.selector` case: when `base` is `.ref head` and `canonicalizeBuiltinConst?`
  resolves, return that value; else `.selector (rec' base) label` as before. The aliased-CALL `.builtinCall`
  rewrite is unchanged — both aliased heads now canonicalize in the one pass.
- No new module/loader plumbing: the existing `applyBuiltinAliases` wiring in `parseDocument` (stdin) +
  `parseDocumentFile` (file) covers both load paths, and is still a no-op when no import aliases a builtin.

### Verify

`lake build` clean (112 jobs, all `native_decide` green). `scripts/check-fixtures.sh` — `fixture pairs ok`,
zero unintended drift (the new CLI + Lean-port fixture + module fixture green). **Canaries jq -S = 0** from
`/Users/chakrit/Documents/prod9/infra` (whole-`apps` export, `."cert-manager"` + `.argocd` selected):
both UNAFFECTED — prod9 uses unaliased imports. No shell touched. Behavior pinned: all three `list`
constants resolve == cue; unaliased `list.Ascending` unchanged; the calls fix (`l.Sum`) still resolves; an
aliased USER import's const-shaped member (`import f "ex.com/foo"; f.Ascending`) stays a deferred selector
(`_|_`), NOT the comparator struct. A local field shadowing the alias name with no import (`l: {Ascending:
7}`) stays field access (`7`) — the alias map is empty, the pass a no-op. An aliased import colliding with
a top-level field of the same name is the A2-y redeclaration error on the FILE-load path (matches cue's
rejection); the stdin/loader split for that collision is pre-existing and orthogonal to this slice.

### Tests

3 ParseTests theorems: `canonicalize_builtin_const_resolves_only_aliased_stdlib` (the helper + the
non-builtin-alias / unmapped-label / empty-map boundary), `parse_aliased_stdlib_const_resolves_like_unaliased`
(per-constant e2e — `Ascending`/`Descending` via `Sort` + standalone `Comparer`, vs the unaliased render),
and `parse_unaliased_const_and_aliased_user_member_unchanged` (the boundary — unaliased unchanged + an
aliased user member stays `_|_`). 1 Bug2xTests EXPORT pin `aliased_stdlib_const_sorts_like_unaliased` (a
regression to a deferred selector bottoms the Sort and fails the export). Fixtures:
`testdata/cue/builtins/aliased_list_const.{cue,expected}` (the dual CUE-port witness builds the CANONICAL
AST in `FixturePorts.lean` from `stdlibPackageValue?` while the CLI port parses the ALIASED `.cue` — both
matching `.expected` proves the canonicalization) and module fixture `testdata/modules/alias_list_const/`
(loader path through file load + import binding).

### Records

No `cue`-divergence (kue conforms once fixed) and no spec-gap (an alias is an unambiguous local rebinding —
spec-clear; the same basis as the calls fix). `plan.md` item-6 aliased-stdlib-constant entry struck
(RESOLVED); `spec-conformance-audit.md` item-6 tail updated.

---

## Phase-A Audit: aliased-builtin calls + constants (batch `f4feb93..406556e`) — HEALTHY

Code-quality pass over the two aliased-resolution slices (`ebaafc4` calls, `406556e` constants), per
`docs/guides/slice-loop.md` § Phase A. Highest-risk axis was over/under-canonicalization (a wrong dispatch
returns a wrong value), attacked exhaustively with every witness oracle'd against cue v0.16.1.

### Over/under-canonicalization — clean

OVER cases (must NOT rewrite a user import or a non-import name):
- A user package whose import path's last element is literally a builtin name (`example.com/json`,
  `example.com/list`), ALIASED (`import f "example.com/json"; f.Marshal`), resolves to the USER package's
  fields (`"USER_MARSHAL"`, `42`, `"USER_ASCENDING"`), NOT the builtin. `isBuiltinImport` keys on the full
  import PATH (`example.com/json` ∉ `builtinImportPaths`), not the local name — the dispatch boundary holds.
  Byte-identical to cue; pinned as module fixture `testdata/modules/alias_user_pkg_builtin_name/`.
- A local field shadowing an alias name with NO import (`l: {Ascending: 7}; out: l.Ascending`) → `7` (field
  access). `builtinImportLocalNames []` is `[]`, so `applyBuiltinAliases` short-circuits to a no-op.
- An import + a top-level field of the same name (`import l "list"; l: {…}`) → both kue and cue reject
  ("redeclared as imported package name"); no silent wrong value.

UNDER cases (must rewrite EVERY aliased builtin head, by binding not spelling):
- All builtin families aliased, calls AND constants in one file, byte-identical to cue.
- Binding-not-spelling (the highest wrong-dispatch risk): `import json "strings"; json.ToUpper("hi")` →
  `"HI"` (strings.ToUpper, NOT json), and the inverse `import strings "encoding/json"; strings.Marshal` →
  JSON marshal. The map keys on the import PATH's last element (canonical) paired with the as-written
  binding, so the spelling collision with another family's name is irrelevant. Both byte-identical to cue.

### Totality / DRY / spec

No new `partial`/`sorry`/axiom. `canonicalizeBuiltinCalls` is a fuel-bounded total `def` (the parser's
`partial`s are untouched). The `| other => other` catch-all is sound: every constructor it swallows
(`top`/`bottom`/`bottomWith`/`prim`/`kind`/`notPrim`/`stringRegex`/`boundConstraint`/`ref`/`refId`/
`thisStruct`) is a true `Value` leaf carrying no nested `Value`, so no aliased builtin can hide inside one;
and it matches the established sibling Value-rewrite idiom (`EvalOps.lean:171`, `Eval.lean:1821`/`2201`).
DRY: the calls + constants fixes share one pass; `canonicalizeBuiltinConst?` reuses the `builtinImportLocalNames`
alias map and `stdlibPackageValue?`; the `Value.lean` move de-dups `builtinImportPaths`/`isBuiltinImport`/
`lastPathElement` across the Parse/Module boundary (each defined exactly once). No `cue`-divergence (kue
conforms across every witness); no spec-gap.

### Both canaries re-confirmed DIRECTLY

cert-manager + argocd re-run from `/Users/chakrit/Documents/prod9/infra` as FULL whole-file exports (not the
`-e <field>` isolation that had a CLI quirk) — `kue export apps/<app>.cue | jq -S` vs `cue export … | jq -S`,
diff = 0 for both. Whole-file cert-manager export works (the `-e` field-isolation was the only quirk).

### Coverage added

`parse_aliased_builtin_call_resolves_like_unaliased` extended with the `regexp` family (was 6 families,
omitting the 7th builtin). New `parse_aliased_builtin_call_dispatches_by_binding_not_spelling` theorem
(the `import json "strings"` / `import strings "encoding/json"` cross-name cases). `builtin_import_local_names_*`
extended with the two cross-name unit assertions. Module fixture `testdata/modules/alias_user_pkg_builtin_name/`
(a user package whose path last-elem collides with a builtin, aliased — the strongest OVER witness, oracle'd
against cue).

### Phase-B latent finding (codebase-wide, deferred)

The four `| other => other` Value-rewrite catch-alls (`Parse.lean:1688`, `EvalOps.lean:171`,
`Eval.lean:1821`/`2201`) are sound today but silently bypass any FUTURE recursive `Value` constructor — an
under-rewrite the type system would not catch. Folded into `plan.md` as a Phase-B (architecture) item, not an
inline change (diverging one of four siblings in isolation would inconsistency-tax the idiom).

### Value-rewrite catch-alls made exhaustive (2026-06-23, type-safety hardening)

Resolved the finding above. Replaced all four `| other => other` catch-alls with explicit constructor
enumerations, so a future recursive `Value` constructor is a COMPILE error at each site (forcing a
recurse-or-leaf decision) rather than a silent pass-through:

- `canonicalizeBuiltinCalls` (`Parse.lean`) — a true STRUCTURAL rewrite (recurses every recursive ctor
  already), so the catch-all swallowed only leaves: enumerated the 11 leaves (`top`, `bottom`, `bottomWith`,
  `prim`, `kind`, `notPrim`, `stringRegex`, `boundConstraint`, `ref`, `refId`, `thisStruct`), each returning
  `value` unchanged.
- `collapseDefaultDisjunction` (`EvalOps.lean`), `openStructValue` + `closeEmbeddedOver` (`Eval.lean`) —
  SHALLOW projections (handle one ctor/shape, identity on the rest, NO recursion into children). Enumerated
  ALL pass-through ctors (leaf + recursive). The two `Eval` sites additionally carry an explicit
  `.struct _ _ _ _ _ => value` arm for the non-plain-struct shapes their narrow first arm
  (`.struct fields _ none [] _`) misses — which the catch-all had been absorbing.

Byte-identical (leaves/pass-throughs return the SAME values; suite 1697 `native_decide` pins conserved,
cert-manager + argocd `jq -S` = 0). Exhaustiveness VERIFIED to bite: a scratch dummy recursive ctor
(`scratchDummyRecursive (inner : Value)`) errored `Missing cases: (Value.scratchDummyRecursive _)` at all
four sites — `Parse.lean:1638`, `EvalOps.lean:170`, `Eval.lean:1820`, `Eval.lean:2230` — then reverted
(not committed). The scratch run also confirmed the codebase enforces exhaustiveness broadly (the same dummy
tripped pre-existing matches in `Format`, `Lattice`, `Manifest`, and several other `Eval` sites).

OUT of scope (deliberate, recorded): the two eval-dispatch fuel terminals `evalValueCoreWithFuel`
(`| _, value => pure value`) and `evalStructRefsM` (`| value => pure value`) are the eval fixpoint's
no-rule-needed fallback keyed on `(fuel, value)`, NOT structural `Value→Value` rewrites. Their identity arm is
already guarded by a synced leaf-enumeration helper (`valueReducesToSelf`, with a "MUST stay in sync"
maintenance note). Making them "exhaustive" would force re-listing every recursive ctor's full eval rule —
a different, semantically-loaded change, not this hardening.

---

## Completed Slice: `resolveEmbeddedDisjDefault` soundness check → CASE B fix `embed-disj-arm-closedness` (2026-06-23)

Closed the plan item-6 open question on `resolveEmbeddedDisjDefault`'s pass-1 label-surfacing
path. **Determination: CASE B — a real divergence, fixed.** Adversarial-first per the slice brief;
every witness oracle'd vs `cue` v0.16.1 (`/Users/chakrit/go/bin/cue`).

### What the question actually was

`resolveEmbeddedDisjDefault` (`= collapseDefaultDisjunction`, `Eval.lean:~1897`) is called in TWO
places. The brief flagged the one in `evalEmbeddingFieldsWithFuel` (`~3757`): this is
LABEL-SURFACING only — its `head ++ tail` result (`embeddingFields`) feeds exactly the Pass-2
frame augment (a `Self.<embedded-label>` selection) + the closedness union
(`closeEmbeddedOver merged embeddingFields …`, `~3539`). The VALUE is produced separately by the
`.disj` distribution arm of `meetEmbeddingsWithFuel` (`~3858`), which is where the V2
`embed-disj-arm-fallthrough` fix lives. So the label-surfacing call is NOT itself the value path —
but probing the value path under a use-site narrowing (the brief's "reaching THIS path") found the
bug one layer over.

### The divergence (CASE B)

The `.disj` distribution did `meet current (openStructValue alternative.snd)` per arm. `openStructValue`
reopens a closed def arm to `.regularOpen` — correct to WIDEN the host's allowed labels (an embedding
widens, never imposes), but it persisted into the residual `.disj`, so each arm lost its OWN closedness.
A LATER use-site narrowing introducing a label DISJOINT from a closed DEFAULT arm was then wrongly
ADMITTED, and the (still-live) default won:

| witness                                       | cue v0.16.1        | kue pre-fix                  |
|-----------------------------------------------|--------------------|------------------------------|
| `{(*_#A{n:5} \| _#B{s:string})} & {s:"x"}`    | `{s:"x"}`          | `{n:5, s:"x"}` (leak)        |
| `{(*_#A{n:int} \| _#B{s:string})} & {s:"x"}`  | `{s:"x"}`          | `incomplete value: int`      |
| `#S:{(*_#A{tag,n} \| _#B{tag,s})}; #S&{s:"x"}`| `{tag:"b",s:"x"}`  | `incomplete value: int`      |

cue rejects `s` from the closed default by closedness → default bottoms → survivor `_#B` wins. The
DIRECT (non-embedded) `(*_#A | _#B) & {s:"x"}` path was already CORRECT (`{s:"x"}`) — its arms stay
closed defs at meet time (`Lattice.meetWithFuel` `.disj, value` distributes WITHOUT opening), which
is the mechanism the embedded path failed to match.

### Fix (reuses the existing close machinery)

In the `.disj` arm, after `meet current (openStructValue arm)`, RE-CLOSE each arm per-arm via
`closeEmbeddedOver hostFields armFields armOpen armResult` — the exact analog of the top-level close
at `~3539`, applied inside the distribution. `closeEmbeddedOver` re-applies `applyClosednessFrom`
over (host ∪ arm) labels: widens by the host's labels (the host regular field a closed arm does not
declare still survives — `embed-disj-arm-closedness-host-extra-field` guard) yet restores the arm's
own closedness against the LATER narrowing. The default mark is preserved (the close is value-only).

### Regression guards held (all pinned, all green)

Disjunction-defaults capability `x:(*"a"|"b")&("b"|"c")`→`"b"`; equal-default dedup; mark-precedence;
AD2-1 lone-default collapse; the four V2 `embed-disj-*` pins (dead-default fall-through, live-default
kept, all-die conflict, single-arm); the host-extra-field WIDEN guard. 4 new `exportJsonMatches`
pins (`embed_disj_arm_closedness_*`) + a section `#check` sentinel.

### LATENT follow-up surfaced (NOT this slice, pre-existing)

A NESTED embedded disjunction-of-disjunction — `{(*_#Outer1 | {c:1})} & narrow` where `_#Outer1` is
itself `*_#Inner | …` and the narrowing kills the inner default `_#Inner` — loses the default MARK
on the surviving sub-arm: kue exports "ambiguous value: multiple non-default disjuncts remain" where
cue picks the marked survivor (`{b:"x"}`). Confirmed PRE-EXISTING by building HEAD in a throwaway
worktree: HEAD diverges too (differently — `incomplete value: int`, because the inner closed arm was
opened). My fix is strictly not-worse (it now correctly bottoms the inner closed arm; the residual
just hits a SEPARATE `flattenAlternatives`/`normalizeDisj` mark-inheritance gap). Distinct mechanism,
filed in the plan as a latent follow-up.

### Verify

`lake build` 112 jobs green (full `native_decide` suite incl. 4 new pins). `scripts/check-fixtures.sh`
`fixture pairs ok` (zero drift). Canaries from `/Users/chakrit/Documents/prod9/infra`: cert-manager
(~11.5s) + argocd (~51s) `jq -S` = 0 (content-identical). No shell touched (shellcheck N/A). No
`cue`-divergence/spec-gap recorded — kue now conforms to cue + the closedness algebra.

## Audit (single-pass, code-quality) — batch `20b8397..32ddfda` — HEALTHY + over-close coverage

Scoped single-pass audit over the type-safety catch-all refactor (`e8d6e85`) + the
embed-disj-arm-closedness soundness fix (`32ddfda`). **Verdict: HEALTHY.**

**Over-close verdict (the TOP risk) — REFUTED.** The per-arm re-close does NOT over-close a
legitimately-open arm, every witness oracle'd vs cue v0.16.1:

- A `...`-OPEN-tail default arm ADMITS a disjoint narrow (`{(*_#A{n:9,...} | _#B{s})} & {extra:1}`
  → `{n:9, extra:1}`, not bottom) — `closeEmbeddedOver` is identity on a tail-bearing struct, so
  the open arm is never re-closed; `evaluatedStructOperand?`'s `.defOpenViaTail → false` does NOT
  cause over-close because the value never reaches the plain-struct re-close arm.
- A PLAIN (non-def) open arm STAYS open (`_A{n}`, `armOpen=true` ⇒ no closedness imposed).
- host-extra-field survives WHILE the closed arm rejects the disjoint narrow, on ONE shape
  (`{h, (*_#A | _#B)} & {s:"x"}` → `{h, s:"x"}`).
- mark-precedence / equal-default dedup / AD2-1 lone-default / `(*"a"|"b")&("b"|"c")→"b"` all
  UNCHANGED. No valid arm wrongly bottoms.

**The 3 reported witnesses == cue post-fix** (closed-default `n:5` leak, `incomplete int`,
tagged-disjunction through `#S`).

**New nested-disj-of-disj default-mark latent — independently confirmed PRE-EXISTING** by building
the parent commit `e8d6e85` in a throwaway worktree: the same witness diverges there too
(`incomplete value: int`), differently from HEAD (`ambiguous value: multiple non-default disjuncts
remain`); both differ from cue's `{b:"x"}`. The fix is strictly not-worse. Filed (plan + breadcrumb)
as the next-leader candidate.

**Catch-all refactor BYTE-IDENTICAL.** 3 projection sites
(`openStructValue`/`closeEmbeddedOver`/`collapseDefaultDisjunction`) enumerate ALL non-target ctors
as pass-through identity (= the prior `| other => other`); `canonicalizeBuiltinCalls` enumerates only
the 11 true leaves (every recursive ctor recurses above the old catch-all). Exhaustiveness is
machine-proven by the compiler (green build, no `_`-wildcard) — stronger than a manual ctor count.

**Coverage ADDED inline** (the over-close direction was unpinned pre-audit): 3 `exportJsonMatches`
pins — `embed_disj_arm_closedness_open_tail_arm_admits_disjoint`,
`_plain_open_arm_admits_disjoint`, `_host_extra_survives_and_disjoint_rejected` — + a `#check`
sentinel. **Totality:** no new `partial`/`sorry`/axiom; the per-arm re-close is total.

Verify: `lake build` 112 jobs green (full `native_decide` + 3 new pins). `check-fixtures.sh`
`fixture pairs ok`. Both canaries `jq -S` = 0 from infra with the FRESHLY-BUILT binary (cert-manager
~11.5s, argocd ~51s). shellcheck clean (no shell touched). Audit counter RESET to 0.

---

## Designed-Deferral: Nested-Disjunction Outer-Default-Mark Inheritance (NESTED-DISJ-MARK)

Adjudicated the filed nested-disj-of-disj default-mark divergence (the embed-disj-arm-closedness
audit's latent follow-up). Outcome: **DESIGNED-AND-DEFERRED** — a correct, spec-verified diagnosis +
designed fix, deferred rather than shipping a mark change that would broadly risk the
default-selection precedence (the slice's explicit STOP condition). NO eval/lattice behavior changed;
this slice lands the spec-verified rule, the deferral record, and regression-guarding pins.

**STEP 0 — the spec-verified two-tier nested default-mark RULE (probed cue v0.16.1).** First finding:
the source form `*( … )` (a `*` directly on a parenthesized group) is a **parse error** — `preference
mark not allowed at this position`. The nesting only arises via a definition/ref whose body is a
disjunction (`_O: *_I | _B`, embedded as `*_O | …`). cue's rule for a `*`-marked GROUP that is itself a
disjunction-with-inner-`*`: the outer `*` puts the WHOLE group's arms in the OUTER default-set; the
inner `*` is a PREFERENCE WITHIN that set. After a narrowing prunes dead arms:
- **tier 1** — an inner-`*`-preferred arm survives ⇒ it is the default. `(*_I | 9) & (1|2)` with
  `_I:*1|5` → `1`; `(*_I | 9) & (>=1 & <=5)` → `1`.
- **tier 2** — the inner-preferred arm DIES but another inner arm survives ⇒ the surviving inner arm
  INHERITS the outer `*` and beats an outer-REGULAR survivor. `(*_#O | {c}) & {b:"x"}` (`#O:*#I|#B`,
  `#I` killed by closedness) → cue `{b:"x"}` (the marked survivor); scalar analog `(*_I | 9) & >=5`
  with `_I:*1|5` → `5`.
- An UNMARKED group does NOT inherit: `((*#I | #B) | {…}) & {b:"x"}` → cue ambiguous (`incomplete
  {b:"x"} | {b:"x",c?:int}`) — the inner survivor stays regular. The group `*`-vs-not is the
  discriminator cue exports on.

Reconciled an apparent contradiction: `(*_I | 9) & (2|9)` is ambiguous in cue, but `(*_I | 9) & >=5`
resolves to `5` — the difference is the narrowing being a DISJUNCTION (`.disj & .disj` cross-product
path, `withDefaultConvention` on both sides) vs a non-disjunction (`.disj & value`). The rule is
uniform; the `2|9` case just routes through a different, already-correct meet path.

**The divergence (tier-2 only).** Kue eagerly flattens a `(.default, .disj nested)` arm at EVAL time —
`Eval.lean:3410-3414` `.disj` case → `normalizeEvaluatedDisj` → `normalizeDisj` → `liveAlternatives`
→ `flattenAlternatives`. `*_I | 9` (`_I:*1|5`) becomes the FLAT residual `*1 | 5 | 9` — the inner
non-default `5` is now `.regular`, with no link to the outer `*`. A later narrowing that kills the
inner default `1` leaves `5` regular ⇒ export goes AMBIGUOUS where cue picks the marked survivor.
Confirmed in a PURE `.disj & value` form (`(*_I | 9) & >=5` → kue `5 | 9` ambiguous, cue `5`) and the
filed struct repro.

**Root cause (why deferred).** A flat 2-state `Mark` (`.regular`/`.default`) cannot encode the
two-tier "in the outer default-set WITH an inner preference": one bit holds either tier-1
(`[(.default,1),(.regular,5)]` — tier-2 lost) or all-default (`[(.default,1),(.default,5)]` — tier-1
lost, no-narrow `*_I|9` would wrongly go ambiguous instead of `1`), never both. The designed fix needs
one of:
- **(A)** a THIRD `Mark` state (`.groupDefault`) threaded through `flattenAlternatives` /
  `withDefaultConvention` / `resolveDisjDefault?` — ripples across 8 files (`Format`/`Manifest`/`Yaml`/
  `Order`/`Parse` all pattern-match `Mark`, which derives `BEq`/`DecidableEq`); or
- **(B)** do NOT structurally flatten a `(.default, .disj nested)` arm — keep it nested through
  `normalizeDisj` so the two-tier survives to meet time, where a narrowing-aware
  `distributeMeetIntoAlternatives` (drafted this slice in `Lattice.lean`'s `.disj & value` case,
  then REVERTED — it is dead code today because all disjunction construction routes through the
  eval-time flatten, so a nested `.disj` arm never reaches meet) resolves it — ripples the flatness
  invariant that `liveAlternatives` / `resolveDisjDefault?` / `Manifest`'s ambiguity-report / dedup all
  assume.

Both are LARGE, delicate changes to the exact default-mark algebra the slice flags as fragile, with a
broad default-selection regression surface. A correct adjudication + design is the valid outcome here;
a wrong mark change is not. DEFERRED, fully recorded.

**Landed this slice (no behavior change).** `cue-spec-gaps.md` NESTED-DISJ-MARK row (the two-tier rule
+ designed fix). `spec-conformance-audit.md` Genuinely-open #2 + `plan.md` open backlog. 5
`TwoPassTests` `nested_disj_mark_*` pins, all oracle'd vs cue: tier-1 (matches), no-narrow value
(matches), unmarked-group ambiguous (regression guard, matches), and TWO `⚠ DEFERRAL WITNESS` pins
(scalar + struct) asserting the current wrong-ambiguous via `exportJsonBottoms = true` — tripwires
that FLIP to false when the fix lands. + a `#check` section sentinel.

Verify: `lake build` 112 jobs green (full `native_decide` + 5 new pins). `check-fixtures.sh` `fixture
pairs ok` (zero drift). No eval/lattice behavior delta ⇒ canaries unchanged from the last green run
(the shape is absent from cert-manager + argocd; jq-S=0 holds). No shell touched. No
`partial`/`sorry`/axiom added.

---

## Completed Slice: DRY collapse `selectEvaluatedField .disj` → `selectFromConcrete` (item-6) (2026-06-23)

The item-6 DRY: `selectEvaluatedField`'s resolved-default `.disj` arm re-listed the carrier dispatch
(`.struct`/`.embeddedList`/`.embeddedScalar` → `selectFromDecls`) the top-level `match` already had.
Collapsed by EXTRACTING the non-disjunction carrier dispatch to a shared `selectFromConcrete (base
label)` — called both at the top level and once `resolveDisjDefault?` picks a default. The DRY win is
real (the carrier dispatch lives in one place); `selectFromConcrete` reads cleaner than the duplicated
5-arm sub-dispatch.

**Behavior determination (the crux — this is NOT a pure refactor).** The plan flagged the collapse
"gains free nested-disjunction recursion." Investigated precisely before shipping:

- **Carrier defaults (the source-reachable main case): BYTE-IDENTICAL.** `resolveDisjDefault?` returns
  a `.struct`/`.embeddedList`/`.embeddedScalar`; `selectFromConcrete` runs the same `selectFromDecls`.
  Pinned (`select_into_default_disjunction{,_scalar_carrier,_list_carrier,_nested_carrier}`).
- **Doubly-nested `.disj`-valued default: BYTE-IDENTICAL DEFERRAL (recursion gain DEFERRED).**
  `liveAlternatives` flattens ONE level, so a TRIPLE-nested disjunction leaves an inner `.disj` as the
  resolved default. The old `_` arm deferred this to `.selector`; the collapse keeps it with an
  explicit `some (.disj _) => .selector base label`. The "free recursion" (recursing → cue's `1`) was
  NOT shipped: a self-recursive `selectEvaluatedField` on `resolveDisjDefault?`'s output needs a
  well-founded `termination_by` proving the output is `sizeOf`-smaller through
  `liveAlternatives`/`flattenAlternatives` (a `foldr` that `++`s nested arms) /`dedupAlternatives` —
  LARGE + delicate machinery (same class as the deferred NESTED-DISJ-MARK fix) for a shape that
  eval-time flatten makes UNREACHABLE from source (verified: `x: *_O | {a:9}` with deep `_O` nesting
  evals to a FLAT `*{a:1}|{a:2}|…` before selection; cue + kue both → `1`). Not worth importing a WF
  recursion for an unreachable edge. Pinned the deferral (`..._deep_nested_defers`).
- **Field-select off a SCALAR default: kue bug FIXED to match cue (a gained correctness, not a
  divergence).** `resolveDisjDefault?` can return a scalar (`*5 | {a:1}`). The old `_` arm deferred
  `x.a` to a `.selector` ("incomplete value"); `selectFromConcrete` routes a `.prim` through its `_ =>
  .bottom`, so `x.a` is `.bottom` — a TYPE ERROR, matching cue (`invalid operand x … want list or
  struct`). Load-bearing downstream: `x: *5 | {a:1}; y: x.a | "fb"` was kue-AMBIGUOUS (the incomplete
  arm couldn't shed), cue → `"fb"`; post-fix kue → `"fb"` (the dead arm sheds). Pinned
  (`select_field_off_scalar_default_drops_arm`, via `exportJsonMatches`). NOT a cue-divergence (kue was
  wrong, now conforms), so no `cue-divergences.md` entry.
- **Ambiguous default (`none`): unchanged.** `none => .selector base label` preserved
  (`select_into_ambiguous_disjunction_still_defers`).

**Mark deferral tripwires unchanged (orthogonal).** The 2 `nested_disj_mark_*_DEFERRAL_witness` pins
(+ the 3 other `nested_disj_mark_*`) are a MEET/eval-time Mark-flattening problem
(`Eval.lean:3410-3414`) about which arm wins after a narrowing — nothing to do with the selection
dispatch. They still assert the deferred behavior (`exportJsonBottoms = true`), unflipped.

**Landed.** `Eval.lean`: new `def selectFromConcrete`; `selectEvaluatedField` reduced to a `.disj` arm
+ `_ => selectFromConcrete base label`. Two stale doc references (`selectedFieldValue`,
`selectFromDecls` headers: "four pluck sites"/"struct/embed arms") repointed at `selectFromConcrete`.
`TwoPassTests`: 4 new pins + a `#check` sentinel (the deep-nested DRY collapse). `plan.md` DRY item
struck.

Verify: `lake build` 112 jobs green (full `native_decide` + new pins). `check-fixtures.sh` `fixture
pairs ok` (zero drift). Canaries from `prod9/infra` root: cert-manager + argocd `jq -S` diff = 0
(byte-identical drop-in preserved — the scalar-default fix is absent from both corpora). No shell
touched. Total — no `partial`/`sorry`/axiom; `selectFromConcrete` is non-recursive (trivially
terminating).

---

## Completed Slice: CLI entry-UX — bare `kue` prints help; drop the empty-stdin smoke demo

Goal: make a freshly-`brew install`ed `kue` behave like a conventional CLI. Two
fresh-install killers: (1) bare `kue` with no args HUNG — `parse [] => .eval [] => runEval
[]` read `IO.getStdin.readToEnd`, which blocks forever on an interactive terminal, so a new
user typing `kue` saw a freeze and concluded it was broken; (2) `kue eval` on empty stdin
dumped a dev smoke reel (`int & 1 => 1`, `"a" & "b" => _|_`, …). Both are entry-path bugs;
`--help`/`-h`/`version`/per-command help already existed and were left intact.

### Fix (cue-aligned)

1. **Bare `kue` (no args) → top-level help, exit 0.** `Cli.parse [] => .help none` (was
   `.eval []`), matching `cue`/`git`/`docker` (bare command → usage). This fixes the hang
   AND surfaces the help that was hidden behind it. The `kue <file…>` shorthand is
   unaffected — it routes through `parse`'s positional-args fallthrough to `.eval files`,
   not `parse []`. Stdin eval is now explicit: `kue eval` (piped or `<`), never bare
   `kue`.

2. **Empty-stdin smoke demo removed.** `runEval []` dropped its `if trimmed-empty →
   printSmoke` branch; empty stdin now evaluates the empty source like any input → empty
   struct → empty output, exit 0, matching `cue eval -` (verified: `printf '' | cue eval
   -` → empty, exit 0). `printSmoke` deleted.

3. **Dead code removed.** `Kue/Examples.lean` (`smokeLines`, the 14 `*SmokeResult` defs,
   and the `smoke_lines_match_plan` `native_decide` theorem pinning the demo strings) was
   referenced ONLY by the removed `printSmoke` CLI hook — nothing else imports any of it.
   Deleted the file and its `import Kue.Examples` from `Kue.lean` (general-coding: no dead
   code). Build dropped 112 → 110 jobs.

4. **Harness call-sites.** `scripts/check-fixtures.sh` used the bare `kue <file` redirect
   (no args) in two places — which now prints help. Moved `check_cli_fixture_outputs` to
   the explicit `kue eval <file`, and repointed the `check_cli_behavior` eval-agreement
   check from the now-tautological bare-vs-`eval` redirect to the file-arg shorthand
   (`kue <file>` == `kue eval <file>`). Added two regression assertions: bare `kue
   </dev/null` prints the `Commands:` listing on exit 0 (the anti-hang guard), and `kue
   eval </dev/null` prints nothing on exit 0 (the no-smoke guard). The stale `Cli.lean`
   back-compat comments (claiming the harness depends on bare `kue < file`) were
   corrected.

5. **Help polish (small, in-scope).** Aligned the `Commands:` description column (the
   `export` line was the wide one), fixed the synopsis to `kue <file...>` (bare `kue` no
   longer evals), and added a 3-line Examples block.

### Tests

`CliTests.parse_empty` flipped to `parse [] = .help none` (`native_decide`). The file-arg
shorthand stays pinned (`parse_bare_file`/`parse_bare_files`). Harness gained the
anti-hang + no-smoke assertions above.

### Scope

Entry-UX only. The broader cue-aligned command surface (new `vet`/`fmt`/`def` subcommands,
a `-` explicit-stdin marker, flag parity) is a NEW user-scoped objective, deliberately not
started here (tracked in plan.md item 7, awaiting the user's CLI-design direction). The
`--version` = `0.1.0-alpha` vs dated-tag question is defensible as-is — noted, not
changed.

### Verify

`lake build` 110 jobs green (no warning/`sorry`/axiom; CLI/IO is pure-adjacent, no new
axioms in pure modules). Direct behavior: bare `kue` (no redirect) → help + exit 0, no
hang (was exit 124 / timeout); bare `kue </dev/null` → help + exit 0; `kue eval
</dev/null` → empty + exit 0 (not smoke); `kue <file>` byte-identical to `kue eval
<file>`; `kue eval` still reads piped stdin (`a: 1` round-trips).
`scripts/check-fixtures.sh` `fixture pairs ok` (zero drift, all CLI checks green).
`shellcheck scripts/check-fixtures.sh` clean. Canaries from `prod9/infra` root:
cert-manager + argocd
`jq -S` diff = 0 (entry-UX change doesn't touch eval/export). Total — no
`partial`/`sorry`/new axioms; the `parse` change is a single pure-arm flip.

---

## Completed Slice: B3d-1 — `CUE_REGISTRY` parse + module→OCI-ref resolution (PURE)

Goal: the fully PURE, offline foundation of the B3d registry-fetch track — given a
`CUE_REGISTRY` config string + a module path + a version, compute the OCI location (host,
secure-flag, repository, tag) with NO network, NO `curl`, NO IO. Transport decision:
`docs/decisions/2026-06-25-registry-fetch-via-curl-subprocess.md`.

### What landed

New pure, IO-import-free module `Kue/Registry.lean` (+ `Kue/Tests/RegistryTests.lean`,
registered in `Kue.lean` / `Kue/Tests.lean`). NOT yet wired into `Module.lean` — that is
B3d-4/5. Two pieces:

1. **`CUE_REGISTRY` simple-syntax parser** (`parseConfig`, `parseRegistry`). Empty/unset →
   the Central Registry default `registry.cue.works`, secure. A comma-separated list of
   `prefix=registryspec` (prefix-routed) or bare `registryspec` (catch-all) entries. A
   registry spec = `host` / `host:port` / `[::1]:5000`, an optional `/repository`
   path-prefix (split at the FIRST `/`), an optional `+secure`/`+insecure` suffix (peeled at
   the LAST `+`, index > 0). The literal `none` (global or `prefix=none`) means "no
   registry". Errors: empty part, empty prefix, empty reference, duplicate prefix, duplicate
   catch-all, unknown suffix.

2. **`module@version → OciRef` resolution** (`resolve`, `resolveFromConfig`,
   `selectRegistry`, `prefixMatches`, `joinRepo`). Longest-complete-element-prefix match
   (`foo/bar` matches `foo/bar/x`, NOT `foo/barry`; exact `prefix==path` wins outright;
   catch-all fallback). A `none` registry resolves to `Resolution.noRegistry` (fetch must
   fail cleanly). The repository = `joinRepo(prefix, basePath)`, the tag = the plain
   version.

### Conformance (cue v0.16.1 source — authoritative OCI protocol, NOT the language spec)

- `internal/mod/modresolve/resolve.go`: `ParseCUERegistry` (the simple-syntax parse +
  duplicate/empty rules), `parseRegistry` (one spec: `none` sentinel, `+suffix` at last `+`,
  `host[/repo]` first-slash split, `isInsecureHost`), `ResolveToLocation` (longest-prefix
  complete-element match, `path.Join(repository, mpath)`, `Tag = PrefixForTags+vers` —
  `PrefixForTags` empty in simple syntax). Many test expectations mirror its
  `resolve_test.go` lookup table.
- `mod/modconfig/modconfig.go`: `DefaultRegistry = "registry.cue.works"`; the
  `file:`/`inline:`/`simple:` kind split (only `simple` reaches this parser; `file`/`inline`
  DEFERRED).
- `mod/module/escape.go` `escapeString`: ASCII `A`–`Z` → `!` + lower-case, applied only when
  an upper-case rune is present (`Foo.com/Bar` → `!foo.com/!bar`). **Surprise pinned:** this
  escaping is used ONLY by the on-disk download/extract cache layout
  (`mod/modcache/cache.go`), NOT the OCI repository name — `ResolveToLocation` joins the RAW
  (unescaped) base module path. Both forms modelled (`escapePath`/`escapeVersion`,
  `extractCachePath`/`downloadCachePath`) for B3d-4/5 to consume.
- `mod/module/module.go` `BasePath` + `cue/ast/importpath.go` `SplitPackageVersion`: the
  `@<major>` suffix (`prodigy9.co/defs@v0`) is cut at the FIRST `@` and discarded for the OCI
  repo; the OCI tag carries the FULL version (`v0.3.19`). `stripMajor` / `mkModuleVersion`.

### Illegal-states-unrepresentable + totality

`RegistrySpec` = `none | reg host insecure repository` (a `none` registry carries no
host/repo — never confusable with an empty real one). `Resolution` = `found OciRef |
noRegistry | error msg` (a success always carries all four fields; "no registry" is its own
constructor, never a sentinel host). All functions total — no `partial`, `sorry`, or axiom.

### Test coverage

40+ `native_decide` theorems + `#guard`s in `RegistryTests.lean`: default/empty; bare host;
`host:port` secure; `host/path-prefix` join; multi-element prefix; `+insecure`/`+secure`
overrides (incl. with prefix); localhost / `127.0.0.1` / `[::1]` / `[::1]:5000` / `[0:0::1]`
default-insecure; non-loopback IPv6 secure; global `none`; `prefix=none` (matched +
fall-through); catch-all-`none`; longest-prefix-wins; complete-element boundary
(`bar` ≠ `barry`); exact-prefix; fallback entry; order-independence; the five config errors;
major-strip + full-version tag; `escape.go` upper-case escaping; both cache-path layouts.

### Verify

`lake build` 114 jobs green (no warning/`sorry`/axiom). `scripts/check-fixtures.sh`
`fixture pairs ok` (zero drift; no fixtures added — pure unit-pinned). No shell touched.
CLI smoke (`kue export <file>`) byte-identical. NO cue-divergence (conformed to cue source);
spec-gap recorded in `compat-assumptions.md` (the `file:`/CUE-syntax-config deferral; the
escaping/tag rules are cue tooling, outside the language spec).

---

## Completed Slice: B3d-2 — OCI image-manifest parsing (PURE, offline)

Goal: parse a CUE module's OCI image manifest (`application/vnd.oci.image.manifest.v1+json`)
JSON into typed descriptors — a total, PURE `String → Except String OciManifest` with NO
network / `curl` / IO. The impure `curl` GET that produces the manifest bytes is B3d-4's edge;
this is its pure, theorem-pinned core. Transport decision:
`docs/decisions/2026-06-25-registry-fetch-via-curl-subprocess.md`.

### What landed

New pure, IO-import-free module `Kue/Oci.lean` (+ `Kue/Tests/OciManifestTests.lean`,
registered in `Kue.lean` / `Kue/Tests.lean`). NOT yet wired into `Module.lean` — that is
B3d-4/5.

- **Typed, illegal-states-unrepresentable** `structure Descriptor` (`mediaType`, `digest`,
  `size : Nat`) + `structure OciManifest` (`config : Descriptor`, `layers : List Descriptor`).
  A manifest that omits any descriptor field is a parse ERROR, never a descriptor with an
  empty/zero placeholder. `schemaVersion` and the manifest-level `mediaType` are not retained
  (not load-bearing for descriptor extraction; cue itself never re-checks `schemaVersion`).
- **`parseManifest : String → Except String OciManifest`** over Lean's standard `Lean.Json.parse`
  (`Lean.Data.Json`, shipped with the toolchain). **No second JSON parser:** `Kue/Json.lean`
  only SERIALIZES (`ManifestValue → String`), so reusing the stdlib parser is the "reuse, don't
  reinvent" intent of the slice; it adds no Lake dependency. A malformed JSON document surfaces
  that parser's error cleanly; a missing/wrong-typed field surfaces `Lean.Json`'s own typed
  error (`property not found: …` / `String expected` / `Natural number expected`).
- **Layer selection BY mediaType, exactly-one** (`moduleZipDescriptor` → `application/zip`,
  `moduleFileDescriptor` → `application/vnd.cue.modulefile.v1`): `selectUniqueLayer` errors if a
  wanted layer is absent OR duplicated — never silently first-wins. This is strictly STRONGER
  than cue's blind `layers[0]`/`layers[1]` indexing (it rejects an ambiguous/absent layer cue
  would mis-read) while conforming to every well-formed manifest cue produces.
- **`validateModuleManifest`** enforces cue's `GetModuleWithManifest` invariants with conforming
  error phrasing: `isModule` (config mediaType == `application/vnd.cue.module.v1+json`), exactly
  two layers (`"module manifest should refer to exactly two blobs, but got N"`), both selectable
  layers present+unique. `isModuleManifest` / `parseModuleManifest` are the bool / one-shot forms.

### Conformance (cue v0.16.1 source — authoritative OCI protocol, NOT the language spec)

`mod/modregistry/client.go`:
- `unmarshalManifest` — JSON-decodes into `ociregistry.Manifest`.
- `isModule` — `m.Config.MediaType == moduleArtifactType` (`"application/vnd.cue.module.v1+json"`).
- `isModuleFile` — `desc.MediaType == moduleFileMediaType` (`"application/vnd.cue.modulefile.v1"`).
- `GetModuleWithManifest` — `len(Layers) == 2`; `isModuleFile(Layers[1])`; the error strings we
  mirror.
- `putCheckedModule` — the construction side: `Layers[0]` is the module zip (`application/zip`,
  `Size`, `Digest = digest.FromBytes(zip)`), `Layers[1]` is `cue.mod/module.cue`
  (`moduleFileMediaType`). The digest is the `sha256:<hex>` string we preserve VERBATIM so B3d-4
  can compare `Sha256.digestString blob == d.digest`.

### Illegal-states-unrepresentable + totality

Every descriptor carries all three fields by construction; `OciManifest` is config + layers. All
functions total — no `partial`, `sorry`, or axiom; parsing is `Except`-threaded, never panics.

### Test coverage

17 `native_decide`/`#guard` pins in `OciManifestTests.lean` (representative in-Lean manifest JSON
— the cache stores extracted files, not the manifest, so there is no raw manifest on disk to
golden against): a well-formed 2-layer module manifest → `moduleZipDescriptor` /
`moduleFileDescriptor` yield the right `{mediaType, digest, size}`, digest preserved verbatim;
config mediaType ≠ module type → `isModuleManifest` false + `validateModuleManifest` error; zip
layer absent OR duplicated → typed error (never first-wins); malformed JSON → clean parse error;
valid JSON missing a `digest` field / with a non-numeric `size` → typed error, no crash;
`parseDescriptor` in isolation (well-formed + missing-`mediaType`).

### Verify

`lake build` 122 jobs green (no warning/`sorry`/axiom; every `native_decide`/`#guard` pin
checked). `scripts/check-fixtures.sh` `fixture pairs ok` (zero drift; no fixtures added — pure
unit-pinned). No shell touched. NO cue-divergence (conformed to cue's own OCI tooling); no
spec-gap (OCI manifest parsing is tooling protocol, outside the CUE language spec — noted in
`compat-assumptions.md`).

### For B3d-4

- B3d-4 GETs the manifest at the resolved OCI ref (B3d-1), `parseManifest`s it,
  `validateModuleManifest`s it, then GETs the `moduleZipDescriptor` blob and checks
  `Sha256.digestString blob == descriptor.digest` (B3d-3). `moduleFileDescriptor` lets it fetch
  just `cue.mod/module.cue` for MVS dependency resolution without pulling the full zip.

---

## Completed Slice: B3d-3 — SHA-256 (FIPS 180-4) + `cue.sum` `h1:` dirhash (PURE)

Goal: the cryptographic primitive the B3d registry-fetch track needs — a total, IO-free
SHA-256 over `ByteArray` (to verify OCI blob `sha256:<hex>` digests in B3d-4) plus the Go
`golang.org/x/mod/sumdb/dirhash` `Hash1` ("h1:") algorithm a `cue.sum` line is built from
(to verify in B3d-5). kue had NO crypto/SHA-256 before this slice. Transport/decomposition
decision: `docs/decisions/2026-06-25-registry-fetch-via-curl-subprocess.md`.

### What landed

New pure, IO-import-free module `Kue/Sha256.lean` (+ `Kue/Tests/Sha256Tests.lean`, registered
in `Kue.lean` / `Kue/Tests.lean`). NOT yet wired into `Module.lean` — that is B3d-4/5. Three
pieces:

1. **SHA-256 core** (`sha256 : ByteArray → ByteArray`, 32-byte digest; `sha256String` for
   UTF-8 text). `UInt32`/`ByteArray` throughout (a `List Nat` impl is too slow under
   `native_decide`). FIPS 180-4: the 64 `K` round constants, the 8 `H0` init words, message
   padding (`0x80` + zero-fill to length ≡ 56 mod 64 + big-endian 64-bit BIT-length suffix),
   the 64-word message schedule (`σ₀`/`σ₁` recurrence), the 64-round compression
   (`Ch`/`Maj`/`Σ₀`/`Σ₁`, wrapping `UInt32 +`, `rotr` = `(x >>> n) ||| (x <<< (32-n))`), and
   big-endian word→byte serialisation. `UInt32`'s native ops ARE the spec's mod-2³² `+`, `SHR`,
   `<<`, `⊕`; only `rotr` is spelled out.
2. **Hex + OCI digest** (`hex : ByteArray → String` lowercase, `digestString` = `sha256:<hex>`).
   No prior bytes→hex helper existed in the codebase (only a hex-DIGIT predicate in `Yaml.lean`),
   so `hex` is new; B3d-4 uses `digestString` to verify a downloaded manifest/blob.
3. **dirhash `Hash1`** (`hash1 : List (String × ByteArray) → String`, `hash1Line` for one
   file). Byte-order name sort (compare on `String.toUTF8.toList`, matching Go `slices.Sort`
   over strings), per-file summary line `lowerhex(sha256(contents)) ++ "  " ++ name ++ "\n"`
   (TWO U+0020 spaces, one U+000A — `fmt.Fprintf(h, "%x  %s\n", …)`), outer SHA-256 over the
   concatenated summary, result `"h1:" ++ base64Std`. The std-base64 step REUSES
   `Kue.base64Encode` (the `encoding/base64` builtin's encoder) — not reimplemented.

### dirhash conformance + cue-source citation

The dirhash algorithm is `golang.org/x/mod/sumdb/dirhash` `hash.go` `Hash1` (read at
`~/go/pkg/mod/golang.org/x/mod@v0.26.0/sumdb/dirhash/hash.go`). The load-bearing
cue-specific fact is the dirhash `name` for a module-zip entry: cue's `modzip.Create`
(`~/go/pkg/mod/cuelang.org/go@v0.16.1/mod/modzip/zip.go`, the `dirFileIO.Path` =
`f.slashPath` path passed to `zw.Create`) stores zip entries under their BARE
module-root-relative slash path (`cue.mod/module.cue`, `foo.cue`) — it does NOT prefix
`<module>@<version>/` the way Go's own modzip does. `CheckZip` (same file) confirms by
validating bare names (`cue.mod/module.cue`, not `mod@ver/cue.mod/module.cue`). So the
dirhash `name` IS the raw zip-entry path; `hash1` is name-agnostic, keeping the zip-name
edge in B3d-4. cue v0.16.1 does NOT itself write/verify a `cue.sum` via dirhash in its
embedded source path (OCI blob-digest verification is its mechanism); `h1:` here serves
`cue.sum`-file verification (the format `cue mod` writes).

### Illegal-states + totality

All functions total — no `partial`, `sorry`, or axiom. SHA-256 is fixed-round (64 per
512-bit block) over a finite statically-padded message, so totality is structural. `#print
axioms` on `sha256`/`hash1`/`hash1Line` shows only `propext`/`Quot.sound`/`Classical.choice`
(the last from `Array.qsort`'s well-foundedness in stdlib) — no `sorryAx`.

### Test coverage + ground truth

30+ `native_decide`/`#guard` pins in `Sha256Tests.lean`:
- **NIST/FIPS 180-4 vectors** (exact): `""` → `e3b0c4…b855`; `"abc"` → `ba7816…15ad`; the
  56-byte `"abcdbcde…nopq"` two-block example → `248d6a…06c1`.
- **Padding boundaries** (all `'a'`-repeated, pinned vs `shasum -a 256` — an impl kue does not
  share): lengths 0, 55 (largest single-block-padding fit), 56 (forces 2nd block), 63, 64
  (exactly one input block), 65, 119 (the two-input-block padding boundary), plus an 85-byte
  mixed-content vector.
- **Digest/hex/primitive** spot pins (`digestString` empty-blob; `hex` lowercase; `rotr`,
  `ch`, `maj`).
- **dirhash structural**: `hash1Line` shape (inner sha256 + two-space + name + newline);
  the base64-std step over the empty digest.
- **dirhash `h1:` END-TO-END**: TWO values (single-file `cue.mod/module.cue`; two-file
  unsorted-input exercising the byte-order sort) reproduced INDEPENDENTLY from the Go
  algorithm with `shasum -a 256` + `base64` + the documented `%x  %s\n` summary —
  `h1:ftG4xWQPV4pZ9dJyz1U9yMplIdnOoyX/hdskb0yd9w8=` and
  `h1:P7/mTCFrvF77thKflcmV8eVMxjYU7kC0InTdJLeRHRI=`. This is a TRUE cross-check (not
  self-consistency), so there is **no soft gap** — the end-to-end `h1:` is independently
  grounded offline. (No local `cue.sum` exists on disk to anchor against, but the Go-algorithm
  reproduction via standard Unix tools is an equivalent, stronger ground truth.)

### Verify

`lake build` 118 jobs green (no warning/`sorry`/axiom; every `native_decide` pin checked,
incl. all SHA-256 vectors + both `h1:` values). `scripts/check-fixtures.sh` `fixture pairs
ok` (zero drift; no fixtures added — pure unit-pinned). No shell touched. NO cue-divergence
(conformed to FIPS 180-4 + the Go dirhash source); no spec-gap (SHA-256/dirhash are tooling
protocol + a published standard, outside the CUE language spec — noted in
`compat-assumptions.md`).

### For B3d-2 / B3d-4

- **B3d-4 (curl edge)** verifies blob digests with `digestString`/`sha256`: an OCI manifest
  has exactly 2 layers, `layers[1]` = module file (`application/vnd.cue.modulefile.v1`),
  `layers[0]` = the zip (`application/zip`); each blob's descriptor digest is `sha256:<hex>`
  of its bytes (`digest.FromBytes`, `mod/modregistry/client.go`). `digestString blob` must
  equal the descriptor's `digest` field.
- **B3d-2 (manifest parse)** supplies those descriptors; `Sha256.digestString` is the verifier
  it hands B3d-4.
- **`cue.sum` (B3d-5)**: `hash1` takes the in-memory `(zip-entry-name, contents)` list; the
  zip reader (B3d-4) supplies BARE entry names verbatim (no `<module>@<version>/` prefix).

---

## Completed Slice: B3d-4 — OCI fetch over a `curl` subprocess (offline-verified)

Goal: the IO edge of the B3d registry-fetch track — actually GET an OCI module manifest +
blob off a registry, over a `curl` subprocess (decision
`docs/decisions/2026-06-25-registry-fetch-via-curl-subprocess.md`), decomposed into PURE,
offline-testable builders plus a thin impure runner. B3d-4 only PROVIDES the fetch capability;
wiring it into the resolver (the `Module.lean` fetch-trigger) is B3d-5.

### PURE — OCI Distribution URL/argv builders (`Kue/Oci.lean`)

Authoritative protocol source (cue v0.16.1 tooling, so the Go code IS the spec): the URL paths
in `cuelabs.dev/go/oci/ociregistry/.../ocirequest/create.go` and the manifest `Accept` header
set in `ociclient/client.go` `doRequest`. Added (all `native_decide`/`#guard`-pinned):

- `scheme : OciRef → String` — `http` if `insecure` else `https`.
- `manifestUrl ref` → `<scheme>://<host>/v2/<repository>/manifests/<tag>`.
- `blobUrl ref digest` → `<scheme>://<host>/v2/<repository>/blobs/<digest>` (digest verbatim).
- `manifestAcceptTypes` — cue's `knownManifestMediaTypes` in order: the OCI image manifest +
  index, the deprecated `…artifact.manifest.v1+json`, the three docker manifest types, then
  `*/*`. Some registries withhold the body without an explicit `Accept`, so all known kinds are
  offered.
- `curlBaseFlags := ["-sSL", "--fail-with-body"]`; `acceptHeaderArgs` (one
  `-H "Accept: <type>"` per type, mirroring Go's multi-valued header);
  `manifestCurlArgs`/`blobCurlArgs` (full argv, URL last).

`Oci.lean` gained `import Kue.Registry` (pure → pure; it consumes `Registry.OciRef`).

**curl flags — chosen by philosophy (fail loud, never silently mis-succeed):** `-s` silent (no
progress meter) + `-S` show-errors (a `-s`-suppressed error still prints to stderr); `-L`
follow redirects (registries 307 a blob GET to backing object storage — without `-L` curl
returns the redirect body, not the blob); `--fail-with-body` (a non-2xx HTTP status makes curl
exit non-zero so the IO runner sees the failure, WHILE still writing the error body to stdout —
`--fail` alone discards it, so the registry's JSON error is preserved for the diagnostic). An
HTTP 404/401 is thus a Lean `Except.error`, never a successful empty fetch. Output goes to
stdout (no `-o`), so the fetch itself writes nothing to disk.

### IMPURE — the thin curl runner + fetch composition (`Kue/OciFetch.lean`, NEW)

The codebase's FIRST `IO.Process` user. Imports only the pure trio Oci/Sha256/Registry — never
Eval/Resolve/Value (the Phase-B seam: IO depends on the pure protocol core, never the reverse).
Each function is a total `IO (Except String _)`:

- `runCurl args` — **spawns** curl (`stdout := .piped`) and captures stdout as RAW bytes via
  `readBinToEnd`. NOT `IO.Process.output`: that decodes stdout as a UTF-8 `String`, which
  corrupts a binary module zip and would make digest verification compare mangled bytes. stdout
  (the body, possibly large) is drained BEFORE `wait` so a full pipe never deadlocks the child;
  stderr (kept small, since `--fail-with-body` routes error bodies to stdout) is read after.
  Exit 0 → `ok bytes`; non-zero → `error` with the exit code + stderr.
- `curlGet url extraArgs` — the single curl seam every fetch routes through
  (`curlBaseFlags ++ extraArgs ++ [url]`).
- `curlGetVerified url expectedDigest` — the SHA-256 **integrity gate** at URL level: requires
  `Sha256.digestString bytes == expectedDigest`, else error. Expressed at the URL level so it is
  exercisable against a `file://` fixture offline.
- `fetchManifest ref` — GET (with the manifest `Accept` headers) → `parseManifest` →
  `validateModuleManifest`; returns a confirmed 2-layer CUE module manifest.
- `fetchBlob ref descriptor` — `curlGetVerified (blobUrl ref descriptor.digest) descriptor.digest`.
  A corrupt/tampered/wrong-content blob is REJECTED — the integrity gate the whole B3d-3 SHA-256
  work exists to enforce.
- `fetchModuleZip ref` — manifest → `moduleZipDescriptor` → `fetchBlob`; returns the verified
  zip BYTES. Extraction + cache-write + resolver wiring are B3d-5.

No `partial`/`sorry`. The pure builders depend only on `propext`; the IO functions on the
standard `propext`/`Quot.sound`/`Classical.choice` every `IO` action carries.

### Offline test — the curl seam end-to-end via `file://` (NO network)

Mechanism (matches the existing IO-test idiom — `scripts/write-fixture-ports.lean` run by
`scripts/check-fixtures.sh`): a new `scripts/check-ocifetch.lean`, run as
`lake env lean --run scripts/check-ocifetch.lean <testdata/ocifetch>` and wired into
`check-fixtures.sh` (`check_ocifetch_seam`), so the loop's verify gate covers it. Fixtures under
`testdata/ocifetch/` (committed, repo-local): `manifest.json` (a valid 2-layer cue module
manifest whose zip-layer digest is the REAL sha256 of `module.zip`), `module.zip` (an opaque
blob standing in for a module zip — the seam tests integrity, not zip validity, which is B3d-5),
`modulefile.cue` (the module-file blob). Six assertions, all PASSING:

1. `curlGet` reads a `file://` blob (the subprocess seam works without a network).
2. captured bytes hash to the fixture digest (raw-byte capture is byte-faithful — proves
   `readBinToEnd`, not UTF-8 String decoding).
3. `curlGetVerified` (the `fetchBlob` path) PASSES on the correct digest.
4. **`curlGetVerified` REJECTS a mismatched digest** — the integrity gate, the whole point of
   verifying blobs (REQUIRED test).
5. `curlGet` on a missing path errors (curl exits non-zero → `Except.error`; no silent empty
   success).
6. the fixture manifest validates + its zip descriptor digest matches `module.zip`.

The fixture digests were precomputed with `shasum -a 256` (an impl kue does not share — a true
cross-check). No network, no out-of-tree writes (the script only READS the fixtures).

### Verify

`lake build` 124 jobs green (no warning/`sorry`; the new pure pins all checked).
`scripts/check-fixtures.sh` → `fixture pairs ok` + the `ocifetch file:// seam ok` block (all six
assertions). `shellcheck scripts/check-fixtures.sh` clean. `curl --version` present
(8.20.0). No cue-divergence (conformed to the OCI Distribution spec + cue's client). Spec gap:
none beyond what `compat-assumptions.md` already records for the fetch edge (auth/login,
tag-listing for MVS = B3d-6).

### The live-registry fetch — human-gated (logged, not failed)

The real HTTPS GET from `registry.cue.works` was NOT run: network egress + out-of-tree writes
are outside the AFK envelope. The edge is implemented + offline-verified (`file://`); the live
smoke is logged in `.afk.log` with the exact `curl` one-liner (manifest GET with the same flags
+ `Accept` headers Kue emits, then a blob GET) a human can run — a one-word go-ahead unblocks it.
A logged gap, not a failure; the slice lands green offline.

### For B3d-5 (wire into resolver)

B3d-5 replaces the `Module.lean:32` `moduleNotOnDiskError` (`registry fetch is B3d`) with:
resolve (`Registry.resolveFromConfig` over `$CUE_REGISTRY`) → `OciFetch.fetchManifest` →
`moduleZipDescriptor` → `OciFetch.fetchBlob` (or `fetchModuleZip` for both at once) → write the
verified zip to the download cache (`Registry.downloadCachePath`) → unzip into the extract cache
(`Registry.extractCachePath`) → fall through to the existing read-path (`locateModuleDir`). It
also folds in B3d-5a (unify the cache-layout authority). B3d-4's edge hands it the verified zip
bytes; what it still needs is a zip extractor and the cache directory writes (both new IO).

---

## Completed Slice: B3d-5z — pure-Lean ZIP reader + DEFLATE inflate + CRC-32 (offline-verified)

Goal: the PURE transform the verified module-zip bytes from `OciFetch.fetchModuleZip` (B3d-4)
need next — unzip them into in-memory `(name, contents)` entries so B3d-5 can write them to the
cache and `Sha256.hash1` (already present, takes `List (String × ByteArray)`) can hash them into
a `cue.sum` `h1:` line.

### The fork: pure Lean, not an `unzip` subprocess

Resolved by philosophy (decision note
`docs/decisions/2026-06-25-registry-fetch-via-curl-subprocess.md`, extended to extraction). The
curl GET is the SOLE impurity in the fetch path; the transform of already-verified bytes belongs
in the pure core. Pure Lean is deterministic, total, fully offline-`native_decide`-testable, adds
no runtime dependency, and composes directly with the dirhash — it wins on every axis. cue module
zips are confirmed all-DEFLATE (`unzip -v` shows `Defl:N`), so a STORED-only reader would not do:
real RFC 1951 inflate was required.

### `Kue/Inflate.lean` (RFC 1951 inflate)

- **`BitReader`** — LSB-first within each byte (`readBit`/`readBits`/`alignByte`/`readByte`);
  Huffman codes' MSB-first-within-the-code packing is handled by the decoder, not the reader.
- **`Huffman`** — a canonical table BUILT from per-symbol code lengths (§3.2.2: count per length,
  first-code-per-length, symbols grouped by length in ascending symbol order); `decodeGo` walks
  bits MSB-first accumulating `(code, len)` and maps a matched code to its symbol in `O(maxBits)`.
- **Three block types** — STORED (§3.2.4: align, LEN/NLEN with the `NLEN = ~LEN` check, raw
  copy), fixed Huffman (§3.2.6 fixed lit/len + 5-bit dist tables), dynamic Huffman (§3.2.7: HLIT/
  HDIST/HCLEN, the code-length-code preamble in `clcOrder`, then RLE symbols 16/17/18 decoding the
  literal+distance code lengths).
- **§3.2.5 base+extra tables** for length codes 257..285 and distance codes 0..29.
- **LZ77 back-reference copy** — `copyBackref` copies byte-by-byte from `out.size - dist`, so
  overlapping copies (a `dist=1` run-length fill is the common case) are correct; a `dist`
  pointing before the output start is a typed error.

### `Kue/Zip.lean` (PKWARE container + CRC-32 + top level)

- **Little-endian `u16`/`u32`** readers (out-of-range → 0, caught structurally upstream).
- **CRC-32** — table-free, poly `0xEDB88320`, reflected, init/final `0xFFFFFFFF` (the zip
  standard). `crc32 "" = 0`, `crc32 "123456789" = 0xCBF43926`.
- **`Method`** sum type (`stored`/`deflate`) — illegal-states-unrepresentable for compression;
  any other central-directory method is a typed error at parse time, never a silent skip.
- **EOCD backward scan** (`findEocd`, bounded by the ≤ 65535-byte comment window) → **Central
  Directory walk** (`parseCentralDirectory`, bounded by the EOCD entry count) reading name /
  method / CRC / sizes / local-header offset per entry. The central directory is the
  AUTHORITATIVE index (local headers can defer sizes to a data descriptor); the local header is
  re-read only for its name+extra lengths to find the compressed-data start.
- **`readZip : ByteArray → Except String (List (String × ByteArray))`** — decompresses each
  entry (STORED = raw span, DEFLATE = `Inflate.inflate`), VERIFIES the uncompressed size AND the
  CRC-32 against the central-directory values (the integrity gate, like B3d-4's blob-digest gate —
  a mismatch is rejected, never returned), and SKIPS directory entries (empty or trailing-`/`
  names) exactly as cue's own `mod/modzip` `Unzip` does. Entries returned in central-directory
  order; names are the bare module-root-relative paths (no `<mod>@<ver>/` prefix, cue's modzip
  convention) so they feed `hash1` verbatim.

### Totality (no `partial`)

The Huffman symbol loop is bounded by `bitLen + 1` (every iteration consumes ≥ 1 bit and the
reader cannot advance past `data.size * 8`); the block loop by `data.size + 1` (every block reads
≥ 3 bits); `decodeGo` by `maxBits - len` (≤ 15) via `termination_by`. Out-of-fuel is unreachable
on well-formed input (the end-of-block symbol always arrives first) but yields a typed
"truncated/malformed" error rather than a `partial` non-termination hole. `#print axioms` shows
only `propext`/`Quot.sound`(/`Classical.choice`) — no `sorryAx`, no `partial`.

### Tests

`Kue/Tests/ZipTests.lean` `native_decide`-pins, all on SMALL independently-produced inputs (a
big in-kernel inflate is slow, so the large golden goes through the binary): CRC-32 standard
vectors; raw-deflate byte vectors from Python `zlib.compressobj(wbits=-15)` (fixed-Huffman
literals, fixed-Huffman back-ref, dynamic-Huffman, empty, `dist=1` RLE) — an encoder Kue does
not share, so decoding them back is a genuine cross-check; synthetic STORED (`zip -0`) and
DEFLATE (`zip -9`) archives from the system `zip` tool decoded back to their `(name, contents)`;
and error paths (non-zip → error, reserved BTYPE=3 → error). Golden: `scripts/check-zip.lean`
(wired into `scripts/check-fixtures.sh`, mirroring `check-ocifetch.lean`) drives `readZip` over
a real cached cue module zip `testdata/zip/module.zip` (`prodigy9.co/defs` v0.3.4 — 69 flat
all-DEFLATE files, ~90 KB) and cross-checks every file's sha256 + central-directory order against
`testdata/zip/module.zip.sha256` (ground truth from `unzip -p <zip> <name> | shasum -a 256`).
All 69 files byte-identical, all CRC-verified. No network; READ-only over committed fixtures.

### For B3d-5 (wire into resolver)

B3d-5 now has the full chain: `OciFetch.fetchModuleZip ref` → verified zip BYTES →
`Zip.readZip bytes` → `(name, contents)` entries → (a) write each to the extract cache
(`Registry.extractCachePath`), and (b) `Sha256.hash1 entries` for the `cue.sum` `h1:`
verification. The extractor and CRC gate are done; what B3d-5 still adds is the cache directory
writes (new IO) and the resolver wiring that replaces `Module.lean`'s `registry fetch is B3d`.

## B3d-5 — fetch→extract→cache-write→read-path wiring (+ B3d-5a folded) — 2026-06-26

The CONNECT slice: the B3d pieces (Registry resolve, OciFetch curl edge, Sha256/hash1, Zip
reader) were all built but inert. B3d-5 wires them into `Module.lean`'s import resolver so a
declared dependency absent from disk is FETCHED rather than hard-erroring `registry fetch is B3d`.

### Wiring

`Module.lean` gained `import {Registry,OciFetch,Zip,Sha256}` — the correct dependency direction
(the IO module depends on the pure protocol core; the core never depends on IO). The fetch
triggers at exactly ONE site: the `none` branch of `resolveImportTarget` (a dep that
`locateModuleDir` finds in neither vendor nor cache). On that branch it reads `CUE_REGISTRY`,
calls `fetchAndCacheModule`, and on success retries `locateModuleDir` — the existing read-path
then takes over UNCHANGED. On a fetch/verify failure it falls back to the original
`moduleNotOnDiskError` phrasing (the dep genuinely couldn't be supplied). A module already on disk
never enters this branch, so the read-path is byte-identical to before.

New functions (all total `IO (Except …)`, no new `partial`/`sorry`):
- `readCueRegistry : IO String` — the env read (empty/unset ⇒ `Registry.parseConfig`'s default).
- `readCueSum : FilePath → IO (List (String × String))` — parse an importer's `cue.sum`
  (`<modpath> <version> h1:<base64>` lines, go.sum-shaped) when present; `[]` when absent.
- `lookupCueSum` — the recorded `h1:` for a dep, keyed `modpath@version`.
- `writeModuleToCache root mv zipBytes entries` — write the raw zip to
  `<root>/download/<esc-path>/@v/<esc-ver>.zip` and each entry under
  `<root>/extract/<esc-path>@<esc-ver>/`, via the `Registry` cache-path authority (`root` is the
  `<cacheRoot>/mod` base). Returns the extract root.
- `fetchAndCacheModule cueRegistry importerRoot dep fetchZip` — resolve (`none`/unset registry ⇒
  clear "cannot fetch" error) → `fetchZip ref` → `Zip.readZip` → `cue.sum` `h1:` check (when
  recorded) → `writeModuleToCache`. `fetchZip` is INJECTED (production passes
  `OciFetch.fetchModuleZip`; the offline test passes a local-file reader) so the cache-write +
  read-path is exercisable without the OCI URL scheme.
- `resolveImportTarget` gained a `where loadDepContext` helper (shared by the present-on-disk and
  post-fetch branches) — reads the dep module's own `module:`/`deps` and returns its context.

### Cache-write layout + atomicity

Layout is Go-module-style, the same the read-path already consumed: `mod/download/<esc-path>/@v/
<esc-ver>.zip` (raw verified zip) + `mod/extract/<esc-path>@<esc-ver>/<entry>` (unpacked). Both go
through `Registry.{downloadCachePath,extractCachePath}`. Atomicity is a plain `createDirAll` +
write (NOT temp-dir-then-rename) — the alpha choice. Acceptable because the read-path keys off the
extract *directory* and the entries land before the retry-locate reads it; a crash mid-write would
leave a partial extract dir a future `cue mod` verify (B3d-6) should re-validate. Noted as a
B3d-6 hardening candidate.

### cue.sum verification (the integrity finding)

cue v0.16.1 ships **no** `cue.sum` mechanism — there is no `HashZip`/`golang.org/x/mod/sumdb/
dirhash` consumer in its source, and nothing reads or writes a `cue.sum` file. The OCI blob
`sha256:` digest (verified in `fetchBlob`/`curlGetVerified`, B3d-4) is cue's only live integrity
check. So B3d-3's `Sha256.hash1` had no live consumer. Resolved by philosophy
(defense-in-depth + don't-block-real-modules): the OCI digest is the primary gate (matches cue);
kue ADDITIONALLY enforces a `cue.sum` `h1:` line when the importer ships one (a mismatch REJECTS
the install — never silently proceed), and proceeds when absent (matching cue v0.16.1). Recorded
in `cue-spec-gaps.md`. `cue.sum` WRITE (`cue mod tidy`) is B3d-6.

### B3d-5a — unified cache-path authority (folded in)

The Phase-B audit flagged a latent divergence: `locateModuleDir` computed the extract path itself
(`joinModulePath`, UNescaped) while `Registry.extractCachePath` computed it ESCAPED — agreeing on
real lowercase paths but diverging on an (illegal-but-constructible) uppercase path
(`Foo.com/Bar`: read `…/Foo.com/…` vs write `…/!foo.com/…` → silent cache miss). Fixed by routing
`locateModuleDir`'s `cached` candidate through `Registry.extractCachePath` — now read- and
write-path agree by construction, including the escaping. Byte-identical for real lowercase
modules: the argocd canary stayed at a 0-line `cue export` diff, and `ModuleTests` pins
`extractCachePath "/c/mod" (mk "lib.example/defs" "v0.1.0") = "/c/mod/extract/lib.example/defs@v0.1.0"`,
the escaping-identity on lowercase, and the closed uppercase divergence.

### Tests

- **Offline pipeline test** `scripts/check-fetch-pipeline.lean` (wired into `check-fixtures.sh`,
  mirroring `check-ocifetch.lean`/`check-zip.lean`): drives `fetchAndCacheModule` with a real
  DEFLATE fixture zip `testdata/ocifetch/pipeline/module.zip` (`lib.example/defs@v0.1.0`) and
  `CUE_CACHE_DIR` → a repo-local temp dir set by the shell wrapper (Lean has no `setEnv`). Pins:
  install succeeds → extract root + entries on disk → raw zip in the download layout →
  `locateModuleDir` finds it → located dir == `Registry.extractCachePath` (B3d-5a); plus the
  negative cases run first against the still-empty cache and each is asserted to error AND leave
  nothing locatable — `none` registry, transport failure, and a WRONG `cue.sum` `h1:` (rejection);
  and a MATCHING `cue.sum` passes. No network (the fetcher reads a local file); the temp cache is
  removed by the wrapper.
- **B3d-5a guards** in `Kue/Tests/ModuleTests.lean` (`native_decide`): the lowercase
  `extractCachePath` layout, the escaping-identity on a real path, and the uppercase divergence.
- **Canary (non-regression):** `kue export apps/argocd.cue` from `prod9/infra` (the
  `prodigy9.co/defs` dep is in the real cache) is byte-identical to `cue export` (`jq -S` diff =
  0 lines) — the present-on-disk read-path never enters the fetch branch and the B3d-5a
  unification did not move the cache location. (cert-manager in this infra checkout is plain YAML,
  not a CUE module — argocd is the live CUE canary.)

`lake build` clean (0 warnings/`sorry`; `fetchAndCacheModule`/`writeModuleToCache`/`locateModuleDir`
on only `propext`/`Classical.choice`/`Quot.sound`). `scripts/check-fixtures.sh` green incl. the new
pipeline gate. `shellcheck scripts/check-fixtures.sh` clean.

### The live gap (human-gated)

NOT run (out of AFK envelope): the real HTTPS fetch of a genuinely-missing dep from
`registry.cue.works` — outbound network egress + a WRITE to the real `~/Library/Caches/cue`. Exact
human smoke recorded in `.afk.log`: remove `prodigy9.co/defs` from the real cache, `kue export
apps/argocd.cue` from `prod9/infra`, expect a successful fetch+verify+load (export = `cue export`)
instead of the not-on-disk error.

### For B3d-6

MVS version *solving* (resolve a version *range* to a concrete pin), the `cue mod get/tidy`
commands, and `cue.sum` WRITE — the last reuses the `atomicWriteBinFile` primitive landed in
B3d-A1 (below). Private/Bearer-token registries (the `WWW-Authenticate` flow) also remain.

---

## Audit Slice: B3d Phase-A code-quality (curl/inflate/zip + fetch wiring, `90aa8d5..c9c8e30`)

Recovery entry, retroactively written 2026-07-02 — landed as `c93bade` (2026-06-26,
`docs/spec/plan.md` +76) with no log entry at the time.

Phase-A audit of B3d-4 (OciFetch/Oci), B3d-5z (Inflate/Zip), B3d-5 (Module.lean
fetch-on-missing), per `docs/guides/slice-loop.md` Phase A. **Verdict:
HEALTHY-with-fixes.** The three integrity gates (OCI blob sha256 digest, zip CRC-32 +
uncompressed-size, `cue.sum` h1) are ENFORCED on the production fetch path and
unbypassable — traced fetch → readZip(CRC) → cue.sum → writeModuleToCache; nothing
unverified reaches the cache; digest compared verbatim, fails closed. Inflate total (no
partial/sorry/axiom), fuel bounds provably sufficient, malformed-DEFLATE branches all map
to typed errors. No Violation, no security hole.

Fix-slices folded into `plan.md`: **B3d-A1** (soundness, MED, top-ranked — non-atomic
extract cache-write + pathExists-only trust in `locateModuleDir`; a crash mid-extract
leaves a partial module the read path silently trusts; fix = extract-to-temp + atomic
rename) and **B3d-A2** (test-strength, LOW — adversarial DEFLATE/ZIP reject branches
under-pinned). No inline fixes (both slice-sized). `lake build` (130 jobs) +
`check-fixtures.sh` + shellcheck green.

---

## Audit Slice: B3d Phase-B architecture (module graph + B3d-6 readiness)

Recovery entry, retroactively written 2026-07-02 — landed as `92f0b80` (2026-06-26) with
no log entry at the time.

Architecture/refactor audit over the B3d module graph. **Verdict: HEALTHY-with-fixes.**
Module graph clean — no cycles; IO confined to OciFetch/Module; Eval/Resolve/Value import
zero B3d modules.

- **B3d-A1 SHARPENED** with a concrete design: extract-to-sibling-temp + atomic
  `IO.FS.rename` (same-fs), the `.partial`-marker alternative rejected, `.zip` temp-rename
  for Go-modcache parity. Own slice; land in/before B3d-6.
- **B3d-B1 filed (LOW, new):** `Descriptor.digest` / `cue.sum` h1 stringly-typed — YAGNI
  now; trigger at B3d-6 where `cue.sum` WRITE gives a second consumer (Digest/Hash
  smart-constructor newtypes, parse-once-at-boundary).
- `Kue/Bytes.lean` re-eval trigger fired → CONFIRMED STILL YAGNI (no shared signature:
  Sha256 BE vs Zip LE, one consumer each). `Inflate.readDynamicTables` sym==18 branch
  BORDERLINE but unreachable by `Huffman.build` construction — as-is. `Module.lean` not
  yet outgrowing its home; `ModuleFetch.lean` carve trigger noted for B3d-6.

B3d-6 readiness: READY. `lake build` (130 jobs) + fixtures + shellcheck green.

---

## Completed Slice: Atomic cache write — temp-dir + rename (B3d-A1)

The TOP-RANKED B3d fix from both audit phases. B3d-5's `writeModuleToCache` extracted a fetched
module's zip entries one-by-one DIRECTLY into the final slot `mod/extract/<esc>@<ver>/`, and
`locateModuleDir` trusts that dir on a bare `pathExists`. A crash mid-extract left a PARTIAL
module a later run silently loaded as complete (wrong value, no re-fetch). The bytes are already
integrity-verified (OCI digest + per-entry CRC), so this is a durability/atomicity bug, not a
security hole — MED soundness.

### Design — atomic publish via sibling temp + POSIX rename

- **`atomicExtractDir (dest) (entries)`** unpacks every entry into a sibling temp dir
  `<parent>/.tmp-<dest-fileName>-<nonce>/` — SAME parent as the final slot ⇒ SAME filesystem ⇒
  POSIX `rename(2)` is atomic — then `IO.FS.rename`s that temp dir onto `dest`. `dest` is
  therefore only ever observed COMPLETE or ABSENT; `locateModuleDir`'s bare `pathExists` is sound
  **by construction**, zero read-path change, no second on-disk invariant (the `.partial`-marker
  alternative was rejected by the Phase-B audit — strictly worse).
- **`atomicWriteBinFile (path) (bytes)`** does the same for a single file: write `<path>.tmp-<nonce>`
  then rename onto `path`. The download `.zip` now goes through it (Go-modcache parity — removes the
  truncated-`.zip` window).
- Both are **reusable primitives** in `Kue/Module.lean`; B3d-6's `cue.sum`/lockfile WRITE will share
  `atomicWriteBinFile`.

### Nonce — `freshNonce`, total

`IO.monoNanosNow` (cross-process separation — two attempts almost never start the same nanosecond)
paired with `IO.rand 0 0xFFFFFF` (covers the residual + same-process same-nanos case), as
`"<nanos>-<rand>"`. Both are ordinary `IO` reads — **no `partial`**, no failure mode. A fresh nonce
per attempt means a stale `.tmp-…` from a prior crash never collides; `atomicExtractDir` also
defensively `removeDirAll`s a same-named pre-existing temp before extracting.

### Stale temp + rename-over-existing

A leftover `.tmp-…` dir is excluded from the exact `<esc>@<ver>` slot name `locateModuleDir`
matches (the `.tmp-` prefix guarantees it), so a crash orphan is never mistaken for a real module —
CONFIRMED by test. Inline GC is left to a future `cue mod` cache-clean (B3d-6+), per the audit.
Rename-over-existing race (a concurrent fetch published the slot first): the loser `removeDirAll`s
its own temp and reuses the extant complete slot — `rename` onto a non-empty dir is never attempted.

### Crash-window soundness tests (`scripts/check-fetch-pipeline.lean`)

Extended the offline pipeline driver (repo-local `CUE_CACHE_DIR`):
- a pre-created `.tmp-<slot>-…` partial dir for a PRESENT slot ⇒ `locateModuleDir` still resolves
  the real published slot, never the partial;
- a `.tmp-…` partial for an ABSENT slot ⇒ module stays `none` (no partial load);
- **idempotent re-fetch** over an existing slot succeeds (no rename-over-existing crash) and leaves
  NO lingering `.tmp-` dir.

### Verification

`lake build` clean (130 jobs, 0 warnings/`sorry`, no new `partial`/axiom). `scripts/check-fixtures.sh`
green incl. the extended pipeline gate. `shellcheck` clean. Regression: `prod9/infra` argocd canary
`kue export apps/argocd.cue | jq -S` vs `cue export … | jq -S` = **0-line diff** (read-path
unmoved).

---

## Completed Slice: B3d-6a — semver compare + pure MVS solver (PURE, offline)

Goal: land the fully-offline pure core of B3d-6 — the version-ordering and version-selection
math — so the network-gated `cue mod` surface (B3d-6b) sits on top of a proven, total solver.
Two new IO-free modules; no network, no out-of-tree writes.

### Semver comparison (`Kue/Semver.lean`)

A faithful Lean port of Go's `golang.org/x/mod/semver` `Compare` — the package cue depends on
for module-version ordering, authoritative OVER strict semver.org. Source cited:
`~/go/pkg/mod/golang.org/x/mod@v0.15.0/semver/semver.go` (`parse`, `parseInt`,
`parsePrerelease`, `compareInt`, `comparePrerelease`, `isNum`, `isBadNum`).

- `parse : String → Option Parsed` — leading `v`; `vMAJOR` and `vMAJOR.MINOR` are `.0` / `.0.0`
  shorthands; `parseInt` rejects extra leading zeros; an optional `-prerelease` (dot-split
  identifiers, each `[0-9A-Za-z-]`-only, non-empty, all-numeric ones rejected for leading zero
  via `isBadNum`) and an optional `+build` (same charset, no bad-num rule); anything trailing ⇒
  invalid. Returns `none` for an invalid version.
- `compare : String → String → Int` (`-1/0/+1`): **invalid < valid**, two invalids equal (Go's
  `Compare` contract). Numeric major/minor/patch via Go's **`compareInt` = LENGTH-then-ASCII** on
  the no-leading-zero decimal string — so `v1.2.0 < v1.10.0` and `v2.0.0 < v10.0.0` order
  NUMERICALLY, not lexically. A version WITH a prerelease sorts BEFORE the same release.
- Prerelease ordering is the SPLIT of Go's single `comparePrerelease`: `comparePrerelease`
  handles the top-level "no prerelease is HIGHER" rule (empty list > non-empty); the inner
  `comparePrereleaseIds` does dot-by-dot (numeric < non-numeric; two numerics by length-then-
  ASCII; otherwise ASCII) and on EXHAUSTION makes the SHORTER set LOWER ("a larger set of
  pre-release fields has higher precedence"). Keeping these two rules separate (Go conflates them
  behind its top-level empty-string check) was the one subtlety — an initial single-function
  version mis-ordered `alpha < alpha.1`.
- **Build metadata `+…` is IGNORED in precedence** (parsed for validity only).

### MVS solver (`Kue/Mvs.lean`)

Russ Cox's Minimal Version Selection (<https://research.swtch.com/vgo-mvs>), the algorithm cue
and Go use. Source cited: cue v0.16.1 `internal/mod/mvs/mvs.go` (`BuildList`/`buildList`) and
`graph.go` (`NewGraph`, `Graph.Require`, `Graph.BuildList`, `sortVersions`).

- `RequirementGraph = List (ModuleVersion × List ModuleVersion)` — an EXPLICIT finite value (each
  module@version → its direct (module, minVersion) requirements). Pure: no IO callback, so
  reachability + maxima are deterministic and termination is structural. (Resolved by philosophy:
  an explicit graph value over `cue`'s network-pulling `Reqs` interface — illegal-states fewer,
  total, offline-testable.)
- `solve : ModuleVersion → RequirementGraph → List ModuleVersion`. Algorithm = **max of the
  mins**: compute the transitively reachable node set from the root, then for every module PATH
  the MAXIMUM version appearing anywhere in that set (mirrors `Graph.Require`'s
  `selected[path] = max(selected[path], dep.version)` over `Semver.compare`). "Minimal" names the
  per-requirement minimum each edge demands; MVS takes their max so all constraints hold while
  never jumping to "latest" ⇒ reproducible.
- **Build-list ORDER** (cue's `Graph.BuildList` + `sortVersions`): the **target first**, pinned to
  its own version (cue requires `reqs.Max(target,v)==target` — the target always wins for its own
  path, even if the graph names a higher version of it), then every OTHER selected path sorted by
  `(path, version)` (path ASCII, version by `Semver.compare` as tiebreak).
- **Distinct MAJORS are distinct PATHS** (`m` vs `m/v2`) — they get independent `selected[path]`
  entries and coexist; never a conflict. (The major is encoded in the path, exactly as cue's
  `module.Version`.)
- **Termination, no `partial`/fuel-hack:** reachability is `reachAux` over a `fuel` bound =
  `|allNodes| + |targets| + 1` with a visited set — each non-skip step adds one DISTINCT node
  (≤ `|allNodes|`), each skip strictly shrinks the worklist, so a **cycle halts** and the worklist
  drains before fuel runs out. `selectMaxima`/`sortSelected` are finite folds/`qsort`. Only
  `propext` (no `sorry`, no axioms beyond the stdlib defaults).
- `solveMany` covers cue's multi-target `BuildList` (a workspace with several main modules): roots
  first (deduped by path, in order), then the sorted remainder.

### Tests (`Kue/Tests/MvsTests.lean`, TDD-first, `native_decide`/`#guard`)

- **Semver:** the full doc-comment precedence chain pinned pairwise —
  `v1.0.0-alpha < -alpha.1 < -alpha.beta < -beta < -beta.2 < -beta.11 < -rc.1 < v1.0.0` (note
  `-beta.2 < -beta.11` is the NUMERIC-not-lexical pin); `v1.2.0<v1.10.0` / `v2.0.0<v10.0.0` /
  `v1.0.2<v1.0.10`; numeric-identifier < alpha-identifier; longer-prerelease-set wins;
  build-metadata-ignored; invalid<valid + two-invalids-equal; leading-zero invalidity;
  `vMAJOR`/`vMAJOR.MINOR` shorthands; `maxVersion` fold.
- **MVS — the canonical worked examples:** the **diamond** (main→A,B; A→C v1.2.0; B→C v1.3.0 ⇒
  select **C v1.3.0**, max of mins); an **upgrade** (main directly requires C v1.4.0 ⇒ it
  dominates both transitive mins); a **downgrade-by-not-requiring** (drop B's edge on C ⇒ C falls
  to v1.2.0, no explicit downgrade). Plus same-module-two-mins→take-higher,
  distinct-majors-coexist (`m`+`m/v2`), a **cycle (A⇄B) terminates**, unreachable-excluded,
  empty-graph⇒just-main, main-path-pinned-over-a-higher-graph-version, and path-sorted remainder.

### Verification

`lake build` clean (136 jobs, **0 warnings/`sorry`**, no `partial`/axiom in the new modules).
`scripts/check-fixtures.sh` green — `fixture pairs ok` + the fetch-pipeline / zip-golden / ocifetch
gates all pass (no regression). No shell touched (`shellcheck` n/a). **No network, no out-of-tree
writes** — both modules are IO-free and the tests are `native_decide` over in-source fixtures.

### Remaining (B3d-6b, network-gated)

NOT wired into the resolver — that needs the requirement graph BUILT from network-fetched deps'
`module.cue`. B3d-6b: (1) fetch each dep's `module.cue` `deps` to build the `RequirementGraph`;
(2) OCI `tags/list` for "latest"/major resolution; (3) `cue mod get`/`cue mod tidy` command
parse + dispatch; (4) wire `Mvs.solve` into the resolver (replace lenient per-hop resolution with
one up-front MVS build-list); (5) `cue.sum` WRITE via `Module.atomicWriteBinFile`.

## Audit Slice: B3d Phase-A on B3d-6a — semver empty-segment validity + MVS fuel truncation

Recovery entry, retroactively written 2026-07-02 — landed as `e0d1156` (2026-06-26;
`Kue/Semver.lean`, `Kue/Mvs.lean`, `Kue/Tests/MvsTests.lean`, `docs/spec/plan.md`) with
no log entry at the time.

Re-derived B3d-6a against the Go/cue oracles; **two Violations found, both fixed inline.**

- **Semver:** ordering byte-for-byte conformant with Go `x/mod/semver`, but parse
  accepted EMPTY prerelease/build segments (`v1.2.3-`, `v1.2.3+`, `v1.2.3-alpha+` valid in
  Kue, invalid in Go). Root cause: parse conflated "no `-`/`+` tail" with "an empty
  tail". Fix: track hasPre/hasBuild, reject an empty segment after its marker. `isValid`
  feeds B3d-6b candidate-tag filtering — a real (narrow) bug.
- **MVS:** max-of-mins/build-list order/distinct-majors/cycles all conform, but
  `reachable`'s fuel bound `|allNodes|+|targets|+1` counted only DISTINCT expansions while
  `reachAux` burns fuel on every step incl. skips — a near-complete 6-node graph reached
  only 4, silently dropping build-list nodes. Fix: fuel = (N+1)², a sound bound on TOTAL
  steps.

Totality reconfirmed via `#print axioms` (propext/Classical.choice/Quot.sound only).
Tests: +6 semver empty-segment `#guard`s, `mvs_dense_no_truncation` (`native_decide`),
axiom pins for `compare`/`solve`. `lake build` (136 jobs) + fixtures + shellcheck green.

---

## Audit Slice: B3d Phase-B CLOSURE — track HEALTHY; audit sections distilled

Recovery entry, retroactively written 2026-07-02 — landed as `f40dd9c` (2026-06-26,
docs-only) with no log entry at the time.

Final Phase-B architecture/cleanup audit of the B3d registry-fetch track. **Verdict:
HEALTHY** — module graph a clean DAG (IO confined to OciFetch+Module; Eval/Resolve/Value
import zero B3d modules; pure-island → thin-IO-edge seam holds); three integrity gates
enforced + unbypassable; inflate total. `Mvs.solve` ruled an ACCEPTABLE
deliberately-staged pure primitive (follow-on B3d-6b filed), not orphaned dead code.
`Module.lean` (674 lines) not yet outgrowing its home; `Kue/ModuleFetch.lean` carve filed
as a B3d-6b-conditional trigger.

Plan-hygiene: the three accumulated 2026-06-26 B3d audit sections (~292 lines) folded
into one terse closed-state note in `plan.md` carrying the landed-track summary + ranked
open items (B3d-6b network-gated, B3d-A2, B3d-B1, `Mvs.solve` main-pin hardening, the
ModuleFetch carve trigger, the perf-guide note). No code touched; build (136 jobs) +
fixtures + shellcheck green.

---

## Completed Slice: B3d-7 — OCI Bearer-token Auth (curl + docker credential-helper)

The unblock for fetching real/private deps: the curl edge did a BARE GET, so registries that gate
reads behind the Docker/OCI **Bearer-token flow** (`ghcr.io`, `registry-1.docker.io`) returned
`401`. This slice adds that flow. Decision (recorded, not relitigated): implement bearer auth over
curl + source credentials via the **docker credential-helper protocol** — NO new binary dependency
(oras/crane rejected to preserve "self-contained on ubiquitous tools").

### The auth flow

A bare GET → `401` + `WWW-Authenticate: Bearer realm=…,service=…,scope=…`. The client mints a token
(`GET <realm>?service=…&scope=…` with HTTP Basic when a credential exists, tokenless otherwise) →
`{"token":…}` → retries the original request with `Authorization: Bearer <token>` → `200`.

`OciFetch.authedGet`: bare GET → on the non-2xx, a header PROBE (`curl -sSL -o /dev/null -D -`, no
`--fail-with-body` so the `401`'s headers come back) → `wwwAuthenticateOf` (last `WWW-Authenticate`
line, case-insensitive) → `OciAuth.parseChallenge` → `mintToken` → authed retry. A `401` that can't
be parsed/satisfied is a clear typed `Except.error`, never a hang or a swallowed empty success. The
raw-byte blob path is preserved (no UTF-8 decode of binary); the bearer header is built from an
in-memory token and passed only as curl argv.

### Cred-helper dispatch (`resolveCredential`)

`OciAuth.credSourceFor` decodes `~/.docker/config.json` (pure over the file text) to a `CredSource`
sum: `inline base64UserPass` (the `auths.<host>.auth` field) | `helper binaryName`
(`credHelpers.<host>` wins, else global `credsStore`, only for hosts with an `auths` entry) | `none`.
The IO edge: inline → `base64DecodeString` + `splitUserPass`; helper → spawn
`docker-credential-<binary> get` (host on stdin, EOF via dropping the moved stdin handle) →
`parseHelperResponse` `{Username,Secret}`; none → `none` (then an anonymous tokenless mint, which
public registries like ghcr issue for public repos).

### Token cache

`OciFetch.TokenCache = IO.Ref (List (String × String))`, keyed by `realm|service|scope`. A fresh
cache per `fetchModuleZip` is threaded through `fetchManifest` + `fetchBlob` so a `401`-gated
registry mints ONE token for the manifest + blob GETs. IN-MEMORY only — never persisted.

### base64 DECODE (`Kue/Base64.lean`)

The module had encode only; added a total `base64Decode : String → Option (List UInt8)` (rejects
bad length, non-alphabet chars, malformed padding — `none`, no panic) + `base64DecodeString`.
Round-trips `base64Encode`; pinned against the system `base64` tool (independent ground truth).

### Pure core (`Kue/OciAuth.lean`, `native_decide`-pinned)

`parseChallenge` (param order / quotes / whitespace / case-insensitive scheme / comma-in-quoted-
scope / extra params tolerated; missing realm or non-Bearer scheme → `none`); `queryEncode`
(RFC-3986 unreserved set) + `tokenUrl`; `parseTokenResponse` (`token` ∥ `access_token`, `token`
wins); `credSourceFor`; `splitUserPass`; `parseHelperResponse`. All total over `Lean.Json.parse`,
no `partial`/`sorry`/axioms.

### The live ghcr proof

Drove kue's OWN `fetchManifest` + `fetchBlob` against the REAL `ghcr.io` for
`prodigy9.co/defs@v0.3.19` (`CUE_REGISTRY=prodigy9.co=ghcr.io/prod9`, sourcing the cred from the
osxkeychain helper). Result: manifest = the validated 2-layer module manifest; the zip blob
DIGEST-VERIFIES (`sha256:b5de5cb543c043ec2fd41d96f47d76eb68ce5eb71bc240be8aac421192ffa2fb`, 109225
bytes — public content addresses). The whole bare-GET → 401 → challenge-parse → cred-resolve →
token-mint → authed-retry → digest-verify pipeline works end-to-end. Probe:
`scripts/check-ghcr-live.lean` (NETWORK + creds, deliberately NOT in the offline gate).

### Secret hygiene

A resolved credential and a minted token live ONLY as curl argv (visible to the curl child, never
echoed by us) + in-memory `String`s. Never printed, logged, written to disk, committed, or put in a
fixture. Offline tests use SYNTHETIC base64 (`dXNlcjpwYXNz` = `user:pass`) and synthetic
challenges/responses. The staged diff was grepped for token-shaped strings before commit — clean.
Errors report OUTCOMES (an unsatisfiable `401`, a helper non-zero exit), never the secret value.

### Tests

Offline (`Kue/Tests/OciAuthTests.lean`, `native_decide`/`#guard`): base64 decode round-trips +
malformed rejection; `WWW-Authenticate` parse (canonical ghcr, case-insensitive scheme, param
reorder, unquoted, whitespace + extra params, comma-in-quoted-scope, no-scope, `Basic` rejected,
missing-realm rejected); token-URL build + percent-encoding; token-response (`token` vs
`access_token`, both-present, extra fields, empty/none/malformed); docker-config → `CredSource`
(inline / credsStore-with-auths-entry / per-host-helper-wins / absent-host / store-without-entry /
malformed); `splitUserPass` (first-colon, colon-in-password, no-colon); `parseHelperResponse` (incl.
the `<token>` identity-token convention). Live: the ghcr probe above.

### Verification

`lake build` clean (0 warnings/`sorry`, no `partial`/axiom in the new modules — the `Id.run do`
loops are structurally total). `scripts/check-fixtures.sh` green (no regression; the new offline
auth pins compile-as-`#guard`). Live ghcr probe PASS (manifest ok, blob digest + size match). No
shell touched (the live probe is a Lean script run via `lake env lean --run`, so `shellcheck` n/a).

### Remaining (B3d-6b)

B3d-7 unblocks B3d-6b's requirement-graph fetch: its dep-`module.cue` GETs now work against
authed/private registries, not just public anonymous ones. B3d-6b still needs the `module.cue`
`deps` parser to BUILD the graph, OCI `tags/list` for "latest"/major resolution, the
`cue mod get/tidy` command surface, wiring `Mvs.solve` into the resolver, and `cue.sum` WRITE.

## Completed Slice: Default disjunction in string interpolation (wild default-disj-in-interpolation)

Wild-caught (2026-06-28), fixed 2026-06-29. The layer-2 residual that survived the
`self-hidden-in-list-embed` fix: a DEFAULT disjunction read as a string-interpolation operand
kept the interpolation incomplete instead of shedding to its default.

### Root cause

`Kue/Eval.lean`, the `fuel + 1, .interpolation parts` eval arm: each part was evaluated, then
`evalInterpolation` rendered the operands via `interpolationText?`. A `.disj` operand (e.g.
`#r: string | *"ghcr.io"`) is non-string-coercible, so `interpolationText?` returned `none` and
the whole interpolation stayed a `.interpolation` — `incomplete value: "\(string | *"ghcr.io")…"`
at export. The mechanism was confirmed empirically (the previous slice's hand-off diagnosis held),
not assumed: an interpolation hole is a CONCRETE-REQUIRED context, and the default was never
forced there.

### The fix (`Kue/Eval.lean`)

`.map collapseDefaultDisjunction` over the evaluated parts before `evalInterpolation`. This reuses
the SHARED default-shedding projection (`Kue/EvalOps.lean`, `collapseDefaultDisjunction` →
`resolveDisjDefault?`) that the dyn-label key, the `if` guard, the scalar/unary operand, and the
embedded-disjunction arm already use — no parallel path forked (DRY). It is identity on every
non-default-disjunction value, and `resolveDisjDefault?` only sheds a UNIQUE marked default (or a
sole live regular arm), so an ambiguous disjunction (no default, multiple defaults) stays a `.disj`
and renders incomplete — matching cue.

### Tests

Wild fixture `testdata/wild/default-disj-in-interpolation/` UNQUARANTINED (`.known-red` removed) —
now enforced: `"\(#r)-suffix"` with `#r: string | *"ghcr.io"` → `"ghcr.io-suffix"`. Five
`native_decide` pins in `Bug2xTests.lean` (each cross-checked against cue):

- `interp_default_disj_sheds_to_default` — the fix.
- `interp_no_default_disj_bottoms` — `string | int` (no default) stays incomplete → bottoms.
- `interp_default_overridden_by_unification` — `#r: "x"` overrides → `"x-suffix"` (unified, not
  default).
- `interp_multiple_defaults_bottoms` — `*"a" | *"b"` (no unique default) → bottoms.
- `plain_ref_default_disj_unchanged` — `y: #r` (non-interpolation) → `"ghcr.io"` unchanged;
  confirms only the interpolation path moved.

### prod9 re-sweep (read-only, cached deps, no network) — LAYER 3 FOUND

`apps/{lem,n8n,x9,typesense,cert-manager}.cue`, `kue export` vs `cue export`, diff lines:

| app          | before | after | note                                          |
| ------------ | ------ | ----- | --------------------------------------------- |
| lem          | bottom | 188   | still bottoms — NEW layer 3                   |
| n8n          | bottom | 322   | still bottoms — NEW layer 3                   |
| x9           | bottom | 449   | still bottoms — NEW layer 3                   |
| typesense    | bottom | 223   | still bottoms — NEW layer 3                   |
| cert-manager | 0      | 0     | no regression                                 |

The interpolation fix IS confirmed working in the apps: the `namespace.yaml` subtree now exports
clean, with `"ghcr.io-pull-secret"` (the defaulted-disjunction interpolation) resolved. The
residual bottom is a SEPARATE construct — `"website.yaml": _|_` and `#out: _|_`, sourced from the
`packs.#WebApp & parts.#UseKeel` composition (`prodigy9.co/defs@v0.3.19`): a `conflicting values`
hard conflict (not an incomplete), distinct from layers 1–2. cert-manager has no such composition,
hence clean.

LAYER 3 NOT captured as a self-contained wild fixture: every module-free reduction attempted
either flips polarity (kue clean / cue errors) or drops `#UseKeel` inputs cue needs (both error) —
the conflict only manifests faithfully (kue bottoms / cue clean) inside the full app graph, which
is not self-contained `.cue`. Isolating a faithful minimal repro is the next slice's first job;
the reproduction path is the real app under `CUE_REGISTRY="prodigy9.co=ghcr.io/prod9"` with the
cached `defs@v0.3.19`. Logged as a blocker in `.afk.log`.

## Completed Slice: Self.#hidden in List Embeddings (wild self-hidden-in-list-embed)

Wild-caught (2026-06-28) from prod9 `apps/{lem,n8n,x9,typesense}.cue` via
`defaults.#Basics`/`packs.#WebApp` (`prodigy9.co/defs@v0.3.19`): kue exported `bottom` where
cue and the spec yield a clean value.

### Root cause

A definition embeds another def by reference (`#Base: {#Meta, …}`) and carries a `Self`-aliased
LIST embedding whose item reads a hidden field the embed contributes (`[{name: Self.#name}]`,
`#name` from the `#Meta` embed). The embedding-`Self` two-pass
(`needsEmbeddedSelfPass`/`embeddedSelfPassFieldIndices`, `Kue/Eval.lean`) re-evaluates only the
STATIC `canonical` fields against the frame augmented with the embedded labels. The
`Self.<embedded-label>` read here lives inside an EMBEDDING (the list literal classified
`isEmbeddingValue`), not a static field — so the two-pass never touched it. The list embedding
was evaluated by `evalEmbeddingFieldsWithFuel` / `meetEmbeddingsWithFuel` against the Pass-1
frame (`nested`), which lacks the sibling-embedding-contributed `#name` → `Self.#name` resolved
to `_|_`, then the non-output definition's `_|_` failed export.

Spec basis (kue was WRONG): embedding is unification, so a hidden field is in scope for
same-struct references however contributed → `Self.#name` must be `string`; and a non-concrete
value in an unreferenced definition is non-output and must not fail export. cue agrees with the
spec (no `cue-divergences.md` entry).

### The fix (`Kue/Eval.lean`)

New gate `embeddingsReadEmbeddedSelf canonical embeddings newEmbeddedLabels` (mirrors
`needsEmbeddedSelfPass`, but scans the EMBEDDING values rather than the static fields — an
embedding sits at the host's frame depth, so `refsSelfEmbeddedLabel evalFuel 0 selfIndex` applies
directly). When it fires, the embeddings are RE-EVALUATED against the augmented frame
(`canonical ++ newEmbeddedFields`): both `evalEmbeddingFieldsWithFuel` (for `embeddingFields`,
used by `closeEmbeddedOver`) and `meetEmbeddingsWithFuel` (for `met`, the actual embedded values)
take `nestedForEmbeds` instead of `nested`. Gated tightly — byte-identical when no embedding reads
a sibling-embedded `Self.<L>`. Applied identically to BOTH struct-eval arms: the eager
`.structComp` arm (~`Eval.lean:3553`) and the def-force arm (~`Eval.lean:4124`).

`Kue/Manifest.lean` was NOT touched — fix #1 alone makes `Self.#name` resolve to `string`
(incomplete, not `.contradiction`), and the existing manifester arm already keeps the non-output
definition out of export. The genuine-conflict case (`#u: 1 & 2` → bottom) still errors (pinned).

### Tests

New wild fixture `testdata/wild/self-hidden-in-list-embed/` (red → green), wired into a new
`check_wild_fixtures` runner in `scripts/check-fixtures.sh` (`kue export --out json` vs
`<slug>.expected`). New `native_decide` pins in `Kue/Tests/Bug2xTests.lean`:
`self_hidden_in_list_embed_resolves` (export `{z:1}`), `self_hidden_in_list_embed_value_concrete`
(the list item's `name` is the concrete `Self.#name`), `def_genuine_conflict_still_bottoms`
(adversarial: `#u: 1 & 2` still bottoms), `self_hidden_plain_embed_resolves` (adversarial:
non-list `Self.#hidden` still works), `list_embed_no_self_hidden_unaffected` (adversarial: a list
embedding with no Self-hidden read is byte-identical).

### prod9 re-sweep (read-only, cached deps, no network)

`apps/{lem,n8n,x9,typesense,cert-manager}.cue`, `kue export` vs `cue export`:

| app          | before | after                                              |
| ------------ | ------ | -------------------------------------------------- |
| lem          | bottom | bottom — RESIDUAL (default-disj-in-interpolation)  |
| n8n          | bottom | bottom — RESIDUAL (same)                           |
| x9           | bottom | bottom — RESIDUAL (same)                           |
| typesense    | bottom | bottom — RESIDUAL (same)                           |
| cert-manager | 0-diff | 0-diff (no regression)                             |

The list-embed Self-hidden layer this slice targets is RESOLVED for all four: a faithful minimal
repro (`#Basics`-shaped, nested `Self.#components.pull_secret` reads, list embedding, `#out`
selection) exports clean once `#registry` is made concrete — proving the chained
`Self.#components.X` read now resolves (was the bottleneck). The four apps still bottom solely on
a SEPARATE, newly-isolated layer: a DEFAULT disjunction (`#registry: string | *"ghcr.io"`) read
into a string interpolation (`"\(Self.#registry)-pull-secret"`) does not apply its `*` default at
export, leaving the interpolation incomplete. cert-manager has no such construct, hence clean.

That residual is captured as a NEW wild fixture `testdata/wild/default-disj-in-interpolation/`
(the next slice's red seed), QUARANTINED via a `.known-red` marker so the green gate holds until
its fix lands. `check_wild_fixtures` skips (and reports) a `.known-red` dir.

### Verification

`lake build` clean (0 warnings/`sorry`/axiom; all pre-existing `native_decide` pins still pass —
this is an eval-core change). `scripts/check-fixtures.sh` exit 0 (self-hidden green;
default-disj quarantined). `shellcheck scripts/check-fixtures.sh` clean. No network, no
out-of-tree writes (prod9 + cue cache read-only).

---

## Audit Slice: Phase-A eval-batch audit (`f40dd9c..4b24902` = B3d-7 auth + eval-L1/L2) — HEALTHY, closed

Recovery entry, retroactively written 2026-07-02 — landed as `4b64502` (2026-06-29) with
no log entry at the time; the full findings block lives in `plan.md`'s "Phase-A audit
(2026-06-29 … HEALTHY, closed)" note.

Re-traced all three slices against philosophy + CUE spec. **No Violations.**

- **Secret hygiene (highest priority): no leak path.** Auth secrets in curl argv +
  in-memory only; `TokenCache` is an `IO.Ref`, never persisted; error paths report
  outcomes, not secrets. Offline tests synthetic; the live script asserts public digests
  only. Tree + all three commits grep clean for token/PAT/key shapes.
- **Auth correctness pinned:** challenge parse, token-field precedence, cred-source
  precedence, strict base64, anon fallback, unsatisfiable-401 → typed error.
- **Eval-L1:** `embeddingsReadEmbeddedSelf` precise — gate off ⇒ byte-identical for plain
  embeds; adversarial pins sufficient. Spec basis: embedding = unification.
- **Eval-L2:** reuses the shared `collapseDefaultDisjunction` (no behavior fork);
  ambiguous disjunctions stay incomplete.
- No new `partial`/`sorry`/axiom; `check_wild_fixtures`/`.known-red` quarantine ruled
  sound (both wild fixtures enforced). Borderline (non-blocking): stray untracked
  `repro-bottom.cue` debug scratch at repo root, flagged for a human to `rm`.

`lake build` + `check-fixtures.sh` + shellcheck green.

---

## Audit Slice: Phase-B on the eval batch — embed-Self re-fold extraction fix-slice filed

Recovery entry, retroactively written 2026-07-02 — landed as `d7a9ac3` (2026-06-29) with
no log entry at the time.

Phase-B architecture audit of `f40dd9c..4b24902`, whole-graph lens. **Verdict:
HEALTHY** — module graph acyclic; IO confined to OciFetch; OciAuth pure (IO→pure
direction correct); the L2 fix genuinely DRY (reuses `collapseDefaultDisjunction`). No
ModuleFetch carve warranted (OciFetch 290 / Module 674 lines, single responsibility
each).

Two findings FILED, docs-only (no eval-core touched — concurrency guard):
**B-AUDIT-refold-1** (HEADLINE, MED) — the L1 fix duplicated the embedding-Self re-fold
block verbatim-modulo-two-names across both struct-eval arms (`.structComp` + def-force),
a real drift hazard; a shared-helper extraction is designed and ranked lead of the
Borderline/LOW cleanups (eval-core → own slice + full regression, NOT inline). And a new
`kue-performance.md` row for the L1 embedding-value re-fold cost (~2x embedding fold on
embedding-heavy structs). The commit itself shipped no code change.

---

## Completed Slice: collapse let/ref-delivered list carriers in meet (prod9 eval-conformance layer 3)

Goal: fix the spurious `_|_` when a list-embedding carrier struct's list-embed body is delivered
through a `let`/reference rather than written inline. Captured wild fixture
`testdata/wild/let-list-meets-carrier/` (`f`/`e`/`f2` → `[1,2]`).

### Real mechanism (root-caused empirically, NOT the pre-slice diagnosis)

The pre-slice breadcrumb fingered the meet arms (`Lattice.lean` ~1247–1307 + `meetCore:519`) and
proposed widening the meet to recognize more carriers. That was a RED HERRING — a meet-layer fix
over-collapses a genuine conflict. The actual mechanism, confirmed by a `dbg_trace` at the meet
entry:

- Inline `{#name:"web",[1,2]}` and field-ref `ls:{#k,[...]}; [1,2]&ls` BOTH already worked. Only
  the `let` delivery (and only when BOTH the carrier and the resulting list reach a `.struct ×
  .embeddedList` meet) bottomed.
- A struct-body `let` becomes a `letBinding` FIELD on the enclosing struct. The embed body
  (`[1,2]&ls`) evaluates to an `.embeddedList`. The enclosing struct — now carrying ONLY the
  `letBinding` decl (no output field) — then meets that `.embeddedList`. Operand order is
  `.struct, .embeddedList`, which hits the meet arm `leftLike, .embeddedList`; `asListPair` fails
  on a struct, so it routes to `meetCore` → `.bottom` (`Lattice.lean:520`). This SHADOWS the
  `listLike, .struct fields _ none [] _` list-collapse arm (which only fires when the struct is on
  the RIGHT). Inline never reaches this because the embed is still a `.list` at collapse time, not
  an `.embeddedList`.

### Surgical fix

`Kue/Eval.lean`, `meetEmbeddingsWithFuel`'s embedding-collapse arm (the `_ =>` branch for a
non-closure/non-disj evaluated embedding, where `current` is a `.struct fields _ none [] _`): add
a LIST-embedding collapse mirroring the existing `{5}`→`5` scalar collapse. When the host has no
output field and the evaluated embedding is list-shaped (`asListPair`), build the `.embeddedList`
carrying the host's `declFields` (merged with the embed's own decls via `mergeStructFieldsWith`).
The fix lives in eval — NOT meet — because PROVENANCE is the soundness key: here `evaluated` is the
host's OWN embedding (collapse is sound), whereas at meet time `{#a,[1,2]} & {#b}` is a SEPARATE
foreign decls-struct conjunct that cue v0.16.1 rejects as a list-vs-struct conflict (two existing
pins `meet_embedded_list_with_decls_struct_bottoms` / `_decls_struct_with_embedded_list_` assert
this). A meet-layer fix could not distinguish the two (an empty `{}` ≈ a residual decl-struct at
meet time) — exactly the reasoning the `{5}`→`5` comment already records. `Lattice.lean` left
untouched.

### Tests

Wild fixture `testdata/wild/let-list-meets-carrier/` (auto-discovered by `check_wild_fixtures`)
red → green: `f`/`e`/`f2` → `[1,2]`. Adversarial cross-checks vs cue v0.16.1, all matching:

- decls stay selectable after collapse (`(carrier & let-list).#name` → `"web"`).
- genuine conflicts STILL bottom: `[1,2]&[3,4,5]` (length), `[1]&["x"]` (element), let-delivered
  length conflict `{#name,[1,2]}&[3,4,5]`, carrier & extra REGULAR field via let
  (`{#name,[1,2]} & {extra:1}` → cue list-vs-struct conflict).
- `{#a,[1,2]} & {#b}` foreign-decls-struct conflict UNCHANGED (the over-collapse guard).
- inline `ctrl`, plain struct meet, and a carrier-stays-struct meet (`{#name}&{#k}` → `{}`) all
  unaffected.

### prod9 re-sweep (read-only, cached deps, no network) — Layer 4 remains

`kue export` vs `cue export`, cue-missing lines (`grep -c '^>'`-equivalent):

| app          | before (L2) | after (L3) | status                                  |
| ------------ | ----------- | ---------- | --------------------------------------- |
| lem          | 188         | 187        | bottom — LAYER 4 (imported `#WebApp`)   |
| n8n          | 322         | 321        | bottom — LAYER 4 (same)                 |
| x9           | 449         | 448        | bottom — LAYER 4 (same)                 |
| typesense    | 223         | 222        | bottom — LAYER 4 (same)                 |
| cert-manager | 0           | 0          | 0-diff (no regression)                  |
| gateway      | 0           | 0          | both-bottom (bad input, unchanged)      |

The four apps STILL bottom — a distinct LAYER 4. Bisection: `packs.#WebApp & {…}` (the let-carrier
`let web = #WebApp & {…}; [...]`) bottoms even WITHOUT `parts.#UseKeel`. `#WebApp` is a `Self={…}`
def embedding `attr.#Metadata`/`attr.#Hosts` and emitting a top-level `[Self.#components.…]` list.
A self-contained local reduction of the `Self=`+nested-`#components`-list+embed-def shape now
exports CLEAN (the L3 fix covers it), so the L4 trigger is a subtler facet of the imported def
(candidate: `attr.#Metadata`/`attr.#Hosts` carrier embeddings, the `#replicas: int | *1` / `#env:
… | *{}` default disjunctions interacting with the list emit, or a cross-import frame detail). NOT
yet a self-contained wild fixture — module-free reductions flip polarity, so it needs dedicated
bisection from the real app graph (next slice). **Eval-conformance front is NOT closed.**

### Verification

`lake build` clean (0 warnings/`sorry`/axiom; all pre-existing `native_decide` pins still pass —
this is an eval-core change, so a broken pin would be a real regression; none).
`scripts/check-fixtures.sh` exit 0 (let-list-meets-carrier green; all prior fixtures unchanged).
No network, no out-of-tree writes (prod9 + cue cache read-only).

## Root A (SOUNDNESS over-accept): def closedness through embedded disjunction

`fix(eval): propagate definition closedness into embedded disjunction arms (was over-accept)`

### The bug (over-accept — kue admits what cue/spec reject)

A *definition* embedding a structural disjunction lost closedness through the arms:

```cue
#M: {{a: int} | {kind: string}}
out: #M & {kind: "k"}
```

- **cue v0.16.1 / spec:** `{"out":{"kind":"k"}}`. `#M` is closed; closedness distributes into
  the embedded disjunction's arms; the `{a:int}` arm closes → `& {kind:"k"}` adds a disallowed
  field → that arm is `_|_`; only `{kind:string}` survives → concrete.
- **kue (before):** `"ambiguous value: multiple non-default disjuncts remain"` — BOTH arms
  survived because the `{a:int}` arm was OPEN and wrongly admitted `kind`. A soundness over-accept
  (worse direction than the L1–L4 over-rejections).

### The REAL mechanism (empirically pinned, not from the brief)

Three diagnoses were red herrings this run, so the site was pinned with `dbg_trace`, not assumed:

1. The NON-embedded form `#M: {a:int} | {kind:string}` is already CORRECT — its disj body is a
   `.disj` whose arms `normalizeDefinitionValueWithFuel` closes (the `.disj` arm recurses each
   alternative; a no-pattern struct arm → `mkStruct … defClosed`). The meet then distributes
   `& {kind:"k"}` per arm and the closed `{a:int}` arm bottoms.
2. The EMBEDDED form carries the disjunction as an *embedding* (a `comprehension` member of `#M`'s
   `.structComp` body), not as the body's `.disj` directly.
3. `normalizeDefinitionValueWithFuel`'s `.structComp` arm passed ALL `comprehensions` through
   UNTOUCHED (by design — a struct/ref embedding UNIONS labels into the def's allowed set and must
   NOT impose closedness, else it rejects the def's own siblings). But that also skipped a
   disjunction embedding, leaving its struct-literal arms at the parser default `regularOpen`.
   Trace at `meetEmbeddingsWithFuel`'s `.disj` branch (the `embed-disj-arm-closedness` site)
   confirmed both arms arrived `StructOpenness.regularOpen`, so the per-arm `closeEmbeddedOver`
   saw `armOpen=true` and left them open. cue closes a struct LITERAL written inside a def body
   regardless of whether it sits in a disjunction; kue's normalize did not.

### The fix (surgical, soundness-direction)

`Kue/Normalize.lean`, the def-body `.structComp` arm of `normalizeDefinitionValueWithFuel`: map the
embeddings, recursing the CLOSING normalizer into a `.disj` embedding (which closes each
struct-literal arm), leaving every other embedding untouched:

```lean
let normalizedComprehensions := comprehensions.map fun c =>
  match c with
  | .disj _ => normalizeDefinitionValueWithFuel fuel c
  | _ => c
```

`.disj` is matched directly (Normalize.lean predates `isEmbeddingValue`, which lives in Eval). A
non-disj embedding (a `.refId` to another def, a struct embed) is a no-op pass-through, so
referenced-def arms keep their OWN closedness — no over-close. The over-correction guard is
structural: only `normalizeDefinitionValueWithFuel` (the CLOSING walker, reached by def bodies
only) carries the fix; a NON-definition struct `M: {{a:int}|{kind:string}}` goes through the spine
`normalizeDefinitionsWithFuel` (line `.structComp` recurses comprehensions with the spine, openness
preserved), so its arms stay OPEN — the open control is UNCHANGED.

### Adversarial pins (all cross-checked vs cue v0.16.1)

- Fixture `#M & {kind:"k"}` → `{kind:"k"}` (closed arm dropped, concrete). ✓
- Open control `M:{{a:int}|{kind:string}}; M & {kind:"k"}` → both arms kept (kue "ambiguous",
  cue "incomplete") — UNCHANGED, the critical over-rejection guard. ✓
- `#N:{{a:int}|{b:int}}; #N & {a:1}` → `{a:1}` (allowed by the `{a:int}` arm, `{b:int}` closed
  rejects `a`) = cue. No over-close. ✓
- `#M & {zzz:1}` → bottom (ALL arms violated, empty disjunction) = cue. ✓
- `#X:{{n:int}|{s:string}}; #X & {s:"x"}` → `{s:"x"}` (closed `{n:int}` arm rejects `s`) = cue. ✓
- Plain closed unchanged: `#C:{x:int}; #C & {x:1,y:2}` → bottom; `#C & {x:1}` → `{x:1}`. ✓

### Verification

`lake build` clean (140/140, 0 warnings/`sorry`; only the standard `propext/Classical.choice/
Quot.sound` axioms; every `native_decide` pin passes — the closedness family is the key regression
surface, a broken pin would be a real soundness regression, none broke).
`scripts/check-fixtures.sh` exit 0 (root-A fixture green; L1/L2/L3 green; L4 stays `.known-red`
quarantined). cert-manager canary diff = 0 (closedness-heavy guard). prod9 re-sweep: lem/n8n/x9/
typesense still FULLY bottom (L4 unchanged — the apps emit nothing in both before/after; root A is
a prerequisite for L4, not the L4 fix). Diff is `Kue/Normalize.lean` only (+18/-4). No network, no
out-of-tree writes (prod9 + cue cache read-only).

## Completed Slice: `disj-arm-list-embed-dropped` (L4 — re-applied; root A unblocked it)

A struct embedding a disjunction with a list-shaped arm dropped that arm when the host is a
list-carrier → spurious bottom. Repro (the wild fixture):
`#Emit: {#name:string, [{x:#name}]}; #Mixin: {{[...]} | {kind:string}}; out: #Emit & #Mixin &
{#name:"web", [...]}` → cue `{"out":[{"x":"web"}]}`, kue was `bottom`.

**Root cause (re-derived against current source — the held fix's site moved under root A).** The
embedded-disjunction distribution arm — `meetEmbeddingsWithFuel`'s `.disj` branch
(`Kue/Eval.lean` ~3926) — met each disjunction arm against the host with the PLAIN `meet`. For a
list-shaped arm (`{[...]}` → an `.embeddedList`/list carrier) against a list-carrier host that is
still a decls-bearing struct, the plain `meet` sees struct-vs-list → `.bottom`; `normalizeDisj`
then prunes the (live) list arm, and with the struct arm `{kind:string}` genuinely bottoming
against the list host, the whole disjunction bottoms. The non-disj single-embedding path already
collapses this correctly (the `{5}`→`5` / list-carrier collapse in the `_` arm), and the bare-disj
conjunct path (`th`) works — only the WRAPPED embedded disjunction (`{(disj)}`, the `.disj`
distribution) lacked the collapse.

**Fix (`Kue/Eval.lean`, `.disj` distribution arm, ~line 3940).** When the plain `meet current
armOpened` bottoms AND the arm is list-shaped (`asListPair alternative.snd |>.isSome`), re-run the
arm through the single-embedding sub-fold `meetEmbeddingsWithFuel nextFuel env current [arm]` — the
exact path the `conjDisjArms?` branch (~3837) already uses — so the host's OWN list-collapse fires
and the list-carrier host keeps the arm. Gated two ways: (1) list-shaped arms only — the struct-arm
per-arm `closeEmbeddedOver` reclosing is untouched; (2) the disjunction is the host's OWN embedding
(this `embedding`), so the collapse is provenance-sound — a FOREIGN list-vs-struct conjunct
(`{#a,[1,2]} & {#b}`) never reaches this arm, it stays a `meetCore` conflict. `Kue/Lattice.lean`
untouched. The `mapM` (was `map`) threads the sub-fold's `EvalM`.

**Why this lands now.** A prior slice wrote this fix but HELD it (it surfaced a closedness
over-accept). Root A (`c451245` — definition closedness propagates into embedded disjunction arms)
fixed that over-accept, so the re-applied L4 lands soundly. **A+L4 pair complete.**

**Verify.** `lake build` clean (0 warnings/sorry; all `native_decide`/`#guard` pins pass).
`scripts/check-fixtures.sh` exit 0 — `disj-arm-list-embed-dropped` now GREEN and unquarantined
(`.known-red` removed); all other wild + export/cue suites green. Adversarial pins (cue-cross-
checked): `1&[2]`, `{x:1}&[2]`, `{#a,[1,2]}&{#b}` foreign → all bottom; all-arms-bottom disj →
bottom; root-A def-embed-disj closed-arm-violation → still bottoms (A NOT re-broken);
`{[1,2]}&{#b}` single-arm foreign → still bottoms (collapse scoped to disj arms). cert-manager
canary diff = 0 (byte-identical, `jq -S`, 11.5s). prod9 re-sweep (new binary, ~18s each):
lem/n8n/x9/typesense STILL fully bottom — UNCHANGED (the residual is L5: the imported `#WebApp`
`Self=`+error-arm embed carrier, beyond A+L4). The fix is gated to turn list-arm-disj bottoms into
non-bottoms only — it cannot make any bottom worse, and none of the four apps improved. Diff is
`Kue/Eval.lean` only. No network, no out-of-tree writes (prod9 + cue cache read-only); not pushed.

## Completed Slice: TEST-HEALTH retrofit + machine enforcement (fix-slice (a))

Goal: complete the TEST-HEALTH CONVENTION with a machine gate + repo-wide migration, so the
convention stops depending on per-agent memory. Prior state (2026-07-02 audit): only
`Bug2xTests`/`TwoPassTests` were fully compliant; `EvalTests`/`ParseTests` had tripwires but
kept block-comment headers; ~30 modules had neither, and no script checked any of it.

### What landed

1. **Block comments → `--` line comments (all 33 hand-authored modules).** Every `/-! … -/`
   section header and `/-- … -/` per-declaration docstring in `Kue/Tests/*.lean` converted to
   `--` line comments (multi-line blocks preserved, each line re-prefixed). A line comment
   self-terminates at EOL and structurally cannot swallow the next declaration — the root
   cause of the 2026-06-23 silently-dead-theorems incident. `FixturePorts.lean` (generated
   fixture data) is exempt.

2. **Coverage tripwires on every theorem-bearing module.** End-of-file
   `#check @<last-theorem-per-section>` blocks added, one anchor per `/-!`-delimited section
   (the last theorem in that section). A swallowed section makes its anchor an unknown
   identifier → `#check` fails to elaborate = hard build error. Nested-namespace modules
   (`Mvs`/`OciAuth`/`Oci`/`Registry`/`Sha256`/`Zip`) place the block inside the inner
   namespace so names resolve. Anonymous-`example`-only modules (`ModuleTests`) and
   theorem-free helpers/data (`EvalTestHelpers`, `FixturePorts`) carry none — no name can
   anchor `#check`; the gate exempts them.

3. **`scripts/check-test-health.sh` gate** (mirrors `check-fixtures.sh` idioms; shellcheck-
   clean). Three checks over `Kue/Tests/*.lean` (excluding generated `FixturePorts.lean`):
   no `^[[:space:]]*/-` block comments; a `#check @` tripwire present wherever a `^theorem `
   exists; per-module line count ≤ 1800. Negative-tested (injected block comment → exit 1).

4. **Wired into the verify sequence** everywhere `check-fixtures.sh` is invoked: `CLAUDE.md`,
   `docs/guides/slice-loop.md`, `docs/guides/lean4-guide.md`, `RELEASE.md`, `README.md`.
   `docs/reference/failure-modes.md` coverage-status note updated (retrofit landed).

### Verify

`lake build` clean (140 jobs, 0 warnings/sorry). `scripts/check-test-health.sh` → `test health
ok`. `scripts/check-fixtures.sh` → `fixture pairs ok` (all suites green). `shellcheck
scripts/check-fixtures.sh scripts/check-test-health.sh` clean. Docs-and-tests slice: no
`Kue/*` source (non-test) changed; not pushed.

---

## Completed Slice: Enumerate value-producing `| _ =>` catch-alls (audit fix-slice (b))

Goal: eliminate every value-producing `| _ =>` catch-all that matches on a `Value`, per the
standing rule (a new `Value` ctor must force a decision at each dispatch/rewrite site). A
prose ban rots; explicit enumeration turns "handle the new ctor" into a hard build error.

### Scope audit

Raw `| _ =>` counts (Eval ~85, Lattice 14, Builtin 13) are NOT all in-scope. A catch-all is
in-scope only if it BOTH matches on a `Value` AND its arm produces a `Value`. Classification:

- **Builtin.lean — 0 in-scope.** All 13 scrutinize `Prim` (`mathAbs`/`mathRound`) or
  `Option`/`List` (`listMin`/`listMax`/…) — a new `Value` ctor cannot reach them.
- **Lattice.lean — 0 in-scope.** `meetStringRegexPrim` matches `Prim`; `meetKindWithBound`
  matches `Kind`; `meetConjValueWith`/`addConstraintWith` match `List Value` shape (and
  produce `List Value`). None is a match ON a `Value` producing a `Value`.
- **Eval.lean — 13 in-scope**, all converted: `selectFromConcrete`, `selectEvaluatedField`,
  `selectEvaluatedIndex`, `selectEvaluatedListIndex`/`…ListTailIndex`/`…FieldIndex`,
  `withDeferredComprehensions`, `injectLetLocalNarrowings`, `injectEmbedSiblingNarrowings`,
  the embed-force `match evaluated` (`pure evaluated` identity), the
  `meetEmbeddingsWithFuel` scalar-embed fallback, its inner `match current`, and the
  `forceClosureWithConjunct` body dispatch.

Out-of-scope catch-alls left untouched: probe/`Bool`/`Option`/`Nat`/`List` returns, non-`Value`
scrutinees, and the comprehension-payload dispatch (`.payload`/`.deferred`, a non-`Value` type).
The four `other => other` identity sites from 2026-06-23 were already enumerated (not touched).

### Steps

1. Replaced each in-scope `| _ =>` with a `|`-joined explicit ctor enumeration mapping to the
   same RHS the catch-all had. `|`-join (not one-arm-per-ctor) keeps it DRY — a single shared
   RHS — while still forcing exhaustiveness: a new `Value` ctor is absent from the list ⇒
   compile error. Partially-covered ctors (e.g. `.struct fields _ none [] _`) get a general
   `.struct _ _ _ _ _` in the enumeration for their remaining shapes.
2. **Elaboration fix (hoist).** Enumerating the outer `match evaluated` arm that wrapped the
   large scalar-embed collapse block timed out `«tactic execution»` (200k heartbeats):
   enumerating a shared arm that contains recursive calls duplicates the `decreasing_by`
   obligation across every constructor. Hoisted that block into a `let scalarEmbeddingCollapse
   : EvalM Value := …` ahead of the match, so the enumerated arms return a bare identifier
   (no recursive call) and the recursion is elaborated once. Not a workaround — the proper
   factoring for an enumerated dispatch over a fuel-recursive fold.

### Verify

`lake build` clean (140 jobs, 0 warnings/sorry) — the build IS the exhaustiveness proof.
`scripts/check-fixtures.sh` → `fixture pairs ok`; `scripts/check-test-health.sh` → `test
health ok`; `shellcheck scripts/*.sh` clean. Pure refactor: zero behavior change (no fixture
or `native_decide` delta), so no ctor was silently mishandled under any catch-all; no new
tests warranted. Not pushed.

---

## Completed Slice: `for` over a concrete non-iterable = type error (audit fix-slice (d))

Goal: re-adjudicate Kue's zero-iteration on a non-iterable `for` source under the E#4
principle (a concrete operand outside a spec-mandated domain is a type error, not a benign
default). The CUE spec mandates `for` range over a list or struct; cue spec-correctly
hard-errors a scalar source (`cannot range over 5 (found int, want list or struct)`), so
Kue's `out: []` was the wrong side — a `cue-divergences.md` row FLAGGED it 2026-07-02.

### Adjudication

Ran `cue` v0.16.1 on the repros: `for x in 5`/`"s"`/`true` and the scalar carrier
`{#a:1,5}` all ERROR (`cannot range over …`); an abstract scalar type also errors
(`y: int; for x in y` → `cannot range over y (found int, want list or struct)`); only a
genuinely-open source holds (`y: _; for x in y` → cue keeps the residual `[for x in y {x}]`).
So the domain boundary is *decidability*, not concreteness: a value whose type can never
unify to a list/struct is out-of-domain NOW (error), even if not fully concrete; a value
that may still become a list/struct DEFERS. cue is spec-correct throughout — Kue was wrong.

### Change

- `Kue/Value.lean`: new `BottomReason.nonIterableSource (type : ConcreteTypeName)` (sibling to
  `nonBoolGuard`/`nonArithmeticOperand`/`nonStringLabel`).
- `Kue/Eval.lean`: replaced `comprehensionPairs : Value -> Option …` with a three-way total
  `classifyForSource : Value -> ForSourceClass` (`iterable pairs` / `concreteNonIterable ty` /
  `incomplete`), enumerated with no catch-all so a new `Value` ctor forces a decision (mirrors
  `classifyArithOperand`). Iterable: list/listTail/embeddedList/struct. concreteNonIterable
  (decidably non-list/struct): `.prim` (→ `.scalar kind`), `.embeddedScalar` (recurse onto the
  terminal scalar — a carrier manifests as its scalar), `.kind` (`Kind` holds only scalar kinds),
  `.stringRegex` (→ string), `.boundConstraint` (→ number). incomplete (may still become a
  list/struct → DEFER): `.top`, `.notPrim`, unresolved refs/selectors/disjunctions/conjunctions,
  residual comprehensions/builtins/interpolations, bottoms. The `.forIn` clause site: `.iterable`
  walks pairs, `.concreteNonIterable ty` → `.bottom (.bottomWith [.nonIterableSource ty])`,
  `.incomplete` → `.deferred` (same discipline as an incomplete `if` guard, D#1b).

### Behavior (before → after; cue-adjudicated)

- `out: [for x in 5 {x}]` (also `"s"`, `true`, carrier `{#a:1,5}`, abstract `y: int`):
  `out: []` → `out: [_|_]` (list bottom element). cue ERRORS all → Kue now conforms.
- `out: {for x in 5 {a: x}}`: `out: {}` → `out: _|_`. cue errors → conforms.
- `y: _; out: [for x in y {x}]`: unchanged HOLD, now via `.deferred` (was zero-iter) — residual
  `out: [for x in @0.0 {@1.0}]`. cue holds `[for x in y {x}]`; the `@depth.index` rendering is
  the pre-existing D#1b display-only family (value verdict identical), so NO new divergence row.

### Tests

`ComprehensionTests`: replaced the stale `listcomp_for_scalar_carrier_zero` pin with
`listcomp_for_scalar_{int,string,bool}_is_type_error`, `listcomp_for_scalar_carrier_is_type_error`,
`structcomp_for_scalar_int_is_type_error`, `listcomp_for_abstract_scalar_is_type_error`, and
`listcomp_for_top_source_defers` (pins the deferred residual, distinguishing defer from bottom).
Fixtures `testdata/cue/comprehensions/for_scalar_type_error`, `for_struct_scalar_type_error`,
`for_top_source_defers` (+ FixturePorts ports). `cue-divergences.md` zero-iter row REMOVED,
recorded under a new "Resolved" section.

### Verify

`lake build` clean (0 warnings/sorry). `scripts/check-fixtures.sh` → `fixture pairs ok`;
`scripts/check-test-health.sh` → `test health ok`; `shellcheck scripts/*.sh` clean. Not pushed.

## Completed Slice: `partial def` waivers + timeless-comment sweep (audit fix-slices (c)+(e))

Goal: close the last two LOW mechanical fix-slices from the 2026-07-02 design-record audit.
Both are cleanup — zero fixture/behavior delta expected and observed. Bundled because they
touch disjoint surfaces.

### (c) `Module.lean` partial-def cleanup

Enforces CLAUDE.md's rule "`partial def` outside `Parse.lean` requires a one-line waiver;
list recursion never qualifies — write it structurally." Four `partial def`s:

- `findModuleRoot` — waived: recurses up an unbounded parent chain, terminating at the
  filesystem-root fixpoint (`parent == start`), not on a structural measure.
- `loadPackage`, `parseAndBindFiles`, `collectBindings` — a genuine mutual-recursion cycle
  over the filesystem import graph, terminating only via the `visited` cycle-guard. Each
  carries that waiver.

The two functions the plan named "list-recursive" (`parseAndBindFiles` self-recurses over
`files`, `collectBindings` over `imports`) had their list self-recursion rewritten as total
structural `for` loops (Array accumulators, early `return` on error). No `partial` now exists
for a *list*. They keep `partial` only because they are in the mutual cycle with
`loadPackage` — `collectBindings` must call `loadPackage` (to load an imported package) and
`loadPackage` calls back through `parseAndBindFiles`, so the cycle is inherent and a callback
cannot break it. The plan's aspiration to make these two non-partial was therefore not
achievable; the waived-partial state is the honest outcome. Dropped the now-internal
`acc`/`bindingAcc` accumulator params; updated both call sites (`loadPackage`, `loadFileBound`).

### (e) Timeless-comment sweep

Rewrote the 7 audit-listed sites to describe present behavior (dropping "no longer" / "the
old X" / "before/after the fix"): `Builtin.lean:941`, `Normalize.lean:126`, `Regex.lean:651`,
`LatticeTests:708`, `RegexTests:6/183`, `Bug2xTests:545`. A grep sweep
(`no longer|the old|previously|used to|before/after the fix`) showed the audit list was
incomplete, so also fixed every clear code-history narration in non-test source:
`Yaml.lean:34`, `Parse.lean:334`, `Normalize.lean:15`,
`Eval.lean:977/1051/1354/3127/3864/3931/4070/4526`. Skipped genuinely-timeless phrasings the
grep also matched — "no longer `.optional`" (a meet *result*), "Used to <verb>" (purpose),
Sha256 "no longer fit" (block-boundary math). ~20 test-file history comments remain; filed as
fix-slice (e-followup) in the plan rather than expanding this slice's scope.

### Verify

`lake build` clean (140 jobs, 0 warnings/sorry — proves the `for`-loop rewrites are total).
`scripts/check-fixtures.sh` → `fixture pairs ok`; `scripts/check-test-health.sh` →
`test health ok`. No scripts touched (no shellcheck needed). Zero fixture delta. Not pushed.

---

## Completed Slice: Phase A code-quality audit — eval batch `4b64502..HEAD`

Audit-only slice (no production-code change), per the slice-loop guard-rail that audits get a
log entry even when they ship no code. Scope: the un-audited eval batch — the design-record
fix-slice batch (a–e: `97a6e2b`, `736d96b`, `4b8e6ac`, `4f126af`) plus the previously-flagged
soundness-grade eval batch (`4b64502..6c347b5`, root A closedness-thru-embedded-disj). 21
commits, ~46 non-doc files touched.

### Verified landed (binding guard-rail — audits confirm prior filings)

a–e all genuinely in the code, not merely marked DONE: (a) `scripts/check-test-health.sh`
enforces block-comment/tripwire/size across every `Kue/Tests/*.lean` via `find` — the
convention is script-enforced, so the migration is complete by construction; (b) the 13
in-scope value-producing `| _ =>` catch-alls are `|`-joined ctor enumerations (shared RHS, no
copy-paste — the correct DRY idiom; the scalar-embed collapse is hoisted to a thunk so no
enumerated arm carries a recursive call); (c) all 4 `Module.lean` `partial def` waivers are
HONEST (filesystem parent-chain + inherent mutual IO-import-graph cycle — no structural
measure available); (d) `classifyForSource` + the `nonIterableSource` `BottomReason` + the 3
new comprehension fixtures (each with a `FixturePorts` entry, spec-adjudicated expected); (e)
timeless-comment sweep confirmed on the non-test sites. (e-followup) test-file sweep correctly
captured in plan.md.

### Soundness-grade changes scrutinized

Root A (closedness-thru-embedded-disj, `Normalize.lean`): the closing normalizer recurses only
into `.disj` embeddings, struct-literal arms close, `.refId` arms pass through — no over-close;
sound. The for-non-iterable type-error change (d): the concrete/incomplete/iterable
classification is total (no catch-all); `Kind` holds only scalar kinds (no list/struct), so
`.kind → concreteNonIterable` is sound; incomplete operands correctly defer. ONE defect found
(PA-1): `classifyForSource` folds `.bottom`/`.bottomWith` into `.incomplete` on a false
"can't-happen" premise — an evaluated bottom source (`1 & 2`) defers instead of propagating,
retaining a dead disjunct where cue eliminates it (`[for x in (1&2){x}] | [5]` → kue
"ambiguous" vs cue `[5]`). Wild-caught during the audit → committed red seed
`testdata/wild/for-bottom-source-masked-as-incomplete/` (`.known-red`); fix-slice PA-1 filed.

### Verify

`lake build` exit 0. `scripts/check-fixtures.sh` → `fixture pairs ok` (the new red seed is
quarantined, gate skips it). `scripts/check-test-health.sh` → `test health ok`. `shellcheck
scripts/*.sh` clean. No production code touched; the only additions are the quarantined wild
fixture + the plan/log/breadcrumb updates. Not pushed.

---

## Completed Slice: Phase B architecture audit — whole module graph (2026-07-02)

Audit-only slice (no production-code change), per the guard-rail that audits get a log entry
even with no code change. The complementary pass to the same-batch Phase A (`6197dc3`):
Phase A was diff-scoped correctness (filed PA-1); Phase B is cross-cutting design over the
whole module graph.

### Module-graph health — clean

Every import edge in `architecture.md` § Durable whole-graph facts re-verified against the
actual `import` lines: acyclic DAG, no cycles, IO confined to `Module`+`OciFetch`,
`Eval`/`Resolve`/`Value` import zero B3d module, `Builtin` has no `Eval` edge, `EvalOps` no
back-edge into `Eval`. Code-health sweep pristine: zero `sorry`/`panic!`/`unreachable!`/
`.get!` in pure code, zero dead code, zero deprecated APIs (`dropRight`), no stray `partial
def` outside the waived `Parse`/`Module` carve-outs. The type-leverage DRY backlog is
already fully worked out in plan.md Resolved/ruled-out (walker/normalizer/inject/merge/
carrier families CLOSED; newtype candidates filed on B3d-6b). No inline cleanup warranted —
nothing to delete or de-stale.

### Findings filed (plan.md § Fix-slices from the 2026-07-02 Phase B audit)

- **PB-1 [MED, arch]:** `Eval.lean` reached **4609 lines** — past the standing
  `Eval.DefDeferral` carve trigger (~4500 with the tier intact). The trigger has FIRED;
  carve the def-deferral tier (~600 lines) into its own module, leaving the core-force
  `mutual` block (never split) in `Eval.lean`. Pure refactor, byte-identical bar, own slice.
- **PB-2 [MED-LOW, test-org]:** `TwoPassTests` (1763) and `EvalTests` (1743) are within
  ~40–60 lines of the 1800 test-health cap; the next eval-test-touching slice trips the gate
  and blocks forward motion. The periodic test-org pass is now DUE — split both proactively
  at natural seams (org-only, pin-counts conserved). `FixturePorts.lean` (3875) is exempt
  generated data.
- **PB-3 [LOW, doc]:** `Builtin → Json → Manifest` (and `Builtin → Yaml → Json`) makes
  `Builtin` (layer 5) transitively depend on `Manifest`/`Format` (layer 6) — legitimate
  (marshalling builtins are export operations), no cycle, but `architecture.md`'s numbered
  layers and the durable-graph edge list understate it. Add a clarifying sentence + the
  missing edges on a doc-touching slice.

Ranking with the existing backlog: PA-1 (HIGH soundness) → B-AUDIT-refold-1 (MED, active
eval-core drift hazard, already filed) → PB-1 → PB-2 → PB-3. Periodic passes: plan-hygiene
NOT due (distilled today); perf-guide CURRENT (recent batch correctness-only); test-org DUE
(PB-2). **Two-phase audit for this batch is now COMPLETE.**

### Verify

No production code touched; only plan.md + this log + the breadcrumb updated. The Phase A
verify (`lake build` exit 0, `check-fixtures.sh` ok, `check-test-health.sh` ok, `shellcheck`
clean) at `6197dc3` still holds — no code delta since. Not pushed.

## Completed Slice: PA-1 — bottom `for`-source masked as incomplete (2026-07-02)

Phase A fix-slice. `classifyForSource` folded `.bottom`/`.bottomWith` into the `.incomplete`
arm on a false premise ("bottoms never reach here"). The `.forIn` caller evaluates the
source and matches `classifyForSource` with no bottom short-circuit, so a source evaluating
to bottom (`1 & 2`) was DEFERRED (treated as an open comprehension) instead of PROPAGATED —
a soundness bug: in a disjunction the dead ⊥ arm survived (`⊥ | x = x` was not applied),
yielding "ambiguous value" where the arm should drop.

### Change

- `ForSourceClass` (`Kue/Eval.lean`) gained a `bottom (value : Value)` verdict, the 4th
  case — mirroring `GuardVerdict.bottom`.
- `classifyForSource` routes `.bottom => .bottom .bottom` and `.bottomWith reasons =>
  .bottom (.bottomWith reasons)` (was `.incomplete`). Iterable / concrete-non-iterable /
  genuinely-incomplete arms unchanged — only actual-bottom is the new propagation path.
- The `.forIn` caller (`expandClauseChain`) handles the new verdict with
  `.bottom bot => pure (.bottom bot)`, short-circuiting the comprehension. Exhaustive match,
  no catch-all (`lake build` proves it).

### cue agreement

cue and kue AGREE on all forms — no `cue-divergences.md` row.
- `out: [for x in (1 & 2) {x}] | [5]` → both `[5]` (⊥ arm eliminated).
- bare `out: [for x in (1 & 2) {x}]` / struct twin → both conflict-bottom.

### Tests

- Wild red seed `testdata/wild/for-bottom-source-masked-as-incomplete/` GRADUATED: green
  under `check_wild_fixtures`, `.known-red` removed (now gate-enforced).
- New fixtures (testdata pair + FixturePorts entry each):
  `comprehensions/for_bottom_source_list` (`[_|_]`), `for_bottom_source_struct` (`_|_`),
  `for_bottom_source_disjunction` (`[5]` — the value divergence). Defer case
  (`for_top_source_defers`) and concrete-non-iterable case (`for_scalar_type_error`,
  `for_struct_scalar_type_error`) already present, unregressed.

### Verify

`lake build` exit 0 (exhaustiveness + totality), `check-fixtures.sh` ok (graduated seed +
3 new fixtures green), `check-test-health.sh` ok. No scripts touched (shellcheck n/a).
Committed on `main`, not pushed.

---

## Completed Slice: B-AUDIT-refold-1 — dedup the embedding-`Self` re-fold

Goal: remove the near-duplicate embedding-`Self` re-fold block that appeared
verbatim-modulo-two-names in both struct-eval arms (`.structComp` and def-force). The block
had a history of drifting-then-reconverging across the two arms with no type-level catch;
extracting it into one shared helper makes a future one-arm fix impossible to apply asymmetrically.

Pure refactor — BYTE-IDENTICAL behavior bar (zero fixture/canary delta the success criterion).

### Change

- New helper `refoldEmbeddingsIfSelf` inside the core-force `mutual` block, placed just before
  `evalEmbeddingFieldsWithFuel` (it calls that member, so it must live in the mutual block):
  ```
  refoldEmbeddingsIfSelf
    (fuel : Nat) (canonical : List Field) (newEmbeddedFields : List Field)
    (embeddings : List Value) (env : Env) (merged : List Field)
    (nested : Env) (embeddingFieldsPass1 : List Field) (refoldEmbeds : Bool)
    : EvalM (Env × List Field)
  ```
  Returns `(nestedForEmbeds, embeddingFields)`: when `refoldEmbeds`, re-pushes a frame augmented
  with `newEmbeddedFields` and re-evaluates the embeddings against it; otherwise returns the
  Pass-1 `nested` + `embeddingFieldsPass1` unchanged. `termination_by (fuel, 3, embeddings.length + 1)`
  — strictly above `evalEmbeddingFieldsWithFuel`'s `(fuel, 3, embeddings.length)` (same fuel), below
  both callers.
- The gate RESULT (`refoldEmbeds`, from `embeddingsReadEmbeddedSelf`) is passed as a parameter,
  not recomputed — the two parallel gates (`needsEmbeddedSelfPass` for static fields,
  `embeddingsReadEmbeddedSelf` for embedding values) stay unmerged and each computed at its call site.
- Both arms now call the helper: `.structComp` in `evalValueCoreWithFuel` (with `fields`/`env`),
  def-force in `forceClosureWithConjunctCore` (with `canonical`/`capturedEnv`). Each threads the
  returned `nestedForEmbeds` into its `meetEmbeddingsWithFuel` `met`. Three duplicated statements
  per arm collapse to one call.

### Verify

`lake build` exit 0 (no warnings/sorry), `check-fixtures.sh` ok (full 1843-pin regression,
`fixture pairs ok`, zero delta), `check-test-health.sh` ok. cert-manager canary `jq -S` diff vs
`cue` = 0 (empty). No latent divergence surfaced (the two arms are genuinely behavior-identical
modulo the two parameterized names). No scripts touched (shellcheck n/a). Committed on `main`,
not pushed.

---

## Completed Slice: PB-1 — carve the evaluator into EvalBase → EvalDefer → Eval

Goal: `Eval.lean` had grown to 4636 lines, past the ~4500 DefDeferral-carve trigger. Carve
the def-deferral tier into its own module, leaving `Eval.lean` holding the unsplittable
core-force `mutual` block. Pure refactor, byte-identical bar.

### Finding: the tier is not independently separable

The def-deferral tier (the ~600-line `resolveEmbedDefBody?` / `bodyNeedsDefer` /
`conjDefClosure?` / `splitDisjConjunct` … family) depends on the base evaluation machinery
(field/frame/env helpers, folds, merge, selection, classification, `Frame`/`Env`/`EvalState`,
`pushFrame`, conj-flatten, embed-narrowing). That base machinery is ALSO used by the
core-force `mutual` block. So the layering is `base → tier → core-force`. Isolating the tier
alone into `EvalDefer` while the base stayed in `Eval` would cycle (`EvalDefer` needs the base
from `Eval`; `Eval`'s core force needs the tier from `EvalDefer`). The core force does NOT
depend on the tier in the reverse direction that would block the carve — verified the tier
never references any core-mutual member (it is defined before the mutual and could not
forward-reference it). Resolution: split the shared base into its own lower module, giving a
3-module chain rather than the 1-module carve the trigger originally sketched.

### Steps

1. `Kue/EvalBase.lean` (2451 lines) — the base layer: `findEvalField`/`nthField`/frame-slot
   helpers, `foldValueWithDepth`, the regex-error probes, `canonicalizeFields` + the
   `remapConj*` rebase mutual, the `select*` family, the `classify*` verdicts, interpolation,
   `valueTag`/`valueDigest`, the `Frame`/`Env`/`EvalKey`/`EvalState`/`EvalM` types + `pushFrame`,
   `flattenConjDefRef` and the `let`/embed narrowing-injection helpers. Imports the leaf
   modules only (`Builtin`, `Decimal`, `EvalOps`, `Lattice`, `Regex`, `Normalize`, `Std.Data.HashMap`).

2. `Kue/EvalDefer.lean` (692 lines) — the def-deferral tier: the `hasSelfRefAtDepth` self-ref
   analysis mutual plus the def-resolution/deferral family (`defBodyHasSiblingSelfRef`,
   `resolveEmbedDefBody?`, `embeddingClosesHost`, `bodyNeedsDefer`, `followAliasDefBody?`,
   `resolveSelectorDefBody?`, `conjBodyHasDeferringArm`, `importDefClosureBody?`,
   `refDefClosureBody?`, `conjDefClosure?`, `conjStructCompDefer?`, `refAliasDefClosure?`,
   `importSelectorDef?`, `refAliasSelectorDef?`, `conjDisjArms?`, `splitDisjConjunct`).
   `import Kue.EvalBase`; no back-edge.

3. `Kue/Eval.lean` (4636 → 1517 lines) — the clause-outcome types (`ClauseOutcome` +
   `ClauseExpansion`/`ListClauseExpansion`), the effectful merge-sort helpers (`mergeRunsM` …
   `sortValuesM`), the core-force `mutual` block (never split — `termination_by (fuel, tag,
   length)` can't cross a module boundary), and the `runEval`/`evalStructRefs*` entry wrappers.
   `import Kue.EvalDefer`.

4. Wired `import Kue.EvalBase` + `import Kue.EvalDefer` into `Kue.lean` ahead of `import Kue.Eval`.
   `lakefile.lean`'s `lean_lib Kue` globs transitively, so no lakefile change. Architecture
   doc §5 updated to the 3-file chain + edges.

All cuts are contiguous line-range moves (no scattered extraction), so behavior is
byte-identical by construction.

### Verify

`lake build` exit 0 (no warnings/sorry). `check-fixtures.sh` ok (full regression `fixture
pairs ok`, zero delta, wild fixtures green). `check-test-health.sh` ok. cert-manager canary
`jq -S` diff vs `cue` = 0 (empty). No scripts touched (shellcheck n/a). Committed on `main`,
not pushed.

---

## Completed Slice: PB-2 test-org split + PB-3 architecture.md edge note

Goal: land the last two 2026-07-02 Phase A/B audit fix-slices — proactively split the two
near-cap test modules (PB-2) and complete the architecture doc's transitive-edge record
(PB-3) — discharging the audit fix-slice batch in full.

### PB-2 — test-org split (org-only, pin-counts conserved, zero behavior change)

`scripts/check-test-health.sh` caps `Kue/Tests/*.lean` at 1800 lines; `TwoPassTests`
(1763) and `EvalTests` (1743) were within ~40–60 lines of tripping the gate and blocking
the next eval/two-pass-touching slice. Split both at their next contiguous natural seams:

- `Kue/Tests/TwoPassTests.lean` 1763 → **1516**. Carved the held-residual / MEET-RESID /
  RESID-MASK family (a HELD `.structComp` residual survives `meet`; dead residual
  disjunction arms masked/pruned without over-holding a real conflict) into
  **`Kue/Tests/ResidualTests.lean`** (21 theorems). Conservation: 137 = 116 + 21.
- `Kue/Tests/EvalTests.lean` 1743 → **1468**. Carved the struct-closedness /
  pattern-constraint / B2.2-pattern-path / B6-depth / SC-2 / SC-4 def-closing family into
  **`Kue/Tests/ClosednessTests.lean`** (28 theorems). Conservation: 214 = 186 + 28.
  All three of EvalTests's original `#check` tripwires anchored SC-4 theorems that moved
  with the carve, so EvalTests received fresh tripwires (arith operand deferral,
  comparison/unary, lazy sibling meet) to keep `check_tripwires` satisfied; the three SC-4
  anchors moved into ClosednessTests.

Both new modules mirror the TEST-HEALTH CONVENTION exactly (imports mirror `Bug2xTests`;
`--` line-comment section headers; per-section end-of-file `#check @<last-theorem>`
tripwires; single `namespace Kue`). Wired into the test aggregator `Kue/Tests.lean`
alphabetically (`ClosednessTests` after `CliTests`; `ResidualTests` after `RegistryTests`).
The DEFERRED `testdata/cue/{definitions,comprehensions}` sub-grouping (audit item 3) stayed
dropped — not trivial enough to ride this pass. `FixturePorts.lean` (3903) is generated-data
exempt and untouched.

### PB-3 — architecture.md transitive-edge note (doc, XS)

`Builtin → Json → Manifest → {Format, Lattice}` and `Builtin → Yaml → Json` mean `Builtin`
(numbered layer 5) transitively depends on `Manifest`/`Format` (layer 6); the numbered-layer
prose read as if layer 6 strictly follows layer 5. Added one clarifying sentence to §5 (the
Builtin paragraph): the marshalling builtins are a deliberate forward edge into the export
layer because `json.Marshal`/`yaml.Marshal` ARE export operations — legitimate layering, not
a cycle — and recorded the omitted durable edges `Json → Manifest`, `Yaml → Json`,
`Manifest → {Format, Lattice}`. (There is no standalone "Durable whole-graph facts" heading
in `architecture.md`; the DAG edge facts are stated inline per layer, so the omitted edges
landed at the origin of the understatement, §5.)

### Verification

`lake build` exit 0 (148 jobs, no warnings/sorry — proves every moved theorem still
compiles and every relocated `#check` tripwire resolves). `check-fixtures.sh` ok (`fixture
pairs ok`, zero delta — test-org touched no fixtures). `check-test-health.sh` ok — both
split sources under the cap with ~280–330 lines of headroom, both new modules compliant.
Theorem-count conservation confirmed via `git show HEAD:` counts (TwoPass 137, Eval 214)
against post-split sums. No scripts touched (shellcheck n/a); cert-manager canary not
required (no eval-core change). Committed on `main`, not pushed.

### Batch status

With PB-2 and PB-3 landed, the **entire 2026-07-02 Phase A/B audit fix-slice batch is
FULLY DISCHARGED** — PA-1, B-AUDIT-refold-1, PB-1, PB-2, PB-3 all DONE. No audit-filed
fix-slice remains open.

---

## Completed Slice: B2-A2 — pattern×tail cross-combo fixtures (test-gap fill)

Goal: promote the two struct pattern/tail cross-combinations that were pinned only by
`native_decide` into real testdata fixtures, so behavior is exercised through the full
`kue eval` CLI path (not just the in-Lean `meet` algebra).

### Gap

The two committed B2.5 definitions fixtures (`pattern_tail_unify`,
`multi_pattern_tail_unify`) both exercise only **patterns-LEFT × tail-RIGHT**
(`{[string]:int} & {a:5, ...}`). The reverse order (**tail-LEFT × patterns-RIGHT**) and the
**both-tails+patterns** case (each operand carrying a tail AND a pattern) were pinned only by
`LatticeTests` `native_decide` theorems (`mergeStructN_tail_pattern_unifies`,
`mergeStructN_tail_patterns_unifies`, and — for two-tail merge — only without patterns via
`mergeStructN_tail_tail_applies_both_tails_to_extras`). No fixture drove them through
`kue eval`.

### Fixtures added

- `testdata/cue/definitions/tail_pattern_unify.{cue,expected}` — `{a:5, ...} & {[string]:int}`
  ⟹ `{a: 5, [string]: int, ...}`. Reverse of `pattern_tail_unify`; `meet` is commutative here.
- `testdata/cue/definitions/both_tails_pattern_unify.{cue,expected}` —
  `{a:5, [=~"^a"]:int, ...} & {b:"hi", [=~"^b"]:string, ...}` ⟹
  `{a: 5, b: "hi", [=~"^a"]: int, [=~"^b"]: string, ...}`. Each pattern constrains its own
  matching field; both tails keep the struct open.

Both carry matching `FixturePorts.lean` entries (binding rule: every fixture has BOTH a
testdata pair AND a port), so each `.expected` is triangulated by the in-Lean `meet` port,
the `kue eval` CLI, and `cue`.

### Spec adjudication

Oracle `{a:5,...} & {[string]:int}` → `{a:5}` (open). cue v0.16.1 agrees on both cases:
reverse → `{a: 5}` open; both-tails+patterns → `{a: 5, b: "hi"}` open. Lean `meet` port and
`kue eval` produce the same rendered structural form. **No latent bug surfaced** — the
`native_decide` theorems had encoded the behavior correctly; this slice only widened the
observation surface. No `cue-divergences` / `cue-spec-gaps` entry needed.

### Verification

`lake build` exit 0 (148 jobs, no warnings/sorry). `check-fixtures.sh` exit 0 (`fixture
pairs ok`; both new fixtures GREEN through the Lean-port diff and the CLI diff).
`check-test-health.sh` exit 0. No scripts touched (shellcheck n/a); cert-manager canary not
required (pure coverage, no eval-core change). Committed on `main`, not pushed.

---

## Completed Slice: Protocol amendments A1–A8 (keep-going critique) — consolidated batch

Goal: apply the eight ratified process amendments from the 2026-07-02 full-repo audit
critique ([`../notes/2026-07-02-keep-going-protocol-critique.md`](../notes/2026-07-02-keep-going-protocol-critique.md)).
Diagnosis behind them: every script-enforced invariant held; every prose-only/remembered
one drifted. Recorded as ONE batch entry (governance, spanning three commits) rather than
per-amendment, since five amendments are a single coherent doc-edit.

### What each amendment changed

- **A1 — fifth per-slice duty: retraction.** A slice that reopens/supersedes a prior claim
  greps the docs for that claim and annotates every stale site IN THE SAME SLICE. Merged the
  mechanic into the existing CLAUDE.md § "Recurring misalignments" retraction-pointer guard
  (one rule, not two), promoted it to an enumerated fifth per-slice duty in CLAUDE.md
  § "Continuous slice loop" and in `docs/guides/slice-loop.md` § "Slice (per subagent)". No
  duplicated wording — both loop sites reference the CLAUDE.md guard.
- **A2 — strict-xfail quarantine (CODE, `a4e7390`).** `check_wild_fixtures` in
  `scripts/check-fixtures.sh` now HARD-FAILS when a `.known-red` fixture unexpectedly passes
  (`known-red <slug> now passes — remove .known-red to enforce it`), so an en-passant fix
  can't leave a stale quarantine.
- **A3a — single verify entrypoint (CODE, `a4e7390`).** `scripts/check.sh`: `lake build` +
  every `scripts/check-*.sh` by glob + `shellcheck scripts/*.sh`, collecting all failures.
  Doc half (this batch): collapsed every multi-command verify-gate enumeration to
  `./scripts/check.sh` across CLAUDE.md, `docs/guides/slice-loop.md`,
  `docs/guides/lean4-guide.md`, `RELEASE.md`, and the breadcrumb Standing-context gate line.
- **A3b — portable sanitized canary (CODE, `ca4a322`).** `testdata/realworld/cert-manager/`
  (self-contained, sanitized) + `scripts/check-realworld.sh`, auto-globbed by `check.sh` so
  the real-app canary runs IN-GATE. Doc half: reframed the LIVE-infra prod9 canary as an
  OPTIONAL attended spot-check, explicitly NOT part of `check.sh` (external repo, non-portable).
- **A4 — audits open by auditing the last audit.** Made "diff the previous audit's filed
  fix-slices against landed commits; re-rank or explicitly drop each" the literal FIRST step
  of the Phase A procedure in `docs/guides/slice-loop.md` (formalizes the existing CLAUDE.md
  guard; cross-referenced, not duplicated).
- **A5 — single home for open decisions.** OPEN DECISIONS live only in the breadcrumb "Open"
  block; the plan POINTS, never holds a second copy. Precedence: what's-NEXT → breadcrumb
  wins; what's-TRUE → plan wins. Added the rule to `docs/guides/slice-loop.md` and stamped a
  one-line precedence banner in the headers of both the plan and the current breadcrumb.
- **A6 — blind-grind circuit breaker.** After ~3 consecutive fix-slices with ZERO movement
  in a campaign's declared target metric, a MANDATORY reassessment checkpoint fires (re-scope
  / bisect / escalate, OR record a justification to continue) — a forced stop-and-think, not
  an auto-halt. New section in `docs/guides/slice-loop.md`, referenced from CLAUDE.md § loop
  step 6. Attended → escalate; AFK → log to `.afk.log`.
- **A7 — rotate infrastructure into the audit.** Every ~3rd audit cycle, Phase B explicitly
  targets the GATES/TOOLING (`check-*.sh`, `check.sh`, fixture discovery, release tooling),
  not just the module graph. Added to Phase B in `docs/guides/slice-loop.md`.
- **A8 — mechanize git bans (CODE, swept into `a4e7390`).** `ask` rules in repo
  `.claude/settings.json` for `Bash(git checkout:*)` / `Bash(git restore:*)` /
  `Bash(git reset --hard:*)` + a `.gitignore` change to track that file.

### Commits

- `a4e7390` — A3a (`check.sh`) + A2 (strict-xfail quarantine); A8's staged
  `.claude/settings.json` + `.gitignore` were SWEPT IN here (see anomaly below).
- `ca4a322` — A3b (sanitized cert-manager fixture + `check-realworld.sh`).
- The governance doc-edit commit that lands this entry (A1/A4/A5/A6/A7 + the A3a/A3b doc
  halves + this batch record + the failure-mode + the critique-note APPLIED stamp).

### Anomaly (recorded, deliberately NOT rewritten per AFK envelope)

`a4e7390` conflates A2, A3a, and A8: two parallel subagents each `git add`+`commit` against
the shared index, and A8's already-staged files were swept into the tooling agent's commit
before it committed. Content is correct; attribution is muddled (A8 appears under a
"check.sh aggregator" subject). No history rewrite (envelope: no working-tree destruction /
force-push). Captured as a reusable guard in
[`failure-modes.md`](failure-modes.md) § "Parallel commit-bearing subagents collide on one
shared index" (candidate school-level lesson).

### Verification

Docs-only batch (no code change here; the code halves landed in `a4e7390`/`ca4a322`).
`./scripts/check.sh` green — docs don't affect the build, so this confirms no script was
broken. Committed on `main`, NOT pushed (AFK envelope).

---

## Completed Slice: L5 slice 1 — graduate root2/root3; `Lattice.lean:1224` closedness pin was a red herring (2026-07-03)

Goal: fix the two quarantined closedness seeds (`def-disj-closedness-extra-field` /
`single-closed-embed-extra-field`) whose `.afk.log` root cause pinned closedness LOST
through the disjunction distribution and the embed-close path at `Kue/Lattice.lean:1224`.

### Finding (verify-then-fix: the pin was WRONG)

No `Lattice.lean` change was needed. Closedness IS already preserved through both paths.
Verified against `cue` v0.16.1:

- `(#A | #B) & {p:1,r:9}` (def-reference disjunction) → bottom; `#M & {p:1,r:9}` with a
  hidden `#M: #A | #B` → bottom.
- `{#A} & {p:1,r:9}` (embed) → bottom; hidden-def form → bottom.
- `close({p:int}) | close({q:int})` through a disjunction, met with an extra field → bottom.
- Positive (no over-rejection): `(#A|#B) & {p:1}` → `{p:1}`; `{#A} & {p:1}` → `{p:1}`.
- Open arm still accepts extras: `#A | #B` with `#B: {q:int, ...}` (open), met with
  `{q:2, r:9}` → `{q:2, r:9}` (only CLOSED arms reject).

The seeds' RED was a MEASUREMENT ARTIFACT. Each bound its carrier as a *regular exported*
field — `M: #A | #B` (= `{p:int}|{q:int}`, genuinely ambiguous) / `M: {#A}` (= `{p:int}`,
`int` not concrete). That carrier's OWN inherent incompleteness/ambiguity surfaced at
export BEFORE `out`'s (correct) bottom; `cue` errors on the carrier identically
(`M: incomplete value {p:int} | {q:int}` / `M.p: incomplete value int`). So the observed
"ambiguous value" / "incomplete value: int" came from `M`, not from `out` losing closedness.
The disj/embed closedness machinery was already sound via the intervening
`def-closedness-thru-embedded-disj`, bug26/bug27, and bug210 fixes.

### Steps

1. Corrected both seeds to a HIDDEN carrier def (`M` → `#M`) so `out` is the observed
   export result. Both now render `conflicting values (bottom)`, matching `.expected.err`.
2. Removed both `.known-red` markers (`git rm`); the strict-xfail wild gate now enforces them.
3. Annotated each seed's `PROVENANCE.md` with a RETRACTION of the wrong `1224` root-cause claim.
4. Added 3 regular-tree pins under `testdata/cue/definitions/` + `FixturePorts` entries:
   `disj_def_refs_closed_reject_extra` (empty-disjunction bottom),
   `disj_def_refs_closed_accept_in_schema` (positive, no over-reject),
   `embed_closed_def_accept_in_schema` (positive embed). The embed-NEGATIVE case was already
   pinned by `bug210_embed_meet_extra_rejected` (`{#Meta} & {b}` rejects `b`).

### Status of siblings

`webapp-carrier-l5` stays `.known-red` — a DISTINCT root (a `Self`-ref host embedding an
`error()`/`⊥`-arm disjunction, `Eval.lean` splice), NOT closedness. Next L5 target.
**RETRACTED by L5 slice 2 (below):** this attribution was WRONG on both counts — the
`error()`/disjunction framing was a red herring, and the seed IS closedness-family; the
real root was `evaluatedStructOperand?` in `EvalBase.lean` (NOT `Eval.lean`). Now GREEN.

### Verification

`./scripts/check.sh` green (both seeds graduated, ~1843-pin set intact, test-health +
shellcheck clean). Live cert-manager canary (`kue` vs `cue` jq-S export) delta EMPTY. No
`cue` divergence and no spec gap (all cases match `cue` v0.16.1). Committed on `main`, NOT
pushed (AFK envelope).

---

## Completed Slice: L5 slice 2 — graduate webapp-carrier-l5; open-tail operand mis-closed the host (2026-07-03)

Goal: fix `webapp-carrier-l5`, the last RED L5 seed. It over-rejected (`bottom`, exit 1)
where spec + `cue` v0.16.1 export `{out:{kind:"StatefulSet",spec:{foo:"x"}}}`.

### Finding (the prior `Eval.lean` splice / `error()`-arm diagnosis was a RED HERRING)

Bisecting the seed to its minimal trigger refuted the earlier framing entirely — no
disjunction and no `error()` are needed to reproduce. Minimal trigger: a struct with a
sibling FIELD-REFERENCE, unified via `&` with a struct carrying an ELLIPSIS-ONLY (OPEN)
embed:

```
#Ctl: { name: "x", spec: name, ... }
out: #Ctl & { {...} }
```

kue bottomed; spec + `cue` export `{out:{name:"x",spec:"x"}}`. Dropping the sibling ref,
the embed, or making the embed NON-empty (`{extra:1}`) each makes it green — so the trigger
is precisely `<sibling-ref def> & <ellipsis-only-open embed>`.

Root cause: `evaluatedStructOperand?` (`Kue/EvalBase.lean:2399`) special-cased a
`.defOpenViaTail` struct (an explicit-`...`, i.e. OPEN, use operand) to closedness `false`.
In the conj force-splice fold, that spuriously-closed operand closed the OPEN host to the
operand's own (empty) label set, so the host's sibling-referencing field evaluated to
`bottomWith (fieldNotAllowed "spec")`.

### Fix

Drop the special case; the general arm now handles it:

```
| .struct fields openness _ _ _ => some (fields, openness.isOpen)
```

An open-tail operand contributes `true` (open). `applyClosednessFrom` is a no-op when open,
so an open operand imposes no closedness; a genuinely-closed sibling still restricts via its
own `false` — closedness ANDs, so `#Closed & {...}` STAYS closed (no under-rejection). The
helper returns `Option (List Field × Bool)` (a probe, not a `Value`), so its `| _ => none`
is not a Value-producing catch-all.

### Steps

1. Removed the `.defOpenViaTail → (fields, false)` special case in `evaluatedStructOperand?`;
   updated the doc comment to the open-operand rationale.
2. Removed `testdata/wild/webapp-carrier-l5/.known-red` (already committed in `b5425fb`);
   the strict-xfail wild gate now enforces the seed GREEN.
3. Added 3 regular-tree fixtures under `testdata/cue/definitions/` + `FixturePorts` entries:
   `open_tail_embed_sibling_ref_resolves` (the minimal trigger), `open_tail_embed_hidden_backref_resolves`
   (the seed's own hidden `Self.#name` back-ref shape), and the SOUNDNESS GUARD
   `open_tail_operand_no_reopen_closed` (`#C:{p:int}` closed, `#C & {q:2,...}` → `q` still
   REJECTED — the open operand must not reopen a closed def).
4. Finalized `webapp-carrier-l5/PROVENANCE.md` from PROVISIONAL to spec-adjudicated; annotated
   the prior L5-slice-1 log/plan/breadcrumb claims that mis-attributed this root.

### Verification

`./scripts/check.sh` green: full build via the capped `./lake`, all fixtures + wild
(webapp-carrier-l5 enforced GREEN), the 3 new fixtures green, realworld + test-health +
shellcheck clean. `webapp-carrier-l5` seed exports `{out:{kind:"StatefulSet",spec:{foo:"x"}}}`,
matching `.expected`. Live cert-manager canary (`kue` vs `cue` jq-S export) delta EMPTY. No
`cue` divergence, no spec gap (all cases match `cue` v0.16.1). **L5 seed-metric COMPLETE:
all three seeds (root2, root3, webapp-carrier-l5) GREEN + gate-enforced.** Committed on
`main`, NOT pushed (AFK envelope).

## 2026-07-03 — Toolchain upgrade v4.29.1 → v4.31.0

Bumped `lean-toolchain` from `leanprover/lean4:v4.29.1` to `v4.31.0` (latest; no external
Lake deps to update). Migration was near-zero: the only source fixup was
`set_option maxHeartbeats 4000000 in` on `fixturePorts` (the large fixture list exceeds
v4.31's default elaboration heartbeat budget — a compile-time setting, no semantic change).

### Verification

`./scripts/check.sh` GREEN on v4.31.0 (full build via capped `./lake`, all fixtures + wild
+ realworld + test-health + shellcheck). Live cert-manager canary (`kue` vs `cue` jq-S)
delta EMPTY — behaviour byte-identical across the bump, so all `native_decide` theorems
still hold and eval semantics are unchanged. Committed on `main`, NOT pushed (AFK envelope).
