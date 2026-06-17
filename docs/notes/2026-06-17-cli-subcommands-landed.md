# Breadcrumb: proper CLI — subcommands, `--help`, `version` (2026-06-17)

## What landed

The CLI is now a real subcommand dispatcher instead of ad-hoc argv branching in `Main.lean`.

- **`Kue/Cli.lean` (new).** Pure `parse : List String → Command`; `Command` sum type:
  `eval (files)`, `export (ExportOpts)`, `version`, `help (Option HelpTopic)`, `error msg`.
  Help text (`topLevelHelp`/`evalHelp`/`exportHelp`/`helpText`) lives here too.
- **`Main.lean` rewritten** to `runCommand (Kue.Cli.parse args)` — exhaustive dispatch.
- **Surface:** `kue eval [file…]` (explicit name for the default internal-format path),
  `kue export [--out json|yaml] [file]` (unchanged), `kue version`/`--version`/`-V`,
  `kue help [eval|export]`/`--help`/`-h`.
- **`Kue.version`** = `"0.1.0-alpha"` in `Kue/Runtime.lean` — the single in-binary source
  of truth. Static placeholder; trails the release tag until a future `release.sh` step
  rewrites it (noted in RELEASE.md; release.sh NOT touched this slice).
- **Back-compat:** unknown first token (not a subcommand/flag) → eval positionals, so
  `kue < file`, `kue <file…>`, `kue export …` are byte-identical. Confirmed via full
  `check-fixtures.sh`.
- **Exit codes:** `2` usage error, `1` eval/parse/manifest error, `0` success. Missing
  file → `kue: cannot read <path>: …` (clean, no uncaught exception).

## Verify state (all green)

- `lake build` — 84 jobs.
- `scripts/check-fixtures.sh` — `fixture pairs ok` (now includes additive
  `check_cli_behavior` stage).
- `shellcheck scripts/check-fixtures.sh` — clean.
- 25 `CliTests.lean` `native_decide` theorems pin the parse.

## Tests added

- `Kue/CliTests.lean` — 25 parse theorems (bare files, all subcommands + flag spellings,
  every error path).
- `check-fixtures.sh` `check_cli_behavior` — `--help` lists subcommands; `version`/
  `--version` print + agree; `eval` byte-matches bare path; `--bogus` and
  `export --out bogus` exit non-zero with the right stderr substring.
- `packaging/homebrew/kue.rb` `test do` now asserts `kue version` (in-repo copy only).

## Next step

Plan item 2: **open-list collapse on Manifest** (`[1,...]` → concrete `[1]` at manifest
time; `Manifest` currently returns `.incomplete` for a bare `listTail`). Confirm cue's
exact collapse rule against the oracle, then fix `Manifest`'s `listTail`/`embeddedList`-
with-tail arm. After that, the consolidation+test-reorg batch (items 3–4): `boundConstraint`
refactor (now also carrying the decimal/domain bound generalization — see the int-bound
breadcrumb), base64-out-of-`Json`, `testdata/cue/` subsystem reorg, `Field`→`structure`,
Manifest-dispatch tighten.

## Carry-forward

- Alpha cadence: ~1 datestamped cut/day via `scripts/release.sh`, NO CI. Latest is
  `v0.1.0-alpha.20260617.2`. Do NOT touch `scripts/release.sh` / `packaging/` (beyond the
  in-repo formula `test` block) / release files / the tap repo.
- `Kue.version` (`Kue/Runtime.lean`) is where release.sh should bump the in-binary version
  when that wiring is added.
- External repos (prod9, cue cache) are READ-ONLY.
- No tree-reverting git; revert via Edit; `/tmp` for experiments.
