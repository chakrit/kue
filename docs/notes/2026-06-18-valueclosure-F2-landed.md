# RESUME HERE — F2 `structcomp-force-comprehension-loss` landed (2026-06-18)

START-HERE pointer; supersedes `2026-06-18-valueclosure-sliceE-landed.md`. Tree clean, pushed to
`gh:main`. F2 (the re-scoped B', corrected by Phase-A audit `db5ee90`) is done. **The cert-manager
error has moved PAST F2 to a DISTINCT pre-existing bug — that is the LIVE next slice.**

## What just landed (F2)

A deferred-then-forced `.structComp` def silently DROPPED its `if`/`for` comprehensions — the
force arm meet-folded only embeddings and never expanded the conditional/loop comprehensions. Fixed
the two stated sites PLUS three same-class deeper sites that the real-app path exposed:

1. **Force arm (`forceClosureWithConjunct` `.structComp`).** Added `expandComprehensionsWithFuel`
   over the post-splice frame + `staticFields ++ expanded` (mirrors the eager arm), and folded the
   expanded labels into the closedness allow-set (`closeEmbeddedOver (defFields ++ expanded) …`).
   Headline: `#M: {#x:int, if #x>0 {y:#x}}` + `#M & {#x:5}` → `{y:5}` cue-exact (was `{}`).
2. **Non-def lazy-merge (site 2).** `M & {x:5}` for a REGULAR comprehension struct dropped the
   guard too. Relaxed the `refDefClosureBody?` gate to defer a NON-def `.structComp` self-ref body
   (left UNCLOSED — open closedness preserved).
3. **Embed-chain deferral (`bodyNeedsDefer`, env-aware recursive gate).** `Outer: {#Inner}` where
   `#Inner` carries a guard is NOT a self-ref of `Outer`, so the direct check missed it → collapse.
   New gate resolves each embedding (`resolveEmbedDefBody?`) and recurses; wired into
   `refDefClosureBody?` + `importDefClosureBody?` with the right placeholder-frame env.
4. **Conditional-embed-label closedness.** `evalEmbeddingFieldsWithFuel` now forces embed-closures
   WITH the host narrowing so a CONDITIONAL embed label (`ports` from `if #port>0`) surfaces in the
   allow-set — else the host rejected the field the embed-meet actually produced → spurious bottom.
5. **Standalone-selector-force leak.** `pkg.#Def` selected OUTSIDE a conjunction (`out:
   attr.#Ports`, or `{attr.#Ports}` with no narrowing) emitted a bare `.closure` never forced →
   leaked `incomplete`. Now the selector arm FORCES standalone (mirrors `.refId`); the `.conj` fold
   re-produces the closure from the RAW selector (`importSelectorDef?` + in-monad `pushFrame`) for
   the met case, and both embed-meet sites defer selector embeddings the same way.

### Tests

4 new `native_decide` pins (`f2_force_structcomp_guard_fires_post_meet` [headline],
`…_does_not_fire`, `f2_body_needs_defer_through_embed`, `…_skips_plain_embed`); 2 slice-3 producer
pins UPDATED for the new standalone-force. Committed `testdata/modules/structcomp_force_guard/`
(forced cross-pkg def with BOTH `if`-guard AND `for`-comprehension — JSON+YAML byte-identical to
cue) and `structcomp_lazymerge_guard/` (site 2, non-def). Zero existing-fixture drift (an
`embed_chain_selfalias` regression was caught mid-slice via `check-fixtures.sh` and fixed by
deferring selector embeddings).

## REAL-APP VERDICT (the headline — read-only prod9, cue v0.16.1) — HONEST

- **F2 is cue-exact on every targeted shape** (12-case matrix: force-def guard fire/not-fire, `for`
  in a forced def, non-def lazy-merge, embed-in-def-met-at-use, standalone selector). Verified.
- **cert-manager (~11s) and argocd (~54s) STILL return `bottom`.** The F2 comprehension loss is
  genuinely fixed; the error has moved PAST it to a **DISTINCT, PRE-EXISTING** bug (reproduced on
  the HEAD `db5ee90` binary — NOT a regression from F2). The long timings are the unchanged perf
  wall (downstream, unreachable while apps error).

## NEXT SLICE: `closure-import-selector-alias` (CORRECTNESS, the live cert-manager blocker)

A def whose VALUE is an import-selector — or a multi-member package where two defs reference the
same import — does NOT defer its body to a closure, so the use-site narrowing arrives after the
self-ref collapses. **Clean minimal repro (rebuild in `/tmp`, no registry):**

- package `parts` with `#M: {#name: string, name: #name}`; package `defs` with `#A: parts.#M`
  (def aliased DIRECTLY to the selector, NO embed braces); `out: defs.#A & {#name: "n"}`
  → kue `incomplete value: string`, cue `{name: "n"}`.
- Sibling-poison facet: `#ClusterIssuer` (embed form) resolves ALONE, but adding ANY `#Foo` that
  references the `parts` import (alias `#Foo: parts.#X` OR embed `#Foo: {parts.#X}`) collapses the
  otherwise-resolving `#ClusterIssuer` → bottom. So the trigger is "a second package-member
  referencing the shared import binding," and/or "a def aliased to an import selector."

**It is NOT a cache collision** — a cache-bypass build still bottoms (deterministic eval
contamination), confirming the Phase-A audit's call. Likely locus: the `.selector (.refId id)
label` producer + `importDefClosureBody?` gating, OR how a def-aliased-to-selector is reduced in
the `.conj`/`.refId` path (the alias `#A: parts.#M` resolves through TWO import-indirection levels;
the deferral never fires). Diagnose: trace `defs.#A & {#name}` — where does the `name: #name`
self-ref collapse before the splice. After this lands, re-probe cert-manager; if it exports,
frontier moves to **B `closure-perf`** (frame-id sharing — the ~11s/~54s wall). F1 default-mark
algebra is orthogonal and can interleave.

