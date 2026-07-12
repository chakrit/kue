<!-- not spec/decision because: live cross-session breadcrumb; disposable, superseded in place -->

# Session resume — 2026-07-11

`check.sh` GREEN. Standing keep-going loop governs.
HEAD: **BOUND-OPERAND-CLASSIFY — soundness regression FIXED (LANDED 2026-07-12).** Split
`ScalarOperandClass.defer` into `.incomplete` (retain the residual `.unary`) vs `.nonScalar`
(`.list`/`.listTail`/`.embeddedList`/`.struct`). `evalBoundOp`/`evalRegexMatchOp`/`evalNumPos`/
`evalNumNeg` now ⊥ a ground list/struct (was fabricating `<[1,2]`/`<{a:1}`/`=~[1]`/`-[1,2]`);
`evalNeOp` retains (`.nonScalar` arm == `.incomplete` arm); `.top`/`.disj`/`.kind`/abstract-constraints
stay `.incomplete` (`<_`, `<(1|2)` RETAINED). 4 wild guards RED→GREEN + 13 EvalOpsTests theorems
(list/struct/embeddedList ⇒ ⊥ across the four ops, closing the `.bool`-only coverage gap; both-direction
retain guards for neOp/top/disj). `=~5` micro-divergence logged in cue-divergences.md. PA-BOUND-GROUND
discharged. **NEXT (ranked): `BOUND-ORDEREDPRIM` (LOW)** —
`OrderedPrim` bound-operand retype (~60-site refactor; complements, does NOT subsume, the classifier).
Then the flagged binary-comparison sibling (`1 < [1,2]` retains where cue errors — same class, different
path, filed by Phase B); remaining core probes (structural cycles, scoping); F1/F3/F5; LOW audit findings
(PA-ESC-2 / PA-SUB-4 / PA-TT-5 / PB-RELEASE-3 / PB-TESTORG-4).
Prior HEAD (last CODE slice): **PATTERN-BOUND-OPERAND — comparator bounds over any ordered type (LANDED 2026-07-12).**
Comparator bounds (`< <= > >= != =~`) now apply to ANY ordered type and to non-literal operands;
BOTH red seeds `pattern-bound-{string,reference}-operand` GRADUATED. `boundConstraint`'s operand
generalized `DecimalValue → Prim` (arity unchanged → ~30 wildcard match sites untouched); one total
`primOrdCompare?` (+ `BoundKind.admitsPrim?`) drives every bound comparison — numeric decimal, string
lexical by code point (`charsLt`), bytes by byte order (`bytesLt`). `domain` is numeric-only now (inert
`number` sentinel for string/bytes; family fixed by operand kind via `boundKindLabel`/`boundAdmitsKind`).
**Facet 2:** `UnaryOp` gained `boundOp`/`neOp`/`regexMatchOp`; parser lowers a literal operand
immediately, emits a deferred `.unary … operand` for a reference/call (`>k`, `{[=~_re]:int}`, `<len(x)`),
which `evalUnary` lowers to the concrete validator once ground (per CUE grammar `unary_op = … | rel_op`).
Byte-parity with cue v0.16.1: `<"m" & "apple"`→`"apple"`, `string & <"m"`→`<"m"`, `>"a" & >"m"`→`>"m"`,
`bytes & <'m'`→`<'m'`, `=~"^a" & <"m"`/`<"m" & !="a"` conjoin, `>k & "zebra"`→`"zebra"`; `int & <"m"` /
`>5 & >"m"`→⊥ (kue's terser `_|_`). Numeric bounds unchanged. Theorems: `BoundTests` ordered-type section
+ `EvalOpsTests` deferred-lowering section. NOT a cue-divergence (cue was spec-correct). Docs: plan.md
(✅ LANDED, both facets), compat-assumptions.md (bound repr rewritten), implementation-log. `check.sh`
GREEN, committed on `main`.
**Next (ranked):** remaining core-conformance probes — **structural cycles** (spot-check Bug2x for
cycle-through-comprehension / disjunction-guarded cycles), **scoping/reference-resolution** (shadowing
across `let`/field/comprehension-var/alias, hidden-field scope); then float follow-ups **F1**
(`math.Log1p`/`Expm1`) → **F3** (trig) → **F5** (`text/template` float render + `math.Float64bits`); then
LOWs PA-ESC-2 / PA-SUB-4 / PA-TT-5 / PB-RELEASE-3 / PB-TESTORG-4.
Prior HEAD CORE-CONFORMANCE-PROBE below.

## Prior HEAD — CORE-CONFORMANCE-PROBE — pattern-constraint core surface MEASURED (LANDED 2026-07-12).
Bounded differential hunt (~30 cases) over pattern constraints (`[pattern]: constraint`), the
least-recently-probed flagged core area (structural cycles are heavily covered by `Bug2xTests`;
closedness/comprehensions probed 2026-07-04). **Surface is CONFORMING** — regex label filtering,
overlapping-pattern constraint INTERSECTION (incl. comparator-bound values: `[=~"a"]:<10 &
[=~"b"]:>5` meets to `<10 & >5` on a doubly-matched field), recursive patterns, unification-
introduced patterns, disjunction-valued patterns — all byte-identical to cue v0.16.1. Now MEASURED
+ pinned: `testdata/export/pattern_constraints.{cue,json}` + 6 `native_decide` in `ClosednessTests`
(pattern-constraint conformance probe section). **ONE gap found (NEW facet of an already-filed
bug):** a LITERAL string/bytes bound operand (`x: <"m"`, `{[>"m"]: int}`, `>='a'`) fails to parse
("expected number digits") — `parseBoundValue` is numeric-literal-only and `boundConstraint` carries
`DecimalValue` (numeric by construction). SAME root cause as the filed **PATTERN-BOUND-REF-OPERAND**
(reference operands); both land together via the one core change (generalize bound operand →
`Prim`/expr + lexical string/byte-order compare in meet/order/manifest). Red-seeded
`testdata/wild/pattern-bound-string-operand/` (`.known-red`). NOT a cue-divergence (cue spec-correct).
No product-code change. Docs: plan.md (PATTERN-BOUND-REF-OPERAND facet + measured record),
implementation-log. `check.sh` GREEN, committed on `main`.
**Next (ranked):** remaining UNMEASURED core areas to probe — **structural cycles** (spot-check the
Bug2x coverage for gaps in cycle-through-comprehension / disjunction-guarded cycles), **scoping/
reference-resolution** (shadowing across `let`/field/comprehension-var/alias, hidden-field scope);
then the filed **PATTERN-BOUND-{REF,STRING}-OPERAND** core fix (attended, broad — generalizes the
bound operand, graduates BOTH red seeds); then float follow-ups **F1** (`math.Log1p`/`Expm1`) → **F3**
(trig) → **F5** (`text/template` float render + `math.Float64bits`); then LOWs PA-ESC-2 / PA-SUB-4 /
PA-TT-5 / PB-RELEASE-3 / PB-TESTORG-4.
Prior HEAD PA-FLOAT-TEST-6 below.

## Prior HEAD — PA-FLOAT-TEST-6 — permanent guards for the F2 kernel's hardest boundaries (LANDED 2026-07-12).
Turned the three UNPINNED adversarial boundaries (ephemeral in the out-of-tree 343-case Go battery) into
permanent committed guards: +20 `native_decide` theorems in `StrconvTests.lean`. Kernel-direct on
`decimalRatioToFloat`/`decimalToFloat`/`roundToSig` (localize a regression) + end-to-end `call` vs the cue
oracle. All expected values adjudicated against Go `strconv` AND cue v0.16.1 — **no kernel bug** (GREEN
first try). (1) float64 overflow half-even midpoint `(2^54−1)·2^970` ties-to-even ONTO inf, `−1` stays
maxfloat; (2) float32 overflow tie `(2^25−1)·2^103`→inf, `1e39`/`3.5e38`→`+Inf`, `-1e39`→`-Inf`;
(3) fixed-prec carry-growth `99.995`→"100.00", `0.9995`→"1.00", `999.5`→"1000", + `9.995`→"9.99" (nearest
double 9.9949… is BELOW 9.995, so NO carry — Go rounds the EXACT value). Docs: plan.md (✅ LANDED),
implementation-log. `check.sh` GREEN, committed on `main`.
**Next (ranked, unchanged):** **F1** (`math.Log1p`/`Expm1`, float64 via `Kue/Float.lean` + shortest-`'e'`
anchor, smallest F-follow-up) → **F3** (trig `Sin`/`Cos`/`Tan`/…) → **F5** (`text/template` float-in-data
render + `math.Float64bits`) → remaining LOWs: PA-ESC-2 (shared simple-escape table, `Parse.lean` DRY),
PA-SUB-4 (`net.IPv4()⊑net.IP()` subsumption), PA-TT-5 (template fuel-bound proof), PB-RELEASE-3
(`release.sh:43` CPU-cap bypass), PB-TESTORG-4 (BuiltinTests/TwoPassTests split).
Prior HEAD STDLIB-FLOAT-F2 below.

## Prior HEAD — STDLIB-FLOAT-F2 — the IEEE binary64/32 float kernel (LANDED 2026-07-12).
New leaf `Kue/Float.lean` (imports `Kue.Decimal`; built via `Kue.Builtin`). Finite floats modelled
EXACTLY as `BinFloat = (-1)^neg · mantissa · 2^binExp` — big-integer arithmetic, NO hardware `Float`.
Three kernels: `decimalToFloat` (correctly-rounded decimal→binary, round-half-to-even, overflow→err /
underflow→±0 / subnormal re-round), `shortestDigits` (Burger–Dybvig shortest-round-trip; even-inclusive
boundary, carry trailing-zero trim — the `1e23` even-boundary case), `exactDigits`+`roundToSig`
(fixed-prec rounds the EXACT finite decimal). `fmtE`/`fmtF`/`fmtG` = Go `strconv` byte-for-byte, verbs
`e E f F g G`, shortest-`'g'` switch `eprec = 6` (cue's linked Go, NOT the old `21`). Wired
`strconv.ParseFloat(s,{32,64})` (stores shortest-`'e'` = cue's `apd.SetFloat64` anchor → `ParseFloat("100")`
renders `1E+2`) + `strconv.FormatFloat(f,verb,prec,{32,64})` into `.strconv`. Deferred: verbs `b`/`x`/`X`,
bitSize∉{32,64}. Negative-zero renders `0` (divergence logged). Validated 343 kernel + 300 random CLI
cases byte-identical to Go/cue. Fixture `testdata/export/strconv_float`; theorems `parsefloat_*`/
`formatfloat_*` in `StrconvTests.lean`. Docs: plan.md (F2 ✅ + F1/F3/F5 UNBLOCKED), cue-spec-gaps
(STDLIB-FLOAT-F2), cue-divergences (-0), compat-assumptions §Numeric, implementation-log. `check.sh` GREEN.
**F2 UNBLOCKS F1/F3/F5 — all now schedulable.** Committed on `main`.
**Next (ranked):** the F2-unblocked float wirings are now the high-leverage frontier — **F1**
(`math.Log1p`/`Expm1`, float64 via `Kue/Float.lean` + shortest-`'e'` anchor, smallest), **F3** (trig
`Sin`/`Cos`/`Tan`/… in float64), **F5** (`text/template` T3 float-in-data render + `math.Float64bits`).
Then the remaining LOW audit findings: PA-ESC-2 (shared simple-escape table, `Parse.lean` DRY),
PA-SUB-4 (`net.IPv4()⊑net.IP()` subsumption, `Order.lean`), PA-TT-5 (template fuel-bound proof),
PB-RELEASE-3 (`release.sh:43` CPU-cap bypass), PB-TESTORG-4 (BuiltinTests/TwoPassTests split, under cap).
Rank: F1 first (unblocked, small, exercises the new kernel end-to-end); F3/F5 next; LOWs after.
Prior HEAD STRINGFORMAT-LEAF below.

## Prior HEAD — STRINGFORMAT-LEAF — NetAddr fixed-width + StringFormat leaf (PA-NET-1 + PA-SF-3 + PB-SF-3)
Two 2026-07-12 audit findings, one refactor, behavior-conserving. (1) `NetAddr.v6` retyped
`List UInt8 → Vector UInt8 16` (`Kue/Net.lean`): 16-byte width now a TYPE invariant, so every `netIs*`
classifier indexes `bs[i]` (literal <16, total) — all `bs.getD i 0` value-fallbacks gone. Smart ctor
`mkNetAddrV6?` is the single trust boundary refining `finalizeIPv6`'s exactly-16 list into the vector;
`parseNetAddr?` v6 arm `.bind`s it. `v4` carrier already tight (4 fields), untouched. (2)
`stringFormatValid` extracted from `Time.lean` into new leaf `Kue/StringFormat.lean` (imports `Time`+`Net`
as siblings); `Time.lean` now imports only `Value` — **`Time→Net` edge DELETED**; `Lattice`/`Order` swap
`import Kue.Time`→`import Kue.StringFormat`. New theorems `v6_width_by_construction`/`v6_embedded_width`/
`mkV6_{accepts_16,rejects_short,rejects_long}` in `NetTests`; +`#check @` anchor. All existing theorems
conserved. Docs: plan.md (PA-NET-1/PA-SF-3/PB-SF-3/PB-DOCGRAPH-2 ✅ + edge-list rewrite), architecture.md
§5 (5 stdlib leaves, `Time→Net` deleted), implementation-log. `check.sh` GREEN. Committed on `main`.
**Next (ranked): remaining LOW audit findings — (a) PA-ESC-2 shared simple-escape table
(`decode{String,Byte}Escape` DRY, `Parse.lean`); (b) PA-SUB-4 stringFormat subsumption precision
(`net.IPv4()⊑net.IP()` class hierarchy, `Order.lean`); (c) PA-TT-5 template fuel bound proof; (d)
PB-RELEASE-3 `release.sh:43` bypasses `./lake` CPU cap; (e) PB-TESTORG-4 BuiltinTests/TwoPassTests split
(both under cap, no urgent seam). OR the leverage float item F2 (IEEE float64 kernel — unblocks
`strconv.FormatFloat`, `text/template` T3, `Log1p`/`Expm1`, trig; F1/F3/F5 gate on it).** Rank: F2 is
highest-leverage but largest; among LOWs, PA-ESC-2 (real DRY, small) and PA-SUB-4 (precision) first.
Prior HEAD PB-TESTORG-1 below.

## Prior HEAD — PB-TESTORG-1 — split oversized `EvalTests.lean` under the 1800-line test-health cap
`EvalTests.lean` was 1792 lines (8 under cap, one slice from a hard gate failure). Split by THEME into
four sibling modules, verbatim move: `EvalTests.lean` (494 — refs/memo/structural-cycles/terminating-
disjuncts/embedding carriers), `EvalExprTests.lean` (581 — arithmetic/comparison/logical/unary/regex
eval, ref cycles, value aliases, default-disjunction resolve, F1 mark algebra, disj-meet sweep),
`EvalOpsTests.lean` (488 — float mul/div/add-sub, operator domain E#4, scalar op pins),
`EvalStructEqTests.lean` (283 — sibling merge, lazy meet, struct/list equality). 231 theorems
conserved exactly (65+62+76+28); all three new modules registered in `Kue/Tests.lean`; each carries a
`#check @` tripwire. `check.sh` GREEN (`test health ok`, full build). NO product-code change. Discharges
B-4; BuiltinTests(1669)/TwoPassTests(1542) deferred to PB-TESTORG-4 (under cap, no urgent seam).
Committed on `main`. Prior HEAD STDLIB-FLOAT-F4-DIV below.

## Prior HEAD — STDLIB-FLOAT-F4-DIV — closed the division half of F4
**STDLIB-FLOAT-F4-DIV — closed the division half of F4 (apd result-exponent
preservation for float `/`).** An exact-terminating float quotient now renders in cue's GDA ideal
form (`6e2 / 3 → 2.0e+2`, was `200.0`; `1e34/1 → 1e+34`) instead of the fully-expanded decimal;
VALUE was always correct, only FORM diverged. `apdDivide?` (`Kue/Decimal.lean`) + `removeNatFactor`;
`evalDecimalDivide?` tries the exact apd path first, falls to the unchanged 34-digit
`divideDecimalRational?` for non-terminating / >34-sig quotients. NO `DecimalValue` core change.
Rule (spec-silent DISPLAY → cue-compat, pinned via `cue export --out json`): for exact `±m·10^k`
(minimal, `d=digits(m)`), an integer value (`k≥0`) with adjusted exp `k+d−1 ≤ 32` gains one trailing
zero `(10m, k−1)` forcing `.0`/`X.0e+n`; else keep `(m,k)`; zero clamps ideal exp to `0`/`−1`.
Validated 3000+ random cases, zero mismatch. `EvalTests` div theorems → `formatValue` idiom; FORM pin
`float_div_apd_ideal_exponent` in `FloatTests`; wild fixture `float-apd-division-exponent/` (RED→GREEN).
Docs: plan.md (F4 ✅), cue-spec-gaps.md STDLIB-FLOAT-F4 (rule corrected + `/` landed), compat-assumptions.md.
Committed on `main`. **Next: F1–F5 residuals — F2 (IEEE float64 kernel) is the leverage item (unblocks
`strconv.FormatFloat`, `text/template` T3, `Log1p`/`Expm1`, trig), but gated per plan; F1/F3/F5 gate on F2.**
Prior HEAD DOCS-CLEANUP below.

## Prior HEAD — DOCS-CLEANUP — the docs now state a single goal
A correct, spec-conformant CUE implementation across the whole language + stdlib
surface (chakrit, 2026-07-12). CLAUDE.md § Project carries the north-star (spec-conformance is
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
ctor); `stringFormatValid` dispatches them (extracted to the `StringFormat.lean` leaf by
STRINGFORMAT-LEAF; was in `Time.lean`); meet unchanged
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
