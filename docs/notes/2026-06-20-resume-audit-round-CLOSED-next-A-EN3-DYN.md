# RESUME HERE — two-phase audit CLOSED (2026-06-20); **next leader = A-EN3-DYN**

Live START-HERE pointer; supersedes `2026-06-20-resume-A-EN3-done-DRY-1-ruled-AUDIT-DUE.md` (deleted).
Authoritative live roadmap: [`../spec/plan.md`](../spec/plan.md) (capabilities, ranked backlog,
audit verdicts) + [`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md)
§ Consolidated fix backlog.

## Audit state — **COMPLETE. Counter = 0.** No audit due.

The two-phase audit over the **AD4-1 (`524a402`) + A-EN3 (`5652717`)** dedup batch is CLOSED:
**Phase A `6a5521a`** (both dedups SOUND; re-classified A-EN3-DYN to a REACHABLE wrong-result
Violation; filed DYN-DEF-1) + **Phase B `<this commit>`** (architecture HEALTHY; abstractions
confirmed right-level; rankings/rulings folded into the plan). Counter RESET to **0** — next
two-phase audit after **2–3 new slices** (per [`../guides/slice-loop.md`](../guides/slice-loop.md);
do NOT invoke `/ace-audit`).

## NEXT — the next code leader (correctness-first ranking)

The audit re-ordered the backlog to correctness-first. Run these as slices in order:

1. **A-EN3-DYN (Violation — LEADS).** Reconcile `defFrameRefIndices`'s over-deep `.dynamicField`
   value scan from `dynValShift=1` to `0` (the resolver's discipline — `Resolve.lean` resolves a
   dynamic field's key + value in the SAME scope, no frame push). Phase A re-classified this from a
   "LOW unreachable corner" to a **REACHABLE WRONG-RESULT Violation** with a witness:
   ```
   #Add: { #kind: string, kind: string, out: [for x in ["a"] {("k"): kind}] }
   patch: { #kind: "specific", kind: "specific", #Add }
   # cue v0.16.1: patch.out == [{k: "specific"}]   (correct — narrowing reaches the dyn-field value)
   # kue (current): patch.out == [{k: string}]      (WRONG — over-deep scan misses the sibling)
   ```
   The SAME source with a STATIC body field `{k: kind}` evaluates CORRECTLY in kue — clean
   static-vs-dynamic isolation pinning the bug to `dynValShift=1`. **This is a real TDD bug-slice,
   NOT a low-risk inline change** — the fix INTENTIONALLY breaks byte-identical (it corrects a wrong
   result). Steps: set `dynValShift 1→0`; add the witness as a `testdata/cue/.../{cue,expected}` pair
   + `FixturePorts` entry; FLIP `fold_value_dynfield_shift_divergence` (`TwoPassTests.lean:325`) to
   assert the corrected `[5]→[]` arms; full gate. **Ride-along cleanup (do it as the last step):**
   once both `foldValueWithDepth` call sites pass `0`, `dynValShift` is a dead constant → drop the
   parameter from `foldValueWithDepth`/`foldValueWithDepthClauses` and inline the `0` offset. Full
   spec: plan.md § walker-dedup, A-EN3-DYN entry.

2. **DYN-DEF-1 (MEDIUM Violation — SECOND).** A dynamic field declared in a DEFINITION is dropped
   when its keying field is narrowed at the use site:
   ```
   #Add: { kind: string, (kind): "marker" }
   patch: #Add & { kind: "specific" }
   # cue v0.16.1: patch == { kind: "specific", specific: "marker" }
   # kue (current): patch == { kind: "specific" }   (WRONG — dyn field dropped; def output drops it too)
   ```
   DISTINCT from A-EN3-DYN: no comprehension, so `defFrameRefIndices`/`embedComprehensionReadLabels`
   is not the mechanism — the dyn field is lost in the def-splice or dyn-key re-evaluation (likely
   `hiddenFieldsOnly`/`spliceOperandForEmbed`). Diagnosis only; locate the drop, TDD fixture, fix at
   source. Full spec: plan.md § walker-dedup, DYN-DEF-1 entry.

3. **AD2-1 (LOW-MED — disjunction-normalizer dedup; FILE as a slice, do NOT apply inline).** The
   SOLE remaining walker/normalizer-dedup-family member. Value-sound (display-only), so it never
   preempts the two Violations above. Flips two NAMED theorem pins + the SC-3 display contract — a
   human signs off the contract rename. Couples with SC-3. Full spec: plan.md § walker-dedup, AD2-1.

Then the LOW tail (plan item 6), **A#6** (`containsBottom` fuel cap, standalone), **EvalOps
extraction** (plan item 2, parallel-safe mechanical carve).

## Last landed — Phase B audit (this commit), DONE

Architecture HEALTHY, no code fix. Confirmed: `foldValueWithDepth` (A-EN3) + `ClauseOutcome β` /
`expandClauseChain` (AD4-1) are right-level abstractions with pure non-recursive variation points
(combinator owns recursion — the truncate-Step-2 / DRY-1 trap avoided); module graph acyclic, both
dedups intra-`Eval.lean` (zero new edges); `Eval.lean` 3605 lines (SHRANK ~136 — dedups net-removed
lines; EvalOps still the right first carve, not yet due); dropped `*ForPairsWithFuel`/`*Clauses`
helpers gone with zero dangling refs; perf-guide current. **`.any`→`foldl` ruling: ACCEPT** —
`refsSelfEmbeddedLabel`'s lost within-field early-exit is a bounded constant inside the outer
field-level `.any` short-circuit + fuel-bounded trees; restoring `.any` would re-introduce the
per-shape duplication A-EN3 removed. Verify gate green (build 108 jobs / `fixture pairs ok` /
shellcheck clean). Full verdict: plan.md § "Phase-B audit 2026-06-20 (`<this commit>`)".

## CANONICAL PATHS (ground-truth — do NOT re-litigate)

- prod9 stress-test targets: `/Users/chakrit/Documents/prod9/infra/apps/argocd.cue` (PARKED) and
  `.../cert-manager.cue` (content-identical to cue). **Run cert-manager from the infra MODULE dir**
  (`cd .../prod9/infra && {kue,cue} export ./apps/cert-manager.cue`); the bare absolute-path
  invocation errors `import failed: … no cue.mod` for BOTH binaries (a cue.mod-context artifact).
- cue oracle: `/Users/chakrit/go/bin/cue` (v0.16.1) — READ-ONLY, cross-check only.
- kue binary: `.lake/build/bin/kue` (or `lake exe kue`).
- **Python note:** a shell wrapper shadows `python3` with a broken `~/.venv`; use `/usr/bin/python3`
  by absolute path for any generator/oracle scripting.

## STANDING CONTEXT (durable; full detail in CLAUDE.md + guides/slice-loop.md)

- Kue autonomy grant in effect (decide/proceed; resolve forks by philosophy; commit/push on `main`
  when attended). **Spec is authority; `cue` is a fallible cross-check, never a gate** — EXCEPT the
  narrow oracle-as-data-source carve (data, never a gate). Correctness-over-performance.
  **Unattended/AFK → commit, don't push.**
- Orchestrator = thin re-spawner; one subagent per slice; two-phase audit (A then B) every 2–3
  slices — **counter now 0, no audit due** (next after 2–3 new slices). Per-slice duties:
  tests-first; log `cue-divergences.md`; flag `cue-spec-gaps.md`; keep `kue-performance.md` current.
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on main tree.
- **argocd / Bug2-5: PARKED** — a stress-test finding, not on the critical path; may never un-park.
