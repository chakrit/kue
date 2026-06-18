# RESUME HERE — B2.3 + B2.4 LANDED (consumers + single meet merge); B2.2 BLOCKED (2026-06-19)

Supersedes `2026-06-19-b2-1-structopenness-mkstruct-landed.md`. Standing grant in effect
(autonomy / Lean-into-Lean-4 / commit-push freely / specs as restore point). Full record:
`docs/reference/implementation-log.md` ("B2.3 + B2.4 — structN consumer arms + the single
meet merge" entry); the 5-slice B2 plan with the revised sequencing:
`docs/spec/plan.md` (B2 entry — B2.3/B2.4 DONE, B2.2 re-scoped + BLOCKED, B2.5 after).

## What landed — two commits on `main`

`b3881c6` (consumers + meet merge + `mkStruct` move) and `eff5627` (eval/force/module
consumer arms). Both byte-identical — **`structN` is still UNPRODUCED**, so every new arm is
dead and fixtures stay identical.

### Design-ordering correction (consume-before-produce) — do NOT re-litigate

The plan's listed B2.2→B2.3→B2.4 order is UNSAFE: producing `structN` before consumers
handle it makes catch-alls + the `meetCore` `.bottom` dead-arm mishandle live `structN` →
drift. Re-sequenced: **B2.3 (match sites) + B2.4 (single meet arm) FIRST** (dead, trivially
byte-identical), production (B2.2) LAST.

### Landed

- **`mkStruct`/`dedupPatterns`/`coherentTail` moved `Lattice` → `Value`** (so
  `Parse`/`Normalize`/`Resolve`, which import only `Kue.Value`, can construct `structN` at
  B2.2). Layering-correct; no Lattice dependency.
- **Consumer `.structN` arms** at every struct-family match site (`Lattice`, `Eval`,
  `Builtin`, `Runtime`, `Normalize`, `Resolve`, `Parse`, `Module`). Each reproduces the legacy
  form exactly. Highest-risk: `Normalize` def-normalizers (`defOpenViaTail` → VERBATIM like
  the legacy missing `structTail` arm; no-pattern → CLOSE; pattern → keep openness).
- **`mergeStructN`** — the ONE `.structN, .structN` `meetWithFuel` arm, reproducing all 12
  legacy arms by tail/pattern dispatch, preserving each arm's field-merge ORDER (incl.
  `struct×structTail` REVERSED `rf++lf`) + closedness, emitting `structN`. Legacy-missing
  `pattern×tail` cross-combinations kept `.bottom` (B2.5 flips). `.structN × listLike`
  embedding arms added (plain-struct-equiv only).

## ⚠️ B2.2 is BLOCKED — read before resuming

The production flip (make `Parse`/`Runtime`/`Eval`/`Module` PRODUCE `structN` via `mkStruct`)
is WRITTEN AND SEMANTICALLY VALIDATED but reverted from the tree: with it applied, EVERY
`testdata/cue` fixture produces correct output via direct `kue` runs (incl. `struct_embedding_*`
and all `modules/*` — after adding `structN` arms to `Module`'s `module.cue` field-extractors,
which ARE in the tree). It cannot land green: the flip changes the internal `Value`
representation (`struct`→`structN`), and ~17 test files / ~940 sites pin the OLD representation
(`== .struct […] true`, legacy ctors as inputs). `lake build` AND `scripts/check-fixtures.sh`
(harness builds `Kue.Tests.FixturePorts`) both fail. **B2.2 is inseparable from the test
migration.**

## Next step — combine B2.2 + CP3 + test migration as ONE slice

1. Flip construction → `structN` (sites: `Parse.parsedFieldsBaseValue`/`parsedFieldsValue`,
   `Runtime.mergeSourceValues`, the `Eval` eval/force/embedding/comprehension/`dynamicField`
   re-emit arms, `Module.bindImports` wrap). Each was `.struct fields true` /
   `.structTail fields tail` / etc. → `mkStruct fields <openness> <tail> <patterns>`.
2. Delete the 4 old ctors + 12 old meet arms + dead legacy match/construct arms; **rename
   `structN → struct`** → the new 4-arg `Value.struct fields openness tail patterns`.
3. The rename changes `Value.struct`'s arity (2→4): every legacy `.struct f bool` /
   `.structTail f t` / `.structPattern …` / `.structPatterns …` literal — impl AND ~940 test
   sites — rewrites to the 4-arg form. **Compile-error-driven** (the 2-arg ctor vanishes → not
   silent), but large. **Caveat:** `ManifestValue.struct` (different type, 1-arg
   `List (String × ManifestValue)`, same bare spelling) — migrate per-compile-error, NEVER a
   global sed. Split into a per-module / per-test-file sub-sequence for reviewable commits.
4. Gate: `LatticeTests` + struct fixtures byte-identical (representation changes, but
   manifest/format OUTPUT must not).

Then **B2.5** (behavioral cross-combination fix: drop `mergeStructN`'s `.bottom` guards +
4 new oracle fixtures) and **B2b** (structComp collapse). `structComp` is UNTOUCHED here.

### Cadence — AUDIT NOW DUE

This is **2 slices since the last audit** (B2.1 + this B2.3/B2.4). The two-phase audit
(`docs/guides/slice-loop.md`) was deferred at the test-org slice and is now overdue. Given
B2.2/CP3 is a large, risky representation+test migration, a sensible call is to run the
two-phase audit over the landed B2.1–B2.4 work BEFORE starting the B2.2/CP3 megaslice (catches
any consumer-arm fidelity bug while the diff is small), OR right after B2.5. Re-evaluate at
resume.
