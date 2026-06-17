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

- `package` clauses are accepted and otherwise ignored by the source parser. Explicit
  CLI file arguments are merged by unifying their parsed package bodies; mismatched
  package names are rejected, and package-less files can merge with named packages.
  Imports are not modeled yet.
- Top-level fields are parsed into one open struct. References are resolved with the
  current same-struct binding resolver.
- Unsupported source forms generally fail with a parse error instead of being
  approximated. This parser is not a complete CUE syntax validator yet.
- Parse errors carry a source position. Every error records the remaining-suffix length
  at the failure point; `parseSource` converts that to a 1-based `line`/`column` (via a
  total `offsetToLineColumn` walk over the source) stored on `ParseError` alongside the
  raw `message`. The CLI prints `kue: parse error: <line>:<col>: <message>` (CUE-style
  `line:col`). Package-clause conflicts (rare, non-cursor errors) report at `1:1`.
- Separator handling is currently permissive around whitespace. A later parser slice
  should implement CUE's newline and semicolon insertion rules directly.
- The parser supports the language forms already backed by semantic values: scalars,
  primitive kinds, structs, lists, refs, `&`, `|`, defaults, integer bounds, primitive
  exclusions, regex constraints, field pattern constraints, list ellipses, byte literals,
  struct embeddings, untyped struct ellipses, static field aliases, value-position
  aliases (`label: X=value`, incl. `#Def: Self={…}` self-reference), `let` declarations,
  static field selectors, static index expressions, existing builtin call values,
  comprehensions (`for`/`if` field clauses), dynamic fields (`(expr): v`), string
  interpolation (`"\(expr)"`), colon-shorthand nested fields (`a: b: c: 1`,
  desugared to the brace form `a: {b: {c: 1}}` — same AST, so it unifies/closes/exports
  identically; inner labels may be identifiers, definitions, quoted strings, or `(expr)`
  dynamic, each with optional `?`/`!` markers), and multiline string/bytes literals
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
  also rejects) or imports with module resolution. Value-position aliases are now
  supported (see References, bindings, and selectors below).
- The executable reads CUE from stdin or from explicit file arguments and prints
  resolved/evaluated Kue output. Empty stdin still prints the existing semantic smoke
  output for quick build checks.

## Structs, embeddings, and patterns

- Struct embeddings are lowered to conjunctions with the declared fields. This is a
  useful executable model for schema composition, but it is not yet a full embedding
  validator for every non-struct expression shape.
- Duplicate fields are merged after reference evaluation when their field classes have
  an existing merge rule. Unsupported same-label class combinations are kept distinct
  in this pass; diagnostic provenance and output ordering are still first-pass.
- Untyped struct ellipses are represented as `.structTail` values with a top tail. Typed
  struct tails remain semantic-only because the pinned CUE v0.15.4 tool rejects
  `...T` source syntax.
- Multiple pattern fields are represented as independent pattern constraints. Label
  pattern values are still limited to the existing string-kind, exact-string, and
  supported regex subset.

## Numeric literals

- Decimal numeric separators are stripped while parsing. Exponent literals are accepted
  as float strings with normalized exponent signs, but Kue does not yet canonicalize all
  exponent arithmetic the way `cue eval` does.
- Lowercase non-decimal integer literals with `0x`, `0o`, and `0b` prefixes are
  canonicalized to decimal integers while parsing. Separators are accepted in their digit
  sequences.
- CUE's decimal numeric suffix multipliers `K`, `M`, `G`, `T`, `P` and binary suffixes
  `Ki`, `Mi`, `Gi`, `Ti`, `Pi` are accepted on decimal integer and decimal fraction
  literals when the multiplied result is exactly representable as an integer. Inexact
  suffix products fail during parsing, matching `cue eval`.

## Arithmetic expressions

