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

theorem eval_additive_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"sum", .regular, .binary .add (.prim (.int 1)) (.prim (.int 2)), false⟩,
            ⟨"diff", .regular, .binary .sub (.prim (.int 5)) (.prim (.int 3)), false⟩,
            ⟨"cat", .regular, .binary .add (.prim (.string "a")) (.prim (.string "b")), false⟩,
            ⟨"bytes", .regular, .binary .add (.prim (.bytes (textBytes "ab"))) (.prim (.bytes (textBytes "cd"))), false⟩
          ] .regularOpen none []))
      = "sum: 3\ndiff: 2\ncat: \"ab\"\nbytes: 'abcd'" := by
  native_decide

theorem eval_float_additive_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"floatSum", .regular, .binary .add (.prim (mkFloatText "1.5")) (.prim (mkFloatText "2.25")), false⟩,
            ⟨"intFloat", .regular, .binary .add (.prim (.int 1)) (.prim (mkFloatText "2.5")), false⟩,
            ⟨"floatSub", .regular, .binary .sub (.prim (mkFloatText "5.5")) (.prim (.int 2)), false⟩,
            ⟨"exp", .regular, .binary .add (.prim (mkFloatText "1e+3")) (.prim (.int 2)), false⟩,
            ⟨"small", .regular, .binary .add (.prim (mkFloatText "0.1")) (.prim (mkFloatText "0.2")), false⟩
          ] .regularOpen none []))
      = "floatSum: 3.75\nintFloat: 3.5\nfloatSub: 3.5\nexp: 1002.0\nsmall: 0.3" := by
  native_decide

theorem eval_multiplication_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"mul", .regular, .binary .mul (.prim (.int 3)) (.prim (.int 4)), false⟩,
            ⟨
              "precedence",
              .regular,
              .binary .add (.prim (.int 1)) (.binary .mul (.prim (.int 2)) (.prim (.int 3)))
            , false⟩
          ] .regularOpen none []))
      = "mul: 12\nprecedence: 7" := by
  native_decide

theorem eval_division_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"div", .regular, .binary .div (.prim (.int 5)) (.prim (.int 2)), false⟩,
            ⟨"whole", .regular, .binary .div (.prim (.int 6)) (.prim (.int 3)), false⟩,
            ⟨"third", .regular, .binary .div (.prim (.int 1)) (.prim (.int 3)), false⟩,
            ⟨"negative", .regular, .binary .div (.prim (.int (-5))) (.prim (.int 2)), false⟩
          ] .regularOpen none []))
      = "div: 2.5\nwhole: 2.0\nthird: 0.3333333333333333333333333333333333\nnegative: -2.5" := by
  native_decide

theorem eval_division_by_zero_bottom :
    evalBinary .div (.prim (.int 1)) (.prim (.int 0)) = .bottomWith [.divisionByZero] := by
  rfl

theorem eval_integer_keyword_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"divValue", .regular, .binary .intDiv (.prim (.int (-7))) (.prim (.int 3)), false⟩,
            ⟨"modValue", .regular, .binary .intMod (.prim (.int (-7))) (.prim (.int 3)), false⟩,
            ⟨"quoValue", .regular, .binary .intQuo (.prim (.int (-7))) (.prim (.int 3)), false⟩,
            ⟨"remValue", .regular, .binary .intRem (.prim (.int (-7))) (.prim (.int 3)), false⟩
          ] .regularOpen none []))
      = "divValue: -3\nmodValue: 2\nquoValue: -2\nremValue: -1" := by
  native_decide

theorem eval_integer_keyword_incomplete_keeps_infix :
    formatValue (evalBinary .intDiv (.kind .int) (.prim (.int 3))) = "int div 3" := by
  native_decide

theorem eval_equality_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"same", .regular, .binary .eq (.prim (.int 1)) (.prim (.int 1)), false⟩,
            ⟨"diff", .regular, .binary .ne (.prim (.int 1)) (.prim (.int 2)), false⟩,
            ⟨"text", .regular, .binary .eq (.prim (.string "a")) (.prim (.string "b")), false⟩
          ] .regularOpen none []))
      = "same: true\ndiff: true\ntext: false" := by
  native_decide

theorem eval_ordering_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"lt", .regular, .binary .lt (.prim (.int 1)) (.prim (.int 2)), false⟩,
            ⟨"le", .regular, .binary .le (.prim (.int 2)) (.prim (.int 2)), false⟩,
            ⟨"gt", .regular, .binary .gt (.prim (.int 3)) (.prim (.int 2)), false⟩,
            ⟨"ge", .regular, .binary .ge (.prim (.int 3)) (.prim (.int 4)), false⟩,
            ⟨"slt", .regular, .binary .lt (.prim (.string "a")) (.prim (.string "b")), false⟩
          ] .regularOpen none []))
      = "lt: true\nle: true\ngt: true\nge: false\nslt: true" := by
  native_decide

theorem eval_numeric_comparison_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"lt", .regular, .binary .lt (.prim (mkFloatText "1.5")) (.prim (.int 2)), false⟩,
            ⟨"le", .regular, .binary .le (.prim (mkFloatText "1.5")) (.prim (mkFloatText "1.50")), false⟩,
            ⟨"gt", .regular, .binary .gt (.prim (mkFloatText "1e+3")) (.prim (mkFloatText "999.9")), false⟩,
            ⟨"ge", .regular, .binary .ge (.prim (mkFloatText "1.0")) (.prim (.int 1)), false⟩,
            ⟨"eq", .regular, .binary .eq (.prim (.int 1)) (.prim (mkFloatText "1.0")), false⟩,
            ⟨"ne", .regular, .binary .ne (.prim (.int 1)) (.prim (mkFloatText "1.0")), false⟩
          ] .regularOpen none []))
      = "lt: true\nle: true\ngt: true\nge: true\neq: true\nne: false" := by
  native_decide

theorem eval_logical_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"andFalse", .regular, .binary .boolAnd (.prim (.bool true)) (.prim (.bool false)), false⟩,
            ⟨"orTrue", .regular, .binary .boolOr (.prim (.bool false)) (.prim (.bool true)), false⟩,
            ⟨
              "andCmp",
              .regular,
              .binary .boolAnd
                (.binary .lt (.prim (.int 1)) (.prim (.int 2)))
                (.binary .gt (.prim (.int 3)) (.prim (.int 2)))
            , false⟩
          ] .regularOpen none []))
      = "andFalse: false\norTrue: true\nandCmp: true" := by
  native_decide

theorem eval_logical_not_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"notFalse", .regular, .unary .boolNot (.prim (.bool false)), false⟩,
            ⟨"notCmp", .regular, .unary .boolNot (.binary .lt (.prim (.int 1)) (.prim (.int 2))), false⟩,
            ⟨"double", .regular, .unary .boolNot (.unary .boolNot (.prim (.bool true))), false⟩
          ] .regularOpen none []))
      = "notFalse: true\nnotCmp: false\ndouble: true" := by
  native_decide

theorem eval_unary_numeric_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"negGroup", .regular, .unary .numNeg (.binary .add (.prim (.int 1)) (.prim (.int 2))), false⟩,
            ⟨"posGroup", .regular, .unary .numPos (.binary .add (.prim (.int 1)) (.prim (.int 2))), false⟩,
            ⟨"negFloat", .regular, .unary .numNeg (.prim (mkFloatText "1.5")), false⟩
          ] .regularOpen none []))
      = "negGroup: -3\nposGroup: 3\nnegFloat: -1.5" := by
  native_decide

theorem eval_regex_match_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"match", .regular, .binary .regexMatch (.prim (.string "abc")) (.prim (.string "^a")), false⟩,
            ⟨"miss", .regular, .binary .regexMatch (.prim (.string "abc")) (.prim (.string "z")), false⟩,
            ⟨"notMatch", .regular, .binary .regexNotMatch (.prim (.string "abc")) (.prim (.string "z")), false⟩
          ] .regularOpen none []))
      = "match: true\nmiss: false\nnotMatch: true" := by
  native_decide

theorem eval_list_index_out_of_range_bottom :
    (evalStructRefs
      (resolveStructRefs
        (mkStruct [
            ⟨"xs", .regular, .list [.prim (.int 10)], false⟩,
            ⟨"x", .regular, .index (.ref "xs") (.prim (.int 2)), false⟩
          ] .regularOpen none []))
      == mkStruct [
          ⟨"xs", .regular, .list [.prim (.int 10)], false⟩,
          ⟨"x", .regular, .bottomWith [.indexOutOfRange 2 1], false⟩
        ] .regularOpen none []) = true := by
  native_decide

