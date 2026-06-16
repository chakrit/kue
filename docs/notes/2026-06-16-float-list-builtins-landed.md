# Session 2026-06-16 — float-domain `list` builtins landed

Latest resume breadcrumb. Supersedes
[`2026-06-16-float-muldiv-landed.md`](2026-06-16-float-muldiv-landed.md).
Resuming **implementation** next session.

## What was done

Extended the integer-only `list.Sum`/`Min`/`Max`/`Range` arms to the float/decimal domain
and added `list.Avg`. Full record in
[`../reference/implementation-log.md`](../reference/implementation-log.md) =>
"Completed Slice: Float-Domain `list` Builtins". Summary:

- **The governing rule (oracle-confirmed):** CUE's numeric `list` builtins **collapse an
  integral result back to `int`-kind** — `list.Sum([1.0,2.0,3.0]) = 6`,
  `list.Avg([1,2,3]) = 2`, `list.Min([3.0,1.0,2.0]) = 1` — but keep a non-integral result
  as float (`list.Sum([1,2.5,3]) = 6.5`, `list.Avg([1,1,2]) = 1.333…333` at 34 sig
  digits). This differs from literal float arithmetic, which preserves the operand scale
  (`6.0`). Probed with `(expr & int) != _|_`.
- **New in `Kue/Decimal.lean`:** `collapseDecimalToValue` (trim → int if scale 0, else
  float at minimal scale) and `avgDecimalValue?` (exact divide `sum.numerator /
  (10^scale * count)`; integral ⇒ int, else `divideDecimalRational?`).
- **`Kue/Builtin.lean`:** `listToDecimals`/`listAllInts`; `listSum` (all-int fast path
  preserved, else `addDecimalValues`), `listMin`/`listMax` (`decimalLtValues`, collapse
  chosen element), `listAvg`, `listRangeDecimal` (scale operands to common denominator,
  reuse integer count formula, collapse each element). Float `list.Range` arm sits after
  the int one; new `list.Avg` arm; catch-all `unresolvedOrBottom` unchanged.
- Empty `Avg`/`Min`/`Max` and zero-step `Range` ⇒ `_|_` (cue errors explicitly; Kue's
  existing builtin error model collapses to bottom — not a divergence). Empty `Sum` ⇒ 0.
- **16** `native_decide` theorems in `BuiltinTests.lean`; fixture
  `list_builtin_float.{cue,expected}` (15 fields) + `FixturePorts.lean` entry.

Verify gate green: `lake build` (68 jobs), `scripts/check-fixtures.sh` =>
`fixture pairs ok`, `shellcheck` clean. No existing `.expected` drift. No CUE divergence
logged (integral-collapse matches cue exactly). Tree clean, pushed to `gh:main`.

## Alpha status

Remaining alpha boundaries (carried forward from the muldiv breadcrumb, minus the now-
closed float `list` gap):

- **No imports / module resolution** (builtins work via implicit dotted names; real
  `import`s are parsed-and-ignored).
- **No `list.Sort` / `SortStable` / `SortStrings`** (`Sort`/`SortStable` need
  comparator-struct evaluation; `SortStrings` is comparator-free — see below).
- **No unicode case folding** — `strings.ToUpper` / `ToLower` / `ToTitle` deferred.

## Next session — implementation focus

Two candidate families. Oracle probes (cue v0.16.1):

- `list.SortStrings(["b","a","c"]) = ["a","b","c"]` — **comparator-free, oracle-clean.**
- `list.Sort([3,1,2], list.Ascending) = [1,2,3]` — needs the `list.Ascending` comparator
  **struct** (`{x:_, y:_, less: x<y}`) evaluated; the hard part of the Sort family.
- `strings.ToUpper("hello") = "HELLO"` — oracle-clean, but full correctness needs unicode
  case folding (Lean's `Char.toUpper` is ASCII-only; the boundary is non-ASCII).

**Recommended: `list.SortStrings` first** (cleanest — pure string sort, no comparator
struct, no unicode). It unblocks the Sort family's plumbing (a stable string-key sort) and
leaves `list.Sort`/`SortStable` (comparator-struct evaluation) as a focused follow-up.
`strings.ToUpper`/`ToLower`/`ToTitle` are the other clean-probing option but carry the
unicode-folding boundary — land ASCII and document the non-ASCII deferral if taken.

### Mechanics reminder (unchanged)

- `cue` v0.16.1 at `/Users/chakrit/go/bin/cue`. Needs file args (`cue export --out cue
  file.cue`); `kue` reads stdin (`lake exe kue < file.cue`). `.expected` files are
  **kue's** output format (single-space, unaligned); cue aligns columns. Run
  `cue fmt --files testdata/cue/<f>.cue` before the check script (runs `cue fmt --check`).
- **Probe result kind** with `(expr & int) != _|_` to learn int-vs-float — essential here,
  since `cue export` hides float-ness of integral values (`6.0` exports as `6`).
- New fixtures need BOTH a `.cue`/`.expected` pair AND a `FixturePorts.lean` entry.
  Float literals in a port are `.prim (.float "3.7")` (Prim stores the float as a String).
- `Value` derives `BEq` but **not** `DecidableEq` — assert `(a == b) = true := by
  native_decide`. `divideDecimalRational?` is `partial`, so anything routing through it
  (Avg non-divisible, division) needs `native_decide`.
- **Cycle constraint:** `Builtin` cannot import `Eval`, but CAN import `Decimal`.

### Still pending (later slices, unchanged)

- `list.Sort`/`SortStable` (comparator-struct evaluation).
- `strings` unicode case folding + the unimplemented `strings` funcs (`SplitN`, `Trim*`,
  `Runes`, `ContainsAny`, `LastIndex`, …).
- `math` `Sqrt`/`Pow` (apd sig-digit context + NaN modeling) and trig/log/`Exp`.
- Expand pattern constraints beyond string-label representation; remaining alias
  positions in a syntax layer; arithmetic-cycle handling; imports/modules.
