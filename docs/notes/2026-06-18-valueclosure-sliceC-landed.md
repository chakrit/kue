# RESUME HERE — Value.closure slice C (closure-default-in-guard) landed (2026-06-18)

START-HERE pointer; supersedes `2026-06-18-valueclosure-sliceA-landed.md`. Tree clean, pushed to
`gh:main`. Slice C is the default-resolution-in-guard fix; D turned out already-green; **E is the
live next slice.**

## What just landed (slice C)

A comprehension/field guard over a marked-default disjunction (`bool | *false`) now resolves the
default and fires the guard, cue-exact. Orthogonal to closures — reproduced with no def at all
(`x: bool | *false; if !x {…}`). 8 `native_decide` pins + 1 committed fixture; every existing
fixture byte-unchanged (86 jobs, `fixture pairs ok`, shellcheck clean).

### Root cause (traced, read-only `/tmp` repros, cue v0.16.1 oracle)

TWO coupled gaps about disjunction defaults in a concrete context:

1. **Operations did not distribute over disjunctions.** `evalBoolNot`/`evalAdd`/… fell to their
   `_ => .unary…`/`.binary…` fallback on a `.disj` operand, leaving `!x` as `.unary .boolNot
   (.disj …)`. CUE distributes: `op(a | *b)` = `op(a) | *op(b)`, marks preserved. So
   `!(bool|*false)` → `bool|*true`, `(int|*1)+1` → `int+1|*2`. kue left them stuck → incomplete.
   General (also hit top-level `z: !x`, `y: x+1`), not guard-specific.
2. **Guard test did not collapse a defaulted-disjunction condition.** `expandClausesWithFuel`
   compared the condition to `.prim (.bool true)` directly; a `.disj` never matched.

### Fix (reused existing default machinery)

- **`Lattice.lean`:** moved `liveAlternatives`/`defaultAlternatives` out of `Manifest` into
  `Lattice` (the leaf with `flattenAlternatives`/`containsBottom`), refactored `normalizeDisj`
  onto `liveAlternatives`, added **`resolveDisjDefault? : List (Mark × Value) → Option Value`**
  (unique marked default wins; else unique regular; else `none`). `Manifest`'s `.disj` arm now
  calls it — one shared "concrete-context collapse" definition.
- **`Eval.lean`:** `distributeUnary`/`distributeBinary` (after `evalUnary`/`evalBinary`) map the op
  across `.disj` alternatives preserving marks (`combineMark` for binary cross-product), normalize
  via `normalizeEvaluatedDisj`. The `.unary` + general `.binary` eval arms call these. Guard:
  `expandClausesWithFuel` runs a `.disj` condition through `resolveDisjDefault?` before the bool
  test; non-`.disj` passes through, non-default disjunction returns `none` → guard stays unsatisfied.

### Tests

8 pins in `EvalTests`: `resolve_default_disj_{picks_marked_default,non_default_stays_unresolved,
multiple_defaults_stays_unresolved}`; `distribute_{not,add}_over_default_disj`;
`eval_comprehension_guard_{negated_default_disj_admits,direct_default_disj_admits,
non_default_disj_drops}` (last = the over-resolution guard: NON-default disjunction in a guard
STAYS unsatisfied). Committed `testdata/cue/comprehensions/default_in_guard.{cue,expected}` +
`FixturePorts` entry; JSON export byte-identical to cue.

## REAL-APP VERDICT (the headline — read-only prod9, cue v0.16.1)

- **C cue-exact on the real `#ClusterIssuer` default-in-guard shape:** `#staging: bool | *false`
  with `if Self.#staging`/`if !Self.#staging` inside a `Self={…}` closure now resolves byte-exact
  (`out` staging-branch, `out2` prod-branch). Was `bottom` pre-C. C is a confirmed real blocker.
