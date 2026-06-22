# RESUME — two-phase audit CLOSED; next leader = Bug2-10 (2026-06-23)

Live START-HERE; supersedes `2026-06-23-resume-bug29-DONE-next-bug210.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md) +
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Bug2-10 DESIGN
NOTE + SHARED-ROOT ANALYSIS. Full per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md).

## State — audit counter = 0 (RESET). Two-phase audit CLOSED. Next = Bug2-10.

**Two-phase audit of the Bug2-8 + Bug2-9 batch (`9b78c3d`..`2e337b1`) is CLOSED:**
- **Phase A HEALTHY** (`2e337b1`): Bug2-8 `DeclProvenance`/`ConjOperand` new-type discipline
  + union-vs-meet sound; Bug2-9 `flattenConjDefRef` never over-fires, terminating, closedness
  preserved; cert-manager canary held. **Found + fixed inline (`0109bb4`) a major test-suite
  defect:** ~140 of ~150 `TwoPassTests` theorems were SILENTLY DEAD (four unterminated
  `/-- … -/` doc-comments swallowed everything; build stayed green — dead theorems aren't
  kernel-checked). Behavior was still correct (the `.cue/.expected` fixtures independently
  pinned it). Phase A revived all ~143. Filed Bug2-11 (MEDIUM cross-pkg narrowing) + Bug2-12
  (LOW cycle-closedness leak), both parked.
- **Phase B HEALTHY** (this round, commits below): module graph ACYCLIC + strictly layered
  (`Builtin ↛ Eval`, `EvalOps ↛ Eval` no back-edge); `DeclProvenance`/`ConjOperand` exemplary
  type-leverage in `Value.lean` (L1); `flattenConjDefRef` correctly homed in the pre-`mutual`
  helper tier near `conjStructOperand?`, NO catch-all swallow; cleanliness sweep clean;
  `Eval.lean` **3780** (under the ~4500 re-split watch — `Eval.DefDeferral`-first-carve ruling
  STANDS). Type-leverage next-candidate NONE high-value (`FieldClass`'s two `Bool`s are
  deliberately orthogonal CUE axes); test-fixture redundancy NONE to prune (the `.cue/.expected`
  + `native_decide` layers pin DIFFERENT things — the dead-theorem incident proves both are
  load-bearing). **No new code fix-slice.**

**Phase-B commits (all on `main`, PUSHED):**
- `0150095` — **test-health hardening** (the dead-theorem fallout): converted ALL 30 block
  comments in `TwoPassTests.lean` to `--` LINE comments (cannot run away) + an end-of-file
  COVERAGE TRIPWIRE (`#check @<last-theorem>` per 23 sections — a swallowed section makes its
  anchor unknown → `#check` fails to ELABORATE = hard build error, never silent green). 157
  theorems preserved.
- `8b6627b` — **Phase-B verdict + Bug2-10 design note + shared-root analysis** (docs): perf-doc
  de-stale (argocd blocker Bug2-8 → Bug2-10, ~58s→~53s); `TwoPassTests` SPLIT scheduled;
  test-health convention → `failure-modes.md`.

**Full gate green:** `lake build` (110 jobs) + `check-fixtures.sh` + `shellcheck`; cert-manager
canary `jq -S` diff = 0 (kue ≡ cue).

## Next leader — Bug2-10 (DESIGN NOTE in place; the residual argocd blocker)

`kue export apps/argocd.cue` STILL bottoms (~53s) — the live blocker. **Bug2-10:** use-site
narrowing of a host that EMBEDS a def with a sibling self-ref does NOT flow into the embedded
self-ref. **Self-contained repro:** `{#Meta} & {#name:"x"}` where `#Meta: Self={#name:string,
metadata: name: Self.#name}` → cue `{metadata:{name:"x"}}`, kue `incomplete value: string`,
while DIRECT `#Meta & {#name:"x"}` works.

**ROOT CAUSE (traced, Phase-B):** the CONJUNCT-DEFERRAL gate. `{#Meta}` is a `.structComp`
host; `conjDefClosure?` (`Eval.lean:2443`) defers ONLY a bare `.refId`, not a `.structComp`, so
the host evaluates STANDALONE via the `.structComp` arm (:2954) — its `meetEmbeddingsWithFuel`
(:3033) sees `current` = the host's OWN (empty) fields, so `forceClosureWithConjunct …
useOperands` (:3279) splices an EMPTY narrowing and `Self.#name` freezes at `string` BEFORE the
sibling `{#name:"x"}` arrives via the outer `meet`. DIRECT works because a bare `.refId` IS
deferred and the closure-fold (:3152) splices the shared `useOperands` first.

