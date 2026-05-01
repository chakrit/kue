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
  exclusions, regex constraints, and existing builtin call values.
- The parser does not yet support imports, aliases, `let`, embeddings, comprehensions,
  dynamic fields, string interpolation, full numeric literal syntax, byte literals,
  field pattern syntax, or ellipsis syntax.
- The executable reads CUE from stdin and prints resolved/evaluated Kue output. Empty
  stdin still prints the existing semantic smoke output for quick build checks.

Rationale: this keeps language compliance work tied to executable semantics while
avoiding a large parser detour before the core value model can express those forms.
