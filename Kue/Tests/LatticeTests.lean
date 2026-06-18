import Kue.Eval
import Kue.Format
import Kue.Lattice
import Kue.Runtime
import Kue.Tests.EvalTestHelpers

/-! # `LatticeTests` — `meet` / `join` algebra (B4 + B2 regression gate)

Dedicated unit pins for the lattice operators. `meet` (greatest-lower-bound / unification)
and `join` (least-upper-bound / disjunction) are exercised indirectly all over `EvalTests`
and the fixtures, but had no home of their own (B4). This module pins the algebra directly,
with a deliberate focus on the **struct-shape arms B2 will collapse** — the
`struct`/`structTail`/`structPattern`/`structPatterns`/`structComp` pairwise meets.

Two layers, by what survives the B2 refactor:

* **Scalar / kind / bound / regex / list / disjunction algebra** — pinned at the
  `meet`/`join` constructor level. These RHS values do not change under B2 (they touch no
  struct constructor), so a constructor-level pin is the right, tightest gate.
* **Struct-shape behavior** — pinned at the SOURCE level via `evalSourceMatches`, NOT via
  the internal `.structTail`/`.structPattern` constructor RHS. B2 collapses those five
  constructors into one normalized struct, so any pin asserting a specific struct
  constructor as its RHS would break *by construction* when B2 lands — a false regression.
  A source→exported-value pin captures what `cue` produces and what B2 must preserve,
  independent of which constructor carries it internally. (`StructTests` already pins the
  `tail×struct` / `pattern×struct` arms at the constructor level; those are the merge-time
  shapes that B2 keeps observable, so they are not duplicated here.)

All struct cases below are oracle-checked against `cue` v0.16.1 (`/Users/chakrit/go/bin/cue`).

## B2.5 — the struct cross-combination fix (FIXED, pinned below)

`meetWithFuel` (`Lattice.lean`) once MISSED two struct cross-combinations: a pattern-bearing
struct meeting a tail-bearing struct (in either order) had no explicit arm and fell through to
`.bottom`, where `cue` unifies. The legacy five-constructor type could not co-represent a tail
AND patterns, so the arm was unrepresentable. The B2 collapse to one `Value.struct (fields,
openness, tail, patterns)` carries both axes, and B2.5 flips the residual `.bottom` to a real
unify:

```
#P: {[string]: int}
#T: {a: 5, ...}
out: #P & #T        // cue v0.16.1 → {a: 5} (open) ; kue → {a: 5} (open) — FIXED
```

The pins below (`mergeStructN_*_unifies`, both orders, single + multi-pattern) lock in the
cue-correct unified value: the pattern constrains every field, the tail keeps the struct open,
and both axes are retained. -/

namespace Kue

/-! ## Lattice laws — identities and absorption -/

theorem lattice_meet_top_is_identity (value : Value) : meet .top value = value := by
  cases value <;> rfl

theorem lattice_meet_bottom_absorbs (value : Value) : meet .bottom value = .bottom := by
  cases value <;> rfl

theorem lattice_join_bottom_is_identity (value : Value) : join .bottom value = value := by
  cases value <;> rfl

theorem lattice_join_top_absorbs (value : Value) : join .top value = .top := by
  cases value <;> rfl

/-! ## Scalars -/

theorem lattice_meet_equal_ints :
    meet (.prim (.int 5)) (.prim (.int 5)) = .prim (.int 5) := by
  rfl

theorem lattice_meet_conflicting_ints :
    meet (.prim (.int 1)) (.prim (.int 2))
      = .bottomWith [.primitiveConflict (.int 1) (.int 2)] := by
  rfl

theorem lattice_meet_conflicting_strings :
    (isBottom (meet (.prim (.string "a")) (.prim (.string "b")))) = true := by
  native_decide

theorem lattice_join_distinct_ints_is_disjunction :
    (join (.prim (.int 1)) (.prim (.int 2))
      == .disj [(.regular, .prim (.int 1)), (.regular, .prim (.int 2))]) = true := by
  native_decide

/-! ## Kinds -/

theorem lattice_meet_number_int_narrows_to_int :
    meet (.kind .number) (.kind .int) = .kind .int := by
  rfl

theorem lattice_meet_kind_with_inhabitant :
    meet (.kind .int) (.prim (.int 1)) = .prim (.int 1) := by
  rfl

