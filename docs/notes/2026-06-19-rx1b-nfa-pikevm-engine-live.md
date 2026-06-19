# RX-1b landed — Thompson NFA + Pike-VM, the new engine is LIVE

**START HERE.** Supersedes `2026-06-19-rx1a-regex-ast-parser-landed.md` as the live pointer.
RX-1b is the 2nd of three RX-1 slices (the regex-engine replacement) and the BEHAVIOR
CHANGE — the new RE2-conformant engine now drives `=~`/`regexp.Match`, and the old
backtracking matcher is deleted. See `docs/spec/spec-conformance-audit.md` (RX-1a + RX-1b
DONE; RX-1c open; "RX-1 design (implementable)" is the as-built record) and the RX-1b
implementation-log entry.

## What landed

All in the leaf module `Kue/Regex.lean` (still imports only `Char`/`String`):

- **`Inst`** — flat instruction program: `char`/`any`/`split`/`jmp`/`save`/`assert`/`accept`.
  `split`-arm ORDER = greediness (arm `a` first = prefer). `AssertKind` = `start`/`end`/
  `wordBoundary`/`notWordBoundary`. `NFA = { insts, start, slots }`.
- **`compile : Regex → NFA`** — Thompson, continuation-passing (`compileFrag prog re cont`).
  `{m,n}` desugared BEFORE compile by a total `desugar` pass (`expandRepeat`: copies +
  `star`/nested-opts), so the VM has no counters. `compileFrag`/`compileSeq`/`compileAlt` are
  a mutual block, total by `sizeOf` of the finite repeat-free AST. `save 0`/`save 1` bracket
  the whole match; `save 2i`/`save 2i+1` bracket group i.
- **`NFA.run : NFA → List Char → Option (Array (Option Nat))`** — TOTAL Pike-VM. Outer loop
  is structural recursion on the input `List Char`; the ε-closure (`addThread`) dedups by pc
  over the FIXED program (`visited`), fuel = `insts.size` (exact, never spuriously hit). No
  backtracking → linear in `input × insts.size`. Priority: first `accept` in a closure cuts
  lower-priority threads; a later-position match overrides (survivor was higher priority);
  leftmost-start from the lazy `.*?` prefix. Carries the capture array — RX-1c reads it.
- **`matchRegex : String → String → Bool`** — unanchored RE2 `Match`/`=~`. Prepends implicit
  lazy `.*?`. Invalid/deferred pattern → `false`. `regexParseError?` exposes the parse error.

**Rewired 4 dispatch sites** (audit said 3; `Order.subsumesWithFuel`'s `.stringRegex` arm was
the 4th): `Eval.evalRegexMatch`, `Order.subsumesWithFuel`, `Lattice.meetStringRegexPrim`,
`Builtin.regexp.Match` → all call `matchRegex` (each module now `import Kue.Regex`).

**Deleted the old engine** — `Value.lean` ~L771-1011 (`stringRegexMatches` et al.) + dropped
the unused `import Init.Data.String.Search` from `Value.lean`.

## Behavior change toward the spec (NOT byte-identical)

All 7 repros now match cue v0.16.1 (oracle-confirmed): `^(ab)+$ ~ "abab"`=T/`~ "aba"`=F;
`^([a-z0-9]+(-[a-z0-9]+)*)$ ~ "foo-bar-baz"`=T; `^(v[0-9]+)(\.[0-9]+)*$ ~ "v1.2.3"`=T;
`a(b|x)(c|y)d ~ "axyd"`=T; `\bdog\b ~ "cat dog"`=T/`~ "dogcat"`=F; `a+? ~ "aaa"`=T;
`(foo|bar)+ ~ "xfoobarx"`=T (unsound-fallback case now consistent). **NO existing fixture
flipped** — the old engine got the simple patterns right and the new engine reproduces all
of them; `check-fixtures.sh` shows zero drift (only the new `numeric/regex_re2_repros`
fixture added). Nothing for `cue-divergences.md` — RE2 is the spec and cue agrees on every
probe.

## Tests

`RegexTests.lean`: the 7 repros + every simple-pattern fixture as `matchRegex` bool pins;
greedy-vs-lazy priority + group submatch spans read off `run`'s capture array (proves slots
are live + correct for RX-1c). New fixture `numeric/regex_re2_repros` (`.cue`/`.expected` +
`FixturePorts` port).

## Verify (all green)

`lake build` (100 jobs) · `scripts/check-fixtures.sh` → `fixture pairs ok` · `shellcheck`
clean · `#print axioms` on `matchRegex`/`compile`/`run` = standard foundational axioms only
(no `sorryAx`). prod9 (READ-ONLY): cert-manager content-identical to cue (~32s); argocd
unchanged (still its pre-existing Bug2-3 bottom).

## NEXT STEP → RX-1c (submatch wiring)

Expose the Pike-VM's capture array through the builtins. Implement `regexp.ReplaceAll` (+ Go
`Expand` `${n}`/`$n` template grammar — NOT regex backrefs) and `Find*`/`FindSubmatch`/
`FindAll*`; remove the matching `unsupportedBuiltin` deferral arms in `Builtin.evalRegexpBuiltin`
as each lands. **This is the prod9 lever** — `honda-obs/lemonsure/ssw .../defs/filters/regexp.cue`
use `regexp.ReplaceAll`, so RX-1c is what makes those packages export. The capture array is
already computed by `run`; RX-1c is wiring + the template grammar, not a new engine.

Cadence: RX-1b is the 3rd fix-slice since Phase-B audit #2 (after the closedness cluster +
RX-1a). A two-phase audit is DUE at the 2–3-slice mark — run it after RX-1c (or now if the
orchestrator prefers) per `docs/guides/slice-loop.md`.