- Unary numeric `+` and `-` are represented explicitly for non-literal operands.
  Concrete integer operands and float spelling strings evaluate now. Incomplete numeric
  operands remain residual unary expressions until invalid operand diagnostics are
  modeled.
- Additive expressions are represented explicitly. The evaluator currently handles
  concrete integer addition/subtraction plus concrete string and byte concatenation.
  Finite decimal float addition/subtraction is evaluated exactly with scaled integer
  arithmetic, including exponent spellings. List arithmetic is not targeted for `+`
  because CUE v0.15.4 rejects it in favor of `list.Concat`.
- Multiplication expressions are parsed with higher precedence than additive
  expressions. Concrete integer multiplication yields an int. Float multiplication
  (and mixed int×float, which promotes to float) is evaluated exactly through the
  `Decimal` module: numerators multiply and scales add, and CUE preserves the summed
  scale verbatim with no trailing-zero trim (`1.0 * 1.0 = 1.00`, `1.5 * 2.0 = 3.00`).
  Oracle-confirmed against cue v0.16.1.
- Division expressions are parsed at the same precedence as multiplication. `/` always
  yields a float, never an int (`4.0 / 2.0 = 2.0`, `6 / 2 = 3.0`); integer division is
  the separate `div`/`quo` keywords. All four operand domains (int÷int, int÷float,
  float÷int, float÷float) route through one `Decimal` divider. Terminating quotients
  render exactly (`1.0 / 4.0 = 0.25`); non-terminating quotients render at **34
  significant digits** (apd context, matching cue v0.16.1) with round-half-up on the
  guard digit. Round-half-up vs apd's nominal `ROUND_HALF_EVEN` is unobservable here:
  a rational repeating expansion never produces an exact tie, so the guard digit alone
  decides. Division by zero (any zero divisor, int or float) bottoms out with
  `divisionByZero` provenance. No documented division case remains deferred — the prior
  fixed-34-fractional-digit int divider, which over-emitted for quotients ≥ 1, was
  replaced by the shared significant-digit divider as part of this slice.
- Integer keyword expressions `div`, `mod`, `quo`, and `rem` are parsed at
  multiplicative precedence and reuse the existing integer builtin semantics. Concrete
  integer operands evaluate now; incomplete operands remain as residual infix binary
  expressions.

## Comparison and logical expressions

- Equality expressions `==` and `!=` are parsed after additive/multiplicative
  expressions. The evaluator currently handles concrete primitive equality and numeric
  equality across int/float spellings. Equality over incomplete values and compound
  values remains later work.
- Ordering expressions `<`, `<=`, `>`, and `>=` are parsed at the same comparison
  precedence as equality. The evaluator currently handles concrete numeric and string
  operands. Mixed-kind ordering bottoms out; ordering over bytes, incomplete values, and
  compound values remains later work.
- Binary regex match expressions `=~` and `!~` are parsed at comparison precedence.
  The evaluator currently handles concrete string operands using Kue's existing regex
  subset. Non-string concrete primitive operands bottom out; incomplete operands remain
  residual binary expressions.
- Logical expressions `&&` and `||` are parsed above CUE unification/disjunction and
  below equality/ordering comparison precedence. The evaluator currently handles
  concrete boolean operands only. CUE rejects incomplete logical operands as invalid;
  Kue keeps them as residual binary expressions until diagnostic modeling exists.
- Logical negation `!` is represented as a residual unary expression when its operand
  is incomplete. Concrete boolean operands evaluate to concrete booleans, and concrete
  non-boolean primitive operands bottom out.

## References, bindings, and selectors

- `let` declarations are represented as non-output binding fields inside the same
  ordered field list as regular fields. This supports ordinary top-level and nested
  references, but duplicate names between `let` bindings and fields still follow Kue's
  current first-binding resolver instead of a complete lexical binding graph.
- Static field aliases such as `A="label": value` are represented as non-output binding
  fields that refer to the aliased field label.
