# Session 2026-06-17 — B4 multiline strings landed

Latest resume breadcrumb. Supersedes
[`2026-06-17-b2-aliases-landed.md`](2026-06-17-b2-aliases-landed.md).
Resuming **implementation** next session at **B6 — encoding builtins**.

## What was done

Landed **B4 — multiline strings** (`"""…"""`) and **multiline bytes** (`'''…'''`). Every
form previously evaluated to `_|_`. The bug was in **parse, not eval**: `parsePrimaryAtom`
had no triple-delimiter arm, so the lone `'"'` arm read `""` as an empty string and
mis-parsed the rest. Full record in
[`../reference/implementation-log.md`](../reference/implementation-log.md) ⇒ "Completed
Slice: B4 — Multiline Strings". Summary:

- **Parser:** new `parsePrimaryAtom` arms `'"' :: '"' :: '"'` / `'\'' :: '\'' :: '\''`
  (before the single-quote arms) route to `parseMultilineOpen`. A total
  `multilineStripPrefix?` pre-scan finds the closing line's indentation; the opening
  delimiter must be followed by a newline (content-on-opening-line rejected); then
  `parseMultilineBody` strips that prefix from each content line, joins with `\n`, drops
  the trailing pre-closing newline, and reuses the single-line `\(expr)`/escape machinery.
  `'''` rewraps the dedented string as `.prim (.bytes …)`.
- **Dedent rule (oracle-confirmed `cue` v0.16.1):** content starts the line after the
  opening delimiter; the closing delimiter sits on its own line and its leading horizontal
  whitespace is stripped from every content line. Leading/trailing boundary newlines
  excluded. Non-blank lines must carry the full prefix (some-but-insufficient ws ⇒
  "invalid whitespace"); a fully empty line is exempt. Escapes + interpolation apply.
- **Totality:** the strip-prefix scanner is a total structural `def` (no `partial`, no
  `decreasing_by`); the body parser lives in the standing `partial` parser mutual block.
- **Tests:** 6 fixture pairs (`multiline_{string,dedent,interpolation,empty,cert,bytes}`)
  + `FixturePorts.lean` entries; 11 `ParseTests.lean` theorems (`parseSameValue` AST-identity
  vs the single-line equivalent for the happy paths, `parseFails`/`parseFailsAt` for the
  error/deferral cases).

Verify gate green: `lake build` (68 jobs), `scripts/check-fixtures.sh` ⇒ `fixture pairs
ok`, `shellcheck` clean. Real-infra impact: the `"""` parser barrier cleared on all four
multiline-using prod9 files; `infra/apps/argocd.cue` now parses+evaluates (exit 0). The
other three (`argo/bluepages.cue`, `argo/stage9.cue`, `infra-defs/secret.cue`) now fail at
**separate, later** parser gaps (open-list `[...]` expressions, non-string label patterns
`[string]: string`), not the multiline form.

### Deferred (documented in compat-assumptions, not bugs)

- **Multiline bytes interpolation** (`'''…\(x)…'''`) is rejected at parse. Kue's bytes
  value is a plain string payload and the interpolation machinery yields a string, not
  bytes; non-interpolated `'''…'''` dedents to a bytes value normally. Kue-does-less
  boundary, not a `cue` divergence. The real infra use of `'''` is non-interpolated.

## Alpha status

v0.1.0 staged; cut locally via `scripts/release.sh` on chakrit's "cut a slice" command
(**NO GitHub Actions — banned**; there is no `.github` dir, do not create one; release
tooling owned elsewhere — do **not** touch `scripts/release.sh` / `packaging/`). External
repos (prod9/infra etc.) are **read-only**.

## Next session — implementation focus: B6 — encoding builtins

Per `plan.md` Current Focus (data-driven prod9/infra roadmap B1→B6). B1, B2, B4 done;
**B6 is now active**: encoding builtins `base64.Encode`, `json.Marshal` (load-bearing
inside `#Secret`/`#ConfigMap`). Small pure functions; kue already has the value AST. Follow
the package-qualified dispatch pattern (`evalXBuiltin` helper + catch-all route in
`evalBuiltinCall` + fixture + unit theorems), oracle-checked against `cue` v0.16.1. Note
`base64.Encode` takes a *bytes* value — now that `'''` bytes land, the two compose.

Roadmap after B6: B5 manifest output (YAML/JSON serializer + `cue export`-style CLI),
B3 module/import resolution (the big one, LAST — packages gate every real `infra/apps/*`).

### Carry-forward boundaries (unchanged)

- **PENDING AUDIT — parser+alias batch** (`0795530`/`7ec51a4`/`f6c18b5`/`804f1ca`): the
  `/ace-audit` depth pass over the B1/B2 batch failed three times on transient API 500s and
  never completed. Orchestrator spot-check cleared the #1 risk (`Value.thisStruct` is
  explicitly handled everywhere). A full audit is still owed — re-run when the API is
  stable. Do not let it block forward slices.
- **No imports / module resolution** (B3, last). Builtins work via implicit dotted names;
  real `import`s parsed-and-ignored.
- **Separators stay permissive** — `a: 1 b: 2` parses as two fields, no error.
- **No `list.Sort`/`SortStable`**; **non-ASCII case folding** passes through; remaining
  `strings`/`math` funcs parked per Current Focus (core-language over stdlib).
- **Multiline bytes interpolation deferred** (this slice; see above).
