# RESUME — Phase-A audit (aliased calls + constants) CLOSED; NEXT = the LATENT / CLEANUP tail

(2026-06-23) Live START-HERE; supersedes
`2026-06-23-resume-aliased-stdlib-const-resolved-latent-tail-next.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md). Spec-conformance backlog:
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Genuinely-open.
Per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md). Failure modes:
[`../reference/failure-modes.md`](../reference/failure-modes.md). Served status page:
[`../../www/index.html`](../../www/index.html).

## Just closed — Phase-A code-quality audit (batch `f4feb93..406556e`) → HEALTHY

The two aliased-resolution slices (`ebaafc4` calls, `406556e` constants) audited together as
a batch. Highest-risk axis (over/under-canonicalization = wrong value) attacked exhaustively,
every witness oracle'd vs cue v0.16.1 — all clean:

- **OVER:** a USER package whose import path's last element is literally a builtin name
  (`example.com/json` aliased as `f`; `f.Marshal` → the user field, NOT the builtin) resolves
  to the user package — `isBuiltinImport` keys on the full PATH, not the local name. A local
  field shadowing an alias with no import → field access (empty alias map, no-op). An import
  + same-named field → both kue/cue reject. Byte-identical to cue.
- **UNDER:** all families aliased, calls + consts; **binding-not-spelling** (`import json
  "strings"; json.ToUpper` → `strings.ToUpper`; inverse too) — maps by import PATH, spelling
  collision irrelevant. Byte-identical to cue.
- **Totality / DRY:** no new `partial`/`sorry`/axiom; the `other => other` catch-all sound
  (every swallowed ctor a true leaf) + matches the sibling idiom; one shared pass for
  calls+consts; `Value.lean` move de-dups the builtin-path list. No divergence/spec-gap.
- **Both canaries re-run DIRECTLY** (full whole-file export, not `-e`): cert-manager + argocd
  jq-S diff = 0. (The `-e` field-isolation was the only CLI quirk; whole-file export works.)
- **Coverage ADDED:** `regexp` family theorem, a binding-not-spelling dispatch theorem,
  `builtinImportLocalNames` cross-name unit cases, module fixture
  `testdata/modules/alias_user_pkg_builtin_name/` (the strongest OVER witness, oracle'd).

Detail in `implementation-log.md` § "Phase-A Audit: aliased-builtin calls + constants".

## Audit counter = 0 — round CLOSED

This Phase-A pass closes the round opened by the two aliased slices. Counter RESET to 0.
(Scoped single pass — architecture was reassessed healthy recently, so no separate Phase B
this round; the one codebase-wide finding below is filed into the Phase-B backlog.)

## State — substantive backlog EXHAUSTED; only LATENT / CLEANUP remains

Spec-conformance backlog EMPTY (argocd + cert-manager content-identical drop-ins, jq -S
diff = 0); per-eval perf frontier CLOSED. Latest release `v0.1.0-alpha.20260623`.

## 🚨 NEXT LEADER — the remaining LATENT / CLEANUP tail (all latent/cleanup)

Resolve by philosophy (precise/total/illegal-states-unrepresentable), don't ask:

- **item-6 LATENT tail** — `module-file-scoped-imports` (arch-sized; prod9 misses it);
  B2-A1 (latent `tail`-drop, pairs with typed-ellipsis) / B2-A2 (test-gap fill);
  `resolveEmbeddedDisjDefault` check (`Eval.lean:2093`); DRY `selectEvaluatedField .disj`.
- **`other => other` catch-alls (Phase-B, LOW, filed this audit)** — four Value-rewrite passes
  (`Parse.lean:1688`, `EvalOps.lean:171`, `Eval.lean:1821`/`2201`) end in `other => other`;
  sound today but silently bypass a future recursive `Value` ctor. Replace all four with
  explicit leaf arms together. See `plan.md`.
- **SC-3** — the multi-arm-default display-gap (cosmetic Format-layer projection).

Pick the next by philosophy, drive the loop.

## Verify on resume

`git status` clean, `HEAD == @{u}`, `lake build` green, `scripts/check-fixtures.sh` green.
Canaries (from `/Users/chakrit/Documents/prod9/infra`) jq-S=0 if a slice touched eval.

## Release

`v0.1.0-alpha.20260623` is the latest cut. The two aliased-resolution slices are real
behavior changes, so a fresh dated alpha is owed — ride the next auto-due daily cut
(attended) via `scripts/release.sh` (+ `scripts/release-linux.sh`). This audit added only
tests/fixtures (no behavior change), so it does not itself add a new release obligation.

## Live state end
