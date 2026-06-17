# Session 2026-06-17 — B6 encoding builtins landed

Latest resume breadcrumb. Supersedes
[`2026-06-17-b4-multiline-strings-landed.md`](2026-06-17-b4-multiline-strings-landed.md).
Resuming **implementation** next session at **B5 — manifest output**.

## What was done

Landed **B6 — encoding builtins** `base64.Encode` and `json.Marshal`, the two the
prod9/infra gap analysis found load-bearing inside `#Secret`/`#ConfigMap`. Full record in
[`../reference/implementation-log.md`](../reference/implementation-log.md) ⇒ "Completed
Slice: B6 — Encoding Builtins". Summary:

- **New `Kue/Json.lean`** — a total, reusable JSON serializer: `manifestToJson :
  ManifestValue → String` (mutual structural recursion, no `partial`) emits compact JSON
  byte-for-byte matching `cue` v0.16.1, and `valueToJson : Value → Except ManifestError
  String` manifests-then-serializes. Also houses the standard padded base64 encoder
  `base64Encode : List UInt8 → String`. Factored standalone (imports `Manifest`; `Builtin`
  imports it) so **B5 reuses `manifestToJson` verbatim for `--out json`**.
- **`Kue/Builtin.lean`** — `evalBase64Builtin` + `evalJsonBuiltin` dispatchers, routed by
  `base64.` / `json.` name prefix, each ending in the shared `unresolvedOrBottom`. New
  `isPendingArg` predicate separates a genuinely-incomplete concrete shape (`{a: int}` →
  bottom) from an unresolved ref form (preserved for a later pass).
- **Oracle-confirmed (`cue` v0.16.1):** `base64.Encode(null, …)` = standard padded base64
  over UTF-8 bytes; non-null selector → bottom. `json.Marshal` keys are **source-order,
  NOT sorted**; output compact (`,`/`:`, no spaces); floats keep exact spelling
  (`1.50`→`"1.50"`); bytes → base64 JSON string; `<>&/` and non-ASCII NOT escaped (cue
  disables Go HTML escaping); incomplete value → bottom.
- **Tests:** 3 fixture pairs (`base64_encode`, `json_marshal`, `encoding_infra_chain`) +
  `FixturePorts.lean` AST ports; 17 `BuiltinTests.lean` `native_decide` theorems.

Verify gate green: `lake build` (70 jobs), `scripts/check-fixtures.sh` ⇒ `fixture pairs
ok`, `shellcheck` clean. The docker-config chain `base64.Encode(null, json.Marshal({auths:
registry}))` evaluates byte-for-byte against `cue`.

### Deferred (documented in compat-assumptions, not bugs)

- `base64.Encode` non-null encodings; `base64.Decode`; `json.MarshalStream` / `Indent` /
  `Unmarshal` / `Validate`.
- The real `infra-defs/secret.cue` references a **hidden** field (`_auths`); hidden-field
  references do not yet resolve in Kue (pre-existing reference-resolution gap, separate
  from B6). `secret.cue` is also still blocked at the non-string label-pattern parser gap.
  The encoding builtins themselves are not the blocker.

## Alpha status

v0.1.0 staged; cut locally via `scripts/release.sh` on chakrit's "cut a slice" command
(**NO GitHub Actions — banned**; there is no `.github` dir, do not create one; release
tooling owned elsewhere — do **not** touch `scripts/release.sh` / `packaging/`). External
repos (prod9/infra etc.) are **read-only**.

## Next session — implementation focus: B5 — manifest output

Per `plan.md` Current Focus (prod9/infra roadmap B1→B6). B1, B2, B4, B6 done; **B5 is now
active**: a YAML/JSON serializer over `Kue/Manifest.lean` + a `cue export`-style CLI mode
(select expr, `--out yaml/json`, multi-doc streams) — the first true end-to-end manifest
on a self-contained leaf file.

- **Reuse `Kue/Json.lean`'s `manifestToJson` for `--out json`** (do NOT re-implement it).
- **Add a YAML serializer over the same `ManifestValue`** plus `yaml.Marshal` (sharing
  that code, same dotted-dispatch pattern as B6: `evalYamlBuiltin` + `yaml.` route +
  fixtures + theorems).

Roadmap after B5: B3 module/import resolution (the big one, LAST — packages gate every
real `infra/apps/*`).

### Carry-forward boundaries (unchanged)

- **PENDING AUDIT — parser+alias batch** (`0795530`/`7ec51a4`/`f6c18b5`/`804f1ca`): the
  `/ace-audit` depth pass over the B1/B2 batch failed three times on transient API 500s and
  never completed. Orchestrator spot-check cleared the #1 risk (`Value.thisStruct`). A full
  audit is still owed — re-run when the API is stable. Do not let it block forward slices.
- **Newly-surfaced parser gaps (post-B5 candidates):** open-list `[...]` expressions and
  non-string label patterns `[string]: string`. These (plus hidden-field reference
  resolution) block the remaining real infra files.
- **Hidden-field references do not resolve** (`y: _a` where `_a` hidden → bottom) — a
  pre-existing reference-resolution gap surfaced while oracle-checking the B6 infra chain.
- **No imports / module resolution** (B3, last). Builtins work via implicit dotted names;
  real `import`s parsed-and-ignored.
- **Separators stay permissive** — `a: 1 b: 2` parses as two fields, no error.
- **No `list.Sort`/`SortStable`**; **non-ASCII case folding** passes through; remaining
  `strings`/`math` funcs parked per Current Focus (core-language over stdlib).
- **Multiline bytes interpolation deferred** (B4).
