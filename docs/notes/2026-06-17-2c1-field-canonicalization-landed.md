# 2c.1 landed — in-struct duplicate-label canonicalization

**Status:** done, pushed to `gh:main`. Breadcrumb for the next slice (2c.2).

## What landed

`canonicalizeFields : List Field → List Field` (`Eval.lean`) collapses duplicate-label
slots in a struct frame into ONE first-occurrence slot whose body is the unevaluated
`.conj` of the conjuncts (`joinUnevaluated l r := .conj [l, r]`), reusing
`mergeFieldListWith` (foldl merge-into-existing-else-append → preserves first-occurrence
order, shifts no earlier index). Applied immediately before every `pushFrame`: the 5 struct
arms in `evalValueCoreWithFuel` AND the top-level arms in `evalStructRefsM` (top-level goes
through `evalTopFieldsM`, NOT the `.struct` arm — it needed its own canonicalize). Class
combined via `mergeFieldClass`; mismatch keeps slots separate. Total, no `partial def`.

Memo + cycle invariants preserved (canonicalize before fresh-id `pushFrame`; merged self-ref
slot still hits `slotVisited`→`.top`). FULL existing suite + theorems unchanged.

## What 2c.1 fixes (oracle-confirmed, cue v0.16.1)

- `{a:int, b:a, a:1}` → `b:1` (was `b:int`). CRUX.
- nested `{a:int, c:{e:a}, a:1}` → `c.e:1` (2c.3 visibility proven free).
- conflict `{a:1, b:a, a:2}` → `a` and `b` both bottom.
- self-ref `{a:a, a:1}` → `a:1` (no loop).

## What 2c.1 does NOT fix — this is 2c.2 (the next slice)

CORRECTION to the 2c plan: the inlined-def case `d:{a:int,b:a}; y:d&{a:1}` is NOT a 2c.1
case. It is a **meet of two independently-evaluated structs** — `{a:int,b:a}` evaluates `b`
to `int` BEFORE the meet brings in `a:1`. Structurally identical to the referenced-`#D`
path. All three still give `b:int` post-2c.1:

- `{a:int,b:a} & {a:1}` (literal meet)
- `d:{a:int,b:a}; y:d&{a:1}` (sibling ref then meet)
- `#D:{a:int,b:a}; y:#D&{a:1}` (def ref then meet)

Root cause: `meet` is pure `Value→Value→Value` over already-evaluated structs
(`Lattice.lean` `meetCore`; `.refId _,_ => .bottom` makes refs opaque to meet by design).
The colliding-field merge happens AFTER both bodies are evaluated, so `b` already captured
the first conjunct.

## Next: 2c.2 — meet-produced def bodies (the deep one)

The meet must defer evaluation of colliding bodies: when struct-meet collides two fields of
the same label, wrap them in `.conj` and re-evaluate at the meet site (rather than
`meet`-ing two pre-evaluated values), OR defer def-field eval to the meet site. Then 2c.1's
canonicalization mechanism handles the rest. Pin with the hidden-sibling repro
`#D:{#x?:string, out:{val:#x}}; y:#D&{#x:"hi"}` → `out.val:"hi"`, plus `{a:int,b:a}&{a:1}`,
plus the argocd export fixture once green. Then 2c.3 (fold remaining nested-visibility
checks; already mostly free) and 2c.4 (`apps/argocd.cue` end-to-end).

Beware: the plan warns NOT to force approach (b) (re-point refIds inside meet) under
pressure — meet has no env/scope stack. If the full lazy-meet model proves too invasive,
the safe-failure boundary is to stop and record argocd as a follow-up rather than half-rewrite
the evaluator.

## Carry-forward (standing)

- Alpha cadence: ~1 datestamped release/day via `scripts/release.sh` (DO NOT touch it); NO
  CI/Actions ever.
- External repos (prod9, cue cache) are READ-ONLY.
- Re-ranked next-work list (`plan.md`): 2c.2 → open-list-collapse-on-manifest → `intGe/Gt/Le/Lt`
  → `boundConstraint` collapse → post-2c cleanup batch (base64-out-of-Json, test/`testdata`
  reorg, `Field`→structure).
