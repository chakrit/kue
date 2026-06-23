# RESUME — Bug2-12b RESOLVED; audit counter = 1; next = per-eval-cost / spec-gap tail (2026-06-23)

Live START-HERE; supersedes `2026-06-23-resume-two-phase-audit-closed.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md). Spec-conformance backlog:
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Genuinely-open
(Bug2-12b is RESOLVED item 0). Per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md).
Served status page: [`../../www/index.html`](../../www/index.html).

## State — audit counter = 1. Bug2-12b LANDED.

**Bug2-12b RESOLVED** (the contained split-literal self-rec over-close the Bug2-12 fix introduced).
A self-rec closed def whose literals are SPLIT across `&` (`#X: #X & {a:1} & {c:3}`) closed each
literal SEPARATELY, so a use-site re-declaring the def's OWN field (`out: #X & {c:3}`) wrongly
bottomed where cue ADMITS `{a:1,c:3}`. FIXED in `flattenConjDefRef`'s `close == true` branch:
partition `expanded` into the union-able def-body literals (`isUnionableDefValue`) vs the rest (the
self-ref `.refId`, UNTOUCHED), close EACH literal first (so `unionDefOpenness` reads settled def-body
openness, not a raw `regularOpen`), `foldl mergeDefinitionDecls` into ONE merged body, close that
once, re-emit `rest ++ [closed]`. `mkStruct` derives the SINGLE self-clause over the union `{a,c}`.
The Bug2-6/2-7 close-once principle REUSED on the flatten path — no new function, no seam merge.

Witnesses all == cue: FLIP admits `{a:1,c:3}`; genuine-extra rejects `b`; single-literal unchanged;
open-tail-across-split admits; conflict-across-split bottoms; 3-way + split-pattern admit/reject;
selfrec-admit/opentail-self unchanged. The 5 Bug2-6 + 7 Bug2-9 pins and D#2 guardrails STAY GREEN.
`flattenConjDefRef` `propext`-only, total. Full gate green (`lake build` + `check-fixtures.sh`);
canaries jq-S=0 by construction (the arm fires only for self-rec def `.conj` bodies — prod9 has none;
corpus off this machine, read-only). 8 inline pins (1 flipped + 7 new) + 3 export fixtures + 4
internal-format fixture pairs.

## NEXT — pick the next leader (resolve by philosophy; none soundness-bearing, none block adoption)

**Audit cadence: counter = 1.** Two-phase audit DUE at 2–3 slices (per
[`../guides/slice-loop.md`](../guides/slice-loop.md)) — Bug2-12b is 1 slice since the last audit
closed; run the audit after the next 1–2 slices, not now.

Spec-conformance-HIGH is fully DONE. perf #7 frame-sharing is WON'T-FIX (measured ~0.05% ceiling,
unsound where non-empty — see plan.md). Remaining ranked candidates (resolve by philosophy):

- **per-eval-cost slice** (the live perf frontier) — lower the per-eval CONSTANT / eval COUNT over the
  genuinely-large distinct population (argocd ~50s, cert-manager ~11.5s). NOT cross-env sharing (that
  leg is closed). The user-controllable lever is flatten/shorten chains; a per-eval-cost reduction is
  the open principled lever. Detail: `kue-performance.md`.
- **Bug2-12 MUTUAL tail** (LOW, spec-gap-first) — the mutual-recursion closedness leak (`#A: #B & {a}`,
  `#B: #A & {b}`); kue under-closes, cue rejects even the def's OWN field; cue's mutual reading is
  lattice-questionable, so SPEC-CHECK FIRST. Recorded in `cue-spec-gaps.md` Bug2-12 MUTUAL row.
- **SC-4** (LOW, spec-gap-first — nested hidden/let closedness on direct def-meet; cue internally
  inconsistent, spec-check first).
- **item-6 LOW tail** in `plan.md` (`module-file-scoped-imports`, parser strictness,
  `release-linux.sh` dirty-tree guard, A2-x/y, B2-A1/A2 — none soundness-bearing).

## Live state end
