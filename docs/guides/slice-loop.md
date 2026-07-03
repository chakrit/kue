# Slice Loop & Audit Cadence

The standing autonomous workflow for "keep going". Self-contained: the audit passes are
written here as procedures — **do NOT invoke the `/ace-audit` skill**; follow this guide.
The orchestrator is a thin re-spawner; every slice and every audit runs in a fresh
subagent. The orchestrator only does cheap done-checks and re-spawns.

## Design philosophy — type-system first (the audits enforce this)

Kue is in Lean 4 to make the type system do the work. This is the FIRST thing every audit
checks, not a nicety. In priority order:

1. **Make illegal states unrepresentable.** Encode invariants in the types so bad values
   cannot be constructed: precise `inductive`/`structure` over loose types guarded by
   runtime checks; a sum type over boolean/`Option` flags that admit nonsense
   combinations; newtype wrappers for distinct domains (ids, kinds, paths) so they can't
   be swapped; smart constructors where a raw one would admit junk. If a comment or branch
   says "this can't happen", the type is wrong — tighten it.
2. **Prefer ML / functional idioms.** Total functions over partial; `Except`/`Option`
   returns over hidden host-language failure; **exhaustive pattern matching with no
   catch-all `_` that silently swallows future constructors**; immutability; structural or
   fuel-bounded recursion over mutation. Push correctness into types + exhaustiveness, not
   into after-the-fact tests.
3. **Reach for dependent types / refinements where they buy real safety** (the standing
   grant) — not for their own sake. (Note the deliberate perf carve-out: `Value` omits
   `DecidableEq` because the kernel reduces it slowly; behavior is pinned by
   `native_decide`. Tightening representations is free; forcing kernel proofs is not —
   favor the former.)

## Cadence (repeat indefinitely)

1. Run **2–3 implementation slices** (one subagent each, one commit each).
2. **Code-quality audit** (one subagent; Phase A below).
3. **Architecture / refactor / cleanup audit** (one subagent; Phase B below).
4. Fold all findings into `docs/spec/plan.md` as fix-slices (ranked). Fix-slices count as
   implementation slices in the next round.
5. Go to 1.

Audits are mandatory at the 2–3-slice mark, not optional, and run **A then B,
sequentially** (both edit `plan.md`; parallel would collide). Don't let them stall forward
motion, but don't skip them.

Periodic, not every cycle:
- **Test/fixture organization pass** — when test files or `testdata/` have grown unwieldy,
  spend a slice reorganizing (group by subsystem, split oversized modules, dedupe
  fixtures, tidy `testdata/` layout). Phase B flags when it's due; schedule it as a slice.
- **Plan-hygiene pass** — when audit sections have accumulated in `plan.md` (superseded
  rankings, resolved decisions, completed fix-slice diagnoses), distill it back to the
  live roadmap: North Star + Working Principles, standing capabilities, ranked open
  backlog, pointers. History lives in `implementation-log.md` + git, so the plan sheds it.
  Also refresh `www/index.html` (the human-facing status page, served from repo root —
  separate from the agent design-record) to match the distilled plan.
- **Resilience / retrospective pass** — every *larger* while (roughly every 3–4 audit
  cycles, or once failures have accrued), review what broke *operationally* since the last
  retro — crashed/overloaded subagents, lost work, transient API errors, working-tree
  contention, late-caught misdiagnoses, flaky oracle/tooling — and record each with its
  guard in [`../reference/failure-modes.md`](../reference/failure-modes.md). Fold durable
  mitigations back into this guide and the subagent-prompt conventions so the same failure
  cannot recur. This is process hardening — the operational analog of the code audits.
- **Release** — see "Releases" below (~1 datestamped alpha/day, local script, no CI).

## Slice (per subagent)

