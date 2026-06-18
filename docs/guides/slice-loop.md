# Slice Loop & Audit Cadence

The standing autonomous workflow for "keep going". Self-contained: the audit passes are
written here as procedures — **do NOT invoke the `/ace-audit` skill**; follow this guide.
The orchestrator is a thin re-spawner; every slice and every audit runs in a fresh
subagent. The orchestrator only does cheap done-checks and re-spawns.

## Design philosophy — type-system first (the audits enforce this)

Kue is in Lean 4 to make the type system do the work. This is the FIRST thing every audit
checks, not a nicety. In priority order:

1. **Make illegal states unrepresentable.** Encode invariants in the types so bad values
   cannot be constructed: precise `inductive`/`structure` over loose types guarded by
   runtime checks; a sum type over boolean/`Option` flags that admit nonsense
   combinations; newtype wrappers for distinct domains (ids, kinds, paths) so they can't
   be swapped; smart constructors where a raw one would admit junk. If a comment or branch
   says "this can't happen", the type is wrong — tighten it.
2. **Prefer ML / functional idioms.** Total functions over partial; `Except`/`Option`
   returns over hidden host-language failure; **exhaustive pattern matching with no
   catch-all `_` that silently swallows future constructors**; immutability; structural or
   fuel-bounded recursion over mutation. Push correctness into types + exhaustiveness, not
   into after-the-fact tests.
3. **Reach for dependent types / refinements where they buy real safety** (the standing
   grant) — not for their own sake. (Note the deliberate perf carve-out: `Value` omits
   `DecidableEq` because the kernel reduces it slowly; behavior is pinned by
   `native_decide`. Tightening representations is free; forcing kernel proofs is not —
   favor the former.)

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
`plan.md`, `implementation-log.md`, and the breadcrumb. Three standing duties: tests are
first-class (pin edges, not just happy path); log CUE divergences in
`cue-divergences.md`; when a slice changes eval cost or surfaces a slow/fast CUE pattern,
update [`kue-performance.md`](kue-performance.md). Oracle-check behavior against `cue`
(`/Users/chakrit/go/bin/cue`).

**Correctness over performance** (see
[the decision](../decisions/2026-06-18-correctness-over-performance.md)): never ship a
perf optimization that can return a wrong value. A perf slice needs byte-identical
fixtures + a soundness argument; if soundness cannot be guaranteed, **stop and report**
(file the design + the hole), do not ship it. But basic cases must stay usable — slowness
is a tracked bug, fixed only by sound optimization.

## Phase A — Code-quality audit (the diff/batch since the last audit)

Scope: the slices landed since the previous audit. Check:
- **Correctness** — behavior matches CUE/oracle; edge + error cases handled, not just the
  happy path.
- **Totality** — no unjustified `partial def` (the parser is the standing exception);
  fuel bounds provably sufficient.
- **Illegal-states-unrepresentable (the philosophy above — check it FIRST)** — does the
  new code use the tightest type that fits? Flag loose `String`/`Nat`/`Bool`/`Option`
  representations that should be sum types, newtypes, or refinements; flag any
  constructor/record that admits a nonsense combination; flag "can't happen" branches that
  a better type would erase. Every NEW `Value`/AST constructor handled at EVERY match site
  with NO catch-all `_` silently swallowing it; non-output markers (letBinding, thisStruct)
  excluded from `Format`/`Manifest` output. Partial functions that could be total → finding.
- **DRY / reuse** — no duplicated logic that should share a helper.
- **Test strength** — theorems/fixtures pin real behavior incl. edges, not smoke; every
  new fixture has BOTH a `testdata/.../.{cue,expected}` pair AND a `FixturePorts` entry.
- **Skill compliance** — `general-coding` rules (hard blockers); naming/readability.
- **Spec accuracy** — `plan.md` / `compat-assumptions.md` / log match the code.

Output: fold findings into `plan.md` as fix-slices. Apply only LOW-RISK fixes inline; if
you do, re-run the full verify gate and commit.

## Phase B — Architecture / refactor / cleanup audit (the whole module graph)

Scope: cross-cutting design, broader than the recent diff. Check:
- **Type-system leverage / ML idioms (the philosophy above — a top-level concern here).**
  Across the module graph, where are loose types carrying invariants that the type system
  could enforce? Candidates to propose as tightening fix-slices: stringly-typed data that
  should be a sum type; separate fields that should be one indexed/refined type; raw ids
  that should be newtypes; `Option`+invariant that a refined type subsumes; wildcard
  matches that hide cases; partial functions reducible to total. Push illegal states out
  of the representation — this is the repo's reason to be in Lean.
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
- **Performance-guide currency** — does [`kue-performance.md`](kue-performance.md) reflect
  current perf reality (new slow patterns surfaced, mitigations landed, stale
  known-limitations)? Update it inline or file the gap.

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
