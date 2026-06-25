# Kue Compatibility Assumptions

This file records deliberate compatibility assumptions made while CUE behavior is still
being modeled. Each item should be testable and replaceable by a narrower semantic slice.

**Target:** correct CUE **v0.15** semantics, not bug-for-bug parity with the official
binary — see
[`../decisions/2026-06-14-cue-compatibility-target.md`](../decisions/2026-06-14-cue-compatibility-target.md).
References to v0.15.4 below are the deliberate version pin; the local toolchain (v0.16.1)
is used only for `cue fmt` and ad-hoc cross-checks.

The first parser is a syntax layer over Kue's existing semantic core, not a full CUE front
end. It exists so real source snippets can flow through the same resolver and evaluator
that fixture ports use. Rationale: this keeps language-compliance work tied to executable
semantics while avoiding a large parser detour before the core value model can express
those forms.

## Parser and CLI scope

- `package` clauses are accepted and otherwise ignored by the source parser. Explicit CLI
  file arguments are merged by unifying their parsed package bodies; mismatched package
  names are rejected, and package-less files can merge with named packages. Imports ARE
  modeled (in-module + cross-module resolution, qualified import paths) — see "In-module
  imports resolve (B3a)" / "Cross-module … (B3c)" below.
- Top-level fields are parsed into one open struct. References are resolved against nested
  local scopes, def frames, and captured-frame closures (cross-package def-meet), not just
  the same struct — see plan.md § Standing Capabilities.
- Unsupported source forms generally fail with a parse error instead of being
  approximated. This parser is not a complete CUE syntax validator yet.
- Parse errors carry a source position. Every error records the remaining-suffix length at
  the failure point; `parseSource` converts that to a 1-based `line` /`column` (via a
  total `offsetToLineColumn` walk over the source) stored on `ParseError` alongside the
  raw `message`. The CLI prints `kue: parse error: <line>:<col>: <message>` (CUE-style
  `line:col`). Package-clause conflicts (rare, non-cursor errors) report at `1:1`.
- Separator handling is currently permissive around whitespace. A later parser slice
  should implement CUE's newline and semicolon insertion rules directly.
- The parser supports the language forms already backed by semantic values: scalars,
  primitive kinds, structs, lists, refs, `&`, `|`, defaults, integer bounds, primitive
  exclusions, regex constraints, field pattern constraints, list ellipses, byte literals,
  struct embeddings, untyped struct ellipses, static field aliases, value-position aliases
  (`label: X=value`, incl. `#Def: Self={…}` self-reference), `let` declarations, `_`
  -prefixed identifiers (`_x`, `_foo`, `__bar`) in any expression/value position — the
  lexer treats bare `_` as top only when not followed by an identifier char, so `_x` is a
  hidden-field reference and `_|_` is bottom, never `_` + stray input, static field
  selectors, static index expressions, existing builtin call values, comprehensions
  (`for`/`if` field clauses), dynamic fields (`(expr): v`), string interpolation
  (`"\(expr)"`), list embeddings (a `[` -led struct member is parsed as an embedded list —
  `[...]`, `[1,2,3]` — not a `[label]: value` pattern; the parser falls back to embedding
  when the member is not a valid pattern), colon-shorthand nested fields (`a: b: c: 1`,
  desugared to the brace form `a: {b: {c: 1}}` — same AST, so it unifies/closes/exports
  identically; inner labels may be identifiers, definitions, quoted strings, or `(expr)`
  dynamic, each with optional `?` /`!` markers), and multiline string/bytes literals
  (`"""…"""`, `'''…'''`).
