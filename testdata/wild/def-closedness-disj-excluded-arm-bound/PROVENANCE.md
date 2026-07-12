# def-closedness-disj-excluded-arm-bound

- **Source:** DISJ-CLOSEDNESS-EXCLUDED-ARM-LEAK (2026-07-13 Phase A audit finding, a residual of
  `f0ddb19` DEF-FLATTEN-CLOSEDNESS-DISJ-REF).
- **Defect:** `#X: {a:1} & ({z:9} | >5)` + `y: #X & {w:7}` — `isDistributableDisj`
  (`Kue/EvalBase.lean`) was ALL-OR-NOTHING per disjunction: a single non-whitelisted arm (the
  `.boundConstraint` `>5`) made the WHOLE disjunction non-distributable, so the def never closed
  its own literal around the surviving `{z:9}` struct arm and flattened OPEN — the undeclared `w`
  leaked (kue exported `{a,z,w}`).
- **Root cause (pinned):** the `isDistributableDisjArm` whitelist admitted only
  struct/structComp/refId/prim/nested-disj arms. A `.boundConstraint` arm DIES against the def's own
  non-empty struct literal (`{a:1} & >5` ⇒ struct-vs-number bottom) EXACTLY like a scalar, so it is
  distribute-safe (contributes a bottom combination that drops) — but it was excluded, over-broadly,
  alongside the genuinely-blocking `error(...)` arm.
- **Fix:** widen the whitelist's distribute-safe category to arms that provably bottom against a
  struct literal — `.boundConstraint`, `.kind`, and the list carriers (`.list`/`.listTail`/
  `.embeddedList`) — beside the existing `.prim`. Such a pick is not `isUnionableDefValue`, so the
  cross-product emits its combination as an OPEN `.conj [literal, pick]` that bottoms at eval,
  dropping the arm; the struct arms still close. `error(...)`/comprehension arms stay OUT (force-fold /
  can-produce-a-struct), so the disjunction stays raw when one is present — bug214b unchanged.
- **Spec basis:** a closed definition has a fixed field set per surviving disjunction arm; unifying an
  undeclared field is `field not allowed` → every arm bottoms → bottom.
- **cue:** v0.16.1 ⇒ `y.w: field not allowed`. kue after fix ⇒ bottom.
