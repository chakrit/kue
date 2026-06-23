# RESUME — A2-y import-name redeclaration DONE; NEXT = the LATENT / CLEANUP tail (2026-06-23)

Live START-HERE; supersedes `2026-06-23-resume-resilience-pass-closed-latent-tail-next.md`
(deleted). Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md). Spec-conformance
backlog: [`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) §
Genuinely-open. Per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md). Failure modes:
[`../reference/failure-modes.md`](../reference/failure-modes.md). Served status page:
[`../../www/index.html`](../../www/index.html).

## Just landed — A2-y (import-name redeclaration check)

A top-level bare-identifier field reusing an import's bound local name (`import ".../dep"` +
`dep: {…}`) is now a LOAD error — `<name> redeclared as imported package name`, matching
cue's verdict + first message line. **Spec-mandated** (file-block "No identifier may be
declared twice in the same block"), so Kue conforms, not just matches the binary. Pre-fix
was a genuine SOUNDNESS bug (Kue silently kept both AND resolved `out: dep` to the imported
package, not the user's field).

- **Where:** `Module.lean` — `checkImportRedeclaration` over each file's
  `topLevelFieldNames`, threaded through `collectBindings` + the builtin-only fast path;
  `Parse.lean` records quoted-vs-bare on `ParsedField.field` so `bareIdentifierLabels`
  collects exactly the collision-eligible labels; `topLevelFieldNames` on `ParsedFile`.
- **Boundary (oracle-pinned):** collides = bare/`?`/`!` field == bound name (alias name,
  qualifier name, builtin bind name all count); exempt = quoted `"dep"`, `#dep`/`_dep`
  (distinct namespaces), nested, different-name, alias/qualifier mismatch. Aliased-field
  corner (`x=dep`) deliberately exempted (cue's verdict unobservable there — no-over-reject).
- **Verify:** `lake build` 112 jobs clean; fixtures zero-drift (+2 module fixtures); canaries
  jq-S=0 (cert-manager ~11.7s, argocd ~50.8s — UNAFFECTED, prod9 never hits the collision).
  +13 ModuleTests pins. 1 cue-divergence (1-line vs 2-line diagnostic) + 1 spec-gap (exemption
  boundary). Commit on `main`, pushed `main -> main`.
- **A2-x consequence:** STAYS unobservable — its `importBinding & real-field` merge is only
  reachable via the collision A2-y now rejects at load. No work to do.

**Audit counter = 2.** (Was 1 after the resilience pass; this is the next code slice.)
**🚨 Two-phase audit is DUE after the NEXT slice** (the 2–3-slice mark) — sequential
code-quality then architecture, per [`../guides/slice-loop.md`](../guides/slice-loop.md).

## State — substantive backlog EXHAUSTED; only LATENT / CLEANUP remains

Unchanged otherwise: spec-conformance backlog EMPTY (argocd + cert-manager content-identical
drop-ins, jq -S diff = 0); per-eval perf frontier CLOSED (floor-characterized; cross-env
frame-sharing WON'T-FIX). Latest release `v0.1.0-alpha.20260623` (3 platforms, formula live).

## 🚨 NEXT LEADER — the remaining LATENT / CLEANUP tail (none soundness-bearing)

Resolve by philosophy (precise/total/illegal-states-unrepresentable), don't ask:

- **item-6 LATENT tail** (A2-y now DONE) — `module-file-scoped-imports` (arch-sized; prod9
  doesn't hit it); B2-A1 (latent `tail`-drop, pairs with typed-ellipsis) / B2-A2 (test-gap
  fill); `resolveEmbeddedDisjDefault` check; DRY `selectEvaluatedField .disj`.
- **SC-3** — the multi-arm-default display-gap.

All latent/cleanup. Pick the next by philosophy, drive the loop, **then the two-phase audit
(DUE)**.

## Verify on resume

`git status` clean, `HEAD == @{u}`, `lake build` green, `scripts/check-fixtures.sh` green.
Canaries (from `/Users/chakrit/Documents/prod9/infra`) jq-S=0 if a code slice touched eval.

## Release

`v0.1.0-alpha.20260623` is the latest cut. A2-y is a small loader-strictness fix; ride the
next datestamped alpha (a fresh cut is auto-due ~1/day, attended).

## Live state end
