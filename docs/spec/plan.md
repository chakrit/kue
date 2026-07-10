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
[`implementation-log.md`](implementation-log.md) (chronological,
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
dyn-field family, D-area, regex, BI-1/BI-2, E#4, F-1/2/3, SC-4, Bug2-12 MUTUAL, EvalOps).
**NESTED-DISJ-MARK is CLOSED (2026-07-05): Kue was already SPEC-CORRECT; `cue` is the buggy
side.** The former "lone open VALUE divergence / DESIGNED-DEFERRAL 2026-06-23" was mis-adjudicated
— applying the spec's default-marking rule **M2** (`*⟨v, d⟩ => ⟨v, d⟩`: a mark on an
already-defaulted disjunct is ABSORBED, it does NOT re-broaden the inner default) + **U1**
(`d1 & v2` for the default under a narrow) mandates the AMBIGUOUS result Kue already produces;
`cue`'s resolved value comes from an M2-violating broadening (a `cue` bug). NO Kue code change; the
designed 3rd-`Mark`-state fix is WITHDRAWN (it would have imported `cue`'s bug). Reclassified from
`cue-spec-gaps.md` to `cue-divergences.md` (M2/U1 basis). With this, **there are ZERO open
VALUE-level divergences.** **SC-3** is a display-only spec-gap (multi-arm-default display
divergence; a 2026-07-04 AFK sweep of the whole disjunction/default area confirmed ZERO export
divergence and recorded the all-default `*1 | *2` display as an SC-3 sub-case — guards
`EvalTests` `disj_meet_*`). Full records: `spec-conformance-audit.md` + `cue-spec-gaps.md`.

**perf #7 frame-sharing across env-DEPENDENT evals — WON'T-FIX (2026-06-23,
measurement-driven).** A zero-risk content-addressed shadow measured the share ceiling:
cert-manager 0.045%, argocd 0.059%. The ~175× re-eval is real but NOT content-redundant (the
same shape is reached under genuinely-different observable bindings), so no sound frame-sharing
reclaims it — the residual wall is the irreducible cost of distinct content. Full data +
rejection argument: `kue-performance.md` + implementation-log.

### Ranked OPEN backlog

**STDLIB campaign (2026-07-10, from an alpha stdlib test-drive against `cue` v0.16.1).** Five
findings A–E, ranked — all LANDED (2026-07-10). A follow-on **STDLIB-F** (list-item separator
enforcement), surfaced by slice D's separator work, is queued below.

- **A — stdlib import ROUTING + error quality. ✅ LANDED (2026-07-10).** kue misrouted every
  non-whitelisted import (dot-free stdlib paths `strconv`, `struct`, `time` included) to the
  disk module loader, surfacing the misleading `no cue.mod/module.cue found` error. Fixed:
  `isStdlibImportPath` (`Kue/Value.lean`) classifies by first path element (dot-free ⇒ builtin
  layer, dotted-domain ⇒ external module); a recognized-but-unimplemented stdlib path now emits
  `unsupported builtin package "<path>": …`. External paths route to `resolveImportTarget`
  unchanged. Wild fixture `testdata/wild/stdlib-import-misrouted-to-disk-loader/`. Spec-gap +
  log recorded. Scope was ROUTING only — NOT the package function bodies (B/C).
- **B — `struct` builtin package (MEDIUM). ✅ LANDED (2026-07-10).** `struct.MinFields(n)` /
  `struct.MaxFields(n)` implemented as a `Value.fieldCountConstraint (bound : FieldCountBound)
  (limit : Int)` validator that participates in `meet`. Counting semantics (pinned vs cue v0.16.1):
  only REGULAR fields count — optional (`x?`), required (`x!`), hidden (`_x`), definition (`#x`),
  and `let` all excluded (`FieldClass.countsAsField`). Meet resolves asymmetrically under the
  monotone-non-decreasing field count — satisfied `min` drops, violated `max` bottoms — retaining
  the undecided residual (unsatisfied `min` / open `max`) in a `.conj` beside the struct, which
  `manifest` (`finalizeFieldCountConj`) adjudicates at finalization so cross-conjunct field
  accretion (`{a:1} & MinFields(2) & {b:2}`) is spec-correct. Fixture
  `testdata/export/struct_field_count`; theorems `fieldcount_*` in `FixtureTests`. The package's
  OTHER members (if any) are out of scope for this slice.
