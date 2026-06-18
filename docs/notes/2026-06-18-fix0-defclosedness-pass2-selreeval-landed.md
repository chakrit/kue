# RESUME HERE — fix-slice 0 + Pass-2 selective re-eval landed (2026-06-18)

Newest START-HERE breadcrumb; supersedes `2026-06-18-session-resume.md` and
`2026-06-18-argocd-links-3-4-landed.md` as the pointer. Tree clean, pushed to `gh:main`.
Live roadmap: `docs/spec/plan.md`; full record: `docs/reference/implementation-log.md`.

Standing grant in effect (autonomy, resolve forks by philosophy, commit/push on `main`,
no branch). Two correctness/perf fixes from audit `fc25a71`/`faf38b7` landed as two commits.

## What landed

### FIX 1 — `def-open-tail-closedness` (HIGH correctness; commit `6ad6033`)

The link-3/4 parser collapse silently CLOSED an OPEN def carrying comprehensions/embeddings:
`#D: {e, ...}` then `#D & {extra}` bottomed (cue accepts — `...` opens the def). Root: a
`.structComp` carried ONE `open_ : Bool` conflating "regular struct is open by default" with
"def is closed unless `...`"; the parser set `true` (regular default) and normalize hard-`false`d
to close defs, which ALSO closed `...`-bearing defs (the `...`-presence was lost). One bool can't
encode three states (regular-open, def-open-via-`...`, def-closed).

**Fix (illegal-states-unrepresentable): added `hasTail : Bool` to `.structComp`** (`Value.lean`).
`open_` = regular host openness (eager eval arm honors it; parser sets `true`); `hasTail` = explicit
`...` (parser sets `parts.tail.isSome`). `normalizeDefinitionValueWithFuel` sets the def body's
`open_ := hasTail`. Regular structs never pass normalize, stay open. Threaded through all 42
`.structComp` sites + test literals. Tests: module fixture `testdata/modules/def_open_tail_addfield`
+ 3 EvalTests source pins (`fix0_*`: open admits added field, closed-no-`...` REJECTS = no over-open,
regular stays open).

### FIX 2 — Pass-2 selective re-eval (perf; commit = HEAD after this)

The embedding-`Self` two-pass re-evaluated EVERY static field against the Pass-2 augmented frame.
Added `embeddedSelfPassFieldIndices` (TRANSITIVE closure: a field is re-eval'd iff it reads
`Self.<embedded>` directly OR a sibling `Self.<L>` whose field is re-eval'd). Both Pass-2 sites
re-eval ONLY those (feeding their `(index, field)` entries), reuse Pass-1 for the rest. SOUND +
byte-identical. Pins: `selpass_*` (selection == `[2]` regardless of N, static-sibling reader skipped,
eval count 21/41 = +5/field down from +10, value correct).

## The honest perf finding (READ THIS)

FIX 2 eliminates the audit's modeled +8/field redundancy (eval count +10 → +5 on the repro shape,
~46% at n=8) BUT did **NOT reclaim the cert-manager 31s→92s regression** — wall-clock stayed
~88-104s (±15-20s noise swamps any change; content byte-identical to cue). The regression is NOT
dominated by the per-field Pass-2 recompute; it is dominated by **broader frame-id divergence**
(structurally-identical re-pushes get fresh ids → memo misses). The cheap fix ships (helps
many-unrelated-field defs like `packs.#Argo`), but the cert-manager regression needs the deeper
lever: **canonical frame identity** (same fields + same parent id-stack → reuse id) — now the
primary open perf frontier (plan item 7).

## Verify state (both fixes)

- `lake build` 86 jobs green; `fixture pairs ok` (zero byte-drift — HARD gate for FIX 2);
  shellcheck clean.
- cert-manager: content-identical to cue (sorted-key), byte-identical between FIX-1 and FIX-2.
- argocd link 3 (`#TLSRoute`): byte-identical pre-fix-HEAD vs FIX-1 (git-worktree bisect) — no
  link-2/3/4 regression. Full argocd still blocks on link 5 `packs.#Argo` (unchanged).

## Next step

1. **argocd link 5 `packs.#Argo`** (plan item 1 — the LIVE real-app blocker). `packs.#Argo & {…}`
   bottoms in isolation (~36s, perf-wall-adjacent). Bisect via the scratch-external-module method
   (cue.mod pointing `deps` at the real cache; `kue export -e out probe.cue` vs cue). Distinguish
   "still bottoms" from "correct but slow" — `packs.#Argo` is near both walls.
2. Then **item 7's canonical frame identity** (the cert-manager perf reclaim + `packs.#Argo` wall).
3. Remaining backlog: truncate-primitive (item 2), Regex/EvalOps extractions (3,4), test-org (5),
   field-ordering #3 (6), borderline/LOW (8).

## Bisect/probe recipe (reuse, all read-only)

- Real apps: from `/Users/chakrit/Documents/prod9/infra`, `kue export apps/<app>.cue`. cert-manager
  exports (~90-100s); full argocd times out on link 5.
- Scratch external module: `/tmp/x/cue.mod/module.cue` = `module: "example.com/x"` + `deps:` pointing
  at `prodigy9.co/defs@v0.3.19` (cache at `~/Library/Caches/cue/mod/extract/`). Copy in-module
  `defaults` if needed. NOTE the scratch can be UNFAITHFUL for cross-ref-heavy links (`ls.#name`,
  `#UseCertManager` chain) — verify cue resolves the scratch first; if cue bottoms too, the scratch
  is wrong, not kue.
- Pre/post bisect: `git worktree add /tmp/kue-old <commit>` (isolated; `worktree remove --force`
  after — never `checkout`/`reset` the main tree).
- Content compare: `python3 -c "import json;json.dumps(json.load(...),sort_keys=True)"` (ignores
  field-order #3); the session bash filter mangles piped git/heredoc — use `git commit -F /tmp/msg`.

## Safety (standing)

prod9 + cue cache READ-ONLY (eval/probe only). NO `git checkout`/`restore`/`reset --hard` on the
main tree. NO env mutation outside the project tree.
