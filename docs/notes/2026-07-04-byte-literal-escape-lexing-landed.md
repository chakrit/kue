# Breadcrumb — 2026-07-04 — BYTE-LITERAL-LEXING (escape half) landed

## Where things stand

BYTE-LITERAL-LEXING slice, AFK. Decoded CUE byte-literal (`'...'`) escape sequences —
graduated one of the two committed red seeds. Byte-context interpolation deliberately
deferred (representation ripple); its seed stays quarantined.

### Landed (this slice)

- **Byte escape decoding** — `decodeByteEscape` + `parseQuotedByteBody` (+ `readHexDigits`,
  `readOctalRest`, `hexDigitVal?`, `octDigitVal?`) in `Kue/Parse.lean` decode `\xNN` (hex byte),
  `\NNN` (exactly-3-digit octal), `\uNNNN`/`\UNNNNNNNN` (unicode → UTF-8), `\a\b\f\n\r\t\v\\\'\"`.
  Base64 JSON export already worked (`Json.lean`) — only decoding was missing.
- **Graduated** `testdata/wild/byte-literal-hex-escape` (`'\x01ab'` → `AWFi`); `git rm .known-red`.
- **Fixtures:** new wild `byte-literal-octal-escape` (`'\101\102\103'` → `QUJD`, green base64
  oracle); `testdata/cue/numeric/byte_literal_escapes` (eval + FixturePort); 8 `native_decide`
  in `BytesTests.lean`.

### Deferred / still red

- **`byte-literal-interpolation` seed STAYS `.known-red`.** Byte-context interpolation `'\(1)'`
  needs a distinct byte-interpolation carrier (`.interpolation` renders to STRING, no byte-context
  marker; a byte interp can have zero literal segments so context is not inferable) — a new
  `Value`-producing arm rippling ~20 match sites + digest/format/manifest. Disproportionate to
  bundle. `\(` falls through to literal `(` (`(1)` → `KDEp`), red preserved.
- **Known limitation:** bytes are String-backed → `\xNN`/`\NNN` ≥ 0x80 decode to the codepoint's
  two-byte UTF-8 form, not a lone raw byte (cue is right; kue repr-limited). No fixture ≥ 0x80.

### Follow-up filed — BYTE-INTERPOLATION (plan.md)

Byte-array bytes representation (fixes ≥ 0x80 escapes) + byte-context interpolation carrier
(graduates `byte-literal-interpolation` + the string-context bytes operand `"\(bytesval)"`,
currently DEFERRED/safe).

## Next step

Continue the slice loop. A **two-phase audit is DUE** (last full audit 2026-07-02; many slices
since — list-slice, strings.Runes, struct-eq, interp-operand-typing, this one). Otherwise the
natural follow-on is **BYTE-INTERPOLATION** (byte-array repr + byte interp carrier) or a fresh
un-probed builtin area. `./scripts/check.sh` GREEN, cert-manager canary EMPTY, committed on
`main` (NOT pushed — AFK).
