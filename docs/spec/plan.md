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
- **Comprehensions** — `for k, v in expr` / `for v in expr` / `if cond` field clauses,
  desugaring into fields merged into the enclosing struct; the loop variable is one
  further lexical scope frame, expansion runs at eval time over lists and struct values.
- **Dynamic fields & interpolation** — `(expr): v` computed labels and `"\(expr)"`
  string interpolation. Dynamic fields ride the `structComp` scope machinery, resolving
  their label expr in the enclosing struct's frame and expanding to a concrete field at
  eval time once the label is a string; interpolated labels (`"\(k)": v`) are the common
  form. Interpolation coerces int/float/bool/null/string holes to their CUE spelling.
- **Struct embeddings** — a `{ … }` (or any value) embedded directly in a struct
  resolves its body against the *enclosing* struct's lexical frame and unifies (`meet`)
  into it. Plain embeddings ride the same `structComp` `comprehensions` bucket as
  comprehensions and dynamic fields; a struct embedding merges its fields (collisions
  meet), a non-struct embedding conflicts to bottom.
- **Manifestation** — structured export with default selection (incl. nested),
  field-class filtering, and incompleteness/ambiguity rejection.
- **Builtins** — top-level `close`, `len`, `and`, `or`, `div`, `mod`, `quo`, `rem`, plus
  the package-qualified `strings` family (`Contains`, `HasPrefix`, `HasSuffix`, `Index`,
  `Count`, `Split`, `Join`, `Replace`, `Repeat`, `TrimSpace`, `Fields`), the `list`
  family (`Concat`, `FlattenN`, `Repeat`, `Range`, `Slice`, `Take`, `Drop`, `Contains`,
  and full int+float-domain `Sum`/`Min`/`Max`/`Avg`/`Range`), and the `math` family
  (`Abs` domain-preserving int→int / float→float, `MultipleOf`, and float→int
  `Floor`/`Ceil`/`Round`/`Trunc` via exact-decimal truncation; `Round` is
  half-away-from-zero). Unresolved calls preserved as semantic values; concrete
  type-mismatch args resolve to bottom.
- **Parser/CLI** — recursive-descent parser over the supported subset; numeric literal
  spellings (non-decimal, separators, exponents, suffix multipliers); stdin and explicit
  multi-file evaluation with package-name consistency. Package-qualified builtin calls
  (`strings.X(...)`) parse via call-on-selector; `import` clauses (single and grouped)
  parse and are ignored since the package is implicit in the dotted builtin name.
- **Expressions** — unary/additive/multiplicative/division/integer-keyword arithmetic,
  equality, ordering, numeric comparison across int/float, logical `&&`/`||`/`!`, and
  binary regex match `=~`/`!~`. Float multiplication and division are now evaluated
  exactly through `Kue/Decimal.lean`: mul preserves the summed scale verbatim
  (`1.5 * 2.0 = 3.00`); `/` always yields a float and renders non-terminating quotients
  at 34 significant digits (apd context) with round-half-up. All operand domains
  (int/int, int/float, float/int, float/float) share one divider; zero divisor bottoms
  with `divisionByZero`.

Known deliberate boundaries are tracked in [`compat-assumptions.md`](compat-assumptions.md).

## Audit Fix-Slices (float-numeric family, audit 2026-06-16)

Findings from the `/ace-audit` depth pass over `31a85ba`/`3626ea2`/`9f1d797`. Ordered by
severity; fold each into a slice.

- **[Violation] Totalize `divisionDigits` and `roundDigits` (`Kue/Decimal.lean`).** The
  prior audit's whole theme was converting `partial def`s to fuel-bounded total functions
  (`stringReplace`, `listFlattenN` → `evalFuel`/`resolveFuel` idiom). This batch introduced
  two new `partial def`s that cut against that grain with no rationale at the definition
  site. Both are totalizable:
  - `divisionDigits.loop` recurses on `remainder` (modular, not structurally decreasing)
    guarded by the fixed `sigEmitted > divisionSigDigits` budget. Add a `fuel : Nat`
    bound — sound ceiling is `divisionSigDigits + 1 + <den digit count>` (leading-zero
    positions before the first significant digit are bounded by operand magnitude; sig
    emission is hard-capped). Terminate on `fuel = 0 ∨ remainder = 0 ∨ over-budget`.
  - `roundDigits` has no self-recursion; only its inner `bump` recurses, and that is
    structural on the list. The `partial` marker looks gratuitous — try dropping it
    (lift `bump` to a structural `def` if Lean needs the nudge).
  - Re-run all division/avg theorems after; a fuel-bounded form may shift reduction, so
    confirm `native_decide` still closes. NOT an inline patch — proper slice with a sound
    fuel-bound argument. If `partial` is ever genuinely justified, document it at the site.
- **[Borderline] DRY the integer range-count formula.** `listRange` (`Kue/Builtin.lean`
  ~243-248) and `listRangeDecimal` (~263-269) duplicate the ascending/descending
  count formula verbatim with renamed vars. Extract `rangeCount (start limit step : Int)
  : Int` (a named abstraction — the element count of an integer arithmetic sequence) and
  call it from both; the decimal path passes its scaled-to-common-denominator integers.
