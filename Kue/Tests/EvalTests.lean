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
    manifest (.ref "#A") = .error (.incomplete (.ref "#A")) := by
  rfl

theorem eval_regular_field_reference_to_definition :
    (evalStructRefs
      (resolveStructRefs
        (mkStruct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .ref "#A"⟩] .regularOpen none []))
      == mkStruct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .kind .int⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_missing_reference_bottom :
    (evalStructRefs
      (mkStruct [⟨"x", .regular, .ref "#Missing"⟩] .regularOpen none [])
      == mkStruct [⟨"x", .regular, .bottomWith [.unresolvedReference "#Missing"]⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_resolved_reference_by_binding_id :
    (evalStructRefs
      (mkStruct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .refId ⟨0, 0⟩⟩] .regularOpen none [])
      == mkStruct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .kind .int⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_static_field_selector :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"base", .regular, mkStruct [⟨"inner", .regular, .prim (.int 4)⟩] .regularOpen none []⟩,
            ⟨"x", .regular, .selector (.ref "base") "inner"⟩
          ] .regularOpen none []))
      = "base: {inner: 4}\nx: 4" := by
  native_decide

theorem eval_static_list_index :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"xs", .regular, .list [.prim (.int 10), .prim (.int 20)]⟩,
            ⟨"x", .regular, .index (.ref "xs") (.prim (.int 1))⟩
          ] .regularOpen none []))
      = "xs: [10, 20]\nx: 20" := by
  native_decide

theorem eval_static_string_field_index :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"base", .regular, mkStruct [⟨"inner", .regular, .prim (.int 4)⟩] .regularOpen none []⟩,
            ⟨"x", .regular, .index (.ref "base") (.prim (.string "inner"))⟩
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
            ⟨"base", .regular, .prim (.string "v")⟩,
            ⟨"components", .regular,
              mkStruct [
                  ⟨"a", .regular, mkStruct [⟨"who", .regular, .ref "base"⟩] .regularOpen none []⟩,
                  ⟨"b", .regular, mkStruct [⟨"who", .regular, .ref "base"⟩] .regularOpen none []⟩
                ] .regularOpen none []⟩,
            ⟨"aWho", .regular, .selector (.selector (.ref "components") "a") "who"⟩,
            ⟨"bWho", .regular, .selector (.selector (.ref "components") "b") "who"⟩
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
            ⟨"x", .regular, .conj [.ref "x", mkStruct [⟨"p", .regular, .prim (.int 1)⟩] .regularOpen none []]⟩,
            ⟨"p1", .regular, .selector (.ref "x") "p"⟩,
            ⟨"p2", .regular, .selector (.ref "x") "p"⟩
          ] .regularOpen none []))
      = "x: {p: 1}\np1: 1\np2: 1" := by
  native_decide


/-! ### structural-cycle detection (D#2a).

The CUE spec mandates dynamic detection of STRUCTURAL cycles — a definition (or regular field)
whose body re-enters the SAME struct through a struct layer (`#L: {next: #L}`) — as an error,
DISTINCT from a bare REFERENCE cycle (`x: x` → `_`). Detection is an in-progress struct-body
stack on the `.refId` eval path (`structStack`): a struct body re-entered while still on the
stack bottoms with `.structuralCycle` rather than unrolling fuel-deep to garbage. These pins
cover the spec's oracle table (cue v0.16.1): error cases, the reference-cycle control, the
finite-deep control, and the recursive-list idiom that must NOT false-positive. -/

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


/-! ### terminating-disjunct (D#2b).

The spec's "a node is valid if any of its conjuncts is not cyclic" rule: a recursive def in a
disjunction (`#List | *null`) terminates by taking the non-cyclic arm once the cyclic arm bottoms
with `.structuralCycle` (D#2a). The cyclic arm is pruned by `liveAlternatives`/`resolveDisjDefault?`
(value resolution) — already the existing algebra; D#2b's code change is in `normalizeEvaluatedDisj`,
which now applies `liveAlternatives` (flatten + drop-bottom + dedup, SC-3) so the bottomed arm never
lingers in the EVAL value either. The pruning is value-SOUND: a `containsBottom` arm is dead in every
meet, so removing it changes no value. The surviving default is NOT collapsed into the value (a later
`a & 2` must still see a non-default arm) — default selection stays a manifest/force projection.

These pin the VALUE verdict (export, byte-identical to cue where the verdict agrees); Kue's eval
DISPLAY keeps the full `{…} | *null` per its established full-disjunction-with-default convention
(see `disjunctions/default_disjunction.expected`), which intentionally diverges from cue's
display-collapse — a recorded spec-gap, not a value bug. The export fixtures
`testdata/export/terminating_disj_*` carry the same verdicts as committed pairs. -/

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

-- A#6 fuel-cap probe: a WIDE cyclic body (5 concrete fields) does NOT push the `.structuralCycle`
-- bottom past `containsBottom`'s 100-level cap — detection (D#2a) fires at recursion depth ~2 so the
-- bottom is always shallow, and `liveAlternatives` sees it. The cap needed NO change. cue-exact.
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


/-! ### scalar struct-embedding collapse pins (root prerequisite for list comprehensions).

A struct with no output field embedding a non-struct value IS that value (CUE: `{5}`→`5`). cue
v0.16.1-exact; collapse only when LOSSLESS (no output field). -/

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

/-! ### empty/decl-free struct ∩ scalar is a CONFLICT, not a collapse (audit #10 V1).

The `{5}`→`5` collapse lives in embed-eval (`meetEmbeddingsWithFuel`), where the host is KNOWN
to embed a scalar — NOT in `meet`, which cannot tell an empty struct `{}` from `{5}`'s residual
`mkStruct []`. A genuine struct ∩ scalar must conflict (cue v0.16.1: mismatched types). Before the
fix these all wrongly collapsed to the scalar. -/

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

theorem eval_additive_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"sum", .regular, .binary .add (.prim (.int 1)) (.prim (.int 2))⟩,
            ⟨"diff", .regular, .binary .sub (.prim (.int 5)) (.prim (.int 3))⟩,
            ⟨"cat", .regular, .binary .add (.prim (.string "a")) (.prim (.string "b"))⟩,
            ⟨"bytes", .regular, .binary .add (.prim (.bytes "ab")) (.prim (.bytes "cd"))⟩
          ] .regularOpen none []))
      = "sum: 3\ndiff: 2\ncat: \"ab\"\nbytes: 'abcd'" := by
  native_decide

