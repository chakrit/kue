<!-- not spec/decision because: live cross-session breadcrumb; disposable, superseded in place -->

# Session resume — 2026-07-11

`check.sh` GREEN. Standing keep-going loop governs (the 2026-07-07 "autonomy paused" gate is
resolved/historical). HEAD: **STDLIB-TEXTTEMPLATE-T1** — the `text/template` package's minimal
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
`native_decide`) + `testdata/export/text_template_basic.{cue,json}`. **Wild-caught OUT-OF-SCOPE bug
queued:** `testdata/wild/cue-unicode-escape-dropped/` (`.known-red`) — kue's cue-file string lexer
DROPS the backslash on a `\uXXXX` escape (`"café"` → `"cafu00e9"`; cue correct); seed for a
string-lexer slice. Retraction: wild `stdlib-import-misrouted` guard stays at `uuid` (NOT repointed).
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
