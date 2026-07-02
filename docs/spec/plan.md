# Kue Plan

Status: accepted — living roadmap.

The live implementation roadmap. Kept small, current, and actionable — one focused slice
at a time. The full record of completed slices lives in
[`../reference/implementation-log.md`](../reference/implementation-log.md) (chronological,
one entry per commit) and `git log`; this file holds only where we are and what's next. A
periodic plan-hygiene pass distills it back to the live roadmap (history → log + git); see
[`../guides/slice-loop.md`](../guides/slice-loop.md). Last distilled 2026-07-02.

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
  detail). Diagnosed to `Eval.lean:2209-2247` (`embedBodyEmbedsDisj`/`spliceOperandForEmbed`);
  seed repro at repo-root `repro-l5.cue`. NOT yet a self-contained wild fixture — needs dedicated
  bisection from the real app graph (module-free reductions flip polarity, as in layer 3).
  **Standing ruling (2026-07-02):** capturing the L5 wild fixture/repro is PRE-AUTHORIZED —
  it is safe and valuable regardless of the campaign outcome (the wild-fixture protocol means
  a captured bug stays guarded). The fix-grind BEYOND capture awaits chakrit's campaign
  decision: grind L5+ (attended is safer for closedness-adjacent work), reprioritize to
  B3d-6b/other, or accept the current state.

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
  `"location:identifier"` (F-3, `Import.packageName`). Registry/OCI fetch-on-missing
  (B3d, live-proven incl. bearer-token auth against `ghcr.io`). IO confined to
  `Kue/Module.lean` + `Kue/OciFetch.lean`; `Eval` /`Resolve` stay pure.
- **CLI.** `kue eval`, `kue export [--out yaml|json] [file|dir]` (stdin or arg), `kue
  version`, clean missing-file diagnostics + exit codes.

**Real-app status** (prod9 infra, read-only oracle) — drop-in status was demonstrated on
the {argocd, cert-manager} 2-app sample as of 2026-06-23; the broader corpus (lem, n8n,
x9, typesense) is the open Current front above:
- **cert-manager: content-identical drop-in, ~11.7s — the ONLY live canary.** Exports
  correctly at production fuel, byte-identical to `cue` modulo field-order #3 (the item-7
  cache-hash digest collapsed the ~119s O(N²) wall; the Bug2-x close-once/frame-id chain +
  perf #7 brought it to ~11.7s).
- **argocd: content-identical drop-in, ~50.3s (2026-06-23) — HISTORICAL.** Full
  `apps/argocd.cue` exported CONTENT-IDENTICAL to `cue` (jq -S diff = 0, sorted-key,
  modulo field-order #3). The app has since been REMOVED from the infra checkout, so the claim is
  not re-verifiable; it stands as the record of the Bug2-5..2-14c chain's outcome.

The argocd milestone closed a 10-fix narrowing/close-once chain (**Bug2-5 → Bug2-14c**,
2026-06-22..23): definition multi-declaration close-once across reference / embed /
cross-package boundaries, use-site narrowing delivery to deferred def interiors,
unset-optional selection, and the `#Mixin` structural-disjunction let-local narrowing
(Bug2-14b/c). The full blow-by-blow is HISTORY — in `implementation-log.md`,
`spec-conformance-audit.md`, and `git log`. Durable rulings that survived the chain are in
Resolved/ruled-out below.

## Live Backlog (open work, ranked)

Correctness gates real-app adoption; cleanups are parallel-safe filler. Two backlog
owners: the **spec-conformance fixes** are owned by
[`spec-conformance-audit.md`](spec-conformance-audit.md) § Genuinely-open ranked backlog
(the authoritative ranked list — do NOT duplicate it here); the **plan-only roadmap**
below owns the non-spec-conformance work.

> Partially RETRACTED 2026-06-28 — the milestone below held only on the {argocd,
> cert-manager} 2-app sample; a root-A soundness over-accept was found after; see
> § Current front (L5 open).

**🎯 MILESTONE — the spec-conformance backlog is EMPTY (2026-06-23).** Every correctness
item is RESOLVED; the genuinely-open set is now perf #7 (a perf lever, WON'T-FIX) + SC-3 (a
display-only spec-gap) + the item-6 LOW tail — no soundness-bearing work remains. Both prod9
real apps (argocd + cert-manager) are content-identical drop-ins (jq -S diff = 0). This closes
the spec-first re-audit started 2026-06-19; conformance is now demonstrated, not aspirational.

