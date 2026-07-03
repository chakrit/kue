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
- **Status:** RED-SEEDED (`.known-red`) 2026-07-04. STILL QUARANTINED after the
  BYTE-LITERAL-LEXING slice (2026-07-04) that decoded byte escapes and graduated
  `byte-literal-hex-escape`. Byte-context interpolation was deliberately deferred: it needs a
  distinct byte-interpolation carrier (the current `.interpolation` renders to a STRING and has
  no byte-context marker), which ripples a new `Value`-producing arm across ~20 match sites plus
  the digest/format/manifest paths — disproportionate to bundle here. The `'\('` opener falls
  through to a literal `(` (kue emits `(1)` → `KDEp`), preserving the red. Tracked for a
  follow-up byte-interpolation slice (plan.md).
