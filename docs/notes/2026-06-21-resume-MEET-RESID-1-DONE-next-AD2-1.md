# RESUME HERE — MEET-RESID-1 + D#1d-RESIDUAL DONE (2026-06-21); next code leader = AD2-1

Live START-HERE pointer; supersedes `2026-06-21-resume-AUDIT-COMPLETE-next-D1d-RESIDUAL.md`
(deleted). Authoritative live roadmap: [`../spec/plan.md`](../spec/plan.md) (capabilities, ranked
backlog, audit verdicts) + [`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md)
§ Consolidated fix backlog.

## SLICE (2026-06-21): MEET-RESID-1 + D#1d-RESIDUAL — both ✅ DONE (one commit)

A held `.structComp` residual (a comprehension whose dynamic key / `if` / `for` is non-concrete)
now (a) is HELD as a comprehension BODY (D#1d-RESIDUAL one-liner) and (b) SURVIVES a `meet`/`&`
against a struct (MEET-RESID-1). HEAD dropped it to `{}` then bottomed any `&`. Witnesses
oracle-confirmed vs cue v0.16.1.

- **MEET-RESID-1 (lattice):** new `meetWithFuel` arm (`Lattice.lean`, symmetric, ABOVE the
  struct/embeddedList arms, BELOW `.top`) + helper `asResidualMergeOperand?`. Merges the residual's
  RESOLVED fields via `mergeStructN` (a field conflict bottoms THERE — `a:{x:1,for…}&{x:2}` →
  `x: _|_`, export errors, NOT masked), re-wraps `.structComp merged (lcomps++rcomps) mo`. A
  non-struct `other` (`a & 5`) → `none` → `meetCore` → `.bottom` (real type error, unchanged).
- **D#1d-RESIDUAL (one-liner):** `expandClausesWithFuel`'s `onExhausted` (`Eval.lean:~3622`) gained
  `| .structComp .. => .deferred` — a comprehension whose BODY is a held residual re-emits the
  original `.comprehension` (held), not `.payload []` (→ `{}`).

### ★ The soundness gate (why the defer can NEVER mask a conflict) — STRUCTURAL, not a predicate

> **A `.structComp` is, by construction, ALWAYS an unresolved residual whose `fields` are already
> conflict-free.** A resolved conflict is `.bottom`, never a `.structComp` — that state is
> unrepresentable.

Exhaustive over the two production sites: `withDeferredComprehensions` emits a `.structComp` only
when the static merge SUCCEEDED (a field conflict returns `.bottom` FIRST) + `deferred ≠ []`; the
parse-time form is unevaluated-by-construction (eager arm expands it before any meet). So
"unresolved residual" ≡ "is `.structComp`"; the predicate is the constructor tag and can never fire
on a conflict. Illegal-states-unrepresentable does the gate's work. Full argument + the reduction +
two-pass-convergence proof: plan.md MEET-RESID-1 entry + the implementation-log entry.

### Verify (all green)

`lake build` 108 jobs; axiom-clean (`propext`/`Classical.choice`/`Quot.sound`, no `sorryAx`/
`partial`); `check-fixtures.sh` → `fixture pairs ok` (all existing byte-identical; **7 TwoPassTests
green**); **cert-manager export BYTE-IDENTICAL to pre-fix HEAD baseline `90071b4`** (throwaway
worktree) AND = cue — meetWithFuel is THE hot path, zero regression. 8 adversarial `native_decide`
theorems in `TwoPassTests.lean` (witness + held body + 4 soundness tripwires + 2 no-over-fire
controls), all source-level + oracle-checked. No `cue-divergences.md` / `cue-spec-gaps.md` change
(CONFORMS; held-`@d.i` display is the documented D#1b row).

## Audit state — **counter = 1** (this is slice 1 of the new code batch).
**Next audit after 2–3 NEW code slices** (AD2-1 will be slice 2). Two-phase (A then B) per
[`../guides/slice-loop.md`](../guides/slice-loop.md) — do NOT invoke `/ace-audit`.

The prior two-phase audit (A-EN3-DYN + DYN-DEF-1 batch) is DONE: Phase A `503955b`, Phase B
`90f43f5`. D#1d-RESIDUAL investigation `90071b4` (no-code). This MEET-RESID-1 + D#1d-RESIDUAL commit
is the FIRST code slice since the counter reset.

## NEXT — the next code leader (correctness-first)

1. **AD2-1 (LOW-MED — disjunction-normalizer dedup; FILE as a slice, do NOT apply inline) —
   LEADER.** `normalizeEvaluatedDisj` (`Eval.lean:694`, EVAL) and `normalizeDisj`
   (`Lattice.lean:277`, LATTICE/meet) near-identical, differ ONLY on the LONE-arm rule. Value-sound
   (display-only). Flips TWO NAMED theorem pins (`meet_disjunction_preserves_default_marker`,
   `lattice_…`) + the SC-3 display contract — a human signs off the contract rename. Couples with
   SC-3. Full spec: plan.md § AD2-1.
2. The LOW cosmetic tail (plan item 6), **A#6** (`containsBottom` fuel cap, standalone), **EvalOps
   extraction** (plan item 2, parallel-safe mechanical carve).

## CANONICAL PATHS (ground-truth — do NOT re-litigate)

- prod9 stress-test targets: `/Users/chakrit/Documents/prod9/infra/apps/argocd.cue` (PARKED) and
  `.../cert-manager.cue` (semantically = cue; byte-differs only in JSON key ordering — pre-existing,
  NOT a regression). **Run cert-manager from the infra MODULE dir** (`cd .../prod9/infra &&
  {kue,cue} export ./apps/cert-manager.cue`); the bare absolute-path invocation errors
  `import failed: … no cue.mod` for BOTH binaries. Semantic compare: `/usr/bin/python3 -c "import
  json;print(json.load(open(a))==json.load(open(b)))"`.
- cue oracle: `/Users/chakrit/go/bin/cue` (v0.16.1) — READ-ONLY, cross-check only.
- kue binary: `.lake/build/bin/kue` (or `lake exe kue`). FixturePorts lives at
  `Kue/Tests/FixturePorts.lean` (hand-built AST only — no source-string port; prefer
  `evalSourceMatches`/`exportJsonBottoms` `native_decide` theorems in `*Tests.lean` for new
  source-level pins).
- **Python note:** a shell wrapper shadows `python3` with a broken `~/.venv`; use `/usr/bin/python3`
  by absolute path.
- **Baseline-compare trick (no working-tree risk):** `git worktree add -d /tmp/kue-head HEAD` →
  `cd /tmp/kue-head && lake build` → compare its binary → `git worktree remove --force
  /tmp/kue-head` (run the remove from the kue repo dir, not prod9).

## STANDING CONTEXT (durable; full detail in CLAUDE.md + guides/slice-loop.md)

- Kue autonomy grant in effect (decide/proceed; resolve forks by philosophy; commit/push on
  `main` when attended). **Spec is authority; `cue` is a fallible cross-check, never a gate** —
  EXCEPT the narrow oracle-as-data-source carve. Correctness-over-performance. **Unattended/AFK →
  commit, don't push.**
- Orchestrator = thin re-spawner; one subagent per slice; two-phase audit (A then B) every 2–3
  slices — **counter now 1.** Per-slice duties: tests-first; log `cue-divergences.md`; flag
  `cue-spec-gaps.md`; keep `kue-performance.md` current.
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on main tree.
- **argocd / Bug2-5: PARKED** — a stress-test finding, not on the critical path.
