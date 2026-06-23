# RESUME — multi-ref-cyclic flatten fan-out BOUNDED; audit counter = 1 (2026-06-23)

Live START-HERE; supersedes `2026-06-23-resume-audit-closed-perf-frontier.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md). Spec-conformance backlog:
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Genuinely-open.
Per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md).
Served status page: [`../../www/index.html`](../../www/index.html).

## State — audit counter = 1. Last slice: PERF flatten-fan-out bound (SHIPPED).

**Multi-ref-cyclic flatten fan-out FIXED.** A closed cycle whose head conjoins ≥2
back-referencing defs (`#A: #B & #C & {a}`, `#B: #A & {b}`, `#C: #A & {c}`) was CORRECT
after Bug2-12-mutual but TIMED OUT (>40s). `flattenConjDefRef` now threads an `expanding`
visited-path set: a depth-0 ref to a slot already on the current expansion path is
returned UNEXPANDED, so each cycle member's literals are collected ONCE instead of along
the cross-product of reference paths. **Before→after: the 3-line repro >40s (killed) →
~0.01s warm / ~0.55s cold.**

- **Sound by construction:** the bare `.refId` returned for an already-visited slot is
  EXACTLY the leaf the unbounded recursion bottoms to at fuel exhaustion;
  `mergeDefinitionDecls` unions a member's literal idempotently and the re-entrant
  `.refId`s in `rest` `.conj`-meet idempotently under D#2 — so the literal UNION and `rest`
  set are the same finite sets, value byte-identical. Only the multi-HOP-chain field ORDER
  canonicalizes
  (`a,c,b` → reverse-declaration `c,b,a`, an unordered-map detail; `cue` over-rejects so it
  is no oracle). Argument in the implementation-log.
- **Gate GREEN:** `lake build` clean (no warning/`sorry`/axiom), `check-fixtures.sh` ZERO
  drift. Canaries from `prod9/infra`: cert-manager jq -S = 0 (~12.4s), argocd jq -S = 0
  (~54s) — UNCHANGED (the bound fires only on closed multi-ref cycle re-entry, untouched by
  the real apps).
- **6 new fast `native_decide` pins** (`### Multi-ref cyclic flatten-fan-out BOUND` in
  `Bug2xTests.lean`): 2/3/4-way + reject + open-tail + split-literal + dup-back-ref — the
  multi-ref cases that PREVIOUSLY could not be pinned (timed out).
  `bug212_mutual_threeway_admits` re-baked for the canonicalized field order (value
  unchanged).

The multi-ref-cyclic limitation is REMOVED from `kue-performance.md` § Known limitations
and recorded under § What the engine already handles for you (Multi-ref CYCLIC def flatten
is bounded). `plan.md` perf item #5 updated (fan-out FIXED).

## NEXT — pick the next leader (resolve by philosophy; none soundness-bearing)

Spec-conformance-HIGH fully DONE. The whole Bug2-12 family (self-rec + 2-12b + MUTUAL)
RESOLVED. perf-#7 frame-sharing WON'T-FIX (~0.05% ceiling). The flatten fan-out is now
BOUNDED. Ranked candidates:

1. **per-eval-CONSTANT perf frontier** (the live lever) — lower the per-eval CONSTANT /
   eval COUNT over the genuinely-large DISTINCT population on the real apps (cert-manager
   ~12.4s, argocd ~54s; argocd's ~50s is the residual, NOT the fan-out — that is fixed — and
   NOT cross-env sharing, which is closed). Profile the SETUP/import closure + the
   `.struct`/`.refId`/`.conj` re-eval under divergent frames. Detail: `kue-performance.md`
   § Known limitations (Absolute per-eval cost on deep apps).
2. **SC-4** (LOW, spec-gap-first — nested hidden/let closedness on direct def-meet; cue
   internally inconsistent, spec-check FIRST, do not reflexively match cue).
3. **item-6 LOW tail** in `plan.md` (parser strictness `*(1|2)`/`__x`, A2-x/y, B2,
   `module-file-scoped-imports`, the concurrent-release tap-clone race — none
   soundness-bearing).

**Audit:** counter = 1. Two-phase audit due at 2–3 (per `docs/guides/slice-loop.md`); not
yet due.

## Live state end
