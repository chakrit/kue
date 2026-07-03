# Breadcrumb — BI-3 stdlib conformance probe landed (2026-07-04)

Slice **BI-3-STDLIB-PROBE** landed (AFK, committed on `main`, NOT pushed). Deeper-stdlib +
type/kind conformance sweep vs cue v0.16.1.

## Landed (kue == cue, oracle-confirmed)

Seven previously-unregistered builtins registered + implemented in `Kue/Builtin.lean`:
`list.Reverse`, `strings.LastIndex`, `strings.Compare`, `strings.Trim`/`TrimLeft`/`TrimRight`
(cutset = rune SET), `strings.TrimPrefix`/`TrimSuffix` (fixed affix). Helpers total (bounded
`for`, structural recursion — no `partial`). Fixtures `builtins/strings_trim`,
`builtins/strings_compare`, `builtins/list_reverse` + 10 `native_decide` in `BuiltinTests.lean`.

## Swept clean (guards only, no code)

- **Type/kind meets fully conformant** — `int & number`, `1.5 & int`→⊥, `"x" & bytes`→⊥,
  bounds+kind, disjunction narrowing all match cue. 2 guard theorems pin it. Next probe can
  SKIP language-level meets.
- Negative/oob/empty arg-errors on `list.*`/`strings.Repeat` conformant (both bottom, cue message
  richer — presentation).
- cue-non-functions confirmed: `strings.Title`/`PadLeft`/`PadRight`, `math.GreatestCommonDivisor`,
  `math.MaxInt64` — kue bottom is correct.

## Filed for follow-up (BI-3-RESIDUAL in plan.md)

Bounded next slices: `math.Mod`/`Signbit`; `strings.MinRunes`/`MaxRunes`/`SliceRunes`/`ByteAt`;
`list.IsSorted`/`Sort`/`SortStable` (effectful comparator seam BI-EFF). Separate deferred exp/ln
increment: `math.Log`/`Log10`/`Exp`, general fractional/negative `math.Pow`, `math.Pi` constant.

## State

`./scripts/check.sh` GREEN. Canary EMPTY. Registered builtin inventory now: core(8),
strings(23), list(14), math(8), regexp(7), base64(1), json(1), yaml(1). `struct.*` (MinFields/
MaxFields) still UNREGISTERED — untouched this slice, candidate for a constraint-builtin probe.

Next unblocked: BI-3-RESIDUAL trim-family cousins (`strings.SliceRunes`/`ByteAt`/`MinRunes`/
`MaxRunes` — bounded, pure) or `math.Mod`/`Signbit`. `list.Sort*` needs the BI-EFF seam first.
