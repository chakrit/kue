# RESUME HERE — B2.2/CP3-pre LANDED (test-only structN pre-migration); CP3-flip NEXT (2026-06-19)

Supersedes `2026-06-19-b2-3-b2-4-consumers-meet-merge-landed.md` and the Phase-B audit #5
pointer (`24da14d`). Standing grant in effect (autonomy / Lean-into-Lean-4 / commit-push
freely / specs as restore point). Full record: `docs/reference/implementation-log.md`
("B2.2/CP3-pre" entry); plan: `docs/spec/plan.md` (B2 entry — CP3-pre marked DONE inside the
B2.2 block, above the de-risked execution plan).

## What landed — 5 commits on `main` (pushed: see below)

`b79af85` Order.subsumes merge + OrderTests · `e44bb44` StructTests · `b55a5c8` FixturePorts
pure-op ports · `8949c45` Manifest/Yaml/List/Builtin · `8923b51` mergeStructN pins.

- **`Order.subsumes`** eight struct arms → ONE `.structN, .structN` arm
  (`structNSubsumesWithFuel`), legacy-exact. `subsumes` has no production caller, so the
  structN-only arm changes no production result. OrderTests migrated in lockstep (it is the
  ONLY struct-subsumes-pin file).
- **~360 constructed-input test sites** migrated to `.structN`: OrderTests, StructTests,
  FixturePorts (43 producer-FREE ports only), Manifest/Yaml/List/Builtin. `ManifestValue.struct`
  (no openness bool) guarded — left untouched.
- **9 `mergeStructN` pins** in LatticeTests: field-order reversal (both orders), tail×tail
  both-sides extras, arm-7 dedup (oracle vs cue v0.16.1) + distinct-concat, `.bottom`
  cross-combos (B2.5 flips). All `native_decide`/`rfl` green ⟹ consumer arms validated
  byte-identical to legacy. ZERO fixture byte-drift at every commit.

## Next step — B2.2/CP3-FLIP (spawn with `isolation: worktree`)

The hard landing, ONE green commit (red mid-edit until every site is fixed → worktree).
Procedure (compiler-driven, NEVER a global sed — `ManifestValue.struct` collision):

1. **Flip producers** to emit `structN` via `mkStruct`: `Parse.parsedFieldsBaseValue`/
   `parsedFieldsValue` (`Parse.lean:~509-532`), `Runtime.mergeSourceValues` (`Runtime.lean:60`),
   the `Eval` eval/force/embedding/comprehension/`dynamicField` re-emit arms,
   `Module.bindImports` (`Module.lean:60/162`). (`.structComp` is NOT touched — that's B2b.)
2. **Delete** the 4 old ctors (`struct`/`structTail`/`structPattern`/`structPatterns`) + the 12
   old `meetCore`/meet arms (`Lattice.lean:~463-468,1067-1140`) + dead legacy match arms, then
   **rename `Value.structN → Value.struct`** (arity 4). The vanishing 2-arg ctor makes every
   stale literal a COMPILE ERROR — the compiler enumerates all remaining sites. Fix per error,
   module-by-module in dependency order (see plan's rename mechanics).
3. **Migrate the ~95 produced-output test sites** (`== .struct` LHS-of-resolver/eval) +
   the 85 FixturePorts PRODUCER ports (147 ctors) — also compile-error-driven once the arity
   flips. The mapping table + the `/tmp/migrate_structn.py`-style transformer (port-aware,
   `ManifestValue.struct`-guarded, recursive into nested fields) from CP3-pre is reusable; in
   the flip the second pass rewrites `.structN → .struct` on Value-side sites only.
4. **Pin `applyEvaluatedStructN`** (must-fix item 3): a pattern-struct eval
   (`{a: int, [=~"x"]: string}`) end-to-end fixture + oracle check, confirming byte-parity with
   the legacy `applyEvaluatedStructPattern(s)` output.
5. Gate: `lake build` green + `scripts/check-fixtures.sh` `fixture pairs ok` (manifest/format
   OUTPUT byte-identical; representation changed, rendering must not).

Then **B2.5** (drop `mergeStructN`'s `.bottom` cross-combo guards + 4 oracle fixtures — diffs
against the CP3-pre `.bottom` pins) and **B2b** (structComp collapse).

## Cadence — AUDIT DUE AT/AFTER THE FLIP

CP3-pre is 1 slice since the Phase-B audit #5 (`24da14d`). The flip is the natural audit
boundary: run the two-phase audit (`docs/guides/slice-loop.md`, NOT `/ace-audit`) right after
CP3-flip lands (it removes the old ctors/arms — the dead-code/DRY sweep is most valuable then),
or fold it before B2.5.
