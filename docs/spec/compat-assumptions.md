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
  struct embeddings, untyped struct ellipses, static field aliases, `let` declarations,
  static field selectors, static index expressions, existing builtin call values,
  comprehensions (`for`/`if` field clauses), dynamic fields (`(expr): v`), and string
  interpolation (`"\(expr)"`).
- The parser does not yet support non-field aliases, typed struct ellipsis syntax
  (`...T`, which cue v0.15.4 also rejects), or imports with module resolution.
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
  fields that refer to the aliased field label. Other alias positions are still
  unsupported.
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
