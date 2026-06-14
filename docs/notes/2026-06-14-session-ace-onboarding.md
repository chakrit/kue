# Session 2026-06-14 — ACE onboarding, lowfat migration, docs tightening

End-of-session breadcrumb. Resuming **implementation** next session.

## What was done

- **ACE re-onboard (`/ace-init`).** Repo was already onboarded; trimmed the active skill
  set in `ace.local.toml` from `["*"]` to `general-coding, cue-coding, markdown-writing,
  shell, skill-creator` (the rest were design/web/other-language noise). User-global
  skills unaffected.
- **RTK → lowfat (`305da42`).** lowfat 0.6.8 was already installed + hooked globally;
  `.rtk/filters.toml` held no custom filters. Removed `RTK.md`, `.rtk/`, and RTK refs in
  `AGENTS.md`/`CLAUDE.md`/`.gitignore`. lowfat runs transparently via the user-scope hook.
- **docs/ scaffold + migration (`c28c354`).** Adopted the ace-docs two-cluster layout
  (`guides/ reference/` + `spec/ decisions/ notes/`). Moved flat docs into buckets
  (history preserved via rename); `docs/README.md` is the index.
- **docs tightening (`e08d682`).** Split `plan.md` (3,200 → 71 lines): live roadmap in
  `spec/plan.md`, completed-slice record in `reference/implementation-log.md` (kept for
  verification). Rewrote `spec/architecture.md` to the real module layout. Fixed the
  stale module map in `guides/lean4-guide.md`. Regrouped `compat-assumptions.md`. Added
  ADR `decisions/2026-06-14-cue-compatibility-target.md`.

All pushed; `main` even with `gh/main` at `e08d682`. Build + full fixture suite +
shellcheck were green.

## North star (reconfirmed this session)

Kue targets **correct CUE v0.15 semantics**, *not* bug-for-bug parity with the official
`cue` binary — the buggy v0.15 binary is the thing Kue exists to replace. Toolchain pin
stays v0.15.4 (local `cue` is v0.16.1, used only for `cue fmt`). See the ADR.

## Next session — implementation focus

1. **Pick up the TDD slice loop** from `docs/spec/plan.md` → *Later Slices*. Natural next
   candidates: comprehensions / dynamic fields (needs richer lexical binding scope), or
   remaining builtins. One slice per commit; commit subject mirrors the slice title;
   append the completed slice to `reference/implementation-log.md`.
2. **Fixture-as-oracle audit (from the ADR consequence).** `testdata/cue/*.expected` were
   cross-checked against `cue eval`, so they may encode official-v0.15 bugs. Before
   leaning on them as ground truth, audit against *intended* semantics and, where the
   binary is wrong, encode the correct value with a noted divergence. Good standalone
   slice.

## Process notes

- Verify gate: `lake build` then `scripts/check-fixtures.sh` then
  `shellcheck scripts/check-fixtures.sh`. The fixture script prints only `fixture pairs
  ok` on full success (stages are silent unless they fail).
- Skill set is now narrow — `general-coding` + `cue-coding` are the load-bearing ones for
  implementation work.
