# RESUME HERE — DYN-DEF-1 DONE (2026-06-20); **two-phase AUDIT DUE**, then AD2-1

Live START-HERE pointer; supersedes `2026-06-20-resume-A-EN3-DYN-done-next-DYN-DEF-1.md`
(deleted). Authoritative live roadmap: [`../spec/plan.md`](../spec/plan.md) (capabilities,
ranked backlog, audit verdicts) +
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Consolidated fix
backlog.

## Audit state — **counter = 2. TWO-PHASE AUDIT DUE (do this next).**

A-EN3-DYN (slice 1) + DYN-DEF-1 (slice 2) — the two dyn-field-correctness Violations — are a
coherent batch to audit together at the 2-slice mark. Run the two-phase audit per
[`../guides/slice-loop.md`](../guides/slice-loop.md) — **A (code-quality) then B
(architecture/cleanup), SEQUENTIALLY; do NOT invoke `/ace-audit`** (the procedure is in the
guide). Scope: the A-EN3-DYN (`4cd8fbe`) + DYN-DEF-1 (`46e9871`) diffs for Phase A; the whole
module graph for Phase B. Auditor's call whether to batch AD2-1 in as slice 3 first — but the
two dyn-field fixes stand on their own as an audit batch.

## Last landed — DYN-DEF-1 (this slice), DONE + pushed (`46e9871`)

Spec-conformance Violation fix: a dynamic field `(expr): v` whose label was NOT a concrete
string was silently DROPPED instead of held. cue v0.16.1 holds it under eval, errors under
export; kue dropped it (def's own display lost the field; abstract-keyed structs exported `{}`).

```
#Add: {kind: string, (kind): "m"}
x: #Add
# cue eval → x: {kind: string, (kind): "m"}   kue (pre-fix) → x: {kind: string}  (DROPPED)
```

**Diagnosis corrected the sketch (two-site lesson applied).** The orchestrator's "specific to
definitions / def-splice" framing was WRONG: (1) the NARROWED witness already re-keyed on HEAD
(the A-EN3-DYN `hasSelfRefAtDepth` key-scan had repaired the deferral gate); (2) the bug was
NOT def-specific — a plain struct with an abstract key dropped identically. Real locus = a PAIR
of silent-drop arms keyed on a non-string label: `expandComprehensionWithFuel` `.dynamicField`
(`_ => .ok ([], [])`) and the standalone `.dynamicField` eval (`_ => .bottom`).

**Fix.** One exhaustive `classifyDynLabel : Value -> DynLabelVerdict` (mirrors `classifyGuard`,
no catch-all) at BOTH sites — concrete string re-keys; bottom propagates; concrete non-string is
a type error (`BottomReason.nonStringLabel`); abstract/incomplete (incl. the `string` kind)
DEFERS, holding the UNEVALUATED `.dynamicField` so a later narrowed re-eval re-keys it. Standalone
arm also now preserves `fieldClass` (was hardcoded `.regular`). Renamed `NonBoolGuardType →
ConcreteTypeName` (now shared by 4 BottomReasons). Full detail: implementation-log DYN-DEF-1 entry.

CONFORMS to spec (cue correct → no `cue-divergences.md` correctness entry). Held-residual `@d.i`
key display folds into the existing D#1b display-divergence row. Gate green: `lake build` (108
jobs) / `fixture pairs ok` (corpus byte-identical except the corrected A-EN3 fixture
`dynfield_comprehension_key_and_nested_value.expected`, whose def-display had baked in the drop) /
shellcheck clean; cert-manager byte-identical to pre-fix HEAD baseline + semantically equal to
cue. Tests: `classify_dynlabel_*` unit pins (PresenceTests); `dyndef_*` end-to-end pins
(ComprehensionTests); 3 `definitions/dyndef_*` fixtures.

## NEXT — after the audit, the next code leader

1. **TWO-PHASE AUDIT (DUE NOW)** — A then B, per the guide. Fold findings into `plan.md` as
   ranked fix-slices (they count as slices next round).
2. **AD2-1 (LOW-MED — disjunction-normalizer dedup; FILE as a slice, do NOT apply inline).** The
   SOLE remaining walker/normalizer-dedup-family member. Value-sound (display-only). Flips two
   NAMED theorem pins (`meet_disjunction_preserves_default_marker`,
   `lattice_meet_disjunction_preserves_default_marker`) + the SC-3 display contract — a human
   signs off the contract rename. Couples with SC-3. Full spec: plan.md § walker-dedup, AD2-1.

Then the LOW tail (plan item 6), **A#6** (`containsBottom` fuel cap, standalone), **EvalOps
extraction** (plan item 2, parallel-safe mechanical carve).

## CANONICAL PATHS (ground-truth — do NOT re-litigate)

- prod9 stress-test targets: `/Users/chakrit/Documents/prod9/infra/apps/argocd.cue` (PARKED) and
  `.../cert-manager.cue` (semantically identical to cue; byte-differs only in JSON key ordering —
  a pre-existing artifact, NOT a regression). **Run cert-manager from the infra MODULE dir**
  (`cd .../prod9/infra && {kue,cue} export ./apps/cert-manager.cue`); the bare absolute-path
  invocation errors `import failed: … no cue.mod` for BOTH binaries (a cue.mod-context artifact).
  Semantic compare: `/usr/bin/python3 -c "import json;print(json.load(open(a))==json.load(open(b)))"`.
- cue oracle: `/Users/chakrit/go/bin/cue` (v0.16.1) — READ-ONLY, cross-check only.
- kue binary: `.lake/build/bin/kue` (or `lake exe kue`). FixturePorts lives at
  `Kue/Tests/FixturePorts.lean` (NOT `Kue/FixturePorts.lean` — the guide's path is stale).
- **Python note:** a shell wrapper shadows `python3` with a broken `~/.venv`; use `/usr/bin/python3`
  by absolute path for any generator/oracle scripting.
- **Baseline-compare trick (no working-tree risk):** `git worktree add -d /tmp/kue-head HEAD` →
  `cd /tmp/kue-head && lake build` → compare its binary → `git worktree remove --force
  /tmp/kue-head` (run the remove from the kue repo dir, not prod9). Confirms a change did/didn't
  alter a prod-app output without touching the main tree.

## STANDING CONTEXT (durable; full detail in CLAUDE.md + guides/slice-loop.md)

- Kue autonomy grant in effect (decide/proceed; resolve forks by philosophy; commit/push on
  `main` when attended). **Spec is authority; `cue` is a fallible cross-check, never a gate** —
  EXCEPT the narrow oracle-as-data-source carve (data, never a gate).
  Correctness-over-performance. **Unattended/AFK → commit, don't push.**
- Orchestrator = thin re-spawner; one subagent per slice; two-phase audit (A then B) every 2–3
  slices — **counter now 2, AUDIT DUE**. Per-slice duties: tests-first; log
  `cue-divergences.md`; flag `cue-spec-gaps.md`; keep `kue-performance.md` current.
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on main tree.
- **argocd / Bug2-5: PARKED** — a stress-test finding, not on the critical path; may never
  un-park.
