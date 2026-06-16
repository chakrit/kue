# Release + Homebrew setup (2026-06-16)

Binary releases and `brew install` for Kue, modeled on `ace-rs/ace`. Releases are cut
**locally** — there is no CI and no GitHub Actions (banned). `scripts/release.sh` is the
whole pipeline; running it is gated on chakrit saying "cut a slice".

## Distribution choice: ship a prebuilt binary (not build-from-source)

The hard Lean question was whether a lake-built `kue` binary is self-contained or drags
in the Lean runtime dylibs from the elan toolchain. Verified on the local arm64 build:

```
$ otool -L .lake/build/bin/kue
	/usr/lib/libc++.dylib
	/usr/lib/libSystem.B.dylib
```

Only macOS system libraries. Lean 4's default `lake build` links the Lean runtime
**statically** into the executable, so the binary is self-contained — no elan, no
bundled dylibs. So the ace pattern applies directly: ship a prebuilt arm64 asset, formula
`bin.install`s it. Chosen over a build-from-source formula (`depends_on elan`, run `lake
build`) because it installs faster and is more reproducible — users get exactly the bits
released, not a recompile against whatever toolchain state their machine has.

## Release mechanism: local script, no CI

`scripts/release.sh <version>` (e.g. `scripts/release.sh 0.1.0`) is the entire pipeline,
same shape as ace's `release.sh` (ace also uses no Actions):

1. Guards: must run on macOS arm64 with a clean working tree; tap formula must exist.
2. `lake build kue` → host arm64 binary at `.lake/build/bin/kue`.
3. Stage `dist/kue-aarch64-apple-darwin`, compute its `sha256`.
4. Ensure the `v<version>` tag exists, push it.
5. `gh release create` (or `gh release upload --clobber` if the release exists) with the
   asset.
6. `sed`-patch the tap formula's `version`/`url`/`sha256`, commit, push the tap.

**Host-only build is the one divergence from a full ace-style release.** ace
cross-compiles all targets locally with cargo-zigbuild; Lean has no comparable
cross-compiler, so we build for the host only. That is sufficient: the formula is
arm64-macOS-only (`depends_on arch: :arm64`, `depends_on :macos`), which is the only
platform served by `brew`. Other platforms build from source per the README.

Auth is chakrit's local `gh` login (scopes `repo`) plus the local tap clone — no tokens,
no secrets, nothing stored in any repo.

## `kue` has no `version` subcommand

`kue` treats any arg as a file path, so the formula `test` can't run `kue version`. It
pipes CUE through stdin and asserts output instead: `printf 'x: int & 1\n' | kue` →
`x: 1`.

## Artifacts

- `scripts/release.sh` — the release pipeline (above).
- `packaging/homebrew/kue.rb` — the formula, source of truth. `scripts/release.sh`
  patches the *tap's* copy; keep this in-repo copy in sync when the structure changes.
- README "Installation" — `brew install chakrit/tap/kue` plus the build-from-source path.

## Tap repo

`chakrit/homebrew-tap` (public) exists and is seeded with `Formula/kue.rb` (placeholder
`url`/`sha256` until the first real release patches them). Homebrew maps
`brew install chakrit/tap/kue` to that repo's `Formula/kue.rb`. Cloned locally at
`../homebrew-tap` relative to the kue repo (override with `KUE_TAP_DIR`).

## Cutting a release

On "cut a slice": `scripts/release.sh <version>`. It tags, builds, publishes the GH
release asset, and patches+pushes the tap formula in one run. First release is `0.1.0`
(alpha) — the `v0.1.0` tag is already pushed, so the script will reuse it.
