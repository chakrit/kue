# RX-1a landed — regex AST + parser (additive, byte-identical)

**START HERE.** Supersedes `2026-06-19-sc2-nested-def-body-closedness-landed.md` as the live
pointer. RX-1a is the 1st of three RX-1 slices (the regex-engine replacement) and the 2nd
fix-slice since Phase-B audit #2. See `docs/spec/spec-conformance-audit.md` (RX-1a DONE;
RX-1b/c open; "RX-1 design (implementable)" is the spec) and the RX-1a implementation-log
entry.

## What landed

New LEAF module `Kue/Regex.lean` (imports only `Char`/`String` — no `Value`/`Eval`):

- **`Regex` AST** (RE2 subset, illegal-states-unrepresentable): `empty` / `lit` / `cls`
  (ranges + `negated`) / `any` / `anchorStart` / `anchorEnd` / `wordBoundary (negated)` /
  `concat` / `alt` / `star` / `plus` / `opt` / `«repeat» (min) (max : Option Nat)` /
  `group (index : Option Nat)`. **Greediness = a `Bool` field on each quantifier** (not a
  lazy constructor). `repeat.max : Option Nat` (no sentinel for `{m,}`). `group.index` =
  `none` for `(?:…)`, `some i` for a capturing group (left-to-right from 1). Derives
  `Repr, BEq` only (Lean can't auto-derive `DecidableEq` through nested `List Regex`; pins
  use `==`/`Bool`).
- **`parseRegex : String → Except RegexParseError Regex`** — recursive-descent
  (`alt → concat → quantified → atom`, mutual through `group`), TOTAL via input-length fuel
  (standing parser exception); no `partial`, no `sorry`; `termination_by fuel` per mutual
  function. Class body + `{m,n}` digit-runs separately fuel-bounded.
- **Invalid → `.error`, NEVER a silent literal-fallback.** Typed: `.malformed`
  (unbalanced `(`/`)`, dangling `\`, nothing-to-repeat, bad `{m,n}` count), `.backreference`
  (`\1` — RE2 has no backrefs; distinct from `ReplaceAll`'s `${n}` template, an RX-1c
  concern), `.unsupportedRegex` for DEFERRED constructs (`(?i)` flags, `(?P<…>)` named
  captures, `\A`/`\z`/`\Q`, POSIX `[[:…:]]`, `\p{…}`, in-class `\D`/`\W`/`\S`).

## Additive / byte-identical

The new module is wired into the BUILD only (`Kue.lean` import + `Kue/Tests/RegexTests.lean`),
NOT into any dispatch site. The old `Value.lean` engine (`stringRegexMatches` et al.,
~L771-1012) stays live and in use. So nothing's behavior changes — `check-fixtures` is ZERO
byte-drift. RX-1b is the behavior change.

## Tests (`Kue/Tests/RegexTests.lean`, all `native_decide`, registered in `Tests.lean`)

The 7 audit repros pin the EXACT AST (not vacuous): `^(ab)+$`/`^(ab)*$` (quantifier binds
the GROUP), `^([a-z0-9]+(-[a-z0-9]+)*)$` (nested+multi group, idx 1/2),
`^(v[0-9]+)(\.[0-9]+)*$` (multi-group, `\.` literal), `a(b|x)(c|y)d` (two alt groups),
`\bdog\b` (`\b` anchor both ends, not literal `b`), `a+?` (lazy plus). Plus greedy/lazy
across `* ? `, `{m,n}` shapes, non-capturing-index, negated class + perl atoms + `.`,
invalid patterns (incl. `a{5,2}` → error), `\1` → `.backreference '1'`, 4 deferred →
`.unsupportedRegex`.

## CUE divergence noted

`a{5,2}` (m>n): RE2/cue reject (`invalid repeat count`). Kue's `parseRepeatSuffix`
distinguishes a well-formed-but-bad brace (`.invalid` → error) from a non-quantifier `{`
(`.notQuant` → literal), so it rejects too — not a literal fallback. (Agreement with cue,
not a Kue-correct divergence, so NOT added to `cue-divergences.md`.)

## Verify (all green)

`lake build` (96+ jobs, new module + theorems check) · `scripts/check-fixtures.sh` →
`fixture pairs ok` (zero drift) · `shellcheck` clean.

## NEXT STEP → RX-1b (the behavior change)

Thompson `compile : Regex → NFA` (flat `Array Inst`, RE2/Pike style: `char`/`any`/`split`/
`jmp`/`save`/`assert`/`accept`; split-arm ORDER encodes greediness) + total Pike-VM
`run : NFA → List Char → Option (Array (Option Nat))` (dedup threads by pc → linear, no
backtracking, structurally total — removes the old engine's fuel-out-as-non-match soundness
hole). Desugar bounded `{m,n}` to concat-of-opt at compile time (VM sees no counters). Then
REWIRE the 3 dispatch sites — `Eval.evalRegexMatch`, `Lattice.meetStringRegexPrim`,
`Builtin.regexp.Match` — to the VM and DELETE the old `Value.lean` block (~L771-1012).

**Gate for RX-1b** (NOT byte-identical — the old engine mis-validates): (1) the 7 repros now
MATCH cue (add as `=~` fixtures); (2) existing simple-pattern fixtures stay green
(`regex_match_expressions`, `regex_group_alternation_pattern`, `regex_bounded_repetition_pattern`,
`regex_label_pattern`, `regex_wildcard_pattern`, `regexp_match`, `modules/regexp_import`); (3)
cross-check semver/DNS-1123/docker-ref/k8s-name vs cue; (4) `native_decide` pins for
greedy-vs-lazy priority, `\b` at word edges, submatch spans. **Worktree recommended** (deletes
a large block from the hot `Value.lean` + adds a leaf). RX-1c (submatch + `ReplaceAll`/`Find*`)
follows.

Cadence: RX-1a is the 2nd fix-slice since audit #11 / Phase-B #2. A two-phase audit is due at
the 2–3-slice mark (after RX-1b or the next slice).
