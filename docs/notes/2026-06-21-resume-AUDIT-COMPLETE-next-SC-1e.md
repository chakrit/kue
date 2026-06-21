# RESUME HERE — AUDIT ROUND COMPLETE (2026-06-21); next leader = SC-1e

Live START-HERE pointer; supersedes `2026-06-21-resume-SC-1b-DONE-AUDIT-DUE.md` (deleted).
Authoritative live roadmap: [`../spec/plan.md`](../spec/plan.md) (capabilities, ranked backlog, the
two newest audit verdict blocks) + [`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md)
§ Consolidated fix backlog (§ SC-1b DONE, § SC-1e open).

## ★ AUDIT STATE — COMPLETE. Counter reset to 0. Next audit after 2–3 NEW slices.

The two-phase audit for the RESID-MASK-2 + SC-1b batch is **DONE** — no longer "AUDIT DUE":

- **Phase A `176bc42`** — SC-1b CLEAN (intersection = `.all` conjunction over per-conjunct clauses;
  `closedClauses = [] ↔ open` invariant holds at every construction site; 37 adversarial cases match
  cue v0.16.1; no missed consumer). RESID-MASK-2 light-check CLEAN (correctly a cue-spec-gap, not a
  divergence). Filed EMBED-CLOSE-1 (doc-only; kue already spec-correct).
- **Phase B `<this-commit>`** — whole-graph HEALTHY (~10th consecutive healthy round). `ClosedClause`
  encapsulation CLEAN across the module graph (admittance is Lattice-only; all other modules
  pass-through) → **SC-1 closedness-representation family RESOLVED.** Import graph acyclic/unchanged;
  no dead code beyond the one stale comment (FIXED INLINE this round); `Eval` 3702 / `Lattice` 1336
  both under the ~4500 re-split threshold (EvalOps stays the right first carve). Ranking + the
  SC-1e/EMBED-CLOSE-1 merge settled (below). Verify GREEN; one LOW-RISK inline (stale comment),
  committed + pushed.

**Counter = 0. Run 2–3 implementation slices, THEN the next two-phase audit.**

## NEXT-BATCH LEADER = SC-1e (the closedness-carry fix) — autonomous, CLEAN

**SC-1e + EMBED-CLOSE-1 collapse into ONE thematic slice** (settled by Phase B; re-probed kue + cue
v0.16.1). They share the monotone-closedness-under-composition theme but are NOT one code root —
land them together as the closedness-carry slice:

1. **SC-1e — the actual behavior fix (MED).** Root = the `defOpenViaTail` tail-composition arm at
   `Lattice.lean:1007`: it passes `closedClauses = []`, dropping `bothClauses`, so an open-`...` partner
   WRONGLY re-opens a closed conjunct. **Confirmed isolated to THIS arm:** `(#A & #B) & {x1:5}` (no
   tail) correctly REJECTS today (SC-1b path); adding `...` re-opens (`x1` admitted; cue rejects).
   **Fix:** when `bothClauses` is non-empty (either operand closed), produce a CLOSED no-tail result
   carrying `bothClauses` — the open `...` is vacuous against closedness. Its own test sweep.
2. **Stale-comment collapse — ALREADY DONE INLINE this audit.** The `Lattice.lean:1005/6` comment now
   names `closedClauses`, marks the line a KNOWN BUG (SC-1e), and states the fix. The SC-1e code change
   replaces that arm's `[]`; update the comment to past-tense when you do.
3. **EMBED-CLOSE-1 — pin-only, NO code change (LOW-MED).** kue ALREADY rejects `{#A, y1}` AND its
   spec-equiv `#A & {y1}` (cue self-contradicts: admits embed, rejects meet). The embed form has NO
   `...` tail → does NOT route through line 1007 → the SC-1e fix can't regress it. Purely
   ADD-A-FIXTURE-AND-PIN to lock kue's existing-correct monotone rejection (`cue-divergences.md` row
   already filed). Land it as the closedness-carry test sweep in the SC-1e slice.

