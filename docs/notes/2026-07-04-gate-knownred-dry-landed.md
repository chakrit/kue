# Breadcrumb: 2026-07-04 — GATE-KNOWNRED-DRY landed (shared `.known-red` helper)

Supersedes `2026-07-04-audit-struct-eq-half1-landed.md` as the live front.

## What landed

**GATE-KNOWNRED-DRY (LOW, infra) — DONE.** Pure DRY, shell-only (no Lean/eval change).
`scripts/check-fixtures.sh` carried the SAME three-state `.known-red` quarantine protocol
copy-pasted in `check_wild_fixtures` and `check_module_subpaths`.

- New helper `handle_known_red <known_red> <passed> <grad_label> <quar_label>` emits the
  graduation/quarantine diagnostic and returns a verdict: `0` = quarantined & still failing
  (report + skip), `1` = quarantined but now PASSES (graduation hard-fail → caller `status=1`),
  `2` = not quarantined (caller does its own pass/fail handling).
- Both gates call `handle_known_red … || verdict=$?` + a 3-line verdict map. The non-quarantined
  failure diagnostics (wild bare `status=1`; module err/diff branch) stay at each call site,
  reached only on verdict `2`. Shape-check-applies-to-quarantined behavior untouched (it runs
  before the helper call).
- Wording BYTE-IDENTICAL via preformatted labels: wild `<slug>` / `wild fixture <cue>`; module
  `module fixture <dir> subpath <sub>` for both.

`shellcheck` clean; `./scripts/check.sh` GREEN (exit 0). No live `.known-red` exists, so the
three-state verdict was smoke-tested in isolation OUTSIDE the repo (helper sourced verbatim) —
output matched the pre-refactor text exactly for both label forms. No eval change ⇒ no canary.
Committed on `main`, NOT pushed (AFK envelope).

## Still open — AUDIT-STRUCT-EQ half-2 (deferred/attended)

`dedupAlternatives` still uses the order-SENSITIVE global `Value` `BEq`, so `{a:1,b:2} | {b:2,a:1}`
→ `ambiguous value` where cue collapses. Do NOT redefine the global `BEq` (cycle detection at
`Eval.lean:292 structStack.contains` relies on exact equality). Needs an order-independent equality
fed into `dedupAlternatives`, coupled with a broader disjunction-canonicalization pass — a
soundness-sensitive, ATTENDED slice.

## Next step (pick by rank)

1. **B3d-6b (NETWORK-GATED)** — `cue mod get/tidy` + requirement-graph fetch + `cue.sum` WRITE.
   Network-gated; skip if AFK/offline.
2. **AUDIT-STRUCT-EQ half-2 (attended)** — order-independent `dedupAlternatives`; couple with
   disjunction canonicalization. NOT for AFK (soundness-sensitive, touches global disjunction path).
3. **ARCH-QUOTED-STRIP (MEDIUM)** — parse-only quoting; drop `Field.quoted` from the eval layer,
   delete the `stripFieldQuoting` walk.
4. **B2-A1** — thread `tail` through the patterns-present meet (lands with typed-ellipsis).

Two-phase audit: last full audit was the 2026-07-04 Phase B (GATE-KNOWNRED-DRY was one of its
filings, now cleared). Next audit due in ~2–3 slices.
