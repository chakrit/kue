<!-- not spec/decision because: live cross-session breadcrumb; disposable, superseded in place -->

# Session resume — 2026-07-11

`main` == `gh/main` @ `a2bc950` (pushed). `check.sh` GREEN. Standing keep-going loop governs.
HEAD: **DOCS-CLEANUP — the docs now state a
single goal: a correct, spec-conformant CUE implementation across the whole language + stdlib
surface (chakrit, 2026-07-12).** CLAUDE.md § Project carries the north-star (spec-conformance is
the goal; `cue` is a fallible reference; no config corpus is a target/gate/floor/priority). Swept
every cert-manager / argocd / canary / prod9-as-goal reference out of the live docs — deleted
outright, never negated: retired the ~90%-dead `spec-conformance-audit.md` (its 3 live rows are in
plan.md, which now owns the ranked backlog); deleted plan.md's real-app-status block and reframed
the L1–L5 section as construct-level semantic fixes; genericized the perf / failure-modes /
slice-loop guides (kept the lessons, dropped the anecdotes); cleaned lean4-guide, compat-assumptions,
architecture, cue-spec-gaps, cue-divergences. `implementation-log.md` + `decisions/` left as
immutable history. **OPEN for chakrit (explicit go needed — working test infra, not docs):** remove
the `check-realworld.sh` real-config gate + `testdata/realworld/cert-manager/` fixture, the last
cert-manager tie. **Next: resume spec-conformance / robustness work — the language-surface coverage
the audits flagged unmeasured (comprehensions, closedness, pattern constraints, structural cycles,
scoping) + the F1–F5 float residuals, prioritized by conformance not usage.** Prior HEAD
MANIFEST-FIELDCOUNT below.

## Prior HEAD — MANIFEST-FIELDCOUNT — decouple manifest fuel from sibling breadth (HIGH audit fix)

`kue export` failed ENTIRELY on any struct with ≥99 top-level fields
(`incomplete value`), on trivial plain-int input. Root cause (by observation, NOT the
`manifestFuel=100` coincidence): `manifestFieldsWithFuel`/`manifestItemsWithFuel` (`Kue/Manifest.lean`)
peeled one fuel unit per SIBLING — the field at list-index `i` manifested at fuel `100-2-i`, hitting
0 (`.incomplete`) at `i=98` flat / `i=96` nested (the two-field offset = the enclosing struct's two
units). 500-field struct failed identically at index 98 → a constant bump is a pure cliff-move
(banned). Fuel must bound nesting DEPTH, not breadth. Fix: thread `fuel` UNCHANGED across siblings
(mirrors `evalFieldRefsListWithFuel`); only `manifestWithFuel`'s `fuel+1` descent into a value spends
a unit; termination via explicit lexicographic `(fuel, phase, len)`. Breadth now free (99/500/5000/
arbitrary counts byte-match `cue export --out json`); depth still capped at 100 (the legit totality
bound, shared with eval — noted, not the bug). WF recursion breaks `rfl`, so ~30 manifest `rfl` tests
migrated to the `(… == …) = true := by native_decide` BEq idiom (house standard; `Value` omits
`DecidableEq` by design) — whole surface in-slice (ManifestTests 23, FixtureTests 4, Closure/Eval 1
each). Wild fixtures `wide-struct-{export,nested,large}/` (RED→GREEN). Folded in a LOW audit
test-guard: `eval_add_context_rounding_half_up_even_tie` (apd half-UP tie rule, both signs, prior
coverage zero). **Class note: field-count/fuel cliffs — any fuel walk that decrements per list
element (not per depth) has this bug; the manifest was the last such site (eval was already correct).**
Committed on `main`, not pushed. **Next: F4-division form (derived rule ready in cue-spec-gaps.md),
then F1–F5 residuals.** Prior HEAD STDLIB-FLOAT-F4 below.

