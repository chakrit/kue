# byte-literal-interpolation

- **Source:** conformance probe 2026-07-04 (string-interpolation / regexp / encoding sweep),
  minimal synthetic repro.
- **CUE construct at fault:** interpolation `\(expr)` inside a BYTE literal (`'...'`). The
  interpolation must evaluate the hole and splice its byte form; `'\(1)'` is the byte string
  `1` (0x31).
- **Spec basis (kue is WRONG, cue is right):** CUE interpolation applies in both string and
  byte literals. `cue export` → `{ "a": "MQ==" }` (base64 of the one byte `0x31`). kue's byte
  lexer never recognizes the `\(` interpolation opener in a byte literal — it treats `\(` as a
  literal `(` and emits the raw bytes `(1)` (`KDEp`). Parser-level (byte-literal lexing), not an
  evaluator fault; separate from the string-interpolation operand-typing fix landed alongside
  this seed. No `cue-divergences.md` entry — cue agrees with the spec.
- **Status:** RED-SEEDED (`.known-red`) 2026-07-04, captured-not-fixed. Fix belongs to a
  byte-literal-lexing slice (see also `byte-literal-hex-escape`).
