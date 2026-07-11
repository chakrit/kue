# block-comment-rejected  (lexer — CUE has no block comments)

- **Source:** found 2026-07-11 during the STDLIB test-drive (tour + cuetorials examples
  vs `cue` v0.16.1). Not a prod9 export — a directed exploration of parser leniency. kue
  ACCEPTED a C-style `/* */` block comment (exported `{"a":1,"b":2}`) that CUE's grammar
  does not admit. Landed as an ENFORCED fixture (green after the fix in the same slice),
  not quarantined.
- **CUE construct at fault:** a `/* */` block comment (`a: 1 /* c */`). CUE has no block
  comments — only `//` line comments.
- **Direction: OVER-ACCEPT** — kue parsed input the spec rejects.
- **Root cause (kue):** the trivia scanners (`skipTrivia`, `skipSameLineTrivia`,
  `fieldSeparatorAux` in `Kue/Parse.lean`) treated `/* … */` as whitespace via
  `dropBlockComment`. Fix: remove block-comment handling entirely — `/*` surfaces as a
  stray `/` (division) whose operand `*` is not a valid primary, so every position rejects
  with a `parse error: … unexpected character` (mirroring `cue`, which also has no
  block-comment concept and errors on the stray `/`). The `Kue/ModCmd.lean` module-file
  scanner's `.block` Lex state was likewise removed (module.cue is parsed by `parseSource`,
  which now rejects block comments before any textual scan runs).
- **Spec basis:** the CUE language spec (cuelang.org/docs/references/spec, § Comments)
  states: "CUE supports line comments that start with the character sequence `//` and stop
  at the end of the line." Block comments are not in the grammar. `cue` v0.16.1 rejects
  `a: 1 /* c */` with `expected operand, found '/'` (exit 1) — consistent with the spec.
