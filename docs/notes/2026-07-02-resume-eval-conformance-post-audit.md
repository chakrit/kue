# RESUME HERE — eval-conformance front; 2026-07-02 audit campaign FULLY DISCHARGED

The live START-HERE. Supersedes
[`2026-06-25-resume-b3d-registry-fetch-active.md`](2026-06-25-resume-b3d-registry-fetch-active.md).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md). Per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md).

> **Doc precedence (amendment A5):** this breadcrumb owns what's-NEXT (the "Open" block
> below is the single home for open decisions); the plan owns what's-TRUE. On disagreement,
> breadcrumb wins for next-step, plan wins for roadmap/rulings. See
> [`../guides/slice-loop.md`](../guides/slice-loop.md).

> **2026-07-02 audit + fix-slice campaign COMPLETE.** The full-repo audit (design record,
> reference/guides, code/skill-compliance, fixtures) and BOTH eval-batch audit phases (A
> correctness, B architecture) are done, and every fix-slice they filed has landed:
> repair batch (a)–(e), PA-1, B-AUDIT-refold-1, PB-1, PB-2, PB-3 — all DONE. **No
> audit-filed fix-slice remains open.** The **protocol amendments (A1–A8) are now APPLIED
> (2026-07-03)** — see the Open block. The **L5 grind campaign is COMPLETE (2026-07-03):**
> all three RED seeds (root2, root3, webapp-carrier-l5) are GREEN and gate-enforced — the
> declared seed-metric is met. What's genuinely next is pulling from the standing backlog /
> plan-only roadmap (B3d-6b MVS wiring, item-6 LOW list). Nothing below this line is a
> blocker; it's the closed record.

## State

- **B2-A2 landed (2026-07-02, item-6 LOW).** Promoted the two struct pattern/tail
  cross-combos that were `native_decide`-only into real testdata:
  `definitions/{tail_pattern_unify,both_tails_pattern_unify}` pairs + `FixturePorts`
  entries. Covers tail-LEFT × patterns-RIGHT and both-tails+patterns; cue v0.16.1 / kue
  eval / Lean `meet` all agree (`{a:5}` open; `{a:5,b:"hi"}` open). No latent bug; pure
  coverage, no eval-core change. Moved to item-6 "Done" sublist.
- **Full-repo audit + repair (2026-07-02).** Four parallel auditors (design record,
  reference/guides, code/skill-compliance, fixture infrastructure) swept everything;
  repairs landed the same day. Code health confirmed strong: zero
  `sorry`/`axiom`/`unsafe`, IO layering clean, shellcheck clean, red-first wild protocol
  held 5/5. The dominant defect class was **doc drift + prose-convention rot**, now
  repaired and guarded.
- **Docs re-baselined.** plan.md distilled 1734 → 697 lines (Status header, resolved
  items collapsed to ruling+pointer); stale "correctness DONE / backlog EMPTY" milestone
  blocks carry RETRACTED-2026-06-28 pointers; architecture.md "Where We Are" rewritten
  (the banned Float recommendation removed, B3d/EvalOps marked done);
  spec-conformance-audit.md backlog corrected (perf #7 = WON'T-FIX; live correctness
  backlog = plan § Current front); 6 missing audit entries recovered into the
  implementation-log; lean4-guide / cue-language-guide de-staled ("cue as oracle" →
  spec-authority); distribution ADR marked `revised`.
- **Guard-rails written.** CLAUDE.md § "Recurring misalignments" — ten binding rules
  distilled from what prior autonomous passes got wrong (convention-lands-with-migration,
  script gates over prose, `| _ =>` ban in Value-producing matches, `partial def`
  waivers, no file inventories in prose, timeless comments, audits get log entries,
  wild auto-discovery + committed red seeds, retraction pointers, cert-manager-only
  canary).
