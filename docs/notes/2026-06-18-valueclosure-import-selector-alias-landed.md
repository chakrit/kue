# RESUME HERE — `closure-import-selector-alias` landed (2026-06-18)

START-HERE pointer; supersedes `2026-06-18-valueclosure-F2-landed.md`. Tree clean, pushed to
`gh:main`. **The cert-manager CORRECTNESS blocker is FIXED. The frontier is now PERF (B
`closure-perf`)** — cert-manager no longer bottoms, it now exceeds the perf wall.

## What just landed (two distinct sub-fixes, two commits)

Root-causing the slice split into TWO genuinely distinct bugs:

### Sub-fix 1 (`8f0c89e`) — alias-to-import-selector deferral

A def whose body IS an import selector (`#A: parts.#M`) or embeds one (`#A: {parts.#M}`) did not
defer through the package indirection: the producers detected only a DIRECT struct body needing
deferral, so an alias whose body is a `.selector` fell to the eager path and resolved `parts.#M` in
the `defs` frame BEFORE the use-site `& {#name}` narrowed → `name: #name` collapsed to `string`
(kue `incomplete value: string`, cue `{name: "n"}`). **Fix:** `followAliasDefBody?` (Eval.lean)
follows the selector/ref chain (fuel-bounded vs cyclic aliases) to the terminal struct body AND the
package frame it captures (`parts`, not `defs`); `importDefClosureBody?` gained an alias-follow
fallthrough; new `refAliasDefClosure?`/`refAliasSelectorDef?` thread the terminal frame into the
`.conj` closure splice and the `.refId` standalone-force arm. 6 native_decide pins + 3 module
fixtures (`alias_import_selector`, `_embed`, `_chain`).

### Sub-fix 2 (THIS commit) — duplicate import-binding meet-collision (the REAL blocker)

Bisecting the offline real-package repro proved the isolated `#ClusterIssuer` is cue-exact; the
bottom came from the FULL `defs` package, narrowed to **a SECOND file in the `parts` package
importing `attr`** (`parts/pod_controller.cue` alongside `parts/metadata.cue`, both `import attr`).
`bindImports` bound each file's imports per-file, then `mergeSourceValues` `meet`-folded the
siblings — two files importing `attr` ⇒ the merged package carried the `attr` hidden label TWICE,
and `meet`-ing two independently-loaded copies of the package corrupted the binding → bottom.
**Fix (Module.lean):** defer binding to the package level — `parseAndBindFiles` returns RAW bodies +
the combined binding set; `loadPackage` merges bodies then `bindImports (dedupeBindings bindings)`
ONCE. `dedupeBindings` keeps the first binding per name. 2 native_decide pins + module fixture
`dup_import_binding`.

## REAL-APP VERDICT (the headline — read-only prod9, cue v0.16.1) — HONEST

**Correctness COMPLETE for this blocker; frontier = PERF.**
- A faithful BOUNDED offline repro with the EXACT duplicate-import trigger feeding `#ClusterIssuer`
  is now BYTE-EQUAL to `cue`. The bottom is gone.
- The FULL real `cert-manager.cue` no longer bottoms but now **exceeds 120s and even 300s** (was
  ~11s to reach the bottom). Removing the short-circuiting bottom exposed the full evaluation cost,
  which hits the unchanged perf wall. argocd (was ~54s bottom) is the same class, larger.
- So the cert-manager error has moved from a CORRECTNESS bottom to the PERF wall.

## NEXT SLICE: **B `closure-perf`** (frame-id sharing / memo — the minutes-scale wall)

The full `defs@v0.3.19` package eval is now correct but minutes-slow. This is the documented perf B
(frame-id sharing). Look at `EvalKey`/`pushFrame`: every `pushFrame` allocates a fresh frame id, so
structurally-identical re-evaluations (the `Self.#components.X` / `packs.#Argo` fan-out) miss the
memo cache. The `fuel` is LOAD-BEARING in `EvalKey`; the cache keys on the env ID-STACK, so frames
allocated fresh per selection don't share cache entries. Profile where the minutes go (likely the
closure-force fan-out re-deriving large `#components`/`packs` structs per selection), then share frame
ids / canonicalize the cache key so identical sub-evals hit. **F1 default-mark is orthogonal** and no
longer gates cert-manager — interleave if perf B stalls.

### Fast offline perf repro

Full offline copy recipe (no registry, but now minutes not <1s because it's correct):
copy real `defs`/`parts`/`attr`/`packs` from `~/Library/Caches/cue/mod/extract/prodigy9.co/defs@v0.3.19/`
into a `/tmp` module, `sed`-rewrite `prodigy9.co/defs` → `ex.com/cm/defs`, point `main.cue` at
`#ClusterIssuer`. For a BOUNDED correctness probe (completes fast), use only the chain files +
`pod_controller.cue` (the dup-import trigger) — that's byte-equal to cue and runs in <1s.

## Standing context (durable, do not relearn)

- **prod9 real-app checkout:** `/Users/chakrit/Documents/prod9` (NOT `~/prod9`). Module root
  `infra/`; apps under `infra/apps/`. defs pinned `prodigy9.co/defs@v0.3.19` in the cue cache
  `~/Library/Caches/cue/mod/extract/prodigy9.co/defs@v0.3.19/`. READ-ONLY. Never leave scratch in prod9.
- **`fuel` is LOAD-BEARING** in `EvalKey`; closure-force / meet-embeddings is fuel-bounded.
- **Release:** ~1 datestamped alpha/day, `scripts/release.sh` only — CI/Actions BANNED. Did NOT cut
  a release. **Safety:** prod9 + cue cache READ-ONLY. `git commit -F /tmp/msg`. NO
  `git checkout`/`restore`/`reset --hard`. cue oracle: `/Users/chakrit/go/bin/cue` v0.16.1.

## Audit cadence — OVERDUE

Slices A, C, E, **F2**, and now **closure-import-selector-alias** (2 sub-fixes) have landed since the
last Phase-A/B pass. The two-phase audit per `docs/guides/slice-loop.md` (covering A-C-E-F2-import
alias) is OVERDUE — do NOT invoke `/ace-audit`; follow the guide. Run it BEFORE or interleaved with
perf B; don't let it stall the perf slice but it is now well past the 2-3-slice mark.
