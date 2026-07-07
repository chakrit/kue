# Ship Prebuilt Binaries, Release Locally (No CI)

- **Date:** 2026-06-16
- **PR:** manual (promoted from a setup note, 2026-06-19)
- **Status:** revised

> **Update 2026-06-23:** releases now ship 3 platforms (macOS arm64 + Linux amd64/arm64
> via `scripts/release-linux.sh`), and `kue version` exists — the two Consequences below
> are historical. The core decision (prebuilt binaries, local script, no CI) stands.

## Decision

Kue ships as a **prebuilt arm64-macOS binary** installed via a Homebrew formula's
`bin.install`, and releases are cut **locally** by `scripts/release.sh` — never by CI or
GitHub Actions.

## Rationale

Why ship a prebuilt binary rather than the obvious build-from-source Homebrew formula:

- Lean 4's `lake build` links the Lean runtime **statically** — verified on the local
  arm64 build, `otool -L .lake/build/bin/kue` lists only `/usr/lib/libc++.dylib` and
  `/usr/lib/libSystem.B.dylib` (macOS system libs, no elan-toolchain dylibs). The binary
  is self-contained, so shipping the bits directly is sound.
- A prebuilt asset installs faster and is reproducible — users get exactly the released
  bits, not a recompile against whatever toolchain state their machine carries. A
  build-from-source formula would need `depends_on elan` and a full `lake build` per
  install.

Why a local release script rather than CI: GitHub Actions is banned project-wide. The
release pipeline lives in `scripts/release.sh`, run by chakrit and gated on "cut a slice."
Auth is the local `gh` login (`repo` scope) plus the local tap clone — no tokens, no
secrets stored in any repo.

## Consequences

- **Host-only build** is the single divergence from a full cross-compiled release: Lean
  has no cross-compiler, so `release.sh` builds for the host arm64 only. The formula is
  arm64-macOS-only (`depends_on arch: :arm64`, `depends_on :macos`) — the only platform
  `brew` serves here. Other platforms build from source per the README.
- **Tap:** `chakrit/homebrew-tap` (public) holds `Formula/kue.rb`. `release.sh`
  `sed`-patches the tap's `version`/`url`/`sha256` and pushes it; the in-repo
  `packaging/homebrew/kue.rb` is the source of truth, kept in sync. The tap is cloned at
  `../homebrew-tap` (override with `KUE_TAP_DIR`).
- **No `kue version` subcommand** — `kue` treats any arg as a file path, so the formula
  `test` pipes CUE via stdin instead: `printf 'x: int & 1\n' | kue` → `x: 1`.
- **Push the branch before `release.sh`** — the script pushes the *tag* (and its commit
  objects) but never the branch ref. Cutting from an unpushed `main` leaves the tag on a
  commit `gh/main` doesn't contain — the release-consistency failure mode. Run
  `git push gh main` first, then `release.sh <version>`, then `release-linux.sh <version>`
  for the two Linux assets.

## Alternatives considered

- **Build-from-source formula** (`depends_on elan`, `lake build`) — rejected: slower
  installs, non-reproducible, requires the toolchain present.
- **CI-built releases (GitHub Actions)** — rejected: Actions banned project-wide; a local
  script keeps the pipeline readable and under direct control.

The host-only-build limit is the binding constraint behind flip-condition #2 in the
[implementation-language decision](2026-06-17-implementation-language-lean4.md): if
cross-platform distribution becomes urgent, this is the wall that makes a Rust rewrite
arguable.
