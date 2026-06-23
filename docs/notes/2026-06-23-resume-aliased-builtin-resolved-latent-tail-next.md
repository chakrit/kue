# RESUME — aliased-builtin resolution RESOLVED; NEXT = the LATENT / CLEANUP tail

(2026-06-23) Live START-HERE; supersedes
`2026-06-23-resume-a2y-audit-closed-latent-tail-next.md` (deleted).
Authoritative roadmap: [`../spec/plan.md`](../spec/plan.md). Spec-conformance backlog:
[`../spec/spec-conformance-audit.md`](../spec/spec-conformance-audit.md) § Genuinely-open.
Per-slice history:
[`../reference/implementation-log.md`](../reference/implementation-log.md). Failure modes:
[`../reference/failure-modes.md`](../reference/failure-modes.md). Served status page:
[`../../www/index.html`](../../www/index.html).

## Just landed — aliased-builtin call resolution (item-6 LATENT) → RESOLVED

An ALIASED stdlib import (`import j "encoding/json"` + `j.Marshal({a:1})`) returned
`incomplete value` where cue marshals. Root: the parser lowered the call off the LITERAL
member-access head (`j.Marshal`), so the alias-blind `BuiltinFamily.ofName?` never mapped
`j` to the canonical `json`.

- **Fix:** a post-parse alias canonicalization in `Parse.lean`
  (`builtinImportLocalNames` + `canonicalizeBuiltinCallName` + the total
  `canonicalizeBuiltinCalls` Value-rewrite), applied in BOTH `parseDocument` (stdin) and
  `parseDocumentFile` (file) so every load path is covered. Rewrites a builtin-alias call
  head to its canonical package BEFORE dispatch, scoped to builtin paths
  (`isBuiltinImport`) so an aliased USER import is NEVER misdispatched.
- **DRY move:** `builtinImportPaths`/`isBuiltinImport`/`lastPathElement` moved to
  `Value.lean` (shared base) — `Module.lean`'s copies deleted, no cross-boundary
  duplication.
- **Conformance:** all six families (`json`/`strings`/`math`/`list`/`base64`/`yaml`)
  resolve == cue v0.16.1; unaliased unchanged; aliased user import → user package
  (deferred selector).
- **Canaries jq-S=0** (cert-manager ~11.5s, argocd ~50.7s, from infra root) — prod9 uses
  unaliased imports, unaffected.
- **Tests:** 4 ParseTests theorems (alias map + head rewrite + per-family e2e +
  unaliased/user boundary), 1 Bug2xTests export pin, fixtures
  `testdata/cue/builtins/aliased_builtin.{cue,expected}` (dual CUE-port + CLI witness) +
  module fixture `testdata/modules/alias_builtin_call/`.
- **No cue-divergence, no spec-gap** (an alias is an unambiguous local rebinding).

## Audit counter = 1

This slice was a real code change (Parse + Value + Module + tests). One slice since the
last two-phase audit (the A2-y audit CLOSED the prior round at counter 0). **Two-phase
audit DUE again after 1–2 more slices.**

## State — substantive backlog EXHAUSTED; only LATENT / CLEANUP remains

Spec-conformance backlog EMPTY (argocd + cert-manager content-identical drop-ins, jq -S
diff = 0); per-eval perf frontier CLOSED. Latest release `v0.1.0-alpha.20260623`.

## 🚨 NEXT LEADER — the remaining LATENT / CLEANUP tail (none soundness-bearing)

Resolve by philosophy (precise/total/illegal-states-unrepresentable), don't ask:

- **item-6 LATENT tail** — `module-file-scoped-imports` (arch-sized; prod9 misses it);
  B2-A1 (latent `tail`-drop, pairs with typed-ellipsis) / B2-A2 (test-gap fill);
  `resolveEmbeddedDisjDefault` check (`Eval.lean:2093`); DRY `selectEvaluatedField .disj`.
- **SC-3** — the multi-arm-default display-gap (cosmetic Format-layer projection).
- **Adjacent to this slice (optional, LOW):** an aliased stdlib CONSTANT (`import l
  "list"; l.Ascending`) is NOT yet canonicalized — `stdlibPackageValue?` keys off the
  literal head too, so `l.Ascending` stays a deferred `.selector` rather than the
  comparator struct. Same alias root, different (no-call) lowering path; this slice scoped
  to CALLS only. Pin it if next touching the stdlib-constant path.

All latent/cleanup. Pick the next by philosophy, drive the loop.

## Verify on resume

`git status` clean, `HEAD == @{u}`, `lake build` green, `scripts/check-fixtures.sh` green.
Canaries (from `/Users/chakrit/Documents/prod9/infra`) jq-S=0 if a slice touched eval.

## Release

`v0.1.0-alpha.20260623` is the latest cut. This slice is a real behavior change (aliased
builtins now resolve), so a fresh dated alpha is owed — ride the next auto-due daily cut
(attended) via `scripts/release.sh` (+ `scripts/release-linux.sh`).

## Live state end