## Standing context (durable, do not relearn)

- **prod9 real-app checkout:** `/Users/chakrit/Documents/prod9` (NOT `~/prod9`). Module root
  `infra/`; apps under `infra/apps/`. defs pinned `prodigy9.co/defs@v0.3.19` in the cue cache
  `~/Library/Caches/cue/mod/extract/prodigy9.co/defs@v0.3.19/`. READ-ONLY. **Never leave scratch
  files in prod9.**
- **Fast offline repro of the real package:** copy the real `defs`/`parts`/`attr`/`packs` dirs
  from the cache into a `/tmp` module, `sed`-rewrite `prodigy9.co/defs/<sub>` import paths to a
  local module path (e.g. `ex.com/cm/<sub>`). Runs in <1s, no registry, no perf wall (the perf
  wall is downstream of the bottom). Bisect by deleting files (use pipe-free globs — the lowfat
  filter mangles `ls | while`).
- **The cert-manager trigger** reduces to `#A: parts.#M` (alias-to-selector) — the cleanest probe.
  The real `attr/ports.cue` (`#port?:int; #ports:[...int]; if #port != _|_ {#ports:[#port]}`) and
  `parts/pod_controller.cue` (embeds `attr.#Ports`) are the in-vivo carriers, but the bug is the
  selector-deferral, not anything `attr.#Ports`-specific (its presence just adds a second
  parts-referencing member).
- **`fuel` is LOAD-BEARING** in `EvalKey`; closure-force / meet-embeddings is fuel-bounded.
- **Release:** ~1 datestamped alpha/day, `scripts/release.sh` only — CI/Actions BANNED. Did NOT cut
  a release. **Safety:** prod9 + cue cache READ-ONLY. `git commit -F /tmp/msg` (bash filter mangles
  piped git input). NO `git checkout`/`restore`/`reset --hard`. cue oracle: `/Users/chakrit/go/bin/cue`
  v0.16.1.

## Audit cadence

Slices 3, 4, A, C, E, **F2** landed since the last Phase-A/B pass; the audit covering A-C-E was
DUE before F2 and is now overdue. F2 is medium-large (5 coupled fixes, behavior-additive, zero
fixture drift). A two-phase audit per `docs/guides/slice-loop.md` is DUE (do NOT invoke
`/ace-audit`; follow the guide) — covering A-C-E-F2. Don't let it stall the next correctness slice.
