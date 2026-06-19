# SC-1d landed — parser preserves the `...` tail when a struct also has patterns

Supersedes `2026-06-19-f1-regexp-import-dispatch-landed.md` as the live pointer. The 1st
spec-first fix-slice since audit #10, and the contained-HIGH parser fix the re-ranked
backlog put FIRST (ahead of RX-1). See `docs/spec/spec-conformance-audit.md` (SC-1d DONE).

## What landed

`Parse.parsedFieldsValue` dropped the `...` tail at PARSE time whenever the struct ALSO had
pattern constraints — the `some tail` branch's `| _, _ => declared` arm returned the
`.regularOpen` + `none`-tail base value the moment patterns were present. Harmless until SC-1c
made a no-`...` pattern def CLOSE; then `#A: {x, [=~"^a"], ...}` parsed WITHOUT its `...`, closed
at normalize, and wrongly REJECTED extras the `...` should admit (an over-close — a wrong
rejection). Spec: `...` opens the struct for all regular fields regardless of patterns; tail and
patterns are orthogonal axes on the unified `Value.struct`.

**Fix** (`Parse.lean` `parsedFieldsValue`, one file): introduced a tail-aware `baseValue` —

    let baseValue :=
      match parts.tail with
      | some tail => mkStruct parts.fields .defOpenViaTail (some tail) parts.patterns
      | none => parsedFieldsBaseValue parts.fields parts.patterns

— and routed every `declared` arm through it (plain base, comprehension-only via
`structCompOpenness`, and the comprehension+pattern `.conj` base). `mkStruct` with `.defOpenViaTail`
enforces ILL-1: tail kept, patterns retained as value-constraints, `closingPatterns = []` (open ⇒
closes nothing). The whole trailing `match parts.tail` dispatch then collapsed to a bare `declared`
(redundant — `baseValue` already encodes the tail in all four pattern×comprehension combinations).

## Behavior (cue v0.16.1 agrees — `...` opens)

- pattern + `...`  → `& {extra: 5}` admits `extra` (OPEN), output keeps the `...`. **The fix.**
- pattern + no-`...` → `& {z: 9}` REJECTS `z` (`z: _|_`). **SC-1c closing intact** — not re-opened.
- pattern + `...`  → matching `abc: "no"` still value-constrained → bottom (`...` admits the LABEL,
  the pattern constrains the VALUE).

## Tests

4 `native_decide` pins in `ParseTests` (`parse_pattern_tail_stays_open`,
`parse_pattern_notail_closes`, `parse_pattern_tail_value_constrains`,
`parse_pattern_tail_node_is_open_via_tail` — the last inspects the parsed node:
`openness = .defOpenViaTail` ∧ `tail.isSome` ∧ `closingPatterns = []`) + 3 fixtures
(`definitions/sc1d_pattern_tail_stays_open`, `…_notail_closes`, `…_tail_value_constrains`) with
`FixturePorts` ports.

## Verify

`lake build` green (96 jobs); `scripts/check-fixtures.sh` → `fixture pairs ok`; `shellcheck` clean.
cert-manager re-probed READ-ONLY: exports clean (exit 0, ~32s), no regression (diff vs cue is the
known field-ORDER gap #3 only — same keys/values). argocd still bottoms on the PRE-EXISTING
Bug2-3/perf wall, NOT an SC-1d/SC-1c over-close. **No prod9 file combines a `[pattern]:` with `...`
in one struct**, so SC-1c had not over-closed a live `{patterns, ...}` shape — SC-1d is the
forward-looking fix for the regression SC-1c could cause, not a recovery of a live one. SC-1d is
purely additive to openness (preserves `...`) → can only make a struct MORE open, never more
closed; cannot regress the real apps.

## Next step

Backlog order (contained-HIGH before the large rewrites):

1. **F-2 (HIGH, CONTAINED)** — strip self-module `@vN` suffix in `readModuleInfo`
   (`Module.lean:221-236`). One-file; deps are stripped but the self-module is not (asymmetry),
   so in-module imports fail. Cheap.
2. **RX-1 (HIGH, LARGE — 3 slices, worktree)** — replace the regex engine with an RE2-equivalent
   AST→NFA→Pike-VM. Highest real-app-correctness lever; design ready in the audit
   ("RX-1 design (implementable)"). RX-1a (AST+parser) → RX-1b (NFA+VM+rewire) → RX-1c
   (submatch+`ReplaceAll`).

Then: Bug2-3/Gap-2b (argocd unblock), D#2 (structural cycles), SC-2 (closing-vs-instantiation,
DIVERGE from cue), then the MED tail.

## Standing rules

- prod9 + cue caches READ-ONLY (eval/probe only). NO `git checkout`/`restore`/`reset --hard`.
  No env mutation outside the project tree.
- Audit cadence: SC-1d is the 1st spec-first fix since audit #10. A two-phase audit is due after
  2–3 landed slices (`docs/guides/slice-loop.md`).
