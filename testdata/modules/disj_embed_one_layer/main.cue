package app

// Gap-2 (Bug2-2): an embedded def `#M` carrying a discriminated disjunction
// (`{shape:"struct",…} | {shape:"list",…} | error`) selects the right arm when narrowed
// DIRECTLY (`#M & {shape:"struct"}`), but when `#M` is itself embedded ONE LAYER DOWN
// (`#U: {#M}`, then `#U & {shape:"struct"}`) the outer use-site narrowing of the
// discriminator `shape` reaches the host frame but was NOT spliced into `#M` behind the
// force tier — the arms MATCH `shape`, they do not READ it, so `embedComprehensionReadLabels`
// missed it. Every arm then survived and the meet bottomed (kue), while cue selects the
// struct arm. `embedDisjArmDeclLabels` surfaces the arm-declared discriminator so `#M`'s
// force-time disjunction distribution prunes the dead arms exactly as the DIRECT case does.
#M: {
	#k:    string
	shape: string
	{shape: "struct", val: #k} | {shape: "list", items: [#k]} | error("no shape")
	...
}
#U: {#M}
outStruct: #U & {#k: "x", shape: "struct"}
outList: #U & {#k: "y", shape: "list"}

// Direct narrowing — UNCHANGED by the fix (already worked one tier up).
outDirect: #M & {#k: "z", shape: "struct"}

// A real conflict on the discriminator that kills ALL structural arms still bottoms
// (soundness): `shape:"other"` matches neither arm, the error arm bottoms → no survivor.
outBottom: (#U & {#k: "w", shape: "other"}) | "fellback"
