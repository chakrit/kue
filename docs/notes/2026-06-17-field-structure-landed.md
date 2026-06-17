# Breadcrumb — `Field` tuple → `structure` landed (consolidation 3e)

## What landed

`abbrev Field := String × FieldClass × Value` → `structure Field where label : String;
fieldClass : FieldClass; value : Value`. Type-system-first tightening (named projections,
no `.2.1` misindexing). **Purely representational, zero behavior change.**

Key design point — the **mutual block is forced**, not a choice:
- `Value`'s six struct-bearing constructors (`struct`/`structTail`/`structPattern`/
  `structPatterns`/`embeddedList`/`structComp`) carry the field list, and the codebase
  already types dozens of signatures + `Frame := Nat × List Field` as `List Field`.
- While `Field` was an `abbrev`, `List Field` was defeq to `List (String × FieldClass ×
  Value)`, so the tuple-carrying constructors and the `List Field` signatures agreed.
- Once `Field` is a `structure`, that defeq breaks. So `Field` must be visible to `Value`'s
  definition → `mutual ... inductive Value ... structure Field ... end`, and the
  constructors switch to `List Field`.

Derived instances preserved exactly: `deriving instance Repr, BEq for Value, Field` after
the mutual block (the tuple gave `Value` only `Repr, BEq`; matched, NOT widened — no
`Inhabited`/`DecidableEq` added). `Value`'s `==`/`Repr` are byte-identical: **every
`native_decide`/`rfl` theorem and every fixture passed UNCHANGED, with NO `rfl`→
`native_decide` switch needed.**

## Migration (build as ground truth — the grep/wc filter is flaky)

~70 sites: field tuple literals `(l, c, v)` → `⟨l, c, v⟩`; `Module`'s positional reads
`f.fst`/`f.snd.snd` → `f.label`/`f.value`; two local `List (String × FieldClass × Value)`
sigs in `Lattice` → `List Field`. A balanced-paren Python rewriter (`/tmp/fieldconv.py`,
not committed) handled the ~60 multi-line / `.field _ _ _`-classed test literals; engine
sites done by hand. Non-Field tuples left alone: `Mark × Value` disjunction alternatives,
`Nat × List Field` frames, `Value × Value` pattern pairs, manifest `String × Value` output.

Files touched: `Value` (the structure), `Eval`/`Parse`/`Resolve`/`Normalize`/`Lattice`/
`Module` (engine), `Examples` + `Tests` + 14 `Tests/*` (literals). No `.expected` changed.

## Verify gate (all green)

- `lake build` → 86 jobs, success.
- `scripts/check-fixtures.sh` → `fixture pairs ok`, unchanged.
- `shellcheck scripts/check-fixtures.sh` → clean.

## Next step

**AUDIT CADENCE.** This is the 1st slice since the last light audit — audit due in ~2 more
slices (orchestrator: count this one). Don't audit yet; keep forward motion.

With 3e done, the **consolidation/cleanup batch is essentially complete** — only the
deferred oversized-module splits (`FixturePorts` 2293 / etc.) and LOW items remain.

Next SUBSTANTIVE item for real-file reach:

1. **Package-dir merge (item 5)** — `kue export ./apps` merges all `package apps` files in
   a dir before manifesting (multi-file packages like `argocd.cue`). **Larger loader slice;
   needs a design pass.** Prefer this over the low-value module-split churn.
2. Largest loader slice: **registry/module-cache import fetch (item 6)**.

## Standing facts (carry forward)

- Alpha cadence: ~1 datestamped alpha/day via `scripts/release.sh`, **NO CI**. Latest
  `v0.1.0-alpha.20260617.3`. Do NOT touch `scripts/release.sh`, `packaging/`, or the tap.
- External repos (go mod cache, prod9 apps) are **read-only** oracles.
