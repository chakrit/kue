# self-hidden-in-list-embed

- **Source:** prod9/infra `apps/{lem,n8n,x9,typesense}.cue` (all four), via `defaults.#Basics`
  / `packs.#WebApp` in `prodigy9.co/defs@v0.3.19`. Found 2026-06-28 while proving the ghcr
  fetch end-to-end — the apps export `bottom` in kue, clean in cue.
- **CUE construct at fault:** a definition that embeds another definition by reference
  (`#Base: {#Meta, …}`) and has a `Self`-aliased **list embedding** whose item reads a hidden
  field contributed by the embed (`name: Self.#name`). kue resolves that read to `_|_` (the
  embedded-`Self` two-pass is skipped for list-embedded reads — `Kue/Eval.lean` foldValueWithDepth
  descends `.embeddedList` items at the wrong frame depth), then the manifester over-enforces the
  `_|_` in the non-output definition into an export error.
- **Spec basis (kue is WRONG, cue is right here):** embedding is unification, so hidden fields
  are in scope for same-struct references however contributed → `Self.#name` must be `string`,
  not `_|_`. And definitions are non-output; a non-concrete value in an *unreferenced* definition
  must not fail export. `cue export` → `{ "z": 1 }`. No `cue-divergences.md` entry — cue agrees
  with the spec on this case.
