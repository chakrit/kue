# START HERE — argocd LINKS 3 + 4 LANDED; next correctness blocker is link 5 (`packs.#Argo`)

Supersedes `2026-06-18-audit10-violations-cleared.md`. The slice `argocd-tlsroute-list-guard`
(plan backlog item 1) landed two correctness fixes — `defs.#TLSRoute` (link 3) AND
`defs.#ListenerSet` (link 4) now content-match cue. Build 86 jobs green, `fixture pairs ok`
(zero drift, existing fixtures byte-unchanged), shellcheck untouched. Pushed to `main`.

## What landed (the named target was mis-diagnosed — TWO distinct root causes, neither in list-guards)

The slice's named target (`#TLSRoute` list-element `if`-guards) ALREADY passed in isolation
(landed `3e0c84f`). Bisecting the REAL `defs.#TLSRoute`/`#ListenerSet` bottoms against cue found
two narrowing-timing bugs in the embedding-`Self` two-pass gate + the open-struct parser shape:

### Fix 1 (`Kue/Eval.lean`) — two-pass gate missed DEEP + LIST-COMPREHENSION self-refs

`refsSelfEmbeddedLabel` (the `needsEmbeddedSelfPass` gate) hard-matched `id.depth == 0` and
recursed into nested structs WITHOUT incrementing the depth — so a `Self.<embedded-label>` read
from a NESTED struct (`spec: { hostnames: Self.#hosts }`, depth 1) was invisible → Pass 2 never
fired → `.bottom`. It ALSO had no `.listComprehension` arm, so a list-comp source
(`[for h in Self.#hosts {…}]`) was unscanned → the comprehension iterated the un-narrowed (empty)
embedded field. Fix: thread `depth` (incremented on struct descents, mirroring `hasSelfRefAtDepth`),
match `id.depth == depth`, add a `.listComprehension` arm to BOTH `refsSelfEmbeddedLabel` and
`hasSelfRefAtDepth`. Fixed `#TLSRoute` (all 3 real cases content-match cue).

### Fix 2 (`Kue/Parse.lean`) — open struct (`...`) WITH embeddings split into a harmful `.conj`

`parsedFieldsValue` emitted `.conj [.structComp(embeds), .structTail(fields, tail)]` whenever a
struct had BOTH comprehensions/embeddings AND a `...` open marker. The two arms carry OVERLAPPING
fields; a `Self.<field>` self-ref landed in the `.structTail` arm, which never saw the embedding-
contributed fields → use-site narrowing collapsed to `.bottom`. The real `defs.#ListenerSet`
blocker (`parts.#Metadata` embedded + def-level `...`). Fix: keep ONE node — the comprehension
form already carries `open_ = true` (= the bare `...`/`.top` tail); a definition-context one is
closed by `normalizeDefinitionValueWithFuel` like any `.structComp`. Dropped the `.conj` split for
the comprehension/pattern case (plain-fields case keeps its `.structTail`).

### Tests
3 module fixtures (`testdata/modules/`): `open_embed_selfref_guard`, `listcomp_embed_selfref`,
`listcomp_embed_selfref_empty` (guard-false → empty). 8 `EvalTests.lean` pins (4 gate pins incl.
no-over-fire on a nested UNRELATED label, 3 source-level cue-exact behavior pins).

## REAL-APP VERDICT — argocd correct through LINK 4; next blocker LINK 5 (`packs.#Argo`)

Read-only oracle (prod9 `/Users/chakrit/Documents/prod9`, cue `/Users/chakrit/go/bin/cue`):
- **cert-manager: STILL content-identical to cue.** No correctness regression. (Timing ~92s,
  up from ~31s — see perf note below.)
