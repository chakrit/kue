# SPIKE (one-off, not a slice) — Lean engine in a Go binary via cgo → COMMIT

(2026-06-25) Self-contained feasibility spike, separate from the CLI slice loop. Does NOT
supersede the active START-HERE
([`2026-06-24-resume-cli-entry-ux-fixed-cli-surface-awaiting-user.md`](2026-06-24-resume-cli-entry-ux-fixed-cli-surface-awaiting-user.md)).

## Verdict: COMMIT

A **single Go binary** (cgo, no `kue` subprocess) calls Kue's real evaluator
(`Kue.evalSourceToString`) **in-process** and prints correct results — the full Lean
runtime (evaluator + GMP/`Decimal` + C++ runtime + libuv) links and coexists with the Go
runtime.

- `x: 1.5 + 2.5` → `x: 4.0` (GMP/Decimal); `a: 1` / `b: a + 1` → `a: 1` / `b: 2` (refs).
- **macOS arm64:** proven. Self-contained (`otool -L` shows only `/usr/lib` + frameworks).
- **Linux x86_64:** built + ran in-container via `spike/Dockerfile.linux-spike` (QEMU).

Everything is under `spike/`; `lake build kue` + `check-fixtures.sh` stay green, untouched.

## The two findings that matter

1. **Owned-vs-borrowed arg is a double-free trap.** The `@[export]` must take an OWNED
   `String`, not `@& String` — `evalSourceToString` consumes its arg. Symptom of getting it
   wrong: first call OK, second call returns `_|_` or SIGSEGVs (looks like global state, is
   refcount corruption).
2. **Lean 4.29 init ABI dropped the world arg.** It's `initialize_<pkg>_<Module>(uint8_t
   builtin)`, package-prefixed, single-arg. Mirror the generated `Main.c`.

Full record + link line + sharp edges:
[`../decisions/2026-06-25-lean-engine-embedded-in-go-via-cgo.md`](../decisions/2026-06-25-lean-engine-embedded-in-go-via-cgo.md).
Reproduce: `bash spike/build.sh`. Spike README: [`../../spike/README.md`](../../spike/README.md).

## Back to the slice loop

This spike answered an architecture question; it is not on the plan's critical path. Resume
normal work from the CLI START-HERE breadcrumb above — the spike changes nothing about the
current `kue` binary or the release pipeline.
