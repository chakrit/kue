# Breadcrumb: 2026-07-04 — AUDIT-RESOLVE-CATCHALL fixed (catch-all enumerated)

Supersedes `2026-07-04-audit-quoted-beq-landed.md` as the live front.

## What landed

**AUDIT-RESOLVE-CATCHALL (LOW, pre-existing latent) — DONE.** `mapRefsValueWithFuel`
(`Kue/Resolve.lean`) ended in `| _, _, value => value` — a `| _ =>` catch-all in a
`Value`-PRODUCING rewrite, CLAUDE.md-banned. Replaced with 13 explicit pass-through arms, one per
`Value` ctor not already handled: leaves (`top`, `bottom`, `bottomWith`, `prim`, `kind`, `notPrim`,
`stringRegex`, `boundConstraint`), atomic/resolved (`refId`, `thisStruct`), eval-only carriers
(`embeddedList`, `embeddedScalar`, `closure`). Exhaustiveness now compiler-proven — a new `Value`
ctor fails the build here instead of being silently swallowed.

Byte-identical (pure refactor): every enumerated ctor was pass-through under the old catch-all and
stays pass-through. `closure` stays pass-through — it owns its `capturedEnv`, not the enclosing
`scopes`; no recursion added. `embeddedList`/`embeddedScalar` are eval-only, never present at the
two pre-eval call sites (`resolveStructRefs`, `rewriteFileImportRefs`). No latent bug surfaced (no
swallowed ctor needed recursion), so no wild fixture. cert-manager canary EMPTY; `check.sh` green.

## Next step (pick by rank)

1. **Phase B audit (owed)** — architecture/refactor; infra-in-scope rotation due (3rd cycle). Run
   before new feature slices. Details: `plan.md` § Audit status. (The 2026-07-04 Phase A audit
   filed AUDIT-QUOTED-BEQ + AUDIT-RESOLVE-CATCHALL, both now DONE; Phase B still owed.)
2. **AUDIT-STRUCT-EQ (plan 0b)** — one order-independent, regular-fields-only, concreteness-guarded
   struct/list equality feeding BOTH `dedupAlternatives` and `evalEq`/`evalNe`. Graduates the
   `struct-equality-quoted-labels-defers` seed; also fixes reordered-field dedup. Soundness-
   sensitive — a real slice, not inline.
3. **B3d-6b (NETWORK-GATED)** — `cue mod get/tidy` + requirement-graph fetch + `cue.sum` WRITE.
4. **B2-A1** — thread `tail` through the patterns-present meet (lands with typed-ellipsis).

If AFK/offline, B3d-6b is network-gated — prefer the Phase B audit or AUDIT-STRUCT-EQ.
