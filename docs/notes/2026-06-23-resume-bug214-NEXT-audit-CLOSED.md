# RESUME — two-phase audit CLOSED; next = Bug2-14 embed-merge fix (2026-06-23)

Live START-HERE; supersedes `2026-06-23-resume-bug214-REDIAGNOSED-PARKED.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md) +
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) (Bug2-14
RE-DIAGNOSED block + the new FIX-SEAM DESIGN). Per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md).

## State — audit counter = 0 (RESET). Two-phase audit CLOSED, HEALTHY both phases.

Batch audited: `8a5f6a2`..`b660d10` (Bug2-13 code `7e69e43` + the Bug2-14 re-diagnosis
slice, which shipped NO code). Phase A HEALTHY (`b660d10` — Bug2-13 both sites sound;
Bug2-14 re-diagnosis VERIFIED + scope SHARPENED to ALL embed-body sibling-refs, not just
comprehensions). Phase B HEALTHY (`80c16d7`). Tree clean, pushed (`b660d10..0deef2f`
landed `main -> main`; `80c16d7` is committed, push it on resume if not already).

## What Phase B did (this round)

- **TwoPassTests SPLIT — DONE inline (`0deef2f`).** Carved the contiguous Bug2-6..2-13 run
  (64 theorems) into `Kue/Tests/Bug2xTests.lean`; 2158 → 1500 lines. Pins CONSERVED 180 =
  116 + 64, no dup names; both files keep `--` line-comment headers + an end-of-file
  `#check` coverage tripwire. Build green (112 jobs), fixtures + shellcheck clean,
  cert-manager content-identical (jq -S = 0). Plan item 3 now DONE.
- **Eval.DefDeferral carve — DEFERRED (not scheduled).** Eval.lean 3989; ~511 under the
  ~4500 watch. Bug2-14's code lands in the core `mutual` block's `forceClosureWithConjunctCore`
  (UNSPLITTABLE), NOT the def-deferral tier, and grows Eval.lean only ~30–80 lines (~4069).
  Folding the carve into Bug2-14 would carve the WRONG tier. Trigger sharpened: carve
  `Eval.DefDeferral` only if a future def-deferral-tier slice crosses ~4500.
- **Bug2-14 FIX-SEAM DESIGN — written into `spec-conformance-audit.md`** (design only). The
  blueprint for the parked slice — read it before coding.
- **Perf-doc de-staled inline** — `kue-performance.md` said the blocker is "now Bug2-13"
  (STALE — LANDED `7e69e43`); corrected to Bug2-14 + the LANDED chain, wall ~54s.

## Next leader — Bug2-14 embed-merge fix (HIGH, on-path argocd; design in place)

The single on-path argocd blocker. Design is now concrete (audit doc, Bug2-14 FIX-SEAM
DESIGN block):

- **WHERE:** `forceClosureWithConjunctCore`'s `.structComp` arm (`Eval.lean:3587`+),
  right after the `mergeConjOperands` union (`:3627`–`:3641`), BEFORE `pushFrame canonical`
  (`:3643`) + `expandComprehensionsWithFuel` (`:3651`).
- **LEVER:** `remapConjRefs` (`:466`) — re-index the embed body's comprehension/let
  conjuncts' frame-local `.refId`s onto the post-merge `canonical` layout, keyed
  embed-local-layout → canonical-layout (frame-neutral pure remap). The defect is that
  `mergeConjOperands` unions the FIELD (`string & "X" = "X"`) but the comprehension's
  sibling-ref keeps the embed-local slot index → reads stale `string`.
- **SOUNDNESS:** re-base IFF the label is BOTH embed-declared AND host-narrowed.
  `remapConjRefs`'s not-in-`mergedMap` → identity already spares genuine embed-internal
  refs. Run under the embed's `capturedEnv` (its own package frame), never a use-site
  frame — the cross-pkg wrong-frame hazard (`crosspkg_defofdef_wrongframe_witness`).