- Multiline strings (`"""…"""`) and multiline bytes (`'''…'''`) are supported. Content
  begins on the line after the opening delimiter; the closing delimiter sits on its own
  line, and the leading horizontal whitespace (spaces/tabs) preceding it is the strip
  prefix removed from every content line. The newline immediately after the opening
  delimiter and the one before the closing line are excluded; remaining lines join with
  `\n`. Each non-blank content line must begin with the full strip prefix (a line with
  some-but-insufficient whitespace is rejected as CUE's "invalid whitespace"); a fully
  empty line is allowed and contributes an empty line. Content on the opening-delimiter
  line is rejected (the delimiter must be followed by a newline). Backslash escapes and
  `\(expr)` interpolation work inside `"""…"""` exactly as in single-line strings.
  **Deferral:** interpolation inside multiline *bytes* (`'''…\(x)…'''`) is rejected at
  parse — Kue's bytes value is a plain string payload and the interpolation machinery
  yields a string, not bytes; non-interpolated `'''…'''` dedents to a bytes value
  normally. This is a Kue-does-less boundary, not a `cue` divergence.
- The parser does not yet support typed struct ellipsis syntax (`...T`, which cue v0.15.4
  also rejects). Value-position aliases are now supported (see References, bindings, and
  selectors below).
- **`let` declarations — all positions supported.** A `let X = expr` binds `X` in the
  enclosing struct's lexical scope (file-scope/top-level *and* in-struct), visible to
  sibling fields and other `let` s, never emitted as output. Confirmed against `cue`
  v0.16.1: file-scope `let`, in-struct `let`, `let` referencing a sibling field, `let`
  referencing a prior `let`, and inner-`let`-shadows-outer all match. (The 2026-06-17
  real-file diagnosis disproved the earlier "`let` is the top blocker" read — the failing
  files were tripping on the `[...]` list embedding inside the `let` RHS, not on `let`.)
  Leniency (kue-does-less, not a kue-is-right divergence so not in `cue-divergences.md`):
  `cue` *errors* on an unreferenced `let` /alias (`unreferenced alias or let clause` —
  intentional dead-binding detection); kue silently drops it. Tightening kue to match is a
  later slice if a real file needs the diagnostic.
- **List-embedding-in-struct eval — IMPLEMENTED (2026-06-17), oracle-matched.** A struct
  whose members are *all non-output* (hidden `_x`, definition `#x`, optional `a?:`, or
  `let`) embedding a list *is* that list: it manifests as the list, indexes as the list,
  yet its declarations stay selectable (`v.#x`). With any **regular or required** field
  present the struct/list embed is a genuine conflict (`⊥`). Modeled by a dedicated
  `Value.embeddedList (items) (tail : Option Value) (decls)` constructor (illegal-states
  win: the list nature and the surviving decls are one value, not a flagged struct). The
  decision pivots on `FieldClass.producesOutput` (true only for `regular` /`required`).
  Meet arms in `Lattice.meetWithFuel` build it (`meet(only-non-output struct, list)`),
  merge two of them (decls meet struct-wise, lists meet via `meetListPairWith`), and meet
  one against a further struct/list; `meetCore` 's fuel-0 fallback bottoms it
  conservatively. `Manifest` emits its concrete items (decls + open tail dropped —
  `{#a:1, [...]}` → `[]`); `Eval.selectEvaluatedField` /`selectEvaluatedIndex` read
  decls/items; `containsBottom` recurses into items/tail/decls so an element conflict
  surfaces (`{#a:1,[1]} & {#b:2,[9]}` → `x.0` conflict, export errors — matches `cue`).
  Oracle evidence (`cue` v0.16.1): `{[1,2,3]}` →`[1,2,3]`; `{#a:1,[1,2]}` →`[1,2]`;
  `{#a:1,[...]}` →`[]`; `{a:1,[1,2]}` →conflict; `{a?:int,[1,2]}` →`[1,2]`; `{a:1}&[1,2]`
  →conflict; `v.#a` and `v[0]` both work on the dual-nature value.
  - **DEFERRED — the `nsp` /`#Argo` *direct* manifest still bottoms, but that matches
    `cue`.** `x: packs.#Argo & {#name:…}` (no `[...]` in the consuming struct) errors in
    *both* kue and `cue` (struct/list conflict): the consuming struct must itself carry a
    `[...]` embed (`configs: packs.#Argo & {[...], #name:…}`, as the real prod9 files do)
    for the embeddedList path to engage. With `[...]` present, `cue` proceeds and the next
    gate is the **`if Self.#x!= _|_` presence-test comprehension guard**. The `!= _|_`
    *comparison* is now fixed (see Comparison section — definedness test landed
    2026-06-17). The **lazy field resolution through definition-meet** gate (slice 2c) is
    now landed: 2c.1 fixed in-struct duplicate labels, 2c.2 fixed conjunction (`&`). A
    definition's field bodies now resolve against the *merged* conjunction scope, not
    their pre-meet scope — the reduced `packs.#Argo` def-meet templating shape exports
    byte-identical to `cue` (see `testdata/export/def_meet_template`). Not a
    list-embedding gap — the embedding semantics here are complete and oracle-clean.
- **Struct conjunction (`&`) merges declarations before evaluating bodies (slice 2c.2).**
  When every operand of a `&` reduces to a same-scope struct, the conjuncts' *unevaluated*
  declarations are merged into one frame (first-occurrence layout, deferred `.conj` on
  collisions; sibling refs rebased onto the merged layout) and evaluated once — so a body
  referencing a sibling that another conjunct narrows sees the narrowed value
  (`d:{a:int,b:a}; y:d&{a:1}` → `y.b:1`). This is an *eval-layer* rewrite of the `.conj`
  arm, not a change to `meet`: `meet` stays a pure `Value→Value→Value` with `.refId`
  opaque to it. Operands that are not same-scope structs (lists, primitives, patterns,
  tails, disjunctions, outer-scope refs) keep the eval-then-`meet` path unchanged.
  **Closedness is preserved exactly:** each closed conjunct (a definition normalizes to a
  closed struct) still rejects fields outside its declared labels (`#D & {extra}` →
  `extra` bottoms), folded identically to binary meet's `applyStructClosedness`; the
  result of conjoining a closed def stays closed.
- **Field modifiers are orthogonal axes (resolved the `#x?` gap).** `FieldClass` is no
  longer a flat enum. It is
  `field (isDefinition isHidden : Bool) (optionality : Optionality)` plus a distinct
  `letBinding` constructor, where `Optionality = regular | optional | required`. The
  legacy names (`.regular`, `.optional`, `.required`, `.hidden`, `.definition`) survive as
  smart constructors, so every existing construction/`==` site is unchanged; only the few
  *match* sites (Manifest/Format/Eval/Normalize) and `mergeFieldClass` were rewritten to
  operate per-axis. `mergeFieldClass` now ORs `isDefinition` /`isHidden` and meets
  optionality on a lattice where a present (`regular`) conjunct dominates and discharges
  `required` (`x! & x = x`), `required` dominates `optional` (`x! & x? = x!`), and
  `optional & optional` stays optional — oracle-confirmed `cue v0.16.1`. This makes `#x?`
  (optional definition), `#x!` (required definition), and `_x?` (optional hidden)
  first-class: `#D: {#x?: string}; y: #D & {#x: "hi"}` merges `#x` to a present definition
  `"hi"` (eval), exports `{}` (definitions are non-output). `producesOutput` is true only
  for a plain present field (`field false false regular`) or a satisfied required field
  (`field false false required`), matching the prior enum; `ignoresClosedness` is
  `isDefinition || isHidden` (so `#x?` /`_x?` ignore closedness on the def/hidden axis
  regardless of optionality). The label string still carries the `#` /`_` prefix, so `#x`
  and `x` are distinct labels and `mergeFieldClass` is only ever invoked for same-prefix
  fields — the cross-prefix combinations the old enum rejected never actually arise.
  **Note:** `mergeFieldClass` 's previous *rejection* of `optional & required` was a bug
  the flat enum forced; oracle confirms `x? & x! = x!` (not `_|_`).
- **In-module imports resolve (B3a).** A single file (or `export` file-mode) routes
  through the import-aware loader: `cue.mod/module.cue` is discovered by walking parent
  dirs, an import path `<module>` or `<module>/<subpath>` is resolved to the corresponding
  dir under the module root, the package's `*.cue` are meet-merged, and the result is
  bound as a hidden top-level field so `pkg.#Sym` resolves through the ordinary selector
  path. Transitive in-module imports load recursively with a visited-set cycle guard.
  Builtin stdlib import paths (`strings`/`list`/`math`/`encoding/{base64,json,yaml}`) are
  skipped by the loader and continue to dispatch via the dotted builtin name.
- **Cross-module / vendored imports resolve (B3c).** An import path matching a `deps`
  entry of the importing `cue.mod/module.cue` is the *dependency* module, not an in-module
  subdir — **a declared dep wins over the in-module prefix interpretation** (so
  `prodigy9.co/defs`, declared as `"prodigy9.co/defs@v0"` in deps, resolves to the
  separate `defs` module even though it lies textually under the `prodigy9.co` module).
  The dep's pinned version comes from `deps.<key>.v`; the owning dep is chosen by longest
  module-path prefix. The module is located **read-only** in priority order: vendored
  `cue.mod/pkg/<modpath>[@ver]/`, then the extract cache
  `<cacheRoot>/mod/extract/<modpath>@<ver>/`, where `cacheRoot` honors `$CUE_CACHE_DIR`,
  else `$XDG_CACHE_HOME/cue`, else the per-OS user cache (Go `os.UserCacheDir`): macOS
  `~/Library/Caches/cue`, other Unix `~/.cache/cue`. The subpath is mapped within the
  located module root and loaded via the same `loadPackage` machinery; a cross-module
  import *inside* a loaded module hops to that module's own context, so transitive
  cross-module resolves recursively. A path matching neither the module prefix nor any dep
  → `unresolved import …: not in-module and matches no dependency …`; a declared dep
  absent from vendor and cache →
  `unresolved import …: module <modpath>@<ver> not found in vendor or cue cache … registry fetch is B3d`.
  **kue is more lenient than `cue` on the transitive graph:** it reads the *intermediate*
  module's `deps` per hop, whereas `cue` requires every transitive dep pinned flat in the
  main module (MVS). Both resolve when the artifact is on disk. **Deferred (B3d):**
  registry FETCH (OCI/`CUE_REGISTRY`), MVS version *solving*, and `cue.sum` verification —
  B3c assumes the artifact is already on disk.
- **Deferred (B3b):** aliased-import edges, nested-path corners, and grouped-import
  comment/ trailing-comma robustness. Real prod9 grouped imports parse fine today, so this
  stays parked. The stdin and multi-file CLI paths still discard imports (pre-B3a
  behavior), so a stdin file with a non-builtin import is unaffected.
- **`export -e <expr>
  ` field-path selector — IMPLEMENTED (2026-06-17), oracle-matched.** ` kue export -e
  <path> ` (or ` --expression`) selects a dotted field path from the evaluated root and
  exports just that value, with no `{name: …}` wrapper — byte-matching `cue export -e`
  (json default + `--out yaml`). Works in both file mode and stdin mode. Selection walks
  the path via `Runtime.selectExprPath`, resolving/evaluating between segments so a nested
  field's own refs bind before the next lookup. A missing segment errors with
  `reference "<seg>" not found` and exit 1 (mirrors `cue`); a present-but-incomplete
  selection falls through to the usual `incomplete value …` manifest error. **Scope:
  dotted field paths only** (`common`, `a.b.c`). **Deferred** (not yet needed for real
  prod9 apps, each a clean add when wanted): index/slice selectors (`a[0]`), repeated `-e`
  → multi-document output (`cue` emits one doc per `-e`), and arbitrary CUE expressions as
  the selector (`cue` evaluates `-e` in the root scope, so e.g. `-e 'a.b & {x:1}'` works
  there). A malformed path (empty segment from a leading/trailing/doubled dot) is a clean
  `invalid -e expression` error, not a crash. **YAML over-quoting now fixed (see YAML
  scalar quoting below).** A whole-file `--out yaml` of `hatari/infra/apps/common.cue` is
  byte-identical to `cue` v0.16.1 (IPs now bare).
- The executable reads CUE from stdin or from explicit file arguments and prints
  resolved/evaluated Kue output. Empty stdin still prints the existing semantic smoke
  output for quick build checks.
- **File-vs-directory entry (`loadEntry`, matches `cue`).** A *directory* argument to
  `kue eval` /`kue export` loads the directory as a package: all same-package `*.cue`
  siblings are meet-merged (reusing the imported-package loader `loadPackage` —
  package-name consistency, sibling merge, per-file import binding) before
  eval/export/`-e`-selection. A bare *file* argument loads only that file with **no**
  sibling merge — exactly `cue` 's contract (`cue export apps/argocd.cue` errors on a
  sibling-defined reference; `cue export ./apps` resolves it). The split is
  `FilePath.isDir` at the IO boundary; the single-file and stdin paths are byte-unchanged.
  A directory with two differing named packages is rejected (kue via the
  conflicting-package-name fold; cue with its `found packages …` diagnostic — both reject,
  message text differs).
