# default-disj-in-interpolation

- **Source:** prod9/infra `apps/{lem,n8n,x9,typesense}.cue`, via `packs.#Basics`
  (`prodigy9.co/defs@v0.3.19`) `#registry: string | *"ghcr.io"` read into
  `"\(Self.#registry)-pull-secret"`. Surfaced 2026-06-28 as the RESIDUAL layer after the
  `self-hidden-in-list-embed` fix: with `#registry` made concrete the 4 apps export clean, so
  the remaining bottom is isolated to this construct alone.
- **CUE construct at fault:** a string interpolation reads a field whose value is a DEFAULT
  disjunction (`string | *"ghcr.io"`). At export kue keeps the interpolation incomplete
  (`incomplete value: "\(string | *"ghcr.io")\("-suffix")"`) instead of applying the `*`
  default and concretizing.
- **Spec basis (kue is WRONG, cue is right here):** CUE default-disjunction semantics — a
  disjunction with a marked default (`*d`) resolves to `d` when a concrete value is REQUIRED
  (export, interpolation operands are required-concrete). `cue export` → `{ "y":
  "ghcr.io-suffix" }`. No `cue-divergences.md` entry — cue agrees with the spec.
- **Status:** `.known-red` — captured, not yet fixed. This is the next slice's red seed; it is
  quarantined from the green gate until the default-concretization fix lands (then delete the
  marker).
