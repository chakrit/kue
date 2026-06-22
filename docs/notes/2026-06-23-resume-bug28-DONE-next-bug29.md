# RESUME — Bug2-8 DONE; next leader = Bug2-9 (2026-06-23)

Live START-HERE; supersedes `2026-06-23-audit-CLOSED-next-bug28.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md) +
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Bug2-8 RESOLVED
/ Bug2-9 PARKED. Full per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md) (Bug2-8 entry).

## State — audit counter = 1 (Bug2-8 = slice 1 of the new batch).

**Bug2-8 RESOLVED (`2332aff`).** Same-def multi-decl close-once ACROSS AN EMBED boundary —
the hardest layer of the argocd blocker chain. New `inductive DeclProvenance := ownDecl |
embeddedDecl` on a named `structure ConjOperand` (replacing the `(List Field × Bool)`
operand tuple). A PLAIN embedding's same-def-path decls (`embedSameDefPathDecls`, gated to
host def labels + `!bodyNeedsDefer && !embedBodyEmbedsDisjDeep`) fold into the static frame
as an `embeddedDecl` operand, so the provenance-aware `mergeConjOperandFields`
close-once-UNIONS the host `ownDecl #m` × embed `embeddedDecl #m` pair via
`mergeDefinitionDecls` (Bug2-6 lever) — the `#m` slot holds the union AND `vis: #m` resolves
against it. The embed meet-fold STRIPS the embed's matching decl (`meetEmbedUnioningDefDecls`)
so the generic meet is idempotent. Boundary held by `isUnionableDefValue` (only
field/pattern-bearing struct def values union; scalar `#x: string` stays a meet) — the
cert-manager REGULAR closed pattern never enters the union. 8 `native_decide` pins + 3
fixtures, oracle-confirmed; cert-manager content-identical (jq-S=0); axiom-clean, total.

## Next leader — Bug2-9 (PARKED, the residual argocd blocker)

`kue export apps/argocd.cue` STILL bottoms (~55s) after Bug2-8 — NOT the final blocker.
**Bug2-9:** use-site narrowing of a REFERENCED multi-conjunct def whose conjuncts include
the cert-manager mixin. The argocd `ls = defaults.#ListenerSet &
{#name,#ns,#passthrough_hosts}`, where `defaults.#ListenerSet = defs.#ListenerSet &
parts.#UseCertManager & {#gateway_name,…}` (a 3-way def-meet). kue bottoms; cue produces the
full ListenerSet manifest. **Localized:** the INLINED 3-way meet with all use fields supplied
directly (`defs.#ListenerSet & parts.#UseCertManager & {all #fields}`) WORKS in kue — the
bottom is specific to REFERENCING the NAMED multi-conjunct def `defaults.#ListenerSet` and
narrowing it at the use site, where `#name`/`#ns` must flow through the multi-conjunct def to
the mixin's `_patch`/`#additions` machinery. Distinct from Bug2-8 (decl-union): this is
narrowing-through-a-referenced-multi-conjunct-def. **~11s to repro in isolation** — a probe
in the apps package: `bug29_ls: defaults.#ListenerSet & {#name:"argocd-ls", #ns:"argocd",
#passthrough_hosts:[…]}` (prod9 module, READ-ONLY — remove the probe after). cue path: full
manifest with cert-manager annotation; kue: `conflicting values (bottom)`. PARKED;
correctness-first per the guardrails.

After Bug2-9: **perf frontier (#7 / item-5)** — STILL GATED (un-gates once argocd resolves;
profile `argo` against a resolving target then) → **item-6 LOW tail** (parser strictness
`*(1|2)`/`__x`, A2-x/y, B2-A1/A2, `resolveEmbeddedDisjDefault` check, `release-linux.sh`
dirty-tree guard).

## Periodic passes status

- **Two-phase audit — DUE after the next 1–2 slices** (counter = 1; Bug2-8 was slice 1 of
  the new batch). Sequential A (code-quality over the Bug2-8 diff — provenance-type
  discipline: EVERY `DeclProvenance`/`ConjOperand` match site handled, no catch-all `_`
  swallowing a case; the static-fold gate soundness; `isUnionableDefValue` discriminator)
  then B (architecture/refactor over the module graph).
- **Test-org pass — APPROACHING-due.** `TwoPassTests.lean` ~1760 (+~47 since the prior 1713;
  ~64 Bug2-x pin refs) — the file to watch. The Bug2-x pins would live in a
  closure/two-pass-merge group when the reorg lands. Pick up as a dedicated slice when
  unwieldy.

## Release state

`v0.1.0-alpha.20260622` was CUT. A fresh alpha is **cadence-available but awaits user
greenlight** — Bug2-8 (`2332aff`) + Bug2-7 (`3361699`) + Bug2-6 (`ef824cb`) + Bug2-5
(`5fca57e`) + the Linux scripts (`df40b62`) are unreleased in-tree. (CI/GitHub Actions
banned; release = local `scripts/release.sh` + `scripts/release-linux.sh`.)

## STANDING CONTEXT (full detail in CLAUDE.md + guides/slice-loop.md)

- Autonomy grant in effect; resolve forks by philosophy; commit/push on `main` (attended).
- Spec is authority; `cue` (`/Users/chakrit/go/bin/cue` v0.16.1) a fallible cross-check,
  never the gate. Correctness over byte-compat. kue binary: `.lake/build/bin/kue`.
- prod9 (`/Users/chakrit/Documents/prod9/infra`) + cue caches READ-ONLY. NO
  `git checkout`/`restore`/`reset --hard` on main tree.
- Orchestrator = thin re-spawner; one subagent per slice; per-slice duties: tests-first;
  log `cue-divergences.md`; flag `cue-spec-gaps.md`.
