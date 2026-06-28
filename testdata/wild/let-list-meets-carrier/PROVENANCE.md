# let-list-meets-carrier

- **Source:** prod9/infra `apps/{lem,n8n,x9,typesense}.cue` (all four), via `packs.#WebApp`
  meeting `parts.#UseKeel`/`#Mixin` (and `#PodMounts` for typesense) in `prodigy9.co/defs@v0.3.19`.
  Found 2026-06-29 — layer 3 of the eval-conformance front (the residual after L1/L2).
- **CUE construct at fault:** a list-embedding *carrier* (a struct with hidden `#`-decls plus a
  top-level list embed) met with a list-shaped value delivered through a `let` binding / reference.
- **Root cause (kue WRONG):** `Kue/Lattice.lean` — the struct-embeds-list collapse arms
  (`meetWithFuel` ~1247-1307) recognize a carrier only in its literal `.struct … none [] …` shape
  via `asListPair`. A `let`/reference-delivered operand doesn't arrive in that form, so the meet
  falls through to `meetCore` and bottoms at `Lattice.lean:519` (`.embeddedList _ _ _, _ => .bottom`).
- **Spec basis:** embedding is unification, so a struct that embeds a list *is* that list, and two
  compatible lists meet element-wise; a `let` is pure substitution and cannot change a value's meet
  behavior vs. inlining it. kue over-conflicts a valid, deployed config. `cue` v0.16.1 → `[1,2]` and
  is correct (NOT a cue bug; no `cue-divergences.md` entry).
- **Note:** the INLINE meet (`ctrl`) exports correctly (`[1,2]`) — kue keeps the carrier form
  internally but the manifester emits the list; only the `let`/reference delivery path bottoms.
