# RESUME HERE — B2.2/CP3-flip LANDED (family-1 struct collapse COMPLETE); AUDIT then B2.5 NEXT (2026-06-19)

Supersedes `2026-06-19-b2-2-cp3-pre-landed.md`. Standing grant in effect (autonomy /
Lean-into-Lean-4 / commit-push freely / specs as restore point). Full record:
`docs/reference/implementation-log.md` ("B2.2/CP3-flip" entry); plan: `docs/spec/plan.md`
(B2.2 marked DONE; the CP3-flip sub-entry follows CP3-pre). Divergences:
`docs/reference/cue-divergences.md` (eval pattern-elision entry).

## What landed — done in a worktree, 3 commits (orchestrator fast-forwards `main`)

Worktree branch `worktree-agent-a73190051b5458ad4`, commits `ee7dfe5`..`3f5bbbe`:
`ee7dfe5` flip producers + delete 4 ctors · `7b3012e` rename structN→struct + migrate ~95
produced-output / ~85 FixturePorts producer literals + dedup divergence · `3f5bbbe`
applyEvaluatedStructN pattern pins + divergence record.

The family-1 struct collapse is **COMPLETE**: 5 ctors → 1. `Value.struct fields openness tail
patterns` is the only struct form left (plus `structComp` = B2b, untouched).

- **Producers** all build via `mkStruct` (open_/hasTail → openness: no-tail ⇒ `.regularOpen`,
  `...` ⇒ `.defOpenViaTail (some tail)`): `Parse.parsedFieldsBaseValue`/`parsedFieldsValue`,
  `Runtime.mergeSourceValues`, `Module.bindImports`, all `Eval` re-emit sites. `applyEvaluatedStructN`
  is now LIVE (pattern arm included).
- **4 ctors deleted**, `structComp` KEPT. Lattice's 12-arm meet matrix + 5 legacy merge helpers
  → single `mergeStructN` arm; all other modules' shadowed legacy arms removed.
- **Rename** `Value.structN → Value.struct` via `\bstructN\b` token replace (~495 sites);
  `ManifestValue.struct` (1-arg) untouched; helper names `mergeStructN`/`applyEvaluatedStructN`/
  `structNSubsumes`/`structNTailCoherent` kept (capital-S, not matched).
- **Tests**: ~95 produced-output literals + ~85 FixturePorts producer ports + nested forms across
  10 files migrated to 4-arg `.struct`. Must-fix item 3 pinned (2 EvalTests pattern-path pins,
  oracle vs cue v0.16.1).

**Gate met:** `lake build` green, `scripts/check-fixtures.sh` → `fixture pairs ok` ZERO
byte-drift, shellcheck clean.

**One authorized divergence (dedup):** `mkStruct`/`dedupPatterns` collapses repeated equal
`[pattern]: c` (legacy `structPatterns` accumulated per-meet, no dedup) → matches cue v0.16.1.
The 4 TwoPassTests embed-narrowing pins' expected updated from legacy triple-`[string]: string`
to the cue-correct single pattern (NOT smuggled back to buggy legacy). Diagnosed as
representation-correct, not byte-drift in the export observable (fixtures unchanged).

## Next step — TWO-PHASE AUDIT (DUE NOW), then B2.5

Cadence: this is 2 slices since Phase-B audit #5 (CP3-pre + CP3-flip) → **audit due**. Run the
two-phase audit per `docs/guides/slice-loop.md` (NOT `/ace-audit`): (A) code-quality over the
flip batch (the ctor-delete + arm-collapse is the natural dead-code/DRY/totality sweep moment),
then (B) architecture/refactor over the whole module graph (struct family is now one ctor — check
for residual structN-era naming, comment staleness, helper consolidation). Fold findings as
fix-slices.

Then:
- **B2.5** — drop `mergeStructN`'s `.bottom` cross-combo guards (the `| _, _, _, _ => .bottom`
  catch-all + the tail×pattern cases in `Lattice.lean`), add 4 oracle-checked fixtures, and flip
  the LatticeTests pins currently asserting `.bottom` (set by CP3-pre) to `unify`. The ONLY
  behavioral (non-byte-identical) slice in B2.
- **B2b** — collapse `structComp` into the unified struct (the separate pre-eval form).
