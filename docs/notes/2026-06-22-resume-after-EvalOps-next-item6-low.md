# RESUME HERE — EvalOps DONE; next leader is the item-6 LOW list (2026-06-22)

Live START-HERE; supersedes `2026-06-22-resume-milestone-awaiting-priority-steer.md`
(deleted). Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md) +
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Genuinely-open
backlog. Full per-slice history: [`../reference/implementation-log.md`](../reference/implementation-log.md).

## State — EvalOps landed; high-value backlog still drained

**EvalOps extraction (plan item 2) is DONE, green** (the priority steer resumed the loop).
Carved the pure scalar algebra (`evalAdd…evalDiv`, `evalEq…evalBinary`,
`distributeUnary`/`distributeBinary`, `collapseDefaultDisjunction`,
`classifyArithOperand`/`arithmeticDomainResult`/`evalRepeat`) out of `Eval.lean` into
`Kue/EvalOps.lean` (346 lines). `Eval.lean` 3701 → 3377 (−324). **Import shape = option (a):**
`EvalOps → {Builtin, Decimal, Regex}` — rejected moving `div`/`mod`/`quo`/`remValue` into
EvalOps because they ALSO back the `div`/`mod`/`quo`/`rem` builtins (`Builtin.lean:892`), so
moving them would force a worse `Builtin → EvalOps` edge. Graph acyclic. Behavior-preserving;
all pins + fixtures green; **+18 `native_decide` pins** added in `EvalTests.lean` (comparison
ops incl. incomparable-kind/bool-unordered → bottom, `evalEq`/`evalNe`, boolean ops, unary
±/! incl. non-numeric/non-bool → bottom + incomplete-defer — gap-closing, these had only
fixture coverage before).

Everything else stays as in the prior breadcrumb: D-area, regex, the full
math/string/list/Unicode builtins (incl. the now-COMPLETE BI-2 family), qualified imports,
the dyn-field correctness family, the walker/normalizer dedups, soundness hardening, the
closedness family — all DONE, green, pushed, audited.

## Next leader (loop continues) — item-6 LOW list (all autonomous, all low-impact)

None block adoption; real configs / prod9 don't hit them. The one genuine
soundness-adjacent item is the leader:

1. **`import-eager-closedness` (MEDIUM)** — silent-admit on the eager selector path. The one
   real soundness-adjacent item left in the LOW list. Start here.
2. The rest of item 6 (opportunistic): `scalar-embed-with-decls`,
   `module-file-scoped-imports`, parser strictness (`__x`, `*(1|2)`), B3
   (`comprehensionPairs .embeddedList`), B2-A1/A2, A2-x/y loader corners, the
   `selectEvaluatedField .disj` DRY, the `resolveEmbeddedDisjDefault` label-surfacing check.

`Eval.lean` at 3377 is well under the ~4500 re-split watch — no further carve pressure.

## Audit + release state

- **Audit counter = 2** (BI-2-§3 = slice 1, EvalOps = slice 2 of the batch). **A two-phase
  audit (A then B, sequential) is DUE after the next slice** — spawn per
  [`../guides/slice-loop.md`](../guides/slice-loop.md), do NOT invoke `/ace-audit`. Last round
  closed clean (Phase A `778edb3` + Phase B `4863009`).
- **Release: a fresh daily alpha is cadence-due.** Last is `v0.1.0-alpha.20260621`; SC-1e,
  AD2-1, BI-2-residual, BI-2-§3, **and now EvalOps** all landed AFTER it and are UNRELEASED.
  A `20260622` alpha (`scripts/release.sh 0.1.0-alpha.20260622`, attended — push/publish) ships
  them. Not cut yet.

## STANDING CONTEXT (full detail in CLAUDE.md + guides/slice-loop.md)

- Autonomy grant in effect; resolve forks by philosophy; commit/push on `main` (attended).
- Spec is authority; `cue` (`/Users/chakrit/go/bin/cue` v0.16.1) a fallible cross-check,
  never the gate. Correctness over byte-compat. kue binary: `.lake/build/bin/kue`.
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on the main tree.
- Orchestrator = thin re-spawner; one subagent per slice; two-phase audit (A then B) every
  2–3 slices. Per-slice duties: tests-first; log `cue-divergences.md`; flag `cue-spec-gaps.md`.
