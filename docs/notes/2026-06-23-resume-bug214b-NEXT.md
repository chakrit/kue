# RESUME — Bug2-14 case-D PLAIN-EMBED half LANDED; next = Bug2-14b force-path (2026-06-23)

Live START-HERE; supersedes `2026-06-23-resume-bug214-NEXT-audit-CLOSED.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md) +
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) (Bug2-14
RESOLVED-partial + the new Bug2-14b filing). Per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md).

## State — audit counter = 1. Bug2-14 (case-D plain-embed half) landed `e404b21`.

Tree clean, pushed `main -> main` (verify HEAD==upstream on resume). One code slice landed
since the last two-phase audit closed → audit counter = 1 (next two-phase audit due after
1–2 more code slices).

## What landed this slice (`e404b21`)

The general "case D" embed-merge frame-binding bug — an embed declaring a label ABSTRACTLY
(`bk: string`) which the host narrows CONCRETELY (`bk: "X"`), leaving the embed body's
sibling/comprehension read bound to the embed-LOCAL un-narrowed value — **RESOLVED for the
PLAIN-EMBED path**.

- **Mechanism (NOT the design's `remapConjRefs`).** `injectEmbedSiblingNarrowings` at
  `meetEmbeddingsWithFuel`'s plain-embed eval (`Eval.lean`): MEET the host's (`current`'s)
  regular-output narrowing into the embed body's same-label read-and-declared slot BEFORE
  the body evals. The analog of `injectLetLocalNarrowings` (Bug2-4) for an embed body. The
  design's `remapConjRefs` re-index lever did NOT fit: the embed body's sibling ref is
  depth-0 into its OWN frame (a separate frame), so re-INDEXING within that frame cannot
  bridge to the host frame; value-INJECTION (meet the host value into the embed's own
  slot) is the sound mechanism. Recorded in the audit doc.
- **Soundness:** re-base IFF embed-declared AND host-narrowed
  (`embedComprehensionReadLabels` ∩ `current` fields). Over-rebase guard PINNED
  (`{bk:"X",{other:string,echo:other}}` → `echo` stays incomplete). Conflict bottoms
  (`int & "X"`). General, not keyed to argocd.
- **Tests:** 8 `native_decide` pins (`Bug2xTests.lean` Bug2-14, tripwire anchor
  `bug214_conflicting_type_bottoms`) + 2 export fixtures. cert-manager content-identical
  (jq -S = 0). Both case-D forms == cue.

## THE MILESTONE — argocd does NOT export (Bug2-14b is a DISTINCT 2nd layer)

`kue export apps/argocd.cue` STILL bottoms (`conflicting values`, ~53s wall). The design's
"the cross-package def-of-def force-path is the SAME fix" read was **EMPIRICALLY WRONG** —
the plain-embed fix does not reach the argocd path. NOT a drop-in. Standing Capabilities
unchanged (cert-manager remains the only real-app content-identical drop-in, ~12.6s). Perf
#7 STAYS GATED. A fresh alpha is cadence-available but NOT a notable milestone (argocd
does not export).

## Next leader — Bug2-14b (HIGH, the actual on-path argocd blocker; PARKED, repro in hand)

Cross-package FORCE-path let-local narrowing through a STRUCTURAL DISJUNCTION. The argocd
`#Mixin` is `listShape | structShape | error(…)` embedding `let _patch{kind:string;
for _,add in Self.#additions {if kind==add.#kind {add.#patch}}}`; the host
`defs.#ListenerSet` declares `kind:"ListenerSet"` as a sibling. On the cross-package FORCE
path (`forceClosureWithConjunctCore`) the host's `kind` does NOT reach `_patch.kind`
through the disjunction arm → the comprehension defers → `metadata.annotations` drops
(bare export silently-incomplete; `[out]`/`[ls]` → `conflicting values`).

