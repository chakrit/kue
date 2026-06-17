# 2c — Lazy field resolution through definition-meet: recon + plan

**Status:** design/implementation plan for slice family 2c (the #1 real-file blocker for
`apps/argocd.cue`). From a read-only recon, 2026-06-17. Drives 2c.1–2c.4.

## Root cause (exact — it's in Eval, NOT meet)

`resolveAndEval = evalStructRefs ∘ resolveStructRefs` (`Runtime.lean:15-16`). Resolution
runs ONCE against the syntactic field list, before any meet. Field bodies are then
evaluated EAGERLY, one-shot, against the **pre-merge** slot list; duplicate/merged labels
are combined too late.

Crux repro: `{a: int, b: a, a: 1}`. `buildFrame` (`Resolve.lean:12-17`) →
`[(a,0),(b,1),(a,2)]`; `findInFrame "a"` returns first match = index 0, so `b` →
`.refId ⟨0,0⟩`. At eval (`Eval.lean:740-745` `.struct` arm) `pushFrame` pushes the UNMERGED
list; `b`'s `⟨0,0⟩` resolves to `a:int` → `int`. Only AFTER all bodies eval does
`mergeEvaluatedFields` (`Eval.lean:99-100`) collapse the two `a`s to `int & 1 = 1` — too
late; `b` already captured `int`. `#D & {a:1}` reduces to the same defect; `meetCore` even
has `.refId _, _ => .bottom` (`Lattice.lean:387-388`) — refs are opaque to meet by design,
so the fix must NOT live in meet.

## Oracle model (cue v0.16.1, confirmed)

- `#D:{a:int,b:a}; y:#D&{a:1}` → `y.b: 1`. **kue wrong** (`incomplete value: int`).
- nested `c:{d:a}` → also `1` (merge visible through nested sub-structs).
- hidden `#D:{#x?:string, out:{val:#x}}; y:#D&{#x:"hi"}` → `out.val:"hi"`.
- ref to still-incomplete merged field stays symbolic: `y:#D&{a:int&>0}` → `b: int & >0`.
- **`Self` is NOT a CUE builtin** — `cue eval` errors "reference Self not found". It only
  works as an arbitrary alias name (B2's `#Role: Self={…}`). Validate 2c against the real
  `out:{val:#x}` hidden-sibling form, NOT a bare `Self`.

CUE model: all conjuncts merge into one field set first; each body then evaluates lazily in
the scope of that unified set.

## Approach (recommended: (c) canonicalize-before-eval)

Rejected: (a) re-resolve refs after meet (indices shift; resolve works on `.ref` strings
not `.refId`; meet has no scope stack). (b) re-point refIds inside meet (meet is pure
`Value→Value→Value` with no env; breaks the refId-opacity invariant; depth math
intractable).

**(c)** Before `pushFrame`/`evalFieldRefsList` in the `.struct` arm, **canonicalize**
`nestedFields` by label: merge duplicate-label bodies into ONE first-occurrence slot whose
body is the *unevaluated* `.conj [bodyA, bodyB]` (NOT `meet` — bodies aren't evaluated
yet), preserving first-occurrence order and shifting no earlier index. Then push + evaluate
against that frame. Because `findInFrame` already returns first-match, `b`'s `⟨0,0⟩` now
lands on the merged `a` slot (`conj[int,1]` → `1`). RefIds, BindingId model, and meet's
refId-opacity all stay intact — the only change is *what sits in slot 0*.

Reuse `mergeFieldListWith` (`Lattice.lean:491-498`, already foldl merge-into-existing-else-
append = preserves first-occurrence position) with a combiner `joinUnevaluated l r =
.conj [l, r]`.

## Sub-slices

- **2c.1 (FIRST, low-risk):** in-struct duplicate-label canonicalization. Add
  `canonicalizeFields : List Field → List Field` and apply in ALL struct arms in
  `Eval.lean` (`.struct`, `structTail`, `structPattern`, `structPatterns`, `structComp`,
  ~`740-794`) before `pushFrame`. Fixes `{a:int,b:a,a:1}` and inlined-def
  `d:{a:int,b:a}; y:d&{a:1}` → `b:1`. Files: `Eval.lean` (+ maybe a `Lattice` helper).
- **2c.2 (hard half):** meet-produced def bodies — `#D & {…}` where `#D` is *referenced*
  (not inlined) must re-evaluate merged bodies. Likely needs def-field eval deferred to the
  meet site, or struct-meet wrapping colliding bodies in `.conj` instead of relying on
  pre-evaluated values. Fixture: `out:{val:#x}`.
- **2c.3:** nested sub-struct visibility (`c:{d:a}`) — likely free once 2c.1 lands; add a
  fixture to prove it (outer ref `depth=1`).
- **2c.4:** `apps/argocd.cue` `packs.#Argo` def-meet path end-to-end (export fixture).

## Behavior-preservation (highest-risk since memoization)

- **Memo cache SAFE:** keyed on `env.ids`; `pushFrame` allocates a fresh id per push, so a
  canonicalized frame is a different object → fresh id → no stale `b:int` hit. CRITICAL:
  canonicalize in exactly ONE place (eval, before `pushFrame`); never let resolve and eval
  disagree on the list, never touch id allocation.
- **Cycles unaffected:** `b:a` is a forward sibling ref, not a cycle; merging `a` into slot
  0's `.conj` leaves `b`'s slot index unchanged; `slotVisited`→`.top` still guards a
  self-referential conj.
- **Likely-shifting fixtures** (run full suite, expect zero diffs except new): `field_conflict`,
  `struct_disjunction_meet`, `nested_struct_field`, `definition_closed`,
  `closed_hidden_definition`, `value_aliases`, `list_embedding_meet_two`. Safe because
  `.conj`-then-eval is semantically identical to eval-then-merge EXCEPT when a slot's body
  references a merged sibling — i.e. only the buggy cases change. `field_conflict` still
  bottoms (conj of conflicting prims → bottom at eval).

## Safe-failure boundary

Land 2c.1 behind its own fixtures first. If the full lazy model (2c.2) proves too invasive
(reworking `selector`/`refId` laziness), STOP after 2c.1+2c.3 — that fixes the in-struct +
inlined-def cases (most real def-meet shapes) — and record 2c.2/argocd as a follow-up
rather than forcing a half-working evaluator rewrite. Do NOT attempt approach (b) under
pressure.

**Key files:** `Eval.lean` (`740-794`, `681-694` refId, `99-100` merge, `587-622`
memo/pushFrame); `Resolve.lean` (`12-32`, `95-97`); `Lattice.lean` (`482-498`, `804`,
`387-388`); `Runtime.lean:15-16`.
