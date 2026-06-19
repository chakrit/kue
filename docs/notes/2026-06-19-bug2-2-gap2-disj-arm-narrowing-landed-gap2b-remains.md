# RESUME HERE — Bug2-2 (Gap-2) landed; Gap-2b (Bug2-3) is the REMAINING argocd blocker (2026-06-19)

**START HERE.** Supersedes
[`2026-06-19-bug2-1-gap1-let-buried-read-detection-landed.md`](2026-06-19-bug2-1-gap1-let-buried-read-detection-landed.md)
as the current pointer. Standing grant in effect (autonomy / Lean-into-Lean-4 / commit-push freely /
specs as restore point).

## What this slice did (Bug2-2 — Gap-2, force-tier disjunction-arm narrowing for a REGULAR discriminator)

Landed the riskier half of the argocd Bug #2 fix for the REGULAR-discriminator disjunction class. An
embedded def `#M` carrying a discriminated disjunction (`{shape:"struct",…} | {shape:"list",…} |
error`) selects the right arm when narrowed DIRECTLY (`#M & {shape:"struct"}`) but BOTTOMED when
embedded one layer down (`#U:{#M}`, then `#U & {shape:"struct"}`).

**Root cause (pinned by instrumenting the `.closure` force-splice in `meetEmbeddingsWithFuel`):** the
splice operand into `#M` was `hiddenFieldsOnly` + the regular siblings a comprehension READS
(`embedComprehensionReadLabels`). The disjunction's DISCRIMINATOR `shape` is a regular sibling the
arms MATCH (declare `shape:"struct"`/`"list"`), not one they READ — so it was dropped from the
splice. `#M` was forced with `shape` un-narrowed, every arm survived (`nLive=2`), the outer meet
conflicted → bottom. (Direct narrowing works because it never takes this embed-closure path.)

**Fix — `embedDisjArmDeclLabels` (`Eval.lean`), GATED.** Returns the regular labels an embed body's
embedded disjunction's ARMS DECLARE that are also top-level regular fields of the body (the
discriminators). Follows a `.refId ⟨0,i⟩` arm into the body's own `let` slot at index `i` (the shapeD
`structShape | listShape` form). `spliceOperandForEmbed` adds them so the host's narrowed
discriminator splices into `#M` and its force-time `conjDisjArms?` distribution prunes the dead arms
exactly as the DIRECT case does — same `liveAlternatives`, re-driven behind the force tier.

**MANDATORY GATE — PASSED.** `embedDisjArmDeclLabels` returns `[]` unless the body's `cs` holds a
`.disj` embedding → no disjunction embedding → no extra splice → byte-identical. Verified by
construction: instrumenting the splice site, **cert-manager fires the gate 0 times** (content-identical
to cue at **30.52s** = baseline); shapeD fires it 6×.

**Soundness:** spliced value is the SAME use-site narrowing, merged BY LABEL — no over-narrow. A real
conflict killing ALL structural arms still bottoms (the `error(…)` arm bottoms; all structural arms
dead → disjunction bottom, cue-exact). Direct-narrowing UNCHANGED.

### Tests (oracle-checked vs cue 0.16.1)

