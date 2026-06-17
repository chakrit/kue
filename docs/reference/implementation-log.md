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
[`../notes/2026-06-17-test-reorg-landed.md`](../notes/2026-06-17-test-reorg-landed.md).

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
