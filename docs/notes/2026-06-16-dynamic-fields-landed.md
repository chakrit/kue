# Session 2026-06-16 — dynamic fields landed

Latest resume breadcrumb. Supersedes the "Next session" section of
[`2026-06-16-comprehensions-landed.md`](2026-06-16-comprehensions-landed.md).
Resuming **implementation** next session.

## What was done

- **Dynamic fields slice — DONE (`804ceff`).** `(expr): v` computed labels plus
  `"\(expr)"` string interpolation. The oracle case
  `for k, v in {a: 1, b: 2} {"\(k)": v}` => `{a: 1, b: 2}` evaluates correctly.
  Full record in [`../reference/implementation-log.md`](../reference/implementation-log.md)
  => "Completed Slice: Dynamic Fields". Key representation choices:
  - `Value.interpolation (parts : List Value)` — literal segments + holes, uniformly
    Values. Eval coerces each part to its CUE string rendering (int/float/bool/null/string)
    and concatenates; bottom holes propagate; non-renderable holes stay residual.
  - `Value.dynamicField label fieldClass value` — carried *inside* `structComp`'s
    `comprehensions` list so it resolves in the enclosing struct's own `(depth, index)`
    frame (same trick comprehensions use) and expands at eval once the label is a string
    prim. Same-label collisions meet through the existing `structComp` merge.
  - Parser: interpolation-aware string scanner splits on `\( … )`; `(expr): v` and
    interpolated quoted labels (`"\(k)": v`) parse to dynamic fields; plain quoted labels
    stay static. `ParsedField.dynamicField` routes through the `comprehensions` bucket.
  - Totality: Format/Resolve/Lattice/Manifest arms for both new constructors;
    `expandComprehensionWithFuel` made fuel-destructuring for structural recursion.
- Verify gate green: `lake build` (66 jobs), `scripts/check-fixtures.sh` =>
  `fixture pairs ok`, `shellcheck` clean. Tree clean, pushed.

## Next session — implementation focus

**General struct-embedding scope bug** (from `docs/spec/plan.md` => Later Slices, now
marked "Next"). This is the deferred bug surfaced during comprehensions and re-confirmed
during dynamic fields.

- A `{ … }` embedded directly in a struct currently resolves its references against the
  *embedded* struct's scope, not the *enclosing* one. Repro:
  `out: { base: 7, {copy: base} }` => Kue gives bottom `copy`; `cue` => `copy: 7`.
- Root cause: embeddings become `.conj [embedding, base]` in `parsedFieldsValue`
  (`Kue/Parse.lean`), and resolution (`Kue/Resolve.lean`) resolves each `.conj` member in
  the *current* scope — the embedded `{copy: base}` is itself a `.struct`, so `base` only
  sees the inner frame. The comprehension/dynamic-field path sidesteps this by carrying
  embeddings inside `structComp` (which pushes the enclosing `buildFrame fields` before
  resolving them). The general fix must make a *plain* embedded struct resolve its bodies
  against the enclosing frame too.
- Likely shape: in `parsedFieldsValue`, route embeddings through the same
  enclosing-frame mechanism `structComp` uses (carry them as embeddings inside a
  struct-with-embeddings node, resolved with `buildFrame fields :: scopes`), rather than a
  flat `.conj` that loses the outer frame. Decide whether to generalize `structComp` to
  hold arbitrary embeddings or add a dedicated node — resolve by philosophy (prefer the
  representation that makes the scope rule total and uniform). Start with a FAILING fixture
  `struct_embedding_scope.cue` checked against `cue` v0.16.1, e.g.
  `out: {base: 7, {copy: base}}` => `out: {base: 7, copy: 7}`.

### Also pending (later slices, unchanged)

- Expand pattern constraints beyond string-label representation; remaining alias positions
  in a syntax layer; arithmetic-cycle handling; remaining builtins; imports/modules.

## Verify gate (unchanged)

`lake build` => `scripts/check-fixtures.sh` => `shellcheck scripts/check-fixtures.sh`. The
fixture script prints only `fixture pairs ok` on full success.

## Process note (carried forward)

Working directory persists between Bash calls — use absolute paths. `cue` needs file
arguments, not stdin (`cue export --out cue file.cue`); `kue` reads stdin. New `Value`
constructors must get arms in every total `Value` match: `Lattice.meetCore`,
`Manifest.manifestWithFuel`, `Format`, `Resolve`, `Eval`, and a `FixturePorts` entry.
`set_option maxHeartbeats … in` does NOT lift the inner `whnf` cap `simp` hits on the
(now larger) `meetCore` match — prove via targeted `rw [meetWithFuel]` + per-arm reduction.
