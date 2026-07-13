# def-closedness-disj-referent

- **Source:** DEF-CLOSEDNESS-NONDEF-REFERENT MILESTONE-VERDICT audit (2026-07-13),
  full cross-surface sweep of the `f0382cc..68c4879` batch.
- **Note:** the referent is HIDDEN (`_foo`) to isolate the CLOSEDNESS defect. A plain
  exported `foo` is an ambiguous top-level disjunction whose OWN "ambiguous value" export
  error masks `y`'s bottom (kue reports the source-first field's error; cue prioritizes the
  hard bottom) — an orthogonal export-error-precedence bug captured in
  `testdata/wild/export-error-bottom-precedence`.
- **Defect:** A definition whose body indirects to a DISJUNCTION of structs
  (`#X: _foo`, `_foo: {a:1} | {b:2}`) leaks closedness. The
  68c4879 `underDef` indirection-close path follows the `.refId` referent but does
  not distribute the enclosing definition's closedness across the referent's
  disjunction arms, so each arm inlines OPEN and a use-site extra (`& {z:9}`) is
  admitted in every arm. A soundness OVER-ACCEPTANCE — exactly the closedness-leak
  class the milestone claimed closed.
- **Spec basis:** CUE closedness — the value of a definition is closed. A definition
  bound to a disjunction closes per arm; a use-site meet adding a field not in an
  arm's allowed set rejects that arm. Both arms reject `z` (and the `b`-arm rejects
  `b`), so the disjunction is empty ⇒ bottom.
- **cue:** v0.16.1 ⇒ `y: 2 errors in empty disjunction` (`y.b`/`y.z` field not
  allowed). kue ⇒ leaks: `y: {a:1,z:9} | {b:2,z:9}`; export reports
  "ambiguous value: multiple non-default disjuncts remain" (both leaked arms live).
- **Contrast (correct):** a DIRECT disjunction def body (`#X: {a:1} | {b:2}`) closes
  per arm and bottoms correctly ("conflicting values (bottom)"). Only the
  indirection-to-disjunction leaks. The fixed kue must emit the same
  closed-disjunction-empty form — expectation pinned to "conflicting values
  (bottom)".
- **Status:** QUARANTINED (`.known-red`). Filed as fix-slice
  DEF-CLOSEDNESS-INDIRECT-DISJ-CONJ (face A).
