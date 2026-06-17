# Breadcrumb — real-app eval blocker DIAGNOSED (cross-package def-meet); deferred (deep)

## TL;DR

Imports resolve for real prod9 apps; the remaining gap to real-app export is TWO distinct
deep blockers in the EVAL layer, both surfaced by `kue export -e <app>
/Users/chakrit/Documents/prod9/infra/apps` (READ-ONLY oracle):

1. **Cross-package def-meet laziness** (correctness). A `pkg.#Def & {use-site fields}` (or
   any unification of an imported definition) evaluates the def body's *self-references*
   prematurely — against the imported def's own frame, before the use-site fields are
   unified in — yielding `incomplete value` / `conflicting values`. cue resolves it.
2. **Eval fan-out / perf blowup** (the hang). Large defs (`defs.#Deployment`,
   `defs.#ServiceAccount` in the real app) burn CPU to a 30–40s+ timeout. CPU-bound, not a
   deadlock — exponential re-evaluation, the `Self.#components.X`-style fan-out the memo
   comment (`Eval.lean` ~L776) already names. The reduced shapes error in 0.01s, so the
   hang scales with def size/nesting, separate from blocker 1.

Both are architectural, neither a clean one-slice fix. Per the slice brief's safe-failure
path, this slice commits the precise diagnosis + reduced repros + recommended approach
rather than forcing a deep change. NO engine change landed this slice.

## How it was found (data-driven)

- `kue export -e <app> <prod9 infra/apps>` for keel/argocd/x9/typesense/vproxy: **all
  TIMEOUT (exit 124) at 30s**, CPU-bound (~99% cpu). cue exports each in <1s.
- Bisected to a single imported def: `defs.#ServiceAccount & {#name,#ns}` hangs; even
  `defs.#Deployment & {…}` alone hangs (37s CPU). The thin `#ServiceAccount` reduces to
  `parts.#Metadata` → `attr.#Metadata` (all in dep `prodigy9.co/defs@v0.3.19`).
- A faithfully-reduced cross-package shape of `#ServiceAccount` errors **fast** (0.01s,
  `conflicting values`) — so the hang is a *separate* blocker from the correctness bug; the
  correctness bug is the one with a crisp minimal repro.

## Blocker 1 — minimal repro (correctness)

A 2-package module under a `cue.mod` (`ex.co`), nothing else:

```
# parts/m.cue
package parts
#M: {
	#name: string
	out: #name        # <- self-reference to a sibling field
}
# top.cue
package ex
import "ex.co/parts"
t1: parts.#M & {#name: "keel"}
```

- **kue**: `export error: incomplete value: string`
- **cue v0.16.1**: `{ "out": "keel" }`

The `Self={…}` value-alias form (`#M: Self={ #name: string; out: Self.#name }`) triggers
the identical failure — the alias is NOT required; a plain sibling self-reference is enough.
Both the on-one-line `&` form and the two-declaration form (`t1: parts.#M` / `t1: #name:
"keel"`) fail identically (both become a `.conj` whose operand is a depth>0 selector).

**Crucial contrast — same-package is FINE.** Put `#M` and `t1` in two files of the *same*
package (no import) and it exports `{"out":"keel"}` correctly. So the bug is *specifically
the import/package boundary*, not def-meet in general.

## Root cause

The 2c.2 lazy-conjunction-eval path (`Eval.lean`: `lazyConjMergedFields` /
`conjStructOperand?`) is what makes same-package `#D & {a:1}` resolve `b:a` to `1`: it
merges *unevaluated* conjunct declarations into ONE frame, pushes once, then evals — so a
body ref sees the narrowed sibling. But `conjStructOperand?` deliberately **refuses any
operand whose refId has `depth != 0`** (the documented safety boundary — plan L1846, and
the depth-0 note at L1097). A cross-package `pkg.#Def` is reached through a *selector into a
hidden import binding*, which is a depth>0 reference. So the conjunction falls back to the
**eval-then-`meet`** path (`Eval.lean` `.conj` arm, the `none` branch ~L930-932):
`parts.#M` is fully evaluated in the imported package's frame first — collapsing `out:
#name` to `incomplete value: string` because `#name` is still just `string` there — and the
subsequent `meet` with `{#name:"keel"}` can no longer un-collapse the already-finalized
`out`.

