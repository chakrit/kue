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

## B2-TARGET known-incomplete meet arms (documented, NOT pinned)

`meetWithFuel` (`Lattice.lean`) is MISSING two struct cross-combinations: a `.structPattern`
or `.structPatterns` value meeting a `.structTail` value (in either order) has no explicit
arm and falls through to the `meetCore` default → `.bottom`, where `cue` unifies. Confirmed
against `cue` v0.16.1:

```
#P: {[string]: int}
#T: {a: 5, ...}
out: #P & #T        // cue → {a: 5}   ;  kue → _|_  (WRONG)
```

Per the A2 rule (never pin wrong behavior with a passing test) and because the Lean test
harness has no expected-fail / xfail marker (a `theorem` is an all-or-nothing build-time
check — pinning the correct RHS would turn the build red, pinning the wrong `.bottom` would
lock in the bug), these arms are documented HERE and in `plan.md`'s B2 entry rather than
given a passing wrong-behavior test. **B2 must add both arms** (`structPattern×structTail`,
`structPatterns×structTail`, both orders) and convert the correct cue value into a passing
pin. This is a Kue bug (Kue wrong, cue correct), so it lives in the plan as a fix-target —
NOT in `docs/reference/cue-divergences.md`, which is only for cases where cue is wrong and
Kue is right. -/

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

end Kue