- The **SINGLE-level** cross-package use already drops it (NOT def-of-def-specific). The
  **DIRECT INLINE** form of the same shape DRAINS (export's re-eval re-expands the bucket
  where `kind` is merged; the force path skips that).
- **Fix family:** carry the host's sibling narrowing (`kind`) into the embed's
  `let _patch` THROUGH the structural-disjunction arm distribution on the force path — the
  force-path analog of `injectLetLocalNarrowings` (Bug2-4) crossed with
  disjunction-distribution (Bug2-5/Gap-2b) and the cross-package frame discipline
  (Bug2-11). The deep embed-merge-tier fix; NOT the plain-sibling re-base just landed.
- **Self-contained 4-package repro (reconstruct; was at `/tmp/b214c`, cue.mod
  `ex.com/b214c`):** `parts/` (`#Mixin` = `structShape | error` embedding `let _patch{…if
  kind==add.#kind…}`; `#Use {#Mixin; #issuer:string|*"main"; #additions: ls:{#kind:
  "ListenerSet", #patch:{metadata:annotations:issuer:Self.#issuer}}}`), `defs/` (`#LS:
  {kind:"ListenerSet"; parts.#Use}`), `main` (`out: defs.#LS & {#issuer:"le"}`,
  `wrapped:[out]`). cue: `out.metadata.annotations.issuer "le"`; kue:
  `{kind:"ListenerSet"}` (annotations DROPPED), `wrapped` → `incomplete value`. Filing in
  `spec-conformance-audit.md` Bug2-14b.
- **Mixin source of truth (READ-ONLY):**
  `~/Library/Caches/cue/mod/extract/prodigy9.co/defs@v0.3.19/parts/{mixin,use_cert_manager}.cue`
  + `listener_set.cue` (the real `defs.#ListenerSet` is OPEN `...`, embeds
  `parts.#Metadata` + `attr.#Hosts` — match it for a faithful repro; my earlier 5-pkg
  reconstruction drained because it was too simple).

After Bug2-14b lands and argocd re-runs: if argocd EXPORTS, un-gate perf #7 (profile the
heavy `argo` sub-package) AND record argocd as a 2nd content-identical real-app drop-in in
Standing Capabilities + breadcrumb + log with wall-time; flag a notable-milestone alpha
for the user's greenlight. If a further bug hides behind the sound drain, it surfaces only
then (honest — no "one fix away" over-claim).

## Audit cadence

**Audit counter = 1.** Next two-phase audit due after 1–2 more code slices, per
`slice-loop.md` (A code-quality then B architecture, sequential — do NOT invoke
`/ace-audit`).

## Release state

`v0.1.0-alpha.20260622` was CUT. A fresh alpha is cadence-available, awaits user
greenlight — NOT notable (argocd does NOT export; cert-manager remains the only real-app
drop-in). CI/Actions banned; release = local `scripts/release.sh` + `release-linux.sh`.

## STANDING CONTEXT (full detail in CLAUDE.md + guides/slice-loop.md)

- Autonomy grant in effect; resolve forks by philosophy; commit/push on `main` (attended).
- Spec is authority; `cue` (`/Users/chakrit/go/bin/cue` v0.16.1) a fallible cross-check,
  never the gate. Correctness over byte-compat. kue binary: `.lake/build/bin/kue` (kue's
  own `eval` has NO `-e`; `kue export -e X` IS supported via the export path; `-e`
  bracket-string selectors like `argocd["x.yaml"]` do NOT parse — use a scratch field).
- prod9 (`/Users/chakrit/Documents/prod9/infra`) + cue caches READ-ONLY. NO `git
  checkout`/`restore`/`reset --hard` on the main tree. argocd oracle = `kue export
  apps/argocd.cue` from the infra root.
- Orchestrator = thin re-spawner; one subagent per slice; per-slice duties: tests-first
  (line-comment headers + `#check` tripwire on any new/touched test module); log
  `cue-divergences.md`; flag `cue-spec-gaps.md`.
