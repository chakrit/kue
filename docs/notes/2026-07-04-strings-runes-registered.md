# Breadcrumb — 2026-07-04 — STRINGS-RUNES-MISSING: `strings.Runes` registered

## What this slice did

Registered `strings.Runes(s)` (AFK, unattended) — a real CUE builtin kue left unregistered,
so it silently bottomed. Now returns cue's rune-codepoint list.

## Behavior (cue v0.16.1, confirmed)

`strings.Runes(s)` → LIST of INT Unicode code points, one per rune (NOT strings, NOT bytes):
`"abc"`→`[97,98,99]`, `"héllo"`→`[104,233,108,108,111]`, astral `"a😀b"`→`[97,128512,98]`
(emoji = one rune, full code point), `""`→`[]`, decomposed `"e"+U+0301`→`[101,769]` (combining
marks are their own scalar; cue does not normalize). Wrong-arity / non-string arg = cue error.

## Change

- `Kue/Builtin.lean`: `stringRunes` maps `value.toList` (Lean `Char` = Unicode scalar, so
  multibyte/astral are one element — not bytes/surrogates) to `.prim (.int codepoint)`.
  Dispatch arm in `evalStringsBuiltin`; no new `BuiltinFamily` case (already `.strings`), no
  `| _ =>` — wrong-arity/non-string fall through the existing `unresolvedOrBottom` tail
  (concrete ⇒ bottom, matching cue).
- Fixture `strings_runes.{cue,expected}` (ascii/multibyte/emoji/empty/combining) +
  `FixturePorts` entry; 6 `native_decide` theorems in `BuiltinTests.lean`.

## Verify

`./scripts/check.sh` GREEN. cert-manager canary EMPTY (kue == cue after `jq -S`). Committed
on `main`, NOT pushed (AFK envelope).

## Next

**2026-07-04 Phase A audit DONE** (`abbab99..HEAD`) — float-unify (`8a76260`) and
`strings.Runes` (`6461d16`) CLEAN; struct/list `==` (`1130638`) has ONE MEDIUM finding filed
**STRUCT-EQ-LEAF-TYPESENSE** (plan 0d): `[1.0]==[1]`/`{a:1.0}=={a:1}` → kue `true`, cue `false`
(number-leaf value-equality inside containers). Doc "matches cue exactly" claims corrected
inline. A4 verified GATE-KNOWNRED-DRY + STRUCT-EQ half-1 landed; ARCH-QUOTED-STRIP still open
by design. **Phase B (architecture/refactor) now OWED** before the next slice batch.

`LIST-SLICE-MISSING` (`x[lo:hi]` parser gap) still open. Attended: GDA-FLOAT-RENDER slice
(float export canonical-form byte-match + negative-zero) is the highest-value numeric
follow-up. Resume plan HIGH/MEDIUM tail.
