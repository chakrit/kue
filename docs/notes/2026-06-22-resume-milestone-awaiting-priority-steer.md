# RESUME HERE — high-value backlog DRAINED; awaiting a priority steer (2026-06-22)

Live START-HERE; supersedes `2026-06-21-resume-BI-2-DONE-next-EvalOps.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md) +
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Genuinely-open
backlog. Full per-slice history: [`../reference/implementation-log.md`](../reference/implementation-log.md).

## State — the high-value backlog is fully drained

All spec-conformance-HIGH + soundness + correctness work is DONE, green, pushed, audited:
D-area (cycles/guards/`let`-comprehensions), regex (corpus divergence-free), the full
math/string/list/Unicode builtins (incl. decimal `Sqrt`/`Pow`/`exp`/`ln` — see the new ADR),
qualified imports, the dyn-field correctness family (incl. 2 masked bottoms the adversarial
audits caught: RESID-MASK-1, the Manifest mask), the walker/normalizer dedups (AD4-1, A-EN3,
AD2-1; DRY-1 ruled out), soundness hardening (truncate-primitive, total `containsBottom`),
the closedness family (SC-1b/1c/1d/1e + EMBED-CLOSE-1). Docs reconciled + routed; `www/`
separated to repo root (human/server-facing, OUTSIDE the agent docs). Two alphas out.

**The once-"user-gated" trio was resolved AUTONOMOUSLY** (the user pushed back on the gating
— correctly): AD2-1 unified (lone-default marker provably vacuous), SC-3 settled by Kue's
display convention (show the full sound value), BI-2-residual shipped in exact decimal (NO
Float). See Lesson below.

## ⏸ PENDING — a priority steer from the user (the open question)

`/ace-save` was invoked right after I surfaced this. The remaining backlog is genuinely
LOW-impact and each slice is a real token spend, so I handed the priority call to the user:
**is the marginal remainder worth continuing, or is there something higher-value (on or off
this backlog) to move to?** Awaiting the steer. If the answer is "keep going", resume the
loop with the next leader below.

## Next leader (IF the loop resumes) — all autonomous, all low-impact

1. **EvalOps extraction** (plan item 2) — carve ~256 lines of pure scalar algebra to
   `Kue/EvalOps.lean`. Mechanical, parallel-safe, low-risk; NOT urgent (`Eval.lean` ~3702,
   under the ~4500 re-split watch).
2. **item-6 LOW list** (none block adoption; real configs / prod9 don't hit them):
   `import-eager-closedness` (MEDIUM — silent-admit on the eager selector path),
   `scalar-embed-with-decls`, `module-file-scoped-imports`, parser strictness (`__x`,
   `*(1|2)`), B3 (`comprehensionPairs .embeddedList`), B2-A1/A2, A2-x/y loader corners, the
   `selectEvaluatedField .disj` DRY, the `resolveEmbeddedDisjDefault` label-surfacing check.

## Audit + release state

- **Audit counter = 1** (BI-2-§3 = slice 1 of the new batch). Next two-phase audit due after
  2–3 slices. Last round closed clean (Phase A `778edb3` + Phase B `4863009`).
- **Release: a fresh daily alpha is cadence-due.** Last is `v0.1.0-alpha.20260621`; SC-1e,
  AD2-1, BI-2-residual, BI-2-§3 all landed AFTER it and are UNRELEASED. A `20260622` alpha
  (`scripts/release.sh 0.1.0-alpha.20260622`, attended) ships them. Not cut yet — deferred to
  the priority steer.

## Lesson (durable — also recorded in `../guides/slice-loop.md`)

Don't inherit audit "user-gated / human-signs-off" verdicts as gates — re-examine by
philosophy first; most resolve autonomously. AD2-1 was a soundness *analysis* (not a user
call); BI-2-residual was decimal-not-Float (the "needs Float" framing was inherited, wrong).
Reserve user-surfacing for forks where philosophy is genuinely silent AND the choice is
expensive to reverse. Default is resolve-and-proceed.

## Flag for ace-school

The `ace-docs` skill defines NO `www/` convention (only "HTML alongside the markdown").
This session established the rule by hand: `docs/` = agent/dev-facing markdown; `www/` (repo
root) = human/server-facing site — DON'T mix audiences. Worth proposing upstream to
`ace-docs` via `ace-school`.

## STANDING CONTEXT (full detail in CLAUDE.md + guides/slice-loop.md)

- Autonomy grant in effect; resolve forks by philosophy; commit/push on `main` (attended).
- Spec is authority; `cue` (`/Users/chakrit/go/bin/cue` v0.16.1) a fallible cross-check,
  never the gate. Correctness over byte-compat. kue binary: `.lake/build/bin/kue`.
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on the main tree.
- Orchestrator = thin re-spawner; one subagent per slice; two-phase audit (A then B) every
  2–3 slices. Per-slice duties: tests-first; log `cue-divergences.md`; flag `cue-spec-gaps.md`.
