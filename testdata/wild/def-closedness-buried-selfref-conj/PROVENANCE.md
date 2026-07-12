# def-closedness-buried-selfref-conj

- **Source:** Phase A milestone-reconfirmation audit (2026-07-13, post-`345f08b`) — a second
  RESIDUAL of the parenthesized-nested-`.conj`-in-a-closed-def closedness class.
- **Defect:** `#X: {a:1} & (#X & {b:2})` + `y: #X & {z:9}` — a closed recursive definition whose
  self-reference is BURIED inside a parenthesized nested `.conj` (`(#X & {b:2})`). The def resolves
  to the closed struct `{a:1,b:2}` (verified: `#X & {a:1,b:2}` succeeds), but a use-site `& {z:9}`
  leaks the undeclared `z`. kue export ⇒ `{y:{a:1,b:2,z:9}}` (exit 0); cue v0.16.1 ⇒
  `y.z: field not allowed`.
- **Root cause (pinned):** the nested `.conj` `(#X & {b:2})` is IMPURE (contains a self-ref), so
  `normalizeDefBodyConjunct` correctly does NOT splice it — but then the buried-self-ref guard in
  `flattenConjDefRef` (`Kue/EvalBase.lean`) returns the def body UNEXPANDED (`[constraint]`) to avoid
  unrolling the self-ref, and the own-literal-union close never runs, so the def's closedness (fields
  `{a,b}`) is dropped. The FLAT form `#X: {a:1} & #X & {b:2}` (no parens) closes correctly — the
  self-ref is a top-level conjunct handled by the `expanding`/close-over-literals path.
- **Spec basis:** a closed definition is closed to its declared field set (here `{a,b}`) regardless
  of `&`-grouping or where the self-reference sits; an undeclared field is `field not allowed` →
  bottom.
- **cue:** v0.16.1 ⇒ `y.z: field not allowed`. Expected (post-fix): bottom.
- **Control that already closes (regression guard):** the flat form `#X: {a:1} & #X & {b:2}` rejects
  `z` correctly.
