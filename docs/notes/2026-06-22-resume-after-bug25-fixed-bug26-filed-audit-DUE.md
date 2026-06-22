# RESUME — Bug2-5 FIXED; Bug2-6 filed (argocd blocker); audit DUE (2026-06-22)

Live START-HERE; supersedes
`2026-06-22-resume-after-carrier-decl-select-next-item6-low-audit-due-at-3.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md) +
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Live-slice detail.
Full per-slice history: [`../reference/implementation-log.md`](../reference/implementation-log.md).

## State — Bug2-5 DONE (`5fca57e`, pushed `main -> main`)

The argocd Bug2-5 mechanism is FIXED — but it was NOT the final argocd blocker. Bisecting
past it uncovered a distinct, deeper, pre-existing blocker (Bug2-6).

- **Bug2-5 (transitive-embed disj-path narrowing injection).** A co-embedding sibling
  def's static `kind` narrows a mixin let-local (`_patch.kind`) buried inside a
  disjunction-bodied `#Mixin`, embedded TRANSITIVELY (`#ListenerSet` → `#UseCertManager` →
  `#Mixin`). The break was ONE level deeper than the original sketch: the host's
  `spliceOperandForEmbed` into the MIDDLE def dropped `kind`, because
  `embedBodyEmbedsDisj` is a one-level check and the middle def neither reads `kind` nor
  directly embeds a disjunction. **Fix:** `embedBodyEmbedsDisjDeep` follows the embed chain
  (via `resolveEmbedDefBody?`, mirroring `bodyNeedsDefer`) so a transitively-embedded
  disjunction triggers the SAME sound Gap-2b regular-field splice. Not the
  `.disj`-distribution injection predicted — once `kind` reaches the splice the narrowing
  already flows; the bug was purely the missing GATE. NO new walker family member
  (transitive extension of the existing gate; mirrors `bodyNeedsDefer`). 8 `native_decide`
  pins + export fixture `bug25_disj_arm_let_local_narrowing`. cert-manager
  content-identical; fixtures green.

- **Bug2-6 (the REAL argocd blocker — PARKED, distinct mechanism).** Definition
  multi-declaration closedness. **Minimal repro:** `#Foo: {a: 1}` + `#Foo: {c: 3}` → cue
  unifies bodies BEFORE closing → `{a:1, c:3}`; kue closes each decl SEPARATELY and
  conjoins → mutual rejection → `{a: _|_, c: _|_}`. Hits argocd's `#UseCertManager` (three
  `#additions:` hidden-field decls). **Soundness constraint:** `#A & #B` (distinct closed
  defs) must STILL reject — the fix needs same-def-decl provenance (in
  `canonicalizeFields`/`joinUnevaluated`), not a naive meet-time closed-set union. PARKED
  for a dedicated slice; correctness-first. Full diagnosis: `spec-conformance-audit.md`
  Live-slice detail + implementation-log 2026-06-22.

## NEXT STEP — 🚨 TWO-PHASE AUDIT DUE (counter = 3)

**Audit counter = 3** (CARRIER-STRUCT-MEET = 1, CARRIER-DECL-SELECT = 2, **Bug2-5 = 3**).
A two-phase audit (A then B, sequential, NOT `/ace-audit`) is **DUE before the next
feature slice**, per [`../guides/slice-loop.md`](../guides/slice-loop.md):

- **Phase A (code-quality):** correctness, totality, illegal-states, DRY, test strength,
  skill compliance over the batch (incl. the Bug2-5 `embedBodyEmbedsDisjDeep` addition —
  verify the transitive gate is sound + the splice-soundness claim holds; check the
  walker-dedup ruling was honored, not a false merge).
- **Phase B (architecture):** module boundaries, layering, dead code, the embed-splice
  helper family (`embedBodyEmbedsDisj` / `embedBodyEmbedsDisjDeep` /
  `spliceOperandForEmbed` / `embedComprehensionReadLabels` / `embedDisjArmDeclLabels` — is
  this family coherent or drifting?), test/fixture org.

Fold findings into the plan as fix-slices; don't stall forward motion.

## After the audit — leader candidates

1. **Bug2-6** (the real argocd blocker — def multi-decl closedness). HIGH value, a
   provenance-carrying def-merge fix; the milestone (argocd export) needs it. Spec-defined
   (definition unification), general, NOT app-specific. The natural next HIGH slice — but
   weigh against its soundness sensitivity (must not break `#A & #B` rejection).
2. **Perf frontier (#7 / item-5)** — STILL gated on the argocd unblock (now Bug2-6, not
   Bug2-5). Un-gates once Bug2-6 lands; profile `argo` against a resolving target then.
3. **item-6 LOW tail** (`plan.md` § item 6) — none soundness-bearing, none block adoption.
4. **SC-4** (LOW, spec-gap-first).

## Release state — `v0.1.0-alpha.20260622` CUT (was HEAD `b3f7cd9`)

Cut this session (attended greenlight). Next alpha cadence-due ~next day of work. Bug2-5
(`5fca57e`) lands AFTER the cut → bundles into the next alpha. (CI/GitHub Actions banned;
release = local `scripts/release.sh`.)

## STANDING CONTEXT (full detail in CLAUDE.md + guides/slice-loop.md)

- Autonomy grant in effect; resolve forks by philosophy; commit/push on `main` (attended).
- Spec is authority; `cue` (`/Users/chakrit/go/bin/cue` v0.16.1) a fallible cross-check,
  never the gate. Correctness over byte-compat. kue binary: `.lake/build/bin/kue`.
- prod9 + cue caches READ-ONLY (argocd source: `apps/argocd.cue` in
  `~/Documents/prod9/infra`; its `defs` resolves to `~/Library/Caches/cue/mod/extract/
  prodigy9.co/defs@v0.3.19`). NO `git checkout`/`restore`/`reset --hard` on main tree.
- Orchestrator = thin re-spawner; one subagent per slice; two-phase audit (A then B) every
  2-3 slices. Per-slice duties: tests-first; log `cue-divergences.md`; flag
  `cue-spec-gaps.md`.