**FIX (approach A, preferred):** in `evalConjStandard`'s `none` branch, route a `.structComp`
host whose embeds need the use-site narrowing (embed body has a sibling self-ref —
`defBodyHasSiblingSelfRef`/`bodyNeedsDefer`) through the SAME `closures`/`useOperands` machinery
the bare-ref fold uses (gather siblings via `spliceNarrowingOperand?`, force each embed closure
with them). Does NOT touch `meetEmbeddingsWithFuel` internals (the splice is already correct;
the bug is delivery). Composes with `injectLetLocalNarrowings` + the Bug2-5 `embedChainAny`
/`embedBodyEmbedsDisjDeep` deep gate. **Over-fire guard:** fire ONLY when the embed body has a
sibling self-ref AND a sibling narrowing conjunct exists, else cert-manager's plain-embed
(Bug2-8 static-decl union) + no-narrowing `{#Meta}` standalone stay byte-identical.

**SHARED-ROOT verdict (full detail in `spec-conformance-audit.md`):** Bug2-10/2-11 PARTIAL
shared root (narrowing-delivery to a deferred def interior; 2-10 = structComp-host conjunct
not deferred, 2-11 = cross-package selector not flattenable — distinct frames, so approach A
lands 2-10 + EXTENDS toward 2-11 but does not close it free). Bug2-12 NOT subsumed (closedness-
set leak on the cycle fold, orthogonal). **ARGOCD CHAIN IS ONE DEEP FIX (Bug2-10), NOT THREE** —
2-11 is off the argocd path (same-frame), 2-12 latent non-blocking.

## After Bug2-10 (ranked)

1. **`TwoPassTests` SPLIT** (scheduled — `plan.md` item 3) — by bug-family: carve `bug2x_*`
   sections into `Bug2xTests.lean`, each file gets the tripwire; convert headers to `--`. The
   1879-line file is the demonstrated silent-failure surface.
2. **Perf frontier (#7 / item-5)** — STILL GATED on the argocd unblock (un-gates once Bug2-10
   lands; profile `argo` against a resolving target then).
3. **item-6 LOW tail** — parser strictness `*(1|2)`/`__x`, A2-x/y, B2-A1/A2,
   `resolveEmbeddedDisjDefault` check, `release-linux.sh` dirty-tree guard.

Bug2-11 (MEDIUM, cross-package) + Bug2-12 (LOW, cycle-closedness, spec-check first) are
independent backlog, NOT argocd-blocking.

## Release state

`v0.1.0-alpha.20260622` was CUT. A fresh alpha is **cadence-available but awaits user
greenlight** — Bug2-9 (`5d9cf8f`) + Bug2-8 (`2332aff`) + the test-health hardening (`0150095`)
+ Bug2-7..Bug2-5 + the Linux scripts are unreleased in-tree. (CI/GitHub Actions banned;
release = local `scripts/release.sh` + `scripts/release-linux.sh`.)

## STANDING CONTEXT (full detail in CLAUDE.md + guides/slice-loop.md)

- Autonomy grant in effect; resolve forks by philosophy; commit/push on `main` (attended).
- Spec is authority; `cue` (`/Users/chakrit/go/bin/cue` v0.16.1) a fallible cross-check, never
  the gate. Correctness over byte-compat. kue binary: `.lake/build/bin/kue`.
- prod9 (`/Users/chakrit/Documents/prod9/infra`) + cue caches READ-ONLY. NO
  `git checkout`/`restore`/`reset --hard` on main tree. Faithful Bug2-10 oracle: a THROWAWAY
  `/tmp` module with `cue.mod` depending on `prodigy9.co/defs@v0.3.19` — no prod9 mutation.
- Orchestrator = thin re-spawner; one subagent per slice; per-slice duties: tests-first
  (line-comment headers + `#check` tripwire on any new/touched test module); log
  `cue-divergences.md`; flag `cue-spec-gaps.md`.