Full workflow in fresh context: plan → TDD → implement → verify (`./scripts/check.sh` —
the single repo-local entrypoint: `lake build` + every `scripts/check-*.sh` gate by glob +
`shellcheck scripts/*.sh`) → commit/push to `gh:main` → update
`plan.md`, `implementation-log.md`, and the breadcrumb. Five standing duties: tests are
first-class (pin edges, not just happy path); log CUE divergences in `cue-divergences.md`;
flag CUE spec gaps in `cue-spec-gaps.md`; when a slice changes eval cost or surfaces a
slow/fast CUE pattern, update [`kue-performance.md`](kue-performance.md); and **retraction**
— a slice that reopens or supersedes a prior claim greps the docs and annotates every stale
site IN THE SAME SLICE (the fifth per-slice duty; canonical rule in CLAUDE.md § Recurring
misalignments).

**Subagent-prompt conventions (durable — copy into every slice/audit prompt):**

- **Cap build CPU.** `lake build` saturates every core and starves an interactive
  machine. `source scripts/lean-cap.sh` before any `lake build` (the gate scripts already
  do): it pins `LEAN_NUM_THREADS=2` (Lean threads + Lake job count) and wraps `lake` in
  `nice` so builds stay low-priority and core-bounded. Override upward on a dedicated
  build box (`LEAN_NUM_THREADS=8 …`).
- **Canary — two tiers.** The **sanitized, self-contained cert-manager fixture**
  (`testdata/realworld/cert-manager/{cert-manager.cue,.expected}`) runs IN-GATE via
  `scripts/check-realworld.sh` (auto-globbed by `./scripts/check.sh`) — portable, no
  external repo, part of the standard verify. The **LIVE-infra attended canary**
  (`( cd /Users/chakrit/Documents/prod9/infra && kue export apps/<app>.cue )`) is an
  OPTIONAL eval-core spot-check, explicitly NOT part of `check.sh` (external repo,
  non-portable, attended-only). When you run it: CUE module resolution is CWD-sensitive —
  from the Kue repo root, `apps/...` 404s and the corpus looks "absent" when it is not.
  "Not found" means wrong cwd, never a missing corpus; the corpus is READ-ONLY (never
  write into it).
- **Confirm the push, don't assert it:** before reporting "pushed", check the actual
  `git push` output shows `main -> main`. A "pushed" claim without that line is unverified —
  the orchestrator re-checks HEAD==upstream regardless (see Notes).
- **Real-app depth claims are EMPIRICAL, not design-level:** never report "one fix away" /
  "same fix" for a real-app blocker from design analysis alone — verify by actually running
  the canary export. An honest "one confirmed layer; unknown if more behind it" beats a
  confident design estimate (which has been falsified by the real app, twice).