- Fixtures: `testdata/modules/disj_embed_one_layer` (inline arms — struct/list selection +
  direct-unchanged + real-conflict-falls-back, byte-identical to cue) + `disj_embed_force_narrow`
  (shapeD — struct arm + emitted patch, content-identical modulo field-order #3).
- `native_decide` pins in `TwoPassTests.lean`: `embed_disj_arm_decl_labels_inline`/`_let_refs`
  (mechanism), `embed_disj_arm_decl_labels_no_disj_gate` (THE GATE → `[]`),
  `disj_embed_one_layer_selects_struct_arm`/`_selects_list_arm` (both arms, no over-prune),
  `disj_direct_narrow_unchanged`, `disj_embed_one_layer_real_conflict_bottoms` (SOUNDNESS),
  `disj_embed_force_narrow_emits_patch` (shapeD e2e).
- Verify: `lake build` green (96 jobs), `scripts/check-fixtures.sh` → `fixture pairs ok` ZERO drift
  (cert-manager 30.52s, link-5/A5/`crossmod_embed_guard` pins unchanged), `shellcheck` clean.

## argocd: NOT unblocked — Gap-2b is the REMAINING blocker (the next slice)

`kue export apps/argocd.cue` STILL bottoms (~88s, exit 1) — but for a DIFFERENT, separate reason than
shapeD. The spike's shapeD/`probe_disj_inline` used a REGULAR discriminator (`shape`), which Gap-2
clears. The REAL `defs/parts.#Mixin` (cue cache `…/defs@v0.3.19/parts/mixin.cue`) discriminates
STRUCTURALLY:
- `listShape = { #components: [string]: _patch; [...] }` — LIST-shaped arm (`[...]` embed), keyed on
  the HIDDEN `#components`.
- `structShape = { _patch; ... }` — plain struct arm, no concrete discriminator.

No regular discriminator label → `embedDisjArmDeclLabels` doesn't fire. Minimized repro
`/tmp/kprobe/struct_disc.cue` (cue selects `structShape`, emits `meta:"yes"`; Kue bottoms).
Instrumenting `conjDisjArms?` distribution: `nLive=2` — the LIST-shaped arm is NOT pruned against the
STRUCT host (`{kind:"ListenerSet",…}`) when the arm carries the spliced `_patch` comprehension, so a
`struct | list` disjunction survives and bottoms downstream. **WITHOUT `_patch` the structural
pruning WORKS** (`/tmp/kprobe/sd5.cue` selects `structShape`) — so Gap-2b is the
list-arm-vs-struct-host pruning INTERACTING with the spliced comprehension patch behind the force
tier.

## Next step

**Slice Bug2-3 — Gap-2b (structural disjunction-arm pruning behind force). The remaining argocd
unblock.** Mechanism to investigate: when distributing the host into a LIST-shaped arm
(`[...]`/`.embeddedList`), the meet against a STRUCT host must bottom that arm (struct-vs-list type
mismatch, cue-exact) so `liveAlternatives` prunes it — today it survives, likely because the `_patch`
splice into the list arm yields a struct-ish residual that doesn't trip the mismatch. Probe the
list-arm meet path (`Lattice.lean` `.embeddedList`/`asListPair`, and how the force-tier disjunction
distribution at `Eval.lean` line ~2661 builds each arm). SOUNDNESS-GATED like Gap-2: cert-manager
byte-identity MANDATORY (cert-manager has no struct-vs-list disjunction arm → a structural-pruning fix
should be byte-identical; verify by construction with the same 0-fire instrumentation). After Gap-2b:
RE-MEASURE `kue export apps/argocd.cue`. Repros under `/tmp/kprobe/` (struct_disc.cue, sd3.cue,
sd5.cue, sd6.cue) — rebuild minimal if `/tmp` is gone. See `plan.md` "Slice Bug2-3 — Gap-2b" +
implementation-log "Bug2-2".

## Audit cadence — DUE

Bug2-1 + Bug2-2 = **2 code slices** since the last two-phase audit. The audit is DUE at the
2-3-slice mark. **Run the two-phase audit (per `docs/guides/slice-loop.md` — do NOT invoke
`/ace-audit`) before or alongside Bug2-3:** (A) code-quality over `e124a5e..HEAD` (the Bug2-1 +
Bug2-2 batch — correctness, totality, illegal-states, DRY, test strength, skill compliance), then (B)
architecture/refactor/cleanup (incl. A-EN3 the walker consolidation — fold `defFrameRefIndices` +
its let-following + `embedDisjArmDeclLabels` + `selfReferencedLabels` behind one frame-aware fold).

**Behind that:** Bug2-3 (Gap-2b, argocd), A-EN3 (walker consolidation, LOW/DRY), B6-deferred,
field-order #3, the LOW tail.

## Standing rules

- prod9 + cue caches READ-ONLY (eval/probe only). NO `git checkout`/`restore`/`reset --hard`. No env
  mutation outside the project tree.
