# Session 2026-06-16 — post-audit hardening 2 landed

Latest resume breadcrumb. Supersedes
[`2026-06-16-float-list-builtins-landed.md`](2026-06-16-float-list-builtins-landed.md).
Resuming **implementation** next session.

## What was done

Closed the float-numeric `/ace-audit` fix-slices (commit `d6c54a5`). Full record in
[`../reference/implementation-log.md`](../reference/implementation-log.md) =>
"Completed Slice: Post-Audit Hardening 2". Summary:

- **Totalized both new `partial def`s in `Kue/Decimal.lean`** — the standing convention is
  total functions; `partial` is debt.
  - `divisionDigits.loop` → fuel-bounded `divisionDigitsLoop`, ceiling
    `divisionDigitsFuel den = divisionSigDigits + 1 + (toString den).toList.length`.
    Significant emission is hard-capped; leading fractional zeros are bounded by the den
    digit count — so the over-budget exit always fires before fuel runs out (the `fuel = 0`
    arm is unreachable on real inputs). Behaviorally identical to the partial form.
  - `roundDigits` → plain `def`; inner `bump` lifted to structural `roundDigitsBump`.
  - **No `partial def` remains in `Decimal.lean`.**
- **`rangeCount`** extracted (shared integer arithmetic-sequence count); `listRange` +
  `listRangeDecimal` both call it.
- **`DecimalDivideResult`** sum (`nonNumeric | divByZero | ok String`) replaces
  `evalDecimalDivide?`'s `Option (Option String)`; `evalDiv` callsite updated.
- Doc fix: muldiv breadcrumb's wrong `partial` attribution corrected.
- All pre-existing division/avg `native_decide` theorems pass **unchanged**; added two
  high-fuel pins (`1.0/7.0` full-34-sig, `1.0/700.0` leading-zero slack) locking the bound.

Verify gate green: `lake build` (68 jobs), `scripts/check-fixtures.sh` =>
`fixture pairs ok`, `shellcheck` clean. Pure refactor, no semantic change, no CUE
divergence logged. Tree clean, pushed to `gh:main`.

## Alpha status

v0.1.0 was tagged. Remaining alpha boundaries (carried forward):

- **No imports / module resolution** (builtins work via implicit dotted names; real
  `import`s are parsed-and-ignored).
- **No `list.Sort` / `SortStable` / `SortStrings`** (`Sort`/`SortStable` need
  comparator-struct evaluation; `SortStrings` is comparator-free — see below).
- **No unicode case folding** — `strings.ToUpper` / `ToLower` / `ToTitle` deferred.

## Next session — implementation focus

Back to features. Oracle probes (cue v0.16.1):

- `list.SortStrings(["b","a","c"]) = ["a","b","c"]` — **comparator-free, oracle-clean.**
  **Recommended next.** Pure string sort, no comparator struct, no unicode. Unblocks the
  Sort family's plumbing (a stable string-key sort) and leaves `list.Sort`/`SortStable`
  (comparator-struct evaluation) as a focused follow-up.
- `list.Sort([3,1,2], list.Ascending) = [1,2,3]` — needs the `list.Ascending` comparator
  **struct** (`{x:_, y:_, less: x<y}`) evaluated; the hard part of the Sort family.
- `strings.ToUpper("hello") = "HELLO"` — oracle-clean alternative, but full correctness
  needs unicode case folding (Lean's `Char.toUpper` is ASCII-only; the boundary is
  non-ASCII). Land ASCII and document the non-ASCII deferral if taken.

### Mechanics reminder (unchanged)

- `cue` v0.16.1 at `/Users/chakrit/go/bin/cue`. Needs file args (`cue export --out cue
  file.cue`); `kue` reads stdin (`lake exe kue < file.cue`). `.expected` files are
  **kue's** output format (single-space, unaligned); cue aligns columns. Run
  `cue fmt --files testdata/cue/<f>.cue` before the check script.
- **Probe result kind** with `(expr & int) != _|_` to learn int-vs-float.
- New fixtures need BOTH a `.cue`/`.expected` pair AND a `FixturePorts.lean` entry.
- `Value` derives `BEq` but **not** `DecidableEq` — assert `(a == b) = true := by
  native_decide`. Division results (now fuel/`Nat.rec` form) still do NOT `rfl`-reduce;
  use `native_decide` for any division/avg theorem.
- **Cycle constraint:** `Builtin` cannot import `Eval`, but CAN import `Decimal`.

### Still pending (later slices, unchanged)

- `list.Sort`/`SortStable` (comparator-struct evaluation).
- `strings` unicode case folding + the unimplemented `strings` funcs (`SplitN`, `Trim*`,
  `Runes`, `ContainsAny`, `LastIndex`, …).
- `math` `Sqrt`/`Pow` (apd sig-digit context + NaN modeling) and trig/log/`Exp`.
- Expand pattern constraints beyond string-label representation; remaining alias
  positions in a syntax layer; arithmetic-cycle handling; imports/modules.
