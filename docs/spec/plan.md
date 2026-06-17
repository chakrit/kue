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

## Architecture Fix-Slices (Phase B audit 2026-06-17 #5 — consolidation batch, AUTHORITATIVE)

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
2b. **[HIGH — bound-model semantics, NEXT bound item] Decimal/domain-tagged bound semantics.**
   The deferred SEMANTIC half: a bare `>0` should be a *number* bound (admits `1.5`, matching
   cue) while `int & >0` narrows to int, and `>0.5` should parse. Add (a) a numeric domain
   tag to `boundConstraint` so a bare bound is number-typed, and (b) a `Decimal`-valued bound
   so `>0.5` parses and float-domain comparison works. This is where `(int&>0)&1.5`→⊥ stays
   but bare `>0 & 1.5` starts matching cue. The 2a fold left the representation one field
   short of this on purpose. Touches the same `meetBound*`/`Format`/`Parse` arms.
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
4. **[MEDIUM — promote] Linux `cacheRoot` default** (`Module.lean`): branch on
   `System.Platform` so Linux defaults to `~/.cache/cue` not `~/Library/Caches/cue` absent
   `$CUE_CACHE_DIR`/`$XDG_CACHE_HOME`. Small portability slice; independent of the above.
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

**3a. base64 out of `Json.lean` → `Kue/Base64.lean`.** Move `base64Encode`/`base64Alphabet`
(currently in `Json.lean`) into a new `Kue/Base64.lean` over no Kue deps. Re-point the
three consumers' imports: `Yaml.lean` (bytes scalar), `Builtin.lean` (`encoding/base64`),
`Module.lean` if it references it. Add `Kue/Base64.lean` to the `Kue` umbrella import.

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
