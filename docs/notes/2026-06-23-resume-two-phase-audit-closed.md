# RESUME — two-phase audit CLOSED; audit counter = 0; next = Bug2-12b (2026-06-23)

Live START-HERE; supersedes `2026-06-23-resume-missing-field-selection-resolved.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md). Spec-conformance backlog:
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Genuinely-open
(Bug2-12b is item 0, with the fix-seam design).
Per-slice history: [`../reference/implementation-log.md`](../reference/implementation-log.md).
Served status page: [`../../www/index.html`](../../www/index.html).

## State — audit counter = 0. TWO-PHASE AUDIT CLOSED.

The two-phase audit over batch `fccab69..6f77bfe` (Bug2-12 self-recursive + missing-field-selection)
is DONE. **Phase A: HEALTHY** (`6f77bfe`) — missing-field discriminator CONFIRMED sound (29-witness
battery; no provisional field reaches `selectFromDecls`); Bug2-12 self-ref gate exact. Phase A filed
ONE new contained over-close, **Bug2-12b** (ranked TOP fix-slice, above perf #7). **Phase B: HEALTHY**
— module graph ACYCLIC + layered, both changes sit correctly; `Eval.lean` 4198 lines (below the ~4500
watch); dropped `base` param fully removed; tech-debt sweep clean; test/fixture health fine; perf-guide
current. Phase B filed the Bug2-12b fix-seam design + the close-each/close-once DRY ruling. No code
landed this round (design only); tree clean, full gate + canaries green at `6f77bfe`.

## NEXT — Bug2-12b (the over-close fix, design in place)

**Leader = Bug2-12b.** A self-rec closed def whose literals are SPLIT across `&` (`#X: #X & {a:1} &
{c:3}`) over-closes: `flattenConjDefRef`'s `expanded.map (normalizeDefinitionValueWithFuel …)` closes
each literal conjunct SEPARATELY, so a use-site re-declaring the def's OWN field (`out: #X & {c:3}`)
wrongly bottoms — cue ADMITS `{a:1,c:3}`. Contained to the split-literal self-rec shape (canaries
jq-S=0).

**Fix-seam (full design in `spec-conformance-audit.md` item 0):** in `flattenConjDefRef`'s `close ==
true` branch (`Eval.lean:1655-1657`), instead of `expanded.map close`, partition `expanded` into the
union-able def-body literals (`isUnionableDefValue`) vs the rest (self-ref `.refId` + other deferred
conjuncts), `foldl mergeDefinitionDecls` the literals into ONE body, close THAT once, re-emit
`<untouched conjuncts> ++ [<single closed-union body>]`. This is the Bug2-6/2-7 close-once principle
on the flatten path — `mergeDefinitionDecls` (`:385`) unions fields/patterns/openness; `mkStruct`
derives the SINGLE self-clause over the union. Avoids the first-attempt trap (which broke 6 Bug2-6..9
pins) because it stays GATED `isDefinition && isSelfRef` and touches ONLY the literal conjuncts — the
self-ref `.refId` is untouched (cycle detection unchanged), and non-self-rec multi-conjunct defs never
enter this arm. Must-pin witnesses: FLIP `bug212_multiconjunct_redeclare_OVERCLOSE` to admit `{a:1,c:3}`;
genuine-extra still rejects; single-literal unchanged; open-tail-across-split admits; conflict-across-
split bottoms; the 6 Bug2-6..9 pins green; D#2 guardrails green; canaries jq-S=0.

**close-each/close-once DRY ruling (plan.md Resolved/ruled-out):** the Bug2-12 flatten path and the
Bug2-7 conj-fold path are genuinely DISTINCT seams that UNIFY at the shared primitive
`mergeDefinitionDecls` — the Bug2-12b fix REUSES that primitive, it does NOT merge the two functions
(forbidden by the standing `mergeFieldsWith` ruling — the which-seam-fires distinction is the soundness
boundary). So Bug2-12b is a FIX (reuse the primitive on the flatten path), not a unification refactor.

### After Bug2-12b — ranked candidates (none soundness-bearing, none block adoption)

- **per-eval-cost slice** (the live perf frontier; frame-sharing is WON'T-FIX) — lower the per-eval
  CONSTANT / eval COUNT over the genuinely-large distinct population (~50s argocd).
- **Bug2-12 MUTUAL tail** (LOW, spec-gap-first) — the mutual-recursion closedness leak (`#A: #B & {a}`,
  `#B: #A & {b}`); cue's "reject the def's own field" reading is lattice-questionable; spec-check first.
  Recorded in `cue-spec-gaps.md` Bug2-12 MUTUAL row.
- **SC-4** (LOW, spec-gap-first — nested hidden/let closedness on direct def-meet; cue internally
  inconsistent, spec-check first).
- **item-6 LOW tail** in `plan.md` (`module-file-scoped-imports`, parser strictness, A2-x/y, B2-A1/A2,
  concurrent-tap-race note, DRY `resolveEmbeddedDisjDefault` check).

## Live state

- **TWO content-identical prod9 drop-ins:** cert-manager **~11.5s** (1448 B), argocd **~50s** (jq-S=0
  vs `cue`, both re-measured this audit). Bug2-5..2-14c chain CLOSED. perf #7 frame-sharing WON'T-FIX.
  `Eval`+`Lattice` FULLY total; module graph ACYCLIC; axiom-clean.

## RELEASE STATUS

`v0.1.0-alpha.20260623` is **CUT** and the Homebrew formula is live-correct on all 3 platforms. Do NOT
re-cut. Next alpha: ~daily via `scripts/release.sh` + `scripts/release-linux.sh` (local only;
CI/Actions banned; push/release attended-only).

## STANDING CONTEXT (full detail in CLAUDE.md + guides/slice-loop.md)

- Autonomy grant in effect; resolve forks by philosophy; commit/push/release on `main` (attended).
  Don't pause at milestones.
- Spec is authority; `cue` (`/Users/chakrit/go/bin/cue`) a fallible cross-check, never the gate. kue
  binary: `.lake/build/bin/kue`. Canary oracles: run from the prod9 infra root
  (`/Users/chakrit/Documents/prod9/infra`, READ-ONLY) so cue has its module context — `cue export
  apps/{argocd,cert-manager}.cue`.
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on the main tree.
- Orchestrator = thin re-spawner; one subagent per slice; per-slice duties: tests-first (`--` headers
  + `#check` tripwire on any new/touched test module); log `cue-divergences.md`; flag `cue-spec-gaps.md`.
