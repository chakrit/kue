import Kue.Eval
import Kue.Format
import Kue.Manifest
import Kue.Resolve
import Kue.Runtime
import Kue.Tests.EvalTestHelpers

namespace Kue

/-! ### Frame-id sharing (perf B) — canonical frame identity + its soundness boundary.

The perf win: structurally-identical re-pushes under the same parent id-stack reuse a frame
id, so the downstream `EvalKey` (keyed on `env.ids`) hits the memo instead of re-deriving an
identical subtree. The deep-inline shape `{a: <body>, b: <body>}` (each level inlines the same
nested struct TWICE) is the worst case: pre-sharing each inline copy keys apart → 2^depth
re-pushes; shared, the second copy reuses the first's id → linear. The soundness boundary is
pinned right after: id reuse must happen ONLY for genuinely-identical evaluations. -/

/-- A depth-`n` deep-inline value: `root: {a: B, b: B}` where `B` recurses to depth `n`. The
    two slots `a`/`b` carry IDENTICAL inline bodies, so frame-id sharing collapses the second
    push into the first. -/
def deepInlineValue : Nat -> Value
  | 0 => .struct [⟨"v", .regular, .prim (.string "x")⟩] .regularOpen none []
  | n + 1 =>
      let inner := deepInlineValue n
      .struct [⟨"a", .regular, inner⟩, ⟨"b", .regular, inner⟩] .regularOpen none []

def deepInlineRoot (n : Nat) : Value :=
  .struct [⟨"root", .regular, deepInlineValue n⟩] .regularOpen none []

-- PERF: with frame-id sharing the deep-inline eval count is LINEAR in depth (`2·depth + 2`),
-- not exponential. At depth 8 this is 18 core evals; WITHOUT sharing it is 767 (a 42× gap), so
-- any regression that defeats sharing — or any unsound widening that stops the memo hitting —
-- blows this pin far past 18. This is the deterministic exponential→linear witness.
theorem eval_deep_inline_sharing_is_linear :
    evalStructRefsCalls (deepInlineRoot 8) = 18 := by
  native_decide

theorem eval_deep_inline_count_depth4 :
    evalStructRefsCalls (deepInlineRoot 4) = 10 := by
  native_decide

theorem eval_deep_inline_count_depth6 :
    evalStructRefsCalls (deepInlineRoot 6) = 14 := by
  native_decide

-- PERF + VALUE: the shared eval still produces the correct deeply-nested value (sharing is a
-- pure perf change — the value is byte-identical to what the unshared eval would give).
theorem eval_deep_inline_value_correct :
    formatTopLevel (resolveAndEval (deepInlineRoot 2))
      = "root: {a: {a: {v: \"x\"}, b: {v: \"x\"}}, b: {a: {v: \"x\"}, b: {v: \"x\"}}}" := by
  native_decide

/-! ### Pass-2 selective re-eval (perf, audit PART B). The embedding-`Self` two-pass re-evaluated
    EVERY static field against the augmented frame, so a field that never reads `Self.<embedded-
    label>` was redundantly recomputed (a fresh frame id → no Pass-1 cache hit). The fix re-evaluates
    ONLY the fields that depend (directly or transitively via a sibling `Self.<L>` read) on an
    embedded label, reusing Pass-1 values for the rest — byte-identical (correctness gate: zero
    fixture drift), eval-count reduced. -/

-- The audit's shape: an OPEN `{embed; …; ...}` def whose embed supplies `et`, with ONE field
-- `dep: Self.et` (depends on the embedded label) and N unrelated fields `u_i: Self.base + i`
-- (depend only on the static sibling `base`). The two-pass must re-eval ONLY `dep`.
def selPassSelfF : Field := ⟨"#self", .definition, .thisStruct⟩
def selPassBaseF : Field := ⟨"base", .regular, .prim (.int 100)⟩
def selPassDepF : Field := ⟨"dep", .regular, .selector (.refId ⟨0, 0⟩) "et"⟩
def selPassUnrelated (n : Nat) : List Field :=
  (List.range n).map fun i =>
    (⟨s!"u{i}", .regular, .binary .add (.selector (.refId ⟨0, 0⟩) "base") (.prim (.int (Int.ofNat i)))⟩ : Field)
