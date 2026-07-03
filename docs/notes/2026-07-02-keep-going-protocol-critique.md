# "Keep going" protocol critique — proposed amendments (2026-07-02)

From the 2026-07-02 full-repo audit. Diagnosis: every script-enforced invariant held;
every prose-only/remembered one drifted. Four structural flaws → eight amendments.

> **Status: APPLIED 2026-07-03.** All 8 amendments landed (ratified by chakrit): A2/A3/A8
> in code (commits `a4e7390`, `ca4a322`), A1/A4/A5/A6/A7 as governance doc-edits (CLAUDE.md
> + `docs/guides/slice-loop.md` + banners in the plan/breadcrumb). Consolidated batch
> record: [`../reference/implementation-log.md`](../reference/implementation-log.md). This
> note is retained as the design rationale; it is no longer a pending decision.

## Flaws

1. All per-slice duties are forward-writing; nothing back-propagates retractions (stale
   "DONE" blocks survived root A's retraction across plan/audit-doc/architecture).
2. Slice-scoped agents can't own repo-wide work (TEST-HEALTH 23/37 unconverted; filed
   fix-slices decayed unchecked).
3. Orchestrator verifies green-ness, not truth (false "FixturePorts registration" claim
   copied into two docs; wild-gate hole survived batch-scoped audits).
4. Two authorities for decision state, no precedence (plan said L5 self-startable;
   breadcrumb said awaits decision).

## Amendments (ranked)

1. **Fifth per-slice duty — retraction.** A slice that reopens/supersedes a prior claim
   greps docs for the claim and annotates every site in the same slice.
2. **Strict-xfail quarantine.** `check_wild_fixtures` fails/flags when a `.known-red`
   fixture unexpectedly passes (cl2 was fixed en passant, unnoticed); promote on green.
3. **No convention without a gate.** Repo-wide conventions land with full migration + a
   `scripts/check-*.sh` gate in the same slice; verify step runs `check-*.sh` by glob.
4. **Audits open by auditing the last audit** — diff its filed fix-slices against landed
   commits; re-rank or explicitly drop.
5. **Single home for open decisions** — breadcrumb "Open" block only; plan points.
   Precedence: what's-next → breadcrumb wins; what's-true → plan wins.
6. **Blind-grind circuit breaker** — after ~3 fix-slices with zero external-metric
   movement (e.g. apps still 0/4), stop fixing, re-scope/bisect or escalate.
7. **Rotate infrastructure into the audit** — every ~3rd cycle, Phase B targets the
   gates themselves (check scripts, fixture discovery, release tooling).
8. **Mechanize AFK git bans** — deny `git checkout`/`restore`/`reset --hard` in
   `.claude/settings.json` (run-2 self-flagged a checkout; prose restraint fails).

Amendments 1–5 ≈ one CLAUDE.md/slice-loop edit + two small script changes.
