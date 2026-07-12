# def-closedness-reref-drop

- **Source:** Phase A MILESTONE-CONFIRMATION audit (2026-07-13, 3rd attempt, post-`3e8c7c8`) — the
  THIRD def-body entry-path residual of the nested-conj-closedness class the batch was closing.
- **Defect:** `#Y: ({b:2} & {d:4})` + `#X: #Y` + `y: #X & {z:9}`. `#Y`'s closedness is
  FLATTEN-DERIVED (the nested `.conj` of struct literals is closed at `#Y`'s flatten). RE-REFERENCING
  `#Y` through a def body that is a bare `.refId` (`#X: #Y`) drops that derived closedness, so the
  undeclared `z` leaks. kue export ⇒ `{y:{b:2,d:4,z:9}}` (exit 0); cue v0.16.1 ⇒
  `y.z: field not allowed`. Also leaks the split-literal form `#Y: {b:2} & {d:4}`.
- **Root cause (pinned):** `#X`'s body is `.refId #Y`, matched by `flattenConjDefRef`'s
  `defBodyConjuncts` `| _ => none` → `[constraint]` (unexpanded). `#X` then resolves via plain
  ref-eval to `#Y`'s materialized VALUE, which carries no flatten-derived closedness — the close ran
  only at `#Y`'s OWN flatten (`.conj`-body arm / own-literal union), never on the re-referenced form.
  `normalizeDefBodyConjunct` / `closeDefLiteralUnion` are reached only for `.conj`/`.disj` def-body
  top constructors; a `.refId` body is a third entry that bypasses them.
- **Spec basis:** closedness is a property of the definition; `#X: #Y` inherits `#Y`'s closed field
  set, so a use-site field outside it is `field not allowed` → bottom.
- **cue:** v0.16.1 ⇒ `y.z: field not allowed`. Expected (post-fix): bottom.
- **Controls that already close (regression guards):** the DIRECT forms `#Y & {z:9}` (both
  nested-conj and split-literal reject); and the re-ref of a SINGLE-struct-literal def
  `#Y: {b:2,d:4}` + `#X: #Y` (closedness intrinsic to the struct, correctly rejects).
