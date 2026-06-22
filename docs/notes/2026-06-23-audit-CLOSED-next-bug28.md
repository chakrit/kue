# RESUME — two-phase audit CLOSED; next leader = Bug2-8 (2026-06-23)

Live START-HERE; supersedes `2026-06-23-resume-bug27-DONE-next-bug28.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md) +
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Bug2-8 design
note. Full per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md).

## State — audit counter = 0 (RESET). Two-phase audit CLOSED.

The Bug2-6 + Bug2-7 batch (`d949666`..`10e8837`) audit is COMPLETE, both phases:

- **Phase A — HEALTHY (`10e8837`).** Provenance machinery sound: `#A & #B` rejection
  survives all adversarial shapes; `unionDefOpenness` over-open structurally
  unconstructable (mkStruct invariant); cert-manager canary held (jq-S=0); conflict
  bottoms both paths. 7 pins + 2 fixtures added inline.
- **Phase B — HEALTHY (`bd25e04`).** Module graph ACYCLIC + strictly layered, cleanliness
  sweep clean, `Eval.lean` 3558 (well under the ~4500 re-split watch;
  DefDeferral-first-carve ruling STANDS). One inline doc de-stale; the headline ruling +
  Bug2-8 design note landed.

### Headline ruling — `mergeFieldsWith` consolidation RULED OUT (keep separate)

Recorded in `plan.md` § Resolved/ruled-out. Three reasons, do not re-litigate:
1. `mergeFieldListWith` + `mergeConjFields` ALREADY share `mergeFieldIntoWith` (differ
   only in combiner arg + seed) — the proposed skeleton-share is, for that pair, already
   done.
2. `canonicalizeFields` cannot join under a `Value→Value→Value` combiner — its per-label
   helper dispatches on the merged field-class (`isDefinition` → `mergeDefinitionDecls`,
   else `.conj`) and omits the bottom-rewrite. Four-classifiers / DRY-1 precedent.
3. **Soundness boundary:** within-vs-cross-operand (union-vs-meet) lives in WHICH named
   function the caller invokes; merging into a combiner-arg makes it one wrong arg to pass
   the union combiner cross-operand → re-opens closed patterns (the cert-manager / Bug2-8
   trap). FORBIDDEN regardless of skeleton.

## NEXT STEP — Bug2-8 (the residual argocd blocker; design note now IN PLACE)

**Bug2-8:** same-def multi-decl close-once ACROSS AN EMBED boundary. `#UseCertManager`
embeds `#Mixin` and adds its own `#additions` decls, so the decls span the embed
(cross-operand) yet must still close-once-UNION — the within-vs-cross-operand split that
made Bug2-6/2-7 tractable no longer separates union from meet. **Minimal repro:**
`#A: {#m: {a:1}}` then `#Use: {#A; #m: {c:3}; vis: #m}` → `out: #Use.vis` → cue
`{a:1,c:3}`, kue bottoms. Tripwire pin
`bug28_WITNESS_embed_cross_decl_close_once_wrongly_bottoms`
(`TwoPassTests`; FLIP when fixed). Boundary pin
`bug28_embed_closed_pattern_field_stays_meet` must STAY green.

**DESIGN NOTE WRITTEN** — `spec-conformance-audit.md` § Bug2-8 design note (the slice
starts from there, NOT a blank page). Shape: a `DeclProvenance` sum tag
(`ownDecl`/`embeddedDecl`, NOT a Bool — illegal-states-unrepresentable) on the per-operand
tuple; route a host `ownDecl #m` × embed `embeddedDecl #m` DEFINITION-class pair through
`mergeDefinitionDecls` close-once-union in `meetEmbeddingsWithFuel` / the `.structComp`
force-fold (`forceClosureWithConjunctCore`, `Eval.lean:3205`);
pattern/regular/distinct-def meets UNTOUCHED. Manifestation quirk to fix: `kue export -e
out` yields `{c:3}` (drops `a`) while whole-file bottoms — make BOTH correct. Witnesses
(must-merge + must-still-meet incl. cert-manager canary) enumerated in the design note.

After Bug2-8: **perf frontier (#7 / item-5)** — STILL GATED (un-gates once argocd
resolves; profile `argo` against a resolving target then) → **item-6 LOW tail** (parser
strictness `*(1|2)`/`__x`, A2-x/y, B2-A1/A2, `resolveEmbeddedDisjDefault` check,
`release-linux.sh` dirty-tree guard).

## Periodic passes status

- **Test-org pass — APPROACHING-due, not yet scheduled.** `TwoPassTests.lean` 1713 (+217
  since the prior Phase-B's 1496; 56 Bug2-x pin refs) — the file to watch. The Bug2-x pins
  would live in a closure/two-pass-merge group when the reorg lands. Pick up as a
  dedicated slice when it grows unwieldy; Bug2-8 is the next leader.

## Release state

`v0.1.0-alpha.20260622` was CUT. A fresh alpha is **cadence-available but awaits user
greenlight** — Bug2-7 (`3361699`) + Bug2-6 (`ef824cb`) + Bug2-5 (`5fca57e`) + the Linux
scripts (`df40b62`) are unreleased in-tree. (CI/GitHub Actions banned; release = local
`scripts/release.sh` + `scripts/release-linux.sh`.)

## STANDING CONTEXT (full detail in CLAUDE.md + guides/slice-loop.md)

- Autonomy grant in effect; resolve forks by philosophy; commit/push on `main` (attended).
- Spec is authority; `cue` (`/Users/chakrit/go/bin/cue` v0.16.1) a fallible cross-check,
  never the gate. Correctness over byte-compat. kue binary: `.lake/build/bin/kue`.
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on main tree.
- Orchestrator = thin re-spawner; one subagent per slice; two-phase audit (A then B) DUE
  again after the next 2–3 slices (counter = 0 now). Per-slice duties: tests-first; log
  `cue-divergences.md`; flag `cue-spec-gaps.md`.
