# RESUME — embed-disj-arm-closedness audit CLOSED (HEALTHY); NEXT = nested-disj-mark latent

(2026-06-23) Live START-HERE; supersedes
`2026-06-23-resume-embed-disj-arm-closedness-fixed-latent-tail-next.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md). Spec-conformance backlog:
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Genuinely-open.
Per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md). Failure modes:
[`../reference/failure-modes.md`](../reference/failure-modes.md). Served status page:
[`../../www/index.html`](../../www/index.html).

## Just CLOSED — single-pass audit, batch `20b8397..32ddfda` — HEALTHY

Scoped single pass over the type-safety catch-all refactor (`e8d6e85`) + the
embed-disj-arm-closedness soundness fix (`32ddfda`). Verdict **HEALTHY** (plan.md, verdict
cluster). The TOP risk — the per-arm re-close OVER-closing a legitimately-open arm — is
REFUTED, every witness oracle'd vs cue v0.16.1:

- **`...`-open-tail arm ADMITS** a disjoint narrow (`{(*_#A{n,...} | _#B{s})} & {extra:1}` →
  `{n,extra}`, not bottom) — `closeEmbeddedOver` is identity on a tail-bearing struct.
- **plain (non-def) open arm STAYS open** (`armOpen=true` ⇒ no closedness imposed).
- **host-extra survives WHILE the closed arm rejects** the disjoint narrow, on ONE shape.
- **mark-precedence / equal-default dedup / AD2-1 / `(*"a"|"b")&("b"|"c")→"b"`** unchanged.
- The 3 reported witnesses == cue post-fix. Catch-all refactor BYTE-IDENTICAL (3 projection
  sites enumerate all non-target ctors; `canonicalizeBuiltinCalls` enumerates the 11 true
  leaves; exhaustiveness compiler-proven). Both canaries jq-S=0 from infra (fresh binary).

**+3 over-close coverage pins ADDED inline** (the over-close direction was unpinned pre-audit):
`embed_disj_arm_closedness_open_tail_arm_admits_disjoint`,
`_plain_open_arm_admits_disjoint`, `_host_extra_survives_and_disjoint_rejected` + a `#check`
sentinel.

## NEW nested-disj-mark latent — CONFIRMED PRE-EXISTING (independently)

**Nested embedded disjunction-of-disjunction loses the default MARK.** `{(*_#Outer1 | {c:1})}
& narrow` where `_#Outer1` is itself `*_#Inner | …` and `narrow` kills the inner default
`_#Inner`: kue exports `ambiguous value: multiple non-default disjuncts remain` where cue picks
the marked survivor (`{b:"x"}`). Independently confirmed PRE-EXISTING by building parent
`e8d6e85` in a throwaway worktree — same witness diverges there too (`incomplete value: int`,
differently); the fix is strictly not-worse. Distinct mechanism — a
`flattenAlternatives`/`normalizeDisj` mark-inheritance gap, NOT closedness. Repro:
`_#Inner:{a:int}` · `_#B:{b:string}` · `_#Outer1:{(*_#Inner | _#B)}` ·
`out:{(*_#Outer1 | {c:1})} & {b:"x"}`.

## Audit counter = 0 (round CLOSED this pass)

The two-phase audit obligation is discharged by this single-pass code-quality audit (scope:
one soundness fix + one byte-identical refactor; architecture reassessed healthy recently).
Counter RESET to 0. Next two-phase audit triggers per the normal cadence
([`../guides/slice-loop.md`](../guides/slice-loop.md)) after the next 2–3 substantive slices.
Do NOT invoke `/ace-audit` — follow the guide procedure.

## State — substantive backlog EXHAUSTED; only LATENT / CLEANUP remains

Spec-conformance backlog EMPTY (argocd + cert-manager content-identical drop-ins, jq -S diff =
0); per-eval perf frontier CLOSED. Latest release `v0.1.0-alpha.20260623`.

## 🚨 NEXT LEADER — nested-disj-mark latent (strongest), then the CLEANUP tail

Resolve by philosophy (precise/total/illegal-states-unrepresentable), don't ask:

- **NEW nested-disj-mark latent** (above) — `flattenAlternatives`/`normalizeDisj` default-mark
  inheritance when an inner default sub-arm dies. A REAL divergence (wrong export on a real
  shape), soundness-adjacent — the **strongest** next-leader candidate.
- **item-6 LATENT tail** — `module-file-scoped-imports` (arch-sized; prod9 misses it); B2-A1
  (latent `tail`-drop, pairs with typed-ellipsis) / B2-A2 (test-gap fill); DRY
  `selectEvaluatedField .disj`.
- **SC-3** — the multi-arm-default display-gap (cosmetic Format-layer projection; the residual
  `*{…} | {…}` shown in `eval` on the plain-open-arm shape is this gap — export is identical).

Pick the next by philosophy, drive the loop.

## Verify on resume

`git status` clean, `HEAD == @{u}`, `lake build` green, `scripts/check-fixtures.sh` green.
Canaries (from `/Users/chakrit/Documents/prod9/infra`) jq-S=0 if a slice touched eval.

## Release

`v0.1.0-alpha.20260623` is the latest cut. The embed-disj-arm-closedness fix is a BEHAVIOR
change (embedded-default-disjunction × closedness × use-site-narrowing path) → a fresh alpha is
OWED; ride the next auto-due daily cut (attended) via `scripts/release.sh` (+
`scripts/release-linux.sh`).

## Live state end
