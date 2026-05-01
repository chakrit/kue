# Kue Compatibility Assumptions

This file records deliberate compatibility assumptions made while CUE behavior is still
being modeled. Each item should be testable and replaceable by a narrower semantic slice.

## Basic Parser and CLI

The first parser is a syntax layer over Kue's existing semantic core, not a full CUE
front end. It exists so real source snippets can flow through the same resolver and
evaluator that fixture ports use.

Current assumptions:

- `package` clauses are accepted and ignored. Package identity, imports, and multi-file
  merging are not modeled yet.
- Top-level fields are parsed into one open struct. References are resolved with the
  current same-struct binding resolver.
- Unsupported source forms generally fail with a parse error instead of being
  approximated. This parser is not a complete CUE syntax validator yet.
- Separator handling is currently permissive around whitespace. A later parser slice
  should implement CUE's newline and semicolon insertion rules directly.
- The parser supports the language forms already backed by semantic values: scalars,
  primitive kinds, structs, lists, refs, `&`, `|`, defaults, integer bounds, primitive
  exclusions, regex constraints, field pattern constraints, list ellipses, byte literals,
  struct embeddings, and existing builtin call values.
- Struct embeddings are lowered to conjunctions with the declared fields. This is a
  useful executable model for schema composition, but it is not yet a full embedding
  validator for every non-struct expression shape.
- The parser does not yet support imports, aliases, `let`, comprehensions, dynamic
  fields, string interpolation, full numeric literal syntax, or struct ellipsis syntax.
- Multiple pattern fields parse through the current single-pattern semantic model. This
  preserves executable behavior but is not a final representation of independent CUE
  pattern constraints.
- Nested structs resolve same-struct references with local binding ids. References that
  fall through to an enclosing struct remain label-based during evaluation until binding
  ids can carry explicit scope identity.
- The executable reads CUE from stdin and prints resolved/evaluated Kue output. Empty
  stdin still prints the existing semantic smoke output for quick build checks.

Rationale: this keeps language compliance work tied to executable semantics while
avoiding a large parser detour before the core value model can express those forms.
