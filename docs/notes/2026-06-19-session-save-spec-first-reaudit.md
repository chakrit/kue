# RESUME HERE — session save (ace-save, 2026-06-19)

Deliberate save point. Newest START-HERE; supersedes all prior breadcrumbs as the pointer.
Tree clean; `main` at `2ffd7f8`, **pushed** to `gh:main`. The authoritative live roadmap is
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) (the spec-first
backlog) + [`../spec/plan.md`](../spec/plan.md).

User note on this save: I was running ill on **max effort** (set mid-session) — restart next
session, likely at lower effort. Nothing lost; everything below is committed + pushed.

## THE BIG SHIFT THIS SESSION — spec-first reframe

The loop had drifted into treating **byte-identical-to-`cue`-v0.16.1 as the correctness
gate** — structurally bug-replicating. We **flipped the methodology** (durable in
`../guides/slice-loop.md` + `CLAUDE.md`): authority is **(1) the CUE spec → (2) lattice
first principles → (3) the `cue` binary as a fallible cross-check, never the gate.** Then ran
a **full 6-area re-audit** (A disjunctions, B closedness, C structs, D comprehensions, E
scalars/builtins, F manifest/modules). It found real spec-grounded bugs the old gate had
masked AND vindicated most of the engine as genuinely correct. Findings + ranked fix backlog
live in `spec-conformance-audit.md`. Two new catalogs: `../reference/cue-spec-gaps.md`
(spec-silent) distinct from `../reference/cue-divergences.md` (cue-wrong-vs-spec).

## DONE this session (all committed + pushed)

- **Methodology reframe** + full re-audit + the status page refresh (`../www/index.html` —
  current, has a "Code legend" decoding SC-/D#-/F-/RX-/Gap-/B# prefixes).
- **Regex family COMPLETE**: `RX-1a/b/c` — a real RE2 engine in `Kue/Regex.lean` (AST→Thompson
  NFA→Pike-VM, total/axiom-clean, submatch + `regexp.ReplaceAll`/`Find*` with Go `Expand`
  template), replacing the silently-wrong backtracking matcher. `RX-2b` (invalid pattern →
  `invalidRegex` bottom at every site), `RX-2c` (RE2 repeat cap 1000). Audited RE2-correct on
  a 96-case corpus diff.
- **Closedness cluster DRAINED**: `SC-1`/`SC-1c`/`SC-1d`/`SC-2` (closed struct stays closed
  through pattern-meet + nested + instantiation; `SC-2b` correctly DIVERGES from cue —
  recorded). `D#1a` (bottom comprehension guard propagates). `F-1` (`regexp` import), `F-2`
  (self-module `@vN` strip).
- **argocd narrowing chain**: `Bug2-3`/`Gap-2b` (structural list-vs-struct disjunction-arm
  pruning, via sound meet not a heuristic) + `Bug2-4` (let-local declare-and-read narrowing).

## IMMEDIATE NEXT STEPS (in order)

1. **Finish audit #14 — Phase B is PENDING.** Phase A landed (`2ffd7f8`: Bug2-3+Bug2-4
   verified clean; filed DRY-1). Phase B should do: whole-graph sweep + **plan-hygiene
   assessment** (plan.md ~1756 lines + audit doc ~1221 are BLOATED — distill to live state,
   history to log+git; the www page is already current) + **the strategic re-rank below**.
2. **STRATEGIC CALL (the user was about to weigh in when we saved):** argocd is **NOT
   unblocked** and is **6 narrowing layers deep** (Bug#1 → Gap-1 → Gap-2 → Gap-2b → Bug2-4 →
   now **Bug2-5**), each fix sound + *generalizing* but revealing the next, with wall-clock
   **climbing** (88→104→153s). cert-manager is fully correct. **My lean: PIVOT** — bank the
   argocd progress, do plan-hygiene → **D#2** (structural cycles; spec-mandated MISSING
   feature; DESIGNED, 2 slices), track Bug2-5 rather than reflexively grind layer 7. **Ask the
   user** their argocd priority first (stress-test-so-deprioritize vs must-export-keep-going)
   — it changes the ranking.
3. Then the ranked backlog (`spec-conformance-audit.md`): **D#2a/b** (structural cycles,
   DESIGNED), **Bug2-5** (argocd: disjunction-arm let-local narrowing from a *co-embedding
   sibling* — `injectLetLocalNarrowings` is force-arm-only, never fires on the `.disj`
   path; repro `/tmp/kue-ls-shape.cue`), **RX-2a** (`\D\W\S` in char-class), **DRY-1**
   (consolidate 3 fixpoint let-walkers into one `walkFollowedLets`), **SC-4** (LOW, likely cue
   artifact — spec-check first), MED tail (D#1b/c, D#3, SC-3, BI-1/2, F-3), the 4 spec-gap
   ratifications, A#6 (`containsBottom` fuel cap).

## CANONICAL PATHS (ground-truth — a Phase-A auditor got confused; do NOT re-litigate)

The prod9 real-app oracle targets ARE on this host:
- `/Users/chakrit/Documents/prod9/infra/apps/argocd.cue` and `.../cert-manager.cue`
- cue oracle: `/Users/chakrit/go/bin/cue` (v0.16.1) — READ-ONLY, cross-check only.
- kue binary: `.lake/build/bin/kue` (or `lake exe kue`).
All prior argocd/cert-manager measurements were real (no remote-fs confusion).

## STANDING CONTEXT (durable, do not relearn)

- Kue autonomy grant in effect (decide/proceed; resolve forks by philosophy; commit/push on
  `main`). **Spec is authority, cue is fallible** (the reframe). Correctness-over-performance.
- Orchestrator = thin re-spawner; one subagent per slice; **two-phase audit every 2–3 slices**
  (A then B); subagents commit at checkpoints. Per-slice duties now FOUR: tests-first; log
  divergences (`cue-divergences.md`); **flag spec gaps** (`cue-spec-gaps.md`); perf-guide.
- prod9 + cue caches READ-ONLY. NO `git checkout`/`restore`/`reset --hard` on the main tree
  (a subagent brushed this with a no-op `git checkout` — prompts now forbid it). Worktree
  isolation used for risky flips (B2, RX-1b) → FF main on success.
- Transient API 529s hit RX-1c (3×) — recovered, retried, nothing lost. Treat as retry-now.
