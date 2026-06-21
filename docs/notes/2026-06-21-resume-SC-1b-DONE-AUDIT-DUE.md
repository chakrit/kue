# RESUME HERE — SC-1b RESOLVED (2026-06-21); TWO-PHASE AUDIT DUE next

Live START-HERE pointer; supersedes `2026-06-21-resume-RESID-MASK-2-DONE-next-SC-1b.md` (deleted).
Authoritative live roadmap: [`../spec/plan.md`](../spec/plan.md) (capabilities, ranked backlog, audit
verdicts) + [`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Consolidated
fix backlog (§ SC-1b DONE, § SC-1e new).

## ★ AUDIT STATE — counter = 2 → TWO-PHASE AUDIT DUE NOW (do it before the next code slice)

RESID-MASK-2 was slice 1 (`f0613e5`, spec-review, no code). **SC-1b was slice 2 (`406e719`,
pushed).** That hits the 2–3-slice mark → **the two-phase audit is DUE.** Run it per
[`../guides/slice-loop.md`](../guides/slice-loop.md) (do NOT invoke `/ace-audit`; the procedure is
written there), SEQUENTIALLY: **(A) code-quality** (correctness, totality, illegal-states, DRY, test
strength, skill compliance over RESID-MASK-2 + SC-1b), then **(B) architecture/refactor/cleanup**
(module boundaries, layering, dead code, simplification, test/fixture organization over the module
graph). Fold findings into the plan as fix-slices. SC-1b is a meaty, wide-blast-radius change (a core
`Value.struct` field retype) — give Phase A real attention on the `closedClauses` representation and
the migrated test pins.

## What just landed — SC-1b (closed×closed-pattern intersection), `406e719` (pushed)

The meet of two CLOSED structs was closed to the UNION of allowed-sets, not the INTERSECTION — a
field matching EITHER conjunct's pattern was admitted on a later meet. CUE's rule is conjunctive
(closedness is monotone). The old `closingPatterns : List Value` (flat, `any`-checked) could not
represent the conjunction.

- **Fix = provenance representation.** Replaced `closingPatterns` with `closedClauses : List
  ClosedClause` (`ClosedClause = {fieldLabels : List String, patterns : List Value}`). One clause per
  closed conjunct; a field is admitted iff `ignoresClosedness` OR EVERY clause admits it. Self-closed
  → one clause; meet → CONCATENATION (conjunction). **Invariant `closedClauses = [] ↔ open`,
  mkStruct-enforced** — a closed struct always carries ≥1 clause (`close({})` → one all-empty clause).
  This is the provenance the CUE closedness guide explicitly mandates.
- **Blast radius (mechanical):** `Value.lean` (new mutual `structure ClosedClause`, retyped ctor
  field, `mkStruct` default, `dedupClauses`/`canonicalizeClause`/`ClosedClause.mapPatterns`);
  `Lattice.lean` (`fieldAllowedByClause(s)With` = conjunction `all`, `applyClausesWith`, `mergeStructN`
  threads `leftClauses`/`rightClauses`, carries `bothClauses`); `Builtin.closeValue` (idempotent on
  already-closed — must NOT collapse clauses); `Eval`/`Resolve`/`Normalize`/`Module` recursion sites.
- **Original audit witness was MASKED.** Same-pattern `^x` + disjoint EXPLICIT fields → the disjoint
  required fields poison, hiding the union lossiness. REAL witnesses use DIFFERENT patterns
  (`#A:{[=~"^x"]} & #B:{[=~"^y"]}` then `& {x1}`). Field-side (CRUX) needs per-clause field-labels (the
  merged `fields` over-approximates each clause's set). Diagnosis was subtler than the sketch — recorded.
- **17 `native_decide` pins** (12 source-level `StructTests ### SC-1b`, 5 clause-logic units
  `LatticeTests ### SC-1b`) + 1 fixture pair (`definitions/sc1b_closed_pattern_intersection`); all
  migrated existing closedness pins updated. Every case oracle-confirmed vs cue v0.16.1.

### Verify (all green)

`lake build` 108 jobs; `scripts/check-fixtures.sh` → `fixture pairs ok` (zero drift + the new pair);
`shellcheck` clean (no shell touched); **cert-manager export SEMANTICALLY identical to cue** (def-meet
hot path — prod9 leans on closed defs). No `cue-divergences.md`/`cue-spec-gaps.md` change (Kue MATCHES
cue; spec mandates the provenance). Committed + **pushed** (attended) `406e719`.

## NEXT — after the audit (correctness-first)

1. **AUDIT FIRST (above).** Then fold findings as fix-slices.
2. **SC-1e (closed × open-`...`) — NEWLY DIAGNOSED during SC-1b, pre-existing, MED, CLEAN autonomous.**
   A closed struct met with an open-`...` struct must STAY closed (the `...` does not re-open the
   closed conjunct — monotonicity). cue rejects `#A:{[=~"^x"]} & {b:1, ...}`'s `b`; Kue admits
   (confirmed against the `f0613e5` baseline → NOT an SC-1b regression). Root: the B2.5 tail×patterns
   arm in `mergeStructN` produces `defOpenViaTail` with empty clauses, dropping the closed clause. Two
   closed structs never reach that arm, so it is strictly closed×open-tail (disjoint from SC-1b). Fix
   sketch in audit § SC-1e: when either operand is closed (`bothClauses` non-empty), produce a CLOSED
   no-tail result carrying `bothClauses` (the open `...` is vacuous against closedness). Its own slice +
   test sweep.
3. **The increasingly user-gated tail (SURFACE to the user after the audit, don't grind):**
   - **AD2-1** (LOW-MED disjunction-normalizer dedup; display-only, value-sound) — flips two NAMED
     theorem pins + the SC-3 display contract; a human signs off the contract rename.
   - **SC-3** (display-residual) — COUPLED with AD2-1's contract rename; same human gate.
   - **BI-2-residual** (Sqrt + neg/fractional Pow) — a large Float/NaN/Infinity numeric-model
     subproject, its own undertaking.
   - **EvalOps extraction** (plan item 2) — clean mechanical carve, parallel-safe; good autonomous
     filler if the user-gated items stall.
   → **Next-leader note:** after the audit, likely SURFACE AD2-1/SC-3/BI-2-residual to the user (gated),
   and take SC-1e + EvalOps as the autonomous path meanwhile.

## CANONICAL PATHS (ground-truth — do NOT re-litigate)

- prod9 stress-test targets: `/Users/chakrit/Documents/prod9/infra/apps/argocd.cue` (PARKED) and
  `.../cert-manager.cue` (semantically = cue; byte-differs only in JSON key ordering — pre-existing,
  NOT a regression). **Run cert-manager from the infra MODULE dir** (`cd .../prod9/infra &&
  {kue,cue} export ./apps/cert-manager.cue`); the bare absolute-path invocation errors `import failed:
  … no cue.mod` for BOTH binaries. Semantic compare: `/usr/bin/python3 -c "import
  json;print(json.load(open(a))==json.load(open(b)))"`.
- cue oracle: `/Users/chakrit/go/bin/cue` (v0.16.1) — READ-ONLY, cross-check only.
- kue binary: `.lake/build/bin/kue` (or `lake exe kue`). For source-level closedness pins use
  `exportJsonBottoms` / `exportJsonMatches` `native_decide` theorems (e.g. the new `StructTests ###
  SC-1b`); for the closing-machinery logic use `fieldAllowedByClausesWith` units (`LatticeTests ###
  SC-1b`). Manifest ERROR-KIND pins → hand-built-AST `rfl` in `ManifestTests.lean`.
- **Python note:** a shell wrapper shadows `python3` with a broken `~/.venv`; use `/usr/bin/python3`
  by absolute path.
- **Baseline-compare trick (no working-tree risk):** `git worktree add -d /tmp/kue-head HEAD` →
  `cd /tmp/kue-head && lake build` → compare its binary → `git worktree remove --force /tmp/kue-head`
  (run the remove from the kue repo dir, not prod9). Used this slice to confirm SC-1e is pre-existing.

## STANDING CONTEXT (durable; full detail in CLAUDE.md + guides/slice-loop.md)

- Kue autonomy grant in effect (decide/proceed; resolve forks by philosophy; commit/push on `main`
  when attended). **Spec is authority; `cue` is a fallible cross-check, never a gate** — EXCEPT the
  narrow oracle-as-data-source carve. Correctness-over-performance. **Unattended/AFK → commit, don't
  push.**
- Orchestrator = thin re-spawner; one subagent per slice; two-phase audit (A then B) every 2–3 slices
  — **counter now 2 → DUE.** Per-slice duties: tests-first; log `cue-divergences.md`; flag
  `cue-spec-gaps.md`; keep `kue-performance.md` current.
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on main tree.
- **argocd / Bug2-5: PARKED** — a stress-test finding, not on the critical path.
