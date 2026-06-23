# RESUME — aliased-stdlib-CONSTANT resolution RESOLVED; NEXT = the LATENT / CLEANUP tail

(2026-06-23) Live START-HERE; supersedes
`2026-06-23-resume-aliased-builtin-resolved-latent-tail-next.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md). Spec-conformance backlog:
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Genuinely-open.
Per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md). Failure modes:
[`../reference/failure-modes.md`](../reference/failure-modes.md). Served status page:
[`../../www/index.html`](../../www/index.html).

## Just landed — aliased-stdlib-CONSTANT resolution (item-6 LATENT) → RESOLVED

The no-call analog of the aliased-builtin-CALLS fix (`ebaafc4`). A stdlib CONSTANT
(`list.Ascending`/`Descending`/`Comparer`) resolves INLINE at parse off the LITERAL head
(`stdlibPackageValue? pkg label`), so an aliased import (`import l "list"` + `l.Ascending`)
keyed `stdlibPackageValue? "l" …` → `none` and survived as a deferred `.selector (.ref
"l") "Ascending"` — `Sort` then bottomed where cue sorts to `[1,2,3]`.

- **Fix:** extend the SAME post-parse pass (`canonicalizeBuiltinCalls`, `Parse.lean`). Its
  `.selector base label` case now, when `base` is `.ref alias`, maps the alias head back to
  the canonical package (`canonicalizeBuiltinConst?`, reusing `builtinImportLocalNames`'s
  alias map) and re-resolves via `stdlibPackageValue?`, yielding the same comparator
  struct as the unaliased form. The aliased-CALL rewrite is unchanged — both aliased heads
  now canonicalize in the one pass.
- **Boundary held:** scoped to builtin paths, so a user import's const-shaped member
  (`import f "ex.com/foo"` + `f.Ascending`) is NEVER rewritten (stays a deferred selector
  → `_|_`). A local field shadowing the alias name with no import (`l: {Ascending: 7}`)
  stays field access (`7`) — empty alias map, the pass a no-op.
- **Conformance:** all three `list` constants resolve == cue v0.16.1; unaliased unchanged;
  the calls fix (`l.Sum`) still resolves.
- **Canaries jq-S=0** (cert-manager + argocd, whole-`apps` export with `."cert-manager"` /
  `.argocd` selected, from infra root) — prod9 uses unaliased imports, unaffected.
- **Tests:** 3 ParseTests theorems (the `canonicalizeBuiltinConst?` boundary + per-const
  e2e + the unaliased/user-member boundary), 1 Bug2xTests export pin, fixtures
  `testdata/cue/builtins/aliased_list_const.{cue,expected}` (dual CUE-port + CLI) + module
  fixture `testdata/modules/alias_list_const/`.
- **No cue-divergence, no spec-gap** (an alias is an unambiguous local rebinding).

## 🚨 Audit counter = 2 — TWO-PHASE AUDIT DUE after THIS slice

The prior slice (aliased-builtin CALLS, `ebaafc4`) put the counter at 1; this aliased-const
slice is the second real code change since the A2-y audit CLOSED the last round. **A
two-phase audit (sequential A code-quality → B architecture/refactor) is now DUE** per
`docs/guides/slice-loop.md` — run it BEFORE or AS the next slice. The two aliased-alias
fixes are a natural batch to audit together (Parse `canonicalizeBuiltinCalls` —
calls + const heads, the `Value.lean` DRY move, the fixture/test additions).

## State — substantive backlog EXHAUSTED; only LATENT / CLEANUP remains

Spec-conformance backlog EMPTY (argocd + cert-manager content-identical drop-ins, jq -S
diff = 0); per-eval perf frontier CLOSED. Latest release `v0.1.0-alpha.20260623`.

## 🚨 NEXT LEADER — two-phase audit DUE, then the remaining LATENT / CLEANUP tail

Resolve by philosophy (precise/total/illegal-states-unrepresentable), don't ask:

- **Two-phase audit (DUE)** — audit the two aliased-resolution slices + recent batch.
- **item-6 LATENT tail** — `module-file-scoped-imports` (arch-sized; prod9 misses it);
  B2-A1 (latent `tail`-drop, pairs with typed-ellipsis) / B2-A2 (test-gap fill);
  `resolveEmbeddedDisjDefault` check (`Eval.lean:2093`); DRY `selectEvaluatedField .disj`.
- **SC-3** — the multi-arm-default display-gap (cosmetic Format-layer projection).

All latent/cleanup. Pick the next by philosophy, drive the loop.

## Verify on resume

`git status` clean, `HEAD == @{u}`, `lake build` green, `scripts/check-fixtures.sh` green.
Canaries (from `/Users/chakrit/Documents/prod9/infra`) jq-S=0 if a slice touched eval.

## Release

`v0.1.0-alpha.20260623` is the latest cut. Both aliased-resolution slices are real behavior
changes, so a fresh dated alpha is owed — ride the next auto-due daily cut (attended) via
`scripts/release.sh` (+ `scripts/release-linux.sh`).

## Live state end