- **CLI surface (subcommand dispatcher, `Kue/Cli.lean`).** `parse : List String → Command`
  is a pure fold into a `Command` sum type; `Main` dispatches exhaustively. Surface:
  `kue eval [file…]` (explicit name for the default internal-format path — stdin, single
  file via the loader, or multi-file merge), `kue export [--out json|yaml] [file]`,
  `kue version` / `--version` / `-V` (prints `Kue.version`), `kue help [eval|export]` /
  `--help` / `-h` (top-level synopsis + subcommand list + per-command usage). **Dispatch
  is back-compat by construction:** a first token that is not a recognized subcommand or
  top-level flag is treated as the eval positional list, so `kue < file`, `kue <file…>`,
  and `kue export …` behave exactly as before this slice. Exit codes are distinct: `2` for
  usage errors (unknown subcommand-flag, bad/missing `--out` value), `1` for
  eval/parse/manifest failures, `0` on success. A missing or unreadable input file reports
  `kue: cannot read <path>: <io-error>` rather than an uncaught exception. CUE divergence:
  this is **not** `cue` 's command surface (`cue eval`/`cue export`/`cue vet`/…) — Kue
  ships only the subset above; `eval` prints Kue's internal format, not `cue eval` 's.
  `cue` -compat is at the `export` byte level (see the manifest section), not the CLI
  ergonomics.

## Structs, embeddings, and patterns

- Struct embeddings are lowered to conjunctions with the declared fields. This is a useful
  executable model for schema composition, but it is not yet a full embedding validator
  for every non-struct expression shape.
- Duplicate fields are merged after reference evaluation when their field classes have an
  existing merge rule. Unsupported same-label class combinations are kept distinct in this
  pass; diagnostic provenance and output ordering are still first-pass.
- Untyped struct ellipses are represented as `.structTail` values with a top tail. Typed
  struct tails remain semantic-only because the pinned CUE v0.15.4 tool rejects `...T`
  source syntax.
- **Open-list export collapse.** On the manifest/export path an open list collapses to its
  concrete prefix — the open/typed tail is dropped, matching `cue export` (oracle
  v0.16.1): `[1,...]` →`[1]`, `[...]` →`[]`, `[1,2,...int]` →`[1,2]`, `[1,...string]`
  →`[1]`. No open-list shape is genuinely incomplete *because of* its tail; a non-concrete
  prefix *element* is still incomplete (`[int,...]` errors in both cue and kue). The
  INTERNAL `formatValue` representation keeps the open form (`[1,...]`) — this is a
  manifest-only collapse, applied identically to bare `listTail` and struct-`embeddedList`
  tails.
- Multiple pattern fields are represented as independent pattern constraints. The label
  pattern is an arbitrary constraint expression — kind/type (`[string]:`, `[int]:`,
  `[bool]:`), exact string (`["a"]:`), bound (`[>0]:`), and the supported regex subset
  (`[=~"re"]:`) all parse and match (a field whose string label unifies with the pattern
  is constrained by the value). Both surface forms reach the same `structPattern`
  representation: the brace form `{[string]: T}` and the bare colon-shorthand
  `f: [string]: T` (= `f: {[string]: T}`), the latter including under optional/definition
  outer fields (`#labels?: [string]: string`). The bracket-`[`-in-field-position
  disambiguation: a balanced `[ … ]` immediately followed by `:` is a pattern; otherwise
  it is a list embedding (`[1, 2, 3]`). Matching reach for the pattern value is still
  bounded by `meetValue` (regex by its supported subset, etc.); the surface syntax itself
  is general.

## Numeric literals

- Decimal numeric separators are stripped while parsing. Exponent literals are accepted as
  float strings with normalized exponent signs, but Kue does not yet canonicalize all
  exponent arithmetic the way `cue eval` does.
- Lowercase non-decimal integer literals with `0x`, `0o`, and `0b` prefixes are
  canonicalized to decimal integers while parsing. Separators are accepted in their digit
  sequences.
- CUE's decimal numeric suffix multipliers `K`, `M`, `G`, `T`, `P` and binary suffixes
  `Ki`, `Mi`, `Gi`, `Ti`, `Pi` are accepted on decimal integer and decimal fraction
  literals when the multiplied result is exactly representable as an integer. Inexact
  suffix products fail during parsing, matching `cue eval`.

## Arithmetic expressions

- Unary numeric `+` and `-` are represented explicitly for non-literal operands. Concrete
  integer operands and float spelling strings evaluate now. Incomplete numeric operands
  remain residual unary expressions until invalid operand diagnostics are modeled.
- Additive expressions are represented explicitly. The evaluator currently handles
  concrete integer addition/subtraction plus concrete string and byte concatenation.
  Finite decimal float addition/subtraction is evaluated exactly with scaled integer
  arithmetic, including exponent spellings. List arithmetic is not targeted for `+`
  because CUE v0.15.4 rejects it in favor of `list.Concat`.