def selPassBody (n : Nat) : Value :=
  .structComp ([selPassSelfF, selPassBaseF, selPassDepF] ++ selPassUnrelated n)
    [.struct [⟨"et", .regular, .prim (.string "z")⟩] .defClosed none []] .defOpenViaTail

-- SELECTION: the Pass-2 re-eval set is EXACTLY the dependent field (`dep` at canonical index 2),
-- regardless of how many unrelated fields surround it — the redundant recompute is excluded.
theorem selpass_reevaluates_only_dependent_field :
    (embeddedSelfPassFieldIndices
        (canonicalizeFields ([selPassSelfF, selPassBaseF, selPassDepF] ++ selPassUnrelated 6)) ["et"]
      == [2]) = true := by
  native_decide

-- A field reading `Self.<L>` for a STATIC sibling `L` (not an embedded label) is NOT selected —
-- its value is frame-id-independent under the Pass-2 augment, so reusing Pass-1 is byte-identical.
theorem selpass_skips_static_sibling_reader :
    ((embeddedSelfPassFieldIndices
        (canonicalizeFields ([selPassSelfF, selPassBaseF, selPassDepF] ++ selPassUnrelated 3)) ["et"]).contains 3
      == false) = true := by
  native_decide

-- EVAL COUNT is LINEAR with the SMALL slope (+5/unrelated-field), witnessing the redundant Pass-2
-- recompute is gone: pre-fix the slope was +10/field (every field re-evaluated in Pass 2). A
-- regression that re-broadened the re-eval set blows these past the asserted counts.
theorem selpass_eval_count_n2 :
    evalStructRefsCalls (resolveStructRefs (selPassBody 2)) = 21 := by
  native_decide

theorem selpass_eval_count_n6 :
    evalStructRefsCalls (resolveStructRefs (selPassBody 6)) = 41 := by
  native_decide

-- VALUE: the selective re-eval still resolves `Self.et` correctly (`dep: "z"`) AND the unrelated
-- fields keep their Pass-1 values (`u0: 100`, `u1: 101`) — byte-identical to a full re-eval.
theorem selpass_value_correct :
    formatTopLevel (resolveAndEval (selPassBody 2))
      = "#self: @self\nbase: 100\ndep: \"z\"\nu0: 100\nu1: 101\net: \"z\"" := by
  native_decide

/-- Push two frames and report `(id1, id2)`. The soundness boundary lives in whether these
    ids coincide: they MUST coincide only when the two pushes are the genuinely-same evaluation
    (same fields AND same parent id-stack). -/
def twoPushIds (fields1 : List Field) (env1 : Env) (fields2 : List Field) (env2 : Env) :
    Nat × Nat :=
  runEval do
    let e1 <- pushFrame fields1 env1
    let e2 <- pushFrame fields2 env2
    pure (e1.head!.fst, e2.head!.fst)

-- SOUNDNESS PIN 1: structurally-IDENTICAL re-pushes under the SAME parent SHARE an id (the
-- whole point — this is what makes the memo hit).
theorem frame_share_identical :
    (let f := [(⟨"x", .regular, .prim (.int 1)⟩ : Field)]
     let ids := twoPushIds f [] f []
     ids.fst == ids.snd)
      = true := by
  native_decide

-- SOUNDNESS PIN 2: structurally-DIFFERENT re-pushes (different field value) do NOT share — a
-- too-coarse key would corrupt by returning one struct's memo for the other.
theorem frame_no_share_different_fields :
    (let f1 := [(⟨"x", .regular, .prim (.int 1)⟩ : Field)]
     let f2 := [(⟨"x", .regular, .prim (.int 2)⟩ : Field)]
     let ids := twoPushIds f1 [] f2 []
     ids.fst == ids.snd)
      = false := by
  native_decide

