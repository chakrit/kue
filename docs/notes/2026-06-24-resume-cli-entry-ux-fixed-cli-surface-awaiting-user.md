# RESUME — CLI entry-UX FIXED (bare `kue` → help, no smoke); NEXT = user's CLI direction

(2026-06-24) Live START-HERE; supersedes
`2026-06-23-resume-disj-select-audit-closed-item6-tail-next.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md) (CLI/UX = item 7).
Spec-conformance backlog:
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Genuinely-open.
Per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md). Failure modes:
[`../reference/failure-modes.md`](../reference/failure-modes.md). Served status page:
[`../../www/index.html`](../../www/index.html).

## Just landed — CLI entry-UX fix (the fresh-install killers)

Two bugs made a `brew install`ed `kue` feel broken; both fixed:

- **Bare `kue` (no args) HUNG** — `parse [] => .eval [] => runEval []` read
  `IO.getStdin.readToEnd`, blocking forever on a TTY. Now `parse [] => .help none` →
  prints top-level help, exit 0 (cue/git/docker convention). Pinned
  (`CliTests.parse_empty`). The `kue <file…>` shorthand is unaffected (positional-args
  fallthrough → `.eval files`, not `parse []`).
- **`kue eval` empty stdin printed a smoke reel** — dev artifact. Branch removed; empty
  input now evaluates the empty struct → empty output, exit 0 (matches `cue eval -`).
- **Dead code removed** — `Kue/Examples.lean` (`smokeLines` + 14 `*SmokeResult` defs + the
  `smoke_lines_match_plan` theorem) was referenced ONLY by the deleted `printSmoke` hook;
  file + its `import` gone (build 112 → 110 jobs).
- **Harness** — moved the two bare `kue <file` redirect call-sites to explicit `kue eval
  <file`; eval-agreement check repointed to the file-arg shorthand; +2 regression
  assertions (bare `kue </dev/null` → `Commands:` listing exit 0; `kue eval </dev/null` →
  empty exit 0). Stale `Cli.lean` back-compat comments corrected. Help polished (column
  alignment + Examples block).

Verify done: `lake build` 110 jobs green (no warning/sorry/axiom), `check-fixtures.sh`
`fixture pairs ok`, `shellcheck` clean, canaries cert-manager + argocd jq-S=0. Detail in
`implementation-log.md` (CLI entry-UX slice).

## Audit counter = 1

One code-quality slice landed since the last audit (round closed at 0 the prior
breadcrumb). Counter now 1; the next two-phase audit re-triggers at 2–3 landed slices. Do
NOT invoke `/ace-audit` — follow [`../guides/slice-loop.md`](../guides/slice-loop.md).

## 🚨 NEXT LEADER — broader cue-aligned CLI surface (USER-SCOPED — do NOT self-start)

The entry-UX fix is the focused first cut. The larger objective — **a cue-aligned CLI
command surface** — is now a tracked-but-unstarted area (plan.md item 7) and is the user's
to scope:

- New subcommands (`vet`, `fmt`, `def`, …), a `-` explicit-stdin marker (`kue eval -`),
  flag parity with `cue`. **This is a DESIGN objective awaiting the user's direction** —
  do NOT autonomously expand the command set; it's a deliberately-deferred next leader,
  not a pick-by-philosophy slice.
- **DEFERRED footnote (not a blocker):** `kue --version` = `0.1.0-alpha` (datestamped per
  nightly) rather than the dated release tag — defensible as-is; revisit only if the
  version/build plumbing is reworked, not as a standalone.

If the user gives no CLI direction, the alternative live frontier is the prior tail —
**item-6 LATENT cleanups** (`module-file-scoped-imports` DEFER-VS-EXECUTE flag, B2-A1/A2,
SC-3 display-gap) — all zero-observable-value (prod9 doesn't hit them), so
defer-vs-execute is the question, not how-to-fix. NESTED-DISJ-MARK stays DEFERRED (3rd
`Mark` state, large).
Resolve by philosophy, drive the loop.

## State

Spec-conformance backlog substantively EXHAUSTED — lone open VALUE divergence is
NESTED-DISJ-MARK (designed-deferral). argocd + cert-manager content-identical drop-ins (jq
-S = 0, re-confirmed this round from `/Users/chakrit/Documents/prod9/infra` via the `k8s/`
subdirs). Per-eval perf frontier CLOSED.

## Verify on resume

`git status` clean, `HEAD == @{u}`, `lake build` green (110 jobs),
`scripts/check-fixtures.sh` green. Bare `kue </dev/null` prints help + exit 0 (no hang);
`kue eval </dev/null` empty + exit 0 (no smoke). Canaries (from
`/Users/chakrit/Documents/prod9/infra`, against
`./k8s/cert-manager` + `./k8s/argocd`) jq-S=0.

## Release

`v0.1.0-alpha.20260623` is the latest cut. A FRESH alpha is OWED: the prior-round
scalar-default-select fix + this CLI entry-UX fix are user-observable changes not yet in a
tagged release (the entry-UX one is especially user-facing). Auto-cut the next due daily
alpha (attended) via `scripts/release.sh` (+ `scripts/release-linux.sh` for Linux assets).
Both behavior changes are absent from the canary corpora — drop-in parity unaffected.

## Live state end