- Multiplication expressions are parsed with higher precedence than additive expressions.
  Concrete integer multiplication yields an int. Float multiplication (and mixed
  int×float, which promotes to float) is evaluated exactly through the `Decimal` module:
  numerators multiply and scales add, and CUE preserves the summed scale verbatim with no
  trailing-zero trim (`1.0 * 1.0 = 1.00`, `1.5 * 2.0 = 3.00`). Oracle-confirmed against
  cue v0.16.1.
- Division expressions are parsed at the same precedence as multiplication. `/` always
  yields a float, never an int (`4.0 / 2.0 = 2.0`, `6 / 2 = 3.0`); integer division is the
  separate `div` /`quo` keywords. All four operand domains (int÷int, int÷float, float÷int,
  float÷float) route through one `Decimal` divider. Terminating quotients render exactly
  (`1.0 / 4.0 = 0.25`); non-terminating quotients render at **34 significant digits** (apd
  context, matching cue v0.16.1) with round-half-up on the guard digit. Round-half-up vs
  apd's nominal `ROUND_HALF_EVEN` is unobservable here: a rational repeating expansion
  never produces an exact tie, so the guard digit alone decides. Division by zero (any
  zero divisor, int or float) bottoms out with `divisionByZero` provenance. No documented
  division case remains deferred — the prior fixed-34-fractional-digit int divider, which
  over-emitted for quotients ≥ 1, was replaced by the shared significant-digit divider as
  part of this slice.
- Integer keyword expressions `div`, `mod`, `quo`, and `rem` are parsed at multiplicative
  precedence and reuse the existing integer builtin semantics. Concrete integer operands
  evaluate now; incomplete operands remain as residual infix binary expressions.

## Comparison and logical expressions

- Equality expressions `==` and `!=` are parsed after additive/multiplicative expressions.
  The evaluator currently handles concrete primitive equality and numeric equality across
  int/float spellings. Equality over incomplete values and compound values remains later
  work.
- **`e == _|_` / `e != _|_` is CUE's definedness test, not value equality** (the
  `if Self.#x != _|_` idiom). Oracle-pinned (`cue` v0.16.1): evaluate the non-`_|_`
  operand and classify three-way — a *defined* value (prim/struct/list/…) gives `!= _|_`
  true / `== _|_` false; an *error* (evaluated bottom: a missing field, a conflict) gives
  `== _|_` true; an *incomplete* operand (kind `int`, a bound `>5`, an unresolved
  ref/disj, `_` /top) keeps the comparison itself incomplete — it does NOT resolve to a
  bool, matching `cue` 's "non-concrete value in operand to ==" / "requires concrete
  value". Triggered only on the **syntactic `_|_` literal** (parses to bare `.bottom`) at
  the `.binary` dispatch; ordinary `==` /`!=` whose operand merely *evaluated* to an error
  still propagates that error (`(1/0) == 2` → the error, not `false`), also
  oracle-confirmed. `classifyDefinedness` / `evalPresenceTest` in `Eval.lean`;
  `presence_test_guard` fixture + `PresenceTests`.
  - **kue-side deferral (NOT a `cue` divergence).** kue models a missing-field selection
    on a *concrete closed struct* as a residual `.selector` (→ *incomplete*), whereas
    `cue` treats it as a definite *bottom* (so `x.absent == _|_` → `true` in `cue`). The
    observable guard behavior agrees — both make `if x.absent != _|_` drop — so the real
    idiom is unaffected; only a bare `x.absent == _|_` outside a guard would differ.
    Tightening missing-field-on-closed-struct to bottom is the principled fix (the loose
    incomplete/bottom conflation the type-system lens flags) but has broad blast radius
    across every selection path and does NOT unblock the argocd gate, so it is deferred.
  - **Lazy field resolution through definition-meet — RESOLVED.** A definition's
    comprehension body + field refs now resolve against the *merged* meet scope, not the
    pre-meet scope, both same-package (slice 2c.2 + the `#x?` optional-definition fix —
    `#D: {#x?: string}; y: #D & {#x:"hi"}` → `out.val:"hi"`; see "Struct conjunction
    (`&`)" and "Field modifiers" above) and cross-package via import (`Value.closure`
    capture frame — `parts.#M & {#name:"keel"}` → `out:"keel"`; see plan.md Standing
    Capabilities and `testdata/modules/crosspkg_defmeet/`).
- Ordering expressions `<`, `<=`, `>`, and `>=` are parsed at the same comparison
  precedence as equality. The evaluator currently handles concrete numeric and string
  operands. Mixed-kind ordering bottoms out; ordering over bytes, incomplete values, and
  compound values remains later work.
- **Numeric bounds are decimal-valued and domain-tagged (`>0` is a number bound — matches
  CUE).** Kue parses `>n` /`>=n`/`<n`/`<=n` into a single
  `boundConstraint (bound : DecimalValue) (kind : BoundKind) (domain : NumberDomain)`
  (decimal limit + domain tag since 2026-06-17 item **2b**; the 2a fold landed the single
  ctor with an `Int` limit and no domain, deliberately one field short). The limit is an
  exact base-10 rational (`Kue.DecimalValue`, reused from the decimal arithmetic layer),
  so decimal bound literals **parse** (`>0.5`, `>-1.5`, `<3.14`) and the comparator
  (`BoundKind.admits`) compares via `decimalLeValues` /`decimalLtValues` — no float
  rounding. `NumberDomain = number | int | float` (a proper sum, not a flag) tags which
  numeric kinds a bound admits: a **bare** bound is `number` -domain and admits **both int
  and float**, matching cue (`>0 & 1.5` → `1.5`, `>0.5 & 1.0` → `1.0`, `>=0 & <=10 & 5.5`
  → `5.5`). The prior over-strict divergence (kue `>0 & 1.5` → `_|_`) is **closed**. A
  bound's `domain` is narrowed to `int` /`float` only conceptually — see the kind-meet
  rule below; in practice a parsed bound is always `number` -domain and the kind conjunct
  does the narrowing.
- **A numeric kind meeting a bound retains the kind as a conjunction (`int & >0`,
  `float & >0`).** Meeting a numeric kind with a bound (`meetKindWithBound`): `int`
  /`float` are retained as a conjunct (`int & >0` → `.conj [kind int, >0]`, formatting
  `int & >0`; likewise `float & >0`), because the kept kind is load-bearing — it is the
  conjunct that rejects the wrong primitive kind, *not* the bound. The bound keeps its
  `number` domain rather than being narrowed: the kept kind conjunct already guards every
  operand, and leaving the bound untouched keeps meet **commutative** (a range
  `[>=0, <=n]` that `& int` reduces pairwise cannot narrow every member uniformly — but it
  does not need to). `number` is dropped (`number & >0` → `>0`, redundant); `string`
  /non-numeric conflict. Oracle-pinned to cue v0.16.1: `int & >0` prints `int & >0`,
  `(int & >0) & 1.5` → `_|_`, `(int & >0) & 5` → `5`, `float & >0 & 1.0` → `1.0`,
  `float & >0 & 1` → `_|_`, `int & >=0 & <=65535` → the flat `int & >=0 & <=65535` (cue
  *displays* this as the alias `uint16`; kue keeps the structural conjunction — a
  cosmetic-only divergence, same value). Conjunction meets reduce over a *flat* constraint
  set (`flattenConj` + `addConstraintWith` in `Lattice.lean`) so nested/ multi-bound
  conjunctions merge pairwise without nesting or scrambling into bottom, then the re-wrap
  `sortConjMembers` -sorts the members into a **canonical order** (kind first, then bounds
  by `(BoundKind.rank, limit)`, then `notPrim`, then `stringRegex`). This makes meet
  commutative on the canonical form (`meet a b == meet b a`) and matches cue's kind-first
  display order — closing the Phase-A `a & b ≠ b & a` canonical-`Value` hazard.
