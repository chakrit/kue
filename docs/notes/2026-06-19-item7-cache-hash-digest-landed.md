# Breadcrumb: item 7 — cache-key hash digest landed (2026-06-19)

**START HERE.** Supersedes [`2026-06-18-session-save.md`](2026-06-18-session-save.md)
and
[`2026-06-19-a2-followup-importbinding-marker-landed.md`](2026-06-19-a2-followup-importbinding-marker-landed.md)
as the current pointer.

## What landed (the real perf wall — DONE)

Item 7: the O(N²) memo-cache hash collision. The `EvalKey`/`SatKey` hashes keyed on
`valueTag` (top constructor tag only) + `envIds.LENGTH`, so a deep app's steady-state
population collapsed into ONE hash bucket → O(N) `BEq` scan per `cache.get?` → O(N²).
Fixed with `valueDigest DIGEST_DEPTH` (depth 3) — a total, fuel-free, bounded-depth
structural digest — in both `Hashable` instances, plus hashing the full `envIds`. `BEq`
UNCHANGED → soundness unconditional (hash only picks a bucket; a lossy digest can
miss/scan, never return a wrong value). Zero fixture byte-drift.

**Measured (READ-ONLY prod9 oracle `/Users/chakrit/Documents/prod9/infra`):**

- cert-manager `kue export apps/cert-manager.cue --out yaml`: **119s → ~30.6s (~3.9×)**,
  content-identical to `cue` (only field order differs — known #3).
- Full `apps/argocd.cue`: >7.5min/killed → **~88s but STILL bottoms** (`conflicting
  values (bottom)`) — the SEPARATE fuel-exhaustion-at-scale limit, not a hash problem.
  Much faster, not unblocked.
- `FrameKey` deepening: profiled, ZERO change → left shallow (frame sharing + `parentIds`
  already discriminate). No follow-up slice needed.

Pins (`EvalPerfTests.lean`): bucket distribution (1000 k8s-shaped structs → 1000 buckets
at depth 3 vs 1 under `valueTag`), depth-0 degenerates to the tag, totality/determinism
on a deep value.

## Where things stand

- **Real-app correctness: DONE** for both probed prod9 apps (cert-manager + argocd
  `packs.#Argo` chain). cert-manager now exports correctly AND in ~30s — the
  basic-usability bar from the correctness-over-performance decision is met for this app.
- **The hash wall is gone.** The next perf lever is NO LONGER the cache hash; it is the
  **fuel-exhaustion-at-scale** frontier that still bottoms full `apps/argocd.cue` at ~88s.
  Raising `evalFuel` is NOT a fix (trades soundness/termination for a higher-but-finite
  ceiling); the lever is reducing the combined eval's convergence depth / per-eval count
  so it stays under the ceiling.

## Next step (pick one)

1. **Celebrate the real-app unblock partially:** cert-manager is fast and correct. argocd
   is fast but fuel-bottomed — the remaining real-app gap is the fuel ceiling under
   combined load.
2. **Audit cadence:** item 7 is 1 slice since the last audit. Per the slice loop, a
   two-phase audit is due at the 2–3-slice mark — schedule it after the next slice or now.
3. **Backlog (no longer behind the hash wall):** B6-deferred; field-order #3 (cue orders
   `ref & {own}` own-fields first — a byte-diff concern, gates argocd byte-parity but not
   correctness); B2-A1/A2; the argocd fuel-exhaustion frontier (the new perf #1).

## Standing rules

- prod9 + cue caches READ-ONLY (eval/probe only). NO `git checkout`/`restore`/`reset
  --hard`. No env mutation outside the project tree.
- Working agreement grant (autonomy, resolve forks by philosophy, commit/push freely on
  `main`, keep specs current) is in effect.
