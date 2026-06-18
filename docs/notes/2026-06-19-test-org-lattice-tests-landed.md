# RESUME HERE — test-org pass + LatticeTests LANDED (2026-06-19)

Supersedes the prior START-HERE pointer
(`2026-06-19-b7-descendclauses-unification-landed.md`). Standing grant in effect (autonomy
/ Lean-into-Lean-4 / commit-push freely / specs as restore point). Full record:
`docs/reference/implementation-log.md` ("test-org pass (EvalTests split) + B4
LatticeTests" entry); ranked work: `docs/spec/plan.md` (Live Backlog — item 5 + B4 now
DONE).

## What landed — two commits on `main`

Part 1 (test-org split) + Part 2 (LatticeTests), pushed to `gh:main`.

### Part 1 — `EvalTests.lean` split (item 5, behavior- and coverage-preserving)

`EvalTests.lean` (~3022 lines) split by subsystem into per-`Kue/`-area modules, cut at the
existing section seams. Coverage preserved EXACTLY (verified pre/post): theorem 256→256,
native_decide 253→253, def 28→28. Zero fixture byte-drift.

- `EvalTestHelpers.lean` — shared `evalSourceMatches` + new `exportJsonMatches` source
  oracles (the only cross-cutting helpers; imported by all split modules).
- `EvalPerfTests.lean` (~470) — frame-id sharing, Pass-2 selective re-eval,
  fuel-saturation, perf-B memo pins.
- `ClosureTests.lean` (~762) — closure ctor/eval/producer/meet, embed chains,
  import-selector aliases.
- `TwoPassTests.lean` (~611) — two-pass gate, B1/A1/A5 remap, B7 `descendClauses`
  agreement, hidden-def + embed-disj narrowing.
- `EvalTests.lean` (slimmed ~1210) — ref/selector/cycle eval, arithmetic/ordering/unary,
  list-comprehensions, scalar-embed collapse, F1 default-mark algebra, refs/aliases,
  lazy-chain.

All wired into `Kue/Tests.lean`. `testdata/` untouched. NOT split (future ride-along):
`FixturePorts` (generated), `FixtureTests`, `StructTests`, `BuiltinTests`.

### Part 2 — `LatticeTests.lean` (B4 + B2 regression gate)

27 `meet`/`join` algebra pins: lattice laws, scalars, kinds, bounds, regex, lists,
disjunctions, and the struct-shape arms B2 collapses. Struct arms pinned via SOURCE-level
JSON `export` (`exportJsonMatches`), NOT internal constructor RHS — so they survive B2's
constructor collapse as a regression gate. Covered: struct×struct (open + closed-reject),
tail×tail, pattern×pattern, pattern×patterns, patterns×patterns.

**Option (b) taken for the known-incomplete arms.** `meetWithFuel` is MISSING
`structPattern×structTail` and `structPatterns×structTail` (both orders) → they hit the
catch-all → `meetCore` → `.bottom`, where cue unifies (`{[string]: int} & {a: 5, ...}` →
cue `{a: 5}`, kue `_|_`). No expected-fail marker exists in the Lean harness and the A2
rule forbids pinning the wrong `.bottom`, so these are DOCUMENTED in the
`LatticeTests.lean` header + the plan's B2 entry, NOT given a passing test. This is a Kue
bug (Kue wrong) → it lives in the plan, NOT `cue-divergences.md`. Corrected a stale plan
claim: `structPattern×structPatterns` is already implemented (`Lattice.lean:1015-1034`)
and is now pinned.

## Verify (all green)

`lake build` 96 jobs; `scripts/check-fixtures.sh` → `fixture pairs ok` (ZERO byte-drift
after both parts). No shell scripts changed (shellcheck N/A). Pure test-reorg + new test
module, no `Kue/` source change → perf unchanged. Struct expectations oracle-checked vs
`cue` v0.16.1.

## Next step — TWO-PHASE AUDIT IS DUE

This is the 2nd slice since the last audit (B7 + this test-org/LatticeTests slice). Per
the slice-loop cadence (every 2-3 slices), the two-phase audit is due NEXT — or it may be
deferred to land immediately after B2 (the orchestrator's call; B2 is the next headline
and is now de-risked). Run it per `docs/guides/slice-loop.md` (do NOT invoke
`/ace-audit`): (A) code-quality audit, then (B) architecture/refactor audit over the whole
module graph.

Then, ranked (plan.md Live Backlog sequence):

1. **B2** — headline 5-struct-constructor unification (collapse `struct`/`structTail`/
   `structPattern`/`structPatterns`/`structComp` into one normalized `struct` with a
   3-state `StructOpenness`). NOW DE-RISKED: `LatticeTests.lean` pins the correct arms
   (the migration's regression gate) and documents the two missing `pattern×tail` arms B2
   must ADD (flip them to passing pins). Design-spike first, then mechanical multi-commit
   migration.
2. **B6** design-spike / **A2-followup** import-binding marker / **item 1** follow-up
   (full `apps/argocd.cue` end-to-end).
3. **Parallel-safe cleanups:** items 3 (Regex extraction) / 4 (EvalOps extraction) / B5;
   remaining test-org for `FixtureTests`/`StructTests`/`BuiltinTests`; B4 ride-along
   `DecimalTests`/`FormatTests`.
