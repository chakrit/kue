# Session 2026-06-16 — list.SortStrings landed

Latest resume breadcrumb. Supersedes
[`2026-06-16-post-audit-hardening-2-landed.md`](2026-06-16-post-audit-hardening-2-landed.md).
Resuming **implementation** next session.

## What was done

Landed `list.SortStrings` — the comparator-free string sort. Full record in
[`../reference/implementation-log.md`](../reference/implementation-log.md) =>
"Completed Slice: `list.SortStrings`". Summary:

- `byteSeqLe` (total, structural lexicographic `≤` on UTF-8 byte sequences) +
  `listSortStrings` in `Kue/Builtin.lean`. The latter collects elements as strings (any
  non-string ⇒ bottom), then runs the **total, stable** `List.mergeSort` with
  `byteSeqLe a.toUTF8.toList b.toUTF8.toList`. No `partial`.
- **Ordering rule (oracle-confirmed, cue v0.16.1): byte-lexicographic** = Go's
  `sort.Strings`. Capitals before lowercase (`"A" < "a"`), multibyte after all ASCII
  (`"é" > "z"`). For valid UTF-8 this equals Unicode codepoint order.
- Dispatch arm added to `evalListBuiltin`; catch-all `unresolvedOrBottom` unchanged.
- 11 `native_decide` theorems + fixture pair `list_sort_strings.{cue,expected}` +
  `FixturePorts.lean` entry. Error cases (non-string element, non-list arg) are
  theorem-only.

Verify gate green: `lake build` (68 jobs), `scripts/check-fixtures.sh` =>
`fixture pairs ok`, `shellcheck` clean. No CUE divergence (cue and Kue agree everywhere).
Tree clean, pushed to `gh:main`.

## Alpha status

v0.1.0 staged; cut locally via `scripts/release.sh` on chakrit's "cut a slice" command
(**NO GitHub Actions — banned**; release tooling is owned elsewhere, do not touch
`scripts/release.sh` / `packaging/`). Remaining alpha boundaries (carried forward):

- **No imports / module resolution** (builtins work via implicit dotted names; real
  `import`s are parsed-and-ignored).
- **No `list.Sort` / `SortStable`** (comparator-struct evaluation). `SortStrings` is now
  landed.
- **No unicode case folding** — `strings.ToUpper` / `ToLower` / `ToTitle` deferred.

## Next session — implementation focus

Two candidates; **`strings.ToUpper`/`ToLower`/`ToTitle` is the cleaner next slice.**

- **`strings.ToUpper`/`ToLower`/`ToTitle` (RECOMMENDED).** No struct evaluation, no new
  Value variants — a pure `String → String` map, same shape as the existing `strings.*`
  arms. The single obstacle is unicode: Lean's `Char.toUpper`/`toLower` are **ASCII-only**,
  so non-ASCII (`"é" → "É"`, German ß, Turkish ı, title-case digraphs) is the boundary.
  Plan: land the ASCII subset (oracle-clean for ASCII inputs), pin it with theorems +
  fixture, and **document the non-ASCII deferral** explicitly (mirror how `math` deferred
  `Sqrt`/`Pow`). `ToTitle` needs Go's word-boundary rule (uppercase first letter of each
  run of letters) — oracle-check the exact boundary definition against cue first.
- **`list.Sort`/`list.SortStable` (the harder one).** Needs the `list.Ascending`-style
  comparator **struct** (`{x:_, y:_, less: x<y}`) evaluated once per comparison — i.e.
  struct-evaluation plumbing the builtin layer does not have (recall: `Builtin` cannot
  import `Eval`). This is the real Sort-family work; defer until the strings family is
  cleared or until a comparator-eval bridge is designed.

### Mechanics reminder (unchanged)

- `cue` v0.16.1 at `/Users/chakrit/go/bin/cue`. Needs file args + `import` (e.g.
  `cue export --out cue file.cue`); `kue` reads stdin (`lake exe kue < file.cue`).
  `.expected` files are **kue's** output format. Run `cue fmt --files testdata/cue/<f>.cue`
  before the check script.
- New fixtures need BOTH a `.cue`/`.expected` pair AND a `FixturePorts.lean` entry.
  Generate the `.expected` from the port: `lake env lean --run
  scripts/write-fixture-ports.lean <tmpdir>` then copy the file into `testdata/cue/`.
- `Value` derives `BEq` but **not** `DecidableEq` — assert `(a == b) = true := by
  native_decide`.
- **Cycle constraint:** `Builtin` cannot import `Eval`, but CAN import `Decimal`.

### Still pending (later slices, unchanged)

- `list.Sort`/`SortStable` (comparator-struct evaluation) — last `list` work.
- `strings` unicode case folding + the unimplemented `strings` funcs (`SplitN`, `Trim*`,
  `Runes`, `ContainsAny`, `LastIndex`, …).
- `math` `Sqrt`/`Pow` (apd sig-digit context + NaN modeling) and trig/log/`Exp`.
- Imports/modules; pattern constraints beyond string-label representation; remaining alias
  positions; arithmetic-cycle handling.
