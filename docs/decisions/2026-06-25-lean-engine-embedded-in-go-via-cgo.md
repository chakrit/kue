# Embed the Lean Engine in a Go Binary via cgo (Single Binary, Go Owns `main`)

- **Date:** 2026-06-25
- **PR:** manual (spike under `spike/`)
- **Status:** accepted (spike verdict: **COMMIT**)

## Decision

Kue can ship as a **single Go binary** that owns `main` and links the Lean 4 evaluator in
as a guest via cgo — **no `kue` subprocess**. A feasibility spike proved the full Lean
runtime (the real evaluator + GMP bignum via `Decimal` + the C++ runtime + libuv) links and
coexists with the Go runtime in one process, on **macOS arm64** and **Linux x86_64**. This
unblocks the intended architecture: Go owns the OCI/CUE-module ecosystem surface at `main`;
the strongly-typed Lean engine does evaluation in-process.

The spike lives in `spike/` and is isolated — it is NOT part of `lake build kue` or the
release scripts. `lake build kue` + `scripts/check-fixtures.sh` stay green and unchanged.

## What was proven

A single cgo binary (`spike/main.go` → `spike/shim.c` → exported Lean `kue_spike_eval` →
`Kue.evalSourceToString`) printed, from the embedded engine:

- `x: 1.5 + 2.5` → `x: 4.0` — exercises `Decimal`/GMP (the float sum keeps its point;
  this is Kue's real formatter output, not the approximate `x: 4` the spike brief guessed).
- `a: 1` / `b: a + 1` → `a: 1` / `b: 2` — exercises reference resolution
  (`resolveStructRefs` + `evalStructRefs`).

`otool -L spike-bin` (macOS) shows only `/usr/lib` + system frameworks: the entire Lean
runtime is statically linked, the binary is self-contained and runs from anywhere.

## The working recipe

### Init sequence (Lean 4.29 ABI — single `uint8_t builtin`, NO world)

The world-passing init ABI assumed by older docs is gone in 4.29. The generated C init is
`initialize_<pkg>_<Module>(uint8_t builtin)` (e.g. `initialize_spike_Spike`), package-name
prefixed, single-argument. Mirror the toolchain's own generated `main`:

```c
lean_initialize_runtime_module();
lean_object *r = initialize_spike_Spike(1 /* builtin */);   // transitively inits Kue
/* check lean_io_result_is_error(r); */ lean_dec_ref(r);
lean_io_mark_end_initialization();
lean_init_task_manager();
```

`lean_initialize_runtime_module` / `lean_init_task_manager` are NOT in the public `lean.h`
in 4.29 — declare them yourself, exactly as the generated `Main.c` does.

### The link line (empirical crux — `leanc --print-ldflags` is the authority)

`leanc --print-ldflags` is `leanc`'s own recipe and the only reliable source — the two
platforms diverge sharply, and guessing the Linux half wrong was the one real blocker hit.

**macOS arm64** (C++ stdlib is the SYSTEM libc++):

```
libkuespike.a \
  -L$(lean --print-prefix)/lib/lean -L$(lean --print-prefix)/lib \
  -lleancpp -lleanrt -lInit -lStd -lLean -lgmp -luv -lc++ -lm
```

**Linux x86_64** (the Lean toolchain ships + STATICALLY links its OWN libc++):

```
libkuespike.a \
  -L$(lean --print-prefix)/lib/lean -L$(lean --print-prefix)/lib \
  -Wl,--start-group -lleancpp -lleanrt -lInit -lStd -lLean -Wl,--end-group \
  -lgmp -luv -Wl,-Bstatic -lc++ -lc++abi -Wl,-Bdynamic -lpthread -ldl -lrt -lm
```

The Linux divergences, each one load-bearing and each one a separate blocker hit and fixed:

- **C++ stdlib is libc++, NOT GNU libstdc++.** Lean's Linux toolchain bundles its own
  clang + libc++ (`-lc++ -lc++abi` from `$PREFIX/lib`). Linking `-lstdc++` leaves every
  `std::__1::…` symbol in `libleanrt.a` (chrono, mutex, basic_string, to_string) unresolved
  — `std::__1` IS the libc++ inline namespace. Fix: link the toolchain's libc++, never the
  distro's libstdc++.
- **Force STATIC libc++ with `-Wl,-Bstatic … -Wl,-Bdynamic`.** Without the `-Bstatic`
  wrapper the linker prefers `$PREFIX/lib/libc++.so.1` over the `.a`; the binary links but
  dies at startup with `libc++.so.1: cannot open shared object file` — that `.so` is in the
  Lean toolchain dir, not on the system loader path. `-Bstatic` bakes the `.a` in, matching
  the macOS half's self-contained property. (`leanc`'s own recipe does exactly this.)