- **C — `strconv` builtin package (MEDIUM). ✅ LANDED (2026-07-10).** Pure conversions in
  `Kue/Strconv.lean`, dispatched via a new `.strconv` `BuiltinFamily` arm. **Shipped** (exact vs
  cue v0.16.1, arbitrary-precision matching Kue's `Int`): `Atoi`, `FormatInt`, `FormatUint`
  (= `FormatInt` in cue), `ParseInt`, `ParseUint`, `FormatBool`, `ParseBool`. `ParseInt`/`ParseUint`
  cover base-0 prefix auto-detect (`0x`/`0b`/`0o`/leading-`0` octal), Go's underscore-separator
  rule (base 0 only), case-insensitive digits, and the `bitSize` range check (`0` = unbounded,
  `b>0` = signed `[-2^(b-1),2^(b-1)-1]` / unsigned `[0,2^b-1]`, `b<0` = empty). Errors are typed
  `BottomReason`s (`strconvSyntax`/`strconvRange`/`strconvInvalidBase`). **Deferred** (route to
  `unsupportedBuiltin`): `Itoa` (not a callable function in cue v0.16.1), `FormatFloat`/`ParseFloat`
  (float shortest-round-trip is incompatible with the exact-decimal core), `Quote`/`Unquote`/
  `QuoteToASCII`/… (need Go's full Unicode `IsPrint` table). **Divergence:** base restricted to Go's
  documented `2..36`; cue leaks `math/big`'s `2..62` — recorded in `cue-divergences.md`. Fixture
  `testdata/export/strconv_basic`; theorems in `Kue/Tests/StrconvTests.lean`. STDLIB-A wild fixture
  repointed `strconv`→`time` (retraction).
- **D — import-placement parse grammar. ✅ LANDED (2026-07-10).** Root cause was NOT
  import-specific: kue lacked CUE's statement separation entirely — the operator-precedence
  chain skipped full trivia (newlines included) when hunting a trailing binary operator, so a
  newline never terminated an expression and consecutive declarations with no comma were
  silently accepted (`x: 1\nimport "strings"`, `foo "bar"`, `a: 1 b: 2` all passed). Fixed by
  implementing CUE's newline-termination (implicit-comma) rule: `skipSameLineTrivia` for every
  trailing-operator lookahead (horizontal ws + block comments, stopping at newline/`//`),
  operator-at-line-END still continuing (the operand parse skips full trivia after the
  operator), plus `fieldSeparator` enforcement in `parseFieldsUntil` (a `,`/`;`/newline must sit
  between declarations, else `missing ',' in struct literal`). Late import is one instance.
  Wild fixture `testdata/wild/import-after-decl/`; parse theorems in `Kue/Tests/ParseTests.lean`
  (§ Import placement + field separators). Spec-gap + log recorded.
- **E — unused-import diagnosis MESSAGE (LOW). ✅ LANDED (2026-07-10).** Confirmed render-only,
  as predicted: the `declared ⇒ used` VERDICT already lands (2026-07-05) with `.importedNotUsed`
  carrying path+alias; only the CLI render collapsed it to the generic `conflicting values
  (bottom)`. `Manifest.manifestWithFuel` now routes a `.bottomWith` whose reasons carry
  `.importedNotUsed` (via `unusedImportReasons`) to a new `ManifestError.importedNotUsed
  [(path, alias?)]`, which `Runtime.formatManifestError` renders as cue's per-import
  `imported and not used: "<path>"` (`" as <alias>"` when aliased, one line each for multiple).
  Position is NOT emitted — the reason carries no source span. Wild fixtures
  `testdata/wild/{unused-import,unused-import-aliased,used-import-ok}/`; render theorems
  `*_render_message` in `ImportEnforcementTests` (via new `exportErrorMessage` helper). Spec-gap
  recorded.

- **F — list-item separator enforcement (queued).** Slice D added CUE's newline/comma statement
  separation to STRUCT literals (`parseFieldsUntil`'s `fieldSeparator`), but LIST literals were
  not covered: `parseListItems` still accepts space-separated items like `[1 2]` where cue
  requires a separator (`,`/newline) between elements (`[1 2]` ⇒ cue `expected ',' or ']'`).
  Mirror D's `fieldSeparator` discipline into `parseListItems`. Wild fixture red-first; parse
  theorems in `ParseTests`.

0. **AUDIT-QUOTED-BEQ (HIGH — correctness regression from `f128600`). DONE (2026-07-04);
   MECHANISM SUPERSEDED by ARCH-QUOTED-STRIP (0c, 2026-07-05).** The "STRIP route" +
   "no custom instance" resolution below is HISTORICAL: `stripFieldQuoting` is deleted and
   `Field.quoted` is now the `Quoted` newtype (inert `BEq`), which makes the leak
   type-unrepresentable without any strip pass. Read 0c for the live mechanism.
   `Field.quoted : Bool` was added to `Value.lean` AND included in the derived `BEq` for
   `Value`/`Field`/`ClosedClause`. `quoted` is parse-time provenance for the load-time no-shadow
   check ONLY, but it was NOT inert to evaluation: it leaked into every `Value`-`BEq` site, so two
   structs CUE deems identical (`{x:1}` vs `{"x":1}`) compared UNEQUAL and `dedupAlternatives`
   failed to collapse `d: {x:1} | {"x":1}` (kue `ambiguous value`, cue `{x:1}`). Fixed via the
   STRIP route: `Parse.stripFieldQuoting` — a total, enumerated (no catch-all) `Value` walk
   mirroring `canonicalizeBuiltinCalls` — normalizes every `Field.quoted → false` at both
   parse→eval seams (`parseDocument`, `parseDocumentFile`), AFTER `checkLetFieldShadow` reads the
   true quoting. Derived `BEq`/`DecidableEq` then see a uniform `false` and stay consistent (no
   custom instance). Seed graduated; dedup + nested-list + necessary-quoting fixtures + 4
   `native_decide` theorems added; all 24 `noshadow_*` theorems intact; cert-manager canary empty.

   **Split-out (the `==` symptom was NOT this bug):** `({x:1}) == ({"x":1})` still errors
   `incomplete value` — filed as **AUDIT-STRUCT-EQ** below. `evalEq` DEFERS all non-`.prim`
   operands before any `BEq`, so the strip never reaches the `==` operator; struct `==` was simply
   never implemented. Orthogonal to label quoting.

0b. **AUDIT-STRUCT-EQ — ✅ FULLY CLOSED (half-1 2026-07-04, half-2 2026-07-05).** (MEDIUM — feature
   gap + pre-existing divergence). RE-SCOPED by the 2026-07-04 Phase B audit: SPLIT into an
   autonomous-safe half and a deferred half; BOTH now landed. `Kue/EvalOps.lean:evalEq`
   handles only `.prim`; every struct/list `==`/`!=` defers to `.binary .eq` → `incomplete value`
   (all-bare `({x:1}) == ({x:1})` defers identically — not a quoting issue). cue reduces concrete
   struct/list `==` to a bool. TWO entangled issues: (1) reduce concrete struct/list operands to
   bool, deferring while non-concrete (`{x:int} == {x:int}`, which cue also leaves unreduced);
   (2) cue struct `==` is ORDER-INDEPENDENT (`{a:1,b:2} == {b:2,a:1}` → `true`), but kue's struct
   equality is raw order-SENSITIVE `Value` `BEq` (no canonical field sort) — the SAME model makes
   kue's disjunction dedup diverge on reordered fields (`{a:1,b:2} | {b:2,a:1}` → `ambiguous`, cue
   collapses; logged in `cue-divergences.md`).

   **Phase B architectural verdict (2026-07-04):**
   - **DO NOT redefine the global `Value` `BEq` to be order-independent.** It is used for structural
     CYCLE detection (`Eval.lean:292 structStack.contains bodyVal`; comment: "Identity is exact
     `Value` equality") and builtin-arg dedup (`Lattice.lean:394`). Order-independence is a COARSER
     equality → distinct-order structs would collide → spurious cycle false-positives + changed
     dedup semantics globally. `satCache`/`cache` are keyed on `valueDigest`, NOT full `BEq`, so
     they are unaffected either way.
   - **Half (1) — `evalEq` concrete struct/list `==` — ✅ DONE (2026-07-04).** `Kue/EvalOps.lean`
     adds `structEqConcrete? : Value → Value → Option Bool`, reachable ONLY from `evalEq`'s
     non-`prim`/non-`bottom` arm. Concreteness guard FIRST (`isConcrete` + `containsBottom`) →
     `none` (defer) unless BOTH operands are fully concrete and bottom-free, mirroring the manifest
     output-field filter (regular fields only; required defers; hidden/def/`let`/import/optional/
     pattern ignored). Then `concreteEq`: structs compare ORDER-INDEPENDENTLY over regular output
     fields (equal count + label-matched equal values); lists ORDER- and LENGTH-sensitively;
     primitives reuse the decimal-aware leaf equality; cross-shape → `false`. `evalNe`/`.ne` inherit
     the negation. Seed `struct-equality-quoted-labels-defers` graduated; 5 export fixtures +
     `struct-equality-incomplete-defers` wild guard + 14 `native_decide` theorems; gate green;
     cert-manager canary empty. Probe-matrix matches cue v0.16.1 on the tested cases (reordered/
     quoted/hidden-ignored/nested/open-tail/cross-shape/lists/scalar `1==1.0`) — but the "matches
     EXACTLY" claim was overstated: the 2026-07-04 Phase A audit found the matrix MISSED int-vs-float
     leaves inside containers (`[1.0]==[1]`, `{a:1.0}=={a:1}` → kue `true`, cue `false`). Filed as
     **STRUCT-EQ-LEAF-TYPESENSE** (0d below). NESTED `embeddedScalar`
     field values stay deferred (isConcrete → false): a safe, exotic residual, not a regression.
   - **Half (2) — order-independent `dedupAlternatives` — ✅ DONE (2026-07-05).** `Lattice.lean`
     adds `normalizeFieldOrder : Value → Value` (a field-ORDER normal form: every struct-bearing
     constructor's member list sorted by label via `sortFieldsByLabel`, sub-values normalized
     recursively; list element order PRESERVED; `termination_by structural`, total) and
     `eqUpToFieldOrder := normalizeFieldOrder left == normalizeFieldOrder right`. `dedupAlternatives`
     now tests arm equality with `eqUpToFieldOrder` (NOT the global order-sensitive `BEq`) and keeps
     the INCOMING (earlier-in-list) arm's value, so `{a:1,b:2} | {b:2,a:1}` collapses to one arm
     displaying the first-declared order — matching cue byte-for-byte. Chosen route: a canonical
     normal form (order-independence BY CONSTRUCTION) over an ad-hoc order-insensitive compare. The
     global `Value` `BEq` is UNTOUCHED — cycle detection (`Eval.lean` `structStack.contains`) still
     relies on exact equality; the coarser equality is confined to the dedup path. Over-collapse
     guarded: differing value / label-set / openness / field-class / list-element-order all stay
     distinct. 17 `native_decide` theorems (`LatticeTests` `structeq_*`) + `structeq_disj_reorder`
     export fixture (reordered/three-way/nested, kue == cue). `./scripts/check.sh` GREEN;
     cert-manager canary in-gate GREEN. The reordered-dedup divergence is REMOVED from
     `cue-divergences.md` (kue now agrees with cue and spec). **AUDIT-STRUCT-EQ is fully CLOSED.**

0c. **ARCH-QUOTED-STRIP — ✅ DONE (2026-07-05, Option B).** `Field.quoted` was parse provenance on
   the eval-layer `Value.Field`, made inert only by a `Parse.stripFieldQuoting` walk at the two
   parse→eval seams — an UNENFORCED "any pre-eval producer setting `quoted := true` must feed through
   the strip" invariant that already bit once (AUDIT-QUOTED-BEQ). **Mechanism deviation from the
   filed plan:** the filed durable fix ("drop `quoted` entirely; have `parsedFieldsValue` bubble a
   collidable-label set up through its recursion") was found INFEASIBLE in-slice — `parsedFieldsValue`
   is NOT recursive over the subtree and there is no `ParsedField` subtree: nested structs are already
   fully-built `Value`s (with `Field.quoted`) by the time they arrive, so the reverse no-shadow check
   (`collidableFieldLabel`/`collectFieldNames`) walks the built `Value`, including structs embedded
   arbitrarily deep inside expressions. Dropping the field would require threading a provenance set
   through the ENTIRE expression parser (a parser-wide return-type change), not ~1 slice. **Chosen
   (Option B):** `Field.quoted : Quoted` — a newtype whose `BEq` IGNORES its payload (`fun _ _ =>
   true`), keeping automatic `deriving Repr, BEq for Value, Field`. Quoting is now inert to every
   `Value`/`Field` equality BY CONSTRUCTION (the AUDIT-QUOTED-BEQ leak is type-unrepresentable, no
   producer can perturb equality), which also makes derived `BEq` consistent with `valueDigest` (which
   already omitted `quoted`) — the inconsistency the strip masked. `collidableFieldLabel` keeps reading
   the provenance (`field.quoted.value`); a `Coe Bool Quoted` leaves eval-layer field constructions
   writing a plain `false`. The ~55-line `stripFieldQuoting` walk + both seam calls are DELETED (not
   bypassed). Supersedes AUDIT-QUOTED-BEQ's "strip route / no custom instance" (rank 0 below): Option B
   keeps *derived* BEq — a one-line inert `BEq Quoted`, NOT a hand-rolled mutual `BEq Value`/`Field`,
   which was that decision's actual concern — so it supersedes cleanly. TDD red→green demonstrated
   (payload-respecting `BEq Quoted` ⇒ the `quoted_inert_*` pins + `ParseTests` dedup pins go RED; the
   digest-consistency pin stays green, proving BEq was the sole leak). 6 new `native_decide` theorems
   (`LatticeTests` `quoted_inert_*`); `./scripts/check.sh` GREEN; cert-manager canary byte-identical.

0d. **STRUCT-EQ-LEAF-TYPESENSE — ✅ RESOLVED (2026-07-04 Phase B, kue correct / cue buggy).**
   Adjudicated against the CUE spec: **value-based numeric equality applies recursively inside
   containers**, so kue's `1130638` code was already CORRECT and cue's `[1]==[1.0]=false` is a cue
   bug. Spec (Comparison operators): "Numeric values are equal if they represent the same number.
   When comparing an integer with a floating-point number, the integer is first converted to
   floating-point" + list/struct `==` are "recursively equal" over elements — recursive element
   equality reuses `==`, so the int→float carve-out applies at any depth. cue is internally
   INCONSISTENT (scalar `1==1.0`→`true`, container `[1]==[1.0]`→`false`); kue is value-based
   EVERYWHERE, hence spec-correct AND consistent. The Phase A "recommended: match cue / type-
   sensitive" lean was WRONG (would replicate the cue bug); the spec is EXPLICIT, not silent, so
   this is a `cue-divergences.md` entry, NOT a spec-gap. `1 & 1.0 = ⊥` does not bear on `==`
   (comparison ≠ unification). Landed inline: 6 `native_decide` theorems (int-vs-float in list,
   struct, nested-at-depth, unequal, `evalNe` negation) + 4 fixture cases in
   `numeric/equality_expressions` + the divergence record. No code change (kue was already right).

0e. **PRIM-FLOAT-PARSED ✅ LANDED 2026-07-05 (LOW-MEDIUM — type-system leverage + minor perf; from
   the 2026-07-04 Phase B audit).** `Prim.float` now carries `(value : DecimalValue) (text : String)`
   (was raw `String`), smart-constructed through the sole `mkFloatText` constructor which sets
   `value := parseDecimalText text` once at build time. `decimalFromPrim?` and `primsUnifyEqual` read
   the stored decimal with ZERO hot-path re-parse; the illegal `| _, _ => leftText == rightText`
   fallback in `primsUnifyEqual` is ERASED (the float arm is now a total `decimalEqValues` on the two
   stored values). `mathAbs`/`mathRound` also drop their per-call `parseDecimalText`. Behavior-
   preserving by construction: `value` is a deterministic function of `text`, so derived `BEq` on
   `Prim.float` still reduces to text-equality (fixtures + cert-manager canary byte-identical). 5 new
   `native_decide` theorems in `FloatTests.lean` pin the invariants (stored-decimal exactness/totality,
   by-value unify, verbatim text round-trip incl. trailing-zero/scientific, BEq≡text, bound edges).
   Original spec retained for provenance: `Prim.float` carried the raw literal `String` (`Kue/Value.lean:19`), so every
   float-vs-float meet (`primsUnifyEqual`, `Kue/Lattice.lean:14`) and every float compare
   (`toDecimalValue?`/`evalDecimalCompare?`) RE-PARSES the text via `parseDecimalText` on the hot
   path. Two smells: (1) repeated `parseDecimalText` work on a value that never changes, and (2) the
   `parseDecimalText` `Option` forces a `| _, _ => leftText == rightText` "can't happen" fallback in
   `primsUnifyEqual` (a float literal from the lexer ALWAYS parses) — exactly the illegal-state the
   repo wants erased at the type. **Fix: refine `Prim.float` to carry a smart-constructed
   `DecimalValue` alongside the source text** (`float (value : DecimalValue) (text : String)`, built
   once at lex time). Erases the re-parse AND the unreachable fallback branches; the retained `text`
   preserves round-trip rendering (GDA-FLOAT-RENDER's concern). Cost: `Prim.float` is a CORE type
   threaded through lexer/formatter/eval — a signature change touching many sites → its own MEDIUM
   slice, not an inline fix. Perf impact is real but small (float meets are a minority of meets);
   the primary win is illegal-states-unrepresentable. Couple with GDA-FLOAT-RENDER (both touch the
   float representation) if convenient.

0f. **BYTE-ARRAY-REPR ✅ LANDED 2026-07-05 (MEDIUM, core-type — ordinary test-first slice; from the
   2026-07-04 Phase B audit; CONSOLIDATES the bytes-as-String debt).** `Prim.bytes` now carries
   `Array UInt8` (was `String`). Fully CLOSED BYTE-HIGHBYTE — the `byte-literal-high-byte` seed
   graduated GREEN (`'\xff'`/`'\377'` → `/w==`, the single octet 0xFF). The three latent bugs were
   fixed at the same sites: `len` byte count (`.size`), `formatPrim` `\xNN`/named-escape byte encoder,
   lossy `.toUTF8` base64 (Json/Yaml/Builtin now encode the raw bytes). Also fixed the multiline-bytes
   escape gap (dedicated `parseMultilineByteBody` decoding byte escapes). **Prerequisite for
   BYTES-SLICE-MISSING and BYTE-INTERPOLATION is now MET** — both remain open dependents (below).
   Original spec retained for provenance: `Prim.bytes` carried a `String` (`Kue/Value.lean:21`),
   so a byte ≥0x80 cannot be represented as one octet — `decodeByteEscape` (`Parse.lean:182`) folds
   `\xNN`/`\NNN` through `Char.ofNat` into that codepoint's multi-byte UTF-8 form. This ONE loose
   representation is the root of THREE filed items: BYTE-HIGHBYTE (Json/Yaml base64 round-trips
   through lossy `.toUTF8`), BYTES-SLICE-MISSING (needs byte-indexed slicing), and BYTE-INTERPOLATION
   (byte-context carrier). **Verdict — CONSOLIDATE the repr change, keep the two feature follow-ups
   dependent.** Refine the carrier to a byte array. **Choose `Array UInt8`, NOT `ByteArray`:** it
   preserves the existing `deriving Repr, BEq, DecidableEq` on `Prim` (`Value.lean:22`) + `Hashable`
   for `digestPrim`, and keeps the `primsUnifyEqual_refl` proof (`Lattice.lean:23`) closing —
   `ByteArray` lacks `DecidableEq`/`Repr` in Lean core (a soundness snag). No interaction with the
   `Field.quoted` strip (that walks labels, never `Prim` payloads) or STRUCT-EQ (bytes compare by
   byte-array equality, cleaner than String). **Invasiveness MEDIUM: ~16 production sites across 9
   files** (Value, Parse×3, Lattice×2 +proof, EvalOps×3, Builtin×2, EvalBase×2, Format, Json, Yaml)
   + carrier-literal churn in ~6 test modules. The diff is CORRECTIVE, not just mechanical — it fixes
   three latent bugs at the SAME sites: `len('\xff')` (`Builtin.lean:36`, counts UTF-8 bytes → should
   be `.size`), `formatPrim` output (`Format.lean:60`, emits NO byte-escaping today — needs a `\xNN`
   encoder), and the lossy `.toUTF8` base64 (`Json.lean:54`/`Yaml.lean:311`/`Builtin.lean:780`).
   **What it unlocks vs. what stays separate:** fully CLOSES BYTE-HIGHBYTE (graduates
   `byte-literal-high-byte` — fold it INTO this slice). It is a PREREQUISITE that de-risks but does
   NOT subsume the other two: BYTES-SLICE-MISSING still needs its own byte-slice dispatch (repr just
   makes the impl a clean `Array.extract`); BYTE-INTERPOLATION still needs the byte-context carrier
   arm rippling ~20 match sites (repr makes segment concat a clean array append but the carrier
   plumbing is the bulk cost, independent of String-vs-array). So: land BYTE-ARRAY-REPR FIRST as a
   focused core-type slice (carrier + the 3 latent fixes + high-byte graduation), then BYTES-SLICE
   and BYTE-INTERPOLATION as small dependents. Also fixes the multiline-bytes escape gap
   (`parseMultilineBytes`, `Parse.lean:1434`, currently routes through the string escape lexer).
   Land it autonomously test-first: a core `Prim` change is not a stop condition (internal risk
   is absorbed by the gate + fixtures + audit, not human review) — pin the carrier + 3 latent
   fixes + high-byte graduation with `native_decide` theorems before the refactor.

1. **B3d-6b — FULLY LANDED 2026-07-05 (`kue mod tidy` + MVS + `cue.sum` write + main-pin fix +
   leg 4 export-path MVS + leg 2 `mod get`).** The substantive registry work landed: `kue mod tidy`
   fetches each transitive dependency's `module.cue` over the read-only registry GET, builds the
   `RequirementGraph`, runs the CHECKED MVS solver (`Mvs.solveChecked` — the main-pin fix: a dep
   requiring a higher version of the main module's own path is a typed error, not a silent pin),
   and WRITES `cue.sum` with the verified `h1:` digests. New `Kue/ModCmd.lean` (carved from
   `Module.lean`); offline gate `scripts/check-mod-tidy.lean` drives a diamond graph proving
   max-of-mins selection + cue.sum. **leg 4 LANDED 2026-07-05** (export-path MVS rewiring — the
   disk-built graph governs import resolution). **leg 2 LANDED 2026-07-05** (`kue mod get
   <module>[@version]` — deps-block emitter + `.../tags/list` "latest" resolution; see § B3d track).
   **B3d-6b is now fully closed** — no remaining FILED dependents.

2. **B2-A1 — RESOLVED-BY-PROBE (2026-07-04, non-bug).** The prior claim ("`applyEvaluatedStructN`
   routes the patterns-present case through a meet that DROPS `tail`") was STALE: `applyEvaluatedStructN`
   (`EvalBase.lean:342,350`) PRESERVES `tail` on both arms (empty-patterns → `mkStruct … tail`;
   patterns-present → the `tail` stays on the pattern-bearing struct fed to `meet`). Typed-tail
   application is already correct and theorem-pinned: `meet` rejects a wrong-typed ADDITIONAL field
   (`StructTests` `meet_typed_ellipsis_rejects_conflicting_extra_field`), accepts a matching one,
   and exempts a struct's OWN declared fields (`…does_not_constrain_declared_field_by_tail`) — which
   is why `applyEvaluatedStructN` correctly leaves its own explicit fields untouched. **No source
   reaches this path:** `{...T}` is rejected at parse in BOTH kue (`Parse.lean:1483` "typed struct
   ellipsis is not supported yet") and cue v0.16.1 ("missing ',' in struct literal") — the CUE spec
   marks `...expr` reserved-but-unimplemented. Lists differ: `[...T]` IS parsed+enforced by both,
   and kue matches cue (`[...int] & [1,"s"]` → bottom on both). Parse-rejection now guarded by
   `ParseTests` `parse_struct_typed_{ellipsis,top_ellipsis}_rejected`. Nothing to fix unless/until
   typed-ellipsis SYNTAX is implemented (a separate feature, not a soundness debt).

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
- **B3d-B1 — DONE 2026-07-10.** `Kue.Hash1` newtype now wraps the `cue.sum` `h1:<base64>` token
  end-to-end (produce `Sha256.hash1` → accumulate `fetchGraph`/`cueSumRows` → parse/format
  `parseCueSumText`/`formatCueSum` → verify `fetchAndCacheModule`); `Hash1.parse`/`render` are the
  file-format boundary. The OCI `Descriptor.digest` (`sha256:<hex>`) stays a bare `String`
  (separate concern). **kue-performance B3d note** still open. (B3d-A2, Mvs.solve main-pin, and
  the `ModuleFetch` carve all LANDED 2026-07-05.)
- **GATE-KNOWNRED-DRY (LOW, infra; from the 2026-07-04 Phase B / A7 rotation) — DONE.**
  The two copy-pasted three-state `.known-red` blocks in `check_wild_fixtures` and
  `check_module_subpaths` are replaced by one `handle_known_red <known_red> <passed> <grad_label>
  <quar_label>` helper: it emits the graduation/quarantine diagnostic and returns a verdict
  (0 = quarantined-skip, 1 = graduation hard-fail, 2 = not-quarantined → caller's own pass/fail
  handling). Each caller passes a preformatted label so its wording stays byte-identical to
  before (wild: `<slug>` / `wild fixture <cue>`; module: `module fixture <dir> subpath <sub>` for
  both). Behavior EXACTLY preserved; shellcheck-clean; `check.sh` green. Three-state verdict
  smoke-tested in isolation (no live `.known-red` currently exists).
- **A2-x (latent) — `importBinding` merge-asymmetry.** STAYS unobservable (the only collision
  that would exercise it is the one A2-y rejects at LOAD). No work; recorded so it is not
  re-investigated.
- **AUDIT-RESOLVE-CATCHALL (LOW, pre-existing, latent) — DONE.** `mapRefsValueWithFuel`'s
  trailing `| _, _, value => value` catch-all is REPLACED by 13 explicit pass-through arms (the
  leaves + `refId`/`thisStruct`/`embeddedList`/`embeddedScalar`/`closure`), so exhaustiveness is
  now compiler-proven — a new `Value` ctor fails the build at this rewrite site instead of being
  silently swallowed. Byte-identical behavior (all swallowed ctors were pass-through under the
  catch-all and remain so; `closure` stays pass-through — it owns its `capturedEnv`, not the
  enclosing `scopes`; `embeddedList`/`embeddedScalar` are eval-only, never present at the two
  pre-eval call sites). No latent bug surfaced. cert-manager canary EMPTY; `check.sh` green.
- **UNUSED-IMPORT-BINDNAME / AUD-B6 (MEDIUM — latent false-positive; filed by the `0427bf1..HEAD`
  Phase A audit) — DONE 2026-07-06.** RETRACTION: this entry's original diagnosis assumed `cue`
  ACCEPTS a bare `import ".../x/foo"` whose dir declares `package bar` (used as `bar.Field`) and
  expected the fix to make Kue return NON-bottom. That premise is WRONG: `cue` v0.16.1 REJECTS such a
  program — `no files in package directory with package name "foo"` — requiring the `:bar` qualifier.
  So `importLocalBindName` dropping the `declaredName` arm can only mis-flag programs `cue` itself
  rejects; teaching the check the `declaredName` arm would make Kue wrongly ACCEPT a `cue`-illegal
  import. Resolved instead as the F-3 suffix-vs-declared-name MISMATCH gate: `collectBindings`
  enforces the loaded `package` clause == expected name (qualifier, else last path element), a
  cue-shaped load error on divergence. This keeps `importBindName` purely lexical (param-free, moved
  to `Value.lean`, one resolution shared by parse-time check + loader binder; `importLocalBindName`
  deleted) so the parse-time unused check can never mis-name a bound import. (The
  `collectReferencedHeads` WALK was always false-positive-safe — exhaustive, no catch-all, `[]` arms
  carry no `Value`; the gap was never the reference walk.) Fixtures `import_bare_pkgname_mismatch`
  (expected.err) + `import_qualifier_pkgname_rescue`.

### COMPREHENSION/EMBEDDING/PATTERN CONFORMANCE PROBE (2026-07-04) — area clean, one parser gap seeded

Bounded divergence hunt over `for`/`if`/`let` comprehensions, struct embedding, and pattern
constraints (`[expr]: T`). Area is **spec-conformant** at the VALUE level across the whole
matrix — the only real divergence is a parser-completeness gap (below). Confirmed CONFORMANT
(kue == cue, spec-correct): `for k,v` over struct (skips hidden/optional/def members), `for
i,x` over list, value-only `for`, nested/multi-clause `for`, `let`-clause + `if`-guard,
empty-source (no fields), `for`/`if` producing struct fields dynamically; embed struct+sibling,
embed scalar/string/list carrier, embed def/ref, embed comprehension/conditional, embed
conflict → ⊥; pattern applied to added fields, regex-keyed, multi-pattern overlap, pattern +
explicit field (explicit must satisfy pattern → ⊥ on violation), pattern + `...` tail, pattern
excludes hidden/def fields, pattern via unification, dynamic field matched by pattern. Guard
theorems: `ComprehensionTests` `listcomp_for_kv_skips_nonregular`/`structcomp_for_produces_fields`;
`StructTests` `pattern_via_unification_constrains_added_field`/`pattern_explicit_field_must_satisfy`/
`pattern_matches_dynamic_field`.

- **PATTERN-BOUND-REF-OPERAND (parser completeness; FILE — parser+evaluator, soundness-adjacent).**
  kue's parser accepts only LITERAL operands for relational/bound operators: `parseBoundValue`
  (`Kue/Parse.lean`) wants a numeric literal for `> >= < <=`; the `=~`/`!~` arms call
  `parseQuotedString` (string literal); `!=` wants a `.prim`. A REFERENCE or any expression
  operand — `x: >k`, `{[=~_re]: int}`, `{[>k]: int}`, `<len(y)` — fails to parse ("expected
  string literal" / "expected number digits"). cue v0.16.1 accepts all: CUE grammar has
  `unary_op = … | rel_op` with an arbitrary `UnaryExpr` operand. kue is WRONG (over-restrictive) —
  rejects valid CUE. **Fix is broad + soundness-core, red-seeded not forced (AFK):** the bound
  `Value` repr must carry an UNRESOLVED operand expression; the parser must parse a general
  `UnaryExpr` operand for every rel_op; the evaluator must evaluate the operand (deferring on
  incomplete) before applying the relation. Bounds are pervasive → own careful attended slice.
  Red seed `testdata/wild/pattern-bound-reference-operand/` (`.known-red`; spec-adjudicated
  expected). NOT a cue-divergence (cue is spec-correct here); a plain kue completeness bug.
- **Embed/comprehension field ORDER — already-ratified spec gap, NOT re-filed.** `{ {a:1}, b:2 }`
  → kue `{b,a}` (declaration order, embeddings after regular fields), cue `{a,b}`. This is
  "Field order #3" (spec-conformance-audit § RATIFIED): spec declares structs unordered, cue's
  order is "an undocumented internal-graph artifact"; parity DECLINED, Kue keeps source order.
  jq `-S` canary is order-insensitive. Recognized + skipped per probe instructions.

### NUMERIC/BUILTIN CONFORMANCE PROBE (2026-07-04) — one bug fixed, follow-ups filed

Bounded divergence hunt over numeric literals/formatting/arithmetic + a stdlib-builtin
sampling. Confirmed CONFORMANT (kue == cue, spec-correct): `0.1+0.2`, `1.0/3.0` (34-digit),
huge bignum int literals + arithmetic, int-vs-float unification rejection, all numeric
bounds (`>=0 & <=10 & 5`, `>3 & int`, conflicting → bottom, `>=1.5 & int`), `math.Round`/
`Floor`/`Ceil`/`Trunc` incl. negatives + `.5`, `div`/`mod`/`quo`/`rem` sign behavior,
`len(string)` (bytes: ascii/multibyte/emoji), `strings.Join`/`Split`/`ToUpper`/`TrimSpace`/
`Replace`/`Contains`, `list.Concat`/`Range`/`Sort`/`FlattenN`.

- **FLOAT-UNIFY-EQUAL (semantic bug) — FIXED this slice.** `meetPrim` compared `Prim`
  structurally, so unifying two floats equal-in-value but distinct-in-string (`1.0 & 1.00`,
  `0.10 & 0.1`, `100.0 & 1e2`, `1.5 & 1.50`) bottomed — contradicting kue's own `==` (which
  returns `true`). `primsUnifyEqual` now compares float-vs-float by exact base-10 value
  (`parseDecimalText`+`decimalEqValues`), keeping the LEFT operand (cue's rule); other kinds
  stay structural; int-vs-float stays a type conflict. Wild fixture
  `float-unify-equal-diff-representation` (enforced) + `NumberTests` `meet_prim_float_*`.
- **GDA-FLOAT-RENDER ✅ LANDED 2026-07-05.** Floats now render through CUE's canonical GDA
  `to-scientific-string` per output surface via `renderFloatText` (`Value.lean`), replacing
  verbatim `text` emission in `Format`/`Json`/`Yaml`. Byte-identical to `cue` v0.16.1 across
  JSON (uppercase `E`, bare whole floats), YAML (uppercase `E`, `.` whole floats), and
  cue-native (lowercase `e`, `.0` whole floats) on the full matrix: small-exp expansion
  (`1e-2`→`0.01`, `12345e-2`→`123.45`), large-magnitude scientific (`1e40`→`1E+40`),
  plain/scientific boundary at adjusted-exp `≥ −6` (`1e-6`→`0.000001`, `1e-7`→`1E-7`),
  representation collapse (`1.00e2`→`100`/`100.0`), `-0.0`→`0.0`. **Plan's original mechanism
  was FALSE and is superseded:** "render on the exact `DecimalValue`" cannot work — a
  normalized `DecimalValue` (non-negative `scale`) multiplies a positive exponent into the
  coefficient, so `1e2` and `1.00e2` share `{100,0}` yet must render `1E+2` vs `100`, and
  `1e40`→`{10^40,0}` would render PLAIN not scientific. The apd `(coefficient, exponent)` form
  is reconstructed from the retained `text` instead (the round-trip anchor 0e kept). Recorded
  in `cue-spec-gaps.md` (FLOAT OUTPUT FORM — spec-silent, kue matches cue). Retraction: the
  original bullet's claim that "arithmetic sign-of-zero (`0.0 * -1`→cue `-0.0`)" is a target to
  match is WRONG — `cue` export does NOT uniformly normalize zeros (it exports `-0.0` for that
  arithmetic case); kue normalizes ALL rendered zeros to `0.0` (lattice-consistency: `-0.0 ==
  0.0`), matching cue on the literal `-0.0`→`0.0` and diverging on the arithmetic case,
  recorded in `cue-divergences.md`. Fixtures: `testdata/export/float_render_gda.*`,
  `testdata/cue/numeric/float_gda_render.expected`; `FloatTests` GDA section (4 theorems).
- **STRINGS-RUNES-MISSING — DONE (2026-07-04).** `strings.Runes(s)` now registered:
  `stringRunes` maps each `Char` (Unicode scalar) to `.prim (.int codepoint)`, so
  multibyte/astral are one int per rune (`"a😀b"`→`[97,128512,98]`), astral-correct (full
  code point, not surrogate halves/bytes). Dispatch arm in `evalStringsBuiltin`; wrong-arity
  / non-string falls through to `unresolvedOrBottom` (concrete ⇒ bottom, matching cue's
  error). Fixture `strings_runes` (ascii/multibyte/emoji/empty/combining) + 6 `native_decide`
  theorems. kue == cue v0.16.1 on all cases.
- **BI-3-STDLIB-PROBE — DONE (2026-07-04).** Conformance probe of the deeper stdlib +
  type/kind ops (registered-builtin sweep + language meets). **Registered & implemented this
  slice** (all unregistered gaps, kue previously bottomed, cue succeeds — kue == cue v0.16.1):
  `list.Reverse`; `strings.LastIndex` (byte index of last occurrence, empty needle ⇒ byte
  length), `strings.Compare` (byte-lexicographic −1/0/1), `strings.Trim`/`TrimLeft`/`TrimRight`
  (cutset is a rune SET, not a prefix), `strings.TrimPrefix`/`TrimSuffix` (single fixed affix).
  Helpers `listReverse`/`stringLastByteIndex`/`byteSeqCompare`/`stringCompare`/`stringTrim*` in
  `Builtin.lean`, dispatch arms in `evalListBuiltin`/`evalStringsBuiltin` (wrong shape ⇒
  `unresolvedOrBottom`). Fixtures `strings_trim`, `strings_compare`, `list_reverse` + 10
  `native_decide` (`BuiltinTests.lean`). **Type/kind meet ops SWEPT CLEAN** (no code change): `int
  & number`→int, `1 & number`→1, `1.5 & int`→⊥, `1 & float`→⊥, `"x" & bytes`→⊥, `null & int`→⊥,
  `_ & 5`→5, `>5 & int & <10 & 7`→7, `(int|string) & 5`→5, `>5 & <3`→⊥ — all agree with cue
  (verdict + concrete value); 2 guard theorems pin the family. Also-conformant (both error, only
  message text differs): all negative/oob/empty-list arg errors on `list.Take`/`Slice`/`Repeat`/
  `Range(zerostep)`/`Min`/`Avg`, `strings.Repeat(neg)`. **cue-non-functions confirmed** (kue
  bottom is correct — these are NOT functions in cue v0.16.1): `strings.Title`/`PadLeft`/`PadRight`,
  `math.GreatestCommonDivisor`, `math.MaxInt64` (undefined field). Canary EMPTY.
- **BI-3-RESIDUAL (bounded subset DONE 2026-07-04; validators + byte-repr still FILED).**
  **Registered & implemented this slice** (kue == cue v0.16.1 on the agreeing corpus): `math.Mod`
  (Go float-remainder, sign of dividend, exact-decimal `x − trunc(x/y)·y`; `Mod(x,0)` ⇒ bottom;
  DIVERGES from cue's float64 on non-float64-exact remainders — `Mod(5.5,2.1)`=`1.3` vs cue
  `1.2999…998`, recorded in `cue-divergences.md`), `math.Signbit` (true iff `numerator<0`;
  `Signbit(-0.0)`=false, matching cue's parse-time `-0.0`→`0.0`), `strings.SliceRunes` (half-open
  rune-indexed window on `Char` scalars; oob/neg/`lo>hi` ⇒ bottom). Helpers `mathMod`/`mathSignbit`/
  `stringSliceRunes` in `Builtin.lean`, dispatch arms in `evalMathBuiltin`/`evalStringsBuiltin`.
  Fixtures `builtins/math_mod_signbit`, `builtins/strings_slicerunes` + 21 `native_decide`
  (`BuiltinTests.lean`). **Still FILED** (validator seam kue lacks — the `matchN`/`matchIf`/
  `list.MatchN` family, `Eval.lean` BI-EFF EXTENSION RULE): `strings.MinRunes`/`MaxRunes` (rune-count
  CONSTRAINT validators — `"abc" & strings.MinRunes(3)` needs a `.builtinCall`-participates-in-`meet`
  seam; today `meet(scalar, .builtinCall)` ⇒ bottom, `Lattice.lean:481`, so a validator can't be
  forced without the seam). [`struct.MinFields`/`MaxFields` are now LANDED (STDLIB-B, 2026-07-10)
  via a dedicated `Value.fieldCountConstraint` validator that participates in `meet` directly — a
  struct-count validator, not the scalar `.builtinCall` seam; the `strings.MinRunes`/`MaxRunes`
  scalar-validator seam remains the open residual here.] Also still filed:
  `strings.ByteAt`/`ByteSlice` (need byte-array-repr, DEPENDENT of BYTE-ARRAY-REPR),
  `list.IsSorted`/`Sort`/`SortStable` (comparator-struct `list.Ascending`/`Descending` — the
  effectful-builtin seam BI-EFF; kue leaves these an incomplete residual today). SEPARATE
  (deferred exp/ln increment, needs decimal `exp`/`ln` to 34 digits — see BI-2-residual /
  cue-spec-gaps): `math.Log`/`Log10`/`Exp`, general fractional/negative `math.Pow` exponent, and
  the `math.Pi` constant (cue ships a 64-digit literal). None soundness-bearing; kue bottoms
  rather than emit a wrong value.
- **LIST-SLICE-MISSING (feature gap) — DONE (2026-07-04).** List slicing `x[lo:hi]` now
  parses as a postfix form alongside indexing `x[i]` and desugars to `list.Slice` (parser
  branch in `parseSelectorRest` + `parseSliceRest`, `Kue/Parse.lean`). Bounds are optional
  (omitted low = `0`, omitted high = `len(base)`). Semantics inherited from the existing
  `listSlice` + builtin-defer machinery: list-only operand, half-open 0-based; oob-high /
  negative / `lo>hi` → bottom; string operand → bottom; incomplete bound → residual defer.
  kue == cue v0.16.1 across the matrix (canary empty). Fixture `list_slice` + 14
  `native_decide` (`SliceTests.lean`). Follow-up: BYTES-SLICE-MISSING (below).
- **BYTES-SLICE-MISSING (feature gap; FILE, not a bug — DEPENDENT of BYTE-ARRAY-REPR rank 0f; repr
  prerequisite MET 2026-07-05, impl still open — the `Array UInt8` carrier makes the slice a clean
  `Array.extract`).** cue slices bytes too
  (`'hello'[1:3]` → `'el'`, base64 `ZWw=`), byte-indexed; kue bottoms (the `list.Slice`
  desugar is list-only). Deferred deliberately from LIST-SLICE: reusing `list.Slice` for
  bytes would wrongly make the user-facing `list.Slice('bytes',…)` succeed, and a clean fix
  needs its own slice dispatch (an internal `__slice`/slice-family builtin handling both
  list and bytes) — a separate slice with its own byte-indexed fixtures. Tracked here as an
  unimplemented direction (cue is spec-correct on bytes slicing; not a divergence).

- **INTERP-OPERAND-TYPING (bug) — DONE (2026-07-04).** A string interpolation `"\(x)"` with a
  CONCRETE operand of a forbidden type now bottoms instead of passthrough-rendering. Probe (2026-07-04
  string-interpolation/regexp/encoding sweep) found `"\(null)"`→`"null"`, `"\([1,2])"`→literal
  `"\([1,2])"`, `"\({b:1})"`→literal `"\({b:1})"` — all kue-wrong; spec restricts an interpolation
  operand to `bool|string|bytes|number`. Fix: `classifyInterpolationPart` (total, all-ctor
  enumeration, mirrors `classifyDynLabel`) + `combineInterpVerdict` fold in `EvalBase.lean`, new
  `BottomReason.nonInterpolatable`. Concrete scalars still render; UNRESOLVED operands (ref/kind/
  bound/disj) still DEFER (no false errors — cert-manager canary EMPTY). Fixture
  `numeric/interpolation_type_error` + 8 `native_decide` (`Tests.lean`).
- **BYTE-LITERAL-LEXING (bug; escape half DONE 2026-07-04; interpolation DEFERRED).** Escape
  decoding FIXED: `decodeByteEscape` + `parseQuotedByteBody` in `Parse.lean` decode `\xNN` (hex
  byte), `\NNN` (exactly-three-digit octal), `\uNNNN`/`\UNNNNNNNN` (unicode → UTF-8), and
  `\a\b\f\n\r\t\v\\\'\"`. Graduated `byte-literal-hex-escape` (`'\x01ab'` → `AWFi`); added
  `byte-literal-octal-escape` (`QUJD`), `numeric/byte_literal_escapes` (eval fixture + FixturePort),
  8 `native_decide` (`BytesTests.lean`). Base64 JSON export already worked (`Json.lean`). ~~KNOWN
  LIMITATION: bytes are String-backed, so `\xNN`/`\NNN` ≥ 0x80 decode to that codepoint's two-byte
  UTF-8 form~~ — RETRACTED 2026-07-05 by BYTE-ARRAY-REPR (rank 0f): the `Array UInt8` carrier holds
  `\xNN`/`\NNN` ≥ 0x80 as a single raw byte; `BytesTests.lean` now pins the high-byte round-trip.
  Byte-context interpolation
  DEFERRED — seed `byte-literal-interpolation` STAYS `.known-red`: it needs a distinct byte-
  interpolation carrier (`.interpolation` renders to a STRING, no byte-context marker) — a new
  `Value`-producing arm rippling ~20 match sites + digest/format/manifest, disproportionate to
  bundle; `\(` falls through to a literal `(` (`(1)` → `KDEp`), red preserved. Follow-up slice
  **BYTE-INTERPOLATION**: ~~byte-array bytes repr (fixes ≥ 0x80, graduates the `byte-literal-high-byte`
  red seed)~~ (DONE 2026-07-05 in BYTE-ARRAY-REPR rank 0f) + byte-context interpolation carrier
  (graduates the `byte-literal-interpolation` seed +
  string-context bytes operand `"\(bytesval)"`, currently DEFERRED/safe).
  **RE-SCOPED (2026-07-04 Phase B): the byte-array repr half is now BYTE-ARRAY-REPR (rank 0f), which
  CLOSES BYTE-HIGHBYTE (fold that seed's graduation into 0f). BYTE-INTERPOLATION remains the residual
  byte-context-carrier follow-up, a DEPENDENT that lands after 0f — the carrier plumbing (~20 sites)
  is its own cost, not unlocked by the repr alone.**
  Related:
  bytes-operand render into a STRING interpolation (`"\(bytesval)"`) is also unimplemented — kue
  DEFERS it (safe), cue renders the UTF-8 form (`"ab"`); fold into the same slice.
- **BUILTIN-IMPORT-LENIENCY — ✅ LANDED 2026-07-05.** A package-qualified stdlib builtin
  reference (call `strings.ToUpper(...)` or constant `list.Ascending`) now resolves ONLY when its
  package is imported; an un-imported reference is `reference "<pkg>" not found` (bottom), matching
  cue v0.16.1. Enforced in the import-aware post-parse pass (`applyBuiltinAliases` →
  `canonicalizeBuiltinCalls`/`gateBuiltinImport`/`resolveBuiltinConstSelector`, `Kue/Parse.lean`),
  the single choke point both single-file (`parseDocument`) and module-load (`parseDocumentFile`)
  parses pass through. The slice operator `x[lo:hi]` desugars to a NEW core `slice` builtin —
  import-exempt (a language operator) and distinct from the import-gated public `list.Slice`.
  Corpus needed zero fixture migration (all 28 builtin-using fixtures already imported, being
  cue-oracle-derived); tests in `ImportEnforcementTests.lean`.
- **UNUSED-IMPORT — ✅ LANDED 2026-07-05 (sibling of BUILTIN-IMPORT-LENIENCY).** The mirror
  half: an `import` present but never referenced in the file body is now cue's `imported and
  not used` build error, so the document bottoms (`.importedNotUsed`). Enforced in `resolveImports`
  (`Kue/Parse.lean`, both parse entry points) via a pre-canonicalization `collectReferencedHeads`
  walk that gathers every referenced package head and checks each import's local bind name against
  it; detection only under-reports so a used import is never mis-flagged. Corpus migration: ZERO
  genuine unused imports (a 632-file scan flagged only two pre-existing ERROR fixtures where a
  prior error — import-name redeclaration, invalid package id — supersedes). Two stale ParseTests
  that pinned the old leniency (`parse_import_clause_is_ignored`) retargeted to the enforced
  bottom. Tests in `ImportEnforcementTests.lean` (16 new theorems). Both halves of cue's import
  contract (declared ⇔ used) now hold.

### 2026-07-05 two-phase audit findings (batch `d6dac7c..HEAD`: `mod get` leg2 + unused-import)

A4 (audit-the-last-audit): the 2026-07-05 Phase-B filings reconcile clean — AUD-B2/B3/B4 all landed
(DONE, unchanged); **AUD-B5 re-verified STILL OPEN + correctly scoped** — `buildDiskGraphAux`
(`Module.lean:385`) and `fetchGraphAux` (`ModCmd.lean:91`) are byte-for-byte the two BFS builders
AUD-B5 describes; leg2 added no third graph walk (`mod get` uses tags/list, not a graph), so the
LOW/deferred verdict stands. Not closable, not newly urgent.
  - **[RETRACTED — AUD-B5 landed]** Both walks now share `Module.bfsRequirementGraphAux`; see the
    AUD-B5 DONE entry under "Open Phase-B fix-slices".

**Phase A — one REAL bug fixed inline, one MEDIUM latent false-positive filed:**

- **MODGET-COMMENT-EXCISION (correctness — silent module.cue corruption). ✅ FIXED (this audit).**
  Adversarial probe of `exciseTopLevelDeps`/`dropBalanced` (`ModCmd.lean`) found the textual deps
  splicer was NOT comment-aware: a `//` or `/* */` comment carrying an unbalanced `}` (or a lone
  `"`) INSIDE the deps block made `dropBalanced` mis-close early, splicing the deps-block remnants
  back into module.cue as top-level content — `applyModGet` then emitted a corrupt file (no error,
  `found=true`). A top-level comment with an unbalanced `{` raised brace depth and hid the following
  deps field (errored on a valid file). FIX: replaced the `(inString, escaped)` bool pair in both
  scanners with a `Lex` sum type (`normal | str escaped | line | block`) — illegal-states
  (escaped-while-not-in-string) now unrepresentable — and taught both to skip `//`/`/* */` (braces
  and quotes inside a comment are inert; comments are copied verbatim by the excision). Six
  `native_decide` regressions added to `ModCmdTests` (line-comment `}` in deps, block-comment `}{"`
  in deps, lone `"` in a line comment, top-level `{` comment, end-to-end `applyModGet` no-corrupt).
  All previously-adversarial shapes now correct; build + `check.sh` green.
- **UNUSED-IMPORT-BINDNAME / AUD-B6 (MEDIUM — latent false-positive). DONE 2026-07-06** — resolved
  as the F-3 suffix-vs-declared-name MISMATCH gate, NOT the audit's assumed "defer + accept". The
  audit expected `import ".../foo"` (dir declares `package bar`) used as `bar.Field` to be a false
  unused-flag on a VALID program; `cue` v0.16.1 REJECTS that program (`no files in package directory
  with package name "foo"`, demanding the `:bar` qualifier). So the divergence set is exactly the
  programs `cue` rejects — the naive "give the check the declaredName arm" fix would make Kue ACCEPT
  a `cue`-illegal import (wrong-direction divergence). Root-cause fix: `collectBindings` now enforces
  the loaded package's `package` clause == the import's expected name (qualifier, else last path
  element); a mismatch is a cue-shaped load error. That keeps `importBindName` purely LEXICAL (one
  param-free resolution in `Value.lean`, shared by the parse-time unused check and the loader binder —
  `Parse.importLocalBindName` deleted, DRY), so a bound package's name always equals its
  last-path-element/qualifier and the parse-time check can never mis-name a used import. Fixtures:
  `import_bare_pkgname_mismatch` (expected.err, cue-shaped) + `import_qualifier_pkgname_rescue`
  (`:bar` rescues, byte-identical to cue). See implementation-log 2026-07-06.

Emitter (`parseDeps`/`renderDepsBlock`) canonical form re-checked against the committed
byte-identical-to-`cue`-v0.16.1 fixtures (tab indent, `{v: "…"}` shape, ascending key sort) — SOUND;
not re-run against the live registry (offline gate). Guards: `collectReferencedHeads` fully
enumerated (no `Value` catch-all); `hasTopLevelField`'s `_` is a Bool probe (allowed); totality
holds (all new scanners fuel-bounded, no `partial def`); `check-comments` green.

**Phase B — placement CLEAN, no refactor warranted.** `mod get` machinery is coherently homed in
`ModCmd` (sibling to `mod tidy`); `Oci.tagsListUrl` sits with `manifestUrl` in the OCI URL family;
`collectReferencedHeads`/`unusedImports` sit in `Parse` immediately after the mirror
`applyBuiltinAliases`/`importedBuiltinPackages` import machinery. `parseDeps` is the single deps
reader, shared by tidy (`depsFromEntries`) and get (`applyModGet`) — no new duplication. The only
open architecture item is the pre-existing AUD-B5 (re-affirmed above). No dead code; graph stays
acyclic/layered. No inline Phase-B change.
  <!-- RETRACTED: AUD-B5 has since landed (Module.bfsRequirementGraphAux); no open architecture
       item remains from this batch. -->


### 2026-07-04 Phase A audit findings (batch `dfdd1ab..HEAD`: list-slice / interp-typing / byte-escapes)

Batch verdict: all three code changes SOUND. A4 reconciliation clean (STRUCT-EQ-LEAF-TYPESENSE
divergence row + `numeric/equality_expressions` fixtures present and match code; PRIM-FLOAT-PARSED
still open; ARCH-QUOTED-STRIP / GDA-FLOAT-RENDER / BYTES-SLICE-MISSING / BYTE-INTERPOLATION /
BUILTIN-IMPORT-LENIENCY all still tracked, no decay). [Retraction 2026-07-05: PRIM-FLOAT-PARSED
and GDA-FLOAT-RENDER have since LANDED — see their entries above.] Two LOW findings:

- **INTERP-STRUCT-PATTERN-DEFER (LOW — correctness/consistency). ✅ DONE 2026-07-04.** Collapsed
  both struct arms of `classifyInterpolationPart` (`Kue/EvalBase.lean`) to a single pattern-agnostic
  `.struct _ _ _ _ _ => .nonInterpolatable .struct` — a pattern-bearing struct now ERRORS (bottom)
  like a plain struct instead of over-DEFERring, matching cue's eval type-error on
  `"\({[string]:int})"`. Exhaustiveness preserved (struct covered once). Regression: `out_pattern`
  in `numeric/interpolation_type_error` fixture (`→ _|_`) + native_decide guard in `Tests.lean`
  (pattern-struct → bottom; incomplete-scalar interp still DEFERS). cert-manager canary empty.
- **BYTE-HIGHBYTE-NO-RED-SEED (test-debt / rule-compliance). ✅ SEEDED 2026-07-04 → GRADUATED GREEN
  2026-07-05** (BYTE-ARRAY-REPR rank 0f). Wild seed `testdata/wild/byte-literal-high-byte`
  (`a: '\xff'` → `{ "a": "/w==" }`) was RED against HEAD (kue exported `w78=`, the 2-byte UTF-8 of
  U+00FF); the `Array UInt8` carrier now holds the raw byte 0xFF as one octet, so the seed passes and
  its `.known-red` quarantine was removed. Octal `'\377'` is the same byte, also green.

The **2026-07-04 Phase B audit** (`dfdd1ab..HEAD`; A7 GATES/TOOLING infra-rotation cycle) closed
HEALTHY. Phase A fixes confirmed landed (INTERP-STRUCT-PATTERN-DEFER at `EvalBase.lean:1162`;
BYTE-HIGHBYTE seed tracked). PART 1: the three String-backed-bytes items consolidate under one
core-type fix-slice **BYTE-ARRAY-REPR (rank 0f, MEDIUM)** — `Array UInt8` carrier,
folds BYTE-HIGHBYTE, keeps BYTES-SLICE / BYTE-INTERPOLATION as dependents. A7 infra: `check.sh` +
`handle_known_red` DRY (holding across both gates) + strict-xfail + realworld + test-health all
SOUND; seed hygiene PASS (24 wild, 2 `.known-red`, both tracked+filed); FixturePorts (generated,
exempt) not unmanageable. Architecture CLEAN: graph acyclic/layered, list-slice desugar no layer
blur. No inline code change (all findings non-trivial). Periodic passes: plan-hygiene/test-org NOT
due, perf-guide current, resilience/retro APPROACHING. **The 2026-07-04 two-phase audit is COMPLETE.**

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

The **2026-07-04 Phase B audit** (`a8d07b7..HEAD` + whole-graph; A7 infra-rotation cycle) closed
with the module graph HEALTHY and TWO new fix-slices filed. A4: both Phase A fixes verified landed
IN CODE (`stripFieldQuoting` wired at both seams post-`checkLetFieldShadow`; `mapRefsValueWithFuel`
catch-all enumerated) — neither decayed. Architecture verdicts: the `mapRefsValueWithFuel` unified
walker is GOOD reuse (AD4-1 leaf-differs shape, not the DRY-1 trap); file-scoped imports' NUL-sep
synthetic label + shadow-aware rewrite is CLEAN, Module/Resolve boundary intact; `Field.quoted` +
strip-walk is SOUND but carries an unenforced "must-strip" invariant → filed **ARCH-QUOTED-STRIP**
(rank 0c — DONE 2026-07-05 via the `Quoted`-newtype Option B, not the filed parse-only-quoting
mechanism; see 0c). A7 infra: `check.sh` aggregator + `./lake`/`./lean` caps sound; the
two-gate `.known-red` quarantine is DUPLICATED → filed **GATE-KNOWNRED-DRY** (LOW tail). AUDIT-
STRUCT-EQ re-scoped (split; see rank 0b). No inline code change (all findings non-trivial). Periodic
passes: test-org/plan-hygiene/perf-guide NOT due; resilience/retro APPROACHING (flagged, not
overdue). The **2026-07-04 two-phase audit is now COMPLETE.**

The **2026-07-05 two-phase audit** (bytes/mvs/mod-tidy batch `88f02a8..`) is COMPLETE. Phase A
(`f9e5ae6`) filed AUD-A1..A4 to the log; Phase B RESOLVED all four in code (unlike prior phases,
this one refactored): AUD-A3 DRY (`mainPathConflict : Option String`, `solveChecked` reuses it,
`0202aa5`); AUD-A4 illegal-states (`cueSumRows` folds over fetched nodes so every row carries its
`h1` — can't-happen drop erased, `ecbe8ac`); AUD-A1 unused simp args (`ace8898`); AUD-A2
convention-migration (timeless-comment sweep of ~27 sites + `scripts/check-comments.sh` grep gate
over `Kue/**/*.lean`, `17f9f02`). One NEW finding resolved inline — AUD-B1: `Mvs.solveMany` was
dead/untested speculative surface, now pinned by `mvs_multi_root_pins_each_and_sorts_shared`.
Architecture verdicts clean: `ModCmd` carve from `Module` has no back-coupling/cycle; `ModCmd`/`Mvs`
`partial`-free (fuel-bounded); mod-tidy fixtures consistent + gate self-validating (dynamic `h1:`);
byte-carrier change clean (base64 centralized, no String residue). A whole-graph Explore scan filed
three fix-slices (below). Detail: log.

The **2026-07-05 (batch-5) two-phase audit** (`7b6e66f..e10d282`: ARCH-QUOTED-STRIP plan 0c,
PRIM-FLOAT-PARSED plan 0e) is COMPLETE — **BOTH PHASES CLEAN, zero new fix-slices**. Phase A
hard-verified the two designated high-value points: the inert `BEq Quoted := ⟨fun _ _ => true⟩`
is SAFE (Value/Field derive only `Repr, BEq` — no `DecidableEq`/`LawfulBEq` to contradict it; the
sole quoting readers `letBinderLabel`/`collidableFieldLabel` read `field.quoted.value` directly,
never via `BEq`; `valueDigest` already omitted quoted so BEq/digest now consistent by construction;
`Coe Bool Quoted` one-directional, no surprising elaboration), and `mkFloatText`'s
`.getD (intDecimal 0)` fallback is UNREACHABLE (all 10 sites feed lexer- or own-formatter text; no
unvalidated string reaches it → no masked-`0` bug, no wild fixture). No new `Value` catch-all;
`check-comments` green; convention migrated with its surface. Phase B verified `DecimalValue`
above `Prim` is coherent (no forward-ref), `mkFloatText` is the SOLE float route (only raw `.float`
is inside it + an identity passthrough), and no dead code from the `stripFieldQuoting` deletion
(`builtinAliasFuel` still consumed by `canonicalizeBuiltinCalls`). AUD-B2/B4 re-verified STILL OPEN
+ correctly scoped. Detail: log.

The **2026-07-05 (batch-4) two-phase audit** (`6012a8e..41dbe9e`: AUD-B3 enumeration,
STRUCT-EQ half-2, NESTED-DISJ-MARK reframe) is COMPLETE — **BOTH PHASES CLEAN, zero new
fix-slices** (a valid clean-audit outcome, no work invented). Phase A verified
`classifyScalarOperand` + `normalizeFieldOrder` each enumerate all 29 `Value` constructors
with no `Value` catch-all (class-enum catch-alls permitted), the new tests carry
over-collapse + negative guards (not happy-path), and the timeless-comment gate is green.
Phase B verified `normalizeFieldOrder` placement (colocated with its sole consumer
`dedupAlternatives`), no duplication with `canonicalizeFields`/`conjMemberLe`, and the
coarse `eqUpToFieldOrder` confinement leak-proof (used only in the dedup path; global `BEq`
untouched for cycle detection). AUD-B2/B4 re-verified STILL OPEN + correctly scoped. Detail: log.

The **2026-07-05 (leg4/float/import batch) two-phase audit** (`6eafcf5..HEAD`:
GDA-FLOAT-RENDER `7996477`, BUILTIN-IMPORT-LENIENCY `1f292a8`, B3d-6b-leg4 `33ca159`,
consolidation `3f0f378`) is COMPLETE — **Phase A CLEAN (zero fix-slices), Phase B ONE LOW
finding filed (AUD-B5, deferred with tradeoff)**. A4 (audit-the-last-audit): the batch-4
Phase-B filings AUD-B2 (modtidy zip source) and AUD-B4 (`textBytes` in-place note) landed in
this batch's consolidation commit `3f0f378` — VERIFIED (`scripts/gen-modtidy-fixtures.py`
regenerates the five zips from readable `src/` trees; the `textBytes` rationale note is at the
def in `Kue/Value.lean`). Both correctly DISCHARGED.

Phase A hard-verified the four designated high-value points against real call sites:
- **Float apd rendering** — `floatApdForm` parses EVERY float `text` the lexer can emit
  (lexer normalizes the exponent to lowercase `e` with an explicit sign and strips a leading
  `+`, so the lowercase-`e`-only split is sound) AND every eval-produced float text
  (`formatFiniteDecimal`/`divideDecimalRational?`/`negateFloatText` emit only plain
  `[-]W[.F]`, never scientific). The `1e-6`/`1e-7` plain↔scientific boundary is correct
  (`exponent ≤ 0 ∧ adjusted ≥ −6`). Cross-checked `cue` on `100.0`/`10.0e1`/`250e-2`/`0.0`/
  `1e2`/`1e-7` across JSON/YAML/cue — all three surfaces byte-match.
- **Import enforcement** — no un-imported builtin path slips the gate: `applyBuiltinAliases`
  runs at BOTH parse entrypoints (`parseDocument`, `parseDocumentFile`), per-file; no
  `.builtinCall` for a qualified name is constructed after the gate except the eval-time
  `json/yaml.Marshal` re-defer (which only fires for a call that already passed the gate);
  the only no-call stdlib constants are `list.Ascending/Descending/Comparer`, all routed
  through the import-checked `resolveBuiltinConstSelector`. No legitimately-imported builtin
  is wrongly rejected (aliased + unaliased call and constant forms all resolve; gate keys off
  the canonicalized package name against `importedBuiltinPackages`).
- **leg-4 override** — a currently-resolving lenient load is never regressed: a
  declared-but-unvendored dep makes `buildDiskGraphAux` error → `solveVersionOverride` returns
  an EMPTY override (per-hop fallback); `solveChecked` errors ONLY on a dep requiring the main
  module's OWN path (the genuine cue-reject case), never on a benign graph. `ModuleContext.selected`
  is threaded through all three construction sites (`loadPackageDir`, `loadFileBound`, the
  recursive `depCtx`) — no hop drops it into the `[]` default.
- **Guards** — no swallowing `| _ =>` on a Value-producing match (the `.selector`-arm
  `| _ => .selector (rec' base) label` is a `.ref?` probe inside a fully-enumerated outer
  match, not a dispatch swallow); `gateBuiltinImport`'s `_` is on a `List String` splitOn
  result; `check-comments` green; the import convention migrated with its enforcement.

**Open Phase-B fix-slices (2026-07-05, ranked):**
- **AUD-B5 (LOW) — DONE.** Extracted `Module.bfsRequirementGraphAux` — a generic
  `(nodeOf : α → ModuleVersion) (expand : α → IO (Except String (List α × β))) (fuelExhausted)`
  combinator, structural on `fuel` (⇒ total, no `partial`; `expand` is a leaf callback that never
  recurses, keeping structural-recursion inference intact — the AD4-1 shape). `buildDiskGraphAux`
  (`Kue/Module.lean`, disk-first) and `fetchGraphAux` (`Kue/ModCmd.lean`, registry) are now thin
  call sites; both fuel-exhaustion messages preserved byte-for-byte. Pure refactor — the mod-tidy +
  disk-graph fixtures are the guard; `./scripts/check.sh` green.
- **AUD-B3 (MEDIUM) — DONE (`6012a8e`).** Routed all six Value-producing catch-all sites
  (`evalBoolBinary`/`evalBoolNot`/`evalNumPos`/`evalNumNeg`, plus the same-pattern
  `evalPrimitiveOrdering`/`evalRegexMatch` — converted together per the "convention lands with its
  migration" Law) through one enumerated `classifyScalarOperand : Value -> ScalarOperandClass`
  (no `Value` catch-all; the residual dispatch is now on the finite class enum, like
  `classifyArithOperand`). Strictly behavior-preserving; 14 `native_decide` residual-preservation
  pins added. No grep guard: the compliant fix idiom emits a line `| _, _ => .binary …` matching the
  CLASS enum — syntactically identical to a banned `Value` catch-all (and to `arithmeticDomainResult`),
  so no cheap grep separates compliant from banned. Stays reviewer-enforced.
- **AUD-B2 (LOW) — DONE (2026-07-05).** The five `testdata/ocifetch/modtidy/*.zip` are no longer
  opaque: the file tree each encodes is checked in under `testdata/ocifetch/modtidy/src/<name>/`
  (readable `cue.mod/module.cue` + package `.cue`), regenerated by `scripts/gen-modtidy-fixtures.py`
  (zips each `src/<name>/` → `<name>.zip`), with a `README.md` on regen. Reproducible, not opaque;
  gate stays green (h1 dirhashes are content-derived at run time, so container churn is free).
  Regenerated zips verified content-identical to the originals.
- **AUD-B4 (LOW) — DONE / DOCUMENTED IN PLACE (2026-07-05).** `Value.textBytes` (`Kue/Value.lean`)
  is test-only but stays in core: relocating it would cost seven new imports across the seven test
  modules that use it (they share no common test-support import) for a one-line `Value`-domain
  constructor helper — a move that ripples awkwardly for zero core benefit. Left in place with a
  test-support-in-core rationale note at the def (the lower-churn correct option per the AUD-B4 brief).

The **2026-07-04 Phase A audit** (`a8d07b7..HEAD`: file-scoped imports `53fe3cc`, let/alias
no-shadow forward `e20af9a` + reverse `f128600`) found ONE HIGH regression and ONE LOW latent —
filed as AUDIT-QUOTED-BEQ (rank 0) and AUDIT-RESOLVE-CATCHALL (LOW tail) above; Phase B owed. A4:
the 2026-07-03 audit was CLEAN (zero fix-slices), nothing to verify-landed — confirmed. Verified
CLEAN: the mechanical ~2,500-site `, false` `Tests/` pass is behavior-preserving (Lean's
type-directed `⟨⟩` elaboration precludes a silent mis-target; `, false` makes the pre-existing
`quoted` default explicit); `Field.quoted` is set-once at the genuine quoted parse site
(`parseQuotedLabelField`, `Parse.lean:1664`) and read only by `collidableFieldLabel` (the leak into
`BEq` is the AUDIT-QUOTED-BEQ finding, not a second bug); the unified `checkLetFieldShadow` /
predicate-parameterised `collectMemberLabels` is correct both directions, DRY, and readable (its
`| _ => []` is a `List String` COLLECTOR terminal, not a Value-dispatch), with real over-rejection
accept-guards (quoted/def/dynamic/for-var/comprehension-let/incomparable-sibling) and an EMPTY
cert-manager canary; file-scoped imports' `mapRefsValueWithFuel` unification shares every binder
frame and its NUL-separated synthetic labels are uncollidable + `importBinding`-class (non-output)
+ shadow-aware; the `cue-spec-gaps` reverse no-shadow row is CLOSED and matches the code.

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
secret. `Mvs.solve` is WIRED both into `kue mod tidy` (via `Mvs.solveChecked`, the main-pin fix, over a
registry-fetched graph) AND into the IMPORT-RESOLUTION path (B3d-6b-leg4, 2026-07-05: a disk-built
requirement graph governs import version selection — max-of-mins, not per-hop) — no longer a
staged-but-unused primitive.

**Open B3d items (ranked):**
- **B3d-6b — FULLY LANDED 2026-07-05 (all legs).** Legs (1) requirement-graph fetch, (3) `mod tidy`
  command parse + dispatch, (5) `cue.sum` WRITE, and the `Mvs.solve` main-pin fix landed via
  `Kue/ModCmd.lean` + `kue mod tidy` (offline gate `scripts/check-mod-tidy.lean`); leg 4
  (export-path MVS) and leg 2 (`mod get`) landed same-day. **No FILED dependents remain.**
  - **B3d-6b-leg4 — export-path MVS rewiring — LANDED 2026-07-05.** The MVS build list now governs
    the IMPORT-RESOLUTION path (`Module.lean`'s mutual loader): at load entry `solveVersionOverride`
    builds the requirement graph OFF DISK (`buildDiskRequirementGraph` — root-threaded BFS over each
    dep's on-disk `cue.mod/module.cue` via `locateModuleDir`+`readModuleInfo`, total, no network),
    runs `Mvs.solveChecked`, and threads the build-list projection (bare path → version) through the
    new `ModuleContext.selected` field; `resolveImportTarget` overrides each cross-module import's
    version with the selected one. Cross-module selection is now max-of-mins, not per-hop. On-disk
    diamond fixture `testdata/modules/crossmod_diamond` (`a`→c@v0.1.0, `b`→c@v0.2.0; MVS picks
    v0.2.0 for both) — red-first proved per-hop gave `fromA`=v0.1.0, the fix gives v0.2.0 both,
    cross-checked byte-identical against cue v0.16.1. **Canary-safe by construction:** a
    single-version graph selects each path's only version (override is a no-op), and a non-buildable
    graph falls back to an EMPTY override (per-hop, today's behavior) — the cert-manager canary
    re-ran byte-identical. 7 new `native_decide` tests pin diamond/3-deep/single/main-conflict
    selection + `selectedVersion`. Divergence CLOSED in `compat-assumptions.md`. The flat-requirement
    *enforcement* (cue requires every transitive dep pinned in main) is deliberately NOT in scope —
    kue discovers deps transitively; that stays a separate, bounded leniency.
  - **B3d-6b-leg2 — `mod get` + tags/list — LANDED 2026-07-05.** `kue mod get <module>[@version]`
    adds/updates a dependency in `cue.mod/module.cue`. Three pure capabilities + one IO edge, all
    in `Kue/ModCmd.lean`: (a) the **deps-block emitter** — parse the existing module.cue for its
    deps, merge the target (keyed on module path + major, so distinct majors coexist), re-render
    ONLY the `deps` block in cue's canonical tab-indented form via a string/brace-aware textual
    excision that preserves all non-deps content (illegal-states-unrepresentable: a present-but-
    unlocatable deps block ERRORS rather than emit a conflicting file); (b) **tag "latest"
    resolution** — bare/`@latest`/`@vN`/`@vN.M` filter the registry `.../tags/list` to valid
    non-prerelease semver matching the constraint and take the max (`Semver.maxVersion`); (c) the
    pure driver `modGetResolveAndApply` (source + arg + in-memory tags → new source), so the whole
    pipeline is `native_decide`-checkable OFFLINE. Byte-identical to `cue mod get` v0.16.1 for the
    canonical (block-form) add. Divergence: kue preserves non-deps content verbatim where cue
    reformats the whole file — spec-silent, recorded in `cue-spec-gaps.md`. 40 `native_decide`
    tests (`Tests/ModCmdTests.lean`) + CLI parse pins (`Tests/CliTests.lean`). The read-only
    tags/list GET (`ociListTags`) is production-only; no gate depends on the network.
- **B3d-A2** (test-strength, LOW) — DONE 2026-07-05. Pinned every adversarial DEFLATE/ZIP reject
  branch to its EXACT typed error (not just "is error"), so a wrong branch firing fails the pin.
  14 new `native_decide` theorems in `Tests/ZipTests.lean`: 9 DEFLATE (STORED LEN/NLEN, dist-too-
  far-back, invalid dist code, litlen-symbol-286-OOR, dynamic bad-CLC, dynamic invalid-litlen,
  dynamic dist-symbol-30-OOR, block fuel-exhaustion, + the prior BTYPE=3) and 5 ZIP (short/no-EOCD,
  bad CD sig, unsupported method, bad local sig, CRC mismatch, size mismatch). Malformed DEFLATE
  streams bit-crafted + cross-checked against Python `zlib` (raw, wbits=-15); ZIPs are single-field
  mutations of `storedZip`. NO soundness bug: every branch already rejected correctly (the fuel
  guard fires on a truncated 1-bit-literal stream — proven no-hang). Distance-symbol-30 and
  literal-symbol-286 are reachable only via a dynamic table / the fixed table's over-wide code
  space; the block-loop fuel guard and the dynamic-length-underflow guard are defensive-unreachable
  by construction (each block/RLE-step consumes ≥1 unit against a matched bound) and left un-pinned.
- **B3d-B1 — DONE 2026-07-10 (type-leverage).** The `cue.sum` `h1:` string is now the `Kue.Hash1`
  newtype threaded produce→accumulate→format/parse→verify, so a raw string can no longer reach a
  digest position; the main-module node (which never had a digest) was dropped from the fetched-node
  table entirely rather than carrying a sentinel — `runTidy` supplies its graph edge directly. The
  OCI `Descriptor.digest` (`sha256:<hex>`) was left a bare `String`: a distinct concern with no
  second consumer, so a newtype there would be ceremony.
- **`Mvs.solve` main-pin — DONE 2026-07-05.** `Mvs.solveChecked` surfaces the cue-panic case
  (a dependency requiring a higher version of the main module's own path) as a typed error
  instead of a silent pin; `mod tidy` calls it. 4 native_decide theorems.
- **`Kue/ModuleFetch.lean` carve — DONE 2026-07-05 (as `Kue/ModCmd.lean`).** B3d-6b's command
  layer (transitive graph fetch + cue.sum write + `mod tidy` orchestration) was carved into a new
  `Kue/ModCmd.lean` rather than growing `Module.lean` past the ~200-line trigger; `Module.lean`
  keeps import resolution + the shared fetch/cache primitives.
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
  [`implementation-log.md`](implementation-log.md)
  (chronological, one entry per commit) and `git log`. Every audit batch and design spike
  is recorded there — this plan holds only the live roadmap.
- **Spec-conformance fix backlog (authoritative):**
  [`spec-conformance-audit.md`](spec-conformance-audit.md) § Genuinely-open ranked backlog.
- **CUE-divergence record:**
  [`cue-divergences.md`](cue-divergences.md).
- **CUE spec-gap record:**
  [`cue-spec-gaps.md`](cue-spec-gaps.md).
- **Decisions:** [`../decisions/`](../decisions/) (compatibility target,
  correctness-over-perf, numeric model, oracle-as-data-source, registry transport).
- **Slice loop + audit cadence:** [`../guides/slice-loop.md`](../guides/slice-loop.md).
- **Performance guide:** [`../guides/kue-performance.md`](../guides/kue-performance.md).
- **Status page (human-facing, served):** [`../../www/index.html`](../../www/index.html) —
  single human-scannable status page, OUTSIDE the agent design-record; refreshed on
  plan-hygiene passes.
- **CUE semantics reference:** [`../vendor/cue-language-guide.md`](../vendor/cue-language-guide.md);
  [`architecture.md`](architecture.md) + [`compat-assumptions.md`](compat-assumptions.md).
- **Latest session state / next step:** the most recent breadcrumb in
  [`../scratch/`](../scratch/).
