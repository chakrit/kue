# def-flatten-closedness-disj-select

- **Source:** DEF-FLATTEN-CLOSEDNESS-DISJ both-direction guard (2026-07-13).
- **Role:** proves the closedness fix does not OVER-close — a field declared by one
  disjunction arm is still admitted, and the disjunction resolves to the surviving arm.
- **Defect (pre-fix):** kue kept both arms open, so `& {b:2}` was admitted by BOTH the
  `{a,b}` and `{a,c}` arms ⇒ "ambiguous value: multiple non-default disjuncts remain"
  instead of resolving. Closing the arms lets the `{a,c}` arm reject `b` and drop out.
- **cue:** v0.16.1 ⇒ `{y: {a:1, b:2}}`. kue after fix ⇒ same.
