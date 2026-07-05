#!/usr/bin/env python3
"""Generate testdata/ocifetch/modtidy/*.zip from the checked-in src/ tree.

The `mod tidy` offline gate (`scripts/check-mod-tidy.lean`) drives a diamond requirement
graph out of five committed module zips. Those zips were previously opaque binaries with no
source (AUD-B2). The readable source now lives under `testdata/ocifetch/modtidy/src/<name>/`
— one directory per zip, holding the exact file tree that zip encodes (`cue.mod/module.cue`
plus the package `.cue`). This script re-zips each `src/<name>/` into `<name>.zip`.

Reproducibility, not byte-identity: the gate computes each `h1:` dirhash from the zip's
DECOMPRESSED contents at run time (`fixtureH1`), so any zip container carrying the same file
tree passes — timestamps and compression choice are free. We fix both for a stable diff.

`Kue/Zip.lean` reads STORED (0) and DEFLATE (8); we emit DEFLATE to match the originals.
`malformed/` intentionally holds invalid CUE in `cue.mod/module.cue` — the gate's
malformed-dependency error path depends on it; the zip itself stays well-formed.

Re-run to regenerate (idempotent):  scripts/gen-modtidy-fixtures.py
"""

import zipfile
from pathlib import Path

MODTIDY = Path(__file__).resolve().parent.parent / "testdata" / "ocifetch" / "modtidy"
SRC = MODTIDY / "src"
FIXED_DATE = (2026, 1, 1, 0, 0, 0)  # deterministic mtime for a stable container diff


def build(name: str) -> None:
    src_dir = SRC / name
    if not src_dir.is_dir():
        raise SystemExit(f"missing source tree: {src_dir}")
    files = sorted(p for p in src_dir.rglob("*") if p.is_file())
    out = MODTIDY / f"{name}.zip"
    with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for path in files:
            arcname = path.relative_to(src_dir).as_posix()
            info = zipfile.ZipInfo(arcname, date_time=FIXED_DATE)
            info.compress_type = zipfile.ZIP_DEFLATED
            zf.writestr(info, path.read_bytes())
    print(f"wrote {out.relative_to(MODTIDY.parent.parent)} ({', '.join(p.relative_to(src_dir).as_posix() for p in files)})")


def main() -> None:
    for name in ("a", "b", "c-1.2.0", "c-1.3.0", "malformed"):
        build(name)


if __name__ == "__main__":
    main()
