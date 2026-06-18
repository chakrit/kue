# Kue Plan

The live implementation roadmap. Kept small, current, and actionable — one focused slice
at a time. The full record of completed slices lives in
[`../reference/implementation-log.md`](../reference/implementation-log.md), retained for
verification; this file holds only where we are and what's next.

## North Star

Kue targets **CUE v0.15 semantics, done correctly**. Where the official `cue` v0.15
binary is buggy, Kue should implement the *correct* behavior, not replicate the bug. The
compatibility target is the language as specified, not bug-for-bug parity with the
reference implementation. See
[`../decisions/2026-06-14-cue-compatibility-target.md`](../decisions/2026-06-14-cue-compatibility-target.md).

## Working Principles

- Use TDD where behavior is testable: write theorem checks or executable examples
  before implementation.
- Keep the semantic model simple before optimizing representation.
- Prefer total functions and explicit semantic values over hidden host-language
  failure.
- Avoid dependencies until they clearly remove more complexity than they add.
- Keep each commit small enough to review, revert, or extend safely. One slice per
  commit; the commit subject mirrors the slice title.

## Current Focus — data-driven roadmap to replace `cue` for prod9/infra (2026-06-16)

**Real goal (chakrit):** make kue able to evaluate PRODIGY9's actual infra CUE so it can
replace `cue`, mostly for `prod9/infra` and related repos — as fast as possible.

A read-only gap analysis ran kue against 92 sampled real files across `prod9/infra`,
`infra-defs`, `infra-stage9`. Result: **kue evaluates ZERO real manifest-producing files
today; 85/92 fail at the *parser*** on two ubiquitous-but-trivial forms the fixture suite
never exercised (so the earlier "parser is feature-complete" read was wrong — it only
checked semantic-core features). Slices, in evidence-ranked order (cheap independent wins
first, the big import subsystem last because it gates the real workflow):

1. **B1 — colon-shorthand nested fields** (`a: b: c: 1`). Pure parser; desugar chained
   labels to nested structs. Unblocks the single largest tranche of files. **DONE**
   (commit pending) — `parseFieldValue` recurses through the same `parsedFieldsValue`
   builder the brace path uses, so `a: b: 1` builds the identical AST to `a: {b: 1}`
   (pinned by `parseSameValue` theorems). Inner labels: identifiers, definitions, quoted
   strings (incl. dotted `"prodigy9.co/app"`), `(expr)` dynamic; optional `?`/`!` markers.
2. **B2 — value/field aliases** (`X=expr`, esp. `#Def: Self={…}` self-reference; 50/92
   files). Parser + resolver binding so `Self.#f` resolves. **DONE** — value-position
   aliases parse via `valueAliasHead?` (`Ident =`, distinguished from `==`); a struct
   alias prepends a `.thisStruct` `let`-binding, and `Self.field` resolves as a same-struct
   sibling ref via a dedicated `selector (refId …)` eval arm (inherits the cycle guard).
   Self-reference within a def resolves; post-unification re-resolution and bare `Self`
   deferred (compat-assumptions). Cleared the `=` parse barrier across real infra-defs
   (28/32 files now parse+evaluate; the remaining 4 are B4/B3).
3. **B4 — multiline strings** (`"""…"""`, bytes `'''…'''`; previously → `_|_`). **DONE** —
   the bug was in *parse*, not eval: `parsePrimaryAtom` had no `"""`/`'''` arm, so the lone
   `"` arm read `""` as an empty string and mis-parsed the rest. New `parsePrimaryAtom` arms
   `'"' :: '"' :: '"'` / `'\'' :: '\'' :: '\''` route to `parseMultilineOpen`, which (a)
   finds the closing line's indentation via the total `multilineStripPrefix?` pre-scan,
   (b) requires a newline after the opening delimiter (content-on-opening-line rejected),
   then (c) runs `parseMultilineBody` — an interpolation-aware pass that strips the prefix
   at each line start (non-blank lines lacking it → "invalid whitespace"; fully-blank lines
   exempt), joins lines with `\n`, drops the trailing pre-closing newline, and reuses the
   existing `\(expr)`/escape machinery. `'''` produces `.prim (.bytes …)`; bytes
   interpolation is deferred (rejected at parse — see compat-assumptions). Oracle-matched on
   basic/indented-dedent/interpolation/empty/cert/no-indent/blank-line/escape and both error
   cases. Unblocked the parser on all four multiline-using prod9 files; `infra/apps/argocd.cue`
   now parses+evaluates to exit 0 (the other three hit separate later gaps — open-list
   `[...]` and non-string label patterns — not the `"""` barrier).
