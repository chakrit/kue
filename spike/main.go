package main

// This is a SPIKE: a single Go binary (cgo) that calls Kue's REAL Lean
// evaluator in-process — no `kue` subprocess. It proves Go can own `main`
// while the Lean 4 engine (parse → resolve → eval → format, incl. GMP bignum
// via Decimal) runs linked-in as a guest.
//
// The link line is derived empirically from `leanc --print-ldflags`; see
// build.sh, which writes LDFLAGS into a generated cgo_flags.go so this file
// stays platform-agnostic.

/*
#include <stdlib.h>
#include "shim.h"
*/
import "C"

import (
	"fmt"
	"os"
	"runtime"
	"unsafe"
)

func kueInit() {
	// Lean's runtime uses thread-local state (allocator, task manager). Pin
	// this goroutine to the OS thread that runs kue_init so every subsequent
	// Lean call lands on the same thread Lean initialized. Go may otherwise
	// migrate the goroutine across OS threads between cgo calls.
	runtime.LockOSThread()
	C.kue_init()
}

func kueEval(src string) string {
	cs := C.CString(src)
	defer C.free(unsafe.Pointer(cs))
	out := C.kue_eval_c(cs)
	defer C.kue_free_c(out)
	return C.GoString(out)
}

func main() {
	kueInit()

	// The non-trivial cases the spike must prove: full runtime, GMP/Decimal,
	// and reference resolution.
	cases := []struct {
		name, src string
	}{
		{"decimal-add (GMP)", "x: 1.5 + 2.5"},
		{"reference resolve", "a: 1\nb: a + 1"},
	}

	failed := false
	for _, c := range cases {
		got := kueEval(c.src)
		fmt.Printf("=== %s ===\n", c.name)
		fmt.Printf("in:  %q\n", c.src)
		fmt.Printf("out: %s\n", got)
		fmt.Println()
	}

	// Hard assertions so the binary's exit code is a verdict signal.
	// Kue's real formatter renders the decimal sum as "x: 4.0" (float result
	// keeps its point) — that exact string is what the in-process engine must
	// return, and is the GMP/Decimal proof.
	if got := kueEval("x: 1.5 + 2.5"); got != "x: 4.0" {
		fmt.Fprintf(os.Stderr, "FAIL decimal-add: expected %q, got %q\n", "x: 4.0", got)
		failed = true
	}
	if got := kueEval("a: 1\nb: a + 1"); got != "a: 1\nb: 2" {
		fmt.Fprintf(os.Stderr, "FAIL reference: expected %q, got %q\n", "a: 1\nb: 2", got)
		failed = true
	}

	if failed {
		os.Exit(1)
	}
	fmt.Println("ALL CASES PASSED — Lean engine ran in-process inside the Go binary.")
}
