# Breadcrumb — 2026-07-05 BYTE-ARRAY-REPR (rank 0f) landed

## Where the loop stands

Just landed: **BYTE-ARRAY-REPR (rank 0f)** — the `Prim.bytes` carrier is now `Array UInt8`
(was `String`). Fully CLOSED BYTE-HIGHBYTE; the `byte-literal-high-byte` wild seed graduated
GREEN. Highest-leverage byte item from the 2026-07-04 Phase B audit is done. Byte VALUE
semantics are now exact — a byte ≥ 0x80 is one octet, not a multi-byte UTF-8 codepoint.

## What landed this slice

- **Carrier:** `Prim.bytes (value : Array UInt8)` (`Value.lean`). Chose `Array UInt8` over
  `ByteArray` (which lacks `DecidableEq`/`Repr` in Lean core, breaking `Prim`'s `deriving`
  and the `primsUnifyEqual_refl` proof). Added `textBytes : String → Array UInt8` bridge.
- **3 latent bugs fixed at the same sites:** `len('\xff') == 1` (`.size`, not `utf8ByteSize`);
  `formatPrim` byte encoder (`formatByte`/`formatBytesLiteral`, `\n\r\t`/`\'`/`\\`/printable/
  `\xNN`); base64 export encodes raw bytes (Json/Yaml/Builtin `base64.Encode`), not lossy
  `.toUTF8`.
- **Multiline-bytes escape gap:** dedicated `parseMultilineByteBody` (`Parse.lean`) decodes
  byte escapes; `decodeByteEscape` now yields `List UInt8` (`\xNN`/`\NNN` → one octet,
  `\u`/`\U` → codepoint UTF-8 bytes).
- **Tests:** `BytesTests.lean` rewritten to pin raw bytes (high-byte round-trip, mixed
  ASCII+high, codepoint-vs-raw-byte distinction, empty, `\xNN` format round-trip, base64
  `/w==`). ~16 `.bytes "…"` literals migrated to `textBytes` across FixturePorts/FixtureTests/
  EvalTests/BuiltinTests/Tests. `evalRepeat` split into `evalRepeatString`/`evalRepeatBytes`.
- **Docs:** plan.md 0f marked LANDED + seed graduated + dependents' prerequisite MET +
  stale "String-backed limitation" retracted; implementation-log entry; byte-formatting
  choice recorded in `cue-spec-gaps.md`; `multiline_bytes.expected` updated to the
  single-quote inline-escape form.

## Verify

`./scripts/check.sh` GREEN (150 build jobs + all gates). High-byte seed exports `/w==` (hex
and octal forms). Committed on `main` (explicit pathspec), NOT pushed.

## Next

The two byte dependents are now UNBLOCKED (repr prerequisite met), both still open in
`plan.md`:

- **BYTES-SLICE-MISSING** — a clean `Array.extract` on the new carrier; needs its own
  slice-family dispatch (`__slice` handling list + bytes) + byte-indexed fixtures. Smallest
  next byte slice.
- **BYTE-INTERPOLATION** — the residual: a byte-context interpolation carrier (`.interpolation`
  renders to a STRING, no byte marker) rippling ~20 match sites + digest/format/manifest;
  graduates `byte-literal-interpolation`. Broader; attended-grade.

Otherwise pick from `plan.md` § Ranked OPEN backlog (PATTERN-BOUND-REF-OPERAND, BI-EFF,
STRUCT-EQ half-2, ARCH-QUOTED-STRIP, PRIM-FLOAT-PARSED, BUILTIN-IMPORT-LENIENCY). 2 quarantined
seeds remain: `byte-literal-interpolation`, `pattern-bound-reference-operand`.
