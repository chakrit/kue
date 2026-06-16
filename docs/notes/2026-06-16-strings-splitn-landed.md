# Session 2026-06-16 — strings.SplitN landed

Latest resume breadcrumb. Supersedes
[`2026-06-16-strings-case-folding-landed.md`](2026-06-16-strings-case-folding-landed.md).
Resuming **implementation** next session.

## What was done

Landed `strings.SplitN(s, sep, n)`. Full record in
[`../reference/implementation-log.md`](../reference/implementation-log.md) =>
"Completed Slice: `strings.SplitN`". Summary:

- Factored the raw-string splitting core out of `strings.Split` into `stringSplitParts`;
  `stringSplit` now maps it to `Value`s (behavior identical). `stringSplitN` is total (no
  fuel/recursion — `take`/`drop`/`intercalate`).
- **Oracle-confirmed `n` semantics (cue v0.16.1, matches Go), probed exhaustively:**
  `n==0` ⇒ `[]`; `n<0` ⇒ all pieces (= `Split`); `n>0` ⇒ first `n-1` pieces verbatim, LAST
  is the unsplit remainder (`SplitN("a,b,c",",",2)` ⇒ `["a","b,c"]`); count > pieces ⇒ all,
  no padding; empty sep ⇒ runes then n-capped (`SplitN("abc","",2)` ⇒ `["a","bc"]`); empty
  `s` + non-empty sep ⇒ `[""]`; empty `s` + empty sep ⇒ `[]`; sep absent ⇒ `[s]`.
  **No deferral — empty-sep cleanly supported; cue and Go agree everywhere.**
- One arm in `evalStringsBuiltin`; catch-all `unresolvedOrBottom` unchanged (non-string
  `s`/`sep` / non-int `n` ⇒ bottom; abstract args ⇒ unresolved).
- 11 `native_decide` theorems + fixture `strings_splitn.{cue,expected}` (11 cases) +
  `FixturePorts.lean` entry. No CUE divergence logged (cue correct on all cases).

Verify gate green: `lake build` (68 jobs, all theorems pass), `scripts/check-fixtures.sh`
=> `fixture pairs ok`, `shellcheck` clean. Tree clean, pushed to `gh:main`.

## Alpha status

v0.1.0 staged; cut locally via `scripts/release.sh` on chakrit's "cut a slice" command
(**NO GitHub Actions — banned**; release tooling owned elsewhere — do not touch
`scripts/release.sh` / `packaging/`). Remaining alpha boundaries (carried forward):

- **No imports / module resolution** (builtins work via implicit dotted names; real
  `import`s are parsed-and-ignored).
- **No `list.Sort` / `SortStable`** (comparator-struct evaluation). `SortStrings` landed.
- **Unicode (non-ASCII) case folding** — `ToUpper`/`ToLower`/`ToTitle` are ASCII-only;
  non-ASCII passes through unchanged. ASCII subset landed; full Unicode deferred.

## Next session — implementation focus

Still the **remaining deferred `strings` functions** (same shape as `SplitN` — pure
byte/rune maps, no new `Value` variants, no struct-evaluation plumbing), preferred over
`list.Sort`/`SortStable` (which needs a comparator-struct evaluation bridge the `Builtin`
layer lacks — `Builtin` cannot import `Eval`).

- **`strings.Trim`/`TrimPrefix`/`TrimSuffix`/`TrimLeft`/`TrimRight` (RECOMMENDED first).**
  `Trim` strips a **cutset** (any rune in the set) from both ends; `TrimPrefix`/`Suffix`
  strip a fixed affix once; `TrimLeft`/`Right` are one-sided cutset strips. All pure
  byte/rune maps. Watch the cutset-vs-affix distinction. Oracle-check empty-cutset and
  empty-affix against cue.
- **`strings.Runes`** (string → list of single-rune strings — trivial, `stringSplitParts
  s ""` already does the rune split; just wrap). **`strings.ContainsAny`** (any rune of a
  cutset present in `s`). **`strings.LastIndex`** (byte index of last occurrence — mirror
  `stringByteIndex` scanning from the end).
- **`list.Sort`/`list.SortStable` (the harder one).** Needs the `list.Ascending`-style
  comparator **struct** (`{x:_, y:_, less: x<y}`) evaluated once per comparison — struct
  evaluation the builtin layer does not have. Defer until the strings family is cleared or
  a comparator-eval bridge is designed.

### Mechanics reminder (unchanged)

- `cue` v0.16.1 at `/Users/chakrit/go/bin/cue`. Needs file args + `import` (e.g.
  `cue export file.cue --out json`); `kue` reads stdin (`.lake/build/bin/kue < file.cue`).
  `.expected` files are **kue's** output format. Run `cue fmt --files testdata/cue/<f>.cue`
  before the check script.
- New fixtures need BOTH a `.cue`/`.expected` pair AND a `FixturePorts.lean` entry.
  Generate the `.expected` from the port: `lake env lean --run
  scripts/write-fixture-ports.lean <tmpdir>` then copy the file into `testdata/cue/`.
- `Value` derives `BEq` but **not** `DecidableEq` — assert `(a == b) = true := by
  native_decide`.
- **Cycle constraint:** `Builtin` cannot import `Eval`, but CAN import `Decimal`.
- Lean's `Char.toUpper`/`toLower`/`isWhitespace` are ASCII-narrow (`isWhitespace` misses
  `\v`/`\f`); when ASCII-faithfulness matters, spell the predicate explicitly.

### Still pending (later slices, unchanged)

- `list.Sort`/`SortStable` (comparator-struct evaluation) — last `list` work.
- Remaining `strings` funcs (`Trim*`, `Runes`, `ContainsAny`, `LastIndex`, …) and full
  Unicode case folding.
- `math` `Sqrt`/`Pow` (apd sig-digit context + NaN modeling) and trig/log/`Exp`.
- Imports/modules; pattern constraints beyond string-label representation; remaining alias
  positions; arithmetic-cycle handling.
