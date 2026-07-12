# Kue Architecture

Status: implemented — living document.

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
`*Tests.lean`, so `lake build` exercises the suite at elaboration time). `Main.lean` is
the `kue` executable.

### 1. Surface syntax — `Parse.lean`

A narrow recursive-descent parser over the subset already backed by semantic values. It
keeps package clauses, fields, pattern fields, embeddings, lists, refs, defaults, bounds,
`let`, aliases, selectors, indices, numeric literal spellings, and the expression grammar
visible. Unsupported source forms fail with a parse error rather than being approximated.
Boundaries are tracked in [`compat-assumptions.md`](compat-assumptions.md).

### 2. Binding and resolution — `Resolve.lean`

Converts syntax-level label references into binding identities (`refId`) against a field
environment, including nested-struct local scopes. The evaluator consumes resolved
references instead of repeatedly searching strings in nested maps.

### 3. Semantic values — `Value.lean`

The core domain: top, bottom with structural provenance (`BottomReason`), primitives (int,
float, number, string, bytes, bool, null), kinds, integer bounds, primitive exclusions,
structs with field classes, lists and list tails, struct patterns, disjunctions with
default markers, references, selectors/indices, builtin calls, and unary/binary expression
nodes. Closedness is carried as `closedClauses : List ClosedClause` (one
`{fieldLabels, patterns}` per closed conjunct); the `closedClauses = [] ↔ open` invariant
is enforced at the single `mkStruct` construction choke point, so the admittance check is
the per-conjunct INTERSECTION (a field survives iff every clause admits it), not a flat
union. `Value.lean` imports only `Kue.Regex` (a true leaf).

### 4. Order and lattice — `Order.lean`, `Lattice.lean`, `Normalize.lean`

`Order.lean` defines subsumption (`subsumes`, a deliberate test-only oracle).
`Lattice.lean` implements total `meet` /`join` with fuel-bounded recursion through
compound values and the normalization the laws need (flatten disjunctions, drop bottom
alternatives, numeric-kind hierarchy); it owns the closedness admittance logic
(`fieldAllowedByClausesWith` and the per-conjunct clause conjunction) and the single-sourced
duplicate-field collapse DECISION (`mergeFieldClass` + `mergeFieldLayoutInto`, the keep-or-append
fold both the evaluator frame (`EvalBase.canonicalizeFields`) and the resolver layout
(`Resolve.canonicalFieldLayout`) share so they cannot drift). `Normalize.lean`
carries definition-implied closedness normalization (a leaf, `import Kue.Value` only).
`containsBottom` (the disjunction-prune predicate) is TOTAL/structural — no fuel cap — so
a bottom at any depth is found, including through a `.structComp` residual's resolved
fields. Target laws: commutativity, associativity, idempotence, top/bottom identities, and
distribution of meet over finite disjunctions.

### 5. Evaluation — `EvalBase.lean`, `EvalDefer.lean`, `Eval.lean`, `EvalOps.lean`, `Builtin.lean`

