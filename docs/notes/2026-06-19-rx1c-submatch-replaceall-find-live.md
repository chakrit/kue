# RX-1c landed — submatch / `ReplaceAll` / `Find*` live; the regex trilogy is COMPLETE

**START HERE.** Supersedes `2026-06-19-rx1b-nfa-pikevm-engine-live.md` as the live pointer.
RX-1c is the 3rd and final RX-1 slice — it exposes the Pike-VM's capture array through the
`regexp.*` substitution/find builtins. See `docs/spec/spec-conformance-audit.md` (RX-1a/b/c
DONE; "RX-1 design" is the as-built record) and the RX-1c implementation-log entry (tail of
`docs/reference/implementation-log.md`).

## What landed

**Engine layer (the Regex leaf, pure `String → … → Option`):** `findSubmatch`/`find`/
`findAll`/`findAllSubmatch` (leftmost RE2 group spans, rune-indexed) +
`replaceAll`/`replaceAllLiteral` (Go `Expand` template `$n`/`${n}`/`$$`; longest-name rule
disambiguates `$1suffix` (names group `1suffix`→empty) vs `${1}suffix` (group 1 + literal);
unknown/non-participating group → empty). `allMatches` iterates non-overlapping leftmost
matches; a **zero-width match ADVANCES one rune** (Go) so `x*` over `"abc"` cannot loop —
total, fuel = input length + 2.

- **Leftmost match START** is read off an explicit whole-match wrapper group (`bumpGroups`
  shifts every group index +1, `re` is wrapped in `group (some 1)`), because the program's
  own slots 0/1 are PINNED to offset 0 by the lazy unanchored prefix.

**Dispatch (`evalRegexpBuiltin`, Builtin.lean):** removed the `unsupportedBuiltin` arms for
the implemented forms. `Find*` family **bottoms on no-match** (cue v0.16.1 raises `no match`,
NOT Go's nil — oracle-confirmed). `ReplaceAll*` never bottoms on a valid pattern (no-match →
`src` unchanged). Invalid pattern → `.invalidRegex` (RX-2b); abstract arg → residual
`.builtinCall`. **KEPT `unsupportedBuiltin`:** `FindString*`/`FindAllString*`/`Split` (cue
v0.16.1 exposes NO such function — calling them is a non-function error there) and
`FindNamedSubmatch`/`FindAllNamedSubmatch` (need deferred named captures).

**Pre-existing RX-1b bug FIXED (newline crossing).** The unanchored-search prefix was
`.star false .any`, but RE2 `.` excludes `\n` — so `=~`/`Match`/`Find*`/`ReplaceAll` could not
match across a newline (`matchRegex "two" "one\ntwo"` was false; cue → true). Surfaced by the
prod9 multiline filter `([^\n]+)--two\n`. Fixed at the cause: a shared `unanchoredPrefix =
.star false (.cls [] true)` (any char incl `\n`) in both `matchRegex` and `findFrom`. The
body's own `.` is untouched.

## Tests (all green)

27 `native_decide` RegexTests (engine layer + 3 cross-newline regressions) + 19 BuiltinTests
(dispatch) + new fixture `builtins/regexp_submatch` (.cue/.expected + FixturePorts), Kue output
byte-identical to cue across all 14 fields incl. nested-list `FindAllSubmatch`. Every `expected`
oracle-checked vs cue v0.16.1. Axiom-clean (no `sorryAx`/`partial`).

## Verify (all green)

`lake build` (100 jobs) · `check-fixtures.sh` → `fixture pairs ok` (zero drift) · `shellcheck`
clean. prod9 (READ-ONLY): cert-manager content-identical to cue (`jq -S`, exit 0, ~32s); argocd
unchanged (still its pre-existing Bug2-3 `conflicting values` bottom, ~94s — NOT a regex error).

## prod9 lever (HONEST — partial unblock)

The `#Regexp` filter (`regexp.ReplaceAll`) now exports cue-exact — both the simple `${1}ly`
case and the multiline `${0}${1}--insert\n` case byte-match cue. BUT the `filters` PACKAGE as a
whole still does NOT export: its sibling `#Template` filter uses `text/template`'s
`template.Execute`, which is unimplemented (not even in the import allowlist). RX-1c unblocks
the regexp filter, NOT the full filters package. A `text/template` builtin slice would be the
next prod9 lever.

## NEXT STEP → two-phase audit DUE, then Bug2-3 / D#2

A two-phase audit is DUE at the 2–3-slice mark: RX-2b + RX-1c have landed since audit #12. Run
it per `docs/guides/slice-loop.md` (do NOT invoke `/ace-audit` — the procedure is written
there): (A) code-quality audit over the RX-2b/RX-1c batch, then (B) architecture/refactor
audit over the whole module graph.

**The audit MUST also re-check `cue-divergences.md`** as the prompt flagged. Finding from this
slice: the `(?i)` deferred-construct case (cue matches `"ABC" =~ "(?i)abc"`, Kue bottoms) is
**Kue-incomplete (RX-2a-adjacent), NOT a cue-bug** — and it is **correctly NOT recorded** in
`cue-divergences.md` (verified: the only regex entries there are the two RX-2b field-less
invalid-pattern divergences, both legitimate eval-strategy artifacts). No miscategorization
exists; the audit can confirm-and-move-on.

After the audit: **Bug2-3 / Gap-2b** (the last argocd export blocker — structural disjunction-arm
pruning, designed) and **D#2** (structural-cycle detection, designed, LARGE). RX-2a (in-class
`\D\W\S`) is the remaining regex gap (MED, after RX-1c since both touch the regex module).
