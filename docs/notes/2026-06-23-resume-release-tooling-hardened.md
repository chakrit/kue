# RESUME — release tooling hardened (race-safe tap push + dirty guard) (2026-06-23)

Live START-HERE; supersedes `2026-06-23-resume-parser-strictness-done.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md). Spec-conformance backlog:
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Genuinely-open.
Per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md).
Served status page: [`../../www/index.html`](../../www/index.html).

## Just landed — release-tooling hardening (plan item-6 LOW ×2; infra/shell, NOT Lean)

Two audit LOWs, now relevant because releases AUTO-CUT (working agreement amended to
auto-release → `release.sh` and `release-linux.sh` may run concurrently against the SAME
tap clone):

- **Race-safe tap push (no lock).** New shared `scripts/tap-push.sh` (sourced by BOTH
  release scripts, DRY alongside `patch-formula-block.sh`) exposes `tap_push <tap_dir>
  <msg> <repatch_fn>`. Replaces each script's `pull --ff-only` + `commit` + `push` with a
  lock-FREE retry loop: resolve remote from the branch upstream (tap remote is `gh`, NOT
  `origin` — never assume); `fetch` + `reset --hard <remote>/<branch>` (clean base at the
  remote tip, includes the sibling's block) → re-apply OUR patch via callback →
  commit-if-changed → push → on REJECT loop up to `TAP_PUSH_RETRIES` (5) with
  `TAP_PUSH_BACKOFF` (2s), then `die`. `flock` DELIBERATELY AVOIDED — absent on the macOS
  release host (would silently no-op). The callback (`repatch_macos`/`repatch_linux`)
  re-runs each script's own `patch_formula_*` — idempotent (patcher keys on the
  asset-suffixed url, invariant across version bumps → re-patch hits the SAME block) +
  block-scoped (touches ONLY that asset's block → sibling block preserved).
- **`release-linux.sh` dirty-tree guard.** Added the same
  `[ -z "$(git -C "$REPO_ROOT" status --porcelain)" ] || die …` precondition `release.sh`
  has, before the Docker build — so the Linux asset (`COPY . /src`) is built from a
  committed tree matching the macOS asset.

`patch-formula-block.sh` UNCHANGED (verified idempotent for realistic asset-suffixed urls
+ block-scoped by direct test). `reset --hard` is scoped to the TAP clone, discarding only
the script's own regenerable patch — never the kue working tree.

## Verify

`shellcheck` 0.11.0 CLEAN on all four scripts (release.sh, release-linux.sh,
patch-formula-block.sh, tap-push.sh). Concurrency DRY-RUN done: throwaway bare remote +
two clones running `repatch_macos`/`repatch_linux` TRULY concurrently — 12-round stress +
a `gh`-named-remote round, EVERY round landed both the macOS block + both Linux blocks +
the version bump with ZERO lost updates; the race loser observed a real push reject,
re-fetched the winner, re-patched, pushed. Retry-exhaustion path → clean `die` after N. NO
Lean
change: `lake build` clean (112 jobs), `check-fixtures.sh` ZERO drift. Published
`v0.1.0-alpha.20260623` release/assets/formula NOT touched — change affects only FUTURE
runs.

## State — audit counter = 2. Two-phase audit DUE after the next slice.

Spec-conformance backlog still EMPTY (every correctness item RESOLVED; argocd +
cert-manager content-identical drop-ins, jq -S = 0). This slice was infra/shell (release
tooling), no semantics touched, module graph unchanged.

## NEXT — pick the next leader (resolve by philosophy; none soundness-bearing)

Ranked candidates (item-6 LOW tail keeps shrinking — two release-script LOWs now CLOSED):

1. **item-6 LOW tail** in `plan.md` — remaining: A2-x/y (importBinding merge-asymmetry +
   import-name redeclaration check), B2-A1/A2 (typed-ellipsis `tail` thread + test-gap
   fill), `module-file-scoped-imports` (arch-sized per-file import scoping), the
   `resolveEmbeddedDisjDefault` distribution check, DRY `selectEvaluatedField .disj`. None
   soundness-bearing.
2. **per-eval-CONSTANT perf frontier** (argocd ~50s residual). Big levers EXHAUSTED
   (frame-sharing WON'T-FIX ~0.05% ceiling, safe-wins + flatten-bound SHIPPED); a deeper
   hot-path micro-opt is incremental/hard — flag diminishing returns honestly.
3. **SC-3** display-gap (multi-arm-default display-collapse — cosmetic Format-layer
   projection; close only if the eval-display convention is revisited).

## Release

`v0.1.0-alpha.20260623` CUT; Homebrew formula live-correct on all 3 platforms. (This
release-tooling slice + the prior parser-strictness slice are candidates to ride the next
datestamped alpha — the tap-push hardening only affects FUTURE cuts.)

## Audit

Counter = **2** (parser-strictness + this release-tooling slice). **Two-phase audit DUE
after the next slice**, per [`../guides/slice-loop.md`](../guides/slice-loop.md): (A)
code-quality, then (B) architecture/refactor/cleanup over the batch.

## Live state end
