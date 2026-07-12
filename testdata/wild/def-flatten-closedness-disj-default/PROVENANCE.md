# def-flatten-closedness-disj-default

- **Source:** DEF-FLATTEN-CLOSEDNESS-DISJ silent-leak guard (2026-07-13).
- **Role:** the strongest confirmation that the under-close is a real SOUNDNESS leak, not
  just a stricter error. With a default arm the disjunction resolves, so the pre-fix open
  arms produced a concrete WRONG export `{a:1,b:2,d:4}` — `d` admitted past a closed def.
- **Defect (pre-fix):** kue exported `{a:1,b:2,d:4}`; cue v0.16.1 rejects `d`.
- **Spec basis:** a closed definition's arm has a fixed field set; the undeclared `d` is
  `field not allowed` in every arm → bottom.
- **cue:** v0.16.1 ⇒ `y.d: field not allowed`. kue after fix ⇒ bottom.
