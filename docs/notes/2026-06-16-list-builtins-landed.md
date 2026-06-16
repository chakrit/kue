# Session 2026-06-16 — list builtin family landed

Latest resume breadcrumb. Supersedes
[`2026-06-16-strings-builtins-landed.md`](2026-06-16-strings-builtins-landed.md).
Resuming **implementation** next session.

## What was done

- **list Builtins slice — DONE.** Second package-qualified builtin family, reusing the
  dispatch infra from the strings slice (no new infrastructure). Full record in
  [`../reference/implementation-log.md`](../reference/implementation-log.md) =>
  "Completed Slice: list Builtins". Key points:
  - **Dispatch.** `evalBuiltinCall`'s catch-all now also routes
    `name.startsWith "list."` to a new `evalListBuiltin` (in `Kue/Builtin.lean`),
    mirroring `evalStringsBuiltin`: concrete type-mismatch ⇒ bottom; all-concrete but
    unmatched ⇒ bottom; abstract args keep the call unresolved.
  - **Implemented (11), oracle-exact vs `cue` v0.16.1:** `Concat`, `FlattenN`
    (depth 0 = no-op, <0 = full), `Repeat` (neg ⇒ bottom), `Range` (int; step 0 ⇒
    bottom; ceiling-division element count; descending for neg step), `Slice`
    (neg/over/inverted ⇒ bottom), `Take`/`Drop` (clamp past end; neg ⇒ bottom),
    `Contains` (structural `BEq`; needle restricted to concrete `.prim`/`.list` so
    abstract needles stay unresolved), and **integer-domain** `Sum` (empty = 0),
    `Min`/`Max` (empty ⇒ bottom; non-int element ⇒ bottom).
  - 16 `native_decide` theorems in `Kue/BuiltinTests.lean`; `list_builtin.{cue,expected}`
    fixture + hand-built `FixturePorts.lean` entry; both CLI and Lean-port paths diff
    clean against the oracle-derived `.expected`.
- Verify gate green: `lake build` (66 jobs), `scripts/check-fixtures.sh` =>
  `fixture pairs ok`, `shellcheck` clean. Tree clean, pushed.

### Deferred from this slice (by design, noted not faked)

- **`list.Avg`** — exact-rational mean: collapses to `int` when count divides sum
  (`Avg([1,2,3]) = 2`), else a float at apd's 34-significant-digit precision
  (`Avg([1,2,4]) = 2.333…` to 33 digits). kue's `/` always emits `.0`-floats, so Avg
  needs the shared decimal formatter, not `/`.
- **Float-domain `Sum`/`Min`/`Max` and float `Range`** — need `addDecimalValues` /
  decimal compare, which live in `Eval`. `Builtin` can't import `Eval` (Eval imports
  Builtin — cycle). Blocked on lifting `DecimalValue`/`addDecimalValues`/
  `formatFiniteDecimal`/`decimalFromPrim?` into a lower module (`Lattice` or new
  `Decimal`). That refactor unblocks both this and `Avg`.
- **`list.Sort`/`SortStable`/`SortStrings`** — `Sort` takes a comparator *struct*
  `{x: _, y: _, less: x < y}` (`list.Ascending`/`list.Descending` are predefined such
  structs), not a function value. Needs evaluating `less` against per-pair bindings —
  beyond the builtin layer today.

## Next session — implementation focus

**Add the `math` builtin family** (next family per `docs/spec/plan.md` => Later
Slices). Same shape as strings/list: an `evalMathBuiltin` helper in `Kue/Builtin.lean`,
a `name.startsWith "math."` route in `evalBuiltinCall`, a `math_builtin.{cue,expected}`
fixture pair, a `FixturePorts.lean` entry, and `native_decide` theorems.

Oracle-check each against `cue` v0.16.1 before encoding. Watch the same float wall: any
`math` function returning a non-integer (most of them — `Sqrt`, `Pow`, `Floor` returns
int-valued float, etc.) hits the **same decimal-in-Eval cycle** as list's float domain.
So a clean math slice is likely **integer-only first** (`math.Abs` on ints,
`math.MultipleOf`, maybe `math.Round*` returning ints), OR do the **decimal-lift refactor
first** (move `DecimalValue` & friends out of `Eval` into a lower module) and then math +
list's deferred float domain + `Avg` all unlock together. The refactor-first path is
likely the higher-leverage next slice — decide by oracle-probing which `math` funcs are
int-closed before committing.

### Mechanics reminder (unchanged from strings slice)

- `cue` needs file args (`cue export --out cue file.cue`) and the `import "math"` line;
  `kue` reads stdin. `.expected` files are **kue's** output format (single-space
  `label: value`, `[a, b]` lists), NOT `cue fmt`'s column alignment — but for the
  pure-value cases here they coincide with cue's `--out cue` values modulo alignment.
  The check script runs `cue fmt --check` on `.cue` sources, so
  `cue fmt --files testdata/cue/<f>.cue` first.
- New fixtures need BOTH a `.cue`/`.expected` pair AND a hand-built `FixturePorts.lean`
  entry; the check script diffs the CLI path and the Lean-port path and flags any
  `.expected` lacking a port.
- `Value` derives `BEq` but **not** `DecidableEq` — assert eval results in tests as
  `(a == b) = true := by native_decide`, not `a = b := by decide`.
- **Import-cycle constraint:** `Eval` imports `Builtin`, so `Builtin` cannot import
  `Eval`. Any builtin needing `Eval`'s decimal/arithmetic helpers requires lifting those
  helpers to a module both can import.

### Also pending (later slices, unchanged)

- Decimal-lift refactor (unblocks list float domain + `Avg` + most of `math`).
- Deferred `strings` funcs needing unicode case folding (`ToUpper`/`ToLower`/`ToTitle`)
  and the rest (`SplitN`, `Trim*`, `Runes`, `ContainsAny`, `LastIndex`, …).
- `list.Sort`/`SortStable`/`SortStrings` (comparator-struct evaluation).
- Expand pattern constraints beyond string-label representation; remaining alias
  positions in a syntax layer; arithmetic-cycle handling; imports/modules (real symbol
  binding — currently imports are parsed-and-ignored).
