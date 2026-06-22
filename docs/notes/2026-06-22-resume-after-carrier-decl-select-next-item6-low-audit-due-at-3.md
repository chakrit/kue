# RESUME — CARRIER-DECL-SELECT landed; counter=2; next = item-6 LOW; audit due at 3 (2026-06-22)

Live START-HERE; supersedes
`2026-06-22-resume-after-carrier-struct-meet-next-carrier-decl-select.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md) +
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Genuinely-open
backlog. Full per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md).

## State — CARRIER-DECL-SELECT DONE (slice 2 of the new batch)

The DRY fix-slice filed by the Phase-B audit landed. `selectEvaluatedField` repeated the
same decl-selection triple SIX times (three decl-bearing carrier shapes `.struct` /
`.embeddedList` / `.embeddedScalar`, at the top level AND again inside the `.disj`-resolved
sub-case). Collapsed to one helper.

- **Fix (Eval):** extracted `selectFromDecls (base) (label) (decls) : Value` —
  `findEvalField` → `selectedFieldValue` (the single closing decision) / deferred
  `.selector base label` on a miss. Routed all SIX sites through it (top-level trio +
  disj-resolved trio). The three shapes AGREE exactly, so this is real dedup (NOT the
  four-classifiers false-sharing case, where they DISAGREE).
- **Home = `Eval.lean`, NO new edge.** Helper wanted in both `Eval` and `Runtime`;
  `Runtime` already `import`s `Eval` (line 1), so `Eval` is the lowest module both see.
  Graph unchanged (`Eval → {Builtin, EvalOps, Decimal, Lattice, Regex, Normalize}`;
  `Runtime` sits above).
- **Runtime is a DIFFERENT operation — NOT shared across the seam.** `lookupField?`'s
  carrier arms looked like the same triple but yield the RAW `Field.value` (no close) and
  return `Option` (`none` = genuine absence, for the `-e` "field not found" diagnostic —
  never a deferred `.selector`). Routing it through `selectFromDecls` would silently change
  behavior (close def bodies it keeps raw, lose the `none`-vs-present distinction) AND DRY
  across a module boundary (banned). Collapsed only the WITHIN-Runtime triplication: a
  1-line local `fieldValue?`; doc-comment records why it stays distinct.
- **Tests (+2 pins):** the thin path was selection off a DEFAULTED disjunction whose
  default arm is a CARRIER — the `.disj` sub-case's carrier arms had no direct pin (the
  `.struct`-via-disj arm was already covered). Added
  `TwoPassTests.select_into_default_disjunction_{scalar,list}_carrier`. Top-level carrier
  selection already covered (`scalar_embed_with_decls_decl_selectable` + `_multiple` +
  `_in_unification`; fixture `lists/list_embedding_select_index.cue`; `.struct` ubiquitous).
- **Verify:** `lake build` 110 jobs clean (no `sorry`/axiom/new warning);
  `check-fixtures.sh` zero drift; `shellcheck` n/a. Behavior-preserving, pin-count
  conserved +2. NO cue-divergence, NO spec-gap (pure refactor).

## NEXT STEP — leader = the item-6 LOW list (none soundness-bearing)

**Audit counter = 2** (CARRIER-STRUCT-MEET = slice 1, CARRIER-DECL-SELECT = slice 2 of the
new batch). **Two-phase audit due after the NEXT slice (at 3)**, per
[`../guides/slice-loop.md`](../guides/slice-loop.md) — Phase A (code-quality) then Phase B
(architecture), sequential, NOT `/ace-audit`.

Pick the next slice from the item-6 LOW list (`plan.md` § item 6) — all LOW, none
soundness-bearing, none block adoption:

- `module-file-scoped-imports` (arch-sized — per-file import scope frames; bites only the
  same-NAME-different-target case, prod9 doesn't hit it).
- Parser strictness: `*(1|2)` laxity (`cue` rejects at parse); `__x` double-underscore
  accepted (`cue` reserves `__`-prefixed idents). Track as a parser-strictness pass.
- A2-x / A2-y (`importBinding` merge-asymmetry; missing import-name redeclaration check —
  both corners prod9 doesn't hit).
- B2-A1 (`applyEvaluatedStructN` drops `tail` in the patterns-present meet — lossless
  today, breaks at typed-ellipsis) / B2-A2 (test-gap fill: reverse + both-tails fixtures).
- `resolveEmbeddedDisjDefault` (`Eval.lean`) — verify the pass-1 label-surfacing path
  doesn't also need use-site-narrowing distribution.
- DRY `selectEvaluatedField .disj` remaining win: fold the disj match itself into a
  RECURSIVE `selectEvaluatedField` call on the resolved default (gains free nested-disj
  recursion). The carrier-arm half is DONE (CARRIER-DECL-SELECT); this is the residual.
- `scalar-embed` provenance follow-ups (opportunistic pins when next touching Lattice/Eval).

`Eval.lean` < ~4500 re-split watch (ruling stands). `EvalTests.lean` growing; test-org
re-carve not yet due.

## Release state — `v0.1.0-alpha.20260622` CUT (2026-06-22, attended greenlight)

Cut from HEAD `b3f7cd9` via `scripts/release.sh 0.1.0-alpha.20260622`: tag pushed, GitHub
release published, homebrew-tap formula bumped + pushed (`bca1e1c..e7a8eaa`). Bundled
everything since `v0.1.0-alpha.20260621`: SC-1e, AD2-1, BI-2-residual, BI-2-§3, EvalOps,
import-eager-closedness, the first two-phase audit, TL-1, TL-2, scalar-embed-with-decls +
B3, the second two-phase audit, CARRIER-STRUCT-MEET, CARRIER-DECL-SELECT. Next alpha
cadence-due ~next day of work. (CI/GitHub Actions banned; release is the local script.)

## STANDING CONTEXT (full detail in CLAUDE.md + guides/slice-loop.md)

- Autonomy grant in effect; resolve forks by philosophy; commit/push on `main` (attended).
- Spec is authority; `cue` (`/Users/chakrit/go/bin/cue` v0.16.1) a fallible cross-check,
  never the gate. Correctness over byte-compat. kue binary: `.lake/build/bin/kue`.
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on main tree.
- Orchestrator = thin re-spawner; one subagent per slice; two-phase audit (A then B) every
  2-3 slices. Per-slice duties: tests-first; log `cue-divergences.md`; flag
  `cue-spec-gaps.md`.
