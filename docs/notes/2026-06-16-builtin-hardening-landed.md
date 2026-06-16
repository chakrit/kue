# Session 2026-06-16 — post-audit builtin hardening landed

Latest resume breadcrumb. Supersedes
[`2026-06-16-decimal-lift-landed.md`](2026-06-16-decimal-lift-landed.md).
Resuming **implementation** next session.

## What was done

Closed three `/ace-audit` findings (`b92035b..8af9e2f`) in commit `1edc760`. Full record
in [`../reference/implementation-log.md`](../reference/implementation-log.md) =>
"Completed Slice: Post-audit builtin hardening". Summary:

1. **DRY'd the dispatch fallback** (this gated `math`). `Kue/Builtin.lean` now has one
   module-scope `isConcreteArg` + `unresolvedOrBottom (name) (args)`, replacing the
   byte-identical `where` triplets under `evalListBuiltin` and `evalStringsBuiltin`.
   The rule lives once: unmatched call ⇒ bottom if any arg is bottom or all args are
   concrete, else stay `.builtinCall`. **The `math` dispatcher must call
   `unresolvedOrBottom name args` — do not re-duplicate the triplet.**
2. **Totalized two `partial def`s.** `stringReplace` → fuel-bounded `stringReplaceLoop`
   (fuel = source UTF-8 size). `listFlattenN` → `listFlattenFuel`, full-flatten fuel
   from new `listNestingDepth`. Both `partial` dropped. Behavior-preserving.
3. **Pinned tests.** Float×float / float÷float = bottom (EvalTests, deferred decimal
   wiring made visible); `strings.Replace` count==0 unchanged + `list.Slice` negative
   low = bottom (BuiltinTests); new oracle-checked fixture
   `comprehension_loopvar_shadow.{cue,expected}` (loop var shadows sibling/outer `v`,
   exercising the `(depth,index)` scope chain).

Verify gate green: `lake build` (68 jobs), `scripts/check-fixtures.sh` =>
`fixture pairs ok`, `shellcheck` clean. No existing `.expected` drift (only new file is
the shadow fixture). Tree clean, pushed to `gh:main`.

## Next session — implementation focus

**Add the `math` builtin family** (next per `docs/spec/plan.md` => Later Slices). Same
shape as strings/list: an `evalMathBuiltin` helper in `Kue/Builtin.lean`, a
`name.startsWith "math."` route in `evalBuiltinCall`, a `math_builtin.{cue,expected}`
fixture pair, a `FixturePorts.lean` entry, and `native_decide` theorems.

- **Reuse the shared dispatch helper**: the `evalMathBuiltin` catch-all arm must be
  `| name, args => unresolvedOrBottom name args` — finding #1 put it in place for exactly
  this. No new fallback triplet.
- For exact-decimal math, **add `import Kue.Decimal` to `Kue/Builtin.lean`** (legal — no
  cycle) and reuse `addDecimalValues` / `decimalLtValues` / `formatFiniteDecimal` /
  `decimalFromPrim?`. Float-returning funcs (`Sqrt`, `Pow`, `Floor`/`Ceil`/`Round`)
  format through `formatFiniteDecimal`; integer-closed ones (`math.Abs` on ints,
  `math.MultipleOf`) need no decimal. **Oracle-check each against `cue` v0.16.1**
  (`/Users/chakrit/go/bin/cue`, confirmed present) before encoding.
- `Sqrt`/`Pow` with irrational results need apd's sig-digit context — probe the oracle
  for exact expected strings; if a clean exact match isn't reachable yet, scope those to
  a follow-up and land the rational-exact subset first.

### Also now implementable (decimal-lift unblocked; pick whichever oracle-probes cleanest)

- **`list.Avg`** — exact-rational mean; int-collapse when count divides sum, else float.
- **Float-domain `list.Sum`/`Min`/`Max`** — extend the int arms to fall through to a
  decimal path on `.float` elements via `addDecimalValues` / `decimalLtValues`.
- **Float `list.Range`** — decimal stepping.

### Mechanics reminder (unchanged)

- `cue` needs file args (`cue export --out cue file.cue`) and the `import "math"` line;
  `kue` reads stdin. `.expected` files are **kue's** output format. The check script
  runs `cue fmt --check` on `.cue` sources, so `cue fmt --files testdata/cue/<f>.cue`
  first.
- New fixtures need BOTH a `.cue`/`.expected` pair AND a hand-built `FixturePorts.lean`
  entry; the check script diffs the CLI path and the Lean-port path.
- `Value` derives `BEq` but **not** `DecidableEq` for builtin results — assert as
  `(a == b) = true := by native_decide`, not `a = b := by decide`. (Eval-level `rfl`
  proofs work where the result is a fully-reduced literal, as in the float-deferral pins.)
- **Cycle constraint:** `Builtin` still cannot import `Eval`, but it CAN import `Decimal`.

### Still pending (later slices, unchanged)

- `list.Sort`/`SortStable`/`SortStrings` (comparator-struct evaluation).
- Deferred `strings` funcs needing unicode case folding (`ToUpper`/`ToLower`/`ToTitle`)
  and the rest (`SplitN`, `Trim*`, `Runes`, `ContainsAny`, `LastIndex`, …).
- Expand pattern constraints beyond string-label representation; remaining alias
  positions in a syntax layer; arithmetic-cycle handling; imports/modules.
