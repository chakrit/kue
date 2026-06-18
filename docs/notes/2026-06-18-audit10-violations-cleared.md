# START HERE — audit-#10 BOTH HIGH Violations CLEARED; next correctness link is link 3 (TLSRoute)

Supersedes `2026-06-18-argocd-secret-data-landed.md`. Commits `52b64dc` (V1) + `b2b558f` (V2),
both pushed to `main`. Build 86 jobs green, `fixture pairs ok` (zero drift, existing fixtures
byte-unchanged), shellcheck untouched (no script changes).

## What landed — the two audit-#10 HIGH Violations (both wrong VALUES on basic shapes)

### V1 (`52b64dc`) — `scalar-embed-collapse-provenance`

The `{5}`→`5` collapse lived in `meet` (`collapsesToScalarEmbed`, Lattice `.struct fields _,
listLike` arms). At meet time `{}` is indistinguishable from `{5}`'s residual `.struct []`, so it
wrongly absorbed ANY scalar an empty/decl-free struct met: `{} & 5` → `5`, `5 & {}` → `5`,
`{} & "s"` → `"s"`, `true & {}` → `true`, `out:{}` + `out:5` → `5` (cue: conflict in every case).

Fix: moved the collapse INTO `meetEmbeddingsWithFuel` (embed-eval, Eval.lean ~2181), where the
host is KNOWN to embed a scalar — collapse only when output-free + decl-free
(`collapsesToScalarEmbed`) and the embedding resolved to a terminal scalar. Lattice meet arms
revert to `meetCore` (→ `.struct .., _ => .bottom`), restoring the cue conflict. List comprehensions
(`[{x} for…]`) and `{5}`/`{5,5}`/`{5,6}` go through the SAME `.structComp`→`meetEmbeddingsWithFuel`
path → preserved. The LOW borderline `{#a:1, 5}` still bottoms (NOT widened — that is the unsound
direction; stays the OPEN `scalar-embed-with-decls` item).

### V2 (`b2b558f`) — `embed-disj-arm-fallthrough`

`meetEmbeddingsWithFuel` collapsed an embedded default disjunction to its default arm BEFORE the
host narrowing, with no fall-through when the narrowing KILLED the default:
`(*_#A{v:int}|_#B{v:string})` met with `{v:"s"}` → kue bottom, cue `{kind:"b",v:"s"}`.

TWO manifestations, both fixed by DISTRIBUTE-into-every-arm + prune-bottoms via `normalizeDisj`
(NOT `normalizeEvaluatedDisj`, which does not prune):
1. `conjDisjArms?` path (deferral-needing arms — argocd `#OpaqueSecret`): per-arm sub-fold
   `meetEmbeddingsWithFuel current [arm]` at a dropped fuel tier, then `normalizeDisj`.
2. PLAIN `.disj`-embedding path (the plan's repro — arms with no sibling self-ref, so
   `conjDisjArms?` DECLINES): meet OPENED host into each arm, then `normalizeDisj`.
   **Note: the plan described path 1, but the repro actually hits path 2.** Both needed fixing.

Residual now kept `*{default} | {other}` (faithful CUE); manifest picks the default, cue-exact.

## Tests

V1: 5 pins (empty/decl-free struct ∩ int/string/bool conflicts, both meet orders, `out:{}`+`out:5`).
V2: 4 pins (dead-default fall-through, live-default kept, all-die conflict, single-arm) + 3 existing
ss2 pins updated to the distributed residual (their manifested JSON is byte-unchanged + cue-exact;
only the internal `.disj` residual string differs). All in `Kue/Tests/EvalTests.lean`.

## REAL-APP RE-PROBE — no regression; argocd blocker still link 3

- **cert-manager: content-identical to cue** (`jq -S`), ~31s. No regression.
- **argocd link-2 `defs.#Secret`: `data` populated base64, content-identical to cue.** The 3-arm
  embedded disjunction still resolves to the `_#OpaqueSecret` default after V2's distribution.
- **Full argocd export STILL bottoms (~99s) on LINK 3, NOT link 2.** `defs.#TLSRoute` bottoms in
  isolation (~4s) — the tracked `argocd-tlsroute-list-guard`. Pre-existing, NOT a V1/V2 regression.

## NEXT STEP — link 3 `argocd-tlsroute-list-guard` (the live correctness blocker, capability ready)

