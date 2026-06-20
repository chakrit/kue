# RESUME HERE — A-EN3-DYN DONE (2026-06-20); **next leader = DYN-DEF-1**

Live START-HERE pointer; supersedes `2026-06-20-resume-audit-round-CLOSED-next-A-EN3-DYN.md` (deleted).
Authoritative live roadmap: [`../spec/plan.md`](../spec/plan.md) (capabilities, ranked backlog,
audit verdicts) + [`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md)
§ Consolidated fix backlog.

## Audit state — **counter = 1.** No audit due yet.

The two-phase audit over the AD4-1 + A-EN3 batch closed at counter 0 (Phase A `6a5521a` + Phase B
`a788f5c`). **A-EN3-DYN is slice 1 of the new batch (this slice). Counter = 1.** Next two-phase
audit (A then B, per [`../guides/slice-loop.md`](../guides/slice-loop.md) — do NOT invoke
`/ace-audit`) is due after **1–2 more slices** (the 2–3-slice mark).

## Last landed — A-EN3-DYN (this slice), DONE + pushed

Spec-conformance Violation fix: a comprehension inside an embedded def reading a regular def sibling
SOLELY through a DYNAMIC field's value, with the sibling narrowed at the use site, lost the narrowing
(witness exported as incomplete `string`; cue v0.16.1 gives `[{k: "specific"}]`).

```
#Add: {#kind: string, kind: string, out: [for x in ["a"] {("k"): kind}]}
patch: {#kind: "specific", kind: "specific", #Add}
# cue → patch.out == [{k: "specific"}]   kue (pre-fix) → export error "incomplete value: string"
```

**Root cause = TWO parallel sites of the SAME depth-mirror bug** (a `.dynamicField` pushes no
resolver frame, so its value must be scanned at the PARENT depth, not `depth+1`). The original
diagnosis named only the first; the second was found by instrumenting the eval after the first fix
alone did not move the result:
1. `foldValueWithDepth`/`defFrameRefIndices` (`dynValShift=1`) → splice-seed scan missed the sibling.
2. `hasSelfRefAtDepth` (same `+1` on the dyn-field value, key dropped) → `defBodyHasSiblingSelfRef`
   returned false → def took the EAGER path (resolved `out` against `kind: string`) instead of the
   deferral/closure-force path. **Both fixes were necessary.**

Fix: dropped the now-dead `dynValShift` parameter (all three `foldValueWithDepth` instantiations pass
`0`) and inlined the `0` offset; `hasSelfRefAtDepth`'s dyn-field arm now scans key+value at `depth`.
Tests: 4 new `testdata/cue/comprehensions/` fixtures (witness, static control, multi-level
key+nested-value, unaffected-no-sibling) + `FixturePorts` entries, oracle-checked vs cue v0.16.1; the
A-EN3 pin `fold_value_dynfield_shift_divergence` (locked the over-scan) REPLACED by
`fold_value_dynfield_value_scanned_at_parent_depth` (corrected arms). CONFORMS to spec → no
`cue-divergences.md` entry. Gate green: `lake build` (108 jobs) / `fixture pairs ok` (full corpus
byte-identical except the now-correct buggy case) / shellcheck clean; cert-manager byte-identical to
the pre-fix HEAD baseline (verified via throwaway worktree) and semantically identical to cue.

## NEXT — the next code leader (correctness-first ranking)

1. **DYN-DEF-1 (MEDIUM Violation — LEADS).** A dynamic field declared in a DEFINITION is dropped when
   its keying field is narrowed at the use site:
   ```
   #Add: {kind: string, (kind): "marker"}
   patch: #Add & {kind: "specific"}
   # cue v0.16.1: patch == {kind: "specific", specific: "marker"}
   # kue (current): patch == {kind: "specific"}   (WRONG — dyn field dropped; def output drops it too)
   ```
   DISTINCT from A-EN3-DYN: no comprehension, so `defFrameRefIndices`/`embedComprehensionReadLabels`
   is not the mechanism — the dyn field is lost in the def-splice or dyn-key re-evaluation (likely
   `hiddenFieldsOnly`/`spliceOperandForEmbed`). A PLAIN-struct version (no def) works in kue. NOTE:
   A-EN3-DYN's two-site lesson — the splice-seed scan and the deferral gate are SEPARATE mechanisms;
   when probing DYN-DEF-1, check both the splice (does the dyn field reach the operand?) and whether
   the field even survives def re-keying, before assuming a single locus. Diagnosis-first, TDD,
   fix at source. Full spec: plan.md § walker-dedup, DYN-DEF-1 entry.

2. **AD2-1 (LOW-MED — disjunction-normalizer dedup; FILE as a slice, do NOT apply inline).** The SOLE
   remaining walker/normalizer-dedup-family member. Value-sound (display-only), so it never preempts
   the Violation above. Flips two NAMED theorem pins + the SC-3 display contract — a human signs off
   the contract rename. Couples with SC-3. Full spec: plan.md § walker-dedup, AD2-1.

Then the LOW tail (plan item 6), **A#6** (`containsBottom` fuel cap, standalone), **EvalOps
extraction** (plan item 2, parallel-safe mechanical carve).

## CANONICAL PATHS (ground-truth — do NOT re-litigate)

- prod9 stress-test targets: `/Users/chakrit/Documents/prod9/infra/apps/argocd.cue` (PARKED) and
  `.../cert-manager.cue` (semantically identical to cue; byte-differs only in JSON key ordering — a
  pre-existing artifact, NOT a regression). **Run cert-manager from the infra MODULE dir**
  (`cd .../prod9/infra && {kue,cue} export ./apps/cert-manager.cue`); the bare absolute-path
  invocation errors `import failed: … no cue.mod` for BOTH binaries (a cue.mod-context artifact).
  Semantic compare: `python3 -c "import json;print(json.load(open(a))==json.load(open(b)))"`.
- cue oracle: `/Users/chakrit/go/bin/cue` (v0.16.1) — READ-ONLY, cross-check only.
- kue binary: `.lake/build/bin/kue` (or `lake exe kue`).
- **Python note:** a shell wrapper shadows `python3` with a broken `~/.venv`; use `/usr/bin/python3`
  by absolute path for any generator/oracle scripting.
- **Baseline-compare trick (no working-tree risk):** `git worktree add -d /tmp/kue-head HEAD` →
  `cd /tmp/kue-head && lake build` → compare its binary → `git worktree remove --force`. Confirms a
  change did/didn't alter a prod-app output without touching the main tree.

## STANDING CONTEXT (durable; full detail in CLAUDE.md + guides/slice-loop.md)

- Kue autonomy grant in effect (decide/proceed; resolve forks by philosophy; commit/push on `main`
  when attended). **Spec is authority; `cue` is a fallible cross-check, never a gate** — EXCEPT the
  narrow oracle-as-data-source carve (data, never a gate). Correctness-over-performance.
  **Unattended/AFK → commit, don't push.**
- Orchestrator = thin re-spawner; one subagent per slice; two-phase audit (A then B) every 2–3
  slices — **counter now 1, no audit due** (next after 1–2 more slices). Per-slice duties:
  tests-first; log `cue-divergences.md`; flag `cue-spec-gaps.md`; keep `kue-performance.md` current.
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on main tree.
- **argocd / Bug2-5: PARKED** — a stress-test finding, not on the critical path; may never un-park.