theorem lattice_meet_conflicting_kinds_has_provenance :
    meet (.kind .int) (.kind .string)
      = .bottomWith [.kindConflict .int .string] := by
  rfl

theorem lattice_join_kind_subsumes_regex :
    (join (.kind .string) (.stringRegex "^a$") == .kind .string) = true := by
  native_decide

/-! ## Bounds — the bound×scalar narrowing surface lives in `BoundTests`; pin the
join-with-kind absorption here so the algebra has a `join` bound pin. -/

theorem lattice_meet_bound_with_satisfying_scalar :
    meet (.boundConstraint (intDecimal 0) .ge .number) (.prim (.int 1)) = .prim (.int 1) := by
  rfl

theorem lattice_meet_bound_with_violating_scalar :
    meet (.boundConstraint (intDecimal 0) .gt .number) (.prim (.int (-1)))
      = .bottomWith [.boundConflict] := by
  rfl

/-! ## Regex -/

theorem lattice_meet_regex_with_matching_string :
    (meet (.stringRegex "^a$") (.prim (.string "a")) == .prim (.string "a")) = true := by
  native_decide

theorem lattice_meet_regex_with_non_matching_string :
    (isBottom (meet (.stringRegex "^a$") (.prim (.string "b")))) = true := by
  native_decide

/-! ## Lists -/

theorem lattice_meet_lists_elementwise :
    meet (.list [.prim (.int 1), .kind .int]) (.list [.kind .int, .prim (.int 2)])
      = .list [.prim (.int 1), .prim (.int 2)] := by
  rfl

theorem lattice_meet_lists_length_conflict_bottoms :
    (isBottom (meet (.list [.prim (.int 1), .prim (.int 2)]) (.list [.prim (.int 1)]))) = true := by
  native_decide

theorem lattice_join_distinct_lists_is_disjunction :
    (join (.list [.prim (.int 1)]) (.list [.prim (.int 2)])
      == .disj [(.regular, .list [.prim (.int 1)]), (.regular, .list [.prim (.int 2)])]) = true := by
  native_decide

/-! ## Disjunctions — distribution + default-mark algebra. -/

theorem lattice_meet_disjunction_distributes_and_prunes :
    meet
      (.disj [(.regular, .prim (.string "a")), (.regular, .prim (.int 1))])
      (.kind .string)
      = .prim (.string "a") := by
  rfl

theorem lattice_meet_disjunction_preserves_default_marker :
    meet
      (.disj [(.default, .prim (.int 1)), (.regular, .prim (.string "a"))])
      (.kind .int)
      = .disj [(.default, .prim (.int 1))] := by
  rfl

/-! ## Struct-shape arms (B2 regression gate) — source-level, oracle-checked vs cue v0.16.1.

These pin the OBSERVABLE result of each struct constructor pair that B2 collapses. They are
the gate B2's mechanical migration must keep green; the internal constructor carrying the
result may change, the exported value may not. The struct shapes are pinned through the JSON
`export` (`exportJsonMatches`) rather than the CUE-syntax `eval` output, because eval keeps
the structural decoration (`...`, `[string]: T`) that B2 will re-render — JSON shows only the
concrete fields, which B2 must preserve. The one rejection case (closed def + extra field)
errors the whole export, so it is pinned through `eval` as a bottomed field (`b: _|_`), itself
representation-independent. -/

-- struct × struct, OPEN: two open structs merge their fields.
theorem lattice_struct_meet_struct_open_merges :
    exportJsonMatches "out: {a: 1} & {b: 2}\n"
        "{\n    \"out\": {\n        \"a\": 1,\n        \"b\": 2\n    }\n}\n" = true := by
  native_decide

-- struct × struct, CLOSED def: an extra field past a closed definition is REJECTED (`_|_`).
theorem lattice_struct_meet_struct_closed_rejects_extra :
    evalSourceMatches
        "#C: {a: int}\nout: #C & {a: 1, b: 2}\n"
        "#C: {a: int}\nout: {a: 1, b: _|_}" = true := by
  native_decide

-- structTail × structTail: two `...`-tailed structs unify; both tails and fields merge.
theorem lattice_structTail_meet_structTail :
    exportJsonMatches
        "#A: {a: int, ...}\n#B: {b: string, ...}\nout: #A & #B & {a: 1, b: \"x\"}\n"
        "{\n    \"out\": {\n        \"a\": 1,\n        \"b\": \"x\"\n    }\n}\n" = true := by
  native_decide

