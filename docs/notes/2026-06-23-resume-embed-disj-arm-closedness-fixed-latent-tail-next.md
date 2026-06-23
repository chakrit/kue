# RESUME — `resolveEmbeddedDisjDefault` question CLOSED (CASE B fixed); NEXT = LATENT / CLEANUP tail

(2026-06-23) Live START-HERE; supersedes
`2026-06-23-resume-catchalls-exhaustive-latent-tail-next.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md). Spec-conformance backlog:
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Genuinely-open.
Per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md). Failure modes:
[`../reference/failure-modes.md`](../reference/failure-modes.md). Served status page:
[`../../www/index.html`](../../www/index.html).

## Just landed — `embed-disj-arm-closedness` (item-6 open question RESOLVED, CASE B)

The plan's `resolveEmbeddedDisjDefault` open question is CLOSED — **CASE B, a real divergence,
fixed**. The label-surfacing call (`evalEmbeddingFieldsWithFuel`, `Eval.lean:~3757`) only feeds the
closedness union + Pass-2 frame; the VALUE is the `.disj` distribution arm of
`meetEmbeddingsWithFuel` (`~3858`). Probing THAT arm under a use-site narrowing found the bug: it
OPENED each arm (`openStructValue`) into the residual `.disj`, so a later narrowing of a label
DISJOINT from a CLOSED default arm was wrongly admitted (closed default won with a leaked label)
where cue rejects it by closedness and falls through to the survivor —
`{(*_#A{n} | _#B{s})} & {s:"x"}` → cue `{s:"x"}`, kue pre-fix `{n,s:"x"}` / `incomplete int`.

Fix: per-arm re-close via `closeEmbeddedOver hostFields armFields armOpen armResult` (the analog of
the top-level close at `~3539`) — widens by host labels yet restores each arm's own closedness
against the later narrowing. The DIRECT (non-embedded) path already got this. 4 new
`embed_disj_arm_closedness_*` pins + a `#check` sentinel. Disjunction-defaults capability +
equal-default dedup + mark-precedence + AD2-1 + the 4 V2 `embed-disj-*` pins all held. Canaries
jq-S=0. Detail in `implementation-log.md` § "`resolveEmbeddedDisjDefault` soundness check".

## 🚨 NEW LATENT finding (surfaced this slice, NOT fixed — pre-existing)

**Nested embedded disjunction-of-disjunction loses the default MARK.** `{(*_#Outer1 | {c:1})} &
narrow` where `_#Outer1` is itself `*_#Inner | …` and `narrow` kills the inner default `_#Inner`:
kue exports `ambiguous value: multiple non-default disjuncts remain` where cue picks the marked
survivor (e.g. `{b:"x"}`). Confirmed PRE-EXISTING (HEAD worktree diverges too, differently —
`incomplete value: int`). Distinct mechanism — a `flattenAlternatives`/`normalizeDisj`
mark-inheritance gap, NOT closedness. My fix is strictly not-worse. Repro:
`_#Inner:{a:int}` · `_#Outer1:{(*_#Inner | {b:string})}` · `out:{(*_#Outer1 | {c:1})} & {b:"x"}`.

## Audit counter = 2 → TWO-PHASE AUDIT DUE AFTER THE NEXT SLICE

Counter was 1; this is slice 2 of the round. The NEXT substantive slice triggers the two-phase
audit per [`../guides/slice-loop.md`](../guides/slice-loop.md): **(A) code-quality** then
**(B) architecture/refactor/cleanup**. Do NOT invoke `/ace-audit` — follow the guide procedure.

## State — substantive backlog EXHAUSTED; only LATENT / CLEANUP remains

Spec-conformance backlog EMPTY (argocd + cert-manager content-identical drop-ins, jq -S diff = 0);
per-eval perf frontier CLOSED. Latest release `v0.1.0-alpha.20260623`.

## 🚨 NEXT LEADER — the remaining LATENT / CLEANUP tail

Resolve by philosophy (precise/total/illegal-states-unrepresentable), don't ask:

- **NEW nested-disj-mark latent** (above) — `flattenAlternatives`/`normalizeDisj` default-mark
  inheritance when an inner default sub-arm dies. Soundness-adjacent (wrong export on a real shape),
  a strong next-leader candidate.
- **item-6 LATENT tail** — `module-file-scoped-imports` (arch-sized; prod9 misses it); B2-A1
  (latent `tail`-drop, pairs with typed-ellipsis) / B2-A2 (test-gap fill); DRY
  `selectEvaluatedField .disj`.
- **SC-3** — the multi-arm-default display-gap (cosmetic Format-layer projection).

Pick the next by philosophy, drive the loop. (`resolveEmbeddedDisjDefault` is now struck from the
tail — RESOLVED.)

## Verify on resume

`git status` clean, `HEAD == @{u}`, `lake build` green, `scripts/check-fixtures.sh` green.
Canaries (from `/Users/chakrit/Documents/prod9/infra`) jq-S=0 if a slice touched eval.

## Release

`v0.1.0-alpha.20260623` is the latest cut. This slice is a soundness FIX (behavior change on the
embedded-default-disjunction × closedness × use-site-narrowing path); it adds a release obligation —
ride the next auto-due daily cut (attended) via `scripts/release.sh` (+ `scripts/release-linux.sh`).

## Live state end
