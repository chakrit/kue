# `testdata/wild/` — wild-caught regression fixtures

Real-world cases that surfaced a Kue divergence **outside** a planned slice (a prod9 app
export, a manual run, a stumble). The highest-signal tests we have — the corpus the curated
canaries miss. Procedure: [`../../docs/guides/slice-loop.md`](../../docs/guides/slice-loop.md)
("Wild-caught regressions"). Standing duty: project [`CLAUDE.md`](../../CLAUDE.md).

Rules (full text in the guide):

- **Captured FIRST, before the fix** — the fixture must reproduce (fail) red first; the fix
  turns it green; it stays a permanent guard.
- **Minimal + self-contained** — lift the offending construct out of any private dep; no
  registry/network/prod9 needed to run it.
- **Expected value is SPEC-adjudicated, never `cue`-matched** — `cue` is a fallible
  reference; a `bottom`/diff vs `cue` may be `cue`'s bug. Pin the spec-correct value; log any
  `cue` disagreement in `../../docs/spec/cue-divergences.md`.

Layout per case — `testdata/wild/<slug>/`:

- `<slug>.cue` — the minimal repro (+ a tiny `cue.mod/` module repro only if the bug is
  import/module-shaped).
- `<slug>.expected` — the spec-correct output (the assertion).
- `PROVENANCE.md` — one line: source app + date + the CUE construct at fault + spec basis.

AUTO-DISCOVERED by `check_wild_fixtures` in `scripts/check-fixtures.sh` — every
non-quarantined `<slug>/` dir is enforced (a `.known-red` marker quarantines a
captured-but-unfixed case; delete it when the fix lands to re-arm the guard). No
registration step. Wild fixtures are enforced ONLY by that shell gate — `lake build`
never sees them.