- **cert-manager export still `bottom` (~10s), but the error MOVED PAST C and PAST D.** Probing
  downstream blockers in isolation:
  - **D (`closure-presence-test-selfref`) ALSO already passes.** `if Self.#ns != _|_` (presence
    over self-ref) AND `len(Self.#labels) > 0` are both cue-exact post-A/C. **No D slice needed**
    (re-opens only if the real chain surfaces a D-specific failure).
  - **E (`closure-embed-chain`) is the LIVE next blocker.** 2-level repro `#Inner: Self={#name:
    string, iname: Self.#name}; #Outer: Self={ #Inner & {#name: Self.#oname}, #oname: string,
    oname: Self.#oname }; out: #Outer & {#oname:"z"}` → kue `bottom`, cue `{iname:"z", oname:"z"}`.
    The inner embedded closure's `Self.#name` → `_|_` when the outer force re-forces the nested
    embedded closure. Real `#ClusterIssuer → parts.#Metadata → attr.#Metadata` is 3-level.

## NEXT SLICE: E `closure-embed-chain` (correctness)

Recursion through a NESTED embedded closure + `Self=` alias. Single-level embed (slice A) works;
2-level does not. Likely site: `meetEmbeddingsWithFuel`/`forceClosureWithConjunct` in `Eval.lean`
— when the outer closure force re-forces an inner embedded closure, the inner `Self.#name` self-ref
must resolve against the inner def's OWN (spliced) frame, not collapse to `_|_`. Rebuild repro in
`/tmp/pf_chain` (gone on reboot): see the 2-level shape above. After E, re-probe cert-manager; if it
exports, frontier moves to **B `closure-perf`** (~10s wall).

## Standing context (durable, do not relearn)

- **prod9 real-app checkout:** `/Users/chakrit/Documents/prod9` (NOT `~/prod9`). Module root
  `infra/` (`infra/cue.mod`); apps under `infra/apps/`. defs pinned `prodigy9.co/defs@v0.3.19` in
  the cue cache `~/Library/Caches/cue/mod/extract/prodigy9.co/defs@v0.3.19/`. READ-ONLY.
- **Real `#ClusterIssuer`** (`.../defs@v0.3.19/cluster_issuer.cue`): `Self={ parts.#Metadata;
  #email; #staging: bool|*false; spec: acme: { email: Self.#email; if Self.#staging{…};
  if !Self.#staging{…}; … } }`. `parts.#Metadata` embeds `attr.#Metadata` with `if Self.#ns != _|_`
  guards — the 3-level chain (E).
- **Repro modules** in `/tmp` ONLY (rebuild if gone): `/tmp/pf_self` (Self+embed+nested+cond — C,
  now WORKS), `/tmp/pf_pres` (presence-test — D, WORKS), `/tmp/pf_len` (len-guard — D, WORKS),
  `/tmp/pf_chain` (multi-level embed — E, FAILS), `/tmp/plain.cue` (C no closure, WORKS).
- **Default-resolution machinery lives in `Lattice.lean` now** (`resolveDisjDefault?`,
  `liveAlternatives`, `defaultAlternatives`) — reuse it; don't reinvent. `Manifest` and the
  eval guard both call it.
- **`fuel` is LOAD-BEARING** in `EvalKey` — never drop it. The closure-force / meet-embeddings
  mutual recursion is fuel-bounded.
- **Release:** ~1 datestamped alpha/day, `scripts/release.sh` only — CI/Actions BANNED. Latest
  `v0.1.0-alpha.20260617.3`. Did NOT cut a release (mid-churn).
- **Safety:** prod9 + cue cache READ-ONLY. Bash filter mangles piped git input → `git commit -F
  /tmp/msg`. NO `git checkout`/`restore`/`reset --hard`. cue oracle: `/Users/chakrit/go/bin/cue`
  v0.16.1.

## Audit cadence

Slices 3, 4, A landed since the last Phase-A/B pass; C now lands on top. C is small (distribution +
one guard collapse + a helper consolidation), behavior-additive (zero fixture drift). A two-phase
audit per `docs/guides/slice-loop.md` is DUE around now (do NOT invoke `/ace-audit`; follow the
guide) — covering slices 3-4-A-C. Don't let it stall slice E.
