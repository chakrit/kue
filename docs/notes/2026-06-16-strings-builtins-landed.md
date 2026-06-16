# Session 2026-06-16 — strings builtin family landed

Latest resume breadcrumb. Supersedes the "Next session" section of
[`2026-06-16-struct-embedding-scope-landed.md`](2026-06-16-struct-embedding-scope-landed.md).
Resuming **implementation** next session.

## What was done

- **strings Builtins slice — DONE.** First package-qualified builtin family plus the
  dispatch infra it needed. Full record in
  [`../reference/implementation-log.md`](../reference/implementation-log.md) =>
  "Completed Slice: strings Builtins". Key points:
  - **Parser infra (the slice's core).** Package-qualified calls did not parse before.
    `parseSelectorRest` (in `Kue/Parse.lean`) now has a `'(' :: …` arm: a `.ref pkg`
    base + label + call emits `.builtinCall "pkg.label" args` (dotted name, no new
    `Value` constructor — reuses `.builtinCall`, so Resolve/Eval/Manifest/Format are
    untouched). `import "strings"` and grouped `import ( … )` are consumed and ignored
    (`consumeImportClauses`); the old "imports unsupported" parse error is gone, and the
    `parse_imports_are_unsupported` test was replaced by two import-ignored tests.
  - **Dispatch.** `evalBuiltinCall` catch-all routes `name.startsWith "strings."` to
    `evalStringsBuiltin` (in `Kue/Builtin.lean`). Args arrive fully evaluated.
  - **Implemented (11), oracle-exact vs `cue` v0.16.1:** `Contains`, `HasPrefix`,
    `HasSuffix`, `Index` (byte offset, `-1` miss), `Count` (non-overlapping; empty
    needle = runes+1), `Split` (empty sep = per-rune; keeps trailing empties), `Join`
    (non-string elem ⇒ bottom), `Replace` (count-limited; `<0` = all), `Repeat` (neg ⇒
    bottom), `TrimSpace`, `Fields`. Type-mismatch on concrete args ⇒ bottom; abstract
    args keep the call unresolved.
- Verify gate green: `lake build` (66 jobs), `scripts/check-fixtures.sh` =>
  `fixture pairs ok`, `shellcheck` clean. Tree clean, pushed.

## Next session — implementation focus

**Add the `list` builtin family** (next builtin family per `docs/spec/plan.md` =>
Builtin families). The package-qualified dispatch is now in place, so this is purely:
an `evalListBuiltin` helper in `Kue/Builtin.lean`, a catch-all route
(`name.startsWith "list."`) in `evalBuiltinCall`, a fixture pair, and `native_decide`
unit theorems in `Kue/BuiltinTests.lean`.

Candidates, oracle-check each against `cue` v0.16.1 before encoding (semantics have
edges — flatten depth, sort comparators, range bounds):

- `list.Concat([[…], […]])`, `list.FlattenN(list, depth)`, `list.Repeat(list, n)`,
- `list.Range(start, limit, step)`, `list.Slice`, `list.Take`/`Drop`,
- `list.Contains`, `list.Sort`/`list.SortStable` (comparator/`list.Ascending`),
- `list.Sum`, `list.Min`, `list.Max`, `list.Avg`.

Pick a coherent oracle-verifiable subset (correctness over breadth); note the rest as
remaining in the log + a new breadcrumb. One family per slice, one commit.

### Mechanics reminder

- `cue` needs file args (`cue export --out cue file.cue`), needs the `import "list"`
  line for `list.*`; `kue` reads stdin. `.expected` files are **kue's** output format
  (single-space `label: value`), NOT `cue fmt`'s column alignment — generate them by
  running `kue` on the (cue-fmt'd) `.cue` source. The check script runs
  `cue fmt --check` on `.cue` sources, so `cue fmt --files testdata/cue/<f>.cue` first.
- New fixtures need BOTH a `.cue`/`.expected` pair AND a hand-built `FixturePorts.lean`
  entry; the check script diffs the CLI path and the Lean-port path and flags any
  `.expected` lacking a port.
- `Value` derives `BEq` but **not** `DecidableEq` — assert eval results in tests as
  `(a == b) = true := by native_decide`, not `a = b := by decide`.

### Also pending (later slices, unchanged)

- Deferred `strings` funcs needing unicode case folding (`ToUpper`/`ToLower`/`ToTitle`)
  and the rest (`SplitN`, `Trim*`, `Runes`, `ContainsAny`, `LastIndex`, …).
- `math` builtin family.
- Expand pattern constraints beyond string-label representation; remaining alias
  positions in a syntax layer; arithmetic-cycle handling; imports/modules (real symbol
  binding — currently imports are parsed-and-ignored).
