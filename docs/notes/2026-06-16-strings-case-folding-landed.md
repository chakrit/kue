# Session 2026-06-16 — strings.ToUpper/ToLower/ToTitle (ASCII) landed

Latest resume breadcrumb. Supersedes
[`2026-06-16-list-sortstrings-landed.md`](2026-06-16-list-sortstrings-landed.md).
Resuming **implementation** next session.

## What was done

Landed `strings.ToUpper` / `strings.ToLower` / `strings.ToTitle` — the ASCII subset, with
the non-ASCII case-folding boundary documented (not silently wrong). Full record in
[`../reference/implementation-log.md`](../reference/implementation-log.md) =>
"Completed Slice: `strings.ToUpper`/`ToLower`/`ToTitle` (ASCII)". Summary:

- `asciiToUpper`/`asciiToLower` in `Kue/Builtin.lean` map via `Char.toUpper`/`toLower`,
  which are **ASCII-only** in Lean — non-ASCII runes pass through unchanged (the deferral
  boundary). `asciiToTitle` + `asciiTitleSeparator` capitalize the first char of each
  **whitespace-delimited** word; non-whitespace (`-`, `.`, `_`, `/`, digits) does NOT start
  a word. Three new arms in `evalStringsBuiltin`; catch-all `unresolvedOrBottom` unchanged.
- **Oracle-confirmed (cue v0.16.1) — the crux: `ToTitle` is PER-WORD capitalization, NOT
  "upper-case every letter".** The task brief's stated assumption (Go `strings.ToTitle`
  upper-cases all letters) was **wrong** for cue. cue's `strings.ToTitle` =
  `golang.org/x/text`-style title: upper-case the first char of each word, leave the rest
  untouched. Probed exhaustively: word separator is **whitespace ONLY** (`unicode.IsSpace`);
  `ToTitle("a-b a.b a_b a/b")` → `"A-b A.b A_b A/b"`, `ToTitle("3 abc a3bc")` →
  `"3 Abc A3bc"` (digit is not a separator). All ASCII cases match cue byte-for-byte.
- **Non-ASCII deferral = passthrough (not bottom).** Chosen for consistency with the other
  byte-faithful string builtins and to stay total + ASCII-correct. Divergences (all
  non-ASCII): `ToUpper("café")`→Kue `"CAFé"` / cue `"CAFÉ"`; `ToLower("CAFÉ")`→Kue `"cafÉ"`;
  `ToTitle("über alles")`→Kue `"über Alles"` / cue `"Über Alles"`. Logged in
  `docs/spec/compat-assumptions.md` → "String case folding". **NOT** in
  `cue-divergences.md` — that file is for cue defects where Kue is right; here cue is
  correct and Kue is deliberately limited (the file's own scoping excludes unimplemented
  behavior).
- 19 `native_decide` theorems (ToUpper/ToLower/ToTitle × lowercase/uppercase/empty/
  digits+punct; ToTitle per-word + whitespace-only-separator + digit-not-separator +
  leading-whitespace; 3 non-ASCII passthrough boundary; abstract-arg-unresolved;
  non-string-bottom) + fixture pair `strings_case.{cue,expected}` (14 ASCII cases) +
  `FixturePorts.lean` entry.

Verify gate green: `lake build` (68 jobs, all theorems pass), `scripts/check-fixtures.sh`
=> `fixture pairs ok`, `shellcheck` clean. Tree clean, pushed to `gh:main`.

## Alpha status

v0.1.0 staged; cut locally via `scripts/release.sh` on chakrit's "cut a slice" command
(**NO GitHub Actions — banned**; release tooling is owned elsewhere — do not touch
`scripts/release.sh` / `packaging/`). Remaining alpha boundaries (carried forward):

- **No imports / module resolution** (builtins work via implicit dotted names; real
  `import`s are parsed-and-ignored).
- **No `list.Sort` / `SortStable`** (comparator-struct evaluation). `SortStrings` landed.
- **Unicode (non-ASCII) case folding** — `ToUpper`/`ToLower`/`ToTitle` are ASCII-only;
  non-ASCII passes through unchanged. ASCII subset is now landed; full Unicode deferred.

## Next session — implementation focus

The cleaner next slice is the **remaining deferred `strings` functions** over
`list.Sort`/`SortStable`: same shape as what just landed (pure `String → …` maps, no new
`Value` variants, no struct-evaluation plumbing), whereas `list.Sort` still needs a
comparator-struct evaluation bridge the `Builtin` layer lacks.

- **`strings.SplitN` (RECOMMENDED first).** `Split` with a count cap. `stringSplit`
  already exists; add an `n`-bounded variant. Oracle-check the `n<0`/`n==0`/`n==1` edge
  semantics against cue first (Go: `n==0`→nil, `n<0`→all, `n>0`→at most n with last piece
  unsplit).
- **`strings.Trim`/`TrimPrefix`/`TrimSuffix`/`TrimLeft`/`TrimRight`.** `Trim` strips a
  **cutset** (any rune in the set) from both ends; `TrimPrefix`/`Suffix` strip a fixed
  affix once. All pure byte/rune maps. Watch the cutset-vs-affix distinction.
- **`strings.Runes`** (string → list of single-rune strings; trivial via `toList`),
  **`strings.ContainsAny`** (any rune of a cutset present), **`strings.LastIndex`**
  (byte index of last occurrence — mirror `stringByteIndex` scanning from the end).
- **`list.Sort`/`list.SortStable` (the harder one).** Needs the `list.Ascending`-style
  comparator **struct** (`{x:_, y:_, less: x<y}`) evaluated once per comparison — struct
  evaluation the builtin layer does not have (`Builtin` cannot import `Eval`). Defer until
  the strings family is cleared or a comparator-eval bridge is designed.

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
- Remaining `strings` funcs (`SplitN`, `Trim*`, `Runes`, `ContainsAny`, `LastIndex`, …)
  and full Unicode case folding.
- `math` `Sqrt`/`Pow` (apd sig-digit context + NaN modeling) and trig/log/`Exp`.
- Imports/modules; pattern constraints beyond string-label representation; remaining alias
  positions; arithmetic-cycle handling.