- **`--start-group`/`--end-group`** around the mutually-referential Lean archives
  (`leancpp`/`Lean`/`Init`/`leanrt`).
- **Extra system libs:** `-lpthread -ldl -lrt`.

`libkuespike.a` is an `ar` archive of the spike module object + **all** Kue `*.c.o.export`
objects except `Main` (which carries its own `main`/initializer). The Lean runtime archives
are static, hence the self-contained binary. cgo wiring is generated into
`spike/cgo_flags.go` by `spike/build.sh`, which branches the LDFLAGS on `uname`.

### Marshaling shim

`char* kue_eval_c(const char* s)`: `lean_mk_string(s)` → call the export → `strdup` the
`lean_string_cstr` of the result → `lean_dec` the result. `kue_free_c` frees the strdup'd
copy. The Go side pins the goroutine with `runtime.LockOSThread()` before `kue_init` so all
Lean calls stay on the thread that initialized the runtime.

## Sharp edges (the real implementation MUST handle these)

- **Owned vs borrowed argument is a double-free trap — the headline finding.** The export
  must take an **owned** `String` (`def kueSpikeEval (input : String)`), NOT a borrowed
  `@& String`. `evalSourceToString` *consumes* its argument; a borrowed export forwards the
  borrowed handle into a consuming callee, and then the C caller decs it again → double
  free. The symptom is insidious: the *first* call returns correctly, the *second* returns a
  corrupted result (`_|_`) or SIGSEGVs — it looks like leaked global eval state, but it is
  refcount corruption. With an owned arg, the C caller must NOT dec the input (the callee
  consumes it).
- **cgo compiles every `.c` in the package dir.** Keep the Lean-generated `Spike.c` (and any
  scratch C with its own `main`) OUT of the Go package directory or you get duplicate
  `_main` / double-compiled symbols. The spike puts generated C under `spike/gen/` and only
  the archive carries those objects.
- **Thread affinity.** Lean's runtime uses thread-local state; pin the cgo-calling goroutine
  (`runtime.LockOSThread`). Not yet stress-tested under concurrent Go goroutines calling in
  — the real loader (which does IO, world-passing) will need a deliberate threading model.
- **No Lean cross-compile.** Same constraint as the existing release: the Linux binary is
  built natively in a container (QEMU for amd64 on an arm64 host), not cross-compiled.
- **Pure entry only (for now).** The spike used `evalSourceToString` (`String → Except
  ParseError String`, no IO) to avoid world-passing across the FFI. The real IO loader
  (file reads, imports) is a later, harder concern — it crosses `IO` and must thread the
  Lean world correctly.

## Reproduce

`bash spike/build.sh` (macOS, host Go + elan toolchain required). Linux:
`docker buildx build --platform linux/amd64 --build-arg LEAN_TOOLCHAIN=v4.29.1
--file spike/Dockerfile.linux-spike --load .` — the build RUNs the spike; a green build is
the verdict.

## Alternatives considered

- **`kue` subprocess from Go** — rejected: the spike's whole point is to prove in-process
  linking works, removing process-spawn overhead and the two-binary distribution. It does.
- **Lean owns `main`, Go as guest** — not explored; Go must own `main` to host the
  OCI/CUE-module ecosystem libraries, which is the architectural driver.