- Binary regex match expressions `=~` and `!~` are parsed at comparison precedence. The
  evaluator currently handles concrete string operands using Kue's existing regex subset.
  Non-string concrete primitive operands bottom out; incomplete operands remain residual
  binary expressions.
- Logical expressions `&&` and `||` are parsed above CUE unification/disjunction and below
  equality/ordering comparison precedence. The evaluator currently handles concrete
  boolean operands only. CUE rejects incomplete logical operands as invalid; Kue keeps
  them as residual binary expressions until diagnostic modeling exists.
- Logical negation `!` is represented as a residual unary expression when its operand is
  incomplete. Concrete boolean operands evaluate to concrete booleans, and concrete
  non-boolean primitive operands bottom out.

## References, bindings, and selectors

- `let` declarations are represented as non-output binding fields inside the same ordered
  field list as regular fields. This supports ordinary top-level and nested references,
  but duplicate names between `let` bindings and fields still follow Kue's current
  first-binding resolver instead of a complete lexical binding graph.
- Static field aliases such as `A="label": value` are represented as non-output binding
  fields that refer to the aliased field label.
- **Value-position aliases** such as `label: X=value` (esp. `#Def: Self={…}`) are
  supported. The alias is visible within the value it labels and refers to the whole value
  — oracle-confirmed against `cue` v0.16.1: an alias is **not** visible to siblings or the
  enclosing struct, only inside its own value and that value's descendants. For a struct
  value, a non-output `let` -binding (`.letBinding`) named by the alias is prepended to
  the struct's fields with the value `.thisStruct`; a `Self.field` selector on that
  binding is resolved as an ordinary same-struct sibling reference (it inherits the
  same-struct cycle guard, so self-reference cycles bound to top rather than diverging).
  For a non-struct (scalar) value the alias is inert — a scalar cannot reference its own
  alias and siblings cannot see it, so the value passes through unchanged.
  - **Deferred:** like every Kue reference, a `Self.field` self-reference resolves against
    the value's **lexical** frame, not the post-unification merge. So `#D & {x: 5}` where
    `#D` is `Self={x: int, y: Self.x}` leaves `y: int` (cue gives `y: 5`). This is the
    same pre-existing boundary that affects plain sibling refs (`y: x` under unification),
    not specific to aliases — lifting it requires re-resolving references against the
    merged value and is tracked as broader resolver work, not an alias gap.
  - **Deferred:** a **bare** `Self` (the whole struct as a value, e.g. `copy: Self`) emits
    the residual `@self` rather than a value; `cue` rejects it as a structural cycle. The
    load-bearing prod9 pattern is always `Self.field` (a selector), never bare `Self`, so
    this is left as a documented boundary.
  - **Permissiveness note (not a divergence):** `cue` rejects an *unreferenced* value
    alias as a hard error (`unreferenced alias or let clause X`); Kue accepts it and emits
    the value. This is consistent with Kue's standing permissive stance (cf. separators)
    and is a Kue-does-less boundary, not a `cue` defect, so it is not in
    `docs/reference/cue-divergences.md`. A scalar alias (`a: X="hi"`) is therefore always
    "unreferenced" by `cue` 's rule but evaluates fine in Kue.
- Static field selectors such as `base.inner` are represented explicitly and evaluate
  declared fields on evaluated structs. Static index expressions such as `xs[1]` and
  `base["inner"]` evaluate concrete integer list indices and concrete string field indices
  after resolving the base and key expressions. Missing string field indices remain
  incomplete index values, and open-list tail indices beyond the fixed prefix also remain
  incomplete. Invalid closed-list indices bottom out with first-pass structural provenance
  only; richer index diagnostics and non-field dynamic selection remain later work.
- Nested structs resolve same-struct references with local binding ids. References that
  fall through to an enclosing struct remain label-based during evaluation until binding
  ids can carry explicit scope identity.

## String case folding (`ToUpper` / `ToLower` / `ToTitle`)

- **`ToUpper`/`ToLower`: full BMP Unicode simple case mapping (BI-1, 2026-06-20).** Both
  map the entire Basic Multilingual Plane cased-letter set — ASCII, Latin-1 supplement,
  Latin Extended, Greek, Cyrillic, Armenian, fullwidth, and the long tail of irregular
  singletons (`µ`→`Μ`, `ÿ` →`Ÿ`, …) — via the oracle-derived table in `Kue/CaseTable.lean`
  (lookup + char map in `Kue/Builtin.lean`). `ToUpper("café") == "CAFÉ"`,
  `ToLower("ΑΒΓ") == "αβγ"`: oracle-faithful to `cue` v0.16.1 across the BMP. A rune with
  no table entry (uncased, or a length-changing special case — see next bullet) passes
  through unchanged.
- **Simple mapping, not full folding — the coverage boundary.** `cue` 's `strings.ToUpper`
  / `ToLower` are Go's `unicode.ToUpper` /`ToLower`: a pure rune-wise **simple 1:1** map
  with NO length-changing special-casing. So `ToUpper("ß") == "ß"` (German ß does NOT
  expand to `SS`), matching `cue` — Kue conforms. The deferred long tail (a separate slice
  if ever needed): full case folding (`ß`→`SS`, title-case digraphs), **locale tailoring**
  (Turkish/Azeri `tr` /`az` rules), and context rules (Greek final sigma). NB: the
  *default* (`und`-locale) simple mappings for the Turkish-I confusables ARE implemented —
  `İ` (U+0130)→`i`, `ı` (U+0131)→ `I`, exactly as `cue` (pinned:
  `strings_to_{lower,upper}_dot{ted,less}_*_i`); only the locale-specific retailoring of
  those (e.g. `İ` →dotless `ı` under `tr`) is deferred. All recorded as a spec-gap in
  `docs/reference/cue-spec-gaps.md`. Code points outside the BMP (astral planes) are not
  in the table → identity (no astral-plane cased letter is common; extend the generator's
  range if a real case appears).
- **`ToTitle` is STILL ASCII-bounded (the lone case holdout).** It upper-cases only the
  ASCII first letter of each whitespace-delimited word; a non-ASCII word-initial letter is
  left unchanged. `ToTitle("über alles")` → Kue `"über Alles"`, cue `"Über Alles"` (the
  one remaining case-builtin divergence, all non-ASCII). ToTitle was NOT folded into BI-1
  because its mapping is Unicode **title-case** (distinct from upper — `ǆ` →`ǅ`, not `Ǆ`)
  and its word boundary is `unicode.IsSpace` (broader than ASCII whitespace); both need
  their own table + predicate. This is a deferred-capability boundary (Kue does *less*
  than `cue`), not a `cue` defect, so it stays here and not in `cue-divergences.md`.
