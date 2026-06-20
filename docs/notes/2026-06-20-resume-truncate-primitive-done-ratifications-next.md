# RESUME HERE — truncate-primitive CLOSED (2026-06-20); next = spec-gap ratifications

Live START-HERE pointer; supersedes
`2026-06-20-resume-audit-complete-truncate-primitive-next.md` (deleted). Authoritative
live roadmap: [`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md)
§ Consolidated fix backlog (ranked spec-conformance fixes) +
[`../spec/plan.md`](../spec/plan.md) (capabilities, non-spec roadmap, audit verdicts).

## Audit state — Counter = 1 (truncate-primitive = slice 1 of the new batch). NOT due.

The prior two-phase audit closed (Phase A `5f1c143` + Phase B `4593185`); counter reset 0.
**truncate-primitive is slice 1** of the new batch → counter now **1**. Next two-phase
audit due after **1–2 more** slices. Do NOT add a spurious "AUDIT DUE" flag.

## LAST SLICE — truncate-primitive Step 1 DONE + Step 2 RULED OUT (committed, pushed)

Soundness hardening, the illegal-states-unrepresentable reason-to-be. **Item CLOSED.**

- **Step 1 (DONE):** added `EvalState.truncate {α} (result : α) : EvalM α` — the single
  primitive fusing the `fuel=0` field-drop + `truncCount` bump + return. Rewrote all
  truncation sites through it; dropping without bumping is no longer expressible AT those
  sites (one choke point, was disciplinary across the sites).
- **COUNT RECONCILED — SEVEN sites, not six.** The plan/breadcrumb said "six"; the actual
  count is seven (two `evalValueCoreWithFuel` arms + five expansion helpers). The seventh,
  `expandListClausesWithFuel`, landed with the later list-comp slice and bumped correctly
  by discipline. **Audited all seven first: every one already bumped — NO latent
  drop-without-bump bug.** A localize-a-sound-invariant refactor, not a bug fix.
- **Step 2 (ATTEMPTED, RULED OUT — not deferred):** a `withFuel` dispatch making the bump
  physically unskippable was built + tested; it BREAKS the mutual block's `termination_by`
  (routing the `fuel=0` dispatch through a lambda hides the `fuel = n+1` pattern → Lean
  can't prove the recursive decrease, `failed to prove termination`). Full type-level
  unrepresentability would need re-architecting saturation off the
  monotonic-counter+bracket (the design audit-#6 deliberately chose) — not worth it.
  Residual routing-discipline is an invariant note at the primitive + on the `truncCount`
  field. See plan item 1 + log.
- **Tests:** 3 new structural pins in `EvalPerfTests.lean`
  (`truncate_bumps_truncCount_by_one` over an arbitrary start,
  `truncate_returns_its_argument` polymorphic `rfl`,
  `truncate_bumps_for_every_dropped_shape`) — pin the primitive's bump+return contract at
  build. Behavior-preserving proof = byte-identical full corpus + the existing cross-fuel
  hazard pins.
- **Verify:** `lake build` green (108 jobs); `check-fixtures.sh` → `fixture pairs ok`
  (zero drift); cert-manager `export` content-identical to `cue` (`jq -S`, 984 bytes).

## NEXT LEADER (recommendation) → the 4 spec-gap ratifications (LOW, doc-ish, ONE slice)

Spawn this as the next slice. Rationale: truncate-primitive drained the last designed HIGH
item; the cheap spec-conformance work is mostly done. The 4 spec-gap ratifications in
[`../reference/cue-spec-gaps.md`](../reference/cue-spec-gaps.md) are a single low-effort
slice that closes the remaining doc-debt (ratify Kue's principled choice + basis for each
gap where the spec is silent and the binary's behavior is an artifact). Cheap momentum
before the next audit.

- **Close runner-up: A#6** (`containsBottom` fuel cap 100, `Lattice.lean:146` — STANDALONE
  soundness hardening, thematically adjacent to this slice). A real hardening item for
  genuinely-deep NON-cyclic nested bottoms; never implicated in any shipped path (D#2a
  detects at depth ~2). Pick this if you'd rather keep hardening over doc-debt.

### Other ranked candidates (after the above)

- **BI-2-residual** (MED, LARGE) — `math.Sqrt` (IEEE-754 float64 + `NaN`/`Infinity` + Go
  sci-notation formatter) and `math.Pow` neg/fractional exponent (apd 34-digit decimal
  Pow + Infinity). Both BOTTOM honestly today. Needs a Float/decimal-numeric design fork.
  No real app needs it — a deliberate numeric subproject, not a quick slice.
- **SC-3** display-residual (LOW, spec-gap — cosmetic default-collapse).
- **SC-4** (LOW, spec-gap-FIRST), **SC-1b** (closed×closed-pattern, MED).
- **EvalOps extraction** → `Kue/EvalOps.lean` (plan item 2, ACTIONABLE, PARALLEL-SAFE,
  mechanical — the standing first carve if `Eval.lean` size becomes pressing; 3645 lines,
  under the ~4500 watch).
- **Periodic passes** (non-blocking): plan-hygiene (distill + refresh
  `docs/www/index.html`), the deferred `testdata/cue/{definitions,comprehensions}`
  fixture-regroup (high blast radius via hand-maintained `FixturePorts`, low win —
  DEFERRED).

## CANONICAL PATHS (ground-truth — do NOT re-litigate)

- prod9 stress-test targets:
  `/Users/chakrit/Documents/prod9/infra/apps/argocd.cue` (parked) and
  `.../cert-manager.cue` (fully correct, ~12s export, content-identical to cue).
- cue oracle: `/Users/chakrit/go/bin/cue` (v0.16.1) — READ-ONLY, cross-check only.
- kue binary: `.lake/build/bin/kue` (or `lake exe kue`).
- **Python note:** a shell wrapper shadows `python3` with a broken `~/.venv`; use
  `/usr/bin/python3` by absolute path for any generator/oracle scripting.

## STANDING CONTEXT (durable; full detail in CLAUDE.md + guides/slice-loop.md)

- Kue autonomy grant in effect (decide/proceed; resolve forks by philosophy; commit/push
  on `main` when attended). **Spec is authority; `cue` is a fallible cross-check, never a
  gate** — EXCEPT the one narrow oracle-as-data-source carve governed by the ADR (data,
  never a gate). Correctness-over-performance. **Unattended/AFK → commit, don't push**
  (CLAUDE.md).
- Orchestrator = thin re-spawner; one subagent per slice; two-phase audit (A then B) every
  2–3 slices. Per-slice duties: tests-first; log `cue-divergences.md`; flag
  `cue-spec-gaps.md`; keep `kue-performance.md` current.
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on main tree.
- **argocd / Bug2-5: PARKED** — a stress-test finding, not on the critical path.
