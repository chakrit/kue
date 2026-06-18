# RESUME HERE — Value.closure slice E (closure-embed-chain) landed (2026-06-18)

START-HERE pointer; supersedes `2026-06-18-valueclosure-sliceC-landed.md`. Tree clean, pushed to
`gh:main`. Slice E (the multi-level embed-chain correctness fix) is done; **a NEW correctness
blocker (B') surfaced building E and is the LIVE next slice — NOT perf yet.**

## What just landed (slice E)

A multi-level embedded-closure self-ref chain — a def embedding a def embedding a def, each a
`Self={…}` self-ref — now propagates a use-site narrowing through every embed level instead of
collapsing to `bottom`. 2-level AND 3-level, explicit `& {#name: …}` wiring AND implicit
plain-embed flow, all cue-exact. 8 `native_decide` pins + 1 committed module fixture; every
existing fixture byte-unchanged (86 jobs, `fixture pairs ok`, shellcheck clean).

### Root cause (traced — the breadcrumb's "force doesn't recurse" framing was WRONG)

THREE coupled bugs, none of them force-recursion (forcing already recurses via `.conj`/embed
defers):

1. **Closedness leak (E1).** The eager `.structComp` eval arm + the non-closure branch of
   `meetEmbeddingsWithFuel` `meet`-ed an embed WITHOUT opening its closedness. A closed embed
   (`#Plain:{pval}`) into a host with a regular `x` rejected `x` (`x ∉ {pval}`) → `bottom`. Slice
   A dodged it (its only embed `parts.#Metadata` was HIDDEN-ONLY → `ignoresClosedness`); any embed
   with a REGULAR field trips it. Minimal: `out: { #Plain; x: "z" }` bottomed.
2. **Producer gap (E2a).** `conjStructOperand?`'s lazy-merge (splices a use-site narrowing into a
   def frame) has no `.structComp` arm at ANY depth, and is depth-0-only for `.struct`. So an
   embed-bearing def, OR a nested (`depth>0`) self-ref def reached from inside an embedding, was
   eager → collapsed before the narrowing arrived.
3. **Splice contamination (E2b).** Force-splicing the host's FULL `current` into an embed carried
   (a) the host's `Self=`/`let` aliases — colliding with the embed's OWN `Self`, breaking its
   `Self.label` selections → `bottom`; and (b) the host's REGULAR fields (`apiVersion`/`kind`) —
   the embed re-evaluated and conflicted on them.

### Fix (`Kue/Eval.lean`)

- **`closeEmbeddedOver`** + `openStructValue` at both embed-meet sites — meet OPEN, re-close over
  `def ∪ embed` labels, DRY'd into ONE shared helper (eager arm + force arm).
- **`refDefClosureBody?` / `conjDefClosure?`** — defer a bare ref to an embed-bearing `.structComp`
  (any depth) or NESTED (`depth>0`) `.struct`/`.structTail` self-ref def to a `.closure`; wired into
  the `.refId` arm (standalone force for a bare ref), the `.conj` fold, and `meetEmbeddingsWithFuel`.
  Depth-0 `.struct`/`.structTail` keeps the lazy-merge path → zero fixture drift.
- **`hiddenFieldsOnly`** — splice ONLY the host's hidden/definition fields into an embed (the shared
  `#name`), never aliases (own `Self`) or regular fields (unify at the outer `meet`).
  **`stripLetBindings`** on the multi-operand `.conj` fold use-operands.

### Tests

8 pins: `close_embedded_over_unions_allowed_labels`, `eager_structcomp_embed_closed_keeps_host_field`
(E1); `embed_chain_two_level_narrows_through`, `embed_chain_two_level_standalone_forces`,
`embed_chain_inner_conflict_is_bottom`; `ref_def_closure_{skips_depth0_struct,fires_for_nested_struct}`.
Committed `testdata/modules/embed_chain_selfalias/` — the real 3-level PLAIN-embed cross-package
shape (`#ClusterIssuer → parts.#Metadata → attr.#Metadata`, implicit hidden-field flow), JSON
byte-identical to cue.

## REAL-APP VERDICT (the headline — read-only prod9, cue v0.16.1) — HONEST

