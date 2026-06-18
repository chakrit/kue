# RESUME HERE — Value.closure slice 3 (closure-producer) landed (2026-06-18)

START-HERE pointer; supersedes `2026-06-18-valueclosure-slice2-landed.md`. Tree clean,
pushed to `gh:main` at `42db7fa`.

## What just landed

**Frontier #1 (`Value.closure`) slice 3 of 5 (`closure-producer`) is committed (`42db7fa`).**
The FIRST behavior-changing closure slice. `evalValueCoreWithFuel`'s `.selector (.refId id)
label` arm now EMITS a `.closure capturedPkgEnv defBody` (instead of eagerly evaluating the
base and plucking the field) when selecting an imported definition whose body
self-references — the exact shape that collapses today. Build 86 jobs, `fixture pairs ok`
(zero drift — behavior-preserving on every committed fixture), 7 `native_decide` pins, plus
the `closure-env-sync-guard` tripwire folded in.

### The producer (trigger, empirically traced)

In the `.selector (.refId id) label` arm, `thisStructFieldIndex? = none` else-branch, BEFORE
the eager `base`-eval:

```
match importDefClosureBody? env id label with
| some (pkgFields, defBody) => do
    let capturedEnv <- pushFrame pkgFields env
    pure (.closure capturedEnv defBody)
