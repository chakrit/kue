# RESUME HERE — two-phase audit CLOSED; audit counter = 0; next leader = CARRIER-STRUCT-MEET (2026-06-22)

Live START-HERE; supersedes `2026-06-22-resume-after-scalar-embed-with-decls.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md) +
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Genuinely-open
backlog. Full per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md).

## State — two-phase audit CLOSED (batch `1ab6f19`..`fa0a414`: TL-1 / TL-2 / scalar-embed)

The post-batch audit ran both phases, sequential, per
[`../guides/slice-loop.md`](../guides/slice-loop.md) (NOT `/ace-audit`). Both verdicts in:

- **Phase A — HEALTHY** (`fc2bb6a`). Scalar-embed batch reviewed: `.embeddedScalar` handled
  at every match site (no catch-all swallow), producer gate correct (pure `{5}`→`5` collapse
  UNTOUCHED), classifier/`resolveOperand`-unwrap recursion sound + total. Landed coverage +
  witness pins + a `cue-spec-gaps.md` correction inline. **ONE soundness fix-slice filed,
  TOP-ranked: `CARRIER-STRUCT-MEET`** (below). Deferred the carrier share/no-share question
  to Phase B.
- **Phase B — HEALTHY** (`<this commit>`, the carrier RULING). Whole module graph re-checked
  after the carrier landed: ACYCLIC, strictly layered, carrier added NO bad edge (ctors in
  `Value` L1, meet in `Lattice`, produced once in `Eval`). Clean sweep: no `sorry`/`panic!`
  /`dropRight`/dead code/stale markers; `Eval.lean` 3442 < ~4500 re-split watch; no perf
  note warranted. **Headline carrier ruling DELIVERED** (below). **One DRY fix-slice filed:
  CARRIER-DECL-SELECT** (LOW, ranked below CARRIER-STRUCT-MEET).

## 🎯 The carrier share/no-share RULING (Phase-B headline — durable, in plan.md § Resolved)

`.embeddedScalar` vs `.embeddedList`: **keep DISTINCT constructors; share ONLY the
decl-selection seam; do NOT merge, do NOT share the meet seam.** The scalar-embed slice's
parallel-ctor design is VINDICATED. Three separable seams:

- **Constructors — keep distinct.** A scalar never indexes/iterates; merging into an
  `embeddedCarrier (payload) (decls)` would force runtime scalar-vs-list re-discrimination at
  every output/iteration site (Manifest/Format/`comprehensionPairs`/`selectEvaluatedListIndex`
  /`classifyGuard`/`classifyDynLabel`/`classifyArithOperand`), re-introducing the illegal
  states (`index a scalar`, `iterate a scalar`) the split makes unrepresentable. Four-classifiers
  / walker-dedup precedent: shared part too thin, divergence IS the point.
- **Meet seam — do NOT share, despite the shared bug.** The skeletons are isomorphic but the
  payload-meet step is irreducible (list `asListPair`+`meetListPairWith` prefix/tail alignment
  vs scalar `scalarCarrierPartner?`+bare `meetWithFuel`); a 3-callback combinator hits the
  lambda-hides-`fuel+1` trap that broke DRY-1. CARRIER-STRUCT-MEET writes its fix 4× by hand —
  a mechanical DELETION, the correct cost.
- **Decl-selection seam — DO share** → CARRIER-DECL-SELECT (filed). The one seam where the
  carriers AGREE (and agree with plain `.struct`): real dedup, not false-sharing.

## NEXT STEP — leader = `CARRIER-STRUCT-MEET` (soundness; jumps the queue)

**Audit counter = 0** (reset). Next slice is the TOP-ranked soundness fix-slice, ahead of all
item-6 LOW work. Full diagnosis in `plan.md` (the 🚨 TOP-RANKED block). One-paragraph recap:

- **Bug:** a carrier (`.embeddedScalar`/`.embeddedList` — the carrier IS its scalar/list) met
  with a PURE decls-only struct that has NO embed of its own WRONGLY MERGES. `{#a:1,5} & {#b:2}`
  is `5 & {#b:2}` = int-vs-struct = **bottom** (spec); Kue admits `{#a:1,#b:2,5}` — MORE
  PERMISSIVE than spec, a soundness gap. The IDENTICAL bug pre-exists for BOTH carriers.
- **Locus (4 sites):** the `.struct fields _ none [] _` sub-case in each carrier's `none`-branch:
  `Lattice.lean:1257` / `:1272` (`embeddedList` left/right) + `:1295` / `:1310` (`embeddedScalar`
  left/right). All four read `if structHasOutputField then .bottom else <merge decls>`.
- **Fix:** DELETE the `else <merge decls>`; route the no-output decls-only-struct sub-case to
  `meetCore` (→ bottom). Merge stays ONLY via the partner branch (carrier & carrier). Apply
  uniformly to both carriers — **by hand at all 4 sites** (the Phase-B ruling says NO shared
  meet seam; the fix is a mechanical deletion, not new logic).
- **Boundary (oracle-confirmed v0.16.1, KEEP):** carrier & carrier MERGES; carrier &
  output-field-struct BOTTOMS (already correct via `structHasOutputField`); carrier &
  decls-only-struct-without-embed must BOTTOM (THE FIX).
- **Test debt to FLIP:** `ListTests.meet_scalar_carrier_with_decls_struct` + the `embeddedList`
  twin pin the WRONG merge → re-pin to bottom. The EvalTests
  `WITNESS_scalar_carrier_meet_{plain_decls_struct,lone_hidden_struct}_wrongly_merges` pins
  (added Phase-A) → flip to `exportJsonBottoms`.
- **Docs:** correct `cue-spec-gaps.md` (the carrier-vs-plain-struct meet was the spec-silent
  COMBINATION the slice under-specified).

### After CARRIER-STRUCT-MEET — then CARRIER-DECL-SELECT, then the item-6 LOW list

- **`CARRIER-DECL-SELECT`** (DRY, LOW) — a `selectFromDecls base label decls` helper shared by
  the `.struct` + both carrier arms at `Eval.lean:618-625` / `:637-644`, and collapse the
  `Runtime.lean:87-88` carrier pair. Lands AFTER CARRIER-STRUCT-MEET (same arms; avoid churn
  collision). Composes cleanly — independent seam.
- Then the remaining item-6 LOW items (NONE soundness-bearing): `module-file-scoped-imports`,
  parser strictness, the DRY items (`selectEvaluatedField .disj` 5-arm,
  `resolveEmbeddedDisjDefault`), B2-A1/A2, A2-x/y, `scalar-embed` provenance follow-ups.

`Eval.lean` 3442 < ~4500 re-split watch (ruling stands). `EvalTests.lean` 1608 — growing;
test-org re-carve not yet due (prior carve to Comprehension/Sort already happened).

## Release state — `v0.1.0-alpha.20260622` cadence-due (attended; NOT cut)

Last release `v0.1.0-alpha.20260621`. UNRELEASED since: SC-1e, AD2-1, BI-2-residual, BI-2-§3,
EvalOps, import-eager-closedness, the prior audit, TL-1, TL-2, scalar-embed-with-decls + B3,
**and this two-phase audit**. Cut `v0.1.0-alpha.20260622` via
`scripts/release.sh 0.1.0-alpha.20260622` (attended — push/publish; CI/GitHub Actions banned;
clean tree first). **Awaiting user greenlight — do NOT cut.**

## STANDING CONTEXT (full detail in CLAUDE.md + guides/slice-loop.md)

- Autonomy grant in effect; resolve forks by philosophy; commit/push on `main` (attended).
- Spec is authority; `cue` (`/Users/chakrit/go/bin/cue` v0.16.1) a fallible cross-check, never
  the gate. Correctness over byte-compat. kue binary: `.lake/build/bin/kue`.
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on the main tree.
- Orchestrator = thin re-spawner; one subagent per slice; two-phase audit (A then B) every
  2-3 slices. Per-slice duties: tests-first; log `cue-divergences.md`; flag `cue-spec-gaps.md`.