theorem eval_float_additive_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"floatSum", .regular, .binary .add (.prim (.float "1.5")) (.prim (.float "2.25"))⟩,
            ⟨"intFloat", .regular, .binary .add (.prim (.int 1)) (.prim (.float "2.5"))⟩,
            ⟨"floatSub", .regular, .binary .sub (.prim (.float "5.5")) (.prim (.int 2))⟩,
            ⟨"exp", .regular, .binary .add (.prim (.float "1e+3")) (.prim (.int 2))⟩,
            ⟨"small", .regular, .binary .add (.prim (.float "0.1")) (.prim (.float "0.2"))⟩
          ] .regularOpen none []))
      = "floatSum: 3.75\nintFloat: 3.5\nfloatSub: 3.5\nexp: 1002.0\nsmall: 0.3" := by
  native_decide

theorem eval_multiplication_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"mul", .regular, .binary .mul (.prim (.int 3)) (.prim (.int 4))⟩,
            ⟨
              "precedence",
              .regular,
              .binary .add (.prim (.int 1)) (.binary .mul (.prim (.int 2)) (.prim (.int 3)))
            ⟩
          ] .regularOpen none []))
      = "mul: 12\nprecedence: 7" := by
  native_decide

theorem eval_division_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"div", .regular, .binary .div (.prim (.int 5)) (.prim (.int 2))⟩,
            ⟨"whole", .regular, .binary .div (.prim (.int 6)) (.prim (.int 3))⟩,
            ⟨"third", .regular, .binary .div (.prim (.int 1)) (.prim (.int 3))⟩,
            ⟨"negative", .regular, .binary .div (.prim (.int (-5))) (.prim (.int 2))⟩
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
            ⟨"divValue", .regular, .binary .intDiv (.prim (.int (-7))) (.prim (.int 3))⟩,
            ⟨"modValue", .regular, .binary .intMod (.prim (.int (-7))) (.prim (.int 3))⟩,
            ⟨"quoValue", .regular, .binary .intQuo (.prim (.int (-7))) (.prim (.int 3))⟩,
            ⟨"remValue", .regular, .binary .intRem (.prim (.int (-7))) (.prim (.int 3))⟩
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
            ⟨"same", .regular, .binary .eq (.prim (.int 1)) (.prim (.int 1))⟩,
            ⟨"diff", .regular, .binary .ne (.prim (.int 1)) (.prim (.int 2))⟩,
            ⟨"text", .regular, .binary .eq (.prim (.string "a")) (.prim (.string "b"))⟩
          ] .regularOpen none []))
      = "same: true\ndiff: true\ntext: false" := by
  native_decide

theorem eval_ordering_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"lt", .regular, .binary .lt (.prim (.int 1)) (.prim (.int 2))⟩,
            ⟨"le", .regular, .binary .le (.prim (.int 2)) (.prim (.int 2))⟩,
            ⟨"gt", .regular, .binary .gt (.prim (.int 3)) (.prim (.int 2))⟩,
            ⟨"ge", .regular, .binary .ge (.prim (.int 3)) (.prim (.int 4))⟩,
            ⟨"slt", .regular, .binary .lt (.prim (.string "a")) (.prim (.string "b"))⟩
          ] .regularOpen none []))
      = "lt: true\nle: true\ngt: true\nge: false\nslt: true" := by
  native_decide

theorem eval_numeric_comparison_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"lt", .regular, .binary .lt (.prim (.float "1.5")) (.prim (.int 2))⟩,
            ⟨"le", .regular, .binary .le (.prim (.float "1.5")) (.prim (.float "1.50"))⟩,
            ⟨"gt", .regular, .binary .gt (.prim (.float "1e+3")) (.prim (.float "999.9"))⟩,
            ⟨"ge", .regular, .binary .ge (.prim (.float "1.0")) (.prim (.int 1))⟩,
            ⟨"eq", .regular, .binary .eq (.prim (.int 1)) (.prim (.float "1.0"))⟩,
            ⟨"ne", .regular, .binary .ne (.prim (.int 1)) (.prim (.float "1.0"))⟩
          ] .regularOpen none []))
      = "lt: true\nle: true\ngt: true\nge: true\neq: true\nne: false" := by
  native_decide

theorem eval_logical_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"andFalse", .regular, .binary .boolAnd (.prim (.bool true)) (.prim (.bool false))⟩,
            ⟨"orTrue", .regular, .binary .boolOr (.prim (.bool false)) (.prim (.bool true))⟩,
            ⟨
              "andCmp",
              .regular,
              .binary .boolAnd
                (.binary .lt (.prim (.int 1)) (.prim (.int 2)))
                (.binary .gt (.prim (.int 3)) (.prim (.int 2)))
            ⟩
          ] .regularOpen none []))
      = "andFalse: false\norTrue: true\nandCmp: true" := by
  native_decide

theorem eval_logical_not_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"notFalse", .regular, .unary .boolNot (.prim (.bool false))⟩,
            ⟨"notCmp", .regular, .unary .boolNot (.binary .lt (.prim (.int 1)) (.prim (.int 2)))⟩,
            ⟨"double", .regular, .unary .boolNot (.unary .boolNot (.prim (.bool true)))⟩
          ] .regularOpen none []))
      = "notFalse: true\nnotCmp: false\ndouble: true" := by
  native_decide

theorem eval_unary_numeric_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"negGroup", .regular, .unary .numNeg (.binary .add (.prim (.int 1)) (.prim (.int 2)))⟩,
            ⟨"posGroup", .regular, .unary .numPos (.binary .add (.prim (.int 1)) (.prim (.int 2)))⟩,
            ⟨"negFloat", .regular, .unary .numNeg (.prim (.float "1.5"))⟩
          ] .regularOpen none []))
      = "negGroup: -3\nposGroup: 3\nnegFloat: -1.5" := by
  native_decide

theorem eval_regex_match_expressions :
    formatTopLevel
      (resolveAndEval
        (mkStruct [
            ⟨"match", .regular, .binary .regexMatch (.prim (.string "abc")) (.prim (.string "^a"))⟩,
            ⟨"miss", .regular, .binary .regexMatch (.prim (.string "abc")) (.prim (.string "z"))⟩,
            ⟨"notMatch", .regular, .binary .regexNotMatch (.prim (.string "abc")) (.prim (.string "z"))⟩
          ] .regularOpen none []))
      = "match: true\nmiss: false\nnotMatch: true" := by
  native_decide

theorem eval_list_index_out_of_range_bottom :
    (evalStructRefs
      (resolveStructRefs
        (mkStruct [
            ⟨"xs", .regular, .list [.prim (.int 10)]⟩,
            ⟨"x", .regular, .index (.ref "xs") (.prim (.int 2))⟩
          ] .regularOpen none []))
      == mkStruct [
          ⟨"xs", .regular, .list [.prim (.int 10)]⟩,
          ⟨"x", .regular, .bottomWith [.indexOutOfRange 2 1]⟩
        ] .regularOpen none []) = true := by
  native_decide

