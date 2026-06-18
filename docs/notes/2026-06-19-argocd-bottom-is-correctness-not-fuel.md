# Breadcrumb: argocd bottom RE-DIAGNOSED — a correctness bug, NOT fuel (2026-06-19)

**START HERE.** Supersedes
[`2026-06-19-item7-cache-hash-digest-landed.md`](2026-06-19-item7-cache-hash-digest-landed.md) as
the current pointer.

## What this slice did (a perf spike that turned into a correctness finding)

The slice was a perf investigation of the full `apps/argocd.cue` `conflicting values (bottom)`,
suspected (per old breadcrumbs) to be fuel-exhaustion-at-scale. **That hypothesis is now
DISPROVEN.** The bottom is a deterministic CORRECTNESS divergence, not a fuel truncation. Per
`docs/decisions/2026-06-18-correctness-over-performance.md` and the slice instruction, I STOPPED and
recorded it rather than papering over it. **No production code landed** (debug instrumentation added
and reverted; tree at baseline, `lake build` green, 96 jobs).

## The verdict, with evidence

- **Fuel does not fix it.** `evalFuel` 100/200/600 → bottoms at every level (wall 88s/131s/301s,
  scales ~linearly, bottom never clears). `resolveFuel`/`remapFuel` → 100000 on a fast repro → still
  bottoms. So NOT truncation at any ceiling (eval/resolve/remap).
- **Localized:** `defaults.#ListenerSet` and `defs.#TLSRoute` each bottom STANDALONE on valid CUE
  that `cue` 0.16.1 exports (e.g. `cue export apps/v_lsonly` → clean; Kue → bottom). NOT in
  `packs.#Argo` or `configs.yaml`.
- **Signal:** resolved tree shows `listener.yaml: [.bottom]` (bare) co-occurring with `bottomWith
  [fieldConflict #args/#from/#to]` — labels from UNREFERENCED `defs` workload defs
  (`pod_controller.cue`/`daemonset.cue`) the `#ListenerSet` path never touches. `cue` doesn't
  evaluate those.
- **Hypothesis (not yet pinned):** the trigger is the CROSS-MODULE hop (consumer `prodigy9.co` →
  dep `prodigy9.co/defs@v0.3.19`). A single-module vendor of the same def (correctly referenced by
  its declared package name) evaluates CLEANLY. Likely an import-laziness / eager-package-eval gap
  letting an unreferenced conflicting dep sibling pollute the consumer's selected value —
  plausibly adjacent to the A2-followup `FieldClass.importBinding` laziness work (whose
  `unreferenced_import_conflict` fixture pins the SAME-module case; the cross-MODULE case may differ).

Full bisection, dead ends, and caveats: `plan.md` → "Perf-spike → CORRECTNESS finding"; perf entry
updated in `kue-performance.md`.

## Next step (a CORRECTNESS slice, AHEAD of the perf items)

1. Build a minimal cross-module repro OUTSIDE prod9 (consumer module + dep module with two defs, one
   referenced, one with an interior conflict) that reproduces a `defaults.#ListenerSet`-style bottom.
   (This slice couldn't nail one — vendoring kept collapsing the module boundary or mismatching dep
   paths. That is task 1.)
2. Diagnose: is an unreferenced conflicting sibling in an imported DEP package being eagerly
   meet/evaluated into the consumer's value across the module hop? Compare against the A2-followup
   import-laziness guard.
3. Fix soundly (unreferenced bound-package interiors stay lazy across module hops), gate with a new
   module fixture + cert-manager/argocd content-identity, RE-MEASURE the 88s wall (it is downstream
   of this; only meaningful once the app exports at all).

## Repro assets (uncommitted, on the session host — regenerate if gone)

- `/tmp/infra-scratch` — a writable COPY of prod9 infra (prod9 itself is READ-ONLY). `apps/v_lsonly`
  etc. are `package main` subset files. `kue export apps/v_lsonly --out yaml` bottoms (~28-50s);
  `cue export apps/v_lsonly/main.cue` exports clean.
- Dead-end caveat: a hand-vendored single-module copy that references a package by its DIR name
  instead of its DECLARED package name is INVALID CUE (both tools reject) — not the bug.

## Audit cadence

This spike + item 7 = 2 slices since the last audit. A two-phase audit is DUE (per
`docs/guides/slice-loop.md` Phase A then Phase B). But the spike landed NO code, so the audit batch
is effectively just item 7 (`463f8e1..` the hash commit) — Phase A over that is small. Orchestrator:
either run the audit now or fold it after the correctness-fix slice above.

## Standing rules

- prod9 + cue caches READ-ONLY (eval/probe only). NO `git checkout`/`restore`/`reset --hard`. No env
  mutation outside the project tree.
- Working agreement grant (autonomy, resolve forks by philosophy, commit/push freely on `main`, keep
  specs current) is in effect.
