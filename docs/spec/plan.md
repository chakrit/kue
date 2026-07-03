# Kue Plan

Status: accepted — living roadmap.

> **Doc precedence (amendment A5):** OPEN DECISIONS live in the breadcrumb's "Open" block;
> this plan POINTS to them, never holds a second copy. On disagreement — what's-NEXT →
> breadcrumb wins; what's-TRUE → this plan wins. See
> [`../guides/slice-loop.md`](../guides/slice-loop.md) § "Open decisions — single home".

> **Protocol amendments A1–A8 (keep-going critique) — APPLIED 2026-07-03.** All eight
> ratified process amendments landed (A1 retraction duty, A2 strict-xfail quarantine, A3
> `check.sh` + sanitized canary, A4 audit-the-last-audit, A5 doc precedence, A6 blind-grind
> breaker, A7 infra-in-audit, A8 git-ban settings). Batch record in the implementation-log;
> the discharged proposal note carries an APPLIED retraction stamp. Not re-open.

The live implementation roadmap. Kept small, current, and actionable — one focused slice
at a time. The full record of completed slices lives in
[`../reference/implementation-log.md`](../reference/implementation-log.md) (chronological,
one entry per commit) and `git log`; this file holds only where we are and what's next. A
periodic plan-hygiene pass distills it back to the live roadmap (history → log + git); see
[`../guides/slice-loop.md`](../guides/slice-loop.md). Last distilled 2026-07-04.

## North Star

Kue targets **CUE v0.15 semantics, done correctly**. Where the official `cue` v0.16.1
binary is buggy, Kue implements the *correct* behavior, not the bug. The compatibility
target is the language as specified, not bug-for-bug parity. See
[`../decisions/2026-06-14-cue-compatibility-target.md`](../decisions/2026-06-14-cue-compatibility-target.md).

## Working Principles

- TDD where behavior is testable: theorem checks or executable examples before code.
- Keep the semantic model simple before optimizing representation.
- Total functions and explicit semantic values over hidden host-language failure.
- Avoid dependencies until they clearly remove more complexity than they add.
- One slice per commit; subject mirrors the slice title. Small enough to review/revert.
- **Correctness over performance.** A latent unsound result is a Violation even with no
  failing fixture; a perf miss is acceptable. See [`../decisions/`](../decisions/).
- **Spec is the authority; `cue` is a fallible cross-check, never the gate.**
  Byte-identical to `cue` is structurally bug-replicating. Conform to the CUE spec; where
  it is silent, to lattice first principles (precise, total,
  illegal-states-unrepresentable). When `cue` disagrees with the spec it is WRONG → follow
  the spec, record in `cue-divergences.md`.
- **Real-app compilation is a stress test, not the goal.** Getting prod9 infra (argocd,
  cert-manager) to `export` *validates* correct semantics; it is never an end in itself.
  Rank slices by spec-correctness and clean design evolution — never let one app's shape
  pull the loop into per-app special-casing. A real-app blocker is a stress-test finding,
  resolved by GENERAL semantic fixes as they mature, never by per-app narrowing — the
  Bug2-5..2-14c argocd chain landed exactly this way (each fix general, oracle-pinned at
  single-package granularity, no argocd-keyed code).

## Prod9 eval-conformance campaign — L1–L5 COMPLETE (2026-07-03)

The `apps/{lem,n8n,x9,typesense}.cue` bottom-out (via `prodigy9.co/defs@v0.3.19`
`packs.#WebApp` / `defaults.#Basics`) was peeled layer by layer. Each blocking construct was
lifted OUT of the private dep into a self-contained `testdata/wild/` fixture (reproduced RED
first), fixed with a GENERAL, spec-grounded change (never per-app narrowing), and left
gate-enforced green. All layers resolved:

- **L1 — Self.#hidden in list embeddings** (`self-hidden-in-list-embed`). The embedding-`Self`
  two-pass scanned only static fields; now re-evaluates embeddings against the augmented frame
  when an embedding reads a sibling-embedded `Self.<L>`.
- **L2 — default-disjunction not concretized in string interpolation**
  (`default-disj-in-interpolation`). `.map collapseDefaultDisjunction` over evaluated
  interpolation parts, reusing the shared default-shedding projection.
- **L3 — let/ref-delivered list-carrier meet bottomed** (`let-list-meets-carrier`). Fixed at
  the EVAL layer (a list-embedding collapse mirroring the `{5}`→`5` scalar collapse), NOT meet.
  **Provenance is the soundness key:** the host's OWN embedding collapses; a SEPARATE foreign
  decls-struct conjunct (`{#a,[1,2]} & {#b}`) still bottoms, matching cue — a meet-layer fix
  would have over-collapsed it (the red herring this slice ruled out).
