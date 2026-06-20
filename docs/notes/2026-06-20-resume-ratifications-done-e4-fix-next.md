# RESUME HERE — spec-gap ratifications CLOSED (2026-06-20); next = E#4-fix (or A#6)

Live START-HERE pointer; supersedes
`2026-06-20-resume-truncate-primitive-done-ratifications-next.md` (deleted). Authoritative
live roadmap: [`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md)
§ Consolidated fix backlog (ranked spec-conformance fixes) +
[`../spec/plan.md`](../spec/plan.md) (capabilities, non-spec roadmap, audit verdicts).

## Audit state — Counter = 2 (slice 2 of the new batch). AUDIT DUE NEXT (or after 1 more).

The prior two-phase audit closed (Phase A `5f1c143` + Phase B `4593185`); counter reset 0.
**truncate-primitive = slice 1; this ratifications slice = slice 2** → counter now **2**.
The two-phase audit is now **DUE at the 2-slice mark** — run it (A then B, sequentially,
per [`../guides/slice-loop.md`](../guides/slice-loop.md), do NOT invoke `/ace-audit`) before
or right after the next code slice. At the latest, after ~1 more slice. The audit batch =
truncate-primitive + ratifications (mostly doc + 3 pins, low audit surface).

## LAST SLICE — spec-gap ratifications (4 gaps): 3 RATIFIED, 1 ESCALATED (committed, pushed)

Closed the "4 spec-gap ratifications" backlog item — the lower-confidence open questions
where the spec is silent and Kue made a principled choice. Each re-derived from the spec +
first principles, current behavior re-verified against the `cue` oracle, then ratified or
escalated. **Backlog item CLOSED.**

- **(1) Import-binding laziness B#2/F-5 — RATIFIED.** Spec genuinely silent; tolerate an
  unreferenced bottom imported def on an OPERATIONAL-LAZINESS basis (demand-driven value
  model; `importBinding` keeps the package shallow). Re-verified: `unreferenced_import_conflict`
  exports `{"out":{"name":"ok"}}`. Pinned by that fixture + `rx2b_label_pattern_invalid_bottoms`.
- **(2) `A|B` un-narrowed struct disjunction (A) — RATIFIED.** Keep open (a join with no
  unique default IS the join; verified meet-identity vs `.top`). Corrected the prior
  "`incomplete`" note. NEW pins `StructTests.disj_struct_arms_no_default_*`.
- **(3) Field order #3 (C/F-4) — RATIFIED.** Keep Kue's declaration/source order (total,
  deterministic). **Corrected the cue-behavior record:** cue's cross-conjunct order is an
  undocumented internal-graph artifact, NOT "first-introduced" — sorts for simple literals,
  interleaves for def-ref meets. Parity DECLINED (supersedes plan item #4). NEW pin
  `meet_struct_field_order_is_declaration_order`.
- **(4) E#4 list `+`/`*` — ⚠ MIS-FILED → ESCALATED, NOT ratified.** The spec MANDATES the
  operator domain (int/float/string/bytes), so a list operand is a TYPE ERROR. `cue` is
  spec-correct (hard-errors); **Kue is WRONG** — leaves a held residual instead of a
  type-error bottom (`evalAdd`/`evalMul`/`evalSub`/`evalDiv` only bottom for `prim,prim`;
  a `.list` falls through the `_,_ => .binary` catch-all). Filed as **E#4-fix** (see below).
  Recorded in `cue-spec-gaps.md` as the ⚠ MIS-FILED row — NOT a `cue-divergence`.

No new ADR (none rises to cross-cutting; the spec-gap rows are the record).
Verify: `lake build` green (108 jobs, +3 pins); `check-fixtures.sh` → `fixture pairs ok`
(zero drift; docs + pins only, no eval-path code). Commit `8c839e0`, pushed.

## NEXT LEADER (recommendation) → E#4-fix (LOW-MED, real spec divergence, contained)

Spawn this as the next slice (it is also slice 3 → run the DUE two-phase audit around it).
Rationale: the ratification surfaced a GENUINE spec-conformance bug (`[1,2]+[3,4]` /
`3*[1,2]` leave a residual where the spec mandates a type-error bottom). Higher value than
A#6 (which hardens a path D#2b confirmed is never reached). Contained + clear:

- **E#4-fix.** Add an explicit ill-typed arm to `evalAdd`/`evalMul`/`evalSub`/`evalDiv`
  (`Eval.lean:787-839`): when an operand is a fully-evaluated non-arithmetic shape
  (`.list`/`.listTail`/`.struct`/concrete non-prim) and not bottom/incomplete, return a
  type-error `.bottomWith` (a dedicated spec-shaped `BottomReason` is cheap), mirroring the
  `prim,prim → .bottom` path. Keep the residual ONLY for genuinely-incomplete operands (an
  unresolved ref that could still become a prim). Pins: `[1,2]+[3,4]` → bottom, `3*[1,2]` →
  bottom, `1+"x"` control still bottoms, `let x=_; x+[1]` stays residual until `x` resolves
  (add as `testdata/cue/...` fixtures + `FixturePorts` entries). NOT a `cue-divergence`
  (cue is correct). Full diagnosis in `plan.md` item #6 + `cue-spec-gaps.md` MIS-FILED row.

- **Close runner-up: A#6** (`containsBottom` fuel cap 100, `Lattice.lean:146` — STANDALONE
  soundness hardening). Real hardening for genuinely-deep NON-cyclic nested bottoms; never
  implicated in a shipped path (D#2b detects cyclic at depth ~2). Pick this if you'd rather
  harden over fixing E#4 first; both are LOW/contained.

### Other ranked candidates (after the above)

- **BI-2-residual** (MED, LARGE) — `math.Sqrt` (IEEE-754 + `NaN`/`Infinity` + Go sci-notation
  formatter) and `math.Pow` neg/fractional exponent (apd 34-digit decimal Pow + Infinity).
  Both BOTTOM honestly today. Needs a Float/decimal-numeric design fork. No real app needs it.
- **SC-3** display-residual (LOW, spec-gap — cosmetic default-collapse).
- **SC-4** (LOW, spec-gap-FIRST), **SC-1b** (closed×closed-pattern, MED).
- **EvalOps extraction** → `Kue/EvalOps.lean` (plan item 2, ACTIONABLE, PARALLEL-SAFE,
  mechanical — the standing first carve if `Eval.lean` size becomes pressing; ~3645 lines,
  under the ~4500 watch).
- **DRY-1** (LOW Phase-B refactor — `walkFollowedLets` extraction; schedule after Bug2-5).
- **Periodic passes** (non-blocking): plan-hygiene (distill + refresh
  `docs/www/index.html`), the deferred `testdata/cue/{definitions,comprehensions}`
  fixture-regroup (high blast radius via hand-maintained `FixturePorts`, low win — DEFERRED).

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
