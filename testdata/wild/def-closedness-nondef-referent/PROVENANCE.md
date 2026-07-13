# def-closedness-nondef-referent

- **Source:** DEF-BODY-CLOSEDNESS-UNIFY MILESTONE-VERDICT audit (2026-07-13).
- **Defect:** A definition whose body indirects (bare `.refId`, `.selector`, or `.index`)
  to a NON-definition struct leaks closedness. `#X: foo` / `#X: foo.bar` / `#X: list[0]`
  where the referent is a plain (non-def) struct — a use-site extra field is admitted.
  The DEF-CLOSEDNESS-REREF-DROP fix closed only the DEF-referent sub-case (`#X: #Y`,
  #Y a def), where the referent flatten-resolves to a closed def and `close` fires. A
  non-def referent yields `close` false, so the body inlines OPEN and the use-site extra
  leaks — a soundness over-acceptance.
- **Spec basis:** CUE closedness — the value of a definition is closed. Referencing a
  struct through a definition (`#X: foo`) produces a closed value; the definition-ness of
  #X, not the openness of `foo`, governs. cue closes both def- and non-def-referents;
  kue is internally inconsistent (def-referent closes, non-def-referent leaks).
- **cue:** v0.16.1 ⇒ `y.z: field not allowed`. kue ⇒ admits (`{foo:{a:1}, y:{a:1,z:9}}`).
- **Reach:** the residual generalizes across `#X: foo`, `#X: foo.bar`, `#X: list[0]`, and
  chains through non-def bindings (`#X: bar`, `bar: foo`, `foo: {a:1}`). All close under
  cue; all leak under kue. The def-referent forms (`#X: #Y`, `#X: foo` where `foo: #Y`,
  `#X: #Foo.bar`) close correctly.
- **Status:** QUARANTINED (`.known-red`). Filed as fix-slice DEF-CLOSEDNESS-NONDEF-REFERENT.