- **[Borderline] `evalDecimalDivide?` returns `Option (Option String)`.** The nested
  Option encodes three outcomes (non-numeric ⇒ outer `none`, div-by-zero ⇒ `some none`,
  ok ⇒ `some (some text)`). The callsite in `evalDiv` handles all three, but a small sum
  type (`nonNumeric | divByZero | ok String`) would be more illegal-states-unrepresentable
  and self-documenting per the repo's stated philosophy. Low cost, low urgency.
- **[Out of scope / doc fix] `2026-06-16-float-muldiv-landed.md` line ~83** says
  "`divideDecimalRational?` is `partial`". It is a plain `def`; the `partial` markers are
  on its dependencies `divisionDigits`/`roundDigits`. The functional claim (results don't
  `rfl`-reduce, use `native_decide`) is correct. Folds naturally into the totalization
  slice above (which removes the `partial`s and moots the note).

## Later Slices

- Expand pattern constraints beyond the current string-label representation:
  non-string label patterns and fuller regular expression matching.
- Add remaining alias positions in a syntax layer instead of constructing
  semantic values directly.
- Expand cycle handling for arithmetic cycles and richer validation behavior.
- **Builtin families.** Top-level helpers, the `strings` package, and the `list`
  package (integer domain) are landed (see Implementation Status). The decimal-lift
  refactor is also landed: `DecimalValue` and its arithmetic/compare/format helpers now
  live in `Kue/Decimal.lean` (below both `Eval` and `Builtin`), so `Builtin` can do
  exact-decimal work without the old `Builtin → Eval` cycle. **Post-audit builtin
  hardening landed** (commit `1edc760`): the duplicated dispatch fallback is now one
  shared `unresolvedOrBottom` + `isConcreteArg` (reuse it in the `math` dispatcher
  instead of re-duplicating); `stringReplace` and `listFlattenN` are fuel-bounded total
  (no more `partial`); `strings.Replace` count==0, `list.Slice`
  negative-low, and a loop-var-shadows-sibling comprehension are pinned by tests.
  **Float mul/div landed** (this slice): the float-mul/div deferral pins were flipped to
  positive assertions; `evalMul`/`evalDiv` route float and mixed operands through
  `mulDecimalValues` / `divideDecimalRational?` in `Kue/Decimal.lean`. The shared divider
  replaced the prior int-only `formatIntegerDivision`, which over-emitted (fixed 34
  *fractional* digits rather than 34 *significant*) for quotients ≥ 1 — a latent bug now
  corrected.
  **`math` family rational-exact subset landed** (`Abs`, `MultipleOf`,
  `Floor`/`Ceil`/`Round`/`Trunc`): `evalMathBuiltin` reuses the shared
  `unresolvedOrBottom` fallback and does exact-decimal work via `parseDecimalText` +
  `formatFiniteDecimal`. `Abs` is domain-preserving (int→int, float→float);
  `Floor`/`Ceil`/`Round`/`Trunc` take a number and return an int (`Round` is
  half-away-from-zero). **Deferred from `math`:** `Sqrt`/`Pow` (irrational results need
  apd sig-digit context — `cue` gives `Sqrt(2)=1.4142135623730951` at ~17 digits but
  `Pow(2,0.5)=1.414…209698` at 34 digits, and `Sqrt(-1)=NaN.0` rather than erroring, so
  they need both apd-context formatting and a NaN value Kue does not yet model) plus the
  trig/log/`Exp` family.
  **Float-domain `list` builtins landed** (this slice): `list.Avg` plus float/mixed
  `Sum`/`Min`/`Max`/`Range`. The numeric builtins follow CUE's integral-collapse rule —
  an integral result renders as `int` (`list.Sum([1.0,2.0,3.0]) = 6`,
  `list.Avg([1,2,3]) = 2`), a non-integral one as float (`list.Avg([1,1,2]) =
  1.333…333`, 34 sig digits). New `collapseDecimalToValue` / `avgDecimalValue?` in
  `Kue/Decimal.lean`; `Builtin` accumulates via `addDecimalValues`, compares via
  `decimalLtValues`, divides via `divideDecimalRational?`. The all-int fast path on
  `Sum`/`Min`/`Max` is preserved. Still deferred from `list`:
  `Sort`/`SortStable`/`SortStrings` (need comparator-struct evaluation) — the only
  remaining `list` work.
  Then the deferred `strings` functions that need unicode case folding
  (`ToUpper`/`ToLower`/`ToTitle`) or are otherwise unimplemented (`SplitN`,
  `Trim`/`TrimPrefix`/`TrimSuffix`, `Runes`, `ContainsAny`, `LastIndex`, …). Each is
  oracle-checked against `cue` v0.16.1; the package-qualified dispatch (call-on-selector
  → dotted `.builtinCall` name) is in place, so a new family is an `evalXBuiltin` helper,
  a catch-all route in `evalBuiltinCall`, a fixture, and unit theorems.
- Add imports and full module resolution after the syntax and resolver layers exist.
