# START HERE — argocd bisected; disjunction-selection + embedding-Self chain LINK 1 LANDED

Supersedes `2026-06-18-fuel-saturation-landed.md`. Commit `83a8ac4`, pushed. Build 86 jobs,
tests 40 jobs (8 new pins), fixtures byte-identical (+5 new export fixtures), shellcheck clean.

## What the argocd `bottom` actually WAS (the bisect verdict)

NOT either suspected borderline finding. Bisected the argocd-at-every-fuel `bottom` to its
first blocker `defs.#Secret`, minimized to a **fully OFFLINE single-file repro** (no
cross-package import) — so it is neither `module-file-scoped-imports` (needs siblings) nor
`import-eager-closedness` (needs an import). A **THIRD distinct gap**: the disjunction-selection
+ embedding-`Self` family. Both filed borderline findings stand as filed (real, but argocd does
NOT hit them).

## What landed (`83a8ac4`) — one family, three facets

1. **`selectEvaluatedField` `.disj` case.** Selecting a field INTO a disjunction collapses the
   default arm first (`resolveDisjDefault?`), then selects. Was: no `.disj` case → `.bottom`.
   Non-default multi-arm disjunction stays a deferred `.selector` (no over-fire).
2. **`resolveEmbeddedDisjDefault` at the embedding-merge sites** (`meetEmbeddingsWithFuel` +
   `evalEmbeddingFieldsWithFuel`): an embedded default disjunction collapses to its arm before
   merging, so its fields become regular host fields; non-default passes through.
3. **Gated two-pass for `Self.<embedded-label>`** in BOTH the eager `.structComp` arm and
   `forceClosureWithConjunctCore` (the `#Secret` def-ref path): re-evaluate static fields
   against a frame augmented with embedded labels. **Gated by `needsEmbeddedSelfPass`**
   (`refsSelfEmbeddedLabel` scan) — fires ONLY when a static field actually selects
   `Self.<new-embedded-label>`. Un-gated cost cert-manager 2x (~59s); gated restored ~29s.

## REAL-APP VERDICT (the headline) — argocd is NOT a drop-in yet (chain, not one gap)

- **cert-manager: STILL a drop-in, NO regression.** `jq -S` identical to cue, ~29s.
- **`#Secret` structure now CORRECT** vs cue (apiVersion/kind/type:"Opaque"/metadata). This
  was the FIRST chain link. **TWO further DEEP correctness links remain** + a perf wall:
  - **`argocd-secret-data` (NEXT correctness link).** `for k,v in Self.#data` in the embedded
    default arm runs against the arm's EMPTY `#data` before the use-site narrowing reaches it
    → secret `data:{}` vs cue's payload. Repro `w3`: `_#A: {#k:"a", #data:[string]:string,
    out:{for k,v in Self.#data {"\(k)":v}}}` + `_#B:{#k:"b",out:{}}` + `#S:{#data:[string]:
    string; (*_#A|_#B)}` + `out: #S & {#data: foo:"bar"}` → kue `out:{}`, cue `out:{foo:"bar"}`.
    Narrowing must flow INTO the embedded default arm before its comprehension expands —
    default-disjunction-arm analog of the slice-A/E closure-narrowing work.
  - **`argocd-tlsroute-list-guard` (DEEP).** Repro `lr`: `#R: Self={ #g?:string; #l?:string;
    spec: refs: [if Self.#g != _|_ {{name:Self.#g}}, if Self.#l != _|_ {{kind:"LS",
    name:Self.#l}}] }` + `out: #R & {#g:"nginx", #l:"argocd-ls"}` → kue bottom, cue resolves.
    List-element `if`-guards over Self-narrowed hidden fields.
  - **`argo` sub-package perf wall.** Full `kue export apps/argocd.cue` now evals PAST the
    early bottom (the fixes unblock it) and times out >200s on the heavy
    `argo_.{stage9,bluepages,ircp,tmg,sunzapper}.configs` (was 95s-to-bottom). Perf frontier.

## EXACT next step

Per plan F-B5 item 1: **`argocd-secret-data`** is the next correctness link (repro `w3`
above). Root: at `resolveEmbeddedDisjDefault` we pick the ALREADY-EVALUATED default arm,
which expanded its `for`/comprehension against its own `#data` before the use-site narrowing
unified in. Fix direction: the use-site hidden-field narrowing (`hiddenFieldsOnly`, the same
splice `meetEmbeddingsWithFuel` uses for closures) must reach the default arm BEFORE its
comprehension expands — i.e. force/re-expand the default arm WITH the host's narrowing, not
pick a pre-narrowed value. Likely touches the disjunction-arm evaluation in
`meetEmbeddingsWithFuel`/`evalValueCoreWithFuel`'s `.disj` arm. Then `argocd-tlsroute-list-
guard`, then the `argo` perf wall. After that re-probe full argocd for drop-in.

## How to bisect prod9 apps (the method that worked — reuse it)

Per-key `-e` selection on the full app is too slow (~95s full eval) and the path parser
mangles quoted dotted keys. Instead: scratch module in `/tmp/argobi/` with `cue.mod/module.cue`
= `module: "example.com/argobi"` + `deps: "prodigy9.co/defs@v0": {v:"v0.3.19"}`, then one CUE
file per shape `import "prodigy9.co/defs"` and `out: defs.#X & {…}`; run `kue export -e out`
(seconds) vs `cue export -e out --out json`. defs extracted at
`~/Library/Caches/cue/mod/extract/prodigy9.co/defs@v0.3.19` (READ-ONLY). Then minimize each
failing shape to self-contained single-file CUE (no import) to classify the gap.

## Standing context (durable, do not relearn)

- **prod9 real-app checkout:** `/Users/chakrit/Documents/prod9`. Module root `infra/`; apps
  `infra/apps/*.cue`. defs pinned `prodigy9.co/defs@v0.3.19` in cue cache. READ-ONLY (prod9
  + cue cache: eval/probe/read only, NEVER mutate).
- **`fuel` is LOAD-BEARING** in `EvalKey`/`ForceKey` (263 truncation cases). `satCache`/`SatKey`
  are fuel-FREE but ONLY hold SATURATED results; `truncCount` drives the classification (six
  bump sites — a SEVENTH fuel-threaded helper that drops fields must bump it too).
- **Two-pass gate (`needsEmbeddedSelfPass`) is PERF-LOAD-BEARING.** It keeps cert-manager
  single-pass (~29s). Un-gating it is a 2x regression. Any change to the embedding-Self path
  must keep the gate tight (fires only on a genuine `Self.<embedded-label>` selection).
- **Audit cadence:** disjsel-chain is 1 slice since the last Phase-A/B (`e282124`). The
  two-phase audit (`docs/guides/slice-loop.md`; do NOT invoke `/ace-audit`) is due at the
  2–3-slice mark — interleave after `argocd-secret-data` or the next link. It should re-hunt
  the new two-pass + `resolveEmbeddedDisjDefault` for over-fire / fixture-drift latency and
  the satCache cross-fuel false-share.
- **Profiling:** prof harness removed; re-add a fuel-parameterized driver if needed, use the
  COMPILED binary. `evalFuel = 100` (`Kue/Eval.lean`); cert-manager converges at 16.
- **Release:** ~1 alpha/day, `scripts/release.sh` only — CI/Actions BANNED. Did NOT cut one.
  `git commit -F /tmp/msg`. NO working-tree-overwriting git. cue oracle: `/Users/chakrit/go/bin/cue`
  (v0.16.1; fixtures match).
