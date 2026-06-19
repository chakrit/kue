# RESUME HERE — argocd bottom PINNED: comprehension-guard / embed-narrowing (2026-06-19)

**START HERE.** Supersedes
[`2026-06-19-argocd-bottom-is-correctness-not-fuel.md`](2026-06-19-argocd-bottom-is-correctness-not-fuel.md)
as the current pointer. Standing grant in effect (autonomy / Lean-into-Lean-4 / commit-push freely /
specs as restore point).

## What this slice did

Pinned the full `apps/argocd.cue` `conflicting values (bottom)` to its real root cause and landed a
sound partial fix. **The prior breadcrumb's cross-module / import-laziness hypothesis is DISPROVEN**
— the bug reproduces SAME-MODULE and has nothing to do with unreferenced siblings or the module hop.
The `#args/#from/#to` `fieldConflict` signal was a red herring (an unrelated `tests:` aggregate).

### The pinned root cause

Minimizing `defaults.#ListenerSet` (= `defs.#ListenerSet & parts.#UseCertManager & {…}`) down to
`parts.#Mixin` pinned the shape: a comprehension guard reads a REGULAR sibling narrowed at the use
site —

```
#Mixin: Self={
  #additions: [string]: {#kind: string, #patch: _}
  let _patch = { kind: string; for _, add in Self.#additions { if kind == add.#kind { add.#patch } } ... }
  let structShape = { _patch; ... }
  listShape | structShape | error("…")
  ...
}
#UseCertManager: { #Mixin; #additions: cert_ls: {#kind: "ListenerSet", #patch: {metadata: …}} }
```

cue defers the comprehension until `kind` is concrete (from `& {kind: "ListenerSet"}`) and emits the
matched `#patch`. Kue forces the embedded def with only HIDDEN fields spliced (`hiddenFieldsOnly`),
so the guard fires against the un-narrowed `kind: string`, stays incomplete, and the guarded body
drops — the outer `meet` cannot re-fire a collapsed comprehension.

### Two bugs at different nesting depths

- **Bug #1 — single-embed comprehension-guard splice (FIXED).** `#Outer` embeds `#Inner` whose guard
  is a DIRECT top-level comprehension. Fix in `Kue/Eval.lean`: `defFrameRefIndices` (collects the
  def-frame slot indices a value reads, threading frame depth incl. a comprehension's `+1`-per-`for`)
  → `embedComprehensionReadLabels` → `spliceOperandForEmbed` (splice = `hiddenFieldsOnly` PLUS the
  regular siblings a comprehension reads). Wired into the two `forceClosureWithConjunct` splice sites
  (`evalEmbeddingFieldsWithFuel`, `meetEmbeddingsWithFuel`). Sound: real-conflict still bottoms,
  guard-false no over-fire (`native_decide` pins + `crossmod_embed_guard` fixture). Zero fixture
  drift; cert-manager unaffected.

- **Bug #2 — let-buried multi-embed narrowing (OPEN — the actual argocd blocker).** In the real
  `#Mixin` the comprehension is buried under `let _patch` → `let structShape` → embed, AND wrapped in
  `listShape | structShape | error(…)`. The use-site narrowing must propagate DOWN several `let`/embed
  layers (and through the disjunction-arm selection) to reach the guard. The single-level splice does
  not thread that far: WITH the disjunction it BOTTOMS; without it, wrong-output (drops the patch).

### argocd status

Full `apps/argocd.cue` STILL bottoms — re-measured **88.85s** (2026-06-19, post Bug-#1 fix). Bug #1's
fix is real forward progress (single-embed case + a cross-module fixture) but does NOT clear the app;
Bug #2 is the remaining blocker.

## Repros (uncommitted, session host — regenerate if gone)

- `/tmp/same-mod` — same-module vendored `#Mixin`. Toggle the `listShape | structShape | error`
  disjunction in `mixin.cue`: WITH it → bottom; without → wrong-output (drops the patch). The
  single-embed `#Inner`/`#Outer` reduction (no `let`, no disjunction) now exports correctly (Bug #1).
- `/tmp/ls-probe` — cross-module `defs.#ListenerSet & parts.#UseCertManager` against the real
  `prodigy9.co/defs@v0.3.19` cache: still bottoms (Bug #2). Oracle `cue export .` exports clean.

## Next step

**TWO-PHASE AUDIT DUE FIRST.** This is the 2nd code slice since the last two-phase audit (item 7 = 1,
this = 2; the RE-DIAGNOSIS spike landed no code). Run BOTH phases sequentially per
[`docs/guides/slice-loop.md`](../guides/slice-loop.md) (the procedure is written THERE — do NOT invoke
`/ace-audit`): (A) code-quality over this batch — the new `defFrameRefIndices`/`embedComprehension-
ReadLabels`/`spliceOperandForEmbed` helpers (correctness, totality, illegal-states, test strength,
skill compliance), then (B) architecture/refactor/cleanup over the whole module graph. Fold findings
into the plan as fix-slices.

**THEN: Bug #2 — the argocd unblock. DESIGN NOW IMPLEMENTABLE** (Phase-B spike `0d4b1a0`, in
`plan.md` "Bug #2 design (implementable)"). The spike DECOMPOSED Bug #2 into **two independent
gaps** (the single-blob framing was imprecise), each grounded on a minimal oracle-checked repro
(`/tmp/bug2/shape{A,B,D}.cue` + `probe_*`):
- **Gap-1 — let-buried read detection** (fixes shapeA/B wrong-output): `embedComprehensionReadLabels`
  / `defFrameRefIndices` must FOLLOW a `letBinding` `.refId` into its value to discover the regular
  sibling (`kind`) a let-buried comprehension reads. Purely additive detection; `probe_hidden` proves
  the splice already propagates correctly once the label is found. SOUNDNESS: GO (only widens the
  spliced-label set, same op as Bug #1). **Slice Bug2-1; A-EN1 rides along** (same detection gap, the
  `for`-source variant).
- **Gap-2 — force-tier disjunction-arm narrowing** (fixes shapeD bottom): an embedded def's
  disjunction arms don't get the outer narrowing when the def is itself embedded one layer down.
  Distribute spliced operands into each arm + prune dead arms in the force path, mirroring the
  `meetEmbeddingsWithFuel` distribution that works one tier up. SOUNDNESS: GO-WITH-GATE (the
  regression-prone disjunction-arm family; byte-identical cert-manager gate MANDATORY; STOP-and-report
  if it can't be gated off cert-manager's bytes). **Slice Bug2-2**, then RE-MEASURE `kue export
  apps/argocd.cue` (88.85s bottom → expect non-bottom export; residual is the item-7 perf wall).

RECOMMENDED LEVER: extend the splice/force machinery, NOT a deferred-evaluation rewrite (proven
unnecessary by `probe_hidden`). 2 slices, SPLIT (Gap-1 low-risk first, Gap-2 gated second).

Behind Bug #2: item 7 (frame-id canonical identity, the PERF wall), then B6-deferred sub-gap +
field-order #3 + the LOW items.

## Standing rules

- prod9 + cue caches READ-ONLY (eval/probe only). NO `git checkout`/`restore`/`reset --hard`. No env
  mutation outside the project tree.
