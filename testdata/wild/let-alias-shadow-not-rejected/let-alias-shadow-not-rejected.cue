package repro

// A `let` (equally, a value alias `y=`) may not shadow an enclosing binding of
// the same name. cue rejects this at LOAD:
//   cannot have both alias and field with name "x" in same scope
// kue currently ACCEPTS it (the no-shadow validation is unimplemented) — a
// spec-adjudicated UNDER-rejection, so this is RED until kue enforces the rule.
// General, NOT import-specific (surfaced while verifying file-scoped-import
// shadow detection, where cue rejected the `let x`/alias-`x` shadow forms): it
// reproduces with a plain enclosing field and needs no module/import.
x: 1
out: {
	let x = "shadow"
	got: x
}