`#TLSRoute.spec.parentRefs` is a LIST of `if Self.#x != _|_ {…}` elements over use-site-narrowed
hidden fields. The list-comp parse+eval surface and the def-deferral machinery are in place; what's
missing is the SAME narrowing-before-guard-eval discipline applied to LIST-element `if` guards
inside a force-spliced def (the list analog of the struct-comprehension fix). The minimal
SELF-CONTAINED repro now PASSES in kue (matches cue):
`#R: Self={#g?:string; #l?:string; spec: refs: [if Self.#g != _|_ {{name:Self.#g}}, if Self.#l != _|_
{{kind:"LS",name:Self.#l}}]}` + `out: #R & {#g:"nginx", #l:"argocd-ls"}` → both give the full refs.
So the real `defs.#TLSRoute` bottom is from ADDITIONAL structure beyond the minimal shape — bisect
the real def (scratch-module method below) to find what the minimal repro is missing.

Other parked backlog (unchanged): `scalar-embed-with-decls` (LOW — `{#a:1,5}`→`5`, needs a scalar
carrier for selectable decls), `truncate-primitive` (F-B1 soundness hardening), regex extraction
(R3), EvalOps extraction (R1), field-ordering parity #3, test-org pass, per-eval perf (argo
sub-package wall).

## Two-phase audit DUE

This makes 2 slices since the audit-#10 plan entry (the audit itself committed no code beyond the
plan). The two-phase audit (`docs/guides/slice-loop.md`; do NOT invoke `/ace-audit`) is at the
2–3-slice mark — run before or interleaved with link 3. A code-quality audit should re-hunt: (1)
the V2 per-arm sub-fold for termination soundness (`meetEmbeddingsWithFuel nextFuel … [arm]` drops
a fuel tier — verify the saturation/`truncCount` invariant: a `fuel=0` arm sub-fold bumps
`truncCount`, which is correct honesty) and over-distribute (does a non-default disjunction with no
unique winner now distribute where it should stay deferred?); (2) the V1 collapse move — any OTHER
caller that relied on the Lattice meet-arm collapse (grep showed only `meetEmbeddingsWithFuel` uses
`collapsesToScalarEmbed` now); (3) `resolveEmbeddedDisjDefault` at Eval.lean:2093 (`evalEmbeddingFieldsWithFuel`
pass-1 label surfacing) — does it ALSO need distribution, or is label-surfacing-only correct there?

## Standing context (durable, do not relearn)

- **prod9 real-app checkout:** `/Users/chakrit/Documents/prod9`. Module root `infra/`; apps
  `infra/apps/*.cue`; run `cue`/`kue` FROM `infra/`. defs pinned `prodigy9.co/defs@v0.3.19` in cue
  cache. READ-ONLY (prod9 + cue cache: eval/probe/read only, NEVER mutate).
- **Bisect method:** scratch module `/tmp/argobi2/cue.mod/module.cue` = `module:
  "example.com/argobi2"` + `language: version: "v0.16.1"` + `deps: "prodigy9.co/defs@v0": {v:"v0.3.19"}`,
  then `import "prodigy9.co/defs"` + `out: defs.#X & {…}`; `kue export -e out probe.cue` (seconds)
  vs `cue export -e out probe.cue --out json`. The `-e` path parser mangles QUOTED DOTTED keys —
  use the scratch module per-shape, not `-e` on the full app. `defaults`/`apps/argo` are IN-MODULE
  (`prodigy9.co`), not external deps — copy their `.cue` into the scratch tree if needed.
- **`fuel` is LOAD-BEARING** in `EvalKey`/`ForceKey`. A fuel-threaded helper that DROPS fields at
  `fuel=0` MUST bump `truncCount`; one that merely DECLINES (`conjDisjArms?`→`none`) need not.
- **Two-pass gate (`needsEmbeddedSelfPass`) is PERF-LOAD-BEARING** (keeps cert-manager single-pass
  ~29-31s). Un-gating is a 2x regression.
- **Build/lake env:** elan has NO default toolchain configured; `lake`/`lake env lean` resolve the
  toolchain from the CWD's `lean-toolchain`, so run them FROM the repo root (`scripts/check-fixtures.sh`
  uses absolute `repo_root` paths but does NOT cd — invoke it with cwd = repo root).
- **Release:** ~1 alpha/day, `scripts/release.sh` only — CI/Actions BANNED. Did NOT cut one.
  `git commit -F /tmp/msg`. NO working-tree-overwriting git. cue oracle: `/Users/chakrit/go/bin/cue`
  (v0.16.1). `evalFuel = 100`, `meetFuel`/`formatFuel` constants in `Kue/Eval.lean`.