**The CUE spec is the authority, NOT the `cue` binary.** Kue exists because `cue` is
frequently buggy; `cue` v0.16.1 is a *fallible reference implementation*, never the gold
standard. NEVER treat byte-identical-to-`cue` as the correctness gate — that gate is
structurally bug-replicating (it suppresses the very divergences Kue exists to fix). The
gate is conformance to the **CUE language spec**, and where the spec is silent, to
**lattice-theoretic first principles** (precise, total, illegal-states-unrepresentable —
the repo's reason to be). Use the `cue` binary (`/Users/chakrit/go/bin/cue`) only as a
cross-check, and on every behavior ask: *does the spec mandate this, or is it just what the
binary does?* When `cue` disagrees with the spec, the binary is WRONG → Kue follows the
spec, record in `cue-divergences.md`. When the spec is silent, `cue`'s behavior is an
artifact → Kue makes a principled choice, record in `cue-spec-gaps.md` (even when Kue
matches `cue` — matching an artifact is lower-confidence, not a mandate). Check the claim
against the actual CUE spec before matching OR diverging. (One narrow legitimate use of the
oracle as a *data source* — generating committed data for an externally-standardized,
non-`cue`-buggy domain like the Unicode case table — is governed by
[the oracle-as-data-source decision](../decisions/2026-06-20-oracle-as-data-source.md); it is
NEVER a correctness gate for CUE semantics.)

**Wild-caught regressions → `testdata/wild/` fixture FIRST, then fix.** The canaries are a
tiny sample; the moment a *real* situation surfaces a divergence outside a planned slice —
a prod9 app export that errors or differs, a manual exploration, an orchestrator/user
stumble — it is captured as a regression fixture *before* any fix. This is the highest-signal
test we get (the wild corpus the curated fixtures miss), and the rule is test-first even
here: the fixture must REPRODUCE (fail) first, the fix turns it green, and it stays a
permanent guard so the same real-world case can never silently regress.

- **Home:** `testdata/wild/<slug>/` — AUTO-DISCOVERED by `check_wild_fixtures` in
  `scripts/check-fixtures.sh` (every non-quarantined dir is enforced; a `.known-red`
  marker quarantines a captured-but-unfixed case). No `FixturePorts` registration.
  Consequence: wild fixtures are enforced ONLY by the shell gate — `lake build` never
  sees them, so a slice is not green until `check-fixtures.sh` passes too.
- **Minimal + self-contained:** lift the offending construct OUT of any private dep — the
  repro must need no registry/network/prod9 corpus (inline the few lines that trigger it).
  A `<slug>.cue` (+ a tiny `cue.mod` module repro only if the bug is import/module-shaped)
  plus its expected output.
- **Expected value is SPEC-adjudicated, never `cue`-matched.** A `bottom` or a diff vs `cue`
  does NOT establish Kue is wrong — `cue` is the fallible reference (see the spec-authority
  rule directly above); `cue` accepting something may be `cue`'s bug. Adjudicate the case
  against the CUE spec (or lattice-theoretic first principles when silent), pin the
  spec-correct value, and if `cue` disagrees record it in `cue-divergences.md`. Only after
  adjudication is the fixture's `expected` written.
- **Provenance line:** record where it came from (source app + date) alongside the fixture,
  so its real-world relevance stays traceable.
- **Then fix as a normal slice:** the failing `wild/` fixture IS that slice's red; green it,
  audit edges around it, done.

**Commit at checkpoints, not only at the end.** A subagent that crashes or hits a transient
API error loses ALL uncommitted work — this has happened (~89 tool-uses lost to an
"Overloaded" error mid-audit, nothing committed → total re-run). So commit at natural
internal seams: the design sub-spike into `plan.md`, each independently-green sub-fix, and
audit findings BEFORE composing the final summary. "One slice per commit" stays the default
for clean history, but a few checkpoint commits on a long or multi-step slice beat risking
total loss. On a crash — including a HOST-process exit that destroys in-process state — the
orchestrator recovers from GIT STATE, never from memory: `git rev-parse HEAD` vs `@{u}` +
`git status --porcelain` against the last known-good. Nothing committed since known-good AND
tree clean → the slice never landed → FULL re-run; partial commits → re-run only the lost
remainder. Treat transient API errors / 0-token rate-limit returns as retry-NOW, never
wait-it-out. See [`../reference/failure-modes.md`](../reference/failure-modes.md).

**Docs convention — show the CUE.** Any doc that references a CUE *language* feature
includes a short (2–4 line) CUE code block showing the concrete construct, so a reader
sees the syntax it maps to. Verify each block parses/evaluates in `cue` before shipping —
never ship invalid or invented syntax. Engine-internal references (perf, memoization,
fuel, module refactors, test-org) get NO block — a CUE snippet there is misleading.

**Correctness over performance** (see
[the decision](../decisions/2026-06-18-correctness-over-performance.md)): never ship a
perf optimization that can return a wrong value. A perf slice needs byte-identical
fixtures + a soundness argument; if soundness cannot be guaranteed, **stop and report**
(file the design + the hole), do not ship it. But basic cases must stay usable — slowness
is a tracked bug, fixed only by sound optimization.

## Phase A — Code-quality audit (the diff/batch since the last audit)

**FIRST STEP (before any new findings): audit the last audit.** Diff the previous audit's
filed fix-slices against landed commits — for each, confirm it actually landed (a commit,
not just a plan entry), then re-rank or EXPLICITLY DROP it. "Scheduled in the plan" decays
to zero unless it re-enters the active queue. Only after this reconciliation do you file new
findings. (Formalizes the CLAUDE.md guard *"Audits verify that previously-filed fix-slices
actually landed."*)

Scope: the slices landed since the previous audit. Check:
- **Correctness** — behavior matches CUE/oracle; edge + error cases handled, not just the
  happy path.
- **Totality** — no unjustified `partial def` (the parser is the standing exception);
  fuel bounds provably sufficient.
- **Illegal-states-unrepresentable (the philosophy above — check it FIRST)** — does the
  new code use the tightest type that fits? Flag loose `String`/`Nat`/`Bool`/`Option`
  representations that should be sum types, newtypes, or refinements; flag any
  constructor/record that admits a nonsense combination; flag "can't happen" branches that
  a better type would erase. Every NEW `Value`/AST constructor handled at EVERY match site
  with NO catch-all `_` silently swallowing it; non-output markers (letBinding, thisStruct)
  excluded from `Format`/`Manifest` output. Partial functions that could be total → finding.
- **DRY / reuse** — no duplicated logic that should share a helper.
- **Test strength** — theorems/fixtures pin real behavior incl. edges, not smoke; every
  new fixture has BOTH a `testdata/.../.{cue,expected}` pair AND a `FixturePorts` entry.
- **Skill compliance** — `general-coding` rules (hard blockers); naming/readability.
- **Spec accuracy** — `plan.md` / `compat-assumptions.md` / log match the code.

Output: fold findings into `plan.md` as fix-slices. Apply only LOW-RISK fixes inline; if
you do, re-run the full verify gate and commit.

## Phase B — Architecture / refactor / cleanup audit (the whole module graph)

**Every ~3rd audit cycle, rotate infrastructure into scope.** On that cycle Phase B
explicitly audits the GATES and TOOLING themselves — the `scripts/check-*.sh` gates, the
`check.sh` aggregator, wild/fixture auto-discovery, and the release tooling — not just the
module graph. The gates are code too and rot the same way; a cheap grep that stopped
matching, a discovery glob that silently skips a dir, or a stale release step is exactly the
class of drift the script gates exist to prevent. File findings as fix-slices like any other.

Scope: cross-cutting design, broader than the recent diff. Check:
- **Type-system leverage / ML idioms (the philosophy above — a top-level concern here).**
  Across the module graph, where are loose types carrying invariants that the type system
  could enforce? Candidates to propose as tightening fix-slices: stringly-typed data that
  should be a sum type; separate fields that should be one indexed/refined type; raw ids
  that should be newtypes; `Option`+invariant that a refined type subsumes; wildcard
  matches that hide cases; partial functions reducible to total. Push illegal states out
  of the representation — this is the repo's reason to be in Lean.
- **Module boundaries & layering** — import edges sane (e.g. `Builtin → Decimal`, never
  `Builtin → Eval`); no cycles; one clear responsibility per module.
- **Abstraction quality** — right representations; illegal states unrepresentable at the
  type level; leaky or missing abstractions; modules that have outgrown their home.
- **Refactor / cleanup** — dead code, deprecated APIs (e.g. `String.dropRight`),
  duplication ACROSS modules, functions in the wrong place.
- **Simplification** — complexity that can be removed; over-engineering.
- **Tech-debt & consistency** — divergent patterns across similar code; stale TODOs;
  `compat-assumptions` entries that have accumulated and should become real slices.
- **Test/fixture health** — coverage gaps at the seams; oversized test modules or messy
  `testdata/` that warrant the organization pass; fixture-harness debt.
- **Performance-guide currency** — does [`kue-performance.md`](kue-performance.md) reflect
  current perf reality (new slow patterns surfaced, mitigations landed, stale
  known-limitations)? Update it inline or file the gap.

Output: fold findings into `plan.md` as architecture fix-slices (ranked); large refactors
become their own planned slices. Apply only low-risk cleanups inline (re-verify + commit).

## Open decisions — single home + precedence

Two durable records carry state: the **breadcrumb** (`docs/notes/…` START-HERE) and the
**plan** (`docs/spec/plan.md`). To stop the two-authorities drift (the plan once said an
item was self-startable while the breadcrumb said it awaited chakrit):

- **OPEN DECISIONS live in ONE place — the breadcrumb's "Open" block.** `plan.md` POINTS
  to them; it never holds a second copy of an open decision's state.
- **Precedence when they disagree:** **what's-NEXT → the breadcrumb wins** (it owns the
  ordered open queue and the next-step pointer); **what's-TRUE → the plan wins** (it owns
  the roadmap, capabilities, and resolved rulings). A conflict is a bug in whichever doc
  lost its lane — fix it in the same slice you notice it.

