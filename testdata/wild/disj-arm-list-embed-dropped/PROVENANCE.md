# disj-arm-list-embed-dropped

- **Source:** all 4 prod9 apps (`lem`/`n8n`/`x9`/`typesense`), via `parts.#Mixin`
  (`listShape | structShape | error(…)`) embedded in `#UseKeel`/`#PodMounts`/`#AllowListenerSets`,
  composed with a list-carrier def (`#WebApp`/`#StatefulSet`) in `prodigy9.co/defs@v0.3.19`.
  Found 2026-06-29 — **layer 4, the single remaining structural ROOT** (R1). A scope-map diagnostic
  showed every other `_|_` site in the apps is *propagation* from this one root; fixing it should
  converge all 4 apps. L1–L4 are the same `#WebApp`-shape family.
- **CUE construct at fault:** a struct that embeds a disjunction with a list-shaped arm
  (`{ {[...]} | {kind: string} }`), where the host is a list-carrier.
- **Root cause (kue WRONG):** `Kue/Eval.lean:3926-3933`, the `.disj alternatives` branch of
  `meetEmbeddingsWithFuel`: `meet current (openStructValue arm)` for the `{[...]}` arm meets the
  host struct against the opened list arm as a top-level struct-vs-list KIND conflict
  (`Kue/Lattice.lean:519-520`, `.embeddedList _ _ _, _ => .bottom`) → `.bottom`; `normalizeDisj`
  then prunes the (wrongly) dead arm, so the list arm vanishes and the whole value bottoms.
- **Spec basis (kue over-rejects, cue right):** unification distributes over disjunction
  (`x & (a|b) = (x&a)|(x&b)`), and a disjunction is bottom only if ALL arms are bottom. `x & listShape`
  is satisfiable here (the value is a list carrier), so the arm must survive. An embedding host must
  be transparent to a list arm — not a top-level struct-vs-list kind conflict. `cue` v0.16.1 →
  `{"out":[{"x":"web"}]}` and is correct (NOT a cue bug).
