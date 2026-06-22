# RESUME — Bug2-9 DONE; next leader = Bug2-10 (2026-06-23)

Live START-HERE; supersedes `2026-06-23-resume-bug28-DONE-next-bug29.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md) +
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Bug2-9 RESOLVED
/ Bug2-10 PARKED. Full per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md) (Bug2-9 entry).

## State — audit counter = 2 (Bug2-8 = slice 1, Bug2-9 = slice 2). 🚨 TWO-PHASE AUDIT DUE.

**Bug2-9 RESOLVED (`5d9cf8f`).** Use-site narrowing of a REFERENCED NAMED multi-conjunct
def. `#LS: #Base & {…}` has a `.conj` BODY; referencing + narrowing it
(`#LS & {#name}`) bottomed/incompleted while the INLINED 3-way meet worked. Root cause:
the `.refId` eval arm forced `#LS`'s `.conj` body STANDALONE (no use-operands), so a
conjunct's sibling self-ref (`vis: #name`) collapsed to abstract `string` BEFORE the
use-site narrowing arrived (`incomplete value: string`). Fix: `flattenConjDefRef`
(`Kue/Eval.lean`) — in the `.conj` eval arm, FLATTEN a depth-0 ref-to-`.conj`-bodied def
into its constituents BEFORE the fold, making the named ref byte-identical to the inlined
meet. Depth-0-bounded (def + use site share the package frame), fuel-bounded (alias
cycles), recurses through a chain of named multi-conjunct defs. Total, axiom-clean
(propext). Soundness: named == inlined == cue (faithful prod9 `defs.#ListenerSet` via the
`defs@v0.3.19` cache); conflict still bottoms; closedness preserved. cert-manager canary
content-identical (jq -S = 0). 5 fixtures (`bug29_*`) + 5 pins (TwoPassTests Bug2-9).

## Next leader — Bug2-10 (PARKED, the residual argocd blocker)

`kue export apps/argocd.cue` STILL bottoms (~53s) after Bug2-9 — NOT the final blocker.
**Bug2-10:** use-site narrowing of a host that EMBEDS a def with a sibling self-ref does
NOT flow the narrowing into the embedded def's self-ref. **Fully self-contained repro (no
cache):**

```cue
#Meta: Self={ #name: string, metadata: name: Self.#name }
direct:   #Meta & {#name: "x"}   // cue & kue BOTH: {metadata: {name: "x"}}  ✓
embedded: {#Meta} & {#name: "x"} // cue: {metadata:{name:"x"}}; kue: incomplete value: string  ✗
```

The DIRECT meet narrows correctly; the EMBEDDED-then-narrowed form leaves
`metadata.name: string` (un-narrowed). **In argocd:** `defs.#ListenerSet` EMBEDS
`parts.#Metadata` (`metadata.name: Self.#name`), and `defaults.#ListenerSet & {#name,…}`
never reaches that embedded self-ref — so `metadata.name`/`metadata.annotations` drop and
the export incompletes/bottoms. The mixin's `_patch` annotation injection itself WORKS
(the residual shows `annotations: {"cert-manager.io/cluster-issuer": "i"}` correctly);
only the `parts.#Metadata` embed's `Self.#name` stays abstract. This is the **Bug2-4/2-5
NARROWING family** — `meetEmbeddingsWithFuel`'s closure-force-splice should carry the
narrowing into the embed but doesn't for the same-package `{#Meta}` embed shape.
**Caution:** the breadcrumb that filed Bug2-9 said "the INLINED 3-way meet WORKS in kue" —
that meant "does not BOTTOM"; the inlined form ALSO drops the annotation (content-
incorrect). Bug2-9's flatten made named == inlined, exposing this shared Layer-B defect.
PARKED; correctness-first per the guardrails.

After Bug2-10: **perf frontier (#7 / item-5)** — STILL GATED (un-gates once argocd
resolves; profile `argo` against a resolving target then) → **item-6 LOW tail** (parser
strictness `*(1|2)`/`__x`, A2-x/y, B2-A1/A2, `resolveEmbeddedDisjDefault` check,
`release-linux.sh` dirty-tree guard).

## Periodic passes status

- **🚨 Two-phase audit — DUE NOW** (counter = 2; Bug2-8 = slice 1, Bug2-9 = slice 2).
  Sequential A (code-quality over the Bug2-8 + Bug2-9 diff — for Bug2-9:
  `flattenConjDefRef` totality + the depth-0/fuel boundary soundness, the
  `flatMap`-before-fold placement, NO
  catch-all swallow; for Bug2-8: provenance-type discipline) then B (architecture/refactor
  over the module graph — `flattenConjDefRef` sits in `Eval`'s pre-`mutual` helper tier,
  near `conjStructOperand?`; check it is the right home + no overlap with the
  closure-deferral producers). Do NOT invoke `/ace-audit`; follow `slice-loop.md`.
- **Test-org pass — APPROACHING-due.** `TwoPassTests.lean` ~1820 (+~56 from Bug2-9's 5
  pins over the prior 1764; ~69 Bug2-x pin refs) — the file to watch. Pick up as a
  dedicated slice when unwieldy.

## Release state

`v0.1.0-alpha.20260622` was CUT. A fresh alpha is **cadence-available but awaits user
greenlight** — Bug2-9 (`5d9cf8f`) + Bug2-8 (`2332aff`) + Bug2-7 (`3361699`) + Bug2-6
(`ef824cb`) + Bug2-5 (`5fca57e`) + the Linux scripts (`df40b62`) are unreleased in-tree.
(CI/GitHub Actions banned; release = local `scripts/release.sh` +
`scripts/release-linux.sh`.)

## STANDING CONTEXT (full detail in CLAUDE.md + guides/slice-loop.md)

- Autonomy grant in effect; resolve forks by philosophy; commit/push on `main` (attended).
- Spec is authority; `cue` (`/Users/chakrit/go/bin/cue` v0.16.1) a fallible cross-check,
  never the gate. Correctness over byte-compat. kue binary: `.lake/build/bin/kue`.
- prod9 (`/Users/chakrit/Documents/prod9/infra`) + cue caches READ-ONLY. NO
  `git checkout`/`restore`/`reset --hard` on main tree. Faithful Bug2-9/2-10 oracle: a
  THROWAWAY `/tmp` module with `cue.mod` depending on `prodigy9.co/defs@v0.3.19` (resolves
  from the shared `~/Library/Caches/cue` extract) — no prod9 mutation.
- Orchestrator = thin re-spawner; one subagent per slice; per-slice duties: tests-first;
  log `cue-divergences.md`; flag `cue-spec-gaps.md`.