- **Fixture gate hardened** (`check_wild_fixtures`): enumerates `testdata/wild/*/` dirs
  (a missing/typo'd expected file now FAILS instead of silently vanishing); new
  `<slug>.expected.err` pins spec-correct-BOTTOM outcomes; kue exit codes checked.
- **Red seeds committed** (were log-file prose / untracked scratch):
  - `closed-disj-both-arms-reject-extra` (cl2) — **GREEN, enforced**: fixed en passant
    by the root-A/L4 closedness work; kue now bottoms, matching spec + cue.
  - `def-disj-closedness-extra-field` (root2) — **GREEN, enforced (2026-07-03, L5 slice 1)**.
    The `Lattice.lean:1224` root-cause pin was a RED HERRING: closedness IS preserved through
    the disjunction distribution (verified vs cue across def-ref/`close()`/mixed-arm variants).
    The seed's RED was a measurement artifact — the carrier `M` was a *regular exported* field
    whose own inherent ambiguity (`{p:int}|{q:int}`) surfaced before `out`'s correct bottom
    (cue errors on `M` identically). Corrected to a HIDDEN def (`#M`); `out` now bottoms as
    expected. No `Lattice.lean` change. See its PROVENANCE.md retraction.
  - `single-closed-embed-extra-field` (root3) — **GREEN, enforced (2026-07-03, L5 slice 1)**.
    Same artifact: `M: {#A}` = `{p:int}` (incomplete) exported before `out`; embed-close was
    already sound (`{#A} & {p,r}` bottoms, covered by bug210). Corrected to `#M`. No code change.
  - `webapp-carrier-l5` — **GREEN, enforced (2026-07-03, L5 slice 2)**; `.known-red` removed.
    RETRACTION: the "distinct root — `Self`-ref host embedding an `error()`/`⊥`-arm disjunction
    (`Eval.lean` splice), NOT closedness" framing was WRONG. Bisect refuted it — the disjunction
    and `error()` arm are RED HERRINGS. Minimal trigger: a sibling-field-ref def `&`-met with an
    ellipsis-only (OPEN) embed (`#Ctl:{name:"x",spec:name,...}` / `out:#Ctl & {...}`). Root cause:
    `evaluatedStructOperand?` (`Kue/EvalBase.lean`) mapped a `.defOpenViaTail` (explicit-`...`, i.e.
    OPEN) operand to closedness `false`, spuriously closing the OPEN host to the operand's empty
    label set so the sibling-ref field bottomed as `fieldNotAllowed`. Fix: an open-tail operand
    contributes `true` — closedness ANDs, so `#Closed & {...}` still stays closed (soundness guard
    fixture pins it). It IS closedness-family, contra the old note. See its PROVENANCE.md.

## Open (ranked)

1. **L5 campaign — COMPLETE (2026-07-03).** All three RED seeds (root2, root3,
   webapp-carrier-l5) are GREEN and gate-enforced; the declared target metric (those seeds
   going green) is MET. root2/root3 were measurement artifacts (L5 slice 1); webapp-carrier-l5
   was a genuine over-rejection in `evaluatedStructOperand?` (L5 slice 2, fixed). Next work
   comes from the standing backlog / plan-only roadmap (B3d-6b MVS wiring, item-6 LOW list) —
   chakrit's call on which to pull.
   - **Protocol amendments — APPLIED 2026-07-03 (was a parked decision, now discharged).**
     All 8 keep-going amendments (A1–A8) landed; the proposal note
     [`2026-07-02-keep-going-protocol-critique.md`](2026-07-02-keep-going-protocol-critique.md)
     carries an APPLIED retraction stamp. Batch record in the implementation-log.
   - **Queued for push (envelope-blocked, awaiting chakrit).** The 11 pre-amendment commits
     + all amendment commits (`63c05d3`, `57fc772`, `efb6cae`, `a4e7390`, `ca4a322`, + the
     governance commit) are committed on `main` but UNPUSHED — this run was AFK. Push waits
     for chakrit.
2. **Eval-batch audit — COMPLETE (both phases, 2026-07-02).** Phase A (`6197dc3`,
   diff-scoped correctness): audited `4b64502..HEAD`; a–e verified landed; root A + the
   for-non-iterable change sound. ONE defect: **PA-1** — `classifyForSource` masks a BOTTOM
   `for` source as incomplete (false "can't-happen"), retaining a dead disjunct where cue
   eliminates it (value-level soundness). **PA-1 FIXED (2026-07-02):** `ForSourceClass`
   gained a `bottom` verdict, `classifyForSource` routes bottoms to it, the `.forIn` caller
   propagates it — wild seed GRADUATED (green, `.known-red` removed), 3 new fixtures, cue
   agreement on all forms (no divergence). **Phase B (architecture,
   whole graph) — DISCHARGED, HEALTHY.** Module graph clean acyclic DAG (all
   `architecture.md` edges re-verified); code-health pristine (no dead code / deprecated
   APIs / stray partials). Three fresh findings filed: **PB-1** `Eval.lean` = 4609 >
   the 4500 DefDeferral-carve trigger (carve the ~600-line deferral tier); **PB-2**
   `TwoPassTests`/`EvalTests` (1763/1743) near the 1800 cap → test-org pass now DUE;
   **PB-3** `architecture.md` layer-numbering doc note (LOW). Ranking: PA-1 (DONE) →
   B-AUDIT-refold-1 (DONE) → PB-1 (DONE) → PB-2 → PB-3. **PB-1 landed (2026-07-02):
   evaluator carved into a 3-module chain `EvalBase → EvalDefer → Eval` (`Eval.lean` 4636 →
   1517, keeps the unsplittable core-force `mutual`; `EvalDefer.lean` = def-deferral tier +
   `hasSelfRefAtDepth` mutual = 692; `EvalBase.lean` = shared base machinery = 2451). FINDING:
   the tier is not independently separable (depends on base helpers the core force also uses →
   isolating it alone cycles); `EvalBase` breaks the cycle, hence 3 modules not 1. Byte-identical:
   build clean, full regression + wild green, cert-manager jq-S delta = 0.** **PB-2 landed
   (2026-07-02):** `TwoPassTests` 1763 → 1516 (held-residual/MEET-RESID/RESID-MASK family →
   `ResidualTests.lean`, 21 thms; 137 = 116 + 21); `EvalTests` 1743 → 1468
   (closedness/pattern/SC-2/SC-4 family → `ClosednessTests.lean`, 28 thms; 214 = 186 + 28);
   pin-counts conserved, org-only, both new modules TEST-HEALTH-compliant + wired into
   `Kue/Tests.lean`; deferred `testdata/cue` sub-grouping stayed dropped. **PB-3 landed
   (2026-07-02):** `architecture.md` §5 got the marshalling-builtin forward-edge clarification
   + the omitted `Json → Manifest` / `Yaml → Json` / `Manifest → {Format, Lattice}` edges.
   **→ the 2026-07-02 Phase A/B audit fix-slice batch is now FULLY DISCHARGED.**
3. **Audit fix-slices** in plan.md Live Backlog. **(a) TEST-HEALTH retrofit +
   `scripts/check-test-health.sh` gate — DONE (2026-07-02):** all 33 hand-authored test
   modules converted to `--` headers, per-section `#check` tripwires added, gate enforces
   (headers / tripwire presence / ≤1800-line cap) and is wired into the verify sequence;
   `FixturePorts.lean` generated-data exempt. **(b) value-producing catch-all enumeration —
   DONE (2026-07-02):** scope audit found only 13 in-scope sites (all `Eval.lean`;
   Lattice/Builtin catch-alls all scrutinize `Prim`/`Kind`/`Option`/`List`, not `Value`),
   each `| _ =>` replaced by a `|`-joined explicit ctor enumeration; scalar-embed fallback
   hoisted to a `let` thunk to keep enumerated arms recursion-free (else `decreasing_by`
   blows up). Pure refactor, fixtures/health green. **(d) `for`-over-non-iterable
   re-adjudication under E#4 — DONE (2026-07-02):** cue is spec-correct (hard-errors a
   non-iterable source); Kue's zero-iter was wrong. Replaced `comprehensionPairs` with a
   three-way `classifyForSource` — a decidably-non-iterable source (scalar `.prim`/carrier,
   abstract scalar `.kind`, `.stringRegex`, numeric `.boundConstraint`) is a type error
   (`.nonIterableSource`), a genuinely-open source (`.top`, unresolved ref/disj) DEFERS. Matches
   cue on all cases; `cue-divergences.md` zero-iter row REMOVED (→ Resolved). New pins + 3
   fixtures. **(c) `Module.lean` partial-def cleanup — DONE (2026-07-02):** all 4 `partial
   def`s carry a one-line waiver; `parseAndBindFiles`/`collectBindings` list self-recursion
   rewritten as total `for` loops (they stay waived-partial only for the inherent mutual cycle
   with `loadPackage`). **(e) timeless-comment sweep — DONE (2026-07-02):** 7 audit-listed
   sites + all clear code-history comments in non-test source fixed; ~20 test-file comments
   deferred to (e-followup) in plan.md. **The 2026-07-02 audit fix-slice batch (a)–(e) is now
   COMPLETE.**
