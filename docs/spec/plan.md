# Kue Plan

The live implementation roadmap. Kept small, current, and actionable — one focused slice
at a time. The full record of completed slices lives in
[`../reference/implementation-log.md`](../reference/implementation-log.md) (chronological,
one entry per commit) and `git log`; this file holds only where we are and what's next. A
periodic plan-hygiene pass distills it back to the live roadmap (history → log + git); see
[`../guides/slice-loop.md`](../guides/slice-loop.md). Last distilled 2026-06-23.

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

## Current front — prod9 cue-compat eval conformance

`apps/{lem,n8n,x9,typesense}.cue` (via `defaults.#Basics`/`packs.#WebApp`,
`prodigy9.co/defs@v0.3.19`) bottomed in kue where cue/the spec are clean; cert-manager clean.
Peeled in two layers:

- **Layer 1 — Self.#hidden in list embeddings — FIXED (2026-06-28).** A `Self`-aliased list
  embedding reading a hidden field contributed by a sibling def-embed (`[{name: Self.#name}]`)
  resolved to `_|_`: the embedding-`Self` two-pass scanned only static fields, never the
  embedding the read sits in. Fix: re-evaluate embeddings against the augmented frame when an
  embedding reads a sibling-embedded `Self.<L>` (`embeddingsReadEmbeddedSelf`, both struct-eval
  arms). Wild fixture `testdata/wild/self-hidden-in-list-embed/` red → green; 5 new pins. A
  faithful minimal `#Basics`-shaped repro exports clean once `#registry` is concrete — proving
  the chained `Self.#components.X` read now resolves for all four apps.
- **Layer 2 — default-disjunction not concretized in string interpolation — FIXED
  (2026-06-29).** `#registry: string | *"ghcr.io"` read into `"\(Self.#registry)-pull-secret"`
  kept the interpolation incomplete. Fix: `.map collapseDefaultDisjunction` over evaluated parts
  in the `.interpolation` eval arm (`Kue/Eval.lean`), reusing the shared default-shedding
  projection. Wild fixture `testdata/wild/default-disj-in-interpolation/` unquarantined → green;
  5 new `native_decide` pins. The `namespace.yaml` subtree of all four apps now exports clean
  (`"ghcr.io-pull-secret"` resolved).

  **Phase-A audit (2026-06-29, batch `f40dd9c..4b24902` = B3d-7 auth + eval-L1 + eval-L2) —
  HEALTHY, closed.** Re-traced all three slices against the philosophy + spec.
  - *Secret hygiene (highest priority): no leak on any path.* Auth secrets live only in curl argv
    + in-memory `String`s; `TokenCache` is an `IO.Ref`, never persisted; `resolveCredential` and
    every error path report outcomes, not secrets. All offline tests use synthetic creds/base64;
    `check-ghcr-live.lean` asserts only public digests. Tree + all three commits grep clean for
    token/PAT/key shapes.
  - *Auth correctness:* `parseChallenge` (order/quote/whitespace/case/comma-in-scope tolerant,
    Basic rejected, realm required), `parseTokenResponse` (`token` wins over `access_token`),
    `credSourceFor` precedence (`credHelpers` > `credsStore`+auths-entry > inline > none),
    strict-canonical `base64Decode` (rejects non-zero discarded bits), anon-token fallback, and
    an unsatisfiable 401 → typed error (no hang/swallow) — all pinned, conform to the Docker
    token-auth flow.
  - *Eval-L1 no over-fire:* `embeddingsReadEmbeddedSelf` fires only when (a) an embedding
    contributed a label no static field declares AND (b) some embedding value reads that label
    through the host `Self` alias at the right depth/index — byte-identical (gate off) for plain
    embeds. Spec basis: embedding = unification, so the hidden field is in scope however
    contributed. Adversarial pins sufficient (genuine `#u:1&2` still bottoms; plain non-list
    Self.#hidden resolves; list-embed-without-self-hidden unaffected).
  - *Eval-L2 no over-shed:* `.map collapseDefaultDisjunction` reuses the SAME shared projection as
    dyn-label/if-guard/scalar (no behavior fork); identity on non-`.disj`, collapses only a unique
    default, leaves ambiguous disjunctions `.disj` (stay incomplete). Pins sufficient
    (shed / no-default→bottom / unification-override / multi-default→bottom / plain-ref).
  - *Totality / axioms:* no new `partial`/`sorry`/custom axiom — touched eval + auth defs depend
    only on `propext`/`Classical.choice`/`Quot.sound`. `collapseDefaultDisjunction` is
    exhaustively enumerated (no catch-all → a new `Value` ctor forces a decision).
  - *`check_wild_fixtures` + `.known-red`:* sound — the green gate enforces every non-quarantined
    wild fixture (missing `.cue` → fail; mismatch → fail); a `.known-red` dir is printed +
    skipped, removing the marker re-arms it. Both fixtures now enforced (neither quarantined).
  - *No Violations.* One Borderline (non-blocking): a stray untracked `repro-bottom.cue` debug
    scratch file sits at repo root — working-tree litter from the L1/L2 work, not committed, not a
    secret. Left in place (AFK: no untracked-file deletion); flag for a human to `rm`.
- **Layer 3 — let/ref-delivered list-carrier meet bottomed — FIXED (2026-06-29).** A
  list-embedding carrier struct (`{let ls=…, [1,2]&ls}` / `{#name:"web", [1,2]}`) whose enclosing
  struct carries ONLY non-output decls (a `let`/`Self=` binding, a hidden/def field) bottomed when
  its list-embedding body was delivered through a `let`/reference. The embed evaluates to an
  `.embeddedList`, then the enclosing decls-only struct meets it — operand order `.struct,
  .embeddedList` hits the `leftLike, .embeddedList` meet arm (whose `asListPair` fails on a struct)
  and routes to `meetCore` → `.bottom`, SHADOWING the `listLike, .struct …` list-collapse arm.
  Inline (`{#name:"web",[1,2]}`) worked because the embed is still a `.list` (not yet an
  `.embeddedList`), so it hits the collapse arm directly. **Fix is at the EVAL layer, NOT meet**
  (`meetEmbeddingsWithFuel`, `Kue/Eval.lean`): a list-embedding collapse mirroring the existing
  `{5}`→`5` scalar collapse — when the host (`current`) is a decls-only struct (no output field)
  and its evaluated embedding is list-shaped (`asListPair`), build the `.embeddedList` carrying the
  host's `declFields` (merged with the embed's own decls). Provenance is the soundness key:
  `evaluated` is the host's OWN embedding, so this is NOT the `{#a,[1,2]} & {#b}` case (a SEPARATE
  foreign decls-struct conjunct) — cue v0.16.1 rejects THAT as a list-vs-struct conflict, and
  `meetCore` still bottoms it (two existing pins assert this; a meet-layer fix would have
  over-collapsed them — that was the red herring this slice ruled out). Wild fixture
  `testdata/wild/let-list-meets-carrier/` (`f`/`e`/`f2`) red → green; decls stay selectable
  (`.#name` → `"web"`, cue-exact); genuine list conflicts (`[1,2]&[3,4,5]`, `[1]&["x"]`,
  let-delivered length conflict, carrier & extra regular field) all still bottom, matching cue.
- **Root A (SOUNDNESS over-accept) — def closedness through embedded disjunction — FIXED.** A
  *definition* embedding a structural disjunction (`#M: {{a:int} | {kind:string}}`) lost its
  closedness through the arms, so kue ACCEPTED what cue/spec REJECT (`#M & {kind:"k"}` → kue
  "ambiguous, both arms"; cue/spec → `{kind:"k"}`, the `{a:int}` arm closed-rejects `kind` → bottom
  → survivor concrete). Root cause: `normalizeDefinitionValueWithFuel`'s `.structComp` arm left ALL
  `comprehensions` (embeddings) untouched — correct for struct/ref embeds (they UNION labels, must
  not impose closedness), but WRONG for a disjunction embedding whose arms are struct LITERALS in
  the def body: those must close exactly as the non-embedded `#M: {a:int} | {kind:string}` arms do
  (the `.disj` arm already closes them). Empirically pinned via `dbg_trace`: the arms arrived
  `regularOpen` at the embed-disj-arm-close site (`meetEmbeddingsWithFuel`'s `.disj` branch,
  `Kue/Eval.lean`), so the per-arm `closeEmbeddedOver` saw `armOpen=true` and left them open. Fix
  (`Kue/Normalize.lean`, def-body `.structComp` arm): recurse the CLOSING normalizer
  (`normalizeDefinitionValueWithFuel`) into a `.disj` embedding so each struct-literal arm closes;
  a `.refId`/non-disj embedding is a no-op pass-through (no over-close, referenced-def arms keep
  their own closedness). Over-correction guarded: the NON-definition control (`M: {{a:int} |
  {kind:string}}`) goes through the spine (non-closing) walker → arms stay OPEN, both survive,
  UNCHANGED (cue-exact incomplete). Wild fixture `def-closedness-thru-embedded-disj` red → green.
  Adversarial pins (all cue-cross-checked): `#N:{{a:int}|{b:int}} & {a:1}` → `{a:1}` (both-allowed,
  no over-close); `#M & {zzz:1}` → bottom (all arms violated); `#X:{{n:int}|{s:string}} & {s:"x"}`
  → `{s:"x"}` (closed `{n:int}` arm rejects `s`); plain `#C:{x:int} & {x:1,y:2}` → bottom,
  `#C & {x:1}` → `{x:1}` (unchanged). cert-manager canary 0; lem/n8n/x9/typesense still fully
  bottom (L4 unchanged — root A was a prerequisite, not the L4 fix). **This unblocks L4** (the
  imported `#WebApp` shape relies on closedness distributing through its default disjunctions).
- **disj-arm-list-embed-dropped (L4) — LANDED.** A struct embedding a disjunction with a
  list-shaped arm dropped that arm when the host is a list-carrier → spurious bottom
  (`out: #Emit & #Mixin & {#name:"web",[...]}` where `#Mixin: {{[...]} | {kind:string}}`).
  Root cause: the embedded-disjunction distribution arm (`meetEmbeddingsWithFuel`'s `.disj`
  branch, `Kue/Eval.lean`) met each arm against the host with the PLAIN `meet`, which treats a
  list-shaped arm (`{[...]}`) against a list-carrier host as struct-vs-list and bottoms it →
  `normalizeDisj` prunes the live list arm → overall bottom. Fix: when the plain meet bottoms
  AND the arm is list-shaped (`asListPair`), re-run the arm through the single-embedding sub-fold
  (`meetEmbeddingsWithFuel … [arm]`) — the same path the `conjDisjArms?` branch already uses — so
  the host's OWN list-collapse fires. Gated to list-shaped arms (struct-arm closedness reclosing
  untouched) and to the host's own embedded disjunction (provenance sound: a foreign list-vs-struct
  conjunct stays a `meetCore` conflict, never reaches here). Root A (`c451245`, closedness
  propagating into embedded disjunction arms) was the prerequisite that let this land soundly —
  **A+L4 pair complete.** Wild fixture `disj-arm-list-embed-dropped` red → green (unquarantined).
  Adversarial pins (cue-cross-checked): `1&[2]`, `{x:1}&[2]`, `{#a,[1,2]}&{#b}` foreign → all
  bottom; all-arms-bottom disj → bottom; root-A def-embed-disj closed-arm-violation → still bottoms
  (A not re-broken). **L5 (imported `#WebApp` app carrier) still OPEN** — see next bullet.
- **Layer 4 / L5 — imported `#WebApp` carrier still bottoms — OPEN (next slice).** Layer 3 fixed the
  minimal+adversarial captures, but the four real apps STILL bottom (re-sweep UNCHANGED:
  lem 188, n8n 322, x9 449, typesense 223; cert-manager 0, gateway 0 both-bottom). The residual
  is in `packs.#WebApp` itself (a `Self={…}` def embedding `attr.#Metadata`/`attr.#Hosts`,
  emitting a top-level `[Self.#components.env, …]` list) wrapped in the `let web = #WebApp & {…};
  [...]` carrier — and it bottoms even WITHOUT `parts.#UseKeel` (bisected: `packs.#WebApp & {…}`
  alone). A self-contained local reduction of the `Self=`+nested-`#components`-list+embed-def shape
  exports CLEAN (the layer-3 fix covers it), so the trigger is a subtler facet of the imported
  def (candidates: `attr.#Metadata`/`attr.#Hosts` carrier embeddings, the `#replicas: int | *1` /
  `#env: … | *{}` default disjunctions interacting with the list emit, or a cross-import frame
  detail). NOT yet a self-contained wild fixture — needs dedicated bisection from the real app
  graph (module-free reductions flip polarity, as in layer 3). First job of the next slice:
  isolate a faithful minimal repro, then capture + fix.

## Standing Capabilities (what Kue does now)

The semantic core is broad and oracle-checked against `cue` v0.16.1
(`/Users/chakrit/go/bin/cue`). Currently working, cue-exact modulo the tracked
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
  guard is a TYPE ERROR, presence-test `X !=/== _|_` drops. Scalar struct-embedding
  collapse (`{5}`→`5`) at embed-eval.
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
  `"location:identifier"` (F-3, `Import.packageName`). IO confined to `Kue/Module.lean`;
  `Eval` /`Resolve` stay pure. (Registry/OCI fetch deferred — prod9 is fully on-disk.)
- **CLI.** `kue eval`, `kue export [--out yaml|json] [file|dir]` (stdin or arg), clean
  missing-file diagnostics + exit codes.

**Real-app status** (prod9 infra, read-only oracle) — TWO content-identical drop-ins:
- **cert-manager: content-identical drop-in, ~11.7s.** Exports correctly at production fuel,
  byte-identical to `cue` modulo field-order #3 (the item-7 cache-hash digest collapsed the
  ~119s O(N²) wall; the Bug2-x close-once/frame-id chain + perf #7 brought it to ~11.7s).
- **argocd: content-identical drop-in, ~50.3s (2nd prod9 real app; 2026-06-23).** Full
  `apps/argocd.cue` exports CONTENT-IDENTICAL to `cue` (jq -S diff = 0, sorted-key, modulo
  field-order #3). The whole manifest byte-matches cue — no on-path layer hides behind a sound
  drain. The ~50.3s wall is now a PURE perf concern (no correctness divergence) — see perf #7
  (the ranked leader below).

The argocd milestone closed a 10-fix narrowing/close-once chain (**Bug2-5 → Bug2-14c**,
2026-06-22..23): definition multi-declaration close-once across reference / embed / cross-package
boundaries, use-site narrowing delivery to deferred def interiors, unset-optional selection, and
finally the `#Mixin` structural-disjunction let-local (`_patch.kind`) receiving the host's `kind`
narrowing through a single-closure embed chain (Bug2-14b — wrong-frame gate) and a multi-closure
`.conj` fold (Bug2-14c — two-pass sibling-field splice). The full blow-by-blow (every Bug2-N
commit, mechanism, repro, soundness boundary) is HISTORY — in `implementation-log.md`,
`spec-conformance-audit.md`, and `git log`. Durable rulings that survived the chain are in
Resolved/ruled-out below.

## Live Backlog (open work, ranked)

Correctness gates real-app adoption; cleanups are parallel-safe filler. Two backlog
owners: the **spec-conformance fixes** are owned by
[`spec-conformance-audit.md`](spec-conformance-audit.md) § Consolidated fix backlog (the
authoritative ranked list — do NOT duplicate it here); the **plan-only roadmap** below
owns the non-spec-conformance work.

**🎯 MILESTONE — the spec-conformance backlog is EMPTY (2026-06-23).** Every correctness
item is RESOLVED; the genuinely-open set is now perf #7 (a perf lever, WON'T-FIX) + SC-3 (a
display-only spec-gap) + the item-6 LOW tail — no soundness-bearing work remains. Both prod9
real apps (argocd + cert-manager) are content-identical drop-ins (jq -S diff = 0). This closes
the spec-first re-audit started 2026-06-19; conformance is now demonstrated, not aspirational.

**Spec-conformance backlog — see `spec-conformance-audit.md` § Genuinely-open ranked
backlog (authoritative; do NOT duplicate the detail here).** Everything
spec-conformance-HIGH is DONE (the closedness family incl. SC-1b/1e + EMBED-CLOSE-1, the
MEET-RESID-1/A#6 family, the dyn-field family, D-area, regex, BI-1/BI-2, E#4, F-1/2/3, the
4 ratifications). The BI-2 family is **COMPLETE** (math.Pow + math.Sqrt cover their full real
domain in EXACT DECIMAL, Float correctly AVOIDED, axiom-clean). **EvalOps** (item 2) DONE
2026-06-22. Remaining spec-conformance: **NONE open** — **SC-4 RESOLVED 2026-06-23** (nested
HIDDEN/LET plain-struct closedness on direct def-meet: case (b), kue under-closed → fixed; the
closing field-walker twin's hidden+let arms now recurse the closing walker; conforms to cue on the
direct paths, one SC-2b-family bound-select divergence recorded). SC-3 is a recorded
spec-gap only (multi-arm-default display divergence). **NESTED-DISJ-MARK** (nested-disjunction
outer-default inheritance when the inner default dies, tier-2) is a **DESIGNED-DEFERRAL 2026-06-23** —
the lone open VALUE divergence — adjudicated to a spec-verified two-tier rule but deferred (the fix
needs a 3rd `Mark` state or a non-flattening nested-disj invariant; both LARGE + delicate, STOP rather
than risk default-selection). Full record: `spec-conformance-audit.md` § Genuinely-open #2 +
`cue-spec-gaps.md` NESTED-DISJ-MARK row. The full Bug2-5..2-14c chain, AD2-1,
DRY-1, and CARRIER-STRUCT-MEET are RESOLVED — durable rulings in Resolved/ruled-out below; the
blow-by-blow in `implementation-log.md` + `spec-conformance-audit.md` + git. **Bug2-12 MUTUAL
RESOLVED 2026-06-23** (mutual-recursion closed-def closedness): adjudicated to the
lattice-principled transitive-union allowed-set — Kue ADMITS transitively-declared fields, REJECTS
genuine extras; `cue` over-rejects the def's own field (a cue bug, recorded as a cue-divergence).
FIXED via `defSlotInClosedCycle`; canaries jq-S=0 (prod9 has zero recursive defs — neutral).

