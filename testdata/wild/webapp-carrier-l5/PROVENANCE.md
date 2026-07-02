# webapp-carrier-l5  (L5 — imported #WebApp carrier — QUARANTINED, .known-red)

- **Source:** bisected 2026-06-30 from the four still-bottoming prod9 app exports
  (lem/n8n/x9/typesense; see `.afk.log` run-2 and `docs/spec/plan.md` L5). The typesense
  `let ss = defs.#StatefulSet & { parts.#PodMounts; … }` binding bottoms; this is the
  hand-reduced local seed (originally repo-root scratch `repro-l5.cue`, moved here
  2026-07-02 so the red seed is committed, not untracked scratch).
- **Status: SEED, self-contained but PROVISIONAL.** No imports/registry needed — it runs
  standalone and reproduces the bottom. But prior module-free reductions of L5 flipped
  polarity, so treat the exact construct boundary as unconfirmed until the next L5 slice
  re-verifies this seed still tracks the real app failure. The `.expected` is likewise
  provisional: it pins `cue` v0.16.1's export (`{"out": {"kind": "StatefulSet", "spec":
  {"foo": "x"}}}`), consistent with plan.md's L5 analysis that the carrier should export;
  the spec adjudication is to be finalized when the fixing slice lands.
- **CUE construct at fault:** a `Self={…}` definition (`#Ctl`) with a hidden-from-output
  `#name` and a `Self.#name` back-reference, met with an embedded definition (`#Mixin`)
  whose body embeds a disjunction `{kind: string, ...} | error("nope")` (the second arm
  is an unresolved-reference call, so it bottoms and the first, open arm must survive).
- **Direction: OVER-REJECT** — kue bottoms ("conflicting values (bottom)", exit 1) where
  cue exports the concrete value (exit 0).
- **Spec basis (provisional):** the `error(...)` arm is erroneous → discarded from the
  disjunction; the surviving arm is open (`...`) and `#Mixin` itself is open (`...`), so
  embedding it must not reject `#Ctl`'s fields; `#name: "x"` resolves `Self.#name` →
  `spec.foo: "x"`. `cue` v0.16.1 agrees (exports, exit 0).
