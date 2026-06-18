# RESUME HERE — Value.closure slice A (closure-realapp-selfalias) landed (2026-06-18)

START-HERE pointer; supersedes `2026-06-18-valueclosure-slice4-landed.md`. Tree clean, pushed to
`gh:main` at `1673d1e`.

## What just landed

**Slice A (`closure-realapp-selfalias`) is committed (`1673d1e`).** The multi-operand fold,
`.structComp` embed splice, and — the largest unlock — DEEP/nested self-ref detection. All
targeted shapes cue-exact; every existing fixture byte-unchanged (86 jobs, `fixture pairs ok`,
shellcheck clean). 7 new `native_decide` pins + 1 committed module fixture.

### Root cause (traced, not guessed)

Facet (b)/(c) was NOT "package-sourced struct" — it was **`.structComp`**. A def that EMBEDS
another value (`#Def: { parts.#Metadata; #x; spec: #x }`) parses to `.structComp` (embeddings
live in `structComp.comprehensions`), which slice 4's gate/force/embedding-meet all dropped.
Building the fix surfaced the ACTUAL real-app blocker: the slice-4 gate (`hasDepth0Ref`) only
flagged TOP-LEVEL sibling self-refs, but real defs reference hidden fields from DEEP nested
positions (`spec: acme: email: Self.#email` → `refId ⟨3,_⟩`) and comprehension GUARDS
(`if Self.#staging`).

### Six sub-fixes (one commit; see plan.md "Slice A design sub-spike" + impl-log)

A.1 gate `.structComp`; A.2 force `.structComp` (splice + meet-fold embeds, closedness = UNION of
def+embed labels); A.3 multi-operand fold (`allClosures`, force-splice EVERY closure against the
shared use set); A.4 embedding-meet closure splice (force a `.closure` embed, body OPENED, host
fields spliced, fuel-decremented); A.5 `.structComp` closedness in `normalizeDefinitionValueWithFuel`;
**A.6 `hasSelfRefAtDepth(depth)`** replaces `hasDepth0Ref` — descends every frame-pusher, flags
`refId ⟨depth,_⟩` at the def frame, scans comprehension guards. A.6 is the largest real-app unlock.

## REAL-APP VERDICT (the headline — read-only prod9, cue v0.16.1)

Slice A is cue-exact on every shape it targets (verified by minimal repros in `/tmp`): multi-closure
`#M & #N & {narrow}`; single-level embed (local + cross-pkg self-ref); `Self={…}` value-alias; DEEP
nested self-refs; comprehension guards over a CONCRETE self-ref. **BUT cert-manager / argocd STILL
return `bottom` (cert-manager ~9.6s — perf wall ALSO unresolved).** The remaining gap is BOTH
correctness AND perf, NOT perf-only. The real defs chain THREE FURTHER, independent correctness
shapes slice A does not cover — each its own slice:

- **C. `closure-default-in-guard` (SMALLEST, do NEXT).** A comprehension guard over a DEFAULT
  disjunction doesn't resolve the default: `#staging: bool | *false; if !Self.#staging {…}` → cue
  uses default `false` → admits; kue leaves the condition a disjunction → drops. **Orthogonal to
  closures** — reproduces with NO def (`x: bool | *false; if !x {…}` drops in kue, cue admits).
  Fix: `expandClausesWithFuel`'s guard test (`Eval.lean`) must resolve the condition disjunction's
  DEFAULT before checking `== .prim (.bool true)` — reuse `defaultAlternatives` from `Manifest`.
  Real `#ClusterIssuer` uses exactly this. Repro: `/tmp/plain.cue` (no closure), `/tmp/pf_self`.
- **D. `closure-presence-test-selfref`.** Real `parts.#Metadata` guards on `if Self.#ns != _|_ {…}`
  (presence-test over a self-ref) + `len(Self.#labels) > 0`. Unverified under the closure force.
- **E. `closure-embed-chain`.** A MULTI-LEVEL embed chain (`#Outer{ #Mid{ #Inner } }`, each a
  `Self={…}` self-ref) collapses → kue `bottom`, cue `{iname,mname,oname}`. The 2-level case fails:
  the inner embed's `Self.#name` → `_|_` when the outer force re-forces the nested embedded closure.
  Single-level (slice A) works; recursion through a nested embedded closure + `Self=` alias does not.
  Real `#ClusterIssuer → parts.#Metadata → attr.#Metadata` is 3-level. Repro: `/tmp/pf_chain`.
- **B. `closure-perf` (frontier #2).** cert-manager ~9.6s while erroring. Downstream of correctness;
  profile after C/D/E once real apps resolve.

**Sequence: C (smallest, orthogonal) → D → E → B.** None is slice A; slice A's audit-defined scope
is complete and green. C is the cleanest next slice — orthogonal to closures, reproduces without
any def, likely a small `defaultAlternatives`-in-guard fix.

## Standing context (durable, do not relearn)

- **prod9 real-app checkout:** `/Users/chakrit/Documents/prod9` (NOT `~/prod9`). Module root for
  the apps is `infra/` (`infra/cue.mod`); apps under `infra/apps/`. defs pinned `prodigy9.co/defs@v0.3.19`
  in the cue cache `~/Library/Caches/cue/mod/extract/prodigy9.co/defs@v0.3.19/`. READ-ONLY.
- **Real `#ClusterIssuer`** (`.../defs@v0.3.19/cluster_issuer.cue`): `Self={ parts.#Metadata; #email;
  #staging: bool|*false; spec: acme: { email: Self.#email; if Self.#staging{…}; if !Self.#staging{…};
  privateKeySecretRef: name: Self.#name + "-secret"; … } }`. `parts.#Metadata` is itself a `Self=`
  def embedding `attr.#Metadata` with `if Self.#ns != _|_` guards — the 3-level chain (E).
- **Repro modules** live in `/tmp` ONLY (rebuild if gone): `/tmp/pf_self` (Self+embed+nested+cond —
  C blocker), `/tmp/pf_chain` (multi-level embed — E blocker), `/tmp/plain.cue` (C, no closure),
  `/tmp/pf_a` (multi-closure, WORKS), `/tmp/pf_embed` (single embed, WORKS).
- **`fuel` is LOAD-BEARING** in `EvalKey` — never drop it. The closure-force / meet-embeddings
  mutual recursion is fuel-bounded: `forceClosureWithConjunct` (tier 4) calls `meetEmbeddingsWithFuel`
  (tier 3) at same fuel; the back-edge (meet-embeddings forcing a closure embed) DECREMENTS fuel.
- **Release:** ~1 datestamped alpha/day, `scripts/release.sh` only — CI/Actions BANNED. Latest
  `v0.1.0-alpha.20260617.3`. Did NOT cut a release (mid-churn).
- **Safety:** prod9 + cue cache READ-ONLY. Bash filter mangles piped git input → `git commit -F /tmp/msg`.
  NO `git checkout`/`restore`/`reset --hard`. cue oracle: `/Users/chakrit/go/bin/cue` v0.16.1.
- **Field-ordering parity (#3)** resurfaces in multi-field real-app output (embed fields ordered
  after vs before def fields). Orthogonal byte-polish; the committed fixture stays single-output to
  dodge it.

## Audit cadence — DUE

Slices 3, 4, A are landed since the last Phase-A/B pass (`a347386`/`31b329c`, slices 1-2; plus the
slice 3-4 Phase-A `1f76347`). Slice A is large and behavior-changing — a two-phase audit per
`docs/guides/slice-loop.md` is DUE around now (do NOT invoke `/ace-audit`; follow the guide). Don't
let it stall slice C.
