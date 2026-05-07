# Kue Compatibility Assumptions

This file records deliberate compatibility assumptions made while CUE behavior is still
being modeled. Each item should be testable and replaceable by a narrower semantic slice.

## Basic Parser and CLI

The first parser is a syntax layer over Kue's existing semantic core, not a full CUE
front end. It exists so real source snippets can flow through the same resolver and
evaluator that fixture ports use.

Current assumptions:

- `package` clauses are accepted and otherwise ignored by the source parser. Explicit
  CLI file arguments are merged by unifying their parsed package bodies; mismatched
  package names are rejected, and package-less files can merge with named packages.
  Imports are not modeled yet.
- Top-level fields are parsed into one open struct. References are resolved with the
  current same-struct binding resolver.
- Unsupported source forms generally fail with a parse error instead of being
  approximated. This parser is not a complete CUE syntax validator yet.
- Separator handling is currently permissive around whitespace. A later parser slice
  should implement CUE's newline and semicolon insertion rules directly.
- The parser supports the language forms already backed by semantic values: scalars,
  primitive kinds, structs, lists, refs, `&`, `|`, defaults, integer bounds, primitive
  exclusions, regex constraints, field pattern constraints, list ellipses, byte literals,
  struct embeddings, untyped struct ellipses, static field aliases, `let` declarations,
  and existing builtin call values.
- Struct embeddings are lowered to conjunctions with the declared fields. This is a
  useful executable model for schema composition, but it is not yet a full embedding
  validator for every non-struct expression shape.
- Duplicate fields are merged after reference evaluation when their field classes have
  an existing merge rule. Unsupported same-label class combinations are kept distinct
  in this pass; diagnostic provenance and output ordering are still first-pass.
- Untyped struct ellipses are represented as `.structTail` values with a top tail. Typed
  struct tails remain semantic-only because the pinned CUE v0.15.4 tool rejects
  `...T` source syntax.
- `let` declarations are represented as non-output binding fields inside the same
  ordered field list as regular fields. This supports ordinary top-level and nested
  references, but duplicate names between `let` bindings and fields still follow Kue's
  current first-binding resolver instead of a complete lexical binding graph.
- Static field aliases such as `A="label": value` are represented as non-output binding
  fields that refer to the aliased field label. Other alias positions are still
  unsupported.
- The parser does not yet support imports, non-field aliases, comprehensions, dynamic
  fields, string interpolation, full numeric literal syntax, or typed struct ellipsis
  syntax.
- Multiple pattern fields are represented as independent pattern constraints. Label
  pattern values are still limited to the existing string-kind, exact-string, and
  supported regex subset.
- Nested structs resolve same-struct references with local binding ids. References that
  fall through to an enclosing struct remain label-based during evaluation until binding
  ids can carry explicit scope identity.
- The executable reads CUE from stdin or from explicit file arguments and prints
  resolved/evaluated Kue output. Empty stdin still prints the existing semantic smoke
  output for quick build checks.

Rationale: this keeps language compliance work tied to executable semantics while
avoiding a large parser detour before the core value model can express those forms.
