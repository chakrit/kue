# byte-literal-hex-escape

- **Source:** conformance probe 2026-07-04 (string-interpolation / regexp / encoding sweep),
  minimal synthetic repro.
- **CUE construct at fault:** the `\xNN` hex byte escape inside a BYTE literal (`'...'`).
  `'\x01ab'` is the three bytes `0x01 'a' 'b'`.
- **Spec basis (kue is WRONG, cue is right):** CUE byte literals support `\xNN` (and `\NNN`
  octal, `\uNNNN`, etc.) escapes. `cue export` → `{ "a": "AWFi" }` (base64 of `0x01 0x61
  0x62`). kue's byte lexer drops the backslash and keeps the literal characters `x01ab`
  (`eDAxYWI=`), so `\x01` is not decoded. Parser-level (byte-literal escape decoding). No
  `cue-divergences.md` entry — cue agrees with the spec.
- **Status:** RED-SEEDED (`.known-red`) 2026-07-04, captured-not-fixed. Fix belongs to a
  byte-literal-lexing slice (see also `byte-literal-interpolation`).
