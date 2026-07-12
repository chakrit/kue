# def-closedness-bare-disj-conj-arm

- **Source:** Phase A milestone-reconfirmation audit (2026-07-13, post-`345f08b`) — the RESIDUAL
  the `normalizeDefBodyConjunct` fix (DEF-CLOSEDNESS-NESTED-CONJ-ARM) did NOT reach.
- **Defect:** `#X: ({b:2} & {d:4}) | {c:3}` + `y: #X & {z:9}` — a definition whose body is a BARE
  `.disj` (the disjunction IS the whole body, not a conjunct of a `.conj` body) with a parenthesized
  nested-`.conj` arm. The `.conj` arm is not merged, so `disjArmClass (.conj _) = .blocking` still
  holds for it, the disjunction flattens OPEN, and the undeclared `z` leaks into the selected arm.
  kue export ⇒ `{y:{b:2,d:4,z:9}}` (exit 0); cue v0.16.1 ⇒ `y.z: field not allowed`.
- **Root cause (pinned):** `normalizeDefBodyConjunct` fires only inside the `| .conj rawCs =>` arm
  of `flattenConjDefRef` (`Kue/EvalBase.lean`), which merges a `.disj` conjunct's arms. A def body
  that is a BARE `.disj` never enters that arm (`Field.value field` is `.disj`, matched by
  `| _ => [constraint]`), so its nested-`.conj` arm is never merged. The `345f08b` disj-arm fixture
  (`def-closedness-nested-conj-disj-arm`) uses the WRAPPED form `{a:1} & ((…) | {c:3})`, which DOES
  enter the `.conj` arm — so it passes while the bare-`.disj` form leaks.
- **Spec basis:** a closed definition has a fixed field set per surviving disjunction arm regardless
  of `&`-grouping inside the arm; unifying an undeclared field is `field not allowed` → the arm
  bottoms → the disjunction is empty → bottom.
- **cue:** v0.16.1 ⇒ `y.z: field not allowed`. Expected (post-fix): bottom.
- **Controls that already close (regression guards):** bare-`.disj` with PLAIN struct arms
  (`#X: {b:2} | {c:3}`) rejects `z` correctly; the wrapped form (`#X: {a:1} & ((…)|{c:3})`) rejects
  correctly.
