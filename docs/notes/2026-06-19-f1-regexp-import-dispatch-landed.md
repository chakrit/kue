# F-1 landed — `regexp` builtin import resolves + `regexp.Match` dispatch wired

Supersedes `2026-06-19-d1a-bottom-guard-propagates-landed.md` as the live pointer. Third
spec-first fix-slice from the consolidated backlog in
`docs/spec/spec-conformance-audit.md` (HIGH #3).

## What landed

Real prod9 apps `import "regexp"`; Kue rejected it (`unresolved import: regexp`) because
`"regexp"` was missing from `builtinImportPaths` — even though a regex engine already backs
`=~`. F-1 adds the allowlist entry + the call-form dispatch; it does NOT touch the engine.

1. `Module.lean` — `"regexp"` added to `builtinImportPaths`, so the loader leaves it to the
   call-form dispatch (like `strings`/`list`/`math`) and the bare `regexp` ref stays
   unresolved-as-package, ready for `regexp.Fn(...)` to parse to `.builtinCall "regexp.Fn"`.
2. `Builtin.lean` — new `evalRegexpBuiltin`, wired into `evalBuiltinCall`'s prefix dispatch.
   `regexp.Match(pattern, string) -> bool` calls `stringRegexMatches pattern s` — the SAME
   engine entrypoint `=~` (`evalRegexMatch`) uses, so the two agree by construction.
3. `Value.lean` — new `BottomReason.unsupportedBuiltin (name)` for the deferred forms.

## Match semantics — UNANCHORED (confirmed vs cue v0.16.1)

`regexp.Match` matches if the pattern occurs ANYWHERE in the string
(`stringRegexMatches` → `regexMatchAnywhereWithFuel` unless `^`-anchored), identical to Go's
`regexp.MatchString` and CUE's `=~`. Cross-check, all byte-identical to `cue`:

- `regexp.Match("^x", "xyz")` → true   (anchored start)
- `regexp.Match("y", "xyz")` → true    (mid-string → UNANCHORED)
- `regexp.Match("b", "abc")` → true    (mid-string → UNANCHORED)
- `regexp.Match("q", "xyz")` → false   (no match)
- `regexp.Match("z$", "xyz")` → true ; `regexp.Match("[0-9]", "a1b")` → true

## Deferred (RX-1) — NOT a silent wrong answer

The engine is a boolean matcher only (no submatch, no substitution). So `ReplaceAll`,
`ReplaceAllLiteral`, `Find`/`FindSubmatch`/`FindAll*` and every capture/substitution form are
DEFERRED: a CONCRETE call → `.bottomWith [.unsupportedBuiltin name]` (clear unsupported
signal); an ABSTRACT-arg call stays an unresolved `.builtinCall` for a later pass. The reason
collapses to `.contradiction` in the manifest (`.bottomWith _` is reason-agnostic there), so it
exports as an error with no manifest behavior change.

⚠ **prod9 reality (honest):** the only `regexp.*` prod9 actually uses is `regexp.ReplaceAll`
with `${n}` backrefs (`honda-obs/lemonsure/ssw .../defs/filters/regexp.cue`). F-1 unblocks the
IMPORT but NOT those apps' exports — `ReplaceAll` needs RX-1's submatch-capable engine. Probe
proof: `kue export .../defs/filters/` no longer errors on `import "regexp"`; it now advances to
a DIFFERENT unimplemented builtin (`text/template`). So F-1 is a real but partial unblock.

⚠ **Inherits RX-1's engine limits.** `regexp.Match` shares the current non-RE2 engine:
grouped quantifiers, `\b`, lazy quantifiers, multi-group all mis-match, and an invalid pattern
is treated as a literal (no validity check → no error, where cue errors). RX-1 fixes both `=~`
and `regexp.*` together; F-1 deliberately did NOT attempt the engine rewrite.

## Verify (gate passed)

`lake build` green (96 jobs); `scripts/check-fixtures.sh` → `fixture pairs ok`; `shellcheck`
clean. cert-manager re-probed READ-ONLY: exports clean (~34s), no regression. Tests: 7
`native_decide` pins in `BuiltinTests` (anchored-start; unanchored ×2; no-match; shared-engine
dispatch; ReplaceAll-unsupported-not-silent; ReplaceAll-unresolved-on-abstract-arg) + fixture
`builtins/regexp_match` (six Match forms + `FixturePorts` port) + module fixture
`modules/regexp_import` (end-to-end loader: import resolves + dispatch runs).

## No cue-divergence

`regexp.Match` agrees with cue on every probed case; the deferrals are Kue limitations
(engine, RX-1), not cue bugs. Nothing for `cue-divergences.md`.

## Next step — TWO-PHASE AUDIT DUE

SC-1 + D#1a + F-1 = 3 spec-first fixes since audit #9. Run the two-phase audit per
`docs/guides/slice-loop.md` (do NOT invoke `/ace-audit`; the procedure is written there) BEFORE
the next feature slice, sequentially:

- **(A) code-quality audit** over the recent batch. Must scrutinize: SC-1's new
  `closingPatterns` field on `Value.struct` (threading through `mkStruct`/meet — correctness,
  the SC-1b intersection gap); D#1a's `Except`-threading through the comprehension cluster
  (totality, enumerated guard match, DRY between struct/list twins); F-1's `evalRegexpBuiltin`
  (deferred-form coverage, the `unsupportedBuiltin` signal, dispatch DRY vs the other package
  dispatchers' `unresolvedOrBottom` fallback).
- **(B) architecture/refactor/cleanup audit** over the module graph (boundaries, dead code,
  test/fixture organization).

Then the backlog: RX-1 (regex → RE2, LARGE — unblocks `regexp.ReplaceAll`/the prod9 filters
AND `=~`), D#2 (structural cycles, LARGE), Bug2-3/Gap-2b (argocd unblock), F-2 (self-module
`@vN` strip), SC-1b (intersection-aware closed allowed-set), SC-2 (closing-vs-instantiation,
DIVERGE from cue).

## Standing rules

- prod9 + cue caches READ-ONLY (eval/probe only). NO `git checkout`/`restore`/`reset --hard`.
  No env mutation outside the project tree.
