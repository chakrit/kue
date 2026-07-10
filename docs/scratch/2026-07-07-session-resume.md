<!-- not spec/decision because: live cross-session breadcrumb; disposable, superseded in place -->

# Session resume — 2026-07-07

> chakrit: real-world test-drive day for the alpha. This session ran the bridge + one slice
> + a release under an explicit "stop when done, don't march" gate. **Autonomous
> implementation is PAUSED** until chakrit says resume.

Clean tree, `main` == `gh/main` at `0c7aefb`. `check.sh` GREEN (AUD-B6 slice verified it).

## What landed

- **AUD-B6 — `b1be061`** (via subagent). Audit premise was *inverted*: the supposed
  false-positive unused-import was actually Kue being too *lenient* — it bound
  `import "…/foo"` where dir `foo/` declares `package bar`, which `cue` v0.16.1 rejects
  (`no files in package directory with package name "foo"`). Fix: bind-name resolution made
  purely lexical (one param-free `importBindName` in `Value.lean`; the two-arg
  `Parse.importLocalBindName`/`Module.importBindName` forms deleted — DRY) + the **F-3
  suffix-vs-declared-name gate** enforced in `collectBindings`. Closes the F-3 residual open
  since 2026-06-20. Fixtures: `import_bare_pkgname_mismatch` (red→green),
  `import_qualifier_pkgname_rescue` (`:bar` qualifier rescue). Not a divergence — it
  *removes* a latent one. Detail: `docs/spec/implementation-log.md` (AUD-B6 entry).
- **`.inbox.log` gitignored — `0c7aefb`** (ace-connect control-mode inbox artifact).
- **Release `v0.1.0-alpha.20260707.1`** — all 3 assets (macOS arm64, linux amd64+arm64),
  tap bumped + pushed clean. Pushed `main` *before* `release.sh` so the tag sits on the
  pushed branch (release-consistency practice now recorded in the distribution decision doc).

## Bridge state (LIVE)

ace-connect engine running, slug `chakrit.kue.claude`, **control mode**, on a persistent
Monitor. One peer exchange this session: `prod9.infra-defs.claude` asked how to get a kue
binary → answered (prebuilt asset / brew tap / `lake build`); they'll ping on divergences
that look like `cue` bugs. Logged in `.inbox.log`. If resuming post-`/clear`, the Monitor
survives context wipe — don't rebind the slug; recover per ace-connect Flow step 4.

## STDLIB campaign (2026-07-10) — wild-caught from an alpha stdlib test-drive

Slices **A–F all LANDED** (2026-07-10). Earlier follow-on **STDLIB-F queued** in `plan.md` § Ranked OPEN
backlog. Test-drive against `cue` v0.16.1 surfaced five findings:

- **A — stdlib import ROUTING + error quality. ✅ LANDED.** kue misrouted dot-free stdlib
  paths (`strconv`, `struct`, `time`) to the disk loader → misleading `no cue.mod…`. Fixed by
  the STRUCTURAL rule: `isStdlibImportPath` (dot-free first path element = builtin layer;
  dotted-domain = external module) + `isUnimplementedBuiltin` (`Kue/Value.lean`); loader emits
  `unsupported builtin package "<path>": …` (`collectBindings` + `loadFileBound`,
  `Kue/Module.lean`). Wild fixture `testdata/wild/stdlib-import-misrouted-to-disk-loader/`.
  Spec-gap + log recorded.
- **B — `struct` builtin package. ✅ LANDED.** `struct.MinFields`/`MaxFields` via a new
  `Value.fieldCountConstraint (FieldCountBound) (Int)` validator participating in `meet`
  (`applyFieldCountConstraint`/`finalizeFieldCountConj`, `Kue/Lattice.lean`). Counts only
  REGULAR fields (optional/required/hidden/def/`let` excluded). Fixture
  `testdata/export/struct_field_count`; `fieldcount_*` theorems. Spec-gap + log recorded.
  - **Follow-up FIELDCOUNT-DISJ ✅ (2026-07-10, Phase-A audit fix).** A retained `min` residual
    inside a disjunction arm wasn't finalized on collapse → spurious "ambiguous" on
    `MinFields(2) & ({a:1} | {a:1,b:2})`. Fixed: `finalizeDisjArm` (`Kue/Manifest.lean`) finalizes
    each arm at manifest (reusing `finalizeFieldCountConj`); manifest-only, accretion untouched.
    Wild fixture `min-fields-disj-arm-underfill-pruned`; `fieldcount_disj_*` theorems (8).
