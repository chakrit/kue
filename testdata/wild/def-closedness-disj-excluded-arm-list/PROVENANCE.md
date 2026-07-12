# def-closedness-disj-excluded-arm-list

- **Source:** DISJ-CLOSEDNESS-EXCLUDED-ARM-LEAK (2026-07-13 Phase A audit finding, a residual of
  `f0ddb19` DEF-FLATTEN-CLOSEDNESS-DISJ-REF). Sibling of `def-closedness-disj-excluded-arm-bound`.
- **Defect:** `#X: {a:1} & ({z:9} | [1,2])` + `y: #X & {w:7}` — the list-carrier arm (`[1,2]`) made
  the all-or-nothing `isDistributableDisj` return false, so the def flattened OPEN and leaked the
  undeclared `w` (kue exported `{a,z,w}`).
- **Root cause (pinned):** same as the -bound sibling — the `isDistributableDisjArm` whitelist
  excluded list carriers, though `{a:1} & [1,2]` ⇒ struct-vs-list bottom makes a list arm
  distribute-safe (its combination drops, the struct arm closes).
- **Fix:** the widened distribute-safe category includes `.list`/`.listTail`/`.embeddedList`; the list
  arm's combination emits an OPEN `.conj [literal, list]` that bottoms at eval.
- **Spec basis:** a closed definition rejects an undeclared field on every surviving arm → bottom.
- **cue:** v0.16.1 ⇒ `y.w: field not allowed`. kue after fix ⇒ bottom.
