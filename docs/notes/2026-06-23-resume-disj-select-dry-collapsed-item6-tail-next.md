# RESUME — disj-select DRY COLLAPSED (item-6); audit DUE; NEXT = item-6 LATENT tail / SC-3

(2026-06-23) Live START-HERE; supersedes
`2026-06-23-resume-nested-disj-mark-deferred-item6-tail-next.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md). Spec-conformance backlog:
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Genuinely-open.
Per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md). Failure modes:
[`../reference/failure-modes.md`](../reference/failure-modes.md). Served status page:
[`../../www/index.html`](../../www/index.html).

## Just landed — DRY collapse of `selectEvaluatedField`'s `.disj` arm

Item-6 DRY struck. The resolved-default carrier dispatch
(`.struct`/`.embeddedList`/`.embeddedScalar` → `selectFromDecls`), formerly re-listed inside the
`.disj` sub-case, is EXTRACTED to a shared non-recursive `selectFromConcrete (base label)` — called
at top-level AND once `resolveDisjDefault?` resolves a default. NOT a pure refactor; full behavior
determination in the implementation-log entry. Three outcomes:

- **Carrier + ambiguous-`none` + doubly-nested-`.disj`-default deferral: BYTE-IDENTICAL.** The
  "free nested-disjunction recursion" the plan flagged was DESIGNED-DEFERRED (an explicit
  `some (.disj _) => .selector`): recursing would gain cue's value but needs a well-founded
  `termination_by` through `liveAlternatives`/`flatten`/`dedup` — LARGE machinery for a shape
  eval-time flatten makes UNREACHABLE from source. Not worth it.
- **Field-select off a SCALAR default: kue bug FIXED == cue** (a gain, NOT a divergence). The old
  `_` arm deferred `x.a` (x = `*5|{a:1}`) to a wrong `.selector` ("incomplete"); `selectFromConcrete`
  `.bottom`s it (cue type-errors), so `y: x.a | "fb"` sheds the dead arm → `"fb"` (was kue-AMBIGUOUS).
  No `cue-divergences.md` entry (kue was wrong, now conforms).

Pinned both ways (4 new `TwoPassTests` pins + `#check` sentinel). The 2 `nested_disj_mark_*_DEFERRAL`
tripwires are MEET-time Mark issues — ORTHOGONAL to selection, unflipped.

## 🚨 Audit counter = 2 → TWO-PHASE AUDIT DUE after the NEXT slice

Prior counter was 1 (the NESTED-DISJ-MARK designed-deferral). This slice is a real code-quality-bearing
change (+1) → **counter = 2**. Per the normal 2–3 cadence
([`../guides/slice-loop.md`](../guides/slice-loop.md)), run the **two-phase audit** (A code-quality,
then B architecture/refactor) AFTER the next landed slice — do NOT invoke `/ace-audit`, follow the
guide. Batch to audit: NESTED-DISJ-MARK adjudication + this DRY collapse + whatever next lands.

## State — substantive backlog EXHAUSTED; only LATENT / CLEANUP + one DEFERRED divergence

Spec-conformance backlog: the lone open VALUE divergence is NESTED-DISJ-MARK (DESIGNED-DEFERRED — a
MEET-time Mark-type problem). Everything else is LATENT/CLEANUP or display-only (SC-3). argocd +
cert-manager content-identical drop-ins (jq -S diff = 0); per-eval perf frontier CLOSED. Latest
release `v0.1.0-alpha.20260623`.

## 🚨 NEXT LEADER — item-6 LATENT tail, then SC-3

Resolve by philosophy (precise/total/illegal-states-unrepresentable), don't ask:

- **item-6 LATENT tail** — `module-file-scoped-imports` (arch-sized; prod9 misses it); B2-A1 (latent
  `tail`-drop, pairs with typed-ellipsis) / B2-A2 (test-gap fill). The DRY `selectEvaluatedField .disj`
  item is now DONE.
- **SC-3** — multi-arm-default display-gap (cosmetic Format-layer projection; the residual `*{…} |
  {…}` shown in `eval` is this gap — export is identical).
- **NESTED-DISJ-MARK** — DEFERRED; revisit only as a designed standalone (3rd `Mark` state or
  non-flattening nested-disj invariant) when a real config needs tier-2, NOT as a quick next slice.
  The disj-select DRY's deferred recursion gain is a SEPARATE, smaller deferral (a WF `termination_by`
  on `selectEvaluatedField`) — pick it up only alongside a slice that needs the doubly-nested-default
  recursion from real source (none does yet).

Pick the next by philosophy, drive the loop. **Audit is DUE after it.**

## Verify on resume

`git status` clean, `HEAD == @{u}`, `lake build` green, `scripts/check-fixtures.sh` green.
Canaries (from `/Users/chakrit/Documents/prod9/infra`) jq-S=0 — this slice touched eval (selection
dispatch) and re-ran them green (both 0).

## Release

`v0.1.0-alpha.20260623` is the latest cut. This slice's only USER-OBSERVABLE behavior change is the
field-select-off-scalar-default fix (a kue-bug→cue-conformance), absent from the canary corpora. The
prior embed-disj-arm-closedness BEHAVIOR change + this fix owe the next auto-due daily cut (attended)
via `scripts/release.sh` (+ `scripts/release-linux.sh`).

## Live state end
