# RESUME — Value-rewrite catch-alls now EXHAUSTIVE; NEXT = the LATENT / CLEANUP tail

(2026-06-23) Live START-HERE; supersedes
`2026-06-23-resume-aliased-audit-closed-latent-tail-next.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md). Spec-conformance backlog:
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Genuinely-open.
Per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md). Failure modes:
[`../reference/failure-modes.md`](../reference/failure-modes.md). Served status page:
[`../../www/index.html`](../../www/index.html).

## Just landed — Value-rewrite catch-alls made exhaustive (type-safety hardening)

The Phase-B `| other => other` finding is RESOLVED. All four Value-rewrite catch-alls now
enumerate their constructors explicitly, so a future recursive `Value` ctor is a compile
error (recurse-or-leaf forced) instead of a silent pass-through:

- `canonicalizeBuiltinCalls` (`Parse.lean`) — true structural rewrite → enumerated the 11
  leaves.
- `collapseDefaultDisjunction` (`EvalOps.lean`), `openStructValue` + `closeEmbeddedOver`
  (`Eval.lean`) — shallow projections → enumerated ALL pass-through ctors (+ an explicit
  `.struct _ _ _ _ _` arm on the two `Eval` sites for the non-plain-struct shapes the narrow
  first arm misses).

Byte-identical: suite 1697 `native_decide` pins conserved, cert-manager + argocd jq-S = 0.
Exhaustiveness VERIFIED to bite — a scratch dummy recursive ctor errored at all four sites
(`Parse.lean:1638`, `EvalOps.lean:170`, `Eval.lean:1820`, `Eval.lean:2230`), then reverted
(not committed). OUT of scope (recorded): the two eval-dispatch fuel terminals
(`evalValueCoreWithFuel`, `evalStructRefsM`) — the eval fixpoint's no-rule fallback, already
guarded by the synced `valueReducesToSelf` leaf helper, not a structural rewrite.

Detail in `implementation-log.md` § "Value-rewrite catch-alls made exhaustive".

## Audit counter = 1

This slice opened a fresh round (counter was reset to 0 by the prior aliased-audit close).
One more substantive slice → two-phase audit per
[`../guides/slice-loop.md`](../guides/slice-loop.md) (A code-quality, then B
architecture/cleanup).

## State — substantive backlog EXHAUSTED; only LATENT / CLEANUP remains

Spec-conformance backlog EMPTY (argocd + cert-manager content-identical drop-ins, jq -S
diff = 0); per-eval perf frontier CLOSED. Latest release `v0.1.0-alpha.20260623`.

## 🚨 NEXT LEADER — the remaining LATENT / CLEANUP tail (all latent/cleanup)

Resolve by philosophy (precise/total/illegal-states-unrepresentable), don't ask:

- **item-6 LATENT tail** — `module-file-scoped-imports` (arch-sized; prod9 misses it);
  B2-A1 (latent `tail`-drop, pairs with typed-ellipsis) / B2-A2 (test-gap fill);
  `resolveEmbeddedDisjDefault` check (`Eval.lean:2093`); DRY `selectEvaluatedField .disj`.
- **SC-3** — the multi-arm-default display-gap (cosmetic Format-layer projection).

Pick the next by philosophy, drive the loop.

## Verify on resume

`git status` clean, `HEAD == @{u}`, `lake build` green, `scripts/check-fixtures.sh` green.
Canaries (from `/Users/chakrit/Documents/prod9/infra`) jq-S=0 if a slice touched eval.

## Release

`v0.1.0-alpha.20260623` is the latest cut. This slice is a byte-identical refactor (no
behavior change), so it adds NO new release obligation — ride the next auto-due daily cut
(attended) via `scripts/release.sh` (+ `scripts/release-linux.sh`) when one is owed.

## Live state end