- **Root A — def closedness through embedded disjunction** (`def-closedness-thru-embedded-disj`).
  A SOUNDNESS over-accept: a definition embedding a structural disjunction lost closedness
  through the arms. The closing normalizer now recurses into a `.disj` embedding so each
  struct-literal arm closes; a `.refId`/non-disj embedding is a no-op pass-through. Prerequisite
  that unblocked L4.
- **L4 — disj-arm-list-embed dropped** (`disj-arm-list-embed-dropped`). A list-shaped
  disjunction arm met against a list-carrier host bottomed as struct-vs-list → arm pruned →
  spurious bottom. Now, when the plain meet bottoms AND the arm is list-shaped, re-run it through
  the single-embedding sub-fold so the host's own list-collapse fires. Root A + L4 are a pair.
- **L5 — three closedness seeds graduated** (all `.known-red` removed): root2/root3 were a
  MEASUREMENT artifact (the carrier was bound as a regular exported field, so its own
  incompleteness surfaced before `out`'s bottom; corrected to a hidden `#M`), and webapp-carrier-l5
  was `evaluatedStructOperand?` (`Kue/EvalBase.lean`) mis-closing an OPEN open-tail operand.
  Dropping the `.defOpenViaTail → false` special case (open now contributes `openness.isOpen`;
  closedness still ANDs) fixed it without under-rejecting a genuinely-closed sibling.

**Durable ruling carried out of the campaign:** every fix was general and oracle-pinned at
single-package granularity — none keyed to an app (the Bug2-5..2-14c discipline). Full
bisection trails + adversarial pins live in `implementation-log.md` + git; the soundness
argument lives at each wild fixture. A full end-to-end re-export of the four apps is the
outstanding EMPIRICAL check (the captured blocking constructs are all fixed; whole-app export
was not re-run this campaign — do NOT claim the apps export clean without running the canary).

## Standing Capabilities (what Kue does now)

The semantic core is broad and oracle-checked against `cue` v0.16.1
(`/Users/chakrit/go/bin/cue`). Scope qualifier: drop-in status was demonstrated on a
2-app sample (argocd + cert-manager) as of 2026-06-23; argocd has since been removed from
the infra checkout (its claim is historical, not re-verifiable), and the broader prod9
corpus is the open Current front. Currently working, cue-exact modulo the tracked
field-ordering byte-parity gap (#3):

- **Evaluator + lattice.** Total `meet` /`join` over the full `Value` domain; primitives,
  kinds, bounds, regex, struct/list shapes. `Field` is a `structure`. Disjunctions with
  default-mark algebra (unification ANDs default sets; arithmetic/comparison/unary
  resolve-operand-first; nested two-level precedence; equal-default dedup).
  Structural-cycle detection: `#L:{n,next:#L}` errors; `#List | *null` terminates on
  `*null` (D#2).
  ```cue
  port: int & >0 & <=65535
  port: 8080  // 8080
  ```
- **Closures / cross-package def-meet.** `Value.closure (frame) (body)` carries the
  capture frame so an imported def's body unifies with the use-site *before* its
  cross-frame self/sibling refs resolve. Deep/nested self-ref detection
  (`hasSelfRefAtDepth`); multi-level embed chains resolve. Forcing tier closes imported
  def bodies at capture.
  ```cue
  import "ex.com/pkg"
  web: pkg.#Def & {name: "web"}
  ```
- **Comprehensions.** Struct (`for k,v in s {…}`) and list (`[for x in xs {x}]`, incl.
  `if` guards, `let` clauses (D#3), nested/multi/zero-yield, plain+comp interleave). Guard
  classification (D#1b/c): incomplete guard DEFERS (residual node), concrete non-bool
  guard is a TYPE ERROR, presence-test `X !=/== _|_` drops. `for` over a concrete
  non-iterable is a TYPE ERROR (E#4); a `.top`/unresolved source DEFERS; a bottom source
  PROPAGATES (PA-1). Scalar struct-embedding collapse (`{5}`→`5`) at embed-eval.
  ```cue
  out: [for x in [1, 2, 3] {x * 2}]  // [2, 4, 6]
  ```
- **Disjunction defaults under embedding.** Use-site narrowing distributes into every arm
  of an embedded default disjunction, pruning dead arms.
  ```cue
  x: (*"a" | "b") & ("b" | "c")  // "b"
  ```
- **Fuel-saturation perf.** Eval count FLAT across fuel (bracketed monotonic truncation
  counter; truncated values fuel-keyed, saturated results fuel-free). `evalFuel = 100`.
  Frame-id sharing + force-memo. Cache keyed on a bounded-depth structural digest
  (`valueDigest`, `DIGEST_DEPTH=3`; `BEq` untouched → soundness unconditional). Perf #7
  (2026-06-23) added a `selfEvaluatingLeaf?` fast path (env-independent leaves bypass the
  cache) + saturated-only `satCache` insert — both value-identical by construction.
- **Builtins.** `base64.Encode`, `json.Marshal` (`Kue/Json.lean`), `yaml.Marshal`
  (`Kue/Yaml.lean`), `regexp.Match`, `math.Pow`/`math.Sqrt` (full real domain, exact decimal),
  `list.Sort` /`SortStable`, `strings.*` /`list.*`/`math.*` namespaces. Multiline strings.
  Dispatch is via a closed `BuiltinFamily` enum (`core` + the 7 qualified packages) classified
  by `BuiltinFamily.ofName?` and matched EXHAUSTIVELY — a non-builtin name bottoms on concrete
  args (no silent residual); a new family forces a dispatch arm (TL-1).
  ```cue
  import "encoding/json"
  out: json.Marshal({a: 1})  // "{\"a\":1}"
  ```
- **Regex.** RE2-equivalent AST → NFA matcher in `Kue/Regex.lean` (a true leaf), incl.
  `\b`, lazy quantifiers, in-class `\D` /`\W`/`\S` set-complement, `maxRepeat=1000`.
  Corpus divergence-free.
- **Imports / modules.** `cue.mod` discovery, in-module + cross-module (vendored or
  extract-cache) resolution by longest module-path prefix, multi-file merge, transitive
  loads, package-dir entry (`kue export./apps`), qualified import path
  `"location:identifier"` (F-3, `Import.packageName`). Imports are FILE-SCOPED (a sibling
  file's imports are invisible; same-named imports occupy separate slots — `53fe3cc`).
  Registry/OCI fetch-on-missing (B3d, live-proven incl. bearer-token auth against `ghcr.io`).
  IO confined to `Kue/Module.lean` + `Kue/OciFetch.lean`; `Eval` /`Resolve` stay pure.
- **Load-time validation.** Import-name redeclaration (A2-y) and `let`/alias vs
  bare/hidden-field shadow across comparable scopes — BOTH directions (forward `e20af9a`;
  reverse via `Field.quoted`, 2026-07-04) — are rejected at parse/load with cue's message;
  parser strictness (`*(1|2)`, `__x`) spec-mandated rejects.
- **CLI.** `kue eval`, `kue export [--out yaml|json] [file|dir]` (stdin or arg), `kue
  version`, clean missing-file diagnostics + exit codes.

**Real-app status** (prod9 infra, read-only oracle) — drop-in status was demonstrated on
the {argocd, cert-manager} 2-app sample as of 2026-06-23; the broader corpus (lem, n8n,
x9, typesense) is the open eval-conformance front above:
- **cert-manager: content-identical drop-in, ~11.7s — the ONLY live canary.** Exports
  correctly at production fuel, byte-identical to `cue` modulo field-order #3. Runs IN-GATE
  via `scripts/check-realworld.sh` (sanitized, self-contained fixture).
- **argocd: content-identical drop-in, ~50.3s (2026-06-23) — HISTORICAL.** Exported
  content-identical (jq -S diff = 0) before being REMOVED from the infra checkout; the claim
  is not re-verifiable and stands as the record of the Bug2-5..2-14c chain's outcome.

The argocd milestone closed a 10-fix narrowing/close-once chain (**Bug2-5 → Bug2-14c**,
2026-06-22..23): definition multi-declaration close-once across reference / embed /
cross-package boundaries, use-site narrowing delivery to deferred def interiors,
unset-optional selection, and the `#Mixin` structural-disjunction let-local narrowing
(Bug2-14b/c). The blow-by-blow is HISTORY (`implementation-log.md`, `spec-conformance-audit.md`,
`git log`). Durable rulings that survived the chain are in Resolved/ruled-out below.

## Live Backlog (open work, ranked)

Correctness gates real-app adoption; cleanups are parallel-safe filler. The
**spec-conformance fixes** are owned by
[`spec-conformance-audit.md`](spec-conformance-audit.md) § Genuinely-open ranked backlog (the
authoritative ranked list — do NOT duplicate it here). Everything spec-conformance-HIGH is
DONE (the closedness family incl. SC-1b/1e + EMBED-CLOSE-1, the MEET-RESID-1/A#6 family, the
dyn-field family, D-area, regex, BI-1/BI-2, E#4, F-1/2/3, SC-4, Bug2-12 MUTUAL, EvalOps). The
lone open VALUE divergence is **NESTED-DISJ-MARK** (nested-disjunction outer-default
inheritance when the inner default dies) — a **DESIGNED-DEFERRAL 2026-06-23**: the fix needs a
3rd `Mark` state or a non-flattening nested-disj invariant, both LARGE + delicate → STOP rather
than risk default-selection. **SC-3** is a display-only spec-gap (multi-arm-default display
divergence). Full records: `spec-conformance-audit.md` + `cue-spec-gaps.md`.

**perf #7 frame-sharing across env-DEPENDENT evals — WON'T-FIX (2026-06-23,
measurement-driven).** A zero-risk content-addressed shadow measured the share ceiling:
cert-manager 0.045%, argocd 0.059%. The ~175× re-eval is real but NOT content-redundant (the
same shape is reached under genuinely-different observable bindings), so no sound frame-sharing
reclaims it — the residual wall is the irreducible cost of distinct content. Full data +
rejection argument: `kue-performance.md` + implementation-log.

### Ranked OPEN backlog

1. **B3d-6b (NETWORK-GATED) — the single remaining substantive registry slice.** `cue mod
   get/tidy` + requirement-graph fetch + `cue.sum` WRITE. Five legs (see § B3d track below).

2. **B2-A1 (latent, currently lossless) — pairs with typed-ellipsis.** `applyEvaluatedStructN`
   (`Eval.lean:330`) routes the patterns-present case through a meet that DROPS `tail`. Lossless
   today (the only tail a parsed struct carries is bare `...` = `.top`, a no-op to drop+re-supply);
   breaks the day typed-ellipsis lands. Thread `tail` through the pattern arm + a round-trip pin;
   land with any typed-ellipsis slice.

3. **scalar-embed provenance follow-ups (opportunistic).** Pins (3-level flatten, disj ops
   beyond `+` /`&`, composed select-into-F1-default) when next touching Lattice/Eval.

**LOW tail (opportunistic; none block adoption):**
- **e-followup** — timeless-comment sweep of `Tests/` (~20 clear code-history comments remain:
  `PresenceTests`, `TwoPassTests`, `ComprehensionTests`, `ModuleTests`, `YamlTests`,
  `ClosureTests`, `LatticeTests`, `EvalPerfTests`, `BuiltinTests`, `EvalTests`, `FixturePorts`).
  Convert on-touch or as a dedicated sweep.
- **item-3 testdata regroup (DEFERRED)** — sub-grouping `testdata/cue/{definitions,
  comprehensions}` into nested subdirs; high blast radius (`FixturePorts.lean`'s `fileName`
  strings are the join key, ~77 fixtures). Pick up as a dedicated careful slice or drop.
- **B3d-A2** DEFLATE/ZIP adversarial reject-branch pins; **B3d-B1** `Digest`/`Hash1` newtype
  (rides B3d-6b sum-write); **Mvs.solve main-pin** (rides B3d-6b); **`Kue/ModuleFetch.lean`
  carve** (trigger only if B3d-6b pushes the fetch cluster past ~200 lines); **kue-performance
  B3d note**.
- **A2-x (latent) — `importBinding` merge-asymmetry.** STAYS unobservable (the only collision
  that would exercise it is the one A2-y rejects at LOAD). No work; recorded so it is not
  re-investigated.

### Audit status — all filed fix-slices DISCHARGED

The **2026-07-02 two-phase audit** fix-slice batch is FULLY DISCHARGED — (a) TEST-HEALTH
retrofit + `scripts/check-test-health.sh`, (b) value-producing `| _ =>` enumeration (13
in-scope `Eval.lean` sites; a new `Value` ctor now fails exhaustiveness), (c) `Module.lean`
`partial def` waivers + list self-recursions rewritten structural, (d) `for`-over-non-iterable
type-error (`classifyForSource`, E#4), (e) timeless-comment sweep (non-test source), PA-1
(bottom-`for`-source propagation via `ForSourceClass.bottom`), B-AUDIT-refold-1
(`refoldEmbeddingsIfSelf` shared helper), PB-1 (`EvalBase → EvalDefer → Eval` carve — the tier
depends on base helpers the core-force also uses, so a 3-module split, not 1), PB-2
(`ClosednessTests`/`ResidualTests` split), PB-3 (`architecture.md` §5 edge note). Detail: log.

The **2026-07-03 two-phase audit** closed CLEAN, both phases, zero fix-slices filed. Phase A
(`08a537e..HEAD` eval batch, `a8d07b7`): A4 verified all five prior fix-slices landed in code
(none decayed); the L5-2 open-tail-operand closedness verdict re-derived SOUND (no
under-rejection across meet orders, 3-way conjunctions, nested, field-referenced). Phase B
(`7487d06`, A7 infra-in-scope rotation): module graph layering/cycles clean, the
`EvalOps → EvalBase → EvalDefer → Eval` carve matched by `architecture.md`; infra (`check.sh` /
`./lake`+`./lean` cap / strict-xfail quarantine / `check-realworld.sh` + sanitized cert-manager)
all sound; one LOW hole fixed inline (`check.sh` now shellchecks the `./lake`/`./lean` root
wrappers). Toolchain is Lean **v4.31.0** (`1d7fc37`). No open audit-filed fix-slice remains.

### Plan-only roadmap — resolved items (ruling + pointer; detail in the log + git)

1. **`truncate-primitive` (soundness hardening) — CLOSED.** One `EvalState.truncate` choke
   point (Step 1 done); the `withFuel` combinator RULED OUT (a lambda hides `fuel=n+1`, breaks
   `termination_by`).
2. **EvalOps extraction → `Kue/EvalOps.lean` — DONE (2026-06-22).** Pure scalar algebra carved
   out; import shape `EvalOps → {Builtin, Decimal, Regex}`, no back-edge.
3. **Test/fixture-org — splits DONE; fixture regroup DEFERRED (LOW tail above).**
   **TEST-HEALTH CONVENTION (durable, applies to ALL new/touched `Kue/Tests/*.lean`):** section
   headers are `--` LINE comments, never `/-- -/`/`/-! -/` block comments (a line comment cannot
   swallow the next theorem); every test module carries an end-of-file
   `#check @<last-theorem-per-section>` tripwire. `FixturePorts.lean` is generated data (exempt).
   Machine-enforced by `scripts/check-test-health.sh` (repo-wide retrofit landed; ≤1800-line cap).
4. **Field-ordering parity #3 — RATIFIED CLOSED: Kue keeps source order; parity DECLINED.**
   Spec silent (structs unordered, output order implementation-defined) → Kue's declaration order
   is the principled, test-pinned choice; `cue`'s cross-conjunct order is an undocumented
   internal-graph artifact. `cue-spec-gaps.md` RATIFIED row. Reopen only if a fixture demands
   cue's exact bytes (none does).
5. **Per-eval-cost perf frontier — CLOSED (2026-06-23).** Hash digest DONE (119s → ~30s
   cert-manager); perf #7 safe wins landed; frame-sharing WON'T-FIX (above); per-eval constant
   floor-characterized; multi-ref-cyclic flatten fan-out FIXED (visited-path bound). Only
   remaining lever is user-controllable flatten/shorten. Full data: `kue-performance.md` + log.
6. **Borderline / LOW open items — see § Ranked OPEN backlog + LOW tail above.**
   `module-file-scoped-imports` DONE 2026-07-03 (`53fe3cc`): imports FILE-SCOPED via a synthetic
   NUL-separated label (`fileScopedImportLabel`, uncollidable) + a shadow-aware pre-merge ref
   rewrite (`rewriteFileImportRefs`) riding the same `mapRefsValueWithFuel` traversal as
   reference resolution; package FIELDS still merge and stay shared. All three faces green
   (collision + shadow seeds graduated; sibling-invisible pinned as an `.err` fixture; binder-form
   shadow guard byte-identical to cue). Other DONE item-6 members (B2-A2, B-AUDIT-refold-1,
   scalar-embed-with-decls, TL-1/TL-2, import-eager-closedness, parser-strictness, release-tooling,
   DRY `selectEvaluatedField .disj`, value-rewrite catch-all enumeration, B3, A2-y,
   aliased-builtin/constant resolution, `resolveEmbeddedDisjDefault` narrowing): see log.
7. **CLI / entry-UX.** Bare `kue` prints help; stdin eval explicit (`kue eval`) — Entry-UX fix
   DONE (2026-06-24). **NEW SCOPED OBJECTIVE (awaiting user direction — do NOT self-start):** the
   broader cue-aligned CLI surface (`vet`/`fmt`/`def`, a `-` explicit-stdin marker, flag parity).
   Known DEFERRED: `kue --version` reports `0.1.0-alpha`, not the dated tag — defensible as-is.
   **Module-fetch architecture — DECIDED (2026-06-25): full Lean 4, NOT a Go frankenstein.** The
   cgo Go-shell + Lean-engine spike was REJECTED by chakrit (leaky seam vs correctness +
   human-traceability); do not re-spike. See `docs/decisions/2026-06-25-lean-engine-embedded-in-go-via-cgo.md`.

## B3d track — CLOSED (audit history distilled 2026-06-26)

The registry/OCI module-fetch track (decision:
`docs/decisions/2026-06-25-registry-fetch-via-curl-subprocess.md`) landed end-to-end.
Modules: `Registry` (CUE_REGISTRY parse + module→OCI-ref + cache-path authority), `Oci`
(manifest parse + URL/curl-arg builders), `OciAuth` (bearer-token flow parsing), `OciFetch`
(the sole `IO.Process` curl edge + the three integrity gates), `Sha256` (FIPS 180-4 + `h1:`
dirhash), `Inflate` (RFC 1951 DEFLATE), `Zip` (PKWARE + CRC-32), `Semver` (Go `x/mod/semver`
port), `Mvs` (pure MVS solver), and `Module.lean` wiring (`fetchAndCacheModule` + atomic
cache-write). B3d-1...B3d-5 (+5a/5z), B3d-6a, B3d-A1, and B3d-7 (OCI bearer-token auth — proven
LIVE against real `ghcr.io` for `prodigy9.co/defs@v0.3.19`) are DONE. Per-slice detail:
`implementation-log.md` (71+ B3d entries) + git.

Both 2026-06-26 audit rounds closed **HEALTHY**: module graph is a clean DAG (IO confined to
`OciFetch`+`Module`; `Eval`/`Resolve`/`Value` import ZERO B3d module); the three integrity gates
(blob `sha256:` digest, zip CRC-32+size, `cue.sum` `h1:`) are enforced and unbypassable on the
production path; inflate is total (fuel-bounded, malformed → typed-error). Totality
`#print axioms`-pinned (stdlib axioms only). 🔒 Secret hygiene (B3d-7): a credential/token lives
only in curl argv + in-memory strings, never logged/persisted; errors report outcomes, never the
secret. `Mvs.solve` is an ACCEPTABLE staged primitive (pure, total, fully `native_decide`-pinned,
reachable from `MvsTests`) unwired only because the resolver edge is network/human-gated — filed
as B3d-6b, not stranded.

**Open B3d items (ranked):**
- **B3d-6b** (NETWORK-GATED, the single remaining substantive slice) — `cue mod get/tidy`
  + requirement-graph fetch + cue.sum WRITE. Five legs, all needing live registry egress
  or the command surface: (1) fetch each dep's `module.cue` `deps` block to BUILD the
  `RequirementGraph` (curl edge is bearer-auth-capable via B3d-7); (2) OCI `.../tags/list` for
  "latest"/major→concrete; (3) `cue mod get`/`cue mod tidy` command parse + dispatch; (4) wire
  `Mvs.solve` into the resolver (replace lenient per-hop resolution with one up-front MVS
  build-list) GATED ON a diamond-divergence fixture; (5) `cue.sum` WRITE via
  `Module.atomicWriteBinFile` (the B3d-3 dirhash + B3d-A1 atomic primitive both already exist).
- **B3d-A2** (test-strength, LOW) — pin the DEFLATE/ZIP adversarial reject branches (invalid
  Huffman code, distance-too-far-back, STORED LEN/NLEN, fuel exhaustion, bad CD sig, unsupported
  method, CRC/size mismatch); only BTYPE=3 is pinned today.
- **B3d-B1** (type-leverage, LOW — rides B3d-6b) — `Descriptor.digest`/`cue.sum` `h1:` are
  `String` with an unenforced format invariant; a `Digest`/`Hash1` smart-constructor newtype
  earns its keep at B3d-6b's sum WRITE boundary. YAGNI until that second consumer exists.
- **`Mvs.solve` main-pin** (philosophy-clean, LOW — rides B3d-6b) — `solve` silently pins `main`
  to `main.version` even when the graph names a higher version of main's path (cue PANICS there).
  Make it unrepresentable or a typed error when the resolver wiring lands.
- **`Kue/ModuleFetch.lean` carve** (architecture, conditional) — `Module.lean` is NOT yet
  outgrowing its home; the fetch/cache cluster (~90 lines) is coherent. Trigger: if B3d-6b pushes
  that cluster past ~200 lines or adds a distinct command-dispatch responsibility, carve then.
- **`kue-performance.md` B3d note** (doc, LOW) — inflate is O(output) fuel-bounded; fetch latency
  is curl/network-dominated, off the eval hot path. Fold into a coming B3d slice.

## Resolved / ruled-out (recorded so they are not re-raised)

### Audit-round history (all HEALTHY; per-round detail in implementation-log.md + git)

Every two-phase audit round 2026-06-21..07-03 closed HEALTHY/CLEAN; each round's full write-up
is an implementation-log entry + its own commit. Rounds: `1bd93d8..fc5456d` +
`9afd54c`-baseline Phase-B (2026-06-25, B3d foundation); `890d453..2bd75eb` (A2-y);
`e2d8868..4431597` (parser-strictness + release-tooling); `db8700f..HEAD` (nested-disj-mark
deferral + disj-select DRY); `735dc10..0459beb` (flatten-bound + SC-4); `32643f5..2bbdb05`
(Bug2-12 MUTUAL); `fccab69..6f77bfe` (Bug2-12 + missing-field-selection); `50a0db3..14fb23e`
(perf #7 safe wins); `20b8397..32ddfda` (catch-all refactor + embed-disj-arm-closedness);
`f40dd9c..4b24902` (B3d-7 + eval-L1/L2); the 2026-07-02 two-phase audit (fix-slices a–e + PA/PB,
all discharged); the 2026-07-03 two-phase audit (`a8d07b7`/`7487d06`, both CLEAN). The
resilience/retrospective pass (once flagged OVERDUE) rode the `890d453..2bd75eb` batch; its
learnings live in `failure-modes.md` + `slice-loop.md`.

**🎯 CONSOLIDATED-COMPLETE STATE (2026-06-23) — partially RETRACTED 2026-06-28.** The
{argocd, cert-manager} 2-app sample was a content-identical drop-in and the per-eval perf
frontier CLOSED; a root-A soundness over-accept was found after, and the broader prod9 corpus
opened the eval-conformance front (L1–L5, now COMPLETE — see § Prod9 eval-conformance campaign).
Released `v0.1.0-alpha.20260623` (3 platforms, race-safe tooling).

### Durable whole-graph facts (a future audit re-verifies these)

The module graph is ACYCLIC + strictly layered (`Builtin → {Lattice, Regex, Decimal,
Base64, Json, Yaml, CaseTable}`, NO `Eval`/`EvalOps` edge; `EvalOps → {Builtin, Decimal,
Regex}` no back-edge; the evaluator is the carved chain `EvalBase → EvalDefer → Eval`, with
`Eval → {Builtin, Decimal, EvalOps, Lattice, Regex, Normalize}`; `Lattice → {Value, Regex}`;
`Runtime → Eval`; `Module → {Parse, Runtime, Registry, OciFetch, Zip, Sha256}`;
`OciFetch → {Oci, OciAuth, Base64, Sha256, Registry}`; `Cli → Runtime`; `Normalize → Value`).
The marshalling builtins are a deliberate forward edge into export (`Builtin → Json → Manifest`,
`Yaml → Json`) — legitimate layering, not a cycle. Cleanliness sweeps clean (no
`sorry`/`panic!`/`unreachable!`/`.get!`-in-pure-code, no dead code, no stale markers;
`partial def`s are the `Parse.lean`/`Module.lean` carve-outs only, each waived; `Eval`+`Lattice`
FULLY total). Test-health guarded by the TEST-HEALTH CONVENTION + `check-test-health.sh`.

### Durable rulings (one paragraph each; do not re-litigate)

- **Walker / normalizer dedup family — FULLY CLOSED.** The walkers were NEVER one problem
  — three distinct walker families + a separate normalizer pair, different
  mechanisms/result-types/recursion-domains/termination measures; folding them under one
  abstraction is a false "stuff they all do" extraction. AD4-1 + A-EN3 DONE; DRY-1 RULED
  OUT; AD2-1 RESOLVED (unified); `embedChainAny` SHARED (`0619097`). No open members.
- **CARRIER-DECL-SELECT (DRY, LOW) — DONE 2026-06-22.** `selectFromDecls` extracted;
  all six byte-identical Eval sites routed through it; `Runtime.lookupField?` is a
  DIFFERENT operation, deliberately NOT shared across the seam.
- **`Eval.DefDeferral` carve — DONE (PB-1, 2026-07-02).** The trigger FIRED at 4609 lines;
  carved into `EvalBase → EvalDefer → Eval`. The core-force `mutual` block is NEVER split (its
  `termination_by (fuel, tag, length)` cannot cross a module boundary), so the carve bought FILE
  headroom via the lower `EvalBase` layer, not mutual-block headroom.
- **`resolveDefField?` skeleton-share — RULED OUT (Phase-B 2026-06-23).** The ~6
  def-resolution functions return structurally different things from the same lookup,
  gated differently, and the FRAME each captures is load-bearing and irreducibly
  different (the `crosspkg_defofdef_wrongframe_witness` hazard). KEEP SEPARATE.
- **inject-family DRY (`injectEmbedSiblingNarrowings` vs `injectLetLocalNarrowings`) —
  RULED OUT (Phase-B 2026-06-23).** The nested-`let` recursion DISPATCHES TO A DIFFERENT
  WALKER by design (embed→let, gated on `letPromotedReadLabels`) — a combinator
  parameterized on the read-labels leaf would change the milestone splice's gating, a
  soundness change. KEEP SEPARATE.
- **`mergeFieldsWith` consolidation — RULED OUT (Phase-B 2026-06-23).**
  `mergeFieldListWith` ↔ `mergeConjFields` already share `mergeFieldIntoWith`;
  `canonicalizeFields` cannot join under a `Value→Value→Value` combiner (it dispatches on
  merged field-class) and MUST not: the within-operand-union vs cross-operand-meet
  distinction lives in WHICH function the caller invokes (the Bug2-8 hazard). KEEP SEPARATE.
- **close-each vs close-once (Bug2-12 flatten path vs Bug2-7 conj-fold path) — RULED:
  SHARED PRIMITIVE, DISTINCT SEAMS.** Both defects are fixed by the ONE close-once
  primitive `mergeDefinitionDecls`; the two call contexts are genuinely distinct seams and
  merging the functions is forbidden by the `mergeFieldsWith` ruling.
- **`embedChainAny` (embed-chain walker share) — RULED: SHARE, applied `0619097`.**
  `bodyNeedsDefer`/`embedBodyEmbedsDisjDeep` differ only in a PURE non-recursive leaf
  predicate the combinator owns; the recursion stays lexically in the combinator, so
  `termination_by fuel` infers unchanged — the AD4-1 shape, NOT the DRY-1 trap.
- **CARRIER share/no-share (`.embeddedScalar` vs `.embeddedList`) — RULED (Phase-B
  2026-06-22): keep DISTINCT constructors** (a merged carrier would force runtime
  scalar-vs-list re-discrimination at every output/iteration site); do NOT share the meet
  seam (3-callback combinator = lambda-hides-`fuel+1`); DO share only the decl-selection
  seam (CARRIER-DECL-SELECT, done).
- **Escape-helper "duplication" (`escapeJsonChar` vs `escapeCueStringChar`) — NOT A
  FINDING (Phase-B 2026-06-22).** Five trivial shared arms; the substance diverges (JSON
  control-char escaping vs CUE verbatim). Keep separate.
- **AD2-1 (disjunction-normalizer lone-arm rule) — RESOLVED 2026-06-21, UNIFIED.** A
  lone default `*v` is VACUOUS (value-identical to bare `v` in every onward meet);
  `normalizeDisj`'s lone-arm collapse is now mark-agnostic; SC-3's "keep marked" display
  contract narrowed to MULTI-arm defaults.
- **DRY-1 (let-walker dedup) — RULED OUT (attempted, reverted).** The three let-walkers
  share no combinator — different carriers/visited-sets/follow-mechanisms, and routing
  the nested-let recursion through a callback breaks structural-recursion inference (the
  lambda-hides-`fuel+1` trap). Do not re-file unless a catamorphic 4th walker lands.
- **BI-EFF (effectful-builtin seam) — trigger standing.** `list.Sort`/`SortStable` are
  the only effectful builtins, one inline `runSort` case in `Eval`. Extract a named
  `evalEffectfulBuiltin?` seam AS THE FIRST STEP of the slice that lands the SECOND
  effectful builtin; a name→closure registry is rejected (less traceable than a `match`).
- **F-CASE-ARCH — RULED; both halves discharged.** The generated `Kue/CaseTable.lean`
  STAYS committed (reproducible, reviewable, offline build); oracle-as-data-source is an
  ADR ([`../decisions/2026-06-20-oracle-as-data-source.md`](../decisions/2026-06-20-oracle-as-data-source.md)):
  oracle = sound DATA SOURCE for an externally-standardized domain, NEVER a correctness gate.
- **FOUR-parallel-classifiers DRY — RE-RULED at four: keep SEPARATE.** They disagree on
  the partition (`.prim`/`.struct`/`.disj`/`.structComp` land differently per classifier);
  only the shared default-collapse pre-step was extracted (`collapseDefaultDisjunction`).
  Do not re-raise at five.
- **AD3-1 / Regex extraction — DROPPED (stale).** `Kue/Regex.lean` is already a verified
  true leaf; the NFA rebuild superseded the framing.
- **AD3-4 (bottom-payload newtype) — RULED OUT (over-engineering).** The invariant is
  enforced by construction at every site; a `BottomValue` newtype would ripple for safety
  already bought.
- **`Order.lean` (subsumption) — DELIBERATE test-only oracle**, imported only by
  `Tests/*`; NOT dead code and NOT duplicated. Recorded so a future audit does not re-flag it.

## Pointers (history + reference for anything dropped)

- **Completed-slice history + verification record:**
  [`../reference/implementation-log.md`](../reference/implementation-log.md)
  (chronological, one entry per commit) and `git log`. Every audit batch and design spike
  is recorded there — this plan holds only the live roadmap.
- **Spec-conformance fix backlog (authoritative):**
  [`spec-conformance-audit.md`](spec-conformance-audit.md) § Genuinely-open ranked backlog.
- **CUE-divergence record:**
  [`../reference/cue-divergences.md`](../reference/cue-divergences.md).
- **CUE spec-gap record:**
  [`../reference/cue-spec-gaps.md`](../reference/cue-spec-gaps.md).
- **Decisions:** [`../decisions/`](../decisions/) (compatibility target,
  correctness-over-perf, numeric model, oracle-as-data-source, registry transport).
- **Slice loop + audit cadence:** [`../guides/slice-loop.md`](../guides/slice-loop.md).
- **Performance guide:** [`../guides/kue-performance.md`](../guides/kue-performance.md).
- **Status page (human-facing, served):** [`../../www/index.html`](../../www/index.html) —
  single human-scannable status page, OUTSIDE the agent design-record; refreshed on
  plan-hygiene passes.
- **CUE semantics reference:** [`../reference/cue-language-guide.md`](../reference/cue-language-guide.md);
  [`architecture.md`](architecture.md) + [`compat-assumptions.md`](compat-assumptions.md).
- **Latest session state / next step:** the most recent breadcrumb in
  [`../notes/`](../notes/).
