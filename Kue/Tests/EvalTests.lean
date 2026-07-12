import Kue.Eval
import Kue.Format
import Kue.Manifest
import Kue.Resolve
import Kue.Runtime
import Kue.Tests.EvalTestHelpers

namespace Kue

theorem format_unresolved_ref :
    formatValue (.ref "#A") = "#A" := by
  native_decide

theorem manifest_unresolved_ref_incomplete :
    (manifest (.ref "#A") == .error (.incomplete (.ref "#A"))) = true := by
  native_decide

theorem eval_regular_field_reference_to_definition :
    (evalStructRefs
      (resolveStructRefs
        (mkStruct [⟨"#A", .definition, .kind .int, false⟩, ⟨"x", .regular, .ref "#A", false⟩] .regularOpen none []))
      == mkStruct [⟨"#A", .definition, .kind .int, false⟩, ⟨"x", .regular, .kind .int, false⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_missing_reference_bottom :
    (evalStructRefs
      (mkStruct [⟨"x", .regular, .ref "#Missing", false⟩] .regularOpen none [])
      == mkStruct [⟨"x", .regular, .bottomWith [.unresolvedReference "#Missing"], false⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_resolved_reference_by_binding_id :
    (evalStructRefs
      (mkStruct [⟨"#A", .definition, .kind .int, false⟩, ⟨"x", .regular, .refId ⟨0, 0⟩, false⟩] .regularOpen none [])
      == mkStruct [⟨"#A", .definition, .kind .int, false⟩, ⟨"x", .regular, .kind .int, false⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_static_field_selector :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"base", .regular, mkStruct [⟨"inner", .regular, .prim (.int 4), false⟩] .regularOpen none [], false⟩,
            ⟨"x", .regular, .selector (.ref "base") "inner", false⟩
          ] .regularOpen none []))
      = "base: {inner: 4}\nx: 4" := by
  native_decide

theorem eval_static_list_index :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"xs", .regular, .list [.prim (.int 10), .prim (.int 20)], false⟩,
            ⟨"x", .regular, .index (.ref "xs") (.prim (.int 1)), false⟩
          ] .regularOpen none []))
      = "xs: [10, 20]\nx: 20" := by
  native_decide

theorem eval_static_string_field_index :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"base", .regular, mkStruct [⟨"inner", .regular, .prim (.int 4), false⟩] .regularOpen none [], false⟩,
            ⟨"x", .regular, .index (.ref "base") (.prim (.string "inner")), false⟩
          ] .regularOpen none []))
      = "base: {inner: 4}\nx: 4" := by
  native_decide

-- Memoization regression pins. Evaluation now shares computed-once results via a
-- frame-id-keyed cache; these prove the cache is behavior-preserving on the shapes it
-- targets — repeated selection into a shared sub-struct, and a cycle reached through such
-- repeated selection (the cache must not let a mid-cycle partial leak as a wrong cached
-- value; cycle detection via `visited` must still fire identically).

theorem eval_shared_repeated_selection :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"base", .regular, .prim (.string "v"), false⟩,
            ⟨"components", .regular,
              mkStruct [
                  ⟨"a", .regular, mkStruct [⟨"who", .regular, .ref "base", false⟩] .regularOpen none [], false⟩,
                  ⟨"b", .regular, mkStruct [⟨"who", .regular, .ref "base", false⟩] .regularOpen none [], false⟩
                ] .regularOpen none [], false⟩,
            ⟨"aWho", .regular, .selector (.selector (.ref "components") "a") "who", false⟩,
            ⟨"bWho", .regular, .selector (.selector (.ref "components") "b") "who", false⟩
          ] .regularOpen none []))
      = "base: \"v\"\ncomponents: {a: {who: \"v\"}, b: {who: \"v\"}}\naWho: \"v\"\nbWho: \"v\"" := by
  native_decide

-- A direct self-cycle selected twice: caching must not turn the bounded-cycle `⊤` into a
-- wrong value, and both selections must agree. `x: x & {p: 1}` resolves the cycle to its
-- constraint; `p1`/`p2` select the same field from the cyclic struct.
theorem eval_cycle_with_repeated_selection :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"x", .regular, .conj [.ref "x", mkStruct [⟨"p", .regular, .prim (.int 1), false⟩] .regularOpen none []], false⟩,
            ⟨"p1", .regular, .selector (.ref "x") "p", false⟩,
            ⟨"p2", .regular, .selector (.ref "x") "p", false⟩
          ] .regularOpen none []))
      = "x: {p: 1}\np1: 1\np2: 1" := by
  native_decide