In short: the eager-def-meet limitation the plan tracks for inlined defs, but extended
across the import boundary, where lazy-conj cannot reach because the operand is depth>0.

## Why it's deep (why deferred)

The depth>0 refusal is not an oversight — 2c.2 excluded it as *unsafe*. Splicing an
imported def's fields into a merged frame at the use-site would mis-resolve the def body's
*own* depth>0 references (e.g. `parts.#Metadata`'s `attr.#Metadata` cross-package embed):
those are de-Bruijn-encoded relative to the *parts package frame*, reachable through the
import-binding chain, not from the `ex` use-site frame. There is no single flat frame that
simultaneously carries the def's package context AND the use-site constraint — the
architecture has no closure/thunk Value to defer a body together with its frame.

A self-contained-def-only fix (splice only when the body has no depth>0 refs) would handle
the bare `Self.#name` repro but NOT the real `#ServiceAccount` (its `attr.#Metadata` embed
has depth>0 refs), so it would not unblock the real app — not worth the special case.

## Recommended approach (for the future deep slice)

Introduce a frame-carrying deferral so `pkg.#Def` can unify with use-site fields *before*
its body's self-refs collapse, while the body's own (depth>0) refs still resolve against the
def's package frame. Options, type-system-first:

- A `Value.closure (frame : Frame) (body : Value)` (or `thunk`) constructor: selecting
  `pkg.#Def` yields the unevaluated body tagged with its captured package frame; `meet` of a
  closure with a use-site struct defers to a merged-frame eval that pushes the captured
  frame, splices the use-site constraints, and rebases. This is the principled fix and
  generalizes 2c.2 across the import boundary.
- Cheaper but narrower: in the `.conj` arm, special-case an operand that is a `selector`
  resolving to an imported struct — evaluate the def body in `(use-site-constraint-frame ::
  def-package-frame)` so both resolve. Needs careful rebasing of the use-site conjunct's
  depth-0 refs; verify against the real `#ServiceAccount`/`#Deployment` shapes.

Land blocker 1 and blocker 2 (perf) as SEPARATE slices — they are independent.

## Blocker 2 — the perf hang (separate, also deep)

`defs.#Deployment & {…}` alone is 37s CPU to timeout; `defs.#ServiceAccount` ~30s. The
reduced shapes are instant, so this is fan-out that grows with def size — the memo key
(`EvalKey`, `Eval.lean` ~L781) hashes shallowly and caches on `(fuel, envIds, visited,
value)`, but a large def with many sibling selectors (`Self.#x.y`) still re-derives
sub-structs across fuel levels. Recommended: profile which arm re-evaluates (likely the
selector + `.conj` interaction in big nested defs), and either deepen memoization or
restructure so a sub-struct is computed once per frame. Investigate before designing.

## Repro location

Self-contained repros live in `/tmp` only (NOT committed — external/throwaway). The
reduced module is `parts/m.cue` + `top.cue` + `cue.mod/module.cue` as above; reproduce in a
fresh `/tmp` dir. No testdata fixture added: the module-fixture harness
(`check-fixtures.sh check_module_fixtures`) has no expected-failure mode, so a fixture
pinning the (correct) cue output would red the gate until blocker 1 is fixed. **When blocker
1 lands, add `testdata/modules/crosspkg_defmeet/` (the repro above, `expected` =
oracle JSON) as the regression pin.**

## NEXT step for the loop

Pick blocker 1 (cross-package def-meet laziness) as the next real slice — it has the
crispest repro and is the gating correctness bug. Blocker 2 (perf) gates actually *running*
the full apps to completion but is orthogonal; sequence it after, with profiling first.

## Audit cadence

Last light audit / audit-reference was `b45848b`. Count THIS as a slice since then
(diagnosis-only, no code) — per the loop's ~3–4 cadence, an `/ace-audit` pass is due around
the next 1–2 substantive (code-landing) slices.

## Standing facts (carry forward)

- Alpha cadence: datestamped alphas via `scripts/release.sh`, **NO CI**. Latest
  `v0.1.0-alpha.20260617.3`. Do NOT touch `scripts/release.sh`, `packaging/`, or the tap.
- External repos (cue module cache `~/Library/Caches/cue`, prod9 `infra/apps`) are
  **read-only** oracles. cue oracle: `/Users/chakrit/go/bin/cue` v0.16.1.
