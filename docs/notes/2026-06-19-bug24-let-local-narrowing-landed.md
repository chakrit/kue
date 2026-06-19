# Bug2-4 landed — let-LOCAL declare-and-read narrowing (argocd Mixin minimal repro)

**START HERE.** Supersedes `2026-06-19-bug23-gap2b-structural-disj-prune-landed.md` as the live
pointer. Bug2-4 fixes the let-LOCAL declare-and-read narrowing that the minimal `defs/parts.#Mixin`
repro hit. See `docs/spec/spec-conformance-audit.md` (Bug2-4 DONE writeup + the new **Bug2-5**
fix-slice) and the Bug2-4 implementation-log entry (tail of
`docs/reference/implementation-log.md`). Commit `3f7a761`, pushed to `gh:main`.

## What landed (cue is CORRECT here; Kue dropped the matched patch — spec-grounded)

The bug was NOT a transitive comprehension-read (Bug2-1 already follows lets to a fixpoint). It was
the shape where the read sibling is DECLARED INSIDE the same let that buries the comprehension —
`let _patch = { kind: string; for … { if kind == add.#kind {…} } }` (literally `#Mixin`'s `_patch`).
The guard's `kind` resolves to `_patch`'s OWN frame, where `kind` is also declared, so no embed-def
index names it → a host narrowing spliced at the def frame lands as a SIBLING the guard never reads →
the comprehension fires against `string` and the matched patch (`meta:"yes"`) drops.

**Fix (two helpers, both total + sound — only WIDEN/recover a narrowing, same envelope as Bug2-1):**
- `letPromotedReadLabels` — fixpoint over followed lets; surfaces the regular labels a let's OWN
  comprehension reads from its OWN frame (the labels it promotes to the embed). Wired into
  `embedComprehensionReadLabels` via the shared `embedReadLabelsClosing`.
- `injectLetLocalNarrowings` — in `forceClosureWithConjunctCore`; meets the use-operand's regular
  narrowings into a declare-and-read let-local before its comprehension expands.

## Verify (all green)

`lake build` (100 jobs) · `check-fixtures.sh` → `fixture pairs ok` (zero drift) · `shellcheck`
clean. **cert-manager (prod9, READ-ONLY) content-identical to cue v0.16.1** (`jq -S`, exit 0) — the
byte-identity GATE holds. 7 `native_decide` pins (label surfaced; unread not surfaced; cycle
terminates; disj end-to-end matched patch; real-conflict bottoms; guard-false drops) + fixture
`testdata/modules/mixin_let_local_narrowing` (matched patch surfaces; guard-false drops). Minimal
CLI repros all content-identical to cue: `/tmp/kue-patch4.cue` (two-level let), `/tmp/kue-mixin-min.cue`
(full Mixin with disjunction, def-host), `/tmp/kue-p4-three.cue` (three-level ref-indirection),
`/tmp/kue-p4-nestdecl.cue` (let-in-let nested declaration).

## argocd NOT unblocked — Bug2-5, a DISTINCT residual blocker (pre-existing, NOT a regression)

`kue export apps/argocd.cue` STILL bottoms (~153s, `conflicting values`). MEASURED. The residual
shape, faithfully reproduced in `/tmp/kue-ls-shape.cue`:

```
#ListenerSet: { #UseCertManager; kind: "ListenerSet"; apiVersion: "v1" }
out: #ListenerSet & {#name: "x"}
```

cue emits `meta:"yes"`; Kue drops it. This is `defaults.#ListenerSet = defs.#ListenerSet &
parts.#UseCertManager & {…}`: `defs.#ListenerSet` declares `kind: "ListenerSet"` at ITS def frame and
CO-EMBEDS `#UseCertManager` (→ `#Mixin`). The Mixin's `_patch.kind` must be narrowed by the SIBLING
def's `kind`, NOT by a use-operand. Because `#Mixin`'s body is the `listShape | structShape | error`
DISJUNCTION, the embed resolves on the `.disj` arm of `meetEmbeddingsWithFuel` (each arm `meet`s the
host AFTER the arm and `_patch`'s comprehension have evaluated), so the narrowing arrives too late and
`injectLetLocalNarrowings` (force `.structComp` arm only) never fires. This narrowing-injection into a
DISJUNCTION-arm-referenced let-local on the eager/disj path is a deeper mechanism than read-label
following.

Pre-existing: the fix is purely additive (only recovers narrowings, never drops fields), so the
ls-shape `meta`-drop existed before this slice. cert-manager remains the one fully-correct probed
real app.

Latent concern (for the architecture audit): CLI `kue export` and the in-Lean `exportJsonMatches`
test harness take DIFFERENT embed paths for the same def-host Mixin source — the harness reaches the
force `.structComp` arm (so `injectLetLocalNarrowings` fires for the theorem) but the CLI does not
(it fixes the def-host case via `letPromotedReadLabels` + the existing splice). Both produce correct
output; the path divergence should be reconciled.

## NEXT STEP → two-phase audit DUE, then Bug2-5, then plan-hygiene / D#2a

Bug2-4 is the 2nd fix-slice since audit #13 → **a two-phase audit is now at the 2–3-slice mark.**
Run it per `docs/guides/slice-loop.md` (do NOT invoke `/ace-audit`): (A) code-quality over the
Bug2-3 + Bug2-4 diffs — gate narrowness, `letPromotedReadLabels`/`injectLetLocalNarrowings` totality
and over-splice, AND the CLI-vs-harness path divergence flagged above; then (B)
architecture/refactor over the whole graph (the embed/force/disj paths are accreting splice variants
— Bug2-1, Gap-2b, Bug2-4, soon Bug2-5 — candidate for consolidation).

Then the ranked work:

1. **Bug2-5 (HIGH — the residual single argocd export blocker, undesigned).** Narrowing-injection
   into a disjunction-arm-referenced let-local on the eager/disj path of `meetEmbeddingsWithFuel`
   (the `.disj`-distribution arm) — the disjunction analogue of Bug2-4's `injectLetLocalNarrowings`.
   Pinned repro `/tmp/kue-ls-shape.cue`. Inject the co-embedding sibling-def narrowing into `_patch`
   BEFORE the arm's comprehension expands. After this, MEASURE `kue export apps/argocd.cue` again —
   if it exports content-identical to cue, that is the argocd real-app UNBLOCK (both probed prod9
   apps correct). If it bottoms on yet another shape, report it precisely + confirm pre-existing.
2. **Plan-hygiene pass** (was due before Bug2-4; rides in now) — distill `plan.md` + this audit doc,
   mark RX-2c DONE, move DONE entries to the log.
3. **D#2a / D#2b (HIGH, DESIGNED — structural-cycle detection + terminating-disjunct).**
4. **RX-2a (MED — in-class `\D`/`\W`/`\S`).**

prod9 reminder: caches + `apps/*.cue` are READ-ONLY; never mutate the environment outside the
project tree.