- **`ToTitle` is per-word capitalization, NOT "upper-case every letter".**
  Oracle-confirmed: it upper-cases the first character of each **whitespace-delimited**
  word and leaves the rest untouched — NOT Go's `strings.ToTitle` (which upper-cases all
  letters). `-`, `.`, `_`, `/`, digits, and other punctuation do NOT start a new word:
  `ToTitle("a-b a.b")` → `"A-b A.b"`. The ASCII whitespace set covered is the six runes
  `\t \n \v \f \r` and space.
- **Provenance of the table.** `scripts/gen-case-table.py` derives `Kue/CaseTable.lean` by
  querying the LOCAL `cue` oracle over the BMP (READ-ONLY, no network) and emitting the
  differing src→dst pairs as two sorted arrays. The data-approach spike
  (`spec-conformance- audit.md` BI-1) rejected algorithmic ranges: the mapping is
  overwhelmingly irregular (632 of 674 ToUpper offset-runs are singletons), so a table is
  the only clean, fully-correct path. Unicode case mapping is not a `cue` -buggy area, so
  the oracle is a sound data source; the Unicode standard is the principled authority and
  the full-folding tail above the gap.

## Encoding builtins (`base64.Encode`, `json.Marshal`)

Supported. Both dispatch on the dotted builtin name (`import "encoding/base64"` /
`import "encoding/json"` parsed-and-ignored, like the other families). The JSON serializer
lives in the reusable `Kue/Json.lean` (`manifestToJson`), shared with B5.

- **`base64.Encode(encoding, data)` supports only the `null` encoding** — standard padded
  base64 (RFC 4648, `base64.StdEncoding`) over the UTF-8 bytes of a string or bytes
  payload. Oracle-confirmed (`cue` v0.16.1): `null` selects standard padding; any non-null
  encoding selector is an error (`cue`: "base64: unsupported encoding: cannot use value …
  as null"), so Kue resolves it to bottom. Encoding over a string uses its UTF-8 bytes
  (`"héllo"` → `"aMOpbGxv"`), identical to encoding the equivalent bytes value.
  **Deferred:** non-null encodings (`base64.URLEncoding` etc.) and `base64.Decode` (no
  error/bytes-result path for malformed input yet). Kue-does-less boundary, not a `cue`
  defect.
- **`json.Marshal(value)` produces compact JSON byte-for-byte matching `cue`.**
  Oracle-confirmed (`cue` v0.16.1): object keys are emitted in **source/insertion order,
  NOT sorted** (`{b,a,c}` → `{"b":…,"a":…,"c":…}`); separators are `,` and `:` with no
  spaces; floats render from their exact stored decimal text verbatim (`1.0`→`"1.0"`,
  `1.50` →`"1.50"`, `0.1` →`"0.1"`); a bytes value marshals to a base64 JSON string (Go
  `[]byte` semantics); control characters below `0x20` escape as `\b\f\n\r\t` or `\uXXXX`;
  `<`, `>`, `&`, `/` and all non-ASCII runes pass through verbatim — `cue` disables Go's
  default HTML-escaping (this is `cue` 's documented behavior, not a defect, so it is NOT
  a `cue-divergence`). The value is manifested first, so defaults and incompleteness rules
  apply: an incomplete or contradictory value (e.g. `{a: int}`) is bottom (`cue` errors
  "cannot convert incomplete value … to JSON"). An argument that is still an unresolved
  reference form (`.ref`/`.selector`/`.index`/`.builtinCall`) is preserved as an
  unresolved `.builtinCall` so a later evaluation pass can complete it. **Deferred:**
  `json.MarshalStream` (multi-doc), `json.Indent` (pretty-printing), `json.Unmarshal`
  /`json.Validate` (parsing).
- **Composition note (infra docker-config).** The prod9/infra
  `base64.Encode(null, json.Marshal({auths: …}))` chain evaluates correctly when the inner
  struct's fields resolve. The two former blockers on `infra-defs/secret.cue` are now
  RESOLVED: hidden-field references resolve (`_a: "secret"; y: _a` → `y: "secret"`), and
  the non-string label-pattern (`[string]: string`) parses. The encoding builtins were
  never the blocker, and neither residual gap remains.

## Manifest output: `export` CLI mode, YAML serializer, `yaml.Marshal`

Supported (B5). `kue export [--out yaml|json] [file]` is a `cue export` -style mode that
manifests then serializes; the bare eval path (`kue
< file` / `kue file…` / `kue eval …` → internal `formatValue`) is unchanged. Default `--out` is **json** (matches `cue export`). Reads a file arg or stdin. A parse error exits 1 with the positioned diagnostic; a non-concrete/contradictory value exits 1 with `kue: export error: <reason>
`; a bad/missing ` --out` value exits 2 (usage error). `export` is one arm of the
subcommand dispatcher (`Kue/Cli.lean`) alongside `eval` /`version`/`help` — see the CLI
surface entry in "Parser and CLI scope".

- **JSON (`--out json` / default)** is pretty-printed: 4-space indent, source-order keys,
  `": "` separators, trailing newline — `valueToJsonPretty` in `Kue/Json.lean`, distinct
  from B6's compact `manifestToJson` (used by `json.Marshal`). Oracle-matched
  byte-for-byte.
- **YAML (`--out yaml`)** is `Kue/Yaml.lean` 's total `manifestToYaml`, matching `cue` 's
  go-yaml v3 emitter on the **infra-relevant core**: 2-space block nesting; `- ` block
  sequences (a compound item's first line rides the `- ` introducer; nested lists →
  `- - 1`); `|-` block scalars for strings containing `\n` (chomped, indented under the
  key); empty `{}` / `[]` inline; bytes → base64 scalar. **Scalar quoting** reproduces
  cue's decision exactly, as the **union of the two layers cue actually composes**
  (`wouldParseAsNonString`, oracle-verified against `cue` v0.16.1): **double-quoted** iff
  the bare form would read back as something other than a string — (1) cue's
  `internal/encoding/yaml.shouldQuote`: a fixed YAML-1.1 legacy-token set (`y/Y n/N t/T
  f/F yes no on off true false null ~.inf.nan` and case variants — note this is the
  *enumerated* set, NOT general case-insensitivity: `tRuE` is a string) plus a
  conservative date/time/base60/`0x`-hex regex (`2024-13-40` quotes by regex even though
  it is not a valid date); **or** (2) go-yaml v3's emitter resolving it to a real
  int/float (decimal/`0b`/`0o`/`0x`, `_` -separated) or base60 float. The key consequence:
  a **multi-segment token is none of these** — `34.142.159.249`, `1.2.3`, `10.0.0.0/8`,
  `nginx:1.25`, `1.2.3.4` are not numbers, dates, or tokens, so they stay **bare**,
  matching cue (the old `yamlLooksNumeric` over-quoted them). **Single-quoted** when
  structurally unsafe but not ambiguous — a leading indicator
  (`,[]{}#&*!|>'"%@`-backtick), a leading `-` /`?`/`:` followed by a space, a `: `
  (colon-space) or ` #` (space-hash) anywhere, a trailing `:`, or leading/trailing/all
  space. Keys follow the same string rule (so a `f` /`n` key is quoted). A top-level
  scalar emits the bare scalar; a top-level list emits a YAML sequence.
- **`yaml.Marshal(value)`** routes via the `yaml.` dotted dispatch (shared
  `unresolvedOrBottom` / `isPendingArg`, same shape as `json.Marshal`); it manifests then
  emits the YAML document **with a trailing newline** (oracle-confirmed framing).
  Incomplete → bottom; unresolved-ref form preserved.
- **No `---` multi-document streams.** Oracle-confirmed (`cue` v0.16.1):
  `cue export --out yaml` of a top-level list produces a single YAML sequence, NOT `---`
  -separated documents; cue emits `---` framing only through `yaml.MarshalStream`. So Kue
  emits no `---`, and `yaml.MarshalStream` is **deferred**. (The B5 plan note
  hypothesizing `---` for top-level lists was wrong — the oracle corrected it; this is
  cue-correct behavior, not a `cue-divergence`.)
- **Deferrals (Kue-does-less, not cue defects):** `-e` /`--expression` sub-expression
  selection (export currently serializes the whole evaluated root); `yaml.MarshalStream` /
  `yaml.Unmarshal` / `yaml.Validate` / `yaml.ValidatePartial`; and the exotic go-yaml
  scalar/layout surface Kue does not reproduce — flow style (`{a: 1}` inline), anchors and
  aliases, complex/non-string keys, line folding/column-width wrapping, the `>` folded
  block style, and sexagesimal number detection (cue's go-yaml v3 treats `1:2:3` as a bare
  string, which Kue matches). A top-level bare scalar or list **literal** as a whole
  source file is a pre-existing parser limitation (top level must be a field set), not an
  export-mode gap.

## Registry config and module → OCI-ref resolution (`CUE_REGISTRY`, B3d-1)

`Kue/Registry.lean` ports the OCI-tooling layer that maps a `CUE_REGISTRY` config + a module
path + version to an OCI location (host, secure-flag, repository, tag), purely and offline.
This is **cue tooling, not the CUE language spec** — so cue v0.16.1's own source IS the
reference here (`internal/mod/modresolve/resolve.go`, `mod/modconfig/modconfig.go`,
`mod/module/escape.go`, `mod/modcache/cache.go`), and Kue conforms to it exactly.

- **Default.** Empty/unset `CUE_REGISTRY` → the Central Registry host `registry.cue.works`
  for all modules, secure.
- **Simple syntax.** A comma-separated, order-independent list. A bare entry is a catch-all
  registry; a `prefix=registryspec` entry routes modules under that module-path prefix.
  A registry spec is `host` / `host:port` / `[::1]:5000`, with an optional `/repository`
  path-prefix (all routed modules stored under it) and an optional `+secure`/`+insecure`
  suffix. Default security: insecure for `localhost` / `127.0.0.1` / `::1`, secure
  otherwise.
- **`none`.** A global `none` or `prefix=none` resolves to "no registry" — a fetch under it
  must fail (modelled as `Resolution.noRegistry`, distinct from any host).
- **Prefix matching.** Longest match wins, on COMPLETE path elements only: `foo.example/bar`
  matches `foo.example/bar/x` but NOT `foo.example/barry`. An exact `prefix == path` wins
  outright. Duplicate identical prefixes (and a duplicate catch-all) are config errors.
- **Repository + tag.** The OCI repository is the registry path-prefix joined with the
  **UNESCAPED** base module path (Go `path.Join`), and the tag is the **plain full version**
  (`v0.3.19`). The `@<major>` suffix on a module path (`prodigy9.co/defs@v0`) is the major
  version — stripped for the repo, while the OCI tag carries the full version. Confirmed
  against cue source: `ResolveToLocation` does NOT escape the repository; `EscapePath`/
  `EscapeVersion` (the `!`-lowercasing in `escape.go`) apply ONLY to the on-disk
  download/extract cache directory layout (`modcache/cache.go`), which Kue also models for a
  later slice.

**DEFERRED — the `file:` / `inline:` config kinds and the full CUE-syntax config-file form.**
`CUE_REGISTRY` may carry a `file:<path>` / `inline:<cue>` kind prefix selecting a richer
config file (the `#File` schema: `moduleRegistries` / `defaultRegistry` with `pathEncoding`
=`path`/`hashAsRepo`/`hashAsTag`, `stripPrefix`, `prefixForTags`). Kue implements **only the
simple comma-separated syntax** (the `simple:` kind, or a bare value). The
hash/strip/tag-prefix encodings and the file/inline kinds are not yet implemented; a config
that requires them is out of B3d-1 scope. (`modconfig.go` handles the kind split upstream;
the simple parser receives the post-`simple:`-strip string.)

## OCI image-manifest parsing (B3d-2)

`Kue/Oci.lean` parses a CUE module's OCI image manifest
(`application/vnd.oci.image.manifest.v1+json`) into typed descriptors — purely and offline
(`String → Except String OciManifest`). This is OCI-tooling protocol, NOT the CUE language
spec, so the authority is cue's own `mod/modregistry/client.go` (v0.16.1), conformed to
exactly. Reuses Lean's standard `Lean.Json.parse` (`Kue/Json.lean` only serializes — there is
no second JSON parser).

