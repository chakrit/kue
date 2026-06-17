# List-embedding-in-struct eval landed — and the rule was NOT laziness

**Slice:** the `[...]`-in-struct / `meet(struct, list)` semantics — the #1 real-file
blocker behind `kue export apps/argocd.cue` returning `⊥`.

## The headline correction

The previous breadcrumb (and plan item 2) assumed `cue` *lazily tolerates* a struct/list
conflict when the value is only selected into. **Oracle measurement (`cue` v0.16.1) shows
that is wrong.** `cue` is *eager and structural*:

- A struct embedding a list IS the list **iff the struct has no output field** — output =
  `regular` or `required`. Hidden (`_x`), definition (`#x`), optional (`a?:`), `let` are
  all non-output.
- With any output field present → genuine struct/list conflict (`⊥`), eagerly.

Evidence (all `cue export`/`cue eval`):

| input                       | cue result        |
|-----------------------------|-------------------|
| `{[1,2,3]}`                 | `[1,2,3]`         |
| `{#a:1, [1,2]}`             | `[1,2]`           |
| `{#a:1, [...]}`             | `[]`              |
| `{a:1, [1,2]}`              | conflict (`⊥`)    |
| `{a?:int, [1,2]}`           | `[1,2]`           |
| `{a:1} & [1,2]`             | conflict (`⊥`)    |
| `v={#a:1,[10,20]}; v.#a, v[0]` | `1`, `10` (dual) |

The value is genuinely dual-natured: hidden selection AND list indexing both work on it.

## What landed

New `Value.embeddedList (items : List Value) (tail : Option Value) (decls : List Field)`
constructor — the list nature plus surviving non-output decls as one value
(type-system-first; no flagged struct). Pivot: new total `FieldClass.producesOutput`
(true only for `regular`/`required`).

- `Lattice.meetWithFuel`: arms (before the struct arms, so a left `embeddedList` keeps its
  decls) build it from `meet(non-output struct, list)`, merge two (decls meet struct-wise,
  lists via new `meetListPairWith` over `(items, optTail)`), and meet one vs a further
  struct/list. `meetCore` fuel-0 fallback bottoms it.
- `Manifest`: emits the concrete items (decls + open tail dropped — `{#a:1,[...]}`→`[]`).
- `Eval`: `selectEvaluatedField` reads decls; `selectEvaluatedIndex` indexes items.
- `containsBottom`: recurses into items/tail/decls so an element conflict surfaces
  (`{#a:1,[1]} & {#b:2,[9]}` → `x.0` conflict, export errors — matches `cue`).
- `Format`: `{decls…, [items…]}`.

Genuine `{a:1}&[1,2]` / `{a:1,[1,2]}` conflicts still `⊥` (oracle-matched).

## Tests

8 fixtures + FixturePorts entries; 9 `ListTests` `native_decide` theorems. Theorem count
**663**. Verify gate green: `lake build`, `scripts/check-fixtures.sh` ⇒ `fixture pairs ok`,
`shellcheck` clean.

## Next blocker — read-only check

`kue export apps/argocd.cue` STILL returns `⊥`, but **this slice is not the cause**:

- The direct `x: packs.#Argo & {#name:…}` (no `[...]` in the consuming struct) errors in
  *both* kue and `cue` (struct/list conflict). The consuming struct must carry its own
  `[...]` — as the real `configs: packs.#Argo & {[...], #name:…}` files do — for the
  embeddedList path to engage.
- With `[...]` present, `cue` proceeds and the next gate is the **`if Self.#x != _|_`
  presence-test comprehension guard** (plan item 2b). kue's guard does not fire, so
  `#components` def-meet bodies stay incomplete. Isolated repro:
  `#D: Self={#x?: string, out: {if Self.#x != _|_ {val: Self.#x}}}; y: #D & {#x: "hi"}`
  → `cue` `out.val: "hi"`; kue `out: {}` and `y: ⊥`.

**Point next at: the `if _x != _|_` presence-test guard eval (plan item 2b).** Then the
re-ranked list — item 3 collapse `intGe/Gt/Le/Lt → bound+kind`, item 4 base64-out-of-Json,
item 5 test/`testdata` reorg.

## Carry forward

- Alpha cadence: ~1 datestamped alpha/day via `scripts/release.sh` on chakrit's command.
  NO CI / no `.github`; do NOT touch `scripts/release.sh` / `packaging/` / release files.
- External repos (prod9 tree + cue cache) are READ-ONLY reference.
- Audit cadence: this is a deep-core slice (new Value constructor touching meet/manifest/
  eval/format/containsBottom). 5th slice since the Phase A/B audit — an `/ace-audit` pass
  over the recent batch (this slice the headline: embeddedList meet-arm ordering soundness,
  `producesOutput` correctness, `containsBottom`/manifest completeness) is due soon.
