# RESUME HERE — AD2-1 DONE (2026-06-21); walker/normalizer-dedup family FULLY CLOSED

Live START-HERE pointer; supersedes
`2026-06-21-resume-SC-1e-DONE-closedness-CLOSED.md`. Authoritative live roadmap:
[`../spec/plan.md`](../spec/plan.md) (capabilities, ranked backlog) +
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md).

## ★ AUDIT STATE — counter = 2. **Two-phase audit is now DUE** (after this slice).

SC-1e was slice 1 of the new batch; **AD2-1 is slice 2** → counter = 2. At the 2–3-slice
mark: run the next two-phase audit BEFORE the next code slice — (A) code-quality over the
SC-1e + AD2-1 batch, then (B) architecture/refactor/cleanup over the module graph.
Procedure: [`../guides/slice-loop.md`](../guides/slice-loop.md) (NOT the `/ace-audit`
skill). Reset the counter to 0 after.

## ✦ THIS SLICE — AD2-1 RESOLVED (lone-default normalizer unified)

The last walker/normalizer-dedup member, resolved by SOUNDNESS ANALYSIS (prior audits
deferred it "USER-GATED" — over-caution about a pin rename; the real question was
autonomous). **Verdict: the lone-default lattice-marker is NON-load-bearing (vacuous).**

- `normalizeDisj`'s lone-arm collapse is now mark-agnostic (`[(_, v)] => v`), matching
  `normalizeEvaluatedDisj` — the two normalizers now agree on every lone-arm case. (The
  eval path keeps its distinct `joinValues` all-regular branch; only the divergent
  lone-arm rule was unified, not the whole function.)
- Proof: `combineMark` is AND + `withDefaultConvention` only synthesizes defaults for an
  all-regular operand ⇒ a lone `*v` never beats a real default nor manufactures one.
  Sharpest witness: `*1`-lone `& (*2|1)` → `1`, NOT `2`. Cross-checked vs cue v0.16.1
  (every onward-meet `export` byte-identical; cue's display ALSO collapses `*v`-lone → `v`,
  so the fix moves Kue TOWARD cue).
- Named pins RENAMED to the corrected behavior
  (`*_collapses_vacuous_lone_default`); non-load-bearing witnesses added in `LatticeTests`
  (`lattice_lone_default_vacuous_*` + `lattice_multi_arm_default_marker_preserved` — the
  boundary the collapse must NOT cross). `TwoPassTests.embed_disj_live_default_kept`
  expected display updated (lone-default residual collapses, matches cue).
- SC-3 / `cue-spec-gaps.md` D#2b/SC-3 row scope NARROWED: "keep marked in eval display"
  now applies ONLY to MULTI-arm live defaults (where the mark IS load-bearing). The
  lone-default half is gone.

Gate: `lake build` green (108 jobs, axiom-clean); `check-fixtures.sh` → `fixture pairs ok`
(byte-identical — no fixture renders a lone-default residual, so none changed); adversarial
export sweep vs cue all MATCH; cert hot-path unchanged. Detail: implementation-log
`## Completed Slice: AD2-1`; `plan.md` Resolved/ruled-out AD2-1 entry.

## STATUS SNAPSHOT (post-AD2-1)

- **Walker/normalizer-dedup family: FULLY CLOSED.** AD4-1 + A-EN3 DONE, DRY-1 ruled out,
  AD2-1 resolved. No open members.
- **Genuinely-open backlog:** BI-2-residual (MED, Float/NaN/Infinity model — user-gated
  scope decision), EvalOps extraction (mechanical, autonomous, not urgent), SC-4 (LOW,
  spec-gap-first). PARKED: Bug2-5 (argocd residual). SC-3 is now a recorded spec-gap only
  (multi-arm-default display), not open work.

## NEXT STEP

Run the **two-phase audit** (counter = 2, now due) over the SC-1e + AD2-1 batch per
`slice-loop.md`. After it (counter reset), the next autonomous slice is **EvalOps
extraction** (the one remaining mechanical, autonomous item) unless the audit surfaces a
higher-priority fix-slice.