## Prior HEAD — STDLIB-FLOAT-F4 — apd result-exponent preservation for float `+ - *`.
Float arithmetic now threads the apd `(coefficient, exponent)` form (`ApdForm` +
`apdAdd`/`apdSub`/`apdMul` + `apdRoundToContext` + `apdCarrierText`, `Decimal.lean`) instead of
formatting the normalized `DecimalValue` (which erased a positive exponent), so `+ - *` byte-match
cue's GDA render: add/sub exp = `min(e₁,e₂)`, multiply = `e₁+e₂`, both rounded HALF-UP to the 34-digit
apd context. Fixes `2e2 * 3 → 6e+2`, `1e1 + 1e1 → 2e+1`, `1.20 + 1.30 → 2.50` (trailing zeros),
`1e34 + 1 → 1.000…e+34`, `1e1 - 1e1 → 0e+1`. NO change to the `DecimalValue` core type — the carrier
`text` round-trips through `floatApdForm` (the render anchor was always meant to carry the apd form;
only arithmetic failed to populate it). Removed dead `evalDecimalBinary?`/`evalDecimalMultiply?`.
**DIVISION DEFERRED** (subtler apd ideal-exponent) — `6e2 / 3 → 200.0` vs cue `2.0e+2` (VALUE correct,
FORM only); derived exact-division rule (reduce, shift exp −1 for integer results) recorded in
`cue-spec-gaps.md` STDLIB-FLOAT-F4 for a turn-key follow-up. Regression sweep: ZERO existing fixtures
flipped; 37-case manual kue-vs-cue sweep matches everywhere except the deferred division-form cases.
Wild fixture `float-apd-exponent-preservation/` (RED→GREEN) + `float_apd_arithmetic` cue fixture + 4
new EvalTests theorems (mul theorems reworked to assert `formatValue`). Committed on `main`, not pushed.
**Next: F4-division form (the derived rule is ready), then F1–F5 residuals (see plan § STDLIB-FLOAT);
F2 IEEE float64 kernel gated on real prod9 need.** Prior HEAD STDLIB-FLOAT F0 below.

## Prior HEAD — STDLIB-FLOAT F0 — wired the existing decimal `ln`/`exp` kernels
(`decimalLnScaled`/`decimalExpScaled`, already backing `math.Pow`'s general domain) to
`math.Log`/`Log2`/`Log10`/`Exp`/`Exp2`, all byte-identical to cue at 34-sig apd; shipped all 11 `math`
constants (`Pi`…`Log10E`) via `stdlibPackageValue?`. Fixed a latent trailing-zero trim bug: new shared
`renderTranscendentalScaled` (keeps significant trailing zeros, collapses only true integers) replaces
`collapseDecimalToValue` for both Pow + log/exp; corrected the mis-pinned `Pow(10,⅓)` test
(`…651935`→`…6519350`, cue-exact). Canonicalization item: `1.25e3` literal rendering CLOSED
(byte-identical eval+export); the `1.25e3 + 1`→`1251.0` vs cue `1251` arithmetic gap is REAL,
FILED as F4 (apd-exponent preservation), NOT claimed closed. `Log1p`/`Expm1` stay deferred (float64,
F2). 18 new BuiltinTests + `math_log` fixture. **Next: F1–F5 remain (see plan § Ranked OPEN backlog —
STDLIB-FLOAT); F2 (IEEE float64 kernel) is gated on real prod9 need, not speculative.** Committed on
`main`, not pushed. Prior HEAD BYTE-ESCAPE-STRICT below.

## Prior HEAD — BYTE-ESCAPE-STRICT + text/template nested-defer/fuel guards — one
slice folding three LOW audit findings. (1) `decodeByteEscape` (`Kue/Parse.lean`) brought to
cue-strict parity: dropped `\"`, added explicit `\/`, gated `\u`/`\U` on `Nat.isValidChar`; both
callers (`parseQuotedByteBody`, `parseMultilineByteBody`) now parse-error on `none` instead of the
lenient literal fallthrough; byte-context `\(` parse-errors "interpolation not supported yet" in both
byte forms. 18 new `byte_escape_*` `native_decide`; `BytesTests` `lex_bytes_interp_*` flipped to
`= none`. Quarantined `byte-literal-interpolation` seed's kue-output now a parse error (still red,
PROVENANCE annotated). (2) T1-LOW-1: 4 bridge theorems pin `manifestToTemplateData` float-defer at
list-element / struct-in-list / list-in-struct positions (+ int-nesting contrast). (3) T1-LOW-2: 2
byte-matched fuel guards (doubly-nested range + 24-elem single range) against a `runTemplate` fuel
weakening. plan.md BYTE-ESCAPE-STRICT ✅ CLOSED; spec-gap `STRING-ESCAPE-SET` byte-path clause closed.
Committed on `main`, not pushed. Prior HEAD STRING-ESCAPE-SET below.

