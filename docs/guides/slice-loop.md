# Slice Loop & Audit Cadence

The standing autonomous workflow for "keep going". Self-contained: the audit passes are
written here as procedures — **do NOT invoke the `/ace-audit` skill**; follow this guide.
The orchestrator is a thin re-spawner; every slice and every audit runs in a fresh
subagent. The orchestrator only does cheap done-checks and re-spawns.

## Cadence (repeat indefinitely)

1. Run **2–3 implementation slices** (one subagent each, one commit each).
2. **Code-quality audit** (one subagent; Phase A below).
3. **Architecture / refactor / cleanup audit** (one subagent; Phase B below).
4. Fold all findings into `docs/spec/plan.md` as fix-slices (ranked). Fix-slices count as
   implementation slices in the next round.
5. Go to 1.

Audits are mandatory at the 2–3-slice mark, not optional, and run **A then B,
sequentially** (both edit `plan.md`; parallel would collide). Don't let them stall forward
motion, but don't skip them.

Periodic, not every cycle:
- **Test/fixture organization pass** — when test files or `testdata/` have grown unwieldy,
  spend a slice reorganizing (group by subsystem, split oversized modules, dedupe
  fixtures, tidy `testdata/` layout). Phase B flags when it's due; schedule it as a slice.
- **Release** — see "Releases" below (~1 datestamped alpha/day, local script, no CI).

## Slice (per subagent)

Full workflow in fresh context: plan → TDD → implement → verify (`lake build` +
`scripts/check-fixtures.sh` + `shellcheck`) → commit/push to `gh:main` → update
`plan.md`, `implementation-log.md`, and the breadcrumb. Two standing duties: tests are
first-class (pin edges, not just happy path); log CUE divergences in
`cue-divergences.md`. Oracle-check behavior against `cue` (`/Users/chakrit/go/bin/cue`).

## Phase A — Code-quality audit (the diff/batch since the last audit)

Scope: the slices landed since the previous audit. Check:
- **Correctness** — behavior matches CUE/oracle; edge + error cases handled, not just the
  happy path.
- **Totality** — no unjustified `partial def` (the parser is the standing exception);
  fuel bounds provably sufficient.
- **Illegal-states-unrepresentable** — every NEW `Value`/AST constructor handled at EVERY
  match site (no silent wildcard `_` absorption); non-output markers (letBinding,
  thisStruct) excluded from `Format`/`Manifest` output.
- **DRY / reuse** — no duplicated logic that should share a helper.
- **Test strength** — theorems/fixtures pin real behavior incl. edges, not smoke; every
  new fixture has BOTH a `testdata/.../.{cue,expected}` pair AND a `FixturePorts` entry.
- **Skill compliance** — `general-coding` rules (hard blockers); naming/readability.
- **Spec accuracy** — `plan.md` / `compat-assumptions.md` / log match the code.

Output: fold findings into `plan.md` as fix-slices. Apply only LOW-RISK fixes inline; if
you do, re-run the full verify gate and commit.

## Phase B — Architecture / refactor / cleanup audit (the whole module graph)

Scope: cross-cutting design, broader than the recent diff. Check:
- **Module boundaries & layering** — import edges sane (e.g. `Builtin → Decimal`, never
  `Builtin → Eval`); no cycles; one clear responsibility per module.
- **Abstraction quality** — right representations; illegal states unrepresentable at the
  type level; leaky or missing abstractions; modules that have outgrown their home.
- **Refactor / cleanup** — dead code, deprecated APIs (e.g. `String.dropRight`),
  duplication ACROSS modules, functions in the wrong place.
- **Simplification** — complexity that can be removed; over-engineering.
- **Tech-debt & consistency** — divergent patterns across similar code; stale TODOs;
  `compat-assumptions` entries that have accumulated and should become real slices.
- **Test/fixture health** — coverage gaps at the seams; oversized test modules or messy
  `testdata/` that warrant the organization pass; fixture-harness debt.

Output: fold findings into `plan.md` as architecture fix-slices (ranked); large refactors
become their own planned slices. Apply only low-risk cleanups inline (re-verify + commit).

## Releases (local only — CI/GitHub Actions is BANNED)

- Cadence: roughly **one alpha release per day**, datestamped where it makes sense
  (e.g. `0.1.0-alpha.YYYYMMDD`). More often only on a notable milestone.
- Mechanism: `scripts/release.sh <version>` — builds the host arm64 binary, publishes the
  GitHub Release asset via `gh`, and patches + pushes the `chakrit/homebrew-tap` formula.
  No CI, no Actions, ever. Requires a clean working tree (commit first).
- Cut from current `main` HEAD; alpha quality is fine to ship with documented known gaps.

## Notes

- The orchestrator's only between-step job is the cheap done-check (git state + one
  build/fixture run), never the deep work.
- No manual `/ace-save` or `/clear` between slices — the subagent boundary gives fresh
  context; the breadcrumb gives continuity.
