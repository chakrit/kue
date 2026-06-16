# Session 2026-06-16 — decimal-lift refactor landed

Latest resume breadcrumb. Supersedes
[`2026-06-16-list-builtins-landed.md`](2026-06-16-list-builtins-landed.md).
Resuming **implementation** next session.

## What was done

- **Decimal-Lift Refactor — DONE.** Pure structural move, zero behavior change. Full
  record in [`../reference/implementation-log.md`](../reference/implementation-log.md)
  => "Completed Slice: Decimal-Lift Refactor". Key points:
  - **New module `Kue/Decimal.lean`** (imports only `Kue.Value`). Holds `DecimalValue`
    and all its machinery moved out of `Eval`: parsing (`parseDecimalText`,
    `decimalFromPrim?` + helpers), arithmetic (`addDecimalValues`, `subDecimalValues`,
    `scaleDecimalNumerator`, `maxNat`), comparison (`decimalEqValues`,
    `decimalLtValues`, `decimalCompareNumerators`), formatting (`formatFiniteDecimal` +
    `trimDecimalZerosWith`/`decimalIntAbsNat`/`repeatZeros`/`leftPadZeros`), and the
    `Prim` adapters `evalDecimalBinary?` / `evalDecimalCompare?`.
  - **Layering:** new edge is `Value → Decimal`. `Decimal` has no dependency on
    `Eval`/`Builtin`/`Lattice`/`Normalize`, so both `Eval` and `Builtin` can import it
    with no cycle — this is the whole point of the slice. `Eval` now
    `import Kue.Decimal` and keeps everything from `evalAdd` onward, references
    unchanged. Names kept stable; no rename churn.
  - **`Builtin` is NOT yet wired to import `Decimal`** — no dead import. The consuming
    slices add that edge when they actually use it.
- Verify gate green: `lake build` (68 jobs), `scripts/check-fixtures.sh` =>
  `fixture pairs ok`, `shellcheck` clean. **No `.expected` changed** (git status: only
  `Kue/Eval.lean` modified, `Kue/Decimal.lean` added). Tree clean, pushed.

## Next session — implementation focus

**Add the `math` builtin family** (next family per `docs/spec/plan.md` => Later
Slices), now fully unblocked for float-returning functions. Same shape as strings/list:
an `evalMathBuiltin` helper in `Kue/Builtin.lean`, a `name.startsWith "math."` route in
`evalBuiltinCall`, a `math_builtin.{cue,expected}` fixture pair, a `FixturePorts.lean`
entry, and `native_decide` theorems.

To do exact-decimal math, **add `import Kue.Decimal` to `Kue/Builtin.lean`** (now legal —
no cycle) and reuse `addDecimalValues` / `decimalLtValues` / `formatFiniteDecimal` /
`decimalFromPrim?`. Float-returning `math` funcs (`Sqrt`, `Pow`, `Floor`/`Ceil`/`Round`,
…) format through `formatFiniteDecimal`; integer-closed ones (`math.Abs` on ints,
`math.MultipleOf`) need no decimal. Oracle-check each against `cue` v0.16.1 before
encoding. Note: `Sqrt`/`Pow` with irrational results need apd's sig-digit context — probe
the oracle for exact expected strings; if a clean exact match isn't reachable yet, scope
those to a follow-up and land the rational-exact subset first.

### Also now implementable (same refactor unblocked them — good follow-up slices)

- **`list.Avg`** — exact-rational mean: int-collapse when count divides sum, else float
  via `formatFiniteDecimal`.
- **Float-domain `list.Sum` / `list.Min` / `list.Max`** — `addDecimalValues` +
  `decimalLtValues` from `Builtin`. Extend the existing int-domain arms in
  `evalListBuiltin` to fall through to a decimal path on `.float` elements.
- **Float `list.Range`** — decimal stepping via the lifted arithmetic.

These can go before or after `math`; pick whichever oracle-probes cleanest first.

### Mechanics reminder (unchanged)

- `cue` needs file args (`cue export --out cue file.cue`) and the `import "math"` line;
  `kue` reads stdin. `.expected` files are **kue's** output format. The check script
  runs `cue fmt --check` on `.cue` sources, so `cue fmt --files testdata/cue/<f>.cue`
  first.
- New fixtures need BOTH a `.cue`/`.expected` pair AND a hand-built `FixturePorts.lean`
  entry; the check script diffs the CLI path and the Lean-port path.
- `Value` derives `BEq` but **not** `DecidableEq` — assert eval results as
  `(a == b) = true := by native_decide`, not `a = b := by decide`.
- **Cycle constraint is now relaxed for decimals only:** `Builtin` still cannot import
  `Eval`, but it CAN import `Decimal`. Anything a builtin needs from `Eval` that isn't
  decimal still requires a further lift.

### Also pending (later slices, unchanged)

- Deferred `strings` funcs needing unicode case folding (`ToUpper`/`ToLower`/`ToTitle`)
  and the rest (`SplitN`, `Trim*`, `Runes`, `ContainsAny`, `LastIndex`, …).
- `list.Sort`/`SortStable`/`SortStrings` (comparator-struct evaluation).
- Expand pattern constraints beyond string-label representation; remaining alias
  positions in a syntax layer; arithmetic-cycle handling; imports/modules.