4. **root2/root3/webapp-carrier-l5 — ALL GRADUATED GREEN (L5 campaign complete).** root2/root3
   (L5 slice 1, 2026-07-03): no closedness bug existed; the `1224` pin was stale (measurement
   artifacts). webapp-carrier-l5 (L5 slice 2, 2026-07-03): a genuine over-rejection —
   `evaluatedStructOperand?` (`Kue/EvalBase.lean`) mis-mapped an open-tail operand to closed,
   closing the open host. Fixed; the "`Self`-ref/error-arm splice in `Eval.lean`" framing was a
   RED HERRING (see the red-seed list above). All three seeds gate-enforced.
5. **Pending school changes** (for `ace-school`, not from here): the TEST-HEALTH test
   convention (already flagged in `failure-modes.md`) + the audit meta-lesson
   "prose-only conventions rot; land conventions with migration + a script gate"
   (candidate `general-coding` addition).

## Standing context

- Spec is authority; `cue` v0.16.1 (`/Users/chakrit/go/bin/cue`) a fallible cross-check.
- Canary: **cert-manager only** (`apps/cert-manager.cue` under
  `/Users/chakrit/Documents/prod9/infra`, run from that cwd). argocd is GONE from that
  checkout — historical claim, do not re-verify.
- kue binary: `.lake/build/bin/kue`. Gate: `./scripts/check.sh` (single entrypoint —
  `lake build` + every `scripts/check-*.sh` by glob + `shellcheck scripts/*.sh`).
- Toolchain: `leanprover/lean4:v4.31.0` (bumped from v4.29.1 2026-07-03; clean, canary
  byte-identical). Build ONLY via `./lake` (caps to 2 cores + `nice`) — never bare `lake`.
- Relay from AFK run-2's self-flag: it ran `git checkout Kue/Eval.lean` (reverting its
  own in-session edit; no pre-existing WIP lost) — an envelope violation, disclosed for
  chakrit's awareness.
