# RESUME — missing-field-selection RESOLVED; audit counter = 2 (2026-06-23)

Live START-HERE; supersedes `2026-06-23-resume-bug212-selfrec-closed-resolved.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md). Spec-conformance backlog:
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Genuinely-open.
Per-slice history: [`../reference/implementation-log.md`](../reference/implementation-log.md).
Served status page: [`../../www/index.html`](../../www/index.html).

## State — audit counter = 2. TWO-PHASE AUDIT DUE after this slice's verify.

Two implementation slices have now landed since the last audit (Bug2-12 self-recursive, then
missing-field-selection). **Per `slice-loop.md` the two-phase audit (A code-quality, then B
architecture) is DUE — run it before/around the next forward slice.** Do NOT invoke `/ace-audit`;
follow the guide. On resume: verify HEAD == upstream (tree clean, pushed `main -> main`).

## What landed — missing-field-selection (a missing field of a concrete struct reads ABSENT)

A presence-test on a genuinely-MISSING (never-declared) field of a concrete struct returned the
WRONG state. `x: {a: 1}` then `x.b == _|_` / `x.b != _|_` errored `incomplete value`; cue v0.16.1
treats the missing field as ABSENT (`== _|_` true, `!= _|_` false). Same family as Bug2-13 — a
deferral masking a final absence, at the SAME selection boundary.

**Root cause:** `selectFromDecls` (`Eval.lean`) returned `.selector base label` on a miss — a
deferred node `classifyDefinedness` reads `.incomplete`, so the comparison never resolved. Only the
SHALLOW case was observably broken (the audit's noted `x.a.missing` was ALREADY correct because the
intermediate `x.a = 1` is a non-struct prim → the `_ => .bottom` catch-all; a deep STRUCT miss
`x.a.c` was equally broken).

**Discriminator (spec-verified vs cue, the crux):** whatever reaches `selectFromDecls` is an
ALREADY-EVALUATED concrete struct/embed carrier (or a resolved disjunction DEFAULT arm) — every
conjunct merges into the struct value BEFORE selection (`x: base & extra` supplies `b` at
unification, not at select), so a miss is FINAL-absent and can never arrive later. cue confirms
this even for an OPEN `...` struct. The PROVISIONAL case (an UNRESOLVED disjunction with no unique
default — a later arm could supply the field) NEVER reaches `selectFromDecls`: it stays the deferred
`.selector base label` in `selectEvaluatedField`'s `.disj` `_ =>` arm.

**Fix:** one line — `selectFromDecls`'s `none` arm yields `.bottom` (`.error`, so `== _|_` true /
`!= _|_` false). The now-dead `base` param dropped (4 call sites). Free wins: a comprehension guard
over a missing field fires the correct arm; a resolved-default-disjunction select reads absent.

**Boundaries (all == cue v0.16.1):** ABSENT — shallow `x.b`, deep `x.a.c`, open-`...` `x.b`,
disjunction-DEFAULT select. PRESENT (no pre-bottom) — later-conjunct-supplies, narrow-elsewhere
(`x.b` absent / `z.b` present), set field. PROVISIONAL (stays deferred) — unresolved no-default
disjunction. Canaries jq -S = 0 (not on the argocd path → zero drift).

**Tests:** 10 `native_decide` pins (`Bug2xTests` `### missing-field-selection`); 5 export fixtures
(`testdata/export/mfs_*.{cue,json}`, oracle-generated); tripwire sentinel
(`#check @mfs_unresolved_disj_stays_provisional`). One message-only divergence recorded
(`cue-divergences.md`): value-USE `y: x.b` — cue `undefined field`, kue generic bottom (both
reject; presence-test byte-matches).

## Live state

- **TWO content-identical prod9 drop-ins:** cert-manager **~12s** (1448 B), argocd **~50s**
  (37230 B), both jq -S diff = 0 vs `cue`. Bug2-5..2-14c chain CLOSED. perf #7 frame-sharing
  WON'T-FIX. `Eval`+`Lattice` FULLY total; module graph ACYCLIC. axiom-clean.

## NEXT — TWO-PHASE AUDIT, then pick a forward slice

Per `slice-loop.md`: run the two-phase audit (A code-quality over the 2-slice batch
`Bug2-12 + missing-field-selection`, then B architecture/refactor over the module graph). Fold
findings into the plan as fix-slices; don't let them stall forward motion. Then resolve the next
leader by philosophy and drive — do NOT pause to ask "what next". Ranked candidates (none
soundness-bearing, none block adoption):

- **Bug2-12 MUTUAL tail** (LOW, spec-gap-first) — the mutual-recursion closedness leak
  (`#A: #B & {a}`, `#B: #A & {b}`); decide whether to match cue's lattice-questionable "reject the
  def's own field" or hold the principled admit; transitive back-ref detection in
  `flattenConjDefRef`. Recorded in `cue-spec-gaps.md` Bug2-12 MUTUAL row.
- **per-eval-cost slice** (the live perf frontier now frame-sharing is WON'T-FIX) — lower the
  per-eval CONSTANT / eval COUNT over the genuinely-large distinct population (~50s argocd).
- **SC-4** (LOW, spec-gap-first — nested hidden/let closedness on direct def-meet; cue internally
  inconsistent, spec-check first).
- **item-6 LOW tail** in `plan.md` (`module-file-scoped-imports`, parser strictness, A2-x/y,
  B2-A1/A2, concurrent-tap-race note, DRY `resolveEmbeddedDisjDefault` check).

## RELEASE STATUS

`v0.1.0-alpha.20260623` is **CUT** and the Homebrew formula is live-correct on all 3 platforms.
Do NOT re-cut. Next alpha: ~daily via `scripts/release.sh` + `scripts/release-linux.sh` (local
only; CI/Actions banned; push/release attended-only).

## STANDING CONTEXT (full detail in CLAUDE.md + guides/slice-loop.md)

- Autonomy grant in effect; resolve forks by philosophy; commit/push/release on `main`
  (attended). Don't pause at milestones.
- Spec is authority; `cue` (`/Users/chakrit/go/bin/cue`) a fallible cross-check, never the gate.
  kue binary: `.lake/build/bin/kue`. Canary oracles: run from the prod9 infra root
  (`/Users/chakrit/Documents/prod9/infra`, READ-ONLY) so cue has its module context — `cue export
  apps/{argocd,cert-manager}.cue`.
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on the main tree.
- Orchestrator = thin re-spawner; one subagent per slice; per-slice duties: tests-first
  (`--` headers + `#check` tripwire on any new/touched test module); log `cue-divergences.md`; flag
  `cue-spec-gaps.md`.
