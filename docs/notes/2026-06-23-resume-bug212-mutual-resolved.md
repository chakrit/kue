# RESUME — Bug2-12 MUTUAL RESOLVED; audit counter = 2 (audit DUE next slice); next = per-eval-cost / SC-4 (2026-06-23)

Live START-HERE; supersedes `2026-06-23-resume-bug212b-resolved.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md). Spec-conformance backlog:
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Genuinely-open.
Per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md).
Served status page: [`../../www/index.html`](../../www/index.html).

## State — audit counter = 2. Bug2-12 MUTUAL LANDED.

**Bug2-12 MUTUAL RESOLVED** (mutual-recursion closed-def closedness — the last Bug2-12
tail). `#A: #B & {a:1}`, `#B: #A & {b:2}` is a CLOSED mutual cycle. ADJUDICATED: a def's
closed allowed-set is the TRANSITIVE union of all cycle members' declared labels
(`#A = #B & {a} = #A & {a,b}` ⟹ `allowed(#A) = {a,b}`). Closedness BOUNDS use-site
additions; it NEVER rejects a label the def itself declares. So the principled answer:
`#A & {a:1,b:2}` ADMIT; `#A & {c:3}` REJECT (`c` ∉ {a,b}); bare `#A` → `{a:1,b:2}`.

- **Kue was CASE (b) — UNDER-CLOSE:** admitted `{a,b}` (correct) BUT also admitted a
  genuine extra `c` (bug). Root cause: the cross-def back-ref bottoms `#B` via D#2,
  dropping its closedness, so `#B & {a}` resolved OPEN. **FIXED** via new total helper
  `defSlotInClosedCycle` (`Eval.lean`, above `flattenConjDefRef`): the `close` gate now
  fires for ANY depth-0 def→def cycle reaching the slot (not only a DIRECT self-ref). The
  transitive flatten already pulls every cycle member's literals into `expanded`; the
  existing Bug2-12b union-then-close-once machinery fixes the allowed-set to `{a,b}`. No
  new closure mechanism — just gate widening + the cycle detector (`defConjRefSlots`
  companion).
- **`cue` v0.16.1 is BUGGY — OVER-REJECTS** even the def's OWN declared field
  (`#A.a: field not allowed`), closing `#B` prematurely mid-cycle. Recorded as a
  cue-divergence ("Mutual-recursion closed def rejects its OWN declared field"), NOT
  matched. Kue conforms to the lattice-principled answer.

Witnesses all == principled: `#A & {a:1,b:2}` admit; `#A & {c:3}` REJECT (`c: _|_`); bare
`#A` → `{a:1,b:2}`; 3-way admit `{a,b,c}` + reject `d`; open-tail in one member reopens
(admits `c`); one-way non-rec chain (`#A:#B&{a}`, `#B:{b}`) stays REJECT (not a cycle).
D#2 `#L:{n,next:#L}` still bottoms; no-literal mutual cycle (`#A:#B`, `#B:#A`) still `_`.
The self-rec Bug2-12/2-12b pins + 5 Bug2-6 + 7 Bug2-9 close-once pins STAY GREEN.
`defSlotInClosedCycle`/`defConjRefSlots` total, no `partial`/`sorry`/axiom. Full gate
green (`lake build` + `check-fixtures.sh`); canaries cert-manager + argocd jq-S=0 (prod9
zero recursive defs — neutral). 8 inline pins + 3 internal-format fixture pairs.

## NEXT — pick the next leader (resolve by philosophy; none soundness-bearing)

**Audit cadence: counter = 2.** Two-phase audit is **DUE after the next slice** (per
[`../guides/slice-loop.md`](../guides/slice-loop.md)) — Bug2-12b (counter 1) + Bug2-12
MUTUAL (counter 2) since the last audit closed. Run the sequential audit (A code-quality →
B architecture/refactor) after the next 1 slice, not now.

Spec-conformance-HIGH is fully DONE. The whole Bug2-12 family (self-rec + 2-12b + MUTUAL)
is now RESOLVED. perf #7 frame-sharing is WON'T-FIX (~0.05% ceiling, unsound where
non-empty). Remaining ranked candidates (resolve by philosophy):

- **per-eval-cost slice** (the live perf frontier) — lower the per-eval CONSTANT / eval
  COUNT over the genuinely-large distinct population (argocd ~50s, cert-manager ~12s). NOT
  cross-env sharing (closed). The open principled lever. Detail: `kue-performance.md`.
- **SC-4** (LOW, spec-gap-first — nested hidden/let closedness on direct def-meet; cue
  internally inconsistent, spec-check FIRST, do not reflexively match cue).
- **item-6 LOW tail** in `plan.md` (`module-file-scoped-imports`, parser strictness,
  `release-linux.sh` dirty-tree guard, concurrent-release tap-race, A2-x/y, B2-A1/A2 —
  none soundness-bearing).

## Live state end
