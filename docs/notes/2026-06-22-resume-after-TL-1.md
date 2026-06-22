# RESUME HERE — TL-1 landed (BuiltinFamily enum); audit counter = 1 (2026-06-22)

Live START-HERE; supersedes `2026-06-22-resume-after-two-phase-audit-CLOSED.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md) +
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Genuinely-open
backlog. Full per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md).

## State — TL-1 DONE (slice 1 of the new batch)

The first slice of the post-audit batch landed: **TL-1 — closed `BuiltinFamily` enum
replaces stringly-typed builtin dispatch** (type-leverage tightening with a
soundness-adjacent correction).

**What changed.** `evalBuiltinCall` (`Kue/Builtin.lean`) dispatched the builtin FAMILY
axis off a bare `String` — an 8-way exact match + a 7-way `name.startsWith "strings."/…`
prefix chain falling through to a **silent `.builtinCall` residual** when nothing matched
(an unknown name with CONCRETE args manifested as a non-error `incomplete value`, masking
a CUE resolution error). Now: a closed `BuiltinFamily` enum (`core` + the 7 qualified
packages `strings`/`list`/`math`/`regexp`/`base64`/`json`/`yaml`), a single total
classifier `BuiltinFamily.ofName?`, and an EXHAUSTIVE match in `evalBuiltinCall` (no
catch-all → a new family forces a dispatch arm). The non-builtin (`none`) case routes
through `unresolvedOrBottom`: concrete args ⇒ BOTTOM (conforms to `cue`'s `reference …
not found` / `cannot call non-function`), abstract args ⇒ deferred residual (preserved).
The 8 `core` exact-name arms moved to `evalCoreBuiltin`.

**Classification point.** At the one place the name is read as a builtin
(`evalBuiltinCall`) — the parser CANNOT classify earlier (it can't tell `strings.X` from a
user `pkg.X`; both parse to `.builtinCall`). The enum lives in `Builtin.lean` (the only
consumer — no new import edge; graph stays acyclic).

**Unknown-builtin behavior resolved.** WAS: silent `.builtinCall` residual (→ `incomplete
value`). IS: bottom on concrete args, deferred on abstract. Basis: spec is silent on the
diagnostic, lattice first principles decide the verdict (an unresolved builtin is bottom,
never a silent pass-through), and `cue` agrees on the bottom verdict. 1 cue-divergence
(generic vs name-specific bottom message — value agrees) + 1 spec-gap
(unimplemented-builtin diagnostic) recorded.

**Behavior-preserving for known builtins.** The `BuiltinTests.lean` net (~140 pins, ≥1 per
family) stays byte-identical green; +13 new pins (classifier contract, the corrected
unknown-name cases, a yaml family pin). End-to-end: `strings.ToUpper`/`math.Pow`/`len`
unchanged; `foobar.Baz("a")`/`error("boom")` now bottom.

**Verify.** `lake build` green (110 jobs, no new warning/`sorry`/axiom; `evalBuiltinCall`
depends only on the 3 standard axioms); `check-fixtures.sh` → `fixture pairs ok` (zero
drift); `shellcheck` n/a (no shell touched). Commit on `main`, pushed to `gh:main`.

## NEXT STEP — audit counter = 1; resume the slice loop

**Audit counter = 1** (TL-1 is slice 1 of the new batch). Next two-phase audit is due
after 2–3 slices (so after TL-2 + one more, or sooner if a slice warrants). Resume the
ordinary slice loop (one subagent per slice per
[`../guides/slice-loop.md`](../guides/slice-loop.md)).

### Next leader — TL-2, then the rest of the item-6 LOW list (NONE soundness-bearing)

- **TL-2 (LOW-MED, the lower-risk mechanical one) — `BindingId` packs two swappable bare
  `Nat`s.** `BindingId { depth : Nat, index : Nat }` (`Value.lean:495`): `depth` (lexical
  frame-offset) and `index` (field slot) are orthogonal domains that compile if swapped.
  Newtype-wrap both (`Depth`/`FieldIndex`, zero-cost erasure) to make the coordinate-swap
  class unrepresentable. ~50 construction/match sites; zero behavioral risk. File-and-do.
- Then the rest of item-6 (plan.md has full detail; pick opportunistically):
  `scalar-embed-with-decls` (pairs with **B3** `comprehensionPairs .embeddedList`),
  `module-file-scoped-imports` (arch-sized), parser strictness (`__x`, `*(1|2)`), the DRY
  items (`selectEvaluatedField .disj` 5-arm collapse; `resolveEmbeddedDisjDefault`
  label-surfacing check; B2-A1/A2; A2-x/y loader corners).

`Eval.lean` at 3377 is well under the ~4500 re-split watch — no carve pressure.
`EvalTests.lean` ~1480 approaching the test-org re-carve threshold but not yet due (watch
it). `BuiltinTests.lean` grew with TL-1 (~1090) but is cohesive — no carve needed.

## Release state — a fresh daily alpha is STILL cadence-due (attended)

Last release is `v0.1.0-alpha.20260621`. Landed AFTER it and UNRELEASED: SC-1e, AD2-1,
BI-2-residual, BI-2-§3, EvalOps, import-eager-closedness, the prior audit round, **and now
TL-1**. Cut `v0.1.0-alpha.20260622` via `scripts/release.sh 0.1.0-alpha.20260622`
(attended — push/publish; CI/GitHub Actions banned). Requires a clean tree (commit first).
Awaiting user greenlight; not cut yet.

## STANDING CONTEXT (full detail in CLAUDE.md + guides/slice-loop.md)

- Autonomy grant in effect; resolve forks by philosophy; commit/push on `main` (attended).
- Spec is authority; `cue` (`/Users/chakrit/go/bin/cue` v0.16.1) a fallible cross-check,
  never the gate. Correctness over byte-compat. kue binary: `.lake/build/bin/kue`.
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on the main
  tree.
- Orchestrator = thin re-spawner; one subagent per slice; two-phase audit (A then B) every
  2-3 slices. Per-slice duties: tests-first; log `cue-divergences.md`; flag
  `cue-spec-gaps.md`.
