# START HERE — argocd-secret-data (LINK 2) LANDED; next correctness link is link 3 (TLSRoute)

Supersedes `2026-06-18-list-comprehension-parse-eval-landed.md`. Commits `502550f` (sub-slice 1)
+ `2ef055d` (sub-slice 2), both pushed to `main`. Build 86 jobs green, fixtures byte-identical
(+7 new export pairs), shellcheck clean.

## What landed — the argocd link-2 blocker, in two sub-slices

The argocd `bottom` link 2 (`defs.#Secret`'s `data` came out `{}`/bottom instead of the
populated base64 map). Split into two distinct root causes:

### Sub-slice 1 (`502550f`) — parser misclassified `_#x` as hidden-only

Root: `Parse.lean parseFieldClass` treated the field-name axes as MUTUALLY EXCLUSIVE
(`isHidden := !isDefinition && startsWith "_"`), so `_#x` (a HIDDEN DEFINITION in CUE) was
tagged hidden-ONLY, dropping its definition-ness. The def-deferral path
(`refDefClosureBody?`/`conjDefClosure?`) gates on `isDefinition`, so a `_#x` embedding never
deferred to a closure and evaluated STANDALONE — collapsing its sibling self-ref before the
use-site narrowing spliced in. Fix: `isDefinition := startsWith "#" || startsWith "_#"`;
`isHidden := startsWith "_"`. The `FieldClass` model already had orthogonal axes. Also corrected
a latent gap with the same root: `_#C` is now correctly CLOSED (rejects undeclared fields).

### Sub-slice 2 (`2ef055d`) — embedded DEFAULT DISJUNCTION arms collapsed before narrowing

The actual `#Secret` puts `_#OpaqueSecret` in an embedded default disjunction arm
`(*_#OpaqueSecret | _#DockerConfigSecret | _#TLSSecret)`. A disjunction's arms evaluate EAGERLY,
so the default arm (a deferrable def after ss1) was forced standalone with NO use-operands. Fix —
distribute the narrowing into the arms at the UNEVALUATED level:
- **`.conj` fold:** extracted `evalConjStandard`; the `.conj` arm first tries disjunction
  distribution (`splitDisjConjunct`/`conjDisjArms?`) → `*(_#A & narrow) | (_#B & narrow)`, each
  arm-meet re-entering the fold so post-ss1 def-deferral force-splices.
- **`meetEmbeddingsWithFuel`:** collapse to the default arm (`conjDisjArms?` + `resolveDisjDefault?`)
  BEFORE deferral, so the arm force-splices the host's narrowing (not `resolveEmbeddedDisjDefault`'s
  collapsed value).
- **`resolveEmbedDefBody?`/`bodyNeedsDefer`:** added a `.disj` case so a struct embedding
  `(*_#A|_#B)` defers when the default arm needs it.
Gated tight: a plain scalar/struct disjunction is NOT deferred (no over-defer).

### Tests
7 new export fixtures (4 ss1 `embed_hidden_def_*`/`hidden_def_closed`, 3 ss2 `embed_disj_default_*`),
each cue v0.16.1-exact JSON+YAML. 3 parser-classification pins (per-axis truth table) + 12 eval
pins (ss1: comprehension/sibling narrows, empty-narrow, hidden-def closedness, no-over-defer plain
`#Base`, concrete-source eager; ss2: same set through the disjunction + no-over-defer scalar/struct
+ `conjDisjArms?` fuel-zero saturation guard — declines to distribute, not a truncation source).

## REAL-APP VERDICT — argocd LINK 2 CLEARED; next blocker is LINK 3

- **cert-manager: NO regression.** Content-identical to cue (`jq -S`), ~29s single-pass.
- **`defs.#Secret` with `#data` now evals CORRECTLY** (populated base64 `data`, content-identical
  to cue modulo field-order #3, ~3s in the scratch module). `argo_secret` (the live argocd secret
  with `webhook.github.secret`) matches cue. The argocd link-2 correctness gap is CLOSED.
- **Full `kue export apps/argocd.cue` STILL bottoms (~94s) — but on LINK 3, NOT link 2.**
  Bisected to `defs.#TLSRoute` (`route.yaml`/`listener.yaml`): `spec.parentRefs` is a list whose
  elements are `if Self.#gateway_name != _|_ {…}` guards over use-site-narrowed hidden fields →
  kue bottom (~3s, fast-failing in isolation), cue resolves both. This is the tracked
  `argocd-tlsroute-list-guard` (link 3). The `argo` sub-package perf wall remains beyond it.
  argocd is NOT a drop-in yet.