theorem eval_missing_binding_id_bottom :
    (evalStructRefs
      (mkStruct [⟨"x", .regular, .refId ⟨0, 2⟩, false⟩] .regularOpen none [])
      == mkStruct [⟨"x", .regular, .bottomWith [.unresolvedBinding ⟨0, 2⟩], false⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_binding_id_not_label_lookup :
    (evalStructRefs
      (mkStruct [⟨"#same", .definition, .kind .int, false⟩, ⟨"same", .regular, .kind .string, false⟩, ⟨"x", .regular, .refId ⟨0, 1⟩, false⟩] .regularOpen none [])
      == mkStruct [⟨"#same", .definition, .kind .int, false⟩, ⟨"same", .regular, .kind .string, false⟩, ⟨"x", .regular, .kind .string, false⟩] .regularOpen none []) = true := by
  native_decide

theorem resolve_direct_self_reference :
    (resolveStructRefs
      (mkStruct [⟨"x", .regular, .ref "x", false⟩] .regularOpen none [])
      == mkStruct [⟨"x", .regular, .refId ⟨0, 0⟩, false⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_direct_self_reference_as_top :
    (evalStructRefs
      (resolveStructRefs (mkStruct [⟨"x", .regular, .ref "x", false⟩] .regularOpen none []))
      == mkStruct [⟨"x", .regular, .top, false⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_mutual_reference_cycle_as_top :
    (evalStructRefs
      (resolveStructRefs (mkStruct [⟨"x", .regular, .ref "y", false⟩, ⟨"y", .regular, .ref "x", false⟩] .regularOpen none []))
      == mkStruct [⟨"x", .regular, .top, false⟩, ⟨"y", .regular, .top, false⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_three_reference_cycle_as_top :
    (evalStructRefs
      (resolveStructRefs
        (mkStruct [
            ⟨"x", .regular, .ref "y", false⟩,
            ⟨"y", .regular, .ref "z", false⟩,
            ⟨"z", .regular, .ref "x", false⟩
          ] .regularOpen none []))
      == mkStruct [⟨"x", .regular, .top, false⟩, ⟨"y", .regular, .top, false⟩, ⟨"z", .regular, .top, false⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_direct_constrained_cycle_keeps_constraint :
    (evalStructRefs
      (resolveStructRefs (mkStruct [⟨"x", .regular, .conj [.ref "x", .boundConstraint (intDecimal 0) .ge .number], false⟩] .regularOpen none []))
      == mkStruct [⟨"x", .regular, .boundConstraint (intDecimal 0) .ge .number, false⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_mutual_constrained_cycle_keeps_constraint :
    (evalStructRefs
      (resolveStructRefs
        (mkStruct [
            ⟨"a", .regular, .conj [.ref "b", .boundConstraint (intDecimal 0) .ge .number], false⟩,
            ⟨"b", .regular, .ref "a", false⟩
          ] .regularOpen none []))
      == mkStruct [⟨"a", .regular, .boundConstraint (intDecimal 0) .ge .number, false⟩, ⟨"b", .regular, .boundConstraint (intDecimal 0) .ge .number, false⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_non_cycle_reference_still_uses_target_value :
    (evalStructRefs
      (resolveStructRefs (mkStruct [⟨"x", .regular, .kind .int, false⟩, ⟨"y", .regular, .ref "x", false⟩] .regularOpen none []))
      == mkStruct [⟨"x", .regular, .kind .int, false⟩, ⟨"y", .regular, .kind .int, false⟩] .regularOpen none []) = true := by
  native_decide

-- A value alias (`Self={…}`) lowers to a `.thisStruct` let-binding; `Self.field`
-- (a selector on the binding) resolves as a same-struct sibling reference. Pins the
-- eval-level `thisStruct` mechanism directly.
theorem eval_value_alias_self_reference :
    (evalStructRefs
      (resolveStructRefs
        (mkStruct [
            ⟨"Self", .letBinding, .thisStruct, false⟩,
            ⟨"x", .regular, .prim (.int 5), false⟩,
            ⟨"y", .regular, .selector (.ref "Self") "x", false⟩
          ] .regularOpen none []))
      == mkStruct [
          ⟨"Self", .letBinding, .thisStruct, false⟩,
          ⟨"x", .regular, .prim (.int 5), false⟩,
          ⟨"y", .regular, .prim (.int 5), false⟩
        ] .regularOpen none []) = true := by
  native_decide

-- A self-reference cycle through the alias is bounded to top, never diverging.
theorem eval_value_alias_cycle_bounds_to_top :
    (evalStructRefs
      (resolveStructRefs
        (mkStruct [
            ⟨"Self", .letBinding, .thisStruct, false⟩,
            ⟨"x", .regular, .selector (.ref "Self") "y", false⟩,
            ⟨"y", .regular, .selector (.ref "Self") "x", false⟩
          ] .regularOpen none []))
      == mkStruct [
          ⟨"Self", .letBinding, .thisStruct, false⟩,
          ⟨"x", .regular, .top, false⟩,
          ⟨"y", .regular, .top, false⟩
        ] .regularOpen none []) = true := by
  native_decide

theorem eval_regular_disjunction_uses_join_normalization :
    (evalStructRefs
      (mkStruct [⟨"x", .regular, .disj [(.regular, .boundConstraint (intDecimal 5) .ge .number), (.regular, .boundConstraint (intDecimal 0) .ge .number)], false⟩] .regularOpen none [])
      == mkStruct [⟨"x", .regular, .boundConstraint (intDecimal 0) .ge .number, false⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_regular_field_reference_to_hidden :
    (evalStructRefs
      (resolveStructRefs (mkStruct [⟨"_secret", .hidden, .prim (.string "x"), false⟩, ⟨"value", .regular, .ref "_secret", false⟩] .regularOpen none []))
      == mkStruct [⟨"_secret", .hidden, .prim (.string "x"), false⟩, ⟨"value", .regular, .prim (.string "x"), false⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_reference_inside_struct_tail :
    (evalStructRefs
      (resolveStructRefs (mkStruct [⟨"#A", .definition, .kind .int, false⟩] .defOpenViaTail (some (.ref "#A")) []))
      == mkStruct [⟨"#A", .definition, .kind .int, false⟩] .defOpenViaTail (some (.kind .int)) []) = true := by
  native_decide

theorem eval_reference_inside_nested_struct :
    (evalStructRefs
      (resolveStructRefs
        (mkStruct [⟨"x", .regular, mkStruct [⟨"#A", .definition, .kind .int, false⟩, ⟨"x", .regular, .ref "#A", false⟩] .regularOpen none [], false⟩] .regularOpen none []))
      == mkStruct [⟨"x", .regular, mkStruct [⟨"#A", .definition, .kind .int, false⟩, ⟨"x", .regular, .kind .int, false⟩] .regularOpen none [], false⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_reference_inside_struct_pattern :
    (evalStructRefs
      (resolveStructRefs (mkStruct [⟨"#A", .definition, .kind .int, false⟩] .regularOpen none [((.kind .string), (.ref "#A"))]))
      == mkStruct [⟨"#A", .definition, .kind .int, false⟩] .regularOpen none [((.kind .string), (.kind .int))]) = true := by
  native_decide

theorem eval_struct_pattern_constrains_own_regular_field :
    (evalStructRefs
      (mkStruct [⟨"a", .regular, .prim (.string "bad"), false⟩] .regularOpen none [((.kind .string), (.kind .int))])
      == mkStruct [⟨"a", .regular, .bottomWith [.fieldConstraint "a"], false⟩] .regularOpen none [((.kind .string), (.kind .int))]) = true := by
  native_decide

theorem string_kind_pattern_types_matching_field :
    (meet
      (mkStruct [] .regularOpen none [((.kind .string), (.kind .int))])
      (mkStruct [⟨"a", .regular, .prim (.int 1), false⟩] .regularOpen none [])
      == mkStruct [⟨"a", .regular, .prim (.int 1), false⟩] .regularOpen none [((.kind .string), (.kind .int))]) = true := by
  native_decide

theorem string_kind_pattern_rejects_type_mismatch :
    containsBottom
      (meet
        (mkStruct [] .regularOpen none [((.kind .string), (.kind .int))])
        (mkStruct [⟨"a", .regular, .prim (.string "x"), false⟩] .regularOpen none [])) = true := by
  native_decide

theorem eval_len_builtin_call_after_reference_resolution :
    (evalStructRefs
      (resolveStructRefs
        (mkStruct [⟨"x", .regular, .prim (.string "abc"), false⟩, ⟨"y", .regular, .builtinCall "len" [.ref "x"], false⟩] .regularOpen none []))
      == mkStruct [⟨"x", .regular, .prim (.string "abc"), false⟩, ⟨"y", .regular, .prim (.int 3), false⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_integer_builtin_call_after_reference_resolution :
    (evalStructRefs
      (resolveStructRefs
        (mkStruct [
            ⟨"n", .regular, .prim (.int (-7)), false⟩,
            ⟨"q", .regular, .builtinCall "div" [.ref "n", .prim (.int 3)], false⟩
          ] .regularOpen none []))
      == mkStruct [⟨"n", .regular, .prim (.int (-7)), false⟩, ⟨"q", .regular, .prim (.int (-3)), false⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_incomplete_builtin_call_remains_call :
    (evalStructRefs (mkStruct [⟨"x", .regular, .builtinCall "len" [.kind .string], false⟩] .regularOpen none [])
      == mkStruct [⟨"x", .regular, .builtinCall "len" [.kind .string], false⟩] .regularOpen none []) = true := by
  native_decide

-- Slice C (`closure-default-in-guard`). A marked-default disjunction collapses to its
-- default in a concrete context; a non-default disjunction does not. These pin
-- `resolveDisjDefault?` directly.
theorem resolve_default_disj_picks_marked_default :
    (resolveDisjDefault? [(.default, .prim (.bool false)), (.regular, .kind .bool)]
      == some (.prim (.bool false))) = true := by
  native_decide

theorem resolve_default_disj_non_default_stays_unresolved :
    (resolveDisjDefault? [(.regular, .prim (.int 1)), (.regular, .prim (.int 2))]
      == none) = true := by
  native_decide

theorem resolve_default_disj_multiple_defaults_stays_unresolved :
    (resolveDisjDefault? [(.default, .prim (.int 1)), (.default, .prim (.int 2)), (.regular, .kind .int)]
      == none) = true := by
  native_decide

-- Slice F1. A unary op RESOLVES its disjunction operand to the default first, then applies
-- the scalar op — it does NOT distribute. `!(bool | *false)` resolves to `false`, then
-- `!false = true`. (Old slice-C behavior `bool | *true` was wrong: CUE forces the operand
-- concrete; `!(bool | *false)` → `true`, oracle-verified.)
theorem distribute_not_over_default_disj :
    (distributeUnary .boolNot (.disj [(.default, .prim (.bool false)), (.regular, .kind .bool)])
      == .prim (.bool true)) = true := by
  native_decide

-- Slice F1. `(int | *1) + 1` resolves the operand to `1`, then `1 + 1 = 2` — NOT
-- `int+1 | *2`. CUE forces arithmetic operands concrete (`(int | *1) + 1 → 2`,
-- oracle-verified), never a cross-product.
theorem distribute_add_over_default_disj :
    (distributeBinary .add (.disj [(.default, .prim (.int 1)), (.regular, .kind .int)]) (.prim (.int 1))
      == .prim (.int 2)) = true := by
  native_decide

-- ### Slice F1 — default-mark algebra (audit #3 Violation)
--
-- Three coupled facets, oracle-verified against `cue` v0.16.1:
-- (1) unification ANDs default sets across the cross product (was OR);
-- (2) `flattenAlternatives` honors two-level default precedence (a default-marked outer
-- arm selects the inner disjunction's own default structure);
-- (3) equal defaults dedup before the unique-default test.
-- Arithmetic/comparison/unary ops resolve each operand to its default FIRST (no
-- distribution / cross-product).

-- F1 facet 1, the cross-product where `combineMark` lives. Unification ANDs the default
-- sets: `(1|*2) & (1|2|3)` → the no-`*` right operand contributes its whole set as
-- defaults, so only `*2 & 2` survives as a default → resolves to `2`.
theorem f1_unify_cross_and_marks_resolves :
    (resolveDisjDefault?
      (match meet
          (.disj [(.regular, .prim (.int 1)), (.default, .prim (.int 2))])
          (.disj [(.regular, .prim (.int 1)), (.regular, .prim (.int 2)), (.regular, .prim (.int 3))]) with
        | .disj alts => alts
        | _ => [])
      == some (.prim (.int 2))) = true := by
  native_decide

-- F1 facet 1, NEGATIVE: two distinct defaults survive the cross → ambiguous (no resolve).
-- `(*1|2) & (1|*2)` crosses to live `1|2` with no surviving default (`*1&1` regular,
-- `2&*2` regular) → stays the disjunction `1 | 2`.
theorem f1_unify_cross_two_survivors_ambiguous :
    (meet
      (.disj [(.default, .prim (.int 1)), (.regular, .prim (.int 2))])
      (.disj [(.regular, .prim (.int 1)), (.default, .prim (.int 2))])
      == .disj [(.regular, .prim (.int 1)), (.regular, .prim (.int 2))]) = true := by
  native_decide

-- F1. `combineMark` is AND: a result alternative is default iff BOTH inputs were.
theorem f1_combine_mark_is_and :
    (combineMark .default .default == .default
      && combineMark .default .regular == .regular
      && combineMark .regular .default == .regular
      && combineMark .regular .regular == .regular) = true := by
  native_decide

-- F1 facet 3, equal-default dedup. `*1 | *1 | 2` → the two equal defaults collapse to one,
-- so a unique default remains → resolves to `1`. The headline dedup case.
theorem f1_equal_defaults_dedup_resolves :
    (resolveDisjDefault?
      [(.default, .prim (.int 1)), (.default, .prim (.int 1)), (.regular, .prim (.int 2))]
      == some (.prim (.int 1))) = true := by
  native_decide

-- F1 facet 3, NEGATIVE: DISTINCT defaults stay ambiguous (no spurious dedup).
theorem f1_distinct_defaults_stay_ambiguous :
    (resolveDisjDefault? [(.default, .prim (.int 1)), (.default, .prim (.int 2))]
      == none) = true := by
  native_decide

-- F1 facet 2, two-level default precedence. `*d | 5` with `d : 1 | 2` (no inner default):
-- the outer default selects `d`'s disjunction, promoting its own arms to defaults (no
-- inner `*` → both `1` and `2` become defaults), while the regular outer `5` stays
-- regular. The flatten thus carries the inner default structure rather than blanket- or
-- OR-marking — a blanket-OR-mark would wrongly produce `*1 | 2 | 5`.
theorem f1_nested_default_flatten_carries_inner :
    (liveAlternatives
      [(.default, .disj [(.regular, .prim (.int 1)), (.regular, .prim (.int 2))]),
       (.regular, .prim (.int 5))]
      == [(.default, .prim (.int 1)), (.default, .prim (.int 2)), (.regular, .prim (.int 5))]) = true := by
  native_decide

-- F1 facet 2, precedence at resolve. With the `*d | 5` flatten above, the two carried
-- defaults `1`, `2` are DISTINCT → `resolveDisjDefault?` shadows the regular `5` and stays
-- ambiguous (matches cue `incomplete value 1 | 2`), neither resolving to `1` nor keeping
-- `5`.
theorem f1_nested_default_flatten_resolve_ambiguous :
    (resolveDisjDefault?
      [(.default, .disj [(.regular, .prim (.int 1)), (.regular, .prim (.int 2))]),
       (.regular, .prim (.int 5))]
      == none) = true := by
  native_decide

-- F1 facet 2. `*d | 5` with `d : *1 | 2` (inner default `*1`): only the inner default
-- carries → unique default `1` → resolves to `1` (matches cue).
theorem f1_nested_inner_default_resolves :
    (resolveDisjDefault?
      [(.default, .disj [(.default, .prim (.int 1)), (.regular, .prim (.int 2))]),
       (.regular, .prim (.int 5))]
      == some (.prim (.int 1))) = true := by
  native_decide

-- F1 facet 2, NEGATIVE: a REGULAR outer arm does NOT contribute its inner disjunction to
-- the default set. `d | *5` with `d : 1 | 2` → `d`'s arms stay regular (shed), the lone
-- default `5` wins → resolves to `5`.
theorem f1_nested_regular_outer_sheds :
    (resolveDisjDefault?
      [(.regular, .disj [(.regular, .prim (.int 1)), (.regular, .prim (.int 2))]),
       (.default, .prim (.int 5))]
      == some (.prim (.int 5))) = true := by
  native_decide

-- F1, arithmetic resolve-first. `(1|*2) + (10|*20)` resolves each operand to its default
-- (`2`, `20`) then adds → `22`. The headline arithmetic case; NOT a mark cross-product.
theorem f1_arithmetic_resolves_operands_first :
    (distributeBinary .add
      (.disj [(.regular, .prim (.int 1)), (.default, .prim (.int 2))])
      (.disj [(.regular, .prim (.int 10)), (.default, .prim (.int 20))])
      == .prim (.int 22)) = true := by
  native_decide

-- F1, arithmetic NEGATIVE: a no-default operand does NOT resolve, so the op stays a stuck
-- node — `(1|2) + 10` keeps the unevaluated `(1|2) + 10`, matching cue's "unresolved
-- disjunction" (manifest reports incomplete), never an over-resolution.
theorem f1_arithmetic_no_default_stays_stuck :
    (distributeBinary .add
      (.disj [(.regular, .prim (.int 1)), (.regular, .prim (.int 2))])
      (.prim (.int 10))
      == .binary .add (.disj [(.regular, .prim (.int 1)), (.regular, .prim (.int 2))]) (.prim (.int 10)))
      = true := by
  native_decide

-- F1, a non-default disjunction stays a non-default disjunction through resolve — no arm
-- becomes a default and it does not collapse (`1 | 2` stays ambiguous).
theorem f1_non_default_disj_stays_non_default :
    (resolveDisjDefault? [(.regular, .prim (.int 1)), (.regular, .prim (.int 2))]
      == none) = true := by
  native_decide

-- ### Disjunction-meet conformance sweep (2026-07-04 AFK probe).
--
-- End-to-end pins (parse → eval → export) over disjunction×disjunction distribution,
-- bottom-elimination, and default preservation through meet. Every VALUE verdict below is
-- oracle-confirmed byte-identical to cue v0.16.1; the eval-DISPLAY divergences that remain are
-- the documented SC-3 keep-marked family (Kue shows `*` marks cue elides), never a value gap.

-- Distribution, single survivor: `(1|2) & (2|3)` crosses to the lone live arm `2`, which
-- resolves on export. cue: `{"x":2}`.
theorem disj_meet_distribute_single_survivor :
    exportJsonMatches "x: (1|2) & (2|3)\n" "{\n    \"x\": 2\n}\n" = true := by
  native_decide

-- Distribution, multiple survivors → ambiguous. `(1|2) & (2|3|1)` keeps `1|2` (no default),
-- so export fails ambiguous — matching cue's `incomplete value 1 | 2`.
theorem disj_meet_distribute_multi_survivor_ambiguous :
    exportJsonBottoms "x: (1|2) & (2|3|1)\n" = true := by
  native_decide

-- Bottom-elimination, empty intersection → the whole disjunction bottoms. `(1|2) & (3|4)` has
-- no surviving arm. cue: `2 errors in empty disjunction`.
theorem disj_meet_empty_intersection_bottoms :
    exportJsonBottoms "x: (1|2) & (3|4)\n" = true := by
  native_decide

-- All-default from a markerless×markerless meet. `(1|2) & (1|2)`: each markerless operand
-- contributes its whole set as defaults (`withDefaultConvention`), so the surviving arms are
-- BOTH default — default-set = full set → export ambiguous, matching cue's `incomplete 1 | 2`.
theorem disj_meet_markerless_pair_ambiguous :
    exportJsonBottoms "x: (1|2) & (1|2)\n" = true := by
  native_decide

-- SC-3 all-default DISPLAY sub-case: the same markerless×markerless meet renders in eval as
-- `*1 | *2` (both arms carry the vacuous full-set default) where cue elides to `1 | 2`. The
-- (value, default) semantics coincide (export identical, pinned above); only the marked-vs-
-- elided display differs — the SC-3 keep-marked family. Pins current Kue display as a guard.
theorem disj_meet_markerless_pair_eval_all_default_display :
    evalSourceMatches "x: (1|2) & (1|2)\n" "x: *1 | *2" = true := by
  native_decide

-- Default position-independent through meet: `(*1|2) & (2|*1)` — the surviving default `1` is
-- picked regardless of which operand or arm-position carries the mark. cue: `1`.
theorem disj_meet_default_position_independent :
    exportJsonMatches "x: (*1|2) & (2|*1)\n" "{\n    \"x\": 1\n}\n" = true := by
  native_decide

-- Struct-arm default preserved through a narrowing meet: `(*{a:1}|{a:2,b:3}) & {b:3}` narrows
-- BOTH arms with `{b:3}`; the marked arm stays the default → `{a:1,b:3}`. cue agrees.
theorem disj_meet_struct_default_preserved :
    exportJsonMatches "x: (*{a:1}|{a:2,b:3}) & {b:3}\n"
      "{\n    \"x\": {\n        \"a\": 1,\n        \"b\": 3\n    }\n}\n" = true := by
  native_decide

-- Bound narrows a disjunction to its in-range arms, no default introduced: `(1|2|3) & (>=2)`
-- keeps `2 | 3` (ambiguous). cue: `2 | 3`.
theorem disj_meet_bound_narrows_arms :
    evalSourceMatches "x: (1|2|3) & (>=2)\n" "x: 2 | 3" = true := by
  native_decide

-- Float `*` threads the apd `(coefficient, exponent)` form (F4): coefficients multiply,
-- exponents ADD, matching cue's rendered GDA form. Scales add and the summed scale is
-- preserved verbatim: `1.5 * 2.0 = 3.00`, no trailing-zero trim. Assertions pin the RENDERED
-- output (`formatValue`), the observable behavior — the internal carrier `text` is an apd
-- anchor, not the display form. All oracle-confirmed against cue v0.16.1.
theorem eval_mul_two_floats :
    formatValue (evalMul (.prim (mkFloatText "1.5")) (.prim (mkFloatText "2.0"))) = "3.00" := by
  native_decide

-- Multiplication into a large-magnitude result renders in scientific form (positive exponent),
-- NOT the fully-expanded `600.0`: `2e2 * 3 = 6e+2`, `1.5e2 * 1e2 = 1.5e+4`, `1e2 * 1e2 = 1e+4`.
theorem eval_mul_scientific :
    formatValue (evalMul (.prim (mkFloatText "2e2")) (.prim (.int 3))) = "6e+2"
      ∧ formatValue (evalMul (.prim (mkFloatText "1.5e2")) (.prim (mkFloatText "1e2"))) = "1.5e+4"
      ∧ formatValue (evalMul (.prim (mkFloatText "1e2")) (.prim (mkFloatText "1e2"))) = "1e+4"
      ∧ formatValue (evalMul (.prim (.int 10)) (.prim (mkFloatText "1e2"))) = "1.0e+3" := by
  native_decide

-- Was a deferred-bottom pin; float÷float now evaluates through the decimal layer.
-- `/` always yields a float; `3.0 / 2.0 = 1.5` terminates cleanly (oracle-confirmed,
-- cue v0.16.1).
theorem eval_div_two_floats :
    formatValue (evalDiv (.prim (mkFloatText "3.0")) (.prim (mkFloatText "2.0"))) = "1.5" := by
  native_decide

-- Multiplication preserves the full summed scale: `1.0 * 1.0 = 1.00`.
theorem eval_mul_scale_preserved :
    formatValue (evalMul (.prim (mkFloatText "1.0")) (.prim (mkFloatText "1.0"))) = "1.00" := by
  native_decide

-- Mixed int×float promotes to float; int contributes scale 0.
theorem eval_mul_int_float :
    formatValue (evalMul (.prim (.int 2)) (.prim (mkFloatText "1.5"))) = "3.0" := by
  native_decide

-- float×int likewise.
theorem eval_mul_float_int :
    formatValue (evalMul (.prim (mkFloatText "1.5")) (.prim (.int 2))) = "3.0" := by
  native_decide

-- Negative operand carries through multiplication.
theorem eval_mul_negative :
    formatValue (evalMul (.prim (mkFloatText "-1.5")) (.prim (mkFloatText "2.0"))) = "-3.00" := by
  native_decide

-- int×int stays int (no float promotion).
theorem eval_mul_int_int :
    evalMul (.prim (.int 3)) (.prim (.int 4)) = .prim (.int 12) := by
  rfl

-- Float `+`/`-` thread the apd form (F4): the result exponent is `min(e₁,e₂)`, fixing the
-- rendered GDA form. A large-magnitude result renders scientific (`1e1 + 1e1 = 2e+1`,
-- `1.5e2 + 1e2 = 2.5e+2`, `1.5e3 - 1e3 = 5e+2`); a zero result KEEPS the min exponent
-- (`1e1 - 1e1 = 0e+1`); a small-magnitude result stays plain (`1e3 + 2 = 1002.0`).
theorem eval_add_sub_scientific :
    formatValue (evalAdd (.prim (mkFloatText "1e1")) (.prim (mkFloatText "1e1"))) = "2e+1"
      ∧ formatValue (evalAdd (.prim (mkFloatText "1.5e2")) (.prim (mkFloatText "1e2"))) = "2.5e+2"
      ∧ formatValue (evalSub (.prim (mkFloatText "1.5e3")) (.prim (mkFloatText "1e3"))) = "5e+2"
      ∧ formatValue (evalSub (.prim (mkFloatText "1e1")) (.prim (mkFloatText "1e1"))) = "0e+1"
      ∧ formatValue (evalAdd (.prim (mkFloatText "1e3")) (.prim (.int 2))) = "1002.0" := by
  native_decide

-- Trailing zeros survive via the min-exponent coefficient magnitude (no trim): `1.20 + 1.30
-- = 2.50`, `1.50 + 1.50 = 3.00`. A whole exponent-0 result renders `.0` in cue-native but bare
-- in JSON (`1.25e3 + 1 = 1251` under export) — pinned by the wild fixture.
theorem eval_add_trailing_zeros :
    formatValue (evalAdd (.prim (mkFloatText "1.20")) (.prim (mkFloatText "1.30"))) = "2.50"
      ∧ formatValue (evalAdd (.prim (mkFloatText "1.50")) (.prim (mkFloatText "1.50"))) = "3.00"
      ∧ formatValue (evalAdd (.prim (mkFloatText "1.25e3")) (.prim (.int 1))) = "1251.0" := by
  native_decide

-- Beyond the 34-digit apd context precision the exact sum rounds half-up and switches to
-- scientific: `1e33 + 1` stays exact (34 digits), `1e34 + 1` rounds to `1.000…000e+34`.
theorem eval_add_context_rounding :
    formatValue (evalAdd (.prim (mkFloatText "1e33")) (.prim (.int 1)))
        = "1000000000000000000000000000000001.0"
      ∧ formatValue (evalAdd (.prim (mkFloatText "1e34")) (.prim (.int 1)))
        = "1.000000000000000000000000000000000e+34"
      ∧ formatValue (evalAdd (.prim (mkFloatText "1e100")) (.prim (.int 1)))
        = "1.000000000000000000000000000000000e+100" := by
  native_decide

-- Exact-tie rounding is half-UP (ties away from zero), NOT half-even. `apdRoundToContext`'s
-- `2 * remainder >= divisor` rule rounds a dropped-part of exactly ½ up regardless of the kept
-- digit's parity. Guard: a 35-sig-digit float ending `…125` × 10³⁴ drops the trailing `5` on an
-- EXACT tie, and the kept 34th digit is `2` (EVEN) — half-up carries it to `3` (`…13`), whereas
-- half-even would keep the even `2` (`…12`). Pinned both signs (the rule is magnitude-symmetric via
-- `negative`); matches `cue` v0.16.1 (`1.000…013E+34`). Prior tie coverage was zero.
theorem eval_add_context_rounding_half_up_even_tie :
    formatValue (evalAdd (.prim (mkFloatText "1.0000000000000000000000000000000125e34")) (.prim (.int 0)))
        = "1.000000000000000000000000000000013e+34"
      ∧ formatValue (evalAdd (.prim (mkFloatText "-1.0000000000000000000000000000000125e34")) (.prim (.int 0)))
        = "-1.000000000000000000000000000000013e+34" := by
  native_decide

-- A terminating fractional quotient keeps its minimal form: `1.0 / 4.0 = 0.25`.
theorem eval_div_terminating :
    formatValue (evalDiv (.prim (mkFloatText "1.0")) (.prim (mkFloatText "4.0"))) = "0.25" := by
  native_decide

-- Clean division still yields a float, never an int: `4.0 / 2.0 = 2.0`.
theorem eval_div_clean_is_float :
    formatValue (evalDiv (.prim (mkFloatText "4.0")) (.prim (mkFloatText "2.0"))) = "2.0" := by
  native_decide

-- Mixed float÷int promotes; `3.0 / 2 = 1.5`.
theorem eval_div_float_int :
    formatValue (evalDiv (.prim (mkFloatText "3.0")) (.prim (.int 2))) = "1.5" := by
  native_decide

-- Mixed int÷float promotes; `2 / 4.0 = 0.5`.
theorem eval_div_int_float :
    formatValue (evalDiv (.prim (.int 2)) (.prim (mkFloatText "4.0"))) = "0.5" := by
  native_decide

-- Negative division carries the sign.
theorem eval_div_negative :
    formatValue (evalDiv (.prim (mkFloatText "-1.0")) (.prim (mkFloatText "4.0"))) = "-0.25" := by
  native_decide

-- Float division by zero is bottom with divisionByZero provenance.
theorem eval_div_float_by_zero :
    (evalDiv (.prim (mkFloatText "1.0")) (.prim (mkFloatText "0.0")) == .bottomWith [.divisionByZero]) = true := by
  native_decide

-- int÷int routes through the same decimal divider and yields a float: `6 / 2 = 3.0`.
theorem eval_div_int_int_is_float :
    formatValue (evalDiv (.prim (.int 6)) (.prim (.int 2))) = "3.0" := by
  native_decide

-- Division-result RENDER form (apd ideal exponent, F4-DIV) is pinned in `FloatTests`.

-- Repeating-decimal division renders at 34 significant digits, round-half-up.
-- `2.0 / 3.0 = 0.666…667` (34 sig digits). This is the apd-context subset that is
-- now reachable; see compat-assumptions for the rounding-tie boundary.
theorem eval_div_repeating :
    (evalDiv (.prim (mkFloatText "2.0")) (.prim (mkFloatText "3.0"))
      == .prim (mkFloatText "0.6666666666666666666666666666666667")) = true := by
  native_decide

-- Repeating division with an integer part rounds at 34 sig digits, not 34 frac
-- digits: `10.0 / 3.0 = 3.33…3` (33 frac digits). Pins the significant-digit rule
-- that the prior fixed-fraction int divider got wrong for quotients ≥ 1.
theorem eval_div_repeating_int_part :
    (evalDiv (.prim (mkFloatText "10.0")) (.prim (mkFloatText "3.0"))
      == .prim (mkFloatText "3.333333333333333333333333333333333")) = true := by
  native_decide

-- Rounding carries past 9s: `100.0 / 7.0 = 14.28…29`, last digit rounded up.
theorem eval_div_repeating_round_up :
    (evalDiv (.prim (mkFloatText "100.0")) (.prim (mkFloatText "7.0"))
      == .prim (mkFloatText "14.28571428571428571428571428571429")) = true := by
  native_decide

-- High-fuel pin: a full-34-significant-digit repeating quotient with no leading
-- zeros. `1.0 / 7.0 = 0.142857…429` emits the maximum significant digits plus the
-- guard, so the `divisionDigitsFuel` ceiling must not be exhausted before the
-- over-budget exit. Reduces under `native_decide` ⇒ the bound is sufficient.
theorem eval_div_repeating_full_sig :
    (evalDiv (.prim (mkFloatText "1.0")) (.prim (mkFloatText "7.0"))
      == .prim (mkFloatText "0.1428571428571428571428571428571429")) = true := by
  native_decide

-- High-fuel pin exercising the leading-zero slack in the fuel bound: `1.0 / 700.0
-- = 0.001428…429` has two leading fractional zeros (non-emitting iterations) on
-- top of the 34 significant digits, so it leans on the `+ <den digit count>` term
-- of `divisionDigitsFuel`.
theorem eval_div_repeating_leading_zeros :
    (evalDiv (.prim (mkFloatText "1.0")) (.prim (mkFloatText "700.0"))
      == .prim (mkFloatText "0.001428571428571428571428571428571429")) = true := by
  native_decide

-- E#4 — arithmetic operator domain. The CUE spec closes `+ - * /` over int/decimal, and
-- additionally `+`/`*` over strings and bytes. A CONCRETE operand outside an op's domain is a
-- TYPE ERROR (`nonArithmeticOperand`), the same class as `1 + "x"`; an INCOMPLETE operand keeps
-- the binary DEFERRED (`.binary`) since it may still resolve to a number. These pin the unit
-- behavior of `evalAdd`/`evalSub`/`evalMul`/`evalDiv` directly, independent of display.

-- A concrete list operand bottoms `+` (was a held residual; cue: superseded-by-list.Concat).
theorem eval_add_list_is_type_error :
    (evalAdd (.list [.prim (.int 1)]) (.list [.prim (.int 2)])
      == .bottomWith [.nonArithmeticOperand .add .list]) = true := by
  native_decide

-- `-` over a list operand bottoms (cue: `cannot use [..] as type number`).
theorem eval_sub_list_is_type_error :
    (evalSub (.list [.prim (.int 1)]) (.prim (.int 3))
      == .bottomWith [.nonArithmeticOperand .sub .list]) = true := by
  native_decide

-- `*` over a list operand bottoms in either order (cue: superseded-by-list.Repeat).
theorem eval_mul_list_is_type_error :
    (evalMul (.prim (.int 3)) (.list [.prim (.int 1), .prim (.int 2)])
      == .bottomWith [.nonArithmeticOperand .mul .list]) = true := by
  native_decide

-- `/` over a list operand bottoms.
theorem eval_div_list_is_type_error :
    (evalDiv (.list [.prim (.int 1)]) (.prim (.int 3))
      == .bottomWith [.nonArithmeticOperand .div .list]) = true := by
  native_decide

-- A concrete (no-pattern) struct operand bottoms `+` with the `.struct` operand type.
theorem eval_add_struct_is_type_error :
    (evalAdd (mkStruct [⟨"a", .regular, .prim (.int 1), false⟩] .regularOpen none [])
        (mkStruct [⟨"b", .regular, .prim (.int 2), false⟩] .regularOpen none [])
      == .bottomWith [.nonArithmeticOperand .add .struct]) = true := by
  native_decide

-- A `.listTail` (open list) is also a concrete non-arithmetic operand → type error.
theorem eval_add_list_tail_is_type_error :
    (evalAdd (.listTail [.prim (.int 1)] (.kind .int)) (.prim (.int 2))
      == .bottomWith [.nonArithmeticOperand .add .list]) = true := by
  native_decide

-- Per-op asymmetry: `+` over two strings is concat (NOT a type error).
theorem eval_add_strings_concats :
    evalAdd (.prim (.string "a")) (.prim (.string "b")) = .prim (.string "ab") := by
  rfl

-- Per-op asymmetry: `-` over strings IS a type error (string ∉ `-` domain). The wrong-typed
-- prim pair routes through the existing decimal path to a plain `.bottom` (cue errors too).
theorem eval_sub_strings_is_bottom :
    evalSub (.prim (.string "a")) (.prim (.string "b")) = .bottom := by
  rfl

-- `*` over (string, int) is REPETITION (cue, superseding strings.Repeat): `"ab" * 2 = "abab"`.
theorem eval_mul_string_int_repeats :
    evalMul (.prim (.string "ab")) (.prim (.int 2)) = .prim (.string "abab") := by
  rfl

-- Repetition is order-agnostic: `2 * "ab" = "abab"`.
theorem eval_mul_int_string_repeats :
    evalMul (.prim (.int 2)) (.prim (.string "ab")) = .prim (.string "abab") := by
  rfl

-- `*` over (bytes, int) repeats the bytes: `'ab' * 2 = 'abab'`.
theorem eval_mul_bytes_int_repeats :
    evalMul (.prim (.bytes (textBytes "ab"))) (.prim (.int 2)) = .prim (.bytes (textBytes "abab")) := by
  rfl

-- A zero count yields the empty value (not an error).
theorem eval_mul_string_zero_is_empty :
    evalMul (.prim (.string "ab")) (.prim (.int 0)) = .prim (.string "") := by
  rfl

-- A negative repetition count is a type error (cue: cannot convert negative number to uint64).
theorem eval_mul_string_negative_count_is_error :
    evalMul (.prim (.string "ab")) (.prim (.int (-1))) = .bottomWith [.negativeRepeatCount (-1)] := by
  rfl

-- CRITICAL regression pin: a concrete list paired with an INCOMPLETE operand (abstract `int`
-- kind) DEFERS — it does NOT bottom, because the kind may still resolve to a number (cue holds
-- `[1] + x` while `x: int`). The concrete-nonarith side alone must not force a type error.
theorem eval_add_list_incomplete_partner_defers :
    evalAdd (.list [.prim (.int 1)]) (.kind .int) = .binary .add (.list [.prim (.int 1)]) (.kind .int) := by
  rfl

-- Symmetric: incomplete LEFT × concrete list RIGHT also defers.
theorem eval_mul_incomplete_partner_list_defers :
    evalMul (.kind .int) (.list [.prim (.int 1)]) = .binary .mul (.kind .int) (.list [.prim (.int 1)]) := by
  rfl

-- A bound-constraint operand is incomplete → arithmetic defers (it may concretize to a number).
theorem eval_add_bound_operand_defers :
    evalAdd (.boundConstraint (intDecimal 0) .gt .number) (.prim (.int 1))
      = .binary .add (.boundConstraint (intDecimal 0) .gt .number) (.prim (.int 1)) := by
  rfl

-- An unresolved ref operand is incomplete → defers (the pre-fix baseline, must stay).
theorem eval_add_ref_operand_defers :
    evalAdd (.refId ⟨0, 0⟩) (.prim (.int 1)) = .binary .add (.refId ⟨0, 0⟩) (.prim (.int 1)) := by
  rfl

-- ### Comparison / boolean / unary scalar-op pins (EvalOps)
--
-- Direct unit pins for `evalEq`/`evalNe`, the ordering ops (`evalPrimitiveOrdering` via
-- `evalBinary .lt/.le/.gt/.ge`), the boolean ops, and unary negation/not — the carve-set
-- functions that previously had only end-to-end fixture coverage. They fix the edge
-- behavior (incomparable-kind comparison, bool ordering, unary on non-numeric) at the
-- function level, independent of display.

-- `<` over two ints decides numerically.
theorem eval_lt_int_true :
    (evalBinary .lt (.prim (.int 1)) (.prim (.int 2)) == .prim (.bool true)) = true := by
  native_decide

-- `<` is lexicographic over strings.
theorem eval_lt_string_true :
    (evalBinary .lt (.prim (.string "a")) (.prim (.string "b")) == .prim (.bool true)) = true := by
  native_decide

-- `<=` is reflexive at equality.
theorem eval_le_int_equal_true :
    (evalBinary .le (.prim (.int 2)) (.prim (.int 2)) == .prim (.bool true)) = true := by
  native_decide

-- `>` over ints decides numerically.
theorem eval_gt_int_true :
    (evalBinary .gt (.prim (.int 5)) (.prim (.int 2)) == .prim (.bool true)) = true := by
  native_decide

-- `>=` over ints decides numerically.
theorem eval_ge_int_true :
    (evalBinary .ge (.prim (.int 5)) (.prim (.int 5)) == .prim (.bool true)) = true := by
  native_decide

-- Comparison over INCOMPARABLE kinds (int vs string) bottoms — cue: `invalid operands …
-- to '<'`. The `prim,prim` arm finds no decimal compare and no same-string match ⇒ `.bottom`.
theorem eval_lt_incomparable_kinds_is_bottom :
    (evalBinary .lt (.prim (.int 1)) (.prim (.string "a")) == .bottom) = true := by
  native_decide

-- `bool` is NOT ordered: `true < false` bottoms (cue: `invalid operands … (type bool and bool)`).
theorem eval_lt_bool_unordered_is_bottom :
    (evalBinary .lt (.prim (.bool true)) (.prim (.bool false)) == .bottom) = true := by
  native_decide

-- An incomplete operand keeps an ordering comparison DEFERRED (residual `.binary`).
theorem eval_lt_incomplete_defers :
    (evalBinary .lt (.kind .int) (.prim (.int 2))
      == .binary .lt (.kind .int) (.prim (.int 2))) = true := by
  native_decide

-- `==` over distinct ints is `false`.
theorem eval_eq_int_distinct_false :
    (evalEq (.prim (.int 1)) (.prim (.int 2)) == .prim (.bool false)) = true := by
  native_decide

-- `!=` is the negation of `==`.
theorem eval_ne_int_distinct_true :
    (evalNe (.prim (.int 1)) (.prim (.int 2)) == .prim (.bool true)) = true := by
  native_decide

-- AUDIT (EvalOps gap): `==` across DISTINCT KINDS (`1 == "1"`) is `false`, NOT bottom — cue
-- treats `==`/`!=` as total over concrete prims (it falls through `evalDecimalCompare?` to the
-- structural `left == right`, which differs across kinds). Oracle: cue `1 == "1"` ⇒ `false`.
theorem eval_eq_cross_kind_int_string_false :
    (evalEq (.prim (.int 1)) (.prim (.string "1")) == .prim (.bool false)) = true := by
  native_decide

-- AUDIT (EvalOps gap): `!=` across distinct kinds is `true` (the `==` complement).
theorem eval_ne_cross_kind_int_string_true :
    (evalNe (.prim (.int 1)) (.prim (.string "1")) == .prim (.bool true)) = true := by
  native_decide

-- AUDIT (EvalOps gap): string `<=` is `!stringsLt right left` — pins the REVERSED-operand lambda
-- in the `.le` arm (`"b" <= "a"` ⇒ `false`). Oracle: cue `"b" <= "a"` ⇒ `false`.
theorem eval_le_string_reverse_false :
    (evalBinary .le (.prim (.string "b")) (.prim (.string "a")) == .prim (.bool false)) = true := by
  native_decide

-- AUDIT (EvalOps gap): string `>=` is `!stringsLt left right` — pins the `.ge` string lambda
-- (`"b" >= "a"` ⇒ `true`). Oracle: cue `"b" >= "a"` ⇒ `true`.
theorem eval_ge_string_reverse_true :
    (evalBinary .ge (.prim (.string "b")) (.prim (.string "a")) == .prim (.bool true)) = true := by
  native_decide

-- AUDIT (EvalOps gap): string `<=` is reflexive at equality (`"a" <= "a"` ⇒ `true`) — the
-- `decimalEqValues || …` short-circuit has no string analog, so this exercises the
-- `!stringsLt right left` path at the boundary where both `stringsLt` directions are false.
theorem eval_le_string_reflexive_true :
    (evalBinary .le (.prim (.string "a")) (.prim (.string "a")) == .prim (.bool true)) = true := by
  native_decide

-- `&&` over bools decides directly.
theorem eval_bool_and :
    (evalBinary .boolAnd (.prim (.bool true)) (.prim (.bool false)) == .prim (.bool false)) = true := by
  native_decide

-- `||` over bools decides directly.
theorem eval_bool_or :
    (evalBinary .boolOr (.prim (.bool false)) (.prim (.bool true)) == .prim (.bool true)) = true := by
  native_decide

-- `&&` over a NON-bool prim bottoms (cue: `cannot use … as bool`).
theorem eval_bool_and_non_bool_is_bottom :
    (evalBinary .boolAnd (.prim (.int 1)) (.prim (.bool true)) == .bottom) = true := by
  native_decide

-- Unary `!` negates a bool.
theorem eval_unary_not_bool :
    (evalUnary .boolNot (.prim (.bool true)) == .prim (.bool false)) = true := by
  native_decide

-- Unary `!` on a non-bool bottoms (cue: `invalid operation !3`).
theorem eval_unary_not_non_bool_is_bottom :
    (evalUnary .boolNot (.prim (.int 3)) == .bottom) = true := by
  native_decide

-- Unary `-` negates an int.
theorem eval_unary_neg_int :
    (evalUnary .numNeg (.prim (.int 5)) == .prim (.int (-5))) = true := by
  native_decide

-- Unary `-` on a non-numeric operand bottoms (cue: `invalid operation -"a"`).
theorem eval_unary_neg_non_numeric_is_bottom :
    (evalUnary .numNeg (.prim (.string "x")) == .bottom) = true := by
  native_decide

-- Unary `-` on an incomplete operand keeps the unary DEFERRED (residual `.unary`).
theorem eval_unary_neg_incomplete_defers :
    (evalUnary .numNeg (.kind .int) == .unary .numNeg (.kind .int)) = true := by
  native_decide

-- AUD-B3 residual-preservation guards. The `evalBoolBinary`/`evalBoolNot`/`evalNumPos`/
-- `evalNumNeg` (+ `evalPrimitiveOrdering`/`evalRegexMatch`) catch-alls were replaced with an
-- ENUMERATED `classifyScalarOperand` dispatch; these pins fix EXACTLY which constructors keep
-- producing the residual `.binary`/`.unary` so the enumeration cannot silently reroute one.

-- `&&` with an abstract operand DEFERS (residual `.binary`), it does not bottom.
theorem eval_bool_and_incomplete_defers :
    (evalBinary .boolAnd (.kind .bool) (.prim (.bool true))
      == .binary .boolAnd (.kind .bool) (.prim (.bool true))) = true := by
  native_decide

-- A `.ref` operand (a distinct abstract ctor) also defers — the enumeration routes every
-- non-prim/non-bottom shape to the residual, not just `.kind`.
theorem eval_bool_or_ref_defers :
    (evalBinary .boolOr (.ref "x") (.prim (.bool false))
      == .binary .boolOr (.ref "x") (.prim (.bool false))) = true := by
  native_decide

-- A `.bottom` operand BEATS a residual partner: `⊥ && <abstract>` is `⊥`, not deferred.
theorem eval_bool_and_bottom_beats_residual :
    (evalBinary .boolAnd .bottom (.kind .bool) == .bottom) = true := by
  native_decide

-- A `.bottomWith` on the RIGHT (with an abstract left) propagates its reasons, not a residual.
theorem eval_bool_and_right_bottomwith_propagates :
    (evalBinary .boolAnd (.kind .bool) (.bottomWith [.divisionByZero])
      == .bottomWith [.divisionByZero]) = true := by
  native_decide

-- Unary `!` on an abstract operand keeps the unary DEFERRED (residual `.unary`).
theorem eval_unary_not_incomplete_defers :
    (evalUnary .boolNot (.kind .bool) == .unary .boolNot (.kind .bool)) = true := by
  native_decide

-- Unary `+` is identity on int and float, bottoms a non-numeric prim, and defers an abstract.
theorem eval_unary_pos_int :
    (evalUnary .numPos (.prim (.int 5)) == .prim (.int 5)) = true := by
  native_decide

theorem eval_unary_pos_float :
    (evalUnary .numPos (.prim (mkFloatText "1.5")) == .prim (mkFloatText "1.5")) = true := by
  native_decide

theorem eval_unary_pos_non_numeric_is_bottom :
    (evalUnary .numPos (.prim (.string "x")) == .bottom) = true := by
  native_decide

theorem eval_unary_pos_incomplete_defers :
    (evalUnary .numPos (.kind .int) == .unary .numPos (.kind .int)) = true := by
  native_decide

-- Unary `-` negates a float via `negateFloatText`.
theorem eval_unary_neg_float :
    (evalUnary .numNeg (.prim (mkFloatText "1.5")) == .prim (mkFloatText "-1.5")) = true := by
  native_decide

-- Regex match on an abstract operand DEFERS (residual `.binary`), it does not bottom.
theorem eval_regex_match_incomplete_defers :
    (evalBinary .regexMatch (.kind .string) (.prim (.string "^a"))
      == .binary .regexMatch (.kind .string) (.prim (.string "^a"))) = true := by
  native_decide

-- Regex match over two NON-string prims bottoms (both concrete, wrong type).
theorem eval_regex_match_non_string_is_bottom :
    (evalBinary .regexMatch (.prim (.int 1)) (.prim (.int 2)) == .bottom) = true := by
  native_decide

-- Slice 2c.1: an in-struct sibling reference (`b: a`) sees the FULLY-MERGED value of a
-- duplicated label, not the first conjunct. `{a: int, b: a, a: 1}` canonicalizes the two
-- `a` slots into `.conj [int, 1]` at slot 0, so `b` evaluates to `1`, and the duplicate
-- collapses to a single `a` field.
theorem eval_in_struct_sibling_merge :
    (resolveAndEval
      (mkStruct [⟨"a", .regular, .kind .int, false⟩, ⟨"b", .regular, .ref "a", false⟩, ⟨"a", .regular, .prim (.int 1), false⟩] .regularOpen none [])
      == mkStruct [⟨"a", .regular, .prim (.int 1), false⟩, ⟨"b", .regular, .prim (.int 1), false⟩] .regularOpen none []) = true := by
  native_decide

-- A duplicate-label conflict bottoms both the label and any sibling referencing it:
-- `{a: 1, b: a, a: 2}` -> `a` and `b` both bottom.
theorem eval_in_struct_sibling_conflict :
    (resolveAndEval
      (mkStruct [⟨"a", .regular, .prim (.int 1), false⟩, ⟨"b", .regular, .ref "a", false⟩, ⟨"a", .regular, .prim (.int 2), false⟩] .regularOpen none [])
      == mkStruct [
          ⟨"a", .regular, .bottomWith [.primitiveConflict (.int 1) (.int 2)], false⟩,
          ⟨"b", .regular, .bottomWith [.primitiveConflict (.int 1) (.int 2)], false⟩
        ] .regularOpen none []) = true := by
  native_decide

-- Canonicalization is visible through nested sub-structs: `c.e` references the outer `a`,
-- seeing the merged `int & 1 = 1`.
theorem eval_nested_sibling_merge :
    (resolveAndEval
      (mkStruct [
          ⟨"a", .regular, .kind .int, false⟩,
          ⟨"c", .regular, mkStruct [⟨"e", .regular, .ref "a", false⟩] .regularOpen none [], false⟩,
          ⟨"a", .regular, .prim (.int 1), false⟩
        ] .regularOpen none [])
      == mkStruct [
          ⟨"a", .regular, .prim (.int 1), false⟩,
          ⟨"c", .regular, mkStruct [⟨"e", .regular, .prim (.int 1), false⟩] .regularOpen none [], false⟩
        ] .regularOpen none []) = true := by
  native_decide

-- A self-referential merged slot must not loop: `{a: a, a: 1}` canonicalizes to
-- `.conj [a, 1]` at slot 0; the self-ref hits the `slotVisited` -> `.top` guard, so the
-- meet collapses to `1` rather than diverging.
theorem eval_merged_self_ref_cycle :
    (resolveAndEval
      (mkStruct [⟨"a", .regular, .ref "a", false⟩, ⟨"a", .regular, .prim (.int 1), false⟩] .regularOpen none [])
      == mkStruct [⟨"a", .regular, .prim (.int 1), false⟩] .regularOpen none []) = true := by
  native_decide

-- 2c.2: struct conjunction through a referenced binding. `d & {a: 1}` merges the conjuncts'
-- declarations into one frame before evaluating bodies, so `d.b: a` sees the narrowed `a`
-- and `y.b` resolves to `1` (not `int`).
theorem eval_meet_lazy_sibling_ref :
    (resolveAndEval
      (mkStruct [
          ⟨"d", .regular, mkStruct [⟨"a", .regular, .kind .int, false⟩, ⟨"b", .regular, .ref "a", false⟩] .regularOpen none [], false⟩,
          ⟨"y", .regular, .conj [.ref "d", mkStruct [⟨"a", .regular, .prim (.int 1), false⟩] .regularOpen none []], false⟩
        ] .regularOpen none [])
      == mkStruct [
          ⟨"d", .regular, mkStruct [⟨"a", .regular, .kind .int, false⟩, ⟨"b", .regular, .kind .int, false⟩] .regularOpen none [], false⟩,
          ⟨"y", .regular,
            mkStruct [⟨"a", .regular, .prim (.int 1), false⟩, ⟨"b", .regular, .prim (.int 1), false⟩] .regularOpen none [], false⟩
        ] .regularOpen none []) = true := by
  native_decide

-- 2c.2: literal struct conjunction (no reference operand). `{a: int, b: a} & {a: 1}` → `b: 1`
-- via the merged frame.
theorem eval_meet_lazy_literal :
    (resolveAndEval
      (mkStruct [
          ⟨"x", .regular,
            .conj
              [
                mkStruct [⟨"a", .regular, .kind .int, false⟩, ⟨"b", .regular, .ref "a", false⟩] .regularOpen none [],
                mkStruct [⟨"a", .regular, .prim (.int 1), false⟩] .regularOpen none []
              ], false⟩
        ] .regularOpen none [])
      == mkStruct [
          ⟨"x", .regular,
            mkStruct [⟨"a", .regular, .prim (.int 1), false⟩, ⟨"b", .regular, .prim (.int 1), false⟩] .regularOpen none [], false⟩
        ] .regularOpen none []) = true := by
  native_decide

-- 2c.2: a chained sibling reference within one conjunct, narrowed across the meet —
-- `{a: int, b: a, c: b} & {a: 1}` resolves `a`, `b`, `c` all to `1`.
theorem eval_meet_lazy_chain :
    (resolveAndEval
      (mkStruct [
          ⟨"x", .regular,
            .conj
              [
                mkStruct [
                    ⟨"a", .regular, .kind .int, false⟩,
                    ⟨"b", .regular, .ref "a", false⟩,
                    ⟨"c", .regular, .ref "b", false⟩
                  ] .regularOpen none [],
                mkStruct [⟨"a", .regular, .prim (.int 1), false⟩] .regularOpen none []
              ], false⟩
        ] .regularOpen none [])
      == mkStruct [
          ⟨"x", .regular,
            mkStruct [
                ⟨"a", .regular, .prim (.int 1), false⟩,
                ⟨"b", .regular, .prim (.int 1), false⟩,
                ⟨"c", .regular, .prim (.int 1), false⟩
              ] .regularOpen none [], false⟩
        ] .regularOpen none []) = true := by
  native_decide

-- 2c.2: nested sub-struct visibility through a *definition* meet. `out.val` references the
-- hidden `#x`; `#D & {#x: "hi"}` narrows `#x` and the nested `out.val` resolves to `"hi"`.
theorem eval_meet_lazy_hidden_def :
    (resolveAndEval
      (mkStruct [
          ⟨"#D", .definition,
            mkStruct [
                ⟨"#x", .definition, .kind .string, false⟩,
                ⟨"out", .regular, mkStruct [⟨"val", .regular, .ref "#x", false⟩] .regularOpen none [], false⟩
              ] .regularOpen none [], false⟩,
          ⟨"y", .regular, .conj [.ref "#D", mkStruct [⟨"#x", .definition, .prim (.string "hi"), false⟩] .regularOpen none []], false⟩
        ] .regularOpen none [])
      -- SC-2: `#D`'s nested regular field `out` is a plain struct WITHIN the def body, so the
      -- closing walker closes its value (`.defClosed`) — recursively, like every nested
      -- def-body plain struct. The closure carries through the `#D & {…}` meet to `y.out`
      -- (monotone). Formatted output is unchanged (closedness is invisible in `eval` display).
      == mkStruct [
          ⟨"#D", .definition,
            mkStruct [
                ⟨"#x", .definition, .kind .string, false⟩,
                ⟨"out", .regular, mkStruct [⟨"val", .regular, .kind .string, false⟩] .defClosed none [], false⟩
              ] .defClosed none [], false⟩,
          ⟨"y", .regular,
            mkStruct [
                ⟨"#x", .definition, .prim (.string "hi"), false⟩,
                ⟨"out", .regular, mkStruct [⟨"val", .regular, .prim (.string "hi"), false⟩] .defClosed none [], false⟩
              ] .defClosed none [], false⟩
        ] .regularOpen none []) = true := by
  native_decide

-- ## Concrete struct/list equality (`evalEq` beyond `.prim`)

-- Order-INDEPENDENT struct equality: `{a:1,b:2} == {b:2,a:1}` ⇒ `true`.
theorem eval_eq_struct_reordered_true :
    (evalEq
        (mkStruct [⟨"a", .regular, .prim (.int 1), false⟩, ⟨"b", .regular, .prim (.int 2), false⟩] .regularOpen none [])
        (mkStruct [⟨"b", .regular, .prim (.int 2), false⟩, ⟨"a", .regular, .prim (.int 1), false⟩] .regularOpen none [])
      == .prim (.bool true)) = true := by
  native_decide

-- Quoted vs unquoted label is the SAME field (`quoted` bit ignored by `concreteEq`).
theorem eval_eq_struct_quoted_label_true :
    (evalEq
        (mkStruct [⟨"x", .regular, .prim (.int 1), true⟩] .regularOpen none [])
        (mkStruct [⟨"x", .regular, .prim (.int 1), false⟩] .regularOpen none [])
      == .prim (.bool true)) = true := by
  native_decide

-- Differing regular value ⇒ `false`.
theorem eval_eq_struct_unequal_false :
    (evalEq
        (mkStruct [⟨"x", .regular, .prim (.int 1), false⟩] .regularOpen none [])
        (mkStruct [⟨"x", .regular, .prim (.int 2), false⟩] .regularOpen none [])
      == .prim (.bool false)) = true := by
  native_decide

-- Differing output-field COUNT ⇒ `false`.
theorem eval_eq_struct_diff_size_false :
    (evalEq
        (mkStruct [⟨"x", .regular, .prim (.int 1), false⟩] .regularOpen none [])
        (mkStruct [⟨"x", .regular, .prim (.int 1), false⟩, ⟨"y", .regular, .prim (.int 2), false⟩] .regularOpen none [])
      == .prim (.bool false)) = true := by
  native_decide

-- Hidden field differs but is NON-output ⇒ still `true`.
theorem eval_eq_struct_hidden_ignored_true :
    (evalEq
        (mkStruct [⟨"x", .regular, .prim (.int 1), false⟩, ⟨"_h", .hidden, .prim (.int 9), false⟩] .regularOpen none [])
        (mkStruct [⟨"x", .regular, .prim (.int 1), false⟩] .regularOpen none [])
      == .prim (.bool true)) = true := by
  native_decide

-- Empty structs are equal.
theorem eval_eq_empty_structs_true :
    (evalEq (mkStruct [] .regularOpen none []) (mkStruct [] .regularOpen none []) == .prim (.bool true)) = true := by
  native_decide

-- Lists are ORDER-sensitive: `[1,2,3] == [3,2,1]` ⇒ `false`.
theorem eval_eq_list_reordered_false :
    (evalEq
        (.list [.prim (.int 1), .prim (.int 2), .prim (.int 3)])
        (.list [.prim (.int 3), .prim (.int 2), .prim (.int 1)])
      == .prim (.bool false)) = true := by
  native_decide

-- Equal lists ⇒ `true`; different length ⇒ `false`.
theorem eval_eq_list_equal_true :
    (evalEq (.list [.prim (.int 1), .prim (.int 2)]) (.list [.prim (.int 1), .prim (.int 2)]) == .prim (.bool true)) = true := by
  native_decide

theorem eval_eq_list_diff_length_false :
    (evalEq (.list [.prim (.int 1)]) (.list [.prim (.int 1), .prim (.int 2)]) == .prim (.bool false)) = true := by
  native_decide

-- Open-tailed list drops its tail: `[1, ...] == [1]` ⇒ `true`.
theorem eval_eq_open_list_vs_closed_true :
    (evalEq (.listTail [.prim (.int 1)] .top) (.list [.prim (.int 1)]) == .prim (.bool true)) = true := by
  native_decide

-- Struct vs list ⇒ `false` (cross-shape).
theorem eval_eq_struct_vs_list_false :
    (evalEq (mkStruct [⟨"x", .regular, .prim (.int 1), false⟩] .regularOpen none []) (.list [.prim (.int 1)])
      == .prim (.bool false)) = true := by
  native_decide

-- The over-eager DEFER guard: an INCOMPLETE (ref) field keeps `==` residual, NOT a bool —
-- even when another field already differs.
theorem eval_eq_incomplete_field_defers :
    (structEqConcrete?
        (mkStruct [⟨"a", .regular, .prim (.int 1), false⟩, ⟨"b", .regular, .ref "z", false⟩] .regularOpen none [])
        (mkStruct [⟨"a", .regular, .prim (.int 2), false⟩, ⟨"b", .regular, .ref "z", false⟩] .regularOpen none [])
      == none) = true := by
  native_decide

-- A REQUIRED field is not settled ⇒ DEFER.
theorem eval_eq_required_field_defers :
    (structEqConcrete?
        (mkStruct [⟨"x", .required, .prim (.int 1), false⟩] .regularOpen none [])
        (mkStruct [⟨"x", .regular, .prim (.int 1), false⟩] .regularOpen none [])
      == none) = true := by
  native_decide

-- `evalNe` inherits the negation for free.
theorem eval_ne_struct_reordered_false :
    (evalNe
        (mkStruct [⟨"a", .regular, .prim (.int 1), false⟩, ⟨"b", .regular, .prim (.int 2), false⟩] .regularOpen none [])
        (mkStruct [⟨"b", .regular, .prim (.int 2), false⟩, ⟨"a", .regular, .prim (.int 1), false⟩] .regularOpen none [])
      == .prim (.bool false)) = true := by
  native_decide

-- int-vs-float leaves compare BY VALUE, recursively inside containers (CUE spec: list/struct
-- `==` is recursive element equality; number `==` converts int to float). `cue` v0.16.1 returns
-- `false` for the container cases (STRUCT-EQ-LEAF-TYPESENSE) — a `cue` bug; Kue is spec-correct.
theorem eval_eq_scalar_int_float_true :
    (evalEq (.prim (.int 1)) (.prim (mkFloatText "1.0")) == .prim (.bool true)) = true := by
  native_decide

theorem eval_eq_list_int_vs_float_true :
    (evalEq (.list [.prim (.int 1)]) (.list [.prim (mkFloatText "1.0")]) == .prim (.bool true)) = true := by
  native_decide

theorem eval_eq_struct_int_vs_float_true :
    (evalEq
        (mkStruct [⟨"a", .regular, .prim (.int 1), false⟩] .regularOpen none [])
        (mkStruct [⟨"a", .regular, .prim (mkFloatText "1.0"), false⟩] .regularOpen none [])
      == .prim (.bool true)) = true := by
  native_decide

-- Depth: int-vs-float nested two containers deep still compares by value.
theorem eval_eq_nested_list_int_vs_float_true :
    (evalEq (.list [.list [.prim (.int 1)]]) (.list [.list [.prim (mkFloatText "1.0")]])
      == .prim (.bool true)) = true := by
  native_decide

-- A value-UNEQUAL int-vs-float leaf inside a container is `false` (not merely type-blind).
theorem eval_eq_list_int_vs_float_unequal_false :
    (evalEq (.list [.prim (.int 1)]) (.list [.prim (mkFloatText "2.0")]) == .prim (.bool false)) = true := by
  native_decide

-- `evalNe` inherits the negation: `[1] != [1.0]` ⇒ `false`.
theorem eval_ne_list_int_vs_float_false :
    (evalNe (.list [.prim (.int 1)]) (.list [.prim (mkFloatText "1.0")]) == .prim (.bool false)) = true := by
  native_decide

-- COVERAGE TRIPWIRE (test-health). Anchors the LAST theorem of every section; a swallowed
-- section turns its anchor into an unknown identifier and `#check` fails to elaborate.
#check @eval_add_ref_operand_defers                           -- arithmetic operand deferral
#check @eval_unary_neg_incomplete_defers                      -- comparison / unary ops
#check @eval_meet_lazy_hidden_def                             -- lazy sibling meet
#check @eval_ne_list_int_vs_float_false                       -- concrete struct/list equality

end Kue
