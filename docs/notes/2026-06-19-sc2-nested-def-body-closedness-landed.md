# SC-2 landed — nested def-body closedness via a closing field-walker twin

**START HERE.** Supersedes `2026-06-19-f2-self-module-major-version-strip-landed.md` as the
live pointer. SC-2 is the closedness cluster's LAST fix (after SC-1/1c/1d) — the cluster is now
drained to zero. The 1st fix-slice since the SC-2 design landed (Phase-B audit #2, commit
`556a1d8`); see `docs/spec/spec-conformance-audit.md` (SC-2 / SC-2a / SC-2b DONE) and the SC-2
implementation-log entry.

## What landed

A referenced closed def closed only its TOP struct; nested PLAIN-struct field values stayed
`regularOpen`, so `#A: {a: {b: int}} & {a: {b: 1, extra: 5}}` ADMITTED `extra` (spec + cue
REJECT — a def closes "anywhere within … recursively"). Fix = a CLOSING field-walker twin
`normalizeDefinitionFieldWithFuel` in `Normalize.lean`: identical to `normalizeFieldWithFuel`
except the regular/optional/required arm recurses the CLOSING walker
(`normalizeDefinitionValueWithFuel`), not the spine — so nested plain-struct field values close
recursively. The CLOSING walker's no-pattern `.struct`, `.structComp`, and pattern-bearing
`.struct` arms now map the twin over their fields. UNCHANGED arms = the trap defence:
`importBinding` SKIP (bound packages stay lazy → no cert-manager/argocd re-bottom),
`letBinding`/hidden `_x` SPINE (a def's hidden-field nested struct admits extras). Normalize-only;
no `Lattice`/`Eval` edit (meet enforces + preserves the closure, monotone).

SC-2a (cue+spec AGREE) and SC-2b (DIVERGES from cue) are ONE change — Kue stores closedness on
the value and meet is monotone (no shed-on-`&` code), so closing the nested value once preserves
it through instantiation. **SC-2b divergence:** `(#D & {}).r & {b}` — cue re-opens (admits `b`),
Kue rejects; recorded in `cue-divergences.md`. cue is internally inconsistent (the direct path
`#D.r & {b}` rejects in both).

## Soundness obligations (all oracle-checked vs cue v0.16.1)

1. Referenced closed def's nested field rejects extras, recursively at any depth (#1/#2/#3/#6). ✓
2. Plain (non-def) nested struct stays OPEN (#5) — never reaches the twin. ✓
3. Nested `...` stays OPEN (#4) — `defOpenViaTail` returned unchanged. ✓
4. Def's hidden-field nested struct stays OPEN (#8); import binding stays lazy (SKIP arm). ✓

## Verify (all green)

- `lake build` 96 jobs; `scripts/check-fixtures.sh` → `fixture pairs ok` (all existing fixtures
  byte-identical except the ONE flipped SC-2b fixture); `shellcheck` clean.
- 4 `native_decide` soundness pins + flipped SC-2b theorem + 5 `sc2a_*` fixtures + renamed
  `sc2b_instantiated_def_field_stays_closed`; updated `eval_meet_lazy_hidden_def` (nested
  def-body `out` now `.defClosed`).
- **Real-app (READ-ONLY, from `prod9/infra`):** cert-manager `kue export --out yaml` exit 0
  (~32s), content-identical to cue (field-order gap #3 only). argocd still bottoms on the
  pre-existing Bug2-3 (`conflicting values`, NOT a closedness bottom, ~91s) — no regression.

## Next step

Closedness cluster done. Per the re-ranked backlog (`spec-conformance-audit.md`):

1. **RX-1 (HIGH, LARGE — 3 slices, worktree).** Replace the regex engine with an RE2-equivalent
   AST→NFA→Pike-VM. Highest real-app-correctness lever (7 demonstrated silent mis-validations) +
   unblocks F-1's `ReplaceAll` (prod9 exports). Design ready: "RX-1 design (implementable)" in
   `spec-conformance-audit.md`. RX-1a (AST+parser) → RX-1b (NFA+VM+rewire) → RX-1c
   (submatch+`ReplaceAll`). Worktree recommended (RX-1b deletes a large block from `Value.lean`).
2. **Bug2-3 / Gap-2b (HIGH)** — the LAST argocd export blocker (structural disjunction-arm
   pruning, key on list-meet-to-bottom). Sequence with RX-1 by whichever worktree is freer.
3. **D#2 (HIGH-MED, LARGE)** — structural-cycle detection; needs a design spike first.

**Audit cadence:** SC-2 is the 1st fix since audit #11 (per the slice instruction). A two-phase
audit is DUE after 2-3 slices — fold it after RX-1a or the next contained fix.

## Standing rules

- prod9 + cue caches READ-ONLY (eval/probe only). NO `git checkout`/`restore`/`reset --hard`.
  No env mutation outside the project tree.
- Working agreement grant (autonomy, resolve forks by philosophy, commit/push freely on `main`,
  keep specs current) is in effect.
