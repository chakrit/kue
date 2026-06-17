# 2c.2 landed — lazy resolution through struct conjunction (`&`)

**Status:** done, pushed to `gh:main`. Breadcrumb for the next slice.

## What landed

The `.conj` arm in `evalValueCoreWithFuel` (`Eval.lean`) no longer always evaluates each
operand independently then folds `meet`. A new pre-pass `lazyConjMergedFields env
constraints`:

- `conjStructOperand?` reduces each operand to `(declFields, open_)`, following ONLY
  **depth-0** sibling `refId`s to their struct bodies (the safety boundary — a sibling's body
  frame shares the conjunction site's enclosing scope, so splicing its declarations never
  disturbs an outer reference). Returns `none` for non-structs / patterns / tails /
  disjunctions / outer-scope refs → the arm falls back to the original eval-then-`meet` fold.
- Merge all conjuncts' *unevaluated* declarations into one frame: first-occurrence layout,
  deferred `.conj` on label collisions (`mergeConjFields`, mirrors `canonicalizeFields`'s
  combiner).
- `remapConjRefs` (de-Bruijn-style total shift; `termination_by` lexicographic on fuel)
  rebases each conjunct's depth-0 sibling refs onto the merged layout. depth>0 refs untouched
  — the merged frame sits exactly where each conjunct's own frame would, so only the
  merged-frame layer's indices shift.
- `applyConjClosedness` folds each conjunct's closedness over the merged fields — identical to
  binary meet's `applyStructClosedness`. Then `canonicalizeFields` + one `pushFrame` + eval.

So `d & {a:1}` evaluates `{a: conj[int,1], b: a}` once → `b` sees the narrowed slot `a = 1`.

Memo/cycle invariants preserved (canonicalize before the fresh-id `pushFrame`; a self-ref
merged slot still hits `slotVisited`→`.top`). Total throughout, no `partial def`.

## Fixed (oracle-confirmed, cue v0.16.1)

- `d:{a:int,b:a}; y:d&{a:1}` → `y.b:1` (was `int`). CRUX.
- `{a:int,b:a} & {a:1}` (literal meet) → `b:1`.
- `d & {a:>0}` → `b` tracks the narrowed `a`.
- `#D:{#x:string, out:{val:#x}}; y:#D&{#x:"hi"}` → `out.val:"hi"` (nested-through-sub-struct).
- chained `{a:int,b:a,c:b} & {a:1}` → all `1`.
- closed `#D & {b:1}` → `b` bottoms (closedness preserved).
- Reduced `packs.#Argo` def-meet templating shape **exports byte-identical to `cue export`**
  (`testdata/export/def_meet_template`) — first green on the real-file pattern.

## NOT fixed — next slices

1. **Optional-definition class (the t2 `#x?` blocker).** `#x?:string` + `#x:"hi"` won't merge:
   `FieldClass` has no "optional definition" variant, so `mergeFieldClass` rejects
   `optional`+`definition` and the two slots stay separate, leaving the nested `out.val` reading
   the un-narrowed `string`. This is the ONLY reason the `#x?` form of the hidden-def case is
   still wrong. **Recommended fix:** make optionality an orthogonal axis on `Field` (a `Bool`
   beside `FieldClass`, or a 2-field `FieldClass` record `{kind, optional}`), then
   `mergeFieldClass` merges kind and ORs optionality. Touches the parser (`#x?` → definition +
   optional), `mergeFieldClass`, closedness, and manifest. Own slice; orthogonal to 2c.

2. **Self-shadowing nested ref through def-meet.** `#A:{name, out:{metadata:{name: name}}}` —
   the deep field labeled `name` referencing `name` resolves to itself (shadowing), and both
   kue ("incomplete value: _") and `cue` ("field not allowed") reject it. Different semantics
   (lexical shadowing), NOT a 2c regression — `cue` also errors. Out of scope.

3. **`int & >0` → `>0` collapse.** `meet_lazy_incomplete` shows `a:>0` where `cue` keeps
   `int & >0`. Pre-existing pure-meet formatting collapse (the `intGe/Gt/Le/Lt`→bound-collapse
   carry-forward, not introduced by 2c.2). Already on `plan.md`'s next-work list.

## argocd / alpha

`apps/argocd.cue` is not present on this machine (likely a path on another machine). The
reduced `packs.#Argo` def-meet shape is green and exported byte-for-byte, so the core lazy
def-meet path that gated argocd is unblocked. **A fresh datestamped alpha is warranted.**

## Carry-forward (standing)

- Re-ranked next-work (`plan.md`): optional-definition class → open-list-collapse-on-manifest →
  `intGe/Gt/Le/Lt`→`boundConstraint` collapse → post-2c cleanup batch (base64-out-of-Json,
  test/`testdata` reorg, `Field`→structure).
- Alpha cadence: datestamped releases via `scripts/release.sh` (DO NOT touch it); NO CI/Actions.
- External repos (prod9, cue cache) are READ-ONLY.
