import Kue.Eval
import Kue.Format
import Kue.Manifest
import Kue.Resolve
import Kue.Runtime
import Kue.Tests.EvalTestHelpers

namespace Kue

-- Held-residual comprehension + MEET-RESID + RESID-MASK family. Carved out of
-- `TwoPassTests.lean` (test-org split, PB-2): a held `.structComp` residual (abstract
-- dynamic key/`if`/`for`) is HELD by the comprehension-body lift, SURVIVES a `meet` against
-- a struct, and dead residual disjunction arms are masked/pruned without over-holding a real
-- conflict. Soundness tripwires pinned adversarially.

-- MEET-RESID-1 + D#1d-RESIDUAL: a HELD `.structComp` residual (a comprehension whose dynamic
    -- key/`if`/`for` is non-concrete) is HELD by the comprehension-body lift (D#1d-RESIDUAL) and
    -- SURVIVES a `meet`/`&` against a struct (MEET-RESID-1), instead of being dropped to `{}` or
    -- bottomed. The soundness tripwires (conflict-MUST-still-bottom) are pinned ADVERSARIALLY — the
    -- gate's whole purpose is that over-holding (deferring a real conflict) never happens. All
    -- source-level (full parse→eval→meet→format), oracle-cross-checked vs cue v0.16.1.

-- D#1d-RESIDUAL: a comprehension BODY that is itself a held residual (abstract dynamic key) is
-- HELD, not dropped to `{}`. cue holds the block under eval (the `@d.i` label is the D#1b display
-- limit). HEAD dropped this to `a: {}`.
theorem residual_comprehension_body_held :
    evalSourceMatches
      "a: {for k in [string] {(k): 1}}\n"
      "a: {for k in [string] {(@1.0): 1}}" = true := by
  native_decide

-- MEET-RESID-1 WITNESS: the held residual SURVIVES `a & {x:2}` (re-resolved by the two-pass
-- `.conj` fold), carrying the merged `x:2` plus the still-deferred `for`. HEAD bottomed `b`.
theorem residual_survives_meet_with_struct :
    evalSourceMatches
      "a: {for k in [string] {(k): 1}}\nb: a & {x: 2}\n"
      "a: {for k in [string] {(@1.0): 1}}\nb: {x: 2, for k in [string] {(@1.0): 1}}" = true := by
  native_decide

-- ★ SOUNDNESS TRIPWIRE 1 — a real FIELD CONFLICT inside the residual STILL bottoms (`x:1 & x:2`).
-- The merged field surfaces `x: _|_` (the kue rendering convention, identical to a plain
-- `{x:1} & {x:2}` control); the defer NEVER masks it. cue: `b.x: conflicting values 1 and 2`.
theorem residual_meet_field_conflict_bottoms :
    evalSourceMatches
      "a: {x: 1, for k in [string] {(k): 1}}\nb: a & {x: 2}\n"
      "a: {x: 1, for k in [string] {(@1.0): 1}}\nb: {x: _|_, for k in [string] {(@1.0): 1}}"
        = true := by
  native_decide

-- ★ SOUNDNESS TRIPWIRE 2 — a residual met with a SCALAR is a struct-vs-nonstruct type error and
-- MUST bottom wholesale (NOT hold). cue: `mismatched types int and struct`.
theorem residual_meet_scalar_bottoms :
    evalSourceMatches
      "a: {for k in [string] {(k): 1}}\nb: a & 5\n"
      "a: {for k in [string] {(@1.0): 1}}\nb: _|_" = true := by
  native_decide

-- ★ SOUNDNESS TRIPWIRE 3 — the field-conflict residual export ERRORS (no concrete value escapes);
-- pins that the inline `x: _|_` is a genuine bottom, not a spurious survivable value.
theorem residual_meet_field_conflict_export_bottoms :
    exportJsonBottoms "a: {x: 1, for k in [string] {(k): 1}}\nb: a & {x: 2}\n" = true := by
  native_decide

-- A COMPATIBLE field merges and the comp is still held (no spurious conflict on equal values).
theorem residual_meet_compatible_field_held :
    evalSourceMatches
      "a: {x: 1, for k in [string] {(k): 1}}\nb: a & {x: 1, y: 2}\n"
      "a: {x: 1, for k in [string] {(@1.0): 1}}\nb: {x: 1, y: 2, for k in [string] {(@1.0): 1}}"
        = true := by
  native_decide

-- A concrete-key comprehension still RESOLVES (no over-hold): the residual lift fires ONLY on a
-- genuinely-undecidable body, never freezing a resolvable one.
theorem concrete_key_comprehension_still_resolves :
    evalSourceMatches
      "a: {for k in [\"k\"] {(k): 1}}\nb: a & {x: 2}\n"
      "a: {k: 1}\nb: {k: 1, x: 2}" = true := by
  native_decide

-- ### MEET-RESID-1 audit — MASKED-BOTTOM regression guard (Phase-A `RESID-MASK-1`).
--
-- The MEET-RESID-1 soundness argument claimed "a `.structComp` never holds a conflict
-- (unrepresentable)". That is FALSE: `mergeFieldValueWith` stores a field conflict as a PRESENT
-- `.bottomWith` field VALUE (not a top-level `.bottom`), and MEET-RESID-1 / the eager
-- `withDeferredComprehensions` re-wrap such a struct as `.structComp [x:_|_] …` (see Tripwire 1
-- above, which pins exactly that inline `x: _|_`). The real invariant is weaker: a held conflict is
-- fine PROVIDED every bottom-consumer surfaces it. `containsBottom` (the `liveAlternatives`
-- disjunction-prune predicate) did NOT descend `.structComp` — so a residual-with-inner-conflict
-- surviving as a disjunction ARM was not pruned, and a DEAD arm survived → a wrong value (a spurious
-- unresolved `.disj`, or a stuck selector, where cue resolves to the live arm). Fixed by descending
-- `.structComp`'s RESOLVED fields in `containsBottom`. These pins are the destroy-test witnesses;
-- each is oracle-cross-checked vs cue v0.16.1 (cue prunes the dead arm).

-- ★ HEADLINE (the masked bottom): a residual-meet conflict as the NON-default arm of a default
-- disjunction. cue prunes the dead arm → `pick: {y:9}`. Pre-fix kue HELD the dead arm
-- (`*{y:9} | {x:_|_, for…}`) — `containsBottom` was blind to the `.structComp`-wrapped `x:_|_`.
theorem resid_mask_disj_default_prunes_dead_residual_arm :
    evalSourceMatches
      "a: {x: 1, for k in [string] {(k): 1}}\npick: *{y: 9} | (a & {x: 2})\n"
      "a: {x: 1, for k in [string] {(@1.0): 1}}\npick: {y: 9}" = true := by
  native_decide

-- (NOTE — RESID-MASK-2, the eager-prune-vs-hold POLICY that this masking fix exposed, was
-- RESOLVED 2026-06-21 as a cue-spec-gap, not a divergence: see the "RESID-MASK-2" section at
-- the end of this file. The earlier framing here — "a NON-default residual-conflict arm survives
-- as a spurious arm" — was FALSIFIED on current HEAD: kue EAGERLY prunes the definitely-bottom
-- arm and commits to the (possibly still-incomplete) survivor, which is the MORE precise lattice
-- move and spec-consonant with "eliminate bottom alternatives". The soundness of that eager prune
-- — it fires only on a *materialized/terminal* bottom, never on a merely-incomplete arm — is
-- pinned adversarially in that section. The plain-arm control below shows the prune primitive
-- itself is correct.)

-- CONTROL (no residual): the SAME disjunction shape with a plain `{x:1}&{x:2}` dead arm was ALWAYS
-- pruned correctly (a plain `.struct` arm — `containsBottom` saw its `x:_|_`). Pins that the bug
-- was SOLELY the `.structComp` wrapper hiding the inner bottom, and the fix matches this baseline.
theorem resid_mask_control_plain_conflict_arm_pruned :
    evalSourceMatches
      "pick: *{y: 9} | ({x: 1} & {x: 2})\n"
      "pick: {y: 9}" = true := by
  native_decide

-- EVAL CONSTRUCT-SITE (not via meet): `withDeferredComprehensions` itself builds a residual with an
-- inner conflict (`x:1, x:2` static + a held `for`). As a disj arm it must ALSO be pruned — the
-- hole was never meet-specific. cue prunes → `pick: {y:9}`.
theorem resid_mask_eval_site_residual_arm_pruned :
    evalSourceMatches
      "a: {x: 1, x: 2, for k in [string] {(k): 1}}\npick: *{y: 9} | a\n"
      "a: {x: _|_, for k in [string] {(@1.0): 1}}\npick: {y: 9}" = true := by
  native_decide

-- RESIDUAL & RESIDUAL: two held comprehensions whose static fields conflict, as a disj arm — the
-- union-of-comps residual `{x:_|_, for…, for…}` is still pruned. cue → `pick: {y:9}`.
theorem resid_mask_residual_meet_residual_arm_pruned :
    evalSourceMatches
      "a: {x: 1, for k in [string] {(k): 1}}\nb: {x: 2, for j in [string] {(j): 2}}\npick: *{y: 9} | (a & b)\n"
      "a: {x: 1, for k in [string] {(@1.0): 1}}\nb: {x: 2, for j in [string] {(@1.0): 2}}\npick: {y: 9}"
        = true := by
  native_decide

-- DEEP/NESTED conflict inside the residual (A#6 depth × residual boundary): the conflict is one
-- level down (`p: {q: _|_}`). `containsBottom` descends the residual fields, then recurses the inner
-- `.struct` to the nested bottom. cue prunes → `pick: {y:9}`.
theorem resid_mask_nested_conflict_in_residual_arm_pruned :
    evalSourceMatches
      "a: {p: {q: 1}, for k in [string] {(k): 1}}\npick: *{y: 9} | (a & {p: {q: 2}})\n"
      "a: {p: {q: 1}, for k in [string] {(@1.0): 1}}\npick: {y: 9}" = true := by
  native_decide

-- NO OVER-PRUNE (the converse guard): a CONFLICT-FREE residual as the non-default arm must SURVIVE
-- (it is a genuinely-held value, not a dead arm). The fix descends only into the resolved fields, so
-- a residual whose fields carry no bottom stays live and the disjunction remains a real 2-arm value.
-- cue keeps both arms ambiguous here; `exportJsonBottoms` witnesses kue does NOT collapse to one.
theorem resid_mask_no_over_prune_clean_residual_survives :
    exportJsonBottoms
      "a: {for k in [string] {(k): 1}}\npick: {y: 9} | a\n" = true := by
  native_decide


-- ### RESID-MASK-2 — eager-prune-of-definitely-bottom-arm POLICY (resolved as a cue-spec-gap).
--
-- The RESID-MASK-1 fix (`containsBottom` descends `.structComp` resolved fields) made
-- `liveAlternatives` prune a disjunction arm whose held residual carries a TERMINAL inline conflict
-- — EVEN WHEN the surviving arm is itself still incomplete. cue is conservative here: it HOLDS the
-- whole disjunction unresolved until a survivor concretizes (`export` → `N errors in empty
-- disjunction`). kue is strictly MORE precise.
--
-- SOUNDNESS (verified adversarially, 2026-06-21): the prune fires ONLY on a *definitely/terminal*
-- bottom — a `.bottom`/`.bottomWith` node that has already MATERIALIZED from a concrete conflict
-- (`x:1 & x:2`, concrete-vs-bound `x:1 & x:>5`, disjoint-bound `x:>5 & x:<3`) and can never
-- un-bottom under later refinement. It NEVER fires on a merely-incomplete arm (one bottom NOW only
-- because an abstract operand has not resolved): such an arm carries no bottom node, so
-- `containsBottom` is false and the arm survives. The two are not the same, and the don't-prune
-- cases below pin the distinction — an unsoundness would be pruning an arm that a later resolution
-- could make viable, and the adversarial pins demonstrate kue does NOT.
--
-- SPEC BASIS: the CUE spec's disjunction rule mandates *"eliminate bottom alternatives"* and treats
-- `_|_` as the identity for `|`; eager elimination of a definitely-bottom arm is therefore spec-
-- consonant and the precise/total lattice move. The spec does NOT pin the *timing* (it also says
-- "evaluation can retain unresolved disjunctions"), so cue's hold is not a violation — only less
-- precise. Recorded in `docs/reference/cue-spec-gaps.md` (kue MORE precise; not a divergence).
-- These pins LOCK kue's eager-prune so it cannot regress to cue's hold.

-- ★ WITNESS (the spec-gap behavior PINNED): BOTH arms residual; arm 1 is a TERMINAL `x:1 & x:2`
-- conflict (the held `for` dyn-field can only add string-keyed fields, never touch static `x`, so
-- the conflict is terminal). kue prunes arm 1 and commits to the still-incomplete survivor arm 2.
-- cue HOLDS both (`export` → `2 errors in empty disjunction`). kue MORE precise; locked here.
theorem resid_mask2_witness_eager_prune_commits_to_incomplete_survivor :
    evalSourceMatches
      "a: {for k in [string] {(k): 1}, x: 1}\nout: (a & {x: 2}) | (a & {x: 1, ok: true})\n"
      "a: {x: 1, for k in [string] {(@1.0): 1}}\nout: {x: 1, ok: true, for k in [string] {(@1.0): 1}}"
        = true := by
  native_decide

-- ★ SOUNDNESS — DON'T-PRUNE-INCOMPLETE (the adversarial core). arm 1's `a.x` is abstract `int`, so
-- `a & {x:2}` is `{x:2,for…}` — NOT a bottom (no materialized conflict). kue must NOT prune it: it
-- could become viable. Both arms SURVIVE as a real 2-arm disjunction. A regression that pruned on
-- "currently-incomplete-and-not-yet-concrete" rather than "definitely-bottom" would drop arm 1.
theorem resid_mask2_sound_abstract_operand_arm_not_pruned :
    evalSourceMatches
      "a: {x: int, for k in [string] {(k): 1}}\nout: (a & {x: 2}) | (a & {x: 3, ok: true})\n"
      "a: {x: int, for k in [string] {(@1.0): 1}}\nout: {x: 2, for k in [string] {(@1.0): 1}} | {x: 3, ok: true, for k in [string] {(@1.0): 1}}"
        = true := by
  native_decide

-- SOUNDNESS — the could-become-viable arm WINS after narrowing. The same disjunction, then met
-- with `{x:2}`: arm 1 (`x:2`, viable) survives, arm 2 (`x:3 & x:2` = `_|_`) dies. kue commits to
-- arm 1 — the genuinely-correct survivor. Proves the abstract arm 1 was NOT prematurely pruned and
-- that the eager evaluation reaches the right lattice point (the value a later meet selects).
theorem resid_mask2_sound_incomplete_arm_resolves_correctly_after_narrowing :
    evalSourceMatches
      "a: {x: int, for k in [string] {(k): 1}}\nout: ((a & {x: 2}) | (a & {x: 3, ok: true})) & {x: 2}\n"
      "a: {x: int, for k in [string] {(@1.0): 1}}\nout: {x: 2, for k in [string] {(@1.0): 1}}"
        = true := by
  native_decide

-- SOUNDNESS — both arms incomplete, NO conflict (differ only in non-conflicting `y`/`z`). Neither
-- arm is bottom, so the held `for` comprehension is NOT frozen into a bottom and pruned: both
-- survive. Pins that incompleteness alone never triggers a prune (no over-prune on residuals).
theorem resid_mask2_sound_both_incomplete_no_conflict_both_survive :
    evalSourceMatches
      "a: {x: 1, for k in [string] {(k): 1}}\nout: (a & {y: 2}) | (a & {z: 3})\n"
      "a: {x: 1, for k in [string] {(@1.0): 1}}\nout: {x: 1, y: 2, for k in [string] {(@1.0): 1}} | {x: 1, z: 3, for k in [string] {(@1.0): 1}}"
        = true := by
  native_decide

-- SOUNDNESS — bound-narrowing convergence (no residual): `({x:>5} | {x:<0,ok}) & {x:7}`. arm 1
-- (`>5 & 7` = 7, viable) wins; arm 2 (`<0 & 7` = `_|_`) is pruned. cue AGREES exactly (`{x:7}`).
-- The `>5` arm was NOT prematurely pruned while abstract — pinned that the prune waits for a
-- materialized bottom and that kue and cue converge on this concrete-narrowing shape.
theorem resid_mask2_sound_bound_arm_survives_until_concrete_conflict :
    evalSourceMatches
      "out: ({x: >5} | {x: <0, ok: true}) & {x: 7}\n"
      "out: {x: 7}" = true := by
  native_decide

-- PRECISION — terminal-conflict residual arm | concrete-COMPLETE arm. kue prunes the dead residual
-- and yields the clean concrete survivor `{plain:5}`; cue ERRORS entirely (`key value of dynamic
-- field must be concrete`) — it never prunes the dead arm. The starkest spec-gap witness: kue
-- exports a value where cue fails. Locks the eager prune against regression to cue's hold.
theorem resid_mask2_precision_terminal_residual_arm_pruned_for_concrete_survivor :
    evalSourceMatches
      "a: {x: 1, for k in [string] {(k): 1}}\nout: (a & {x: 2}) | {plain: 5}\n"
      "a: {x: 1, for k in [string] {(@1.0): 1}}\nout: {plain: 5}" = true := by
  native_decide

-- REGRESSION — `_|_`-identity for `|`: `_|_ | X` collapses to X for concrete X (the spec rule the
-- eager prune rests on). A bare bottom arm and a terminal-conflict arm both shed cleanly.
theorem resid_mask2_bottom_identity_collapses_to_concrete_arm :
    exportJsonMatches
      "out: (_|_) | {a: 1, b: 2}\n"
      "{\n    \"out\": {\n        \"a\": 1,\n        \"b\": 2\n    }\n}\n" = true := by
  native_decide

theorem resid_mask2_terminal_conflict_arm_sheds_for_concrete_survivor :
    exportJsonMatches
      "out: ({x: 1} & {x: 2}) | {ok: true}\n"
      "{\n    \"out\": {\n        \"ok\": true\n    }\n}\n" = true := by
  native_decide

-- COVERAGE TRIPWIRE (test-health). Anchors the LAST theorem of every section; a swallowed
-- section turns its anchor into an unknown identifier and `#check` fails to elaborate.
#check @concrete_key_comprehension_still_resolves             -- MEET-RESID-1
#check @resid_mask_no_over_prune_clean_residual_survives      -- RESID-MASK-1
#check @resid_mask2_terminal_conflict_arm_sheds_for_concrete_survivor -- RESID-MASK-2

end Kue
