# Session 2026-06-16 — float multiplication and division landed

Latest resume breadcrumb. Supersedes
[`2026-06-16-math-builtins-landed.md`](2026-06-16-math-builtins-landed.md).
Resuming **implementation** next session.

## What was done

Flipped the float-mul/div deferral — the identified **alpha-gating** gap. `evalMul` and
`evalDiv` (`Kue/Eval.lean`) now route float and mixed int/float operands through exact
decimal helpers in `Kue/Decimal.lean` instead of collapsing to `.bottom`. Full record in
[`../reference/implementation-log.md`](../reference/implementation-log.md) =>
"Completed Slice: Float Multiplication and Division (decimal-lift wiring)". Summary:

- **Multiplication** — `int×int` stays int; any float operand promotes to float. Exact:
  numerators multiply, scales add, summed scale preserved **verbatim, no trim**
  (`1.0*1.0 = 1.00`, `1.5*2.0 = 3.00`). New `mulDecimalValues` + `evalDecimalMultiply?`
  using `formatDecimalAtScale` (no-trim renderer split out of `formatFiniteDecimal`).
- **Division** — `/` **always yields a float** (`4.0/2.0 = 2.0`, `6/2 = 3.0`); integer
  division stays the `div`/`quo` keywords. One shared `divideDecimalRational?` reduces the
  two decimals to a rational and renders: terminating exactly (`0.25`), non-terminating at
  **34 significant digits** (apd context) round-half-up (`2/3 = 0.666…667`,
  `100/7 = 14.28…29`). Zero divisor ⇒ `.bottomWith [.divisionByZero]`.
- **Fixed a latent bug at the source.** The old int-only `formatIntegerDivision` emitted a
  fixed 34 *fractional* digits (correct only for quotients < 1) and never rounded; for
  `10/3` it gave 34 threes vs cue's 33. The int÷int path was migrated onto the new
  significant-digit divider and the old helpers (`decimalPrecision`,
  `decimalFractionDigits`, `joinStrings`, `rationalIsNegative`, `intAbsNat`) removed.
- Both deferral pins flipped to positive assertions; **18** mul/div theorems total in
  `EvalTests.lean`; fixture `float_muldiv_expressions.{cue,expected}` (10 fields) +
  `FixturePorts.lean` entry.

Verify gate green: `lake build` (68 jobs), `scripts/check-fixtures.sh` =>
`fixture pairs ok`, `shellcheck` clean. No existing `.expected` drift. No CUE divergence
logged (the int-div correction is Kue fixing its own bug, not diverging from a correct
cue). Tree clean, pushed to `gh:main`.

## Alpha status

An alpha release is being considered; **float mul/div was the identified alpha-gating
gap and is now closed.** With this landed, the remaining alpha boundaries are:

- **No imports / module resolution** (builtins work via implicit dotted names; real
  `import`s are parsed-and-ignored).
- **No `list.Sort` / `SortStable` / `SortStrings`** (need comparator-struct evaluation).
- **No unicode case folding** — `strings.ToUpper` / `ToLower` / `ToTitle` deferred.
- **No deferred repeating-decimal division boundary remains** — the full operand matrix
  and the 34-sig-digit repeating case landed in this slice. (Listed for completeness: this
  alpha gap is now resolved.)

## Next session — implementation focus

Per the prior breadcrumb, point at **float-domain `list` functions**, now fully unblocked
(the decimal layer has mul/div/add/sub/compare/format):

- **`list.Avg`** — exact-rational mean. Probe the oracle: int-collapse when count divides
  sum, else float at apd 34-sig-digit formatting. Reuse `divideDecimalRational?` (it
  already does the sum/count rational with the right rounding) rather than re-deriving.
- **Float-domain `list.Sum` / `Min` / `Max`** — extend the int arms (`listSumInt` /
  `listMinInt` / `listMaxInt` in `Kue/Builtin.lean`) to fall through to a decimal path on
  `.float` elements via `addDecimalValues` / `decimalLtValues`. A `.float` element
  currently ⇒ bottom; lift that.
- **Float `list.Range`** — decimal stepping (current `listRange` is int-only; use
  `addDecimalValues` to accumulate the step and `decimalLtValues` for the bound).

Then revisit deferred `math` `Sqrt`/`Pow` once an apd sig-digit context exists (note:
`divideDecimalRational?` now *is* a 34-sig-digit context for the division case — the
Sqrt/Pow blocker is the irrational *root/power* algorithm + differing precisions + NaN,
not formatting), and the deferred `strings` funcs (unicode case folding; `SplitN`,
`Trim*`, `Runes`, `ContainsAny`, `LastIndex`, …).

### Mechanics reminder (unchanged)

- `cue` v0.16.1 at `/Users/chakrit/go/bin/cue`. Needs file args (`cue export --out cue
  file.cue`); `kue` reads stdin (`lake exe kue < file.cue`). `.expected` files are
  **kue's** output format (single-space, unaligned); cue aligns columns. Run
  `cue fmt --files testdata/cue/<f>.cue` before the check script (it runs `cue fmt --check`).
- **Probe result kind** with `(expr & int) != _|_` to learn int-vs-float.
- New fixtures need BOTH a `.cue`/`.expected` pair AND a `FixturePorts.lean` entry; the
  check script diffs the CLI path against the Lean-port path. Float literals in a port are
  `.prim (.float "3.7")` (Prim stores the float as a String).
- `Value` derives `BEq` but **not** `DecidableEq` — assert `(a == b) = true := by
  native_decide`. Division results do NOT reduce under `rfl`; use `native_decide` for any
  division theorem (mul terminates and `rfl`-reduces fine). [Correction: this note
  originally attributed `partial` to `divideDecimalRational?` — it was always a plain
  `def`; the `partial` markers were on its dependencies `divisionDigits`/`roundDigits`.
  Both are now fuel-bounded/structural total defs (post-audit hardening 2, 2026-06-16), so
  no `partial` remains in `Decimal.lean`. The `native_decide` guidance still holds — the
  fuel/`Nat.rec` form does not `rfl`-reduce either.]
- **Cycle constraint:** `Builtin` cannot import `Eval`, but CAN import `Decimal`.

### Still pending (later slices, unchanged)

- `list.Sort`/`SortStable`/`SortStrings` (comparator-struct evaluation).
- Expand pattern constraints beyond string-label representation; remaining alias
  positions in a syntax layer; arithmetic-cycle handling; imports/modules.