- **Value-position aliases** such as `label: X=value` (esp. `#Def: Self={…}`) are
  supported. The alias is visible within the value it labels and refers to the whole
  value — oracle-confirmed against `cue` v0.16.1: an alias is **not** visible to siblings
  or the enclosing struct, only inside its own value and that value's descendants. For a
  struct value, a non-output `let`-binding (`.letBinding`) named by the alias is prepended
  to the struct's fields with the value `.thisStruct`; a `Self.field` selector on that
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
    the residual `@self` rather than a value; `cue` rejects it as a structural cycle.
    The load-bearing prod9 pattern is always `Self.field` (a selector), never bare `Self`,
    so this is left as a documented boundary.
  - **Permissiveness note (not a divergence):** `cue` rejects an *unreferenced* value
    alias as a hard error (`unreferenced alias or let clause X`); Kue accepts it and emits
    the value. This is consistent with Kue's standing permissive stance (cf. separators)
    and is a Kue-does-less boundary, not a `cue` defect, so it is not in
    `docs/reference/cue-divergences.md`. A scalar alias (`a: X="hi"`) is therefore always
    "unreferenced" by `cue`'s rule but evaluates fine in Kue.
- Static field selectors such as `base.inner` are represented explicitly and evaluate
  declared fields on evaluated structs. Static index expressions such as `xs[1]` and
  `base["inner"]` evaluate concrete integer list indices and concrete string field
  indices after resolving the base and key expressions. Missing string field indices
  remain incomplete index values, and open-list tail indices beyond the fixed prefix also
  remain incomplete. Invalid closed-list indices bottom out with first-pass structural
  provenance only; richer index diagnostics and non-field dynamic selection remain later
  work.
- Nested structs resolve same-struct references with local binding ids. References that
  fall through to an enclosing struct remain label-based during evaluation until binding
  ids can carry explicit scope identity.

## String case folding (`ToUpper` / `ToLower` / `ToTitle`)

- **ASCII-only case mapping; non-ASCII passes through unchanged.** `strings.ToUpper`,
  `strings.ToLower`, and `strings.ToTitle` map only the ASCII letter range (`A`–`Z` ↔
  `a`–`z`); every non-ASCII rune is emitted byte-for-byte unchanged. Lean's
  `Char.toUpper`/`toLower` are themselves ASCII-only, so this is the natural total-function
  boundary — no `partial`, no Unicode case-table dependency. The boundary is deliberate and
  documented rather than silent: ASCII inputs are exactly oracle-faithful to `cue` v0.16.1;
  non-ASCII inputs diverge in a single, predictable way (see below).
- **Why passthrough, not bottom.** Passthrough keeps the ASCII domain 100% correct while
  staying total over the full string space, consistent with the rest of the string builtins
  (`Index`/`Count`/`Split` are byte-faithful, never bottoming on non-ASCII). Bottoming on
  any non-ASCII rune would make a large class of otherwise-valid strings unusable for an
  internal limitation. This is a deferred-capability boundary (Kue does *less* than `cue`
  here), not a `cue` defect, so it is documented here and not in
  `docs/reference/cue-divergences.md` (which records only cases where `cue` is wrong and
  Kue is right).
- **`ToTitle` is per-word capitalization, NOT "upper-case every letter".** Oracle-confirmed
  (`cue` v0.16.1): `strings.ToTitle` upper-cases the first character of each
  **whitespace-delimited** word (`unicode.IsSpace` separator) and leaves the rest of each
  word untouched — it is NOT Go's `strings.ToTitle` (which upper-cases all letters), and the
  word separator is whitespace ONLY. `-`, `.`, `_`, `/`, digits, and other punctuation do
  NOT start a new word: `ToTitle("a-b a.b")` → `"A-b A.b"`. The ASCII whitespace set covered
  is the six runes `\t \n \v \f \r` and space; non-ASCII whitespace (e.g. NBSP) is treated as
  a non-separator (deferral boundary), so it does not trigger title-casing.
