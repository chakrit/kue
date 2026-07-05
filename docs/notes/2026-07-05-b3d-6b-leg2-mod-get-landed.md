# B3d-6b-leg2 LANDED — `cue mod get` (deps-block emitter + tags/list latest) (2026-07-05)

`kue mod get <module>[@version]` adds/updates a dependency in `cue.mod/module.cue`. This closes
B3d-6b's final FILED dependent — **B3d-6b is now FULLY CLOSED** (core + leg4 + leg2 all landed
2026-07-05). No remaining substantive registry slice.

## What landed (all in `Kue/ModCmd.lean`)

- **Deps-block emitter** (the capability kue lacked). `applyModGet`: parse existing deps, merge the
  target (`mergeDep`, keyed on module path + major via `depKey` — distinct majors coexist),
  re-render ONLY the `deps` block (`renderDepsBlock`, canonical tab-indented, keys sorted), splice
  it back preserving all non-deps content. The splice uses a string/brace-aware textual excision
  (`exciseTopLevelDeps`/`exciseAux`/`afterDepsField`/`dropBalanced`) — fuel-bounded, total, no
  `partial`. A present-but-unlocatable deps block ERRORS (no conflicting second block).
- **Tag "latest" resolution.** `parseVerSpec` (`latest`/exact/major/majorMinor) + `resolveVerSpec`
  filter valid NON-prerelease semver matching the constraint, take the max (`Semver.maxVersion`).
- **Pure driver** `modGetResolveAndApply` (source + arg + in-memory tags → `(version, newSource)`)
  — the whole pipeline is offline `native_decide`-checkable; the network only supplies tags.
- **IO edge (production-only, no gate depends on it):** `Oci.tagsListUrl` + `ModCmd.ociListTags`
  (read-only `.../tags/list` GET via `OciFetch.authedGet`); `runModGet` reads → conditionally
  fetches tags (a full `@vX.Y.Z` skips the network) → resolves+emits → atomic write.
- **Wiring:** `Cli.lean` `ModOp.get` + `parseMod` + help; `Main.lean` `runModGet` dispatch.

## Emitter approach: structured deps + textual excision (NOT a full CUE printer)

kue has no CUE pretty-printer, and `cue mod get` reformats the WHOLE file (expands shorthand,
drops comments). Reproducing that would need a full printer (the "too large" stop condition) AND
risks data loss on unknown fields. Chosen instead: emit ONLY the canonical `deps` block (which IS
byte-identical to cue) and preserve every other byte verbatim. Verified byte-identical to
`cue mod edit --require` for the canonical block-form add; the non-deps reformatting divergence is
spec-silent — recorded in `cue-spec-gaps.md` (MODULE.CUE REFORMATTING).

## How "latest" was tested offline

`resolveVerSpec` and `modGetResolveAndApply` take an in-memory tag list, so `native_decide`
theorems ARE the offline end-to-end test (no fixture/script, no network). Pinned: latest picks the
semver-max non-prerelease tag; `@v1` resolves to the max `v1.x`; prereleases and non-semver tags
are filtered; empty/no-match ⇒ typed error. A live `tags/list` smoke can be run MANUALLY but is
never a gate dependency.

## Tests

40 `native_decide` in `Tests/ModCmdTests.lean` (emitter add/update/preserve/sort/nested-brace/
string-with-braces/token-boundary + spec parse + resolve + end-to-end incl. no-op/downgrade/error
cases) + `Tests/CliTests.lean` parse pins (`parse_mod_get` replaces the retracted deferral pin).

## Verify + retraction

`./scripts/check.sh` GREEN (all gates; cert-manager realworld canary byte-identical — it does not
run `mod get`, confirmed untouched; shellcheck PASS). Retraction of leg2's "deferred / needs
deps-block emitter" claim closed in the same slice: `plan.md` (item #1 + § B3d track),
`compat-assumptions.md`, `Cli.lean`/`ModCmd.lean` comments, `CliTests.lean`, and the two active
2026-07-05 notes (core-landed + consolidation) carry RESOLVED pointers.

Committed on `main`, explicit pathspec, NOT pushed. **Broader front returns to eval-conformance**
(`plan.md` § Current front) — the substantive registry track (B3d-6b) is done.