-- ### structural-cycle detection (D#2a).
--
-- The CUE spec mandates dynamic detection of STRUCTURAL cycles — a definition (or regular field)
-- whose body re-enters the SAME struct through a struct layer (`#L: {next: #L}`) — as an error,
-- DISTINCT from a bare REFERENCE cycle (`x: x` → `_`). Detection is an in-progress struct-body
-- stack on the `.refId` eval path (`structStack`): a struct body re-entered while still on the
-- stack bottoms with `.structuralCycle` rather than unrolling fuel-deep to garbage. These pins
-- cover the spec's oracle table (cue v0.16.1): error cases, the reference-cycle control, the
-- finite-deep control, and the recursive-list idiom that must NOT false-positive.

-- Oracle #1: a self-referential def is a structural cycle. The lever tags the re-entry
-- `.structuralCycle` (asserted on the REASON, not merely "some bottom"), so a regression to the
-- old fuel-deep unroll — or to an untagged bottom — fails. cue: `#L.next: structural cycle`.
theorem structural_cycle_self_ref_detected :
    evalSourceDetectsStructuralCycle "#L: {n: int, next: #L}\nx: #L\n" = true := by
  native_decide

-- The structural cycle makes the value non-manifestable: `export` bottoms (the value verdict
-- cue agrees on). With every field concrete except the cyclic ref, the ONLY fault is the cycle.
theorem structural_cycle_self_ref_export_bottoms :
    exportJsonBottoms "#L: {n: 1, next: #L}\nx: #L\n" = true := by
  native_decide

-- Oracle #3: MUTUAL recursion (`#A` → `#B` → `#A`) is detected for free — `#A`'s body re-enters
-- the stack two hops down, same mechanism, no special-casing. cue: `#B.a: structural cycle`.
theorem structural_cycle_mutual_detected :
    evalSourceDetectsStructuralCycle "#A: {b: #B}\n#B: {a: #A}\nz: #A\n" = true := by
  native_decide

-- A structural cycle through a REGULAR (non-definition) field is detected too — the lever keys
-- on struct-body re-entrancy, not definition-ness (cue agrees: `a.next: structural cycle`).
theorem structural_cycle_regular_field_detected :
    evalSourceDetectsStructuralCycle "a: {n: int, next: a}\n" = true := by
  native_decide

