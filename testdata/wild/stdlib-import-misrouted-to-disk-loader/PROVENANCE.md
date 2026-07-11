# stdlib-import-misrouted-to-disk-loader  (stdlib campaign — slice A)

- **Source:** wild-caught 2026-07-10 during a stdlib test-drive against `cue` v0.16.1
  (`/Users/chakrit/go/bin/cue`). `printf 'import "strconv"\nx: strconv.Atoi("42")\n'` then
  `kue export` produced `kue: no cue.mod/module.cue found in any parent directory` — the
  disk module-loader error — while `cue` recognized `strconv` as a standard-library import.
- **CUE construct at fault:** a recognized-but-unimplemented stdlib import. kue's builtin
  whitelist (`Kue/Value.lean` `builtinImportPaths`) covered only
  strings/list/math/regexp/encoding/{base64,json,yaml}; `isBuiltinImport` is a membership
  test, so every other path — including dot-free stdlib paths (`strconv`, `struct`, `time`)
  — fell through to `resolveImportTarget`/the disk loader.
- **Direction: MISROUTING / WRONG-ERROR.** Both kue and cue reject (strconv.Atoi is
  unimplemented here), but kue rejected for the wrong reason with a misleading message.
- **Root cause:** routing keyed off an implemented-whitelist membership test instead of the
  STRUCTURAL stdlib-vs-external distinction CUE uses — a stdlib/builtin path's first element
  carries no domain (no dot), an external module path's first element is a domain. Fixed by
  `isStdlibImportPath` (dot-free first path element) + `isUnimplementedBuiltin`: a recognized
  stdlib path absent from `builtinImportPaths` now yields a clear "unsupported builtin
  package" error; external (dotted) paths keep going to the module loader unchanged.
- **Spec basis:** CUE distinguishes import paths structurally — a non-domain-qualified first
  element names a standard-library package. Recorded in `docs/spec/cue-spec-gaps.md` (the
  exact unimplemented-builtin error text is kue's principled choice; spec is silent on it).
- **Graduated GREEN** in the same slice: the routing fix emits the clear error, so the
  fixture pins `unsupported builtin package "<pkg>"` as its stable `.expected.err`
  substring. Not `.known-red`.
- **Retraction (STDLIB-C, 2026-07-10):** `strconv` is now implemented, so it no longer
  hits the unimplemented-routing path. The fixture was REPOINTED to `time` to keep the
  routing/error contract under guard — the guard is package-agnostic, not about `strconv`
  specifically.
- **Retraction (STDLIB-TIME, 2026-07-11):** `time` is now implemented (`import "time"`
  resolves), so it no longer hits the unimplemented-routing path either. REPOINTED to `net`
  (still an unimplemented dot-free stdlib package cue recognizes) — same package-agnostic
  routing/error guard.