-- SOUNDNESS PIN 3: SAME fields but DIFFERENT parent id-stack do NOT share — depth>0 refs in
-- the body walk different outer frames, so the two evaluations differ. The parent id-stack is
-- load-bearing in the sharing key.
theorem frame_no_share_different_parent :
    (let f := [(⟨"x", .regular, .prim (.int 1)⟩ : Field)]
     let ids := twoPushIds f [(7, [])] f [(9, [])]
     ids.fst == ids.snd)
      = false := by
  native_decide

-- SOUNDNESS PIN 4 (constraint b): a closed/definition field and a regular field of the "same"
-- label differ AS FIELDS at the push site (the force path closes a def body via normalization,
-- changing the field class/values), so they get DISTINCT frame ids — an eager(open)/forced
-- (closed) eval of the same import alias can never falsely collide. `.definition` vs `.regular`
-- on the same label is the closed-vs-open stand-in; they must not share.
theorem frame_no_share_closed_vs_open :
    (let f1 := [(⟨"x", .definition, .prim (.int 1)⟩ : Field)]
     let f2 := [(⟨"x", .regular, .prim (.int 1)⟩ : Field)]
     let ids := twoPushIds f1 [] f2 []
     ids.fst == ids.snd)
      = false := by
  native_decide

/-! ### Fuel-saturation caching — the fuel-multiplication fix + its soundness boundary.

A result whose entire (transitive) eval never hit a `fuel = 0` base nor a cycle `.top` is
SATURATED: fuel-insensitive, identical at every higher fuel. Such results are cached FUEL-FREE
(`satCache`), so a converged value evaluated at fuel f and re-requested at any fuel ≥ f is served
from one cache entry — collapsing the per-fuel-level re-derivation (cert-manager: ~84 levels → 1).
TRUNCATED results (the 263 fuel-truncation cases) stay fuel-keyed and are NEVER served across fuel.

Classification is by bracketing the monotonic `truncCount` in the single cached wrapper, so the
hole the design flagged (an arm forgetting to propagate `truncated`) cannot occur: no arm
classifies. The pins below witness both the PERF win (a re-eval at higher fuel adds ZERO core
evals) and the SOUNDNESS boundary (a fuel-differing value is NOT served its low-fuel truncated
form at high fuel). -/

/-- Evaluate `value` at `f1` then at `f2` in the SAME `EvalM` run (shared `satCache`/`cache`),
    reporting `(v1, v2, callsAfterFirst, callsTotal)`. The second eval's added core evals are
    `callsTotal - callsAfterFirst`: ZERO iff `f2`'s request was served from the fuel-free
    `satCache` (the value saturated at `f1`). The env is `[]` (no enclosing frame). -/
def evalTwiceAt (f1 f2 : Nat) (value : Value) : Value × Value × Nat × Nat :=
  let action : EvalM (Value × Value × Nat × Nat) := do
    let v1 <- evalValueWithFuel f1 [] [] value
    let callsAfterFirst := (<- get).evalCalls
    let v2 <- evalValueWithFuel f2 [] [] value
    let callsTotal := (<- get).evalCalls
    pure (v1, v2, callsAfterFirst, callsTotal)
  (action.run { cache := ∅, nextFrameId := 0 }).fst

/-- `value` evaluated standalone at `fuel` (fresh state) — the GROUND TRUTH a cross-fuel reuse
    must match. -/
def evalOnceAt (fuel : Nat) (value : Value) : Value :=
  (evalValueWithFuel fuel [] [] value |>.run { cache := ∅, nextFrameId := 0 }).fst

/-- A SELF-REFERENTIAL value that GROWS with fuel — the synthetic 263-class. `{a: {b: <outer a>}}`:
    field `b` references the enclosing `a` (depth 1), so each fuel level expands one more `{b: …}`
    nesting before bottoming on the unresolved binding. `@fuel 3 → {a:{b:{b:@1.0}}}`, `@fuel 5 →
    {a:{b:{b:{b:@1.0}}}}`, … — the SAME `(env,visited,value)` yields DIFFERENT values at different
    fuel. This is exactly the case that MUST stay fuel-keyed (never served fuel-free). -/
def satTruncValue : Value :=
  .struct [⟨"a", .regular, .struct [⟨"b", .regular, .refId ⟨1, 0⟩⟩] .regularOpen none []⟩] .regularOpen none []