theorem eval_missing_binding_id_bottom :
    (evalStructRefs
      (mkStruct [⟨"x", .regular, .refId ⟨0, 2⟩⟩] .regularOpen none [])
      == mkStruct [⟨"x", .regular, .bottomWith [.unresolvedBinding ⟨0, 2⟩]⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_binding_id_not_label_lookup :
    (evalStructRefs
      (mkStruct [⟨"#same", .definition, .kind .int⟩, ⟨"same", .regular, .kind .string⟩, ⟨"x", .regular, .refId ⟨0, 1⟩⟩] .regularOpen none [])
      == mkStruct [⟨"#same", .definition, .kind .int⟩, ⟨"same", .regular, .kind .string⟩, ⟨"x", .regular, .kind .string⟩] .regularOpen none []) = true := by
  native_decide

theorem resolve_direct_self_reference :
    (resolveStructRefs
      (mkStruct [⟨"x", .regular, .ref "x"⟩] .regularOpen none [])
      == mkStruct [⟨"x", .regular, .refId ⟨0, 0⟩⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_direct_self_reference_as_top :
    (evalStructRefs
      (resolveStructRefs (mkStruct [⟨"x", .regular, .ref "x"⟩] .regularOpen none []))
      == mkStruct [⟨"x", .regular, .top⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_mutual_reference_cycle_as_top :
    (evalStructRefs
      (resolveStructRefs (mkStruct [⟨"x", .regular, .ref "y"⟩, ⟨"y", .regular, .ref "x"⟩] .regularOpen none []))
      == mkStruct [⟨"x", .regular, .top⟩, ⟨"y", .regular, .top⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_three_reference_cycle_as_top :
    (evalStructRefs
      (resolveStructRefs
        (mkStruct [
            ⟨"x", .regular, .ref "y"⟩,
            ⟨"y", .regular, .ref "z"⟩,
            ⟨"z", .regular, .ref "x"⟩
          ] .regularOpen none []))
      == mkStruct [⟨"x", .regular, .top⟩, ⟨"y", .regular, .top⟩, ⟨"z", .regular, .top⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_direct_constrained_cycle_keeps_constraint :
    (evalStructRefs
      (resolveStructRefs (mkStruct [⟨"x", .regular, .conj [.ref "x", .boundConstraint (intDecimal 0) .ge .number]⟩] .regularOpen none []))
      == mkStruct [⟨"x", .regular, .boundConstraint (intDecimal 0) .ge .number⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_mutual_constrained_cycle_keeps_constraint :
    (evalStructRefs
      (resolveStructRefs
        (mkStruct [
            ⟨"a", .regular, .conj [.ref "b", .boundConstraint (intDecimal 0) .ge .number]⟩,
            ⟨"b", .regular, .ref "a"⟩
          ] .regularOpen none []))
      == mkStruct [⟨"a", .regular, .boundConstraint (intDecimal 0) .ge .number⟩, ⟨"b", .regular, .boundConstraint (intDecimal 0) .ge .number⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_non_cycle_reference_still_uses_target_value :
    (evalStructRefs
      (resolveStructRefs (mkStruct [⟨"x", .regular, .kind .int⟩, ⟨"y", .regular, .ref "x"⟩] .regularOpen none []))
      == mkStruct [⟨"x", .regular, .kind .int⟩, ⟨"y", .regular, .kind .int⟩] .regularOpen none []) = true := by
  native_decide

/-- A value alias (`Self={…}`) lowers to a `.thisStruct` let-binding; `Self.field`
    (a selector on the binding) resolves as a same-struct sibling reference. Pins the
    eval-level `thisStruct` mechanism directly. -/
theorem eval_value_alias_self_reference :
    (evalStructRefs
      (resolveStructRefs
        (mkStruct [
            ⟨"Self", .letBinding, .thisStruct⟩,
            ⟨"x", .regular, .prim (.int 5)⟩,
            ⟨"y", .regular, .selector (.ref "Self") "x"⟩
          ] .regularOpen none []))
      == mkStruct [
          ⟨"Self", .letBinding, .thisStruct⟩,
          ⟨"x", .regular, .prim (.int 5)⟩,
          ⟨"y", .regular, .prim (.int 5)⟩
        ] .regularOpen none []) = true := by
  native_decide

/-- A self-reference cycle through the alias is bounded to top, never diverging. -/
theorem eval_value_alias_cycle_bounds_to_top :
    (evalStructRefs
      (resolveStructRefs
        (mkStruct [
            ⟨"Self", .letBinding, .thisStruct⟩,
            ⟨"x", .regular, .selector (.ref "Self") "y"⟩,
            ⟨"y", .regular, .selector (.ref "Self") "x"⟩
          ] .regularOpen none []))
      == mkStruct [
          ⟨"Self", .letBinding, .thisStruct⟩,
          ⟨"x", .regular, .top⟩,
          ⟨"y", .regular, .top⟩
        ] .regularOpen none []) = true := by
  native_decide

theorem eval_regular_disjunction_uses_join_normalization :
    (evalStructRefs
      (mkStruct [⟨"x", .regular, .disj [(.regular, .boundConstraint (intDecimal 5) .ge .number), (.regular, .boundConstraint (intDecimal 0) .ge .number)]⟩] .regularOpen none [])
      == mkStruct [⟨"x", .regular, .boundConstraint (intDecimal 0) .ge .number⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_regular_field_reference_to_hidden :
    (evalStructRefs
      (resolveStructRefs (mkStruct [⟨"_secret", .hidden, .prim (.string "x")⟩, ⟨"value", .regular, .ref "_secret"⟩] .regularOpen none []))
      == mkStruct [⟨"_secret", .hidden, .prim (.string "x")⟩, ⟨"value", .regular, .prim (.string "x")⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_reference_inside_struct_tail :
    (evalStructRefs
      (resolveStructRefs (mkStruct [⟨"#A", .definition, .kind .int⟩] .defOpenViaTail (some (.ref "#A")) []))
      == mkStruct [⟨"#A", .definition, .kind .int⟩] .defOpenViaTail (some (.kind .int)) []) = true := by
  native_decide

theorem eval_reference_inside_nested_struct :
    (evalStructRefs
      (resolveStructRefs
        (mkStruct [⟨"x", .regular, mkStruct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .ref "#A"⟩] .regularOpen none []⟩] .regularOpen none []))
      == mkStruct [⟨"x", .regular, mkStruct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .kind .int⟩] .regularOpen none []⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_reference_inside_struct_pattern :
    (evalStructRefs
      (resolveStructRefs (mkStruct [⟨"#A", .definition, .kind .int⟩] .regularOpen none [((.kind .string), (.ref "#A"))]))
      == mkStruct [⟨"#A", .definition, .kind .int⟩] .regularOpen none [((.kind .string), (.kind .int))]) = true := by
  native_decide

theorem eval_struct_pattern_constrains_own_regular_field :
    (evalStructRefs
      (mkStruct [⟨"a", .regular, .prim (.string "bad")⟩] .regularOpen none [((.kind .string), (.kind .int))])
      == mkStruct [⟨"a", .regular, .bottomWith [.fieldConstraint "a"]⟩] .regularOpen none [((.kind .string), (.kind .int))]) = true := by
  native_decide

theorem string_kind_pattern_types_matching_field :
    (meet
      (mkStruct [] .regularOpen none [((.kind .string), (.kind .int))])
      (mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none [])
      == mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none [((.kind .string), (.kind .int))]) = true := by
  native_decide

theorem string_kind_pattern_rejects_type_mismatch :
    containsBottom
      (meet
        (mkStruct [] .regularOpen none [((.kind .string), (.kind .int))])
        (mkStruct [⟨"a", .regular, .prim (.string "x")⟩] .regularOpen none [])) = true := by
  native_decide

theorem eval_len_builtin_call_after_reference_resolution :
    (evalStructRefs
      (resolveStructRefs
        (mkStruct [⟨"x", .regular, .prim (.string "abc")⟩, ⟨"y", .regular, .builtinCall "len" [.ref "x"]⟩] .regularOpen none []))
      == mkStruct [⟨"x", .regular, .prim (.string "abc")⟩, ⟨"y", .regular, .prim (.int 3)⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_integer_builtin_call_after_reference_resolution :
    (evalStructRefs
      (resolveStructRefs
        (mkStruct [
            ⟨"n", .regular, .prim (.int (-7))⟩,
            ⟨"q", .regular, .builtinCall "div" [.ref "n", .prim (.int 3)]⟩
          ] .regularOpen none []))
      == mkStruct [⟨"n", .regular, .prim (.int (-7))⟩, ⟨"q", .regular, .prim (.int (-3))⟩] .regularOpen none []) = true := by
  native_decide

theorem eval_incomplete_builtin_call_remains_call :
    (evalStructRefs (mkStruct [⟨"x", .regular, .builtinCall "len" [.kind .string]⟩] .regularOpen none [])
      == mkStruct [⟨"x", .regular, .builtinCall "len" [.kind .string]⟩] .regularOpen none []) = true := by
  native_decide

/-- Slice C (`closure-default-in-guard`). A marked-default disjunction collapses to its
    default in a concrete context; a non-default disjunction does not. These pin
    `resolveDisjDefault?` directly. -/
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

/-- Slice F1. A unary op RESOLVES its disjunction operand to the default first, then applies
    the scalar op — it does NOT distribute. `!(bool | *false)` resolves to `false`, then
    `!false = true`. (Old slice-C behavior `bool | *true` was wrong: CUE forces the operand
    concrete; `!(bool | *false)` → `true`, oracle-verified.) -/
theorem distribute_not_over_default_disj :
    (distributeUnary .boolNot (.disj [(.default, .prim (.bool false)), (.regular, .kind .bool)])
      == .prim (.bool true)) = true := by
  native_decide

/-- Slice F1. `(int | *1) + 1` resolves the operand to `1`, then `1 + 1 = 2` — NOT
    `int+1 | *2`. CUE forces arithmetic operands concrete (`(int | *1) + 1 → 2`,
    oracle-verified), never a cross-product. -/
theorem distribute_add_over_default_disj :
    (distributeBinary .add (.disj [(.default, .prim (.int 1)), (.regular, .kind .int)]) (.prim (.int 1))
      == .prim (.int 2)) = true := by
  native_decide

/-! ### Slice F1 — default-mark algebra (audit #3 Violation)

    Three coupled facets, oracle-verified against `cue` v0.16.1:
    (1) unification ANDs default sets across the cross product (was OR);
    (2) `flattenAlternatives` honors two-level default precedence (a default-marked outer
        arm selects the inner disjunction's own default structure);
    (3) equal defaults dedup before the unique-default test.
    Arithmetic/comparison/unary ops resolve each operand to its default FIRST (no
    distribution / cross-product). -/

/-- F1 facet 1, the cross-product where `combineMark` lives. Unification ANDs the default
    sets: `(1|*2) & (1|2|3)` → the no-`*` right operand contributes its whole set as
    defaults, so only `*2 & 2` survives as a default → resolves to `2`. -/
theorem f1_unify_cross_and_marks_resolves :
    (resolveDisjDefault?
      (match meet
          (.disj [(.regular, .prim (.int 1)), (.default, .prim (.int 2))])
          (.disj [(.regular, .prim (.int 1)), (.regular, .prim (.int 2)), (.regular, .prim (.int 3))]) with
        | .disj alts => alts
        | _ => [])
      == some (.prim (.int 2))) = true := by
  native_decide

/-- F1 facet 1, NEGATIVE: two distinct defaults survive the cross → ambiguous (no resolve).
    `(*1|2) & (1|*2)` crosses to live `1|2` with no surviving default (`*1&1` regular,
    `2&*2` regular) → stays the disjunction `1 | 2`. -/
theorem f1_unify_cross_two_survivors_ambiguous :
    (meet
      (.disj [(.default, .prim (.int 1)), (.regular, .prim (.int 2))])
      (.disj [(.regular, .prim (.int 1)), (.default, .prim (.int 2))])
      == .disj [(.regular, .prim (.int 1)), (.regular, .prim (.int 2))]) = true := by
  native_decide

/-- F1. `combineMark` is AND: a result alternative is default iff BOTH inputs were. -/
theorem f1_combine_mark_is_and :
    (combineMark .default .default == .default
      && combineMark .default .regular == .regular
      && combineMark .regular .default == .regular
      && combineMark .regular .regular == .regular) = true := by
  native_decide

/-- F1 facet 3, equal-default dedup. `*1 | *1 | 2` → the two equal defaults collapse to one,
    so a unique default remains → resolves to `1`. The headline dedup case. -/
theorem f1_equal_defaults_dedup_resolves :
    (resolveDisjDefault?
      [(.default, .prim (.int 1)), (.default, .prim (.int 1)), (.regular, .prim (.int 2))]
      == some (.prim (.int 1))) = true := by
  native_decide

/-- F1 facet 3, NEGATIVE: DISTINCT defaults stay ambiguous (no spurious dedup). -/
theorem f1_distinct_defaults_stay_ambiguous :
    (resolveDisjDefault? [(.default, .prim (.int 1)), (.default, .prim (.int 2))]
      == none) = true := by
  native_decide

/-- F1 facet 2, two-level default precedence. `*d | 5` with `d : 1 | 2` (no inner default):
    the outer default selects `d`'s disjunction, promoting its own arms to defaults (no
    inner `*` → both `1` and `2` become defaults), while the regular outer `5` stays
    regular. The flatten thus carries the inner default structure rather than blanket- or
    OR-marking — the OLD bug produced `*1 | 2 | 5`. -/
theorem f1_nested_default_flatten_carries_inner :
    (liveAlternatives
      [(.default, .disj [(.regular, .prim (.int 1)), (.regular, .prim (.int 2))]),
       (.regular, .prim (.int 5))]
      == [(.default, .prim (.int 1)), (.default, .prim (.int 2)), (.regular, .prim (.int 5))]) = true := by
  native_decide

/-- F1 facet 2, precedence at resolve. With the `*d | 5` flatten above, the two carried
    defaults `1`, `2` are DISTINCT → `resolveDisjDefault?` shadows the regular `5` and stays
    ambiguous (matches cue `incomplete value 1 | 2`), neither resolving to `1` nor keeping
    `5`. -/
theorem f1_nested_default_flatten_resolve_ambiguous :
    (resolveDisjDefault?
      [(.default, .disj [(.regular, .prim (.int 1)), (.regular, .prim (.int 2))]),
       (.regular, .prim (.int 5))]
      == none) = true := by
  native_decide

/-- F1 facet 2. `*d | 5` with `d : *1 | 2` (inner default `*1`): only the inner default
    carries → unique default `1` → resolves to `1` (matches cue). -/
theorem f1_nested_inner_default_resolves :
    (resolveDisjDefault?
      [(.default, .disj [(.default, .prim (.int 1)), (.regular, .prim (.int 2))]),
       (.regular, .prim (.int 5))]
      == some (.prim (.int 1))) = true := by
  native_decide

/-- F1 facet 2, NEGATIVE: a REGULAR outer arm does NOT contribute its inner disjunction to
    the default set. `d | *5` with `d : 1 | 2` → `d`'s arms stay regular (shed), the lone
    default `5` wins → resolves to `5`. -/
theorem f1_nested_regular_outer_sheds :
    (resolveDisjDefault?
      [(.regular, .disj [(.regular, .prim (.int 1)), (.regular, .prim (.int 2))]),
       (.default, .prim (.int 5))]
      == some (.prim (.int 5))) = true := by
  native_decide

/-- F1, arithmetic resolve-first. `(1|*2) + (10|*20)` resolves each operand to its default
    (`2`, `20`) then adds → `22`. The headline arithmetic case; NOT a mark cross-product. -/
theorem f1_arithmetic_resolves_operands_first :
    (distributeBinary .add
      (.disj [(.regular, .prim (.int 1)), (.default, .prim (.int 2))])
      (.disj [(.regular, .prim (.int 10)), (.default, .prim (.int 20))])
      == .prim (.int 22)) = true := by
  native_decide

/-- F1, arithmetic NEGATIVE: a no-default operand does NOT resolve, so the op stays a stuck
    node — `(1|2) + 10` keeps the unevaluated `(1|2) + 10`, matching cue's "unresolved
    disjunction" (manifest reports incomplete), never an over-resolution. -/
theorem f1_arithmetic_no_default_stays_stuck :
    (distributeBinary .add
      (.disj [(.regular, .prim (.int 1)), (.regular, .prim (.int 2))])
      (.prim (.int 10))
      == .binary .add (.disj [(.regular, .prim (.int 1)), (.regular, .prim (.int 2))]) (.prim (.int 10)))
      = true := by
  native_decide

/-- F1, a non-default disjunction stays a non-default disjunction through resolve — no arm
    becomes a default and it does not collapse (`1 | 2` stays ambiguous). -/
theorem f1_non_default_disj_stays_non_default :
    (resolveDisjDefault? [(.regular, .prim (.int 1)), (.regular, .prim (.int 2))]
      == none) = true := by
  native_decide

/-- Was a deferred-bottom pin; float×float now evaluates exactly through the decimal
    layer. Scales add and CUE preserves the summed scale verbatim: `1.5 * 2.0 = 3.00`
    (oracle-confirmed, cue v0.16.1), no trailing-zero trim. -/
theorem eval_mul_two_floats :
    evalMul (.prim (.float "1.5")) (.prim (.float "2.0")) = .prim (.float "3.00") := by
  rfl

/-- Was a deferred-bottom pin; float÷float now evaluates through the decimal layer.
    `/` always yields a float; `3.0 / 2.0 = 1.5` terminates cleanly (oracle-confirmed,
    cue v0.16.1). -/
theorem eval_div_two_floats :
    (evalDiv (.prim (.float "3.0")) (.prim (.float "2.0")) == .prim (.float "1.5")) = true := by
  native_decide

/-- Multiplication preserves the full summed scale: `1.0 * 1.0 = 1.00`. -/
theorem eval_mul_scale_preserved :
    (evalMul (.prim (.float "1.0")) (.prim (.float "1.0")) == .prim (.float "1.00")) = true := by
  native_decide

/-- Mixed int×float promotes to float; int contributes scale 0. -/
theorem eval_mul_int_float :
    (evalMul (.prim (.int 2)) (.prim (.float "1.5")) == .prim (.float "3.0")) = true := by
  native_decide

/-- float×int likewise. -/
theorem eval_mul_float_int :
    (evalMul (.prim (.float "1.5")) (.prim (.int 2)) == .prim (.float "3.0")) = true := by
  native_decide

/-- Negative operand carries through multiplication. -/
theorem eval_mul_negative :
    (evalMul (.prim (.float "-1.5")) (.prim (.float "2.0")) == .prim (.float "-3.00")) = true := by
  native_decide

/-- int×int stays int (no float promotion). -/
theorem eval_mul_int_int :
    evalMul (.prim (.int 3)) (.prim (.int 4)) = .prim (.int 12) := by
  rfl

/-- Terminating division renders without padding. -/
theorem eval_div_terminating :
    (evalDiv (.prim (.float "1.0")) (.prim (.float "4.0")) == .prim (.float "0.25")) = true := by
  native_decide

/-- Clean division still yields a float, never an int: `4.0 / 2.0 = 2.0`. -/
theorem eval_div_clean_is_float :
    (evalDiv (.prim (.float "4.0")) (.prim (.float "2.0")) == .prim (.float "2.0")) = true := by
  native_decide

/-- Mixed float÷int promotes; `3.0 / 2 = 1.5`. -/
theorem eval_div_float_int :
    (evalDiv (.prim (.float "3.0")) (.prim (.int 2)) == .prim (.float "1.5")) = true := by
  native_decide

/-- Mixed int÷float promotes; `2 / 4.0 = 0.5`. -/
theorem eval_div_int_float :
    (evalDiv (.prim (.int 2)) (.prim (.float "4.0")) == .prim (.float "0.5")) = true := by
  native_decide

/-- Negative division carries the sign. -/
theorem eval_div_negative :
    (evalDiv (.prim (.float "-1.0")) (.prim (.float "4.0")) == .prim (.float "-0.25")) = true := by
  native_decide

/-- Float division by zero is bottom with divisionByZero provenance. -/
theorem eval_div_float_by_zero :
    (evalDiv (.prim (.float "1.0")) (.prim (.float "0.0")) == .bottomWith [.divisionByZero]) = true := by
  native_decide

/-- int÷int now routes through the same decimal divider and yields a float: `6 / 2 = 3.0`. -/
theorem eval_div_int_int_is_float :
    (evalDiv (.prim (.int 6)) (.prim (.int 2)) == .prim (.float "3.0")) = true := by
  native_decide

/-- Repeating-decimal division renders at 34 significant digits, round-half-up.
    `2.0 / 3.0 = 0.666…667` (34 sig digits). This is the apd-context subset that is
    now reachable; see compat-assumptions for the rounding-tie boundary. -/
theorem eval_div_repeating :
    (evalDiv (.prim (.float "2.0")) (.prim (.float "3.0"))
      == .prim (.float "0.6666666666666666666666666666666667")) = true := by
  native_decide

/-- Repeating division with an integer part rounds at 34 sig digits, not 34 frac
    digits: `10.0 / 3.0 = 3.33…3` (33 frac digits). Pins the significant-digit rule
    that the prior fixed-fraction int divider got wrong for quotients ≥ 1. -/
theorem eval_div_repeating_int_part :
    (evalDiv (.prim (.float "10.0")) (.prim (.float "3.0"))
      == .prim (.float "3.333333333333333333333333333333333")) = true := by
  native_decide

/-- Rounding carries past 9s: `100.0 / 7.0 = 14.28…29`, last digit rounded up. -/
theorem eval_div_repeating_round_up :
    (evalDiv (.prim (.float "100.0")) (.prim (.float "7.0"))
      == .prim (.float "14.28571428571428571428571428571429")) = true := by
  native_decide

/-- High-fuel pin: a full-34-significant-digit repeating quotient with no leading
    zeros. `1.0 / 7.0 = 0.142857…429` emits the maximum significant digits plus the
    guard, so the `divisionDigitsFuel` ceiling must not be exhausted before the
    over-budget exit. Reduces under `native_decide` ⇒ the bound is sufficient. -/
theorem eval_div_repeating_full_sig :
    (evalDiv (.prim (.float "1.0")) (.prim (.float "7.0"))
      == .prim (.float "0.1428571428571428571428571428571429")) = true := by
  native_decide

/-- High-fuel pin exercising the leading-zero slack in the fuel bound: `1.0 / 700.0
    = 0.001428…429` has two leading fractional zeros (non-emitting iterations) on
    top of the 34 significant digits, so it leans on the `+ <den digit count>` term
    of `divisionDigitsFuel`. -/
theorem eval_div_repeating_leading_zeros :
    (evalDiv (.prim (.float "1.0")) (.prim (.float "700.0"))
      == .prim (.float "0.001428571428571428571428571428571429")) = true := by
  native_decide

/-- Slice 2c.1: an in-struct sibling reference (`b: a`) sees the FULLY-MERGED value of a
    duplicated label, not the first conjunct. `{a: int, b: a, a: 1}` canonicalizes the two
    `a` slots into `.conj [int, 1]` at slot 0, so `b` evaluates to `1`, and the duplicate
    collapses to a single `a` field. -/
theorem eval_in_struct_sibling_merge :
    (resolveAndEval
      (mkStruct [⟨"a", .regular, .kind .int⟩, ⟨"b", .regular, .ref "a"⟩, ⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none [])
      == mkStruct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.int 1)⟩] .regularOpen none []) = true := by
  native_decide

/-- A duplicate-label conflict bottoms both the label and any sibling referencing it:
    `{a: 1, b: a, a: 2}` -> `a` and `b` both bottom. -/
theorem eval_in_struct_sibling_conflict :
    (resolveAndEval
      (mkStruct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .ref "a"⟩, ⟨"a", .regular, .prim (.int 2)⟩] .regularOpen none [])
      == mkStruct [
          ⟨"a", .regular, .bottomWith [.primitiveConflict (.int 1) (.int 2)]⟩,
          ⟨"b", .regular, .bottomWith [.primitiveConflict (.int 1) (.int 2)]⟩
        ] .regularOpen none []) = true := by
  native_decide

/-- Canonicalization is visible through nested sub-structs: `c.e` references the outer `a`,
    seeing the merged `int & 1 = 1`. -/
theorem eval_nested_sibling_merge :
    (resolveAndEval
      (mkStruct [
          ⟨"a", .regular, .kind .int⟩,
          ⟨"c", .regular, mkStruct [⟨"e", .regular, .ref "a"⟩] .regularOpen none []⟩,
          ⟨"a", .regular, .prim (.int 1)⟩
        ] .regularOpen none [])
      == mkStruct [
          ⟨"a", .regular, .prim (.int 1)⟩,
          ⟨"c", .regular, mkStruct [⟨"e", .regular, .prim (.int 1)⟩] .regularOpen none []⟩
        ] .regularOpen none []) = true := by
  native_decide

/-- A self-referential merged slot must not loop: `{a: a, a: 1}` canonicalizes to
    `.conj [a, 1]` at slot 0; the self-ref hits the `slotVisited` -> `.top` guard, so the
    meet collapses to `1` rather than diverging. -/
theorem eval_merged_self_ref_cycle :
    (resolveAndEval
      (mkStruct [⟨"a", .regular, .ref "a"⟩, ⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none [])
      == mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []) = true := by
  native_decide

/-- 2c.2: struct conjunction through a referenced binding. `d & {a: 1}` merges the conjuncts'
    declarations into one frame before evaluating bodies, so `d.b: a` sees the narrowed `a`
    and `y.b` resolves to `1` (not `int`). -/
theorem eval_meet_lazy_sibling_ref :
    (resolveAndEval
      (mkStruct [
          ⟨"d", .regular, mkStruct [⟨"a", .regular, .kind .int⟩, ⟨"b", .regular, .ref "a"⟩] .regularOpen none []⟩,
          ⟨"y", .regular, .conj [.ref "d", mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []]⟩
        ] .regularOpen none [])
      == mkStruct [
          ⟨"d", .regular, mkStruct [⟨"a", .regular, .kind .int⟩, ⟨"b", .regular, .kind .int⟩] .regularOpen none []⟩,
          ⟨"y", .regular,
            mkStruct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.int 1)⟩] .regularOpen none []⟩
        ] .regularOpen none []) = true := by
  native_decide

/-- 2c.2: literal struct conjunction (no reference operand). `{a: int, b: a} & {a: 1}` → `b: 1`
    via the merged frame. -/
theorem eval_meet_lazy_literal :
    (resolveAndEval
      (mkStruct [
          ⟨"x", .regular,
            .conj
              [
                mkStruct [⟨"a", .regular, .kind .int⟩, ⟨"b", .regular, .ref "a"⟩] .regularOpen none [],
                mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []
              ]⟩
        ] .regularOpen none [])
      == mkStruct [
          ⟨"x", .regular,
            mkStruct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.int 1)⟩] .regularOpen none []⟩
        ] .regularOpen none []) = true := by
  native_decide

/-- 2c.2: a chained sibling reference within one conjunct, narrowed across the meet —
    `{a: int, b: a, c: b} & {a: 1}` resolves `a`, `b`, `c` all to `1`. -/
theorem eval_meet_lazy_chain :
    (resolveAndEval
      (mkStruct [
          ⟨"x", .regular,
            .conj
              [
                mkStruct [
                    ⟨"a", .regular, .kind .int⟩,
                    ⟨"b", .regular, .ref "a"⟩,
                    ⟨"c", .regular, .ref "b"⟩
                  ] .regularOpen none [],
                mkStruct [⟨"a", .regular, .prim (.int 1)⟩] .regularOpen none []
              ]⟩
        ] .regularOpen none [])
      == mkStruct [
          ⟨"x", .regular,
            mkStruct [
                ⟨"a", .regular, .prim (.int 1)⟩,
                ⟨"b", .regular, .prim (.int 1)⟩,
                ⟨"c", .regular, .prim (.int 1)⟩
              ] .regularOpen none []⟩
        ] .regularOpen none []) = true := by
  native_decide

/-- 2c.2: nested sub-struct visibility through a *definition* meet. `out.val` references the
    hidden `#x`; `#D & {#x: "hi"}` narrows `#x` and the nested `out.val` resolves to `"hi"`. -/
theorem eval_meet_lazy_hidden_def :
    (resolveAndEval
      (mkStruct [
          ⟨"#D", .definition,
            mkStruct [
                ⟨"#x", .definition, .kind .string⟩,
                ⟨"out", .regular, mkStruct [⟨"val", .regular, .ref "#x"⟩] .regularOpen none []⟩
              ] .regularOpen none []⟩,
          ⟨"y", .regular, .conj [.ref "#D", mkStruct [⟨"#x", .definition, .prim (.string "hi")⟩] .regularOpen none []]⟩
        ] .regularOpen none [])
      -- SC-2: `#D`'s nested regular field `out` is a plain struct WITHIN the def body, so the
      -- closing walker closes its value (`.defClosed`) — recursively, like every nested
      -- def-body plain struct. The closure carries through the `#D & {…}` meet to `y.out`
      -- (monotone). Formatted output is unchanged (closedness is invisible in `eval` display).
      == mkStruct [
          ⟨"#D", .definition,
            mkStruct [
                ⟨"#x", .definition, .kind .string⟩,
                ⟨"out", .regular, mkStruct [⟨"val", .regular, .kind .string⟩] .defClosed none []⟩
              ] .defClosed none []⟩,
          ⟨"y", .regular,
            mkStruct [
                ⟨"#x", .definition, .prim (.string "hi")⟩,
                ⟨"out", .regular, mkStruct [⟨"val", .regular, .prim (.string "hi")⟩] .defClosed none []⟩
              ] .defClosed none []⟩
        ] .regularOpen none []) = true := by
  native_decide

/-! ### B2.2 must-fix item 3 — `applyEvaluatedStructN` pattern path (end-to-end, live).

With production emitting the unified `.struct`, an evaluated pattern-struct now flows through
`applyEvaluatedStructN`'s pattern arm (`meet (mkStruct [] op none patterns) (mkStruct fields
…)`), which applies each `[pattern]: constraint` to the matching evaluated fields. These pin
that arm against cue v0.16.1: a matching field is constrained (`xy` matches `=~"x"`, so
`string & "hi" = "hi"`; a conflicting constraint bottoms it), a non-matching field is left
untouched (`z`). cue elides the residual `[=~"x"]: c` pattern in `eval` output but APPLIES it;
Kue keeps the pattern visible (a formatting divergence, recorded) — the field VALUES agree
exactly with cue (`xy: "hi"`/`xy: _|_`, `z: 1`). -/
theorem eval_pattern_struct_applies_to_matching_field :
    evalSourceMatches
        "out: {[=~\"x\"]: string, xy: \"hi\", z: 1}\n"
        "out: {xy: \"hi\", z: 1, [=~\"x\"]: string}"
      = true := by
  native_decide

theorem eval_pattern_struct_constraint_conflict_bottoms_field :
    evalSourceMatches
        "out: {[=~\"x\"]: int, xy: \"str\"}\n"
        "out: {xy: _|_, [=~\"x\"]: int}"
      = true := by
  native_decide

/-! ### B6 — definition-body closedness enforced through a regular field (gap 1).

A closed `#Def` nested under a REGULAR field reaches the use-site meet still closed, so an
undeclared field is rejected. Pre-B6 `normalizeFieldWithFuel` left a regular field's value
unwalked, so the nested def stayed open and admitted the extra. Oracle: cue v0.16.1 reports
`out.extra: field not allowed` for the closed form and admits `extra` when the def is opened via
`...`. The eager-selector form (`x.#Inner`, gap 2) is the SAME root cause — once normalize closes
the def, the eager selector returns the closed body and the existing meet enforces it. -/
theorem eval_closed_def_under_regular_field_rejects_extra :
    evalSourceMatches
        "a: {\n\t#Inner: {x: int}\n}\nout: a.#Inner & {x: 1, extra: 2}\n"
        "a: {#Inner: {x: int}}\nout: {x: 1, extra: _|_}"
      = true := by
  native_decide

theorem eval_eager_selector_closed_def_rejects_extra :
    evalSourceMatches
        "x: {#Inner: {y: int}}\nout: x.#Inner & {y: 1, extra: 3}\n"
        "x: {#Inner: {y: int}}\nout: {y: 1, extra: _|_}"
      = true := by
  native_decide

theorem eval_open_def_under_regular_field_admits_extra :
    evalSourceMatches
        "a: {\n\t#Inner: {x: int, ...}\n}\nout: a.#Inner & {x: 1, extra: 2}\n"
        "a: {#Inner: {x: int, ...}}\nout: {x: 1, extra: 2, ...}"
      = true := by
  native_decide

/-! ### B6-A2 — definition-body closedness enforced through a `let`-bound value.

A closed `#Def` nested under a `let` binding closes exactly as under a regular field: `letBinding`
is its OWN `FieldClass` kind, NOT the import-binding A2 trap (the hidden-field skip), so the spine
walker can recurse it safely. Oracle cue v0.16.1: `let x = {#I: {y:int}}; x.#I & {extra}` →
`out.extra: field not allowed`; an open def (`...`) under the same `let` admits `extra` (no
over-close). This is the `letBinding` arm of the future A2-followup 4-way `FieldClass` split. -/
theorem eval_let_nested_def_closes :
    evalSourceMatches
        "let x = {#I: {y: int}}\nout: x.#I & {y: 1, extra: 2}\n"
        "out: {y: 1, extra: _|_}"
      = true := by
  native_decide

theorem eval_let_nested_def_open_admits_extra :
    evalSourceMatches
        "let x = {#I: {y: int, ...}}\nout: x.#I & {y: 1, extra: 2}\n"
        "out: {y: 1, extra: 2, ...}"
      = true := by
  native_decide

theorem eval_let_plain_struct_stays_open :
    evalSourceMatches
        "let x = {p: {y: int}}\nout: x.p & {y: 1, extra: 2}\n"
        "out: {y: 1, extra: 2}"
      = true := by
  native_decide

/-! ### B6-T1 — closedness regression pins.

B6 is the most regression-prone class (prior closedness changes bottomed `#ListenerSet`/
cert-manager). These pin the shapes the Phase-A over-close hunt exercised so future closedness
work cannot silently regress them. Each oracle-checked vs cue v0.16.1. (SC-2 closed the former
direct-def-path gap — `#D.r & {extra}` now correctly rejects; pinned in the SC-2 cluster below.) -/
theorem eval_b6_depth2_nested_def_closes :
    evalSourceMatches
        "a: {b: {#Inner: {x: int}}}\nout: a.b.#Inner & {x: 1, extra: 2}\n"
        "a: {b: {#Inner: {x: int}}}\nout: {x: 1, extra: _|_}"
      = true := by
  native_decide

theorem eval_b6_plain_struct_under_regular_stays_open :
    evalSourceMatches
        "a: {b: {x: int}}\nout: a.b & {x: 1, extra: 2}\n"
        "a: {b: {x: int}}\nout: {x: 1, extra: 2}"
      = true := by
  native_decide

theorem eval_b6_def_meet_rejects_unallowed :
    evalSourceMatches
        "#D: {a: int, b: string}\nout: #D & {a: 1, c: 2}\n"
        "#D: {a: int, b: string}\nout: {a: 1, b: string, c: _|_}"
      = true := by
  native_decide

theorem eval_b6_comprehension_field_admits_sibling :
    evalSourceMatches
        "a: {x: int, if true {y: 1}}\nout: a & {x: 1, y: 1}\n"
        "a: {x: int, y: 1}\nout: {x: 1, y: 1}"
      = true := by
  native_decide

theorem eval_b6_embedding_field_admits_sibling :
    evalSourceMatches
        "base: {m: int}\na: {base, n: int}\nout: a & {m: 1, n: 2}\n"
        "base: {m: int}\na: {n: int, m: int}\nout: {n: 2, m: 1}"
      = true := by
  native_decide

-- SC-2b — DIVERGES from cue (recorded in cue-divergences.md). cue RE-OPENS nested closedness on
-- a `& {}` instantiation (`(#D & {}).r & {extra}` admits `extra`); the spec says closedness is
-- monotone through meet, so the closed `r` STAYS closed and `extra` is REJECTED. Kue follows the
-- spec. cue is internally inconsistent: the direct path `#D.r & {extra}` rejects (cue+Kue agree),
-- only the no-op `& {}` re-opens — an eval-strategy artifact, not lattice-derivable.
theorem eval_sc2b_instantiated_def_field_stays_closed :
    evalSourceMatches
        "#D: {r: {x: int}}\nout: (#D & {}).r & {x: 1, extra: 2}\n"
        "#D: {r: {x: int}}\nout: {x: 1, extra: _|_}"
      = true := by
  native_decide

/-! ### SC-2 — nested def-body closedness (the closing field-walker twin).

The four soundness obligations from the SC-2 design, pinned. The closing walker closes a
referenced def's nested PLAIN-struct field VALUES (obligation 1), recursively, BUT only inside
a referenced def — a plain non-def struct (obligation 2) and a hidden-field nested struct
(obligation 4) stay open, and a nested `...` stays open (obligation 3). Each oracle-checked vs
cue v0.16.1; obligations 1/3 agree with cue, 2/4 agree with cue (controls). -/

-- Obligation 1: a referenced closed def's nested field rejects an extra (the SC-2a fix).
theorem eval_sc2_nested_def_field_closes :
    evalSourceMatches
        "#A: {a: {b: int}}\nout: #A & {a: {b: 1, extra: 5}}\n"
        "#A: {a: {b: int}}\nout: {a: {b: 1, extra: _|_}}"
      = true := by
  native_decide

-- Obligation 2: a PLAIN (non-def) nested struct stays OPEN — the closing twin never runs here.
theorem eval_sc2_plain_nested_struct_stays_open :
    evalSourceMatches
        "A: {a: {b: int}}\nout: A & {a: {b: 1, extra: 5}}\n"
        "A: {a: {b: int}}\nout: {a: {b: 1, extra: 5}}"
      = true := by
  native_decide

-- Obligation 3: a nested `...` keeps the nested struct OPEN (`defOpenViaTail` left unchanged).
theorem eval_sc2_nested_tail_stays_open :
    evalSourceMatches
        "#A: {a: {b: int, ...}}\nout: #A & {a: {b: 1, extra: 5}}\n"
        "#A: {a: {b: int, ...}}\nout: {a: {b: 1, extra: 5, ...}}"
      = true := by
  native_decide

-- Obligation 4: a def's HIDDEN-field nested struct stays OPEN (the spine walker, untouched).
theorem eval_sc2_hidden_field_nested_stays_open :
    evalSourceMatches
        "#A: {_h: {x: int}}\nx: #A\nout: x._h & {x: 1, extra: 2}\n"
        "#A: {_h: {x: int}}\nx: {_h: {x: int}}\nout: {x: 1, extra: 2}"
      = true := by
  native_decide

end Kue
