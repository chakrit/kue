# Releasing Kue

How to cut a Kue release. **Local only — GitHub Actions / CI is banned.** The entire
pipeline is `scripts/release.sh`; this file is the checklist around it so steps run in the
right order and none are forgotten. Design rationale lives in
[`docs/decisions/2026-06-16-distribution-prebuilt-local-release.md`](docs/decisions/2026-06-16-distribution-prebuilt-local-release.md).

## Cadence & versioning

- Roughly **one alpha per day**, datestamped: `0.1.0-alpha.YYYYMMDD`.
- A second build the same day gets a `.N` suffix: `0.1.0-alpha.YYYYMMDD.2`, `.3`, …
- **Version constant.** `kue version` / `kue --version` prints `Kue.version`, defined in
  [`Kue/Runtime.lean`](Kue/Runtime.lean) (`def version : String := "0.1.0-alpha"`). It is
  the single in-binary source of truth and is currently a static placeholder, not the
  datestamped release tag. A future `release.sh` step should rewrite this constant to the
  `<version>` being cut so the shipped binary self-reports its release; until then it
  trails the tag. (Not wired in this slice — `release.sh` left untouched.)
- Cut from an **audited, releasable** `main` HEAD (see step 1). Alpha quality may ship with
  documented known gaps, but never a crash, non-termination, or half-landed work.

## Preconditions (verify before cutting)

1. **Host:** macOS **arm64**. The formula ships an arm64 asset only; `release.sh` refuses
   to run elsewhere. (Other platforms build from source — that's fine, not released.)
2. **Branch & tree:** on `main`, working tree **clean** (`git status` empty). `release.sh`
   refuses a dirty tree.
3. **HEAD is releasable:** the last code landed at HEAD has passed the loop's two-phase
   audit (Phase A code-quality + Phase B architecture, per
   [`docs/guides/slice-loop.md`](docs/guides/slice-loop.md)). Do NOT release un-audited
   mid-batch work — cut from the audited point, don't chase "one more fix" into unaudited
   code.
4. **Tap clone present:** `chakrit/homebrew-tap` cloned at `../homebrew-tap` relative to
   this repo (sibling dir), or set `KUE_TAP_DIR=<path>`. The tap clone must be clean and on
   `main` (the script does `git pull --ff-only` then commits + pushes the formula).
5. **`gh` authenticated** as the repo/tap owner with `repo` scope (`gh auth status`).

## Pre-release verify gate (must be green)

```sh
./scripts/check.sh   # lake build + every scripts/check-*.sh gate (glob) + shellcheck scripts/*.sh
```

## Cut the release

```sh
scripts/release.sh <version>     # e.g. scripts/release.sh 0.1.0-alpha.20260617.2
```

`release.sh` runs these steps (in order) — know what it does so a mid-run failure is
diagnosable:

1. Guards: macOS arm64, clean tree, tap formula exists.
2. `lake build kue` → host binary at `.lake/build/bin/kue`.
3. Stage `dist/kue-aarch64-apple-darwin`; compute its `sha256` (printed).
4. Ensure the `v<version>` tag exists; push it to `gh`.
5. Publish the GitHub Release: `gh release create` (or `gh release upload --clobber` if the
   release already exists) with the asset.
6. Patch the tap formula (`Formula/kue.rb`): `version`, `url`, `sha256`.
7. Tap: `git pull --ff-only`, commit `kue <version>`, push.

## Post-release verification (always run — confirms the chain is coherent)

```sh
# formula on the remote tap points at the new version + matching sha
gh api repos/chakrit/homebrew-tap/contents/Formula/kue.rb --jq '.content' \
  | base64 -d | grep -E '^\s*(version|url|sha256)'

# the release asset exists at the tag
gh release view v<version> --repo chakrit/kue --json assets --jq '.assets[].name'
```

Confirm: formula `version`/`url`/`sha256` match the `<version>` and the `sha256` printed by
`release.sh`, and the asset `kue-aarch64-apple-darwin` is present. (Do NOT `brew install`
to "test" from the session — that mutates the host; let the user verify.)

## User install / upgrade

```sh
brew install chakrit/tap/kue        # first time (taps implicitly)
brew update && brew upgrade kue     # subsequent releases
```

## Fixups

- **Wrong/stale formula sha or url:** re-run `scripts/release.sh <same version>` — step 5
  re-uploads with `--clobber` and step 6 re-patches the formula. Idempotent.
- **Bad tag:** `git push gh :refs/tags/v<version>` (delete remote) + `git tag -d v<version>`
  (delete local), then re-cut. Only safe if no one has installed that version.
- **Delete a bad release:** `gh release delete v<version> --repo chakrit/kue`.

## Out of scope (do not add)

- **GitHub Actions / any CI** — banned. Releases are local-script only.
- **Registry publishing**, cross-platform binaries (host arm64 only), MVS/version solving.
  Other platforms build from source per the README.