-- PERF + SOUNDNESS: a CONVERGING value (`deepInlineValue 2`, literal nesting, no fuel-sensitive
-- refs) SATURATES at fuel 6 (its fields never reach fuel 0). A re-request at fuel 20 in the same
-- run hits the fuel-free `satCache` and adds ZERO core evals — the fuel-multiplication collapse.
-- AND the served value equals the fresh fuel-20 eval (the reuse is correct, not just cheap). The
-- cert-manager-shaped win: converge low, was re-derived across ~84 fuel levels → now one.
theorem sat_converged_reused_across_fuel_is_free_and_correct :
    (let r := evalTwiceAt 6 20 (deepInlineValue 2)
     -- second eval added zero core evals (served from satCache)…
     (r.snd.snd.snd - r.snd.snd.fst == 0)
       -- …and the cross-fuel-reused value equals the ground-truth fuel-20 eval…
       && (r.snd.fst == evalOnceAt 20 (deepInlineValue 2))
       -- …and equals the fuel-6 value (it was already converged).
       && (r.fst == r.snd.fst))
      = true := by
  native_decide

-- SOUNDNESS (the 263-class — THE critical pin): `satTruncValue` TRUNCATES at fuel 3 (bottoms on
-- the unresolved self-binding) but EXPANDS FURTHER at fuel 20. Evaluating at fuel 3 first must
-- NOT poison the fuel-20 request: the fuel-20 value must equal the fresh fuel-20 eval (the deeper
-- expansion), NOT the fuel-3 stump. A truncated result wrongly keyed fuel-free would FAIL this —
-- it would serve the fuel-3 stump at fuel 20. This is the corruption the slice exists to prevent.
theorem sat_truncated_not_served_across_fuel :
    (let r := evalTwiceAt 3 20 satTruncValue
     -- the fuel-20 reuse equals the GROUND-TRUTH fuel-20 eval (deeper), not the fuel-3 stump…
     (r.snd.fst == evalOnceAt 20 satTruncValue)
       -- …and the two fuels genuinely differ (so this is a real cross-fuel hazard, not a no-op).
       && (r.fst != r.snd.fst))
      = true := by
  native_decide

-- SOUNDNESS: the fuel-3 eval really IS truncated (differs from the fuel-20 expansion) — pins that
-- the previous test's hazard is genuine, i.e. `satTruncValue` is fuel-sensitive at fuel 3.
theorem sat_low_fuel_truncates :
    (evalOnceAt 3 satTruncValue != evalOnceAt 20 satTruncValue) = true := by
  native_decide

-- SOUNDNESS: a truncated value re-evaluated at the SAME low fuel is served from the fuel-keyed
-- `cache` (cheap, byte-identical), keeping the fuel axis honest for the 263-class. Second eval at
-- the SAME fuel 3 adds zero core evals (fuel-keyed `cache` hit, not a fuel-free hit).
theorem sat_truncated_same_fuel_is_cached :
    (let r := evalTwiceAt 3 3 satTruncValue
     (r.snd.snd.snd - r.snd.snd.fst == 0) && (r.fst == r.snd.fst))
      = true := by
  native_decide

