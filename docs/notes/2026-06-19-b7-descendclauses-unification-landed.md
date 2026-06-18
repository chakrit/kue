# RESUME HERE — B7 clause-walker unification LANDED (2026-06-19)

Supersedes the prior START-HERE pointer
(`2026-06-19-a5-followup-deferral-gate-landed.md`). Standing grant in effect
(autonomy / Lean-into-Lean-4 / commit-push freely / specs as restore point). Full record:
`docs/reference/implementation-log.md` ("B7" entry); ranked work: `docs/spec/plan.md`
(Live Backlog — B7 now marked DONE).

## What landed — four commits on `main`

`bbb00b2` / `c5cbb0e` / `aa5518c` + this docs commit (pushed to gh:main).

B7 unifies the five frame-depth clause walkers behind ONE authority, killing a bug that had
recurred FOUR times (A1's sibling, A5, A5-followup, the #3 backwards-reasoning walker): each
walker hand-re-derived the de Bruijn clause-chain rule (`+1` per `for`, `+0` per `guard`,
body at the accumulated depth) and one eventually got it wrong.

**The authority — `descendClauses` in `Value.lean`** (the leaf where `Clause` is defined,
imported by both Resolve and Eval):
```
descendClauses {α} (empty : α) (append : α→α→α)
    (onSource onGuard : Nat→Value→α) (onBody : Nat→α)
    (depth : Nat) : List (Clause Value) → α
```
Pure, total, structural on the clause list, `Value`-non-recursive — it threads depth only
and hands each piece back to the caller's `onSource`/`onGuard`/`onBody`, generic over the
accumulator with a monoid-like `(empty, append)`. A thin `clauseChainDepth start clauses`
(the fold with an identity body-handler) recovers the post-chain depth.

**What migrated:**
- Three scanners → one-line `descendClauses` instantiations (Bool ‖/false, List ++/[]):
  `refsSelfEmbeddedLabelClauses`, `selfReferencedLabelsClauses`, `hasSelfRefAtDepthClauses`.
  No longer self-recursive; their mutual blocks shrank.
- `remapConjRefs`'s `.comprehension`/`.listComprehension` body shift → `clauseChainDepth
  frameDepth clauses`. **`clauseFrameShift` DELETED** — it was the second, inequivalent
  encoding of the rule living only in `remapConjRefs` (the sharpest recurrence hazard).
- `resolveClausesWithFuel` (the fifth walker) NOT migrated — it threads a scopes stack, not
  a `Nat`, and is `mutual` with eval. It stays the REFERENCE, tied to the fold by an
  agreement theorem.

**NOT a `Depth` newtype** (option (a), rejected): ~24 arm rewrites + `DecidableEq`/kernel
cost on the hot resolve path for zero new guarantee. The recurring bug was the per-walker
*re-derivation*, not a raw `+1`.

**NEW guarantee (the structural pin this slice buys):** two `native_decide` agreement
theorems in `EvalTests` —
- `descend_clauses_frame_count_matches_resolve`: the depth `resolveClausesWithFuel` reaches
  for a comprehension body equals `clauseChainDepth` (ties fold↔reference without coupling code).
- `descend_clauses_agrees_remapConjClauses`: the body fold agrees with the clause-list rebuild.
Plus `descend_clauses_chain_depth_counts_only_for` pinning the +1/+0 shape. Future drift
between the fold and a walker / the resolver is now a build failure, not a silent wrong value.

## Verify (all green, every commit)

`lake build` 86 jobs; `scripts/check-fixtures.sh` → `fixture pairs ok` (ZERO byte-drift
across all four commits — the whole correctness gate for a behavior-preserving refactor).
The two B7-relevant fixtures spot-checked content-identical to live `cue` v0.16.1:
`comprehension_conj_body_remap` → `s.a.out: 99`; `comprehension_embed_self_narrow_body` →
`v.out: [{v: "y"}]`, `v.#t: "y"`. No shell scripts changed (shellcheck N/A). Pure refactor,
no eval-path change → perf unchanged (no `kue-performance.md` edit).

## Next step — TWO-PHASE AUDIT IS DUE

B7 is 1 slice since the last audit. Per the slice-loop cadence (every 2–3 slices), the
two-phase audit is now due. Run it NEXT (sequential, per `docs/guides/slice-loop.md` — do
NOT invoke `/ace-audit`): **(A) code-quality audit** over B7 (correctness, totality,
illegal-states, DRY, test strength, skill compliance — pay attention to the new
`descendClauses` fold + the agreement theorems), then **(B) architecture / refactor audit**
over the whole module graph. Fold findings into the plan as fix-slices.

Then, ranked (plan.md Live Backlog sequence):

1. **B2** — headline 5-struct-constructor unification (collapse `struct`/`structTail`/
   `structPattern`/`structPatterns`/`structComp` into one normalized `struct` with a 3-state
   `StructOpenness`; erases the `open_`/`hasTail` nonsense state AND the incomplete 12-arm
   meet matrix). Design-spike first, then mechanical multi-commit migration. The single
   biggest type-system-leverage win left in the graph.
2. **B6** design-spike / **A2-followup** import-binding marker / **item 1** follow-up
   (full `apps/argocd.cue` end-to-end).
3. **Overdue test-org pass (item 5):** `EvalTests.lean` is now ~3020 lines. When it lands,
   B7's agreement theorems are a natural seed for a new `ClauseDepthTests` module; B4's
   `LatticeTests` should land before/with B2.

Releases: ~1 datestamped alpha/day via `scripts/release.sh` (local only — CI banned).