- **C — `strconv` builtin package. ✅ LANDED.** Pure conversions in `Kue/Strconv.lean` via a
  new `.strconv` `BuiltinFamily` arm. Shipped: `Atoi`, `FormatInt`, `FormatUint`, `ParseInt`,
  `ParseUint`, `FormatBool`, `ParseBool` (arbitrary-precision; base-0 prefixes + underscores +
  `bitSize` range). Deferred (→ `unsupportedBuiltin`): `Itoa` (non-callable in cue),
  `FormatFloat`/`ParseFloat` (exact-decimal core), `Quote`/`Unquote`/… (Unicode `IsPrint` table).
  Divergence: base restricted to Go's `2..36` (cue leaks `2..62`) — `cue-divergences.md`. Fixture
  `testdata/export/strconv_basic`; `Kue/Tests/StrconvTests.lean` (52 theorems). Wild fixture
  `stdlib-import-misrouted-to-disk-loader` repointed `strconv`→`time` (retraction).
- **D — import-placement parse grammar. ✅ LANDED (2026-07-10).** Root cause was NOT
  import-specific: kue lacked CUE's statement separation entirely — the operator-precedence
  chain crossed newlines when hunting a trailing operator, so a newline never terminated an
  expression and consecutive declarations with no comma passed (`x: 1\nimport "strings"`,
  `foo "bar"`, `a: 1 b: 2`). Fixed by CUE's implicit-comma-at-newline: `skipSameLineTrivia`
  for trailing-operator lookahead (operator-at-line-END still continues) + `fieldSeparator`
  enforcement in `parseFieldsUntil` (`missing ',' in struct literal`). Wild fixture
  `testdata/wild/import-after-decl/`; parse theorems in `Kue/Tests/ParseTests.lean`. Spec-gap
  STDLIB-D + log recorded.
- **E — unused-import diagnosis MESSAGE. ✅ LANDED (2026-07-10).** Confirmed render-only:
  `Manifest.ManifestError.importedNotUsed` + `unusedImportReasons` route the `.importedNotUsed`
  bottom reason to `Runtime.formatManifestError`, which now renders cue's `imported and not used:
  "<path>"` (`" as <alias>"` aliased, one line per unused import). Wild fixtures
  `testdata/wild/{unused-import,unused-import-aliased,used-import-ok}/`; render pins
  `*_render_message` in `ImportEnforcementTests`.

STDLIB campaign A–E all LANDED.

- **F — list-item separator enforcement. ✅ LANDED (LIST-SEP, 2026-07-10).** Mirrored slice D's
  `fieldSeparator` into `parseListItems` (DRY — same helper, no parallel separator). `[1 2]` now
  errors `missing ',' in list literal`; `[1\n2]`→`[1, 2]` (spec auto-comma; cue rejects newline-
  elision inside `[]` while accepting it for structs — a cue bug, recorded in `cue-divergences.md`).
  Wild `testdata/wild/list-same-line-no-comma`; `ParseTests` LIST-SEP block. Detail in log.

### STDLIB-batch two-phase audit followup (2026-07-10) — LANDED

Closed the three remaining LOW/polish findings from the STDLIB-batch two-phase audit in one
audit-followup commit: **Phase-B LOW-1** (`BuiltinFamily` doc drift 8/7 → 9/9 corrected),
**Phase-B LOW-2** (new `every_builtin_package_resolves_to_family` sync theorem pinning
`builtinPackageNames` ↔ `BuiltinFamily.ofName?`), **Phase-A finding #3** (strconv deferred-fn
now renders `unsupported builtin function "strconv.Quote": …` via new
`ManifestError.unsupportedBuiltinFunction`, not generic bottom). Also VERIFIED + recorded (not
fixed) a kue-leniency bug: kue accepts `/* */` block comments; cue+spec reject → `cue-divergences.md`
§ Known kue-side divergences + QUEUED `BLOCK-COMMENT-REJECT` in `plan.md`. `check.sh` GREEN.

**Next:** STDLIB campaign + its audit followup all landed. `BLOCK-COMMENT-REJECT` is the freshest
QUEUED item (parser conformance — mind blast radius: `ModCmd.lean` scanner also honors `/* */`);
otherwise pick from `plan.md` § Ranked OPEN backlog. The "autonomy paused" gate above is HISTORICAL to
the 2026-07-07 attended session — the standing keep-going loop governs.

## Pending school changes

None this session.