- **Module identity.** A manifest is a CUE module iff `config.mediaType ==
  "application/vnd.cue.module.v1+json"` (cue's `isModule`). A differing config mediaType yields
  a typed "not a module manifest" error, never a silent accept.
- **Layers.** A well-formed module manifest has exactly TWO layers: the module zip
  (`application/zip`) and `cue.mod/module.cue` (`application/vnd.cue.modulefile.v1`). cue
  constructs them as `layers[0]`/`layers[1]` and validates by index. **Kue selects each layer
  BY mediaType and requires exactly one match** (`moduleZipDescriptor` / `moduleFileDescriptor`
  error on an absent OR duplicated layer) — strictly stronger than cue's blind indexing, still
  accepting every well-formed manifest cue produces, and never silently picking the first of an
  ambiguous pair. `validateModuleManifest` additionally enforces the exactly-two-layers and
  `isModule` invariants with cue's error phrasing.
- **Descriptors.** Each `Descriptor` carries `mediaType`, the `sha256:<hex>` `digest`
  (preserved VERBATIM for B3d-4's `Sha256.digestString blob == digest` check), and `size`. A
  manifest that omits any field is a parse error, not a zero/empty placeholder.
- **Not retained.** `schemaVersion` and the manifest-level `mediaType` are parsed-over but not
  kept — they are not load-bearing for descriptor extraction and cue never re-checks
  `schemaVersion`. Manifest `annotations` (module metadata) are likewise out of scope here;
  B3d does not yet consume them.

## SHA-256 + `cue.sum` `h1:` dirhash (B3d-3)

`Kue/Sha256.lean` provides a total, IO-free SHA-256 (FIPS 180-4) and the Go
`golang.org/x/mod/sumdb/dirhash` `Hash1` ("h1:") algorithm. These are NOT in the CUE
language spec — SHA-256 is a published standard (FIPS 180-4) and dirhash is module-tooling
protocol — so the authority is FIPS 180-4 + the Go source, conformed to exactly. Now
AVAILABLE (was a hard capability gap — kue had no crypto before this slice):

- **Digest verification.** `digestString bytes = "sha256:" ++ hex (sha256 bytes)` reproduces
  OCI's `digest.FromBytes` (`mod/modregistry/client.go`); B3d-4 verifies a downloaded
  manifest/blob against its descriptor `digest`.
- **`cue.sum` `h1:`.** `hash1 : List (String × ByteArray) → String` reproduces `Hash1` over
  in-memory `(name, contents)` files (byte-order name sort, per-file
  `lowerhex(sha256(contents)) ++ "  " ++ name ++ "\n"`, outer SHA-256, `"h1:" ++ base64Std`).
  The std-base64 step reuses the `encoding/base64` builtin's encoder (`Kue.base64Encode`).

**Module-zip entry naming (pinned protocol fact).** cue's `modzip.Create`
(`mod/modzip/zip.go`) stores zip entries under their BARE module-root-relative slash path
(`cue.mod/module.cue`, `foo.cue`) — NOT prefixed `<module>@<version>/` like Go's own modzip.
So the dirhash `name` is the raw zip-entry path. `hash1` is name-agnostic; the zip reader
(B3d-4) supplies entry names verbatim.

**DEFERRED — the zip-reading IO edge.** `hash1` operates on already-in-memory `(name,
contents)` pairs; reading a module zip into that list is the IO edge, B3d-4. cue v0.16.1
itself relies on OCI blob-digest verification rather than writing a `cue.sum` in its embedded
source path; `h1:` here serves verification of the `cue.sum` format `cue mod` produces.

## OCI fetch over a `curl` subprocess (B3d-4)

`Kue/OciFetch.lean` is the IO edge that GETs a module's OCI manifest + blobs off a registry,
over a `curl` subprocess (decision
`docs/decisions/2026-06-25-registry-fetch-via-curl-subprocess.md`). The protocol is the OCI
Distribution Spec v1.1, conformed to cue's own client (`cuelabs.dev/.../ociregistry/ociclient`
+ `mod/modregistry/client.go`, v0.16.1) — tooling, not the CUE language spec, so the Go code is
the authority. Pure URL/argv builders live in `Kue/Oci.lean`; the impure runner is the only
`IO.Process` user in the codebase.

- **Endpoints used.** Manifest GET `<scheme>://<host>/v2/<repository>/manifests/<tag>`; blob GET
  `<scheme>://<host>/v2/<repository>/blobs/<digest>`. `<scheme>` is `http` for an insecure
  (loopback / `+insecure`) registry, `https` otherwise. `<repository>`/`<tag>` come from
  `Registry.resolve` (B3d-1); the tag is the plain version.
- **Manifest `Accept` header.** A manifest GET offers cue's `knownManifestMediaTypes` (OCI image
  manifest + index, the deprecated artifact type, three docker manifest types, `*/*`) as one
  `-H "Accept: <type>"` per type — some registries withhold the body without an explicit
  `Accept`. A blob GET sends no `Accept` (content-addressed by digest).
