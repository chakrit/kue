# Breadcrumb: Phase B audit — consolidation-batch plan finalized (2026-06-17)

Phase B architecture/refactor/cleanup audit ran over the int-bound + CLI + open-list
family (Phase A `20fe8fa` just landed). Plan-only change: folded ONE authoritative ranked
consolidation-batch plan into `docs/spec/plan.md` as section
**"Architecture Fix-Slices (Phase B audit 2026-06-17 #5 — AUTHORITATIVE)"**; marked #4
SUPERSEDED. No code changed.

## Verdicts (re-confirmed this pass)

- **Main/Cli/Runtime layering: CLEAN.** `Main → {Kue, Cli}`, `Cli → Runtime`, `Runtime →
  {Eval, Format, Lattice, Parse, Resolve, Json, Yaml}`. `Cli` is pure argv→`Command` (no
  IO); `Main` owns IO + dispatch. No back-edge, no IO leak. Sum types tight, parse total.
- **Eval.lean (1191): keep whole.** `meetConjValueWith` rewrite landed in `Lattice` not
  `Eval`, so Eval shape unchanged. `EvalOps` extraction still optional LOW.
- **Manifest Value-dispatch: ALREADY exhaustive** (no catch-all over `Value`). The only
  wildcard left is `manifestFieldsWithFuel`'s `_ =>` over `FieldClass` — folded as item 3f.
- **Module layering: clean, acyclic, `Builtin → Eval` still absent.**

## The single ranked sequence (recommended: 3 → 1+2 → 4 → 5/6)

1. **[MEDIUM] conj canonical-sort** — `a&b ≠ b&a` as `Value`s; sort `.conj` members
   (kind, then bounds by `(cmp,domain)`, then others) in `meetConjValueWith` re-wrap.
2. **[MEDIUM] `intGe/Gt/Le/Lt` → `boundConstraint (Decimal) (BoundKind) (domain : Kind)`**
   — ~130 occ / 9 modules; folds the bare-bound + float-bound divergences.
3. **[MEDIUM, OVERDUE] consolidation+test-reorg batch** — base64-out-of-Json,
   `testdata/cue/` flat→subsystem subdirs + harness rewire, `Field`→`structure` (~95
   sites), `FixturePorts`/`FixtureTests`/`BuiltinTests` split, Manifest-FieldClass tighten.
4. **[MEDIUM] Linux `cacheRoot` default** (Module.lean, `System.Platform` branch).
5/6. **[LOW]** `embeddedList.decls` newtype; `EvalOps` extraction.

**conj-sort (1) PAIRS with boundConstraint (2)** — both edit `meetConjValueWith`'s re-wrap
+ the canonical member-order comparator; after the fold the 4 per-op ctors collapse to one,
so the sort key is computed once. Land together (1's commutativity theorems against the
post-fold representation) to avoid rewriting the comparator twice.

**Recommended order: do item 3 (cheap mechanical cleanups + overdue test-reorg) FIRST** to
shrink the test surface the representation refactors must chase references through, **then
1+2 together** (shared conj-bound code), then 4, then 5/6. Full move-plan for item 3
(3a–3f) is spelled out in plan.md so a subagent executes it mechanically.

## Inline fixes applied this audit

NONE. CLI flag-scan DRY nit deliberately NOT extracted (distinct per-context error text is
the contrast `general-coding` protects). `Field`→structure (95 sites) and Manifest-
FieldClass tighten are larger than "small clean swap" → folded, not applied.

## Verify state

- `lake build` — 84 jobs, green (no code changed this pass).

## Next step

Re-enter the slice loop. First slice: **consolidation+test-reorg batch (plan.md #5 item 3,
sub-tasks 3a–3f)** as one verify cycle, then the conj-sort + boundConstraint pair (items 1+2
together).

## Carry-forward

- Alpha cadence: ~1 datestamped cut/day via `scripts/release.sh`, NO CI. Latest is
  `v0.1.0-alpha.20260617.2`. Do NOT touch `scripts/release.sh` / `packaging/` / release
  files / the tap repo.
- `Kue.version` (`Kue/Runtime.lean`) is the in-binary version release.sh bumps.
- External repos (prod9, cue cache) are READ-ONLY. No tree-reverting git; revert via Edit;
  `/tmp` for experiments.
