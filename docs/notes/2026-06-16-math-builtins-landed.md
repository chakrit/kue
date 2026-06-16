# Session 2026-06-16 — math builtin family landed

Latest resume breadcrumb. Supersedes
[`2026-06-16-builtin-hardening-landed.md`](2026-06-16-builtin-hardening-landed.md).
Resuming **implementation** next session.

## What was done

Added the `math.*` builtin family (rational-exact subset). Full record in
[`../reference/implementation-log.md`](../reference/implementation-log.md) =>
"Completed Slice: Math Builtin Family (rational-exact subset)". Summary:

- `Kue/Builtin.lean` now `import Kue.Decimal`. New `evalMathBuiltin` dispatcher with a
  `name.startsWith "math."` route in `evalBuiltinCall`; catch-all arm reuses the shared
  `unresolvedOrBottom name args` (no duplicated triplet).
- **`math.Abs`** — domain-preserving (int→int, float→float). Oracle-confirmed.
- **`math.MultipleOf`** — int×int → bool; zero divisor ⇒ `.bottomWith [.divisionByZero]`.
- **`math.Floor`/`Ceil`/`Round`/`Trunc`** — number → **int** (oracle: all unify with
  `int`, no `.0`). Int input = identity; float parsed to `DecimalValue` and reduced over
  `divisor = 10^scale`. `Round` is half-away-from-zero.
- Fixture `math_builtin.{cue,expected}` (23 fields) + `FixturePorts.lean` entry +
  14 `native_decide` theorems in `BuiltinTests.lean`.

**Deferred from math** (documented in plan + log, not guessed): `Sqrt`/`Pow` (irrational
results need apd sig-digit context — `cue` uses ~17 digits for `Sqrt`, 34 for `Pow`; and
`Sqrt(-1)=NaN.0`, needing a NaN value Kue doesn't model) plus the trig/log/`Exp`/constant
families.

Verify gate green: `lake build` (68 jobs), `scripts/check-fixtures.sh` =>
`fixture pairs ok`, `shellcheck` clean. No existing `.expected` drift. Tree clean,
pushed to `gh:main`. No CUE divergence logged (Kue matches the oracle on all 23 fields).

## Next session — implementation focus

Pick whichever oracle-probes cleanest first (all unblocked by the decimal-lift refactor;
`Builtin` can import `Decimal` and use `addDecimalValues` / `decimalLtValues` /
`formatFiniteDecimal` / `decimalFromPrim?`):

- **`list.Avg`** — exact-rational mean. Probe the oracle: int-collapse when count divides
  sum, else float (likely apd 34-sig-digit formatting for non-terminating means — check
  whether a clean exact string is reachable, defer the irrational case if not, same as
  `Sqrt`/`Pow`).
- **Float-domain `list.Sum`/`Min`/`Max`** — extend the int arms (`listSumInt` /
  `listMinInt` / `listMaxInt` in `Kue/Builtin.lean`) to fall through to a decimal path on
  `.float` elements via `addDecimalValues` / `decimalLtValues`. Currently a `.float`
  element ⇒ bottom; this lifts that.
- **Float `list.Range`** — decimal stepping (current `listRange` is int-only).

Then revisit the **deferred `math` `Sqrt`/`Pow`** once an apd sig-digit context exists,
and the deferred `strings` funcs (unicode case folding `ToUpper`/`ToLower`/`ToTitle`;
`SplitN`, `Trim*`, `Runes`, `ContainsAny`, `LastIndex`, …).

### Mechanics reminder (unchanged)

- `cue` v0.16.1 at `/Users/chakrit/go/bin/cue`. Needs file args + an `import` line
  (`cue export --out cue file.cue`); `kue` reads stdin (`lake exe kue < file.cue`).
  `.expected` files are **kue's** output format (single-space, unaligned). The check
  script runs `cue fmt --check`, so `cue fmt --files testdata/cue/<f>.cue` first.
- **Probe the result kind** with `(math.X(...) & int) != _|_` to learn int-vs-float —
  this is how the `Floor`-returns-int vs `Sqrt`-returns-float distinction was found.
- New fixtures need BOTH a `.cue`/`.expected` pair AND a hand-built `FixturePorts.lean`
  entry; the check script diffs the CLI path and the Lean-port path. Float literals in a
  fixture port are `.prim (.float "3.7")` (Prim stores the float as a String).
- `Value` derives `BEq` but **not** `DecidableEq` — assert
  `(a == b) = true := by native_decide`, not `a = b := by decide`.
- **Cycle constraint:** `Builtin` cannot import `Eval`, but CAN import `Decimal`.

### Still pending (later slices, unchanged)

- `list.Sort`/`SortStable`/`SortStrings` (comparator-struct evaluation).
- Expand pattern constraints beyond string-label representation; remaining alias
  positions in a syntax layer; arithmetic-cycle handling; imports/modules.
