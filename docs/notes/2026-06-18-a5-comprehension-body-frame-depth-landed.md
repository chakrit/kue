# RESUME HERE — A5 comprehension-body frame-depth regression LANDED (2026-06-18)

Supersedes the prior START-HERE pointer (`2026-06-18-argocd-packs-argo-chain-landed.md`).
Standing grant in effect (autonomy / Lean-into-Lean-4 / commit-push freely / specs as
restore point). Full record: `docs/reference/implementation-log.md` ("A5" entry); ranked
work: `docs/spec/plan.md` (Live Backlog).

## What landed — `c3d0089` (pushed to gh:main)

A5: the B1 (`80df01e`) comprehension-body frame-depth regression, fixed in ALL THREE
frame-depth walkers. A comprehension body lives `#forClauses` frames deeper than the
comprehension node (`for` pushes a frame, `guard` none) — authority is
`resolveClausesWithFuel`. Each walker re-derived it by hand and recursed the body at FLAT
depth:

- **A5 proper (wrong value):** `remapConjRefs`/`remapConjClauses` — a comprehension-conjunct
  body ref to a merged sibling stayed at its stale slot. Repro
  `t: {s:{p:10,q:20}} & {s:{a:{for v in [1] {out: zz}}, zz:99}}`: cue → `s.a.out: 99`,
  kue → `20`. FIXED.
- **Sibling `selfReferencedLabels`** (Pass-2 selection): flat scan missed a `Self.<embed>`
  read in a `for` body. FIXED.
- **Gate `refsSelfEmbeddedLabel`:** found UNSOUND (the old "too-shallow over-fires = perf"
  comment was backwards — it UNDER-fires = a stale-value miss). FIXED too.

Fix shape: new `clauseFrameShift` (+1 per `for`, +0 per `guard`) + per-walker depth-threading
helpers (`remapConjClauses`, `selfReferencedLabelsClauses`, `refsSelfEmbeddedLabelClauses`).
Replaced the misleading depth-0 pin with realistically-resolved native_decide pins + an
end-to-end fixture (`comprehension_conj_body_remap`, oracle vs cue 0.16.1).

## CRITICAL — A5-followup is the OBSERVABLE wrong value, still OPEN (HIGH)

The depth fixes are correct and pin the walkers, but the visible wrong value is NOT yet
fixed — a SEPARATE Pass-2 re-eval gap gates it. Minimal repro (cue 0.16.1 → `v.out.v: "y"`,
kue → `string | *"def"`):
```
#H: {#t: string | *"def"}
#R: Self={#H, out: [for x in [1] {v: Self.#t}]}
v: #R & {#t: "y"}
```
The field IS selected and the gate DOES fire (proven by unit pins); the defect is that
Pass-2 re-eval of a comprehension-VALUED field does not re-expand its body against the
augmented frame — it reuses the Pass-1 expansion. Likely near the eager/lazy two-pass arms
(`Eval.lean` ~2238 / ~2631), where selected `(index, field)` entries go to
`evalFieldRefsListWithFuel` against `nested2`. See plan.md A5-followup.

## Verify (all green at commit)

`lake build` 86 jobs; `scripts/check-fixtures.sh` → `fixture pairs ok` (zero byte-drift; the
cert-manager/argocd-derived module fixtures are byte-identical = the correctness gate). No
shell changed. Real-app exports (cert-manager/fx/keel/n8n) all hit the documented perf wall
(timeout) regardless of this change — perf, not correctness.

## Next step (pick one, ranked)

1. **A5-followup** (HIGH) — the Pass-2 comprehension-valued-field re-eval gap above. Closes
   the observable wrong value A5 surfaced. Repro is ready; instrument the two-pass arms.
2. **B7** (MEDIUM-HIGH) — typed frame coordinate / one shared `clauseDepthShift` the now-4
   walkers consume, making a 4th re-derivation a compile error. Design-spike first; subsumes
   A5's structural fix. The `clauseFrameShift` helper is the seed.
3. **B2** headline struct refactor / **B6** design-spike / **A2-followup** import-binding
   marker / **item 1** follow-up.

Two-phase audit is DUE soon (A5 is the 1st slice since the last audit pair; spawn after
~2-3 more). Releases: ~1 datestamped alpha/day via `scripts/release.sh` (local only).