- **argocd `defs.#Secret` (link 2): content-matches cue.** No regression.
- **argocd `defs.#TLSRoute` (link 3): content-correct vs cue** (basic, cross-ns gateway,
  listenerset — all 3, modulo field-order #3).
- **argocd `defs.#ListenerSet` (link 4): content-correct vs cue** (`rt`/`ls` resources match).
- **Full `kue export apps/argocd.cue` STILL bottoms — on LINK 5: `packs.#Argo`.** `packs.#Argo &
  {…}` bottoms in isolation (~36s, perf-wall-adjacent). Deeper root cause: nested `defs.#ArgoRepo`/
  `#ArgoProject`/`#ArgoApp` embeds each with their own `if Self.#x != _|_` guards + a `[...]` open
  list + many cross-`defs` embeds. **argocd is NOT a drop-in yet** — content-correct on the
  lightweight resources, blocked on the heavy `argo_.*.configs` sub-package.

## PERF REGRESSION (recorded, SOUND — ships per correctness-over-perf)

Both fixes raised eval cost: cert-manager ~31s→~92s, `#TLSRoute` ~4s→~9s, `#Secret` ~3s→~13s.
Cause: the parser collapse routes `{embed;…;...}` defs (the dominant prod9 `#Def` shape) through
the single-`.structComp` two-pass embed-re-eval path (more re-evaluation than the old `.conj`
split), and the gate fires on more/deeper refs. Byte-identical fixtures → SOUND, ships per
`docs/decisions/2026-06-18-correctness-over-performance.md`. Bumps backlog item 7 (per-eval-cost
perf) to MORE URGENT — more shapes now near the wall.

## NEXT STEP — link 5 `argocd-packs-argo` (plan backlog item 1, the live blocker)

Bisect `packs.#Argo` (cue cache `…/defs@v0.3.19/packs/argo.cue`) against cue. It embeds
`defs.#ArgoRepo`/`#ArgoProject`/`#ArgoApp` (each `Self={ … if Self.#x != _|_ {…} … }`). Distinct,
deeper than links 3/4 — likely a cross-`defs` nested-embed narrowing or the `[...]` list-open path.
While bisecting, distinguish "still bottoms" (correctness link 5) from "correct but slow" (the
per-eval perf wall, item 7 — `packs.#Argo` is ~36s). After link 5: truncate-primitive (item 2,
soundness hardening), regex/EvalOps extractions (3,4), field-ordering #3 (6), test-org (5).

## Standing context (durable, do not relearn)

- **prod9 real-app checkout:** `/Users/chakrit/Documents/prod9`. Module root `infra/`; apps
  `infra/apps/*.cue`; run `cue`/`kue` FROM `infra/`. defs pinned `prodigy9.co/defs@v0.3.19` in cue
  cache (`~/Library/Caches/cue/mod/extract/prodigy9.co/defs@v0.3.19/`). READ-ONLY (prod9 + cache:
  eval/probe/read only, NEVER mutate).
- **Bisect methods (reuse):**
  1. **Scratch external module** `/tmp/<x>/cue.mod/module.cue` = `module: "example.com/x"` +
     `language: version: "v0.16.1"` + `deps: "prodigy9.co/defs@v0": {v:"v0.3.19"}`, then
     `import "prodigy9.co/defs"` + `out: defs.#X & {…}`; `kue export -e out probe.cue` (seconds)
     vs `cue export -e out probe.cue --out json`. Resolves from the REAL cache.
  2. **Editable cache copy** for shape-bisecting an imported def: `cp -R …/defs@v0.3.19 /tmp/copy`,
     point a scratch module's `deps` at it via a project-local `_cache/mod/extract/…` dir AND set
     `CUE_CACHE_DIR=/tmp/copy_cache` (NOTE: kue's project-local `_cache` discovery diverged from the
     env-var path in one probe — prefer setting `CUE_CACHE_DIR` explicitly for reliable results).
     Then strip/edit files and re-run kue (cue keeps reading the REAL cache, so reason about cue
     for the reduced shape rather than oracle it directly).
  3. **`mini` clean package** (validated): a fresh `prodigy9.co/mini` module with the def + the
     minimal `parts.#Metadata`/`attr.#Hosts`/`attr.#ServiceRef` copied in (rewrite their internal
     `prodigy9.co/defs/attr` imports to `prodigy9.co/mini/attr`), driven via `CUE_CACHE_DIR`. Gives
     a clean, cue-matching minimal repro for `{embed; …; ...}`-shaped def bugs.
- **`fuel` is LOAD-BEARING** in `EvalKey`/`ForceKey`. A fuel-threaded helper that DROPS fields at
  `fuel=0` MUST bump `truncCount`; one that merely DECLINES need not. (This slice added no new
  `fuel=0` drop path — the depth/listComp changes are pure-predicate, `evalEmbeddingFieldsWithFuel`
  already bumps on its `fuel=0` arm.)
- **Two-pass gate (`needsEmbeddedSelfPass`) is PERF-LOAD-BEARING** — but its depth/listComp widening
  this slice is correctness-required (genuine nested/list-comp refs DO need Pass 2). The cost shows
  in the cert-manager regression; the fix for the cost is item 7 (frame-id sharing), NOT narrowing
  the gate.
- **Build/lake env:** elan has NO default toolchain; run `lake`/`scripts/check-fixtures.sh` FROM
  the repo root (`lean-toolchain` resolution is CWD-relative).
- **Release:** ~1 alpha/day, `scripts/release.sh` only — CI/Actions BANNED. Did NOT cut one.
  `git commit -F /tmp/msg`. NO working-tree-overwriting git. cue oracle: `/Users/chakrit/go/bin/cue`
  (v0.16.1). `evalFuel = 100` (`Kue/Eval.lean`).

## Two-phase audit DUE

This `argocd-tlsroute-list-guard` slice makes it 2 since the last audit (audit-#10 + this). The
two-phase audit (`docs/guides/slice-loop.md`; do NOT invoke `/ace-audit`) is at the 2–3-slice mark
— run before or interleaved with link 5. Code-quality audit should re-hunt: (1) the
`refsSelfEmbeddedLabel`/`hasSelfRefAtDepth` depth threading + `.listComprehension` arms — any OTHER
self-ref-scanning predicate (e.g. `defBodyHasSiblingSelfRef`, `bodyNeedsDefer`) that ALSO needs the
`.listComprehension` arm or depth fix to match? (2) the parser open-struct collapse — does dropping
the `.structTail` for the comprehension+tail case lose the open-tail's CONSTRAINT for any shape
(only `.top` tails are supported today, so the redundancy holds — but confirm if typed-ellipsis
lands). (3) the perf regression — is there a SOUND way to keep the single-node representation but
avoid the extra re-eval (e.g. skip Pass 2 when the augment is idempotent)? Phase B should weigh
whether the gate widening should be cached.
