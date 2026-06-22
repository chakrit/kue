# RESUME HERE — import-eager-closedness DONE; TWO-PHASE AUDIT NOW DUE (2026-06-22)

Live START-HERE; supersedes `2026-06-22-resume-after-EvalOps-next-item6-low.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md) +
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Genuinely-open
backlog. Full per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md).

## State — import-eager-closedness landed; the LAST soundness-adjacent LOW item is closed

**`import-eager-closedness` (plan item 6 MEDIUM) is DONE, green, pushed.** A SOUNDNESS fix: an
imported plain closed def selected via the EAGER selector path SILENTLY ADMITTED extra fields
(the force path closed correctly — the two paths disagreed). Fixed via **option (b),
structurally unified**: a new single `selectedFieldValue` (`Eval.lean`) closes a SELECTED
DEFINITION field's body through `normalizeDefinitionValueWithFuel`; all four eager pluck sites in
`selectEvaluatedField` route through it, so the eager and force paths share ONE closing decision
and CANNOT disagree. Option (a) (close at load) rejected — the A2 trap (closing a whole bound
package re-closes unreferenced nested defs). Both facets pinned (silent-admit + incomplete-mask),
plus over-close guard (`...` def stays open) + pattern edges (admit match, reject non-match). 7
`native_decide` pins (`ClosureTests ### import-eager-closedness`) + 1 corrected pre-existing pin
+ 2 module fixtures. 1 cue-divergence (incomplete-mask error message — value agrees, both bottom).
`selectedFieldValue` axiom-clean (`propext` only). cert-manager/argocd cross-package hot-path
fixtures byte-identical.

Everything else stays as in the prior breadcrumb: D-area, regex, the full
math/string/list/Unicode builtins (BI-2 family COMPLETE), qualified imports, EvalOps, the
dyn-field family, the walker/normalizer dedups, soundness hardening — all DONE, green, pushed,
audited. **The closedness family is now FULLY CLOSED** (SC-1/1b/1c/1d/1e + SC-2 + EMBED-CLOSE-1 +
import-eager); the only remaining import corner is unreferenced-import LAZINESS, a deliberate
ratified gap.

## NEXT STEP — TWO-PHASE AUDIT (A then B), MANDATORY, BEFORE any feature slice

**Audit counter = 3** (BI-2-§3, EvalOps, import-eager-closedness = the 3-slice batch). A
two-phase audit is **DUE NOW** — the orchestrator runs it next, BEFORE the next feature slice.
Spawn per [`../guides/slice-loop.md`](../guides/slice-loop.md) (do NOT invoke `/ace-audit`):
sequential **(A) code-quality** over this 3-slice batch (correctness, totality,
illegal-states, DRY, test strength, skill compliance — pay attention to `selectedFieldValue` and
the EvalOps carve), then **(B) architecture/refactor/cleanup** over the module graph. Both edit
`plan.md` → run sequentially, never parallel. Fold findings into `plan.md` as ranked fix-slices.
Last audit round closed clean (Phase A `778edb3` + Phase B `4863009`).

## Next leader AFTER the audit — item-6 LOW list (NONE soundness-bearing now)

With import-eager-closedness resolved, the item-6 LOW list has **no soundness-bearing item
left** — all are incompleteness/cosmetic/latent, none block adoption, real configs / prod9
don't hit them. Pick opportunistically:

- `scalar-embed-with-decls` (`{#a:1, 5}` → `5`; needs a scalar-with-decls carrier) — pairs with
  **B3** (`comprehensionPairs .embeddedList`, `for x in {#a:1,[1,2]}` iterates zero times).
- `module-file-scoped-imports` (arch-sized; per-file import scope frames).
- Parser strictness (`__x` double-underscore, `*(1|2)` laxity).
- The DRY items: `selectEvaluatedField .disj` 5-arm collapse; the
  `resolveEmbeddedDisjDefault` label-surfacing check; B2-A1/A2; A2-x/y loader corners.

`Eval.lean` at ~3380 is well under the ~4500 re-split watch — no carve pressure.

## Release state — a fresh daily alpha is cadence-due (attended)

Last release is `v0.1.0-alpha.20260621`. Landed AFTER it and UNRELEASED: SC-1e, AD2-1,
BI-2-residual, BI-2-§3, EvalOps, **and now import-eager-closedness**. Cut
`v0.1.0-alpha.20260622` via `scripts/release.sh 0.1.0-alpha.20260622` (attended — push/publish;
CI/GitHub Actions banned). Requires a clean tree (commit first). Not cut yet — do it after the
audit, or now if no further code lands first.

## STANDING CONTEXT (full detail in CLAUDE.md + guides/slice-loop.md)

- Autonomy grant in effect; resolve forks by philosophy; commit/push on `main` (attended).
- Spec is authority; `cue` (`/Users/chakrit/go/bin/cue` v0.16.1) a fallible cross-check, never
  the gate. Correctness over byte-compat. kue binary: `.lake/build/bin/kue`.
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on the main tree.
- Orchestrator = thin re-spawner; one subagent per slice; two-phase audit (A then B) every 2-3
  slices. Per-slice duties: tests-first; log `cue-divergences.md`; flag `cue-spec-gaps.md`.
