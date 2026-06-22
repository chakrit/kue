# RESUME HERE — scalar-embed-with-decls + B3 landed; audit counter = 3 → AUDIT DUE (2026-06-22)

Live START-HERE; supersedes `2026-06-22-resume-after-TL-2.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md) +
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Genuinely-open
backlog. Full per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md).

## State — scalar-embed-with-decls + B3 DONE (slice 3 of the post-audit batch)

The third slice landed: a **scalar-with-decls carrier** + the **B3 ride-along**, closing
two struct-embedding incompleteness gaps without crossing the soundness boundary.

**What changed.** New `Value.embeddedScalar (scalar) (decls)` ctor — the direct scalar
analog of `.embeddedList`. A struct embedding a scalar PLUS non-output decls (`{#a:1, 5}`)
now manifests as the scalar `5` while keeping `.#a` selectable (`x.#a → 1`); Kue used to
bottom. Built at embed-eval (`meetEmbeddingsWithFuel`) when the host has no output field,
HAS decls, and the embedding is a terminal scalar (`isTerminalScalar`). B3:
`comprehensionPairs` gained the `.embeddedList items _ _ => some (listPairsFrom 0 items)`
arm, so `for x in {#a:1,[1,2]}` iterates `[1,2]` (was zero).

**Soundness boundary HELD.** The pure `{5}`→`5` collapse (`collapsesToScalarEmbed`, no
decls) is UNTOUCHED — the carrier is a SEPARATE branch for the decls-present case.
Widening the collapse to admit decls is the unsound direction (would DROP them); avoided.
A genuine conflict (`{#a:1,5,6}`) holds an inline bottom → `containsBottom` flags →
export rejects (cue-faithful). Soundness-net pins green throughout: pure `{5}` collapse,
`{5,6}`/`{a:1,5}`/`{#a:1,5,6}` conflicts, conflict-select reject.

**New-ctor discipline.** `.embeddedScalar` handled at EVERY match site, no catch-all
swallow: Lattice (meet arms + `containsBottom` + `meetCore`), Eval (select/definedness/
guard/dynlabel/digest/tag + `foldValueWithDepth`/`remapConjRefs` walkers), EvalOps
(`resolveOperand` UNWRAPS to scalar before arith + `classifyArithOperand`),
Format/Manifest/Normalize×2/Runtime. `hasSelfRefAtDepth` correctly leaves it to the
catch-all (post-eval carrier, never in a raw def body — same as `.embeddedList`). Detail:
the implementation-log entry for this slice.

**Verify.** `lake build` green (110 jobs, no new warning/`sorry`/axiom; axiom-clean);
`check-fixtures.sh` → `fixture pairs ok`, zero drift (4 expected fixture additions);
`shellcheck` n/a. 1 cue-divergence (non-iterable `for` zero-iter, PRE-EXISTING) + 1
spec-gap (carrier semantics) recorded. Commit on `main`, pushed to `gh:main`.

## NEXT STEP — audit counter = 3 → TWO-PHASE AUDIT (A then B) IS DUE

**Audit counter = 3** (TL-1, TL-2, scalar-embed-with-decls). A two-phase audit — **(A)
code-quality, then (B) architecture — sequential, per
[`../guides/slice-loop.md`](../guides/slice-loop.md), do NOT invoke `/ace-audit`** — is
DUE NOW, before the next feature slice. The orchestrator runs it next.

Audit focus for THIS batch's diff (Phase A): the new `.embeddedScalar` ctor — confirm
EVERY match site has an explicit arm (no catch-all swallow), the producer gate is correct
(pure collapse untouched), the `classifyGuard`/`classifyDynLabel`/`classifyArithOperand`
recursion onto the inner scalar is sound + total, and `resolveOperand`'s unwrap doesn't
mis-fire. Phase B: whether `.embeddedScalar` + `.embeddedList` should share representation
(parallel structures over the same "struct-reduces-to-embedded-value-with-decls" domain —
but a scalar is not a list, so a forced merge is likely false-sharing; rule on it).

### Next leader (after the audit) — the remaining item-6 LOW list (NONE soundness-bearing)

Pick opportunistically (plan.md item 6 has full detail per item):

- **`module-file-scoped-imports`** (arch-sized) — per-file import scope frames.
- **Parser strictness** — `*(1|2)` laxity, `__x` double-underscore acceptance.
- **DRY items** — `selectEvaluatedField .disj` 5-arm collapse;
  `resolveEmbeddedDisjDefault` label-surfacing-narrowing check; B2-A1/A2 (tail-threading +
  test-gap); A2-x/y loader corners (import-name redeclaration).
- **`scalar-embed` provenance follow-ups** — opportunistic pins when next touching
  Lattice/Eval.

`Eval.lean` at ~3400 is well under the ~4500 re-split watch. `EvalTests.lean` growing —
watch the test-org re-carve threshold (not yet due).

## Release state — a fresh daily alpha is STILL cadence-due (attended)

Last release is `v0.1.0-alpha.20260621`. Landed AFTER it and UNRELEASED: SC-1e, AD2-1,
BI-2-residual, BI-2-§3, EvalOps, import-eager-closedness, the prior audit round, TL-1,
TL-2, **and now scalar-embed-with-decls + B3**. Cut `v0.1.0-alpha.20260622` via
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