## Blind-grind circuit breaker

Each campaign names its **target metric** up front (e.g. an L-series grind = the specific
RED seeds going green; a real-app push = the prod9 drop-in count). After **~3 consecutive
fix-slices with ZERO movement in that metric**, a MANDATORY reassessment checkpoint fires:
re-scope, bisect from a different angle, or escalate — OR record an explicit justification
to continue (some correct prerequisite work legitimately shows no needle movement, so this
is a forced stop-and-think, NOT an auto-halt). Attended → escalate to chakrit; AFK → log
the checkpoint to `.afk.log` (what the metric is, the 3 slices that didn't move it, and the
re-scope/continue call) and proceed only on a recorded justification.

## Releases (local only — CI/GitHub Actions is BANNED)

- Cadence: roughly **one alpha release per day**, datestamped where it makes sense
  (e.g. `0.1.0-alpha.YYYYMMDD`). More often only on a notable milestone.
- Mechanism: `scripts/release.sh <version>` — builds the host arm64 binary, publishes the
  GitHub Release asset via `gh`, and patches + pushes the `chakrit/homebrew-tap` formula.
  No CI, no Actions, ever. Requires a clean working tree (commit first).
- Cut from current `main` HEAD; alpha quality is fine to ship with documented known gaps.

## Notes

