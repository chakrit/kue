# RESUME HERE — argocd link 5 (`packs.#Argo`) unblocked; last correctness gap CLOSED (2026-06-18)

Newest START-HERE breadcrumb; supersedes `2026-06-18-fix0-defclosedness-pass2-selreeval-landed.md`
as the pointer. Tree clean, pushed to `gh:main` (HEAD `cd9386f`). Live roadmap:
`docs/spec/plan.md`; full record: `docs/reference/implementation-log.md` ("argocd-packs-argo" entry).

Standing grant in effect (autonomy, resolve forks by philosophy, commit/push on `main`, no branch).

## What landed — `argocd-packs-argo` as a 4-link correctness CHAIN

`packs.#Argo` (argocd link 5) bottomed in isolation; the bottom was FOUR independent root causes,
each fixed + pinned as its own commit (bisected with FAST `/tmp` scratch-module repros pointing
`deps` at `prodigy9.co/defs@v0.3.19` in the real cache — never the ~71s app):

1. **`8ce2462` — list-embed use-site narrowing.** `spliceNarrowingOperand?` surfaces an
   `.embeddedList`'s decls in the conjunction-deferral fold (was dropped → def read its default).
2. **`6436d08` — optional-aware arm pruning + hidden-bottom propagation.** `fieldBottomCounts`
   skips OPTIONAL fields in the struct bottom-check (an UNSET `#u?: _|_` no longer prunes its
   disjunction arm); a supplied impossible field bottoms at manifest. The `#ArgoRepo`
   `(_#GitHubApp | _#PAT)` arm-kill.
3. **`14994e6` — REGRESSION fix.** Sub-fix 2's manifest check recursed the whole hidden-field
   subtree and bottomed cert-manager (imported-package bindings carry unreferenced conflicts cue is
   lazy on). Made it SHALLOW (`isBottom`, no recurse). cert-manager byte-identical to baseline.
4. **`7898cff` — presence test over a disjunction.** `classifyDefinedness` treats a `.disj` as
   `.defined` — `(*"argocd"|string) != _|_` is `true`, so the `parts.#Metadata`
   `if Self.#ns != _|_ {namespace}` guard fires (`#ArgoRepo` was missing `metadata.namespace`).

`cd9386f` — docs (implementation-log + plan).

## HEADLINE — argocd correctness status

