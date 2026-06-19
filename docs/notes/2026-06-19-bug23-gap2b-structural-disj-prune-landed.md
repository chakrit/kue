# Bug2-3 / Gap-2b landed — structural list-arm-vs-struct-host disjunction prune

**START HERE.** Supersedes `2026-06-19-rx1c-submatch-replaceall-find-live.md` as the live
pointer. Bug2-3 fixes the disjunction-pruning class that was the designed "last argocd
blocker." See `docs/spec/spec-conformance-audit.md` (Bug2-3/Gap-2b DONE writeup + the new
Bug2-4 fix-slice) and the Bug2-3 implementation-log entry (tail of
`docs/reference/implementation-log.md`). Commit `d9f66ca`, pushed to `gh:main`.

## What landed (cue is CORRECT here; Kue was under-pruning — spec-grounded)

A def embedding a STRUCTURAL disjunction (`listShape | structShape`, discriminated by
list-vs-struct SHAPE, not a regular label), embedded one layer down (`#U: {#M}`) and
force-narrowed by a sibling regular OUTPUT field the arms lack: the host's regular fields
reached the disjunction only as a SIBLING, never met INTO the list arm as a value, so the sound
`list & {regular fields} = ⊥` prune never fired → both arms survived → ambiguous bottom.

**Fix (the design's lever, GATED):** `embedBodyEmbedsDisj` detects a disjunction-embedding body
(a `.disj` in `cs`, or a depth-0 `.refId` to a let slot holding a `.disj`). When it fires,
`spliceOperandForEmbed` routes ALL the host's regular OUTPUT fields into the embedded arms (not
just the narrow comprehension-read/discriminator labels). The EXISTING `meet`-over-`.disj`
distribution then prunes a list-shaped arm against the struct host via the SOUND type-conflict
meet; a struct-compatible arm survives untouched (meet idempotent on a field it already
carries). **The prune is the meet primitive, NOT a shape heuristic** — two struct-compatible
arms stay ambiguous (cue-exact).

## Verify (all green)

`lake build` (100 jobs) · `check-fixtures.sh` → `fixture pairs ok` (zero drift) · `shellcheck`
clean. **cert-manager (prod9, READ-ONLY) content-identical to cue v0.16.1** (`jq -S`, exit 0) —
the byte-identity GATE holds. 6 `native_decide` pins (prune, direct-prune, real-conflict-bottoms,
struct|struct-stays-ambiguous, gate-off, gate-on) + fixture
`testdata/modules/disj_embed_struct_disc` (struct arm wins + emits the regular field; direct
identical; real conflict bottoms — all oracle-checked vs cue).

Soundness (all four obligations verified vs cue): (1) struct-compatible arm survives; (2) real
conflict (host matches neither arm) bottoms; (3) directly-narrowed disjunction unchanged; (4)
`struct | struct` ambiguous stays ambiguous, NOT falsely pruned.

## argocd NOT unblocked — a SEPARATE pre-existing bug surfaced (Bug2-4)

The structural prune now works (guard-free repro exports content-identical to cue), but
`kue export apps/argocd.cue` STILL bottoms (~104s, `conflicting values`). Cause is a DISTINCT
bug: a **two-level-embedded `let _patch` comprehension guard does not see the host narrowing.**
`#U: {#M}`, `#M` embeds `let _patch = { kind: string, for _, add in Self.#additions { if kind
== add.#kind { add.#patch } } }`; the host's narrowed `kind` reaches `#U` but
`embedComprehensionReadLabels` follows let-comprehension reads only ONE level, so `kind` is
stripped before reaching `_patch`'s frame → the guard sees `string`, never fires → the matched
`#patch` (`meta:"yes"`) is dropped. **Reproduces with NO disjunction** (`/tmp/kue-patch4.cue`);
**confirmed identical on clean HEAD `2ab5c84`** — NOT a regression from this slice. cert-manager
remains the one fully-correct probed real app.

## NEXT STEP → two-phase audit DUE, then plan-hygiene, then Bug2-4 / D#2a

Bug2-3 is the 1st fix-slice since audit #13 (RX-2b + RX-1c batch). **A two-phase audit is now at
the 2–3-slice mark** — run it per `docs/guides/slice-loop.md` (do NOT invoke `/ace-audit`): (A)
code-quality over the Bug2-3 diff (gate narrowness, the `embedBodyEmbedsDisj` heuristic vs the
meet primitive, the all-regular splice's closedness interaction), then (B) architecture/refactor
over the whole graph.

Then, per the Phase-B schedule, the **plan-hygiene pass** (now due — distill `plan.md` + this
audit doc, mark RX-2c DONE, move DONE entries to the log). After hygiene, the ranked work:

1. **Bug2-4 (HIGH — the NEW single argocd export blocker, undesigned).** Transitive
   comprehension-read-splice: make `embedComprehensionReadLabels` follow an embedded let's
   comprehension reads TRANSITIVELY (when `#M` embeds `_patch` whose guard reads host-providable
   `kind`, surface `kind` as a `#M` read-label), gated so a body NOT embedding a
   comprehension-reading let stays byte-identical. Pinned repro `/tmp/kue-patch4.cue` (and the
   in-tree shape in `testdata/modules/disj_embed_struct_disc` is guard-free, so add a guarded
   two-level fixture with the fix). This is now the last argocd correctness blocker.
2. **D#2a / D#2b (HIGH, DESIGNED — structural-cycle detection + terminating-disjunct).**
   Ancestor-force-stack on `forceClosureWithConjunct` (reuse `ForceKey`), then the terminating
   default arm via `liveAlternatives`/`resolveDisjDefault?`. Cannot regress real apps (zero
   self-ref defs in prod9).
3. **RX-2a (MED — in-class `\D`/`\W`/`\S`).** Serialize after any regex-module work.

prod9 reminder: caches + `apps/*.cue` are READ-ONLY; never mutate the environment outside the
project tree.
