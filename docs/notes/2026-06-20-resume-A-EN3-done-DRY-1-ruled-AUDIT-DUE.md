# RESUME HERE — A-EN3 DONE + DRY-1 RULED OUT (2026-06-20); **two-phase audit now DUE**

Live START-HERE pointer; supersedes `2026-06-20-resume-AD4-1-done-next-A-EN3-DRY-1.md` (deleted).
Authoritative live roadmap: [`../spec/plan.md`](../spec/plan.md) (capabilities, ranked backlog,
audit verdicts) + [`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md)
§ Consolidated fix backlog.

## Audit state — counter = **2**. ⚠ **AUDIT DUE** (the 2–3-slice mark).

The previous two-phase audit closed (counter reset 0). New batch since: **AD4-1 = slice 1**,
**A-EN3 = slice 2** (DRY-1 ruled out — not a slice). Two NEW slices have landed → the two-phase
audit (A then B, sequentially, per [`../guides/slice-loop.md`](../guides/slice-loop.md) — do NOT
invoke `/ace-audit`) is DUE before the next code slice. Scope: the AD4-1 (`524a402`) + A-EN3
(`5652717`) dedup batch for Phase A; whole module graph for Phase B.

## Last landed — A-EN3 (def-frame fold dedup), DONE (`5652717`)

Behavior-preserving DRY refactor (byte-identical fixtures + re-run `native_decide` pins = proof).
The three structural `Value`-folds `refsSelfEmbeddedLabel`/`selfReferencedLabels`/`defFrameRefIndices`
collapsed to thin instantiations of ONE generic `foldValueWithDepth` (combine + empty + a pre-order
`Option` leaf hook + a `dynValShift` offset). The three `*Clauses` helpers were dropped (the fold's
single `descendClauses`-based clause handler subsumes them).

- **Termination preserved STRUCTURALLY** (no `termination_by`, matching the originals; recursive
  self-call lexically visible inside the combinator's own `match fuel | 0 | f+1 => foldValueWithDepth
  … f …` — the truncate-Step-2 lambda trap avoided). Axiom-clean (`propext`/`Quot.sound`).
- **All two-pass agreement + Bug2-1..2-4 soundness pins re-run green** — they are `native_decide`,
  so they recompute against the deduped form (= definitional equivalence); NO hand re-proof. +3 new
  combinator pins (empty-monoid, leaf short-circuit, `dynValShift` divergence) in `TwoPassTests`.
- **Latent finding (NOT fixed — would break byte-identical):** `defFrameRefIndices` scans a
  `.dynamicField`'s VALUE at `depth+1` but the resolver pushes no frame there (`Resolve.lean:139`)
  → over-deep, misses def-refs buried in a dyn-field value. Unreachable in corpus, preserved + pinned
  + flagged. Filed as **A-EN3-DYN** (LOW fix-slice). Full writeup: implementation-log § "A-EN3".
- Gate: `fixture pairs ok` (zero drift), cert-manager content-identical to cue v0.16.1.

## DRY-1 — RULED OUT (attempted under A-EN3, reverted; no behavior change shipped)

The let-walkers (`closeDefFrameReadIndices`/`letPromotedReadLabels`/`injectLetLocalNarrowings`) do
NOT share a combinator: (1) `closeDefFrameReadIndices` recurses on a `List Nat` worklist (different
carrier/visited-set/follow-by-index), (2) collect (`→ List String`) vs rewrite (`→ Value`, must
rebuild struct metadata a dispatch discards), (3) a termination trap — empirically a `step`-callback
combinator failed structural-recursion inference (the truncate-Step-2 trap). Contrast AD4-1: its
variation point was a PURE leaf; DRY-1's IS the recursion. **Do NOT re-file.** Full reasoning:
plan.md § walker-dedup + implementation-log § "DRY-1".

## NEXT — run the two-phase audit, THEN the next code leader

1. **Audit (DUE NOW)** — Phase A (code-quality over the AD4-1 + A-EN3 batch), then Phase B (whole
   module graph). Per `slice-loop.md`; fold findings into `plan.md` as fix-slices. Phase A should
   confirm: the `foldValueWithDepth` dedup is sound (no behavior drift, the `dynValShift` knob
   honestly documents the one divergence), termination structural, pins real. Phase B: does the
   `Value`-fold combinator belong in `Eval.lean` or a shared helper module; is the eval file size
   (still large) due an extraction (EvalOps still the right first carve).
2. **Then the next code leader** (after audit fix-slices, by rank):
   - **AD2-1** (LOW-MED — disjunction-normalizer dedup; **FILE as a slice, do NOT apply inline** —
     flips two NAMED theorem pins + the SC-3 display contract; a human signs off). Now the SOLE
     remaining walker/normalizer-dedup-family member. Full spec in plan.
   - **A-EN3-DYN** (LOW — reconcile `defFrameRefIndices`'s over-deep `.dynamicField` value scan to
     depth 0, +witnessing fixture, flip the divergence pin). Standalone, surfaced by A-EN3.
   - **A#6** (`containsBottom` fuel cap 100, `Lattice.lean`) — standalone soundness hardening, LOW.
   - **SC-1b** (closed×closed-pattern, MED) / **SC-3** display-residual (LOW, spec-gap; couples AD2-1).
   - **EvalOps extraction** (`Kue/EvalOps.lean`, plan item 2) — parallel-safe mechanical carve.

## CANONICAL PATHS (ground-truth — do NOT re-litigate)

- prod9 stress-test targets: `/Users/chakrit/Documents/prod9/infra/apps/argocd.cue` (PARKED) and
  `.../cert-manager.cue` (content-identical to cue). **Run cert-manager from the infra MODULE dir**
  (`cd .../prod9/infra && {kue,cue} export ./apps/cert-manager.cue`); the bare absolute-path
  invocation errors `import failed: … no cue.mod` for BOTH binaries (a cue.mod-context artifact).
- cue oracle: `/Users/chakrit/go/bin/cue` (v0.16.1) — READ-ONLY, cross-check only.
- kue binary: `.lake/build/bin/kue` (or `lake exe kue`).
- **Python note:** a shell wrapper shadows `python3` with a broken `~/.venv`; use `/usr/bin/python3`
  by absolute path for any generator/oracle scripting.

## STANDING CONTEXT (durable; full detail in CLAUDE.md + guides/slice-loop.md)

- Kue autonomy grant in effect (decide/proceed; resolve forks by philosophy; commit/push on `main`
  when attended). **Spec is authority; `cue` is a fallible cross-check, never a gate** — EXCEPT the
  narrow oracle-as-data-source carve (data, never a gate). Correctness-over-performance.
  **Unattended/AFK → commit, don't push.**
- Orchestrator = thin re-spawner; one subagent per slice; two-phase audit (A then B) every 2–3
  slices — **counter now 2, AUDIT DUE.** Per-slice duties: tests-first; log `cue-divergences.md`;
  flag `cue-spec-gaps.md`; keep `kue-performance.md` current.
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on main tree.
- **argocd / Bug2-5: PARKED** — a stress-test finding, not on the critical path; may never un-park.