## Prior HEAD — STRING-ESCAPE-SET — the CUE double-quoted string escape decoder.
The wild `\uXXXX`-dropped bug (below) is FIXED: `parseStringEscape` (decoded only `\n\r\t`, dropped
the `\` on everything else) is replaced by a total `decodeStringEscape` mirroring the byte path but
producing code points + raising a PARSE ERROR on bad escapes. Full set now decoded/rejected byte-for-byte
vs cue: `\uNNNN`/`\UNNNNNNNN` → code point (surrogate/out-of-range rejected via `Nat.isValidChar`),
`\a\b\f\v\n\r\t\\\/\"` simple, and `\xNN`/octal/`\'`/unknown/short-hex all parse errors. `\'` vs `\"`
is context-sensitive (string vs byte literal). Wild fixture promoted RED→GREEN (`.known-red` removed).
19 new `native_decide` in `ParseTests.lean`. Mirror BYTE-path leniency (accepts `\"`/unknown where cue
errors) filed as **BYTE-ESCAPE-STRICT (LOW)** in plan.md — NOT in this slice (blast-radius bound).
Spec-gap `STRING-ESCAPE-SET` records the `\/` cue-compat leniency. Committed on `main`, not pushed.
Prior HEAD STDLIB-TEXTTEMPLATE-T1 below.

## Prior HEAD — STDLIB-TEXTTEMPLATE-T1 — the `text/template` package's minimal
green core + escapers. cue v0.16.1 exposes EXACTLY three leaves: `Execute`/`HTMLEscape`/`JSEscape`
(all → string). New leaf module `Kue/TextTemplate.lean` (`import Kue.Value` only) = a total,
fuel-bounded lexer + parse-tree + tree-walk evaluator over its own `TemplateData` tree (float
UNREPRESENTABLE by construction) + the two pure escapers; `.textTemplate` `BuiltinFamily` arm +
`Kue.manifestToTemplateData` bridge (key-sorts struct fields). Shipped: text, `{{.F}}`/`{{.A.B}}`/
`{{.}}`, if/range(list/struct/null)/with + else, comment, `{{- -}}` trim, Go-`fmt` `map[k:v]`/`[a b c]`
rendering, missing/null ⇒ `<no value>` (nested null ⇒ `<nil>`). Deferred (`unsupportedBuiltin`):
FLOAT data (⇒ T3 float kernel), all FUNCS/pipelines/vars/printf/define (⇒ T2/T4), non-ASCII
`JSEscape` (IsPrint table); malformed template / field-on-scalar ⇒ bottom, nonexistent leaf ⇒ bare
bottom. 35-case differential byte-identical to cue. `Kue/Tests/TextTemplateTests.lean` (60+
`native_decide`) + `testdata/export/text_template_basic.{cue,json}`. **Wild-caught bug it seeded:**
`testdata/wild/cue-unicode-escape-dropped/` — the `\uXXXX`-dropped string-lexer bug — is now FIXED by
STRING-ESCAPE-SET (HEAD above; fixture promoted, `.known-red` removed). Retraction: wild
`stdlib-import-misrouted` guard stays at `uuid` (NOT repointed).
Committed on `main`, not pushed (attended-push pending). Prior HEAD STDLIB-NET below.

## Latest slice (2026-07-11) — STDLIB-TEXTTEMPLATE-T1 (`text/template`, minimal core + escapers)

New `.textTemplate` `BuiltinFamily`. `Kue/TextTemplate.lean` (leaf, imports `Kue.Value` only): lexer
(`{{`/`}}` + `{{-`/`-}}` trim), whitelist parser (`parseSeq`, fuel = item count — anything outside
the T1 grammar ⇒ `.unsupported`), fuel-bounded tree-walk evaluator (shared decreasing budget). Float
defer boundary = illegal-states-unrepresentable: `TemplateData` has NO float constructor, so
`manifestToTemplateData` (`Builtin.lean`) returns `none` on a `.prim (.float …)` anywhere in the
tree ⇒ `unsupportedBuiltin "text/template.Execute"`. Two render modes: `renderAction` (top-level
null ⇒ `<no value>`) vs `renderGoValue` (nested null ⇒ `<nil>`, Go-`fmt` `map[]`/`[]`). `JSEscape`
ASCII exact (7 named escapes + control `\u00XX` uppercase); non-ASCII ⇒ `unsupportedBuiltin
"text/template.JSEscape"` (IsPrint table deferred). Full detail: implementation-log. T2/T3/T4
roadmap in plan.md.

## Latest slice (2026-07-11) — STDLIB-NET (`net` package, scoped to IP validators)

New `.net` `BuiltinFamily`. `Kue/Net.lean` holds the `netip` parser (strict IPv4, IPv6 `::` +
embedded-v4 + `%zone`) + CIDR + `Addr.Is*` classification, all fuel-bounded/total. Extended
`StringFormat` with `netIP`/`netIPv4`/`netIPv6`/`netIPCIDR` + 7 class predicates (no new `Value`
ctor); `stringFormatValid` (`Time.lean`, now imports `Net`) dispatches them; meet unchanged
(ground bottoms, abstract retains). `evalNetBuiltin` + bare-validator/const resolution
(`Parse.lean`) + `net.` in `builtinImportPaths`. FQDN deferred (cue = idna `ToASCII`, full
IDNA2008 — `ab--cd`/`xn--a` reject). Full detail: implementation-log.

## Latest slice (2026-07-11) — STDLIB-TIME Phase-A audit followup

Three `56fe65e` audit findings closed in one slice. MEDIUM: `validRFC3339Offset` was
structural-only (any two digits passed); now range-checks hour ≤ 24 / minute ≤ 60 (boundary
verified against the cue v0.16.1 binary — 24 and 60 are the accepted maxima). LOW-1: over-range
offset theorems + `stringFormat` disj-arm-survival theorem; `manifestValueOk` promoted to shared
helper. LOW-2: the "fractional-division divergence" was undemonstrated — a hard probe CONFIRMED
a real one (kue exact-integer beats cue's float64 by 1 ns), now logged + pinned. Wild fixture
`rfc3339-offset-overrange` (red→green). Full detail: implementation-log.

## Latest slice (2026-07-11) — STDLIB-TIME (`time` package, scoped)

New `.time` `BuiltinFamily`. `Kue/Time.lean` holds the Go-duration lexer (`parseGoDuration`,
structural/fuel-bounded) + calendar-aware RFC3339 validator (leap-year days-in-month). New
`Value.stringFormat (fmt)` meet-participating string validator, threaded like `stringRegex`
everywhere (ground non-conforming string bottoms; ABSTRACT string RETAINS — `string &
time.Duration()` stays incomplete). Shipped: `ParseDuration`, the `Duration`/`Time` validators
(bare/`()`/bool-fn forms), `Format` for RFC3339/Nano layouts, all unit/layout/month/weekday
constants. Deferred (`unsupportedBuiltin`): `Unix`/`Parse`/`FormatString`/`Split`/`FormatDuration`
+ non-RFC3339 `Format` layouts (need epoch/format engine); `time.Date` bare-bottom. Duration
int64-bounded (Go type contract). `Kue/Tests/TimeTests.lean` (60+ `native_decide`) +
`testdata/export/time_basic.cue`. Retraction: wild `stdlib-import-misrouted-to-disk-loader`
repointed `time` → `net`. Full detail: implementation-log.

## Latest slice (2026-07-11) — STDLIB-B-PHASEB (Phase-B audit cleanup)

Four Phase-B findings folded into one low-risk slice. **2A (MEDIUM, latent drift):**
`finalizeLengthConj` matched only `.list` for uniqueness finalization, missing
`.listTail`/`.embeddedList` while meet-time `classifyUniqueTarget` covered all three — a
meet-vs-manifest divergence. Fixed by routing through the shared `listItems?` extractor, HOISTED
`EvalOps.lean → Value.lean` (lowest common module; `Lattice → EvalOps` would cycle). **1B (LOW):**
`isConcreteArg → isSettledArg` — pure rename + doc; it gates dispatch-settled SHAPE, not
groundness (use `Value.isGround` for that). **3A (LOW, retraction):** refreshed stale post-rename
symbols in `cue-spec-gaps.md` (`fieldCountConstraint → lengthConstraint .fields`, etc.). **Plan
hygiene:** B-3 dropped (moot), B-4 re-scoped+deferred, 2B filed deferred (coupled to next validator
shape). 2 new `native_decide` (listTail meet/manifest agree). Full detail: implementation-log.

## Latest slice (2026-07-11) — STDLIB-VALIDATORS-SOUND (Phase-A HIGH-1/HIGH-2 fix)

Two confirmed HIGH soundness bugs from the STDLIB-VALIDATORS (`5d9b65c`) Phase-A audit, one
shared root cause (conflating "structurally decided now" with "final/concrete" — eager
decisions sound only on GROUND values firing on ABSTRACT ones). HIGH-1: abstract-string length
→ `LengthMeasure.unknown` (was fabricated `lowerBound 0`), so `string & MinRunes(n)` retains
incomplete and `(string & MinRunes(5)) | "hi"` no longer collapses to a fabricated `"hi"`.
HIGH-2: `hasStructuralDup` → `hasGroundDup` gated on new total `Value.isGround`, so
`[int,int] & UniqueItems` retains rather than eager-bottoming; ground dups (`[1,1]`,
`[{a:1},{a:1}]`) still bottom. 4 RED-first wild fixtures + 11 new `native_decide`. Two
`cue-divergences.md` rows (cue export's own abstract-UniqueItems fabrication; disj render
delta). Full detail: implementation-log.

## This session (2026-07-10→11) — two LOW slices + a wild-caught STDLIB campaign

Attended. chakrit asked: do the queued LOW tasks, then test-drive kue on interesting
internet CUE examples. The test-drive (tour + cuetorials examples vs `cue` v0.16.1) matched
on simple cases and surfaced a whole frontier: **the CUE stdlib is ~1/3 implemented.** Ten
slices + a two-phase audit landed, all pushed, all green.

### Landed (git `00a706d..b00129e`)

- **AUD-B5 `8ed98e1`** — DRY'd the two BFS requirement-graph builders into
  `bfsRequirementGraphAux` (leaf-callback combinator, structural on fuel; AD4-1 shape).
- **B3d-B1 `be936dc`** — `Hash1` newtype for the cue.sum h1 digest; eliminated a latent
  fake-empty-h1 seed (real illegal-states win).
- **STDLIB-A `4625079`** — stdlib import ROUTING: `isStdlibImportPath` (dot-free first path
  element ⇒ builtin layer; dotted-domain ⇒ external module) + clear
  `unsupported builtin package "<path>"` error, no more misleading `no cue.mod`.
- **STDLIB-B `2c3ce9e`** — `struct.MinFields/MaxFields` as a `meet`-participating
  `fieldCountConstraint` validator (counts REGULAR fields only; optional/required/hidden/
  def/`let` excluded).
  - **FIELDCOUNT-DISJ `9a32bdb`** (Phase-A audit fix) — retained-min residual inside a
    disjunction arm wasn't finalized on collapse → spurious "ambiguous". `finalizeDisjArm`
    (`Manifest.lean`) finalizes each arm at manifest; accretion untouched.
- **STDLIB-C `326b8c4`** — `strconv` package (`Kue/Strconv.lean`, `.strconv` family).
  Shipped Atoi/FormatInt/FormatUint/ParseInt/ParseUint/FormatBool/ParseBool (arbitrary
  precision, base-0 prefixes + underscores + bitSize). Deferred → unsupported-fn error
  (real-but-not-computed): FormatFloat/ParseFloat (exact-decimal core), Quote/Unquote/QuoteToASCII
  (Unicode IsPrint table). Itoa is non-callable in cue → bottoms BARE, not "unsupported" (B-1
  2026-07-11). Divergence: base 2..36 vs cue's leaked 2..62.
- **STDLIB-D `d902e03`** — root cause was NOT import-specific: kue lacked CUE statement
  separation entirely. Implemented newline-as-implicit-comma (`skipSameLineTrivia` +
  `fieldSeparator`); `a: 1 b: 2` / late imports now rejected. Broad parser change, audit
  verified sound.
- **STDLIB-E `7707355`** — render-only: cue-shaped `imported and not used: "<path>"`
  (`" as <alias>"` aliased).
- **LIST-SEP `2c3659b`** — list-element separators (reuses D's `fieldSeparator`). `[1 2]`
  now errors; `[1\n2]`→`[1,2]` (spec auto-comma — **kue is more spec-correct than cue here:**
  cue rejects newline-elision in `[]` while accepting it in `{}`, its own inconsistency;
  recorded in `cue-divergences.md`).
- **audit-followup `b00129e`** — closed the two Phase-B LOW nits (doc-count drift;
  `every_builtin_package_resolves_to_family` sync theorem) + Phase-A #3 (strconv deferred-fn
  now renders `unsupported builtin function "strconv.Quote"`). Recorded (not fixed) the
  block-comment leniency.

### Two-phase audit (over the batch) — DONE

Phase A (code-quality) found the FIELDCOUNT-DISJ correctness bug (fixed) + its test gap +
the strconv-diagnostics nit; verified STDLIB-D's ASI change sound. Phase B (architecture)
clean — the builtin-package dispatch SCALES (~2 files + optional leaf per package), so the
stdlib campaign is cheap to continue. Both audits logged.

The BLOCK-COMMENT-REJECT + STDLIB-PATH batch's own two-phase audit filed B-1 (MEDIUM) + B-2/F1/F2
(LOW) + B-3/B-4 (test-org). **Followup slice landed (2026-07-11):** B-1 unified the three builtin
fallback shapes into one `unsupportedOrBottom` combinator and ADJUDICATED the marker — it's a
positive recognition claim, emitted only from explicit real-but-deferred arms; the catch-all bottoms
bare (nonexistent-leaf, cue-compatible). Fixed the mislabeled-nonexistent pins (Itoa, FindString).
B-2 (stale doc), F1 (collapsed duplicate trivia skippers), F2 (interpolation block-comment pin) done.
B-3/B-4 (test-org) DEFERRED to a future test-org pass. Detail: plan.md + implementation-log.

## Next steps — the STDLIB frontier (see `plan.md` § Ranked OPEN backlog)

Two tracks:

1. **Spec-conformance (unambiguous, no priority call):** `BLOCK-COMMENT-REJECT` ✅ LANDED
   (2026-07-11) — kue now rejects `/* */` (removed `dropBlockComment` + the `.block` Lex
   state in `ModCmd.lean`); every position errors `unexpected character`. Guarded by wild
   fixture `block-comment-rejected` + `ParseTests parse_block_comment_*`. Next spec-conformance
   items: none currently queued (cue-divergences.md § kue-side is now empty).
2. **New stdlib packages (priority-sensitive — key to which packages prod9 configs hit):**
   `time`, `net`, `uuid`, `crypto/*`, `encoding/hex|csv`, `text/template`; finish
   `strconv` (Quote/FormatFloat need a Unicode IsPrint table / float-format design); round
   out `strings`/`list`/`math`. Dispatch cost is low (audit-confirmed).
   - **STDLIB-PATH ✅ LANDED (2026-07-11)** — `path` package (was the highest-usage
     unimplemented, 11 prod9 hits). `Kue/Path.lean` + `.path` `BuiltinFamily`. Full unix/plan9:
     Clean/Join/Split/Dir/Base/Ext/IsAbs/SplitList/Resolve/Rel/Match(Go glob)/ToSlash/FromSlash/
     VolumeName + `path.Unix/Windows/Plan9` constants (no `path.OS` — not a real cue field).
     Windows os DEFERRED (`unsupportedBuiltin`); invalid os bottoms. 75 theorems. Spec-gap + log.
   - **STDLIB-VALIDATORS ✅ LANDED (2026-07-11)** — the `meet`-participating constraint validators:
     `list.MinItems`/`MaxItems`/`UniqueItems`, `strings.MinRunes`/`MaxRunes`. GENERALIZED the
     `struct.MinFields` validator: `fieldCountConstraint` → `Value.lengthConstraint (kind)(bound)(limit)`
     (`kind` ∈ fields/listItems/runes) + sibling `Value.uniqueItems`. Closed list / concrete string
     decides at meet; struct / open list / abstract string retains + finalizes (`finalizeLengthConj`).
     Runes = code points, not bytes. UniqueItems equality field-order-independent (`eqUpToFieldOrder`).
     Bare `list.UniqueItems` + `()` form both work. ~40 theorems + `export/list_string_validators`
     fixture (byte-identical to cue). `list.IsSorted` DEFERRED (comparator arg = BI-EFF corner).
   - **STDLIB-STRINGS-LEAVES ✅ LANDED (2026-07-11)** — the remaining PLAIN `strings` functions.
     Oracle diff (`pkg/strings/pkg.go` = 34 funcs) → 8 missing, all pure/total, none effectful:
     `ByteAt`/`ByteSlice` (BYTE-indexed; `ByteSlice` returns `bytes`; `Prim.bytes` already existed
     so the "byte-array-repr" filing was moot), `ContainsAny`/`IndexAny`/`LastIndexAny` (rune SET,
     BYTE offsets), `SplitAfter`/`SplitAfterN` (sep stays on preceding piece; trailing sep ⇒
     trailing empty; fuel-bounded, total), `ToCamel` (word-initial lower-case; shares
     `mapWordInitial` with `asciiToTitle`; ASCII-bounded, non-ASCII passthrough divergence in
     spec-gaps). Task candidates `SplitAny`/`IndexRune`/`Map` DON'T exist in cue's strings pkg —
     confirmed, nothing deferred. 25 theorems + `export/strings_leaves` fixture (byte-identical).
     Next stdlib: `time`, `net`, `uuid`, `crypto/*`, `encoding/hex|csv`; finish `strconv` Quote/Float.

Test-drive scratch files at `~/Documents/chakrit/kue-testdrive/` (outside the repo).

## Historical (not this session)

- ace-connect bridge (slug `chakrit.kue.claude`, control mode) was live in the 2026-07-07
  session; NOT touched this session — do not assume it's still running. Recover per
  ace-connect Flow step 4 if needed.
- 2026-07-07: AUD-B6 (`b1be061`), release `v0.1.0-alpha.20260707.1`. Detail in the log.

## Pending school changes

None this session.
