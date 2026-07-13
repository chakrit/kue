# Provenance

- **Source:** Kue FINAL Phase A milestone-verdict audit, 2026-07-13 (adversarial
  referent-structure sweep of the `8b19318` closedness fold).
- **Class:** closedness-through-indirection (6th residual). The fold unified struct and
  pure-disjunction referents but not a disjunction reached as a conjunction MEMBER.
- **Kind:** SOUNDNESS over-acceptance — a closed definition admits a foreign field.
- **Oracle:** cue v0.16.1 rejects (`y: 2 errors in empty disjunction: y.a / y.q field not
  allowed`). Kue currently emits `{a:1,c:3,q:99}`. Spec-adjudicated expected: bottom.
- **Status:** quarantined `.known-red` (captured red-first; fix pending).
