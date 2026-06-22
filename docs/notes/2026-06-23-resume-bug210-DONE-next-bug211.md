# RESUME — Bug2-10 DONE; next = Bug2-11 (the CORRECTED argocd blocker) (2026-06-23)

Live START-HERE; supersedes `2026-06-23-resume-audit-CLOSED-next-bug210.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md) +
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Bug2-11 +
ARGOCD-DEPTH REFRAME CORRECTED. Per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md) (Bug2-10 entry).

## State — audit counter = 1 (Bug2-10 = slice 1). Next = Bug2-11.

**Bug2-10 RESOLVED (`aa4172b`, on `main`; pushed if attended):** use-site narrowing into a
`.structComp` HOST's embedded self-ref. `{#Meta} & {#name:"x"}` (host is a structComp
embedding a self-ref def) now narrows `metadata.name` to `"x"` (was `incomplete value`),
matching cue + the DIRECT form.

- **Mechanism (delivery, approach A exactly).** `conjStructCompDefer?` (`Eval.lean`) defers
  a structComp host whose embed body has a sibling self-ref (`bodyNeedsDefer`, over a
  placeholder body-frame `(0,[]) :: env`) to its `.closure (env, hostBody)`, so it joins the
  SAME shared-`useOperands` fold the bare-ref path runs (`forceClosureWithConjunctCore`'s
  `.structComp` arm). Call-site gate: a narrowing sibling exists (`conjNarrowingSibling?`).
  Did NOT touch `meetEmbeddingsWithFuel` internals.
- **Plus a PRE-EXISTING embed-meet closedness leak fixed** (`embeddingClosesHost` /
  `embeddingFieldIsDefinition`): embedding a CLOSED def into a no-`...` host closes it over
  `host ∪ embed` labels, so a later MEET rejects an undeclared extra (`{#Meta} & {b}` →
  reject `b`; was ADMITTED — reproducible with NO self-ref, so genuinely pre-existing).
  ONLY for `regularOpen` (explicit `...` host stays open). Embed-FORM `{#Meta, b}` still
  admits `b`.
