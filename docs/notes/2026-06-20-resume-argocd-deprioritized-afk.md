# RESUME HERE — F-3 DONE (qualified import path parses); BI-1 spike or a periodic pass next; audit DUE after ~1 more slice (BI-2=1, F-3=2) (2026-06-20)

Live START-HERE pointer; supersedes all prior breadcrumbs. Authoritative live roadmap:
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md)
§ Consolidated fix backlog (owns the ranked spec-conformance fixes) +
[`../spec/plan.md`](../spec/plan.md) (capabilities + non-spec roadmap).

**Latest (2026-06-20):** F-3 landed → **qualified import path `"location:identifier"` now PARSES**
(previously the unstripped `:id` broke directory resolution — `package directory not found:
…/lib/math-utils:math`, the dash-dir case the qualifier exists for). Spec grammar
`ImportPath = '"' ImportLocation [ ":" identifier ] '"'` puts the qualifier INSIDE the string.
Modeling: split it out at parse → `Import.path` is the LOCATION only, new
`Import.packageName : Option String` carries the explicit qualifier (`none` = default to last path
element). Keeps `path` directly usable by all consumers; the explicit-vs-defaulted distinction is
representable; the `Option` qualifier + existing `path` is the minimal precise shape (no redundant
explicit/defaulted sum — the defaulted value IS the last element). `splitImportPath` splits on the
sole `:` (ImportLocation can't contain `:` per the spec excluded-char set); `isPackageIdentifier`
validates the qualifier at PARSE (identifier-start + parts, not `#`/`_#`), rejecting junk — cue
accepts junk and defers to a load error, so Kue is MORE conformant (F-3 divergence).
`importBindName` precedence: alias > qualifier > declared-name > last-element. **SCOPE = parse +
bind-name**; the stricter suffix-vs-LOADED-declared-name MISMATCH gate (cue's `package name "other"`)
is a recorded resolution residual (needs the loaded name). 8 parse pins + 4 `importBindName`/
`isPackageIdentifier` pins + 4 module fixtures (`qualified_import{,_bare,_mixed,_invalid_id}`, the
three success cases byte-identical to cue). 1 cue-divergence + 1 spec-gap. cert-manager/argocd use no
qualifier — unaffected. See implementation-log + audit doc 2026-06-20.

**Audit state — BI-2 = slice 1, F-3 = slice 2 of the NEW batch; audit DUE after ~1 more slice.** The
two-phase audit closed at **Phase A `7ee15d8`** + **Phase B `457a165`** (counter reset to 0). BI-2
(slice 1) + F-3 (slice 2) have landed ⇒ next two-phase audit DUE after **~1 more slice** (or run it
now if the next pick is itself a periodic pass). When it comes: run sequentially (A then B, both edit
`plan.md`/this doc — parallel collides); follow [`../guides/slice-loop.md`](../guides/slice-loop.md),
do NOT invoke `/ace-audit`. **Phase-B rulings to carry forward (do not re-litigate):** walker dedups
are THREE distinct families (AD4-1 `EvalM` clause-drivers / A-EN3 pure `Value` folds / DRY-1
let-fixpoint walkers) + a separate normalizer pair (AD2-1) — four mechanisms, NOT one; sequence
AD4-1 → A-EN3+DRY-1 → AD2-1, all post-argocd, gated. The bottom-payload newtype (AD3-4) is RULED OUT
(over-engineering). Test-org + plan-hygiene passes are DUE-but-non-blocking (do not preempt the
feature tail).

## IMMEDIATE NEXT STEPS (the loop can just `Keep going`)

1. **Audit due after ~1 more slice** (BI-2 = slice 1, F-3 = slice 2 of the new post-`457a165` batch;
   counter at 2). Pick slice 3 from the candidates below, then run the two-phase audit (Phase A →
   Phase B). **A periodic plan-hygiene OR test-org pass is the CLEANEST slice-3** — both are
   DUE-but-non-blocking, neither expands the feature surface (so it gives the audit a stable base),
   and plan.md/this doc have accumulated superseded re-ranks worth distilling. Recommended.
2. **BI-1 — the remaining MED feature, picked up with a DATA-APPROACH SPIKE FIRST (do NOT slice
   blind).** Unicode case-fold for `strings.ToUpper/ToLower` (currently ASCII-only → wrong on
   non-ASCII). ⚠ **Envelope risk**: full Unicode case-mapping likely needs a generated case-folding
   TABLE = a data dependency / possible network fetch (the grant forbids fetching external data into
   the repo without explicit need — if a builtin would require vendoring, STOP and flag). BI-1's
   slice MUST first decide: vendored generated table (checked-in, no fetch) vs scoped coverage
   (common ranges only). If picked as slice 3 it carries the envelope risk INTO the pre-audit base —
   prefer a periodic pass first (item 1), then BI-1 as the first slice of the next batch.
4. Then: **SC-3 display-residual** (LOW/spec-gap — cue collapses `*1|2`→`1`, `{…}|*null`→`null`; Kue
   does NOT, unsound; Format-layer projection rewriting ~7 fixtures, close only if the display
   convention is revisited) · **BI-2-residual** (Sqrt float64 + apd-Pow tail — needs Float/`NaN`/
   `Infinity`/sci-notation or a decimal numeric-methods module; lower priority, no app needs it).
5. Then the ranked tail in `spec-conformance-audit.md § Consolidated fix backlog`: **SC-4** (LOW,
   spec-check FIRST — cue is internally inconsistent here, don't reflexively match) · the 4
   spec-gap ratifications in `cue-spec-gaps.md` · **A#6** (`containsBottom` fuel cap 100,
   STANDALONE — D#2 confirmed it is NOT implicated by structural cycles; a real hardening item for
   deep NON-cyclic bottoms) · **DRY-1** (let-walker `walkFollowedLets` consolidation; schedule
   after Bug2-5 if that ever un-parks). **SC-1b** (closed×closed-pattern intersection) sits with
   this MED/hardening tail.
6. Plan-only roadmap (plan.md Live Backlog, NOT in audit.md): `truncate-primitive` (HIGH —
   soundness hardening) · Regex/EvalOps module extractions · test/fixture-org pass ·
   field-order #3 · A2-x/A2-y loader corners · B3/B5 incompleteness. NOTE: plan-side **A-EN3**
   and audit-side **DRY-1** look like the same let-walker consolidation — reconcile when picked.

**argocd / Bug2-5: PARKED** — a stress-test finding, not on the critical path. Resolves as the
general semantics mature; do not chase it with app-specific narrowing.

## CANONICAL PATHS (ground-truth — a prior auditor got confused; do NOT re-litigate)

- prod9 stress-test targets: `/Users/chakrit/Documents/prod9/infra/apps/argocd.cue` and
  `.../cert-manager.cue` (cert-manager is fully correct; argocd parked).
- cue oracle: `/Users/chakrit/go/bin/cue` (v0.16.1) — READ-ONLY, cross-check only.
- kue binary: `.lake/build/bin/kue` (or `lake exe kue`).

## STANDING CONTEXT (durable; full detail in CLAUDE.md + guides/slice-loop.md)

- Kue autonomy grant in effect (decide/proceed; resolve forks by philosophy; commit/push on
  `main` when attended). **Spec is authority; `cue` is a fallible cross-check, never the
  gate.** Correctness-over-performance. **Unattended/AFK → commit, don't push** (CLAUDE.md).
- Orchestrator = thin re-spawner; one subagent per slice; two-phase audit (A then B) every
  2–3 slices. Per-slice duties: tests-first; log `cue-divergences.md`; flag
  `cue-spec-gaps.md`; keep `kue-performance.md` current.
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on the main tree.
- Loose end (low priority): compat-assumptions.md "Composition note (infra docker-config)"
  (~L503–510) may be stale — `_auths` hidden-field refs + `[string]:` label patterns now
  likely resolve; needs a targeted end-to-end check on `secret.cue` before trusting.