-- structPattern × structPattern: two single-pattern structs both constrain the same field.
theorem lattice_structPattern_meet_structPattern :
    exportJsonMatches
        "out: {[string]: int} & {[=~\"^a\"]: >0} & {a1: 5}\n"
        "{\n    \"out\": {\n        \"a1\": 5\n    }\n}\n" = true := by
  native_decide

-- structPattern × structPatterns (the cross-arm the B2 plan once thought missing — it is
-- IMPLEMENTED; pin it so B2's collapse keeps it correct): a single-pattern struct meets a
-- multi-pattern struct.
theorem lattice_structPattern_meet_structPatterns :
    exportJsonMatches
        "out: {[string]: int} & {[=~\"x\"]: >0, [=~\"y\"]: <10} & {x1: 3, y1: 4}\n"
        "{\n    \"out\": {\n        \"x1\": 3,\n        \"y1\": 4\n    }\n}\n" = true := by
  native_decide

-- structPatterns × structPatterns: two multi-pattern structs both apply.
theorem lattice_structPatterns_meet_structPatterns :
    exportJsonMatches
        "out: {[string]: int, [=~\"x\"]: >0} & {[=~\"y\"]: <10, [string]: number} & {x1: 3, y1: 4}\n"
        "{\n    \"out\": {\n        \"x1\": 3,\n        \"y1\": 4\n    }\n}\n" = true := by
  native_decide

/-! ## `mkStruct` smart-constructor invariants (B2.1)

The B2 target representation `Value.struct` is built only through `mkStruct`, which
normalizes its arguments so the illegal states (incoherent tail/openness, duplicate
patterns) are unconstructable. These pins are the regression gate for that guarantee — they
exercise `mkStruct`/`coherentTail`/`dedupPatterns` directly (no producer feeds `struct`
through eval yet in B2.1), so they survive the later B2 migration unchanged. -/

/-- Helper: does a built `struct` carry the coherent `tail = some _ ↔ defOpenViaTail`
    shape? `true` for any other constructor (the property is vacuous off-`struct`). -/
def structNTailCoherent : Value -> Bool
  | .struct _ openness tail _ =>
      match tail, openness with
      | some _, .defOpenViaTail => true
      | none, .defOpenViaTail => false
      | some _, _ => false
      | none, _ => true
  | _ => true

-- A `some` tail forces `defOpenViaTail`, whatever openness the caller passed: the
-- incoherent (tail + regularOpen) pair is normalized, never represented. (`Value` has no
-- `DecidableEq` by design — the perf carve-out — so these pin via `BEq` `==`, like the
-- struct-meet pins above.)
theorem mkStruct_some_tail_forces_defOpenViaTail :
    (mkStruct [] .regularOpen (some (.prim (.int 1))) []
      == .struct [] .defOpenViaTail (some (.prim (.int 1))) []) = true := by
  native_decide

-- A `some` tail with `defClosed` is likewise coerced to `defOpenViaTail` (a closed struct
-- with a `...` is the nonsense state; it cannot be built).
theorem mkStruct_some_tail_closed_coerced :
    (mkStruct [] .defClosed (some .top) [] == .struct [] .defOpenViaTail (some .top) []) = true
      := by
  native_decide

-- `defOpenViaTail` with NO tail gets the bare-`...` default `some .top` — the other half
-- of the never-constructable pair (defOpenViaTail without a tail).
theorem mkStruct_defOpenViaTail_no_tail_defaults_top :
    (mkStruct [] .defOpenViaTail none [] == .struct [] .defOpenViaTail (some .top) []) = true
      := by
  native_decide

-- A non-tail openness keeps `tail = none`: `regularOpen`/`defClosed` are tail-free.
theorem mkStruct_regularOpen_stays_tailless :
    (mkStruct [] .regularOpen none [] == .struct [] .regularOpen none []) = true := by
  native_decide

theorem mkStruct_defClosed_stays_tailless :
    (mkStruct [] .defClosed none [] == .struct [] .defClosed none []) = true := by
  native_decide

-- Coherence holds for every openness/tail combination `mkStruct` is given — the four
-- nonsense inputs are all normalized to a coherent `struct`.
theorem mkStruct_always_coherent :
    (structNTailCoherent (mkStruct [] .regularOpen (some .top) [])
      && structNTailCoherent (mkStruct [] .defClosed (some .top) [])
      && structNTailCoherent (mkStruct [] .defOpenViaTail none [])
      && structNTailCoherent (mkStruct [] .regularOpen none [])
      && structNTailCoherent (mkStruct [] .defClosed none [])
      && structNTailCoherent (mkStruct [] .defOpenViaTail (some .top) [])) = true := by
  native_decide

-- Pattern dedup: a duplicate `(labelPattern, constraint)` pair is dropped, first kept.
theorem mkStruct_dedups_patterns :
    (mkStruct [] .regularOpen none [(.kind .string, .kind .int), (.kind .string, .kind .int)]
      == .struct [] .regularOpen none [(.kind .string, .kind .int)]) = true := by
  native_decide

-- Pattern dedup is idempotent: deduping an already-deduped pattern list is a no-op.
theorem mkStruct_dedup_idempotent :
    (dedupPatterns (dedupPatterns
        [(.kind .string, .kind .int), (.kind .string, .kind .int), (.kind .bool, .kind .int)])
      == dedupPatterns
        [(.kind .string, .kind .int), (.kind .string, .kind .int), (.kind .bool, .kind .int)])
      = true := by
  native_decide

-- Distinct patterns are preserved (dedup does not over-collapse), order stable.
theorem mkStruct_keeps_distinct_patterns :
    (mkStruct [] .regularOpen none [(.kind .string, .kind .int), (.kind .bool, .kind .int)]
      == .struct [] .regularOpen none [(.kind .string, .kind .int), (.kind .bool, .kind .int)])
      = true := by
  native_decide

/-! ## `mergeStructN` arm pins (B2.2/CP3-pre must-fix item 2)

These exercise the `mergeStructN` arms through the LIVE `meet` path (production still emits
old `.struct`, but `meet (.struct…) (.struct…)` already dispatches to `mergeStructN`).
Each pins a behavior the legacy arms carried that a subtly-wrong arm could silently drop:
the cross-shape field-merge order, the tail-on-both-sides extra-field application, the
arm-7 pattern dedup, and the pattern×tail cross-combinations B2.5 unifies (the `_unifies`
pins below — formerly `.bottom`, now the cue-correct unified value). -/

-- `struct × structTail` field-merge ORDER: the tail-bearing side's fields come FIRST
-- (`mergeStructFieldsWith rightFields leftFields` reverses the natural left-first order).
-- `{b, a} & {c, ...}` ⟹ fields `[c, b, a]`, NOT `[b, a, c]`.
theorem mergeStructN_struct_tail_reverses_field_order :
    (meet
        (.struct [⟨"b", .regular, .prim (.string "x")⟩, ⟨"a", .regular, .prim (.int 1)⟩]
          .regularOpen none [])
        (.struct [⟨"c", .regular, .prim (.bool true)⟩] .defOpenViaTail (some .top) [])
      == .struct
          [
            ⟨"c", .regular, .prim (.bool true)⟩,
            ⟨"b", .regular, .prim (.string "x")⟩,
            ⟨"a", .regular, .prim (.int 1)⟩
          ]
          .defOpenViaTail (some .top) []) = true := by
  native_decide

-- `structTail × struct` (the symmetric order) merges tail-side first the same way:
-- left is the tail-bearing side, `mergeStructFieldsWith leftFields rightFields` ⟹ `[c, b, a]`.
theorem mergeStructN_tail_struct_keeps_tail_fields_first :
    (meet
        (.struct [⟨"c", .regular, .prim (.bool true)⟩] .defOpenViaTail (some .top) [])
        (.struct [⟨"b", .regular, .prim (.string "x")⟩, ⟨"a", .regular, .prim (.int 1)⟩]
          .regularOpen none [])
      == .struct
          [
            ⟨"c", .regular, .prim (.bool true)⟩,
            ⟨"b", .regular, .prim (.string "x")⟩,
            ⟨"a", .regular, .prim (.int 1)⟩
          ]
          .defOpenViaTail (some .top) []) = true := by
  native_decide

-- `structTail × structTail`: `applyTailToExtrasWith` runs on BOTH sides' extras. The left
-- tail (`int`) constrains the right's extra field `b`; the merged tail is `meet leftT rightT`.
theorem mergeStructN_tail_tail_applies_both_tails_to_extras :
    (meet
        (.struct [⟨"a", .regular, .top⟩] .defOpenViaTail (some (.kind .int)) [])
        (.struct [⟨"b", .regular, .top⟩] .defOpenViaTail (some .top) [])
      == .struct
          [⟨"a", .regular, .top⟩, ⟨"b", .regular, .kind .int⟩]
          .defOpenViaTail (some (.kind .int)) []) = true := by
  native_decide

-- Arm 7 (`structPatterns × structPatterns`): `leftPatterns ++ rightPatterns` then `mkStruct`
-- DEDUPS equal pairs — `{[=~"a"]: int} & {[=~"a"]: int}` keeps ONE pattern (oracle: cue
-- v0.16.1 collapses the duplicate too, `cue eval` ⟹ `{}`).
theorem mergeStructN_pattern_pattern_dedups_equal_patterns :
    (meet
        (.struct [] .regularOpen none [(.stringRegex "a", .kind .int)])
        (.struct [] .regularOpen none [(.stringRegex "a", .kind .int)])
      == .struct [] .regularOpen none [(.stringRegex "a", .kind .int)]) = true := by
  native_decide

-- Distinct patterns from both sides are CONCATENATED (no over-dedup), order left-then-right.
theorem mergeStructN_pattern_pattern_concats_distinct_patterns :
    (meet
        (.struct [] .regularOpen none [(.stringRegex "a", .kind .int)])
        (.struct [] .regularOpen none [(.stringRegex "b", .kind .string)])
      == .struct [] .regularOpen none
          [(.stringRegex "a", .kind .int), (.stringRegex "b", .kind .string)]) = true := by
  native_decide

-- Cross-combination `structPattern × structTail` (patterns one side, tail the other): the
-- B2.5 behavioral fix. The legacy type could not co-represent a tail AND patterns so this fell
-- to `.bottom`; the unified `struct` carries both axes, so it now UNIFIES — the pattern
-- constrains the field (`int & 1 = 1`), the tail keeps the struct open, and BOTH are retained
-- in the result. Oracle: `{[=~"a"]: int} & {a: 1, ...}` → cue v0.16.1 `{a: 1}` (open). (Both
-- orders — meet is commutative here.)
theorem mergeStructN_pattern_tail_unifies :
    (meet
        (.struct [] .regularOpen none [(.stringRegex "a", .kind .int)])
        (.struct [⟨"a", .regular, .prim (.int 1)⟩] .defOpenViaTail (some .top) [])
      == .struct [⟨"a", .regular, .prim (.int 1)⟩] .defOpenViaTail (some .top)
          [(.stringRegex "a", .kind .int)]) = true := by
  native_decide

theorem mergeStructN_tail_pattern_unifies :
    (meet
        (.struct [⟨"a", .regular, .prim (.int 1)⟩] .defOpenViaTail (some .top) [])
        (.struct [] .regularOpen none [(.stringRegex "a", .kind .int)])
      == .struct [⟨"a", .regular, .prim (.int 1)⟩] .defOpenViaTail (some .top)
          [(.stringRegex "a", .kind .int)]) = true := by
  native_decide

-- The multi-pattern (`structPatterns`) cross-combo composes the same way: every pattern is
-- retained and applied. `[=~"a"]: int` matches `a` (`int & 1 = 1`); `[=~"b"]: string` matches
-- no field here. Oracle: `{[=~"a"]: int, [=~"b"]: string} & {a: 1, ...}` → cue `{a: 1}` (open).
theorem mergeStructN_patterns_tail_unifies :
    (meet
        (.struct [] .regularOpen none
          [(.stringRegex "a", .kind .int), (.stringRegex "b", .kind .string)])
        (.struct [⟨"a", .regular, .prim (.int 1)⟩] .defOpenViaTail (some .top) [])
      == .struct [⟨"a", .regular, .prim (.int 1)⟩] .defOpenViaTail (some .top)
          [(.stringRegex "a", .kind .int), (.stringRegex "b", .kind .string)]) = true := by
  native_decide

theorem mergeStructN_tail_patterns_unifies :
    (meet
        (.struct [⟨"a", .regular, .prim (.int 1)⟩] .defOpenViaTail (some .top) [])
        (.struct [] .regularOpen none
          [(.stringRegex "a", .kind .int), (.stringRegex "b", .kind .string)])
      == .struct [⟨"a", .regular, .prim (.int 1)⟩] .defOpenViaTail (some .top)
          [(.stringRegex "a", .kind .int), (.stringRegex "b", .kind .string)]) = true := by
  native_decide

-- Pattern VIOLATION in a cross-combo: `{[=~"a"]: int} & {a: "x", ...}` — the pattern matches
-- `a` but `int & "x"` bottoms, so the FIELD bottoms (struct survives, stays open). cue v0.16.1
-- errors on field `a` only (`conflicting values "x" and int`), not the whole struct.
theorem mergeStructN_pattern_tail_field_conflict :
    (meet
        (.struct [] .regularOpen none [(.stringRegex "a", .kind .int)])
        (.struct [⟨"a", .regular, .prim (.string "x")⟩] .defOpenViaTail (some .top) [])
      == .struct [⟨"a", .regular, .bottomWith [.fieldConstraint "a"]⟩] .defOpenViaTail (some .top)
          [(.stringRegex "a", .kind .int)]) = true := by
  native_decide

-- Compositional re-meet: a value ALREADY carrying both a tail and patterns (the B2.5 unify
-- output) met again with a tail-struct. Exercises the both-tails (`meet .top .top`) path AND
-- the patterns-retained-across-remeet behavior. Oracle: `({[=~"a"]: int} & {a: 5, ...}) &
-- {b: 9, ...}` → cue v0.16.1 `{a: 5, b: 9}` (open).
theorem mergeStructN_tail_patterns_remeet_tail :
    (meet
        (.struct [⟨"a", .regular, .prim (.int 5)⟩] .defOpenViaTail (some .top)
          [(.stringRegex "a", .kind .int)])
        (.struct [⟨"b", .regular, .prim (.int 9)⟩] .defOpenViaTail (some .top) [])
      == .struct [⟨"a", .regular, .prim (.int 5)⟩, ⟨"b", .regular, .prim (.int 9)⟩]
          .defOpenViaTail (some .top) [(.stringRegex "a", .kind .int)]) = true := by
  native_decide

/-! ## `StructOpenness.meet` (B2.1)

The openness lattice the B2.4 single meet arm will consume: closed dominates,
`defOpenViaTail` is preserved against any open, two regular opens stay open. -/

theorem openness_meet_closed_dominates :
    (StructOpenness.meet .defClosed .regularOpen == .defClosed
      && StructOpenness.meet .regularOpen .defClosed == .defClosed
      && StructOpenness.meet .defClosed .defOpenViaTail == .defClosed) = true := by
  native_decide

theorem openness_meet_tail_preserved :
    (StructOpenness.meet .defOpenViaTail .regularOpen == .defOpenViaTail
      && StructOpenness.meet .regularOpen .defOpenViaTail == .defOpenViaTail) = true := by
  native_decide

theorem openness_meet_open_idempotent :
    StructOpenness.meet .regularOpen .regularOpen == .regularOpen := by
  native_decide

/-! ## `StructOpenness.closeDefBody` (B2b)

The def-body openness derivation `normalizeDefinitionValueWithFuel` applies to a `structComp`
body: a no-`...` body (`regularOpen`) CLOSES, a `...` body (`defOpenViaTail`) stays open, and
`defClosed` is a fixed point. Replaces the legacy `open_ := hasTail` rule, pinned at the type
level. -/

theorem close_def_body_regular_closes :
    StructOpenness.closeDefBody .regularOpen == .defClosed := by
  native_decide

theorem close_def_body_tail_stays_open :
    StructOpenness.closeDefBody .defOpenViaTail == .defOpenViaTail := by
  native_decide

theorem close_def_body_closed_fixed_point :
    StructOpenness.closeDefBody .defClosed == .defClosed := by
  native_decide

/-- End-to-end pin on the ONE semantic site: `normalizeDefinitionValueWithFuel` closes a
    no-`...` `structComp` def body (`regularOpen → defClosed`) and leaves a `...` body open
    (`defOpenViaTail` fixed point). -/
theorem normalize_def_structComp_openness :
    (normalizeDefinitionValueWithFuel normalizeFuel (.structComp [] [] .regularOpen)
        == .structComp [] [] .defClosed
      && normalizeDefinitionValueWithFuel normalizeFuel (.structComp [] [] .defOpenViaTail)
        == .structComp [] [] .defOpenViaTail) = true := by
  native_decide

end Kue