- The orchestrator's only between-step job is the cheap done-check (git state + one
  build/fixture run), never the deep work. The done-check is MANDATORY per slice and
  includes `git rev-parse HEAD` == `@{u}` — equal is the only "pushed"; a subagent's "pushed"
  claim is never trusted on its word (HEAD has been caught ahead of upstream).
- **Independently re-verify high-stakes claims — don't just trust the report.** Routine
  slice reports the orchestrator confirms with the cheap done-check; but MILESTONE-grade
  (real-app byte/content-identical drop-in), SOUNDNESS-grade (perf-fix byte-identity, cache
  correctness), PUSH, and RELEASE claims the orchestrator re-runs DIRECTLY — re-export the
  canary + `jq -S` diff, re-run the build/fixture gate, re-check the published asset/formula
  — before the claim enters the durable record. A high-stakes subagent claim is a hypothesis,
  not a fact.
- No manual `/ace-save` or `/clear` between slices — the subagent boundary gives fresh
  context; the breadcrumb gives continuity.
- **"User-gated" is a high bar — don't inherit it from audit caution.** Audit verdicts of
  "user-gated / human-signs-off" are usually over-caution; re-examine by philosophy before
  deferring — most resolve autonomously. (A "human-signs-off" normalizer dedup turned out to
  be a vacuous-marker soundness *analysis* (AD2-1); a "needs-a-Float-model" builtin was
  decimal-not-Float, no fork at all (BI-2-residual).) Surface a fork to the user ONLY when
  the philosophy is genuinely silent AND the choice is expensive to reverse. Default:
  resolve-and-proceed.
