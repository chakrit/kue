# Breadcrumb: 2026-07-04 — Phase B audit done → two-phase audit COMPLETE

> SUPERSEDED as the live front by `2026-07-04-resilience-retro-landed.md`. The "Next step"
> ranking below is still current — the resilience pass was an out-of-band process-hardening
> slice, not a plan item; resume from the ranked queue here.

Supersedes `2026-07-04-audit-resolve-catchall-landed.md` as the live front.

## What landed

**2026-07-04 Phase B audit (architecture/refactor + A7 infra rotation)** over `a8d07b7..HEAD` +
the whole module graph. Doc-only slice — findings folded into `plan.md` as fix-slices; no code
change. Module graph HEALTHY.

- **A4** — both Phase A fixes verified landed in code (not just planned): `stripFieldQuoting`
  wired at both parse→eval seams AFTER `checkLetFieldShadow`; `mapRefsValueWithFuel` catch-all
  enumerated. Neither decayed.
- **Architecture:** `mapRefsValueWithFuel` unified walker = GOOD reuse (AD4-1 leaf-differs shape).
  File-scoped imports (NUL-sep synthetic label + shadow-aware rewrite) = CLEAN; Module/Resolve
  boundary intact. `Field.quoted` + strip-walk = SOUND but carries an unenforced "must-strip"
  invariant (already bit once via AUDIT-QUOTED-BEQ) → filed **ARCH-QUOTED-STRIP**.
- **A7 infra:** `check.sh` + `./lake`/`./lean` CPU-cap wrappers sound. The two-gate `.known-red`
  quarantine (`check_wild_fixtures` vs `check_module_subpaths`) is COPY-PASTED → filed
  **GATE-KNOWNRED-DRY** (LOW).
- **AUDIT-STRUCT-EQ re-scoped** (plan 0b): SPLIT into an autonomous-safe `evalEq` half and a
  deferred `dedupAlternatives` half. Do NOT redefine global `Value` `BEq` (cycle detection at
  `Eval.lean:292 structStack.contains` relies on exact equality).

Periodic passes: test-org / plan-hygiene / perf-guide NOT due; resilience/retro APPROACHING
(flagged, not overdue).

## Next step (pick by rank)

1. **AUDIT-STRUCT-EQ half (1) — the `evalEq` slice (plan 0b).** Autonomous-safe: a dedicated
   order-independent, regular-fields-only, concreteness-guarded `structEqConcrete? : Value → Value
   → Option Bool` used ONLY by `evalEq`. Additive (evalEq currently just defers non-`.prim`), so it
   can't regress. Graduates the `struct-equality-quoted-labels-defers` `.known-red` seed. ~1 slice.
2. **ARCH-QUOTED-STRIP (plan 0c).** — ✅ DONE 2026-07-05, but NOT via this proposed mechanism.
   "Parse-only quoting: drop `quoted`, bubble a collidable-label set up through `parsedFieldsValue`"
   was infeasible in-slice (`parsedFieldsValue` is not recursive; nested structs arrive pre-built).
   Landed instead as Option B: `Field.quoted : Quoted` newtype with an inert `BEq`; strip deleted.
   See plan 0c + `2026-07-05-arch-quoted-strip-landed.md`.
3. **GATE-KNOWNRED-DRY (LOW tail).** Share a `handle_known_red` helper across the two `.known-red`
   gates in `check-fixtures.sh`.
4. **B3d-6b (NETWORK-GATED).** `cue mod get/tidy` + requirement-graph fetch + `cue.sum` WRITE.
5. **B2-A1.** Thread `tail` through the patterns-present meet (lands with typed-ellipsis).

If AFK/offline: B3d-6b is network-gated — prefer AUDIT-STRUCT-EQ half (1) or ARCH-QUOTED-STRIP.
Two-phase audit for this batch is complete; run 2–3 implementation slices before the next audit.
