# B3d-A2 — DEFLATE/ZIP adversarial reject-branch pins (LANDED 2026-07-05)

Breadcrumb / restore point after the B3d-A2 test-strength slice.

## What this slice did

Pinned every adversarial reject branch of the pure-Lean DEFLATE (`Kue/Inflate.lean`) and ZIP
(`Kue/Zip.lean`) decoders to its EXACT typed error, so a malformed cue-module archive is provably
REJECTED — never silently mis-decoded or wrongly accepted (a soundness hole in the registry-fetch
integrity path). 14 new `native_decide` theorems in `Kue/Tests/ZipTests.lean`, section
"adversarial reject branches (B3d-A2)"; helpers `inflErr`/`zipErr` project the error string.

- DEFLATE (9): STORED LEN/NLEN mismatch, dist-too-far-back, invalid fixed dist code (30/31),
  litlen symbol 286 OOR, dynamic empty-CLC table, dynamic incomplete-litlen table, dynamic dist
  symbol 30 OOR, block symbol-loop fuel exhaustion (no-hang proof), + prior BTYPE=3.
- ZIP (5): short/no-EOCD, bad CD sig, unsupported method, bad local sig, CRC mismatch, size
  mismatch. All are single-field `List.set` mutations of `storedZip`.

Malformed DEFLATE streams were bit-crafted and cross-checked against Python `zlib` (raw,
wbits=-15). **No soundness bug** — every branch already rejected correctly.

## Left un-pinned (intentional — defensive-unreachable)

Two totality guards cannot fire on any input (each block/RLE step consumes ≥1 unit against a
matched fuel/count bound): the outer block-loop fuel guard in `inflate.go` and the
dynamic-code-length underflow guard in `readDynamicTables`. They exist only to keep the functions
total without `partial`. Noted in `plan.md`; not fixture-pinnable without an unreachable input.

## State

`./scripts/check.sh` GREEN. Committed on `main`, NOT pushed. B3d-A2 closed in `plan.md`.

## Next (from plan.md pending)

- **B3d-B1** (type-leverage, LOW) — `Digest`/`Hash1` smart-constructor newtype; second consumer
  (B3d-6b `cue.sum` write) now exists, so it earns its keep.
- **kue-performance B3d note** (doc, LOW) — inflate O(output) fuel-bounded; fetch latency
  curl/network-dominated. Fold into a coming B3d slice.
