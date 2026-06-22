# RESUME HERE — TL-2 landed (Depth/FieldIndex newtypes); audit counter = 2 (2026-06-22)

Live START-HERE; supersedes `2026-06-22-resume-after-TL-1.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md) +
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Genuinely-open
backlog. Full per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md).

## State — TL-2 DONE (slice 2 of the new batch)

The second slice of the post-audit batch landed: **TL-2 — `Depth`/`FieldIndex` newtypes
replace the two bare `Nat`s in `BindingId`** (type-leverage tightening,
illegal-states-unrepresentable, behavior-preserving).

**What changed.** `BindingId { depth : Nat, index : Nat }` carried two orthogonal
domains — `depth` (lexical frame offset) and `index` (field slot) — that compiled if
transposed (a `⟨index, depth⟩` swap was a type-correct bug). Now two single-field
`structure` newtypes in
`Value.lean` (zero-cost over `Nat`): `Depth { val : Nat }` / `FieldIndex { val : Nat }`,
both `deriving Repr, BEq, DecidableEq`, plus `OfNat` instances. `BindingId` is
`{ depth : Depth, index : FieldIndex }`. The two axes are now DISTINCT nominal types — a
`Depth` cannot be passed where a `FieldIndex` is expected (compile-checked); the
transposition class is unrepresentable.

**Why `OfNat` is load-bearing.** ~300 test sites build `BindingId` via the anonymous
constructor `.refId ⟨0, 0⟩`. Lean does NOT auto-flatten numeric literals into nested
single-field structures (`⟨0, 0⟩` tries `0 : Depth` directly and fails for lack of
`OfNat`). With `OfNat Depth`/`OfNat FieldIndex`, `⟨0, 0⟩` elaborates as
`⟨(0 : Depth), (0 : FieldIndex)⟩` — every literal stays byte-identical, zero churn at the
literal sites. (`BEq` + `OfNat` also keep `id.depth == 0` / `id.depth != 0` working.)

**Boundary discipline.** Consumers needing the raw `Nat` for frame arithmetic
(`env.drop id.depth.val`) or slot arithmetic (`nthField id.index.val`) unwrap with
`.val` — the explicit boundary. NO `Coe Depth Nat` (implicit widening would reopen the
swap).
`Hashable` NOT derived (the one digest site hashes through `.val`, so it'd be dead code).

**Sites touched (~57, all mechanical).** ONE construction site (`findInScopes` in
`Resolve.lean`, the sole producer of `BindingId` values); ~50 in `Eval.lean` (48 `.val`
projection-unwraps across the resolver/def-deferral tier + core `.refId` eval arm, 2
reconstruction-wraps `⟨id.depth, ⟨mergedIndex⟩⟩`); the `Format` residual-`refId` render
`s!"@{id.depth.val}.{id.index.val}"` (byte-identical); 4 test fixups where a COMPUTED
`Nat` (`bodyDepth`/`clauseChainDepth`) feeds a literal or a `.depth` comparison.

**Behavior-preserving.** `lake build` green (110 jobs, no new warning/`sorry`/axiom); full
suite + fixtures byte-identical green; pin-count conserved (pure type tightening). No CUE
divergence or spec gap surfaced. +5 `native_decide` pins (`ResolveTests`) locking the
surviving runtime contract — the swap-guard ITSELF is compile-time, so the pins cover the
`OfNat` literal ≡ explicit `.mk`, `.val` round-trip, and the bug-class witnesses
(`⟨2,5⟩ ≠ ⟨5,2⟩`, underlying-`Nat` distinctness for each newtype).

**Verify.** `lake build` green; `check-fixtures.sh` → `fixture pairs ok` (zero drift);
`shellcheck` n/a (no shell touched). Commit on `main`, pushed to `gh:main`.

## NEXT STEP — audit counter = 2; two-phase audit due after the NEXT slice (at 3)

**Audit counter = 2** (TL-1 = slice 1, TL-2 = slice 2 of this batch). A two-phase audit
(A: code-quality, then B: architecture — sequential, per
[`../guides/slice-loop.md`](../guides/slice-loop.md), do NOT invoke `/ace-audit`) is due
after the NEXT slice (slice 3). Run the ordinary slice loop — one subagent per slice —
then the audit.

### Next leader — the remaining item-6 LOW list (NONE soundness-bearing)

Both type-leverage tightenings (TL-1, TL-2) are now DONE. Pick opportunistically from the
item-6 LOW list (plan.md has full detail per item):

- **`scalar-embed-with-decls`** — `{#a:1, 5}` → `5` (Kue bottoms; incompleteness, not
  unsound). Needs a scalar-with-decls carrier. Rides along with **B3**
  (`comprehensionPairs .embeddedList` — `for x in {#a:1,[1,2]}` iterates zero times where
  CUE iterates `[1,2]`).
- **`module-file-scoped-imports`** (arch-sized) — per-file import scope frames.
- **Parser strictness** — `*(1|2)` laxity, `__x` double-underscore acceptance.
- **DRY items** — `selectEvaluatedField .disj` 5-arm collapse;
  `resolveEmbeddedDisjDefault` label-surfacing-narrowing check; B2-A1/A2 (tail-threading +
  test-gap); A2-x/y loader corners (import-name redeclaration).

`Eval.lean` at ~3377 is well under the ~4500 re-split watch — no carve pressure.
`EvalTests.lean` ~1480 approaching the test-org re-carve threshold (watch, not yet due).

## Release state — a fresh daily alpha is STILL cadence-due (attended)

Last release is `v0.1.0-alpha.20260621`. Landed AFTER it and UNRELEASED: SC-1e, AD2-1,
BI-2-residual, BI-2-§3, EvalOps, import-eager-closedness, the prior audit round, TL-1,
**and now TL-2**. Cut `v0.1.0-alpha.20260622` via
`scripts/release.sh 0.1.0-alpha.20260622` (attended — push/publish; CI/GitHub Actions
banned). Requires a clean tree (commit first). Awaiting user greenlight; not cut yet.

## STANDING CONTEXT (full detail in CLAUDE.md + guides/slice-loop.md)

- Autonomy grant in effect; resolve forks by philosophy; commit/push on `main` (attended).
- Spec is authority; `cue` (`/Users/chakrit/go/bin/cue` v0.16.1) a fallible cross-check,
  never the gate. Correctness over byte-compat. kue binary: `.lake/build/bin/kue`.
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on the main
  tree.
- Orchestrator = thin re-spawner; one subagent per slice; two-phase audit (A then B) every
  2-3 slices. Per-slice duties: tests-first; log `cue-divergences.md`; flag
  `cue-spec-gaps.md`.