**Spec-conformance backlog — see `spec-conformance-audit.md` § Genuinely-open ranked
backlog (authoritative; do NOT duplicate the detail here).** Everything
spec-conformance-HIGH is DONE (the closedness family incl. SC-1b/1e + EMBED-CLOSE-1, the
MEET-RESID-1/A#6 family, the dyn-field family, D-area, regex, BI-1/BI-2, E#4, F-1/2/3, the
4 ratifications, SC-4, Bug2-12 MUTUAL, EvalOps). SC-3 is a recorded spec-gap only
(multi-arm-default display divergence). **NESTED-DISJ-MARK** (nested-disjunction
outer-default inheritance when the inner default dies, tier-2) is a **DESIGNED-DEFERRAL
2026-06-23** — the lone open VALUE divergence — adjudicated to a spec-verified two-tier
rule but deferred (the fix needs a 3rd `Mark` state or a non-flattening nested-disj
invariant; both LARGE + delicate, STOP rather than risk default-selection). Full record:
`spec-conformance-audit.md` § Genuinely-open #2 + `cue-spec-gaps.md` NESTED-DISJ-MARK
row. The Bug2-5..2-14c chain, AD2-1, DRY-1, and CARRIER-STRUCT-MEET are RESOLVED —
durable rulings in Resolved/ruled-out below; the blow-by-blow in `implementation-log.md`
+ `spec-conformance-audit.md` + git.

**perf #7 — frame-sharing across env-DEPENDENT evals: WON'T-FIX (2026-06-23,
measurement-driven REJECTION).** A zero-risk content-addressed shadow of `satCache`
measured the share ceiling before touching the soundness core: cert-manager 144/317,788
= 0.045%, argocd 288/486,773 = 0.059%. The ~175× re-eval is real but NOT
content-redundant — the same shape is reached under genuinely-different observable
bindings, so collapsing them is a FALSE share (wrong value). No sound frame-sharing can
reclaim it; the residual wall is the irreducible cost of distinct content, addressable
only by lowering per-eval cost or eval count (the user-controllable flatten/shorten
lever). Full data + rejection argument: `kue-performance.md` + implementation-log
(perf #7 frame-sharing slice).

### Fix-slices from the 2026-07-02 design-record audit (ranked)

- **(a) TEST-HEALTH retrofit + machine enforcement — DONE (2026-07-02).** All 33
  hand-authored `Kue/Tests/*.lean` modules converted to `--` line-comment section headers
  (zero block comments remain; `FixturePorts.lean` is generated data, exempt), per-section
  end-of-file `#check` tripwires added to every theorem-bearing module (anchored to each
  `/-!`-delimited section's last theorem; anonymous-`example`-only modules carry none, as
  no name can anchor `#check`), and `scripts/check-test-health.sh` added enforcing all
  three (no `^[[:space:]]*/-` block comments, tripwire presence where named theorems exist,
  ≤1800-line cap). Wired into the verify sequence (CLAUDE.md, slice-loop, lean4-guide,
  RELEASE, README). Completes the TEST-HEALTH CONVENTION (item 3 below) with a script gate
  instead of convention-by-memory. Detail in the implementation-log.
- **(b) Enumerate value-producing `| _ =>` catch-alls — DONE (2026-07-02).** Scope audit:
  of the raw counts (Eval ~85, Lattice 14, Builtin 13), only **13 sites** were in-scope
  (match on `Value` AND produce a `Value`) — all in `Eval.lean`
  (`selectFromConcrete`/`selectEvaluatedField`/`selectEvaluatedIndex` + the list/field/tail
  index dispatch, `withDeferredComprehensions`, the two `injectLet/Embed…Narrowings`
  rewrites, and three arms of the `meetEmbeddingsWithFuel`/`forceClosureWithConjunct` fold).
  Every Lattice/Builtin catch-all was OUT (scrutinee is `Prim`/`Kind`/`Option`/`List`, not
  `Value`, or RHS non-`Value`). Each in-scope `| _ =>` replaced by a `|`-joined explicit
  ctor enumeration (DRY: one shared RHS, but a new `Value` ctor now fails exhaustiveness).
  Pure refactor, zero behavior change (fixtures + `native_decide` green); the build proved
  no ctor was silently wrong under a catch-all. The `meetEmbeddingsWithFuel` scalar-embed
  fallback was hoisted to a `let scalarEmbeddingCollapse` thunk so the enumerated arms carry
  no recursive call — enumerating a recursive-call-bearing shared arm duplicates the
  `decreasing_by` obligation across every constructor and blows elaboration. Detail in the
  implementation-log.
- **(c) `Module.lean` `partial def` cleanup — ✅ DONE (2026-07-02).** All 4 `partial def`s
  now carry a one-line waiver: `findModuleRoot` (unbounded parent-chain walk),
  `loadPackage`/`parseAndBindFiles`/`collectBindings` (mutual recursion over the filesystem
  import graph, terminating via the `visited` cycle-guard). The two list self-recursions
  (`parseAndBindFiles` over files, `collectBindings` over imports) are rewritten as total
  structural `for` loops — no `partial` remains for a list. They keep `partial` only because
  they are in a genuine mutual-recursion cycle with `loadPackage` (a callback cannot break
  it), which is the honest, waived reason; the plan's "make them non-partial" was not
  achievable while `collectBindings` must call `loadPackage` and vice-versa. `acc`/`bindingAcc`
  accumulator params dropped (internal to the loops).
- **(d) Re-adjudicate `for` over a concrete non-iterable — ✅ DONE (2026-07-02).** Under the
  E#4 principle Kue's zero-iter WAS wrong (cue spec-correctly hard-errors). `classifyForSource`
  (`Eval.lean`, replacing `comprehensionPairs`) now: an iterable (list/struct/embedded-list)
  walks its pairs; a CONCRETE / decidably-non-iterable source (scalar `.prim`/carrier, abstract
  scalar `.kind`, `.stringRegex`, numeric `.boundConstraint`) is a type error
  (`.nonIterableSource`); a genuinely-unresolved source (`.top`, unresolved ref/disjunction —
  may still become a list/struct) DEFERS. Matches cue's verdict on all (error on `5`/`"s"`/
  `true`/`int`, hold on `_`). `cue-divergences.md` row REMOVED (Kue now conforms; recorded under
  "Resolved"). Pins: `ComprehensionTests` `listcomp_for_scalar_{int,string,bool}_is_type_error`,
  `listcomp_for_scalar_carrier_is_type_error`, `structcomp_for_scalar_int_is_type_error`,
  `listcomp_for_abstract_scalar_is_type_error`, `listcomp_for_top_source_defers`; fixtures
  `comprehensions/for_scalar_type_error`, `for_struct_scalar_type_error`, `for_top_source_defers`.