- **Divergence summary (Kue vs `cue` v0.16.1), all non-ASCII only:**
  - `ToUpper("café")` → Kue `"CAFé"`, cue `"CAFÉ"`.
  - `ToLower("CAFÉ")` → Kue `"cafÉ"`, cue `"café"`.
  - `ToTitle("über alles")` → Kue `"über Alles"`, cue `"Über Alles"`.
- **Lifting the boundary later** means a Unicode case-mapping table (mirroring Go's
  `unicode.ToUpper`/`ToLower`/`ToTitle` and `x/text/cases`), including locale-insensitive
  full-case-folding edge cases (German ß, Turkish dotless ı, title-case digraphs). Until
  then this is an alpha boundary alongside imports and `list.Sort`.

## Encoding builtins (`base64.Encode`, `json.Marshal`)

Supported. Both dispatch on the dotted builtin name (`import "encoding/base64"` /
`import "encoding/json"` parsed-and-ignored, like the other families). The JSON
serializer lives in the reusable `Kue/Json.lean` (`manifestToJson`), shared with B5.

- **`base64.Encode(encoding, data)` supports only the `null` encoding** —
  standard padded base64 (RFC 4648, `base64.StdEncoding`) over the UTF-8 bytes of a
  string or bytes payload. Oracle-confirmed (`cue` v0.16.1): `null` selects standard
  padding; any non-null encoding selector is an error (`cue`: "base64: unsupported
  encoding: cannot use value … as null"), so Kue resolves it to bottom. Encoding over a
  string uses its UTF-8 bytes (`"héllo"` → `"aMOpbGxv"`), identical to encoding the
  equivalent bytes value. **Deferred:** non-null encodings (`base64.URLEncoding` etc.)
  and `base64.Decode` (no error/bytes-result path for malformed input yet). Kue-does-less
  boundary, not a `cue` defect.
- **`json.Marshal(value)` produces compact JSON byte-for-byte matching `cue`.**
  Oracle-confirmed (`cue` v0.16.1): object keys are emitted in **source/insertion order,
  NOT sorted** (`{b,a,c}` → `{"b":…,"a":…,"c":…}`); separators are `,` and `:` with no
  spaces; floats render from their exact stored decimal text verbatim (`1.0`→`"1.0"`,
  `1.50`→`"1.50"`, `0.1`→`"0.1"`); a bytes value marshals to a base64 JSON string (Go
  `[]byte` semantics); control characters below `0x20` escape as `\b\f\n\r\t` or
  `\uXXXX`; `<`, `>`, `&`, `/` and all non-ASCII runes pass through verbatim — `cue`
  disables Go's default HTML-escaping (this is `cue`'s documented behavior, not a defect,
  so it is NOT a `cue-divergence`). The value is manifested first, so defaults and
  incompleteness rules apply: an incomplete or contradictory value (e.g. `{a: int}`) is
  bottom (`cue` errors "cannot convert incomplete value … to JSON"). An argument that is
  still an unresolved reference form (`.ref`/`.selector`/`.index`/`.builtinCall`) is
  preserved as an unresolved `.builtinCall` so a later evaluation pass can complete it.
  **Deferred:** `json.MarshalStream` (multi-doc), `json.Indent` (pretty-printing),
  `json.Unmarshal`/`json.Validate` (parsing).
- **Composition note (infra docker-config).** The prod9/infra
  `base64.Encode(null, json.Marshal({auths: …}))` chain evaluates correctly when the
  inner struct's fields resolve. The real `infra-defs/secret.cue` use references a
  **hidden** field (`_auths`); hidden-field references do not yet resolve in Kue (a
  pre-existing reference-resolution gap, separate from B6 — `y: _a` where `_a` is hidden
  → bottom, while `cue` resolves it), and `secret.cue` is additionally still blocked at
  the non-string label-pattern parser gap (`[string]: string`). The encoding builtins
  themselves are not the blocker.

