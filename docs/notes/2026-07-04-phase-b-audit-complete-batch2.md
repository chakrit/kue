# Breadcrumb: 2026-07-04 — two-phase audit COMPLETE for the `abbab99..HEAD` batch

> SUPERSEDED as the live front by `2026-07-04-list-slice-landed.md` (LIST-SLICE-MISSING
> done). The ranked backlog below stays authoritative except LIST-SLICE-MISSING is now DONE
> and BYTES-SLICE-MISSING is newly filed.

Supersedes `2026-07-04-strings-runes-registered.md` / `2026-07-04-audit-struct-eq-half1-landed.md`
as the live front. The batch (struct/list `==` `1130638`, gate-DRY `4e36a39`, typed-ellipsis
`785c8e5`, float-unify `8a76260`, runes `6461d16`) has now had BOTH audit phases:

- **Phase A** (code-quality, `67fc023`) — done last session. Filed STRUCT-EQ-LEAF-TYPESENSE.
- **Phase B** (architecture + STRUCT-EQ-LEAF-TYPESENSE adjudication) — DONE THIS SESSION.

## What landed this session (Phase B)

**STRUCT-EQ-LEAF-TYPESENSE — RULING (A): kue correct / cue buggy.** The CUE spec mandates
value-based numeric `==` applied RECURSIVELY inside containers (spec: int→float conversion +
list/struct elements "recursively equal"). So `[1]==[1.0]`, `{a:1}=={a:1.0}`, `[[1]]==[[1.0]]` are
spec-`true`; cue's container `false` is a cue BUG (internally inconsistent with its scalar `true`).
kue's `1130638` was already correct. Phase A's "match cue / type-sensitive" lean was wrong (would
replicate the bug); spec is EXPLICIT, so this is a divergence record, not a spec-gap.

Landed INLINE (no `==` code change): 6 `native_decide` theorems in `EvalTests`, 4 fixture cases in
`numeric/equality_expressions`, a `cue-divergences.md` row, plan 0d closed. `./scripts/check.sh`
PASS. Committed on `main`, NOT pushed (AFK).

**Architecture verdict: HEALTHY.** float-unify + struct-eq clean and DRY (share the decimal-aware
leaf equality). Layering EvalOps→EvalBase→EvalDefer→Eval intact. One LOW-MEDIUM finding filed:
**PRIM-FLOAT-PARSED** (plan 0e) — `Prim.float` stores raw text, re-parsed on every meet + forces a
"can't happen" fallback; refine to carry a `DecimalValue` (own slice, core-type change).

## Open / next

- Ranked backlog (plan.md § "Ranked OPEN backlog"): 0b AUDIT-STRUCT-EQ half-2 (dedup, attended),
  0c ARCH-QUOTED-STRIP, 0e PRIM-FLOAT-PARSED, then GDA-FLOAT-RENDER, LIST-SLICE-MISSING.
  B3d-6b (registry) is NETWORK-GATED.
- Two-phase audit is now discharged for this batch → resume the slice loop: pick the next slice
  from the ranked backlog (0c ARCH-QUOTED-STRIP or 0e PRIM-FLOAT-PARSED are self-startable code
  slices; half-2 and B3d-6b are attended/network-gated).
- Periodic: plan.md at 662 lines — plan-hygiene approaching, not yet due.
