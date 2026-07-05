# Breadcrumb — 2026-07-05 — NESTED-DISJ-MARK CLOSED (Kue spec-correct; cue buggy)

## What happened

Re-adjudicated the "lone open VALUE divergence" — NESTED-DISJ-MARK, the 2026-06-23
DESIGNED-DEFERRAL. It was **mis-adjudicated**. Kue is SPEC-CORRECT; `cue` is the buggy side.
NO Kue code change — the slice reclassifies + reframes tests + closes the docs.

## The crux (why the prior deferral was wrong)

Prior sessions reverse-engineered a "two-tier rule" from `cue` v0.16.1's output and assumed
`cue` was right + the spec silent. They never applied the spec's formal default algebra.

The spec's marking rule **M2** is explicit: `*⟨v, d⟩ => ⟨v, d⟩` — "keep existing defaults for
marked term". Marking a disjunct that ALREADY carries a default does NOT re-broaden that default
to the whole value set. Confirmed by the spec note: `a|a`, `*a|a`, `*a|*a` all resolve to `a`
(so `*a = a` for defaulted `a`).

Derivation, `(*_I | 9) & >=5` with `_I: *1|5`:
`_I ⇒ ⟨1|5, 1⟩`; `*_I ⇒` M2 `⇒ ⟨1|5, 1⟩` (default stays 1); `| 9 ⇒ ⟨1|5|9, 1⟩`;
`& >=5 ⇒` U1 `⇒ ⟨5|9, 1&≥5⟩ = ⟨5|9, ⊥⟩` ⇒ default dead ⇒ **AMBIGUOUS `5|9`** = Kue's output.
`cue`'s `5` comes from broadening `*⟨v,d⟩ => ⟨v,v⟩` (M1-after-strip) — M2 forbids it. A `cue` bug.

Kue's eager flatten of a `(.default, .disj nested)` arm IS M2's absorb-the-mark. Correct as-is.

## Landed

- `cue-spec-gaps.md`: NESTED-DISJ-MARK row REMOVED (spec is explicit, not a gap).
- `cue-divergences.md`: NEW row (cue bug, M2/U1 basis, cue v0.16.1).
- `plan.md` + `spec-conformance-audit.md` #2: closed. **ZERO open VALUE-level divergences.**
  Designed 3rd-`Mark`-state fix WITHDRAWN.
- `TwoPassTests` `nested_disj_mark_*`: the two `⚠ DEFERRAL WITNESS` pins reframed as
  SPEC-CORRECT GUARDS (full M2/U1 derivation in-comment) + renamed; `#check` sentinel repointed;
  2 edge-case guards added (triple-nest, disj-inside-struct-field).
- Retraction: annotated the "deferred by design" claims in the three 2026-07-04 notes.

`check.sh` GREEN; cert-manager canary GREEN (no eval delta — Kue source untouched).

## Next step

Continue the slice loop. Per the closed audit, remaining open work is representation-quality /
non-core (BYTE-ARRAY-REPR 0f attended-grade, ARCH-QUOTED-STRIP, PRIM-FLOAT-PARSED,
BUILTIN-IMPORT-LENIENCY, B3d-6b network-gated) — no correctness holes; the core CUE semantics
are substantially complete with zero open value divergences.