**The last CORRECTNESS gap is CLOSED.** Every component of `apps/argocd.cue` is content-identical
to cue (sorted-key, modulo field-order #3), verified read-only against the real prod9 infra:
- `packs.#Argo` (scratch): content-OK, 6179 b == cue, ~71s.
- All 5 real `argo_.{stage9,bluepages,ircp,tmg,sunzapper}.configs` (real GitHub-app/PAT data): content-OK.
- `#ArgoRepo` / `#ArgoApp` / `#ArgoProject` (scratch): content-OK.
- argocd deployment config (`#Secret` + 2× `#ConfigMap` = `configs.yaml`): content-OK.
- `route.yaml` (`#TLSRoute`, link 3) / `listener.yaml` (`#ListenerSet`, link 4): correct.

**BUT full `kue export apps/argocd.cue` still bottoms — this is the PERF WALL, not a link 6.**
cue exports the full app in 0.03s (51178 b, concrete — no genuine conflict). kue bottoms after
7m33s with `conflicting values (bottom)`. Since EVERY piece is individually content-correct and cue
confirms the app is concrete, the full-app failure is **fuel exhaustion under the combined load**
(5× ~71s `packs.#Argo` + the rest): `fuel=100` is load-bearing (see
`decisions/2026-06-18-correctness-over-performance.md`), and a truncated value surfaces as bottom.
This is exactly **plan item 7 (per-eval-cost / canonical frame identity)** — the queued perf
frontier — NOT a correctness blocker. argocd is correct-but-unusably-slow end-to-end.

cert-manager: byte-identical to the `8ce2462` baseline (no regression), ~120-160s.

## Verify state (all four sub-fixes + docs)

- `lake build` 86 jobs green across all commits; `fixture pairs ok` (zero byte-drift — every
  existing fixture byte-unchanged); shellcheck clean.
- New committed module fixtures: `list_embed_self_narrowing`, `disj_arm_kill_impossible_field`,
  `disj_presence_guard`. New EvalTests pins: `link5_list_embed_*`, `link5_disj_*`,
  `link5_presence_test_*`. New FixtureTests pins: `link5_hidden_*`.

## Next step

1. **Plan item 7 — per-eval-cost / canonical frame identity** is now THE frontier: it both reclaims
   the cert-manager regression AND unblocks the full `apps/argocd.cue` (which is correct-but-fuel-
   exhausted at scale). Profile against cert-manager (resolving) + `packs.#Argo` (resolving, ~71s) +
   the full app. The lever: structurally-identical frame re-pushes get fresh ids → memo misses →
   exponential divergence → fuel exhaustion. Same fields + same parent id-stack → reuse id
   (audit-heavy: "independently-built frames never falsely share").
2. The two-phase audit (the orchestrator runs it next — `docs/guides/slice-loop.md`, NOT
   `/ace-audit`): (A) code-quality over the 4-link batch, then (B) architecture/refactor.
3. Then the remaining backlog (truncate-primitive #2, Regex/EvalOps #3/#4, test-org #5,
   field-ordering #6, borderline #8).

## KNOWN latent shape (deferred, NOT on the packs.#Argo path)

An inline `Self=`-struct embedding a NO-DEFAULT disjunction-of-defs whose arms read host-`Self`
(`#R: Self={#u?, (_#A|_#B)}; out: #R & {#u:"me"}`, arms read `Self.#u`) is eagerly resolved BEFORE
the use-site narrowing → arms bake `Self.<field>` unnarrowed (then `meet` with the narrow → bottom).
Root-caused: `bodyNeedsDefer`/`resolveEmbedDefBody?` only follows a disjunction's DEFAULT arm, so a
no-default disjunction misses the deferral; AND the host is eagerly evaluated in parallel with the
deferred force (double-eval). The `resolveEmbedDefBodies?` deferral-detection half is correct but
INSUFFICIENT (needs the eager/deferred double-eval dedup too) — reverted, not shipped. The real
`#ArgoRepo` arms read host-SUPPLIED `Self.#url` via the proper embed-Self mechanism (handled by
sub-fixes 2+4), so this shape does NOT block argocd. File as a future correctness slice if a real
target hits it.

## Bisect/probe recipe (reuse, all read-only)

- Scratch module `/tmp/argoprobe/cue.mod/module.cue` = `module: "example.com/argoprobe"` + `deps:`
  `prodigy9.co/defs@v0` `v: "v0.3.19"`; import `prodigy9.co/defs` / `.../defs/packs`. Run cue/kue
  from INSIDE the module dir. `defaults` is NOT a separate dep — inline `#gateway_name` etc.
- Real apps: from `/Users/chakrit/Documents/prod9/infra`, `kue export -e '<app>.configs' ./apps/argo`
  (per-app) or `kue export apps/<app>.cue`. cert-manager ~120-160s; full argocd times out (perf).
- Content compare: `/usr/bin/python3 -c "import json; json.dumps(json.load(...),sort_keys=True)"`
  (ignores field-order #3). The session's `python3` is venv-shadowed — use `/usr/bin/python3`.
- Pre/post bisect: `git worktree add /tmp/kue-old <commit>` (isolated; `worktree remove --force`
  after — never `checkout`/`reset` the main tree). Commit with `git commit -F /tmp/msg`.

## Safety (standing)

prod9 + cue cache READ-ONLY (eval/probe only). NO `git checkout`/`restore`/`reset --hard` on the
main tree. NO env mutation outside the project tree.
