# `mod tidy` diamond-graph fixtures

Five module zips driving the offline `kue mod tidy` gate
(`scripts/check-mod-tidy.lean`). The requirement graph is a diamond: `a` and `b` both
depend on `c`, at `v1.2.0` and `v1.3.0` respectively, so MVS must select `c@v1.3.0`.
`malformed.zip` carries invalid CUE in its `module.cue` to exercise the
malformed-dependency error path (the zip container is well-formed; only its CUE is broken).

The human-readable source each zip encodes lives under `src/<name>/` — one directory per
zip, holding the exact `cue.mod/module.cue` + package `.cue` tree. Edit `src/`, never the
binaries.

Regenerate the zips from `src/`:

    scripts/gen-modtidy-fixtures.py

The gate derives each `h1:` dirhash from the zip's decompressed contents at run time, so a
regenerated zip carrying the same file tree stays green without touching any pinned digest.