- **(e) Timeless-comment sweep — ✅ DONE (2026-07-02) for the audit-listed sites + all
  non-test source.** Rewrote the 7 listed sites (`Builtin.lean:941`, `Normalize.lean:126`,
  `Regex.lean:651`, `LatticeTests:708`, `RegexTests:6/183`, `Bug2xTests:545`) to describe
  current behavior. A grep sweep for `no longer|the old|previously|used to|before/after the
  fix` showed the audit list was NOT complete: also fixed all clear code-history narrations in
  non-test source — `Yaml.lean:34`, `Parse.lean:334`, `Normalize.lean:15`,
  `Eval.lean:977/1051/1354/3127/3864/3931/4070/4526`. Skipped value-state/purpose phrasings
  that are timeless ("no longer `.optional`" = meet result, "Used to <verb>" = purpose,
  Sha256 "no longer fit" = block-boundary math).
- **(e-followup) Timeless-comment sweep, test files [LOW, on-touch].** ~20 clear code-history
  comments remain in `Tests/`: `PresenceTests:316`, `TwoPassTests:12/62/78/157/224/596/708/763`,
  `ComprehensionTests:390`, `ModuleTests:38`, `YamlTests:55`, `ClosureTests:222`,
  `LatticeTests:546/683`, `EvalPerfTests:571/613`, `BuiltinTests:1049/1103`, `EvalTests:920/1205`,
  `FixturePorts:96/3823/3838`. Deferred from (e) to keep that slice scoped; convert on-touch or
  as a dedicated sweep.

### Fix-slices from the 2026-07-02 Phase A audit of the eval batch (`4b64502..HEAD`, ranked)

- **(PA-1) `classifyForSource` masks a BOTTOM `for` source as incomplete [HIGH, soundness].**
  `Eval.lean` `classifyForSource` enumerates `.bottom`/`.bottomWith` into the `.incomplete`
  arm with the (false) justification "Bottoms never reach here". The `.forIn` caller
  evaluates the source and matches `classifyForSource` with NO bottom short-circuit, so a
  source evaluating to bottom (`1 & 2`) reaches the classifier and is DEFERRED instead of
  propagated. Value-level divergence, not just a diagnostic: `out: [for x in (1 & 2) {x}] |
  [5]` → cue `[5]` (⊥ arm eliminated), kue "ambiguous value: multiple non-default disjuncts
  remain" (dead arm retained). Bare `out: [for x in (1 & 2) {x}]` → "incomplete value" where
  cue reports the conflict — same bottom-masked-as-incomplete family as the TL-1 and
  missing-field-selection fixes. **Fix:** give `ForSourceClass` a bottom-propagating verdict
  (a 4th case, or fold into the caller) and route `.bottom`/`.bottomWith` to it, mirroring
  `classifyGuard`'s `.bottom bot => pure (.bottom bot)` arm — the sibling classifier already
  does this correctly. **Red seed COMMITTED + quarantined:**
  `testdata/wild/for-bottom-source-masked-as-incomplete/` (`.known-red`); the fix greens it.
  Add `native_decide` pins for the bare + disjunction forms and remove the `.known-red`
  marker in the same slice.

### Plan-only roadmap (not in the spec-conformance backlog)

