# Release + Homebrew setup (2026-06-16)

Authored the in-repo half of binary releases and `brew install` for Kue, modeled on
`ace-rs/ace`. This note records the distribution choice, what landed in-repo, and the
exact external steps chakrit must authorize to make `brew install` live.

## Distribution choice: ship prebuilt binaries (not build-from-source)

The hard Lean question was whether a lake-built `kue` binary is self-contained or
whether it drags in the Lean runtime dylibs from the elan toolchain. Verified on the
local arm64 build:

```
$ otool -L .lake/build/bin/kue
	/usr/lib/libc++.dylib
	/usr/lib/libSystem.B.dylib
```

Only macOS system libraries. Lean 4's default `lake build` links the Lean runtime
**statically** into the executable, so the binary is self-contained — no elan, no
bundled dylibs. That makes the ace pattern (ship a prebuilt arm64 asset, formula
`bin.install`s it) directly applicable. Chosen over a build-from-source formula
(`depends_on elan`, run `lake build`) because it is faster to install and more
reproducible: the bits users get are exactly the bits CI built and checksummed, not a
recompile against whatever toolchain state the user's machine has.

## How ace does it (reference)

- No GitHub Actions. A local `release.sh` bumps the version, cross-builds all targets
  (`build-all.sh` via cargo-zigbuild), sha256s the macOS arm64 binary, sed-patches the
  formula, commits, tags `v<x.y.z>`, pushes, `gh release create --generate-notes`, then
  `git subtree push` of the in-repo `homebrew-tap/` to the `gh-tap` remote.
- Tap repo: `ace-rs/homebrew-tap`, formula at `Formula/ace.rb`. Install:
  `brew install ace-rs/tap/ace`.
- Formula carries only the macOS arm64 asset + sha; `depends_on arch: :arm64`,
  `depends_on :macos`; `test do` runs the binary.

## What Kue does differently

- **CI-driven, not a local script.** Release builds run in GitHub Actions on a `v*` tag
  push (`.github/workflows/release.yml`), one runner per platform with a clean
  elan-installed toolchain. More reproducible than a developer laptop; aligns with the
  repo's precise/testable philosophy. (ace cross-compiles Rust locally with zig; Lean
  has no comparable mature cross-compiler, so per-platform native runners is the robust
  path.)
- **No `version` subcommand.** `kue` treats any arg as a file path, so the formula
  `test` can't run `kue version`. It pipes CUE through stdin instead and asserts output:
  `printf 'x: int & 1\n' | kue` -> `x: 1`.

## In-repo artifacts (landed)

- `.github/workflows/release.yml` — on `v*` tag push, builds `kue` on macOS arm64
  (`macos-14`), macOS x64 (`macos-13`), and Linux x64 (`ubuntu-latest`), uploads each as
  `kue-<target>`, then a `release` job publishes them to the GH Release with
  `--generate-notes`. Uses `github.token` (no extra secret for the release itself).
- `packaging/homebrew/kue.rb` — the formula. Source of truth lives here; it must be
  published to the tap repo to take effect. `version`/`url`/`sha256` are placeholders
  until the first real release.
- README "Installation" section — `brew install chakrit/tap/kue` plus the
  build-from-source fallback.

## Remaining external steps (require chakrit's authorization — NOT done here)

1. **Create the tap repo** `chakrit/homebrew-tap` on GitHub (public). Homebrew maps
   `brew install chakrit/tap/kue` to repo `chakrit/homebrew-tap`, file `Formula/kue.rb`.
2. **Publish the formula** into that repo at `Formula/kue.rb`. Either copy
   `packaging/homebrew/kue.rb` there manually, or wire a `git subtree`/sync step like
   ace's `release.sh` does. (No external repo was created or pushed from this session.)
3. **Cut the first release.** Push a tag, e.g. `git tag v0.1.0 && git push gh v0.1.0`.
   That triggers `release.yml`, which builds and publishes the assets. Do NOT tag from an
   automation session — chakrit cuts the first tag deliberately.
4. **Patch the formula with the real asset URL + sha256.** After the release publishes,
   compute `shasum -a 256 kue-aarch64-apple-darwin` (download from the release), set
   `version`, `url`, and `sha256` in `Formula/kue.rb` in the tap repo. A future
   enhancement: extend `release.yml` (or a small `release.sh`) to auto-patch and push the
   formula, mirroring ace — needs a `HOMEBREW_TAP_TOKEN` (a PAT or fine-grained token
   with `contents:write` on `chakrit/homebrew-tap`) added as an Actions secret, since
   `github.token` only grants write to the current repo, not the tap repo.

## Secrets summary

- Publishing the release itself: none beyond the built-in `github.token` (workflow has
  `permissions: contents: write`).
- Auto-pushing the formula to the tap repo from CI (optional, step 4): a cross-repo
  `HOMEBREW_TAP_TOKEN` secret. Until that exists, the formula is updated manually.