The evaluator is split into three files along a strict import chain `EvalBase →
EvalDefer → Eval` (each imports the one before it; no back-edge). `EvalBase.lean` holds
the base machinery every evaluation step builds on: field/frame/env helpers, the
depth-threading value folds, merge/canonicalize (the `remapConj*` rebase mutual), the
`select*` selection family, the `classify*` verdict helpers, interpolation, the value
digest, the `Frame`/`Env`/`EvalState`/`EvalM` types + `pushFrame`, and the conj-flatten
and embed-narrowing helpers. `EvalDefer.lean` holds the **def-deferral tier**: the
self-reference analysis mutual (`hasSelfRefAtDepth`) and the def-resolution/deferral
family (`resolveEmbedDefBody?`, `bodyNeedsDefer`, `conjBodyHasDeferringArm`,
`importDefClosureBody?`, `refDefClosureBody?`, `conjDefClosure?`, `conjStructCompDefer?`,
`followAliasDefBody?`, `resolveSelectorDefBody?`, `conjDisjArms?`, `splitDisjConjunct`,
…) — the logic that decides whether and how a definition's body is deferred during force.
The tier is not independently separable: it sits atop the `EvalBase` machinery that the
core force also uses, so isolating the tier alone would cycle; `EvalBase` is the
lower layer that breaks that cycle. `Eval.lean` holds the clause-outcome types, the
effectful merge-sort helpers, the **core-force `mutual` block** (never split — its
`termination_by (fuel, tag, length)` ordering can't cross a module boundary), and the
`runEval`/`evalStructRefs*` entry wrappers.

`Eval.lean` resolves references, applies constraints, distributes meets, evaluates
expressions, and handles reference cycles explicitly with a visited-binding path and
bounded fuel (host-language recursion failure is not acceptable cycle semantics),
including structural-cycle detection (a def/regular self-ref through a struct layer
bottoms with `.structuralCycle`; a `#List | *null` recursion terminates on the default
arm). It does not require export-level concreteness — `int`, `string | int`, `>0 & <10`
are valid results. `EvalOps.lean` carries the pure scalar/expression
algebra (arithmetic/comparison/boolean/unary operand classification and evaluation,
default-disjunction collapse) carved out from under the recursive evaluator — `EvalOps →
{Builtin, Decimal, Regex}`, with no back-edge into `Eval`. `Builtin.lean` holds the pure
builtin helpers (`close`, `len`, `and`, `or`, `div`, `mod`, `quo`, `rem`, the `strings`
/`list`/`math`/`struct`/`strconv`/`path`/`time`/`net`/`text/template` namespaces, `math.Pow` 's
exact domain, Unicode case mapping via `CaseTable.lean`; the pure per-package algorithms live in
their own leaf modules — `Strconv.lean`, `Path.lean`, `Time.lean`, `Net.lean`, `TextTemplate.lean`,
each `→ Value` only with no cross-edges among them, dispatched from `Builtin` via a `BuiltinFamily`
arm; the `stringFormat` string-validators join `Time` + `Net` in a dedicated `StringFormat.lean`
leaf — `StringFormat → {Time, Net}`, imported by `Lattice`/`Order` — so `Time` and `Net` stay
independent siblings with no edge between them); `Eval` dispatches resolved builtin calls and preserves incomplete ones
as semantic values. Effectful builtins whose comparator needs `EvalM`
(`list.Sort`/`SortStable`) are intercepted in `Eval` rather than `Builtin` (which must
stay pure — there is no `Builtin → Eval` back-edge). The marshalling builtins are a
deliberate forward edge into the export layer: `Builtin → Json → Manifest → {Format,
Lattice}` and `Builtin → Yaml → Json` mean `Builtin` (layer 5) transitively depends on
`Manifest`/`Format` (layer 6) — because `json.Marshal`/`yaml.Marshal` ARE export
operations, so a marshalling builtin genuinely needs the export phase; this is legitimate
layering, not a cycle. Durable whole-graph edges from this: `Json → Manifest`, `Yaml →
Json`, `Manifest → {Format, Lattice}`.

### 6. Manifestation and formatting — `Manifest.lean`, `Format.lean`

`Manifest.lean` is the export phase: it selects defaults (recursively), filters hidden/
definition/optional/`let` fields, and rejects unresolved or ambiguous values via an
explicit `ManifestError`, kept separate from evaluation to preserve CUE's `eval` vs
`export` distinction. `Format.lean` renders values in stable CUE-like text.

### 7. Modules and registry fetch — `Module.lean` + the B3d island

`Module.lean` owns `cue.mod` discovery, multi-file package merge, in-module +
cross-module import resolution (vendored or extract-cache), fetch-on-missing for a
declared dep absent from both, and MVS version selection over a disk-built requirement graph
(`solveVersionOverride` — the selected version governs each cross-module import, threaded through
`ModuleContext.selected`). It is one of the two IO modules (the other is `OciFetch`);
`Eval`/`Resolve`/`Value` import none of this layer. The registry-fetch island under it is
a pure protocol core plus one thin IO edge: `Registry.lean` (`CUE_REGISTRY` parse,
module→OCI-ref resolution, cache-path authority), `Oci.lean` (manifest parse, URL/curl-arg
builders), `OciAuth.lean` (Docker/OCI bearer-token flow parsing), `Sha256.lean` (FIPS
180-4 + `cue.sum` `h1:` dirhash, exporting the `Hash1` digest newtype threaded through the
`cue.sum` produce/parse/format/verify chain), `Inflate.lean` (RFC 1951 DEFLATE), `Zip.lean` (PKWARE +
CRC-32), `Semver.lean` (Go `x/mod/semver` port), `Mvs.lean` (pure
minimal-version-selection solver), `OciFetch.lean` (the sole `IO.Process` curl edge;
imports the pure core,
never the evaluator), and `ModCmd.lean` (the `kue mod tidy` command layer — transitive
requirement-graph fetch, MVS via `Mvs.solveChecked`, and `cue.sum` WRITE; carved out of
`Module.lean`). Import direction is strictly IO → pure: `Module → {Parse, Runtime,
Registry, Semver, Mvs, OciFetch, Zip, Sha256}`, `OciFetch → {Oci, OciAuth, Base64, Sha256, Registry}`,
`ModCmd → {Module, Mvs, Semver, Sha256, Zip}`.

### 8. Runtime, CLI, and harness — `Runtime.lean`, `Cli.lean`, `FixturePorts.lean`

`Runtime.lean` centralizes the resolve → evaluate → format flow shared by the CLI and
fixtures, including multi-source merging with package-name consistency. `Cli.lean`
(imports `Runtime`) parses the `kue` command surface (`eval`, `export`, `version`, help);
`Main.lean` is the executable entry. The compatibility
corpus lives in `testdata/cue/` as paired `.cue` / `.expected` files, grouped into
subsystem subdirs (`numeric/ structs/ definitions/ lists/ refs/ …`); `FixturePorts.lean`
records each expected output as a computed Kue value keyed by its `<subdir>/<stem>`
relative subpath, and `scripts/check-fixtures.sh` discovers pairs recursively, generates
ports, diffs them, compares `kue` CLI output, and runs `cue fmt --check`. `*Tests.lean`
modules carry theorem-style and executable checks.

## Where We Are / What's Next

The semantic core, evaluator, manifestation, CLI, builtins (exact-decimal numerics per
[`../decisions/2026-06-22-numeric-model-exact-decimal-no-float.md`](../decisions/2026-06-22-numeric-model-exact-decimal-no-float.md)
— Float/NaN deliberately avoided), imports/module resolution, and the OCI/registry fetch
(B3d, live-proven against `ghcr.io`) are implemented and oracle-checked against `cue`
v0.16.1 — see `plan.md` § Standing Capabilities. The **current front is
spec-conformance and robustness across the whole language + stdlib surface** — systematic
coverage of the spec and its edges, not any config corpus (§ Project goal, CLAUDE.md). See
`plan.md` § Current front. Remaining
tails: B3d-6b CORE + leg4 LANDED (`kue mod tidy` — requirement-graph fetch + MVS + `cue.sum` write, in
the new `Kue/ModCmd.lean`; import-resolution MVS wiring now landed too; one filed dependent: `mod get`) and the
item-6 LOW list, all ranked in [`plan.md`](plan.md); the full slice-by-slice history is in
[`implementation-log.md`](implementation-log.md);
not-yet-modeled corners (per-file import scoping, the exotic go-yaml surface) are tracked
in
[`compat-assumptions.md`](compat-assumptions.md).

## Tooling

Use `elan` to install Lean and Lake; the Lean version is pinned in `lean-toolchain` so
builds don't depend on a globally floating toolchain. `cue` is required by the fixture
checker.
