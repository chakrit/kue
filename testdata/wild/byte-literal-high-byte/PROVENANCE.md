# byte-literal-high-byte

- **Source:** Phase A code-quality audit 2026-07-04 (finding BYTE-HIGHBYTE-NO-RED-SEED),
  minimal synthetic repro.
- **CUE construct at fault:** a byte literal (`'...'`) holding a byte ≥ 0x80 — here `'\xff'`
  (raw byte 0xFF). The sibling octal form `'\377'` is the same byte and fails identically.
- **Spec basis (kue is WRONG, cue is right):** a byte literal is a sequence of raw bytes;
  `'\xff'` is the one byte 0xFF. `cue export` → `{ "a": "/w==" }` (base64 of the single byte
  0xFF). kue exports `{ "a": "w78=" }` — base64 of `0xC3 0xBF`, the 2-byte UTF-8 encoding of
  the code point U+00FF. Root cause: bytes are String-backed in the `Value` repr, so a byte
  escape ≥ 0x80 cannot be held as a single byte — it is stored as a Unicode scalar and
  re-encoded as UTF-8 on export. Silent wrong VALUE (both exit 0), not an error. No
  `cue-divergences.md` entry — cue agrees with the spec.
- **Status:** RED-SEEDED (`.known-red`) 2026-07-04. QUARANTINED — the fix is architectural: it
  needs a byte-array `Value` representation (a `List UInt8` / `ByteArray` carrier) so a byte
  literal holds arbitrary bytes independent of UTF-8. Folded into the filed BYTE-INTERPOLATION /
  byte-array-repr item (plan.md); NOT fixed here.
