# RX-2b — invalid/deferred regex bottoms at every regex site (landed 2026-06-19)

Supersedes `2026-06-18-session-save.md` as the live pointer. First fix-slice since audit #12.

## What landed

A concrete invalid (`a(`) or deferred (`(?i)a`) regex pattern now **bottoms** with the new
`BottomReason.invalidRegex pattern err` instead of silently swallowing to a non-match. The
soundness hole was at every regex site (`=~` → `false`, `!~` → `true`, the lattice meet
bottomed a VALID string, the pattern-label predicate silently failed to constrain). RE2/cue
ERROR on an invalid pattern — Kue now does too.

The already-defined-and-unused `regexParseError? : String → Option RegexParseError`
(`Regex.lean`) became the shared decision; each site guards `some err → .bottomWith
[.invalidRegex pattern err]` BEFORE matching:

- `Eval.evalRegexMatch` — concrete bottoms; ABSTRACT operand still defers (`.binary` residual).
- `Eval.evalRegexNotMatch` — delegates; `.bottomWith` flows through unchanged, so `!~` bottoms
  (NOT `true`).
- `Lattice.meetStringRegexPrim` — invalid bottoms before the prim match.
- `Order.subsumesWithFuel` `.stringRegex` arm — invalid constraint subsumes nothing.
- `Builtin.regexp.Match`.
- **5th consumer the "4-site" sweep missed:** the pattern-LABEL path
  (`labelMatchesPatternWith` wraps the meet in `!containsBottom`, swallowing the bottom). Fixed
  at the `Eval.applyEvaluatedStructN` chokepoint via a new `patternsRegexError?` scan; the
  closedness machinery (SC-1/SC-2) is untouched.

`Value.lean` gained `import Kue.Regex` to carry the typed `RegexParseError` in `BottomReason`
(Regex stays an import-less leaf; no cycle).

## Verify (all green)

`lake build` (100 jobs); `scripts/check-fixtures.sh` → `fixture pairs ok` (only 2 NEW fixtures;
everything else byte-identical — no valid-pattern regression); `shellcheck` clean. Axiom-clean
(`{propext, Classical.choice, Quot.sound}`, no `sorryAx`/`partial`). cert-manager
content-identical to cue (`jq -S`, exit 0, ~32s — valid-pattern apps unaffected). argocd
unchanged (its pre-existing Bug2-3 bottom).

Tests: 4 `regexParseError?` pins (RegexTests), 9 dispatch-site pins (LatticeTests), 2
(OrderTests), 1 (BuiltinTests) + 2 fixtures (`numeric/regex_invalid_patterns`,
`definitions/regex_invalid_pattern_label`).

## Two intentional cue divergences (recorded in `cue-divergences.md`)

1. **Field-less invalid label** — `{[=~"a("]: int}` (no field): cue tolerates → `{}` (lazy:
   errors only when a field is matched); Kue bottoms eagerly (RE2 says the literal is ill-formed
   regardless). With a field present, cue and Kue AGREE (both error).
2. **Deferred constructs** (`(?i)`, etc.) — cue/RE2 support them; Kue bottoms. This is the RX-2a
   not-yet-implemented feature surfaced honestly (stub-not-silent-wrong), NOT a Kue-correct
   divergence. RX-2a will implement it; only logged in the audit, not as a "Kue wins" entry.

## Next step → RX-1c (HIGH — prod9 unblock)

Submatch + `regexp.ReplaceAll` (`${n}` Expand grammar) + `Find*`/`FindSubmatch`; remove the
`unsupportedBuiltin` deferral arms. The Pike-VM already FILLS the capture array (Phase-A audit
dumped the slots — nested/non-participating/leftmost, all RE2-correct), so RX-1c just exposes
it. **Now lands correct-by-construction:** every new capture-dispatch arm parses the same
pattern and inherits RX-2b's invalid→bottom contract instead of re-introducing the swallow.
Unblocks honda-obs/lemonsure/ssw `defs/filters/regexp.cue` (the `regexp.ReplaceAll` EXPORT lever
— F-1 unblocked the import). Design ready: spec-conformance-audit "RX-1 design" + "Submatch".

Cadence note: RX-2b is the 1st fix since audit #12 → next two-phase audit (A code-quality, then
B architecture) is due after ~2 more slices per `slice-loop.md`.

## Standing context (durable, do not relearn)

- Autonomy grant in effect (decide/proceed; resolve forks by philosophy; commit/push on `main`,
  no branch). Correctness over performance.
- Orchestrator = thin re-spawner; one subagent per slice; audits every 2–3 slices; subagents
  commit at checkpoints.
- prod9 + cue cache READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on the main tree.
  `git commit -F /tmp/<unique>` (the bash filter mangles piped/heredoc input).
