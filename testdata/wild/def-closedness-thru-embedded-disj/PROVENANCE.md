# def-closedness-thru-embedded-disj  (root A — SOUNDNESS)

- **Source:** isolated 2026-06-29 while fixing layer 4 (`disj-arm-list-embed-dropped`) — the L4
  fix surfaced it. Blocks L4 and the 4 prod9 apps (`#WebApp`/`#Mixin` shape). A scope diagnostic's
  initial characterization (`close()`/`{kind:string}` arms) was a mischaracterization corrected by
  direct kue-vs-cue testing; this is the accurate, minimal, assertable form.
- **CUE construct at fault:** a *definition* (closed) embedding a disjunction
  (`#M: {{a:int} | {kind:string}}`). Meeting it with an extra field must close each arm.
- **Direction: SOUNDNESS / OVER-ACCEPT** — kue ACCEPTS (ambiguous, both arms kept) what cue/spec
  REJECT (the `{a:int}` arm is closed → rejects `kind` → bottom → only the other arm survives →
  concrete `{kind:"k"}`). This is the worse failure direction (vs the L1–L4 over-rejections).
- **Root cause (kue WRONG):** definition closedness is not propagated into the embedded disjunction's
  arms — likely in the closedness machinery / disjunction normalization (`Kue/Lattice.lean`; the
  `embed-disj-arm-closedness` family per the impl-log is adjacent). Control: the non-definition form
  (`M: {{a:int}|{kind:string}}`) agrees with cue (both arms open, both survive) — isolating the bug
  to definition-closedness propagation, not the disjunction itself.
- **Spec basis:** a definition closes its value (CUE closedness); closedness distributes into embedded
  disjunction arms. `cue` v0.16.1 → `{"out":{"kind":"k"}}` and is correct (NOT a cue bug).
