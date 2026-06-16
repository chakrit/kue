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

## Current Focus — data-driven roadmap to replace `cue` for prod9/infra (2026-06-16)

**Real goal (chakrit):** make kue able to evaluate PRODIGY9's actual infra CUE so it can
replace `cue`, mostly for `prod9/infra` and related repos — as fast as possible.

A read-only gap analysis ran kue against 92 sampled real files across `prod9/infra`,
`infra-defs`, `infra-stage9`. Result: **kue evaluates ZERO real manifest-producing files
today; 85/92 fail at the *parser*** on two ubiquitous-but-trivial forms the fixture suite
never exercised (so the earlier "parser is feature-complete" read was wrong — it only
checked semantic-core features). Slices, in evidence-ranked order (cheap independent wins
first, the big import subsystem last because it gates the real workflow):

1. **B1 — colon-shorthand nested fields** (`a: b: c: 1`). Pure parser; desugar chained
   labels to nested structs. Unblocks the single largest tranche of files. **(active)**
2. **B2 — value/field aliases** (`X=expr`, esp. `#Def: Self={…}` self-reference; 50/92
   files). Parser + resolver binding so `Self.#f` resolves.
3. **B4 — multiline strings** (`"""…"""` currently → `_|_`). Lexer/dedent fix; unblocks
   secret/argo files.
4. **B6 — encoding builtins** `base64.Encode`, `json.Marshal` (load-bearing inside
   `#Secret`/`#ConfigMap`). Small pure functions; kue already has the value AST.
5. **B5 — manifest output**: a YAML/JSON serializer over `Kue/Manifest.lean` + a
   `cue export`-style CLI mode (select expr, `--out yaml/json`, multi-doc streams).
   First true end-to-end manifest on a self-contained leaf file. `yaml.Marshal` shares
   this code.
6. **B3 — module/import resolution** (the big one, LAST): `cue.mod` deps, loading
   `prodigy9.co/defs*` packages from disk, cross-package symbols, multi-file package
   merge. Gates every real `infra/apps/*.cue`. "Packages last" = packages are the final
   and largest blocker, NOT optional.

Note: `strings.*`/`list.*` work *without* an `import` because kue hardcodes those
namespaces and ignores the `import` clause — this masks the absence of any general
import/module mechanism (B3). Remaining stdlib builtins (`strings.Trim*`/`Runes`/…,
`list.Sort`/`SortStable`, unicode case folding) stay parked — infra doesn't need them.
Full gap report: agent run 2026-06-16; reproduce by running kue against the prod9 modules.

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
  `Count`, `Split`, `SplitN`, `Join`, `Replace`, `Repeat`, `TrimSpace`, `Fields`,
  `ToUpper`/`ToLower`/`ToTitle` (ASCII)), the `list`
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
  Parse errors now carry a source position: `ParseError` records the remaining-suffix
  length at the failure site, which `parseSource` converts to 1-based `line`/`column`;
  the CLI prints `kue: parse error: <line>:<col>: <message>`. Remaining parser
  completeness work: non-field aliases and strict CUE newline/semicolon separator
  insertion (separator handling is still permissive around whitespace).
- **Expressions** — unary/additive/multiplicative/division/integer-keyword arithmetic,
  equality, ordering, numeric comparison across int/float, logical `&&`/`||`/`!`, and
  binary regex match `=~`/`!~`. Float multiplication and division are now evaluated
  exactly through `Kue/Decimal.lean`: mul preserves the summed scale verbatim
  (`1.5 * 2.0 = 3.00`); `/` always yields a float and renders non-terminating quotients
  at 34 significant digits (apd context) with round-half-up. All operand domains
  (int/int, int/float, float/int, float/float) share one divider; zero divisor bottoms
  with `divisionByZero`.

Known deliberate boundaries are tracked in [`compat-assumptions.md`](compat-assumptions.md).

## Audit Fix-Slices (float-numeric family, audit 2026-06-16) — CLOSED

Findings from the `/ace-audit` depth pass over `31a85ba`/`3626ea2`/`9f1d797`. **All closed
by post-audit hardening 2** (commit `d6c54a5`):

- **[Violation] Totalize `divisionDigits` and `roundDigits` (`Kue/Decimal.lean`). DONE.**
  - `divisionDigits.loop` → fuel-bounded total `divisionDigitsLoop`, ceiling
    `divisionDigitsFuel den = divisionSigDigits + 1 + (toString den).length`. Leading-zero
    fractional positions are bounded by the den digit count; significant emission is
    hard-capped at `divisionSigDigits + 1`, so the over-budget exit always fires before
    fuel runs out — behaviorally identical to the partial form.
  - `roundDigits` → plain `def`; inner `bump` lifted to structural `roundDigitsBump`.
  - No `partial def` remains in `Decimal.lean`. All division/avg `native_decide` theorems
    pass unchanged; two high-fuel pins added (`1.0/7.0` full-34-sig, `1.0/700.0`
    leading-zero slack) lock the bound's sufficiency.
