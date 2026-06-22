# RESUME — Bug2-7 DONE; next leader = Bug2-8 (2026-06-23)

Live START-HERE; supersedes `2026-06-23-resume-bug26-DONE-next-bug27.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md) +
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Live-slice
detail. Full per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md).

## State — Bug2-7 LANDED (`3361699`); audit counter = 2 (audit DUE after this batch)

**Bug2-7 RESOLVED** (`3361699`, on `main`). Def multi-decl close-once on the reference /
force-fold path. Bug2-6 fixed close-once on DIRECT selection; Bug2-7 fixes it when the
merged def lives inside a `#`-definition wrapper selected/referenced through a sibling
(`#Use: {#additions:…; #additions:…; vis: #additions}` then `#Use.vis`). The wrapper
defers to a `.closure`; the force-fold reconstruction `mergeConjOperands` ran
`mergeConjFields` (plain `.conj`) over each operand BEFORE the downstream
`canonicalizeFields` could union the within-operand decls — so the two `#additions` decls
were `.conj`-collapsed + re-closed SEPARATELY → mutual reject
(`{cert_gw:_|_, cert_ing:_|_}`).

**Mechanism (within-operand vs cross-operand = the soundness boundary):**
`mergeConjOperands` now `canonicalizeFields`-es each operand's OWN fields up-front, so
within-operand repeated DEFINITION-class decls UNION via `mergeDefinitionDecls` (the
Bug2-6 lever, reused), while the CROSS-operand merge (`mergeConjFields`, plain `.conj`) is
UNTOUCHED — a host's `#data` meeting an EMBED's `#data` (distinct operands) still
`.conj`-MEETs. 8 pins + 3 fixtures, oracle-confirmed, axiom-clean (propext/Quot.sound),
total. cert-manager content-identical (jq -S diff = 0; raw 15 = field-order #3). See
implementation-log 2026-06-23.

## The milestone — argocd STILL bottoms (~58s); Bug2-7 was NOT the final blocker

`kue export apps/argocd.cue` still bottoms (~58s wall). It now hits **Bug2-8** (filed,
PARKED). cert-manager stays a content-identical drop-in (jq -S diff = 0). prod9 oracle
cache READ-ONLY; argocd source at `~/Documents/prod9/infra/apps/argocd.cue`; the
`defs@v0.3.19` dep resolves from
`~/Library/Caches/cue/mod/extract/prodigy9.co/defs@v0.3.19`.

## NEXT STEP — Bug2-8 (the new real argocd blocker; PARKED → next dedicated slice)

**Bug2-8:** same-def multi-decl close-once ACROSS AN EMBED boundary. A def declares `#m`
once and EMBEDS another def that also declares `#m` — both are decls of ONE def path, so
cue close-once-UNIONS them, but they are CROSS-operand (host operand + embed operand), so
kue `.conj`-meets → separate re-close → mutual reject → bottom. **Minimal repro:**
`#A: {#m: {a:1}}` then `#Use: {#A; #m: {c:3}; vis: #m}` → `out: #Use.vis` → cue
`{a:1,c:3}`, kue bottoms. Tripwire pin
`bug28_WITNESS_embed_cross_decl_close_once_wrongly_bottoms` (`TwoPassTests`; FLIP when
fixed).

**Why it's HARDER than Bug2-7 (the slice starts here, NOT a blank page):**
within-operand-vs-cross-operand (Bug2-7's lever) NO LONGER separates the union case from
the meet case — both `#m` decls are now cross-operand, yet must UNION. The discriminator
cue uses is same-def-PATH-decl (union) vs cross-conjunct VALUE-meet. **Soundness gate
(keep green):** the cert-manager `#data: [string]: string` closed pattern must stay
closed-MEET across an embed — a naive cross-operand union re-OPENS it (verified; pinned
by `bug28_embed_closed_pattern_field_stays_meet`). The sound fix carries def-PATH
provenance THROUGH the embed merge (in `forceClosureWithConjunctCore`'s `.structComp` arm
+ `meetEmbeddingsWithFuel`/`closeEmbeddedOver`, and the eager `.structComp` eval arm).
Spec basis: same as Bug2-6/2-7 (a definition's multiple declarations unify, close once —
including decls contributed by embedding).

After Bug2-8: **perf frontier (#7 / item-5)** — STILL gated (un-gates once argocd
resolves; profile `argo` against a resolving target then) → **item-6 LOW tail** (parser
strictness, A2-x/y, B2-A1/A2, `resolveEmbeddedDisjDefault` check, `release-linux.sh`
dirty-tree guard).

## AUDIT DUE — counter = 2 (Bug2-6 = slice 1, Bug2-7 = slice 2)

A two-phase audit (A code-quality, then B architecture/refactor) is DUE after this batch
per `slice-loop.md` (every 2–3 slices). Scope: the Bug2-6 + Bug2-7 def-merge diff
(`mergeDefinitionDecls`, `canonicalizeFields`, per-operand canonicalize in
`mergeConjOperands`, `mergeUnevaluatedFieldInto`). Do NOT invoke `/ace-audit`; follow
`slice-loop.md` Phase A then Phase B sequentially, one subagent each. Fold findings into
the plan as fix-slices.

## Release state

`v0.1.0-alpha.20260622` was CUT. A fresh alpha is **cadence-available but awaits user
greenlight** — Bug2-7 (`3361699`) + Bug2-6 (`ef824cb`) + Bug2-5 (`5fca57e`) + the Linux
scripts (`df40b62`) are unreleased in-tree. (CI/GitHub Actions banned; release = local
`scripts/release.sh` + `scripts/release-linux.sh`.)

## STANDING CONTEXT (full detail in CLAUDE.md + guides/slice-loop.md)

- Autonomy grant in effect; resolve forks by philosophy; commit/push on `main` (attended).
- Spec is authority; `cue` (`/Users/chakrit/go/bin/cue` v0.16.1) a fallible cross-check,
  never the gate. Correctness over byte-compat. kue binary: `.lake/build/bin/kue`.
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on main tree.
- Orchestrator = thin re-spawner; one subagent per slice; two-phase audit (A then B) DUE
  NOW (counter = 2). Per-slice duties: tests-first; log `cue-divergences.md`; flag
  `cue-spec-gaps.md`.
