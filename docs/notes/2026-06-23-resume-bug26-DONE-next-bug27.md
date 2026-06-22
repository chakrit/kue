# RESUME — Bug2-6 DONE; next leader = Bug2-7 (2026-06-23)

Live START-HERE; supersedes `2026-06-23-resume-audit-CLOSED-next-bug26.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md) +
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Live-slice detail.
Full per-slice history: [`../reference/implementation-log.md`](../reference/implementation-log.md).

## State — Bug2-6 LANDED (`ef824cb`); audit counter = 1

**Bug2-6 RESOLVED** (`ef824cb`, on `main`, pushed `main -> main`). Definition
multi-declaration close-once: two same-def decls (`#Foo:{a:1}` + `#Foo:{c:3}`) UNIFY their
field-sets and close ONCE over the union (`{a:1,c:3}`), the standard CUE rule. Mechanism
(STRUCTURAL provenance, per the Phase-B design note): `canonicalizeFields` routes a merged
DEFINITION-class slot through the new `mergeDefinitionDecls` (close-once UNION) instead of
`.conj`; the use-site `#A & #B` meet path is untouched (concatenate clauses → reject), so the
soundness guards stay green. `mergeConjFields` (conj-of-EMBEDS) keeps plain `.conj` (a host's
field meeting an embed's same-label field must `.conj`, not union — unioning re-opened a
cert-manager closed pattern). 13 pins + 3 fixtures, oracle-confirmed, axiom-clean, total.
cert-manager content-identical. See implementation-log 2026-06-23.

## The milestone — argocd STILL bottoms (~61s); Bug2-6 was NOT the final blocker

`kue export apps/argocd.cue` still bottoms (~61s wall). Bisected to
`route.yaml`/`listener.yaml` (the `defaults.#ListenerSet = defs.#ListenerSet &
parts.#UseCertManager & {…}` composition; `#UseCertManager` declares `#additions` THREE
times). It now hits **Bug2-7** (filed, PARKED).

## NEXT STEP — Bug2-7 (the new real argocd blocker; PARKED → next dedicated slice)

**Bug2-7:** same-def multi-decl close-once is correct on DIRECT selection (Bug2-6) but LOST
when the merged def is REFERENCED through a sibling. Minimal repro:
`#Use: {#additions: cert_gw:{…}; #additions: cert_ing:{…}; vis: #additions}` → `out: #Use.vis`
gives `{cert_gw:_|_, cert_ing:_|_}` (cue: `{cert_gw:{}, cert_ing:{}}`). Root: the
def-deferral/force-fold reconstruction (`mergeConjOperands`/`mergeConjFields`, `Eval.lean`)
rebuilds the def body from the ORIGINAL decls via plain `.conj` and re-closes each SEPARATELY,
so each clause rejects the other decl's fields. `canonicalizeFields` (Bug2-6) covers direct
same-struct merge but NOT this reconstruction path.

**Sound-fix sketch (the slice starts here, NOT a blank page):** carry same-decl provenance
THROUGH `mergeConjOperands` — distinguish WITHIN-operand repeated decls of one def (must
close-once UNION, the Bug2-6 rule) from CROSS-operand conjuncts (must `.conj`-meet). A naive
union in `mergeConjFields` is UNSOUND (verified: re-opens the cert-manager mixin's closed
`#data: [string]: string` pattern with a stray `...`). Larger design change than Bug2-6 —
the seam is per-operand, not a single same-struct field-list. Tripwire pin:
`bug27_WITNESS_multi_decl_def_ref_wrongly_bottoms` (`TwoPassTests`; FLIP when fixed).
**Soundness gate (keep green):** the cert-manager mixin path (`hidden_def_embed_*` pins) +
`#A & #B` rejection. Spec basis: same as Bug2-6 (definition decls unify, close once).

After Bug2-7: **perf frontier (#7 / item-5)** — STILL gated (un-gates once argocd resolves;
profile `argo` against a resolving target then) → **item-6 LOW tail** (parser strictness,
A2-x/y, B2-A1/A2, `resolveEmbeddedDisjDefault` check, `release-linux.sh` dirty-tree guard).

## Release state

`v0.1.0-alpha.20260622` was CUT. A fresh alpha is **cadence-available but awaits user
greenlight** — Bug2-6 (`ef824cb`) + Bug2-5 (`5fca57e`) + the Linux scripts (`df40b62`) are
unreleased in-tree. (CI/GitHub Actions banned; release = local `scripts/release.sh` +
`scripts/release-linux.sh`.)

## STANDING CONTEXT (full detail in CLAUDE.md + guides/slice-loop.md)

- Autonomy grant in effect; resolve forks by philosophy; commit/push on `main` (attended).
- Spec is authority; `cue` (`/Users/chakrit/go/bin/cue` v0.16.1) a fallible cross-check,
  never the gate. Correctness over byte-compat. kue binary: `.lake/build/bin/kue`.
- prod9 + cue caches READ-ONLY (argocd source: `apps/argocd.cue` in
  `~/Documents/prod9/infra`). NO `git checkout`/`restore`/`reset --hard` on main tree.
- Orchestrator = thin re-spawner; one subagent per slice; two-phase audit (A then B) every
  2-3 slices. Per-slice duties: tests-first; log `cue-divergences.md`; flag
  `cue-spec-gaps.md`. **Audit counter = 1** (Bug2-6 = slice 1 of the new batch; audit due at 3).