- **CROSS-PKG def-of-def force path = the SAME fix, not a separate layer.** It is the
  WITNESS the re-base is needed: direct inline embeds drain only via export's accidental
  re-base; the force path skips that, exposing the gap. Verify witness (5) drains AFTER
  the re-base with no separate def-of-def change; if not, a 2nd layer is exposed → re-file.
- **MUST-PIN witnesses:** (1) comprehension form (argocd `#Mixin`); (2) PLAIN sibling-ref
  `host:{bk:"X",{bk:string,echo:bk}}` → `echo:"X"` (a comprehension-only fix MUST fail
  this); (3) embed-own-concrete stays drained; (4) host-only stays drained; (5) the 5-pkg
  def-of-def force-path repro (bare `ls` exports WITH `metadata.annotations`, `[ls]` does
  NOT bottom); (6) cert-manager byte-identical (the canary).
- TDD case D first (6-line inline, eval-level), then the 5-package force-path layer.
  Pin cert-manager content-identical at every step.

After Bug2-14 lands and argocd re-runs: if argocd EXPORTS, perf #7 un-gates (profile the
heavy `argo` sub-package then). If a further bug hides behind the sound drain, it surfaces
only then (honest — no "one fix away" over-claim).

## THE MILESTONE — argocd does NOT export yet

`kue export apps/argocd.cue` STILL bottoms (~54s, `conflicting values`). NOT a drop-in.
Standing Capabilities unchanged (cert-manager remains the only real-app drop-in). Perf #7
STAYS GATED. A fresh alpha is cadence-available but NOT notable (argocd does not export).

## Repro (reconstruct during the slice)

6-line inline "case D" (eval-level, no module): `host: {bk:"X", {bk:string, for k,v in
{p:1} {if bk=="X" {hit:true}}}}` → cue `{bk:"X",hit:true}`, kue leaves the `for` residual
UNDRAINED. PLAIN form: `host: {bk:"X", {bk:string, echo:bk}}` → cue `echo:"X"`, kue `_|_`.
5-package faithful at `/tmp/b214` (cue.mod `ex.com/b214`; `defs/` + `defs/parts/` +
`defaults/` + `main.cue`) — `kue export . -e bare` (= `ls`) drops `metadata.annotations`;
`-e wrapped` (= `[ls]`) → `conflicting values`; cue exports both with annotations. Mixin
source of truth (READ-ONLY):
`/Users/chakrit/Documents/prod9/infra-defs/parts/{mixin,use_cert_manager}.cue` +
`listener_set.cue`.

## Audit cadence

**Audit counter = 0 (reset).** Two-phase audit CLOSED this round. Next two-phase audit due
after the next 2–3 code slices, per `slice-loop.md` (A code-quality then B architecture,
sequential — do NOT invoke `/ace-audit`).

## Release state

`v0.1.0-alpha.20260622` was CUT. A fresh alpha is cadence-available, awaits user
greenlight — NOT notable (argocd does NOT export; cert-manager remains the only real-app
drop-in). CI/Actions banned; release = local `scripts/release.sh` + `release-linux.sh`.

## STANDING CONTEXT (full detail in CLAUDE.md + guides/slice-loop.md)

- Autonomy grant in effect; resolve forks by philosophy; commit/push on `main` (attended).
- Spec is authority; `cue` (`/Users/chakrit/go/bin/cue` v0.16.1) a fallible cross-check,
  never the gate. Correctness over byte-compat. kue binary: `.lake/build/bin/kue` (kue's
  own `eval` has NO `-e`; `kue export -e X` IS supported via the export path).
- prod9 (`/Users/chakrit/Documents/prod9/infra` + sibling `infra-defs` source) + cue
  caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on the main tree. argocd
  oracle = `kue export apps/argocd.cue` from the infra root.
- Orchestrator = thin re-spawner; one subagent per slice; per-slice duties: tests-first
  (line-comment headers + `#check` tripwire on any new/touched test module); log
  `cue-divergences.md`; flag `cue-spec-gaps.md`.