- **curl flags (fail-loud).** `-sSL --fail-with-body`: silent-but-show-errors, follow redirects
  (registries 307 a blob to object storage), and exit non-zero on a non-2xx HTTP status while
  still surfacing the error body. An HTTP error is a Lean `Except.error`, never an empty success.
- **Integrity gate.** A fetched blob is REJECTED unless `Sha256.digestString bytes ==
  descriptor.digest` (B3d-3's verifier). A corrupt/tampered/wrong-content blob is an error.
- **Byte fidelity.** stdout is captured as RAW bytes (`spawn` + `readBinToEnd`), not via
  `IO.Process.output` (which UTF-8-decodes and would corrupt a binary zip).

**Verification.** The whole curl composition is offline-tested against `file://` fixtures
(`testdata/ocifetch/`, driven by `scripts/check-ocifetch.lean` under `check-fixtures.sh`),
including digest-mismatch rejection. The live HTTPS fetch from `registry.cue.works` is
human-gated (network egress is outside the AFK envelope) and logged in `.afk.log`.

**DEFERRED.**
- **Registry auth / login.** The fetch assumes anonymous access (the Central Registry serves
  public modules without a token). The Bearer-token `WWW-Authenticate` challenge/response flow,
  `cue login`, and credential stores are NOT implemented — a private/authenticated registry is
  out of scope until B3d-6.
- **Tag listing for MVS.** `GET /v2/<repo>/tags/list` (version enumeration for MVS version
  *solving*) is NOT implemented here; B3d-4 fetches a known `<tag>`. Version solving is B3d-6.
- **Resolver wiring.** B3d-4 only provides the fetch capability; replacing `Module.lean`'s
  `registry fetch is B3d` error with resolve → fetch → verify → cache-write → extract is B3d-5.

## ZIP extraction + DEFLATE inflate (B3d-5z)

`Kue.Zip.readZip : ByteArray → Except String (List (String × ByteArray))` is the PURE transform
of a verified module-zip's bytes into in-memory `(name, contents)` entries. It is pure Lean
(`Kue/Inflate.lean` for RFC 1951 inflate, `Kue/Zip.lean` for the PKWARE container + CRC-32), NOT
an `unzip` subprocess — the curl GET is the sole impurity in the fetch path.

- **Authoritative entry list = the Central Directory.** The reader parses the End-Of-Central-
  Directory record (backward scan, since the trailing comment is variable-length) and walks the
  Central Directory for each entry's name / method / CRC-32 / compressed+uncompressed sizes /
  local-header offset. Local file headers are NOT trusted for sizes (streaming writers defer them
  to a data descriptor); the local header is re-read only for its name+extra lengths to locate the
  compressed-data start.
- **Compression methods.** STORED (method 0) and DEFLATE (method 8) — the only methods cue's
  `mod/modzip` emits (every cue module-zip entry is observed DEFLATE, `Defl:N`). The method is a
  closed `Method` sum (`stored`/`deflate`); any OTHER central-directory method is a typed
  `Except.error` at parse time — NEVER a silent skip. (No cue module zip uses any other method;
  if one ever does, kue errors loudly rather than dropping the entry.)
- **Integrity gate.** Each extracted entry's uncompressed bytes are verified against the
  central-directory CRC-32 (poly `0xEDB88320`, the zip standard) AND the declared uncompressed
  size; a mismatch is a typed error, like B3d-4's blob-digest gate. A corrupt/tampered entry is
  rejected, never returned.
- **Directory entries skipped.** Entries with an empty name or a trailing `/` are omitted from
  the result, exactly as cue's own `mod/modzip` `Unzip` does (`name == "" || strings.HasSuffix(name,
  "/")`). `readZip` returns files only, in central-directory order. Entry names are the bare
  module-root-relative slash paths (no `<module>@<version>/` prefix — cue's modzip convention,
  B3d-3), so they feed `hash1` verbatim.
- **DEFLATE coverage.** All three RFC 1951 block types (STORED, fixed Huffman, dynamic Huffman),
  LZ77 back-references with overlapping copies, and the full §3.2.5 length/distance tables are
  implemented. There is no support for ZIP64 (entries ≥ 4 GiB or > 65535 entries), encryption, or
  the legacy `Implode`/`Shrink`/etc. methods — none occur in a cue module zip; each surfaces as a
  typed error (a ZIP64 archive's 16-bit EOCD count/offset would be `0xFFFF`/`0xFFFFFFFF` sentinel
  values, which the current reader does not chase to the ZIP64 EOCD — deferred until a real cue
  module zip needs it, which is not expected since module zips are small).
