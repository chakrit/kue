# Eval memoization landed — the argocd hang is gone

**Slice:** memoize evaluation to kill the exponential re-eval blowup (Phase B's #1, HIGH —
gates the prod9 workflow). Behavior-preserving optimization: same results, just fast.

## What landed

`Kue/Eval.lean`: `evalValueWithFuel` is now a `StateM EvalState` action threading a memo
cache. Evaluation is a pure function of `(fuel, env, visited, value)`, so caching on that
tuple shares an already-computed result instead of re-deriving it.

- **Cache key cheapness via frame ids.** The naive full-tuple key is sound but pays a deep
  `BEq`/`Hashable` on the (large) `env` at every probe — that alone kept the repro at ~57s.
  Fix: each scope frame gets a **process-unique id** when pushed (`pushFrame` allocates from
  a state counter); `Env := List (Nat × List Field)`. The key stores the frame **id stack**
  (`env.ids : List Nat`), so equality is O(depth) over `Nat`s, not deep frame compare. The
  hash is shallow (`fuel`, `visited`, env depth, value top-tag via `valueTag`) — a probe
  never walks the value subtree; `BEq` runs only on a hash-bucket match. This took the repro
  from 57s → ~7s (matching the unsound no-env-key speed ceiling).
- **Why frame ids are sound for sharing.** Ids track frame *identity*. The depth-0
  self-ref (`env` unchanged) and the `env.drop id.depth` rebase (a suffix) keep their ids,
  so the three `Self.#components.X` selections thread the *same* ids → cache hits.
  Independently-built frames get distinct ids → never falsely share (conservative: a missed
  hit is still correct, just slower).
- **Cycle interaction (load-bearing).** `visited` is in the key, so a binding caught
  mid-cycle is keyed apart from the same binding reached fresh — a wrong mid-cycle partial
  can never be cached and replayed where the cycle guard wouldn't fire. The
  `.refId`/`slotVisited`/`⊤`-on-revisit logic is byte-identical; only its result is memoized.
- **Totality.** The monadic split broke auto structural-recursion inference; each mutual fn
  carries explicit `termination_by (fuel, phase, listLen)` — `fuel` on the real recursion,
  `phase` orders equal-fuel hops (folders 3 → field-refs 2 → wrapper 1 → core/leaf 0),
  `listLen` for same-fuel list self-recursion. **No `partial def`.**

`Kue/Value.lean` UNCHANGED — the custom `Hashable EvalKey` needs no derived `Hashable Value`
(tried deriving it first; reverted as dead).

## Behavior preservation — CONFIRMED

All **574** `native_decide`/`rfl` theorems and every fixture pass UNCHANGED. The four
committed cycle fixtures (direct/mutual/three/constrained) pass untouched. New tests:
`shared_selection_fan` fixture (oracle-matched to `cue export`) +
`eval_shared_repeated_selection` / `eval_cycle_with_repeated_selection` theorems (the latter
pins cache+`visited` preserving bounded-cycle resolution, oracle-matched).

## Timing (READ-ONLY checks)

- Minimal repro (`packs.#Argo & {#name:"stage9"}`, `defs@v0.3.19`): 30s+ timeout (~2.6h
  extrapolated at fuel 100) → **~7s, completes**.
- Local `Self`-fan (exact multiplicative shape, no disk): **~0.006s**.
- **Real `kue export apps/argocd.cue`** (from `/Users/chakrit/Documents/prod9/infra`, the
  ~2.6h hang): now **completes in ~57s**, returns `conflicting values (bottom)`.

## Next blocker — confirmed by the read-only check

The argocd `bottom` is **NOT** a memoization regression — it's the expected next gate:
evaluating `packs.#Argo` eagerly forces its trailing `[Self.#components.repo, …]` list
embedding, which meets against the hidden-only struct and conflicts (`meet(struct,list)=⊥`).
CUE's laziness never forces this — the value is only ever selected into (`.#name`, `.#out`),
never emitted whole.

## Next session — RANKED blockers

1. **Open-list `[...]` embedding EVAL — top semantic blocker (plan item 2).** kue eager:
   `meet(struct, list) = ⊥`; cue lazy: tolerates the latent struct/list conflict when the
   value is only selected into, emits as the list when members are only `#hidden`/`_`/`let`.
   `apps/argocd.cue` and `defs/parts/pod_tolerations.cue` both gate on this. Needs the
   embedding rule (hidden-only struct + list embed) and/or lazier selection.
2. **`if _x != _|_ {…}` comprehension-guard eval.** kue parses it but the guard does not
   fire where cue's does (`_x != _|_` as a presence test). Eval gap. Likely needed alongside
   #1 for the argocd `#components` bodies.
3. **Closedness enforcement under import/unification; bare hidden-field references.**
4. **B3d — registry fetch + MVS + `cue.sum`** — DEFERRED per chakrit.

(Medium/low: `intGe/Gt/Le/Lt → boundConstraint` sum; base64-move out of `Json.lean`;
`testdata/` + test-module reorg; `Field` as a `structure`; Linux `cacheRoot` default.)

## Audit cadence — DUE

This is the **4th slice since the Phase A/B audit** (export-discovery → `[string]:` →
`_`-ident → this memoization). The deepest-core slice yet (rewrote the eval mutual block +
its recursion shape). Per CLAUDE.md, run a **two-phase `/ace-audit`** over the recently
landed work next, with this memoization slice as the headline scrutiny target (cache/cycle
soundness, frame-id identity correctness, totality measure). Fold findings as fix-slices;
cadence, not every iteration — don't stall forward motion.

## Carry forward

- Alpha cadence: ~1 datestamped alpha/day via **`scripts/release.sh`** on chakrit's
  command. **NO GitHub Actions / CI (banned); no `.github` dir; do NOT touch
  `scripts/release.sh` / `packaging/` / release files.**
- External repos (prod9 tree + the cue cache) are **READ-ONLY** reference.
- Verify gate this slice: `lake build` exit 0 (all 574 theorems), `scripts/check-fixtures.sh`
  ⇒ `fixture pairs ok`, `shellcheck` clean — all green.
