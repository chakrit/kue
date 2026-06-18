> **SUPERSEDED (2026-06-18).** This early-session breadcrumb is stale (`Value.closure`
> landed; closures and cross-package def-meet now work). Current START-HERE: the newest
> `docs/notes/2026-06-18-*-landed.md` + the live roadmap `docs/spec/plan.md`.

# RESUME HERE — session save 2026-06-18

Latest resume breadcrumb; supersedes `2026-06-17-loader-robustness-landed.md` and the
earlier per-slice notes as the START-HERE pointer. Tree clean, all pushed to `gh:main`
(HEAD `405b4bb`).

## Status: goal MET; holding on ONE design decision

**Kue replaces cue for self-contained prod9/infra apps today.** A real
`hatari/infra/apps/common.cue` exports **cue-identically in JSON and YAML** via
`kue export -e <app> <file|dir>`. Shipped alpha: **`v0.1.0-alpha.20260617.3`**
(`brew install chakrit/tap/kue` / `brew upgrade kue`). Full engine landed + audited this
session: value lattice, structs (all field classes, optional-defs, patterns incl.
`[string]:`), lists, disjunctions, refs + bounded cycles, comprehensions, dynamic fields,
interpolation, embeddings, lazy resolution through conjunction (2c), exact-decimal
arithmetic + decimal/domain bounds matching cue, manifestation, `strings`/`list`/`math`/
`base64`/`json`/`yaml` builtins, memoized eval, imports (in-module + cross-module via the
local cue cache) + multi-file package-dir merge, and a real CLI
(`eval`/`export`/`-e`/`version`/`help`). ~40 slices + ~19 audits, all green.

## THE decision waiting for chakrit — see `docs/spec/plan.md` "DECISION NEEDED"

Full export of apps that meet **imported** defs (`defs.#Deployment & {…}`) is gated on
three deep frontiers; all reconned + recorded, none a clean autonomous slice:

1. **Cross-package def-meet laziness (the real blocker).** Needs an env-carrying
   **`Value.closure`/thunk** — the general lazy-cross-frame fix that REOPENS the "meet is
   pure / refs opaque to meet" invariant the whole 2c family rests on (touches every
   `Value` consumer + cycle handling). The cheap narrowing provably does NOT unblock real
   apps. **This is chakrit's design call: `Value.closure`, or a different decomposition?**
2. **Perf hang — downstream of #1, held.** The floated fuel-insensitive memo is *provably
   unsound* (`fuel` is load-bearing — 263 measured fuel-truncation conflicts). Real blowup
   is exponential frame-id divergence on duplicated sub-refs; real fix = frame-id sharing
   (audit-heavy). Unreachable on real apps until #1 lands. Re-profile after #1.
3. **Field-ordering parity (polish).** cue orders `ref & {own}` own-fields-first; kue
   left-first. Per-`Field` provenance key through meet/manifest; reorders *most* `.expected`
   fixtures. Byte-parity-for-diffing-vs-cue, not functional (YAML maps unordered). Wants
   chakrit's go-ahead before that churn.

**Orchestrator stopped here deliberately** — the clean autonomous frontier is reached; the
only remaining autonomous-clean work is cosmetic make-work (deferred test-module splits,
`EvalOps`/`Regex` extraction) the audits classified LOW/no-benefit/churn-risk. Did NOT
grind it (burns tokens, risks regressions, no goal value).

## Next `/ace`: present the decision, don't auto-implement

Surface the three frontiers; let chakrit pick: (1) the `Value.closure` direction (the one
real unlock), (2) field-ordering churn yes/no, or (3) the parked cosmetic cleanups. Then
plan the chosen one. The `plan.md` "DECISION NEEDED" section is the current authority;
earlier "Re-ranked"/"AUTHORITATIVE" lists in plan.md are superseded design-record.

## Standing context (durable, do not relearn)

- **Release:** ~1 datestamped alpha/day, `0.1.0-alpha.YYYYMMDD[.N]`, **local
  `scripts/release.sh` only — GitHub Actions/CI is BANNED** (also in chakrit's user
  CLAUDE.md). Runbook: `RELEASE.md`. Cut from an audited HEAD. Latest `.3`.
- **Loop:** `docs/guides/slice-loop.md` — 2–3 slices → Phase A code-quality audit → Phase B
  architecture audit → repeat (audits are a written procedure, NOT the `/ace-audit` skill);
  type-system-first philosophy (illegal states unrepresentable + ML idioms) is the audits'
  first check.
- **Safety:** prod9 + the cue cache are READ-ONLY (eval/probe only, never mutate). External
  repos read-only. The session bash output filter non-deterministically mangles piped/
  heredoc git input → use `git commit -F /tmp/msg`; trust `lake build` as coverage
  ground-truth over grep/wc. NO `git checkout`/`restore`/`reset`.
- **Reference:** language-choice investigation (stay Lean 4) →
  `docs/notes/2026-06-17-language-choice-investigation.md`.
