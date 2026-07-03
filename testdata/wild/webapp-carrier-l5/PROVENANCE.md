# webapp-carrier-l5  (L5 — imported #WebApp carrier — GRADUATED, green)

- **Source:** bisected 2026-06-30 from the four still-bottoming prod9 app exports
  (lem/n8n/x9/typesense; see `.afk.log` run-2 and `docs/spec/plan.md` L5). The typesense
  `let ss = defs.#StatefulSet & { parts.#PodMounts; … }` binding bottoms; this is the
  hand-reduced local seed (originally repo-root scratch `repro-l5.cue`, moved here
  2026-07-02 so the red seed is committed, not untracked scratch).
- **Status: GRADUATED (2026-07-03).** Green under the fix below; `.known-red` removed. The
  bisect (see below) refuted the provisional "error-arm / embedded-disjunction" framing —
  the `error("nope")` arm and the whole `#Mixin` disjunction are RED HERRINGS. The minimal
  trigger has no disjunction and no error at all.
- **Bisect — minimal trigger:** a struct with a sibling FIELD-REFERENCE unified via `&`
  with a struct carrying an ELLIPSIS-ONLY embed:

  ```
  #Ctl: { name: "x", spec: name, ... }
  out: #Ctl & { {...} }
  ```

  kue over-rejected (`conflicting values (bottom)`); spec + cue v0.16.1 export
  `{"out": {"name": "x", "spec": "x"}}`. Dropping the sibling ref (`spec: "lit"`), the
  embed (`#Ctl & {}`), or using a NON-empty embed (`{extra: 1}`) each makes it green — so
  the trigger is specifically `<sibling-ref def> & <ellipsis-only-open embed>`.
- **Root cause:** `evaluatedStructOperand?` (`Kue/EvalBase.lean`) mapped a `.defOpenViaTail`
  struct (an explicit-`...`, i.e. OPEN, use operand) to closedness `false`. In the conj
  force-splice fold (`forceClosureWithConjunct`, the `.defOpenViaTail` def arm), that
  spuriously-closed operand closed the OPEN host to the operand's own (empty) label set via
  `applyConjClosedness`, so the host's sibling-referencing field (`spec`) evaluated to
  `bottomWith (fieldNotAllowed "spec")`. Fix: an open-tail operand contributes `true`
  (open) — `applyClosednessFrom` is a no-op when open, and a genuinely-closed sibling still
  restricts via its own `false`, so `#Closed & {...}` stays closed (closedness ANDs).
- **Direction:** OVER-REJECT — kue bottomed where cue exports.
- **Spec basis (adjudicated):** `error("nope")` → bottom; `A | ⊥` simplifies to `A`, so
  `#Mixin`'s disjunction reduces to the open struct `{kind:string,...}`; embedding an OPEN
  struct into `#Ctl` imposes no closedness, so `#Ctl`'s fields survive; `#name:"x"` resolves
  the `Self.#name` back-ref → `spec.foo:"x"`; `#name` is hidden from output. Result:
  `{"out": {"kind":"StatefulSet", "spec":{"foo":"x"}}}`. cue v0.16.1 agrees.
