# Breadcrumb: test/fixture reorganization landed (partial) (2026-06-17)

Consolidation item 3's test/`testdata` reorg + Manifest-FieldClass tighten landed. Purely
organizational: no `.cue`/`.expected` byte changes, no theorem content changes, no
semantic behavior change. Module splits + `Field`→structure + base64-out-of-Json deferred.

## What landed

- **`testdata/cue/` flat→subsystem subdirs.** All 141 fixture pairs `git mv`'d (history
  preserved, pure renames) into 11 subdirs: `numeric/` (23), `definitions/` (25),
  `structs/` (24), `refs/` (15), `builtins/` (14), `lists/` (13), `disjunctions/` (7),
  `multiline/` (6), `comprehensions/` (5), `manifest/` (5), `bounds/` (4). Each pair's
  `.cue` + `.expected`(+`.manifest.expected`) sit together under one subdir.
  `testdata/export/` and `testdata/modules/` untouched.
- **`scripts/check-fixtures.sh` recursive.** Six flat `*.cue`/`*.expected` globs replaced
  by `find … -name '*.expected' -type f | sort` walks; basenames changed from `${f##*/}`
  to path-relative `${f#"${fixture_dir}/"}` so subdir structure round-trips into the
  generated tmpdir without collisions; CLI-output stage `mkdir -p`s the parent;
  `check_cli_behavior` sample moved to `numeric/additive_expressions.cue`. `cue fmt
  --check --files testdata/cue` already recurses. shellcheck clean.
- **`Kue/FixturePorts.lean`.** All 142 `fileName` entries rewritten to the
  `<subdir>/<stem>.expected` relative subpath; `writeFixturePort` `createDirAll`s the
  parent.
- **`Kue/Manifest.lean` (item 3f).** `manifestFieldsWithFuel`'s `_ =>` over `FieldClass`
  replaced by explicit `.field _ _ .regular`/`.optional` + `.letBinding` skip arms (after
  the `.field false false .regular` emit and `.field _ _ .required` incomplete arms). A new
  `Optionality` rung now breaks the build at the emission site. Behavior unchanged.

## Deferred (still queued under item 3)

- **Module splits (3d):** `FixturePorts.lean` (2293), `FixtureTests.lean` (1033),
  `BuiltinTests.lean` (735) by family. Pure test-file moves, no behavior. Deferred because
  splitting the single `def fixturePorts` list literal / interleaved theorem blocks needs
  exact comma/bracket boundary surgery, and this session's shell-output filter was
  non-deterministically truncating listing output (the CLAUDE.md-documented flip-flop) —
  unverifiable mid-stream. `BuiltinTests` is the cleanest next target (theorem names are
  family-prefixed: `close_`/`len_`/`and_`/`or_`/`div_`… core, `strings_*`, `list_*`, math,
  encoding). Use the Edit tool for the surgery, not bash text extraction.
- **`Field` tuple→`structure` (3e, ~95 sites)** and **base64-out-of-`Json` (3a)** — own
  slices.

## Verify state (all green)

- `lake build` — 84 jobs, all relocated theorems re-checked.
- `scripts/check-fixtures.sh` — `fixture pairs ok` (141 pairs from new locations; export +
  module stages byte-identical). `git diff -M` shows zero content lines changed (pure
  renames).
- `shellcheck scripts/check-fixtures.sh` — clean.

## Tooling note

The session's `bash` output was non-deterministically truncating/mangling directory
listings and `wc` counts (60/283/141/43 across identical runs — the CLAUDE.md filter
flip-flop). Reliable counts came from glob-into-positional-params (`set -- *.cue; echo
$#`) and reading temp files via the Read tool. Prefer those over piped `ls`/`find | wc`
in this repo.

## Next step

Resume the loop on **consolidation items 1+2 (paired):** `.conj` canonical member sort +
`intGe/Gt/Le/Lt`→`boundConstraint (bound, cmp, domain)` — they share
`meetConjValueWith`'s re-wrap + the canonical comparator; land item 3's representation
first, do item 1's commutativity theorems against the post-fold form. Then the rest of
item 3's deferred sub-tasks (module splits, `Field`→structure, base64-out-of-Json),
then item 4 Linux `cacheRoot` default.

Carry forward: **alpha cadence** ~1 datestamped release/day via `scripts/release.sh`, NO
CI (latest `v0.1.0-alpha.20260617.2`); **external repos read-only** (prod9/infra etc.).
A `/ace-audit` is due soon (this is ~the 4th slice since the Phase A/B audit batch).