| none => <eager path unchanged>
```

`importDefClosureBody? env id label` returns `some (pkgFields, defBody)` iff, on the
UNEVALUATED binding `id` resolves to in `env`: (1) it is a `.struct pkgFields _`; (2)
`pkgFields` has a field `label` that is a definition (`fieldClass.isDefinition`); (3) that
def body has a sibling self-ref (`defBodyHasSiblingSelfRef` → `hasDepth0Ref`: a `refId
⟨0,_⟩` reachable WITHOUT crossing a frame-pushing node — `hasDepth0Ref` stops at
`.struct`/patterns/comprehension/nested `.closure`). The capture is the FULL id-stack
(`pushFrame pkgFields env`), so the def body's own depth>0 cross-package embeds still walk
the import chain when forced.

### Why behavior-preserving (DO NOT relearn)

Condition 3 is the exact collapse set. Self-ref-free def bodies (`#Widget`, `#Box`, `#Mid`,
`#Atom`, `#Name` — EVERY committed `pkg.#Def & {…}` fixture, verified by trace) evaluate
identically eager-or-deferred → stay eager. Self-ref def bodies (`#M`={#name,out:#name})
error today (`incomplete value`) → deferring regresses no GREEN fixture. NOT the
(a)-narrowed trap: `capturedEnv` is ALWAYS the full env; condition 3 gates only *whether to
defer*. Same-package `#Def & {…}` is a `.refId` (not a selector) → `conjStructOperand?` /
`lazyConjMergedFields` handle it, never enters the selector arm → structurally untouched.

### Env-defeq tripwire (Phase-A `closure-env-sync-guard`, landed here)

`example : (List (Nat × List Field)) = Env := rfl` next to `abbrev Env` in `Eval.lean` —
fails the build if `Frame`/`Env` desyncs from `Value.closure`'s `capturedEnv` rep.

### Observable state after slice 3 (honest)

- Cross-pkg `parts.#M & {#name:"keel"}` repro: was `incomplete value: string`, now
  `conflicting values (bottom)` (closure forced → slice-1 inert `meet` → `.bottom`). STILL
  an error — NOT a committed fixture. Slice 4 fixes it; slice 5 pins it.
- Same-pkg `#M & {#name:"keel"}`: stays `{"out":"keel"}` (untouched).
- Repro modules live in `/tmp` ONLY (not committed): `/tmp/cpdm` (cross-pkg, `cue` →
  `{"out":"keel"}`), `/tmp/samepkg` (same-pkg). Rebuild in fresh `/tmp` if gone.

## NEXT — slice 4 (`closure-meet`) DESIGN SUB-SPIKE FIRST

This is THE unlock: a closure met with a use-site struct must splice the use-site in as an
extra conjunct so the body's `out:#name` sees the narrowed `#name:"keel"` BEFORE it
collapses. `plan.md` § "Value.closure work plan" slice 4 is the authority. What the
sub-spike must pin (carried from this slice + Phase-A findings):

- **Force point (in `Eval`, NOT `Lattice.meet` — meet is pure, no `EvalM`).** The closure is
  produced in the `.selector` arm and currently flows into the `.conj` eval-then-`meet`
  fallback (`Eval.lean` `.conj` `none` branch, ~L1003-1005 post-slice-3): `evalValuesWithFuel`
  yields `[.closure capEnv defBody, .struct useSite]`, then `foldl meet`. RECOMMENDED force
  point: detect, in that `.conj` fallback, when an evaluated operand is a `.closure` and
  another is a (struct-shaped) use-site, and instead of `meet`, force the closure WITH the
  use-site spliced in — i.e. a new `forceClosureWithConjunct fuel capEnv defBody useSite`
  that pushes `capEnv`, merges `useSite` as an extra conjunct into the def body's frame
  (reuse `lazyConjMergedFields`/`mergeConjFields`/`canonicalizeFields`), and evals. Confirm
  whether to handle it there vs. also in a `meet`-arm-triggered Eval hook; the `.conj`
  fallback is the only place a closure currently meets a struct, so start there.
- **Splice mechanics.** The use-site `{#name:"keel"}` is a depth-0 struct relative to the
  USE-SITE frame, but must be merged into the DEF body's frame (under `capEnv`). Its depth-0
  refs (if any) need rebasing onto the merged layout — same machinery `lazyConjMergedFields`
  uses for same-package conjuncts (`rebaseConjunctFields`/`labelIndexMap`). The def body is
  `.struct defFields _`; splice `useSite`'s fields as additional conjuncts per-label so
  `#name` becomes `string & "keel"` → `"keel"`, then `out:⟨0,0⟩` resolves to `"keel"`.
- **Cycle keying (derive from FIRST PRINCIPLES, NOT by analogy to the depth>0 ref arm —
  Phase-A finding 2).** A forced closure is a FRESH eval entry → `visited` starts `[]` →
  the ordinary `slotVisited` machinery catches a self-ref reached via a depth-0 ref into the
  pushed def frame. A closure capturing a self-referencing frame, forced twice with the same
  `capturedEnv` ids + `body` (+ same spliced use-site), shares a memo entry — `EvalKey` keys
  on `(fuel, envIds, visited, value)` and `fuel` STAYS in the key (LOAD-BEARING, 263
  fuel-truncation conflicts — do NOT drop it). `valueTag`'s closure tag (29) participates in
  the shallow memo hash unchanged. Add a self-ref captured-frame termination pin (Phase-A
  finding 3) — a closure whose `capturedEnv` frame refs itself terminates (→ `.top`), not
  loops/exhausts fuel.
- **Format honesty (Phase-A finding 4, slice-5 audit item):** once closures are forceable,
  check a leaked unforced closure can't silently reach Format/Manifest output looking like
  its body. `manifest` already → `.incomplete`; `Format` prints the bare body (no
  deferred-marker). Track in the slice-5 edge-case audit.

After slice 4: slice 5 (`closure-regression`) adds `testdata/modules/crosspkg_defmeet/`
(the `/tmp/cpdm` repro as a committed fixture, `expected = {"out":"keel"}`), edge-case audit
(`Self={…}` alias form, two-declaration `t1: parts.#M` / `t1: #name:"keel"` form, nested
import, closed-struct/pattern interplay, the self-ref captured-frame cycle pin).

## Audit cadence — DUE NOW

Slices 1 (`closure-ctor` `26a2040`), 2 (`closure-eval` `15c92ec`), 3 (`closure-producer`
`42db7fa`) are all landed. The last audit pass was Phase A `a347386` + Phase B `31b329c`
(BOTH over slices 1-2 only). Slice 3 is the third since, and the FIRST behavior-changing
one — a two-phase audit (Phase A code-quality, then Phase B architecture) per
`docs/guides/slice-loop.md` is DUE before/around slice 4. Run it sequentially; fold findings
into the plan as fix-slices; do NOT let it stall slice 4.

## Standing context (durable, do not relearn)

- **Release:** ~1 datestamped alpha/day, `0.1.0-alpha.YYYYMMDD[.N]`, **local
  `scripts/release.sh` only — CI/GitHub Actions BANNED**. Latest `v0.1.0-alpha.20260617.3`.
  Did NOT cut a release (mid-churn). Do NOT touch `scripts/release.sh`, `packaging/`, the tap.
- **Safety:** prod9 + cue cache READ-ONLY (eval/probe only). The session bash output filter
  mangles piped/heredoc git input → use `git commit -F /tmp/msg`. Trust `lake build` as
  coverage ground-truth. NO `git checkout`/`restore`/`reset --hard`.
- **`fuel` is LOAD-BEARING** in `EvalKey` (263 fuel-truncation conflicts) — never drop it
  from the memo key when adapting cycle/memo handling in slices 4-5.
- **Perf hang (frontier #2)** is downstream — real apps error at #1 (~0.9s) before the
  blowup, unreachable until slice 5 lands; re-profile then, then frame-id sharing.
- **cue oracle:** `/Users/chakrit/go/bin/cue` v0.16.1.
