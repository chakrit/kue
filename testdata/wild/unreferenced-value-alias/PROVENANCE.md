# unreferenced-value-alias

- **Source:** SCOPING-PROBE (2026-07-12).
- **Defect:** A value alias (`a: X=1`) never referenced is a CUE error (aliases must be
  used). kue silently accepts it. Missing load-time validation — the alias analog of the
  unused-import error kue already enforces.
- **Spec basis:** CUE — "It is illegal to have an unused alias." Unreferenced alias/let
  is a load error.
- **cue:** v0.16.1 ⇒ `unreferenced alias or let clause X`. kue ⇒ accepts (`{a:1,b:1}`).
- **Status:** QUARANTINED (`.known-red`). Filed as fix-slice UNREFERENCED-ALIAS
  (track alias/let use across a scope; error on any unreferenced binding).