- **Verify (all green):** full `lake build` (sentinels resolve); `check-fixtures.sh` zero
  drift; cert-manager content-identical (jq -S = 0, raw = 15 = field-order #3); axiom-clean
  (propext/Quot.sound). 9 `native_decide` pins (`### Bug2-10`) + 7 `bug210_*` fixture pairs.

## 🚨 THE BIG CORRECTION — argocd is Bug2-11, NOT Bug2-10

The prior breadcrumb + design note claimed **"ARGOCD CHAIN IS ONE DEEP FIX (Bug2-10),
Bug2-11 off-path (same-frame)."** That is **EMPIRICALLY WRONG.** Landing Bug2-10 advanced
`kue export apps/argocd.cue` from `incomplete value: string` to `conflicting values`
(~54s, still bottoms). Probing the real `defaults.#ListenerSet & {#name, #passthrough_hosts}`
shows `metadata: {name: string}` (un-narrowed) + `#passthrough_hosts: _|_`.
`defaults.#ListenerSet` is a **TWO-LEVEL cross-package def-of-def selector**
(`defaults.#ListenerSet = defs.#ListenerSet & {…}`, a cross-pkg def whose body refs the
cross-pkg `defs.#ListenerSet`, which embeds `parts.#Metadata`'s `metadata.name: Self.#name`).
`flattenConjDefRef` correctly declines the cross-package selector → standalone force, NO
use-operands → narrowing never reaches the embed. That is **Bug2-11, and it IS the on-path
argocd blocker.**

**SELF-CONTAINED 3-package repro (no cache; built at `/tmp/b211mod` during the slice):**
```cue
// package defsx
#Meta: Self={ #name: string, metadata: name: Self.#name }
#ListenerSet: { #Meta, #gateway_name: string, #passthrough_hosts: [...string] | *[], kind: "ListenerSet" }
// package defaultsx (imports defsx)
#ListenerSet: defsx.#ListenerSet & { #gateway_name: "nginx" }
// package main (imports defaultsx)
out: defaultsx.#ListenerSet & { #name: "argocd-ls", #passthrough_hosts: ["argo.prodigy9.co"] }
// cue: metadata.name "argocd-ls", passthrough ["argo…"]; kue: metadata.name string, passthrough _|_
```
A SINGLE-level cross-pkg selector (`defsx.#ListenerSet & {narrow}`) narrows FINE — the
failure needs the def-OF-def indirection (exactly argocd's shape). `#passthrough_hosts: _|_`
is a SECONDARY symptom of the SAME root: the standalone force collapses the sibling
disjunction `[...string] | *[]` → `*[]`, conflicting with the use-site list.

## Next leader — Bug2-11 (HIGH, on-path argocd blocker)

Use-site narrowing of a two-level cross-package def-of-def selector whose terminal def embeds
a sibling self-ref. Same fix FAMILY as Bug2-10/2-9 (carry the narrowing through the
deferral), DISTINCT frame: needs the TERMINAL package frame capture (the `importSelectorDef?`
/ `refAliasSelectorDef?` / `refAliasDefClosure?` path that already captures
`(pkgFields, defBody)` — but for a def-of-def, the BODY's cross-pkg selector conjunct must
ALSO carry the use-operands into ITS force). The current `evalConjStandard` closure-fold
force-splices use-operands into a top-level `.closure`, but when the closure's BODY is itself
a `.conj` containing another cross-pkg selector, that inner selector forces standalone.
Likely seam: make the cross-package selector force (or the flatten) thread the use-operands
one level deeper. Build the faithful oracle with a THROWAWAY `/tmp` module depending on
`prodigy9.co/defs@v0.3.19`; the def sources are READ-ONLY at
`~/Library/Caches/cue/mod/extract/prodigy9.co/defs@v0.3.19/` (`listener_set.cue`,
`parts/{metadata,use_cert_manager,mixin}.cue`).

**Over-fire guard (same discipline as Bug2-10):** fire ONLY when the cross-pkg def's
terminal body has a sibling self-ref AND a sibling narrowing exists; cert-manager (which
uses the same def packages) MUST stay content-identical.

## After Bug2-11 (ranked)

1. **Perf frontier (#7 / item-5)** — un-gates once argocd ACTUALLY exports (Bug2-10 did NOT
   un-gate it — corrected). Profile the resolving `argo` target then.
2. **`TwoPassTests` SPLIT** (scheduled — `plan.md` item 3) — carve `bug2x_*` into
   `Bug2xTests.lean`; the 1900+-line file is the demonstrated silent-failure surface. Each
   new file gets the `#check` tripwire + `--` headers.
3. **item-6 LOW tail** + **Bug2-12** (LOW, self-recursive closed-def closedness leak —
   spec-check first; pre-existing, the inlined form leaks identically).

## Release state

`v0.1.0-alpha.20260622` was CUT. A fresh alpha is **cadence-available, awaits user
greenlight** — Bug2-10 (`aa4172b`) + Bug2-9..Bug2-5 + test-health hardening unreleased
in-tree. A fresh alpha would be notable IF argocd exported — it does NOT yet (Bug2-11
pending). CI/Actions banned; release = local `scripts/release.sh` +
`scripts/release-linux.sh`.

## STANDING CONTEXT (full detail in CLAUDE.md + guides/slice-loop.md)

- Autonomy grant in effect; resolve forks by philosophy; commit/push on `main` (attended).
- Spec is authority; `cue` (`/Users/chakrit/go/bin/cue` v0.16.1) a fallible cross-check,
  never the gate. Correctness over byte-compat. kue binary: `.lake/build/bin/kue`.
- prod9 (`/Users/chakrit/Documents/prod9/infra`) + cue caches READ-ONLY. NO
  `git checkout`/`restore`/`reset --hard` on the main tree. Faithful argocd oracle: a
  THROWAWAY `/tmp` module depending on `prodigy9.co/defs@v0.3.19` — no prod9 mutation.
- Orchestrator = thin re-spawner; one subagent per slice; per-slice duties: tests-first
  (line-comment headers + `#check` tripwire on any new/touched test module); log
  `cue-divergences.md`; flag `cue-spec-gaps.md`.
- **Two-phase audit DUE after Bug2-11** (counter will hit 2-3): the Bug2-10 + Bug2-11 batch.