Sequence after the spec-conformance correctness work: bank cheap-ready cleanups, then the
perf frontier (#7 residual), then the deeper parity gap (#6).

**Numbered durable items (cross-reference IDs):**

1. **`truncate-primitive` (soundness hardening) — CLOSED.** Step 1 DONE (one
   `EvalState.truncate` choke point); Step 2 (`withFuel` combinator) RULED OUT — a lambda
   hides the `fuel=n+1` pattern and breaks `termination_by`. Residual routing-discipline
   documented at the primitive; detail in the implementation-log.

2. **EvalOps extraction → `Kue/EvalOps.lean` — DONE (2026-06-22).** Pure scalar algebra
   carved out of `Eval.lean` (−324 lines); import shape `EvalOps → {Builtin, Decimal,
   Regex}`, no back-edge; +18 pins. Detail in the implementation-log.

3. **Test/fixture-org pass (periodic) — splits DONE; fixture regroup DEFERRED.**
   `TwoPassTests` split at the contiguous Bug2-6..13 seam into `Bug2xTests` (`0deef2f`);
   `EvalTests` carved into `ComprehensionTests` + `SortTests` (`4b25cef`); pin-counts
   conserved, org-only. Detail in the implementation-log. **TEST-HEALTH CONVENTION
   (durable, applies to ALL new/touched `Kue/Tests/*.lean`):** section headers are `--`
   LINE comments, never `/-- -/`/`/-! -/` block comments (a line comment cannot swallow
   the next theorem); every test module carries an end-of-file `#check
   @<last-theorem-per-section>` tripwire. Recorded in
   `docs/reference/failure-modes.md`; machine enforcement LANDED via fix-slice (a) above
   (`scripts/check-test-health.sh`, repo-wide retrofit).
   **Remaining sub-item (DEFERRED, optional):** sub-grouping `testdata/cue/{definitions,
   comprehensions}` into nested subdirs — high-blast-radius (`FixturePorts.lean`'s
   `fileName` strings are the join key, ~77 fixtures); deferred per "DEFER rather than
   break discovery"; pick up as a dedicated careful slice or drop.

4. **Field-ordering parity #3 — RATIFIED CLOSED: Kue keeps source order; parity
   DECLINED.** Spec silent (structs unordered, output order implementation-defined), so
   Kue's declaration order is the principled choice, test-pinned. `cue`'s cross-conjunct
   order is an undocumented internal-graph artifact — chasing byte-parity would mean
   reverse-engineering it, rejected. Full re-derivation in `cue-spec-gaps.md` (RATIFIED
   row). Reopen only if a concrete fixture demands cue's exact bytes (none does).

5. **Per-eval-cost perf frontier — CLOSED (2026-06-23).** Hash digest DONE (119s → ~30s
   cert-manager); perf #7 safe wins landed; frame-sharing WON'T-FIX (see block above);
   the per-eval CONSTANT floor-characterized (cache/hash ~2-3% of per-eval cost; argocd
   ~52s ≈ ~486K necessary core evals × irreducible per-meet cost); multi-ref-cyclic
   flatten fan-out FIXED (visited-path bound, >40s → ~0.01s warm). Only remaining lever
   is user-controllable flatten/shorten. Full data: `kue-performance.md` + the
   implementation-log (perf #7, per-eval-constant, flatten-bound slices).

6. **Borderline / LOW (opportunistic; none block adoption).**

   Open:
   - **`module-file-scoped-imports`** (arch-sized) — Kue merges every sibling file's
     import bindings into one shared package frame; CUE scopes them per-file. Bites only
     the same-NAME-different-target case; real prod9 doesn't hit it. Bind each file's
     imports into a per-file scope frame.
   - **B2-A1 (latent, currently lossless)** — `applyEvaluatedStructN` (`Eval.lean:330`)
     routes the patterns-present case through a meet that DROPS `tail`. Lossless today
     (the only tail a parsed struct carries is bare `...` = `.top`, a no-op to
     drop+re-supply); breaks the day typed-ellipsis lands. Thread `tail` through the
     pattern arm + a round-trip pin; pairs with any typed-ellipsis slice.
   - **B2-A2 (test-gap fill)** — both B2.5 fixtures exercise patterns-LEFT × tail-RIGHT;
     the reverse and both-tails+patterns are pinned only by `native_decide`. Add
     `testdata/cue/definitions/{tail_pattern_unify,both_tails_pattern_unify}` pairs +
     `FixturePorts` entries (oracle: `{a:5,...} & {[string]:int}` → `{a:5}` open).
   - **A2-x (latent) — `importBinding` merge-asymmetry.** STAYS unobservable — the only
     collision that would exercise the asymmetric merge is the one A2-y rejects at LOAD.
     No work to do; recorded so it is not re-investigated.
   - **`scalar-embed` provenance follow-ups** — opportunistic pins (3-level flatten, disj
     ops beyond `+` /`&`, composed select-into-F1-default) when next touching
     Lattice/Eval.
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
     verify: `lake build` + the full 1843-pin regression + cert-manager jq-S=0
     (byte-identical is the bar — pure refactor, zero behavior change) + the wild fixtures
     stay green.** Do NOT do inline. Ranked: lead of the Borderline/LOW cleanups (it's the one
     active drift hazard in eval-core; the rest are latent).

   Done (ruling + pointer only; blow-by-blow in the implementation-log):
   - **`scalar-embed-with-decls`** — DONE 2026-06-22. `{#a:1, 5}` → `5` via a dedicated
     `.embeddedScalar` carrier; the no-decls pure-collapse path left untouched (the
     soundness boundary); new ctor handled at every match site, no catch-all swallow.
   - **TL-1** — DONE 2026-06-22. Closed `BuiltinFamily` enum + exhaustive dispatch; an
     unknown name with concrete args now bottoms instead of silently residualizing.
   - **TL-2** — DONE 2026-06-22. `BindingId {depth : Depth, index : FieldIndex}` newtypes
     make the depth/index transposition unrepresentable; `OfNat` keeps test literals.
   - **`import-eager-closedness`** — DONE 2026-06-22 via a single shared
     `selectedFieldValue` closing decision (option (b)); option (a) rejected (A2 trap).
   - **Parser strictness (`*(1|2)`, `__x`)** — DONE 2026-06-23; both spec-mandated
     rejections; 18 parse pins; 1 cue-divergence + 1 spec-gap recorded.
   - **`release-linux.sh` dirty-tree guard** — DONE 2026-06-23 (same clean-tree
     precondition as `release.sh`).
   - **Concurrent-release tap-clone race** — DONE 2026-06-23; shared `scripts/tap-push.sh`
     lock-free retry-on-reject loop (`flock` avoided — absent on macOS).
   - **DRY `selectEvaluatedField .disj`** — DONE 2026-06-23; shared `selectFromConcrete`;
     NOT a pure refactor — the scalar-default select arm now matches cue (`y: x.a | "fb"`
     resolves `"fb"`; was ambiguous, a kue bug fixed).
   - **Value-rewrite `other => other` catch-alls** — DONE 2026-06-23; all four sites
     enumerate ctors explicitly; exhaustiveness verified to bite on a dummy ctor.
   - **B3 (`comprehensionPairs` `.embeddedList`)** — DONE 2026-06-22 (rode along with
     `scalar-embed-with-decls`).
   - **A2-y (import-name redeclaration)** — DONE 2026-06-23; spec-mandated LOAD error
     (was a genuine soundness bug — wrong-value resolution); exemptions match cue.
   - **Aliased-builtin-call + aliased-stdlib-CONSTANT resolution** — RESOLVED 2026-06-23;
     one post-parse alias canonicalization pass (`canonicalizeBuiltinCalls`), scoped to
     builtin import paths so user imports are never rewritten; Phase-A audit HEALTHY.
   - **`resolveEmbeddedDisjDefault` narrowing check** — RESOLVED [fixed] 2026-06-23
     (CASE B, embed-disj-arm-closedness): per-arm re-close over (host ∪ arm) labels; the
     NESTED-DISJ-MARK latent it surfaced is the designed-deferral above.

7. **CLI / entry-UX (cue-aligned command surface).** **Entry-UX fix — DONE (2026-06-24):**
   bare `kue` prints help (was an interactive freeze); empty-stdin smoke demo + dead
   `Kue/Examples.lean` deleted; stdin eval is explicit (`kue eval`). Detail in the
   implementation-log. **NEW SCOPED OBJECTIVE (awaiting user direction — do NOT
   self-start):** the broader cue-aligned CLI command surface (`vet`/`fmt`/`def`, a `-`
   explicit-stdin marker, flag parity with `cue`); the next leader for it = the user's
   CLI-design direction. **Known DEFERRED:** `kue --version` reports `0.1.0-alpha`
   rather than the dated release tag — defensible as-is.

   **Module-fetch / registry direction — DECIDED (2026-06-25): full Lean 4, NOT a Go
   frankenstein.** The Go-shell + Lean-engine-via-cgo architecture was spiked to a working
   link but REJECTED by chakrit (leaky Lean↔Go seam vs correctness + human-traceability);
   the registry/OCI layer stays Lean-native. Spike kept as a feasibility record; do not
   re-spike. See `docs/decisions/2026-06-25-lean-engine-embedded-in-go-via-cgo.md`.

   **B3d (registry/OCI module fetch) — WIRED + LIVE-PROVEN; only B3d-6b remains.** See
   § B3d track below.

## B3d track — CLOSED (audit history distilled 2026-06-26)

The registry/OCI module-fetch track (decision: `docs/decisions/2026-06-25-registry-fetch-via-curl-subprocess.md`)
landed end-to-end. Modules: `Registry` (CUE_REGISTRY parse + module→OCI-ref + cache-path
authority), `Oci` (manifest parse + URL/curl-arg builders), `OciAuth` (bearer-token flow
parsing), `OciFetch` (the sole `IO.Process` curl edge + the three integrity gates),
`Sha256` (FIPS 180-4 + `h1:` dirhash), `Inflate` (RFC 1951 DEFLATE), `Zip` (PKWARE +
CRC-32), `Semver` (Go `x/mod/semver` port), `Mvs` (pure MVS solver), and `Module.lean`
wiring (`fetchAndCacheModule` + atomic cache-write). B3d-1...B3d-5 (+5a/5z), B3d-6a,
B3d-A1, and B3d-7 (OCI bearer-token auth — proven LIVE against real `ghcr.io` for
`prodigy9.co/defs@v0.3.19`, manifest + digest-verified zip blob) are DONE. Per-slice
detail: `implementation-log.md` (71+ B3d entries) + git.

Both 2026-06-26 audit rounds closed **HEALTHY**: module graph is a clean DAG (no cycles; IO
confined to `OciFetch`+`Module`; `Eval`/`Resolve`/`Value` import ZERO B3d module; the pure-island
-> thin-IO-edge seam holds); the three integrity gates (blob `sha256:` digest, zip CRC-32+size,
`cue.sum` `h1:`) are enforced and unbypassable on the production path; inflate is total
(fuel-bounded, malformed -> typed-error). Phase A found + FIXED inline two Violations (semver
empty-prerelease/build-segment validity; MVS `reachable` fuel silently truncating dense graphs ->
bound is now `(N+1)²`). Totality `#print axioms`-pinned (stdlib axioms only). `Kue/Bytes.lean`
extraction re-evaluated TWICE -> confirmed YAGNI (no cross-module hex/int-read consumer;
re-trigger only on a THIRD multi-byte-int reader). 🔒 Secret hygiene (B3d-7): a
credential/token lives only in curl argv + in-memory strings, never logged/persisted;
errors report outcomes, never the secret.

**`Mvs.solve` dead-code ruling:** ACCEPTABLE staged primitive, NOT orphan. It is pure, total,
fully `native_decide`-pinned (diamond/upgrade/downgrade/cycle/distinct-majors), and unwired only
because wiring it into the live resolver is a network/human-gated BEHAVIOR change (the requirement
graph it consumes must be fetched) -- filed as B3d-6b, not stranded. Reachable from `MvsTests`
today; the resolver edge lands with the rest of B3d-6b.

**Open B3d items (ranked):**
- **B3d-6b** (NETWORK-GATED, the single remaining substantive slice) — `cue mod get/tidy`
  + requirement-graph fetch + cue.sum WRITE. Five legs, all needing live registry egress
  or the command surface: (1) fetch each dep's `module.cue` `deps` block to BUILD the
  `RequirementGraph` (the curl edge is bearer-auth-capable via B3d-7, so private/authed
  registries work); (2) OCI `.../tags/list` for "latest"/major->concrete; (3) `cue mod
  get`/`cue mod tidy` command parse + dispatch; (4) wire `Mvs.solve` into the resolver
  (replace lenient per-hop resolution with one up-front MVS build-list) GATED ON a
  diamond-divergence fixture; (5) `cue.sum` WRITE via `Module.atomicWriteBinFile` (the
  B3d-3 dirhash + B3d-A1 atomic primitive both already exist).
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
- **`Kue/ModuleFetch.lean` carve** (architecture, conditional) -- `Module.lean` is NOT yet
  outgrowing its home; the fetch/cache cluster (~90 lines) is coherent. Trigger: if B3d-6b
  pushes that cluster past ~200 lines or adds a distinct command-dispatch responsibility, carve
  then (it would import `OciFetch`/`Zip`/`Sha256`/`Registry`, leaving `Module.lean` the read-path +
  loader). Filed as a trigger, not a now-slice.
- **`kue-performance.md` B3d note** (doc, LOW) -- inflate is O(output) fuel-bounded; fetch latency
  is curl/network-dominated, off the eval hot path; the new `native_decide` vectors are one-shot
  compile-time, not per-eval. Fold into a coming B3d slice.

## Resolved / ruled-out (recorded so they are not re-raised)

### Audit-round history (all HEALTHY; per-round detail in implementation-log.md + git)

Every two-phase audit round 2026-06-21..29 closed HEALTHY; each round's full write-up is
an implementation-log entry + its own commit. Rounds: `1bd93d8..fc5456d` +
`9afd54c`-baseline Phase-B (2026-06-25, B3d foundation — filed B3d-5a, ruled Bytes.lean
YAGNI); `890d453..2bd75eb` (A2-y); `e2d8868..4431597` (parser-strictness +
release-tooling + empty-cache-skip); `db8700f..HEAD` (nested-disj-mark deferral +
disj-select DRY); `735dc10..0459beb` (flatten-bound + SC-4); `32643f5..2bbdb05`
(Bug2-12 MUTUAL); `fccab69..6f77bfe` (Bug2-12 + missing-field-selection);
`50a0db3..14fb23e` (perf #7 safe wins); `20b8397..32ddfda` (catch-all refactor +
embed-disj-arm-closedness); `f40dd9c..4b24902` (B3d-7 + eval-L1/L2 — recorded in
§ Current front). The resilience/retrospective pass (once flagged OVERDUE) rode the
`890d453..2bd75eb` batch; its learnings live in `failure-modes.md` + `slice-loop.md`.

> Partially RETRACTED 2026-06-28 — the consolidated-complete state below held only on
> the {argocd, cert-manager} 2-app sample; a root-A soundness over-accept was found
> after; see § Current front (L5 open).

**🎯 CONSOLIDATED-COMPLETE STATE (2026-06-23).** The substantive backlog was EXHAUSTED on
two axes simultaneously: **(1) spec-conformance backlog EMPTY** — every correctness item
RESOLVED; argocd + cert-manager content-identical drop-ins (jq -S diff = 0). **(2)
per-eval perf frontier CLOSED** — floor-characterized; frame-sharing a false-share,
WON'T-FIX. Released `v0.1.0-alpha.20260623` (3 platforms, race-safe tooling). What
remained then was latent/cleanup only (item-6 tail + SC-3) — until the broader prod9
corpus opened the eval-conformance front.

### Durable whole-graph facts (a future audit re-verifies these)

The module graph is ACYCLIC + strictly layered (`Builtin → {Lattice, Regex, Decimal,
Base64, Json, Yaml, CaseTable}`, NO `Eval`/`EvalOps` edge; `EvalOps → {Builtin, Decimal,
Regex}` no back-edge; `Eval → {Builtin, Decimal, EvalOps, Lattice, Regex, Normalize}`;
`Lattice → {Value, Regex}`; `Runtime → Eval`; `Module → {Parse, Runtime, Registry,
OciFetch, Zip, Sha256}`; `OciFetch → {Oci, OciAuth, Base64, Sha256, Registry}`;
`Cli → Runtime`; `Normalize → Value`). Cleanliness sweeps clean (no
`sorry`/`panic!`/`unreachable!`/`.get!`-in-pure-code, no dead code, no stale markers;
`partial def`s are the `Parse.lean`/`Module.lean` carve-outs only — see audit fix-slice
(c); `Eval`+`Lattice` FULLY total). Test-health guarded by the TEST-HEALTH CONVENTION
(item 3) + the ~2000-line silent-failure watch.

### Durable rulings (one paragraph each; do not re-litigate)

- **Walker / normalizer dedup family — FULLY CLOSED.** The walkers were NEVER one problem
  — three distinct walker families + a separate normalizer pair, different
  mechanisms/result-types/recursion-domains/termination measures; folding them under one
  abstraction is a false "stuff they all do" extraction. AD4-1 + A-EN3 DONE; DRY-1 RULED
  OUT; AD2-1 RESOLVED (unified); `embedChainAny` SHARED (`0619097`). No open members.
- **CARRIER-DECL-SELECT (DRY, LOW) — DONE 2026-06-22.** `selectFromDecls` extracted;
  all six byte-identical Eval sites routed through it; `Runtime.lookupField?` is a
  DIFFERENT operation, deliberately NOT shared across the seam. Detail in the
  implementation-log.
- **`Eval.DefDeferral` carve — HELD, sharpened trigger.** The def-deferral tier
  (~600 lines) is the named first carve, but growth lands in the core-force `mutual`
  block, so carving now buys only indirect headroom. Trigger: carve when EITHER a
  def-deferral-tier slice pushes `Eval.lean` past ~4500, OR core-force growth crosses
  ~4400 with the tier intact. Standalone refactor slice, never inline.
- **`Eval.lean` core mutual block — NEVER split (Phase-B 2026-06-22).** The core
  evaluator `mutual` block (~1140 lines, 15 defs) is UNSPLITTABLE: its `termination_by
  (fuel, tag, length)` ordering would have to be proven across a module boundary. Leave
  `Eval.lean` cohesive; the def-deferral tier (above) is the only named carve.
- **`resolveDefField?` skeleton-share — RULED OUT (Phase-B 2026-06-23).** The ~6
  def-resolution functions return structurally different things from the same lookup,
  gated differently, and the FRAME each captures is load-bearing and irreducibly
  different (the `crosspkg_defofdef_wrongframe_witness` hazard). The only frame-safe
  share (a selector-head helper) is too thin to name and fragments each function. KEEP
  SEPARATE; do not re-file as a DRY win.
- **inject-family DRY (`injectEmbedSiblingNarrowings` vs `injectLetLocalNarrowings`) —
  RULED OUT (Phase-B 2026-06-23).** The nested-`let` recursion DISPATCHES TO A DIFFERENT
  WALKER by design (embed→let, gated on `letPromotedReadLabels`) — a combinator
  parameterized on the read-labels leaf would change the milestone splice's gating, a
  soundness change. The variation point IS the recursion + frame/gating. KEEP SEPARATE.
- **`mergeFieldsWith` consolidation — RULED OUT (Phase-B 2026-06-23).**
  `mergeFieldListWith` ↔ `mergeConjFields` already share `mergeFieldIntoWith`;
  `canonicalizeFields` cannot join under a `Value→Value→Value` combiner (it dispatches on
  merged field-class) and MUST not: the within-operand-union vs cross-operand-meet
  distinction lives in WHICH function the caller invokes — a combiner argument would make
  the union combiner reachable on the cross-operand path (the Bug2-8 hazard). KEEP
  SEPARATE.
- **close-each vs close-once (Bug2-12 flatten path vs Bug2-7 conj-fold path) — RULED:
  SHARED PRIMITIVE, DISTINCT SEAMS.** Both defects are fixed by the ONE close-once
  primitive `mergeDefinitionDecls`; the two call contexts (cycle-flatten vs conj-fold)
  are genuinely distinct seams and merging the functions is forbidden by the
  `mergeFieldsWith` ruling. The shared part is already a named, reused primitive — do
  not re-file as a DRY merge.
- **`embedChainAny` (embed-chain walker share) — RULED: SHARE, applied `0619097`.**
  `bodyNeedsDefer`/`embedBodyEmbedsDisjDeep` differ only in a PURE non-recursive leaf
  predicate the combinator owns; the recursion stays lexically in the combinator, so
  `termination_by fuel` infers unchanged — the AD4-1 shape, NOT the DRY-1 trap
  (leaf-varies vs recursion-varies is the whole ruling).
- **CARRIER share/no-share (`.embeddedScalar` vs `.embeddedList`) — RULED (Phase-B
  2026-06-22): keep DISTINCT constructors** (a merged carrier would force runtime
  scalar-vs-list re-discrimination at every output/iteration site — the illegal state the
  split makes unrepresentable); do NOT share the meet seam (3-callback combinator =
  lambda-hides-`fuel+1`; writing the CARRIER-STRUCT-MEET fix 4× by hand was the correct
  cost); DO share only the decl-selection seam (CARRIER-DECL-SELECT, done).
- **Escape-helper "duplication" (`escapeJsonChar` vs `escapeCueStringChar`) — NOT A
  FINDING (Phase-B 2026-06-22).** Five trivial shared arms; the substance diverges (JSON
  control-char escaping vs CUE verbatim). Keep separate; do not re-file.
- **AD2-1 (disjunction-normalizer lone-arm rule) — RESOLVED 2026-06-21, UNIFIED.** A
  lone default `*v` is VACUOUS (no other arm), value-identical to bare `v` in every
  onward meet; `normalizeDisj`'s lone-arm collapse is now mark-agnostic, agreeing with
  `normalizeEvaluatedDisj`. Adversarially cross-checked vs cue; SC-3's "keep marked"
  display contract narrowed to MULTI-arm defaults. Detail in the implementation-log.
- **DRY-1 (let-walker dedup) — RULED OUT (attempted, reverted).** The three let-walkers
  share no combinator — different carriers/visited-sets/follow-mechanisms, and routing
  the nested-let recursion through a callback breaks structural-recursion inference (the
  lambda-hides-`fuel+1` trap). Do not re-file unless a catamorphic 4th walker over the
  same carrier lands.
- **BI-EFF (effectful-builtin seam) — trigger standing.** `list.Sort`/`SortStable` are
  the only effectful builtins, one inline `runSort` case in `Eval`. Extract a named
  `evalEffectfulBuiltin?` seam AS THE FIRST STEP of the slice that lands the SECOND
  effectful builtin; a name→closure registry is rejected (less traceable than an
  exhaustive `match`).
- **F-CASE-ARCH — RULED; both halves discharged.** The generated `Kue/CaseTable.lean`
  STAYS committed (reproducible, reviewable, offline build); oracle-as-data-source is an
  ADR ([`../decisions/2026-06-20-oracle-as-data-source.md`](../decisions/2026-06-20-oracle-as-data-source.md)):
  oracle = sound DATA SOURCE for an externally-standardized domain, NEVER a correctness
  gate.
- **FOUR-parallel-classifiers DRY — RE-RULED at four: keep SEPARATE.** They disagree on
  the partition (`.prim`/`.struct`/`.disj`/`.structComp` land differently per
  classifier); only the shared default-collapse pre-step was extracted
  (`collapseDefaultDisjunction`). Do not re-raise at five.
- **AD3-1 / Regex extraction — DROPPED (stale).** `Kue/Regex.lean` is already a verified
  true leaf; the NFA rebuild superseded the framing.
- **AD3-4 (bottom-payload newtype) — RULED OUT (over-engineering).** The invariant is
  enforced by construction at every site; a `BottomValue` newtype would ripple for safety
  already bought.
- **`Order.lean` (subsumption) — DELIBERATE test-only oracle**, imported only by
  `Tests/*`; NOT dead code and NOT duplicated. Recorded so a future audit does not
  re-flag it.

## Pointers (history + reference for anything dropped)

- **Completed-slice history + verification record:**
  [`../reference/implementation-log.md`](../reference/implementation-log.md)
  (chronological, one entry per commit) and `git log`. Every audit batch and design spike
  is recorded there — this plan holds only the live roadmap.
- **Spec-conformance fix backlog (authoritative):**
  [`spec-conformance-audit.md`](spec-conformance-audit.md) § Genuinely-open ranked
  backlog.
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