- **E is cue-exact on EVERY embed-chain shape in isolation**, AND a faithful hand-built replica of
  the FULL real `#ClusterIssuer` (3-level chain + `#staging: bool|*false` guards + `privateKeySecretRef`
  interpolation + `solvers` list + presence/`len` guards + `attr.#Metadata`'s `_` embedding) exports
  BYTE-EXACT vs cue. The headline E correctness is COMPLETE.
- **BUT cert-manager (~11s) and argocd (~54s) STILL return `bottom`.** Bisected: the collapse is NOT
  in `#ClusterIssuer` — it is triggered by a SIBLING def in the loaded `prodigy9.co/defs/parts`
  package, **`#PodController`**, which embeds **`attr.#Ports`** (a `.structComp` with a bare-`#port`
  self-ref guard `if #port != _|_`). The mere PRESENCE of `#PodController` in the package poisons the
  UNRELATED `#ClusterIssuer` eval → `bottom`. This is a **CROSS-DEF cache collision** — a NEW
  correctness shape beyond E. The long timings are a separate perf concern (the bottom is fast: 0.04s
  in the minimal cross-def repro).

## NEXT SLICE: B' `closure-crossdef-cache-collision` (CORRECTNESS, not perf)

A sibling structComp-with-guard def (`#PodController` embedding `attr.#Ports`) poisons an unrelated
def's (`#ClusterIssuer`) eval when both are in the loaded package. Almost certainly a cache-key
collision in the closure-force / meet-embeddings path (two defs forcing structComp closures whose
`(fuel, env.ids, visited, value)` keys collide because the captured frame ids or visited markers are
shared). **Minimal repro to rebuild** (cross-pkg, in `/tmp`): a `parts` package with `#ClusterIssuer`
(embeds `parts.#Metadata`) AND a sibling `#PodController` (embeds `attr.#Ports`); `out:
#ClusterIssuer & {…}` → `bottom`. Bisect: it's `attr.#Ports`'s `if #port != _|_` guard embed in a
sibling. After B', re-probe cert-manager; if it exports, frontier moves to **B `closure-perf`**
(~11s cert-manager / ~54s argocd wall).

## Standing context (durable, do not relearn)

- **prod9 real-app checkout:** `/Users/chakrit/Documents/prod9` (NOT `~/prod9`). Module root
  `infra/` (`infra/cue.mod`); apps under `infra/apps/`. defs pinned `prodigy9.co/defs@v0.3.19` in
  the cue cache `~/Library/Caches/cue/mod/extract/prodigy9.co/defs@v0.3.19/`. READ-ONLY. **Never
  leave scratch files in prod9** — I created+removed `apps/zz_*.cue` while bisecting; tree is clean.
- **Real `#ClusterIssuer`** (`.../defs@v0.3.19/cluster_issuer.cue`): `Self={ parts.#Metadata; #email;
  #staging: bool|*false; … }`. `parts.#Metadata` plainly embeds `attr.#Metadata` (`{#name; #ns?;
  #labels?; #annotations?; _}`). The B' trigger is `parts/pod_controller.cue` (`#PodController`
  embedding `attr.#Ports` — `attr/ports.cue`'s `if #port != _|_ {#ports: [#port]}`).
- **`fuel` is LOAD-BEARING** in `EvalKey`; the closure-force / meet-embeddings mutual recursion is
  fuel-bounded. The cache key is `(fuel, env.ids, visited, value)` — the likely B' collision locus.
- **Release:** ~1 datestamped alpha/day, `scripts/release.sh` only — CI/Actions BANNED. Did NOT cut
  a release (mid-churn). **Safety:** prod9 + cue cache READ-ONLY. `git commit -F /tmp/msg` (bash
  filter mangles piped git input). NO `git checkout`/`restore`/`reset --hard`. cue oracle:
  `/Users/chakrit/go/bin/cue` v0.16.1.
- **Repro modules** in `/tmp` ONLY (rebuild if gone): `/tmp/pf_chain/{chain2,chain3,d1,d2,d4,o2}.cue`
  (E chains, WORK), `/tmp/pf_real/` (real `#ClusterIssuer` replica, WORKS), `/tmp/pf_coll/` (cross-def,
  the B'-adjacent shape).

## Audit cadence

Slices 3, 4, A, C, E landed since the last Phase-A/B pass. E is medium (3 coupled fixes, behavior
-additive, zero fixture drift). A two-phase audit per `docs/guides/slice-loop.md` is DUE (do NOT
invoke `/ace-audit`; follow the guide) — covering slices A-C-E. Don't let it stall slice B'.