Then: **EvalOps extraction** (plan item 2) — autonomous filler, parallel-safe; ~256 lines of pure
scalar algebra → `Kue/EvalOps.lean`, mechanical, no back-edge into the evaluator (resolve the
`divValue`/`modValue`/… import shape in the slice).

## ⚠ USER-GATED — SURFACE these to the user; do NOT grind autonomously

The tail of the backlog is now mostly user-gated. The orchestrator should SURFACE these, not take them:

- **AD2-1** (disjunction-normalizer display dedup) — display-only, value-sound, BUT flips two NAMED
  theorem pins + the SC-3 display contract. A display CONTRACT change → human sign-off.
- **SC-3** (display-residual) — COUPLED with AD2-1's contract rename; same human gate. Rank with AD2-1.
- **BI-2-residual** (Sqrt + neg/fractional Pow) — a LARGE Float/NaN/Infinity numeric-model subproject,
  a departure from Kue's exact-rational core; a scope/architecture decision for the user.

**Autonomous path = SC-1e (+EMBED-CLOSE-1 pin) → EvalOps; THEN surface AD2-1 / SC-3 / BI-2-residual.**

## CANONICAL PATHS (ground-truth — do NOT re-litigate)

- prod9 stress-test targets: `/Users/chakrit/Documents/prod9/infra/apps/argocd.cue` (PARKED) and
  `.../cert-manager.cue` (semantically = cue; byte-differs only in JSON key ordering — pre-existing,
  NOT a regression). **Run cert-manager from the infra MODULE dir** (`cd .../prod9/infra &&
  {kue,cue} export ./apps/cert-manager.cue`); the bare absolute-path invocation errors `import failed:
  … no cue.mod` for BOTH binaries. Semantic compare: `/usr/bin/python3 -c "import
  json;print(json.load(open(a))==json.load(open(b)))"`.
- cue oracle: `/Users/chakrit/go/bin/cue` (v0.16.1) — READ-ONLY, cross-check only. **CLI note:** both
  `kue` and `cue` need a FILE arg for `export -e <expr> file.cue` (stdin + `-e` errors `missing value`);
  write a temp `.cue` to probe.
- kue binary: `.lake/build/bin/kue` (or `lake exe kue`). For source-level closedness pins use
  `exportJsonBottoms` / `exportJsonMatches` `native_decide` theorems (e.g. `StructTests ### SC-1b`);
  for the closing-machinery logic use `fieldAllowedByClausesWith` units (`LatticeTests ### SC-1b`).
  Manifest ERROR-KIND pins → hand-built-AST `rfl` in `ManifestTests.lean`.
- **Python note:** a shell wrapper shadows `python3` with a broken `~/.venv`; use `/usr/bin/python3`
  by absolute path.
- **Baseline-compare trick (no working-tree risk):** `git worktree add -d /tmp/kue-head HEAD` →
  `cd /tmp/kue-head && lake build` → compare its binary → `git worktree remove --force /tmp/kue-head`
  (run the remove from the kue repo dir, not prod9). Used to confirm SC-1e is pre-existing.

## STANDING CONTEXT (durable; full detail in CLAUDE.md + guides/slice-loop.md)

- Kue autonomy grant in effect (decide/proceed; resolve forks by philosophy; commit/push on `main`
  when attended). **Spec is authority; `cue` is a fallible cross-check, never a gate** — EXCEPT the
  narrow oracle-as-data-source carve. Correctness-over-performance. **Unattended/AFK → commit, don't
  push.**
- Orchestrator = thin re-spawner; one subagent per slice; two-phase audit (A then B) every 2–3 slices
  — **counter now 0 (just reset).** Per-slice duties: tests-first; log `cue-divergences.md`; flag
  `cue-spec-gaps.md`; keep `kue-performance.md` current.
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on main tree.
- **argocd / Bug2-5: PARKED** — a stress-test finding, not on the critical path.
