<!-- not spec/decision because: live cross-session breadcrumb; disposable, superseded in place -->

# Session resume — 2026-07-11

Clean tree, `main` == `gh/main` at `b00129e`. `check.sh` GREEN. Standing keep-going loop
governs (the 2026-07-07 "autonomy paused" gate is resolved/historical).

## This session (2026-07-10→11) — two LOW slices + a wild-caught STDLIB campaign

Attended. chakrit asked: do the queued LOW tasks, then test-drive kue on interesting
internet CUE examples. The test-drive (tour + cuetorials examples vs `cue` v0.16.1) matched
on simple cases and surfaced a whole frontier: **the CUE stdlib is ~1/3 implemented.** Ten
slices + a two-phase audit landed, all pushed, all green.

### Landed (git `00a706d..b00129e`)

- **AUD-B5 `8ed98e1`** — DRY'd the two BFS requirement-graph builders into
  `bfsRequirementGraphAux` (leaf-callback combinator, structural on fuel; AD4-1 shape).
- **B3d-B1 `be936dc`** — `Hash1` newtype for the cue.sum h1 digest; eliminated a latent
  fake-empty-h1 seed (real illegal-states win).
- **STDLIB-A `4625079`** — stdlib import ROUTING: `isStdlibImportPath` (dot-free first path
  element ⇒ builtin layer; dotted-domain ⇒ external module) + clear
  `unsupported builtin package "<path>"` error, no more misleading `no cue.mod`.
- **STDLIB-B `2c3ce9e`** — `struct.MinFields/MaxFields` as a `meet`-participating
  `fieldCountConstraint` validator (counts REGULAR fields only; optional/required/hidden/
  def/`let` excluded).
  - **FIELDCOUNT-DISJ `9a32bdb`** (Phase-A audit fix) — retained-min residual inside a
    disjunction arm wasn't finalized on collapse → spurious "ambiguous". `finalizeDisjArm`
    (`Manifest.lean`) finalizes each arm at manifest; accretion untouched.
- **STDLIB-C `326b8c4`** — `strconv` package (`Kue/Strconv.lean`, `.strconv` family).
  Shipped Atoi/FormatInt/FormatUint/ParseInt/ParseUint/FormatBool/ParseBool (arbitrary
  precision, base-0 prefixes + underscores + bitSize). Deferred → unsupported-fn error:
  Itoa (non-callable in cue), FormatFloat/ParseFloat (exact-decimal core),
  Quote/Unquote/… (Unicode IsPrint table). Divergence: base 2..36 vs cue's leaked 2..62.
- **STDLIB-D `d902e03`** — root cause was NOT import-specific: kue lacked CUE statement
  separation entirely. Implemented newline-as-implicit-comma (`skipSameLineTrivia` +
  `fieldSeparator`); `a: 1 b: 2` / late imports now rejected. Broad parser change, audit
  verified sound.
- **STDLIB-E `7707355`** — render-only: cue-shaped `imported and not used: "<path>"`
  (`" as <alias>"` aliased).
- **LIST-SEP `2c3659b`** — list-element separators (reuses D's `fieldSeparator`). `[1 2]`
  now errors; `[1\n2]`→`[1,2]` (spec auto-comma — **kue is more spec-correct than cue here:**
  cue rejects newline-elision in `[]` while accepting it in `{}`, its own inconsistency;
  recorded in `cue-divergences.md`).
- **audit-followup `b00129e`** — closed the two Phase-B LOW nits (doc-count drift;
  `every_builtin_package_resolves_to_family` sync theorem) + Phase-A #3 (strconv deferred-fn
  now renders `unsupported builtin function "strconv.Quote"`). Recorded (not fixed) the
  block-comment leniency.

### Two-phase audit (over the batch) — DONE

Phase A (code-quality) found the FIELDCOUNT-DISJ correctness bug (fixed) + its test gap +
the strconv-diagnostics nit; verified STDLIB-D's ASI change sound. Phase B (architecture)
clean — the builtin-package dispatch SCALES (~2 files + optional leaf per package), so the
stdlib campaign is cheap to continue. Both audits logged.

## Next steps — the STDLIB frontier (see `plan.md` § Ranked OPEN backlog)

Two tracks:

1. **Spec-conformance (unambiguous, no priority call):** `BLOCK-COMMENT-REJECT` (queued) —
   kue accepts `/* */` that CUE forbids; mind blast radius (`ModCmd.lean` scanner also
   honors `/* */`). Wild fixture RED-first.
2. **New stdlib packages (priority-sensitive — key to which packages prod9 configs hit):**
   `time`, `net`, `path`, `uuid`, `crypto/*`, `encoding/hex|csv`, `text/template`; finish
   `strconv` (Quote/FormatFloat need a Unicode IsPrint table / float-format design); round
   out `strings`/`list`/`math`. Dispatch cost is low (audit-confirmed).

Test-drive scratch files at `~/Documents/chakrit/kue-testdrive/` (outside the repo).

## Historical (not this session)

- ace-connect bridge (slug `chakrit.kue.claude`, control mode) was live in the 2026-07-07
  session; NOT touched this session — do not assume it's still running. Recover per
  ace-connect Flow step 4 if needed.
- 2026-07-07: AUD-B6 (`b1be061`), release `v0.1.0-alpha.20260707.1`. Detail in the log.

## Pending school changes

None this session.