## NEXT STEP — link 3 `argocd-tlsroute-list-guard` (next correctness link)

`#TLSRoute.spec.parentRefs` is a LIST of `if Self.#x != _|_ {…}` elements over use-site-narrowed
hidden fields. The list-comprehension PARSE+EVAL surface (slice `list-comprehension-parse-eval`)
and the def-deferral machinery (this slice) are both in place; what's missing is the SAME
narrowing-before-guard-eval discipline applied to LIST-element `if` guards inside a force-spliced
def (the list analog of sub-slice 2's struct-comprehension fix). Minimal repro against the real
defs (scratch module method below): `defs.#TLSRoute & {#gateway_name:"nginx", #listenerset_name:
"argocd-ls", …}` → kue bottom, cue full parentRefs. Self-contained repro: `#R: Self={ #g?:string;
#l?:string; spec: refs: [if Self.#g != _|_ {{name:Self.#g}}, if Self.#l != _|_ {{kind:"LS",
name:Self.#l}}] }` + `out: #R & {#g:"nginx", #l:"argocd-ls"}`.

Other parked items (unchanged backlog): `truncate-primitive` (F-B1, owed soundness hardening),
regex extraction (R3), EvalOps extraction (R1), field-ordering parity #3, test-org pass, per-eval
perf (the argo sub-package wall).

## Two-phase audit DUE

This makes 3 slices since the last Phase-A/B (`e282124`): disjsel-chain (link 1),
list-comprehension-parse-eval, and this `argocd-secret-data` (2 sub-slices). The two-phase audit
(`docs/guides/slice-loop.md`; do NOT invoke `/ace-audit`) is at the 2–3-slice mark — run it before
or interleaved with link 3. **A code-quality audit should re-hunt:** (1) the new `conjDisjArms?` /
`splitDisjConjunct` / `evalConjStandard` extraction for over-fire (does a non-default disjunction
ever wrongly distribute?) and termination-measure soundness (`evalConjStandard` at `(fuel,6,0)`);
(2) the `resolveEmbedDefBody?` `.disj` one-level recursion (does it miss a nested
disjunction-of-disjunction default arm?); (3) the parser `_#x` classification's blast radius
(any path that ASSUMED `isDefinition`/`isHidden` mutually exclusive?). **Phase B** should check the
new conj-fold split against the module graph and whether `evalConjStandard` should fold back inline.

## Standing context (durable, do not relearn)

- **prod9 real-app checkout:** `/Users/chakrit/Documents/prod9`. Module root `infra/`; apps
  `infra/apps/*.cue`; run `cue`/`kue` FROM `infra/` (needs `cue.mod`). defs pinned
  `prodigy9.co/defs@v0.3.19` in cue cache. READ-ONLY (prod9 + cue cache: eval/probe/read only,
  NEVER mutate).
- **Bisect method (reuse it):** scratch module `/tmp/argobi2/cue.mod/module.cue` =
  `module: "example.com/argobi2"` + `language: version: "v0.16.1"` + `deps: "prodigy9.co/defs@v0":
  {v:"v0.3.19"}`, then `import "prodigy9.co/defs"` + `out: defs.#X & {…}`; `kue export -e out`
  (seconds) vs `cue export -e out --out json`. The `-e` path parser mangles QUOTED DOTTED keys
  (`argocd."route.yaml"`) — use the scratch module per-shape instead of `-e` on the full app.
  `defaults`/`apps/argo` are IN-MODULE (`prodigy9.co`), not external deps — can't import in a
  scratch external module; copy their `.cue` sources into the scratch tree (read prod9, write /tmp)
  if needed.
- **`fuel` is LOAD-BEARING** in `EvalKey`/`ForceKey` (263 truncation cases). `satCache`/`SatKey`
  are fuel-FREE but ONLY hold SATURATED results; `truncCount` drives classification. A new
  fuel-threaded helper that DROPS fields at `fuel=0` MUST bump `truncCount`; one that merely
  DECLINES (`conjDisjArms?` → `none`) need not (it falls to the standard bracketed path).
- **Two-pass gate (`needsEmbeddedSelfPass`) is PERF-LOAD-BEARING.** Keeps cert-manager
  single-pass (~29s). Un-gating is a 2x regression.
- **Release:** ~1 alpha/day, `scripts/release.sh` only — CI/Actions BANNED. Did NOT cut one.
  `git commit -F /tmp/msg`. NO working-tree-overwriting git. cue oracle:
  `/Users/chakrit/go/bin/cue` (v0.16.1; fixtures match). `evalFuel = 100` (`Kue/Eval.lean`).
