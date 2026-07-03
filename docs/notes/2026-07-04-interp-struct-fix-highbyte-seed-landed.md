# 2026-07-04 — Phase A follow-up: interp-struct fix + high-byte red seed (AFK)

Landed the two LOW findings the Phase A batch-3 audit filed.

## What landed

- **INTERP-STRUCT-PATTERN-DEFER — fixed.** `classifyInterpolationPart` (`Kue/EvalBase.lean`):
  collapsed the two struct arms (`[]` → error, `(_ :: _)` → defer) into one pattern-agnostic
  `.struct _ _ _ _ _ => .nonInterpolatable .struct`. A pattern-bearing struct now ERRORS like a
  plain struct instead of over-DEFERring; matches cue's type-error on `"\({[string]:int})"`.
  Exhaustiveness preserved (no `| _ =>`). Regression: `out_pattern` in
  `numeric/interpolation_type_error` fixture + native_decide guard in `Tests.lean`.
- **BYTE-HIGHBYTE-NO-RED-SEED — seeded, quarantined.** `testdata/wild/byte-literal-high-byte/`
  (`a: '\xff'` → `/w==`, `.known-red`). Confirmed RED: kue `w78=` (2-byte UTF-8), spec/cue `/w==`
  (raw byte 0xFF). Root = String-backed bytes; fix rides **BYTE-INTERPOLATION** (byte-array repr).

## State

Gate `./scripts/check.sh` GREEN. cert-manager canary EMPTY. Committed on `main`, NOT pushed (AFK).

## Next

Phase B (architecture) still owed for the `dfdd1ab..HEAD` batch. Open plan items unchanged:
ARCH-QUOTED-STRIP, GDA-FLOAT-RENDER, BYTES-SLICE-MISSING, BYTE-INTERPOLATION (now graduates both
byte red seeds), BUILTIN-IMPORT-LENIENCY.
