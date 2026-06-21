# SC-1e DONE (2026-06-21); closedness family FULLY CLOSED — SUPERSEDED

> **SUPERSEDED by `2026-06-21-resume-AD2-1-DONE-normalizer-dedup-CLOSED.md`** (AD2-1 landed;
> two-phase audit now due). Kept for the SC-1e detail; read the newer breadcrumb to resume.

Was the live START-HERE pointer; supersedes `2026-06-21-resume-AUDIT-COMPLETE-next-SC-1e.md`
(renamed). Authoritative live roadmap: [`../spec/plan.md`](../spec/plan.md) (capabilities,
ranked backlog) + [`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md)
§ Consolidated fix backlog (SC-1b/1e DONE; closedness family closed).

## ★ AUDIT STATE — counter = 1. Next two-phase audit after 2–3 NEW slices (so after ~1–2 more).

The RESID-MASK-2 + SC-1b batch audit closed last round (Phase A `176bc42` + Phase B
`f59727b`, counter reset 0). **SC-1e is slice 1 of the new batch** → counter = 1. Not yet
audit-due; run 1–2 more slices, THEN the next two-phase audit (A code-quality, then B
architecture; procedure in [`../guides/slice-loop.md`](../guides/slice-loop.md), NOT the
`/ace-audit` skill). The docs-reconciliation pass below is a DOCS-ONLY hygiene pass (no
code, no slice counter bump).

## ✦ DOCS-RECONCILIATION PASS — 2026-06-21 (this pass, docs-only; no code touched)

Reconciled the design record against landed state after the long autonomous run:
**distilled `plan.md` ** (shed ~9 accreted Phase-A/B audit verdict blocks + the shipped
D#2 design → history lives in the implementation-log + git; kept North Star, Working
Principles, Standing Capabilities, the live ranked backlog, durable rulings, pointers);
**reconciled `spec-conformance-audit.md` ** (dropped the stale "next 3-4 =
D#2a/D#2b/RX-2a" ranking — all DONE; added a clean genuinely-open ranked list = AD2-1 /
SC-3 / BI-2-residual / EvalOps; Status table C/E rows de-staled); **fixed
`architecture.md` ** ("not-yet-modeled" list was all-done; added closedClauses + total
`containsBottom` + leaf modules); **fixed `compat-assumptions.md` ** (the "Imports not
modeled" / "same-struct resolver" self-contradiction, and the stale docker-config
Composition note — hidden-field refs + `[string]: string` both resolve now, verified).
Ledgers (`cue-divergences.md`/`cue-spec-gaps.md`) verified current, no edit. `lake build`
108 green + `fixture pairs ok` confirm no code touched.

## ✅ JUST LANDED — SC-1e + EMBED-CLOSE-1 (the closedness-carry slice)

**The closedness family is now FULLY CLOSED** (SC-1/1b/1c/1d/1e + SC-2 DONE; EMBED-CLOSE-1
pinned).

- **SC-1e (closed × open-`...` re-opening) — FIXED.** A closed struct met with an
  open-`...` partner no longer re-opens. **The bug was WIDER than the phase-B sketch:**
  the breadcrumb named only the tail×patterns CATCH-ALL arm (`Lattice.lean:1009`), but a
  FIELD-closed def (`#C:{a:int}`, no patterns) routes through the `struct × structTail`
  arm (arm 3) and dropped the clause too. Fix: one local `closeTailResult` helper in
  `mergeStructN` that ALL FOUR tail arms route through, branching on
  `closedOpenness.isOpen` (= `StructOpenness.meet`, which already makes `defClosed`
  dominate `defOpenViaTail`). Closed ⇒ no-tail result carrying `bothClauses` +
  `applyBothClosedness`; open ⇒ keep the tail. `[] ↔ open` invariant preserved.
- **EMBED-CLOSE-1 — PINNED (no code change).** kue rejects `y1 ∉ #A` in BOTH `{#A, y1}`
  and `#A & {y1}`; cue self-contradicts (admits embed, rejects meet). Locked by
  `StructTests ### EMBED-CLOSE-1` + fixture `embed_close1_pin`; `cue-divergences.md` row →
  pinned.
- **Tests:** 9 `native_decide` pins (`StructTests ### SC-1e` + `### EMBED-CLOSE-1`) + 4
  fixture pairs (with FixturePorts Lean ports), all oracle-confirmed vs cue v0.16.1.
  Verify GREEN: `lake build` (108), `check-fixtures.sh` → `fixture pairs ok` (zero drift),
  **cert-manager byte-identical to the pre-fix HEAD baseline** (pure no-op — no
  closed×open-`...` meet there).

## NEXT — autonomous head is SHORT; the valuable tail is USER-GATED

**EvalOps extraction (plan item 2)** is the only remaining AUTONOMOUS slice — but it is
NOT urgent: mechanical carve of ~256 lines of pure scalar algebra
(`divValue`/`modValue`/…) to `Kue/EvalOps.lean`, no back-edge into the evaluator;
`Eval.lean` (~3702) is UNDER the ~4500 re-split threshold, so it is hygiene, not pressure.
Resolve the import shape in the slice.

## ⚠ USER-GATED — the orchestrator should SURFACE these now (do NOT grind autonomously)

With closedness closed, the genuinely valuable remaining work is all user-gated. **Surface
these to the user as the next decision** (the SC-1e leader-note flagged this hand-off):

- **AD2-1** (disjunction-normalizer display dedup) — display-only, value-sound, BUT flips
  two NAMED theorem pins + the SC-3 display contract. A display CONTRACT change → human
  sign-off.
- **SC-3** (display-residual) — COUPLED with AD2-1's contract rename; same human gate.
  Rank with AD2-1.
- **BI-2-residual** (Sqrt + neg/fractional Pow) — a LARGE Float/NaN/Infinity numeric-model
  subproject, a departure from Kue's exact-rational core; a scope/architecture decision
  for the user.

**Recommendation: SURFACE AD2-1 / SC-3 / BI-2-residual to the user before (or instead of)
grinding EvalOps.** EvalOps is low-value filler; the user-gated items are where the real
remaining value is.

## CANONICAL PATHS (ground-truth — do NOT re-litigate)

- prod9 stress-test targets: `/Users/chakrit/Documents/prod9/infra/apps/argocd.cue`
  (PARKED) and `.../cert-manager.cue` (semantically = cue; byte-differs only in JSON key
  ordering — pre-existing, NOT a regression). **Run cert-manager from the infra MODULE
  dir** (`cd.../prod9/infra && {kue,cue} export./apps/cert-manager.cue`); the bare
  absolute-path invocation errors `import failed: … no cue.mod` for BOTH binaries.
  Semantic compare:
  `/usr/bin/python3 -c "import json;print(json.load(open(a))==json.load(open(b)))"`.
- cue oracle: `/Users/chakrit/go/bin/cue` (v0.16.1) — READ-ONLY, cross-check only. **CLI
  note:** both `kue` and `cue` need a FILE arg for `export -e <expr> file.cue` (stdin +
  `-e` errors `missing value`); write a temp `.cue` to probe. **`kue eval` has NO `-e`
  flag** — pipe the whole file on stdin (`kue < file.cue`) for the CUE-syntax form, or
  `kue export [-e expr]` for JSON.
- kue binary: `.lake/build/bin/kue` (or `lake exe kue`). For source-level closedness pins
  use `exportJsonBottoms` / `exportJsonMatches` `native_decide` theorems (e.g.
  `StructTests ### SC-1b`, `### SC-1e`); for the closing-machinery logic use
  `fieldAllowedByClausesWith` units (`LatticeTests ### SC-1b`). Manifest ERROR-KIND pins →
  hand-built-AST `rfl` in `ManifestTests.lean`.
- **Python note:** a shell wrapper shadows `python3` with a broken `~/.venv`; use
  `/usr/bin/python3` by absolute path.
- **Baseline-compare trick (no working-tree risk):**
  `git worktree add -d /tmp/kue-head HEAD` → `cd /tmp/kue-head && lake build` → compare
  its binary → `git worktree remove --force /tmp/kue-head` (run the remove from the kue
  repo dir, not prod9). Used to confirm SC-1e is a no-op on cert-manager.

## STANDING CONTEXT (durable; full detail in CLAUDE.md + guides/slice-loop.md)

- Kue autonomy grant in effect (decide/proceed; resolve forks by philosophy; commit/push
  on `main` when attended). **Spec is authority; `cue` is a fallible cross-check, never a
  gate** — EXCEPT the narrow oracle-as-data-source carve (SC-1e: cue was CORRECT).
  Correctness-over-performance. **Unattended/AFK → commit, don't push.**
- Orchestrator = thin re-spawner; one subagent per slice; two-phase audit (A then B) every
  2–3 slices — **counter now 1.** Per-slice duties: tests-first; log `cue-divergences.md`;
  flag `cue-spec-gaps.md`; keep `kue-performance.md` current.
- prod9 + cue caches READ-ONLY. NO `git checkout` /`restore`/`reset --hard` on main tree.
- **argocd / Bug2-5: PARKED** — a stress-test finding, not on the critical path.