**perf #7 — frame-sharing across env-DEPENDENT evals: DESIGNED-AND-DEFERRED → WON'T-FIX
(2026-06-23, measurement-driven REJECTION).** The proof-first gated slice MEASURED the share
ceiling before touching the soundness core — and the data kills the approach, so nothing shipped
(correct outcome, no Violation risk taken). Method: a zero-risk content-addressed SHADOW of
`satCache` keyed on the FULL env CONTENTS (compared by structural `BEq`, never read by the result
path) counting how many `satCache`-miss core evals a content-addressed env key would COLLAPSE.
Result on the whole-root export: **cert-manager 144 / 317,788 = 0.045%**; **argocd 288 / 486,773 =
0.059%**. The ~175× re-eval is REAL but NOT content-redundant: the profile's `distinctShapes≈4763`
counted SHAPE similarity (digest-depth 8); the cache correctly keys on CONTENT (sound
ids-as-content-proxy). The ~175 frame envs the same shape is reached under carry ~175
GENUINELY-DIFFERENT observable bindings (distinct resource fields + use-site narrowings) — distinct
evaluations, not id-divergence of identical content. Collapsing them is a FALSE SHARE (wrong value),
which is why the ceiling is ~0%. **No sound frame-sharing widening can reclaim the ~175× — it is the
irreducible cost of distinct content.** The proof obligation is moot (the share is empirically empty
AND unsound where non-empty). perf #7's frame-sharing leg is CLOSED. Live perf frontier rotates to
the per-eval CONSTANT / COUNT (item-6 LOW tail or a future per-eval-cost slice) — the residual ~50s
is a genuinely-large distinct-eval population, addressable only by lowering per-eval cost or the
eval count (flatten/shorten chains — the user-controllable lever), NOT by cross-env sharing. Full
data + the rejection argument: `kue-performance.md` (perf-#7 frame-sharing DESIGNED-AND-DEFERRED
block) + implementation-log (perf #7 frame-sharing slice).

### Plan-only roadmap (not in the spec-conformance backlog)

Sequence after the spec-conformance correctness work: bank cheap-ready cleanups, then the
perf frontier (#7 residual), then the deeper parity gap (#6).

**Numbered durable items (cross-reference IDs):**

1. **`truncate-primitive` (soundness hardening) — CLOSED.** Step 1 DONE (the
   truncation-bump invariant fused into one `EvalState.truncate` choke point across all
   seven drop sites, behavior-preserving); Step 2 (a `withFuel` combinator making the bump
   physically unskippable) RULED OUT — routing the `fuel=0` dispatch through a lambda
   hides the `fuel=n+1` pattern and breaks the mutual block's `termination_by`. Residual
   routing-discipline is documented at the primitive. Detail in the implementation-log.
   (BI-EFF — the effectful-builtin seam, triggered at the 2nd effectful builtin — is in
   Resolved/ruled-out.)

2. **EvalOps extraction → `Kue/EvalOps.lean` — DONE (2026-06-22).** Carved the
   self-contained pure scalar algebra (`ArithOperandClass`/`classifyArithOperand`
   /`arithmeticDomainResult`/`evalRepeat`/`evalAdd…evalDiv`, plus
   `collapseDefaultDisjunction`/`evalEq…evalBinary`/`resolveOperand`/`distributeUnary`
   /`distributeBinary`) out from under the recursive evaluator into `Kue/EvalOps.lean`
   (346 lines). No back-edge into `evalValueWithFuel` (the carve set sits entirely above the
   `mutual` block; verified independent of the `classifyGuard`/`classifyDynLabel` classifier
   block, which STAYS in `Eval.lean`). **Import shape: option (a)** — `EvalOps` imports
   `{Builtin, Decimal, Regex}`. Rejected (b) (moving `div`/`mod`/`quo`/`remValue` into
   EvalOps): those four ALSO back the `div`/`mod`/`quo`/`rem` builtins at `Builtin.lean:892`,
   so relocating them would force a NEW `Builtin → EvalOps` edge — strictly worse than
   `EvalOps → Builtin`. Graph stays acyclic (`EvalOps → {Builtin, Decimal, Regex}`; nothing
   imports EvalOps back). `Eval.lean` 3701 → 3377 (−324); `Eval` now imports `EvalOps`;
   registered in `Kue.lean`. Behavior-preserving: all existing pins + fixtures green,
   pin-count conserved. **Pins ADDED (18, in `EvalTests.lean`):** the comparison ops
   (`lt`/`le`/`gt`/`ge` true cases, incomparable-kind `int`×`string` → bottom, bool-unordered
   → bottom, incomplete-operand defer), `evalEq`/`evalNe`, boolean ops (`&&`/`||`, non-bool →
   bottom), unary (`!` on bool + non-bool → bottom, `-` on int + non-numeric → bottom +
   incomplete defer) — the carve-set ops that previously had only end-to-end fixture coverage.

3. **Test/fixture-org pass (periodic) — `TwoPassTests` SPLIT DONE `0deef2f` (2026-06-23);
   module carve DONE `4b25cef`; fixture regroup DEFERRED.**
   **`TwoPassTests.lean` SPLIT — DONE (Phase-B 2026-06-23, `0deef2f`).** The file (2158 lines, the
   demonstrated silent-failure surface — the Phase-A dead-theorem incident: ~140 theorems silently
   dead under unterminated `/-- -/`) was carved at the CONTIGUOUS Bug2-6..Bug2-13 run: the 64-theorem
   close-once / def-ref / structComp-narrowing / optional-selection block (Bug2-6/2-7/2-8/2-9/2-10/2-11
   /2-13 — was `Eval.lean`-region lines ~1466–2122) moved to a new `Kue/Tests/Bug2xTests.lean`,
   leaving the foundational two-pass / argocd-link / disjunction-selection / RESID-MASK pins (incl. the
   earlier Bug2-1/2-2/2-4/2-5 sections, which interleave with the foundational MEET-RESID/RESID-MASK
   infra) in `TwoPassTests.lean`. The contiguous run was the LOWER-risk seam than the originally-guessed
   "all bug2x" carve (the early Bug2-1/2-4/2-5 sections are not contiguous — fragmenting them would
   split the foundational flow). Registered in `Kue/Tests.lean`. Pin-count CONSERVED: 180 = 116 + 64,
   no duplicate names; both files keep `--` line-comment headers + an end-of-file `#check` coverage
   tripwire (anchors moved with their sections). Org-only, zero behavior change; `lake build` green
   (112 jobs, all tripwire `#check`s elaborate), fixtures + shellcheck clean, cert-manager
   content-identical (jq -S = 0). **TEST-HEALTH
   CONVENTION (durable, applies to ALL new/touched `Kue/Tests/*.lean`):** section headers are `--`
   LINE comments, never `/-- -/`/`/-! -/` block comments (a line comment cannot swallow the next
   theorem); every test module carries an end-of-file `#check @<last-theorem-per-section>` tripwire.
   Recorded in `docs/reference/failure-modes.md`; flagged for `ace-school` (a `general-coding`/test
   convention) — NOT edited into a skill from here. The suite-wide block→line conversion of the OTHER
   ~19 test files (≈440 comments) is LOW-priority defense-in-depth (the build already proves none are
   currently swallowed, and the tripwire is the real guard) — fold it into this org slice opportunistically,
   do not churn 440 sites as a standalone.
   `EvalTests.lean` (had re-grown to 1593) was carved into
   `ComprehensionTests.lean` (29 pins — `listcomp_*` /`letcomp_*`/`eval_comprehension_*`
   incl. comprehension-guard shapes) + `SortTests.lean` (13 pins — BI-2 `list.Sort`
   /`SortStable`); EvalTests → 1246. Org-only, zero behavior change, pin-count conserved
   179→137+29+13. **No `GuardTests` ** — the `classify_guard_*` classifier units already
   live in `PresenceTests`; only the comprehension-guard *shapes* were in EvalTests and
   folded into ComprehensionTests. **Remaining sub-item (DEFERRED, optional):**
   sub-grouping `testdata/cue/{definitions (50), comprehensions (27)}` into nested subdirs
   — high-blast-radius because `FixturePorts.lean` (3049) is hand-maintained source whose
   `fileName := "subdir/stem.expected"` strings are the join key (each move = multi-file
   `git mv` + exact string edit, ~77 fixtures). Deferred per "DEFER rather than break
   discovery"; low marginal win (layout already subsystem-grouped one level deep). Pick up
   as a dedicated careful slice or drop.

4. **Field-ordering parity #3 — RATIFIED CLOSED: Kue keeps source order; parity
   DECLINED.** Spec silent (structs unordered, output order implementation-defined), so
   Kue's declaration order is the principled choice, test-pinned
   (`meet_struct_field_order_is_declaration_order`). `cue` 's cross-conjunct order is an
   undocumented internal-graph artifact (often sorts, sometimes interleaves) — chasing
   byte-parity would mean reverse-engineering it, rejected. Full re-derivation in
   `cue-spec-gaps.md` (RATIFIED row). Reopen only if a concrete fixture demands cue's
   exact bytes (none does).
   ```cue
   out: {b: 1} & {a: 2}  // cue: a, b (graph order); Kue: b, a (source order) — both spec-valid
   ```

5. **Per-eval-cost perf (frontier — hash digest DONE; perf #7 frame-sharing WON'T-FIX).**
   The cache-key hash digest landed (cert-manager 119s → ~30s, byte-identical modulo #3, zero
   drift). Perf #7's two safe wins landed 2026-06-23 (~50.3s argocd, ~11.7s cert-manager). The
   ~175× env-DEPENDENT re-eval was profiled as the residual root and its frame-sharing fix was
   then **MEASURED and REJECTED** (won't-fix, 2026-06-23): the content-share ceiling is ~0.05%
   (cert-manager 144/317788, argocd 288/486773) — the re-evals run under genuinely-distinct
   content, so collapsing them is a false share, not recoverable waste (see the perf #7 block
   above + `kue-performance.md`). The live frontier is now the per-eval CONSTANT / eval COUNT over
   a genuinely-large distinct population, not cross-env sharing — a future per-eval-cost slice, or
   the user-controllable flatten/shorten lever.
   **per-eval CONSTANT PROFILED + FLOOR-CHARACTERIZED (2026-06-23) — frontier CLOSED.** Instrumented
   `evalValueWithFuel`'s cache probes: both apps are FULLY SATURATING (`fuelInserts=fuelHits=0` — the
   fuel-keyed `cache` stays empty the whole run), yet every core eval (`satMisses==evalCalls`: argocd
   486741, cert-manager 317768) still probed the empty fuel-cache, recomputing the SAME depth-3
   `valueDigest` + an `EvalKey` alloc. Landed the sound **empty-`cache`-skip** (probe only when
   `!cache.isEmpty`; an empty HashMap returns `none` for every key → value/saturation-identical;
   `@[inline]` O(1)). Byte-identical (both canaries jq -S = 0, zero drift, suite green). **Measured
   win is at the noise floor:** argocd ~52.8s → ~51.8–52.3s (~1-2%), cert-manager flat ~11.8s — which
   IS the finding: the cache/hash machinery is only ~2-3% of per-eval cost; the wall is the genuine
   `evalValueCoreWithFuel` meet/force/resolve work (tag histogram `.struct` 129K / `.refId` 108K /
   `.conj` 49K / `.selector` 39K) over a genuinely-distinct-content population. **argocd ~52s ≈ ~486K
   necessary core evals × the irreducible per-meet cost; no sound per-eval win exists without lowering
   the eval COUNT, which is content-irreducible** (cross-env sharing = false-share, WON'T-FIX). The
   per-eval-constant frontier is now CLOSED; the only remaining lever is the user-controllable
   flatten/shorten one (`kue-performance.md` expensive-patterns table).
   No active leader remains here. **Multi-ref-cyclic
   flatten fan-out FIXED (2026-06-23).** The closed-cycle repro (`#A: #B & #C & {a}`, `#B: #A & {b}`,
   `#C: #A & {c}`) that ran **>40s** (killed) now exports in **~0.01s warm / ~0.55s cold** — a
   `flattenConjDefRef` `expanding` visited-path bound returns a depth-0 ref to a slot already on the
   expansion path UNEXPANDED, collecting each cycle member's literals ONCE instead of along the
   cross-product of reference paths. SOUND by construction (the bare `.refId` is the leaf the
   unbounded recursion bottoms to at fuel exhaustion; `mergeDefinitionDecls`/D#2 meets are idempotent
   over duplicates), so the allowed-set and value are byte-identical — only the multi-hop-chain field
   ORDER canonicalizes (unordered map, not correctness). cert-manager (~12.4s) + argocd (~54s) jq-S=0
   unchanged (the bound fires only on closed multi-ref cycle re-entry, untouched by the real apps).
   The 2/3/4-way + reject + open-tail + split-literal + dup-back-ref cases are now fast `native_decide`
   pins (previously un-pinnable — they timed out). See `kue-performance.md` § What the engine already
   handles for you (Multi-ref CYCLIC def flatten is bounded). This was the small fast repro of the
   per-eval-cost frontier; the residual per-eval-CONSTANT lever (a genuinely-large distinct population
   on the real apps) remains the next frontier — NOT this fan-out.

6. **Borderline / LOW (opportunistic; none block adoption).** (E#4-fix — arithmetic
   operator domain — landed 2026-06-20; see the implementation-log + `cue-spec-gaps.md`
   row 55.)
   - ~~**`scalar-embed-with-decls`**~~ — **DONE 2026-06-22.** `{#a:1, 5}` → `5` keeping
     `.#a` selectable, via a dedicated **`.embeddedScalar (scalar) (decls)`** carrier in
     `Value.lean` — the direct scalar analog of `.embeddedList`. Built at embed-eval
     (`meetEmbeddingsWithFuel`, the producer) when the host has no output field, HAS decls,
     and the embedding is a terminal scalar (`isTerminalScalar`); manifests as the scalar,
     decls stay selectable (`selectEvaluatedField`/`Runtime.lookupField?`), conflict
     surfaces inline (RESID-MASK → `containsBottom` → export rejects). **The pure-collapse
     path was left UNTOUCHED** (the soundness boundary): `collapsesToScalarEmbed` (no decls)
     still drops `{5}`→`5`; widening it to admit decls would DROP them — the unsound
     direction, avoided. New ctor handled at EVERY match site with NO catch-all swallow
     (Lattice meet + `containsBottom`; Eval select/definedness/guard/dynlabel/digest/tag/
     walkers; EvalOps arith-operand + `resolveOperand` unwrap; Format/Manifest/Normalize×2/
     Runtime). 1 cue-divergence (non-iterable `for` zero-iter, pre-existing) + 1 spec-gap
     (carrier semantics) recorded.
   - **`module-file-scoped-imports`** (arch-sized) — Kue merges every sibling file's
     import bindings into one shared package frame; CUE scopes them per-file. Bites only
     the same-NAME-different-target case; real prod9 doesn't hit it. Bind each file's
     imports into a per-file scope frame.
   - ~~**TL-1 (type-leverage, MEDIUM) — builtin-family dispatch is stringly-typed**~~ —
     **DONE 2026-06-22.** Closed `BuiltinFamily` enum (`core` + the 7 qualified packages
     `strings`/`list`/`math`/`regexp`/`base64`/`json`/`yaml`) in `Builtin.lean` (the only
     consumer — no new import edge); the LEAF stays `String`. A single total classifier
     `BuiltinFamily.ofName?` interprets the name at the one point it is read as a builtin
     (the parser cannot — it can't tell `strings.X` from a user `pkg.X`), and
     `evalBuiltinCall` matches it EXHAUSTIVELY (no catch-all → a new family forces a
     dispatch arm). The previously-silent fall-through (`foobar.Baz`/`nosuchfn`/`error(…)`
     with CONCRETE args produced an inert `.builtinCall` residual = `incomplete value`,
     masking a resolution error) now routes through `unresolvedOrBottom`: concrete ⇒
     BOTTOM (conforms to `cue`'s `reference … not found` / `cannot call non-function`),
     abstract ⇒ deferred residual (preserved). The 8 `core` exact-name arms moved to
     `evalCoreBuiltin`.
     Behavior-preserving for known builtins (the `BuiltinTests` net stays byte-identical
     green; +13 pins incl. the corrected unknown-name cases + a yaml family pin). 1
     cue-divergence (generic vs name-specific bottom message) + 1 spec-gap (unimplemented
     builtin diagnostic) recorded. See implementation-log.
   - ~~**TL-2 (type-leverage, LOW-MED) — `BindingId` packs two swappable bare `Nat`s.**~~
     — **DONE 2026-06-22.** `BindingId { depth : Depth, index : FieldIndex }` — two
     single-field `structure` newtypes (zero-cost over `Nat`) in `Value.lean`, with
     `OfNat` instances so the ~300 `.refId ⟨d, i⟩` test literals stay byte-identical (Lean
     does NOT auto-flatten numerals into nested single-field structures — `OfNat` is
     load-bearing). The two axes are now DISTINCT nominal types (a `Depth` cannot be
     passed where a `FieldIndex` is wanted — the transposition class is unrepresentable,
     compile-checked). Consumers unwrap with `.val` at the frame/slot-arithmetic boundary
     (`env.drop id.depth.val`, `nthField id.index.val`); no `Coe` (implicit widening would
     reopen the swap); `Hashable` not derived (the one digest site hashes through `.val`).
     ~57 mechanical ripple sites: 1 construction (`findInScopes`), ~50 in `Eval.lean`, the
     `Format` render, 4 test fixups. Behavior-preserving: 110-job build clean, full
     suite + fixtures byte-identical green, pin-count conserved; +5 `native_decide` pins
     (`ResolveTests`) locking the surviving runtime contract (the swap-guard itself is
     compile-time). See implementation-log.
   - ~~**`import-eager-closedness`** (MEDIUM)~~ — **DONE 2026-06-22.** Resolved via option
     (b), structurally unified: a new single `selectedFieldValue` closes a SELECTED definition
     field's body (`normalizeDefinitionValueWithFuel`), shared by all four eager pluck sites, so
     the eager and force paths share ONE closing decision and cannot disagree. Option (a)
     (close at load) rejected — the A2 trap (closing a whole bound package re-closes unreferenced
     nested defs). Both facets pinned (silent-admit + incomplete-mask) + over-close guard + pattern
     edges; 1 cue-divergence (incomplete-mask error message). See implementation-log + audit doc.
   - ~~**Parser strictness** — `*(1|2)` laxity; `__x` double-underscore accepted~~ —
     **DONE 2026-06-23.** Both forms were SPEC-MANDATED rejections (spec-verified, not
     cue-quirks): the spec reserves all `__`-prefixed identifiers as keywords, and the `*`
     default mark is valid only on a disjunct WITH siblings (`*1 | 2`), never a sole marked
     operand (`*(1|2)`, `*1`). Fixed with two minimal parser rules —
     `reservedDoubleUnderscore` at the `parseIdentifier` chokepoint (rejects `__x` on every
     spelling; `#__x`/`_#__x` defs + quoted `"__x"` stay valid), and a
     sole-`.default`-marked-disjunct guard in `parseDisjunctionRest` (diagnostic anchored at
     the `*`). 18 `ParseTests` parse pins (reject + valid boundary). 1 cue-divergence (cue
     accepts the inline `a: __x: 1` shorthand — a cue parser inconsistency; Kue conforms to
     the spec) + 1 spec-gap (the murky package-name / import-qualifier `__` corner,
     deliberately out-of-scope). Canaries jq-S=0 (no real config uses the rejected forms).
     See implementation-log.
   - ~~**`release-linux.sh` no dirty-tree guard (LOW, Phase-B 2026-06-23).**~~ — **DONE
     2026-06-23.** Added the same clean-tree precondition `release.sh` has
     (`[ -z "$(git … status --porcelain)" ] || die …`) before the Docker build, so the Linux
     asset (`COPY . /src`) is built from a committed tree matching the macOS asset. See
     implementation-log. (Whether `release.sh` should auto-chain `release-linux.sh` — a
     deliberate two-step split — is a UX call left to the user, not filed.)
   - ~~**Concurrent-release tap-clone race (LOW, audit 2026-06-23).**~~ — **DONE
     2026-06-23**, now relevant because releases AUTO-CUT. New shared `scripts/tap-push.sh`
     (sourced by both, DRY alongside `patch-formula-block.sh`) replaces each script's `pull
     --ff-only` + `push` with a lock-FREE retry-on-reject loop: `fetch` + `reset --hard
     <remote>/<branch>` (clean base at the remote tip, includes the sibling's block) →
     re-apply OUR patch via an idempotent + block-scoped callback (the patcher keys on the
     asset-suffixed url, invariant across bumps; it touches only our block, so the sibling's
     is preserved) → commit-if-changed → push → on REJECT loop up to N (default 5) with
     backoff, then `die`. `flock` deliberately AVOIDED (absent on the macOS release host).
     Verified by a truly-concurrent dry-run (12-round stress + gh-remote round): zero lost
     updates, the race loser re-fetches + re-patches + pushes. See implementation-log.
   - ~~**DRY `selectEvaluatedField .disj` **~~ — **DONE 2026-06-23.** The resolved-default
     carrier dispatch (re-listing `.struct`/`.embeddedList`/`.embeddedScalar` → `selectFromDecls`)
     is extracted to a shared `selectFromConcrete (base label)`, called both at top-level and once
     `resolveDisjDefault?` picks a default. BYTE-IDENTICAL on every carrier default + the
     doubly-nested-`.disj`-default deferral (explicit `some (.disj _) => .selector`). NOT a pure
     refactor: the `_` arm previously deferred a SCALAR default to `.selector` ("incomplete"),
     where cue type-errors (`invalid operand … want list or struct`); routing it through
     `selectFromConcrete` now `.bottom`s the arm — `y: x.a | "fb"` (x scalar-default) resolves to
     `"fb"` == cue (kue WAS AMBIGUOUS — a kue bug now FIXED to match cue, not a divergence).
     The "free nested-disjunction recursion" gain (a `.disj`-valued default recursing to cue's `1`)
     was DESIGNED-DEFERRED: it needs a well-founded `termination_by` proving `resolveDisjDefault?`'s
     output is `sizeOf`-smaller through `liveAlternatives`/`flatten`/`dedup` — LARGE machinery for a
     shape eval-time flatten makes unreachable from source. Pinned both ways (deep-nested defers ==
     current; scalar-fix == cue). 1701 pins, canaries jq-S=0.
   - ~~**Value-rewrite `other => other` catch-alls (Phase-B, LOW, filed 2026-06-23 audit).**~~
     **DONE 2026-06-23.** All four Value-rewrite catch-alls (`Parse.lean` `canonicalizeBuiltinCalls`,
     `EvalOps.lean` `collapseDefaultDisjunction`, `Eval.lean` `openStructValue`/`closeEmbeddedOver`)
     replaced with explicit constructor enumerations — `canonicalizeBuiltinCalls` lists the 11 leaves
     (it recurses every recursive ctor already); the three shallow projections list ALL pass-through
     ctors (leaf + recursive, plus a `.struct _ _ _ _ _` arm for the non-plain-struct shapes the
     narrow first arm misses). Byte-identical (suite 1697 pins conserved, cert-manager + argocd
     jq-S=0). Exhaustiveness now BITES: a scratch dummy recursive `Value` ctor errors at all four
     sites (verified, reverted). The two eval-dispatch fuel terminals (`evalValueCoreWithFuel`,
     `evalStructRefsM`) are deliberately OUT of scope — they are the eval fixpoint's no-rule-needed
     fallback, not structural rewrites, and already have a synced leaf-enumeration helper
     (`valueReducesToSelf`) guarding their identity arm.
   - ~~**B3 (`comprehensionPairs` `.embeddedList`)**~~ — **DONE 2026-06-22** (rode along
     with `scalar-embed-with-decls`). Added the
     `.embeddedList items _ _ => some (listPairsFrom 0 items)` arm, so `for x in
     {#a:1,[1,2]}` now iterates `[1,2]` (was zero). A scalar carrier (`{#a:1,5}`) is
     non-iterable → zero-iter via the `_ => none` catch-all (Kue's standing non-iterable
     handling; cue type-errors — a tracked divergence).
   - **B2-A1 (latent, currently lossless)** — `applyEvaluatedStructN` (`Eval.lean:330`)
     routes the patterns-present case through a meet that DROPS `tail`. Lossless today
     (the only tail a parsed struct carries is bare `...` = `.top`, a no-op to
     drop+re-supply); breaks the day typed-ellipsis lands. Thread `tail` through the
     pattern arm + a round-trip pin; pairs with any typed-ellipsis slice.
   - **B2-A2 (test-gap fill)** — both B2.5 fixtures exercise patterns-LEFT × tail-RIGHT;
     the reverse and both-tails+patterns are pinned only by `native_decide`. Add
     `testdata/cue/definitions/{tail_pattern_unify,both_tails_pattern_unify}` pairs +
     `FixturePorts` entries (oracle: `{a:5,...} & {[string]:int}` → `{a:5}` open).
   - **A2-x (latent) — `importBinding` merge-asymmetry.** `mergeFieldClass` returns `none`
     for `importBinding & <real field>` (merges only with itself) where the old `.hidden`
     merged via `.field`. **STAYS unobservable** — the only collision that would exercise
     this merge is the one A2-y now rejects at LOAD (an `importBinding` never reaches a
     `meet` with a same-named real field, because the load fails first). No work to do.
   - ~~**A2-y (pre-existing) — missing import-name redeclaration check.**~~ — **DONE
     2026-06-23.** A top-level bare-identifier field reusing an import's bound local name
     (`import ".../dep"` + `dep: {…}`, incl. `dep?`/`dep!`, the alias name under `import d
     "…"`, the qualifier name under `"…:foo"`, and a builtin `import "encoding/json"` +
     `json: {…}`) is now a LOAD error — `<name> redeclared as imported package name`,
     matching cue's verdict + first message line. **Spec-mandated** (the file-block
     "No identifier may be declared twice in the same block": an import binds the package
     name in the file block, a same-name bare field re-declares it), NOT a cue quirk — so
     Kue conforms, it does not just match the binary. Pre-fix this was a genuine SOUNDNESS
     bug: Kue silently kept BOTH, and resolved a reference `out: dep` to the imported
     PACKAGE rather than the user's field (wrong value). Fixed in `Module.lean`
     (`checkImportRedeclaration` over each file's `topLevelFieldNames`, threaded through
     `collectBindings` + the builtin-only fast path); the parser now records quoted-vs-bare
     on `ParsedField.field` so `bareIdentifierLabels` collects exactly the collision-eligible
     labels. EXEMPTIONS match cue: quoted `"dep"`, `#dep`/`_dep` (distinct namespaces),
     nested fields, and an alias/qualifier that does not match a field. Canaries jq-S=0
     (prod9 never hits the collision — verified UNAFFECTED). 1 cue-divergence (single-line
     vs two-line diagnostic) + 1 spec-gap (exemption boundary; the aliased-field-label
     corner deliberately exempted as the no-over-reject choice). See implementation-log.
   - ~~**Aliased-builtin-call resolution (latent, LOW) — surfaced by the A2-y audit.**~~
     **RESOLVED 2026-06-23.** An ALIASED stdlib import (`import j "encoding/json"` +
     `j.Marshal(x)`) yielded `incomplete value` where cue marshals — the parser lowered the
     call off the LITERAL member-access head `j`, so `evalBuiltinCall` saw `j.Marshal`, which
     `BuiltinFamily.ofName?` cannot classify. FIX: a post-parse alias canonicalization in
     `parseDocument`/`parseDocumentFile` (`Parse.lean`) rewrites a builtin-alias call head back
     to its canonical package name (`j.Marshal` → `json.Marshal`) BEFORE the alias-blind
     dispatch, using `builtinImportLocalNames` over the file's imports — only when the import
     PATH is a builtin (`isBuiltinImport`), so an aliased USER import (`import f "ex.com/foo"` +
     `f.Bar`) is NEVER misdispatched. `builtinImportPaths`/`isBuiltinImport`/`lastPathElement`
     moved to `Value.lean` (shared base) to avoid duplicating the builtin-path list across the
     Parse/Module boundary. Resolves identically to cue across all six families
     (`json`/`strings`/`math`/`list`/`base64`/`yaml`); unaliased unchanged; canaries jq-S=0
     (prod9 uses unaliased imports). Pins: 4 ParseTests theorems (alias map + head rewrite +
     per-family e2e + the unaliased/user-import boundary), 1 Bug2xTests export pin, fixtures
     `testdata/cue/builtins/aliased_builtin.{cue,expected}` (dual CUE-port + CLI witness) and
     module fixture `testdata/modules/alias_builtin_call/`. No `cue`-divergence (kue conforms).
   - ~~**Aliased-stdlib-CONSTANT resolution (latent, LOW) — adjacent to the calls fix.**~~
     **RESOLVED 2026-06-23.** The no-call analog of the calls fix. A stdlib CONSTANT
     (`list.Ascending`/`Descending`/`Comparer`) resolves INLINE at parse off the LITERAL head
     (`stdlibPackageValue? pkg label`), so an aliased import (`import l "list"` + `l.Ascending`)
     keyed `stdlibPackageValue? "l" …` → `none` and survived as a deferred `.selector (.ref "l")
     "Ascending"` — `Sort` then bottomed where cue sorts. FIX: extend the SAME post-parse pass
     (`canonicalizeBuiltinCalls`) — its `.selector` case now maps an aliased `.ref` head back to
     the canonical package (`canonicalizeBuiltinConst?`, reusing the `builtinImportLocalNames`
     alias map) and re-resolves via `stdlibPackageValue?`, yielding the same comparator struct as
     the unaliased form. Scoped to builtin paths, so a user import's const-shaped member
     (`import f "ex.com/foo"` + `f.Ascending`) is NEVER rewritten (stays a deferred selector). All
     three `list` constants resolve == cue v0.16.1; unaliased unchanged; the calls fix unaffected;
     canaries jq-S=0. Pins: 3 ParseTests theorems (the `canonicalizeBuiltinConst?` boundary +
     per-constant e2e + the unaliased/user-member boundary), 1 Bug2xTests export pin, fixtures
     `testdata/cue/builtins/aliased_list_const.{cue,expected}` (dual CUE-port + CLI witness) and
     module fixture `testdata/modules/alias_list_const/`. No `cue`-divergence (kue conforms).
     **Phase-A audit (2026-06-23, batch `f4feb93..406556e`) — HEALTHY.** Over/under-
     canonicalization attacked exhaustively, every witness oracle'd vs cue v0.16.1:
     OVER (user import whose path last-elem == `json`/`list`, aliased → resolves to the USER
     package; local field shadowing an alias with no import → field access; redeclare-as-import
     → both error identically) and UNDER (all builtin families aliased, calls + consts;
     binding-not-spelling: `import json "strings"; json.ToUpper` → `strings.ToUpper`) all
     byte-identical to cue. `isBuiltinImport` keys on the import PATH, not the local name —
     the dispatch boundary, confirmed. Both canaries re-run DIRECTLY (full whole-file export,
     not `-e`): cert-manager + argocd jq-S diff = 0. Totality clean (no new
     `partial`/`sorry`/axiom; the `other => other` catch-all is sound — every swallowed
     constructor is a true `Value` leaf — and matches the established sibling-pass idiom).
     DRY confirmed (one shared pass for calls + consts; `Value.lean` move de-dups the
     builtin-path list). Coverage ADDED: `regexp` to the per-family theorem, a
     binding-not-spelling dispatch theorem, the `builtinImportLocalNames` cross-name unit
     cases, module fixture `testdata/modules/alias_user_pkg_builtin_name/` (the strongest
     OVER witness, pinned). Latent follow-up (Phase-B, codebase-wide): the four
     `other => other` Value-rewrite catch-alls silently bypass a future recursive constructor.
   - **`scalar-embed` provenance follow-ups** — opportunistic pins (3-level flatten, disj
     ops beyond `+` /`&`, composed select-into-F1-default) when next touching
     Lattice/Eval.
   - ~~**`resolveEmbeddedDisjDefault`** — verify the pass-1 label-surfacing path's
     narrowing handling.~~ **RESOLVED [fixed] 2026-06-23 — CASE B (`embed-disj-arm-closedness`).**
     The label-surfacing call (`evalEmbeddingFieldsWithFuel`, now `Eval.lean:~1897`/`~3757`) only
     surfaces labels for the closedness union + Pass-2 frame; the VALUE comes from the `.disj`
     distribution arm. Probing that arm adversarially found a REAL divergence: it OPENED each arm
     (`openStructValue`) into the residual `.disj`, so a LATER use-site narrowing of a label
     DISJOINT from a closed default arm was wrongly ADMITTED (the closed default won with a leaked
     label) where cue rejects it by closedness and falls through to the survivor
     (`{(*_#A{n} | _#B{s})} & {s:"x"}` → cue `{s:"x"}`, kue pre-fix `{n,s:"x"}` / `incomplete int`).
     Fix: per-arm re-close over (host ∪ arm) labels (the analog of the top-level `closeEmbeddedOver`)
     — widens by host labels yet restores each arm's own closedness against the later narrowing; the
     DIRECT (non-embedded) path already got this. 4 pins, canaries jq-S=0. **LATENT follow-up
     surfaced (NOT this slice): nested embedded disjunction-of-disjunction loses the default MARK
     when the inner default sub-arm dies** (`{(*_#Outer1 | {c:1})} & narrow` where `_#Outer1` is
     itself `*_#Inner | …` and the narrowing kills `_#Inner`) → kue exports "ambiguous: multiple
     non-default disjuncts" where cue picks the marked survivor. Pre-existing (HEAD diverges too,
     differently); a `flattenAlternatives`/`normalizeDisj` mark-inheritance gap, distinct mechanism.
   - **B-AUDIT-refold-1 (type/DRY, MED — Phase-B 2026-06-29 HEADLINE) — embedding-`Self`
     re-fold is a near-duplicate across both struct-eval arms.** The L1 fix (`f6fc514`)
     added a third "gate → augmented `nestedForEmbeds` → re-eval embeddings → meet" block;
     it now appears VERBATIM-MODULO-TWO-NAMES in both arms — `.structComp`
     (`Eval.lean:3558–3572`, vars `fields`/`env`) and def-force (`Eval.lean:4132–4146`,
     vars `canonical`/`capturedEnv`). The ONLY deltas between the two copies are (1) the
     canonical-field list name and (2) the captured env. Three statements (`refoldEmbeds`
     guard, conditional `pushFrame`+re-eval `nestedForEmbeds`, conditional
     `evalEmbeddingFieldsWithFuel`) plus the `met`'s `nested → nestedForEmbeds` swap are
     duplicated. **Drift risk (real, why this ranks): the two arms have a history of
     diverging-then-reconverging** (the perf guide already notes the static-field two-pass
     was independently re-tuned per arm); a future embed-`Self` fix touching one arm and not
     the other silently breaks the other's list-embed path with NO type-level catch — they
     are structurally independent today. **Extraction (concrete):** hoist a shared helper
     above the `mutual` block (alongside `needsEmbeddedSelfPass`/`embeddingsReadEmbeddedSelf`),
     ```
     refoldEmbeddingsIfSelf
       (fuel : Nat) (canonical : List Field) (newEmbeddedFields : List Field)
       (embeddings : List Value) (env : Env) (merged : …)
       (nested : Frame) (embeddingFieldsPass1 : …)
       : EvalM (Frame × …)   -- returns (nestedForEmbeds, embeddingFields)
     ```
     so both arms call it with their own `(canonical, env)` and thread the returned
     `nestedForEmbeds` into the `met`. It lives in the `mutual` block (it calls
     `evalEmbeddingFieldsWithFuel`). The two parallel GATES
     (`needsEmbeddedSelfPass` for static fields vs `embeddingsReadEmbeddedSelf` for embedding
     values) are NOT merged — they answer different questions (which surface reads the
     embedded label) and feed different re-eval targets; keeping them separate is correct, but
     note both share `thisStructBindingIndex?`+`refsSelfEmbeddedLabel` plumbing, so the helper
     should take the gate result as a param, not recompute it. **EVAL-CORE — own slice, own
     verify: `lake build` + the full 1843-pin regression + cert-manager/argocd jq-S=0
     (byte-identical is the bar — pure refactor, zero behavior change) + the two wild fixtures
     stay green.** Do NOT do inline. Ranked: lead of the Borderline/LOW cleanups (it's the one
     active drift hazard in eval-core; the rest are latent).

7. **CLI / entry-UX (cue-aligned command surface).** **Entry-UX fix — DONE
   (2026-06-24).** The two fresh-install killers are fixed: bare `kue` (no args) now
   prints the top-level help and exits 0 (was: blocked on `IO.getStdin.readToEnd`, an
   interactive freeze) — `parse [] => .help none`, pinned (`CliTests.parse_empty`). The
   empty-stdin smoke demo is removed: `kue eval` on empty input evaluates the empty struct
   → no output, exit 0 (matches `cue eval -`), and the dead `Kue/Examples.lean`
   (`smokeLines` + the 14 `*SmokeResult` defs + their plan-pin theorem — referenced ONLY
   by the removed `printSmoke` CLI hook) was deleted. Stdin eval is now explicit (`kue
   eval`, piped or `<`), never bare `kue`. Harness call-sites that used the bare `kue
   <file` redirect moved to explicit `kue eval <file`; the eval-agreement check repointed
   to the file-arg shorthand (`kue <file>` == `kue eval <file>`). Small help polish:
   aligned the `Commands:` description column + added an Examples block. **NEW SCOPED
   OBJECTIVE (awaiting user direction — do NOT self-start):** the broader **cue-aligned
   CLI command surface** (new subcommands — `vet`/`fmt`/`def`, a `-` explicit-stdin
   marker, flag parity with `cue`). This is a user-scoped design objective, deliberately
   NOT expanded here; the next leader for it = the user's CLI-design direction. **Known
   DEFERRED (footnote, not in this slice):** `kue --version` reports `Kue.version` =
   `0.1.0-alpha` (datestamped per nightly) rather than the dated release tag — defensible
   as-is; revisit only if the version/build plumbing is reworked.

   **Module-fetch / registry direction — DECIDED (2026-06-25): full Lean 4, NOT a Go
   frankenstein.** The single-binary Go-shell + Lean-engine-via-cgo architecture (a Go
   outer CLI reusing cue's OCI/module ecosystem, calling the Lean engine through an FFI
   seam) was explored and *spiked to a working link* on macOS arm64 + Linux x86_64
   (`spike/`, `6a32729`), but chakrit **rejected** it: the Lean↔Go seam is too leaky
   (owned-vs-borrowed refcount trap, an IO-boundary `Module.lean` refactor, dual-toolchain
   cgo build) for a project whose value is correctness *and* human-traceability. The
   registry/OCI/module-fetch layer (`B3d` below) therefore **stays a Lean-native, deferred
   problem** — NOT a Go-FFI one. Spike kept as a durable feasibility record; do not
   re-spike. See `docs/decisions/2026-06-25-lean-engine-embedded-in-go-via-cgo.md`
   (status: feasibility-proven, REJECTED).

   **B3d (registry/OCI module fetch) — WIRED (2026-06-26); B3d-6b remains.** Transport DECIDED: a
   `curl` subprocess, NOT FFI (`docs/decisions/2026-06-25-registry-fetch-via-curl-subprocess.md`),
   which splits the OCI protocol into a PURE core (offline TDD) + a thin impure curl edge.
   Slice plan B3d-1…B3d-6 lives in that decision note. B3d-1…B3d-5 (+ B3d-5a, B3d-5z, B3d-6a) are
   DONE: fetch-on-missing is wired into `Module.lean` and offline-verified; the live HTTPS fetch is
   human-gated (`.afk.log`); semver compare + the pure MVS solver are landed. **B3d-7 — OCI
   bearer-token auth — DONE (2026-06-28):** the curl edge now does the Docker/OCI token flow
   (bare GET → `401` → `WWW-Authenticate` parse → docker-credential resolve → token mint → authed
   retry), proven LIVE against real `ghcr.io` for `prodigy9.co/defs@v0.3.19` (manifest + digest-
   verified zip blob). This **unblocks B3d-6b's requirement-graph fetch** — its dep-`module.cue`
   GETs now work against authed/private registries, not just public anonymous ones. Remaining:
   **B3d-6b** (network-gated) — `cue mod get/tidy` commands, fetching deps' `module.cue` to BUILD
   the requirement graph, "latest"-tag listing, wiring the MVS solver into the resolver, and
   `cue.sum` WRITE.
   - **B3d-1 — `CUE_REGISTRY` parse + module→OCI-ref resolution (PURE) — DONE (2026-06-25).**
     New pure, IO-free `Kue/Registry.lean` (+ `Kue/Tests/RegistryTests.lean`). The
     simple-syntax `CUE_REGISTRY` parser (empty→`registry.cue.works`; bare host /
     `host:port` / `[::1]:5000`; optional `/path` repository prefix; `+secure`/`+insecure`;
     `prefix=spec` longest-complete-element-match; bare catch-all; `none` global and
     `prefix=none`; duplicate-prefix / duplicate-catch-all / empty-part / unknown-suffix
     errors) plus `module@version → {host, insecure, repository, tag}` resolution. Conformed
     to cue v0.16.1's own OCI tooling (`internal/mod/modresolve/resolve.go`,
     `mod/modconfig/modconfig.go`) — the authoritative protocol, NOT the language spec. Key
     pinned facts: the OCI **repository is UNESCAPED** (`path.Join(prefix, basePath)` on the
     raw base path; the `@major` suffix stripped, the OCI tag = the plain full version);
     `escape.go`'s `!`-lowercasing escaping applies ONLY to the on-disk download/extract
     cache layout (`modcache/cache.go`), modelled here for B3d-4/5. Illegal-states-
     unrepresentable: `RegistrySpec` (`none` | real), `Resolution` (`found` | `noRegistry` |
     `error`). Total, no `partial`/`sorry`/axiom. 40+ `native_decide`/`#guard` pins; full
     build green, fixtures zero-drift. The `file:`/`inline:` kinds + CUE-syntax config-file
     form (`pathEncoding`/`stripPrefix`/`prefixForTags`/hash encodings) are DEFERRED (see
     `compat-assumptions.md`). NOT yet wired into `Module.lean` — that is B3d-4/5.
   - **B3d-2 — OCI image-manifest parsing (PURE, offline) — DONE (2026-06-25).** New pure,
     IO-free `Kue/Oci.lean` (+ `Kue/Tests/OciManifestTests.lean`). `parseManifest : String →
     Except String OciManifest` over Lean's standard `Lean.Json.parse` (NO second JSON parser —
     `Kue/Json.lean` only serializes; reusing the stdlib parser is the "reuse, don't reinvent"
     intent, and adds no Lake dependency). Typed, illegal-states-unrepresentable `Descriptor`
     (`mediaType`/`digest`/`size`) + `OciManifest` (`config` + `layers`): a manifest that omits
     any descriptor field is a parse error, never a placeholder. Conformed to cue v0.16.1's OCI
     tooling `mod/modregistry/client.go` (`unmarshalManifest`, `isModule`, `isModuleFile`, the
     2-layer invariant in `GetModuleWithManifest`, the construction in `putCheckedModule`) — the
     authoritative protocol, NOT the language spec. **Layer-selection rule:** `moduleZipDescriptor`
     / `moduleFileDescriptor` select BY mediaType (`application/zip` / `application/vnd.cue.modulefile.v1`)
     and require EXACTLY ONE match — strictly stronger than cue's blind `layers[0]`/`layers[1]`
     indexing (rejects an ambiguous/absent layer cue would mis-read), still conforming to every
     well-formed manifest cue produces. `validateModuleManifest` enforces cue's invariants with
     conforming error phrasing: `isModule` (config mediaType == `application/vnd.cue.module.v1+json`),
     exactly two layers, both selectable layers present+unique. Digest strings preserved VERBATIM
     so B3d-4 can compare `Sha256.digestString blob == d.digest`. Total, no `partial`/`sorry`/
     axiom. 17 `native_decide`/`#guard` pins (well-formed → right zip/modulefile descriptors;
     non-module config → typed reject; zip absent/duplicated → error, never first-wins; malformed
     JSON / missing-field / non-numeric-size → clean typed error, no crash). Representative
     in-Lean manifest JSON (the cache stores extracted files, not the manifest). NOT yet wired
     into `Module.lean` — B3d-4 GETs the manifest, then GETs+verifies the zip blob this names.
   - **B3d-3 — SHA-256 (FIPS 180-4) + `cue.sum` `h1:` dirhash (PURE) — DONE (2026-06-25).**
     New pure, IO-free `Kue/Sha256.lean` (+ `Kue/Tests/Sha256Tests.lean`). Total `UInt32`/
     `ByteArray` SHA-256 (the 64 `K` constants, 8 `H0`, padding with big-endian 64-bit length
     suffix, 64-round compression, `Ch`/`Maj`/`Σ`/`σ`), a `hex`/`digestString` (`sha256:<hex>`)
     for OCI blob-digest verification (B3d-4 consumes it), and `hash1 : List (String ×
     ByteArray) → String` reproducing Go `golang.org/x/mod/sumdb/dirhash` `Hash1`: byte-order
     name sort, per-file `lowerhex(sha256(contents)) ++ "  " ++ name ++ "\n"` (TWO spaces),
     outer SHA-256, `"h1:" ++ base64Std`. The std-base64 step REUSES `Kue.base64Encode` (the
     `encoding/base64` builtin's encoder), not reimplemented; `hex` is new (no prior bytes→hex
     helper). Key pinned protocol fact: a cue module zip stores entries under their BARE
     module-root-relative path (`cue.mod/module.cue`, `foo.cue`), NOT `<module>@<version>/`-
     prefixed like Go's own modzip (`cuelang.org/go/mod/modzip` `zip.go` `Create`), so the
     dirhash `name` IS the raw zip-entry path; `hash1` is name-agnostic so the zip-name edge
     stays in B3d-4. Total, no `partial`/`sorry`/axiom (only `propext`/`Quot.sound`/
     `Classical.choice`). 30+ `native_decide`/`#guard` pins: the three NIST/FIPS vectors
     (`""`/`"abc"`/56-byte two-block), padding boundaries 0/55/56/63/64/65/119 + an 85-byte
     mixed vector (all vs `shasum -a 256`), the digest/hex/primitive forms, and TWO end-to-end
     `h1:` values reproduced INDEPENDENTLY from the Go algorithm via `shasum`+`base64` — a true
     cross-check, no soft gap. NOT yet wired into `Module.lean` — that is B3d-4/5.
   - **B3d-4 — OCI fetch over a `curl` subprocess (offline-verified) — DONE (2026-06-26).**
     The IO edge of the B3d track, decomposed into PURE builders + a THIN impure runner. PURE
     (`Kue/Oci.lean`, `native_decide`-pinned): `manifestUrl`/`blobUrl` (the OCI Distribution
     endpoints `…/v2/<repo>/manifests/<tag>` and `…/v2/<repo>/blobs/<digest>` per
     `ocirequest/create.go`), `scheme` (http for insecure, https else), `manifestAcceptTypes`
     (cue's `knownManifestMediaTypes` verbatim — image manifest + index, the deprecated artifact
     type, the three docker types, `*/*`), and the curl argv builders `manifestCurlArgs`/
     `blobCurlArgs` over `curlBaseFlags = ["-sSL", "--fail-with-body"]`. IMPURE
     (`Kue/OciFetch.lean`, the codebase's FIRST `IO.Process` user; imports only the pure trio
     Oci/Sha256/Registry — never Eval/Resolve/Value, the Phase-B seam): `runCurl` (spawns curl,
     captures stdout as RAW bytes via `spawn` + `readBinToEnd` — NOT `IO.Process.output`, which
     UTF-8-decodes and would corrupt a binary zip; stdout drained before `wait` so a large body
     never deadlocks), `curlGet`, `curlGetVerified` (the SHA-256 integrity gate at URL level),
     `fetchManifest` (GET → `parseManifest` → `validateModuleManifest`), `fetchBlob`
     (`curlGetVerified` against `descriptor.digest`), `fetchModuleZip` (manifest → zip descriptor
     → verified blob bytes; stops at bytes — extract/cache-write are B3d-5). **curl flags chosen
     by philosophy — fail loud, never silently mis-succeed:** `-s` silent + `-S` show-errors,
     `-L` follow redirects (registries 307 a blob GET to object storage), `--fail-with-body` (a
     non-2xx HTTP status exits non-zero so the runner sees the failure, while still writing the
     error body for the diagnostic — `--fail` alone discards it). Manifest GET sends one
     `-H "Accept: <type>"` per media type, mirroring Go's multi-valued `Accept` header. **Digest
     integrity is the gate:** a fetched blob is REJECTED unless `Sha256.digestString bytes ==
     descriptor.digest` — a corrupt/tampered/wrong-content blob is an error, never a silent
     success. **Offline-tested** via `scripts/check-ocifetch.lean` (run by
     `scripts/check-fixtures.sh`): drives the whole curl composition against `file://` URLs over
     committed `testdata/ocifetch/` fixtures (a valid 2-layer manifest + a `module.zip` blob with
     its real precomputed sha256 as the descriptor digest), asserting curl reads file://, captured
     bytes hash to the fixture digest (byte-faithful), digest-verify PASSES on the correct digest,
     digest-verify REJECTS a wrong digest, a missing path errors (no silent empty success), and the
     fixture manifest validates with its zip digest matching the blob. No network, no out-of-tree
     writes. Total, no `partial`/`sorry`; pure builders depend only on `propext`, the IO functions
     on the standard `propext`/`Quot.sound`/`Classical.choice` every `IO` action carries. **The
     live HTTPS fetch from `registry.cue.works` is human-gated** (network egress is outside the
     AFK envelope): implemented + offline-verified, but the real-registry smoke is logged in
     `.afk.log` with the exact `curl` one-liner to run — a logged gap, not a failure. NOT wired
     into `Module.lean` — replacing the `registry fetch is B3d` error with
     resolve→fetch→verify→cache-write→extract→read-path is B3d-5.
   - **B3d-5z — pure-Lean ZIP reader + DEFLATE inflate + CRC-32 (offline-verified) — DONE
     (2026-06-26).** The PURE transform the verified module-zip bytes from `fetchModuleZip`
     (B3d-4) need next: unzip them into in-memory `(name, contents)` entries that B3d-5 writes to
     the cache and `Sha256.hash1` hashes into a `cue.sum` line. **Fork resolved by philosophy —
     pure Lean, NOT an `unzip` subprocess:** the curl GET is the sole impurity in the fetch path;
     the transform of already-verified bytes is deterministic, total, fully offline-`native_decide`-
     testable, adds no runtime dependency, and composes directly with the dirhash. An `unzip`
     subprocess would re-introduce a process seam (and a host-tool dependency) for a transform that
     belongs in the pure core, so it loses on every axis we weigh. cue module zips are confirmed
     all-DEFLATE (`unzip -v` shows `Defl:N`), so STORED-only would not do — real RFC 1951 inflate
     was required. Two new pure modules: **`Kue/Inflate.lean`** (RFC 1951): an LSB-first `BitReader`,
     a canonical `Huffman` decoder (built from per-symbol code lengths, decoded MSB-first within a
     code), the three block types (`stored`/fixed-Huffman/dynamic-Huffman with the code-length-code
     preamble + RLE-coded lengths), the §3.2.5 length/distance base+extra-bit tables, and LZ77
     back-reference copy (byte-by-byte so overlapping copies — e.g. `dist=1` run-fills — are
     correct). **`Kue/Zip.lean`** (PKWARE container): little-endian readers, table-free CRC-32
     (poly `0xEDB88320`, the zip standard), an `End-Of-Central-Directory` backward scan, a
     `Central-Directory` walk (the AUTHORITATIVE entry index — local headers can defer sizes), a
     `Method` sum type (`stored`/`deflate`; any other method = typed error, no silent skip), and
     `readZip : ByteArray → Except String (List (String × ByteArray))` which decompresses each
     entry, **VERIFIES its CRC-32 + uncompressed size against the central-directory values** (the
     integrity gate, like the blob-digest gate in B3d-4 — a mismatch is rejected), and skips
     directory entries (empty/trailing-`/` names) exactly as cue's own `mod/modzip` `Unzip` does.
     Entry names are the BARE module-root-relative paths (no `<mod>@<ver>/` prefix — cue's modzip
     convention, confirmed B3d-3), so they feed `hash1` verbatim. **Totality (no `partial`):** the
     Huffman symbol loop is bounded by `bitLen + 1` (every iteration consumes ≥ 1 bit; the reader
     cannot pass `data.size*8`), the block loop by `data.size + 1` (every block reads ≥ 3 bits),
     and `decodeGo` by `maxBits - len` (≤ 15) via `termination_by`; out-of-fuel ⇒ a typed
     "truncated/malformed" error, never a hang. Only `propext`/`Quot.sound`(/`Classical.choice`)
     axioms. **Tests:** `Kue/Tests/ZipTests.lean` `native_decide`-pins — CRC-32 standard vectors
     (`""`→0, `"123456789"`→`0xCBF43926`), raw-deflate vectors from Python `zlib`
     (fixed-Huffman literals, fixed-Huffman back-ref, dynamic-Huffman, empty, `dist=1` RLE), and
     synthetic STORED (`zip -0`) + DEFLATE (`zip -9`) archives decoded back to their files — all
     independently produced, a genuine cross-check. **Golden:** `scripts/check-zip.lean` (run by
     `scripts/check-fixtures.sh`) drives `readZip` over a real cached cue module zip
     `testdata/zip/module.zip` (`prodigy9.co/defs` v0.3.4 — 69 flat all-DEFLATE files) and
     cross-checks every extracted file's sha256 + central-directory order against
     `testdata/zip/module.zip.sha256` (ground truth from `unzip -p | shasum`, an extractor Kue's
     code does not share). All 69 files byte-identical, CRC-verified. No network; READ-only over
     committed fixtures. B3d-5 now has: `fetchModuleZip` bytes → `readZip` → `(name, contents)`
     entries → cache-write + `hash1` dirhash.
   - **B3d-5 — fetch→extract→cache-write→read-path wiring (+ B3d-5a folded) — DONE
     (2026-06-26).** The CONNECT slice: the line-340 `none` branch of `resolveImportTarget` (a
     declared dep absent from vendor+cache) no longer hard-errors `registry fetch is B3d` — it
     fetches, verifies, installs into the cue cache, and retries the locate. New IO edge in
     `Module.lean` (which gained `import {Registry,OciFetch,Zip,Sha256}` — the correct
     direction: the IO module depends on the pure protocol core, never the reverse):
     **`fetchAndCacheModule cueRegistry importerRoot dep fetchZip`** = resolve `CUE_REGISTRY`+dep
     to an `OciRef` via `Registry.resolveFromConfig` (a `none`/unset registry ⇒ a clear
     "cannot fetch" error, never a silent empty install) → `fetchZip ref` (production passes
     `OciFetch.fetchModuleZip`, which already digest-verifies the blob; the param is INJECTED so
     the offline test drives a local-file source) → `Zip.readZip` (CRC+size verified) →
     `cue.sum` `h1:` check when one is recorded → `writeModuleToCache`. **Cache-write layout +
     atomicity:** `writeModuleToCache` routes through the `Registry` authority — the raw verified
     zip to `mod/download/<esc-path>/@v/<esc-ver>.zip`, each unpacked entry under
     `mod/extract/<esc-path>@<esc-ver>/` by its bare zip-relative name (`createDirAll` per parent).
     Atomicity is a simple create-all (NOT temp-dir-then-rename) — the alpha choice, acceptable
     because the read-path keys off the extract *directory* and the entries land before the
     retry-locate reads it; a crash mid-write would leave a partial extract dir that a future
     `cue mod` verify (B3d-6) should re-validate. **`cue.sum`:** cue v0.16.1 ships NO `cue.sum`
     mechanism (no `HashZip`/dirhash consumer in its source) — the OCI blob `sha256:` digest is
     the live integrity gate. kue's `h1:` verification is defensive/forward-compatible: a recorded
     sum that mismatches REJECTS the install (`Sha256.hash1` over the zip entries = the Go
     `dirhash.Hash1` port from B3d-3); an absent file proceeds (matching cue). Recorded in
     `cue-spec-gaps.md`; cue.sum WRITE (`cue mod tidy`) is B3d-6. **Read-path UNCHANGED when the
     module IS present:** the fetch fires ONLY on the `none` branch; a vendored/cached dep takes
     the existing path with no fetch. **Canary (non-regression):** `kue export apps/argocd.cue`
     from `prod9/infra` (`prodigy9.co/defs` cached) is byte-identical to `cue export`
     (`jq -S` diff = 0) — no fetch triggered, the B3d-5a cache-path unification did not move the
     real lowercase module. **Offline pipeline test:** `scripts/check-fetch-pipeline.lean` (wired
     into `check-fixtures.sh`) drives `fetchAndCacheModule` with a local fixture zip
     (`testdata/ocifetch/pipeline/`, a real DEFLATE `lib.example/defs@v0.1.0`) and
     `CUE_CACHE_DIR` → a repo-local temp dir — pinning install+locate, the download-layout, the
     cue.sum accept+reject paths, `none`-registry, and transport-failure (no network, no real-cache
     write). Totality: no new `partial`/`sorry`; only `propext`/`Classical.choice`/`Quot.sound`.
     **The live HTTPS fetch from `registry.cue.works` (network + real-cache write) is human-gated —
     see `.afk.log`.** Remaining for B3d-6: MVS version *solving*, `cue mod get/tidy` commands, and
     `cue.sum` WRITE.
   - **B3d-5a — UNIFY the cache-layout authority (DRY, MED; do AS PART OF B3d-5) — DONE
     (2026-06-26, folded into B3d-5).** `Registry.{extractCachePath,downloadCachePath}` is now the
     SOLE cache-layout authority: `Module.locateModuleDir`'s `cached` candidate is built via
     `Registry.extractCachePath ((cacheRoot/"mod").toString) (Registry.mkModuleVersion …)` — the
     same call the B3d-5 write-path uses — so read-path and write-path agree by construction,
     including the on-disk `escapeString` of any upper-case path. Byte-identical for real lowercase
     modules (the argocd canary stayed at 0-line diff; `ModuleTests` pins
     `extractCachePath "/c/mod" (mk "lib.example/defs" "v0.1.0") = "/c/mod/extract/lib.example/defs@v0.1.0"`
     and the escaping-identity), closing the latent uppercase divergence
     (`Foo.com/Bar` → `…/extract/!foo.com/!bar@…`, also pinned). Closes the cache-layout finding
     from the B3d Phase-B audit (2026-06-25).
   - **B3d-6a — semver compare + pure MVS solver (PURE, offline) — DONE (2026-06-26).** The
     fully-offline pure core of B3d-6: the version-ordering + version-selection math, with NO
     network. Two new IO-free, total modules. **`Kue/Semver.lean`** — a faithful port of Go's
     `golang.org/x/mod/semver` `Compare` (the package cue depends on; authoritative over
     semver.org): `parse : String → Option Parsed` (leading `v`, `vMAJOR`/`vMAJOR.MINOR`
     `.0`-shorthands, no-leading-zero `parseInt`, `-prerelease` + `+build` tails, identifier
     validity incl. `isBadNum`), and `compare` returning `-1/0/+1` — invalid < valid (two invalids
     equal); numeric major/minor/patch via Go's `compareInt` (LENGTH-then-ASCII on the no-leading-
     zero decimal string, so `v1.2.0 < v1.10.0` numerically); a prerelease sorts BEFORE the same
     release; prerelease identifiers dot-by-dot (numeric < non-numeric, two numerics by length-then-
     ASCII, longer equal-prefix set wins) via the SPLIT `comparePrerelease` (empty=no-prerelease is
     HIGHER) / `comparePrereleaseIds` (exhaustion ⇒ shorter is LOWER) — the two rules Go's single
     function conflates at its top-level empty-string check. **Build metadata `+…` ignored in
     precedence** (parsed for validity only). Cite: `~/go/pkg/mod/golang.org/x/mod@v0.15.0/semver/
     semver.go`. **`Kue/Mvs.lean`** — Russ Cox's MVS (cue `internal/mod/mvs/{mvs.go,graph.go}`):
     `solve : ModuleVersion → RequirementGraph → List ModuleVersion` where `RequirementGraph =
     List (ModuleVersion × List ModuleVersion)` is an EXPLICIT finite value (no IO callback —
     deterministic, pure, total). Algorithm = **max of the mins**: the transitive reachable set
     from the root, then per module-PATH the MAXIMUM version seen anywhere (`Graph.Require`'s
     `selected[path]=max(...)` via `Semver.compare`); build list = target first (pinned to its own
     version — `reqs.Max(target,v)==target`), then every other selected path sorted by
     `(path,version)` (`Graph.BuildList`+`sortVersions`). **Distinct majors are distinct paths**
     (`m` vs `m/v2`) ⇒ they coexist, never a conflict. **Termination (no `partial`):** reachability
     is `reachAux` with `fuel = |allNodes|+|targets|+1` and a visited set — each non-skip step adds
     one distinct node, skips shrink the worklist, so a CYCLE halts; maxima/sort are finite folds.
     **Tests** (`Kue/Tests/MvsTests.lean`, `native_decide`/`#guard`): semver — the full doc-comment
     precedence chain `v1.0.0-alpha < -alpha.1 < -alpha.beta < -beta < -beta.2 < -beta.11 < -rc.1 <
     v1.0.0`, numeric-vs-alpha, `v1.2.0<v1.10.0`, build-ignored, invalid<valid, leading-zero
     invalidity, shorthands. MVS — the canonical **diamond** (main→A,B; A→C v1.2.0; B→C v1.3.0 ⇒
     select C v1.3.0, max of mins), an **upgrade** (direct higher min dominates), a **downgrade-by-
     not-requiring** (drop B's edge ⇒ C falls to v1.2.0), same-module-two-mins→higher, distinct-
     majors-coexist, a **cycle terminates**, unreachable excluded, empty⇒just-main, main-path-
     pinned-over-a-higher-graph-version, and path-sorted remainder. Total, no `sorry`/`partial`/
     axioms beyond `propext`. NOT yet wired into the resolver (that needs the network-fetched
     requirement graph) — B3d-6b.
   - **B3d-7 — OCI bearer-token auth (curl + docker credential-helper) — DONE (2026-06-28).** The
     curl edge did a BARE GET, so real registries (`ghcr.io`) `401`'d it. Added the Docker/OCI
     **Bearer-token flow** with NO new binary dependency (oras/crane rejected to keep "self-
     contained on ubiquitous tools" — curl + the docker credential-helper protocol only). PURE
     core `Kue/OciAuth.lean` (`native_decide`-pinned, total): `parseChallenge` (a
     `WWW-Authenticate: Bearer …` header → `{realm, service, scope}`, tolerant of param order,
     quotes, whitespace, case-insensitive scheme, comma-in-quoted-scope, extra params);
     `tokenUrl`/`queryEncode` (RFC-3986 token-request URL build); `parseTokenResponse` (`token` ∥
     `access_token`); `credSourceFor` (docker `config.json` → `inline base64` ∥ `helper binary` ∥
     `none`, with `credHelpers.<host>` > `credsStore` > inline precedence); `splitUserPass` /
     `parseHelperResponse`. `Kue/Base64.lean` gained a total `base64Decode`/`base64DecodeString`
     for the inline `auth` field. IO edge in `Kue/OciFetch.lean`: `authedGet` (bare GET → on `401`
     header-probe via `curl -D -` → `parseChallenge` → `resolveCredential` (inline base64-decode ∥
     spawn `docker-credential-<helper> get`, host on stdin) → `mintToken` (Basic-auth GET to the
     realm; anonymous tokenless mint when no cred — public repos) → authed retry with
     `Authorization: Bearer`); an in-memory `TokenCache` (`IO.Ref`) keyed by realm|service|scope so
     a module's manifest + blob GETs reuse ONE token. `fetchManifest`/`fetchBlob`/`fetchModuleZip`
     route through it; binary-blob raw-byte capture is preserved (no UTF-8 decode of blobs). 🔒
     Secret hygiene: a credential/token lives only in argv for the curl child + in-memory strings,
     never logged/persisted/committed; errors report outcomes (an unsatisfiable `401`, a helper
     non-zero exit), never the secret. **Proven LIVE** against real `ghcr.io` for
     `prodigy9.co/defs@v0.3.19` (`CUE_REGISTRY=prodigy9.co=ghcr.io/prod9`, osxkeychain helper):
     manifest = the validated 2-layer module manifest; zip blob DIGEST-VERIFIES
     (`sha256:b5de5cb…ffa2fb`, 109225 bytes). Offline pins in `Kue/Tests/OciAuthTests.lean`; the
     live probe is `scripts/check-ghcr-live.lean` (NETWORK+creds, deliberately NOT in the offline
     `check-fixtures.sh` gate). **Unblocks B3d-6b's requirement-graph fetch** against
     authed/private registries.
   - **B3d-6b — `cue mod get/tidy` + requirement-graph fetch + cue.sum WRITE (NETWORK-GATED) —
     REMAINING.** The network-dependent command surface that sits ON TOP of B3d-6a's pure solver,
     deferred out of the AFK envelope (live registry egress needs a human). Needs: (1) fetch each
     dep's `module.cue` (its `deps` block) to BUILD the `RequirementGraph` the solver consumes —
     reuses the B3d-4 curl edge (now BEARER-AUTH-CAPABLE via B3d-7, so private/authed registries
     work) + a `module.cue` `deps` parser; (2) tag-listing on the registry to
     resolve "latest"/major→concrete-version for `cue mod get <module>` (the OCI `…/tags/list`
     endpoint); (3) the `cue mod get` / `cue mod tidy` CLI command parsing + dispatch; (4) wiring
     `Mvs.solve` into the resolver — replace the current lenient per-hop resolution (see
     `compat-assumptions.md`) with a single up-front MVS build-list computed from the fetched
     graph; (5) `cue.sum` WRITE via `Module.atomicWriteBinFile` (the dirhash machinery from B3d-3
     already exists; only the tidy-time WRITE is missing). All five are network/command-surface
     work; the version math they depend on is DONE.
   - **Shared bytes-util module (`Kue/Bytes.lean`) — YAGNI, NOT now.** Phase A flagged
     `Sha256.hex` (bytes→hex) + the dirhash byte-ordering as candidate shared primitives.
     Decision (Phase B, 2026-06-25): `Sha256.hex` is the codebase's ONLY bytes→hex encoder
     and has exactly ONE consumer (`digestString`/`hash1`, both in `Sha256.lean`).
     `Yaml.lean`'s `hexDigit` is a different thing — an is-hex-digit *predicate* for token
     resolution, not byte encoding — so NO duplication exists. `escapeString`/percent-encoding
     live in `Registry.lean` and have no second consumer either. Extracting a shared
     bytes-util before a second consumer exists is a premature abstraction (the repo's
     illegal-states-first philosophy favors tight homes, not speculative util drawers).
     **Re-evaluated at B3d-4 (2026-06-26, Phase-B): CONFIRMED STILL YAGNI** — the curl edge
     added NO cross-module hex/int-read consumer (`Sha256.beWord` is BE, `Zip.u16`/`u32` are LE,
     one consumer each; `Inflate` is bit-level only). Next trigger is a THIRD module needing
     multi-byte int reads. Full re-eval in the B3d Phase-B audit section below.

**Walker / normalizer dedup family — FULLY CLOSED.** Decomposition ruling (durable, do not
re-litigate): the walkers were NEVER one problem — three distinct walker families + a
separate normalizer pair, different mechanisms/result-types/recursion-domains/termination
measures; folding them under one abstraction would be a false "stuff they all do"
extraction. **Status: AD4-1 + A-EN3 DONE; DRY-1 RULED OUT; AD2-1 RESOLVED (2026-06-21,
unified); embedChainAny SHARED (2026-06-23, `0619097`).** No open members. The embed-chain
share (`bodyNeedsDefer` + `embedBodyEmbedsDisjDeep` → one `embedChainAny (leaf)` combinator)
is the AD4-1-safe case — pure non-recursive leaf, recursion owned by the combinator — NOT a
re-litigation of DRY-1 (whose variation point WAS the recursion). Detail in Resolved/ruled-out
(`embedChainAny` entry) + git.

**CARRIER-DECL-SELECT (DRY, LOW) — DONE 2026-06-22.** Extracted `selectFromDecls (base) (label)
(decls) : Value` (`findEvalField` → `selectedFieldValue` / deferred `.selector base label`) and
routed all SIX byte-identical Eval sites through it: top-level `.struct`/`.embeddedList`/
`.embeddedScalar` + the three `resolveDisjDefault?` sub-case arms. **Home = `Eval.lean`, no new
edge** — `Runtime` already imports `Eval`, so `Eval` is the lowest module both reach (graph
unchanged). **`Runtime.lookupField?` is a DIFFERENT operation, NOT shared across the seam** — it
yields the RAW `Field.value` (no close) and returns `Option` (genuine-absence `none` for the `-e`
"field not found" diagnostic, never a deferred `.selector`); routing it through `selectFromDecls`
would silently change behavior + DRY across a module boundary. Only the WITHIN-Runtime triplication
collapsed (a 1-line local `fieldValue?`). +2 `native_decide` pins
(`TwoPassTests.select_into_default_disjunction_{scalar,list}_carrier` — the thin disj-resolved
carrier-select path). Behavior-preserving: 110-job build clean, fixtures zero-drift, pin-count
conserved +2. NO cue-divergence, NO spec-gap. Detail in the implementation-log. **Distinct from
FOUR-classifiers** (those DISAGREE on the partition; here the three shapes AGREE exactly — real
dedup, not false-sharing). Next leader: the **item-6 LOW list** (`module-file-scoped-imports`,
parser strictness `*(1|2)`/`__x`, A2-x/y, B2-A1/A2, `resolveEmbeddedDisjDefault` check — all LOW,
none soundness-bearing).

## B3d track — CLOSED (audit history distilled 2026-06-26)

The registry/OCI module-fetch track (decision: `docs/decisions/2026-06-25-registry-fetch-via-curl-subprocess.md`)
landed end-to-end. Modules: `Registry` (CUE_REGISTRY parse + module→OCI-ref + cache-path
authority), `Oci` (manifest parse + URL/curl-arg builders), `OciFetch` (the sole `IO.Process`
curl edge + the three integrity gates), `Sha256` (FIPS 180-4 + `h1:` dirhash), `Inflate` (RFC
1951 DEFLATE), `Zip` (PKWARE + CRC-32), `Semver` (Go `x/mod/semver` port), `Mvs` (pure MVS
solver), and `Module.lean` wiring (`fetchAndCacheModule` + atomic cache-write). B3d-1...B3d-5
(+5a/5z), B3d-6a, and B3d-A1 are DONE; the live HTTPS fetch is human-gated (`.afk.log`).

Both 2026-06-26 audit rounds closed **HEALTHY**: module graph is a clean DAG (no cycles; IO
confined to `OciFetch`+`Module`; `Eval`/`Resolve`/`Value` import ZERO B3d module; the pure-island
-> thin-IO-edge seam holds); the three integrity gates (blob `sha256:` digest, zip CRC-32+size,
`cue.sum` `h1:`) are enforced and unbypassable on the production path; inflate is total
(fuel-bounded, malformed -> typed-error). Phase A found + FIXED inline two Violations (semver
empty-prerelease/build-segment validity; MVS `reachable` fuel silently truncating dense graphs ->
bound is now `(N+1)²`); Phase B sharpened B3d-A1 (now DONE) and filed B3d-B1. Totality
`#print axioms`-pinned (`Semver.compare`/`Mvs.solve`/the atomic-write trio: stdlib axioms only,
no `sorryAx`/`partial`). `Kue/Bytes.lean` extraction re-evaluated TWICE -> confirmed YAGNI (no
cross-module hex/int-read consumer; re-trigger only on a THIRD multi-byte-int reader). The full
blow-by-blow (every slice, mechanism, the two fixed Violations, integrity-gate trace) is HISTORY
-- in `implementation-log.md` (71 B3d entries) + git.

**`Mvs.solve` dead-code ruling:** ACCEPTABLE staged primitive, NOT orphan. It is pure, total,
fully `native_decide`-pinned (diamond/upgrade/downgrade/cycle/distinct-majors), and unwired only
because wiring it into the live resolver is a network/human-gated BEHAVIOR change (the requirement
graph it consumes must be fetched) -- filed as B3d-6b, not stranded. Reachable from `MvsTests`
today; the resolver edge lands with the rest of B3d-6b.

**Open B3d items (ranked):**
- **B3d-6b** (NETWORK-GATED, the single remaining substantive slice) -- see the entry under
  Live Backlog item 7. Five legs, all needing live registry egress or the command surface:
  (1) fetch each dep's `module.cue` `deps` block to BUILD the `RequirementGraph`; (2) OCI
  `.../tags/list` for "latest"/major->concrete; (3) `cue mod get`/`cue mod tidy` command parse +
  dispatch; (4) wire `Mvs.solve` into the resolver (replace lenient per-hop resolution with one
  up-front MVS build-list) GATED ON a diamond-divergence fixture; (5) `cue.sum` WRITE via
  `Module.atomicWriteBinFile` (the B3d-3 dirhash + B3d-A1 atomic primitive both already exist).
- **B3d-A2** (test-strength, LOW) -- pin the DEFLATE/ZIP adversarial reject branches (invalid
  Huffman code, distance-too-far-back, STORED LEN/NLEN, fuel exhaustion, bad CD sig, unsupported
  method, CRC/size mismatch); only BTYPE=3 is pinned today.
- **B3d-B1** (type-leverage, LOW -- rides B3d-6b) -- `Descriptor.digest`/`cue.sum` `h1:` are
  `String` with an unenforced format invariant; a `Digest`/`Hash1` smart-constructor newtype earns
  its keep at B3d-6b's sum WRITE boundary (makes "emit a malformed sum" unrepresentable). YAGNI
  until that second consumer exists.
- **`Mvs.solve` main-pin** (philosophy-clean, LOW -- rides B3d-6b) -- `solve` silently pins `main`
  to `main.version` even when the graph names a higher version of main's path (cue PANICS there).
  Realistic inputs never trigger it; make it unrepresentable or a typed error rather than a silent
  mask when the resolver wiring lands.
- **`Kue/ModuleFetch.lean` carve** (architecture, conditional) -- `Module.lean` (674 lines) is
  NOT yet outgrowing its home; the fetch/cache cluster (~90 lines) is coherent. Trigger: if B3d-6b
  pushes that cluster past ~200 lines or adds a distinct command-dispatch responsibility, carve
  then (it would import `OciFetch`/`Zip`/`Sha256`/`Registry`, leaving `Module.lean` the read-path +
  loader). Filed as a trigger, not a now-slice.
- **`kue-performance.md` B3d note** (doc, LOW) -- inflate is O(output) fuel-bounded; fetch latency
  is curl/network-dominated, off the eval hot path; the new `native_decide` vectors are one-shot
  compile-time, not per-eval. Fold into a coming B3d slice.

## Resolved / ruled-out (recorded so they are not re-raised)

**Audit 2026-06-25 (Phase B, architecture/refactor over the whole module graph; B3d-readiness
focus; baseline `9afd54c` Phase-A HEALTHY) — HEALTHY.** Two-phase audit CLOSED. Build green
(122 jobs), fixtures zero-drift. Headlines:
- **B3d-4/5 seam is STRUCTURALLY SOUND and the right shape for the IO edge.** The new pure
  island `Registry`/`Sha256`/`Oci` has NO inbound deps and imports only `Base64`
  (`Sha256`) / `Lean.Data.Json` (`Oci`) / nothing-Kue (`Registry`). The IO edge lives in
  `Module.lean` (imports `Parse` + `Runtime` only). **Recommended import edges for B3d-4/5
  (hand these to the orchestrator):** `Module → Oci` (parse the GET'd manifest),
  `Module → Sha256` (verify `digestString blob == descriptor.digest`; `cue.sum` `hash1`),
  `Module → Registry` (resolve `CUE_REGISTRY` + cache-path authority — see B3d-5a). All
  three point IO→pure, the correct direction; NONE creates a cycle (the pure trio imports
  nothing under `Kue/` except `Base64`, and `Module` is downstream of everything). `Eval`/
  `Resolve`/`Value` never touch the trio and must not — verified they don't today. The
  decision note's "IO is confined to `Module.lean`" invariant holds and is enforceable by
  these one-directional edges. No risk B3d-4 pulls IO into a pure module IF the edges go
  Module→{Oci,Sha256,Registry} and never the reverse.
- **Type-system leverage in the new island: TIGHT (spot-checked, confirms Phase A).**
  `RegistrySpec`/`Resolution`/`Descriptor`/`OciManifest` are sum/record types that make
  illegal states unrepresentable (a `none` registry carries no host; a descriptor missing a
  field is a parse error, never a placeholder). No loose-type tightening to propose in the
  new code. (Module-graph-wide loose-type sweep: nothing new beyond the standing item-6 list;
  the registry-fetch foundation did not regress it.)
- **Cache-path duplication: CONFIRMED OVERLAP** (read-path `Module.locateModuleDir` vs
  write-path `Registry.extractCachePath`/`downloadCachePath`) — filed as **B3d-5a** in the
  B3d section above: same path for real lowercase modules, one latent uppercase-escaping
  divergence, consolidate INTO B3d-5 (not standalone, since both paths aren't live until
  then). Not inline-fixed: speculative before the second consumer exists.
- **Shared bytes-util (`Kue/Bytes.lean`): YAGNI** — single consumer of `Sha256.hex`, no real
  duplication (Yaml's `hexDigit` is a predicate, not encoding). Filed in B3d section;
  re-evaluate at B3d-4. No `String.dropRight`/deprecated APIs, no stale TODOs in the new
  modules. SHA-256 tests are all `native_decide` (native-compiled, no kernel-reduction perf
  hit) — `kue-performance.md` needs NO note. Test files well-sized (Registry 285, Sha256 176,
  Oci 190 lines); `testdata/` untouched by B3d (the OCI/SHA fixtures are in-Lean vectors).
  **No inline cleanups committed** (the one real finding, B3d-5a, is a B3d-5 sub-task, not a
  low-risk inline edit). **Overall: architecture HEALTHY; B3d-4 has a clean target.**

**Audit 2026-06-25 (Phase A, code-quality; batch `1bd93d8..fc5456d` = B3d-1/2/3 registry-fetch
foundation: `Registry.lean`, `Sha256.lean`, `Oci.lean` + tests) — HEALTHY.** All re-derived
against cue v0.16.1's own OCI tooling (the authority for this non-language-spec layer):
`internal/mod/modresolve/resolve.go`, `mod/module/escape.go`, `mod/modregistry/client.go`,
`mod/modzip/zip.go`, and `cuelabs.dev/.../ociref/reference.go`.
- **Illegal-states (checked first):** strong. `RegistrySpec` (`none` | `reg host insecure repo`)
  makes "no registry" unconfusable with an empty real one; `Resolution` (`found`/`noRegistry`/
  `error`) gives `none`-routing its own constructor, never a sentinel host; `OciRef`/`Descriptor`
  always carry all fields — a manifest omitting any descriptor field is a parse ERROR, not a
  zero-placeholder. No loose `String`/`Bool`/`Option` carrying a hidden invariant; no
  "can't-happen" branch a tighter type should erase.
- **Correctness:** confirmed against source. Registry: complete-element longest-prefix match
  (`bar` ∤ `barry`), insecure-host defaults, UNescaped repo = `path.Join(prefix, basePath)`,
  tag = plain version, escape applied to cache dirs only — all matching `resolve.go`. Host/repo
  first-`/` split coincides with `ociref.Parse`'s `(domainAndPort)/` regex (host never contains
  `/`). SHA-256: NIST vectors + 0/55/56/63/64/65/119 padding boundaries pinned vs an independent
  `shasum`; dirhash `%x  %s\n` two-space line + byte-sort + `h1:`+base64Std verified vs the Go
  algorithm; BARE zip-entry names confirmed vs `modzip.Create` (line 563 `zw.Create(path)`, no
  `<mod>@<ver>/` prefix). Oci: by-mediaType exactly-one layer selection (stronger than cue's
  index check) accepts every well-formed cue manifest, rejects malformed.
- **Totality:** no `partial`/`sorry`/axiom in any of the three modules; `#print axioms` on
  `resolveFromConfig`/`parseConfig`/`sha256`/`hash1`/`parseModuleManifest` shows only
  `propext`/`Classical.choice`/`Quot.sound`.
- **DRY/reuse:** `hash1` reuses `Kue.base64Encode`; Oci reuses the stdlib `Lean.Json.parse`
  (genuinely dependency-free, total) — `Kue/Json.lean` is serialize-only, so no second parser.
  `hex` is genuinely new (no prior bytes→hex helper). No cross-module duplication.
- **Test strength:** strong. No `testdata/` fixtures slipped in (pure unit pins only — the
  fixture-pair rule N/A). Edge pins present for empty-config, IPv6 (loopback + non-loopback +
  port), duplicate-prefix/catch-all errors, SHA-256 multi-block, dirhash ordering, manifest
  duplicate/absent-layer, malformed JSON, missing/non-numeric fields.
- **Inline fix (LOW-RISK, committed `11cfc77`):** the registry-fetch decision note said B3d-2
  would "reuse `Json.lean`"; that file is serialize-only and the slice correctly used the stdlib
  parser. The durable docs (compat-assumptions L619, impl-log L14066) already described the actual
  choice; only the pre-slice decision note misled. Aligned both references.

Borderline (flagged once, NOT fixed — `cue`-byte-identity is never the gate):
- **Oci error phrasings drift from `client.go`.** cue's `GetModuleWithManifest` prints the manifest
  *response* mediaType (`"%v does not resolve to a manifest (media type is %q)"`); Kue prints the
  *config* mediaType in `"does not resolve to a module manifest (config media type is …)"`. The
  CHECK is identical (`isModule` on config mediaType); only the message text differs. Tests assert
  `.error _`, so no behavior gate. Leave as-is unless a future slice needs message parity.
- **`isModuleFile` artifactType branch unmodelled.** cue accepts the modulefile layer if EITHER
  `desc.ArtifactType` OR `desc.MediaType` equals the modulefile type (`client.go:593`); Kue's
  `parseDescriptor` drops `artifactType` and matches on `mediaType` only. cue's own producer
  (`putCheckedModule:393`) sets `MediaType`, so every cue-produced manifest passes; the gap is a
  foreign producer that tags the type in `artifactType` only — narrow, and consistent with Kue's
  documented "strictly stronger than cue's index check" stance.
- **`hostOf` unbracketed-multi-colon host string.** For an (invalid, cue-rejected) bare IPv6 like
  `2001:db8::1`, Kue keeps text before the LAST colon while cue's `net.SplitHostPort` errors and
  falls back to the whole string. The `isInsecureHost` RESULT agrees (secure) and such hosts are
  rejected upstream by `ociref`, so no real divergence.

Out-of-scope (pre-existing / deferred-by-design, noted not fixed): the `file:`/`inline:` and full
CUE-syntax config form (`pathEncoding`/`stripPrefix`/`prefixForTags`/`hashAsRepo`/`hashAsTag`) are
footnote-deferred in compat-assumptions; host/path/version VALIDITY (`CheckPath`/`IsValidHost`/
semver) is a documented caller invariant, not enforced here. Both are intentional B3d scope cuts.

**Audit 2026-06-23 (Phase A, code-quality, SCOPED single-pass; batch `890d453..2bd75eb` =
resilience/retrospective pass + A2-y import-name redeclaration) — HEALTHY.** A2-y is the only code
change. **OVER-strictness: NONE** — every valid witness oracle'd vs cue v0.16.1 ACCEPTS where cue
accepts and REJECTS where cue rejects (alias-no-collision `import d` + `x:`/`dep:` field, quoted
`"dep"`, `#dep`/`_dep`, nested, different-name, qualified-import `"…:foo"` + `foo:`, builtin
`encoding/json` + `json:`, per-FILE sibling `dep` with no import there — all match cue). The
soundness fix is SOUND: a non-colliding field resolves to the FIELD and the import to the PACKAGE,
byte-identical to cue (`thing`/`fromField`/`fromPkg` witness). The `ParsedField.quoted` parser
ripple is CLEAN: `quoted` true only for `"…":` string labels, false for bare + `#`/`_`; both
construction sites + both match sites (`bareIdentifierLabels`, `splitParsedFields`) updated, no
missed site, no `_`-swallow of a future constructor on the eligibility path. TOTALITY: no new
`partial`/`sorry`/axiom; the four new defs are total; IO confined to `Module.lean` (`Eval`/`Resolve`
untouched). Canaries jq-S=0 (cert-manager 38 lines, argocd 1195 lines). Docs records accurate
(cue-divergence single-vs-two-line, spec-gap aliased-field corner, plan/spec-conformance/impl-log all
consistent). **+2 coverage fixtures added inline** (`import_name_field_resolves` pins the exact
wrong-value the soundness fix closed; `import_alias_no_collision` pins A2-y does NOT over-reject a
bare field under an import alias). **ONE latent finding surfaced, NOT a regression:** aliased-builtin
call resolution (`import j "encoding/json"` + `j.Marshal` → `incomplete value`) — pre-existing,
prod9-unaffected, filed in the item-6 LATENT tail above. Verdict: **HEALTHY.**

**Audit 2026-06-23 (Phase B, architecture/refactor; batch `e2d8868..4431597` = parser-strictness +
release-tooling + per-eval empty-`cache`-skip) — HEALTHY (light confirm-and-close; Phase A HEALTHY
`4431597`). 🎯 This round records the CONSOLIDATED-COMPLETE state: spec-conformance backlog EMPTY
AND per-eval perf frontier CLOSED.** Phase A came back HEALTHY (cache-skip byte-identical on
truncating witnesses, parser over-strictness ruled out, release-tooling sound; 3 truncation pins
`4431597`). **Module graph: ACYCLIC + layered, unchanged** — `Value` base → lattice/`Eval`/`Builtin`/
`EvalOps` → `Runtime` (top integration) → `Cli`/`Main`; no cycles. The empty-`cache`-skip
(`Eval.lean:3127`, `if st.cache.isEmpty then none else …`), the parser arms (`Parse.lean`), and
`scripts/tap-push.sh` add NO cross-module edge. **`Eval.lean` = 4318** (+23 since 4295 last round;
below the ~4500 `Eval.DefDeferral` carve watch — ruling stands, not due). **Tech-debt sweep clean**
(no new `partial`/`sorry`/axiom; only TODO/XXX hits are `\uXXXX` doc-comments in `Json.lean`). The
**`KUE_PROFILE` instrument** retained by the per-eval slice is SOUND to keep: fully env-gated in
`Main.lean:91` (`(← IO.getEnv "KUE_PROFILE").isSome`), routes through a SEPARATE entry point
(`resolveAndEvalProfileString` → `evalStructRefsProfile`) reached ONLY when set — zero-cost on the
hot path when off. **Test/fixture health:** `Bug2xTests` 1294, `TwoPassTests` 1493, `EvalTests`
1743, `ParseTests` 809, `EvalPerfTests` 634 — all under the ~2000 silent-failure watch; no org due.
**Perf-guide currency CONFIRMED:** `kue-performance.md` records the per-eval frontier CLOSED
(floor-characterized: argocd ~52s ≈ 486K necessary evals × irreducible meet cost; cache/hash ~2-3%;
empty-`cache`-skip at noise floor; frame-sharing WON'T-FIX ~0.05% ceiling) — accurate, matches code.
**Overall: architecture HEALTHY.** No inline code cleanups needed. Two-phase audit CLOSED; counter →
0. **🚨 NEXT LEADER = the RESILIENCE / RETROSPECTIVE pass (OVERDUE)** — ~11 audit cycles / 23
Phase-A/B commits with ZERO retros and accrued operational learnings; see the breadcrumb for the
enumerated learnings to fold into `failure-modes.md` + `slice-loop.md`. AFTER that: the item-6 LATENT
tail / SC-3. `v0.1.0-alpha.20260623` CUT + formula live (3 platforms).

**Audit 2026-06-23 (Phase A, code-quality, SCOPED single-pass; batch `db8700f..HEAD` =
nested-disj-mark designed-deferral `86538ba` + disj-select DRY collapse `cdf2f39`) — HEALTHY.** The
DRY collapse (`selectEvaluatedField`'s `.disj` resolved-default carrier dispatch extracted to a
shared non-recursive `selectFromConcrete`) is the only code change, and it is BEHAVIOR-SENSITIVE —
fully re-oracled vs cue v0.16.1 + diffed against a `db8700f` before-binary:
- **Carrier defaults BYTE-IDENTICAL** (before-binary diff = 0): struct/list-valued-field/select-
  other-arm all `1`/`[1,2]` pre = post = cue. `selectFromConcrete` dispatches exactly as the old
  inline 5-arm.
- **Scalar-default-select fix CORRECT == cue** — int/bool/null/list/ref-resolved-scalar defaults: the
  dead arm now sheds (`x: *5|{a:1}; y: x.a | "fb"` → `"fb"`), where OLD went AMBIGUOUS (a kue bug).
  Bare select bottoms (cue type-errors); kue emits `conflicting values (bottom)` vs cue's `invalid
  operand …` — message-only divergence, NOT a value divergence (byte-identical-to-cue is not the
  gate; the spec verdict "field-select off a scalar is an error" is what matters).
- **`_ => .bottom` catch-all NEVER over-bottoms.** Probed the worry case: an INCOMPLETE default
  (`*int`, `*(>5)`) makes the WHOLE `x` field incomplete and never reaches a resolved-default select
  (cue/old/new all `incomplete value`), so the only values reaching `selectFromConcrete` via a
  resolved default are concrete scalar/carrier — exactly where pluck-or-bottom is right.
- **Deep-nested `.disj`-default DEFERS unchanged** (explicit `some (.disj _) => .selector`); ambiguous-
  `none` unchanged; both byte-identical pre/post.
**Deferred-mark tripwires UNFLIPPED** — the 5 `nested_disj_mark_*` pins (2 `DEFERRAL_witness`
`exportJsonBottoms = true` + 3 others) are a MEET-time Mark issue, orthogonal to selection;
`cdf2f39` touches zero pin lines, `86538ba` is code-free (test pins + docs only). **TOTALITY:**
`selectFromConcrete` non-recursive (trivially terminating), no new `partial`/`sorry`/axiom, no
`_`-swallow hiding a reachable case. **DRY genuine:** the carrier dispatch now lives in ONE place
(was re-listed in the `.disj` sub-case). **Canaries jq-S=0** (cert-manager + argocd, direct from
`prod9/infra`). **+6 coverage pins added inline** (`593fa58`: bool/null/list/ref-scalar shed +
direct `.bottom` dispatch + `#check`). **ONE docs nuance, NOT a regression:** `86538ba`'s STEP-0
claims inline `*( … )` is a cue parse error — cue v0.16.1 actually accepts `*(*{a:1}|{a:2})|{a:9}`
→ `{a:1}`; the deferral itself is correctly pinned, so this is a basis-prose imprecision in the
nested-disj-mark adjudication, not a code or pin issue. Verdict: **HEALTHY.**

**🎯 CONSOLIDATED-COMPLETE STATE (2026-06-23).** The substantive backlog is EXHAUSTED on two axes
simultaneously: **(1) spec-conformance backlog EMPTY** — every correctness item RESOLVED; argocd +
cert-manager are content-identical drop-ins (jq -S diff = 0). **(2) per-eval perf frontier CLOSED** —
floor-characterized (argocd ~52s ≈ 486K necessary core evals × the irreducible per-meet cost; the
cache/hash machinery is only ~2-3%; cross-env frame-sharing is a false-share, WON'T-FIX). The only
remaining perf lever is the USER-controllable one (flatten / shorten chains → fewer evals). Released
`v0.1.0-alpha.20260623` (3 platforms, race-safe tooling). **What remains is LATENT / CLEANUP only:**
the item-6 tail (A2-x/y loader corners, B2-A1/A2 latent, `module-file-scoped-imports` [prod9 doesn't
hit], `resolveEmbeddedDisjDefault` check, DRY `selectEvaluatedField .disj`) + SC-3 (display-gap) —
none soundness-bearing. Plus the now-OVERDUE resilience/retrospective pass (next leader).

**Audit 2026-06-23 (Phase B, architecture/refactor; batch `735dc10..0459beb` = flatten-bound perf
+ SC-4 nested HIDDEN/LET closedness) — HEALTHY (light confirm-and-close; Phase A HEALTHY `0459beb`).
🎯 This round records the SPEC-CONFORMANCE-BACKLOG-EMPTY milestone.** Phase A confirmed the backlog
is genuinely empty (SC-4 + Bug2-12 RESOLVED; only perf #7 — a perf lever — and SC-3 — display-only
— remain). **Module graph: ACYCLIC + layered, unchanged** — SC-4's `Normalize.lean` change keeps
`Normalize → Value` only; the flatten visited-bound sits in `Eval`'s upper helper region; no new
cross-module edge. **`Eval.lean` = 4295** (+13 since 4282 last round; below the ~4500
`Eval.DefDeferral` carve watch — ruling stands, not due). **Tech-debt sweep clean** (no new
`partial`/`sorry`/axiom; only TODO/XXX hits are `\uXXXX` doc-comments in `Json.lean`); **no new
duplication**. **Test/fixture health:** `Bug2xTests` 1294, `TwoPassTests` 1493, `EvalTests` 1743 —
all under the ~2000 silent-failure watch; no org due. **Perf-guide currency CONFIRMED:** argocd
~50.3s, cert-manager ~11.7s; perf #7 frame-sharing WON'T-FIX (~0.05% ceiling), flatten-bound DONE,
per-eval-CONSTANT the live lever — `kue-performance.md` accurate. **Doc-hygiene shed APPLIED:**
removed the RESOLVED SC-4 + Bug2-12 (+ Bug2-12b + FIX-SEAM DESIGN block) + missing-field-selection
entries from `spec-conformance-audit.md` § Genuinely-open ranked backlog (as-built in
`implementation-log.md` + git); the list now reads perf #7 + SC-3 + item-6 LOW tail — NO live item
or durable ruling lost. Milestone recorded above (spec-conformance backlog block). **Overall:
architecture HEALTHY.** Two-phase audit CLOSED; counter → 0.

**Audit 2026-06-23 (Phase B, architecture/refactor; batch `32643f5..2bbdb05` = Bug2-12b + Bug2-12
MUTUAL + cycle-detector edge pins) — HEALTHY (light confirm-and-close; Phase A HEALTHY `2bbdb05`).**
Whole-graph reassessed healthy last round + the three-gate close-DRY already ruled
(SHARED-PRIMITIVE-DISTINCT-SEAMS below) → scaled pass. **Module graph: ACYCLIC + layered, unchanged.**
The new cycle-detector helpers (`defConjRefSlots` `Eval.lean:1615`, `defSlotInClosedCycle` `:1635`)
sit correctly in `Eval` just above `flattenConjDefRef` — a NEUTRAL upper region, NOT the def-deferral
tier (`:2245+`) and NOT the unsplittable core-force `mutual` (`:3004–4229`); they reuse the
`mergeDefinitionDecls` primitive (`:385`), add NO cross-module edge. **`Eval.lean` = 4282 lines**
(+~167 since the 4115 last round, all in the upper helper region) — below the ~4500 carve watch; the
`Eval.DefDeferral` carve ruling stands (trigger: a def-deferral-tier slice past ~4500, OR core-force
past ~4400 — neither met). **Tech-debt sweep clean** (no new `partial`/`sorry`/axiom; only "TODO/XXX"
hits are `\uXXXX` doc-comments in `Json.lean`, not markers). **No NEW duplication** — the three-gate
close (self-ref Bug2-12 / split-literal Bug2-12b / mutual `inCycle`) reuses `mergeDefinitionDecls`,
already ruled distinct-seams-shared-primitive (no re-file). **Test/fixture health:** `Bug2xTests`
1235, `TwoPassTests` 1493, `EvalTests` 1641 — all under the ~2000 silent-failure watch; no org due.
**Perf-guide currency CONFIRMED + HEADLINE recorded:** the **multi-ref CYCLIC** repro (`#A: #B & #C
& {a}`, both back to `#A`) added to `kue-performance.md` § Known limitations as a 3-line fast repro
of the per-eval-cost / flatten-fan-out frontier (>40s vs single-ref ~0.12s; PREDATES the cycle
detector, verified `32643f5`; `cue` cheaply rejects via the Bug2-12-mutual over-rejection so the
oracle is no profiling aid) — NOT a soundness/termination defect, record-only. argocd ~50.5s,
cert-manager ~11.4s (Phase-A jq-S=0); perf-#7 frame-sharing WON'T-FIX, per-eval-cost the live lever.
**Overall: architecture HEALTHY.** No inline cleanups needed beyond the perf-doc record. Two-phase
audit CLOSED; counter → 0.

**Audit 2026-06-23 (Phase B, architecture/refactor over the module graph; batch `fccab69..6f77bfe`
= Bug2-12 + missing-field-selection) — HEALTHY.** Thin batch (two small selection/closedness changes,
whole-graph reassessed last round) → scaled pass. **Module graph: ACYCLIC + layered** (the two changes
sit correctly — `selectFromDecls`'s `none`→`.bottom` line is in `Eval`, the Bug2-12 `flattenConjDefRef`
closer is in `Eval`, neither adds a cross-module edge). **`Eval.lean` = 4198 lines** (below the ~4500
watch; the `Eval.DefDeferral` carve ruling stands as the next carve if it grows — NOT due yet). **Dead
code: the dropped `base` param is FULLY removed** (`selectFromDecls` now takes `(label)` only; all 4 call
sites updated — confirmed no stray `base`-arg references). **Tech-debt sweep clean** (no new
`partial`/`sorry`/axiom, no stale TODOs introduced). **Test/fixture health:** `Bug2xTests` 1087 lines,
`TwoPassTests` 1493 lines (post-`0deef2f` split) — both under the silent-failure watch; no further org
due. **Perf-guide currency CONFIRMED:** argocd ~50s (jq-S=0, re-measured this audit), cert-manager ~11.5s
(jq-S=0); perf #7 frame-sharing WON'T-FIX, per-eval-cost the live lever — `kue-performance.md` accurate.
**One finding filed:** Bug2-12b fix-seam design (in `spec-conformance-audit.md` item 0). **Bug2-12b is
now RESOLVED 2026-06-23** — the close-once-via-`mergeDefinitionDecls` fix landed on the flatten path
(partition `expanded` into union-able literals vs the untouched self-ref `.refId`, close-each-first,
`foldl mergeDefinitionDecls`, close once, re-emit `rest ++ [closed]`); see implementation-log. **No
inline cleanups needed** (the batch left no debt). The close-each/close-once DRY ruling is recorded below.

**close-each vs close-once (Bug2-12 flatten path vs Bug2-7 conj-fold path) — RULED: SHARED PRIMITIVE,
DISTINCT SEAMS; the Bug2-12b fix REUSES `mergeDefinitionDecls`, it does NOT unify the two functions
(Phase-B 2026-06-23, Headline #2 adjudication).** Phase A noted Bug2-12's `close-each`
(`expanded.map close` in `flattenConjDefRef`) duplicates Bug2-7's `close-each` defect, and the
Bug2-12b fix (union-then-close-once) shares Bug2-7's root. Decomposed:
- **Same PRINCIPLE, same PRIMITIVE.** Both defects are "closed each repeated def-path decl separately,
  then meet rejects each other's fields." Both are fixed by the ONE close-once primitive
  `mergeDefinitionDecls` (`:385`) — union the same-def-path decls' field/pattern/openness sets into ONE
  body, close ONCE over the union. The Bug2-12b fix-slice REUSES this primitive (it does NOT invent a
  new union path), so the principle is unified at the primitive level — exactly as intended.
- **DISTINCT SEAMS — do NOT merge the two functions.** Bug2-7 unions WITHIN a force-fold operand
  (`mergeConjOperands` → `canonicalizeFields`'s `mergeUnevaluatedFieldInto`, dispatching on merged
  field-class). Bug2-12b unions the literal conjuncts on the DEPTH-0 SELF-REF FLATTEN path
  (`flattenConjDefRef`, gated by `isDefinition && isSelfRef`). These are different call contexts with
  different gating and different "what is a same-def-path decl here" (a force-fold operand's fields vs a
  self-rec def-body's split literals). Merging them into one function is FORBIDDEN by the standing
  `mergeFieldsWith` ruling (below): the within-operand-vs-cross-operand / which-seam-fires distinction is
  the soundness boundary, and it lives in WHICH function the caller invokes. The shared part is the
  primitive `mergeDefinitionDecls`, which is ALREADY a named, reused function — there is nothing further
  to factor. **Verdict: the two paths are genuinely DISTINCT (cycle-flatten vs conj-fold); they unify at
  the `mergeDefinitionDecls` primitive, not at the seam. The Bug2-12b slice is a FIX (reuse the
  primitive on the flatten path), not a unification refactor. Do not re-file as a DRY merge of the
  flatten and fold paths.**

**Audit 2026-06-23 (single-pass code-quality, batch `50a0db3..14fb23e`) — HEALTHY.** Scoped
single pass (thin batch: ONE Lean change `014faaf` + docs/infra; whole-graph reassessed last
round). Adversarial soundness of the perf #7 safe-wins **CONFIRMED SOUND**: (1) `selfEvaluatingLeaf?`
is EXACTLY the env/fuel-independent identity set — all 9 listed constructors (`.prim/.kind/.top/
.bottom/.bottomWith/.notPrim/.stringRegex/.boundConstraint/.thisStruct`) reach the core's trailing
`| _, value => pure value` arm, none carries an unevaluated nested `Value`, and the env-dependent
catch-all members (`.embeddedList/.embeddedScalar/.listComprehension`) are conservatively EXCLUDED
(omission keeps the sound slow path) — no false leaf. (2) Saturated-only `satCache` insert is
provably dead-code elimination: `SatKey = EvalKey ∖ {fuel}`, `satCache.get?` is checked FIRST (line
2979) before `cache.get?` (2985), so a saturated entry always serves from satCache at any fuel — the
removed fuel-keyed `cache` insert was structurally unreachable (`evalCacheHits=0` is corroboration,
not the proof). Both canaries jq -S diff = 0 (argocd 51178 B ~50.5s, cert-manager 1448 B ~12s);
5 metric pins moved to lower counts, value pins (`eval_deep_inline_value_correct`,
`selpass_value_correct`) UNCHANGED + green; full `native_decide` suite + `check-fixtures.sh` green;
no new `partial`/`sorry`/axiom. Plan-hygiene `014faaf..686f522` = NO-LOSS (all 5 live items —
per-eval-cost frontier, SC-4, Bug2-12, missing-field-selection, item-6 tail — present; removed lines
are resolved-history with commit hashes intact). Release scripts SOUND (block-aware/fail-loud/
idempotent/disjoint; one LOW concurrent-tap-race note filed in item 6). CLAUDE.md amendment coherent.
Inline fix: concurrent-release tap-clone race recorded as a LOW item-6 entry. `v0.1.0-alpha.20260623`
CUT + formula live-correct on all 3 platforms.

**Audit 2026-06-23 (single-pass code-quality, batch `20b8397..32ddfda` = type-safety catch-all
refactor `e8d6e85` + embed-disj-arm-closedness soundness fix `32ddfda`) — HEALTHY.** The TOP risk
(per-arm re-close OVER-closing a legitimately-open arm) is REFUTED, every witness oracle'd vs cue
v0.16.1: (1) a `...`-OPEN-tail default arm ADMITS a disjoint narrow (`{(*_#A{n,...} | _#B{s})} &
{extra:1}` → `{n,extra}`, NOT bottom) — `closeEmbeddedOver` is identity on a tail-bearing struct, so
the open arm is never closed. (2) a PLAIN (non-def) open arm STAYS open (`armOpen=true` ⇒ no
closedness imposed). (3) host-extra-field survives WHILE the closed arm rejects the disjoint narrow,
on ONE shape (`{h, (*_#A | _#B)} & {s:"x"}` → `{h, s:"x"}`). (4) mark-precedence / equal-default dedup
/ AD2-1 lone-default / `(*"a"|"b")&("b"|"c")→"b"` ALL unchanged. NO valid arm wrongly bottoms. The 3
reported witnesses (closed-default `n:5` leak, `incomplete int`, tagged-disjunction `#S`) == cue
post-fix. The new nested-disj-of-disj default-mark latent is GENUINELY PRE-EXISTING — independently
confirmed by building the parent `e8d6e85` in a throwaway worktree: same witness diverges there too
(`incomplete int`), the fix is strictly not-worse. The catch-all refactor is BYTE-IDENTICAL: 3 sites
(`openStructValue`/`closeEmbeddedOver`/`collapseDefaultDisjunction`) enumerate ALL non-target ctors
as pass-through identity; the 4th (`canonicalizeBuiltinCalls`) enumerates only the 11 true leaves
(every recursive ctor already recurses above) — exhaustiveness machine-proven by the compiler (green,
no `_`-wildcard). TOTALITY: no new `partial`/`sorry`/axiom; the per-arm re-close is total (`some`/
`none` exhaustive). Both canaries jq -S = 0 from infra (cert-manager ~11.5s, argocd ~51s) with the
FRESHLY-BUILT binary. **+3 over-close coverage pins ADDED inline** (`embed_disj_arm_closedness_
open_tail_arm_admits_disjoint` / `_plain_open_arm_admits_disjoint` / `_host_extra_survives_and_
disjoint_rejected`) + a `#check` sentinel — the over-close direction was unpinned pre-audit. Verdict:
**HEALTHY.**

**Per-round audit-verdict HISTORY (2026-06-21..23, ~7 Phase-A/B rounds over the
CARRIER-STRUCT-MEET → Bug2-5..2-14c → perf #7 chain) — all HEALTHY; the as-built per-round
detail is in `implementation-log.md` + git (each audit is its own commit).** Only the durable
rulings those rounds produced survive here (the named DRY/no-share adjudications below + the
carve-trigger). The recurring whole-graph facts a future audit re-verifies: the module graph is
ACYCLIC + strictly layered (`Builtin → {Lattice, Regex, Decimal, Base64, Json, Yaml, CaseTable}`,
NO `Eval`/`EvalOps` edge; `EvalOps → {Builtin, Decimal, Regex}` no back-edge; `Eval → {Builtin,
Decimal, EvalOps, Lattice, Regex, Normalize}`; `Lattice → {Value, Regex}`; `Runtime → Eval`;
`Module → {Parse, Runtime}`; `Cli → Runtime`; `Normalize → Value`); cleanliness sweeps clean (no
`sorry`/`panic!`/`unreachable!`/`.get!`-in-pure-code, no `String.dropRight`/`dropLeft`, no dead
code, no stale markers; `partial def`s are the `Parse.lean`/`Module.lean` carve-outs only, `Eval`
+`Lattice` FULLY total); test-health HEALTHY (`TwoPassTests.lean` split into `Bug2xTests.lean` at
the silent-failure 2000-line surface, both well under it; coverage tripwire + `--` line-comment
headers guard them — see item 3).

- **`Eval.DefDeferral` carve — HELD, sharpened trigger.** `Eval.lean` is ~4115 (the Bug2-14b/c
  fix grew the CORE force `mutual` block `:3707+`, the UNSPLITTABLE region — NOT the def-deferral
  tier). The named first carve is the def-deferral tier (`Eval.lean:2220–2828`,
  `defBodyHasSiblingSelfRef` … `splitDisjConjunct`, ~600 lines, a cohesive `Eval.DefDeferral`
  module) — but carving it now removes lines from a tier that is NOT where growth lands, so the
  headroom benefit is real yet indirect. **HOLD** (don't spend a slice on non-imminent, indirect
  headroom). Trigger: carve the moment EITHER (a) a def-deferral-tier slice pushes `Eval.lean`
  past ~4500, OR (b) core-force growth crosses ~4400 with the def-deferral tier still intact
  (carve FIRST to buy room before the unsplittable core forces a harder split). Schedule as a
  standalone semantic-module refactor, never inline. (Supersedes the "NOT WARRANTED at 3396"
  ruling below — same carve target, threshold reached.)
- **`resolveDefField?` (def-field resolution-skeleton share across the narrowing-delivery family)
  — RULED OUT: keep the ~6 functions SEPARATE. The full-family extraction is the `mergeFieldsWith`
  trap (variation = frame + recursion + return-type, not a pure leaf); the only frame-SAFE share
  (a narrow selector-head helper) is too thin to name and FRAGMENTS each function (Phase-B
  2026-06-23, headline adjudication).** The candidate skeleton — `env.drop id.depth.val → nthField
  id.index.val frame.snd → (.struct pkgFields → findEvalField label) → isDefinition` — recurs
  across `resolveEmbedDefBody?` (`Eval.lean:2160`), `embeddingFieldIsDefinition` (`:2201`),
  `followAliasDefBody?` (`:2331`), `resolveSelectorDefBody?` (`:2381`), `importDefClosureBody?`
  (`:2446`), and `refAliasDefClosure?` (`:2610`, via `followAliasDefBody?`). Decomposed against
  the `embedChainAny`-SHARE vs `mergeFieldsWith`-RULE-OUT precedents:
  - **The five sites return structurally DIFFERENT things from the same lookup, gated
    differently.** `resolveEmbedDefBody?` → `Option Value` (body alone, NO frame, NO isDefinition
    gate, PLUS a `.refId` arm AND a `.disj` default-arm arm the selector skeleton does not cover);
    `embeddingFieldIsDefinition` → `Bool` (the def-CLASS, not the body); `resolveSelectorDefBody?`
    → `(pkgFields, body)` gated on `isDefinition`; `followAliasDefBody?` → `(terminalFrame, body)`
    but RECURSES, building a fresh `nextEnv` per hop; `importDefClosureBody?` → one of THREE
    results (pkg+normalized / followed-terminal / raw-`.conj`) gated on BOTH `isDefinition` AND
    `bodyNeedsDefer`. A single shared resolver cannot express this fan-out without a
    parameter-per-difference signature — strictly looser and more error-prone than the functions
    it would merge (the `canonicalizeFields`-cannot-join precedent).
  - **🚨 Soundness: the FRAME each captures is load-bearing and IRREDUCIBLY different.**
    `resolveSelectorDefBody?` returns `pkgFields` (the selector's OWN package frame — for the
    def-of-def `.conj` descent); `followAliasDefBody?` returns the TERMINAL package frame AFTER
    following the alias chain (a deeper, different frame); `importDefClosureBody?` returns
    `pkgFields` in the direct arm but the FOLLOWED frame in the alias arm. A shared helper that
    picked one canonical frame would resolve in the WRONG frame at some site — exactly the
    `crosspkg_defofdef_wrongframe_witness` hazard (defs-local `_region:"US"` vs defaults-local
    `"EU"`; a use-site-frame splice mis-resolves to "EU"/bottom). Per the `mergeFieldsWith`
    ruling: when the soundness boundary is WHICH function (here: which frame each resolves in) the
    caller invokes, consolidation is FORBIDDEN regardless of skeleton-share. The variation point
    is the FRAME + the RECURSION (`followAliasDefBody?`/`conjBodyHasDeferringArm` recurse building
    fresh frame-envs) — the DRY-1 / `mergeFieldsWith` trap, NOT the `embedChainAny` shape (where
    the variation was a PURE non-recursive `Value → Bool` leaf the combinator owned).
  - **The only frame-SAFE share is a narrow selector-head helper — and it is too thin + it
    FRAGMENTS.** A `resolveSelectorField? : Env → BindingId → String → Option (List Field × Field)`
    returning the raw `(pkgFields, defField)` lookup IS frame-neutral (it returns the lookup, the
    consumer still picks the frame), so it would not endanger the boundary. But it deduplicates
    ONLY the `.selector (.refId id) label` arm prefix (~7 lines) at 4 sites, while leaving each
    function's sibling `.refId` arm (and `resolveEmbedDefBody?`'s `.disj` arm) hand-written — so
    each function becomes "call helper for the selector arm, hand-write the refId arm," which is
    LESS readable, not more. This is the FOUR-classifiers verdict exactly: the shared prefix is
    too thin to name, and the per-site variation (return type, frame use, gating, recursion, the
    sibling arms) IS the point. KEEP SEPARATE. Do not re-file as a DRY win.
- **inject-family DRY (`injectEmbedSiblingNarrowings` Bug2-14 vs `injectLetLocalNarrowings`
  Bug2-4) — RULED OUT: keep SEPARATE. The DRY-1 / `mergeFieldsWith` trap (variation IS the
  recursion + a soundness-load-bearing frame distinction), NOT the `embedChainAny` shape
  (Phase-B 2026-06-23, headline adjudication).** Both walk a `fuel`/`seen`/`narrowings` value
  with the same `rewriteFields` map (meet the host narrowing into a read-and-declared
  same-label slot, gated on a read-labels fn) — a candidate shared inject combinator. Three
  variation points, decomposed against the `embedChainAny`-SHARE vs DRY-1-RULE-OUT precedents:
  - **read-labels leaf (the ONLY `embedChainAny`-safe part):** `embedComprehensionReadLabels`
    vs `letPromotedReadLabels` — pure, non-recursive. If this were the only difference, SHARE
    would be right (the AD4-1 / `embedChainAny` shape). It is not.
  - **the embed recursion:** `injectEmbedSiblingNarrowings` adds a `rewriteEmbeds` block
    recursing through the embeddings list (`cs`, the `.structComp` second field); the let
    walker has NO such block. The combinator would need a "recurse-into-embeds?" flag that
    only one instantiation sets — a parameter-per-difference signature, the
    `canonicalizeFields`-cannot-join precedent.
  - **🚨 THE DECISIVE SOUNDNESS ASYMMETRY — the nested-`let` recursion DISPATCHES TO A
    DIFFERENT WALKER by design.** At a `.letBinding` field, `injectLetLocalNarrowings` recurses
    into ITSELF (`Eval.lean:1839`), but `injectEmbedSiblingNarrowings` calls
    `injectLetLocalNarrowings` (`:1927`) — NOT itself. This is load-bearing: a `let` nested
    inside an embed must be narrowed by **let-local rules** (gated on `letPromotedReadLabels`),
    not embed-sibling rules. A shared combinator parameterized only on the read-labels leaf
    would route the nested-`let` recursion through the SAME leaf — changing Bug2-14's
    let-binding gating from `letPromotedReadLabels` to `embedComprehensionReadLabels`, a
    SOUNDNESS change to the exact splice that landed the argocd milestone (the `_patch`
    let-local disjunction-arm narrowing). The variation point IS the recursion (which walker
    each sub-shape dispatches to) PLUS the frame/gating distinction (embed-frame vs let-frame)
    — exactly the DRY-1 / `mergeFieldsWith` trap (when the soundness boundary is WHICH function
    the recursion invokes, consolidation is FORBIDDEN regardless of skeleton-share), NOT the
    `embedChainAny` shape (a pure non-recursive `Value → Bool/List String` leaf the combinator
    owns while the fixed recursion stays lexically in the combinator). The two functions are
    already MUTUALLY COMPOSED (embed→let), not merely parallel — the asymmetry is structural,
    not incidental. **KEEP SEPARATE.** Per the soundness constraint: even where the skeleton
    shares, a combinator that risks mis-injecting (wrong labels / wrong frame into the
    milestone splice) stays separate. Do not re-file as a DRY win unless a future inject
    walker over the SAME frame/gating with a pure non-recursive leaf lands.
- **`mergeFieldsWith` consolidation (`mergeFieldListWith` / `canonicalizeFields` /
  `mergeConjFields` skeleton-share) — RULED OUT: keep SEPARATE. The skeleton-share is real
  but the seam where it matters (`mergeFieldListWith` ↔ `mergeConjFields`) is ALREADY shared
  via `mergeFieldIntoWith`; `canonicalizeFields` cannot join under a `Value→Value→Value`
  combiner AND must not, on soundness-boundary grounds (Phase-B 2026-06-23, the headline
  adjudication).** Decomposed:
  - **Two of the three already share their match-helper.** `mergeFieldListWith meetValue`
    (Lattice:689) and `mergeConjFields` (Eval:631) both `foldl` over the SAME per-label
    helper `mergeFieldIntoWith` (Lattice:666), differing only in the `meetValue` arg
    (`meet` vs `joinUnevaluated`) and the seed (`[]` vs `accumulated`). The Phase-A-proposed
    "parameterize the skeleton" is, for this pair, already DONE — `mergeFieldIntoWith` IS
    the parameterized skeleton. `mergeConjFields` is a 5-line `foldl` wrapper that picks the
    seed + fixes the combiner; collapsing it into a direct `mergeFieldListWith
    joinUnevaluated` call buys nothing (the seed differs, and the named wrapper carries the
    load-bearing conj-of-EMBEDS doc-comment) and is not worth touching.
  - **`canonicalizeFields` cannot join under the proposed signature.** Its per-label helper
    `mergeUnevaluatedFieldInto` (Eval:401) is NOT a `Value→Value→Value` combiner: it
    dispatches on the MERGED field-class (`fieldClass.isDefinition` →
    `mergeDefinitionDecls` close-once-union, else `joinUnevaluated`), a decision the plain
    combiner signature cannot express. It also DELIBERATELY omits the bottom-rewrite that
    `mergeFieldValueWith` does (`isBottom` → `.fieldConflict`) — an unevaluated decl is not
    yet a meet, so it carries no conflict marker. Forcing it under a shared `mergeFieldsWith`
    would mean threading the field-class into the combiner type — a strictly looser, more
    error-prone signature than the two it would merge. This is the four-classifiers / DRY-1
    precedent: the shared part (the `foldl … else-append` shell) is too thin to name; the
    per-label DECISION is the point, and it differs irreducibly.
  - **🚨 Soundness-boundary: consolidation is FORBIDDEN regardless of skeleton, because the
    within-operand-vs-cross-operand (union-vs-meet) distinction lives in WHICH FUNCTION the
    caller invokes, and that is the whole safety.** `canonicalizeFields` (within ONE operand
    → close-once-UNION via `mergeDefinitionDecls`) and `mergeConjFields` (CROSS-operand →
    `.conj`-MEET) are deliberately DIFFERENT named functions so a call site picks the
    semantics by name — `mergeConjOperands` canonicalizes each operand's OWN fields, then
    `mergeConjFields`-merges ACROSS operands; the soundness boundary IS that ordering of two
    differently-named calls. A merged `mergeFieldsWith combiner` would put union-vs-meet
    into a COMBINER ARGUMENT — making it one wrong argument to pass the union combiner on a
    cross-operand path, which re-opens closed patterns (the cert-manager trap, the exact
    Bug2-8 hazard). The distinct names make the union combiner UNREACHABLE on the
    cross-operand path by construction. Per the prompt's own constraint: "if consolidation
    would blur or endanger that boundary, that's a reason to KEEP SEPARATE even if the
    skeleton is shared." It would, so they stay separate. **Do not re-file as a DRY win.**
- **`embedChainAny` (embed-chain walker share) — RULED: SHARE, applied inline `0619097`
  (2026-06-23). The AD4-1-safe case, NOT the DRY-1 trap.** `bodyNeedsDefer` and
  `embedBodyEmbedsDisjDeep` were byte-isomorphic except the leaf predicate
  (`defBodyHasSiblingSelfRef` vs `embedBodyEmbedsDisj`). Factored the shared fuel-bounded
  chain-walk into `embedChainAny (leaf : Value → Bool) (env) (fuel) (body)`; both became
  one-line instantiations. **Why this is NOT DRY-1:** DRY-1 failed because its variation point
  WAS the recursion (routing the nested-let recursion through a callback hid the `fuel+1`
  pattern, breaking structural-recursion inference). Here the variation point is a PURE
  NON-RECURSIVE `Value → Bool` leaf the combinator owns, and the recursion (the fixed
  chain-walk) stays lexically in the combinator — exactly AD4-1 / `expandClauseChain`'s shape
  (`onExhausted` is "pure and non-recursive, so the fuel/clause recursion stays lexically
  visible to `termination_by`" — that comment IS the precedent). Neither leaf recurses into the
  walk, so `termination_by fuel` infers unchanged. Build clean (native_decide pins green),
  fixtures zero-drift, shellcheck clean. Do NOT re-litigate as a DRY-1-style false share — the
  distinction (leaf-varies vs recursion-varies) is the whole ruling.
- **CARRIER share/no-share (`.embeddedScalar` vs `.embeddedList`) — RULED: keep DISTINCT
  constructors; do NOT merge into an `embeddedCarrier`; share ONLY the decl-selection seam
  (CARRIER-DECL-SELECT, filed). Do NOT share the meet seam (Phase-B 2026-06-22, the
  headline adjudication).** The scalar-embed slice's parallel-ctor design is the RIGHT call.
  Basis, decomposed into the three separable seams the prompt names:
  - **Constructors — keep distinct (no merge).** A scalar is not a list: it never indexes
    and never iterates (the `Value.lean` doc-comment already states this). The divergence is
    structural and load-bearing at the OUTPUT/ITERATION sites, where a merge would
    re-introduce illegal states: `Manifest` (`embeddedScalar` → `manifestWithFuel scalar`,
    NO list-wrap / NO item recursion; `embeddedList` → `.ok (.list items)` + recurse items),
    `Format` (scalar renders the bare value in `{…}`; list renders a `[…]` sub-list with
    tail handling), `comprehensionPairs` (`embeddedList` → `listPairsFrom`; scalar →
    non-iterable via catch-all), `selectEvaluatedListIndex` (list-only), `classifyGuard`
    /`classifyDynLabel`/`classifyArithOperand` (scalar RECURSES onto its inner scalar; list
    → `.nonBool .list`/`.nonString .list`/`.concreteNonArith .list`). A merged
    `embeddedCarrier (payload : Value) (decls)` would force every one of these sites to
    re-discriminate scalar-vs-list on `payload` at RUNTIME — exactly the illegal-state
    (`index a scalar`, `iterate a scalar`) that the two-ctor split makes UNREPRESENTABLE by
    construction. This is the four-classifiers / walker-dedup precedent applied: the shared
    part (carry `decls`) is too thin to name; the divergence IS the point. **Do not
    re-litigate the merge.**
  - **Meet seam — do NOT share, despite the shared bug.** Phase-A's evidence (both carriers
    have the SAME CARRIER-STRUCT-MEET bug + SAME fix) is real but does NOT imply a shared
    meet helper. The two meet arm-BLOCKS (`Lattice.lean:1244-1278` list, `:1285-1316`
    scalar) are structurally isomorphic at the SKELETON (partner-check → payload-meet+decl-
    merge → re-wrap; else struct-sub-case; else `meetCore`) but the PAYLOAD-MEET step is
    irreducibly different — list uses `asListPair`+`meetListPairWith` (prefix/tail
    alignment), scalar uses `scalarCarrierPartner?`+a bare `meetWithFuel` on the scalar. A
    shared higher-order seam parameterized over (partner-extractor, payload-meet, re-wrap)
    would be a 3-callback combinator wrapping ~12 lines of skeleton — the lambda-hides-`fuel
    +1` trap that broke DRY-1 (the payload-meet callback recurses through `meetWithFuel
    fuel`, which Lean's structural-recursion inference cannot see through a passed lambda).
    The skeleton is cheap to keep parallel; the seam is expensive to abstract. **CARRIER-
    STRUCT-MEET writes the fix TWICE (4 sites: the `.struct fields _ none [] _` sub-case at
    `:1257`/`:1272`/`:1295`/`:1310`), by hand, identically — that is the correct cost.** The
    fix is a deletion (drop the `else <merge decls>`, route to `meetCore`→bottom), not new
    logic, so writing it 4× is mechanical, not a maintenance hazard. CARRIER-STRUCT-MEET's
    diagnosis already says "apply uniformly to both carriers" — it composes with this ruling
    as-written; it does NOT need a shared meet seam to land.
  - **Decl-selection seam — DO share (CARRIER-DECL-SELECT, filed above).** This is the ONE
    seam where the carriers genuinely AGREE (both select decls identically, and identically
    to plain `.struct`), so a `selectFromDecls` helper is real dedup, not false-sharing.
    Ranked BELOW CARRIER-STRUCT-MEET (lands after, to avoid touching the same arms twice).
- **`Eval.lean` core mutual block — NEVER split (structural map ruling, Phase-B 2026-06-22;
  the carve-trigger above governs the def-deferral tier).** Structural map: 4 `mutual` blocks
  (`foldValueWithDepth` ~80
  lines; `remapConjRefs` ~147; `hasSelfRefAtDepth` ~110; **the core evaluator
  `evalValueWithFuel`…`expandListClausesWithFuel`, ~1140 lines / 15 mutually-recursive
  defs**) — the core block is UNSPLITTABLE: its `termination_by (fuel, tag, length)` tuple
  ordering (tags 0–6) would have to be proven across a module boundary, fragile and
  unmaintainable. The only semantically-coherent carve candidate is the **def-deferral tier**
  (`resolveEmbedDefBody?`/`bodyNeedsDefer`/`followAliasDefBody?`/`importDefClosureBody?`
  /`refDefClosureBody?`/… ~228 lines, `Eval.lean:1904–2131`): one-directional call graph
  (→ force/eval, no back-edge), but too tightly coupled to its `.refId`/`.selector`/`.conj`
  call sites to gain from isolation now. RULING: leave Eval.lean cohesive; IF it crosses
  ~4500, the def-deferral tier is the named first carve (`Eval.DefDeferral`, importing
  `hasSelfRefAtDepth`/`defBodyHasSiblingSelfRef`/core types). The classifier cluster
  (`classifyGuard`/`classifyDynLabel` ~124) and embedding-splice complex (~191) are also
  carveable but lower-value (too small / too coupled). Never split the evaluator mutual block
  at any size.
- **Escape-helper cross-module "duplication" (`escapeJsonChar` Json.lean vs
  `escapeCueStringChar` Format.lean) — RULED NOT A FINDING (Phase-B 2026-06-22).** The two
  share only 5 trivial literal arms (`"`/`\`/`\n`/`\r`/`\t`); they DIVERGE in the
  substance — JSON does control-char escaping (`\b`/`\f`/`\uXXXX`), CUE passes through
  verbatim. Collapsing the 5 shared arms behind a callback for the divergent tail is the
  "stuff they all do" false-sharing the four-classifiers + DRY-1 rulings already reject:
  the shared part is too thin to name, the divergence IS the point. Keep separate; do not
  re-file.
- **AD2-1 (disjunction-normalizer lone-arm rule) — RESOLVED (2026-06-21, UNIFIED).** The
  prior "USER-GATED" framing was over-caution about renaming named pins; the real question
  was autonomous (is the lone-default marker load-bearing?) and is answered NO. Proof: a
  lone default `*v` (direct or residual from a collapsed larger disjunction) has no other
  arm, so the mark is VACUOUS — value-identical to bare `v` in EVERY onward meet. Mechanism:
  `combineMark` is AND and `withDefaultConvention` only synthesizes a default for an
  all-regular operand, so a vacuous lone default never beats a real default nor manufactures
  one (the sharpest witness: `*1` (lone, vacuous) `& (*2|1)` → `1`, NOT `2` — identical to
  bare `1 & (*2|1)`). Adversarially cross-checked vs `cue` v0.16.1 (default-containing /
  default-absent / marked / conflict-marked / nested onward meets — all `export`
  byte-identical; cue's *display* also collapses the lone `*v` → `v`, so the fix moves Kue
  TOWARD cue). FIX: `normalizeDisj`'s lone-arm collapse is now mark-agnostic
  (`[(_, v)] => v`), matching `normalizeEvaluatedDisj`'s lone-arm rule — the two normalizers
  now agree on every lone-arm case (the eval path keeps its `joinValues` all-regular branch,
  a genuinely distinct subsumption op, so it is NOT folded wholesale — only the divergent
  lone-arm rule is unified). Named pins RENAMED to assert the corrected behavior
  (`meet_disjunction_collapses_vacuous_lone_default`,
  `lattice_meet_disjunction_collapses_vacuous_lone_default`) + adversarial non-load-bearing
  witnesses added (`lattice_lone_default_vacuous_*`, `lattice_multi_arm_default_marker_preserved`).
  `TwoPassTests.embed_disj_live_default_kept` expected display updated (lone-default residual
  `*{…}` → `{…}`, matching cue). SC-3 / `cue-spec-gaps.md` scope narrowed: the "keep marked"
  display contract now applies ONLY to MULTI-arm defaults (where the mark IS load-bearing —
  it selects among live arms a later meet can pick). No fixture display changed (none
  currently render a lone-default residual). Fixtures byte-identical; cert hot-path
  unchanged.
- **DRY-1 (let-walker dedup) — RULED OUT (attempted under A-EN3, reverted; no behavior
  shipped).** The three let-walkers (`closeDefFrameReadIndices` `List Nat` worklist,
  `letPromotedReadLabels` catamorphism, `injectLetLocalNarrowings` endo-rewrite) genuinely
  do NOT share a combinator — different carriers/visited-sets/follow-mechanisms,
  collect-vs-rewrite, and routing the nested-let recursion through a callback breaks
  Lean's structural-recursion inference (the lambda-hides-`fuel+1` trap). Contrast AD4-1's
  success: its variation point (`onExhausted`) was a PURE non-recursive leaf the
  combinator could own; DRY-1's variation point IS the recursion. **Do not re-file**
  unless a future catamorphic 4th walker over the same carrier lands.
- **BI-EFF (effectful-builtin seam) — TRIGGERED at the 2nd effectful builtin; full
  registry REJECTED.** `list.Sort` /`SortStable` are the only effectful builtins
  (comparator needs `EvalM`), one shared inline `runSort` case in `Eval` 's `.builtinCall`
  arm — the right layer, below the abstraction threshold for one case. Trigger: when the
  SECOND effectful builtin lands (`list.IsSorted` or a `matchN` /`matchIf` validator),
  extract a named `evalEffectfulBuiltin?` seam AS THAT SLICE'S FIRST STEP. A
  name→`EvalM`-closure registry is rejected (less traceable than an exhaustive `match`;
  population ~3-4). A forward-pointing comment is at the site.
- **F-CASE-ARCH (committed generated table + oracle-as-data-source) — RULED; both halves
  discharged.** (a) the 49KB generated `Kue/CaseTable.lean` STAYS committed (reproducible,
  reviewable, offline build, no build-time `cue` dep; `DO NOT EDIT` header + generator
  provenance present). (b) the oracle-as-data-source convention is an ADR
  ([`../decisions/2026-06-20-oracle-as-data-source.md`](../decisions/2026-06-20-oracle-as-data-source.md)):
  oracle = sound DATA SOURCE for an externally-standardized `cue` -faithful domain (verify
  vs the EXTERNAL standard, record provenance), NEVER a correctness GATE for CUE
  semantics.
- **FOUR-parallel-classifiers DRY
  (`classifyArithOperand`/`classifyGuard`/`classifyDefinedness`/ `classifyDynLabel`) —
  RE-RULED at four: keep the four verdict functions SEPARATE; extract only the shared
  default-collapse PRE-STEP (`collapseDefaultDisjunction`, DONE inline); a shared
  concreteness partition is REJECTED.** They disagree on the partition
  (`.prim`/`.struct`/`.disj`/`.structComp` land differently per classifier), so a shared
  helper would special-case exactly the disagreeing ctors, leaving only the inert abstract
  tail = "the stuff they all do" = not a name. Sharing would raise coupling + lower the
  new-ctor-forces-a-decision guarantee. Do not re-raise at five.
- **AD3-1 / Regex extraction / B5 regex bullet — DROPPED (stale).** `Kue/Regex.lean`
  already exists as a verified TRUE LEAF (no top-level `import`); the RX-1a/b NFA rebuild
  superseded the "extract the backtracking engine" framing. Nothing to do.
- **AD3-4 (bottom-payload newtype) — RULED OUT (over-engineering).** `GuardVerdict.bottom`
  / `ClauseExpansion.bottom` / `ListClauseExpansion.bottom` carry an unconstrained `Value`
  where only a bottom is valid, but the invariant is already enforced BY CONSTRUCTION
  (every construction site can physically only pass a bottom). A `BottomValue` newtype
  would ripple through every `.bottom` match site for safety already bought.
- **`Order.lean` (subsumption) — DELIBERATE test-only oracle**, imported only by `Tests/*`,
  NOT dead code and NOT duplicated (`meet`/join and `subsumes` /partial-order are
  orthogonal). Recorded so a future audit does not re-flag it as an orphan.

## Pointers (history + reference for anything dropped)

- **Completed-slice history + verification record:**
  [`../reference/implementation-log.md`](../reference/implementation-log.md)
  (chronological, one entry per commit) and `git log`. Every audit batch and design spike
  is recorded there — this plan holds only the live roadmap.
- **Spec-conformance fix backlog (authoritative):**
  [`spec-conformance-audit.md`](spec-conformance-audit.md) § Consolidated fix backlog.
- **CUE-divergence record:**
  [`../reference/cue-divergences.md`](../reference/cue-divergences.md).
- **CUE spec-gap record:**
  [`../reference/cue-spec-gaps.md`](../reference/cue-spec-gaps.md).
- **Decisions:** [`../decisions/`](../decisions/) (compatibility target,
  correctness-over-perf, Value-model fork resolution).
- **Slice loop + audit cadence:** [`../guides/slice-loop.md`](../guides/slice-loop.md).
- **Performance guide:** [`../guides/kue-performance.md`](../guides/kue-performance.md).
- **Status page (human-facing, served):** [`../../www/index.html`](../../www/index.html) —
  single human-scannable status page, OUTSIDE the agent design-record; refreshed on
  plan-hygiene passes.
- **CUE semantics reference:** [`../reference/cue-language-guide.md`](../reference/cue-language-guide.md);
  [`architecture.md`](architecture.md) + [`compat-assumptions.md`](compat-assumptions.md).
- **Latest session state / next step:** the most recent breadcrumb in
  [`../notes/`](../notes/).