4. **B6 — encoding builtins** `base64.Encode`, `json.Marshal` (load-bearing inside
   `#Secret`/`#ConfigMap`). **DONE** — `base64.Encode(null, …)` is standard padded
   base64 (RFC 4648) over the UTF-8 bytes of a string or bytes value; a non-null
   encoding selector is bottom (`cue` errors "unsupported encoding"). `json.Marshal`
   manifests its arg then serializes via the new **reusable** `Kue/Json.lean`
   (`manifestToJson : ManifestValue → String`, total mutual recursion): compact (`,`/`:`,
   no spaces), **source-order keys (NOT sorted)**, floats rendered from their exact
   stored decimal text verbatim (`1.50`→`"1.50"`), bytes→base64 JSON string, control
   chars `<0x20` escaped (`\b\f\n\r\t`/`\uXXXX`), `<>&/` and non-ASCII passed through
   (cue disables Go's HTML escaping). Incomplete/contradictory ⇒ bottom; still-pending
   refs (`.ref`/`.selector`/`.builtinCall`/…) preserved as `.builtinCall`. The
   docker-config chain `base64.Encode(null, json.Marshal({auths: …}))` evaluates
   byte-for-byte against `cue`.
5. **B5 — manifest output**: a YAML/JSON serializer over `Kue/Manifest.lean` + a
   `cue export`-style CLI mode. **DONE** — `kue export [--out yaml|json] [file]` (default
   `--out json`, reads file arg or stdin) manifests then serializes; on a real k8s
   Deployment `kue export --out yaml`/`--out json` are **byte-identical to `cue export`**.
   New `Kue/Yaml.lean` (`manifestToYaml`, total mutual recursion) matches `cue`'s go-yaml
   emitter on the infra core: 2-space block nesting, `- ` sequences (incl. `- - 1`), `|-`
   block scalars for newline strings, empty `{}`/`[]`, and the scalar-quoting rules cue
   actually emits — bare when safe; double-quoted when resolver-ambiguous (YAML 1.1
   bool/null tokens `y/n/t/f/yes/no/on/off/true/false/null/~`, numeric-looking); single-
   quoted when structurally unsafe (leading indicator, `: `, ` #`, trailing `:`, all/edge
   space). Pretty-JSON (`valueToJsonPretty`, 4-space, source-order) added alongside B6's
   compact `manifestToJson`. `yaml.Marshal` builtin routes via the `yaml.` dotted dispatch
   reusing the shared `unresolvedOrBottom`. **No `---` multi-doc**: a top-level list exports
   as a single YAML sequence (oracle-confirmed — cue uses `---` only via `yaml.MarshalStream`,
   deferred). `-e`/`--expression` selection deferred (documented). 33 `YamlTests.lean`
   `native_decide` theorems + 4 oracle-matched `testdata/export/` CLI fixtures
   (`deployment` yaml+json, `scalars`, `shapes`).
6. **B3 — module/import resolution** (the big one, LAST): `cue.mod` deps, loading
   `prodigy9.co/defs*` packages from disk, cross-package symbols, multi-file package
   merge. Gates every real `infra/apps/*.cue`. "Packages last" = packages are the final
   and largest blocker, NOT optional. Sub-sliced B3a–B3d (plan:
   `docs/notes/2026-06-17-b3-import-resolution-plan.md`).
   - **B3a — minimal in-module import, end-to-end (DONE, 2026-06-17).** `cue.mod` discovery
     (`findModuleRoot` walks parents; `module:` parsed via the reused parser), a collecting
     import parser (`parseImportClauses` → `List Import`, threaded into a `ParsedFile`
     record), `Kue/Module.lean` resolving in-module paths to dirs, multi-file meet-merge
     (`mergeSourceValues`), transitive in-module loads with a visited-set cycle guard, and
     binding each loaded package as a **hidden** synthetic top-level field under its
     declared name (or alias) so `pkg.#Sym` resolves through the existing
     `.selector (.refId …)` path — no new eval machinery. IO sits behind `loadFileBound`;
     `Eval`/`Resolve` stay pure. Builtin stdlib imports (`strings`/`list`/`math`/
     `encoding/{base64,json,yaml}`) are skipped by the loader (`isBuiltinImport`), leaving
     the call-form dispatch untouched. File-mode + `export` file-mode route through the
     loader; stdin and multi-file CLI paths unchanged.
   - **B3b — aliased imports + nested paths + grouped-import robustness.** Alias is
     already retained/bound (basic case works); harden the import-clause parser (comments
     inside groups, trailing commas, blank-line separators) and nested-path corner cases.
     Real prod9 files parsed their grouped imports fine in the B3c spot-check, so the
     syntax-edge hardening stays **deferred** until a real file actually needs it.
   - **B3c — cross-module / vendored (DONE, 2026-06-17, the real prod9 unlock).** `deps`
     read from `cue.mod/module.cue` (`parseDeps`: each `"<modpath>@<major>": {v}` entry →
     `Dep{modPath, version}`, `@major` stripped); an import path mapped to its owning dep
     by **longest module-path prefix** (`resolveCrossModule`). A **declared dependency wins
     over the in-module interpretation** (`prodigy9.co` owns `prodigy9.co/defs@v0` as a dep,
     so `prodigy9.co/defs` is the dependency module, not an `infra/defs/` subdir) — this was
     the keystone fix that made `defs.#X` resolve. Module located read-only in priority
     order: vendored `cue.mod/pkg/<modpath>[@ver]/` then extract cache
     `<cacheRoot>/mod/extract/<modpath>@<ver>/` (`cacheRoot` honors `$CUE_CACHE_DIR` →
     `$XDG_CACHE_HOME/cue` → `~/Library/Caches/cue`). Subpath mapped within that root;
     reuses B3a's `loadPackage` (multi-file merge, transitive loads, visited-set) — **no new
     eval machinery**. A cross-module import inside a loaded module hops to *that* module's
     own `ModuleContext` (its root + deps), so transitive cross-module resolves recursively.
     Missing-on-disk → clean deferred error (registry fetch is B3d). IO stays in
     `Module.lean`; `Eval`/`Resolve` pure.
     - **Real-file spot-check (READ-ONLY, prod9/infra):** `defs.#X` now **resolves** — kue
       descends into the real `~/Library/Caches/cue/mod/extract/prodigy9.co/defs@v0.3.19/`
       and loads its files. Import resolution is no longer the blocker. The remaining
       distance to "replace cue for infra" is **parser gaps**, ranked by how many of the 15
       `infra/apps/*.cue` they block:
       1. ~~**`let` declarations**~~ — **NOT A GAP (diagnosed 2026-06-17).** `let` was already
          fully implemented (parse + scope + non-output). The breadcrumb's "unexpected `='`
          at `let nsp = …`" was a *mis-attributed* error: `parseField` committed a `[`-led
          struct member to the `[label]: value` pattern form with no fallback, so the `[...]`
          inside the `let` RHS struct failed and the parser backtracked to mis-report the
          error at the `let`'s `=`. **The real blocker was the open-list `[...]` embedding.**
       2. **Open-list `[...]` embedding.** ✅ **Parse landed 2026-06-17** — a `[`-led struct
          member now falls back to `parseEmbedding` when it isn't a valid pattern, so `[...]`
          and `[1,2,3]` parse as list embeddings. **All 15/15 `infra/apps/*.cue` now parse +
          locally evaluate** (was ~3/15). **Eval semantics still DEFERRED (now the #1
          blocker):** CUE allows a list embedded in a struct that has *no regular exported
          fields* (only `#hidden`/`_`/`let`) — the value emits as the list while definitions
          stay selectable; with any regular field present it conflicts. In prod9 the
          `let`-bound `#Basics & {…[...]}` values are only ever *selected into* (`.#name`,
          `.#out`), never emitted whole, so cue's **laziness** never forces the latent
          struct/list conflict. kue is eager and currently `meet(struct, list) = ⊥`. Closing
          this needs the embedding rule (hidden-only struct + list embed) and/or lazy
          selection — tracked as the next slice.
       3. Then the deeper semantic gaps (closedness enforcement under
          import/unification, bare hidden-field references). **`[string]:` kind/type label
          patterns ✅ DONE 2026-06-17** — see item below.
     - **Design boundary (kue more lenient than cue, not a divergence):** kue reads the
       *intermediate* module's `deps` for a transitive cross-module hop; `cue` requires every
       transitive dep pinned **flat** in the *main* module's `deps` (MVS graph). Both resolve
       when the artifact is on disk; the transitive fixture pins flat to stay oracle-clean.
   - **B3d — registry fetch + version resolution (LAST, deferred per chakrit).** OCI fetch
     from `CUE_REGISTRY`, MVS version solving, `cue.sum` verification. B3c assumes the
     artifact is already on disk (vendor or cache); B3d removes that assumption.

Note: `strings.*`/`list.*` work *without* an `import` because kue hardcodes those
namespaces and ignores the `import` clause — this masks the absence of any general
import/module mechanism (B3). Remaining stdlib builtins (`strings.Trim*`/`Runes`/…,
`list.Sort`/`SortStable`, unicode case folding) stay parked — infra doesn't need them.
Full gap report: agent run 2026-06-16; reproduce by running kue against the prod9 modules.

**AUDIT COMPLETE — parser+alias+multiline batch
(`0795530`/`7ec51a4`/`f6c18b5`/`804f1ca`/`d1a5e35`).** The `/ace-audit` depth pass landed
2026-06-17 after three transient-500 false starts. Verdict: **no Violations, no inline
fixes needed — the batch is clean.** Findings folded as fix-slices below ("Audit
Fix-Slices (parser+alias+multiline family, audit 2026-06-17)"). Headline: `.thisStruct`
exhaustiveness is sound at every Value-matching site; B1 colon-shorthand is provably
AST-identical to the brace form across all inner-label forms; B4 multiline is total and
correct; parser positions have no off-by-one; the three B2 deferred boundaries are real
and correctly documented.

## Audit Fix-Slices (Field-struct + package-dir family — Phase A + B, audit 2026-06-17 #8)

Combined Phase A (code-quality) + Phase B (architecture), type-system-first lens, over the
two slices since the last light audit `25d66a7`: `be2e987` (`Field` tuple → `structure`)
and `1595d2a` (package-dir merge at the entry). Verify gate green at audit time: `lake
build` 86 jobs, `check-fixtures.sh` "fixture pairs ok". Oracle: `cue` v0.16.1
(`/Users/chakrit/go/bin/cue`). No code findings warranted an inline change (see Findings);
this pass changed only `plan.md`.

### Headline verdicts (all CLEAR)

- **`Field`→structure derived-`BEq` equivalence — verdict: `Value` `==` byte-identical, by
  construction.** `structure Field` declares `label : String; fieldClass : FieldClass;
  value : Value` — the exact components and order of the former `String × FieldClass ×
  Value` tuple. Lean's derived structure `BEq` compares fields in declaration order with
  short-circuit `&&`, identical to the tuple's derived `BEq` (`.fst == .fst && .snd.fst ==
  … && .snd.snd == …`): same components, same order, same underlying `FieldClass`/`Value`
  instances. So meet/dedup/manifest equality is unchanged — confirmed *why*, not merely
  that fixtures pass. No instance widened or narrowed: still `BEq` (not `DecidableEq`) on
  `Value` (the deliberate kernel-perf carve-out; `native_decide` pins behavior), `Repr`
  present, nothing new (`Hashable`/`Ord`) that a downstream `==`/sort/map could silently
  pick up. The mutual block was forced purely definitionally (`structure Field` references
  `Value`, `Value`'s struct constructors carry `List Field`); constructor signatures'
  meaning is unchanged — `List Field` stands where the tuple list stood and every one of
  the ~70 sites migrated to `.label`/`.fieldClass`/`.value`/`⟨…⟩`.
- **Package-dir merge (`loadPackageDir`/`loadEntry`) — verdict: correct, no single-file
  regression.** `loadEntry` branches on `FilePath.isDir`: a dir routes to `loadPackageDir`
  (discover module root → `readModuleInfo` → `loadPackage` on the dir), a file routes to
  `loadFileBound` *unchanged*. `loadPackageDir` reuses `loadPackage` verbatim — no
  duplicated merge — so package-name consistency (`foldPackageNames`→`mergePackageNames`),
  sibling meet-merge, and per-file import binding (B3a/B3c) all flow through the same
  machinery imported packages use; `-e` selection applies post-merge in Main. Oracle-checked
  byte-for-byte: `kue export --out json apps` == `cue export --out json ./apps` on the
  `package_dir` fixture (the `subpaths` harness exercises exactly the dir branch). Edge
  cases: empty dir / no `cue.mod` → clean `"no cue.mod/module.cue found…"`; mixed package
  names → clean `"package merge error: conflicting package names"` (cue errors too, exit 1).
  **No single-file/stdin regression**: every `testdata/cue` fixture is a lone file → routes
  to `loadFileBound` (a lone file is its own package, merging only itself); all green,
  byte-unchanged. IO stays at the Module boundary; pure core untouched.
- **Layering — verdict: clean, acyclic, base unchanged.** `Value.lean` still imports only
  `Init` — the `Field`/`Value` mutual block added NO import, so the base module stays the
  base. `Module → {Parse, Runtime}`, `Main → {Kue, Kue.Cli}`, `Lattice → Value`: no
  back-edge, no cycle. `loadEntry`/`loadPackageDir` are pure-IO additions at the existing
  Module boundary.
- **Alpha-readiness (HEAD) — verdict: RELEASABLE.** Build green (86 jobs), full fixture
  suite green, no half-landed work, no crash on the documented paths. Same alpha bar as
  `…alpha.20260617.3`. The two known gaps are documented and non-blocking for an alpha:
  B3d registry fetch (item 6) and the field-ordering divergence (Finding 1 below) — both
  affect *reach/parity on apps*, not correctness of what already resolves. Fine to cut a
  `.4` from HEAD.

### Findings (ranked)

1. **[MEDIUM — output parity, Phase B; DEEP, not a small fix] `ref & {literal}` field
   ordering diverges from cue.** For `y: base & {c: 3, a: 1}` cue exports `c, a, b` (the RHS
   literal's *own* fields first, in source order, then the referent's remaining fields),
   while kue exports `a, b, c` (left-struct-first). Root cause: `mergeStructFieldsWith`
   (`Lattice.lean:538`) folds `rightFields` into a `some leftFields` base, appending unseen
   right-fields at the tail — so every meet emits `left ∪ (right∖left)`, structurally
   left-first. **Scope = DEEP, not a meet/manifest reorder.** (a) The primitive is the
   single meet merge, called from 8+ sites (struct meet, tail/pattern merge, embeddedList
   decls); flipping its base order churns ordering for *all* meets and most fixtures encode
   the current left-first order. (b) cue's rule is not simply "right-first": field position
   tracks where each label is *first introduced* across conjuncts in evaluation order, with
   a referenced definition contributing its fields at the point of reference — faithful
   replication needs field-introduction *provenance* carried through meet (a per-`Field`
   order key on the `Field` structure + threading it through every merge/manifest site), not
   a one-line fold flip (which would fix `base & {c,a}` but break `{a,b} & {c}` and
   definition-embedding order). Recommend: schedule as its own multi-slice change *after*
   B3d, with a provenance-key design spike first. Affects the dominant `#Def & {…}` prod9
   pattern's exported field order → a real byte-parity blocker for app output, but only on
   apps that already resolve.
2. **[DONE 2026-06-17 — loader-robustness slice] Bare nonexistent-file arg threw uncaught
   IO exception.** Was: `kue export /tmp/missing.cue` printed `uncaught exception: no such
   file or directory`. Fixed by wrapping the `export` file-mode `loadEntry` in `.toBaseIO`
   in `Main.lean` (eval already had it) → clean `kue: cannot read <path>: <reason>` + exit
   1, covering file and missing-directory args (both route through `loadEntry`). Done at
   the IO boundary rather than a `pathExists` guard in `loadFileBound` so the catch also
   covers mid-load read failures (e.g. an unreadable cue.mod), and keeps the pure loader
   read-then-fail. Success paths byte-identical; check-fixtures uses valid paths so no
   regression.

### Re-ranked next-work list — CORRECTED by B3d recon (2026-06-17)

**B3d is NOT needed for prod9 — it is already solved by B3c.** A read-only recon traced
the full `prod9/infra` import closure: everything is in the local cue extract-cache and
resolves OFFLINE (`CUE_OFFLINE=1 cue export ./apps -e …` exits 0; kue's current binary
already loads `defs`/`packs`/`parts`/`attr` and gets *past* import resolution to eval
errors). The deps-less `prodigy9.co/defs` module is harmless — it imports only its own
in-module subpackages, so its empty `deps` table is correct. MVS is trivial here
(single-version-per-module: one dep `defs@v0.3.19`). **No registry fetch, no ghcr auth, no
env escalation to chakrit. Do NOT build a B3d loader/registry slice** — it would attempt
nothing the prod9 goal needs. (The original B3d — populating a cold cache via OCI — stays
genuinely deferred/out-of-scope; cue populates the cache, kue reads it.)

**The actual remaining blocker for real apps to fully export is the EVAL layer**, surfaced
as `conflicting values`/`incomplete value` on real `infra/apps/*.cue` AFTER imports
resolve. **DIAGNOSED 2026-06-17** (breadcrumb
`docs/notes/2026-06-17-realapp-eval-crosspkg-defmeet-diagnosis.md`): real apps now in fact
**TIME OUT** (CPU-bound, 30–40s), and the diagnosis split the gap into TWO independent deep
blockers:

  1. **Cross-package def-meet laziness (correctness).** `pkg.#Def & {use-site}` evaluates
     the def body's own sibling/`Self` self-references *prematurely* — in the imported def's
     frame, before the use-site fields unify in — giving `incomplete value`/`conflicting
     values`; cue resolves it. Minimal repro: `parts.#M: {#name: string; out: #name}` +
     `t1: parts.#M & {#name: "keel"}` → kue `incomplete value: string`, cue `{"out":"keel"}`.
     **Same-package is fine** — the bug is specifically the import boundary. Root cause: the
     2c.2 lazy-conj path (`lazyConjMergedFields`/`conjStructOperand?`) deliberately refuses
     depth>0 operands (the documented safety boundary), and `pkg.#Def` is a depth>0 selector
     into a hidden import binding, so it falls to eval-then-`meet` which collapses the body
     first. DEEP: a safe fix needs a frame-carrying deferral (closure/thunk Value, or a
     selector-into-import special case in the `.conj` arm) so the body unifies with the
     use-site before its depth>0 refs resolve — explicitly out of 2c.2's flat-splice scope.
  2. **Eval fan-out / perf hang (separate).** `defs.#Deployment`/`#ServiceAccount` alone
     burn 30–40s CPU to timeout though their reduced shapes are instant — fan-out scaling
     with def size (the `Self.#components.X` re-eval the `EvalKey` memo comment names).
     Profile-first; deepen memoization or compute sub-structs once per frame.

  Land 1 and 2 as SEPARATE slices; 1 is the gating correctness bug (crispest repro), 2
  gates running full apps to completion. When 1 lands, add `testdata/modules/
  crosspkg_defmeet/` pinning the oracle JSON (no expected-failure fixture mode, so it can't
  land before the fix). Then the field-ordering provenance change (DEEP,
Finding 1 — cue orders `x: ref & {own}` own-fields-first; needs a per-Field provenance key
through meet/manifest; multi-slice + design spike). Cheap lock-in available: a
`testdata/modules/crossmod_nodeps/` fixture pinning the deps-less-module-with-self-import
guarantee (recon §5). Finding 2 (missing-file diagnostic) is a cheap ride-along when
Module.lean is next touched.

**DONE 2026-06-17 (loader-robustness slice).** `testdata/modules/crossmod_nodeps/` landed:
app `example.com/app` deps-on `example.com/lib@v0.1.0`; the lib module has an empty `deps`
table yet imports its OWN `example.com/lib/sub` subpackage, and the app imports both `lib`
and `lib/sub` directly. Self-contained committed `_cache/`; `expected` is the byte-for-byte
`cue export` oracle (v0.16.1). Concrete values only — deliberately avoids the cross-package
def-meet bug (#1 below) so it pins resolution, not eval. Two `native_decide` theorems in
`ModuleTests.lean` pin the app→lib `resolveCrossModule` hop and the lib→sub
`resolveImportSubpath` deps-less hop. Finding 2 (missing-file diagnostic) landed in the same
slice.

## DECISION NEEDED — full real-app export gated on a Value-model fork (recon 2026-06-17)

**RESOLVED 2026-06-18 — chakrit approved frontier #1 (the `Value.closure` churn). The
work plan is the next section, `## Value.closure work plan`. This section stays as the
design-record diagnosis; the "Awaiting chakrit" framing below is superseded.**

Recon (commit after `4e5ccca`; breadcrumb `2026-06-17-realapp-eval-crosspkg-defmeet-diagnosis.md`)
established that the full-real-app-export gap is THREE deep items, none a clean unattended
slice. **Surfaced to chakrit — do NOT implement #1 unilaterally; it's a Value-model design
fork.**

1. **Cross-package def-meet laziness (correctness) — Value.closure FORK, chakrit's call.**
   `parts.#M & {#name:"keel"}` (def from an imported pkg) → kue `incomplete value: string`,
   cue `out:"keel"`. Root cause: `conjStructOperand?` (`Eval.lean:815-830`) has no
   `.selector` arm, so an import-selector conjunct falls to eval-then-`meet`; the def body
   evaluates in the package frame (collapsing `out:#name`→`string`) before the use-site
   `#name:"keel"` unifies; pure `meet` (`Lattice.lean:1026`) can't re-derive it. The ONLY
   fix that unblocks the REAL apps is **(b) an env-carrying `Value.closure (frame) (body)`**
   — the general lazy-cross-frame fix — which REOPENS the "meet is pure / refs opaque to
   meet" invariant the whole 2c family relies on (`Lattice.lean:387`) and touches every
   `Value` consumer (meet/manifest/Format/Json/Yaml/`valueTag` memo hash/BEq) + cycle
   handling (a closure capturing a self-referencing frame is a new cycle shape). The cheap
   **(a)-narrowed** (selector arm that splices only depth-0-ref def bodies) is a clean
   single safe-failure slice BUT provably does NOT unblock the real `#ServiceAccount`/
   `#Deployment` (their bodies have depth>0 cross-package embeds) — fixes a toy fixture,
   manufactures false progress. (c) re-eval-after-meet collapses into (b). **Awaiting
   chakrit: `Value.closure` direction, or a different decomposition?**
2. **Perf hang — RECONNED (profiled), hypothesis OVERTURNED, downstream of #1.** The
   floated "fuel-insensitive selection memo" is **provably UNSOUND** — profiling found 263
   cases where identical `(envIds, visited, value)` yields DIFFERENT results at different
   fuel (fuel-truncation: `fuel=0 → pure value` / cycle `.top`), so `fuel` in `EvalKey`
   (`Eval.lean:781-790`) is LOAD-BEARING; dropping it corrupts values. The named
   `Self.#components.X` shape is ALREADY well-memoized (29 hits). The REAL blowup is
   **exponential frame-id divergence**: `{a: prev, b: prev}` re-pushes the same struct
   under two slots but `pushFrame` (`:799-803`) hands fresh ids → zero sharing → 2^depth
   (synthetic depth-10 → 10,238 evals / 0 hits / 30s). Effective fix = **frame-id sharing
   for structurally-identical re-pushes** (same fields + same parent id-stack → reuse id),
   a separate audit-heavy design (must not violate "independently-built frames never
   falsely share"). **AND the perf path is currently UNREACHABLE on real apps — they error
   at #1 (~0.9s) before the blowup.** So: #1 (closure fork) FIRST; re-profile after; THEN
   frame-id-sharing. Do NOT implement the unsound memo change.
3. **Field-ordering parity (DEEP, Finding 1).** cue orders `ref & {own}` own-fields-first;
   kue left-struct-first (`mergeStructFieldsWith`). Per-`Field` provenance key threaded
   through meet/manifest; multi-slice + design spike. Affects byte-parity on apps that
   already resolve.

Cheap NON-fork work available meanwhile: `testdata/modules/crosspkg_defmeet/` +
`crossmod_nodeps/` regression fixtures (can only land WITH their fix / as offline pins),
Finding 2 (missing-file clean diagnostic in `loadFileBound`), the deferred test-module
splits, and LOW items (embeddedList.decls newtype, EvalOps/Regex extraction).

## Perf B — closure-perf (frame-id sharing + force-memo) — PARTIAL, commit `4dbc62c` (2026-06-18)

Two SOUND, behavior-preserving memos landed (every fixture byte-identical; `fuel` kept in
every key). They are real wins but DO NOT unblock real apps — the dominant real-app cost is on
a third axis (fuel) neither touches. Re-profiled with eval-count + cache-hit instrumentation
(transient `evalCalls`/`cacheHits` in `EvalState`; `evalStructRefsCalls` for pins).

**Landed #1 — canonical frame-id sharing.** `pushFrame` reuses the id of a structurally-
identical earlier push under the same parent id-stack (`FrameKey = (parentIds, fields)`), so the
`EvalKey` (keyed on `env.ids`) hits the memo. SOUND: the key proves the two frames are
contents-equal in identical scope → the id is a canonical NAME, not an allocation token; reuse
can only return the matching evaluation. Parent id-stack load-bearing (identical fields under
different parents = different evals). On the synthetic deep-inline `{a: B, b: B}` (each level
inlines the same body twice — the recon's `{a:prev,b:prev}` shape, but INLINE, which is what
actually re-pushes; a sibling-REF shape was already memoized): **exponential → linear** —
depth 8 `767 → 18` (42×), depth 10 `3071 → 22` (140×), depth 12 `12287 → 26` (472×). Pinned
(`eval_deep_inline_*`).

**Landed #2 — closure-force memo.** `forceClosureWithConjunct` bypassed `EvalKey` entirely, so a
`pkg.#Def` selected/referenced N times re-forced its body N times. Split into a cached wrapper +
`forceClosureWithConjunctCore`, keyed on `ForceKey = (fuel, capturedEnv.ids, body, useOperands)`
— the full pure-function input. `body` carries closed-vs-open state already (producer closes
imported def bodies at capture → constraint (b) satisfied without an extra key field).

**4 soundness pins** (`frame_share_identical`, `frame_no_share_different_fields`,
`frame_no_share_different_parent`, `frame_no_share_closed_vs_open`) + 4 perf/value pins.

### THE REAL BLOCKER — fuel multiplication (re-diagnosed; the recon's frame-id story was
### incomplete). NEXT SLICE, needs its own soundness spike.

Profiled `infra/apps/cert-manager.cue` (read-only, prod9): the value CONVERGES at fuel ~16
(fuel 16 → complete, CORRECT output byte-matching `cue` modulo field-ordering #3; fuel 8/12 →
`incomplete value`). But `evalFuel = 100` re-derives the converged value across 84 wasted levels
at ~1.35×/level → effectively infinite (the full-fuel run was killed at 8 min CPU, never
finished). The two landed memos cut ~30% (fuel 8: `84.5k → 60.3k` evals) but CANNOT touch the
fuel axis: `fuel` is in every memo key and is load-bearing (the 263 fuel-truncation cases —
identical `(env,visited,value)` yields DIFFERENT results at different fuel when fuel RUNS OUT
mid-eval). The tag histogram at fuel 8 confirms diffuse re-eval (`.prim` 13.7k, `.struct` 8.6k,
`.kind` 6.8k, `.conj` 5.1k, `.structComp` 3.6k) — the same subtrees re-derived at many fuel
levels, not one hot site.

**The sound fix (DESIGN — do NOT implement until the spike closes the hole):** *fuel-saturation
caching*. INVARIANT: if evaluating `value` at fuel `f` never hit a `fuel = 0` base case (nor a
cycle-bound `.top`) anywhere in its subtree, the result is fuel-INSENSITIVE — identical at all
fuel ≥ f (more fuel cannot change an eval that did not need it). So track a "saturated" bit per
result (`minFuelReached > 0` in the subtree) and, when saturated, cache the result FUEL-
INDEPENDENTLY (key on `(env.ids, visited, value)` only). On a saturated hit, return it for ANY
higher fuel → the 84 wasted re-derivations collapse to one. This stays sound BECAUSE it keys
apart exactly the 263 truncation cases (those are NOT saturated — they bottomed on fuel). THE
HOLE TO CLOSE IN THE SPIKE: the "saturated" bit must thread through the ENTIRE eval core's
return type (every arm + meet/manifest reached during eval) — high blast radius, and a single
arm that forgets to propagate `unsaturated` upward silently caches a truncated value as
saturated → corruption. This is precisely the "behavior-changing perf hack you cannot guarantee"
the slice brief says to STOP on; it is its own slice with its own TDD (pin: a value that
genuinely differs by fuel must NOT be saturation-cached; a converged value MUST be). Do NOT
fold it into a sharing slice.

**Real-app verdict (HEADLINE):** cert-manager exports the CORRECT value (matches `cue` except
field-order #3) but only reachable at lowered fuel; at production fuel 100 it is still too slow
to be a `cue` drop-in. argocd (larger) not separately re-timed — same fuel-axis wall, worse.
Kue is NOT yet a drop-in `cue` replacement for these apps; the fuel-saturation slice is the gate.

## Value.closure work plan (frontier #1 — chakrit-approved churn, 2026-06-18)

AUTHORITATIVE. Supersedes the "DECISION NEEDED" framing above (kept as design-record).
Goal: `parts.#M & {#name:"keel"}` where `#M` is an imported def → `out:"keel"` (matches
`cue`), via an env-carrying `Value.closure` that defers a def body together with the frame
it must resolve against. Each slice keeps `lake build` + `check-fixtures.sh` green.

### The shape (layering-forced)

`Value` (in `Value.lean`) imports nothing from Kue; `Frame := Nat × List Field` /
`Env := List Frame` are `abbrev`s in `Eval.lean`, far ABOVE `Value`. So a closure CANNOT
carry an Eval `Frame` — that inverts the import graph. Resolution (illegal-states route):
inline the env as plain data the base layer already has —

```
| closure (capturedEnv : List (Nat × List Field)) (body : Value)
```

`List (Nat × List Field)` is *defeq* to Eval's `Env` (both are `abbrev`s over the same
product), so Eval threads `capturedEnv` into `pushFrame`/`env.drop` with zero coercion,
yet `Value.lean` stays Kue-import-free. `capturedEnv` carries the FULL id-stack (not one
frame): a def body's depth>0 refs (`attr.#Metadata` cross-pkg embeds) walk the import
chain, so the whole captured env must travel, not just the def's own frame. Derived
`Repr`/`BEq` extend automatically (the `deriving instance` at `Value.lean:526`); the
captured ids make two independently-captured closures compare unequal — the
"independently-built frames never falsely share" invariant rides on the ids exactly as
`Env.ids` does.

### Ordered slices

1. **closure-ctor — introduce `Value.closure` + inert consumer wiring (behavior-preserving,
   MECHANICAL).** Add the constructor to `Value.lean`. The exhaustive (catch-all-free)
   `Value` consumers fail to compile until each gets an arm; that forced set is the exact
   blast radius — `valueTag` (`Eval.lean:717`, add tag 29), `manifestWithFuel`
   (`Manifest.lean:52`, → `.incomplete`), `meetCore` (`Lattice.lean:216`) + `meetWithFuel`
   (`Lattice.lean:847`, → `.bottom` for now), `formatValueWithFuel` (`Format.lean:136`),
   `evalValueCoreWithFuel` (`Eval.lean:898`). Catch-all consumers (`subsumesWithFuel`
   Order `:262`, `normalize*` Normalize, Resolve) absorb it inertly — NO edit. Nothing
   CONSTRUCTS a closure yet, so every new arm is dead code: build + all fixtures unchanged,
   zero behavior change. Pin with `native_decide` round-trip theorems (a `.closure` value
   `Repr`/`BEq`-compares to itself, differs from a different capturedEnv). **DONE
   2026-06-18** — commit `26a2040`. Constructor + five inert arms, 7 pins, zero fixture drift.

2. **closure-eval — force a closure through eval against its captured env (still no
   producer).** `evalValueCoreWithFuel`'s `.closure capturedEnv body` arm: evaluate `body`
   under `capturedEnv` (replace the ambient env with the captured one, rebased), returning
   the evaluated body. With no producer this stays dead code, but it's the semantic anchor
   the later slices target; pin it with a hand-built `.closure` fixture-theorem
   (`evalValue (.closure env body) = evalValue-of-body-in-env`). MECHANICAL once #1 lands.
   **DONE 2026-06-18** — the arm forces `body` under `capturedEnv` (full replacement of the
   call-site env; lexical, not dynamic, scope) with `visited` reset to `[]` and `fuel`
   threaded; `fuel = 0` degrades through the generic arm. 6 pins (captured-binding force,
   empty env, nested closure, lexical-not-dynamic, fuel-exhaustion), zero fixture drift.

3. **closure-producer — the import-selector arm emits a closure (BEHAVIOR CHANGE, gated &
   pinned).** Give `evalValueCoreWithFuel`'s `.selector (.refId id) label` path (and/or the
   `.conj`/`conjStructOperand?` fallback) a branch: when the base resolves to an imported
   def struct reached through a depth>0 binding, instead of eagerly evaluating the body in
   the package frame, yield `.closure capturedPkgEnv defBody`. This is the first slice that
   changes output. Risk: must NOT regress same-package def-meet (which still wants the
   lazy-conj merge) — gate strictly on the depth>0 / import-selector shape. NEEDS ITS OWN
   DESIGN SUB-SPIKE: pin down exactly which resolved shape triggers closure emission vs.
   the existing eager path. Pin with the `crosspkg_defmeet` module fixture (added in #5).
   **DONE 2026-06-18** — sub-spike below; producer lives in the `.selector (.refId id)
   label` arm gated on a depth-0 *sibling self-reference* in the selected def body.

   #### Slice-3 design sub-spike (pinned 2026-06-18 — empirically traced, not guessed)

   **Why the eager path collapses (root, re-confirmed by tracing the `parts.#M` repro):**
   `parts.#M` parses to `.selector (.refId ⟨0,parts⟩) "#M"` — a *depth-0* ref to the hidden
   `parts` import binding, then a `"#M"` selector. (The breadcrumb's "depth>0 binding"
   framing was imprecise: the *selector base* is depth-0; the depth>0 is inside the def body
   — its cross-pkg embeds. The load-bearing fact is "import-selector to a definition," not
   the base's depth.) `conjStructOperand?` has no `.selector` arm (`_ => none`,
   `Eval.lean:831`), so `parts.#M & {…}` fails `lazyConjMergedFields` and falls to the
   `.conj` eval-then-`meet` fallback (`Eval.lean:931-933`). There `parts.#M` evaluates
   *first* via the selector arm's else-branch (`Eval.lean:961-963`): it evals `.refId
   ⟨0,parts⟩` → the WHOLE package struct, which evals `#M`'s body, collapsing `out:#name`
   (`refId ⟨0,0⟩`) to `string` BEFORE the `meet` with `{#name:"keel"}`. `selectEvaluatedField`
   then plucks the already-collapsed `#M`. The base is fully evaluated → intercepting *after*
   the base eval is too late; the producer must act *before* it, on the UNEVALUATED env.

   **Exact trigger (where + predicate).** Producer lives in the `.selector (.refId id)
   label` arm, in the `thisStructFieldIndex? = none` else-branch (`Eval.lean:961`), BEFORE
   the `base <- evalValueWithFuel … (.refId id)` line. Look up the *unevaluated* binding for
   `id` in `env` (`env.drop id.depth`, then `nthField id.index`); emit `.closure (pushFrame
   pkgFields env) defBody` iff ALL hold:
   1. the binding's value is a `.struct pkgFields _` (the import/package — or any — base
      struct, taken UNEVALUATED), and
   2. `pkgFields` has a field named `label` whose `fieldClass.isDefinition` is true (a `#`
      definition), and
   3. that def field's body, when it is a `.struct defFields _`, contains a depth-0 sibling
      self-reference — a `refId ⟨0, _⟩` anywhere in a field body (helper `hasDepth0SelfRef`).
   Otherwise fall through to the existing eager `base`-eval path UNCHANGED. `defBody` is the
   def field's UNEVALUATED `.struct` value; `capturedEnv = pushFrame pkgFields env` (the env
   the package members resolve against — full id-stack, so the def body's own depth>0
   cross-pkg embeds still walk the import chain when forced; the `.struct` force arm pushes
   the def's own fields as the depth-0 frame on top, so `out:⟨0,0⟩` finds `#name`).

   **Why condition 3 is the exact behavior-preservation line (NOT the (a)-narrowed trap).**
   The trap is restricting the *splice/capture* to depth-0-only bodies (dropping cross-pkg
   context). We do NOT: `capturedEnv` is always the FULL `pushFrame pkgFields env`, so a real
   `#ServiceAccount` (self-refs AND depth>0 `attr.#Metadata` embeds) gets the whole package
   env. Condition 3 gates only *whether to defer*, and it is exactly the set that collapses
   today: a def body with no sibling self-ref (`#Widget`={name,size,enabled}, `#Box`,
   `#Mid`, `#Atom`, `#Name` — every committed `pkg.#Def & {…}` fixture) evaluates to the
   same struct whether eager or deferred, because no field's value depends on a sibling the
   use-site narrows — so those MUST stay on the eager path (slice 4 isn't done; a closure
   there would `meet`→`.bottom` and drift). A def body WITH a sibling self-ref
   (`#M`={#name,out:#name}) is precisely the shape that errors today (`incomplete value`) —
   so deferring it regresses no GREEN fixture. Empirically (traced 2026-06-18): all 8
   committed conj-def fixtures have self-ref-free bodies; the only self-ref shape is the
   uncommitted `parts.#M` repro. ∴ slice 3 is byte-identical on every committed fixture.

   **Same-package non-regression (hard line, structurally guaranteed).** Same-package `#M &
   {#name:"keel"}` is `.refId ⟨0,M⟩ & {…}` — a *ref*, not a selector. `conjStructOperand?`
   handles depth-0 `.refId` (`Eval.lean:818-830`) → `lazyConjMergedFields` merges it → it
   NEVER enters the `.selector` arm. Gating the producer in the `.selector (.refId id) label`
   arm cannot touch it. (Verified: same-pkg repro exports `{"out":"keel"}` today and stays.)

   **Slice-3-alone observable behavior.** Slice 3 only CONSTRUCTS closures; the splice is
   slice 4. On the `parts.#M` repro (non-fixture), output changes from `incomplete value:
   string` (eager collapse) to whatever `meet (.closure …) (.struct …)` yields under the
   slice-1 inert arm (`.bottom`) — still an error, still honest, still not a committed
   fixture. The cross-pkg def-meet bug stays unfixed until slice 4; slice 5 pins it. No
   committed fixture observes a closure (condition 3 excludes them all).

   **Self-ref / cycle (carried to slice 4, per Phase-A finding 2).** The producer is the
   first code to build a `capturedEnv` from a real `Env`; get it exact (full `pushFrame
   pkgFields env`, no truncation). `visited:=[]` on force is sound because a forced closure
   is a fresh eval entry — slice 4 derives its cycle handling from first principles (fresh
   entry → empty `visited` → ordinary `slotVisited` catches a self-ref reached via a depth-0
   ref into `capturedEnv`), NOT by analogy to the depth>0 ref arm.

   **Env-defeq tripwire (Phase-A finding 1, folded in here).** Add `example : (List (Nat ×
   List Field)) = Env := rfl` in `Eval.lean` so a future `Frame`/`Env` shape change fails the
   build instead of silently desyncing `Value.closure`'s `capturedEnv` from `Eval.Env`. The
   producer is the natural home — it is the first code to thread a real `Env` into a closure.

4. **closure-meet — meet a closure with a use-site struct (the actual unlock, BEHAVIOR).
   DONE 2026-06-18.** Force point: the `.conj` eval-then-`meet` fallback `none` branch
   (`Eval.lean`). When an evaluated operand is a `.closure` (slice-3 deferred imported def),
   instead of the inert `meet` (→ `.bottom`), `firstClosure?` pulls it out and
   `forceClosureWithConjunct fuel capturedEnv body useOperands` forces it with the OTHER
   conjuncts' evaluated struct fields (`evaluatedStructOperand?`) spliced into the def body's
   frame. The splice reuses the same-package merge machinery, factored to a pure
   `mergeConjOperands (operands : List (List Field × Bool))` shared by `lazyConjMergedFields`
   and the force: def fields + use fields become two conjuncts of one merged frame, pushed onto
   `capturedEnv` and evaluated once, so `out:#name` sees the narrowed `#name:"keel"`. The
   use-site operands are EVALUATED first (at the call site), so their refs are already resolved
   — splicing them never leaks use-site scope into the def frame and rebasing them is a no-op
   (resolved the EC where a use-site field referencing a def hidden sibling is rejected by cue
   anyway). Cycle handling is first-principles: a forced closure is a fresh eval entry
   (`visited := []`), so the ordinary `slotVisited` machinery on the pushed merged frame
   catches a self-referential captured binding → `.top`, no loop (pinned:
   `closure_meet_self_ref_terminates`). `fuel` stays in `EvalKey`.
   - **Closedness fix (latent bug exposed):** an IMPORTED package's def bodies are never
     normalized at load (`normalizeDefinitions` only normalizes the TOP value's own `#`
     fields, not the hidden import binding's), so a forced cross-package def would lose its
     closedness and wrongly admit use-site fields the def doesn't declare. The producer
     (`importDefClosureBody?`) now runs the captured body through
     `normalizeDefinitionValueWithFuel` to close it (`open_ := false`, recursive) at capture.
   - **Open-def (`.structTail`) support added:** `defBodyHasSiblingSelfRef`,
     `forceClosureWithConjunct`, and the gate now handle `.structTail` def bodies (open defs
     with `...`), splicing use fields in and rebasing the tail. Without this, ANY open
     self-ref imported def collapsed (`incomplete value`), even with no extra use field.
   - **Pins (7 new `native_decide` in EvalTests + 1 committed module fixture):**
     `closure_meet_splices_use_site` (THE unlock → `out:"keel"`), `closure_meet_conflict_is_bottom`
     (use-site narrows to a value the def rejects → field-local `.bottomWith primitiveConflict`),
     `closure_meet_empty_use_site` (`#M & {}` == `#M`), `closure_meet_self_ref_terminates`
     (`loop:loop` → `.top`, no divergence), `closure_meet_open_def_admits_extra` (open def
     admits a use-site field), `closure_producer_detects_structtail_sibling`, plus the
     `testdata/modules/crosspkg_defmeet/` regression fixture (`defs.#M & {#name:"keel"}` →
     `{"out":"keel"}`, cue-oracle expected). The two slice-3 producer pins were updated for the
     normalized-closed body (`open_ := false`). Zero drift on every committed fixture.

5. **closure-regression — pin `parts.#M & {#name:"keel"}` and the real shapes.** The
   `testdata/modules/crosspkg_defmeet/` fixture + `native_decide` theorems landed EARLY in
   slice 4 (above). REMAINING for slice 5: the `Self={…}` value-alias real-app shape (see
   `closure-realapp-selfalias` below — it is the actual blocker for real export, NOT the bare
   sibling-self-ref shape slice 4 unlocked), and a periodic test/fixture-organization pass.
   The bare-self-ref edge audit (conflict, empty, self-ref-termination, open-def, two-decl,
   nested) is DONE in slice 4. Decide whether slice 5 folds into `closure-realapp-selfalias`.

### Real-app blockers surfaced by slice 4 (probed 2026-06-18 — read-only prod9)

Slice 4's unlock works perfectly on its target shape (`{#name: string, out: #name}` — a bare
depth-0 sibling self-ref), fast (0.016s) and cue-exact. But **real prod9 apps do NOT use that
shape** — they use `#Def: Self={ … Self.#x … }` value-alias defs that embed cross-package defs
(`parts.#Metadata`). Probing `infra/apps/cert-manager.cue` (`defs.#ClusterIssuer & {…}`, the
SMALLEST real app) and `infra/apps/argocd.cue` (`defs.#Secret`/`#ConfigMap`/`#TLSRoute & {…}`):

- **cue:** both export correctly and instantly (~0.22s for argocd).
- **kue:** both return `conflicting values (bottom)` — and SLOWLY: cert-manager **11.7s**,
  argocd **55s**. So real apps do NOT export end-to-end; they hit BOTH a correctness gap AND
  the perf wall.

Two distinct, independent next slices fall out (do NOT conflate; slice 4's closure path is
provably NOT the cause — the same `Self={}` shape resolves in 0.016s when it has no embed):

**A. `closure-realapp-selfalias` (correctness). DONE 2026-06-18.** Real defs use
`#Def: Self={ parts.#Metadata; #x: string; spec: Self.#x }`. Slice A landed the multi-operand
fold, `.structComp` embed splice (force + embedding-meet + closedness union), and — the largest
unlock — DEEP/nested self-ref detection (`hasSelfRefAtDepth`) so `spec: acme: email: Self.#email`
and comprehension guards defer correctly. All cue-exact on the targeted shapes (see the slice A
design sub-spike above and the landed breadcrumb). Real apps STILL bottom: the chain needed
FURTHER correctness slices — **C `closure-default-in-guard` ✅ DONE 2026-06-18**, **D
`closure-presence-test-selfref` ✅ already passes (verified post-C)**, **E `closure-embed-chain`
(LIVE NEXT)** — plus perf — see "Real-app verdict after slice A" and the C/D/E section below.

**B. `closure-perf` / frame-id-sharing (frontier #2 — now REACHABLE).** Independently, the
real defs blow up super-linearly in time (11.7s small → 55s larger) even while erroring. This
is the parked exponential frame-id divergence (each re-eval of an embedded/selected struct
allocates fresh frame ids, defeating the memo `envIds` key). It was unreachable while real
apps errored at ~0.9s; slice 4 + the eager embed path now reach it. Profiling observation: the
blowup scales with the embed/Self-alias graph size, NOT with closures (closure path is 0.016s).
Fix is audit-heavy (frame-id sharing / canonical frame identity) — its own slice. Sequence:
**A before B** — correctness first; once real apps resolve, B's profiling has a working target.
Likely A precedes the rest of slice 5.

### What this does NOT fix (sequence after)

Field-ordering parity (#3) is orthogonal byte-parity polish — surfaced again in slice 4's EC1
(open def + use-site extra field: values match cue, byte order differs — `extra` before vs
after `out`). The committed `crosspkg_defmeet` fixture avoids it (def-only output).

## Audit Fix-Slices (F2 + import-selector-alias — Phase A code-quality, audit 2026-06-18 #4)

Phase A over `c227042` (F2 structcomp-force-comprehension-loss), `8f0c89e` (alias-to-import-
selector deferral), `acc3d7f` (Module.lean dedupe import bindings). Type-system-first lens.
Verify gate green at audit time: `lake build` 86 jobs, `check-fixtures.sh` "fixture pairs ok"
+ "module fixtures ok", `shellcheck` clean, `lake build Kue.Tests` 40 jobs (all pins pass).
Oracle: `cue` v0.16.1.

**HEADLINE: F2 + alias slice are SOUND — CLEAR to proceed to perf B. No blocking Violations
from this batch.** The dedupe change is sound for its target and drops no by-NAME-distinct
binding; `followAliasDefBody?` is cycle-safe (fuel-bounded) and captures the correct terminal
frame; F2's closedness allow-set folding admits exactly the guard-produced label, no leak. The
findings below are PRE-EXISTING gaps surfaced while adversarially probing the batch (file-
scoped imports; eager-path import closedness) plus test-coverage gaps — none block perf B.

### Findings (ranked)

1. **[BORDERLINE — pre-existing arch gap, dedupe made ONE facet silently wrong] kue has no
   file-scoped imports.** CUE scopes an import binding to the FILE that declares it; kue merges
   every sibling file's bindings into one shared top-level frame (hidden fields), so any file
   sees every sibling's imports and they share the body namespace. Adversarial oracle cases
   (all built read-only, `cue` v0.16.1):
   - *Cross-file leak (pre-existing, parent identical):* file b refs `p.#V` without importing
     `p`; `cue` errors `reference "p" not found`, kue silently resolves to file a's `p`.
   - *Same-alias / different package (dedupe REGRESSED loud→silent):* a.cue `import p "…/px"`,
     b.cue `import p "…/py"`; `cue` keeps them file-scoped (`fromA:px, fromB:py`). Pre-dedupe
     kue errored `conflicting values (bottom)` (loud-wrong); post-dedupe `dedupeBindings` drops
     b's `p→py` (first-name-wins) so `fromB` silently resolves to px (SILENT-wrong). Same final
     verdict (both ≠ cue) but the dedupe traded a loud error for a silent corruption.
   - *Import-name vs body-field collision (pre-existing, parent identical):* b.cue `px:"x"`
     beside a.cue `import px "…"`; `cue` coexists (import hidden, field regular), kue collides →
     `conflicting values (bottom)`.
   By-distinct-NAME bindings (same path under two aliases, two different packages under two
   names) all survive dedupe correctly (oracle-confirmed) — the drop only bites the same-NAME
   case, which is unresolvable WITHOUT file-scoping. Real prod9 packages do not hit this (each
   sibling imports under a distinct or identical-target name), so it does NOT block perf B.
   **Fix-slice `module-file-scoped-imports` (own slice, arch-sized):** bind each file's imports
   into a PER-FILE scope frame, not a shared package frame — resolution must consult the
   declaring file's import set, not the union. Until then, the dedupe `first-wins` should at
   least be order-independent or warn on same-name-different-target. Tracked, not urgent.

2. **[BORDERLINE — pre-existing, SILENT closedness leak across import boundary] a plain closed
   `.struct` def imported and met with extra fields admits them.** `parts.#M: {x:int}` then
   `parts.#M & {x:1, y:2}` → kue `{x:1,y:2}` (admits `y`); `cue` `out.y: field not allowed`.
   Present at the pre-batch baseline `db5ee90` (NOT introduced here). Root: an imported package's
   def bodies are not closed at load (`normalizeDefinitions` only closes the TOP value's own `#`
   fields, never the hidden import binding's), and the EAGER selector path (no sibling self-ref →
   no closure) never re-closes them. The closure-FORCE path DOES close (runs
   `normalizeDefinitionValueWithFuel` at capture), so self-ref imported defs and forced structComp
   defs reject extra fields correctly (oracle-confirmed: `parts.#M:{#x,x:#x}` and the F2
   structComp both give `field not allowed`/non-empty-reject). So the leak is exactly: imported +
   closed + NO sibling-self-ref + plain `.struct`. Same-package closed defs reject correctly.
   **Fix-slice `import-eager-closedness` (MEDIUM):** close imported def bodies at load (normalize
   the hidden import binding's `#` fields), or route the eager import-selector path through the
   same `normalizeDefinitionValueWithFuel` close the force path uses. Pin both the silent-admit
   (`{x:1,y:2}`) and the incomplete-mask (`& {y:2}` → kue `incomplete value` vs cue `field not
   allowed`) facets. Does NOT block perf B (orthogonal correctness gap).

3. **[BORDERLINE — test coverage gaps in the batch] three missing pins.** (a) No END-TO-END
   module fixture for the dedupe DISTINCT-binding case (two sibling files importing DIFFERENT
   packages) — only a `dedupeBindings` unit pin. The absence of this fixture is why finding 1's
   same-name regression went unnoticed. (b) No pin for the closed structComp / closed import def
   closedness-REJECT boundary (use-site adds an undeclared field) — F2 fixtures pin guard-FIRES
   but not guard-CLOSEDNESS. (c) Mutual-alias cycle IS pinned (`alias_follow_cycle_terminates`,
   `#A:#B / #B:#A` → terminates `none`) — no gap there. **Fix-slice `audit4-test-gaps` (LOW):**
   add a `dup_distinct_import` module fixture (oracle the same-name case to DOCUMENT the known
   divergence, or pin the distinct-name correct case) + a closed-structComp-reject pin. Fold (b)
   into the `import-eager-closedness` slice's pins.

4. **[CLEAR — verified sound, no action]** Type-system / totality / DRY over the batch:
   `followAliasDefBody?`, `refAliasDefClosure?`, `refAliasSelectorDef?`, `dedupeBindings*` are
   all total `def`s (no `partial`, no `sorry`), fuel-bounded where recursive (alias-follow
   decrements `fuel`; base arm non-recursive), exhaustive struct-like dispatch with no catch-all
   swallowing a `Value` constructor (the `| body =>` arm classifies via explicit `isStructLike`
   and falls through to `none`, not a silent accept). `dedupeBindingsWith` is structural on the
   list, order-preserving, `seen`-accumulating — correct first-wins. The `.refId`-index-integrity
   claim holds structurally: resolution is by-NAME at eval time over the FINAL bound struct, so
   indices always track the post-bind layout regardless of when binding ran. No DRY violation
   (the alias producers mirror `importSelectorDef?`'s `(frame, body)` shape deliberately).

### What perf B (frame-id-sharing) must account for

- The dedupe change altered the loader for EVERY multi-file package: bodies now merge RAW and
  bind ONCE at package level. Perf-B's frame-id canonicalization keys on env id-stacks — the
  single deduped import frame means a package imported in N sibling files now contributes ONE
  hidden binding (one frame slot), not N. Good for memo sharing (fewer distinct frames), but
  verify the canonical frame-id derivation does not assume per-file binding layout.
- The closure-force path closes imported def bodies at capture (`normalizeDefinitionValueWithFuel`);
  if perf B memoizes forced closures, the cache key must include the closed-vs-open body state
  so an eager (unclosed) and forced (closed) eval of the same import def never alias.

## Audit Fix-Slices (Value.closure slices 3-4 — Phase A code-quality, audit 2026-06-18 #2)

Phase A over the two behavior-changing closure slices: `42db7fa` (closure-producer: the
import-selector arm emits a `.closure`) and `fd06f70` (closure-meet: `forceClosureWithConjunct`
splices the use-site into the forced body; +2 inline bug fixes). Type-system-first lens.
Verify gate green at audit time: `lake build` 86 jobs, `check-fixtures.sh` "fixture pairs ok",
tree clean at `79844c2`. Oracle: `cue` v0.16.1. No inline fix this pass — the one Violation
needs a design sub-spike (it IS slice A's scope), the rest are test-strength/cleanup; this pass
changed only `plan.md`.

### Headline verdict — CLEAR to build slice A, with ONE load-bearing caveat folded INTO it

The single-closure single-use-site machinery is **sound** and cue-exact on its target shape.
No Violation blocks STARTING slice A. BUT the one real correctness hole found
(`closure-multiop-splice` below) is not a separate slice — it is *the same gap slice A must
close*: splicing a SECOND struct/def operand (a package-sourced struct or a second imported def)
into the closure frame currently yields `bottom`/`incomplete` where cue resolves, and real-app
`Self={ parts.#Metadata; … }` defs embed exactly such a package-sourced struct. Slice A cannot
be called done until the multi-operand splice is correct. The two inline bug fixes (closedness,
`.structTail`) are **correct and complete** for what they target (verified below). Meet-purity
containment is **airtight**. Findings ranked below.

### Findings (ranked)

1. **[VIOLATION (scoped INTO slice A, not a standalone blocker) — `closure-multiop-splice`]
   The splice handles ONE closure + LOCAL-literal open structs; a SECOND package-sourced
   struct/def operand collapses to `bottom`/`incomplete`.** Empirically (read-only `/tmp`
   probes, cue v0.16.1 oracle):
   - `#M & #N & {narrow}`, both open self-ref imported defs → cue `{label,out}`, kue
     `incomplete value: string`. Root: `firstClosure?` splices only `#M`; `#N` stays a
     `.closure` in `rest`, `evaluatedStructOperand?` returns `none` for it, so it lands in
     `leftover` and is forced UNSPLICED (`evalValueWithFuel fuel e [] b`, `Eval.lean:1083-1084`)
     — its body never sees the use-site narrowing → collapses.
   - `#M & defs.P & {narrow}` where `P` is a regular/def OPEN struct (NOT a closure, no
     self-ref) → cue `{out,plain}`, kue `conflicting values (bottom)`. Here `P`'s evaluated
     struct DOES go through `useOperands`, yet splicing a *package-sourced* struct into the
     pushed merged frame produces a spurious conflict. A LOCAL inline-literal struct in the
     same position (`base:{plain:"p"}; #M & base & {narrow}`) splices CORRECTLY (kue==cue) —
     so the trigger is "operand whose fields were evaluated against the import/package frame,"
     not same-vs-cross-package at the use site (binding `localP: defs.P` first still fails).
   This is THE shape real apps need: `#Def: Self={ parts.#Metadata; … }` embeds a
   package-sourced struct into the def body. **Fix-slice = slice A itself** must (a) extend
   `firstClosure?`/the fold so EVERY closure operand is force-spliced with the shared
   use-site set (fold over all closures, not just the first), and (b) fix the
   package-sourced-struct splice conflict (likely a closedness or rebase interaction in
   `mergeConjOperands` when an operand's fields carry resolved package-frame values — needs the
   sub-spike's root-cause trace). Until then, multi-operand def-meet is wrong, silently
   (returns an error, so not a wrong *value*, but rejects valid programs).

2. **[BORDERLINE — test strength, fold into slice A] `closure_meet_self_ref_terminates` does
   not exercise a CAPTURED-frame cycle — only a depth-0 slot self-loop.** The pin
   (`EvalTests.lean:1111`) uses `loop: refId ⟨0,1⟩` (a field referencing its own merged-frame
   slot) → `slotVisited` → `.top`. That pins slot-local termination, but the plan/breadcrumb
   claim the stronger "a closure whose `capturedEnv` frame refs ITSELF terminates." The capture
   here is non-cyclic; the cycle is purely in the pushed merged frame. **Action:** slice A adds
   a pin where the captured package frame contains a binding that refs back into the def
   (capture-level cycle), confirming `visited:=[]` + `slotVisited` still terminates. Low risk;
   no code change implied unless the pin fails.

3. **[BORDERLINE — test strength, fold into slice A] No pin for the multi-operand path at all.**
   The 7 slice-4 pins all use exactly ONE closure + ONE use-site struct (or empty). The
   multi-closure and package-sourced-second-operand shapes (finding 1) are untested — the gap
   went unnoticed because every pin is single-operand. Slice A must add: (a) two-closure
   def-meet, (b) closure + package-sourced open struct, (c) closure + embedded package def
   (the real-app shape), each oracle-checked. Pin the FIX, not just the current behavior.

4. **[CLEANUP — confirmed sound, no action] The two inline bug fixes are correct AND complete.**
   (a) **Closedness:** `importDefClosureBody?` runs the captured body through
   `normalizeDefinitionValueWithFuel` (`Eval.lean:977`). Verified it does NOT over-close: only a
   `.struct` body is forced `open_:=false` (`Normalize.lean:11-12`); a `.structTail` (open `...`
   def) hits the catch-all `| _, value => value` (`Normalize.lean:46`) and stays open — so the
   `closure_meet_open_def_admits_extra` behavior is real, not luck. It does NOT under-close:
   `normalizeFieldWithFuel` recurses into nested DEFINITION fields only (`:51-54`), matching CUE
   (a def closes its own labels + nested defs; a nested regular struct literal stays open).
   (b) **`.structTail` gate:** the gate fires only on a genuine depth-0 sibling self-ref in the
   tail-struct's fields/tail (`defBodyHasSiblingSelfRef`, `Eval.lean:944-945`); it cannot fire on
   a non-self-ref open def. Sound. These are real fixes, not fixture-chasing.

5. **[CLEANUP — confirmed sound, no action] Meet-purity reopening containment is airtight.**
   `meetCore` handles `.closure _ _ => .bottom` for BOTH polarities with no catch-all swallowing
   it (`Lattice.lean:393-394`), and `meetWithFuel`'s `value, other => meetCore value other`
   routes there. So a stray closure reaching ANY meet site — `meetEmbeddingsWithFuel`
   (`Eval.lean:1229`), `Builtin.lean:39`, `Runtime.lean:58`, the `firstClosure? = none` fold
   (`Eval.lean:1072`) — degrades to `.bottom` (honest error), never a silent wrong value. The
   `.conj none` force point is the ONLY site that splices; everywhere else is honest-`.bottom`.
   `fuel` stays in `EvalKey` (`Eval.lean:790,797`); no `partial def` introduced; the whole
   closure path is total (fuel-bounded `termination_by`). NOTE for slice A: the embedded-def
   shape reaches `meetEmbeddingsWithFuel` (an embedding evaluates to a `.closure` → `meet` →
   `.bottom`), so slice A's splice must also fire in the embedding-meet path, not just `.conj`.

### What slice A (`closure-realapp-selfalias`) must account for (surfaced here)

- The real blocker is finding 1's multi-operand/package-sourced-struct splice, NOT a new
  "embedded def" deferral mechanism per se: the producer already fires on `parts.#Metadata`
  (it is a selector), but the resulting closure either (a) hits `meetEmbeddingsWithFuel`'s plain
  `meet` → `.bottom` (embedding position), or (b) reaches the `.conj` fold as a second operand
  and is force-spliced wrong. Slice A's sub-spike must root-cause the package-sourced-struct
  splice conflict BEFORE adding the `Self=` alias handling — the alias resolves already
  (minimal `Self={…}` without an embed is cue-exact, per the slice-4 probe); the embed is the
  gap.
- Field-ordering parity (#3) will resurface in any multi-field real-app output (slice-4 EC1).
  Orthogonal byte-polish — do not let it block correctness; the regression fixture should stay
  def-only-output where possible to dodge it.

### Slice A design sub-spike (root-caused 2026-06-18 — empirically traced, not guessed)

**ROOT CAUSE of facet (b)/(c) — it is `.structComp`, not "package-sourced struct".** A def
body that EMBEDS another value (`#Def: { parts.#Metadata; #x: string; spec: #x }`) parses to a
`.structComp staticFields [embedding…] open` (the parser routes every embedding into
`structComp.comprehensions` as `.embedding v`), NOT a `.struct`. The audit's "package-sourced
struct" framing was a symptom: the real discriminator is the def body shape. Traced (read-only
`/tmp/pf_embed`, cue v0.16.1 oracle): even a def embedding a LOCAL same-package plain struct
(`#Def: { #Base; #x; spec: #x }`) yields `incomplete value: string` in kue (cue: `{kind,spec}`)
— cross-package indirection is NOT the trigger; the embedding is. Three sites drop `.structComp`:

1. **Gate (`defBodyHasSiblingSelfRef`, `Eval.lean:942`)** only matches `.struct`/`.structTail`
   → a `.structComp` def body returns `false` → `importDefClosureBody?` returns `none` → NO
   closure is produced → eager path evals `#Def` in its own frame, collapsing `spec:#x` to
   `string` BEFORE the use-site `#x:"hello"` narrows (proof: `kue eval` shows
   `t: {#x:"hello", spec:string, kind:"Service"}` — `#x` narrowed via the plain `.conj` merge,
   `spec` already collapsed).
2. **Force path (`forceClosureWithConjunct`, `Eval.lean:1249`)** has no `.structComp` arm → its
   catch-all `| _ =>` evals the body unspliced then `meet`s — so even if a closure were produced,
   the splice would not reach the static fields.
3. **Embedding-meet path (`meetEmbeddingsWithFuel`, `Eval.lean:1222`)** plain-`meet`s an
   embedding that evaluated to a `.closure` (a self-ref cross-pkg embed `parts.#Metadata`) →
   `.bottom` (proof: `#Def: _|_` in `kue eval` for the self-ref-embed case). This is facet (c).

**Facet (a) multi-operand fold (`Eval.lean:1071-1087`)** is independent of `.structComp`:
`firstClosure?` splices only the FIRST closure; a second imported-def operand (`#M & #N &
{narrow}`) stays a `.closure` in `leftover`, forced UNSPLICED (`evalValueWithFuel fuel e [] b`)
→ its body never sees the use-site narrowing → `incomplete value: string`.

**Decomposition: ONE slice (A), one commit.** Facets (b)/(c) share the single mechanism
(`.structComp`/embedding handling) across three sites; splitting would leave artificially
non-green intermediate states (the gate firing without the force arm = a closure that hits the
catch-all). Facet (a) is small and the audit scoped it into A. All land together. The fix:

- **A.1 Gate.** `defBodyHasSiblingSelfRef` gains a `.structComp fields cs _` arm: a sibling
  self-ref if any static field OR any embedding/comprehension has a depth-0 ref.
- **A.2 Force `.structComp`.** `forceClosureWithConjunct` gains a `.structComp defFields cs _`
  arm mirroring the `.structComp` EVAL arm (`Eval.lean:1190`): splice use-operands into the
  static `defFields` via `mergeConjOperands`, `pushFrame` onto `capturedEnv`, eval the static
  fields, then `meetEmbeddingsWithFuel` the embeddings against the spliced frame. Embeddings
  that evaluate to a `.closure` are force-spliced (see A.4) so an embedded self-ref cross-pkg
  def resolves under the same use-site narrowing.
- **A.3 Multi-operand fold.** Replace `firstClosure?`/`dropFirstClosure`/`leftover` with a fold
  that force-splices EVERY closure operand against the SHARED use-operand set (all non-closure
  struct operands), then `meet`s the forced results together. `#M & #N & {narrow}` resolves
  like cue (associative; the shared use set narrows both defs' siblings).
- **A.4 Embedding-meet closure splice.** `meetEmbeddingsWithFuel` (and the A.2 force) detect an
  embedding that evaluated to a `.closure` and force it (with the current frame's use-context
  spliced where applicable) instead of a plain `meet` → `.bottom`. Minimal form: force the
  closure body under its captured env with the surrounding use-operands as the splice set.
- **A.5 (secondary) `.structComp` closedness.** `normalizeDefinitionValueWithFuel`
  (`Normalize.lean`) has no `.structComp` arm → a `.structComp` def body is returned UNCLOSED.
  Add a `.structComp` arm closing the static portion (`open_ := false`) and normalizing nested
  definition fields, matching the `.struct` arm — so a forced embed-def rejects undeclared
  use-site fields exactly as cue does. Verify against cue's closedness on the embed shape.

**Tests (mandatory pins):** multi-closure `#M & #N & {narrow}`; closure + package-sourced open
struct; the real embed `#Def: { parts.#Metadata; #x; spec:#x } & {narrow}`; a GENUINE
captured-frame-cycle termination pin (a closure whose captured frame refs itself, replacing the
weak depth-0-slot `closure_meet_self_ref_terminates`). Committed module fixture under
`testdata/modules/` mirroring `crosspkg_defmeet/` for the embed shape. Every existing fixture
byte-unchanged.

**Status: DONE 2026-06-18** — see implementation-log + the slice-A landed breadcrumb. All
five sub-fixes (A.1–A.5) landed PLUS a sixth the real apps forced (A.6, below). Every targeted
facet is cue-exact and every existing fixture byte-unchanged.

- **A.6 DEEP / nested self-ref detection (discovered building A — the real-app shape).** The
  slice-4 gate (`hasDepth0Ref`) only flagged TOP-LEVEL sibling self-refs. Real defs reference
  hidden fields from DEEP nested positions — `#ClusterIssuer: Self={ spec: acme: email:
  Self.#email }` refs the top `#email` from 3 frames in (`refId ⟨3,_⟩`), and comprehension
  GUARDS (`if Self.#staging`) too. Without detection the producer never defers → eager collapse
  of the nested ref before the use-site narrows. Replaced `hasDepth0Ref` with `hasSelfRefAtDepth
  (depth)`: descends every frame-pusher (`.struct`/`.structComp`/pattern/comprehension)
  incrementing `depth`, flags `refId ⟨depth,_⟩` (lands on the def's own frame). Also scans
  comprehension clause guards/sources at their enclosing depth. The single largest correctness
  unlock for the real-app `Self={…}` shape; the force/splice already propagates the narrowing
  into nested frames once the closure fires.

### Real-app verdict after slice A (probed 2026-06-18 — read-only prod9, cue v0.16.1 oracle)

Slice A is cue-exact on EVERY shape it targets, verified by minimal repros: multi-closure
`#M & #N & {narrow}`; single-level embed (local + cross-pkg self-ref); `Self={…}` value-alias;
DEEP nested self-refs (`spec: acme: email: Self.#email`); comprehension guards over a concrete
self-ref (`if Self.#staging` with `#staging: bool`). **But cert-manager / argocd still return
`bottom` (cert-manager 9.6s, perf wall ALSO unresolved).** The real defs chain THREE further,
independent correctness shapes slice A does NOT cover — each its own slice, sequence A→…→B:

**C. `closure-default-in-guard` (correctness). DONE 2026-06-18.** A comprehension guard over
a DEFAULT disjunction did not resolve the default. Root cause was TWO coupled gaps: (1)
operations did not distribute over disjunctions (`!(bool|*false)`, `(int|*1)+1` stayed stuck
instead of becoming `bool|*true` / `int+1|*2`), and (2) the guard test compared the condition
to `.prim (.bool true)` without collapsing a defaulted-disjunction condition. Fix: consolidated
`liveAlternatives`/`defaultAlternatives` into `Lattice.lean` + added `resolveDisjDefault?` (the
shared concrete-context collapse rule, now also used by `Manifest`); added
`distributeUnary`/`distributeBinary` in `Eval.lean` (map op over `.disj` alternatives, preserve
marks); the `expandClausesWithFuel` guard now runs a `.disj` condition through
`resolveDisjDefault?` before the bool test. Non-default disjunctions deliberately stay
`incomplete` (no over-resolution). cue-exact on the real `#ClusterIssuer` `#staging: bool |
*false` + `if Self.#staging`/`if !Self.#staging` shape. 8 `native_decide` pins + committed
`testdata/cue/comprehensions/default_in_guard.{cue,expected}`. See impl-log slice C.

**D. `closure-presence-test-selfref` (correctness). ALREADY PASSES — no dedicated slice
needed (verified 2026-06-18 during the C re-probe).** Both `if Self.#ns != _|_ {…}`
(presence-test over a self-ref) AND `len(Self.#labels) > 0` guards are cue-exact post-A/C, in
isolation under a `Self={…}` closure. The slice-A + slice-C work cleared D's scoped shapes; the
"unverified" concern is resolved. If the real chain surfaces a D-specific failure later it
re-opens, but the probed shapes are green.

**E. `closure-embed-chain` (correctness). DONE 2026-06-18.** A MULTI-LEVEL embed chain — a def
embeds a def that embeds a def, each a `Self={…}` self-ref — collapsed: `#Outer{ #Mid{ #Inner } }`
→ kue `bottom`, cue `{aname,mname,oname}`.

**ROOT CAUSE (traced, not the breadcrumb's framing — it is closedness-leak, not force-recursion).**
The collapse is NOT about chaining self-refs or re-forcing inner closures. Minimal repro that bottoms
in kue while cue succeeds: `out: { #Plain; x: "z" }` with `#Plain: {pval: "p"}` — embedding ANY
struct that carries a REGULAR field, alongside a host regular field, → `bottom`. Even `out: { #Plain }`
(pure embed, no host field) bottoms. The discriminator: embedding a **definition** ref (`#Plain`,
closed) fails; embedding a lowercase (open) ref (`plain`) works. Mechanism: an embedded closed struct
`.struct [pval] open=false` meets the host `.struct [x] open` via `meet`; `applyStructClosedness`
with the embed's `rightOpen=false` rejects host label `x ∉ {pval}` → `bottom`. CUE's rule (already in
`openStructValue`'s docstring): an embedding UNIONS its labels into the host's allowed set WITHOUT
imposing its own closedness on the host. Slice A's fixtures dodged this because the only cross-pkg
embed (`parts.#Metadata`) had HIDDEN-ONLY fields (`#kind`,`#norm`) which `ignoresClosedness`; any
embed contributing a regular field — exactly the real 3-level chain's `aname`/`mname`/`oname` — trips
it. The force-`.structComp` arm handled this correctly (opens the embed via `openStructValue`, meets
OPEN, re-closes over `def ∪ embed` labels at the end); the EAGER `.structComp` arm and the non-closure
branch of `meetEmbeddingsWithFuel` did not. The chain "collapses at every level" because every level's
embed contributes a regular field, so the leak fires at the first level and bottoms the whole struct.

**FIX (one slice, one mechanism — embeddings never impose closedness on their host).**
1. **E1 closedness leak.** `closeEmbeddedOver` + `openStructValue` at BOTH embed-meet sites (eager
   `.structComp` eval arm, `.structComp` closure-force arm): meet embeddings OPEN against an OPEN
   host, re-close ONCE over `def ∪ embed` labels. DRY'd into one shared helper.
2. **E2a producer gap.** `refDefClosureBody?`/`conjDefClosure?` defer a bare ref to an embed-bearing
   `.structComp` (any depth) or a NESTED (`depth > 0`) `.struct`/`.structTail` self-ref def to a
   `.closure` — wired into the `.refId` arm (standalone force), the `.conj` fold, AND
   `meetEmbeddingsWithFuel`. Depth-0 `.struct`/`.structTail` keeps the lazy-merge path (no drift).
3. **E2b splice contamination.** `hiddenFieldsOnly` splices ONLY the host's hidden/definition fields
   into an embed (the shared `#name`), never the host's `Self=`/`let` aliases (collide with the
   embed's own `Self`) or regular fields (`apiVersion`/`kind`, which the embed would re-eval and
   conflict on). `stripLetBindings` on the multi-operand `.conj` fold use-operands.

The breadcrumb's "force doesn't recurse" framing was wrong — forcing already recurses via the
`.conj`/embed defers; the three real bugs were the closedness leak, the producer gap, and the
cross-scope splice contamination. All chain shapes (2/3-level, explicit + implicit plain-embed,
closed-host union, narrow-through, inner-conflict→bottom) resolve cue-exact.

**B'. `closure-structcomp-force-comprehensions` (NEW correctness blocker — LIVE NEXT).
RE-DIAGNOSED 2026-06-18 by Phase-A audit #3 — was mislabeled `closure-crossdef-cache-collision`.**
NOT a cache collision. The real bug: `forceClosureWithConjunct`'s `.structComp` arm
(`Eval.lean:1544-1566`) only meets the embeddings (`comprehensions.filter isEmbeddingValue`) and
NEVER calls `expandComprehensionsWithFuel` — so a conditional `if`/`for` guard inside a
deferred-then-forced structComp def is silently dropped. The eager `.structComp` eval arm
(`:1380-1395`) expands them correctly. Reproduces with ONE def, no sibling, no cache:
`#M: {#x: int, if #x > 0 { y: #x }}` + `#M & {#x: 5}` → cue `{y:5}`, kue `{}`. The real
`attr.#Ports` (`if #port != _|_ {…}`) hits this via the embed deferral; `#PodController` is a
red herring (it just loads the guard-bearing structComp). The EvalKey/pushFrame memo is NOT
implicated. **Fix:** thread the non-embedding comprehensions through `expandComprehensionsWithFuel`
in the force arm and merge into `merged` before the embed-meet; audit the lazy-merge path too
(`M & {#x:5}` for a non-def comprehension struct drops the guard the same way). See audit #3
finding F2 at the end of this file for the full target + pins.

**B. `closure-perf` (frontier #2 — still a wall).** cert-manager ~11s, argocd ~54s even while
erroring. Downstream of correctness; profile after B' resolves the cross-def collision.

Sequence (revised 2026-06-18 post-E): **C ✅ → D ✅ → E ✅ → B' (`closure-crossdef-cache-collision`,
LIVE NEXT) → B (perf).** E is complete and green on every embed-chain shape; the live cert-manager
blocker is now B' (a sibling structComp-with-guard def poisoning an unrelated def's eval).

## Architecture Fix-Slices (Phase B audit 2026-06-18 #2 — post Value.closure slices 3-4-A, AUTHORITATIVE)

Whole-module-graph pass after the three behavior-changing closure slices — `42db7fa`
(producer), `fd06f70` (meet-force + 2 inline bug fixes), `1673d1e` (slice A: multi-operand
fold + `.structComp` wiring + `hasSelfRefAtDepth` replacing `hasDepth0Ref`) — building on the
prior Phase B verdict (`31b329c`, slices 1-2) and the slice-3-4 Phase A (`1f76347`).
Type-system-first lens. Verify gate green at audit time: `lake build` 86 jobs,
`check-fixtures.sh` "fixture pairs ok", `shellcheck` clean, tree clean at `e04ffcd`. Oracle:
`cue` v0.16.1. **One inline fix this pass** (dead-helper deletion, item 1 below — re-verified
+ committed); everything else is plan-only.

### Headline verdict — module graph HEALTHY, layering intact after the closure churn

The `31b329c` acyclic-DAG verdict holds unchanged; re-confirmed, not re-derived. Slices
3-4-A added ZERO import edges — every new function lives inside `Eval.lean`'s existing `mutual`
block or as a pure pre-mutual helper. Re-verified directly:

- **`Value.lean` is still a true leaf** — imports only `Init.Data.String.Search`, zero
  `import Kue.*`. The closure ctor stayed `List (Nat × List Field)` raw product data; the
  slice-3/4/A churn was entirely in `Eval.lean`, never touched `Value`'s import set.
- **Import graph unchanged + acyclic:** `Eval ← {Builtin, Decimal, Lattice, Normalize}`; no
  `Builtin → Eval` back-edge; no cycle. Every edge identical to the `31b329c` table.
- **`meetCore`'s `.closure _ _ => .bottom` (both polarities, `Lattice.lean:393-394`) is STILL
  the only meet-site closure handling** — no new meet site grew a closure arm. A stray closure
  reaching any meet degrades to honest `.bottom`; Manifest emits `.incomplete`
  (`Manifest.lean:110-113`), Format prints the body (`Format.lean:213-216`). The deliberate
  splice sites are exactly three, all in `Eval.lean`: the `.conj` fold, `meetEmbeddingsWithFuel`,
  and `forceClosureWithConjunct`. Containment is airtight, unchanged from the Phase-A finding.
- **`closure-env-sync-guard` tripwire LANDED** (folded into the producer slice as planned):
  `example : (List (Nat × List Field)) = Env := rfl` at `Eval.lean:770`. The one type-system
  fix the closure rep owed is now a build-time tripwire; the defeq is no longer convention-only.

### Closure machinery — coherent unit, NOT a tangle; do NOT extract `Kue/Closure.lean` now

The closure family is ~370 added lines splitting into two tiers:

- **Pure pre-mutual helpers** (`Eval.lean:847-1064`): `mergeConjOperands`, `openStructValue`,
  `evaluatedStructOperand?`, `allClosures`, `nonClosureNonStructOperands`, `hasSelfRefAtDepth`,
  `defBodyHasSiblingSelfRef`, `importDefClosureBody?`.
- **In-`mutual` forcing tier**: `forceClosureWithConjunct`, `meetEmbeddingsWithFuel`,
  `evalEmbeddingFieldsWithFuel` — fuel-threaded, mutually recursive WITH `evalValueWithFuel`.

**Verdict: leave it in `Eval.lean`.** A `Kue/Closure.lean` extraction is not viable and not
worth forcing:

1. **The forcing tier is fused into the evaluator's `mutual` block** — `forceClosureWithConjunct`
   calls and is called by `evalValueWithFuel`/`meetEmbeddingsWithFuel` at shared fuel measure.
   Extracting it means moving the ENTIRE evaluator, not a closure submodule. No clean cut exists.
2. **The pure tier shares the conjunction-merge primitives with the non-closure 2c path.**
   `mergeConjOperands` is built from `mergeConjFields`/`labelIndexMap`/`rebaseConjunctFields`/
   `applyConjClosedness`/`allClosednessOpen`, the SAME primitives `lazyConjMergedFields` (2c
   same-scope conjunction) uses. Splitting closures out either fragments those primitives across
   two files or duplicates them — a worse boundary than the status quo.
3. **C/D/E will extend exactly these functions** — C edits `expandClausesWithFuel`'s guard
   (in the `mutual` block), D/E extend the force/embedding-meet path. Churning the boundary now
   and re-churning after the chain lands is pure waste. **Re-judge extraction only AFTER E**, and
   only if the forcing tier has grown its own independent recursion (it has not — it's still
   one fuel measure with the evaluator). Coherent-enough to leave; the comments and the slice-A
   sub-spike make the unit traceable in place.

### Dead code from the slice-3→4→A evolution

1. **[CLEANUP — DONE INLINE this pass] `firstClosure?` + `dropFirstClosure` were dead.** Slice
   A's A.3 multi-operand fold replaced the first-closure-only logic with `allClosures` +
   `nonClosureNonStructOperands` (the actual `.conj` fold call sites, `Eval.lean:1154,1158`), but
   left the two superseded helpers defined with ZERO call sites (`firstClosure?`,
   `dropFirstClosure`). Confirmed dead by grep across `Kue/` (only self-recursive references;
   no test/source consumer). The plan's own A.3 line said "Replace `firstClosure?`/
   `dropFirstClosure`/`leftover` with a fold" — the replacement landed, the defs did not get
   removed. **Deleted inline** (~12 lines); full verify gate re-run green (86 jobs, fixture pairs
   ok, shellcheck clean). The historical doc references in plan.md/impl-log/breadcrumb describe
   slice-4's design accurately at its time and stay as design record. `hasDepth0Ref` (slice A's
   A.6 replacement target) is ALSO fully gone — only a doc reference at `Eval.lean:915` explains
   the generalization to `hasSelfRefAtDepth`; no `def`, no call site remains.

### Re-ranked parked cleanups (carry forward from `31b329c`, re-judged under the churn mandate)

The `31b329c` rankings hold, re-confirmed against the now-larger `Eval.lean` (1565→1553 lines
after the inline deletion):

2. **[STILL-WAIT-FOR-CDE] `evalAdd…evalBinary` → `Kue/EvalOps.lean`.** ACTIONABLE on merit
   (self-contained pure `{Value, Decimal}` dispatch, ~256 lines, real boundary win — carves the
   scalar algebra out from under the recursive evaluator). BUT it OWNS `Eval.lean` line numbers,
   and C/D/E all edit `Eval.lean` (C: `expandClausesWithFuel` guard; D/E: force/embedding-meet).
   Moving ~256 lines out from line 369 shifts every line below it → guaranteed merge collision
   with the in-flight chain. **Land AFTER E**, when the closure work is fully settled. Unchanged
   from `31b329c` (which said "after slice 5"; the chain is now C→D→E→B, so the gate is "after E").
3. **[STILL-ACTIONABLE-NOW, PARALLEL-SAFE] Regex engine → `Kue/Regex.lean`.** Re-confirmed: the
   engine (`Value.lean`, `RegexAtom` + parse/match ending at `stringRegexMatches`) depends only
   on `Char`/`String`, is consumed by `Eval`/`Builtin` only, and sits in `Value.lean` BELOW the
   closure ctor — so it does NOT conflict with C/D/E's `Eval.lean` edits. It is the one cleanup
   that can run concurrently with the correctness chain in its own subagent. Move-plan unchanged:
   new leaf `Kue/Regex.lean` (imports nothing), delete the trailing block from `Value.lean`, add
   `import Kue.Regex` to `Eval`/`Builtin`. Single best parallel-safe slice of the batch. (Did not
   do it inline — it's a multi-file move above the inline-trivial bar.)
4. **[STILL-WAIT-FOR-CDE] Test-org pass.** `Kue/Tests/` has grown further: `EvalTests` is now
   1700+ lines (was 950 at `31b329c` — slices 3-4-A added ~750 lines of closure pins),
   `FixtureTests` 1033, `BuiltinTests` 735, `StructTests` 765. The split is MORE warranted than at
   `31b329c`, but C/D/E will each add closure/guard pins to `EvalTests` (and likely a module
   fixture each under `testdata/modules/`), so splitting now goes immediately stale. **Wait until
   AFTER E**, then split `EvalTests`/`FixtureTests`/`BuiltinTests`/`StructTests` by subsystem in
   ONE pass; leave `FixturePorts` whole (generated data, item-5 verdict stands). `testdata/
   modules/` now has 18 dirs incl. two closure-specific (`crosspkg_defmeet/`,
   `crosspkg_embed_selfalias/`) — sensibly named, no reorg needed; the post-E test-org pass should
   only group the theorem modules, not churn `testdata/`.
5. **[DEFER indefinitely] `embeddedList.decls` newtype.** Single-site invariant, wrap/unwrap cost
   outweighs the marginal illegal-states win. Unchanged from `31b329c` item 3/5.

### Roadmap sanity-check — C→D→E→B order is SOUND

Re-confirmed the slice-A breadcrumb's ranking:

- **C first is correct.** C (`closure-default-in-guard`) is genuinely orthogonal to closures —
  the breadcrumb's claim that it reproduces with no def at all (`x: bool | *false; if !x {…}`
  drops in kue, cue admits) is credible: it's a default-resolution gap in `expandClausesWithFuel`'s
  guard test (`== .prim (.bool true)` without resolving the disjunction default), entirely
  separate from the closure force path. Smallest, lowest-risk, unblocks the real `#ClusterIssuer`
  `#staging: bool | *false` guard. **Could even land BEFORE the rest as a pure guard fix** — it
  does not depend on any closure machinery.
- **D before E is right** — D (presence-test self-ref) is a narrower force-path verification; E
  (multi-level embed chain) is the deepest (recursion through nested embedded closures) and gates
  the 3-level `#ClusterIssuer → parts.#Metadata → attr.#Metadata`. E likely the hardest correctness
  slice of the chain.
- **B last is right** — perf is downstream of correctness; cert-manager errors before the blowup
  fully matters, and B needs a working (resolving) target to profile. No reordering warranted.
- **One refinement:** C is so orthogonal it need not wait behind the closure framing at all —
  schedule it as the immediate next slice regardless of the closure-chain label. D/E stay the
  closure-correctness spine.

## Audit Fix-Slices (Value.closure slices 1-2 — Phase A code-quality, audit 2026-06-18)

Phase A over the first two closure slices: `26a2040` (closure-ctor: constructor + 5 inert
consumer arms) and `15c92ec` (closure-eval: the `.closure` eval arm forces `body` under
`capturedEnv`). Type-system-first lens. Verify gate green at audit time: `lake build` 86
jobs, tree clean at `15c92ec`. Oracle: `cue` v0.16.1. No inline fix this pass — all
findings are below-threshold for inline (one is a guarding tightening that wants TDD, the
rest are doc/test-strength); this pass changed only `plan.md`.

### Headline verdict — CLEAR to build slices 3-4 on

The closure foundation is **sound**. No Violations. Constructor is the layering-correct
representation; the five inert consumers are genuinely inert and route consistently
(`meetWithFuel` catch-all → `meetCore` → `.bottom`; `manifest`/`thisStruct` both →
`.incomplete`; `valueTag 29` is collision-free and the max tag). The eval arm's
lexical-scope semantics (discard call-site env, `visited := []`, normal fuel decrement) is
correct for a captured lexical closure and threads `capturedEnv` into the memo with zero
coercion. Findings below are Borderline/cleanup — none blocks slice 3.

### Findings (ranked)

1. **[BORDERLINE — illegal-states gap, fix-slice `closure-env-sync-guard`] `capturedEnv`'s
   `defeq`-to-`Env` is convention-only; nothing pins it.** `capturedEnv : List (Nat × List
   Field)` (`Value.lean:524`) is *defeq* to `Eval.Env`, and the eval arm relies on that to
   thread it into `evalValueWithFuel` with no coercion (`Eval.lean:1052-1053`). But the
   equality is enforced only by the docstring — if `Frame`/`Env` (`Eval.lean:756,763`) ever
   gains a field or changes shape, `Value.closure` silently desyncs and the no-coercion
   thread breaks at a distance. This is the one type-system finding: the invariant the repo
   exists to encode is currently carried by a comment. **Fix-slice:** add a zero-cost guard
   that fails the build on desync — either `example : (List (Nat × List Field)) = Env := rfl`
   in `Eval.lean` (cheapest; pins the abbrevs equal), or a one-line `abbrev` re-export so
   the closure ctor and `Env` share a single source-of-truth name. Prefer the `rfl` example
   — it adds the type-system tripwire without touching the layering. LOW risk but wants its
   own slice (touches `Eval.lean`, must re-verify); not inline-trivial. **Slice 3 does NOT
   depend on this** — flag it as a cheap hardening slice to land alongside or just after.

2. **[CLEANUP — doc accuracy, fold into slice-4 sub-spike] "mirrors the depth>0 ref arm"
   is imprecise and could mislead slice 4's cycle design.** The slice-2 breadcrumb and
   commit say `visited := []` "mirrors the depth>0 ref arm that resets visited on crossing
   into an outer frame." It does not mirror it exactly: the depth>0 ref arm
   (`Eval.lean:921`) resets to `[id.index]` (seeding the slot just crossed) and rebases env
   to `frame :: outer`; the closure arm resets to `[]` and swaps the *whole* env. The `[]`
   is **correct** for a closure (wholesale env swap → no incoming slot to seed), but the
   "mirrors" framing hides that the two cases differ in exactly the dimension slice 4 cares
   about (self-referential captured frames + `visited` cycle keying). **Action:** the
   slice-4 design sub-spike must derive its `visited`/cycle handling from first principles
   (the closure is a fresh eval entry → `visited` starts empty → the normal `slotVisited`
   machinery catches a self-ref reached via a depth-0 ref into `capturedEnv`), NOT by
   analogy to the ref arm. No code change; correct the framing in the slice-4 spike notes.

3. **[CLEANUP — test strength, fold into slices 3-5] eval pins miss the self-referential
   captured frame — the exact shape slice 4 introduces.** The 5 slice-2 eval pins cover
   captured-binding force, empty env, nested closure, lexical-vs-dynamic, and fuel
   exhaustion. The lexical-vs-dynamic pin (`EvalTests.lean:924`) IS distinguishing (slot-0
   collision: call-site `"callsite"` vs captured `"captured"`, asserts `"captured"` — would
   fail under dynamic scope), so that one is honest. Gap: no pin forces a closure whose
   `capturedEnv` contains a frame that refs *itself* (a depth-0 self-ref binding), which is
   the precise cycle shape slices 3-4 produce. Until a producer exists this can only be a
   hand-built `.closure` literal, but it would pin that `visited := []` + `slotVisited`
   terminates (→ `.top`) rather than looping/exhausting fuel. **Action:** add this pin in
   slice 4 (when the self-ref capture becomes real) or as a hand-built literal earlier; the
   slice-5 edge-case audit already lists the cycle/closed/pattern interplay — extend it to
   the self-ref captured frame explicitly.

4. **[CLEANUP — output honesty, low priority] `formatValueWithFuel` prints a closure body
   with no deferred-marker.** `Format.lean:213-216` prints `.closure _ body` as just
   `formatValueWithFuel fuel body` — a stray unforced closure is indistinguishable from its
   body in formatted output. Manifest correctly emits `.incomplete` (non-concrete); Format
   is debug/surface syntax so this is far less load-bearing, and the captured env genuinely
   is internal machinery. But once slices 3-4 make closures reachable, a formatted closure
   silently lying about being deferred could mask a "closure leaked to output" bug. **Action
   (deferrable):** consider a thin marker (e.g. wrap or a comment prefix) once closures are
   producible; not worth a change while the constructor is dead code. Track as a slice-5
   edge-case audit item ("does a leaked closure ever reach Format/Manifest output").

### Non-findings (checked, no action)

- **`valueTag = 29`**: collision-free (no duplicate tags; 29 is the max), participates in
  the shallow memo hash via `valueTag key.value` (`Eval.lean:791`) — stable and correct.
- **Memo sharing of forced closures**: the eval arm forces via the memoized
  `evalValueWithFuel`, so two closures with the same `capturedEnv` ids + `body` share a
  cache entry. Desirable (same lexical closure = same result); `fuel` stays in `EvalKey`.
- **`fuel = 0` passthrough of an unforced closure**: degrades through `| 0, value => pure
  value` (`Eval.lean:905`) — no crash/loop; downstream manifest/format see a raw `.closure`
  and emit `.incomplete` / print the body. Safe; consistent with every other arm.
- **DRY**: the `.closure` eval arm shares no duplicable logic with the depth>0 ref arm
  (different rebase + visited handling, as finding 2 notes) — no helper extraction warranted.
- **BEq/Repr**: derived, extends to the new arm; the 3 BEq pins (self/distinct-env/
  distinct-body) cover the round-trip the producer/meet slices must not corrupt.

## Architecture Fix-Slices (Phase B audit 2026-06-18 — post Value.closure slices 1-2, churn-authorized, AUTHORITATIVE)

Whole-module-graph pass after the two closure slices (`26a2040` ctor + inert wiring,
`15c92ec` eval arm) and the Phase A clear (`a347386`). **New mandate this pass:** chakrit
lifted the prior "too risky / defer" veto on parked cleanups — "do all the big churn
slices, just keep tests green and honest." So the LOW/no-benefit items the #6 ranking
parked (item 7: `EvalOps`/regex extraction, `embeddedList.decls` newtype; item 2:
test-module splits) are RE-JUDGED here on architectural merit, with the churn-risk veto
gone. Verify gate green at audit time: `lake build` 86 jobs, `check-fixtures.sh` "fixture
pairs ok", tree clean at `a347386`. Oracle: `cue` v0.16.1. **Plan-only pass — no inline
code change** (every actionable item is a multi-file move, above the inline-trivial bar).

### Headline verdict — module graph HEALTHY, layering intact after the closure ctor

The #6 acyclic-DAG verdict still holds; re-confirmed, not re-derived. Import edges
unchanged by the closure work: `Value ← {everything}`; `Decimal/Lattice/Normalize/Order/
Resolve/Format/Parse ← Value`; `Eval ← {Builtin, Decimal, Lattice, Normalize}`; `Builtin ←
{Lattice, Decimal, Base64, Json, Yaml}`; `Manifest ← {Format, Lattice}`; `Runtime ←
{Eval, Format, Lattice, Parse, Resolve, Json, Yaml}`; `Cli ← Runtime`; `Module ← {Parse,
Runtime}`. `Builtin → Eval` forbidden edge absent. No cycle, no back-edge.

**The closure ctor does NOT muddy the Value/Eval boundary — it's the layering-correct
shape.** The concern: a closure carries an Eval-laziness concept (a captured env) yet lives
in the leaf `Value.lean`. Resolution is exactly the one the plan predicted and it's the
*right* one: the ctor carries `capturedEnv : List (Nat × List Field)` — raw product data,
not an `Eval.Env` *name* — so `Value.lean` imports nothing from Kue and stays a true leaf
(confirmed: zero `import Kue.*` in `Value.lean`). Eval threads its `Env` (an `abbrev` over
the identical product) in with zero coercion *because the types are defeq*, not because of
a shared name. This is illegal-states-friendly: the env-as-data lives at the layer that can
hold it without inverting the graph. The only soft spot is that the defeq is convention-
only (Phase-A finding 1, `closure-env-sync-guard`) — re-affirmed below as the one genuine
type-system fix the closure family still owes.

### Re-judged parked cleanups (churn veto lifted — verdict per item)

1. **`evalAdd…evalBinary` pure-op family → `Kue/EvalOps.lean` (old item 7) — ACTIONABLE
   NOW.** The op family (`Eval.lean:369–625`, ~256 lines: `evalAdd/Sub/Mul/Div`, `evalEq/
   Ne`, `evalPrimitiveOrdering`, `evalRegex*`, `evalBoolBinary`, `evalNumPos/Neg`,
   `evalUnary`, `evalBinary`, + `classifyDefinedness`/`evalPresenceTest`) is a self-contained
   pure-`Value → Value` dispatch: it takes NO `EvalM`/fuel/env, and (verified) depends only
   on `Value` (types + `stringRegexMatches`) and `Decimal` (`evalDecimalBinary?`,
   `addDecimalValues`, `evalDecimalCompare?`, …) — NOT on `Builtin`/`Lattice`/`Normalize`,
   Eval's other three imports. So `Kue/EvalOps.lean` importing `{Value, Decimal}` is clean,
   sits strictly below `Eval`, and `Eval` imports it. **Merit (not just cohesion):** it
   carves the one block of `Eval.lean` (1197 lines) that has nothing to do with the
   fuel-threaded recursive evaluator — `Eval` becomes "the recursive `mutual` evaluator +
   its frame/ref/comprehension machinery", and the scalar algebra moves to a leaf where the
   closure/producer slices never have to scroll past it. **Size:** MEDIUM-mechanical — move
   ~256 contiguous lines + their handful of small helpers (`charsLt`/`stringsLt`,
   `negateFloatText`), add one import line, no behavior change (pure move). **Sequencing vs.
   closure slices 3-4: MUST INTERLEAVE, do NOT parallelize.** Slices 3-4 edit `Eval.lean`'s
   `.selector`/`.conj`/meet arms (`evalValueCoreWithFuel`, lines 899+) and the op family
   moving OUT shifts every line number below 369 — a guaranteed merge collision. Land this
   either BEFORE slice 3 (cleaner diffs for 3-4 afterward) or AFTER slice 5 (closure work
   fully settled). Recommend AFTER slice 5: the closure producer/meet design is still in
   flux and may add op-arm-adjacent code; moving the ops out from under an in-flight feature
   risks a confusing rebase. Net: real readability/boundary win, mechanical, but it owns
   `Eval.lean` so it serializes against the closure batch.

2. **Regex engine → `Kue/Regex.lean` (old item 7) — ACTIONABLE NOW, independent.** The
   engine (`Value.lean:567–809`, ~240 lines: `RegexAtom` + parse/match, ending at
   `stringRegexMatches`) depends only on `Char`/`String` — zero `Value`-specific reference
   (verified: it sits *after* the `Value` inductive and `Import`/`ParsedFile`, but none of
   its defs mention `Value`). Only `Eval` (`evalRegex*`) and `Builtin` consume
   `stringRegexMatches`. **Merit:** `Value.lean` (809 lines) carries the `Value` inductive +
   `DecimalValue` + bound/domain/field types + the regex engine; everything EXCEPT regex is
   in `Value`'s own ctor closure and MUST precede it in-module (#6's KEEP-WHOLE verdict,
   still right). The regex block is the ONE genuinely separable ~240-line chunk — extracting
   it makes `Value.lean` exactly "the value model + its forced-companion types" and gives the
   regex engine its own testable home. `Kue/Regex.lean` is a new leaf (imports nothing);
   `Value.lean` need not import it (regex isn't used by `Value`'s ctors); `Eval`/`Builtin`
   add `import Kue.Regex`. **Size:** MEDIUM-mechanical, pure move. **Sequencing: FULLY
   PARALLEL with closure slices 3-4** — it touches `Value.lean` (delete a trailing block)
   and `Eval`/`Builtin` (add an import) but NOT the closure-relevant regions (`Value`
   inductive at 465–524, `evalValueCoreWithFuel`). The only `Value.lean` overlap risk is
   trivial (the closure ctor is at 524, far above the regex block at 567+; deleting 567+
   doesn't move the ctor). Can run in its own subagent concurrently. **This is the single
   best parallel-safe cleanup of the batch.**

3. **`embeddedList.decls` → `NonOutputField` newtype (old items 5/6) — STILL-NOT-WORTH-IT
   (merit, not risk).** The invariant "decls = non-output fields only" is enforced by the
   `declFields` filter at the one construction site, not the type. A `NonOutputField`
   newtype (a `Field` refined to `¬ producesOutput fieldClass`) WOULD make it
   unrepresentable — but the cost isn't churn-fear, it's that the newtype ripples through
   every `embeddedList` consumer (Manifest, Format, Eval-select, Lattice-meet) which all
   currently treat `decls` as plain `List Field` and would need wrap/unwrap at each boundary,
   re-introducing exactly the `.val` noise the newtype is meant to remove — and the
   construction is a SINGLE site already funnelled through `declFields`, so the illegal state
   is already unreachable in practice. Net illegal-states win is marginal (one guarded
   constructor) against real readability cost at ~5 consumer sites. The merit bar, not the
   churn bar, fails it. **Verdict unchanged from #6: defer indefinitely.** (Re-open only if a
   second `embeddedList` constructor ever appears — then the single-site guarantee breaks and
   the newtype earns its keep.)

4. **Deferred test-module splits (`FixturePorts` 2314, `FixtureTests` 1033, `BuiltinTests`
   735) — STILL-NOT-WORTH-IT for `FixturePorts`; the other two ride the test-org pass
   (item 5).** `FixturePorts.lean` (2314 lines) is one generated `def fixturePorts : List
   FixturePort` — 145 entries interleaved by subsystem. The #6 SAFE-FAILURE verdict
   (brace-block surgery + reorder of a generated list, high-risk/low-reward) survives the
   veto lift on MERIT: splitting a single generated `List` literal across modules buys
   nothing architecturally (it's data, not logic; no boundary to clarify) and the
   `write-fixture-ports.lean` generator would need to learn multi-file output — real
   complexity for zero structural gain. **Leave whole.** `FixtureTests`/`BuiltinTests` are
   genuine theorem modules and CAN split by subsystem — fold into the test-org pass below,
   not a standalone churn slice.

### Closure-family architectural impact (this pass's primary new lens)

- **No illegal-states regression introduced.** The closure ctor admits no nonsense combo
  (any `List (Nat × List Field)` + any `Value` body is a legal deferred closure). The five
  inert consumer arms route consistently (#A finding non-findings confirm). No new
  catch-all `_` over `Value` — verified the new ctor is handled at every exhaustive site.
- **The ONE owed type-system fix is the env-defeq tripwire (Phase-A finding 1,
  `closure-env-sync-guard`) — RE-AFFIRMED as ACTIONABLE NOW, highest priority of the batch.**
  `capturedEnv`'s defeq to `Eval.Env` is the load-bearing invariant the no-coercion thread
  rides on, and it's pinned by a docstring only. A one-line `example : (List (Nat × List
  Field)) = Eval.Env := rfl` in `Eval.lean` converts the convention into a build-time
  tripwire (fails the build if `Frame`/`Env` ever changes shape). **Size: trivial (one
  line), touches `Eval.lean`.** Because it touches `Eval.lean` it serializes against the
  closure slices like item 1 — fold it into slice 3 (it's a 1-line add in the same file the
  producer edits) OR land it standalone immediately before slice 3. This is the cheapest,
  highest-merit item in the whole pass: it's the type-system-first fix the closure
  representation actually needs, not a cosmetic move.

### Test / fixture organization — reorg slice WARRANTED, MEDIUM priority

`Kue/Tests/` has grown to 21 modules / 8301 lines; two are oversized theorem modules:
`EvalTests` (950), `FixtureTests` (1033), `BuiltinTests` (735), `StructTests` (765). The
2c tests-out reorg (`9f9437e`) moved them into `Kue/Tests/` but deferred the size splits.
**Recommend a single test-org slice** (the loop's periodic pass, now due): split
`FixtureTests`/`BuiltinTests`/`StructTests`/`EvalTests` by subsystem (e.g. `BuiltinTests`
→ strings/list/math/regex submodules), each re-imported from `Kue/Tests.lean`; leave
`FixturePorts` whole (item 4 above). `testdata/` (203 `.cue` under `cue/`/`export/`/
`modules/`) is sensibly grouped — no reorg needed there. **Priority: MEDIUM** — schedule it
AFTER the closure batch (slices 3-5) lands, NOT interleaved: `EvalTests`/`StructTests` gain
closure pins in slices 3-5, so splitting them now would immediately go stale. Park until
the closure feature is pinned, then split once.

### Ranked next-work list (Phase B 2026-06-18 — supersedes #6's item 7 ranking)

Recommendation: the closure batch (slices 3-5) stays the spine. Slot the cleanups around
it by `Eval.lean` contention: regex extraction runs PARALLEL (own file region); the
env-defeq tripwire folds INTO slice 3 (1 line, same file); EvalOps extraction + test-org
wait until AFTER slice 5 (both serialize against in-flight `Eval.lean`/test churn).

1. **[TRIVIAL — type-system, fold into slice 3 or land just before] `closure-env-sync-guard`
   tripwire** — `example : (List (Nat × List Field)) = Eval.Env := rfl` in `Eval.lean`.
   Highest merit/cost ratio; the one fix the closure rep actually owes. Serializes vs.
   closure slices (touches `Eval.lean`).
2. **[MEDIUM-mechanical — PARALLEL-SAFE] Regex engine → `Kue/Regex.lean`.** New leaf;
   `Value.lean` loses ~240 lines (567–809); `Eval`/`Builtin` add `import Kue.Regex`. Touches
   no closure region → run concurrently in its own subagent.
3. **[MEDIUM-mechanical — AFTER slice 5] `evalAdd…evalBinary` → `Kue/EvalOps.lean`.** New
   module importing `{Value, Decimal}`, below `Eval`; move ~256 lines (369–625) + small
   helpers. MUST interleave (not parallel) — owns `Eval.lean`; land after the closure batch
   settles.
4. **[MEDIUM — AFTER slice 5] Test-org pass.** Split `FixtureTests`/`BuiltinTests`/
   `StructTests`/`EvalTests` by subsystem; leave `FixturePorts` whole. Wait until closure
   pins land so the split doesn't go stale.
5. **[DEFER indefinitely] `embeddedList.decls` newtype** — single-site invariant already
   unreachable; newtype's wrap/unwrap cost outweighs the marginal win. Re-open only if a
   second `embeddedList` constructor appears.

## Audit Fix-Slices (cleanup batch — LIGHT Phase A + Phase B, audit 2026-06-17 #7)

Light combined audit over the 3 small/mechanical cleanup slices since `3827fb7`:
`9f9437e` (tests-out reorg), `7d0657d` (base64 leaf), `e9c3c03` (Linux `cacheRoot`).
Verify gate green at audit time: `lake build` 86 jobs, `check-fixtures.sh` "fixture pairs
ok". Oracle: `cue` v0.16.1.

### Verdicts (all CLEAR — no findings, nothing to fix)

- **No silent test loss (reorg).** `Kue/Tests.lean` imports all 21 `Kue.Tests.*` modules +
  carries its own lattice theorems; `Kue.lean` imports `Kue.Tests`. Build elaborates all 21
  (21 individual `.olean` artifacts present, names matching imports 1:1; 86 jobs). No
  module compiles-but-unimported.
- **base64 leaf, no cycle, behavior-identical.** `Kue/Base64.lean` has ZERO imports (true
  leaf — nothing from Json/Yaml/Builtin). Three consumers (`Json`, `Yaml`, `Builtin`)
  import it. Body is a byte-identical move from old `Json.lean` (same alphabet, same
  bit-ops, same padding branches); base64 fixtures unchanged → behavior preserved.
- **`cacheDirFor` correct + isOSX wiring honest.** Pure helper: precedence `CUE_CACHE_DIR`
  → `XDG_CACHE_HOME/cue` → per-OS (`~/Library/Caches/cue` if `isOSX` else `~/.cache/cue`).
  IO wrapper `cacheRoot` passes the REAL `System.Platform.isOSX` (not hardcoded). Missing
  HOME → `home.getD ""` → `/.cache/cue`, no crash. 5 `native_decide` theorems are real pins
  (both OS branches, both precedence levels, missing-HOME).
- **Layering clean (Phase B).** No `Builtin → Eval` edge. New `Base64` leaf adds no
  back-edge; `Kue/Tests/` subdir is referenced only by `Kue/Tests.lean` (no source module
  imports a test module). Acyclic.

### Re-rank

No new fix-slices. Item 3 in the authoritative list (#6 below) is now DONE: 3a (base64)
and **3e (`Field` tuple → `structure`)** both landed. 3e: `abbrev Field = String ×
FieldClass × Value` → `structure Field where label; fieldClass; value`, defined mutually
with `Value` (the struct-bearing `Value` constructors carry `List Field`, which is no
longer defeq to the tuple once `Field` is a structure, so the mutual block is forced).
Derived `Repr, BEq` preserved byte-identically (all `native_decide`/`rfl` theorems +
fixtures pass unchanged, NO `rfl`→`native_decide` switch needed). ~70 tuple-literal/positional
sites migrated to `⟨…⟩`/`.label`/`.value` (build as ground truth). With 3e done, the
consolidation/cleanup batch is essentially complete (only deferred module-splits + LOW
items remain). Next SUBSTANTIVE item for real-file reach: **package-dir merge** (multi-file
packages like argocd.cue — larger loader slice, needs a design pass). Defer package-dir
merge (item 5) / registry fetch (item 6) until full `cue export ./apps` parity is wanted.

## Audit Fix-Slices (CLI/serializer family — Phase A + light Phase B, audit 2026-06-17)

Combined Phase A + light Phase B over the CLI/serializer batch since `b3aeb53`/`7cf387f`:
`d1c1cd2` (`kue export -e <expr>` field-path selector) and `d8c44e7` (YAML scalar
over-quoting rewrite: `wouldParseAsNonString`). Verify gate green at audit time
(`lake build` 84 jobs, `check-fixtures.sh` "fixture pairs ok", `shellcheck` clean).
Oracle: `cue` v0.16.1 (`/Users/chakrit/go/bin/cue`).

### Headline verdicts

- **YAML predicate — no false-bare (silent-corruption) case found; one false-bare
  byte-divergence FIXED inline.** Two adversarial batteries (~127 strings: edge numbers,
  specials, unicode, all-punctuation, doc markers, IP/semver/CIDR/`name:tag`) diffed
  kue-binary vs `cue export --out yaml`. Number/bool/null/date/base60 classification agrees
  exactly with cue on every case, including the tricky `-.NaN`→bare, `+`→bare/`-`→single,
  `0x_1`→quoted, `99:99`/`60:00`→quoted. The NFAs (`yamlStyleFloat`, `yamlCueDateLike`,
  `yamlRadixInt`, `yamlBase60Float`, `yamlReservedWords`) are **total** — all structural,
  no `partial`, terminate on empty/long/unicode/all-punct. **One miss FIXED:** kue emitted
  bare for scalars starting with `...` or `---`+non-dash (`...`, `....`, `...x`, `---x`,
  `--- x`) where cue single-quotes (go-yaml document-marker prefix rule). Verified the bare
  form still round-trips as a string through go-yaml's own resolver (so not confirmed
  corruption — MEDIUM byte-divergence, not HIGH), but fixed regardless via a
  `yamlDocMarkerPrefix` guard in `yamlNeedsSingleQuote`. Pure dash-runs `---`/`----`
  stay double-quoted upstream (date-like split), matching cue.
- **`-e` selector — correct, no regression.** Dotted paths, cross-segment ref binding
  (`-e a.b` resolves `b`'s refs in `a`'s scope via `resolveAndEval` between steps),
  chained refs, missing field → `reference "<seg>" not found` + exit 1 (matches cue text),
  empty/leading/doubled-dot segment → clean error exit 1, missing `-e` value → exit 2.
  `selectExprPath`/`parseExprPath`/`lookupField?` total. Plain export (no `-e`) byte-identical
  to before (JSON+YAML). CUE divergence logged: `cue export -e` ignores stdin entirely
  (resolves against empty scope → every selector fails); kue correctly selects from stdin
  in both file and stdin mode (see `cue-divergences.md`).
- **Phase B (light) — layering unchanged, acyclic preserved, ALPHA-READY.** No new module;
  `Cli→Runtime→{Eval,Format,…}`, `Main→{Kue,Cli}`, `Yaml→Json`. `Runtime` already imported
  `Eval`; `-e` reuses `findEvalField`/`resolveAndEval` — no new edge. `Builtin→Eval` still
  absent. Build + full suite green, no half-landed work, no crash; known gaps (B3d registry
  fetch, package-dir merge) documented. **HEAD `d8c44e7` is releasable — cut
  `v0.1.0-alpha.20260617.3`** (note: the doc-marker fix below lands a new HEAD; cut from
  that).

### Findings (ranked)

1. **[MEDIUM — silent byte-divergence, FIXED inline this audit] YAML doc-marker prefix.**
   `wouldParseAsNonString`/`yamlNeedsSingleQuote` missed `...`-prefix and `---`+non-dash
   scalars. Fixed via `yamlDocMarkerPrefix` + 7 new theorems in `YamlTests.lean`. Round-trip
   verified safe; output now byte-matches cue. Gate re-run green; committed.
2. **[LOW — cosmetic false-quote] Leading/edge underscore over-quoting.** kue's blanket
   `yamlStripUnderscore` collapses `_`-runs before number classification, so `_1`, `_1_`,
   `__1`, `1_2:3`, `1_:2` get double-quoted where cue leaves them bare (go-yaml admits `_`
   only strictly between two digits). Direction is safe (over-quote never corrupts). Fix:
   gate the underscore strip on "`_` flanked by digits on both sides" before feeding the
   number NFAs; re-pin the existing `1_000`/`1_2`/`0x_1` quoted cases. Scoped, deferrable.
3. **[LOW — test strength] `-e` Runtime edges unpinned.** Only `select_common.*` (happy
   path) is a fixture; missing-field/empty-segment/scalar-descent are verified manually
   here but not by any theorem or fixture. Add `native_decide` theorems for `parseExprPath`
   (empty/leading/trailing/doubled dot → none; normal → segments) and `selectExprPath`
   (missing segment → error; scalar-descent → error; happy multi-segment), plus error/edge
   `.args` fixtures. The parse layer (CliTests) is well covered; the gap is the selection
   layer.
4. **[LOW — type leverage, Phase B] `ExportOpts.expr : Option String` re-parsed at use.**
   The unparsed dotted path is re-split in `exportValueSelecting`; an empty segment is an
   illegal state caught at use, not construction. Tighten by parsing to a validated
   `List`-of-nonempty-segments at the CLI boundary (validate-at-boundary). Minor; fold low.
5. **[LOW — DRY / error-precedence] Main stdin path re-implements `exportSourcesToString`.**
   `runExport`'s stdin branch inlines `parseSources`/`checkSourcePackageNames`/
   `mergeSourceValues` to thread `exportBoundValue`, and **reverses** the original error
   order (`parseSources` before `checkSourcePackageNames`; the shared helper checks package
   names first). Observable only as a differing error message on a malformed single stdin
   source (both still exit `evalErrorCode`). Fix at source: add a
   `exportSourcesSelecting`/`exportBoundSources` Runtime helper that mirrors
   `exportSourcesToString`'s order and takes the `-e` expr, and call it from both Main
   branches. Removes the duplication and the reorder.
6. **[LOW — message divergence, not kue-right] `-e` descent into a scalar.** `-e top.x`
   where `top` is an int: kue says `reference "x" not found`, cue says `invalid operand top
   (found int, want list or struct)`. Both exit 1. cue's message is more precise. Optional:
   distinguish "not a struct" from "field absent" in `lookupField?`/`selectExprPath`.

## Audit Fix-Slices (bound-representation family, Phase A audit 2026-06-17)

Phase A depth pass over `aa5987f` (test/fixture reorg — pure moves), `d87d6dd`
(`boundConstraint` fold 4→1 + canonical conj sort + commutativity theorems), `073e1d9`
(decimal-valued, domain-tagged bounds). Verify gate green at audit time (`lake build` 84
jobs; `check-fixtures.sh` "fixture pairs ok"; shellcheck clean). **This batch closes the
two open findings of the prior Phase A audit (non-commutative conj form #1; `float & >0`
wrongly bottoms #2) — both confirmed fixed below.** No new HIGH/MEDIUM findings.

**HEADLINE — commutativity preserved AND `int`-narrowing airtight (no float past `int`).**
Probed adversarially against cue v0.16.1 across permuted arg orders:
- *Commutativity holds on the canonical form.* `int & >0 & <=10` formats identically
  (`int & >0 & <=10`) in all 5 tested permutations; `(int & >=0) & (>=0 & <=5)` dedupes the
  doubled `>=0` to `int & >=0 & <=5` in both orders; bare-range `>=0 & <=10 & 5.5` → `5.5`
  in all orders; `int & <2.50 & >0.5` → `int & >0.5 & <2.5` in all orders (trailing zero
  trimmed). The `sortConjMembers`/`conjMemberLe` canonical sort is load-bearing and works.
- *`int`-narrowing is airtight.* `int & >0 & 1.5` → ⊥ in EVERY permutation; `int & >0.5 & 0`
  → ⊥; `float & >0 & 1` → ⊥; `float & >0 & 1.0` → `1.0`; bare `>0 & 1.5` → `1.5`. No path
  found where a float sneaks past an `int` conjunct. Mechanism confirmed sound: the bound
  keeps `number` domain and the kept `kind` conjunct (not bound-domain mutation) does the
  narrowing, so range members need no per-member narrowing — all oracle-matched.
- *Decimal compare is exact (no float rounding, no hand-rolled compare — reuses the
  rational order via `decimalLeValues`/`decimalLtValues`).* Strict/non-strict at boundary:
  `>0 & 0`→⊥, `>=0 & 0`→`0`; trailing-zero/scale: `>0.50 & 0.5`→⊥, `>=0.50 & 0.5`→`0.5`,
  `>0.5 & 0.50`→⊥; negatives: `>-1.5 & -1.5`→⊥, `>=-1.5 & -1.5`→`-1.5`. All oracle-matched.
- *`conjMemberKey` is a total order over DecimalValue limits* — `mergeSort conjMemberLe`
  converges to one canonical order in every permutation tested (the empirical commutativity
  evidence above). Decimal tie-break compares limits directly via `decimalLeValues` so
  different scales (`>0.5` vs `>0.50`) order deterministically.
- *Parse of `>0.5`/`>=-1`/`<3.14` is total and correct*; malformed bounds (`>`, `>=`,
  `<x`, `>0.5.5`) error cleanly with position.
- *Module move (`DecimalValue` → `Value.lean`) clean:* no import cycle (`Value` imports
  only `Init`; `Decimal.lean` imports `Value`, correct direction); `Decimal.lean` still
  compiles reusing it; `minInt`/`maxInt` fully removed, zero references remain.
- *`NumberDomain` is a tight 3-way sum* (`number`/`int`/`float`), not a flag; `admitsKind`/
  `narrow`/`kind`/`rank` all total exhaustive matches, no catch-all over the domain.
- *No wildcard swallows a new constructor:* `Format`/`Manifest` handle `boundConstraint`
  explicitly; the Manifest diff REPLACED a `FieldClass` catch-all with explicit
  `.regular`/`.optional`/`.letBinding` arms (philosophy win). `meetCore` has the bound arms
  enumerated. `DecidableEq`/`BEq` deriving intact on the richer `Value`.
- *Test-reorg sanity:* reorg commit `aa5987f` was a clean 141→141 (no fixture
  dropped/added/double-counted by the recursive glob); the bounds commit legitimately added
  3 (→144), each with a `.cue`/`.expected` pair AND a `FixturePorts` entry. The "141
  unchanged" claim in the audit scope referred to the reorg commit specifically — confirmed.

### Findings (ranked — all LOW)

1. **[LOW — stale name] `BottomReason.intBoundConflict` now covers decimal/float bound
   conflicts too.** `meetBoundPrim`/`meetRangePrim`/`meetTwoBounds` all emit
   `.intBoundConflict` for any out-of-bound or infeasible-range case, including
   `>0.5 & 0.25` and `>5 & <3` — no longer int-specific. Rename to `boundConflict` (or
   `numericBoundConflict`) for accuracy. Cosmetic (doesn't affect the `_|_` rendering); fold
   into the float/math family rename pass.

2. **[LOW — latent fragility, not a live bug] `meetRangePrim` conj arm discards the second
   bound's domain (`_`).** The `.conj [boundConstraint .. lowerDomain, boundConstraint .. _]`
   meet-with-prim arm uses `lowerDomain` and ignores the upper member's domain. Sound today
   because `meetTwoBounds` always builds the 2-bound conj with both members sharing the
   narrowed domain (invariant verified by construction), so the two are equal. But the type
   doesn't enforce that invariant — a hand-built `.conj` of two differently-domained bounds
   would silently use only the first. Either assert equality, or (cleaner) introduce a
   `Range` representation that carries one domain for both sides, making the mismatch
   unrepresentable. Track for Phase B (type-tightening).

3. **[LOW — test strength, FIXED inline this audit] Trailing-zero precision tie now pinned
   at the theorem level.** `>0.50 & 0.5`→⊥ (and the scale-mismatch family) was covered
   behaviorally via CLI/oracle but had no `native_decide` theorem; the existing decimal
   theorem used `0.5` vs `1.0`/`0.25` (different magnitudes, not a same-value-different-scale
   tie). Added `meet_decimal_bound_trailing_zero_tie` to `BoundTests.lean` pinning
   `meet (>0.50) (0.5)` → ⊥ and `meet (>=0.50) (0.5)` → `0.5`. Regression-locked.

**Closed-by-this-batch (prior Phase A findings):** #1 (non-commutative canonical conj form)
— FIXED by `d87d6dd`'s `sortConjMembers`; commutativity now holds + theorems pin it. #2
(`float & >0` wrongly bottoms) — FIXED by `073e1d9`'s domain-tagged bounds; `float & >0` →
`float & >0`, `float & >0 & 1.0` → `1.0`, oracle-matched.

**CUE display divergence (cosmetic, not a Kue bug):** cue prints `uint` sugar for
`int & >=0` (`int & >0 & <=10` → `uint & >0 & <=10`; `(int & >=0) & (>=0 & <=5)` →
`uint & <=5`); Kue prints the desugared `int & >=0` form. Semantics identical. Candidate
for `cue-divergences.md` only if Kue ever claims display-parity on `uint`; not a finding.

## Audit Fix-Slices (int-bound-retention + CLI + open-list family, Phase A audit 2026-06-17)

Phase A depth pass over `e98fb65` (int-bound kind retention + `meetConjValueWith`
flat-set rewrite), `7697b1d` (CLI `Command` sum type), `d94af33` (open-list manifest
collapse). Verify gate green at audit time (`lake build`, `check-fixtures.sh`, shellcheck
all pass). Headline verdicts below; findings folded as fix-slices.

**`meetConjValueWith` algebra — SOUND but NOT a canonical commutative form.** Probed
adversarially: no dropped constraint (value-satisfaction is order-invariant — `8080`
admitted by `int & >=0 & <=65535` under any arg order), no duplicated constraint (`int &
>0 & >0` → `[int, >0]`), bounds still tighten (`>5 & >0` → `>5`), idempotent on the merged
form. **But the resulting `.conj` member *order* is argument-order-dependent**, and
structural `BEq` on `.conj` is order-sensitive, so `a & b != b & a` as canonical values.
Concrete: `(int & >0) & (>0 & <10)` formats `int & >0 & <10`; the commuted product formats
`<10 & int & >0` — same constraint, two user-visible outputs; cue's display order is
canonical (kind first). Root cause: `addConstraintWith` appends a non-merging constraint
at the position it lands, and RHS members fold in after LHS `initial`. Pre-existing meet
arms already hardcode a kind-then-bound order (e.g. `.intGe & .intGt → .conj [.intGe,
.intGt]`), so the convention exists but isn't enforced post-fold.

### Findings (ranked)

1. **[MEDIUM — non-commutative canonical conj form] Sort `.conj` members into a canonical
   order after the flat-set fold (or make `.conj` equality order-insensitive).** Sound
   today (no mis-admit/reject), but `a & b` and `b & a` produce different `Value`s and
   different formatted output, and any future equality/dedup/memoization keyed on `.conj`
   structure will see them as distinct. Fix: canonicalize member order in
   `meetConjValueWith`'s re-wrap (kind first, then bounds by op, then others) — cheap,
   total, and makes the type carry the "set, not sequence" invariant. TDD: add
   commutativity theorems (`meet a b == meet b a`) for the 3-way / mixed-side cases that
   currently diverge.

2. **[LOW — pre-existing divergence, NOT this slice] `float & >0` wrongly bottoms.** cue
   v0.16.1: `float & >0` → `float & >0`; Kue → `bottomWith [kindConflict float int]`. NOT
   a regression — old code used `kindAcceptsKind kind .int` which is also `false` for
   float, and `meetKindWithIntBound` preserves that. Stems from the integer-restricted
   bound model (only `intGt`/`intGe`/… exist; no float bounds). Track as a bound-model gap
   for the float/math family; log in `cue-divergences.md`. `int`/`number`/`bool`/`string`
   bound×kind pairs all match the oracle.

3. **[LOW — DRY] CLI flag-scan + help-flag handling duplicated.** `args.find?
   (·.startsWith "-")` appears in both `parse` and `parseExport`; `--help`/`-h` arms repeat
   across `parse`/`parseEval`/`parseExport`. Acceptable (distinct error text per context);
   extract only if a fourth subcommand lands.

4. **[LOW — minor CLI divergence] `--` not treated as end-of-flags.** Kue: `parse ["--"]`
   → `error "unknown flag: --"`. cue treats `--` as a separator. Defensible fail-closed
   given no flag takes `--`-style values; revisit if a future flag needs literal-`-`
   positionals.

**No-regression confirmations (no action):** open-list manifest mirrors the closed-list /
embedded-list arms exactly (recurse `manifestItemsWithFuel`, drop tail), non-concrete
prefix still surfaces `.incomplete`, `open_lists` fixture byte-matches cue; internal
`formatValue` (Format.lean) untouched. The 4 `rfl`→`native_decide` switches are legit
(richer fold no longer kernel-reduces; spot-checked values unchanged — `meet (.conj
[.intGe 0, .intLe 10]) (.prim (.int 7))` still `.prim (.int 7)`). All new defs total (no
`partial`; structural recursion accepted by Lean). `Command`/`ExportOpts`/`HelpTopic` sum
types tight; `parse`/dispatch total + exhaustive; exit codes consistent (usage=2, eval=1);
back-compat eval paths preserved; 25 parse theorems are real input→Command pins.

## Architecture Fix-Slices (Phase B audit 2026-06-17 #6 — post DecimalValue-move, AUTHORITATIVE)

Whole-graph pass with the type-system-first lens, after the bound family + `DecimalValue`
move into `Value.lean` landed. Phase A ran at `b3aeb53`. This is the SINGLE authoritative
ranking; #5 and below are retained as the design record only. Verify gate green at audit
time (`lake build` 84 jobs; `check-fixtures.sh` ok; `shellcheck` clean) after the one inline
fix below.

### Inline fix applied this pass

- **`BottomReason.intBoundConflict` → `boundConflict`** (Phase-A #1). Clean mechanical
  rename, 8 sites (1 ctor in `Value`, 3 in `Lattice`, 4 in `BoundTests`). The reason is no
  longer int-specific — bounds carry a decimal limit + `number|int|float` domain — so the
  `int` prefix was stale. Behavior-preserving; verify gate re-run green; committed.

### Verdicts (whole-graph, this pass)

- **`Value.lean` (795) cohesion — verdict: KEEP WHOLE, do not extract.** It carries the
  `Value` inductive + `DecimalValue` + `boundConstraint`/`BoundKind`/`NumberDomain` +
  `FieldClass`/`Optionality` + `Import`/`ParsedFile` + the regex engine. This reads as a lot,
  but every type except the regex engine is in `Value`'s own transitive closure: `Value`'s
  ctors mention `DecimalValue` (`boundConstraint`), `BoundKind`, `NumberDomain`, `FieldClass`
  (`struct`/`dynamicField`), `Prim`, `BottomReason`, `Clause` — they MUST be defined before
  `Value` in the same module (Lean has no forward refs across modules without an import, and
  `Value` can't import a module that itself needs `Value`). `Import`/`ParsedFile` are the one
  loosely-coupled pair (used by `Module`/`Parse`, not by `Value`'s ctors) but cost nothing
  where they sit. The `DecimalValue` move was correct and is NOT worth reversing into a
  `Kue/Decimal/Base.lean`: the helpers (parse/compare/format) are 160 lines but they're the
  exact surface `boundConstraint` meet/format/order needs, and a base module would just be a
  file `Value` imports — net zero illegal-states benefit, pure churn. The regex engine
  (~240 lines, lines 553–793) is the one genuinely separable block — it depends only on
  `Char`/`String`, nothing `Value`-specific — but it's stable, self-contained, and only
  `Eval`/`Builtin` consume `stringRegexMatches`; extracting to `Kue/Regex.lean` is a LOW
  cohesion-only move (item 7), not a complexity win. No extraction recommended now.
- **Module layering after the move — verdict: clean, acyclic, intended shape.** Edges:
  `Value ← {everything}`; `Decimal ← Value`; `Lattice ← Value`; `Eval ← {Builtin, Decimal,
  Lattice, Normalize}`; `Builtin ← {Lattice, Decimal, Json, Yaml}`; `Manifest ← {Format,
  Lattice}`; `Runtime ← {Eval, Format, Lattice, Parse, Resolve, Json, Yaml}`; `Cli ←
  Runtime`. The `DecimalValue` move did NOT create a back-edge: `Decimal.lean` still
  `import Kue.Value` and reuses the moved helpers — it lost types, gained nothing it
  shouldn't. `Builtin → Eval` forbidden edge absent. No cycle. No mis-placed module.
- **`meetRangePrim` discards the 2nd bound's domain — verdict: NOT A BUG, no `Range` type
  needed (Phase-A #2 RESOLVED as won't-fix).** Re-read `Lattice.lean:56–68`: `meetRangePrim`
  takes a SINGLE `domain` param, not two — both bounds in a canonical range share one domain
  by construction (`meetTwoBounds` narrows the two domains via `NumberDomain.narrow` BEFORE
  emitting `.conj [boundConstraint … domain, boundConstraint … domain]`, line 99–110, same
  `domain` in both). So there is no second domain to discard; the range is already
  domain-coherent. A dedicated `Range` type carrying one domain would just re-encode an
  invariant the construction already guarantees — and `.conj` of two `boundConstraint`s is
  what CUE displays (`>=0 & <=10`), so a `Range` ctor would need to unfold back to `.conj`
  for format/manifest anyway. Dropped from the ranking.
- **`Field` tuple → structure (item 4c/3e) — verdict: still worth doing, still rides the
  mechanical batch.** `Field = String × FieldClass × Value` with 122 `.fst`/`.snd.snd`-style
  destructures. The `Field.label`/`fieldClass`/`value` accessors already paper over it, so
  the type is loose but not actively dangerous (no nonsense combination — all three slots
  always meant). MEDIUM, churn-heavy, behavior-preserving. Keep in the cleanup batch.
- **`embeddedList.decls` invariant — verdict: LOW, unchanged.** "decls = non-output only"
  enforced by the `declFields` filter, not the type. `NonOutputField` newtype makes it
  unrepresentable but ripples through Manifest/Format/Eval/Lattice. Defer (item 6).

### Real-file export status check (read-only, this pass)

Ran `kue export` against real prod9-style `apps/*.cue` (naxon-ai/infra, hatari/infra) and
oracle-compared with `cue`. **Verdict: the engine semantics are essentially met; the
remaining gaps are CLI/loader features, not constraint-solving gaps.** Three blockers, in
bite order:

1. **`-e <expr>` expression selector — DONE (2026-06-17).** `kue export -e <path>` now
   selects a dotted field path from the root before manifesting, byte-matching `cue export
   -e` (json + yaml). Verified on `hatari/infra/apps/common.cue`: `kue export -e common`
   (and `-e common.domains`) JSON-matches cue exactly. Field-path scope only (no indices /
   repeated `-e` / arbitrary expressions — deferred, see compat-assumptions). See breadcrumb
   `docs/notes/2026-06-17-export-expr-selector-landed.md`.
2. **No multi-file package merge.** `kue export apps/argocd.cue` returns `⊥` because the
   file's definitions span sibling files in the same package (`dev.cue` etc.); kue exports
   one file, not a package dir. `cue export ./apps` merges the dir.
3. **No registry/module-cache import fetch (known B3d).** `apps/minio.cue` imports
   `prodigy9.co/defs/packs`; kue reports `unresolved import: … registry fetch is B3d`. cue
   resolves it from `~/Library/Caches/cue`.

Notable: `cue export ./apps` itself fails with `incomplete value` on argocd/gateway/minio
(these files need injected values), so the FULL-package-concrete bar is not even what cue
clears unaided — the realistic target is `-e <expr>` on a single concrete app. **Orchestrator
takeaway: the goal is in the cleanup-only tail for SEMANTICS, but NOT yet for CLI reach —
`-e` selection (and eventually package-dir merge + registry fetch) are real feature slices
standing between kue and "export a real apps file". These are loader/CLI work, not
lattice/eval work.**

### Ranked next-work list (SINGLE authoritative — recommendation after the list)

Recommendation: **the engine is done; spend the tail half on CLI reach, half on cleanup.**
The single highest-leverage real-file unblock is **item 1 (`-e` selector)** — it's small,
it's the literal thing standing between kue and exporting a real concrete app, and it
proves the export path end-to-end on real input. Do it FIRST. Then drain the churn-heavy
cleanup batch (items 2–4) while the engine is quiet, so the foundation is tidy. The
package-dir merge + registry fetch (items 5–6) are larger loader slices — schedule them
only if chakrit wants full `cue export ./apps` parity; the `-e`-on-single-file path already
demonstrates real-file viability.

1. **[DONE 2026-06-17] `kue export -e <expr>` expression selector.** Landed: `-e` /
   `--expression` parse into `ExportOpts.expr`; selection walks the dotted path via
   `Runtime.selectExprPath` (reuses `findEvalField`, resolves between segments) before
   manifest. Field-path scope; indices / repeated-`-e` / arbitrary expressions deferred.
   Real-file proof: `hatari/infra/apps/common.cue` `-e common` exports cue-identically (JSON).
1b. **[DONE 2026-06-17] YAML scalar over-quoting fixed.** The `-e` slice surfaced kue
   quoting dotted-numeric strings (IP `34.142.159.249`, semver `1.2.3`, CIDR, image tag)
   that `cue export --out yaml` emits bare. Replaced the over-broad `yamlLooksNumeric` with
   a total `wouldParseAsNonString` = the exact **union** of cue's `shouldQuote`
   (legacy-token set + date/base60/`0x` regex) and go-yaml v3's emitter (int/float/base60
   resolve). Multi-segment tokens now bare; genuine numbers/bools/nulls/dates still quoted.
   42-case oracle battery + 38 new `YamlTests.lean` theorems; `testdata/export/infra.*`
   fixture. **Whole-file `--out yaml` of `hatari/infra/apps/common.cue` is now
   byte-identical to `cue` v0.16.1.** JSON / internal `formatValue` untouched.
2. **[DONE (tests-out) — `Kue/` source-dir organization, chakrit-flagged] tests-out reorg
   (2c).** All 21 `*Tests.lean` + `FixturePorts.lean` `git mv`'d into `Kue/Tests/`, module
   paths `Kue.Foo`→`Kue.Tests.Foo`; `Kue/Tests.lean` is now the aggregator importing all 21
   (plus its own lattice theorems), and `Kue.lean` imports only `Kue.Tests` instead of ~20
   direct test imports. `FixtureTests`/`write-fixture-ports.lean`/`check-fixtures.sh`
   rewired to `Kue.Tests.FixturePorts`. 16 engine modules stay in `Kue/`. Build 84 jobs
   (unchanged — no silent test loss; all theorems still elaborated), `fixture pairs ok`
   (145 entries unchanged). **Oversized-module splits DEFERRED** (subsumed-3d still open):
   `FixturePorts` (2314) is one monolithic `def fixturePorts : List FixturePort` whose 145
   entries are heavily interleaved by subsystem (54 runs across 11 prefixes), so a split is
   brace-block surgery + reorder of a generated list, not a contiguous line-range cut —
   high-risk/low-reward, deferred per the slice's SAFE-FAILURE clause. `FixtureTests` (1033)
   / `BuiltinTests` (735) splits ride along when revisited. Source-layering
   (Core/Syntax/Eval/Output/Driver) stays OPTIONAL pending chakrit's taste call.
3. **[DONE — cleanup batch] ~~base64-out-of-Json (3a)~~ + ~~`Field`→structure (3e)~~.**
   3a landed (`7d0657d`): `base64Encode` → leaf `Kue/Base64.lean` (zero imports);
   `Json`/`Yaml`/`Builtin` import it; body byte-identical move, base64 fixtures unchanged.
   3e landed: `abbrev Field = String × FieldClass × Value` → `structure Field where label;
   fieldClass; value`, defined **mutually** with `Value` (the struct-bearing `Value`
   constructors carry `List Field`; once `Field` is a structure `List Field` is no longer
   defeq to `List (String × FieldClass × Value)`, forcing the mutual block). Derived
   `Repr, BEq` preserved byte-identically — all theorems + fixtures pass unchanged, no
   `rfl`→`native_decide` switch needed. ~70 tuple-literal/positional sites (`(l,c,v)` →
   `⟨l,c,v⟩`, `.fst`/`.snd.snd` → `.label`/`.value`) migrated, build as ground truth.
4. **[DONE — portability] Linux `cacheRoot` default** (`Module.lean`): pure `cacheDirFor`
   helper branches on `System.Platform.isOSX` so Linux defaults to `~/.cache/cue`, macOS to
   `~/Library/Caches/cue`, absent `$CUE_CACHE_DIR`/`$XDG_CACHE_HOME` (mirrors Go
   `os.UserCacheDir`). Precedence unchanged; 5 `native_decide` theorems pin both OS branches.
5. **Multi-file package-dir export (DONE, 2026-06-17).** `kue export ./apps` /
   `kue eval ./apps` (and `-e <app> ./apps`) now load the *directory* as a package: discover
   its module, then merge all same-package sibling `*.cue` via the existing `loadPackage`
   (package-name consistency + sibling meet-merge + per-file import binding). **Scope was
   contained-reuse, not a redesign** — the gap was purely at the IO entry: `loadFileBound`
   loaded a single file with no sibling merge, while `loadPackage` already did the full
   merge for *imported* packages. Added `loadPackageDir` (discover + `loadPackage` on the
   dir) and `loadEntry` (branches on `FilePath.isDir`: dir ⇒ `loadPackageDir`, file ⇒
   `loadFileBound` unchanged); Main's eval-file and export-file paths route through
   `loadEntry`. **Matches `cue`'s file-vs-dir contract exactly:** a bare file arg does *not*
   pull in package siblings (`cue export apps/argocd.cue` errors on a sibling-defined ref),
   only a dir/package arg does — so the single-file/stdin entry is byte-unchanged (all
   fixtures green). Fixture: `testdata/modules/package_dir/` (a `subpaths` fixture exporting
   the `apps` dir, oracle-matched). Real prod9 unblocked: `kue export -e portal <hatari
   apps>` now descends the whole package and reaches import resolution, surfacing the clean
   B3d deferral on `prodigy9.co/defs/packs` (next blocker, item 6). Ordering note: cue's
   field interleaving for `x: ref & {own}` (own fields first) is a pre-existing single-file
   `meet`-order divergence, independent of package merge — fixtures avoid it by using the
   real-world shape (distinct top-level fields per file, cross-file refs).
6. **[MEDIUM — real-file reach, largest, = old B3d] Registry/module-cache import fetch.**
   Resolve `prodigy9.co/defs/packs`-style imports from `~/Library/Caches/cue/mod/…`.
   Largest loader slice; required for any real app that imports prod9 defs.
7. **[LOW — cohesion] `embeddedList.decls` newtype (old 5); `Eval` arith dispatch →
   `Kue/EvalOps` (old 6); regex engine → `Kue/Regex.lean`.** All cohesion-only, no pain
   today, no illegal-states win. Defer indefinitely; do opportunistically if a neighboring
   slice already touches the area.

---

## Architecture Fix-Slices (Phase B audit 2026-06-17 #5 — consolidation batch, SUPERSEDED by #6)

Whole-graph pass with the type-system-first lens, after the int-bound-retention + CLI +
open-list family landed (`e98fb65`, `7697b1d`, `d94af33`, Phase A `20fe8fa`). This is the
SINGLE authoritative ranking; #4 and below are retained as the design record only. Verify
gate green at audit time (`lake build` 84 jobs; this pass changed no code).

### Verdicts (whole-graph, re-confirmed this pass)

- **`Main`/`Cli`/`Runtime` layering — verdict: clean, no back-edge, cohesive.** New DAG
  edge `Main → {Kue, Kue.Cli}`, `Kue.Cli → Kue.Runtime`, `Kue.Runtime → {Eval, Format,
  Lattice, Parse, Resolve, Json, Yaml}`. `Cli` is pure argv→`Command` parsing + usage text
  (no IO); `Main` owns all IO and dispatches `Command`; `Runtime` is the pure
  source→value/string façade. The `Command`/`ExportOpts`/`HelpTopic` sum types are tight
  (no nonsense combinations); `parse`/`parseEval`/`parseExport`/`runCommand` are total and
  exhaustive. No `Cli → Main` back-edge, no IO leak into `Cli`. Nothing to change.
- **`Eval.lean` (1191) cohesion — verdict UNCHANGED: keep whole.** The `meetConjValueWith`
  rewrite landed in `Lattice`, not `Eval`, so `Eval`'s shape is unchanged since #4. The
  `evalAdd…evalBinary` pure-op family remains the one clean future extraction
  (`Kue/EvalOps.lean`) but at no navigation pain today — stays LOW (item 7). No split now.
- **Module layering — verdict: clean, acyclic.** Re-confirmed the #4 DAG plus the CLI tier
  on top. `Builtin → Eval` forbidden edge still absent. No cycle, no new edge.
- **`Manifest.manifestWithFuel` (Value dispatch) — verdict: ALREADY exhaustive.** Every
  `Value` ctor is spelled out with no catch-all `_` over `Value`; the `_` patterns are all
  on `fuel` or ignored sub-fields. The Phase-A "Manifest dispatch wildcard" item refers to
  `manifestFieldsWithFuel`'s `_ =>` over `FieldClass` (line ~39) — that one stands (item 4d).
- **Loose reps (re-confirmed, all folded below):** `intGe/Gt/Le/Lt` 4 parallel ctors →
  `boundConstraint` (item 2, ~130 non-test occurrences across 9 modules — big blast
  radius); `.conj` member order arg-order-dependent so `a&b ≠ b&a` as canonical `Value`s
  (item 1, the Phase-A MEDIUM); `Field = String × FieldClass × Value` tuple → `structure`
  (item 4c, ~95 destructure sites — NOT small, rides the mechanical batch);
  `embeddedList.decls` non-output invariant unenforced by type (item 6).
- **Inline fixes applied this audit:** NONE. The Phase-A CLI flag-scan DRY nit
  (`args.find? (·.startsWith "-")` in `parse` + `parseEval`) is deliberately NOT extracted:
  each callsite carries distinct per-context error text ("unknown flag" vs "unknown eval
  flag"), which is the Code-Typography *contrast* the skill protects; extracting would
  force threading a message-builder and erase that contrast. `Field`→structure and the
  Manifest-FieldClass tighten are both larger than "small clean swap" (95 / dispatch
  behavior-adjacent) → folded, not applied.

### Ranked next-work list — recommended sequence: 1 → 2 → 3 → (4) → (5/6/7)

Rationale: do the cheap, churn-free type-tightenings and the overdue test-reorg FIRST to
shrink the surface every later refactor has to touch, THEN the two representation refactors
that share `meetConjValueWith`/the conj-bound code together. The conj-sort (item 1) and the
`boundConstraint` fold (item 3) **PAIR**: both edit `meetConjValueWith`'s re-wrap and the
canonical member-order comparator — after the fold the 4 per-op bound ctors collapse to one
`boundConstraint (cmp, domain)`, so the sort key is computed once over the new ctor instead
of 4 tags. Writing the comparator before the fold means rewriting it during the fold; doing
them in one slice avoids that. They are sequenced 1-then-3 (not merged) only because item 1
is sound-today/cosmetic and ships a fast win, while item 3 is a big multi-module slice; if
taken together, do 1's commutativity theorems against the post-fold representation.

1. **DONE (2026-06-17, breadcrumb `2026-06-17-boundconstraint-conjsort-landed.md`) — `.conj`
   canonical member sort.** `meetConjValueWith`'s re-wrap now `sortConjMembers`-sorts the
   reduced constraint list by `conjMemberKey` (kind by `kindRank`, then bounds by
   `(BoundKind.rank, limit)`, then `notPrim` by excluded-prim string, then `stringRegex` by
   pattern length-then-string, then any residual). `meet a b == meet b a` commutativity
   theorems landed in `BoundTests.lean` (bound-pair, strict-pair, kind+bound, 3-way conj,
   bound+notPrim, plus a canonical-order check). Behavior-preserving: no `.expected` file
   changed (the sort matched cue's existing kind-first display order in every observable
   fixture), no theorem value changed.
2a. **DONE (2026-06-17, same breadcrumb) — `intGe/Gt/Le/Lt` → one `boundConstraint`.** Four
   parallel ctors + the `meetIntGe/Gt/Le/Lt`/range-prim family folded into
   `boundConstraint (bound : Int) (kind : BoundKind)` with `BoundKind = ge|gt|le|lt` and per-
   kind helpers (`lower`/`strict`/`symbol`/`rank`/`admits`). Meet arms collapsed to
   `meetBoundPrim` + `meetTwoBounds` (`tightenSameSide`/`rangeFeasible`); join to one
   same-kind-widens arm; `Order` to `boundSubsumesBound`; `Format`/`Parse`/`Manifest`/
   `valueTag`/`Examples` + all test refs migrated (build was the coverage ground truth).
   **Behavior-preserving**: `Int`-valued bound, int-only acceptance unchanged (`int & >0`
   stays, bare `>0` still rejects `1.5` via `int`-domain prim conflict — NOT 2b). Shape is
   deliberately extensible toward 2b: widen `bound` to `Decimal` + add a domain tag without
   reshaping the arms.
2b. **DONE (2026-06-17, breadcrumb `2026-06-17-decimal-bound-semantics-landed.md`) —
   Decimal/domain-tagged bound semantics.** `boundConstraint` now carries
   `(bound : DecimalValue) (kind : BoundKind) (domain : NumberDomain)`. (a) Decimal limits:
   `>0.5`/`>-1.5`/`<3.14` parse (`parseBoundValue` via `parseDecimalText`), comparator
   compares via `decimalLeValues`/`decimalLtValues` (exact, no float rounding). (b) Domain
   tag (`number|int|float`, a proper sum): a bare bound is `number`-domain and admits int+float
   — bare `>0 & 1.5` → `1.5` (the prior over-strict ⊥, now correct); `>0.5 & 1.0` → `1.0`,
   `>0.5 & 0.25` → ⊥; `>=0 & <=10 & 5.5` → `5.5`. `int & >0` stays int-only via the kept
   `kind int` conjunct (NOT bound narrowing — keeps meet commutative), so `(int&>0)&1.5` → ⊥,
   `(int&>0)&5` → `5`; `float & >0 & 1` → ⊥. `DecimalValue` + the decimal parse/compare/format
   helpers moved `Decimal.lean`→`Value.lean` (so `Value` can carry one). 7 new BoundTests
   theorems + 3 new fixtures (`bounds/number_bound_float`, `decimal_bound_float`,
   `number_range_float`). No existing `.expected` changed (no committed fixture hit the
   over-strict path). Last known bound divergence closed.
2c. **[MEDIUM — `Kue/` source-dir organization, chakrit-flagged 2026-06-17] Declutter the
   flat `Kue/` (~28 files: ~16 source + ~12 test/port).** Schedule AFTER the bound refactors
   (2b) settle — moving a module changes its Lean import path (`Kue.Foo`→`Kue.Sub.Foo`), so
   it's import-line churn across the codebase (mechanical, fully gated by `lake build`);
   doing it mid-bound-refactor is churn-on-churn. Two parts: **(i) tests-out (do this —
   high value, low churn):** move the ~12 `*Tests.lean` + `FixturePorts.lean` into
   `Kue/Tests/` (via a `Kue/Tests.lean` aggregator imported from `Kue.lean` so theorems
   still run under `lake build`); this subsumes the deferred 3d module-splits — split the
   oversized ones (`FixturePorts` 2293 / `FixtureTests` 1033 / `BuiltinTests` 735) by
   subsystem/family as they move. **(ii) source-layering (OPTIONAL, pending chakrit's
   taste call):** group source by role — `Core/` (`Value` `Decimal` `Lattice` `Order`
   `Normalize`), `Syntax/` (`Parse`), `Eval/` (`Resolve` `Eval`), `Output/` (`Manifest`
   `Format` `Json` `Yaml`), `Driver/` (`Module` `Runtime` `Cli`), `Builtin`. More
   import-churn for moderate benefit; default is tests-out only unless chakrit asks for the
   full source-layering. Use `git mv`; let `lake build` be the coverage ground-truth for
   stale imports (not the flaky grep/wc filter).
3. **[MEDIUM — consolidation + test-reorg batch, OVERDUE, chakrit-flagged] base64-out-of-
   Json + test/`testdata` reorg + `Field`→structure + Manifest-FieldClass tighten.** Four
   independent mechanical sub-tasks, one verify cycle. **Do this before items 1/2** to
   shrink the test surface the representation refactors must touch (fewer, smaller test
   modules to chase `intG*`/conj references through). Concrete move-plan below (4a–4d).
   - **PARTIAL DONE (2026-06-17, breadcrumb `2026-06-17-test-reorg-landed.md`).** The
     `testdata/cue/` flat→subsystem-subdir reorg (3b) + harness rewire (3c) + the
     Manifest-FieldClass exhaustiveness tighten (3f) landed and verify green. **Done:** all
     141 fixture pairs `git mv`'d into 11 subsystem subdirs (`numeric/ bounds/ disjunctions/
     structs/ definitions/ lists/ refs/ comprehensions/ builtins/ multiline/ manifest/`),
     `check-fixtures.sh` discovery made recursive (`find … -name '*.expected'`,
     path-relative basenames round-tripping into the generated dir),
     `FixturePort.fileName` rewritten to the `<subdir>/<stem>.expected` subpath +
     `writeFixturePort` now `createDirAll`s the parent, `manifestFieldsWithFuel`'s `_ =>`
     over `FieldClass` replaced by explicit `.field _ _ .regular`/`.optional`/`.required` +
     `.letBinding` arms (a new `Optionality` rung now breaks the build). **Deferred to a
     follow-up (still 3d/3e/3a):** the oversized-module splits (`FixturePorts` 2293 /
     `FixtureTests` 1033 / `BuiltinTests` 735 by family — pure test-file moves, no behavior),
     `Field`→`structure` (3e, ~95 sites), and base64-out-of-`Json` (3a). The splits were
     deferred because they require re-emitting list/theorem block fragments with exact
     comma/bracket boundaries, and the session's shell-output filter was non-deterministically
     truncating/mangling listing output (the CLAUDE.md-documented flip-flop) — high risk for
     mechanical text surgery, low risk via the Edit tool but unverifiable mid-stream. Core
     reorg shrinks the navigation surface already; splits remain queued.
4. **[DONE] Linux `cacheRoot` default** (`Module.lean`): landed via pure `cacheDirFor`
   branching on `System.Platform.isOSX` (Linux `~/.cache/cue`, macOS `~/Library/Caches/cue`).
5. **[LOW — type-system leverage] Refine `embeddedList.decls` element type.** "decls =
   non-output only" enforced by the `declFields` filter, not the type. A `NonOutputField`
   newtype (smart ctor) makes it unrepresentable but ripples through `Manifest`/`Format`/
   `Eval`/`Lattice` + deriving. Defer; do alongside item 2 if `BoundKind` proves the
   newtype pattern out (same indexed-type technique).
6. **[LOW — cohesion, optional] Extract `Eval` arithmetic/comparison dispatch →
   `Kue/EvalOps`.** No pain today; revisit on next `Eval` growth. The conjunction-merge
   cluster is NOT a split candidate (coupled to the `mutual`).

**Parser split (`Parse.lean`, 1440) — still OPTIONAL, do NOT split now.** Three cohesive
zones; ranks below every goal item.

### Item 3 — concrete one-slice move-plan (so a subagent executes it mechanically)

**3a. base64 out of `Json.lean` → `Kue/Base64.lean`. DONE (2026-06-17).**
`base64Encode`/`base64Alphabet` moved to a new `Kue/Base64.lean` over no Kue deps (it
imports nothing — sits at the bottom of the layer graph, below `Manifest`/`Json`/`Yaml`/
`Builtin`). Consumers re-pointed with explicit `import Kue.Base64`: `Json.lean` (bytes JSON
string), `Yaml.lean` (bytes scalar), `Builtin.lean` (`base64.Encode`). `Module.lean` only
lists `encoding/base64` as a builtin-import *string* — no function ref, untouched. Added to
the `Kue` umbrella import. Behavior-preserving: identical base64 output, no `.expected`
change, no cycle.

**3b. `testdata/cue/` flat → subsystem subdirs.** ~140 fixtures (283 files) currently flat.
Group into subdirs by subsystem; suggested taxonomy (assign each existing `<name>.{cue,
expected,manifest.expected}` triple to one):
   - `scalars/` — additive/division/equality/integer-keyword expressions, float kind/
     muldiv/additive, bytes kind/additive, number/float scalar cases.
   - `structs/` — field conflict/selector/alias, in-struct sibling merge/conflict,
     duplicate fields, colon-shorthand, dynamic fields, hidden-field reference.
   - `definitions/` — definition closed/reference, closed extra-field/hidden-definition/
     regex-pattern, exact-label pattern.
   - `disjunctions/` — disjunction, default override/disjunction, int-bound disjunction.
   - `bounds/` — int_bounds, int_bound_disjunction (or keep under disjunctions), bound cases.
   - `refs/` — builtin/definition/hidden-field/constrained reference, reference cycles,
     direct self-reference.
   - `comprehensions/` — comprehension for/guard/loopvar-shadow, dynamic-field
     comprehension.
   - `builtins/` — and_or, base64_encode, integer_builtin, encoding_infra_chain.
   (Bucket each remaining fixture by its dominant feature; one dir per fixture, no dup.)

**3c. Harness rewiring (SAME slice — must land atomically with 3b):**
   - `FixturePort.fileName` becomes a *relative subpath* (`"builtins/base64_encode.expected"`);
     `writeFixturePort` already does `targetDir / fileName` so it must `mkdir -p` the parent.
   - `scripts/check-fixtures.sh`: replace every flat `"${fixture_dir}"/*.cue` /
     `*.expected` glob (6 sites: lines 63, 74, 103, 346, 354 + manifest pairing) with a
     recursive `find "${fixture_dir}" -name '*.expected'` walk, and change the
     `${expected_file##*/}` basename-strip to a path-relative form
     (`${expected_file#"${fixture_dir}/"}`) so subdir structure round-trips into the
     generated dir without name collisions. `cue fmt --check --files "${fixture_dir}"`
     already recurses — leave it.
   - Verify: `scripts/check-fixtures.sh` green after the move (byte-identical outputs, just
     relocated).

**3d. Split the three oversized test modules by family (SAME slice or a follow-up — they
are pure test-file moves, no behavior):**
   - `FixturePorts.lean` (2293) → split the `fixturePorts` list by the same subsystem
     taxonomy as 3b (`FixturePorts/Scalars.lean`, `.../Structs.lean`, …) re-exported from a
     thin `FixturePorts.lean`, OR at minimum extract the `def fixturePorts` body into
     per-family sub-lists concatenated at the root.
   - `FixtureTests.lean` (1033) and `BuiltinTests.lean` (735) → split by family the same way.
   - Update `Kue/Tests.lean` (the test umbrella) imports accordingly.

**3e. `Field` tuple → `structure` (SAME slice):** `Value.lean:234` `abbrev Field = String ×
FieldClass × Value` → `structure Field where label : String; fieldClass : FieldClass;
value : Value`. The `label`/`fieldClass`/`value` projections already exist as helpers and
become real fields; the `Field.regular` smart ctor stays. ~95 positional `.snd.snd` /
triple-destructure sites across non-test src must move to named access (LSP-rename the
projections, then fix the literal `(name, .regular, v)` tuple constructions to `{label :=
…}` or a positional `Field.mk`). Mechanical but wide — keep the struct ctors' field type
`List Field` after the change to kill the spelled-out `List (String × FieldClass × Value)`.

**3f. `Manifest.manifestFieldsWithFuel` `_ =>` (line ~39) → explicit FieldClass arms** so a
new ctor/optionality rung breaks the build at the emission site (small; rides this batch).

---

**Inline fixes applied this audit (Phase A section):** none (finding 1 is MEDIUM with behavior change → TDD
slice, not inline). Verify gate was re-run read-only and is green.

## Implementation Status

The semantic core, evaluator, manifestation, a stdin/file CLI, and a broad expression
layer are in place. Summary of standing capabilities (detail per slice in the
implementation log):

- **Value domain** — top, bottom (with structural provenance), primitives
  (int/float/number/string/bytes/bool/null), kinds, integer bounds (incl. strict),
  primitive exclusions, disjunctions with default markers.
- **Lattice** — total `meet`/`join` with normalization; recursive compound meets through
  structs, lists, conjunctions, and disjunction alternatives; numeric-kind hierarchy in
  meet and join.
- **Structs** — regular/optional/required/hidden/definition field classes, field-level
  bottom, open/closed structs, typed and untyped tails, definition-implied closedness,
  `close` builtin, and string/exact/regex pattern constraints (incl. multiple independent
  patterns).
- **Lists** — closed lists and typed open-list tails, element-wise meet.
- **References & cycles** — same-struct and nested-scope resolution via binding ids,
  `let` bindings, static field aliases, and bounded cycle handling (direct, mutual,
  longer; constraints preserved across cycles).
- **Comprehensions** — `for k, v in expr` / `for v in expr` / `if cond` field clauses,
  desugaring into fields merged into the enclosing struct; the loop variable is one
  further lexical scope frame, expansion runs at eval time over lists and struct values.
- **Dynamic fields & interpolation** — `(expr): v` computed labels and `"\(expr)"`
  string interpolation. Dynamic fields ride the `structComp` scope machinery, resolving
  their label expr in the enclosing struct's frame and expanding to a concrete field at
  eval time once the label is a string; interpolated labels (`"\(k)": v`) are the common
  form. Interpolation coerces int/float/bool/null/string holes to their CUE spelling.
- **Struct embeddings** — a `{ … }` (or any value) embedded directly in a struct
  resolves its body against the *enclosing* struct's lexical frame and unifies (`meet`)
  into it. Plain embeddings ride the same `structComp` `comprehensions` bucket as
  comprehensions and dynamic fields; a struct embedding merges its fields (collisions
  meet), a non-struct embedding conflicts to bottom.
- **Manifestation** — structured export with default selection (incl. nested),
  field-class filtering, and incompleteness/ambiguity rejection.
- **Builtins** — top-level `close`, `len`, `and`, `or`, `div`, `mod`, `quo`, `rem`, plus
  the package-qualified `strings` family (`Contains`, `HasPrefix`, `HasSuffix`, `Index`,
  `Count`, `Split`, `SplitN`, `Join`, `Replace`, `Repeat`, `TrimSpace`, `Fields`,
  `ToUpper`/`ToLower`/`ToTitle` (ASCII)), the `list`
  family (`Concat`, `FlattenN`, `Repeat`, `Range`, `Slice`, `Take`, `Drop`, `Contains`,
  and full int+float-domain `Sum`/`Min`/`Max`/`Avg`/`Range`), and the `math` family
  (`Abs` domain-preserving int→int / float→float, `MultipleOf`, and float→int
  `Floor`/`Ceil`/`Round`/`Trunc` via exact-decimal truncation; `Round` is
  half-away-from-zero), and the `encoding` builtins `base64.Encode` (standard padded
  base64, null encoding only) and `json.Marshal` (compact, source-order keys,
  exact-decimal floats; via the reusable `Kue/Json.lean` serializer). Unresolved calls
  preserved as semantic values; concrete type-mismatch args resolve to bottom.
- **Parser/CLI** — recursive-descent parser over the supported subset; numeric literal
  spellings (non-decimal, separators, exponents, suffix multipliers); stdin and explicit
  multi-file evaluation with package-name consistency. Package-qualified builtin calls
  (`strings.X(...)`) parse via call-on-selector. `import` clauses (single and grouped) are
  now *retained* by `parseSourceFile` into a `ParsedFile` (`{value, packageName, imports}`)
  — the collecting twin of the discard-only `parseSource`/`consumeImportClauses` path the
  stdin and multi-file CLI still use. **In-module imports resolve end-to-end (B3a):**
  `Kue/Module.lean` discovers `cue.mod`, resolves `<module>/<subpath>` import paths to
  dirs, meet-merges the package's `*.cue`, and binds each package as a hidden top-level
  field so `pkg.#Sym` resolves through the existing selector path. Builtin stdlib import
  paths are skipped by the loader, leaving the dotted-call dispatch intact. Single-file and
  `export` file-mode route through `Kue.loadFileBound`; stdin keeps the discard path.
  Parse errors now carry a source position: `ParseError` records the remaining-suffix
  length at the failure site, which `parseSource` converts to 1-based `line`/`column`;
  the CLI prints `kue: parse error: <line>:<col>: <message>`. **The CLI is now a proper
  subcommand dispatcher (`Kue/Cli.lean`):** a pure `parse : List String → Command` folds
  argv into a `Command` sum type (`eval (files)`, `export (ExportOpts)`, `version`,
  `help (Option HelpTopic)`, `error msg`); `Main.runCommand` dispatches exhaustively.
  Subcommands: `kue eval [file…]` (explicit name for the default internal-format path),
  `kue export [--out json|yaml] [file]`, `kue version`/`--version`/`-V` (prints
  `Kue.version`, the single source of truth in `Kue/Runtime.lean`), `kue help [cmd]` /
  `--help` / `-h` (top-level + per-command usage). Back-compat preserved by routing any
  first token that is not a known subcommand/flag to the eval path, so `kue < file`,
  `kue <file…>`, and `kue export …` are byte-identical to before. Usage errors (unknown
  subcommand-flag, bad `--out`) exit `2`; eval/parse failures exit `1` (distinct codes).
  Missing input files now report `kue: cannot read <path>: …` instead of an uncaught
  exception. 25 `CliTests.lean` `native_decide` theorems pin the argv→`Command` parse;
  `check-fixtures.sh` gained an additive `check_cli_behavior` stage (help lists
  subcommands, `version` prints, `eval` agrees with the bare path, error cases exit
  non-zero with stderr diagnostics). Colon-shorthand nested
  fields (`a: b: c: 1`) desugar to the brace form via `parseFieldValue` (lookahead
  `valuePositionStartsField` gates the recursion; the inner field routes through the same
  `parsedFieldsValue` builder, so the AST is brace-identical). Value-position aliases
  (`label: X=value`, incl. `#Def: Self={…}` self-reference) parse via `valueAliasHead?`
  (an identifier followed by a single `=`, NOT `==`) and lower through `bindValueAlias`:
  a struct alias prepends a non-output `.thisStruct` `let`-binding, so `Self.field`
  resolves as a same-struct sibling reference (a `selector (refId …) field` eval arm
  rewrites it to the `BindingId` of `field` in the alias frame, inheriting the cycle
  guard). Multiline string/bytes literals (`"""…"""`, `'''…'''`) parse via dedicated
  `parsePrimaryAtom` arms into `parseMultilineOpen`: a total `multilineStripPrefix?`
  pre-scan finds the closing line's indentation, then an interpolation-aware
  `parseMultilineBody` strips that prefix from each content line, joins with `\n`, and
  reuses the single-line `\(expr)`/escape machinery (`'''` → bytes; bytes interpolation
  deferred). Remaining parser completeness work: strict CUE newline/semicolon separator
  insertion (separator handling is still permissive around whitespace).
- **Expressions** — unary/additive/multiplicative/division/integer-keyword arithmetic,
  equality, ordering, numeric comparison across int/float, logical `&&`/`||`/`!`, and
  binary regex match `=~`/`!~`. Float multiplication and division are now evaluated
  exactly through `Kue/Decimal.lean`: mul preserves the summed scale verbatim
  (`1.5 * 2.0 = 3.00`); `/` always yields a float and renders non-terminating quotients
  at 34 significant digits (apd context) with round-half-up. All operand domains
  (int/int, int/float, float/int, float/float) share one divider; zero divisor bottoms
  with `divisionByZero`.

Known deliberate boundaries are tracked in [`compat-assumptions.md`](compat-assumptions.md).

## Audit Fix-Slices (float-numeric family, audit 2026-06-16) — CLOSED

Findings from the `/ace-audit` depth pass over `31a85ba`/`3626ea2`/`9f1d797`. **All closed
by post-audit hardening 2** (commit `d6c54a5`):

- **[Violation] Totalize `divisionDigits` and `roundDigits` (`Kue/Decimal.lean`). DONE.**
  - `divisionDigits.loop` → fuel-bounded total `divisionDigitsLoop`, ceiling
    `divisionDigitsFuel den = divisionSigDigits + 1 + (toString den).length`. Leading-zero
    fractional positions are bounded by the den digit count; significant emission is
    hard-capped at `divisionSigDigits + 1`, so the over-budget exit always fires before
    fuel runs out — behaviorally identical to the partial form.
  - `roundDigits` → plain `def`; inner `bump` lifted to structural `roundDigitsBump`.
  - No `partial def` remains in `Decimal.lean`. All division/avg `native_decide` theorems
    pass unchanged; two high-fuel pins added (`1.0/7.0` full-34-sig, `1.0/700.0`
    leading-zero slack) lock the bound's sufficiency.
- **[Borderline] DRY the integer range-count formula. DONE.** Extracted
  `rangeCount (start limit step : Int) : Int`; `listRange` and `listRangeDecimal` both call
  it. Behavior-preserving (range fixtures/theorems green).
- **[Borderline] `evalDecimalDivide?` returns `Option (Option String)`. DONE.** Replaced
  with the named sum `DecimalDivideResult` (`nonNumeric | divByZero | ok String`); `evalDiv`
  callsite reads the three arms directly.
- **[Doc fix] `2026-06-16-float-muldiv-landed.md` partial attribution. DONE.** Corrected;
  the note now records that no `partial` remains in `Decimal.lean`.

## Audit Fix-Slices (sort/case-folding family, audit 2026-06-16 #2)

Findings from the `/ace-audit` depth pass over `d6c54a5`/`1703008`/`cf2da93`. Scrutiny
verdicts: totalization sound (empirically confirmed on worst-case leading-zero +
non-terminating inputs, e.g. `1/7·10²⁰` renders full 34 sig digits, no fuel exhaustion);
`ToTitle` correct and dead-code-free (matches `cue` v0.16.1 on `mIxEd CaSe`, hyphen/dot
non-separators); `byteSeqLe` a correct total lexicographic order, non-string→bottom resolved
before the sort. Tests are strong behavior pins, not smoke.

- **[Doc fix] compat-assumptions false cross-reference. DONE (this audit).** The
  case-folding section claimed the non-ASCII passthrough divergence "is recorded in
  `docs/reference/cue-divergences.md`", but it was never added there — correctly, since that
  file records only `cue`-is-wrong cases and this is a Kue deferred-capability (Kue does
  *less* than `cue`). Reworded to state the boundary lives in compat-assumptions, not the
  divergence log.
- **[Borderline / optional] No theorem pins the `divisionDigitsFuel` sufficiency.** The
  `fuel = 0` arm returns `(acc.reverse, false)` — a silent truncation, not a loud failure —
  so an off-by-one in the ceiling would yield subtly-wrong (truncated) quotients rather than
  crashing. Soundness currently rests on a prose argument plus `native_decide` pins at
  specific inputs, not a proof over all `(num, den)`. Low risk (worst-cases pass), but a
  Lean lemma bounding loop iterations by `divisionDigitsFuel den` would close the gap
  permanently. Schedule only if the decimal layer is revisited; not blocking.

## Audit Fix-Slices (lazy-resolution + FieldClass family, Phase A audit 2026-06-17)

Phase A code-quality pass over `f885fe7` (2c.1 in-struct duplicate-label canonicalization),
`04cf1db` (2c.2 lazy resolution through struct conjunction), `70e6ec0` (optional-definition
orthogonal `FieldClass` refactor). Type-system-first lens. Oracle: `cue` v0.16.1.

**Headline verdicts (no soundness bug found):**

- **`remapConjRefs` de-Bruijn shift is sound.** Each conjunct is rebased at `frameDepth 0`
  against its OWN `oldLabels` → merged-layout `mergedMap`; only refs whose `depth ==
  frameDepth` (the merged-frame layer) are remapped, descending a `.struct`/`.structTail`/
  `.structPattern(s)` increments `frameDepth` so nested bodies still target the merged frame
  from their new depth, and depth>0 refs pass through untouched. Adversarial cases all
  oracle-match: conjunct with its own duplicate labels (`{a:int,a:>0,b:a}&{a:1}` → `a:1
  b:1`), 3-way `&`, depth>0 outer-sibling ref preserved (`{a:int,b:p}&{a:1}` with `p:5` →
  `b:5`), ref to a label only in the other conjunct returns `none` from `nthField` and is
  left unchanged (then bottoms). No off-by-one, no mis-rebased index observed.
- **`conjStructOperand?` depth-0 boundary is safe.** It splices struct bodies only via
  `depth == 0` sibling refIds; lists/primitives/patterns/tails/disjunctions/outer-refs all
  return `none` and take the eval-then-`meet` fallback. The fallback is correct in every
  probed case (struct&list → bottom; `(a|b)&c` → distributed meet, NOT mis-merged). No
  case found where it should-merge-but-doesn't and silently yields a wrong value.
- **Closedness via `applyConjClosedness` matches binary-meet.** `#D & {extra}` still closes
  (`extra: _|_`); disjunction-in-conjunction takes the meet path; struct&list bottoms.
- **Memo/cycle safe.** Merged/canonicalized frame is built fresh (no stale `b:int` hit
  observed: `b:int; x:({a:b}&{a:1})` → `b:int, x:{a:1}`); self-ref through a merged
  conjunct (`{a:a}&{a:1}`) hits `slotVisited`→`.top` and collapses to `1`.
- **FieldClass 5 match sites correct + exhaustive.** `Manifest` (`.field _ _ .required →
  error` — oracle-confirmed `#b!` is required-not-present even as a definition), `Format`,
  `Eval.structPairs`, `Normalize`, `mergeFieldClass` all handle `.field …`/`.letBinding`
  with no constructor-swallowing wildcard. `mergeFieldClass` lattice oracle-matches all
  probed combos (`#x?&#x`, `_x?&_x`, `#y!&#y`, `a?&a!=a!`, `optional&optional`).
- **Both test rewrites independently oracle-confirmed, NOT made-to-pass.** (1)
  `eval_binding_id_not_label_lookup` `"same"`→`"#same"`: makes a `.definition`-classed slot
  internally consistent (defs are `#`-prefixed); the test's purpose (id-lookup not
  label-lookup) is preserved. (2) `meet_optional_with_required_yields_required` `.bottom`→
  `a!`: `cue` v0.16.1 confirms `a? & a! = a!` (the old enum wrongly bottomed it).
- **Type-system-first: the refactor is a genuine tightening.** The flat 6-variant enum
  could not represent `#x?`/`#x!`/`_x?`; the orthogonal `field (isDef) (isHidden)
  (Optionality) | letBinding` makes those first-class and the parser now preserves both
  modifiers (old parser dropped definition-ness on seeing `?`/`!`). `Optionality.meet` is
  total; all FieldClass projections are exhaustive.

### Findings (all LOW severity — fold as fix-slices)

1. **[LOW — type-system-first] `producesOutput` catch-all `_ => false` spans `Optionality`
   values, not just `FieldClass` constructors.** Not a constructor-swallow risk (already
   assessed in the deep-eval audit, item 1), but a *new* `Optionality` rung would silently
   be non-output. Spelling out all three `Optionality` arms under `.field false false` would
   make a future rung a compile error. Trivial; do alongside any `Optionality` change.

2. **[LOW — recorded divergence, both reject] cross-conjunct lexical scope.** `{a:int,b:a} &
   {a:1, c:b}`: `cue` errors `reference "b" not found` (each struct literal is its own
   lexical scope; `b` is not a sibling of `c`); Kue yields `c: _|_` (unresolved-reference
   bottom). Both REJECT — confirmed Kue does NOT mis-splice the first conjunct's `b` into
   the second (value-independence probe: `c` stays `_|_` whether first-conjunct `b` is `1`
   or `7`). Different diagnostic, same verdict. Candidate for `cue-divergences.md` only if
   we want diagnostic parity; no behavioral fix needed.

3. **[LOW — edge] `#_x`/`_#x` label prefix interaction unprobed.** `parseFieldClass` sets
   `isHidden := !isDefinition && startsWith "_"`, so a `#`-prefixed label is never also
   hidden. Whether `cue` treats any combined-prefix label as both is untested; low value.

No inline fixes applied — all findings are LOW and none is a one-liner safe to land without
a dedicated TDD slice. Build + fixtures were re-verified green during the audit (no code
changed). Folded as fix-slices above.

## Audit Fix-Slices (serialization/export family, audit 2026-06-17)

Findings from the `/ace-audit` depth pass over `ec920f3` (B6: `Json.lean`,
`base64.Encode`/`json.Marshal`) and `a5f9c97` (B5: `Yaml.lean`, pretty-JSON, the `export`
CLI mode). This is the serialization layer the "kue replaces cue" claim rests on; it had
never been audited. Verdicts: **serializers are total** (no `partial def`; `manifestToJson`,
`manifestToJsonPretty`, `manifestToYaml` and their mutual helpers are structural recursion
over `ManifestValue`, and `manifest` itself is fuel-bounded). JSON escaping (control chars,
`\b`/`\f`, non-HTML-escaping of `<>&/`), number-text passthrough, source-key-order, and the
YAML bare/single/double quoting matrix all oracle-match `cue` v0.16.1. The no-flag CLI path
(`kue < file`, `kue file…` → `formatValue`) is genuinely unchanged — only `"export" :: rest`
was prepended to the `main` dispatch. DRY between `Json` and `Yaml` is clean (shared
`base64Encode`/`jsonString`; the primitive-scalar logic is *intentionally* distinct because
JSON always-quotes strings and YAML quotes conditionally — not a drift risk). Incompleteness
rejection is correct: `json.Marshal`/`yaml.Marshal`/`export` all route a non-concrete or
contradictory value to bottom / a non-zero exit, never partial garbage.

- **[HIGH — data loss, FIXED inline this audit] YAML block scalars always emitted `|-`,
  silently dropping trailing newlines.** `yamlBlockScalar` used a fixed `|-` chomp and
  rejoined via `splitOn`, so a string ending in `\n` (a file body, a PEM cert, a script —
  exactly what k8s ConfigMaps/Secrets carry) round-tripped to its content *minus* the
  trailing newline. `kue export` of `a: "x\n"` produced `a: |-\n  x` (round-trips to `"x"`)
  where `cue` produces `a: |\n  x` (round-trips to `"x\n"`). Fixed by emitting the chomping
  indicator `cue`/go-yaml chooses: `|-` (strip) for zero trailing newlines, `|` (clip) for
  exactly one, `|+` (keep) for two or more, reconstructing the explicit trailing blank lines
  in the `|+` case. Pinned by four new oracle-matched theorems + end-to-end binary
  comparison across 0/1/2/3 trailing newlines.
- **[HIGH — invalid/ambiguous YAML, FIXED inline this audit] Block scalar with a
  leading-space first line emitted no indentation indicator.** `a: " x\ny"` produced
  `a: |-\n   x\n  y`, whose first content line's indentation is ambiguous to a parser; `cue`
  emits `a: |2-\n   x\n  y`. Fixed by emitting the `|2` indentation indicator when the first
  line begins with a space. The indicator is the indent *increment* (fixed at 2 in this
  layout), not the absolute column — verified at top level, nested-map, and in-list depths.
  Pinned by a new theorem + depth comparison.
- **[LOW — lossy corner, FOLDED] All-newline block scalar.** A string that is *only*
  newlines (`"\n"`, `"\n\n"`) — no non-empty content line — needs `|2+` in `cue` (forced
  indentation indicator + keep, because there's no content line to anchor indentation).
  Kue emits `|` and loses the newlines. Degenerate (a value that is purely newlines does not
  occur in real manifests); folded rather than risk the common-case fix. Generalize
  `firstLineIndented`/chomp interaction to the empty-first-content-line case when revisited.
- **[LOW — robustness, FOLDED] `kue export` silently drops extra positional files.**
  `parseExportArgs` keeps the first bare arg as the input file and silently ignores any
  further positionals (`some _ => parsed`). `cue` merges multiple files; Kue export is
  documented single-input, but a silent drop is worse than an error — make a second
  positional an error (exit 2) until multi-file merge is wired.
- **[LOW — diagnostic quality, FOLDED] `runExport` file-not-found throws an uncaught IO
  exception** rather than a clean `kue: …: no such file` + `exit 1`. Same preexisting
  behavior as the no-flag `readFileSources` path (not a regression), but the new `export`
  path repeats it; wrap `IO.FS.readFile` in both paths with a positioned diagnostic.
- **[Candidate divergence to log, not a bug] `json.Marshal({a: int})` → bottom.** `cue eval`
  *displays* the call unevaluated, but under concreteness demand (`cue eval -c`, `cue
  export`) it is an error ("cannot convert incomplete value"). Kue mapping it to bottom is
  correct — `cue`'s deferred display is a lazy-eval artifact. Worth a `cue-divergences.md`
  entry if treated as a surprising-`cue` case; otherwise leave as the documented intended
  behavior.

## Audit Fix-Slices (parser batch: `_`-ident + type-label patterns + export discovery, Phase A audit 2026-06-17)

Phase A code-quality pass over `ccda409` (export `cue.mod` discovery from subdir/relative
path), `2bda996` (`[string]:`/`[int]:` type-label-pattern colon-shorthand), `e82f107`
(`_`-prefixed identifier lexing fix). **No Violations found in the landed slices; one
LOW-severity correctness gap (NOT a regression) folded as a fix-slice below.** Verify gate
green (`lake build`, `check-fixtures.sh`, `shellcheck`) on the as-landed tree before any edit.

**`_`-ident lexing (`e82f107`) — COMPLETE, no regression.** The `'_' :: next :: rest` arm
sits after `'_' :: '|' :: '_'` (bottom) and before bare `'_'` (top at EOF). Verified against
the oracle across every position: `_x`/`__bar` (ident), `_` alone (top), `_|_` (bottom),
`_x.y` (selector base), `a._x` (hidden selector tail), `_x` in list/call-arg, `_ | 3`
(disjunction with `_` as top — `|` is not ident-rest so the bare-top arm fires). The
ident-rest predicate is correct (`parseIdentifierStart || 0-9`, i.e. letters, `_`, `#`,
digits). No mis-lexed position found; no regression to bottom/top/normal idents.

**`[`-disambiguation (`2bda996`) — CORRECT; `skipBalancedBrackets` total.**
`valuePositionStartsPatternField` = balanced `[…]` immediately followed by `:`; a `[…]` not
followed by `:` stays a list expression. Disjoint from `valuePositionStartsField`
(`skipLabelToken?` returns `none` on `[`), so no double-classification. `skipBalancedBrackets`
recurses on a strictly shorter list in every arm (quoted-literal arms delegate to
`skipQuotedToken?`, which always returns a proper suffix), so it terminates — `partial` only
because Lean can't auto-derive it (parser standing exception). Quoted `]` inside the pattern
is skipped whole; nesting tracked by `depth`. The type-pattern reuses the existing
`.structPattern`/`.kind` representation — NO redundant new rep (constraint + label both parse
as plain expressions via `parseExpression`).

**Type-system-first — CLEAN.** No new loose reps introduced. `.pattern`/`.structPattern`
reuse existing constructors; `Import.alias : Option String` is the natural shape (alias is
genuinely absent in the bare-path form). `absolutePath`/`discoveryStartDir` are total and
pure (the `cwd` lookup is the IO caller's job), correct on `.`/`..`/trailing-slash via the
downstream parent-walk. No new catch-all `_` that swallows a future constructor; no partial
that should be total.

**Test strength — REAL PINS.** `_`-ident exercised across ref/`!=`/`+`/`==`/selector
positions (`underscore_ident_reference`) and top/bottom (`underscore_top_bottom`); pattern
typing + mismatch pinned via `containsBottom` (`string_kind_pattern{,_mismatch,_only}`,
`type_label_colon_shorthand`). All six new `testdata/cue/*` fixtures have FixturePorts
entries; the `export_subdir` module fixture is CLI-driven (`subpaths` + `expected.<name>`),
correctly exempt from the FixturePorts rule.

**[LOW — parser, NOT a regression] Nested pattern-shorthand on the constraint side fails.**
`f: [string]: [int]: bool` parses fine in CUE (pure constraint, no concrete output) but Kue
errors at the second `:` (`parse error: unexpected character ':'`). Cause: `parsePatternField`
(`Parse.lean` ~L1161) parses the constraint with `parseExpression`, NOT `parseFieldValue`, so
the colon-shorthand desugaring `valuePositionStartsField || valuePositionStartsPatternField`
never runs on a pattern field's value. The named-field value-position case (the `2bda996`
target, `f: [string]: int`) works — this is the missed *constraint-of-pattern* twin, a
pre-existing asymmetry the slice surfaced rather than introduced. **Fix-slice:** route the
`parsePatternField` constraint through `parseFieldValue` (mirroring `parseLabeledField`),
then pin with a `nested_pattern_shorthand` fixture + oracle check. Low-risk but a parse-path
change → its own slice, not inline.

## Audit Fix-Slices (import-resolution + embedding family, Phase A audit 2026-06-17)

Phase A code-quality pass over `2329df2` (B3a in-module imports), `e642e93` (B3c
cross-module/vendored), `05c5c8a` (`[...]` list-embedding parse fix). The import subsystem
(`Kue/Module.lean`, new + IO-heavy) was the headline scrutiny target. **No Violations
found; two LOW-RISK items fixed inline (re-verified + committed). Remaining items are
notes/flags for Phase B.**

**Correctness & totality — SOUND.**
- `findModuleRoot` terminates: parent-walk stops on the `parent == start` fixpoint
  (filesystem root: `/.parent == /` → `none`). The `partial def` is justified (IO, and the
  bound is the finite path depth, not structurally evident). No root loop.
- Cycle guard sound across module hops: `visited` is keyed on absolute `dir.toString`,
  added in `loadPackage` and threaded `loadPackage → parseAndBindFiles → collectBindings →
  loadPackage`. Persists across cross-module hops (dirs absolute), so A→B→A is caught
  (`cycle/` fixture: mutual `a/`↔`b/`). Sibling/diamond imports of the same package each
  pass independently — correct, not a false cycle.
- `parseDeps` / `depKeyModulePath` robust on malformed `module.cue`: non-struct → `[]`;
  `deps` entry lacking a string `v` → skipped (`filterMap`); a key with no `@` → verbatim.
  All pure, total.
- `locateModuleDir` priority correct: vendored-versioned → vendored-bare → cache extract,
  first-existing wins. `cacheRoot` honors `CUE_CACHE_DIR` → `XDG_CACHE_HOME/cue` → macOS
  default, each branch named (no `or`-chain). Linux/XDG-only hosts fall through to the
  macOS path only if `XDG_CACHE_HOME` is unset — acceptable for now (flag for Phase B: a
  `~/.cache/cue` Linux default is missing).

**IO-boundary purity — CONFIRMED.** All FS access (`findModuleRoot`, `readModuleInfo`,
`locateModuleDir`, `listPackageFiles`, the `loadPackage` mutual block, `loadFileBound`)
lives behind `IO` in `Module.lean`. The pure core (`resolveImportSubpath`,
`resolveCrossModule`, `parseDeps`, `loadPackageFromParsed`, `bindImports`) is disk-free and
total. `Eval.lean`/`Resolve.lean` unchanged — the loader hands a fully bound `Value` to the
existing pure pipeline (`exportValue`/`formatResolvedTopLevel`). No IO leaked in.

**Intermediate-deps leniency — SOUND boundary for B3c, but a latent wrong-resolution path;
FLAG for B3d, not a bug today.** Kue reads each transitive module's *own* `deps` per hop
rather than CUE's flat MVS over the root's dependency set. When root and an intermediate
module pin *different* versions of a shared transitive dep, MVS selects the max and only
that one copy is extracted on disk; kue's per-hop lookup would try the intermediate's
pinned version and miss (or load a stale vendored copy). Today's fixtures keep versions
consistent (root+mid both pin `core@v0.2.0`), oracle matches. Documented in
`compat-assumptions.md` §B3c. **Action:** when B3d lands MVS version solving, this per-hop
read must be replaced by the flat resolved set — do not let it persist silently.

**`parseField` `[`-fallback (05c5c8a) — NO REGRESSION.** Follows the exact existing
shape of the `'"'` and `'('` arms: try the structured parse (`parsePatternField`), fall
back to `parseEmbedding` only on `.error`. So a valid `[label]: value` pattern still wins
(it parses successfully → never reaches the fallback); only a `[...]`/`[1,2,3]` that fails
the pattern parse becomes an embedding. No ambiguity: the pattern parse is the
discriminator, and it is deterministic. Pinned by `parse_open_list_embedding_in_struct`,
`parse_list_literal_embedding_in_struct`, plus the pre-existing `[...int]`/`[label]:`
no-regression tests.

**Test strength — REAL PINS, not smoke.** `ModuleTests` `native_decide` theorems pin the
pure logic at edges: textual-but-not-segment prefix is cross-module (`example.computer` vs
`example.com`), longest-prefix dep ownership, `@major` stripping, conflicting package
names rejected, `bindImports` binds `hidden` (output-excluded). Module fixtures cover
cycle, missing-pkg, cross-module-miss (no dep), declared-but-absent-on-disk, vendor vs
cache, transitive, and `mixed_builtin` (stdlib `strings` skip + real import in one grouped
block, exercising builtin dotted-dispatch no-regression). **Note (correct by design):**
module fixtures are CLI-driven via `check_module_fixtures` (file pair + `expected`/
`expected.err`), so the "every fixture needs a FixturePorts entry" rule does NOT apply to
them — that rule is for the Lean-port `testdata/cue/*` fixtures, which the `let_*` additions
satisfy. The `_cache/` + `CUE_CACHE_DIR` isolation (never touches the user's real cache,
for both kue and oracle) is a good harness touch.

**Fixed inline this audit (LOW-RISK, re-verified):**
- `bindImports` doc said "regular field" but binds `FieldClass.hidden` — stale comment
  corrected to state the hidden/output-exclusion intent the test pins.
- `subpathDir` was byte-identical to `joinModulePath` (fold slash-split onto base, skip
  empties) — collapsed `subpathDir` to call `joinModulePath`, keeping the named wrapper for
  intent at its callsites. DRY.

## Audit Fix-Slices (deep-eval family: memoization + list-embedding + presence-test, Phase A audit 2026-06-17)

Phase A code-quality pass over `cded8ba` (memoize eval — `StateM EvalState` + frame-id
memo `HashMap`), `2b63902` (`[...]` struct-embedding eval — `Value.embeddedList` +
`FieldClass.producesOutput`), `05c7b6e` (`!= _|_`/`== _|_` presence test —
`Definedness`/`classifyDefinedness`/`evalPresenceTest`). Type-system-first lens applied
first. **No HIGH/Violation findings. Memo cache is SOUND, `embeddedList` exhaustive,
presence-test interception robust. Items below are LOW-severity type-tightening +
test-gap notes; none fixed inline (all touch refined types or new tests, not one-liners).**

**HEADLINE — memo cache soundness: SOUND.** Probed adversarially (throwaway `/tmp` .cue,
oracle-checked against `cue` v0.16.1):
- **Key completeness — sound.** `EvalKey = ⟨fuel, envIds, visited, value⟩` with
  `deriving BEq` compares the FULL `value` structurally, not just its tag. The shallow
  `Hashable` (uses `valueTag`, `envIds.length`) is lossy only for bucket selection; a
  tag/length collision falls through to structural `BEq`, which disambiguates → miss, no
  false share. Adv case `base:{x:1,y:2}; a:base.x; b:base.y` (two `.selector` keys, same
  tag/env/fuel/visited) returns `1`/`2` distinctly — matches cue.
- **Frame-id identity — collision-free.** `pushFrame` allocates monotonically from
  `nextFrameId` (starts 0 in `runEval`, only ever `+1`), so `(id, fields)` is a bijection
  within a run; `Env.ids : List Nat` therefore uniquely determines the frame-content stack
  → `envIds` equality is sound. Depth-0 self-ref reuses the SAME env (line 692); depth>0
  rebase passes the EXISTING `frame :: outer` from `env.drop` (line 694), reusing original
  ids — both share intentionally. Independently-built frames get distinct ids. Adv case
  `outer:{n:1, inner:{n:2, v:n}}; r:outer.inner.v; s:outer.n` (shadowed `n` at two depths)
  yields `r:2, s:1` — proves no false sharing across same-name scopes. Matches cue.
- **Cycle interaction — safe.** `visited` is in the key and structurally compared. A
  mid-cycle binding returns `.top` and IS cached, but under a key whose `visited` carries
  the slot index; the fresh reach has a different `visited` → different key → the partial
  cannot be replayed past the guard. Pinned by `eval_cycle_with_repeated_selection` +
  `eval_shared_repeated_selection` (`native_decide`); adv `x:x&{p:1}; p1:x.p; p2:x.p` and
  `a:b; b:{p:c.q,r:5}; c:{q:9}` both match cue.
- **Determinism/totality — sound.** `StateM` threads only a memo (read-cached-or-compute,
  insert-on-miss) — result is independent of hit timing (cache returns the same value it
  would have computed). Explicit lexicographic `termination_by (fuel, phase, listLen)`; no
  `partial def`.

**`embeddedList` exhaustiveness (#2) — SOUND, no wildcard absorption.** Every
Value-matching site has a correct explicit arm:
- `Lattice.containsBottomWithFuel:135` — recurses into items + tail + decls (element
  conflicts surface as bottom). `isBottom:95` `_=>false` correct (embeddedList isn't
  bottom). `meetCore:419-420` `.embeddedList _ _ _,_ / _,.embeddedList _ _ _ => .bottom`
  (the laziness fallback; real logic is in `meetWithFuel`). `asListPair:753` explicit.
  `meetWithFuel:921-967` — `.embeddedList` arms PRECEDE the generic struct/list arms so a
  left/right embeddedList keeps its own decls instead of being swallowed by
  `listLike,.struct`; `meetListPairWith` is exhaustive over `Option×Option` (4 arms).
- `Manifest.lean:96` — emits items, excludes tail + decls. Open-tail embeddedList
  manifests as a concrete list (drops tail) — **oracle-confirmed correct** (`{#x:1,[1,...]}`
  → `[1]` in cue v0.16.1).
- **DONE (2026-06-17): bare open-list collapse on manifest (audit item 2).** The bare
  `listTail items tail` arm now manifests as its concrete prefix (drops the open/typed
  tail), matching the embeddedList arm and `cue export`: `[1,...]`→`[1]`, `[...]`→`[]`,
  `[1,2,...int]`→`[1,2]`, `[1,...string]`→`[1]`. A non-concrete prefix element still
  surfaces as `.incomplete` (oracle-confirmed: `[int,...]` errors in cue). Was returning
  `.incomplete (.listTail …)`. INTERNAL `formatValue`/`embeddedList` representation
  unchanged. See compat-assumptions "open-list export collapse".
- `Eval.lean` — `selectEvaluatedField:126` (decls selectable via `findEvalField`),
  `selectEvaluatedIndex:180-181` (items indexed, tail-aware), `classifyDefinedness:263`
  (`.defined`), `valueTag:565` (31). `Format.lean:190` prints `{decls…, [items…]}`.
- **Benign wildcard absorptions:** `Order.subsumesWithFuel` `_,_=>false` (conservative;
  `subsumes` has no non-test callers), `Normalize`/`Resolve`/`join` pass it through as a
  leaf. embeddedList is meet-produced only — never in pre-eval AST — so Normalize/Resolve
  (AST-only) never encounter it. Safe by construction.

**Presence-test interception (#3) — ROBUST, deferral real + documented.** The `.binary`
interception (Eval.lean:704-717) fires ONLY on the syntactic `Value.bottom` constructor as
a direct operand, never an evaluated-bottom. Oracle-confirmed against cue v0.16.1:
`(1/0)==2` → error propagates (NOT `false`); `_|_==2` → `false`; `_|_==(1/0)` → `true`;
`x.b==_|_` (absent) → `true`. `classifyDefinedness` is total (explicit defined/error arms,
`_=>incomplete`); `Definedness` is the right 3-way sum type (illegal-states-unrepresentable
✓). The incomplete→residual `.binary` deferral is real: `int != _|_` → incomplete in BOTH
kue and `cue export` ("requires concrete value"); the missing-field-on-open-struct →
incomplete (vs cue's bottom→`true` for a bare `x.b==_|_`) is the documented kue-side
deferral (compat-assumptions §presence, lines 233-240), observably agrees in the guard
idiom, NOT a masked bug.

### Findings (LOW severity — fold as fix-slices)

1. **[SUPERSEDED by 2c.5] `FieldClass.producesOutput` wildcard.** The flat 6-variant enum
   is gone — `FieldClass` is now orthogonal axes (`field isDef isHidden optionality` +
   `letBinding`). `producesOutput`/`ignoresClosedness` are total over the new shape (a
   present plain field / `isDefinition || isHidden`). The "new variant swallowed" risk no
   longer applies the same way; the remaining wildcard in `producesOutput` (`_ => false`)
   ranges over the finite optionality×def×hidden cube, all genuinely non-output. No action.

2. **[LOW — type-system-first] `embeddedList.decls` invariant ("non-output fields only")
   is unenforced.** The field type `List (String × FieldClass × Value)` admits output
   fields; the "decls are non-output" invariant holds only by every build site filtering
   through `declFields`/merging already-filtered decls. A refined decls element type (a
   `NonOutputField` newtype, or a smart constructor that rejects regular/required) would
   make the illegal state unrepresentable. Blast radius: the `embeddedList` constructor +
   its ~6 build/consume sites in `meetWithFuel`. Propose as a tightening slice.

3. **[LOW — test gap] No theorem pins frame-id non-collision across shadowed scopes.** The
   strongest cache-soundness case (same binding name at two env depths, `outer.inner.v` vs
   `outer.n`) is covered only by manual oracle + the `shared_selection_fan` fixture, not a
   `native_decide` theorem. Add an `eval_shadowed_binding_no_false_share` theorem mirroring
   the adv3 probe (`outer:{n:1, inner:{n:2, v:n}}` → `v:2, s:1`).

4. **[LOW — divergence-log gap] Open-list collapse-on-manifest not logged.** `cue`
   manifests both `[1,...]` and `{#x:1,[1,...]}` as the concrete `[1]` (drops the open
   tail at export). embeddedList-with-tail correctly does this (Manifest.lean:96), but the
   behavior is surprising and undocumented in `cue-divergences.md` / not cross-checked for
   the bare `.listTail` path (which returns `.incomplete` at Manifest.lean:95 — a possible
   bare-listTail divergence to investigate separately). Log the embedded case; open an
   investigation note for the bare `[1,...]` manifest path.

## Audit Fix-Slices (parser+alias+multiline family, audit 2026-06-17)

Findings from the `/ace-audit` depth pass over `0795530` (`strings.SplitN`), `7ec51a4`
(parser source positions + structured `ParseError`), `f6c18b5` (B1 colon-shorthand),
`804f1ca` (B2 value/field aliases + `Value.thisStruct`), `d1a5e35` (B4 multiline). Serialization
(B5/B6) was excluded — already audited in the prior section. **No Violations found; nothing
fixed inline. The items below are LOW/borderline hygiene and test-gap notes only.**

**`.thisStruct` exhaustiveness (the #1 scrutiny) — SOUND.** Every Value-matching site
accounts for the new constructor:
- `Lattice.meetCore:380-382` — explicit `.thisStruct,.thisStruct => .thisStruct`
  (idempotent, correct); `.thisStruct,_`/`_,.thisStruct => .bottom`. `.top`/`.bottom`
  arms precede them, so `meet ⊤ thisStruct = thisStruct` (preserved). `meetWithFuel`
  delegates the tail to `meetCore` (`value,other => meetCore`), inheriting the arms.
- `Manifest.lean:72` — explicit `.error (.incomplete .thisStruct)`; the match is fully
  enumerated (no wildcard), so a leaked marker becomes an incomplete error, never silent
  output. Json/Yaml consume `ManifestValue`, never `Value`, so `thisStruct` cannot reach
  serialization at all.
- `Format.lean:161` — explicit `"@self"` (diagnostic only, like `@d.i` for refId).
- `Eval.lean:502-505` — `Self.field` (`.selector (.refId id) label`) rewrites to the
  sibling `BindingId` via `thisStructFieldIndex?` and recurses through the `.refId` arm
  (480-490), inheriting `slotVisited` (the cycle guard) and bounding self-cycles to `⊤`.
  `fieldLabelIndexFrom` matches on `Field.label` only, independent of `FieldClass`, so the
  rewrite is correct for regular/optional/required/hidden/definition siblings alike
  (`Self.#name` fixture confirms hidden).
- **Wildcard-absorption sites (all benign):** `Order.subsumesWithFuel` has a trailing
  `_,_ => false` that absorbs `thisStruct` → `false`; `subsumes` has no non-test callers,
  and `thisStruct` is rewritten pre-unification, so this is inert (and `false` is the
  conservative answer anyway). `Normalize` (`_,value => value`), `Resolve`
  (`_,_,value => value`), `join` (`value,other => disjOfValues`), `isBottom`/`containsBottom`
  (`_ => false`) all pass `thisStruct` through harmlessly as the leaf it is.

**B1 AST-identity — HOLDS for all inner-label forms.** Both the brace path (`parseStruct`
→ `parsedFieldsValue fields`) and the shorthand path (`parseFieldValue` →
`parsedFieldsValue [inner]`) funnel through the same `parsedFieldsValue` builder and the
same `parseField` label dispatch, so `a: b: V` ≡ `a: {b: V}` for quoted, dynamic `(expr)`,
definition `#x`, and optional/required inner labels. Proven by `shorthand_*_equals_brace`
theorems. **One genuine boundary (borderline, FOLDED):** `a: X=b: V` parses the `X=` as a
*value* alias (`valueAliasHead?` runs before `valuePositionStartsField` in
`parseFieldValue`), whereas `a: {X=b: V}` is a *field* alias. A field-alias inner label in
bare colon-shorthand position diverges. No test pins this and no prod9 file uses it; decide
whether to reject `X=label:` in shorthand position or document the divergence when next
touching the aliases code. Not blocking.

**B4 multiline — total + correct.** `multilineStripPrefixGo`/`multilineStripPrefix?` and
`offsetToLineColumn` are total (structural recursion, fuel-decreasing). Dedent strips the
closing line's indentation from every content line; under-indented lines hit
`invalid whitespace`; blank lines are exempt; leading newline (after opening) and trailing
newline (before close) are both excluded; interpolation/escapes reuse the single-line
machinery. Bytes `'''` reuses `parseMultilineOpen` then re-tags `.string`→`.bytes`, erroring
on interpolation (documented deferral). All covered by `parseSameValue` equivalence theorems
+ error-case theorems.

**Parser positions — no off-by-one.** `withPosition` computes `offset = source.length -
remaining` (chars consumed before the stuck point) and `offsetToLineColumn` reports 1-based
line/col at that char; col resets to 1 after `\n`. Column-one, midline, later-line,
multiline-struct, and unterminated-string positions are all theorem-pinned. The
`remaining`-suffix mechanism (store unconsumed length at the error, reconstruct offset once
at the top) is clean and total.

**B2 deferred positions — all three are REAL boundaries, correctly documented** in
`compat-assumptions.md:170-185`: (1) post-unification re-resolution is the same
lexical-vs-merged boundary that affects every sibling ref, attributed to broader resolver
work, not an alias gap; (2) bare `Self` emits residual `@self`→incomplete (cue rejects it
as a structural cycle — both fail to yield a value); (3) unreferenced-alias permissiveness
is a Kue-does-less stance, correctly NOT logged as a cue divergence.

**SplitN (light pass) — clean.** Shared `stringSplitParts` core; `Split` now delegates to
it (no regression); Go/CUE semantics correct (`n==0`→`[]`, `n<0`→unbounded, `n>0`→first
`n-1` verbatim + rejoined remainder); `cap-1` Nat-safe since `n>0`⇒`cap≥1`.

LOW/borderline items to fold (none blocking):
- **[Borderline, FOLDED] field-alias inner label in colon-shorthand** — see B1 boundary
  above.
- **[DONE — Phase B, commit `5a0d057`] `Yaml.lean:186,192` deprecated `String.dropRight`**
  migrated to `String.dropEnd` (`.toString` coerces the new `String.Slice` return back).
  Behavior unchanged; the two build warnings are cleared.

## Architecture Fix-Slices (Phase B audit 2026-06-17 #2 — eval-blowup diagnosis) — SUPERSEDED by #3

Second Phase B pass, headlined by the priority diagnosis of the `kue export
apps/argocd.cue` hang. Layering verdict from the prior pass (below) is **re-confirmed
unchanged** — the import DAG is still acyclic and correctly shaped. New findings here
supersede the ranking below; the base64 / test-reorg / cacheRoot items from the prior pass
remain valid and are re-ranked into this list.

### HEADLINE — the `kue export apps/argocd.cue` hang is EXPONENTIAL BLOWUP, not non-termination

**Verdict: fuel-bounded exponential re-evaluation. NOT a totality violation.** Every core
recursion (`evalValueWithFuel`, `meetWithFuel`, `resolveValueWithFuel`) is fuel-bounded
(`evalFuel = meetFuel = resolveFuel = 100`); none can run forever. Proven empirically by
temporarily lowering `evalFuel` and timing the minimal repro: fuel 14–40 → ~6–10 s (IO
floor), fuel 50 → 33 s, fuel 60 → >40 s (timeout). Growth ≈ 3.2× per +10 fuel ⇒ fuel 100
is ~2.6 h+ — effectively infinite, but it *would* terminate. Working tree restored to
`evalFuel = 100`; no code changed.

**Minimal repro** (hangs; `/tmp/kuerepro/t3.cue`, module `prodigy9.co`, dep
`defs@v0.3.19` in cache):
```cue
package apps
import "prodigy9.co/defs/packs"
x: packs.#Argo & {#name: "stage9"}
```
Bisection isolated the trigger to the `packs.#Argo` definition itself (the `[...]`
open-list embedding is NOT the cause — `t3` omits it and still hangs; a local-only
reconstruction of the same shape does NOT hang, so the cross-module def-meet path is
load-bearing). `#Argo` is a `Self={…}` value alias whose body ends with a top-level
embedding `[Self.#components.repo, Self.#components.project, Self.#components.app]`, where
`#components` holds three `defs.#ArgoX & { if Self.#f != _|_ {…} }` cross-module def meets,
each re-selecting `Self`.

**Root cause — unmemoized repeated substitution.** `Kue/Eval.lean`:
- `.selector (.refId id) label` (lines 502–505) evaluates the ENTIRE base struct
  (`evalValueWithFuel … (.refId id)`) and then `selectEvaluatedField` plucks one field and
  throws the rest away. So `Self.#components.repo` fully re-evaluates `Self` *and*
  `#components`; the three embedding elements do this 3× over.
- The depth>0 `.refId` arm (line 490) re-evaluates `Field.value field` from scratch every
  visit with the cycle-`visited` set RESET (`[id.index]`) — depth>0 refs (every `Self.x`)
  have NO sharing and NO revisit guard, only the fuel cap.
- `selectEvaluatedField` (lines 107–127) returns the field's *unevaluated* `Value`, so each
  selection re-forces it.
There is no evaluation-result cache anywhere (`grep memo/cache/HashMap` in `Eval.lean` →
none). Each fuel level multiplies the work by the per-node fan (≈3 here), giving the
observed exponential. This is exactly the `Self.x`-style re-eval the audit brief
anticipated.

**The fix it needs (own slice — HIGH, gates the real prod9 workflow; precedes/pairs with
the `[...]` eval-laziness slice).** Memoize evaluation: compute each binding's value once
and share it, CUE-style (the reference implementation evaluates a vertex graph with
computed-once nodes). Concretely — thread an evaluation cache keyed by `BindingId`
(depth-adjusted) through `evalValueWithFuel`, OR evaluate each struct's fields once into a
resolved frame and have `.refId`/`.selector` read the already-evaluated frame instead of
re-evaluating `Field.value`. The depth>0 `.refId` arm and the `.selector (.refId id)` arm
are the two hot sites. This is a real design change (the eval environment grows a memo /
becomes a graph), not a one-line fuel guard — so it is folded, not applied inline.
**Type-system connection:** the missing structure is precisely a *computed-once node* the
representation does not yet model; today `Value` re-substitution stands in for graph
sharing. Encoding "evaluated vs unevaluated" in the type (a thunk/`Computed` node) would
make the re-eval unrepresentable.

### Ranked next-work list (this audit — supersedes the older ranking below)

Ordered by goal-impact (replace `cue` for prod9/infra) vs cost:

1. **[HIGH — eval blowup, gates the workflow] Memoize evaluation. DONE (2026-06-17,
   breadcrumb `docs/notes/2026-06-17-eval-memoization-landed.md`).** `evalValueWithFuel` is
   now a `StateM EvalState` action with a memo cache (`EvalKey → Value`) keyed on
   `(fuel, env-id-stack, visited, value)`. The env carries a process-unique **frame id**
   per push (`pushFrame` allocates from a state counter), so cache equality compares the
   cheap `List Nat` id-stack instead of the deep frame contents; the hash is shallow
   (`fuel`, `visited`, env depth, value top-tag). `visited` stays in the key, so a binding
   caught mid-cycle is keyed apart from the same binding reached fresh — cycle detection is
   untouched. Behavior-preserving: all 574 theorems + every fixture pass unchanged. The
   `packs.#Argo` minimal repro went from ~2.6h (effectively infinite) to ~7s; real
   `kue export apps/argocd.cue` now **completes** (~57s) instead of hanging — exposing the
   next blocker (item 2) rather than masking it. Mutual-block totality is held by an explicit
   lexicographic `termination_by (fuel, phase, listLen)`; no `partial def`. New tests:
   `shared_selection_fan` fixture + `eval_shared_repeated_selection` /
   `eval_cycle_with_repeated_selection` theorems.
2. **[HIGH — semantic] `[...]` open-list embedding eval + `meet(struct,list)`. DONE
   (2026-06-17, breadcrumb `docs/notes/2026-06-17-list-embedding-eval-landed.md`).** The
   earlier "cue tolerates lazily" hypothesis was WRONG — measured against `cue` v0.16.1,
   the rule is *eager and structural*: a struct embedding a list IS the list **iff it has
   no regular/required (output) field** — only hidden/definition/optional/let members — in
   which case it manifests/indexes as the list while its declarations stay selectable; any
   output field → genuine `⊥` conflict. Modeled with a new
   `Value.embeddedList items (tail : Option Value) decls` constructor (type-system-first:
   the dual list/decls nature is one value). `meet` arms build/merge it; `Manifest` emits
   the items; `Eval` selects decls + indexes items; `containsBottom` recurses in. Pivots on
   `FieldClass.producesOutput` (true only for `regular`/`required`). Oracle-matched on every
   probed case (8 `list_embedding_*`/`list_struct_*` fixtures + 9 `ListTests` theorems).
   Genuine `{a:1}&[1,2]` conflicts still bottom. The remaining `apps/argocd.cue` `⊥` is the
   next blocker (2b), NOT this — confirmed both kue and `cue` error on the direct
   `packs.#Argo & {#name:…}` form; with `[...]` in the consuming struct `cue` proceeds and
   the next gate is the `if _x != _|_` guard.
2b. **[HIGH] `if _x != _|_` presence-test comparison eval. DONE (2026-06-17, breadcrumb
   `docs/notes/2026-06-17-presence-test-guard-landed.md`).** Oracle (`cue` v0.16.1) pinned
   `e == _|_` / `e != _|_` as CUE's **definedness test**, not value equality: evaluate the
   non-`_|_` operand and classify three-way — `defined` (resolved value: prim/struct/list/…)
   → `!= _|_` true; `error` (evaluated bottom) → `== _|_` true; `incomplete` (residual:
   kind/bound/ref/unresolved-disj/…) → the comparison stays incomplete (residual node), so a
   guard drops. kue's bug was blanket bottom-propagation in `evalEq` (`concrete != _|_`
   gave `⊥`, not `true`). Fix: intercept `.eq`/`.ne` against the **syntactic** `_|_` literal
   at the `.binary` dispatch (the literal parses to bare `.bottom`; this preserves genuine
   error-propagation for `(1/0)==2`-style non-`_|_` operands — also oracle-confirmed), new
   `classifyDefinedness`/`evalPresenceTest`. Verified: concrete `!= _|_`→true, `== _|_`→false;
   same-scope present guard fires (`out.has: 3`), absent guard drops (`out: {}`) — matches
   `cue` exactly. 12 `PresenceTests` theorems + `presence_test_guard` fixture.
   **Deeper blocker now exposed (2c):** the *real* `#D & {#x:"hi"}` def-meet guard still
   yields `out: {}`/`y: ⊥` — NOT the comparison, but **lazy field resolution through
   definition-meet**: kue eagerly evaluates a definition's comprehension body + field refs
   against the definition's own pre-meet scope (`#x: string`), instead of deferring until the
   meet supplies `#x: "hi"`. Confirmed: `#D: {#x?: string, out: {if true {val: #x}}}; y: #D &
   {#x:"hi"}` → `cue` `out.val: "hi"`, kue `out.val: string` / `y: ⊥`. See compat-assumptions.
2c. **[HIGH — NOW the argocd gate] Lazy field resolution through definition-meet.** A
   definition's comprehension body and field references must resolve against the *meet
   result* (post-`&`), not the definition's own incomplete scope. This is the layer behind
   2b that still blocks `apps/argocd.cue`. Next slice.
3. **DONE (2026-06-17) — Collapse `intGe/intGt/intLe/intLt` into `boundConstraint (bound :
   Int) (kind : BoundKind)`.** Landed as the authoritative-list items 1 + 2a (see "Phase B
   audit #5 — AUTHORITATIVE" above). `BoundKind = ge|gt|le|lt`, one `kind`-dispatched meet
   helper, one ctor; behavior-preserving (Int-valued, int-only acceptance). Decimal/domain
   semantics (the bare-`>0`-is-number divergence) deferred to authoritative item 2b.
4. **[MEDIUM — function in wrong module] Move base64 out of `Json.lean`** (unchanged from
   prior pass, item 1 below). Extract `base64Encode`/`base64Alphabet` to `Kue/Base64.lean`;
   re-point `Yaml`, `Builtin`, `Module` callsites. Scoped mechanical slice.
5. **[MEDIUM — test/fixture organization, chakrit-flagged] Reorganize tests + `testdata/`**
   (unchanged from prior pass, item 2 below). Now overdue: `FixturePorts.lean` is 1936
   lines, `FixtureTests` 1033, `BuiltinTests` 735 — the three largest modules are all test
   infra. Concrete plan in the prior pass's item 2. Schedule as the periodic organization
   pass; one slice.
6. **[LOW — type-system leverage] Make `Field` a `structure`, not a `String × FieldClass ×
   Value` tuple `abbrev`.** `Kue/Value.lean:158`. Accessors `Field.label/fieldClass/value`
   already exist; the tuple still admits positional confusion and forces `.snd.snd`
   internally. A `structure Field where label; fieldClass; value` (with `Field.regular`
   smart ctor kept) tightens it with named projections. Low-impact, broad mechanical touch
   — defer behind the higher items; fold into the test-reorg or a quiet slice.
7. **[MEDIUM — promote candidate-gap] Linux `cacheRoot` default** (unchanged; item 3
   below). Real portability gap for Linux CI/dev without `$CUE_CACHE_DIR`/`$XDG_CACHE_HOME`.
   Small slice.

**Parser cohesion (`Parse.lean`, 1442 lines) — split is OPTIONAL, not urgent.** Structure
is three cohesive zones: a lexer/trivia/import/multiline-scan prelude (≈ lines 70–705), one
big `mutual` recursive-descent grammar block (706–1386, must stay together for Lean mutual
recursion), and a thin file driver (1387–1442). The available split is extracting the
lexer/lookahead prelude into `Kue/Lex.lean`, leaving Parse as grammar+driver. It's a real
cohesion win but a sizable mechanical move with no behavior change and no current pain
(the file is large but navigable and single-responsibility: "surface syntax → AST"). **Do
NOT split now** — it ranks below every item above on goal-impact. Revisit if the grammar
keeps growing or the prelude accretes more lexer state.

---

## Architecture Fix-Slices (Phase B audit 2026-06-17 #4 — post 2c.5 / FieldClass-refactor) — SUPERSEDED by #5

Whole-graph pass after tonight's deep-eval growth (imports, memo, embeddedList,
presence-test, 2c lazy-conjunction-eval, FieldClass orthogonal refactor). A real def-meet
pattern (`def_meet_template`) now exports cue-identically, and the optional-definition
blocker is cleared (2c.5). This supersedes #3 for ranking; #3 and below retained as record.

### Verdicts (whole-graph)

- **Inline fix applied (commit `faa8756`):** the `70e6ec0` FieldClass refactor (flat enum →
  orthogonal `field (isDefinition isHidden : Bool) (optionality : Optionality)` + `letBinding`)
  reintroduced a wildcard `_ => false` in `FieldClass.producesOutput` that now spans the
  `Optionality` lattice — a new optionality rung (or FieldClass ctor) would silently become
  non-output instead of breaking the build. Made exhaustive: `def`/`hidden` short-circuit on
  the boolean axes, then explicit `.regular`/`.required`/`.optional` arms + `.letBinding`. The
  other FieldClass projections (`isDefinition`/`isHidden`/`optionality`/`ignoresClosedness`)
  destructure fully and do NOT swallow a case — left as-is. `Format.lean:211` matches
  `Optionality` over all 3 rungs (no wildcard) — fine.
- **`Eval.lean` cohesion — verdict UNCHANGED: keep as one module, do NOT split (yet).** The
  conjunction-merge cluster (`lazyConjMergedFields`/`conjStructOperand?`/`remapConjRefs`/
  `applyConjClosedness`/`rebaseConjunctFields`/`mergeConjFields`) added tonight is a *pre-pass
  feeding the `mutual` block* — `conjStructOperand?`/`lazyConjMergedFields` sit between the two
  `mutual`s, `remapConjRefs`/closedness helpers are called from inside the lower `mutual`. They
  are intimately coupled to the eval recursion and the `Field`/`Env`/de-Bruijn refId machinery;
  a `Kue/Conj.lean` extraction would have to import `Eval` for the recursion or be imported by
  it while depending on its frame model — same Value-only-split bind as the memo infra. No real
  complexity reduction, pure churn. **Defer.** The `evalAdd…evalBinary` pure-op family
  (`Eval.lean` ~369–625, over `Value`+`Decimal` only, NO memo/env dependency) remains the one
  clean future extraction (`Kue/EvalOps.lean`) — but at 1191 lines with no navigation pain
  today, it stays LOW. Revisit either split only on next growth.
- **Module layering — verdict: clean, acyclic, no new back-edge.** Import DAG after the
  refactor: `Value` (base, no imports) ← `Decimal`/`Format`/`Normalize`/`Order`/`Parse`/
  `Resolve`/`Lattice`; `Eval → Builtin,Decimal,Lattice,Normalize`; `Builtin → Lattice,Decimal,
  Json,Yaml`; `Manifest → Format,Lattice`; `Json → Manifest`; `Yaml → Json`; `Runtime → Eval,
  Format,Lattice,Parse,Resolve,Json,Yaml`; `Module → Parse,Runtime`. The canonical forbidden
  edge `Builtin → Eval` is absent. FieldClass + conjunction-eval added NO new module — all
  inside `Value.lean`/`Eval.lean`. No cycle, no new edge.
- **Remaining loose reps (re-confirmed, all FOLDED below):** `intGe/Gt/Le/Lt` parallel ctors →
  `boundConstraint bound kind` (the textbook fold, item 3); `Field` tuple → `structure` (item
  5); `embeddedList.decls` non-output invariant unenforced by type (item 6). The `FieldClass`
  flat-enum looseness flagged in prior passes is now RESOLVED (it became a structure in 70e6ec0).
- **`Manifest.manifestFieldsWithFuel` (line 39) has a `_ =>` wildcard** swallowing FieldClass
  cases — but it is emission *dispatch* (the `.required` arm errors, the rest skip), not a pure
  projection, so it can't be tied to `producesOutput` directly and rewriting it is
  behavior-adjacent. Folded as a small type-tightening item, not applied inline.

### Ranked next-work list (goal = export real prod9/infra files matching cue)

**Recommendation: `int & >0` (item 1) is now the highest-priority work — it is the live
next-real-file blocker, ahead of the cleanup batch.** With 2c done and a real def-meet
template exporting byte-identically, the codebase IS at a good consolidation point — but
consolidation is pure debt-reduction with zero goal-unblock, and there is exactly one
known wrong-output bug left on the supported subset (`int & >0`). Fix the bug first, then
run the consolidation+test-reorg batch (items 3–4) as one verify cycle before the next
feature family. Next 3–4 slices, in order: **1 → 2 → 3 → 4**. **Item 1 DONE (2026-06-17);
next is item 2 (open-list collapse on Manifest), then the consolidation+test-reorg batch
(items 3–4).**

1. **[HIGH — live next-real-file blocker, WRONG OUTPUT] `int & >0` keeps both conjuncts.
   DONE (2026-06-17).** The bug was in MEET: `meetCore`'s `kind int & intGt/Ge/Le/Lt` arms
   collapsed to the bare bound, dropping `int`. Fix: `meetKindWithIntBound` retains `int` as
   `.conj [.kind .int, bound]` (formats `int & >0`), drops a redundant `number`, conflicts
   on `float`/other. The eager conj-injection broke multi-bound int ranges
   (`int & >=0 & <=65535` ping-ponged into nested conjs → `_|_`), so `meetConjValueWith` was
   rewritten to reduce over a **flat** constraint set (`flattenConj` + `addConstraintWith`):
   both sides flatten, fold pairwise, merge-or-append, re-fold a simplified member against the
   rest. Oracle-matched cue v0.16.1: `int & >0`→`int & >0`, `(int&>0)&1.5`→`_|_`,
   `(int&>0)&5`→`5`, `int & >=0 & <=65535`→flat (cue *displays* `uint16` — cosmetic alias,
   same value). 9 new `BoundTests` theorems; `meet_lazy_incomplete` fixture updated
   (oracle-confirmed cue agrees). **boundConstraint refactor (item 3) FOLDED** — 96
   `intG*` occurrences in `Lattice` + ~70 in tests = high blast radius, and the plan already
   sequences it as the consolidation batch lead. **Deeper twin folded too:** kue's bounds are
   int-only (`>0.5` parse error; bare `>0 & 1.5`→`_|_` vs cue's `1.5`) — needs float/number
   bound literals, tracked in compat-assumptions and item 3. Infra uses int bounds, so kue is
   correct there.
2. **[HIGH — semantic correctness] Open-list collapse on Manifest (`[1,...]`).** Phase A
   finding #4: `Manifest` returns `.incomplete` for an open-list tail where `cue` collapses
   `[1,...]` → concrete prefix `[1]` at manifest time. Real output divergence on any open
   list reaching output. Confirm exact cue collapse rule (prefix-only vs tail-default-fill)
   against oracle, then fix `Manifest`'s `listTail`/`embeddedList`-with-tail arm. Own slice.
3. **[MEDIUM — type-system leverage, FOLDS item-1's deeper twin] Collapse `intGe/intGt/intLe/intLt`
   → a kind+domain-tagged bound.** Four parallel `Value` ctors over one domain with a parallel
   `meetIntGe/Gt/Le/Lt` family in `Lattice` — textbook fold into an indexed type. Now the lead
   of the consolidation batch AND the principled close of the bare-bound divergence item 1
   surfaced: a bound must carry (a) a comparison `BoundKind = ge | gt | le | lt` AND (b) a
   numeric **domain** so a bare `>0` is a *number* bound (admits `1.5`, matching cue) while
   `int & >0` narrows to int. The bound value must widen from `Int` to a decimal so `>0.5`
   parses and float-domain comparison works. Target shape: `boundConstraint (bound : Decimal)
   (cmp : BoundKind) (domain : Kind)`. Touches `Value`/`Lattice`/`Format`/parser/`valueTag` +
   ~70 test references. Big blast radius — its own slice/batch, deliberately deferred past the
   manifest-collapse goal-unblock (item 2).
4. **[MEDIUM — consolidation + test-reorg batch, NOW DUE] base64-out-of-Json + test/`testdata`
   reorg + `Field`→structure + Manifest-dispatch tighten.** Run together (independent,
   mechanical, one verify cycle):
   - **base64 out of `Json.lean`** → `Kue/Base64.lean`; re-point `Yaml`/`Builtin`/`Module`.
   - **test + `testdata/cue/` reorg (chakrit-flagged, overdue)** — group the flat fixture dir
     into subsystem subdirs; split the three largest test modules (`FixturePorts` 2292,
     `FixtureTests` 1033, `BuiltinTests` 735) by family; update `FixturePorts` roots +
     `check-fixtures.sh` glob. This is the periodic organization pass — now due.
   - **`Field` tuple → `structure`** (`Value.lean:231`): named `label`/`fieldClass`/`value`
     projections (already exist as helpers) become real fields; kills positional `.snd.snd`.
   - **`Manifest.manifestFieldsWithFuel` wildcard** → explicit FieldClass arms so a new
     ctor/optionality rung breaks the build at the emission site too (small, rides this batch).
5. **[MEDIUM — promote] Linux `cacheRoot` default** (`Module.lean`): branch on
   `System.Platform` so Linux defaults to `~/.cache/cue` not `~/Library/Caches/cue` absent
   `$CUE_CACHE_DIR`/`$XDG_CACHE_HOME`. Small portability slice for Linux CI/dev.
6. **[LOW — type-system leverage] Refine `embeddedList.decls` element type.** "decls =
   non-output only" invariant enforced by the `declFields` filter but not the type. A
   `NonOutputField` newtype (smart ctor) makes it unrepresentable but ripples through
   `Manifest`/`Format`/`Eval`/`Lattice` + deriving. Defer behind goal-blockers; do alongside
   item 3 if `BoundKind` proves the newtype pattern out.
7. **[LOW — cohesion, optional] Extract `Eval` arithmetic/comparison dispatch → `Kue/EvalOps`.**
   See cohesion verdict above — no pain today; revisit on next growth. The conjunction-merge
   cluster is NOT a split candidate (too coupled to the `mutual`).

**Parser split (`Parse.lean`, 1440) — still OPTIONAL, do NOT split now.** Three cohesive
zones; ranks below every goal item.

## Architecture Fix-Slices (Phase B audit 2026-06-17 #3 — post deep-eval batch) — SUPERSEDED by #4

Whole-module-graph pass after the import/parser/memo/embeddedList/presence-test growth.
This is the current authoritative ranking; the two sections below (#2 eval-blowup, and
the original prior pass) are SUPERSEDED for ranking purposes but retained as the design
record. Items 1/2/2b already landed; the remaining work is re-ranked here.

**`Eval.lean` cohesion — verdict: keep as one module, do NOT extract.** It is one
responsibility ("AST `Value` → evaluated `Value`") expressed as one big `mutual` block
plus its pure dispatch helpers. The memo/`EvalState` infra (`Frame`/`Env`/`EvalKey`/
`EvalState`/`pushFrame`/`runEval`, ~90 lines) is tightly coupled to that `mutual` —
`pushFrame` is a `EvalM` action threaded through every recursive arm, and an `EvalCache`
module would have to either re-export the `mutual` or be imported BY it while depending on
its key type, forcing a `Value`-only split that buys nothing. The presence/definedness
piece (`Definedness`/`classifyDefinedness`/`evalPresenceTest`, ~40 lines) is pure and self-
contained — it *could* live in a `Kue/Presence.lean` over `Value`, but it's small, only
consumed by the one `.binary … .bottom` arm, and moving it adds an import edge for no
complexity reduction. Churn > pain on both. Revisit only if the arithmetic/comparison
dispatch family (`evalAdd…evalBinary`, ~250 lines, all pure over `Value`) keeps growing —
*that* block, not the memo infra, is the clean future extraction (`Kue/EvalOps.lean` over
`Value`+`Decimal`), and it would shrink `Eval.lean` by a quarter. Folded as a LOW item
below, not urgent.

**Module-layering — verdict: clean, no back-edge from the growth.** Re-checked the full
DAG after embeddedList + memo. `Value` base; pure cores (`Lattice`/`Order`/`Normalize`/
`Format`/`Decimal`/`Resolve`/`Parse`) over it; `Manifest → {Format, Lattice}`;
`Json → Manifest`; `Yaml → Json`; `Builtin → {Lattice, Decimal, Json, Yaml}` (NOT
`→ Eval` — old cycle stays broken); `Eval → {Builtin, Decimal, Lattice, Normalize}`;
`Runtime` wiring; `Module → {Parse, Runtime}` at the top. embeddedList is a `Value`
constructor so it added zero edges — `Lattice` builds/merges it, `Manifest`/`Format`/`Eval`
consume it, all already depending on `Value`. The memo `StateM EvalState` lives entirely
inside `Eval`; no module learned about it. **No cycles, no back-edges.**

**Inline fix applied this audit (commit `d11f80e`):** `FieldClass.producesOutput` and
`ignoresClosedness` were `_ => false` wildcards over the 6-variant enum (new-constructor-
swallow risk). Made exhaustive (explicit arm per variant) — a new `FieldClass` now breaks
the build at both decision sites until classified. Verify gate green.

### Ranked next-work list (goal = replace `cue` for prod9/infra)

**Recommendation: do 2c FIRST, before the cleanup batch.** 2c is the single remaining
real-file blocker for `apps/argocd.cue` (the canonical prod9 target) — every cleanup item
is pure debt-reduction with zero goal-unblock. Accumulated debt is real but bounded
(largest items are *test* infra, not core), and none of it is blocking a feature or
causing miscompiles. Push the deep semantics to first green on the target file, THEN spend
a consolidation batch (items 3–4 below) before the next feature family. Do not let the
MEDIUM cleanups jump the queue ahead of the one thing gating the goal.

1. **[DONE — argocd core path unblocked] 2c: Lazy field resolution through definition-meet.**
   Family. **2c.1 LANDED** (in-struct duplicate-label canonicalization): `canonicalizeFields`
   collapses duplicate-label slots in a struct frame into one first-occurrence slot carrying
   the unevaluated `.conj` of the conjuncts, applied before every `pushFrame` (the 5 struct
   arms + the top-level `evalStructRefsM` arms). `{a:int,b:a,a:1}` → `b:1`; nested visibility
   (`c:{e:a}`) works; conflicts bottom; the self-ref cycle guard holds. CORRECTION to the
   2c plan: the inlined-def case `d:{a:int,b:a}; y:d&{a:1}` is NOT fixed by 2c.1 — it is a
   *meet* of two independently-evaluated structs (`b` captures `int` before the meet brings
   in `a:1`), structurally identical to the referenced-`#D` path. Both are 2c.2.
   **2c.2 LANDED (the deep one): lazy resolution through struct conjunction (`&`).** The
   eval locus is the `.conj` arm (`Eval.lean`), NOT pure `meet`. New pre-pass
   `lazyConjMergedFields`: when *every* conjunct reduces to a same-scope struct
   (`conjStructOperand?` follows only depth-0 sibling refIds — the safety boundary; `none` for
   lists/prims/patterns/tails/disjunctions/outer refs → fall back to eval-then-`meet`), merge
   the conjuncts' *unevaluated* declarations into ONE frame (first-occurrence layout, deferred
   `.conj` on collisions), rebase each conjunct's depth-0 sibling refs onto the merged layout
   (`remapConjRefs`, a de-Bruijn-style total shift — depth>0 untouched since the merged frame
   sits exactly where each conjunct's frame would), apply per-conjunct closedness
   (`applyConjClosedness`, same as binary meet's `applyStructClosedness`), `canonicalizeFields`,
   push ONCE, eval. So `d & {a:1}` evaluates `{a: conj[int,1], b: a}` → `b: 1`. Fixtures:
   `meet_lazy_{sibling_ref,literal,incomplete,hidden_def,chain,disj_operand}` + export
   `def_meet_template` (reduced `packs.#Argo` shape — exports byte-identical to cue). 2c.1's
   in-struct canonicalization handles dup labels; 2c.2 extends it across `&`. **2c.5 LANDED
   (optional-definition class — the last real-file blocker):** `FieldClass` refactored from a
   flat enum into orthogonal axes `field (isDefinition isHidden : Bool) (optionality :
   Optionality)` + `letBinding` (a type-system-first fix — the flat enum admitted the illegal
   "uncombineable" `optional`+`definition` state). Legacy ctor names kept as smart constructors
   so the ~28-file blast radius collapses to 5 match sites (Manifest/Format/Eval/Normalize) +
   `mergeFieldClass`, which now merges per-axis (OR def/hidden, meet optionality on a
   present-dominates lattice). `#x?` (optional def), `#x!` (required def), `_x?` (optional
   hidden) are now first-class and merge correctly: `#D: {#x?: string}; y: #D & {#x: "hi"}` →
   `#x: "hi"` (eval), `{}` (export) — oracle-matched. Also fixed a flat-enum bug: `x? & x! = x!`
   (was wrongly `_|_`). Full suite green, +6 theorems +2 fixture pairs. **2c.3:** nested
   sub-struct visibility — proven free (`meet_lazy_hidden_def`,
   `def_meet_template` exercise 2–3 level nesting through def-meet). **2c.4:** `apps/argocd.cue`
   end-to-end — file not present on this machine; the reduced `packs.#Argo` def-meet templating
   shape is green, so the core path is unblocked. A fresh datestamped alpha is warranted.
2. **[HIGH — semantic correctness] Open-list collapse on Manifest (`[1,...]`).** Phase A
   finding #4: `Manifest` returns `.incomplete` for an open-list tail where `cue` collapses
   `[1,...]` to the concrete prefix `[1]` at manifest time. Smaller than 2c, real output
   divergence on any open list reaching output. Confirm exact cue collapse rule
   (prefix-only vs tail-default-fill) against oracle, then fix `Manifest`'s `listTail`/
   `embeddedList`-with-tail arm. Own slice.
3. **[MEDIUM — type-system leverage] Collapse `intGe/intGt/intLe/intLt` → `boundConstraint
   (bound : Int) (kind : BoundKind)`.** Four parallel `Value` constructors over one domain
   with a parallel `meetIntGe/Gt/Le/Lt` family in `Lattice` — textbook "parallel
   structures, fold into an indexed type". `BoundKind = ge | gt | le | lt` makes the four
   meet helpers one `kind`-dispatched helper and the four ctors one; real illegal-states
   win (no bound without a kind, no kind mismatch). Touches `Value`/`Lattice`/`Format`/
   parser/`valueTag`. Own slice — do as the lead item of the post-2c consolidation batch.
4. **[MEDIUM — consolidation batch] base64-out-of-Json + test/`testdata` reorg + `Field`→
   structure.** Run these together as the post-2c cleanup batch (they're independent,
   mechanical, and share a verify cycle):
   - **base64 out of `Json.lean`** → `Kue/Base64.lean`; re-point `Yaml`/`Builtin`/`Module`.
   - **test + `testdata/cue/` reorg (chakrit-flagged, overdue)** — group the flat 114-fixture
     dir into subsystem subdirs; split `BuiltinTests` (735) by family and assess
     regenerating `FixtureTests` per-subdir; update `FixturePorts` roots + `check-fixtures.sh`
     glob. `FixturePorts.lean` (2098) / `FixtureTests` (1033) / `BuiltinTests` (735) are the
     three largest modules and all test infra — this is the periodic organization pass, now due.
   - **`Field` tuple → `structure`** (`Value.lean:176`): named `label`/`fieldClass`/`value`
     projections kill positional confusion and the internal `.snd.snd`. Broad mechanical
     touch; ride it on the reorg's verify cycle.
5. **[MEDIUM — promote candidate-gap] Linux `cacheRoot` default** (`Module.lean`): branch on
   `System.Platform` so Linux defaults to `~/.cache/cue` not `~/Library/Caches/cue` when no
   `$CUE_CACHE_DIR`/`$XDG_CACHE_HOME`. Small slice; portability gap for Linux CI/dev.
6. **[LOW — type-system leverage] Refine `embeddedList.decls` element type.** The "decls =
   non-output fields only" invariant is established by the `declFields` filter
   (`!producesOutput`) but UNenforced by the type — `decls : List (String × FieldClass ×
   Value)` admits a `.regular` field directly. A `NonOutputField` newtype (smart ctor over
   the filter) or a refined subtype would make it unrepresentable, but it ripples through
   the `Manifest`/`Format`/`Eval`/`Lattice` select sites and the `BEq`/`Repr` deriving — not
   a clean small change. Fold as a slice, defer behind the goal-blockers; do alongside item 3
   if `BoundKind` proves the newtype pattern out.
7. **[LOW — cohesion, optional] Extract `Eval` arithmetic/comparison dispatch.** If the
   `evalAdd…evalBinary` pure-op family keeps growing, lift it to `Kue/EvalOps.lean` (over
   `Value`+`Decimal`), shrinking `Eval.lean` ~25%. Not urgent — no pain today; the memo
   infra and presence piece stay put (see cohesion verdict above). Revisit on next growth.

**Parser split (`Parse.lean`, 1442 lines) — still OPTIONAL, do NOT split now.** Three
cohesive zones (lexer prelude / one `mutual` grammar / thin driver); single-responsibility
and navigable. Ranks below every goal item. Revisit only if the grammar keeps growing.

---

## Architecture Fix-Slices (Phase B audit 2026-06-17) — prior pass, layering still valid (SUPERSEDED by #3)

Whole-module-graph pass (broader than Phase A's diff lens). **Layering verdict: clean.**
The internal import DAG is acyclic with the intended shape — `Value` at the base; pure
cores (`Lattice`/`Order`/`Normalize`/`Format`/`Decimal`/`Resolve`/`Parse`) over it;
`Builtin → {Lattice, Decimal, Json, Yaml}` (NOT `Builtin → Eval`, the old cycle stays
broken); `Eval → {Builtin, Decimal, Lattice, Normalize}`; serializers `Json`/`Yaml` over
`Manifest`/`Format` (`Yaml → Json` is a single-call reuse of `jsonString` for escaping —
legitimate, not a back-edge); `Runtime` as the wiring layer; `Module` at the top
(`→ Parse, Runtime`) with IO above the pure core. **No cycles, no back-edges, no muddled
module.** `Module.lean` is cohesive and does NOT need to split: the pure resolution core
(lines ~19–155) and the IO loader boundary (~157+) are already cleanly separated within
one file behind a documented split, and the IO entry points are thin — a physical
two-file split would buy nothing and add an import edge. Leave as-is.

Ranked (highest value first):

1. **[MEDIUM — function in wrong module] Move base64 out of `Json.lean`.** `base64Encode`
   / `base64Alphabet` live in `Kue/Json.lean` but base64 is not JSON; consumers are
   `Yaml.lean:137` (bytes scalar) and `Builtin.lean:623,625` (`encoding/base64`). It rode
   into `Json` with B6. Extract to a small `Kue/Base64.lean` (or a `Kue/Encoding/` home if
   base32/hex land later), re-point the 3 callsites + imports. Pure mechanical move, but
   crosses 3 modules so it's a scoped slice, not an inline fix. Low risk, build-verified.

2. **[MEDIUM — test/fixture organization, chakrit-flagged] Reorganize tests + `testdata/`.**
   Concrete plan, executable as ONE slice:
   - **`testdata/cue/` is a flat 114-fixture dir.** Group into subsystem subdirs:
     `numeric/` (additive/bytes-additive/number/float/bound), `strings/`, `lists/`,
     `structs/` (closed*/definition*/embed/pattern/comprehension*), `disjunctions/`
     (default*/disjunction), `builtins/` (base64/and_or/builtin*), `refs/`
     (reference/cycle/alias). Update the path roots in `FixturePorts.lean` +
     `check-fixtures.sh` glob in the same slice. `testdata/export/` and
     `testdata/modules/` are already coherent — leave them.
   - **Split the two oversized test modules.** `FixtureTests` (986 lines) and
     `BuiltinTests` (735) dwarf the rest. Split `BuiltinTests` by family
     (`StringsBuiltinTests` / `ListBuiltinTests` / `MathBuiltinTests` / `EncodingBuiltinTests`)
     — the families already exist as `evalXBuiltin` dispatchers, so the test split mirrors
     the code. `FixtureTests` is generated-style port assertions; assess whether it can be
     mechanically regenerated per-subdir after the `testdata/` regrouping rather than
     hand-split.
   - **`StructTests` (710) / `EvalTests` (635) / `ParseTests` (553)** are large but
     single-subsystem and cohesive — defer splitting unless they keep growing.
   Do NOT do the move in this audit (it's the periodic organization pass); this entry
   specifies it precisely so it runs as one clean slice.

3. **[MEDIUM — promote candidate-gap] Linux `cacheRoot` default.** `Module.lean:203`
   `cacheRoot` falls back to `~/Library/Caches/cue` (macOS) when neither `$CUE_CACHE_DIR`
   nor `$XDG_CACHE_HOME` is set — on Linux cue defaults to `~/.cache/cue`, so a Linux
   dev/CI without the env vars silently misses the cache. Cheap, real portability gap for
   the prod9 workflow. Fix: branch on `System.Platform` (or probe `~/.cache` vs
   `~/Library/Caches`) for the OS-correct default. Small slice.

4. **[DONE 2026-06-17] `kue export` cue.mod-discovery-from-subdir.** Diagnosed: the
   parent-walk started from the *relative* file directory, whose `.parent` dead-ends
   (`("sub" : FilePath).parent = none`), so the walk never climbed into the cwd's real
   ancestors — only abs-path args found the module root. Fix: `loadFileBound` now resolves
   the path against the working dir to an absolute path before taking `.parent`
   (`absolutePath`/`discoveryStartDir`, pure; `IO.currentDir` at the boundary).
   Relative-from-root, relative-nested, absolute, and relative-from-outside path args all
   discover the module root; no-cue.mod files still export plainly. Pinned by the
   `testdata/modules/export_subdir/` fixture (subpaths harness) + 5 `ModuleTests`
   theorems. Spot-check: real prod9 `infra/apps/*.cue` now resolve `cue.mod` and the
   `prodigy9.co/defs` cache dep; next wall is the dependency-side `[string]: string`
   pattern-constraint parse (blocker, below), not discovery.

5. **[LOW — candidate-gap, keep parked] Closedness gap / hidden-field refs / `[...]` eval
   laziness.** Already tracked under "Later Slices" and `compat-assumptions`; these are
   feature work, not architecture debt. Not promoted by this pass — they belong to the
   semantic roadmap, not the refactor backlog.

   **`[string]:` kind/type label patterns — ✅ DONE 2026-06-17.** Diagnosis: the
   semantic model (`structPattern`/`structPatterns`, `labelMatchesPatternWith`) already
   matched any constraint-valued label pattern, and the brace form `{[string]: int}`
   already parsed+typed correctly. The only gap was the **bare colon-shorthand**
   `#labels?: [string]: string` (= `#labels?: {[string]: string}`): `parseFieldValue`
   recognized labeled-field shorthand (`a: b: …`) but not a pattern field in value
   position, so it fell through to `parseExpression` → `parseList`, which choked on the
   trailing `:` ("unexpected character ':'"). Fix: a `valuePositionStartsPatternField`
   lookahead (balanced `[ … ]` immediately followed by `:`, via `skipBalancedBrackets`)
   routes a value-position pattern field through `parseField` + `parsedFieldsValue`,
   identical to the labeled-shorthand path. The bracket value is an arbitrary
   `parseExpression`, so kind (`[string]:`/`[int]:`/`[bool]:`), exact (`["a"]:`), bound
   (`[>0]:`), and regex (`[=~"re"]:`) all parse; `[1,2,3]` (no trailing `:`) stays a list
   embedding. Oracle-matched v0.16.1: typed field → typed; mismatch → ⊥; pattern-only →
   `{}`. Pinned by 4 fixtures + 2 `native_decide` EvalTests theorems. `defs/attr/
   metadata.cue` now parses. **Next real-file wall (NEW, not the `[...]` blocker):**
   `defs@v0.3.19/parts/pod_tolerations.cue` → "unexpected character '='". **DONE** — the
   `=` was a red herring. Root cause: `_`-prefixed identifiers (`_x`, `_parts`, `_base`)
   were mis-tokenized. `parsePrimaryAtom`'s `'_' :: rest => .top` matched bare `_`
   greedily, consuming only the `_` of `_x` and leaving `x …` as stray input; any
   expression starting with such an ident (`_x != _|_`, `value: _secret`, `_x + 1`) broke,
   and inside a `let X = {…}` body the misalignment surfaced as the outer let's `=`. Fix:
   `'_' :: next :: rest` defers to `parseIdentifierValue` when `next` is an identifier-rest
   char (so `_x`/`_foo`/`__bar` are identifiers), keeping bare `_` → top and `_|_` →
   bottom. Pinned by 2 fixtures (`underscore_ident_reference`, `underscore_top_bottom`) +
   3 `native_decide` theorems (incl. a B2 value-alias/`_|_` regression). `parts` now
   parses; `kue export apps/argocd.cue` advances to the eval-layer
   `meet(struct,list)=⊥` / `[...]` laziness blocker (item 1 below).

6. **[LOW — keep documented] B3c intermediate-deps leniency (per-hop deps vs MVS flat).**
   A deliberate, documented divergence from `cue` (compat-assumptions:109–113); both
   resolve when the artifact is on disk. Not debt — leave as the documented B3c boundary
   until B3d (registry + MVS solving) lands.

**Other findings:** none higher than the above. No dead code, no leftover scaffolding, no
cross-module duplication beyond the misplaced-base64 item. `joinModulePath`/`subpathDir`
in `Module.lean` look like near-dupes but `subpathDir` is a deliberate named alias for the
subpath use-site (documented) — acceptable. Representations are tight; no over-engineering
spotted.

## Later Slices

- Pattern-constraint label values are now general (any constraint expression parses+matches
  via both brace and colon-shorthand surface forms — done 2026-06-17). Remaining pattern
  work: fuller regular-expression matching in `meetValue` (the regex *subset* still bounds
  which `[=~"…"]:` patterns match), not the surface syntax.
- Re-resolve references against the post-unification merge (not just the lexical frame),
  so `#D & {x: 5}` resolves `y: Self.x`/`y: x` to `5` rather than leaving the constraint.
  Affects plain sibling refs and value-alias `Self.field` alike (see compat-assumptions).
- Expand cycle handling for arithmetic cycles and richer validation behavior.
- **Builtin families.** Top-level helpers, the `strings` package, and the `list`
  package (integer domain) are landed (see Implementation Status). The decimal-lift
  refactor is also landed: `DecimalValue` and its arithmetic/compare/format helpers now
  live in `Kue/Decimal.lean` (below both `Eval` and `Builtin`), so `Builtin` can do
  exact-decimal work without the old `Builtin → Eval` cycle. **Post-audit builtin
  hardening landed** (commit `1edc760`): the duplicated dispatch fallback is now one
  shared `unresolvedOrBottom` + `isConcreteArg` (reuse it in the `math` dispatcher
  instead of re-duplicating); `stringReplace` and `listFlattenN` are fuel-bounded total
  (no more `partial`); `strings.Replace` count==0, `list.Slice`
  negative-low, and a loop-var-shadows-sibling comprehension are pinned by tests.
  **Float mul/div landed** (this slice): the float-mul/div deferral pins were flipped to
  positive assertions; `evalMul`/`evalDiv` route float and mixed operands through
  `mulDecimalValues` / `divideDecimalRational?` in `Kue/Decimal.lean`. The shared divider
  replaced the prior int-only `formatIntegerDivision`, which over-emitted (fixed 34
  *fractional* digits rather than 34 *significant*) for quotients ≥ 1 — a latent bug now
  corrected.
  **`math` family rational-exact subset landed** (`Abs`, `MultipleOf`,
  `Floor`/`Ceil`/`Round`/`Trunc`): `evalMathBuiltin` reuses the shared
  `unresolvedOrBottom` fallback and does exact-decimal work via `parseDecimalText` +
  `formatFiniteDecimal`. `Abs` is domain-preserving (int→int, float→float);
  `Floor`/`Ceil`/`Round`/`Trunc` take a number and return an int (`Round` is
  half-away-from-zero). **Deferred from `math`:** `Sqrt`/`Pow` (irrational results need
  apd sig-digit context — `cue` gives `Sqrt(2)=1.4142135623730951` at ~17 digits but
  `Pow(2,0.5)=1.414…209698` at 34 digits, and `Sqrt(-1)=NaN.0` rather than erroring, so
  they need both apd-context formatting and a NaN value Kue does not yet model) plus the
  trig/log/`Exp` family.
  **Float-domain `list` builtins landed** (this slice): `list.Avg` plus float/mixed
  `Sum`/`Min`/`Max`/`Range`. The numeric builtins follow CUE's integral-collapse rule —
  an integral result renders as `int` (`list.Sum([1.0,2.0,3.0]) = 6`,
  `list.Avg([1,2,3]) = 2`), a non-integral one as float (`list.Avg([1,1,2]) =
  1.333…333`, 34 sig digits). New `collapseDecimalToValue` / `avgDecimalValue?` in
  `Kue/Decimal.lean`; `Builtin` accumulates via `addDecimalValues`, compares via
  `decimalLtValues`, divides via `divideDecimalRational?`. The all-int fast path on
  `Sum`/`Min`/`Max` is preserved.
  **`list.SortStrings` landed** (this slice): the comparator-free string sort.
  `listSortStrings` collects the elements as strings (any non-string ⇒ bottom) and runs
  the total, stable `List.mergeSort` with a byte-lexicographic `≤` (`byteSeqLe` over
  `String.toUTF8` — matches Go's `sort.Strings`, so `"Z" < "a" < "é"`). Still deferred
  from `list`: `Sort`/`SortStable` (need comparator-struct evaluation) — the only
  remaining `list` work.
  **`strings.ToUpper`/`ToLower`/`ToTitle` landed (ASCII subset)** (this slice):
  `asciiToUpper`/`asciiToLower` map via `Char.toUpper`/`toLower` (ASCII-only, non-ASCII
  passes through unchanged); `asciiToTitle` capitalizes the first letter of each
  whitespace-delimited word (oracle-confirmed: per-word, NOT upper-case-every-letter; word
  separator is whitespace only). Non-ASCII case folding is a documented deferral boundary
  (`compat-assumptions.md` → String case folding; divergences in `cue-divergences.md`).
  **`strings.SplitN` landed** (this slice): `stringSplitN` over a factored-out
  `stringSplitParts` (raw-string core now shared by `Split` and `SplitN`). Oracle-confirmed
  Go/cue `n` semantics — `n==0` ⇒ `[]`, `n<0` ⇒ all pieces (= `Split`), `n>0` ⇒ first
  `n-1` pieces verbatim with the remainder rejoined (via `sep`) as the last piece; empty
  `sep` splits to runes (then n-capped), empty `s` ⇒ `[""]` for non-empty sep. No
  deferral; empty-sep is cleanly supported.
  Then the still-unimplemented `strings` functions
  (`Trim`/`TrimPrefix`/`TrimSuffix`, `Runes`, `ContainsAny`, `LastIndex`, …) and full
  Unicode case folding. Each is oracle-checked against `cue` v0.16.1; the
  package-qualified dispatch (call-on-selector → dotted `.builtinCall` name) is in place,
  so a new family is an `evalXBuiltin` helper, a catch-all route in `evalBuiltinCall`, a
  fixture, and unit theorems.
- Add imports and full module resolution after the syntax and resolver layers exist.

## Audit Fix-Slices (Value.closure slices C + E — Phase A code-quality, audit 2026-06-18 #3)

Phase A over `1902191` (slice C, closure-default-in-guard) and `6fc26a5` (slice E,
closure-embed-chain). Type-system-first lens, read-only oracle probes (`cue` v0.16.1,
`/Users/chakrit/go/bin/cue`; prod9 NOT needed — every finding reproduces in `/tmp`).
Verify gate green at audit time: `lake build` 86 jobs, `check-fixtures.sh` "fixture pairs
ok", tree clean before this plan edit. Plan-only this pass — both Violations are behavior
changes needing their own fix-slice (one of them subsumes the planned B').

### Headline verdict — slice E SOUND; slice C has a real default-mark Violation; B' MISDIAGNOSED

- **E closedness-opening is SOUND** (the subtlest risk): no leak, no false conflict. A
  closed embed into an open host correctly admits host siblings (`{#A, a:1, c:9}` ==
  cue); a closed *host def* still rejects unknown use-site fields (`#B & {c}` → reject ==
  cue). Only delta is error-message precision ("conflicting values (bottom)" vs cue's
  "field not allowed") — cosmetic, not a correctness Violation.
- **E `hiddenFieldsOnly` is COMPLETE**: an embedded def resolves references in its OWN
  lexical scope, never the host's — cue says "reference not found" when an embed bare-refs
  a host regular field (`#Inner:{copy: host}` in `{#Inner, host:"H"}`). So dropping the
  host's regular fields from the embed splice drops nothing the embed could legitimately
  read. Verdict: not a gap.
- **C default-mark algebra is WRONG (Violation, F1 below)** — `combineMark` uses OR
  semantics where CUE uses AND; `flattenAlternatives` loses CUE's two-level default
  precedence. Produces spurious export errors where cue resolves.
- **B' "cross-def cache collision" is MISDIAGNOSED (Violation, F2 below)** — the real bug
  is a missing comprehension-expansion in the `.structComp` force arm; it reproduces with
  ONE def, no sibling, no cache. The EvalKey/pushFrame memo is NOT implicated. B' must be
  re-scoped to this exact target.

### Findings (ranked)

1. **[VIOLATION — `closure-default-mark-algebra`, slice C] `combineMark` is OR; CUE is
   AND. `flattenAlternatives` drops CUE's two-level default precedence.** CUE's rule: the
   default of `(A) op (B)` is `default(A) op default(B)` — an alternative is in the
   result's default set iff it came from default×default. `combineMark .default _ =>
   .default` / `_ .default => .default` (`Lattice.lean:189-192`) is logical OR; it must be
   `.default` iff BOTH inputs are `.default`. Oracle (eval, `/tmp`):
   - `(1|*2)+(10|*20)` → cue `22` (unique default = `*2+*20`); kue `11|*21|*12|*22` (3
     spurious defaults) → **export errors "multiple non-default disjuncts" where cue
     resolves to 22**. Wrong-error divergence, real.
   - `(*1|2)*(3|*4)` → cue `4`; kue manufactures multiple defaults.
   - `flattenAlternatives` (`Lattice.lean:194-203`) reuses `combineMark` for nested-disj
     flattening AND loses the level structure: `g: *d | 5` with `d: 1|2` → cue `1|2`
     (incomplete; the `5` arm is shed because a marked-default arm exists at that level,
     and the inner no-default disjunction stays unresolved). kue → `*1 | 2 | 5` (promotes
     inner `1` to default via OR, keeps `5`) → export errors where cue gives a clean
     `incomplete value 1 | 2`. So CUE's two-level rule is: if any top-level alt is marked
     default, ONLY default alts survive that level; the nested disjunction's own marks
     apply within — kue's flatten-then-uniform-filter collapses both levels.
   - `*1 | *1 | 2` → cue `1` (equal defaults dedup to one); kue errors "multiple
     non-default disjuncts" (`resolveDisjDefault?` requires exactly `[(_,v)]`, never dedups
     equal defaults).
   **Fix-slice:** (a) `combineMark` → AND (`.default` iff both `.default`); (b)
   `flattenAlternatives`/`normalizeDisj` must honor two-level default precedence (drop
   non-default top-level alts when a default exists at that level, recurse marks into the
   nested disjunction) — NOT a uniform flatten+`containsBottom` filter; (c)
   `resolveDisjDefault?` must dedup structurally-equal defaults before the
   unique-default test. Oracle-pin all three; add a both-operands-disjunction
   cross-product pin and a nested-default-flatten pin (see F3). Behavior change — own
   slice. **Does NOT block B'** (orthogonal: marks vs comprehension expansion), but is a
   genuine wrong-result/wrong-error bug; rank ABOVE B' or alongside.

2. **[VIOLATION — re-scopes B' `closure-crossdef-cache-collision`] The `.structComp`
   force arm DROPS conditional comprehensions.** `forceClosureWithConjunct`'s `.structComp`
   case (`Eval.lean:1544-1566`) does `comprehensions.filter isEmbeddingValue` for the
   embed-meet but NEVER calls `expandComprehensionsWithFuel` — so an `if`/`for` guard
   inside a deferred-then-forced structComp def is silently discarded. The eager
   `.structComp` eval arm (`Eval.lean:1380-1395`) DOES expand them (`:1384`,
   `staticFields ++ expanded`). Reproduces with ONE def, no sibling, no cache:
   - `#M: {#x: int, if #x > 0 { y: #x }}` then `#M & {#x: 5}` → cue `{y: 5}`, kue `{}`.
     (Same shape, eager/inline: `out: {#x: 5, if #x > 0 { y: #x }}` → kue `{y: 5}` ✓ —
     proving the loss is in the FORCE path, not the comprehension logic.)
   - The real-app `attr.#Ports` (`#port: int, if #port != _|_ { ports: [#port] }`)
     reaches the force arm via the embed deferral, loses its guard → the cert-manager
     `bottom`. The breadcrumb's "sibling `#PodController` poisons unrelated
     `#ClusterIssuer` via cross-def cache collision" is a MISREAD — the sibling just makes
     the package load the guard-bearing structComp; the failing eval is the structComp's
     own, in isolation. The `EvalKey = ⟨fuel, env.ids, visited, value⟩` /
     `pushFrame`/`valueTag` memo is NOT implicated (verified: single-def, single
     eval-entry repro; no second def to collide with; `fuel` correctly load-bearing,
     unrelated). **Fix-slice = re-scoped B' `closure-structcomp-force-comprehensions`:**
     thread `expandComprehensionsWithFuel fuel nested (comprehensions.filter (not ∘
     isEmbeddingValue))` into the `.structComp` force arm and merge its fields into
     `merged` BEFORE the embed-meet (mirror the eager arm exactly). Also audit the
     lazy-merge/conjunction path: `M & {#x:5}` for a non-def comprehension struct `M`
     ALSO drops the guard (`out: {}` vs cue `{y:5}`) — same class, separate site; pin both.
     Pin the real `attr.#Ports` shape as a module fixture.

3. **[BORDERLINE — test strength, fold into F1/F2] C and E pins under-cover the exact
   broken paths.** C's 8 pins all distribute over a SINGLE disjunction operand
   (`distributeBinary .add (.disj …) (.prim …)`) — none exercise the both-operands
   cross-product where `combineMark` lives, and none test nested-default flattening or
   equal-default dedup; the bug went unnoticed because every distribution pin is
   single-operand. E's 8 pins cover closedness + embed-chain narrowing but have NO pin for
   a structComp `if`-guard surviving a use-site meet (the F2 shape) and none guarding
   cross-def memo isolation (which turns out to be a non-issue, but a structComp-with-guard
   isolation pin is still owed). **Action:** F1 adds cross-product + nested-default +
   equal-default pins; F2 adds the structComp-guard-through-force pin (unit + module
   fixture). Pin the FIX, not the current behavior.

4. **[CLEANUP — confirmed sound, no action] Slice C `distributeUnary`/`distributeBinary`
   single-operand distribution and the guard collapse are cue-exact.** `(string|*1)-1` →
   `0` (regular branch errors, default survives — `liveAlternatives` filters the bottom,
   `resolveDisjDefault?` picks the lone default); `(1|2)+10` stays incomplete (no
   over-resolution); negated/direct/non-default guard collapse all match cue (n3/n4/n5
   probes). The `normalizeEvaluatedDisj` embedded-`.regular .bottom` alternative is benign
   — downstream `liveAlternatives`/`resolveDisjDefault?` filter it. No action.

5. **[CLEANUP — confirmed sound, no action] Slice E closedness-opening + hiddenFieldsOnly
   are sound and complete** (see headline). `closeEmbeddedOver` re-closes over `def ∪
   embed` labels correctly; opening the embed never leaks (closed host still rejects
   unknown use-site fields) and never false-conflicts (open host admits embed-opened
   fields). `hiddenFieldsOnly`/`stripLetBindings` drop only what an embed cannot lexically
   reach. The one cosmetic gap (kue's "conflicting values (bottom)" where cue emits the
   sharper "field not allowed"/"reference not found") is a diagnostics-precision item, not
   a correctness Violation — note for an eventual error-message pass, do NOT slice now.

### Sequence impact

B' as written (cross-def cache collision) does NOT exist — re-scope it to
`closure-structcomp-force-comprehensions` (F2). Recommended order: **F2 (re-scoped B',
the live cert-manager blocker) → F1 (default-mark algebra, independent correctness) →
re-probe cert-manager → B (perf).** F1 and F2 are orthogonal and could run in either
order; F2 is the real-app unblocker so it leads.

## F2 `structcomp-force-comprehension-loss` — **DONE 2026-06-18**

Landed (see implementation-log entry "F2 `structcomp-force-comprehension-loss`"). Both target
sites fixed (force-arm comprehension expansion + non-def lazy-merge), PLUS two
same-class-but-deeper sites surfaced while wiring the real-app path: the embed-chain deferral
(`bodyNeedsDefer`, an env-aware recursive gate so `Outer: {#Inner}` defers when `#Inner` carries a
guard), the conditional-embed-label closedness (`evalEmbeddingFieldsWithFuel` now forces embeds
WITH the host narrowing so conditional labels join the allow-set), and the standalone-selector
leak (`pkg.#Def` selected outside a conjunction now forces; the `.conj` fold re-produces via
`importSelectorDef?`). 4 new `native_decide` pins + 2 module fixtures
(`structcomp_force_guard`, `structcomp_lazymerge_guard`); 2 slice-3 pins updated for the
standalone-force; zero existing-fixture drift. Verify green (86 jobs, `fixture pairs ok`,
shellcheck clean, oracle byte-match on a 12-case matrix).

**F1 default-mark algebra still PENDING** (separate slice, untouched here — NOT marks-related).

### Real-app re-probe (HEADLINE — HONEST): error moved PAST F2 to a DISTINCT pre-existing bug

cert-manager / argocd STILL `bottom` (~11s / ~54s — perf wall unchanged). F2's comprehension loss
is genuinely fixed; the cert-manager error now lands on a **DISTINCT, PRE-EXISTING** bug (verified
on the HEAD `db5ee90` binary — NOT a regression from F2). **Next slice: `closure-import-selector-
alias` (correctness, the new live cert-manager blocker).** Minimal repro: `#A: parts.#M` (a def
whose value is DIRECTLY an import selector, no embed braces) + `defs.#A & {#name: "n"}` → kue
`incomplete value: string`, cue `{name: "n"}`. A second def referencing the `parts` import binding
also poisons an otherwise-resolving embed-form def (`#ClusterIssuer` resolves alone; adding ANY
`#Foo` that references `parts` collapses it). Root family: import-selector deferral through package
indirection — a def aliased to / embedding a selector into a multi-member package does not defer
its body to a closure, so the use-site narrowing arrives after collapse. NOT a cache collision
(cache-bypass build still bottoms → deterministic eval contamination). Sequence: this correctness
slice FIRST, then re-probe; perf B remains downstream (unreachable while apps error). F1 is
orthogonal and can interleave.

## `closure-import-selector-alias` — **DONE 2026-06-18** (two distinct sub-fixes)

Root-causing the slice split into TWO genuinely distinct bugs (both landed):

### Sub-fix 1 — alias-to-selector deferral (the minimal repro)

A def whose body IS an import selector (`#A: parts.#M`) — or embeds one (`#A: {parts.#M}`) — did
not defer through the package indirection: the producers (`importDefClosureBody?`/`refDefClosureBody?`)
detected only a DIRECT struct body that needs deferral, so an alias whose body is a `.selector`
(not a struct) fell to the eager path, resolving `parts.#M` in the `defs` frame BEFORE the use-site
narrows → `incomplete value: string`. **Fix:** `followAliasDefBody?` (Eval.lean) follows the
selector/ref indirection (fuel-bounded against cyclic chains) to the terminal struct body AND the
package frame it captures (`parts`, not `defs`), and the selector/ref producers fall through to it
when the direct check fails. New conjunct producers `refAliasSelectorDef?` (bare-ref form) thread the
terminal frame into the `.conj` fold's closure splice; `importDefClosureBody?` gained an alias-follow
fallthrough so `defs.#A & {…}` defers like a direct `defs.#M & {…}`. Pinned: 6 `native_decide`
theorems (headline splice, producer-fires, follow-returns-terminal-parts-frame, two-level chain,
no-over-deferral for a non-selector alias, cycle-terminates) + 3 committed module fixtures
(`alias_import_selector`, `_embed`, `_chain`) byte-identical to `cue`.

### Sub-fix 2 — duplicate import-binding meet-collision (the REAL cert-manager blocker)

Bisecting the offline real-app repro proved the isolated `#ClusterIssuer` is cue-exact; the bottom
came from the FULL `defs` package, narrowed to: **a second file in the `parts` package importing
`attr`** (e.g. `parts/pod_controller.cue` alongside `parts/metadata.cue`, both `import attr`). This
is the breadcrumb's "second def referencing the shared import binding poisons" facet. **Mechanism:**
`bindImports` prepends each file's imports to THAT file's struct value, then `mergeSourceValues`
`meet`-folds all files (Module.lean / Runtime.lean). Two files both importing `attr` ⇒ the package
struct gets the `attr` label TWICE, and `meet`-ing two independently-loaded copies of the same
package corrupts the binding → bottom. CUE binds imports file-scoped; the SAME package across files
must be ONE binding, not a meet of two copies. **Fix:** dedupe import bindings at the package level
(bind once across all sibling files), not per-file-then-merge. See implementation-log for the exact
edit. Minimal repro: `parts` package with two files both `import attr`, `parts.#Metadata & {#name}`
→ was bottom, now `{name: "n"}` cue-exact.

### Real-app re-probe after both sub-fixes — see implementation-log + breadcrumb for the landing.
