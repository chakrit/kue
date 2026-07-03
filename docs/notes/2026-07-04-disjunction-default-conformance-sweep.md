# Breadcrumb — 2026-07-04 — disjunction + default-marker conformance sweep

## Where things stand

Bounded CONFORMANCE PROBE of the most divergence-prone CUE area — disjunction unification
(distribution), default-mark (`*`) resolution, bottom-elimination, dedup — AFK. Three-way
compared CUE spec (authority) vs `cue` v0.16.1 (fallible) vs `kue` over ~50 cases.

## Result: area is VALUE-CONFORMANT — no fix needed

**Zero export divergence.** Every `export` verdict matched `cue` byte-for-byte (or both
error) across distribution, default-through-meet, bottom-elimination, struct-arm defaults,
bound narrowing, bool/null defaults, associativity/flatten, dedup. No wild fixture warranted
(no real divergence to reproduce red).

### One new observation — SC-3 display sub-case (NOT a value gap)

A markerless×markerless disj-meet renders `*1 | *2` in eval where `cue` elides to `1 | 2`
(`(1|2)&(1|2)`, and direct `*1|*2`). `withDefaultConvention` promotes each markerless
operand's whole set to defaults → all-`.default` survivors (default-set = full set),
semantically identical to markerless (export ambiguous either way). Documented SC-3
keep-marked family. A "demote all-default → regular" fix is NOT globally sound — in the shared
normalizer it breaks `(*1|*2)|*3` (inner all-default MUST collapse to regular so outer `*3`
wins → export `3`; `kue` already gets this via context-sensitive flatten). Recorded as an
SC-3 sub-case in `cue-spec-gaps.md`; not forced (AFK soundness-core guidance).

### Already-known, NOT re-filed

- **NESTED-DISJ-MARK** tier-2 (DESIGNED-DEFERRAL) — skipped per instruction, not re-opened.
- **AUDIT-STRUCT-EQ half-2** dedup order-sensitivity — reconfirmed (`1|2|1`→`2|1`,
  `{a:1,b:2}|{b:2,a:1}` no-dedup) but export-safe in every probed case (both ambiguous); the
  already-filed OPEN gap, not re-filed.

## Landed (this slice)

- 8 `native_decide` guards in `Kue/Tests/EvalTests.lean` (`disj_meet_*`): end-to-end
  (parse→eval→export) pins for distribution / bottom-elim / all-default-ambiguity /
  default-position-independence / struct-default-through-meet / bound-narrowing, plus one
  eval-display guard on the SC-3 all-default `*1 | *2` form. Complement the constructor-level
  F1 pins.
- `cue-spec-gaps.md` SC-3 row extended (all-default sub-case); `plan.md` + implementation-log
  updated.

No source touched (tests + docs only) → cert-manager canary trivially EMPTY.

## Next step

Continue the slice loop. A **two-phase audit is DUE** (last full 2026-07-02; many slices since
— list-slice, strings.Runes, struct-eq, interp-operand-typing, byte-literal-lexing, this
sweep). Otherwise the natural code follow-on is **BYTE-INTERPOLATION** (byte-array repr + byte
interp carrier, graduates `byte-literal-interpolation` seed), or another bounded conformance
probe (comprehensions, string builtins).
