# RESUME HERE — eval-conformance front; L5 seed captured; docs re-baselined (2026-07-02)

The live START-HERE. Supersedes
[`2026-06-25-resume-b3d-registry-fetch-active.md`](2026-06-25-resume-b3d-registry-fetch-active.md).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md). Per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md).

## State

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
  - `def-disj-closedness-extra-field` (root2) — RED, `.known-red` (kue: ambiguous;
    spec+cue: bottom).
  - `single-closed-embed-extra-field` (root3) — RED, `.known-red` (kue: incomplete;
    spec+cue: field not allowed). Root pinned at `Kue/Lattice.lean:1224` per .afk.log.
  - `webapp-carrier-l5` — the L5 seed (was untracked `repro-l5.cue`), self-contained,
    `.known-red`, provisional `.expected` from cue's export.

## Open (ranked)

1. **chakrit's two decisions** (push + alpha are DONE — main pushed at `6fbc105`+,
   `v0.1.0-alpha.20260702` released with all 3 assets, 2026-07-02):
   - **L5+ campaign** — grind eval-conformance (attended safer; closedness-adjacent) /
     reprioritize to B3d-6b / accept current. L5's wild capture is DONE
     (pre-authorized); the fix-grind awaits the decision.
   - **Protocol amendments** — 8 proposed "keep going" improvements from the audit:
     [`2026-07-02-keep-going-protocol-critique.md`](2026-07-02-keep-going-protocol-critique.md).
     Do not apply until accepted/edited.
2. **Eval-batch audit — DISCHARGED (Phase A, 2026-07-02).** Audited `4b64502..HEAD` (the
   `4b64502..6c347b5` L3+rootA+L4 batch AND the a–e design-record fix-slices). a–e verified
   genuinely landed; root A + the for-non-iterable change scrutinized sound. ONE defect
   found: **PA-1** — `classifyForSource` masks a BOTTOM `for` source as incomplete (false
   "can't-happen" premise), retaining a dead disjunct where cue eliminates it (value-level
   soundness). Red seed committed + quarantined
   (`testdata/wild/for-bottom-source-masked-as-incomplete/`); fix-slice PA-1 filed in
   plan.md. Phase B (architecture) still owed for this batch.
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
4. **root2/root3 quarantined RED** — same closedness family as the L5 campaign; natural
   first targets if the grind is chosen.
5. **Pending school changes** (for `ace-school`, not from here): the TEST-HEALTH test
   convention (already flagged in `failure-modes.md`) + the audit meta-lesson
   "prose-only conventions rot; land conventions with migration + a script gate"
   (candidate `general-coding` addition).

## Standing context

- Spec is authority; `cue` v0.16.1 (`/Users/chakrit/go/bin/cue`) a fallible cross-check.
- Canary: **cert-manager only** (`apps/cert-manager.cue` under
  `/Users/chakrit/Documents/prod9/infra`, run from that cwd). argocd is GONE from that
  checkout — historical claim, do not re-verify.
- kue binary: `.lake/build/bin/kue`. Gate: `lake build` + `scripts/check-fixtures.sh` +
  `scripts/check-test-health.sh`.
- Relay from AFK run-2's self-flag: it ran `git checkout Kue/Eval.lean` (reverting its
  own in-session edit; no pre-existing WIP lost) — an envelope violation, disclosed for
  chakrit's awareness.