## Manifest output: `export` CLI mode, YAML serializer, `yaml.Marshal`

Supported (B5). `kue export [--out yaml|json] [file]` is a `cue export`-style mode that
manifests then serializes; the existing no-flag CLI (`kue < file` / `kue file…` →
internal `formatValue`) is unchanged. Default `--out` is **json** (matches `cue export`).
Reads a file arg or stdin. A parse error exits 1 with the positioned diagnostic; a
non-concrete/contradictory value exits 1 with `kue: export error: <reason>`; a bad flag
exits 2.

- **JSON (`--out json` / default)** is pretty-printed: 4-space indent, source-order keys,
  `": "` separators, trailing newline — `valueToJsonPretty` in `Kue/Json.lean`, distinct
  from B6's compact `manifestToJson` (used by `json.Marshal`). Oracle-matched byte-for-byte.
- **YAML (`--out yaml`)** is `Kue/Yaml.lean`'s total `manifestToYaml`, matching `cue`'s
  go-yaml v3 emitter on the **infra-relevant core**: 2-space block nesting; `- ` block
  sequences (a compound item's first line rides the `- ` introducer; nested lists →
  `- - 1`); `|-` block scalars for strings containing `\n` (chomped, indented under the
  key); empty `{}` / `[]` inline; bytes → base64 scalar. **Scalar quoting** reproduces
  cue's decision exactly for these cases: **bare** when safe; **double-quoted** when the
  plain form would be resolver-ambiguous — the YAML 1.1 bool/null tokens
  (`y n t f yes no on off true false null ~`, case-insensitive) and numeric-looking
  strings (decimal int/float with `_`/sign/exponent, `0b`/`0o`/`0x`, `.inf`/`.nan`);
  **single-quoted** when structurally unsafe but not ambiguous — a leading indicator
  (`,[]{}#&*!|>'"%@`-backtick), a leading `-`/`?`/`:` followed by a space, a `: `
  (colon-space) or ` #` (space-hash) anywhere, a trailing `:`, or leading/trailing/all
  space. Keys follow the same string rule (so a `f`/`n` key is quoted). A top-level
  scalar emits the bare scalar; a top-level list emits a YAML sequence.
- **`yaml.Marshal(value)`** routes via the `yaml.` dotted dispatch (shared
  `unresolvedOrBottom` / `isPendingArg`, same shape as `json.Marshal`); it manifests then
  emits the YAML document **with a trailing newline** (oracle-confirmed framing). Incomplete
  → bottom; unresolved-ref form preserved.
- **No `---` multi-document streams.** Oracle-confirmed (`cue` v0.16.1): `cue export
  --out yaml` of a top-level list produces a single YAML sequence, NOT `---`-separated
  documents; cue emits `---` framing only through `yaml.MarshalStream`. So Kue emits no
  `---`, and `yaml.MarshalStream` is **deferred**. (The B5 plan note hypothesizing `---`
  for top-level lists was wrong — the oracle corrected it; this is cue-correct behavior,
  not a `cue-divergence`.)
- **Deferrals (Kue-does-less, not cue defects):** `-e`/`--expression` sub-expression
  selection (export currently serializes the whole evaluated root); `yaml.MarshalStream`
  / `yaml.Unmarshal` / `yaml.Validate` / `yaml.ValidatePartial`; and the exotic go-yaml
  scalar/layout surface Kue does not reproduce — flow style (`{a: 1}` inline), anchors and
  aliases, complex/non-string keys, line folding/column-width wrapping, the `>` folded
  block style, and sexagesimal number detection (cue's go-yaml v3 treats `1:2:3` as a
  bare string, which Kue matches). A top-level bare scalar or list **literal** as a whole
  source file is a pre-existing parser limitation (top level must be a field set), not an
  export-mode gap.