- **[Borderline] DRY the integer range-count formula. DONE.** Extracted
  `rangeCount (start limit step : Int) : Int`; `listRange` and `listRangeDecimal` both call
  it. Behavior-preserving (range fixtures/theorems green).
- **[Borderline] `evalDecimalDivide?` returns `Option (Option String)`. DONE.** Replaced
  with the named sum `DecimalDivideResult` (`nonNumeric | divByZero | ok String`); `evalDiv`
  callsite reads the three arms directly.
- **[Doc fix] `2026-06-16-float-muldiv-landed.md` partial attribution. DONE.** Corrected;
  the note now records that no `partial` remains in `Decimal.lean`.

## Audit Fix-Slices (sort/case-folding family, audit 2026-06-16 #2)

Findings from the `/ace-audit` depth pass over `d6c54a5`/`1703008`/`cf2da93`. Scrutiny
verdicts: totalization sound (empirically confirmed on worst-case leading-zero +
non-terminating inputs, e.g. `1/7·10²⁰` renders full 34 sig digits, no fuel exhaustion);
`ToTitle` correct and dead-code-free (matches `cue` v0.16.1 on `mIxEd CaSe`, hyphen/dot
non-separators); `byteSeqLe` a correct total lexicographic order, non-string→bottom resolved
before the sort. Tests are strong behavior pins, not smoke.

- **[Doc fix] compat-assumptions false cross-reference. DONE (this audit).** The
  case-folding section claimed the non-ASCII passthrough divergence "is recorded in
  `docs/reference/cue-divergences.md`", but it was never added there — correctly, since that
  file records only `cue`-is-wrong cases and this is a Kue deferred-capability (Kue does
  *less* than `cue`). Reworded to state the boundary lives in compat-assumptions, not the
  divergence log.
- **[Borderline / optional] No theorem pins the `divisionDigitsFuel` sufficiency.** The
  `fuel = 0` arm returns `(acc.reverse, false)` — a silent truncation, not a loud failure —
  so an off-by-one in the ceiling would yield subtly-wrong (truncated) quotients rather than
  crashing. Soundness currently rests on a prose argument plus `native_decide` pins at
  specific inputs, not a proof over all `(num, den)`. Low risk (worst-cases pass), but a
  Lean lemma bounding loop iterations by `divisionDigitsFuel den` would close the gap
  permanently. Schedule only if the decimal layer is revisited; not blocking.

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
  `Sum`/`Min`/`Max` is preserved.
  **`list.SortStrings` landed** (this slice): the comparator-free string sort.
  `listSortStrings` collects the elements as strings (any non-string ⇒ bottom) and runs
  the total, stable `List.mergeSort` with a byte-lexicographic `≤` (`byteSeqLe` over
  `String.toUTF8` — matches Go's `sort.Strings`, so `"Z" < "a" < "é"`). Still deferred
  from `list`: `Sort`/`SortStable` (need comparator-struct evaluation) — the only
  remaining `list` work.
  **`strings.ToUpper`/`ToLower`/`ToTitle` landed (ASCII subset)** (this slice):
  `asciiToUpper`/`asciiToLower` map via `Char.toUpper`/`toLower` (ASCII-only, non-ASCII
  passes through unchanged); `asciiToTitle` capitalizes the first letter of each
  whitespace-delimited word (oracle-confirmed: per-word, NOT upper-case-every-letter; word
  separator is whitespace only). Non-ASCII case folding is a documented deferral boundary
  (`compat-assumptions.md` → String case folding; divergences in `cue-divergences.md`).
  **`strings.SplitN` landed** (this slice): `stringSplitN` over a factored-out
  `stringSplitParts` (raw-string core now shared by `Split` and `SplitN`). Oracle-confirmed
  Go/cue `n` semantics — `n==0` ⇒ `[]`, `n<0` ⇒ all pieces (= `Split`), `n>0` ⇒ first
  `n-1` pieces verbatim with the remainder rejoined (via `sep`) as the last piece; empty
  `sep` splits to runes (then n-capped), empty `s` ⇒ `[""]` for non-empty sep. No
  deferral; empty-sep is cleanly supported.
  Then the still-unimplemented `strings` functions
  (`Trim`/`TrimPrefix`/`TrimSuffix`, `Runes`, `ContainsAny`, `LastIndex`, …) and full
  Unicode case folding. Each is oracle-checked against `cue` v0.16.1; the
  package-qualified dispatch (call-on-selector → dotted `.builtinCall` name) is in place,
  so a new family is an `evalXBuiltin` helper, a catch-all route in `evalBuiltinCall`, a
  fixture, and unit theorems.
- Add imports and full module resolution after the syntax and resolver layers exist.
