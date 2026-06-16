# Session 2026-06-16 — parser source positions landed

Superseded by
[`2026-06-17-b1-colon-shorthand-landed.md`](2026-06-17-b1-colon-shorthand-landed.md).
Supersedes
[`2026-06-16-strings-splitn-landed.md`](2026-06-16-strings-splitn-landed.md).

## What was done

Landed **source-position tracking + structured parse errors**. Full record in
[`../reference/implementation-log.md`](../reference/implementation-log.md) =>
"Completed Slice: Source-position tracking + structured parse errors". Summary:

- `ParseError` now carries `remaining : Nat` (chars left in the suffix at the failure
  point), plus `line`/`column` (1-based) filled at the `parseSource` boundary. `message`
  kept. Still `deriving Repr, BEq, DecidableEq, Inhabited`.
- The parser is recursive descent over `List Char` (no state monad), so position = how
  far into the suffix it got. `parseError` gained a leading `chars` arg recording
  `remaining := chars.length`; 48 throw sites in `Parse.lean` + 1 in `Runtime.lean`
  updated to pass the most-local suffix (EOF arms / non-cursor package errors pass `[]`).
- Total `offsetToLineColumn` (structural recursion, no `partial`) converts
  `offset = source.length - remaining` to `(line, col)`. `withPosition` stamps it in
  `parseSource`, so both the stdin path and the multi-file `parseSources` path get
  positioned errors.
- CLI prints `kue: parse error: <line>:<col>: <message>`
  (e.g. `kue: parse error: 2:4: unexpected character '@'`).
- 7 `native_decide` theorems via new `parseFailsAt source line col` helper, every
  position confirmed against the built binary: `1:1`, `1:9`, `1:10`, `2:4`, `3:6`
  (multi-line struct), `4:1` (EOF unclosed list), `2:1` (EOF unterminated string).
- Stale `compat-assumptions.md` claim fixed: comprehensions / dynamic fields / string
  interpolation DO parse+eval now; the parser does NOT yet support non-field aliases,
  typed struct ellipsis (`...T`, which cue v0.15.4 also rejects), or imports with module
  resolution. Parser/diagnostics notes updated to record source positions on errors.

Verify gate green: `lake build` (68 jobs, all theorems pass), `scripts/check-fixtures.sh`
=> `fixture pairs ok`, `shellcheck scripts/check-fixtures.sh` clean. Pushed to `gh:main`.

### Note: separators stay permissive

`a: 1 b: 2\n` parses as two fields with no separator and no error — confirms the standing
permissive-separator assumption. Strict CUE newline/semicolon insertion remains
unimplemented (parser next-step work, alongside non-field aliases). Position tests used
unambiguous failing tokens (`@`, dangling `.`, unclosed `[`/`(`/`"`) for this reason.

## Alpha status

v0.1.0 staged; cut locally via `scripts/release.sh` on chakrit's "cut a slice" command
(**NO GitHub Actions — banned**; release tooling owned elsewhere — do not touch
`scripts/release.sh` / `packaging/`). Remaining alpha boundaries (carried forward):

- **No imports / module resolution** (builtins work via implicit dotted names; real
  `import`s are parsed-and-ignored). **This is the next focus — see below.**
- **No `list.Sort` / `SortStable`** (comparator-struct evaluation). `SortStrings` landed.
- **Unicode (non-ASCII) case folding** — `ToUpper`/`ToLower`/`ToTitle` are ASCII-only;
  non-ASCII passes through unchanged.
- **Remaining `strings` funcs** (`Trim*`, `Runes`, `ContainsAny`, `LastIndex`) and `math`
  `Sqrt`/`Pow`/trig — parked per the Current Focus re-prioritization (core-language
  completeness over stdlib builtins).

## Next session — implementation focus: LOCAL IMPORTS & MODULES

Per `plan.md` Current Focus (set 2026-06-16): parser form-completeness has landed and
parser errors now carry positions. The active priority is now **step 2 — local imports &
modules (sort-of working)**: make local/relative imports and module resolution at least
partially function for a **single module on-disk** (relative file/package resolution).
Full multi-file package merge and full package-clause semantics stay **deferred to LAST**
(step 3).

What this slice must grapple with (scout first, don't assume):

- **Today `import` is parsed-and-ignored** (`consumeImportClauses` in `Parse.lean`).
  Builtins work because `strings.X` is an *implicit dotted name*, not a bound symbol. A
  real import must bind a package name to a resolved on-disk source and make its exported
  fields referenceable.
- **`cue.mod/` and module roots.** Check whether the repo/testdata has a `cue.mod`
  fixture; a real module resolver keys off the module root + relative import path.
  Oracle-probe how `cue` v0.16.1 resolves a local relative import before encoding —
  module path vs filesystem path mapping is the crux and easy to get subtly wrong.
- **CLI plumbing.** `Main.lean` reads explicit file args / stdin; an import needs to read
  *additional* files the user didn't list, resolved relative to the importing file. That
  means the IO layer (currently `readFileSources`) grows a resolution step. Keep the
  resolver total and the IO boundary thin.
- **Scope it down hard.** Single module, single on-disk relative import, exported fields
  referenceable. NOT: version resolution, registries, multi-module graphs, or full
  package merge (that is step 3, LAST). Land the smallest end-to-end "file A imports
  local file/package B and references its field" and log the boundaries.

### Mechanics reminder (unchanged)

- `cue` v0.16.1 at `/Users/chakrit/go/bin/cue`. Needs file args + `import` (e.g.
  `cue export file.cue --out json`); `kue` reads stdin (`.lake/build/bin/kue < file.cue`)
  or file args. `.expected` files are **kue's** output format. Run
  `cue fmt --files testdata/cue/<f>.cue` before the check script.
- New fixtures need BOTH a `.cue`/`.expected` pair AND a `FixturePorts.lean` entry.
  Generate the `.expected` from the port: `lake env lean --run
  scripts/write-fixture-ports.lean <tmpdir>` then copy into `testdata/cue/`.
- `Value` derives `BEq` but **not** `DecidableEq` — assert `(a == b) = true := by
  native_decide`. `ParseError` DOES derive `DecidableEq` (plain structure) — the
  position tests use `native_decide` on `parseFailsAt`.
- **Cycle constraint:** `Builtin` cannot import `Eval`, but CAN import `Decimal`.
- Parser is `partial` (recursive descent over `List Char`); position is suffix-length,
  converted to line:col only at the `parseSource` boundary via `withPosition`.

### Still pending (later slices, unchanged)

- Strict newline/semicolon separator insertion + non-field aliases (parser completeness
  tail).
- `list.Sort`/`SortStable` (comparator-struct evaluation) — last `list` work.
- Remaining `strings` funcs and full Unicode case folding.
- `math` `Sqrt`/`Pow` (apd sig-digit context + NaN modeling) and trig/log/`Exp`.
- Full packages (multi-file merge, full package-clause semantics) — deferred to LAST.