-- Control (oracle #5): a bare REFERENCE cycle is NOT structural — no struct layer between
-- re-entries — so it stays `_` (resolved via the depth-0 `visited` slot check, untouched by the
-- struct-body lever). Pins that D#2a did not regress the reference-cycle path.
theorem reference_cycle_unchanged :
    evalSourceMatches "x: x\n" "x: _" = true := by
  native_decide

-- Control: a constrained reference cycle still resolves to its constraint (`x: x & >=0` → `>=0`),
-- not a structural-cycle bottom — the conj's bare `.ref` arm is not a struct body.
theorem constrained_reference_cycle_unchanged :
    evalSourceMatches "x: x & >=0\n" "x: >=0" = true := by
  native_decide

-- Control (oracle #4): a FINITE-deep nesting must NOT false-positive — each layer is a DISTINCT
-- struct body, so no body is ever on the stack twice. No `.structuralCycle` anywhere.
theorem finite_deep_struct_no_false_cycle :
    evalSourceDetectsStructuralCycle "#D: {a: {b: {c: {d: int}}}}\nw: #D\n" = false := by
  native_decide

-- Control (the recursive-tree idiom): recursion through an OPEN LIST tail (`[...#T]`) is finite
-- in cue (the tail defers, yielding `[]`), NOT a structural cycle. A concrete finite use exports
-- byte-identically to cue — the lever must not flag the deferred-tail recursion.
theorem recursive_list_tail_finite_use_exports :
    exportJsonMatches "#T: {v: int, kids: [...#T]}\nx: #T & {v: 1, kids: [{v: 2}]}\n"
      "{\n    \"x\": {\n        \"v\": 1,\n        \"kids\": [\n            {\n                \"v\": 2,\n                \"kids\": []\n            }\n        ]\n    }\n}\n" = true := by
  native_decide

-- NESTED cycle (a cyclic def reached THROUGH a non-cyclic outer def): `#Outer.inner = #Inner`,
-- whose own `loop: #Inner` is the cycle. Exercises the restore-saved-stack discipline — `#Outer`
-- pushes/restores cleanly while the inner `#Inner` re-entry is the one that bottoms. Detection
-- still fires (not masked by the outer frame); value verdict bottoms, as cue (`#Inner.loop:
-- structural cycle`). Pins that the lever sees a cycle that is not at the top of the spine.
theorem structural_cycle_nested_under_noncyclic_detected :
    evalSourceDetectsStructuralCycle "#Inner: {loop: #Inner}\n#Outer: {inner: #Inner}\nr: #Outer\n" = true := by
  native_decide

-- MUTUAL cycle through REGULAR (non-definition) fields (`a.bb → b`, `b.aa → a`): the class-agnostic
-- lever (keys on struct-body re-entrancy, not definition-ness) detects the mutual-regular combination
-- too — the single-field regular case and the def-mutual case are each pinned, this is their cross.
-- cue agrees (`b.aa: structural cycle`).
theorem structural_cycle_mutual_regular_fields_detected :
    evalSourceDetectsStructuralCycle "a: {bb: b}\nb: {aa: a}\nz: a\n" = true := by
  native_decide


-- ### terminating-disjunct (D#2b).
--
-- The spec's "a node is valid if any of its conjuncts is not cyclic" rule: a recursive def in a
-- disjunction (`#List | *null`) terminates by taking the non-cyclic arm once the cyclic arm bottoms
-- with `.structuralCycle` (D#2a). The cyclic arm is pruned by `liveAlternatives`/`resolveDisjDefault?`
-- (value resolution) — already the existing algebra; D#2b's code change is in `normalizeEvaluatedDisj`,
-- which now applies `liveAlternatives` (flatten + drop-bottom + dedup, SC-3) so the bottomed arm never
-- lingers in the EVAL value either. The pruning is value-SOUND: a `containsBottom` arm is dead in every
-- meet, so removing it changes no value. The surviving default is NOT collapsed into the value (a later
-- `a & 2` must still see a non-default arm) — default selection stays a manifest/force projection.
--
-- These pin the VALUE verdict (export, byte-identical to cue where the verdict agrees); Kue's eval
-- DISPLAY keeps the full `{…} | *null` per its established full-disjunction-with-default convention
-- (see `disjunctions/default_disjunction.expected`), which intentionally diverges from cue's
-- display-collapse — a recorded spec-gap, not a value bug. The export fixtures
-- `testdata/export/terminating_disj_*` carry the same verdicts as committed pairs.

-- Oracle #2 (the spec headline): `#List | *null` terminates on `*null` once the cyclic `#List` arm
-- bottoms → `tail: null`. cue agrees (`tail: null`); Kue under-resolved before D#2a+D#2b.
theorem terminating_disj_default_arm :
    exportJsonMatches "#List: {head: int, tail: #List | *null}\ny: #List & {head: 1}\n"
      "{\n    \"y\": {\n        \"head\": 1,\n        \"tail\": null\n    }\n}\n" = true := by
  native_decide

-- A self-referential struct def in a disjunction with a NON-null default (`#Tree | *{v: 0}`): the
-- cyclic arm bottoms, the default struct survives → `child: {v: 0}`. cue agrees.
theorem terminating_disj_nonnull_default_arm :
    exportJsonMatches "#Tree: {v: int, child: #Tree | *{v: 0}}\nr: #Tree & {v: 5}\n"
      "{\n    \"r\": {\n        \"v\": 5,\n        \"child\": {\n            \"v\": 0\n        }\n    }\n}\n" = true := by
  native_decide

-- The cyclic arm is NON-default (`*null | #List`): pruning still drops it and the OTHER arm (the
-- `*null` default) wins — order-independent. cue agrees (`tail: null`).
theorem terminating_disj_cyclic_arm_nondefault :
    exportJsonMatches "#List: {head: int, tail: *null | #List}\ny: #List & {head: 1}\n"
      "{\n    \"y\": {\n        \"head\": 1,\n        \"tail\": null\n    }\n}\n" = true := by
  native_decide

-- NO arm survives: a disjunction of two distinct all-cyclic defs (`#A | #B`, both structural cycles)
-- has every arm bottomed → the whole value bottoms (export fails). cue agrees (empty disjunction).
theorem terminating_disj_no_survivor_bottoms :
    exportJsonBottoms "#A: {x: int, self: #A}\n#B: {y: int, other: #B}\nz: {a: #A | #B}\n" = true := by
  native_decide

-- A#6 (was a fuel-cap probe): a WIDE cyclic body (5 concrete fields) prunes correctly. The
-- `.structuralCycle` bottom surfaces shallowly (D#2a fires at recursion depth ~2) so this always
-- worked, but `containsBottom` is now TOTAL/structural (the 100-level cap is gone, A#6) — depth no
-- longer matters even for a deep non-cyclic bottom. cue-exact. Deep-bottom totality pins: LatticeTests.
theorem terminating_disj_wide_body_pruned :
    exportJsonMatches
      "#L: {a: int, b: int, c: int, d: int, e: int, tail: #L | *null}\ny: #L & {a: 1, b: 2, c: 3, d: 4, e: 5}\n"
      "{\n    \"y\": {\n        \"a\": 1,\n        \"b\": 2,\n        \"c\": 3,\n        \"d\": 4,\n        \"e\": 5,\n        \"tail\": null\n    }\n}\n" = true := by
  native_decide

-- Soundness: the non-null default arm stays LIVE — it is not collapsed into the value, so a later
-- meet (`r.child & {v: 9}`) reaches the struct arm and narrows it. cue agrees (`{v: 9, child:{v:0}}`).
theorem terminating_disj_default_arm_stays_meetable :
    exportJsonMatches
      "#Tree: {v: int, child: #Tree | *{v: 0}}\nr: #Tree & {v: 5}\nforced: r.child & {v: 9}\n"
      "{\n    \"r\": {\n        \"v\": 5,\n        \"child\": {\n            \"v\": 0\n        }\n    },\n    \"forced\": {\n        \"v\": 9,\n        \"child\": {\n            \"v\": 0\n        }\n    }\n}\n" = true := by
  native_decide

-- SC-3 (folded into D#2b's `normalizeEvaluatedDisj` change): equal defaults DEDUP in the eval form —
-- `*1 | *1 | 2` now shows `*1 | 2` (was raw `*1 | *1 | 2`). Kue keeps the disjunction-with-default
-- (its convention), deduped; it does NOT collapse to cue's display `1` (which would be value-unsound).
theorem sc3_eval_dedups_equal_defaults :
    evalSourceMatches "x: *1 | *1 | 2\n" "x: *1 | 2" = true := by
  native_decide

-- Soundness regression: the default is a manifest/force PROJECTION, never a value rewrite. `a: *1 | 2`
-- keeps both arms in the value, so `b: a & 2` meets the LIVE `2` arm → `b: 2` (not `1 & 2 = ⊥`). The
-- `normalizeEvaluatedDisj` change must not collapse a multi-live-arm defaulted disjunction. cue: `b: 2`.
theorem sc3_default_not_collapsed_into_value :
    evalSourceMatches "a: *1 | 2\nb: a & 2\n" "a: *1 | 2\nb: 2" = true := by
  native_decide


-- ### scalar struct-embedding collapse pins (root prerequisite for list comprehensions).
--
-- A struct with no output field embedding a non-struct value IS that value (CUE: `{5}`→`5`). cue
-- v0.16.1-exact; collapse only when LOSSLESS (no output field).

-- bare scalar literal collapses; a ref-embedding collapses to the resolved scalar.
theorem scalar_embed_collapse_ref :
    evalSourceMatches "a: 7\nout: {a}\n" "a: 7\nout: 7" = true := by
  native_decide

-- a struct-embedding of a list element collapses each element (the `[{5},{6}]` shape).
theorem scalar_embed_collapse_in_list :
    evalSourceMatches "out: [{5}, {6}]\n" "out: [5, 6]" = true := by
  native_decide

-- an output field PLUS a scalar embedding conflicts (mismatched struct/scalar) — NOT collapsed.
theorem scalar_embed_with_output_field_conflicts :
    evalSourceMatches "out: {a: 1, 5}\n" "out: _|_" = true := by
  native_decide

-- two equal scalar embeddings unify to the scalar; the collapse is idempotent.
theorem scalar_embed_two_equal :
    evalSourceMatches "out: {5, 5}\n" "out: 5" = true := by
  native_decide

-- two distinct scalar embeddings conflict (`5 & 6`).
theorem scalar_embed_two_distinct_conflicts :
    evalSourceMatches "out: {5, 6}\n" "out: _|_" = true := by
  native_decide

-- ### empty/decl-free struct ∩ scalar is a CONFLICT, not a collapse (audit #10 V1).
--
-- The `{5}`→`5` collapse lives in embed-eval (`meetEmbeddingsWithFuel`), where the host is KNOWN
-- to embed a scalar — NOT in `meet`, which cannot tell an empty struct `{}` from `{5}`'s residual
-- `mkStruct []`. A genuine struct ∩ scalar must conflict (cue v0.16.1: mismatched types). Before the
-- fix these all wrongly collapsed to the scalar.

-- empty struct meeting a scalar conflicts (was wrongly `5`). cue: mismatched types struct/int.
theorem empty_struct_meet_scalar_conflicts :
    evalSourceMatches "out: {} & 5\n" "out: _|_" = true := by
  native_decide

-- order-independent: scalar on the left conflicts too.
theorem scalar_meet_empty_struct_conflicts :
    evalSourceMatches "out: 5 & {}\n" "out: _|_" = true := by
  native_decide

-- empty struct ∩ string conflicts (the absorb bug was not int-specific).
theorem empty_struct_meet_string_conflicts :
    evalSourceMatches "out: {} & \"s\"\n" "out: _|_" = true := by
  native_decide

-- empty struct ∩ bool conflicts.
theorem empty_struct_meet_bool_conflicts :
    evalSourceMatches "out: true & {}\n" "out: _|_" = true := by
  native_decide

-- two field decls — `out:{}` then `out:5` — unify via meet and conflict (the broad basic shape).
theorem field_struct_then_scalar_conflicts :
    evalSourceMatches "out: {}\nout: 5\n" "out: _|_" = true := by
  native_decide

-- ### scalar-with-decls carrier (`{#a: 1, 5}` → `5`, `.#a` selectable) — CUE v0.16.1.
--
-- The scalar analog of the `.embeddedList` carrier: a struct with only non-output members
-- embedding a SCALAR manifests as that scalar while keeping its decls selectable. The pure
-- `{5}` collapse (no decls) is UNTOUCHED — it still drops to the bare scalar (the soundness
-- net below). Oracle: `cue export {#a:1,5}` → `5`; `.#a` selects `1`.

-- SOUNDNESS NET (must stay green through the whole slice): pure `{5}` (no decls) collapses.
theorem soundness_pure_scalar_collapse_unchanged :
    evalSourceMatches "out: {5}\n" "out: 5" = true := by
  native_decide

-- SOUNDNESS NET: genuine conflict — two distinct scalar embeds WITH a decl reject. The carrier
-- holds the conflict INLINE (`{#a:1, _|_}`, the RESID-MASK convention `.embeddedList` uses for
-- conflicting elements), so `containsBottom` flags it and the export errors — cue rejects the
-- whole value too (`conflicting values 6 and 5`).
theorem soundness_scalar_with_decls_distinct_conflicts :
    exportJsonBottoms "out: {#a: 1, 5, 6}\n" = true := by
  native_decide

-- SOUNDNESS NET: selecting a decl off a conflicting carrier still rejects (the inline bottom
-- propagates; cue rejects `({#a:1,5,6}).#a` too) — the carrier never masks a genuine conflict.
theorem soundness_scalar_with_decls_conflict_select_rejects :
    exportJsonBottoms "x: {#a: 1, 5, 6}\nout: x.#a\n" = true := by
  native_decide

-- Two EQUAL scalar embeds with a decl unify (`5 & 5 = 5`); the carrier survives.
theorem scalar_embed_with_decls_equal_unify :
    exportJsonMatches "out: {#a: 1, 5, 5}\n" "{\n    \"out\": 5\n}\n" = true := by
  native_decide

-- TARGET: `{#a: 1, 5}` manifests as the scalar `5` (JSON export), decls dropped from output.
theorem scalar_embed_with_decls_exports_scalar :
    exportJsonMatches "out: {#a: 1, 5}\n" "{\n    \"out\": 5\n}\n" = true := by
  native_decide

-- TARGET: `.#a` is selectable through the carrier, yielding the decl value `1`.
theorem scalar_embed_with_decls_decl_selectable :
    exportJsonMatches "x: {#a: 1, 5}\nout: x.#a\n" "{\n    \"x\": 5,\n    \"out\": 1\n}\n" = true := by
  native_decide

-- EDGE: multiple decls + scalar — both decls stay selectable (`x.#a + x.#b = 3`).
theorem scalar_embed_with_decls_multiple :
    exportJsonMatches "x: {#a: 1, #b: 2, 5}\nout: x.#a + x.#b\n"
      "{\n    \"x\": 5,\n    \"out\": 3\n}\n" = true := by
  native_decide

-- EDGE: optional decl + scalar — optional is non-output, the scalar survives.
theorem scalar_embed_with_optional_decl :
    exportJsonMatches "out: {a?: int, 5}\n" "{\n    \"out\": 5\n}\n" = true := by
  native_decide

-- EDGE: regular (output) field + scalar — genuine struct/scalar conflict (NOT a carrier).
theorem scalar_embed_with_output_field_still_conflicts :
    evalSourceMatches "out: {a: 1, 5}\n" "out: _|_" = true := by
  native_decide

-- EDGE: the carrier inside a larger unification — `{#a:1,5} & {#b:2,int}` → `5`, both decls kept.
theorem scalar_embed_with_decls_in_unification :
    exportJsonMatches "x: {#a: 1, 5} & {#b: 2, int}\nra: x.#a\nrb: x.#b\n"
      "{\n    \"x\": 5,\n    \"ra\": 1,\n    \"rb\": 2\n}\n" = true := by
  native_decide

-- EDGE: unifying two carriers with conflicting scalars bottoms (`5 & 6`).
theorem scalar_embed_with_decls_conflicting_unify :
    exportJsonBottoms "out: {#a: 1, 5} & {#b: 2, 6}\n" = true := by
  native_decide

-- OPERAND POSITION (oracle-confirmed against cue v0.16.1). `resolveOperand` unwraps a carrier
-- to its inner scalar in EVERY arith/compare/unary slot, not just `+`. A conflicting carrier
-- (`{#a:1,5,6}`) holds an inner `5 & 6` bottom that must surface BEFORE the op, not silently
-- unwrap to one scalar.
theorem scalar_carrier_compare_lt_sees_scalar :
    exportJsonMatches "out: {#a: 1, 5} < 6\n" "{\n    \"out\": true\n}\n" = true := by
  native_decide

theorem scalar_carrier_compare_eq_sees_scalar :
    exportJsonMatches "out: {#a: 1, 5} == 5\n" "{\n    \"out\": true\n}\n" = true := by
  native_decide

theorem scalar_carrier_unary_neg_sees_scalar :
    exportJsonMatches "out: -{#a: 1, 5}\n" "{\n    \"out\": -5\n}\n" = true := by
  native_decide

theorem scalar_carrier_conflicting_in_operand_bottoms :
    exportJsonBottoms "out: {#a: 1, 5, 6} + 1\n" = true := by
  native_decide

theorem scalar_carrier_conflicting_in_compare_bottoms :
    exportJsonBottoms "out: {#a: 1, 5, 6} < 10\n" = true := by
  native_decide

-- HIDDEN-DECL OUTPUT RULE (oracle-confirmed). A `_b` hidden decl rides the carrier the same as
-- a `#a` definition decl: excluded from export, still selectable.
theorem scalar_carrier_hidden_decl_selectable_not_output :
    exportJsonMatches "x: {#a: 1, _b: 2, 5}\nout: x\nsa: x.#a\nsb: x._b\n"
      "{\n    \"x\": 5,\n    \"out\": 5,\n    \"sa\": 1,\n    \"sb\": 2\n}\n" = true := by
  native_decide

-- CARRIER IN A LARGER MEET (oracle-confirmed). Three carriers chained: scalars unify (`5`),
-- all three decls survive and stay selectable.
theorem scalar_carrier_three_way_meet_keeps_all_decls :
    exportJsonMatches "x: {#a: 1, 5} & {#b: 2, int} & {#c: 3, >0}\nout: [x.#a, x.#b, x.#c]\n"
      "{\n    \"x\": 5,\n    \"out\": [\n        1,\n        2,\n        3\n    ]\n}\n" = true := by
  native_decide

-- CARRIER & OUTPUT-FIELD STRUCT (oracle-confirmed). A right struct carrying a REGULAR (output)
-- field conflicts with the carrier-scalar — `5 & {b:2}` is int-vs-struct bottom.
theorem scalar_carrier_meet_output_field_struct_bottoms :
    evalSourceMatches "out: {#a: 1, 5} & {b: 2}\n" "out: _|_" = true := by
  native_decide

-- LIST-CARRIER & CARRIER (oracle-confirmed). Two list carriers MERGE: lists unify, both decls
-- survive selectable — the list analog of the three-way scalar merge above (case 1, must MERGE).
theorem list_carrier_meet_carrier_keeps_all_decls :
    exportJsonMatches "x: {#a: 1, [1, 2]} & {#b: 2, [1, 2]}\nout: [x.#a, x.#b]\n"
      "{\n    \"x\": [\n        1,\n        2\n    ],\n    \"out\": [\n        1,\n        2\n    ]\n}\n"
      = true := by
  native_decide

-- LIST-CARRIER & OUTPUT-FIELD STRUCT (oracle-confirmed). `[1,2] & {b:2}` is list-vs-struct
-- bottom — the list analog of the scalar output-field case (case 2, must BOTTOM).
theorem list_carrier_meet_output_field_struct_bottoms :
    evalSourceMatches "out: {#a: 1, [1, 2]} & {b: 2}\n" "out: _|_" = true := by
  native_decide

-- ┌─ CARRIER-VS-DECLS-ONLY-STRUCT MEET (CARRIER-STRUCT-MEET, oracle-confirmed v0.16.1) ────────┐
-- A scalar carrier (`{#a:1,5}` IS the scalar `5`) met with a PURE decls-only struct that has NO
-- embed of its own (`{#b:2}` is a struct, not a carrier) BOTTOMS: cue rejects `5 & {#b:2}` as
-- int-vs-struct (spec: unifying different types is `_|_`). The carrier is its payload; payload-kind
-- vs struct = bottom. Distinct from carrier & carrier (`{#a:1,5} & {#b:2,5}`), which MERGES — that
-- stays green below. The identical rule holds for the `.embeddedList` carrier (list analogs follow).
theorem meet_scalar_carrier_with_declsonly_struct_bottoms :
    exportJsonBottoms "x: {#a: 1, 5} & {#b: 2}\nrb: x.#b\n" = true := by
  native_decide

-- Operand order is symmetric — the decls-only struct on the LEFT bottoms identically.
theorem meet_declsonly_struct_with_scalar_carrier_bottoms :
    exportJsonBottoms "x: {#b: 2} & {#a: 1, 5}\nrb: x.#b\n" = true := by
  native_decide

theorem meet_scalar_carrier_with_lone_hidden_struct_bottoms :
    exportJsonBottoms "out: {#x: 1, 5} & {#y: 2}\n" = true := by
  native_decide

-- A carrier carrying MULTIPLE decls met with a decls-only struct still bottoms (the payload is
-- still a scalar regardless of how many decls ride it).
theorem meet_multi_decl_scalar_carrier_with_declsonly_struct_bottoms :
    exportJsonBottoms "out: {#a: 1, #b: 2, 5} & {#c: 3}\n" = true := by
  native_decide

-- LIST-carrier analogs — the same rule, `[1,2] & {#b:2}` is list-vs-struct bottom.
theorem meet_list_carrier_with_declsonly_struct_bottoms :
    exportJsonBottoms "x: {#a: 1, [1, 2]} & {#b: 2}\nrb: x.#b\n" = true := by
  native_decide

theorem meet_declsonly_struct_with_list_carrier_bottoms :
    exportJsonBottoms "x: {#b: 2} & {#a: 1, [1, 2]}\nrb: x.#b\n" = true := by
  native_decide
-- └────────────────────────────────────────────────────────────────────────────────────────────┘

-- ┌─ SELF-CONJ-CYCLE-INDIRECT (duplicate-field slot layout + reference-cycle truncation) ─┐
-- Resolution indexes the DEDUPLICATED slot layout (`buildFrame` over `canonicalFieldLayout`),
-- so a reference to a field sitting after a collapsed duplicate lands on its evaluator slot
-- instead of a stale higher index that would dangle into `unresolvedBinding` → bottom. The
-- reference cycle then truncates to top via the existing depth-0 `slotVisited` guard.
theorem dupfield_forward_ref_resolves :
    evalSourceMatches "x: 1\nx: y\ny: 1\n" "x: 1\ny: 1" = true := by
  native_decide

theorem sibling_cycle_truncates_to_top :
    evalSourceMatches "x: 1\nx: y & int\ny: x\n" "x: 1\ny: 1" = true := by
  native_decide

-- A PLAIN sibling reference (not a conjunction) across a collapsed duplicate slot also
-- resolves — the fix is the resolve/eval index-layout alignment, not a conj-only rebase.
theorem plain_ref_across_collapsed_dup_resolves :
    evalSourceMatches "x: 1\nx: 1\ny: 5\nz: y\n" "x: 1\ny: 5\nz: 5" = true := by
  native_decide

-- GUARD (over-truncation, one direction): a genuine conflict must STILL bottom.
theorem direct_self_conflict_still_bottoms :
    exportJsonBottoms "x: 1\nx: x & 2\n" = true := by
  native_decide

theorem cyclic_conflict_still_bottoms :
    exportJsonBottoms "x: 1\nx: y\ny: 2\n" = true := by
  native_decide

-- GUARD (over-truncation, other direction): a legitimate indirect resolve must STILL resolve.
theorem indirect_field_selection_still_resolves :
    evalSourceMatches "x: {a: 1}\nx: {b: x.a}\n" "x: {a: 1, b: 1}" = true := by
  native_decide
-- └────────────────────────────────────────────────────────────────────────────────────────────┘

-- ┌─ SELF-SELECT-CYCLE-CROSSFRAME (cross-frame selector reference-cycle → top) ─┐
-- `x.a` inside `x`'s own body selects a field of the struct being evaluated. Forcing the whole
-- `x` re-enters its in-progress body (a `.conj` body escapes `structStack` and bottoms via fuel;
-- a `.struct` body bottoms structurally) — both fabricate `_|_`. Resolving `x.label` to `label`'s
-- slot in the LIVE enclosing frame (found by `pushFrame` frame identity, `enclosingSelfSelectId?`)
-- routes the self-selection through the depth-0 `slotVisited ⇒ truncate .top` reference-cycle rule.
theorem self_select_cycle_truncates_to_top :
    evalSourceMatches "x: {a: 1}\nx: {a: x.a}\n" "x: {a: 1}" = true := by
  native_decide

-- A NON-cyclic self-select (`b` reads sibling `a`) resolves its target, not truncated.
theorem self_select_sibling_noncycle_resolves :
    evalSourceMatches "x: {a: 1, b: x.a}\n" "x: {a: 1, b: 1}" = true := by
  native_decide

-- GUARD (over-suppression, the dangerous direction): a VALID cross-struct select whose target
-- frame is NOT the live enclosing one must STILL resolve — not be mistaken for a self-cycle.
theorem self_select_valid_crossframe_resolves :
    evalSourceMatches "x: {a: 1}\ny: {b: x.a}\n" "x: {a: 1}\ny: {b: 1}" = true := by
  native_decide

-- GUARD (frame identity, not label heuristic): a DIFFERENT struct `z` whose sole field `a`
-- coincides in label with `x`'s must resolve `z.a = x.a`, never self-truncate on label match.
theorem self_select_label_coincidence_resolves :
    evalSourceMatches "x: {a: 1}\nz: {a: x.a}\n" "x: {a: 1}\nz: {a: 1}" = true := by
  native_decide

-- GUARD (over-truncation): a real conflict through the cycle must STILL bottom
-- (`x.a → top`, so `a = 1 & (top & 2) = 1 & 2 = ⊥`).
theorem self_select_cycle_conflict_still_bottoms :
    exportJsonBottoms "x: {a: 1}\nx: {a: x.a & 2}\n" = true := by
  native_decide

-- NESTED (two-selector chain `x.a.b`): the same class, resolved through `selectChainId?`.
theorem self_select_deeper_cycle_truncates_to_top :
    evalSourceMatches "x: {a: {b: 1}}\nx: {a: {b: x.a.b}}\n" "x: {a: {b: 1}}" = true := by
  native_decide

theorem self_select_deeper_valid_crossframe_resolves :
    evalSourceMatches "x: {a: {b: 1}}\ny: {c: x.a.b}\n" "x: {a: {b: 1}}\ny: {c: 1}" = true := by
  native_decide

theorem self_select_deeper_conflict_still_bottoms :
    exportJsonBottoms "x: {a: {b: 1}}\nx: {a: {b: x.a.b & 2}}\n" = true := by
  native_decide
-- └────────────────────────────────────────────────────────────────────────────────────────────┘

-- COVERAGE TRIPWIRE (test-health). Anchors the LAST theorem of every section; a swallowed
-- section turns its anchor into an unknown identifier and `#check` fails to elaborate.
#check @eval_static_string_field_index                       -- static selectors / indices
#check @eval_cycle_with_repeated_selection                   -- memoization pins
#check @structural_cycle_mutual_regular_fields_detected      -- structural-cycle detection
#check @sc3_default_not_collapsed_into_value                 -- terminating-disjunct
#check @scalar_embed_two_distinct_conflicts                  -- scalar struct-embedding collapse
#check @field_struct_then_scalar_conflicts                   -- empty struct meet scalar
#check @meet_declsonly_struct_with_list_carrier_bottoms      -- scalar/list decl carriers
#check @indirect_field_selection_still_resolves              -- dedup slot layout + cycle guards
#check @self_select_deeper_conflict_still_bottoms            -- cross-frame selector cycle → top

end Kue