/-- THE THIRD-TRUNCATION-SOURCE pin (audit 2026-06-18 #6). The two `evalValueCoreWithFuel`
    arms (`fuel=0` base, cycle `.top`) are NOT the only fuel-truncation sources: the comprehension
    /embedding-expansion helpers (`expandClausesWithFuel`, `expandComprehensionWithFuel`,
    `evalEmbeddingFieldsWithFuel`, `meetEmbeddingsWithFuel`) each have a fuel=0 arm that DROPS
    fields/meets when fuel runs out mid-expansion. The original saturation slice did not bump
    `truncCount` there, so a comprehension truncated at low fuel was misclassified SATURATED and
    cached fuel-free → a higher-fuel request was served the smaller (wrong) struct. The audit fix
    bumps `truncCount` at all four helper arms. This `.structComp`-wrapped `if true {x:1}` expands
    to `{x:1}` at high fuel but DROPS `x` at low fuel — the exact shape that corrupted. -/
def satCompTruncValue : Value :=
  .structComp []
    [.comprehension [.guard (.prim (.bool true))]
      (.struct [⟨"x", .regular, .prim (.int 1)⟩] .regularOpen none [])]
    .regularOpen

-- SOUNDNESS (third-truncation-source corruption): the comprehension truncates at fuel 2
-- (`{}`) but expands at fuel 20 (`{x:1}`). Evaluating at fuel 2 first must NOT poison the fuel-20
-- request via the fuel-free `satCache`: the fuel-20 reuse must equal the fresh fuel-20 eval (the
-- expansion), not the fuel-2 stump. Pre-fix this FAILED (served the `{}` stump at fuel 20).
theorem sat_comprehension_truncation_not_served_across_fuel :
    (let r := evalTwiceAt 2 20 satCompTruncValue
     (r.snd.fst == evalOnceAt 20 satCompTruncValue)
       && (r.fst != r.snd.fst))
      = true := by
  native_decide

-- SOUNDNESS: the fuel-2 comprehension eval really IS truncated (drops `x`) vs fuel 20 — pins
-- that the hazard above is genuine, i.e. the helper fuel-exhaustion is fuel-sensitive.
theorem sat_comprehension_low_fuel_truncates :
    (evalOnceAt 2 satCompTruncValue != evalOnceAt 20 satCompTruncValue) = true := by
  native_decide

/-- THE LIST-COMPREHENSION fuel-truncation source (slice `list-comprehension-parse-eval`). The
    new `expandListClausesWithFuel` has the SAME `fuel=0` arm as its struct sibling: it DROPS the
    yielded elements when fuel runs out mid-expansion. It MUST bump `truncCount` there, or a
    list-comp truncated at low fuel is misclassified SATURATED and cached fuel-free → a higher-fuel
    request is served the smaller (wrong) list. This `[for x in [1,2,3] {9}]` yields `[]` at fuel 1
    (truncated) but `[9,9,9]` at fuel 20 (full) — the exact hazard shape. -/
def satListCompTruncValue : Value :=
  .list [.listComprehension
    [.forIn none "x" (.list [.prim (.int 1), .prim (.int 2), .prim (.int 3)])]
    (.structComp [] [.prim (.int 9)] .regularOpen)]

-- SOUNDNESS (list-comp truncation-source corruption): truncates at fuel 1 (`[]`) but expands at
-- fuel 20 (`[9,9,9]`). Evaluating at fuel 1 first must NOT poison the fuel-20 request via the
-- fuel-free `satCache`: the fuel-20 reuse must equal the fresh fuel-20 eval, not the fuel-1 stump.
theorem sat_list_comprehension_truncation_not_served_across_fuel :
    (let r := evalTwiceAt 1 20 satListCompTruncValue
     (r.snd.fst == evalOnceAt 20 satListCompTruncValue)
       && (r.fst != r.snd.fst))
      = true := by
  native_decide

-- SOUNDNESS: the fuel-1 list-comp eval really IS truncated (`[]`) vs fuel 20 (`[9,9,9]`) — pins
-- that the hazard above is genuine, i.e. the new helper's fuel-exhaustion is fuel-sensitive.
theorem sat_list_comprehension_low_fuel_truncates :
    (evalOnceAt 1 satListCompTruncValue != evalOnceAt 20 satListCompTruncValue) = true := by
  native_decide

/-! ### perf-B memo false-share pins (audit 2026-06-18 #5, owed `perfb-soundness-pins`).

The perf-B audit cleared the frame-share + force memos as SOUND but flagged that the 4 existing
pins test `pushFrame` ID COINCIDENCE, not the resulting VALUE — a regression could corrupt a value
while still satisfying a coincidence pin. These are the owed E2E *value* pins: a memo false-share
would change the EXPORTED value and trip them. Folded into the fuel-saturation slice so its new
`Saturation` threading through the SAME keys inherits real false-share coverage. -/

-- PERF-B PIN 1 (force-memo `useOperands` keying, E2E value — audit finding #1). `#D & {x:1}`
-- forced at two sites must SHARE (same value `1`) while `#D & {x:2}` stays distinct (`2`) — the
-- force memo keys on `useOperands`, so a key that dropped it would serve `p`'s `1` for `q`'s `2`
-- (or vice versa) and trip this. Exercises the load-bearing real-app memo through real values.
theorem perfb_force_memo_narrows_by_useOperands :
    evalSourceMatches
        "#D: {x: int}\np: (#D & {x: 1}).x\nq: (#D & {x: 1}).x\nr: (#D & {x: 2}).x\n"
        "#D: {x: int}\np: 1\nq: 1\nr: 2" = true := by
  native_decide

-- PERF-B PIN 2 (frame-sharing parentIds, E2E value — audit finding #2). Identical inner body
-- `{r: outer}` under DIFFERENT parents (`outer: 1` vs `outer: 2`) must resolve to DIFFERENT
-- values (`r: 1` vs `r: 2`). A parentIds regression that shared the inner frame across parents
-- would cross-resolve and corrupt — this asserts the exported struct, so the corruption trips it.
theorem perfb_frame_share_parent_disambiguates_value :
    evalSourceMatches
        "a: {outer: 1, inner: {r: outer}}\nb: {outer: 2, inner: {r: outer}}\n"
        "a: {outer: 1, inner: {r: 1}}\nb: {outer: 2, inner: {r: 2}}" = true := by
  native_decide

-- PERF-B PIN 3 (closed-vs-open through REAL normalization, E2E value — audit finding #3, replacing
-- the `.definition`-vs-`.regular` stand-in). `#C & {x:1}` (closed) admits only `x` — adding `y`
-- REJECTS (`y: _|_`); `R & {x:1, y:2}` (open) admits both. The bodies differ AS VALUES via the
-- real close path, so the force/frame memos can never falsely collide an open eval with a closed
-- one (and the closed rejection is pinned through normalization, not a field-class proxy).
theorem perfb_closed_vs_open_distinct_values :
    evalSourceMatches
        "#C: {x: int}\nR: {x: int, ...}\nclosed: (#C & {x: 1})\nrejects: (#C & {x: 1, y: 2})\nopen: (R & {x: 1, y: 2})\n"
        "#C: {x: int}\nR: {x: int, ...}\nclosed: {x: 1}\nrejects: {x: 1, y: _|_}\nopen: {x: 1, y: 2, ...}"
          = true := by
  native_decide

-- FIX-SLICE-0 (def-open-tail-closedness, audit `fc25a71`). The COMPREHENSION/EMBED `.structComp`
-- path's openness, end-to-end. An OPEN def (`...`) carrying an embed + an `if`-guard admits a field
-- the use site ADDS past `...` — pre-fix the parser collapse dropped the `...` and normalize
-- hard-closed the `.structComp` arm, so `added` bottomed (cue accepts it). The fix records
-- `...`-presence (`hasTail`) on `.structComp` and normalize sets the def body's openness from it.
theorem fix0_open_def_embed_comp_admits_added_field :
    evalSourceMatches
        "#Base: {kind: \"S\"}\n#D: {#Base, port: int, if port > 0 {pos: true}, ...}\nout: #D & {port: 8080, added: \"x\"}\n"
        "#Base: {kind: \"S\"}\n#D: {port: int, kind: \"S\"}\nout: {port: 8080, added: \"x\", pos: true, kind: \"S\"}"
          = true := by
  native_decide

-- FIX-SLICE-0 NO-OVER-OPEN: the SAME embed+comprehension shape WITHOUT `...` is a CLOSED def — the
-- added field REJECTS (`added: _|_`), matching cue's `field not allowed`. Pins that honoring
-- `hasTail` does not open a genuinely-closed def (the over-open failure mode).
theorem fix0_closed_def_embed_comp_rejects_added_field :
    evalSourceMatches
        "#Base: {kind: \"S\"}\n#D: {#Base, port: int, if port > 0 {pos: true}}\nout: #D & {port: 8080, added: \"x\"}\n"
        "#Base: {kind: \"S\"}\n#D: {port: int, kind: \"S\"}\nout: {port: 8080, added: _|_, pos: true, kind: \"S\"}"
          = true := by
  native_decide

-- FIX-SLICE-0 REGULAR NON-DEF: a plain comprehension struct (no def, no `...`) stays OPEN — adding a
-- field is admitted (cue: regular structs are open by default). Pins that the parser's `hasTail`
-- change does not close regular `.structComp` values, which never pass through normalize.
theorem fix0_regular_comp_struct_stays_open :
    evalSourceMatches
        "x: {a: 1, if true {b: 9}}\nout: x & {c: 2}\n"
        "x: {a: 1, b: 9}\nout: {a: 1, b: 9, c: 2}"
          = true := by
  native_decide

-- LINK-5 (argocd `packs.#Argo`) — list-embed Self-narrowing through the conjunction-deferral fold.
-- A def whose only manifested content is a trailing LIST embed reading `Self.<hidden>` manifests AS
-- that list. The use site `#D & {[...], #name: "web"}` is a struct-embedding-an-open-list operand;
-- it evaluates to an `.embeddedList` whose decls carry `#name: "web"`. The fold dropped that
-- narrowing (the operand collapsed to a list, `evaluatedStructOperand?` recovered no fields), so the
-- def's list embed read the DEFAULT (`*"def-name"` → `"def-name"`). cue narrows to `"web"`. The fix
-- (`spliceNarrowingOperand?`) surfaces the `.embeddedList` decls so the splice narrows the def frame.
theorem link5_list_embed_self_narrows_to_use_default :
    evalSourceMatches
        "#D: Self={\n\t#name: *\"def-name\" | string\n\t[Self.#name]\n}\nout: #D & {[...], #name: \"web\"}\n"
        "#D: {#name: *\"def-name\" | string, [*\"def-name\" | string]}\nout: {#name: \"web\", [\"web\"]}"
          = true := by
  native_decide

-- LINK-5 nested-#components shape (faithful `packs.#Argo` skeleton): the list embed references
-- `Self.#components.{repo,app}`, each a struct reading `Self.#name`. The use-site narrowing must
-- reach `#name` two frames deep through the list embed's struct elements.
theorem link5_list_embed_nested_components_narrows :
    evalSourceMatches
        "#D: Self={\n\t#name: string\n\t#c: {repo: {n: Self.#name}, app: {n: Self.#name}}\n\t[Self.#c.repo, Self.#c.app]\n}\nout: #D & {[...], #name: \"web\"}\n"
        "#D: {#name: string, #c: {repo: {n: string}, app: {n: string}}, [{n: string}, {n: string}]}\nout: {#name: \"web\", #c: {repo: {n: \"web\"}, app: {n: \"web\"}}, [{n: \"web\"}, {n: \"web\"}]}"
          = true := by
  native_decide

-- LINK-5 NO-OVER-FIRE: the list embed reads a def-CONCRETE hidden field (`#tag: "fixed"`), while the
-- use site narrows a DIFFERENT field (`#name`). The embed result is unchanged (`["fixed"]`); the
-- splice does not corrupt a field the list embed never reads. Pins that the narrowing-splice is
-- additive — it only supplies the use-site values, never overrides a def-concrete read.
theorem link5_list_embed_concrete_field_unaffected_by_other_narrow :
    evalSourceMatches
        "#D: Self={\n\t#name: string\n\t#tag: \"fixed\"\n\t[Self.#tag]\n}\nout: #D & {[...], #name: \"web\"}\n"
        "#D: {#name: string, #tag: \"fixed\", [\"fixed\"]}\nout: {#name: \"web\", #tag: \"fixed\", [\"fixed\"]}"
          = true := by
  native_decide

-- LINK-5 disjunction arm-kill via impossible OPTIONAL field (argocd `#ArgoRepo` shape, sub-fix 2).
-- `(_#A | _#B) & {#u: "me"}` where `_#A` has `#u?: _|_`: supplying `#u` makes `_#A`'s optional
-- impossible field REGULAR-and-bottom, so `_#A` dies and `_#B` (`#u: string`) wins → `{#u:"me",
-- kind:"b"}`. Pre-fix `containsBottom` counted the UNSET `#u?: _|_` as bottoming `_#A` even before
-- the narrowing — pruning BOTH arms → `_|_`. The fix (`fieldBottomCounts`) skips OPTIONAL fields
-- in the struct bottom-check; the supplied-`#u` bottom surfaces at manifest (sub-fix-2 FixtureTests).
theorem link5_disj_arm_kill_via_impossible_optional :
    evalSourceMatches
        "_#A: {#u?: _|_, kind: \"a\"}\n_#B: {#u: string, kind: \"b\"}\nout: (_#A | _#B) & {#u: \"me\"}\n"
        "_#A: {#u?: _|_, kind: \"a\"}\n_#B: {#u: string, kind: \"b\"}\nout: {#u: \"me\", kind: \"b\"}"
          = true := by
  native_decide

-- LINK-5 NO-OVER-PRUNE: with NO narrowing, an UNSET impossible OPTIONAL field leaves BOTH arms LIVE
-- (cue keeps `{kind:"a"} | {kind:"b"}`). Pins that `fieldBottomCounts` does not prune an arm for an
-- unsatisfiable-but-unset optional — only a SUPPLIED field's bottom kills it.
theorem link5_disj_unset_optional_keeps_both_arms :
    evalSourceMatches
        "_#A: {#u?: _|_, kind: \"a\"}\n_#B: {#g?: _|_, kind: \"b\"}\nout: (_#A | _#B)\n"
        "_#A: {#u?: _|_, kind: \"a\"}\n_#B: {#g?: _|_, kind: \"b\"}\nout: {#u?: _|_, kind: \"a\"} | {#g?: _|_, kind: \"b\"}"
          = true := by
  native_decide

-- LINK-5 presence test over a DISJUNCTION field (argocd `parts.#Metadata` shape, sub-fix 4). A
-- DEFAULT disjunction `*"argocd" | string` is a PRESENT value, so `#ns != _|_` is `true` (cue). The
-- presence test classified a `.disj` as `.incomplete`, leaving `#ns != _|_` unresolved — so the
-- `if Self.#ns != _|_ {namespace: Self.#ns}` guard in `parts.#Metadata` dropped `namespace` that cue
-- emits (`#ArgoRepo` was missing `metadata.namespace: "argocd"`). Fix: `classifyDefinedness` treats
-- a `.disj` as `.defined` (an all-bottom disjunction never reaches here — `liveAlternatives` prunes).
theorem link5_presence_test_default_disjunction_is_present :
    evalSourceMatches
        "out: {\n\t#ns: *\"argocd\" | string\n\tt: #ns != _|_\n}\n"
        "out: {#ns: *\"argocd\" | string, t: true}"
          = true := by
  native_decide

-- LINK-5 presence test over a PLAIN (no-default) disjunction is also PRESENT (cue: `("a"|"b") != _|_`
-- is `true`). Pins that the fix is not default-specific.
theorem link5_presence_test_plain_disjunction_is_present :
    evalSourceMatches
        "out: {\n\t#x: \"a\" | \"b\"\n\tt: #x != _|_\n}\n"
        "out: {#x: \"a\" | \"b\", t: true}"
          = true := by
  native_decide

-- PERF-B PIN 4 (frame-id must NOT leak into value identity/output — audit finding #4). The whole
-- memo soundness rests on `valueTag` being constant per constructor (frame ids never enter a memo
-- HASH) and `Format` dropping the captured env (ids never reach output). Pin both: two closures
-- with the SAME body but DIFFERENT captured-env ids have equal `valueTag` and Format-print equal.
-- A future `valueTag`/`Format` edit that started hashing/printing `capturedEnv` would trip this.
theorem perfb_frame_id_does_not_leak :
    (let body : Value := .struct [⟨"k", .regular, .prim (.int 1)⟩] .regularOpen none []
     let c1 : Value := .closure [(7, [])] body
     let c2 : Value := .closure [(9, [])] body
     (valueTag c1 == valueTag c2) && (formatValue c1 == formatValue c2))
      = true := by
  native_decide


end Kue
