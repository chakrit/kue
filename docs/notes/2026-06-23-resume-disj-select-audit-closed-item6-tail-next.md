# RESUME — disj-select DRY audit CLOSED (HEALTHY); NEXT = item-6 LATENT tail / SC-3

(2026-06-23) Live START-HERE; supersedes
`2026-06-23-resume-disj-select-dry-collapsed-item6-tail-next.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md). Spec-conformance backlog:
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Genuinely-open.
Per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md). Failure modes:
[`../reference/failure-modes.md`](../reference/failure-modes.md). Served status page:
[`../../www/index.html`](../../www/index.html).

## Just closed — Phase-A SCOPED audit of the disj-select DRY collapse: HEALTHY

Audited batch `db8700f..HEAD` (nested-disj-mark designed-deferral `86538ba` + disj-select DRY
collapse `cdf2f39`). The DRY collapse is the only code change and is behavior-sensitive; fully
re-oracled vs cue v0.16.1 + diffed against a `db8700f` before-binary worktree. Findings:

- **Carrier defaults BYTE-IDENTICAL** (before-binary export diff = 0). `selectFromConcrete`
  dispatches exactly as the old inline 5-arm: struct / list-valued-field / select-other-arm all pre
  = post = cue.
- **Scalar-default-select fix CORRECT == cue** across int / bool / null / list / ref-resolved-scalar
  defaults — the dead arm sheds (`x: *5|{a:1}; y: x.a | "fb"` → `"fb"`), where OLD went AMBIGUOUS (a
  kue bug). Bare select bottoms (cue type-errors); kue's message (`conflicting values (bottom)`)
  differs from cue's (`invalid operand …`) — a message-only divergence, NOT a value divergence (the
  spec verdict "field-select off a scalar is an error" is what's gated, not byte-identical messages).
- **`_ => .bottom` catch-all NEVER over-bottoms.** Probed: an INCOMPLETE default (`*int`, `*(>5)`)
  makes the WHOLE `x` field incomplete and never reaches a resolved-default select (cue/old/new all
  `incomplete value`), so only concrete scalar/carrier values reach `selectFromConcrete` via a
  resolved default — exactly where pluck-or-bottom is right.
- **Deep-nested `.disj`-default DEFERS unchanged** (`some (.disj _) => .selector`); ambiguous-`none`
  unchanged; both byte-identical pre/post.
- **Deferred-mark tripwires UNFLIPPED** — the 5 `nested_disj_mark_*` pins are a MEET-time Mark issue,
  orthogonal to selection; `cdf2f39` touches zero pin lines, `86538ba` is code-free (test + docs).
- **TOTALITY clean** — `selectFromConcrete` non-recursive (trivially terminating), no new
  `partial`/`sorry`/axiom, no `_`-swallow hiding a reachable case. DRY genuine (carrier dispatch in
  ONE place now).

**Inline fix landed (`593fa58`):** +6 adversarial coverage pins (bool/null/list/ref-scalar shed +
direct `selectEvaluatedField … == .bottom` dispatch + `#check` sentinel) — the prior batch pinned
only the int-literal shed. **ONE docs nuance (not a regression):** `86538ba`'s STEP-0 claims inline
`*( … )` is a cue parse error, but cue v0.16.1 accepts `*(*{a:1}|{a:2})|{a:9}` → `{a:1}` — a
basis-prose imprecision in the nested-disj-mark adjudication; the deferral itself is correctly
pinned. Left as-is (record-only; folding it would risk re-opening a settled deferral over a cosmetic
prose fix). Verdict: **HEALTHY.**

## Audit counter = 0 (RESET — round closed)

This Phase-A SCOPED single pass CLOSES the round; per the slice-loop guide the counter resets to 0.
Next two-phase audit re-triggers at 2–3 landed code-quality slices. Do NOT invoke `/ace-audit` —
follow [`../guides/slice-loop.md`](../guides/slice-loop.md).

## State — substantive backlog EXHAUSTED; only LATENT / CLEANUP + one DEFERRED divergence

Spec-conformance backlog: the lone open VALUE divergence is NESTED-DISJ-MARK (DESIGNED-DEFERRED — a
MEET-time Mark-type problem). Everything else is LATENT/CLEANUP or display-only (SC-3). argocd +
cert-manager content-identical drop-ins (jq -S diff = 0, re-confirmed direct from `prod9/infra` this
round); per-eval perf frontier CLOSED.

## 🚨 NEXT LEADER — item-6 LATENT tail, then SC-3

Resolve by philosophy (precise / total / illegal-states-unrepresentable), don't ask. **All are
ZERO-observable-value (prod9 doesn't hit them; lossless/cosmetic today)** — so the leading question is
defer-vs-execute, not how-to-fix:

- **`module-file-scoped-imports`** (ARCH-SIZED) — 🚩 **DEFER-VS-EXECUTE FLAG.** An autonomous risky
  refactor of WORKING, RELEASED import machinery for an UNOBSERVABLE gain (prod9 never hits it) may
  warrant DEFERRAL over execution. Weigh the regression surface (released import resolution) against
  the zero user-facing benefit before committing to the refactor — record the choice in the plan.
- **B2-A1 / B2-A2** — defensive / test-gap (latent `tail`-drop pairing with typed-ellipsis; test-gap
  fill). Lossless today.
- **SC-3** — multi-arm-default display-gap (cosmetic Format-layer projection; the residual
  `*{…} | {…}` in `eval` is this gap — export is identical).
- **NESTED-DISJ-MARK** — DEFERRED; revisit only as a designed standalone (3rd `Mark` state or
  non-flattening nested-disj invariant) when a real config needs tier-2, NOT as a quick next slice.
  The disj-select DRY's deferred recursion gain (a WF `termination_by` on `selectEvaluatedField`) is
  a separate, smaller deferral — pick up only alongside a slice that needs doubly-nested-default
  recursion from real source (none does yet).

Pick the next by philosophy, drive the loop.

## Verify on resume

`git status` clean, `HEAD == @{u}`, `lake build` green (112 jobs), `scripts/check-fixtures.sh` green.
Canaries (from `/Users/chakrit/Documents/prod9/infra`) jq-S=0 — re-run green this round (cert-manager
1448 B, argocd 51178 B, both diff = 0).

## Release

`v0.1.0-alpha.20260623` is the latest cut. A FRESH alpha is OWED: the scalar-default-select fix
(`cdf2f39`) + the prior embed-disj-arm-closedness change are user-observable behavior changes not yet
in a tagged release. Auto-cut the next due daily alpha (attended) via `scripts/release.sh`
(+ `scripts/release-linux.sh` for the Linux assets). Both behavior changes are absent from the canary
corpora, so the drop-in parity is unaffected.

## Live state end
