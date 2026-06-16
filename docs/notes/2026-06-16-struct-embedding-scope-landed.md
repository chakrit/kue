# Session 2026-06-16 — struct-embedding scope landed

Latest resume breadcrumb. Supersedes the "Next session" section of
[`2026-06-16-dynamic-fields-landed.md`](2026-06-16-dynamic-fields-landed.md).
Resuming **implementation** next session.

## What was done

- **General struct-embedding scope slice — DONE (`6e11198`).** A `{ … }` embedded
  directly in a struct now resolves its body against the *enclosing* struct's lexical
  frame, not the embedded struct's. `out: { base: 7, {copy: base} }` => `copy: 7`
  (was bottom). Full record in
  [`../reference/implementation-log.md`](../reference/implementation-log.md) =>
  "Completed Slice: Struct-Embedding Scope". Key choices:
  - Plain embeddings now ride the `structComp` `comprehensions` bucket (same place
    comprehensions and dynamic fields live), so Resolve/Eval push the enclosing
    `buildFrame fields :: scopes` before touching them. The old flat
    `.conj (embeddings ++ [base])` in `parsedFieldsValue` was the bug — `.conj` members
    resolve in the *current* scope, and an embedded `.struct` pushes only its own frame.
  - The `structComp` eval arm splits the bucket: comprehensions/dynamic fields expand to
    fields (merged with statics); plain embeddings (`isEmbeddingValue` = not a
    comprehension/dynamic field) are evaluated in the enclosing env and `meet`-folded into
    the struct. Struct embedding => field merge (collisions meet); non-struct embedding
    (`{ x: 1, 5 }`) => bottom. All via the lattice; no `structComp` signature change.
  - Removed the now-dead `embeddings` field from `ParsedFieldParts` and the trailing
    `match parts.embeddings` in `parsedFieldsValue`.
- Verify gate green: `lake build` (66 jobs), `scripts/check-fixtures.sh` =>
  `fixture pairs ok`, `shellcheck` clean. Tree clean, pushed.

## Next session — implementation focus

**Add remaining builtin functions** (from `docs/spec/plan.md` => Later Slices, now
marked "Next"). Beyond the implemented `close`, `len`, `and`, `or`, `div`, `mod`,
`quo`, `rem`. Candidates, oracle-checked against `cue` v0.16.1 for exact semantics
before encoding:

- string helpers (`strings.ToUpper`, `strings.Contains`, `strings.Split`, …),
- list helpers (`list.Concat`, `list.FlattenN`, …),
- math/numeric builtins.

Mechanics: builtin calls already round-trip as semantic values when unresolved, so each
new builtin is (a) an arm in `evalBuiltinCall` (`Kue/Builtin.lean` — read it first to see
the dispatch shape and the existing arms), (b) totality arms wherever a builtin result
needs them, and (c) a fixture pair plus a hand-built FixturePort. Confirm `cue`'s output
spelling (e.g. does `strings.Split` keep empty trailing fields?) with the binary first;
`cue export --out cue file.cue` is the oracle, `kue` reads stdin.

Pick one small cohesive builtin family per slice (one commit). Don't try to land them all.

### Also pending (later slices, unchanged)

- Expand pattern constraints beyond string-label representation; remaining alias positions
  in a syntax layer; arithmetic-cycle handling; imports/modules.

## Verify gate (unchanged)

`lake build` => `scripts/check-fixtures.sh` => `shellcheck scripts/check-fixtures.sh`. The
fixture script prints only `fixture pairs ok` on full success.

## Process note (carried forward)

Working directory persists between Bash calls — use absolute paths. `cue` needs file
arguments, not stdin (`cue export --out cue file.cue`); `kue` reads stdin. New fixtures
need BOTH a `.cue`/`.expected` pair AND a `FixturePorts.lean` entry (hand-built Value AST
through `resolveAndEval`/`formatTopLevel`) — the check script diffs both the CLI path and
the Lean-port path, and flags any `.expected` lacking a port. New `Value` constructors
must get arms in every total `Value` match: `Lattice.meetCore`, `Manifest.manifestWithFuel`,
`Format`, `Resolve`, `Eval`, and a `FixturePorts` entry. `set_option maxHeartbeats … in`
does NOT lift the inner `whnf` cap `simp` hits on the larger `meetCore` match — prove via
targeted `rw [meetWithFuel]` + per-arm reduction.
