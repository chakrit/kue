import Kue.Eval
import Kue.Format
import Kue.Manifest
import Kue.Resolve
import Kue.Runtime

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
        (.struct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .ref "#A"⟩] true))
      == .struct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .kind .int⟩] true) = true := by
  native_decide

theorem eval_missing_reference_bottom :
    (evalStructRefs
      (.struct [⟨"x", .regular, .ref "#Missing"⟩] true)
      == .struct [⟨"x", .regular, .bottomWith [.unresolvedReference "#Missing"]⟩] true) = true := by
  native_decide

theorem eval_resolved_reference_by_binding_id :
    (evalStructRefs
      (.struct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .refId ⟨0, 0⟩⟩] true)
      == .struct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .kind .int⟩] true) = true := by
  native_decide

theorem eval_static_field_selector :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ⟨"base", .regular, .struct [⟨"inner", .regular, .prim (.int 4)⟩] true⟩,
            ⟨"x", .regular, .selector (.ref "base") "inner"⟩
          ]
          true))
      = "base: {inner: 4}\nx: 4" := by
  native_decide

theorem eval_static_list_index :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ⟨"xs", .regular, .list [.prim (.int 10), .prim (.int 20)]⟩,
            ⟨"x", .regular, .index (.ref "xs") (.prim (.int 1))⟩
          ]
          true))
      = "xs: [10, 20]\nx: 20" := by
  native_decide

theorem eval_static_string_field_index :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ⟨"base", .regular, .struct [⟨"inner", .regular, .prim (.int 4)⟩] true⟩,
            ⟨"x", .regular, .index (.ref "base") (.prim (.string "inner"))⟩
          ]
          true))
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
        (.struct
          [
            ⟨"base", .regular, .prim (.string "v")⟩,
            ⟨"components", .regular,
              .struct
                [
                  ⟨"a", .regular, .struct [⟨"who", .regular, .ref "base"⟩] true⟩,
                  ⟨"b", .regular, .struct [⟨"who", .regular, .ref "base"⟩] true⟩
                ]
                true⟩,
            ⟨"aWho", .regular, .selector (.selector (.ref "components") "a") "who"⟩,
            ⟨"bWho", .regular, .selector (.selector (.ref "components") "b") "who"⟩
          ]
          true))
      = "base: \"v\"\ncomponents: {a: {who: \"v\"}, b: {who: \"v\"}}\naWho: \"v\"\nbWho: \"v\"" := by
  native_decide

-- A direct self-cycle selected twice: caching must not turn the bounded-cycle `⊤` into a
-- wrong value, and both selections must agree. `x: x & {p: 1}` resolves the cycle to its
-- constraint; `p1`/`p2` select the same field from the cyclic struct.
theorem eval_cycle_with_repeated_selection :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ⟨"x", .regular, .conj [.ref "x", .struct [⟨"p", .regular, .prim (.int 1)⟩] true]⟩,
            ⟨"p1", .regular, .selector (.ref "x") "p"⟩,
            ⟨"p2", .regular, .selector (.ref "x") "p"⟩
          ]
          true))
      = "x: {p: 1}\np1: 1\np2: 1" := by
  native_decide

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
  | 0 => .struct [⟨"v", .regular, .prim (.string "x")⟩] true
  | n + 1 =>
      let inner := deepInlineValue n
      .struct [⟨"a", .regular, inner⟩, ⟨"b", .regular, inner⟩] true

def deepInlineRoot (n : Nat) : Value :=
  .struct [⟨"root", .regular, deepInlineValue n⟩] true

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
  .struct [⟨"a", .regular, .struct [⟨"b", .regular, .refId ⟨1, 0⟩⟩] true⟩] true

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
      (.struct [⟨"x", .regular, .prim (.int 1)⟩] true)]
    true

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
    (.structComp [] [.prim (.int 9)] true)]

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

def evalSourceMatches (source expected : String) : Bool :=
  match evalSourceToString source with
  | .ok output => output == expected
  | .error _ => false

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

-- PERF-B PIN 4 (frame-id must NOT leak into value identity/output — audit finding #4). The whole
-- memo soundness rests on `valueTag` being constant per constructor (frame ids never enter a memo
-- HASH) and `Format` dropping the captured env (ids never reach output). Pin both: two closures
-- with the SAME body but DIFFERENT captured-env ids have equal `valueTag` and Format-print equal.
-- A future `valueTag`/`Format` edit that started hashing/printing `capturedEnv` would trip this.
theorem perfb_frame_id_does_not_leak :
    (let body : Value := .struct [⟨"k", .regular, .prim (.int 1)⟩] true
     let c1 : Value := .closure [(7, [])] body
     let c2 : Value := .closure [(9, [])] body
     (valueTag c1 == valueTag c2) && (formatValue c1 == formatValue c2))
      = true := by
  native_decide

/-! ### list-comprehension parse+eval pins (slice `list-comprehension-parse-eval`).

End-to-end behavioral pins over the full list-comprehension surface, each cue v0.16.1-exact (the
`.expected` strings are the oracle-checked outputs). Parsed-resolved-evaluated-formatted, so a
regression anywhere in the parser/resolver/eval chain trips them. Paired with the
fuel-truncation/saturation guards above (`sat_list_comprehension_*`). -/

-- for over a literal list, body uses the loop var.
theorem listcomp_for_basic :
    evalSourceMatches "out: [for x in [1, 2, 3] {x * 2}]\n" "out: [2, 4, 6]" = true := by
  native_decide

-- for-index form: `for i, x in list` binds the 0-based index.
theorem listcomp_for_index :
    evalSourceMatches "out: [for i, x in [10, 20, 30] {i*100 + x}]\n" "out: [10, 120, 230]"
      = true := by
  native_decide

-- for-k,v over a struct: iterates regular fields, binding key + value.
theorem listcomp_for_kv_struct :
    evalSourceMatches "out: [for k, v in {a: 1, b: 2} {v}]\n" "out: [1, 2]" = true := by
  native_decide

-- if guard mixed with a plain element: order preserved, false guard yields zero.
theorem listcomp_if_mixed :
    evalSourceMatches "out: [if true {1}, 2]\n" "out: [1, 2]" = true := by
  native_decide

theorem listcomp_if_false_zero :
    evalSourceMatches "out: [if false {42}]\n" "out: []" = true := by
  native_decide

-- for + if clause chain: the guard filters the iteration.
theorem listcomp_for_if_chain :
    evalSourceMatches "l: [1, 2, 3]\nout: [for x in l if x > 1 {x}]\n"
        "l: [1, 2, 3]\nout: [2, 3]" = true := by
  native_decide

-- nested for: the outer var is in scope for the inner; flattened in iteration order.
theorem listcomp_nested_for :
    evalSourceMatches "xs: [1, 2]\nys: [10, 20]\nout: [for x in xs for y in ys {x + y}]\n"
        "xs: [1, 2]\nys: [10, 20]\nout: [11, 21, 12, 22]" = true := by
  native_decide

-- mixed plain elements + comprehension: source order is preserved through the flatten.
theorem listcomp_mixed_order :
    evalSourceMatches "xs: [5, 6]\nout: [1, for x in xs {x}, 2]\n"
        "xs: [5, 6]\nout: [1, 5, 6, 2]" = true := by
  native_decide

-- empty source yields the empty list (not bottom).
theorem listcomp_empty_source :
    evalSourceMatches "out: [for x in [] {x}]\n" "out: []" = true := by
  native_decide

-- multiple elements yielded per outer iteration (inner for produces >1 each).
theorem listcomp_multi_yield :
    evalSourceMatches "out: [for x in [1, 2] for y in [x, x*10] {y}]\n" "out: [1, 10, 2, 20]"
      = true := by
  native_decide

-- struct-valued body element (body has a field, so the element IS that struct).
theorem listcomp_struct_body :
    evalSourceMatches "out: [for x in [1, 2] {a: x}]\n" "out: [{a: 1}, {a: 2}]" = true := by
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

theorem eval_additive_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ⟨"sum", .regular, .binary .add (.prim (.int 1)) (.prim (.int 2))⟩,
            ⟨"diff", .regular, .binary .sub (.prim (.int 5)) (.prim (.int 3))⟩,
            ⟨"cat", .regular, .binary .add (.prim (.string "a")) (.prim (.string "b"))⟩,
            ⟨"bytes", .regular, .binary .add (.prim (.bytes "ab")) (.prim (.bytes "cd"))⟩
          ]
          true))
      = "sum: 3\ndiff: 2\ncat: \"ab\"\nbytes: 'abcd'" := by
  native_decide

theorem eval_float_additive_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ⟨"floatSum", .regular, .binary .add (.prim (.float "1.5")) (.prim (.float "2.25"))⟩,
            ⟨"intFloat", .regular, .binary .add (.prim (.int 1)) (.prim (.float "2.5"))⟩,
            ⟨"floatSub", .regular, .binary .sub (.prim (.float "5.5")) (.prim (.int 2))⟩,
            ⟨"exp", .regular, .binary .add (.prim (.float "1e+3")) (.prim (.int 2))⟩,
            ⟨"small", .regular, .binary .add (.prim (.float "0.1")) (.prim (.float "0.2"))⟩
          ]
          true))
      = "floatSum: 3.75\nintFloat: 3.5\nfloatSub: 3.5\nexp: 1002.0\nsmall: 0.3" := by
  native_decide

theorem eval_multiplication_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ⟨"mul", .regular, .binary .mul (.prim (.int 3)) (.prim (.int 4))⟩,
            ⟨
              "precedence",
              .regular,
              .binary .add (.prim (.int 1)) (.binary .mul (.prim (.int 2)) (.prim (.int 3)))
            ⟩
          ]
          true))
      = "mul: 12\nprecedence: 7" := by
  native_decide

theorem eval_division_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ⟨"div", .regular, .binary .div (.prim (.int 5)) (.prim (.int 2))⟩,
            ⟨"whole", .regular, .binary .div (.prim (.int 6)) (.prim (.int 3))⟩,
            ⟨"third", .regular, .binary .div (.prim (.int 1)) (.prim (.int 3))⟩,
            ⟨"negative", .regular, .binary .div (.prim (.int (-5))) (.prim (.int 2))⟩
          ]
          true))
      = "div: 2.5\nwhole: 2.0\nthird: 0.3333333333333333333333333333333333\nnegative: -2.5" := by
  native_decide

theorem eval_division_by_zero_bottom :
    evalBinary .div (.prim (.int 1)) (.prim (.int 0)) = .bottomWith [.divisionByZero] := by
  rfl

theorem eval_integer_keyword_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ⟨"divValue", .regular, .binary .intDiv (.prim (.int (-7))) (.prim (.int 3))⟩,
            ⟨"modValue", .regular, .binary .intMod (.prim (.int (-7))) (.prim (.int 3))⟩,
            ⟨"quoValue", .regular, .binary .intQuo (.prim (.int (-7))) (.prim (.int 3))⟩,
            ⟨"remValue", .regular, .binary .intRem (.prim (.int (-7))) (.prim (.int 3))⟩
          ]
          true))
      = "divValue: -3\nmodValue: 2\nquoValue: -2\nremValue: -1" := by
  native_decide

theorem eval_integer_keyword_incomplete_keeps_infix :
    formatValue (evalBinary .intDiv (.kind .int) (.prim (.int 3))) = "int div 3" := by
  native_decide

theorem eval_equality_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ⟨"same", .regular, .binary .eq (.prim (.int 1)) (.prim (.int 1))⟩,
            ⟨"diff", .regular, .binary .ne (.prim (.int 1)) (.prim (.int 2))⟩,
            ⟨"text", .regular, .binary .eq (.prim (.string "a")) (.prim (.string "b"))⟩
          ]
          true))
      = "same: true\ndiff: true\ntext: false" := by
  native_decide

theorem eval_ordering_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ⟨"lt", .regular, .binary .lt (.prim (.int 1)) (.prim (.int 2))⟩,
            ⟨"le", .regular, .binary .le (.prim (.int 2)) (.prim (.int 2))⟩,
            ⟨"gt", .regular, .binary .gt (.prim (.int 3)) (.prim (.int 2))⟩,
            ⟨"ge", .regular, .binary .ge (.prim (.int 3)) (.prim (.int 4))⟩,
            ⟨"slt", .regular, .binary .lt (.prim (.string "a")) (.prim (.string "b"))⟩
          ]
          true))
      = "lt: true\nle: true\ngt: true\nge: false\nslt: true" := by
  native_decide

theorem eval_numeric_comparison_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ⟨"lt", .regular, .binary .lt (.prim (.float "1.5")) (.prim (.int 2))⟩,
            ⟨"le", .regular, .binary .le (.prim (.float "1.5")) (.prim (.float "1.50"))⟩,
            ⟨"gt", .regular, .binary .gt (.prim (.float "1e+3")) (.prim (.float "999.9"))⟩,
            ⟨"ge", .regular, .binary .ge (.prim (.float "1.0")) (.prim (.int 1))⟩,
            ⟨"eq", .regular, .binary .eq (.prim (.int 1)) (.prim (.float "1.0"))⟩,
            ⟨"ne", .regular, .binary .ne (.prim (.int 1)) (.prim (.float "1.0"))⟩
          ]
          true))
      = "lt: true\nle: true\ngt: true\nge: true\neq: true\nne: false" := by
  native_decide

theorem eval_logical_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ⟨"andFalse", .regular, .binary .boolAnd (.prim (.bool true)) (.prim (.bool false))⟩,
            ⟨"orTrue", .regular, .binary .boolOr (.prim (.bool false)) (.prim (.bool true))⟩,
            ⟨
              "andCmp",
              .regular,
              .binary .boolAnd
                (.binary .lt (.prim (.int 1)) (.prim (.int 2)))
                (.binary .gt (.prim (.int 3)) (.prim (.int 2)))
            ⟩
          ]
          true))
      = "andFalse: false\norTrue: true\nandCmp: true" := by
  native_decide

theorem eval_logical_not_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ⟨"notFalse", .regular, .unary .boolNot (.prim (.bool false))⟩,
            ⟨"notCmp", .regular, .unary .boolNot (.binary .lt (.prim (.int 1)) (.prim (.int 2)))⟩,
            ⟨"double", .regular, .unary .boolNot (.unary .boolNot (.prim (.bool true)))⟩
          ]
          true))
      = "notFalse: true\nnotCmp: false\ndouble: true" := by
  native_decide

theorem eval_unary_numeric_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ⟨"negGroup", .regular, .unary .numNeg (.binary .add (.prim (.int 1)) (.prim (.int 2)))⟩,
            ⟨"posGroup", .regular, .unary .numPos (.binary .add (.prim (.int 1)) (.prim (.int 2)))⟩,
            ⟨"negFloat", .regular, .unary .numNeg (.prim (.float "1.5"))⟩
          ]
          true))
      = "negGroup: -3\nposGroup: 3\nnegFloat: -1.5" := by
  native_decide

theorem eval_regex_match_expressions :
    formatTopLevel
      (resolveAndEval
        (.struct
          [
            ⟨"match", .regular, .binary .regexMatch (.prim (.string "abc")) (.prim (.string "^a"))⟩,
            ⟨"miss", .regular, .binary .regexMatch (.prim (.string "abc")) (.prim (.string "z"))⟩,
            ⟨"notMatch", .regular, .binary .regexNotMatch (.prim (.string "abc")) (.prim (.string "z"))⟩
          ]
          true))
      = "match: true\nmiss: false\nnotMatch: true" := by
  native_decide

theorem eval_list_index_out_of_range_bottom :
    (evalStructRefs
      (resolveStructRefs
        (.struct
          [
            ⟨"xs", .regular, .list [.prim (.int 10)]⟩,
            ⟨"x", .regular, .index (.ref "xs") (.prim (.int 2))⟩
          ]
          true))
      == .struct
        [
          ⟨"xs", .regular, .list [.prim (.int 10)]⟩,
          ⟨"x", .regular, .bottomWith [.indexOutOfRange 2 1]⟩
        ]
        true) = true := by
  native_decide

theorem eval_missing_binding_id_bottom :
    (evalStructRefs
      (.struct [⟨"x", .regular, .refId ⟨0, 2⟩⟩] true)
      == .struct [⟨"x", .regular, .bottomWith [.unresolvedBinding ⟨0, 2⟩]⟩] true) = true := by
  native_decide

theorem eval_binding_id_not_label_lookup :
    (evalStructRefs
      (.struct [⟨"#same", .definition, .kind .int⟩, ⟨"same", .regular, .kind .string⟩, ⟨"x", .regular, .refId ⟨0, 1⟩⟩] true)
      == .struct [⟨"#same", .definition, .kind .int⟩, ⟨"same", .regular, .kind .string⟩, ⟨"x", .regular, .kind .string⟩] true) = true := by
  native_decide

theorem resolve_direct_self_reference :
    (resolveStructRefs
      (.struct [⟨"x", .regular, .ref "x"⟩] true)
      == .struct [⟨"x", .regular, .refId ⟨0, 0⟩⟩] true) = true := by
  native_decide

theorem eval_direct_self_reference_as_top :
    (evalStructRefs
      (resolveStructRefs (.struct [⟨"x", .regular, .ref "x"⟩] true))
      == .struct [⟨"x", .regular, .top⟩] true) = true := by
  native_decide

theorem eval_mutual_reference_cycle_as_top :
    (evalStructRefs
      (resolveStructRefs (.struct [⟨"x", .regular, .ref "y"⟩, ⟨"y", .regular, .ref "x"⟩] true))
      == .struct [⟨"x", .regular, .top⟩, ⟨"y", .regular, .top⟩] true) = true := by
  native_decide

theorem eval_three_reference_cycle_as_top :
    (evalStructRefs
      (resolveStructRefs
        (.struct
          [
            ⟨"x", .regular, .ref "y"⟩,
            ⟨"y", .regular, .ref "z"⟩,
            ⟨"z", .regular, .ref "x"⟩
          ]
          true))
      == .struct [⟨"x", .regular, .top⟩, ⟨"y", .regular, .top⟩, ⟨"z", .regular, .top⟩] true) = true := by
  native_decide

theorem eval_direct_constrained_cycle_keeps_constraint :
    (evalStructRefs
      (resolveStructRefs (.struct [⟨"x", .regular, .conj [.ref "x", .boundConstraint (intDecimal 0) .ge .number]⟩] true))
      == .struct [⟨"x", .regular, .boundConstraint (intDecimal 0) .ge .number⟩] true) = true := by
  native_decide

theorem eval_mutual_constrained_cycle_keeps_constraint :
    (evalStructRefs
      (resolveStructRefs
        (.struct
          [
            ⟨"a", .regular, .conj [.ref "b", .boundConstraint (intDecimal 0) .ge .number]⟩,
            ⟨"b", .regular, .ref "a"⟩
          ]
          true))
      == .struct [⟨"a", .regular, .boundConstraint (intDecimal 0) .ge .number⟩, ⟨"b", .regular, .boundConstraint (intDecimal 0) .ge .number⟩] true) = true := by
  native_decide

theorem eval_non_cycle_reference_still_uses_target_value :
    (evalStructRefs
      (resolveStructRefs (.struct [⟨"x", .regular, .kind .int⟩, ⟨"y", .regular, .ref "x"⟩] true))
      == .struct [⟨"x", .regular, .kind .int⟩, ⟨"y", .regular, .kind .int⟩] true) = true := by
  native_decide

/-- A value alias (`Self={…}`) lowers to a `.thisStruct` let-binding; `Self.field`
    (a selector on the binding) resolves as a same-struct sibling reference. Pins the
    eval-level `thisStruct` mechanism directly. -/
theorem eval_value_alias_self_reference :
    (evalStructRefs
      (resolveStructRefs
        (.struct
          [
            ⟨"Self", .letBinding, .thisStruct⟩,
            ⟨"x", .regular, .prim (.int 5)⟩,
            ⟨"y", .regular, .selector (.ref "Self") "x"⟩
          ]
          true))
      == .struct
        [
          ⟨"Self", .letBinding, .thisStruct⟩,
          ⟨"x", .regular, .prim (.int 5)⟩,
          ⟨"y", .regular, .prim (.int 5)⟩
        ]
        true) = true := by
  native_decide

/-- A self-reference cycle through the alias is bounded to top, never diverging. -/
theorem eval_value_alias_cycle_bounds_to_top :
    (evalStructRefs
      (resolveStructRefs
        (.struct
          [
            ⟨"Self", .letBinding, .thisStruct⟩,
            ⟨"x", .regular, .selector (.ref "Self") "y"⟩,
            ⟨"y", .regular, .selector (.ref "Self") "x"⟩
          ]
          true))
      == .struct
        [
          ⟨"Self", .letBinding, .thisStruct⟩,
          ⟨"x", .regular, .top⟩,
          ⟨"y", .regular, .top⟩
        ]
        true) = true := by
  native_decide

theorem eval_regular_disjunction_uses_join_normalization :
    (evalStructRefs
      (.struct [⟨"x", .regular, .disj [(.regular, .boundConstraint (intDecimal 5) .ge .number), (.regular, .boundConstraint (intDecimal 0) .ge .number)]⟩] true)
      == .struct [⟨"x", .regular, .boundConstraint (intDecimal 0) .ge .number⟩] true) = true := by
  native_decide

theorem eval_regular_field_reference_to_hidden :
    (evalStructRefs
      (resolveStructRefs (.struct [⟨"_secret", .hidden, .prim (.string "x")⟩, ⟨"value", .regular, .ref "_secret"⟩] true))
      == .struct [⟨"_secret", .hidden, .prim (.string "x")⟩, ⟨"value", .regular, .prim (.string "x")⟩] true) = true := by
  native_decide

theorem eval_reference_inside_struct_tail :
    (evalStructRefs
      (resolveStructRefs (.structTail [⟨"#A", .definition, .kind .int⟩] (.ref "#A")))
      == .structTail [⟨"#A", .definition, .kind .int⟩] (.kind .int)) = true := by
  native_decide

theorem eval_reference_inside_nested_struct :
    (evalStructRefs
      (resolveStructRefs
        (.struct
          [⟨"x", .regular, .struct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .ref "#A"⟩] true⟩]
          true))
      == .struct
        [⟨"x", .regular, .struct [⟨"#A", .definition, .kind .int⟩, ⟨"x", .regular, .kind .int⟩] true⟩]
        true) = true := by
  native_decide

theorem eval_reference_inside_struct_pattern :
    (evalStructRefs
      (resolveStructRefs (.structPattern [⟨"#A", .definition, .kind .int⟩] (.kind .string) (.ref "#A") true))
      == .structPattern [⟨"#A", .definition, .kind .int⟩] (.kind .string) (.kind .int) true) = true := by
  native_decide

theorem eval_struct_pattern_constrains_own_regular_field :
    (evalStructRefs
      (.structPattern [⟨"a", .regular, .prim (.string "bad")⟩] (.kind .string) (.kind .int) true)
      == .structPattern
        [⟨"a", .regular, .bottomWith [.fieldConstraint "a"]⟩]
        (.kind .string)
        (.kind .int)
        true) = true := by
  native_decide

theorem string_kind_pattern_types_matching_field :
    (meet
      (.structPattern [] (.kind .string) (.kind .int) true)
      (.struct [⟨"a", .regular, .prim (.int 1)⟩] true)
      == .structPattern [⟨"a", .regular, .prim (.int 1)⟩] (.kind .string) (.kind .int) true) = true := by
  native_decide

theorem string_kind_pattern_rejects_type_mismatch :
    containsBottom
      (meet
        (.structPattern [] (.kind .string) (.kind .int) true)
        (.struct [⟨"a", .regular, .prim (.string "x")⟩] true)) = true := by
  native_decide

theorem eval_len_builtin_call_after_reference_resolution :
    (evalStructRefs
      (resolveStructRefs
        (.struct [⟨"x", .regular, .prim (.string "abc")⟩, ⟨"y", .regular, .builtinCall "len" [.ref "x"]⟩] true))
      == .struct [⟨"x", .regular, .prim (.string "abc")⟩, ⟨"y", .regular, .prim (.int 3)⟩] true) = true := by
  native_decide

theorem eval_integer_builtin_call_after_reference_resolution :
    (evalStructRefs
      (resolveStructRefs
        (.struct
          [
            ⟨"n", .regular, .prim (.int (-7))⟩,
            ⟨"q", .regular, .builtinCall "div" [.ref "n", .prim (.int 3)]⟩
          ]
          true))
      == .struct [⟨"n", .regular, .prim (.int (-7))⟩, ⟨"q", .regular, .prim (.int (-3))⟩] true) = true := by
  native_decide

theorem eval_incomplete_builtin_call_remains_call :
    (evalStructRefs (.struct [⟨"x", .regular, .builtinCall "len" [.kind .string]⟩] true)
      == .struct [⟨"x", .regular, .builtinCall "len" [.kind .string]⟩] true) = true := by
  native_decide

theorem eval_comprehension_for_keyed_over_struct :
    (evalStructRefs
      (resolveStructRefs
        (.structComp
          []
          [
            .comprehension
              [.forIn (some "k") "v" (.struct [⟨"x", .regular, .prim (.int 1)⟩] true)]
              (.struct [⟨"key", .regular, .ref "k"⟩, ⟨"val", .regular, .ref "v"⟩] true)
          ]
          true))
      == .struct [⟨"key", .regular, .prim (.string "x")⟩, ⟨"val", .regular, .prim (.int 1)⟩] true)
      = true := by
  native_decide

theorem eval_comprehension_for_over_list :
    (evalStructRefs
      (resolveStructRefs
        (.structComp
          []
          [
            .comprehension
              [.forIn none "v" (.list [.prim (.int 42)])]
              (.struct [⟨"only", .regular, .ref "v"⟩] true)
          ]
          true))
      == .struct [⟨"only", .regular, .prim (.int 42)⟩] true) = true := by
  native_decide

theorem eval_comprehension_if_true_admits :
    (evalStructRefs
      (resolveStructRefs
        (.structComp
          []
          [.comprehension [.guard (.prim (.bool true))] (.struct [⟨"flag", .regular, .prim (.bool true)⟩] true)]
          true))
      == .struct [⟨"flag", .regular, .prim (.bool true)⟩] true) = true := by
  native_decide

theorem eval_comprehension_if_false_drops :
    (evalStructRefs
      (resolveStructRefs
        (.structComp
          []
          [.comprehension [.guard (.prim (.bool false))] (.struct [⟨"hidden", .regular, .prim (.int 1)⟩] true)]
          true))
      == .struct [] true) = true := by
  native_decide

theorem eval_comprehension_body_sees_sibling_field :
    (evalStructRefs
      (resolveStructRefs
        (.structComp
          [⟨"base", .regular, .prim (.int 7)⟩]
          [.comprehension [.guard (.prim (.bool true))] (.struct [⟨"copy", .regular, .ref "base"⟩] true)]
          true))
      == .struct [⟨"base", .regular, .prim (.int 7)⟩, ⟨"copy", .regular, .prim (.int 7)⟩] true)
      = true := by
  native_decide

theorem eval_comprehension_for_source_sees_sibling_field :
    (evalStructRefs
      (resolveStructRefs
        (.structComp
          [⟨"k", .regular, .prim (.int 3)⟩]
          [.comprehension [.forIn none "v" (.list [.ref "k"])] (.struct [⟨"g", .regular, .ref "v"⟩] true)]
          true))
      == .struct [⟨"k", .regular, .prim (.int 3)⟩, ⟨"g", .regular, .prim (.int 3)⟩] true)
      = true := by
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

/-- Slice C. The negated real-app guard shape: `x: bool | *false; if !x { y: 1 }`. The `!`
    distributes over the default disjunction and the guard collapses the default to `true`,
    so the body admits. cue-exact (`{x: false, out: {y: 1}}`). -/
theorem eval_comprehension_guard_negated_default_disj_admits :
    (evalStructRefs
      (resolveStructRefs
        (.struct
          [⟨"x", .regular, .disj [(.default, .prim (.bool false)), (.regular, .kind .bool)]⟩,
           ⟨"out", .regular,
             .structComp []
               [.comprehension [.guard (.unary .boolNot (.ref "x"))]
                 (.struct [⟨"y", .regular, .prim (.int 1)⟩] true)]
               true⟩]
          true))
      == .struct
        [⟨"x", .regular, .disj [(.default, .prim (.bool false)), (.regular, .kind .bool)]⟩,
         ⟨"out", .regular, .struct [⟨"y", .regular, .prim (.int 1)⟩] true⟩]
        true) = true := by
  native_decide

/-- Slice C. The direct guard shape `if x` with `x: bool | *true` admits (default `true`). -/
theorem eval_comprehension_guard_direct_default_disj_admits :
    (evalStructRefs
      (resolveStructRefs
        (.struct
          [⟨"x", .regular, .disj [(.default, .prim (.bool true)), (.regular, .kind .bool)]⟩,
           ⟨"out", .regular,
             .structComp []
               [.comprehension [.guard (.ref "x")]
                 (.struct [⟨"y", .regular, .prim (.int 1)⟩] true)]
               true⟩]
          true))
      == .struct
        [⟨"x", .regular, .disj [(.default, .prim (.bool true)), (.regular, .kind .bool)]⟩,
         ⟨"out", .regular, .struct [⟨"y", .regular, .prim (.int 1)⟩] true⟩]
        true) = true := by
  native_decide

/-- Slice C (over-resolution guard). A NON-default disjunction in a guard must STAY
    unsatisfied — only marked defaults collapse. `if x` with `x: bool` (no default) drops
    the body, matching cue's `incomplete value bool`. -/
theorem eval_comprehension_guard_non_default_disj_drops :
    (evalStructRefs
      (resolveStructRefs
        (.struct
          [⟨"x", .regular,
             .disj [(.regular, .prim (.bool true)), (.regular, .prim (.bool false))]⟩,
           ⟨"out", .regular,
             .structComp []
               [.comprehension [.guard (.ref "x")]
                 (.struct [⟨"y", .regular, .prim (.int 1)⟩] true)]
               true⟩]
          true))
      == .struct
        [⟨"x", .regular,
           .disj [(.regular, .prim (.bool true)), (.regular, .prim (.bool false))]⟩,
         ⟨"out", .regular, .struct [] true⟩]
        true) = true := by
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
      (.struct
        [⟨"a", .regular, .kind .int⟩, ⟨"b", .regular, .ref "a"⟩, ⟨"a", .regular, .prim (.int 1)⟩]
        true)
      == .struct
        [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.int 1)⟩]
        true) = true := by
  native_decide

/-- A duplicate-label conflict bottoms both the label and any sibling referencing it:
    `{a: 1, b: a, a: 2}` -> `a` and `b` both bottom. -/
theorem eval_in_struct_sibling_conflict :
    (resolveAndEval
      (.struct
        [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .ref "a"⟩, ⟨"a", .regular, .prim (.int 2)⟩]
        true)
      == .struct
        [
          ⟨"a", .regular, .bottomWith [.primitiveConflict (.int 1) (.int 2)]⟩,
          ⟨"b", .regular, .bottomWith [.primitiveConflict (.int 1) (.int 2)]⟩
        ]
        true) = true := by
  native_decide

/-- Canonicalization is visible through nested sub-structs: `c.e` references the outer `a`,
    seeing the merged `int & 1 = 1`. -/
theorem eval_nested_sibling_merge :
    (resolveAndEval
      (.struct
        [
          ⟨"a", .regular, .kind .int⟩,
          ⟨"c", .regular, .struct [⟨"e", .regular, .ref "a"⟩] true⟩,
          ⟨"a", .regular, .prim (.int 1)⟩
        ]
        true)
      == .struct
        [
          ⟨"a", .regular, .prim (.int 1)⟩,
          ⟨"c", .regular, .struct [⟨"e", .regular, .prim (.int 1)⟩] true⟩
        ]
        true) = true := by
  native_decide

/-- A self-referential merged slot must not loop: `{a: a, a: 1}` canonicalizes to
    `.conj [a, 1]` at slot 0; the self-ref hits the `slotVisited` -> `.top` guard, so the
    meet collapses to `1` rather than diverging. -/
theorem eval_merged_self_ref_cycle :
    (resolveAndEval
      (.struct [⟨"a", .regular, .ref "a"⟩, ⟨"a", .regular, .prim (.int 1)⟩] true)
      == .struct [⟨"a", .regular, .prim (.int 1)⟩] true) = true := by
  native_decide

/-- 2c.2: struct conjunction through a referenced binding. `d & {a: 1}` merges the conjuncts'
    declarations into one frame before evaluating bodies, so `d.b: a` sees the narrowed `a`
    and `y.b` resolves to `1` (not `int`). -/
theorem eval_meet_lazy_sibling_ref :
    (resolveAndEval
      (.struct
        [
          ⟨"d", .regular, .struct [⟨"a", .regular, .kind .int⟩, ⟨"b", .regular, .ref "a"⟩] true⟩,
          ⟨"y", .regular, .conj [.ref "d", .struct [⟨"a", .regular, .prim (.int 1)⟩] true]⟩
        ]
        true)
      == .struct
        [
          ⟨"d", .regular, .struct [⟨"a", .regular, .kind .int⟩, ⟨"b", .regular, .kind .int⟩] true⟩,
          ⟨"y", .regular,
            .struct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.int 1)⟩] true⟩
        ]
        true) = true := by
  native_decide

/-- 2c.2: literal struct conjunction (no reference operand). `{a: int, b: a} & {a: 1}` → `b: 1`
    via the merged frame. -/
theorem eval_meet_lazy_literal :
    (resolveAndEval
      (.struct
        [
          ⟨"x", .regular,
            .conj
              [
                .struct [⟨"a", .regular, .kind .int⟩, ⟨"b", .regular, .ref "a"⟩] true,
                .struct [⟨"a", .regular, .prim (.int 1)⟩] true
              ]⟩
        ]
        true)
      == .struct
        [
          ⟨"x", .regular,
            .struct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"b", .regular, .prim (.int 1)⟩] true⟩
        ]
        true) = true := by
  native_decide

/-- 2c.2: a chained sibling reference within one conjunct, narrowed across the meet —
    `{a: int, b: a, c: b} & {a: 1}` resolves `a`, `b`, `c` all to `1`. -/
theorem eval_meet_lazy_chain :
    (resolveAndEval
      (.struct
        [
          ⟨"x", .regular,
            .conj
              [
                .struct
                  [
                    ⟨"a", .regular, .kind .int⟩,
                    ⟨"b", .regular, .ref "a"⟩,
                    ⟨"c", .regular, .ref "b"⟩
                  ]
                  true,
                .struct [⟨"a", .regular, .prim (.int 1)⟩] true
              ]⟩
        ]
        true)
      == .struct
        [
          ⟨"x", .regular,
            .struct
              [
                ⟨"a", .regular, .prim (.int 1)⟩,
                ⟨"b", .regular, .prim (.int 1)⟩,
                ⟨"c", .regular, .prim (.int 1)⟩
              ]
              true⟩
        ]
        true) = true := by
  native_decide

/-- 2c.2: nested sub-struct visibility through a *definition* meet. `out.val` references the
    hidden `#x`; `#D & {#x: "hi"}` narrows `#x` and the nested `out.val` resolves to `"hi"`. -/
theorem eval_meet_lazy_hidden_def :
    (resolveAndEval
      (.struct
        [
          ⟨"#D", .definition,
            .struct
              [
                ⟨"#x", .definition, .kind .string⟩,
                ⟨"out", .regular, .struct [⟨"val", .regular, .ref "#x"⟩] true⟩
              ]
              true⟩,
          ⟨"y", .regular, .conj [.ref "#D", .struct [⟨"#x", .definition, .prim (.string "hi")⟩] true]⟩
        ]
        true)
      == .struct
        [
          ⟨"#D", .definition,
            .struct
              [
                ⟨"#x", .definition, .kind .string⟩,
                ⟨"out", .regular, .struct [⟨"val", .regular, .kind .string⟩] true⟩
              ]
              false⟩,
          ⟨"y", .regular,
            .struct
              [
                ⟨"#x", .definition, .prim (.string "hi")⟩,
                ⟨"out", .regular, .struct [⟨"val", .regular, .prim (.string "hi")⟩] true⟩
              ]
              false⟩
        ]
        true) = true := by
  native_decide

/-! ## `Value.closure` constructor — slice 1 (closure-ctor) round-trip pins

The constructor is inert (no producer yet); these theorems lock its identity so the later
producer/meet slices can't silently corrupt hashing or comparison. -/

/-- A closure `BEq`-compares equal to itself (derived `BEq` extends to the new arm). -/
theorem closure_beq_self :
    ((Value.closure [(0, [⟨"#name", .definition, .kind .string⟩])] (.ref "#name"))
      == (Value.closure [(0, [⟨"#name", .definition, .kind .string⟩])] (.ref "#name")))
      = true := by
  native_decide

/-- A different captured env makes two closures compare unequal — the captured ids carry
    the "independently-built frames never falsely share" invariant into `BEq`. -/
theorem closure_beq_distinct_env :
    ((Value.closure [(0, [⟨"#name", .definition, .kind .string⟩])] (.ref "#name"))
      == (Value.closure [(1, [⟨"#name", .definition, .kind .string⟩])] (.ref "#name")))
      = false := by
  native_decide

/-- A different body makes two closures compare unequal. -/
theorem closure_beq_distinct_body :
    ((Value.closure [(0, [])] (.ref "a")) == (Value.closure [(0, [])] (.ref "b")))
      = false := by
  native_decide

/-- The closure tag is its own bucket in the memo hash (no collision with other arms). -/
theorem closure_valueTag :
    valueTag (.closure [(0, [])] .top) = 29 := by
  native_decide

/-! ### slice 2 (closure-eval) — forcing the deferred body under its captured env

The eval arm forces `body` against `capturedEnv` (lexical scope), discarding the call-site
env/visited. No producer yet ⇒ these run on hand-built `.closure` literals, but they pin the
semantic anchor slices 3-4 target. -/

/-- Forcing a closure evaluates its body under the captured env: a depth-0 ref into the
    captured frame resolves to that frame's binding, proving the body sees `capturedEnv`. -/
theorem closure_eval_forces_captured_binding :
    (runEval (evalValueWithFuel evalFuel [] []
        (.closure [(7, [⟨"x", .regular, .prim (.int 42)⟩])] (.refId ⟨0, 0⟩)))
      == .prim (.int 42)) = true := by
  native_decide

/-- A closure with an empty captured env forces a body that needs no scope to a literal. -/
theorem closure_eval_empty_captured_env :
    (runEval (evalValueWithFuel evalFuel [] []
        (.closure [] (.prim (.int 1))))
      == .prim (.int 1)) = true := by
  native_decide

/-- A closure whose body is itself a closure forces through both layers (nested force):
    the inner closure carries its own captured frame, resolved when the outer body forces. -/
theorem closure_eval_nested_closure :
    (runEval (evalValueWithFuel evalFuel [] []
        (.closure []
          (.closure [(9, [⟨"y", .regular, .prim (.string "inner")⟩])] (.refId ⟨0, 0⟩))))
      == .prim (.string "inner")) = true := by
  native_decide

/-- Lexical, not dynamic, scope: the call-site env binds slot 0 to one value, the captured
    env binds it to another. The closure resolves against the captured env — its definition
    site — so the call-site binding (which would win under dynamic scope) is ignored. -/
theorem closure_eval_lexical_not_dynamic :
    (runEval (evalValueWithFuel evalFuel
        [(3, [⟨"x", .regular, .prim (.string "callsite")⟩])] []
        (.closure [(7, [⟨"x", .regular, .prim (.string "captured")⟩])] (.refId ⟨0, 0⟩)))
      == .prim (.string "captured")) = true := by
  native_decide

/-- Fuel exhaustion degrades like every other arm — at `fuel = 0` the closure passes
    through unevaluated rather than crashing or looping. -/
theorem closure_eval_fuel_exhaustion :
    (runEval (evalValueWithFuel 0 []
        [] (.closure [(7, [⟨"x", .regular, .prim (.int 42)⟩])] (.refId ⟨0, 0⟩)))
      == .closure [(7, [⟨"x", .regular, .prim (.int 42)⟩])] (.refId ⟨0, 0⟩)) = true := by
  native_decide

/-- Inert manifest: an unforced closure is non-concrete (incomplete). -/
theorem closure_manifest_incomplete :
    manifest (.closure [(0, [])] (.prim (.int 1)))
      = .error (.incomplete (.closure [(0, [])] (.prim (.int 1)))) := by
  rfl

/-- Inert meet: a closure does not unify with anything yet (slice 4 changes this). -/
theorem closure_meet_bottom :
    (meet (.closure [(0, [])] .top) (.struct [] true) == .bottom) = true := by
  native_decide

/-! ### slice 3 (closure-producer) — the import-selector arm emits a closure

White-box pins: closures are not user-visible until slice 4, so these assert the producer
CONSTRUCTS the right `.closure` (full id-stack captured, unevaluated def body) at the
trigger site, and — critically — that the shapes which currently resolve correctly do NOT
become closures. `runEval` starts `nextFrameId := 0`, so the producer's first `pushFrame`
captures frame id `0`. -/

/-- The collapse shape: a package struct `parts` holding a definition `#M` whose body
    self-references a sibling (`out: #name`, `refId ⟨0,0⟩`). Selecting `parts.#M` OUTSIDE a
    conjunction defers to a closure, then FORCES it standalone (no use-operands) — the terminal
    value when there is no use-site to splice. With no narrowing, `out: #name` collapses against
    the def's own `#name: string`, so the forced result is `{#name: string, out: string}`,
    normalized-CLOSED (`open_ := false`). (A `pkg.#M & {narrow}` instead splices the narrowing via
    the `.conj` fold, which re-produces the closure from the raw selector — see
    `crosspkg_defmeet`.) -/
theorem closure_producer_emits_on_selfref_def :
    (runEval (evalValueWithFuel evalFuel
        [(7, [⟨"parts", .hidden,
          .struct [⟨"#M", .definition,
            .struct [⟨"#name", .definition, .kind .string⟩,
                     ⟨"out", .regular, .refId ⟨0, 0⟩⟩] true⟩] true⟩])] []
        (.selector (.refId ⟨0, 0⟩) "#M"))
      == .struct [⟨"#name", .definition, .kind .string⟩,
                  ⟨"out", .regular, .kind .string⟩] false) = true := by
  native_decide

/-- NON-REGRESSION: a definition WITHOUT a sibling self-reference (`#Widget` = flat
    `{name: string, size: int}`) stays on the eager path — selecting it yields the evaluated
    field, NOT a closure. This is every committed `pkg.#Def & {…}` fixture's shape; the gate
    must leave it untouched so slice 3 is byte-identical on all of them. -/
theorem closure_producer_skips_selfref_free_def :
    (runEval (evalValueWithFuel evalFuel
        [(7, [⟨"defs", .hidden,
          .struct [⟨"#Widget", .definition,
            .struct [⟨"name", .regular, .kind .string⟩,
                     ⟨"size", .regular, .kind .int⟩] true⟩] true⟩])] []
        (.selector (.refId ⟨0, 0⟩) "#Widget"))
      == .struct [⟨"name", .regular, .kind .string⟩,
                  ⟨"size", .regular, .kind .int⟩] true) = true := by
  native_decide

/-- NON-REGRESSION: a NON-definition field (regular, not `#`) with a sibling self-ref is NOT
    a definition selection, so it stays eager — only `#`-definitions defer. -/
theorem closure_producer_skips_non_definition :
    (runEval (evalValueWithFuel evalFuel
        [(7, [⟨"pkg", .hidden,
          .struct [⟨"r", .regular,
            .struct [⟨"a", .regular, .prim (.int 1)⟩,
                     ⟨"b", .regular, .refId ⟨0, 0⟩⟩] true⟩] true⟩])] []
        (.selector (.refId ⟨0, 0⟩) "r"))
      == .struct [⟨"a", .regular, .prim (.int 1)⟩,
                  ⟨"b", .regular, .prim (.int 1)⟩] true) = true := by
  native_decide

/-- FULL ID-STACK capture: the producer captures the ENTIRE env (not just the package frame)
    when building the closure, so a def body's depth>0 cross-package embeds still walk the import
    chain when forced. Selected standalone (no conjunction), the closure is forced with no
    use-operands; `out: refId ⟨0,1⟩` reads the def's own sibling slot 1 (`x`), so the forced
    result is `{out: 1, x: 1}`, normalized-CLOSED. The outer frame 7 is retained beneath the
    pushed package frame — the capture is the full id-stack, not just the package frame. -/
theorem closure_producer_captures_full_id_stack :
    (runEval (evalValueWithFuel evalFuel
        [(5, [⟨"parts", .hidden,
          .struct [⟨"#M", .definition,
            .struct [⟨"out", .regular, .refId ⟨0, 1⟩⟩,
                     ⟨"x", .regular, .prim (.int 1)⟩] true⟩] true⟩]),
         (7, [⟨"outer", .regular, .prim (.int 9)⟩])] []
        (.selector (.refId ⟨0, 0⟩) "#M"))
      == .struct [⟨"out", .regular, .prim (.int 1)⟩,
                  ⟨"x", .regular, .prim (.int 1)⟩] false) = true := by
  native_decide

/-- DEPTH-MATCHED self-ref detection (slice A): a `refId ⟨0,0⟩` nested inside a `.struct` field
    is depth-0 relative to that NESTED frame, NOT the def body — `hasSelfRefAtDepth` descends to
    depth 1 there, so `⟨0,0⟩` (`d == 0 ≠ 1`) is the nested frame's own sibling, not the def's. So
    a def whose only inner ref sits in a nested struct and points at THAT frame is not a def
    self-ref and stays eager. Pins the boundary that keeps the gate from over-firing. -/
theorem closure_producer_nested_struct_ref_not_sibling :
    (defBodyHasSiblingSelfRef
        (.struct [⟨"a", .regular, .prim (.int 1)⟩,
                  ⟨"nested", .regular,
                    .struct [⟨"inner", .regular, .refId ⟨0, 0⟩⟩] true⟩] true)) = false := by
  native_decide

/-- And the positive companion: a direct sibling ref IS detected. -/
theorem closure_producer_direct_sibling_ref_detected :
    (defBodyHasSiblingSelfRef
        (.struct [⟨"#name", .definition, .kind .string⟩,
                  ⟨"out", .regular, .refId ⟨0, 0⟩⟩] true)) = true := by
  native_decide

/-- DEEP self-ref (slice A — the real-app shape): a hidden field read from a NESTED struct
    (`spec: acme: email: #email`, where `#email` is a top-level def field referenced from 3
    frames deep → `refId ⟨3, _⟩`) IS a def self-ref. `hasSelfRefAtDepth` descends `spec`(1),
    `acme`(2), then matches `refId ⟨2, 0⟩` at depth 2 — `d == depth` lands on the def frame. This
    is exactly the shape `#ClusterIssuer`/`#Secret` use that slice 4's depth-0-only gate missed. -/
theorem closure_producer_deep_nested_self_ref_detected :
    (defBodyHasSiblingSelfRef
        (.struct [⟨"#email", .definition, .kind .string⟩,
                  ⟨"spec", .regular,
                    .struct [⟨"acme", .regular,
                      .struct [⟨"email", .regular, .refId ⟨2, 0⟩⟩] true⟩] true⟩] true)) = true := by
  native_decide

/-- DEEP self-ref in a comprehension GUARD (slice A): `if Self.#staging` inside a nested struct
    references the def's `#staging` from the guard condition, which `hasSelfRefAtDepth` scans at
    the comprehension's own depth. A `refId ⟨1, 0⟩` in a guard one struct deep matches depth 1. -/
theorem closure_producer_comprehension_guard_self_ref_detected :
    (defBodyHasSiblingSelfRef
        (.struct [⟨"#staging", .definition, .kind .bool⟩,
                  ⟨"spec", .regular,
                    .structComp [] [.comprehension [.guard (.refId ⟨1, 0⟩)]
                      (.struct [⟨"server", .regular, .prim (.string "x")⟩] true)] true⟩] true)) = true := by
  native_decide

/-! ### slice 4 (closure-meet) — splice the use-site struct into the forced def body

THE unlock: `defs.#M & {#name: "keel"}` where `#M = {#name: string, out: #name}` is an
imported self-referential definition. The `.conj` fallback evaluates `defs.#M` to a closure
(slice 3) and `{#name: "keel"}` to a struct; instead of the inert `meet` (→ `.bottom`), the
closure is forced with the use-site spliced in as an extra conjunct, so `out`'s `#name` ref
sees the narrowed `"keel"` instead of collapsing to `string`. The env mirrors the producer
tests (package binding at frame 7); `runEval` allocates the closure's pushed frame ids. -/

private def pkgEnvWith (defBody : Value) : Env :=
  [(7, [⟨"parts", .hidden, .struct [⟨"#M", .definition, defBody⟩] true⟩])]

private def selfRefM : Value :=
  .struct [⟨"#name", .definition, .kind .string⟩, ⟨"out", .regular, .refId ⟨0, 0⟩⟩] true

/-- THE unlock pinned: forcing `parts.#M & {#name: "keel"}` yields `out: "keel"` (the hidden
    `#name` and the spliced narrowing resolve), NOT the slice-3 `.bottom`. Body is closed
    (`open_ := false`) because `#M` is a definition. -/
theorem closure_meet_splices_use_site :
    (runEval (evalValueWithFuel evalFuel (pkgEnvWith selfRefM) []
        (.conj [.selector (.refId ⟨0, 0⟩) "#M",
                .struct [⟨"#name", .definition, .prim (.string "keel")⟩] true]))
      == .struct [⟨"#name", .definition, .prim (.string "keel")⟩,
                  ⟨"out", .regular, .prim (.string "keel")⟩] false) = true := by
  native_decide

/-- CONFLICT → bottom: the use-site narrows `#name` to a value the def's own `#name` rejects
    (def `#name: "fixed"`, use-site `#name: "keel"`). The splice unifies the two `#name`
    conjuncts → a primitive conflict, which propagates through `#name`'s spliced slot AND
    `out`'s ref to it as a field-local `.bottomWith`; export then rejects the struct. -/
theorem closure_meet_conflict_is_bottom :
    (runEval (evalValueWithFuel evalFuel
        (pkgEnvWith (.struct [⟨"#name", .definition, .prim (.string "fixed")⟩,
                              ⟨"out", .regular, .refId ⟨0, 0⟩⟩] true)) []
        (.conj [.selector (.refId ⟨0, 0⟩) "#M",
                .struct [⟨"#name", .definition, .prim (.string "keel")⟩] true]))
      == .struct
          [⟨"#name", .definition,
            .bottomWith [.primitiveConflict (.string "fixed") (.string "keel")]⟩,
           ⟨"out", .regular,
            .bottomWith [.primitiveConflict (.string "fixed") (.string "keel")]⟩] false) = true := by
  native_decide

/-- EMPTY use-site: `parts.#M & {}` == `parts.#M` — splicing zero use fields leaves the def
    body unchanged (here `#name` stays `string`, so `out` is `string`). -/
theorem closure_meet_empty_use_site :
    (runEval (evalValueWithFuel evalFuel (pkgEnvWith selfRefM) []
        (.conj [.selector (.refId ⟨0, 0⟩) "#M", .struct [] true]))
      == .struct [⟨"#name", .definition, .kind .string⟩,
                  ⟨"out", .regular, .kind .string⟩] false) = true := by
  native_decide

/-- SELF-REF captured frame TERMINATES (does not loop / exhaust fuel): a def field referencing
    itself directly (`loop: loop`, `refId ⟨0,1⟩` at its own slot) is caught by the ordinary
    `slotVisited` machinery on the pushed frame and resolves to `.top` rather than diverging.
    `out` still resolves to the spliced `#name`. -/
theorem closure_meet_self_ref_terminates :
    (runEval (evalValueWithFuel evalFuel
        (pkgEnvWith (.struct [⟨"#name", .definition, .kind .string⟩,
                              ⟨"loop", .regular, .refId ⟨0, 1⟩⟩,
                              ⟨"out", .regular, .refId ⟨0, 0⟩⟩] true)) []
        (.conj [.selector (.refId ⟨0, 0⟩) "#M",
                .struct [⟨"#name", .definition, .prim (.string "keel")⟩] true]))
      == .struct [⟨"#name", .definition, .prim (.string "keel")⟩,
                  ⟨"loop", .regular, .top⟩,
                  ⟨"out", .regular, .prim (.string "keel")⟩] false) = true := by
  native_decide

/-- OPEN def body (`...` → `.structTail`): the use-site may add a field absent from the def,
    and it appears in the output; `out` still sees the narrowed `#name`. The forced body stays
    a `.structTail` (open). -/
theorem closure_meet_open_def_admits_extra :
    (runEval (evalValueWithFuel evalFuel
        (pkgEnvWith (.structTail [⟨"#name", .definition, .kind .string⟩,
                                  ⟨"out", .regular, .refId ⟨0, 0⟩⟩] .top)) []
        (.conj [.selector (.refId ⟨0, 0⟩) "#M",
                .struct [⟨"#name", .definition, .prim (.string "keel")⟩,
                         ⟨"extra", .regular, .prim (.int 42)⟩] true]))
      == .structTail [⟨"#name", .definition, .prim (.string "keel")⟩,
                      ⟨"out", .regular, .prim (.string "keel")⟩,
                      ⟨"extra", .regular, .prim (.int 42)⟩] .top) = true := by
  native_decide

/-- The producer NOW also fires on an OPEN (`.structTail`) self-ref def body (slice 4 extends
    `defBodyHasSiblingSelfRef` to `.structTail`), so open imported defs defer too. -/
theorem closure_producer_detects_structtail_sibling :
    (defBodyHasSiblingSelfRef
        (.structTail [⟨"#name", .definition, .kind .string⟩,
                      ⟨"out", .regular, .refId ⟨0, 0⟩⟩] .top)) = true := by
  native_decide

/-! ### slice A (closure-realapp-selfalias) — multi-operand fold + `.structComp` embed defs

Real prod9 apps use value-alias defs that EMBED cross-package defs
(`#Def: { parts.#Metadata; #x: string; spec: #x }`). The embed makes the def body a
`.structComp` (the parser routes embeddings into `structComp.comprehensions`), which slice 4's
gate/force/embedding-meet paths all dropped. Slice A: (A.1) gate fires on `.structComp` siblings,
(A.2) the force path splices use-operands into a `.structComp` body and meet-folds its
embeddings, (A.3) the `.conj` fold splices the SHARED use set into EVERY closure operand, (A.4)
an embedding/operand that evaluated to a `.closure` is force-spliced not plain-`meet`-ed. -/

/-- A.1 GATE: a `.structComp` def body (an embedding-bearing def) with a sibling self-ref in its
    static fields IS detected — slice 4's gate only matched `.struct`/`.structTail`, so an
    embed-def returned `false` and never deferred. -/
theorem closure_producer_detects_structcomp_sibling :
    (defBodyHasSiblingSelfRef
        (.structComp [⟨"#x", .definition, .kind .string⟩,
                      ⟨"spec", .regular, .refId ⟨0, 1⟩⟩]
                     [.struct [⟨"kind", .regular, .prim (.string "Service")⟩] true] true)) = true := by
  native_decide

/-- A.1 GATE companion: a `.structComp` whose self-ref lives in the EMBEDDING (not the static
    fields) is also detected — the gate scans comprehensions too. -/
theorem closure_producer_detects_structcomp_embedding_sibling :
    (defBodyHasSiblingSelfRef
        (.structComp [⟨"#x", .definition, .kind .string⟩]
                     [.refId ⟨0, 0⟩] true)) = true := by
  native_decide

/-- A.2 FORCE `.structComp`: `parts.#Def & {#x: "hello"}` where `#Def` embeds a literal struct
    `{kind: "Service"}` and has a self-ref `spec: #x`. The force splices `{#x:"hello"}` into the
    static fields BEFORE evaluating, so `spec` sees `"hello"`, AND meet-folds the embedding so
    `kind` appears. Was `incomplete value: string` (eager collapse) pre-slice-A. -/
private def embedDefBody : Value :=
  .structComp [⟨"#x", .definition, .kind .string⟩,
               ⟨"spec", .regular, .refId ⟨0, 0⟩⟩]
              [.struct [⟨"kind", .regular, .prim (.string "Service")⟩] true] true

theorem closure_meet_structcomp_embed_splices :
    (runEval (evalValueWithFuel evalFuel
        [(7, [⟨"defs", .hidden, .struct [⟨"#Def", .definition, embedDefBody⟩] true⟩])] []
        (.conj [.selector (.refId ⟨0, 0⟩) "#Def",
                .struct [⟨"#x", .definition, .prim (.string "hello")⟩] true]))
      == .struct [⟨"#x", .definition, .prim (.string "hello")⟩,
                  ⟨"spec", .regular, .prim (.string "hello")⟩,
                  ⟨"kind", .regular, .prim (.string "Service")⟩] false) = true := by
  native_decide

/-- A.3 MULTI-OPERAND FOLD: `#M & #N & {narrow}` — two self-ref imported defs met with one
    use-site struct narrowing BOTH. Slice 4 spliced only the first closure (`#M`); the second
    (`#N`) was forced UNSPLICED → `tag: #label` collapsed → `incomplete value: string`. The fold
    splices the shared use set into BOTH. `#M = {#name, out:#name}`, `#N = {#label, tag:#label}`,
    both open (`...`) so they admit each other's fields. -/
private def twoDefEnv : Env :=
  [(7, [⟨"defs", .hidden,
    .struct
      [⟨"#M", .definition,
        .structTail [⟨"#name", .definition, .kind .string⟩,
                     ⟨"out", .regular, .refId ⟨0, 0⟩⟩] .top⟩,
       ⟨"#N", .definition,
        .structTail [⟨"#label", .definition, .kind .string⟩,
                     ⟨"tag", .regular, .refId ⟨0, 0⟩⟩] .top⟩] true⟩])]

theorem closure_meet_multi_operand_fold :
    (runEval (evalValueWithFuel evalFuel twoDefEnv []
        (.conj [.selector (.refId ⟨0, 0⟩) "#M",
                .selector (.refId ⟨0, 0⟩) "#N",
                .struct [⟨"#name", .definition, .prim (.string "keel")⟩,
                         ⟨"#label", .definition, .prim (.string "x")⟩] true]))
      == .structTail [⟨"#name", .definition, .prim (.string "keel")⟩,
                      ⟨"out", .regular, .prim (.string "keel")⟩,
                      ⟨"#label", .definition, .prim (.string "x")⟩,
                      ⟨"tag", .regular, .prim (.string "x")⟩] .top) = true := by
  native_decide

/-- GENUINE CAPTURED-FRAME CYCLE termination (replaces the weak depth-0-slot
    `closure_meet_self_ref_terminates`): the closure's CAPTURED package frame contains a binding
    `#Self` that refs BACK into the def at depth 1 (`refId ⟨1, 0⟩` — out of the def's own frame,
    into the package frame, at `#Self`'s own slot → a capture-level self-loop). Forcing must
    terminate (→ `.top` for the cyclic slot) rather than diverge / exhaust fuel. -/
private def capturedCycleEnv : Env :=
  [(7, [⟨"pkg", .hidden,
    .struct
      [⟨"#Self", .definition, .refId ⟨0, 0⟩⟩,
       ⟨"#M", .definition,
        .struct [⟨"#name", .definition, .kind .string⟩,
                 ⟨"back", .regular, .refId ⟨1, 0⟩⟩,
                 ⟨"out", .regular, .refId ⟨0, 0⟩⟩] true⟩] true⟩])]

theorem closure_meet_captured_frame_cycle_terminates :
    (runEval (evalValueWithFuel evalFuel capturedCycleEnv []
        (.conj [.selector (.refId ⟨0, 0⟩) "#M",
                .struct [⟨"#name", .definition, .prim (.string "keel")⟩] true]))
      == .struct [⟨"#name", .definition, .prim (.string "keel")⟩,
                  ⟨"back", .regular, .top⟩,
                  ⟨"out", .regular, .prim (.string "keel")⟩] false) = true := by
  native_decide

/-! ### slice E (closure-embed-chain) — multi-level embed chains + the closedness leak.

The 3-level real shape `#ClusterIssuer → parts.#Metadata → attr.#Metadata` collapsed to `bottom`.
TWO independent root causes (both fixed here): (E1) the eager `.structComp` eval arm and the
non-closure branch of `meetEmbeddingsWithFuel` let an embedded CLOSED struct impose its closedness
on the host's regular fields → `.bottom` (slice A's hidden-only embeds dodged it). (E2) a bare ref
to a self-ref def the lazy-merge path can't splice — an embed-bearing `.structComp` (any depth) or a
NESTED (`depth > 0`) `.struct`/`.structTail` (the inner def of an embed chain) — was evaluated
eagerly, collapsing its self-ref before the use-site narrowing arrived. Fix: producers
(`refDefClosureBody?`/`conjDefClosure?`) defer them to `.closure`s the force-fold splices. -/

/-- E1 CLOSEDNESS LEAK (the closedness rule, isolated): `closeEmbeddedOver` re-closes a meet-folded
    struct over `def ∪ embed` labels — a field declared by neither the def nor any embedding is
    rejected, one declared by EITHER survives. This is what lets an embedding widen the host's
    allowed set without imposing its own closedness. -/
theorem close_embedded_over_unions_allowed_labels :
    (closeEmbeddedOver [⟨"a", .regular, .top⟩] [⟨"b", .regular, .top⟩] false
        (.struct [⟨"a", .regular, .prim (.int 1)⟩,
                  ⟨"b", .regular, .prim (.int 2)⟩,
                  ⟨"c", .regular, .prim (.int 3)⟩] true)
      == .struct [⟨"a", .regular, .prim (.int 1)⟩,
                  ⟨"b", .regular, .prim (.int 2)⟩,
                  ⟨"c", .regular, .bottomWith [.fieldNotAllowed "c"]⟩] false) = true := by
  native_decide

/-- E1 EAGER ARM: embedding a CLOSED struct `{pval}` (a `#`-def's value) into an OPEN host that
    carries a regular `x` keeps BOTH — the closed embed must NOT reject the host's `x`. Was
    `x: bottomWith [fieldNotAllowed "x"]` pre-E (the embed's closedness leaked onto the host). -/
theorem eager_structcomp_embed_closed_keeps_host_field :
    (runEval (evalValueWithFuel evalFuel [] []
        (.structComp [⟨"x", .regular, .prim (.string "z")⟩]
                     [.struct [⟨"pval", .regular, .prim (.string "p")⟩] false] true))
      == .struct [⟨"x", .regular, .prim (.string "z")⟩,
                  ⟨"pval", .regular, .prim (.string "p")⟩] true) = true := by
  native_decide

/-- E2 + the headline: the 2-LEVEL embed chain, cue-exact. `#Outer` (a `.structComp`) embeds
    `#Inner & {#name: Self.#oname}`; the use-site `#Outer & {#oname: "z"}` narrows `#oname`, which
    flows into the embed's `#name`, which the inner def's `iname: Self.#name` reads → all "z". Was
    `bottom` (closedness leak), then `iname: string` (inner closure not force-spliced) pre-fix. -/
private def chainInnerBody : Value :=
  .struct [⟨"#name", .definition, .kind .string⟩,
           ⟨"iname", .regular, .refId ⟨0, 0⟩⟩] true

private def chainOuterBody : Value :=
  .structComp
    [⟨"#oname", .definition, .kind .string⟩,
     ⟨"oname", .regular, .refId ⟨0, 0⟩⟩]
    [.conj [.refId ⟨1, 0⟩,
            .struct [⟨"#name", .definition, .refId ⟨1, 0⟩⟩] true]]
    true

private def chainEnv : Env :=
  [(7, [⟨"#Inner", .definition, chainInnerBody⟩,
        ⟨"#Outer", .definition, chainOuterBody⟩])]

theorem embed_chain_two_level_narrows_through :
    (runEval (evalValueWithFuel evalFuel chainEnv []
        (.conj [.refId ⟨0, 1⟩,
                .struct [⟨"#oname", .definition, .prim (.string "z")⟩] true]))
      == .struct [⟨"#oname", .definition, .prim (.string "z")⟩,
                  ⟨"oname", .regular, .prim (.string "z")⟩,
                  ⟨"#name", .definition, .prim (.string "z")⟩,
                  ⟨"iname", .regular, .prim (.string "z")⟩] false) = true := by
  native_decide

/-- E2 STANDALONE: the SAME `#Outer` selected WITHOUT a use-site narrowing forces to its own value
    (the bare-ref producer forces standalone, no splice) — `#oname`/`oname`/`iname` stay `string`,
    not `bottom` or a leaked `.closure`. Pins that the standalone force terminates and is concrete. -/
theorem embed_chain_two_level_standalone_forces :
    (runEval (evalValueWithFuel evalFuel chainEnv [] (.refId ⟨0, 1⟩))
      == .struct [⟨"#oname", .definition, .kind .string⟩,
                  ⟨"oname", .regular, .kind .string⟩,
                  ⟨"#name", .definition, .kind .string⟩,
                  ⟨"iname", .regular, .kind .string⟩] false) = true := by
  native_decide

/-- E2 CONFLICT → bottom: the outer fixes `iname: "fixed"` but the inner embed sets `iname` to the
    chain-narrowed `#name = #oname = "z"` → a genuine conflict, matching cue's `bottom`. The
    narrowing propagates correctly AND the conflict is honestly reported (the fix does not paper
    over a real conflict by dropping the chain). -/
private def chainConflictOuterBody : Value :=
  .structComp
    [⟨"#oname", .definition, .kind .string⟩,
     ⟨"iname", .regular, .prim (.string "fixed")⟩]
    [.conj [.refId ⟨1, 0⟩,
            .struct [⟨"#name", .definition, .refId ⟨1, 0⟩⟩] true]]
    true

private def chainConflictEnv : Env :=
  [(7, [⟨"#Inner", .definition, chainInnerBody⟩,
        ⟨"#Outer", .definition, chainConflictOuterBody⟩])]

theorem embed_chain_inner_conflict_is_bottom :
    (runEval (evalValueWithFuel evalFuel chainConflictEnv []
        (.conj [.refId ⟨0, 1⟩,
                .struct [⟨"#oname", .definition, .prim (.string "z")⟩] true]))
      == .struct [⟨"#oname", .definition, .prim (.string "z")⟩,
                  ⟨"iname", .regular, .bottomWith [.fieldConflict "iname"]⟩,
                  ⟨"#name", .definition, .prim (.string "z")⟩] false) = true := by
  native_decide

/-- E2 NON-REGRESSION (the bare-ref producer does NOT over-fire): a DEPTH-0 `.struct` self-ref def
    ref keeps the lazy-merge path (`refDefClosureBody?` returns `none` for it), so `#M & {narrow}`
    still resolves exactly as before — the producer only fires for `.structComp` (any depth) or a
    NESTED `.struct`/`.structTail`. -/
theorem ref_def_closure_skips_depth0_struct :
    (refDefClosureBody?
        [(7, [⟨"#M", .definition,
          .struct [⟨"#name", .definition, .kind .string⟩,
                   ⟨"out", .regular, .refId ⟨0, 0⟩⟩] true⟩])] ⟨0, 0⟩
      == none) = true := by
  native_decide

/-- E2 producer FIRES for a NESTED (`depth > 0`) `.struct` self-ref def — the inner def of an embed
    chain, one frame deeper than the embedding's host, which `conjStructOperand?` (depth-0-only)
    cannot lazy-merge. `refDefClosureBody?` returns the normalized (closed) body. -/
theorem ref_def_closure_fires_for_nested_struct :
    (refDefClosureBody?
        [(5, []),
         (7, [⟨"#M", .definition,
          .struct [⟨"#name", .definition, .kind .string⟩,
                   ⟨"out", .regular, .refId ⟨0, 0⟩⟩] true⟩])] ⟨1, 0⟩).isSome = true := by
  native_decide

/-! ### F2 (structcomp-force-comprehension-loss) — a forced `.structComp` def's `if`/`for`
    guard must FIRE post-narrowing, and a struct embedding a guard-bearing def must DEFER so the
    use-site narrowing reaches the embedded guard before it collapses. -/

/-- THE HEADLINE: a forced cross-package structComp def `#M: {#x: int, if #x > 0 {y: #x}}` met
    with `{#x: 5}` expands its `if`-guard AFTER the splice, so `y: 5` appears — the force arm now
    mirrors the eager arm's `staticFields ++ expanded`. The forced body is selected as a `.closure`
    standalone, then the `.conj` fold splices `{#x: 5}` and forces it. Result: `{#x: 5, y: 5}`
    (`#x` hidden → manifests to `{y: 5}`). Before F2 the force arm dropped the guard → `{#x: 5}`. -/
theorem f2_force_structcomp_guard_fires_post_meet :
    (runEval (evalValueWithFuel evalFuel
        [(7, [⟨"pkg", .hidden,
          .struct [⟨"#M", .definition,
            .structComp [⟨"#x", .definition, .kind .int⟩]
              [.comprehension [.guard (.binary .gt (.refId ⟨0, 0⟩) (.prim (.int 0)))]
                (.struct [⟨"y", .regular, .refId ⟨1, 0⟩⟩] true)] true⟩] true⟩])] []
        (.conj [.selector (.refId ⟨0, 0⟩) "#M",
                .struct [⟨"#x", .definition, .prim (.int 5)⟩] true]))
      == .struct [⟨"#x", .definition, .prim (.int 5)⟩,
                  ⟨"y", .regular, .prim (.int 5)⟩] false) = true := by
  native_decide

/-- The guard does NOT fire when the narrowing fails it: `#M & {#x: -1}` → no `y`. Pins that the
    expansion is GATED on the guard condition, not unconditional. -/
theorem f2_force_structcomp_guard_does_not_fire :
    (runEval (evalValueWithFuel evalFuel
        [(7, [⟨"pkg", .hidden,
          .struct [⟨"#M", .definition,
            .structComp [⟨"#x", .definition, .kind .int⟩]
              [.comprehension [.guard (.binary .gt (.refId ⟨0, 0⟩) (.prim (.int 0)))]
                (.struct [⟨"y", .regular, .refId ⟨1, 0⟩⟩] true)] true⟩] true⟩])] []
        (.conj [.selector (.refId ⟨0, 0⟩) "#M",
                .struct [⟨"#x", .definition, .prim (.int (-1))⟩] true]))
      == .struct [⟨"#x", .definition, .prim (.int (-1))⟩] false) = true := by
  native_decide

/-- `bodyNeedsDefer` fires for a struct whose body EMBEDS a guard-bearing def — the embed-chain
    case `Outer: {#Inner}` where `#Inner` carries an `if`-guard self-ref. The embed is NOT a
    self-ref of `Outer`, so the direct `defBodyHasSiblingSelfRef` misses it; the recursive clause
    resolves the embed `#Inner` against env and detects its guard → `Outer` must defer so the
    use-site narrowing reaches `#Inner`. The env places `#Inner` at depth-1 (the binding scope). -/
theorem f2_body_needs_defer_through_embed :
    (bodyNeedsDefer
        [(0, []),
         (9, [⟨"#Inner", .definition,
            .structComp [⟨"#port", .definition, .kind .int⟩]
              [.comprehension [.guard (.binary .gt (.refId ⟨0, 0⟩) (.prim (.int 0)))]
                (.struct [⟨"ports", .regular, .refId ⟨1, 0⟩⟩] true)] true⟩])]
        evalFuel
        (.structComp [] [.refId ⟨1, 0⟩] true)) = true := by
  native_decide

/-- `bodyNeedsDefer` does NOT fire for a struct embedding a self-ref-FREE def — the recursion
    bottoms out (`#Plain` = `{a: 1}` has no sibling self-ref), so `Outer` stays on the eager path.
    Pins that the embed recursion does not over-fire (which would churn green fixtures). -/
theorem f2_body_needs_defer_skips_plain_embed :
    (bodyNeedsDefer
        [(0, []),
         (9, [⟨"#Plain", .definition,
            .struct [⟨"a", .regular, .prim (.int 1)⟩] true⟩])]
        evalFuel
        (.structComp [] [.refId ⟨1, 0⟩] true)) = false := by
  native_decide

/-! ### closure-import-selector-alias — a def aliased to (or embedding) an import-selector must
    DEFER through the package indirection. `#A: parts.#M`, then `defs.#A & {#name: "n"}` collapsed
    eagerly (kue `incomplete value: string`) because the producer only detected a DIRECT import
    selector, not one reached through ANOTHER def alias. `followAliasDefBody?` follows the
    selector/ref chain to the terminal `parts.#M` body AND its `parts` package frame, so the
    use-site conjunct splices at force time exactly as a direct `parts.#M & {…}` does. -/

/-- The `parts` package: `#M: {#name: string, name: #name}` (a self-ref def). -/
private def aliasPartsPkg : Value :=
  .struct [⟨"#M", .definition,
    .struct [⟨"#name", .definition, .kind .string⟩,
             ⟨"name", .regular, .refId ⟨0, 0⟩⟩] true⟩] true

/-- The `defs` package: imports `parts` (binding at index 0) and aliases `#A: parts.#M`
    (`parts` is `.refId ⟨0,0⟩` within the defs frame; index 1 is `#A`). -/
private def aliasDefsPkg : Value :=
  .struct [⟨"parts", .hidden, aliasPartsPkg⟩,
           ⟨"#A", .definition, .selector (.refId ⟨0, 0⟩) "#M"⟩] true

/-- THE HEADLINE: `defs.#A & {#name: "n"}` where `#A: parts.#M` forces THROUGH the alias to the
    `parts.#M` body, splicing the use-site narrowing → `{name: "n"}`. Before this slice the
    eager path resolved `parts.#M` in the defs frame first → `name: string` (incomplete). The
    use-site env binds `defs` at frame index 0. -/
theorem alias_import_selector_splices_use_site :
    (runEval (evalValueWithFuel evalFuel
        [(7, [⟨"defs", .hidden, aliasDefsPkg⟩])] []
        (.conj [.selector (.refId ⟨0, 0⟩) "#A",
                .struct [⟨"#name", .definition, .prim (.string "n")⟩] true]))
      == .struct [⟨"#name", .definition, .prim (.string "n")⟩,
                  ⟨"name", .regular, .prim (.string "n")⟩] false) = true := by
  native_decide

/-- `importDefClosureBody?` follows the alias to discover the deferring `parts.#M` body — it
    returns `some` even though `#A`'s OWN body (`parts.#M`) is a selector, not a struct. Pins
    that the alias-follow path is wired into the selector producer. -/
theorem alias_import_selector_producer_fires :
    (importDefClosureBody? [(7, [⟨"defs", .hidden, aliasDefsPkg⟩])] ⟨0, 0⟩ "#A").isSome = true := by
  native_decide

/-- `followAliasDefBody?` returns the terminal `parts.#M` body paired with the `parts` package
    frame (NOT the `defs` frame) — the captured frame must be where `name: #name` resolves. The
    frame env places the `defs` package fields (holding the `parts` binding at index 0) at depth 0. -/
private def aliasDefsFields : List Field :=
  [⟨"parts", .hidden, aliasPartsPkg⟩,
   ⟨"#A", .definition, .selector (.refId ⟨0, 0⟩) "#M"⟩]

theorem alias_follow_returns_terminal_parts_frame :
    (followAliasDefBody? evalFuel
        [(0, aliasDefsFields), (7, [])]
        aliasDefsFields
        (.selector (.refId ⟨0, 0⟩) "#M")).isSome = true := by
  native_decide

-- EMBED form (`#A: {parts.#M}`) is pinned cue-exact by the committed module fixture
-- `alias_import_selector_embed` — the hand-built in-memory env diverges from the loader's
-- `normalizeDefinitions` frame layout for the `.structComp` embed case, so it is covered
-- end-to-end through the CLI fixture rather than a fragile unit AST.

/-- TWO-LEVEL alias indirection: `#A: parts.#M`, `#B: #A` (a `.refId` to `#A`), then
    `defs.#B & {#name: "n"}` follows the chain `#B → #A → parts.#M`. Pins that the follow
    recurses through a same-package `.refId` alias, not just one selector hop. -/
private def aliasDefsPkgTwoLevel : Value :=
  .struct [⟨"parts", .hidden, aliasPartsPkg⟩,
           ⟨"#A", .definition, .selector (.refId ⟨0, 0⟩) "#M"⟩,
           ⟨"#B", .definition, .refId ⟨0, 1⟩⟩] true

theorem alias_import_selector_two_level_splices :
    (runEval (evalValueWithFuel evalFuel
        [(7, [⟨"defs", .hidden, aliasDefsPkgTwoLevel⟩])] []
        (.conj [.selector (.refId ⟨0, 0⟩) "#B",
                .struct [⟨"#name", .definition, .prim (.string "n")⟩] true]))
      == .struct [⟨"#name", .definition, .prim (.string "n")⟩,
                  ⟨"name", .regular, .prim (.string "n")⟩] false) = true := by
  native_decide

/-- NO OVER-DEFERRAL: a def aliased to a NON-import-selector struct (`#A: {x: int}`, no self-ref)
    does NOT defer — `followAliasDefBody?` returns `none` for it, so the eager/lazy-merge path
    handles `defs.#A & {x: 5}` → `{x: 5}` exactly as before. Pins the gate stays narrow. -/
theorem alias_non_selector_does_not_defer :
    (importDefClosureBody?
        [(7, [⟨"defs", .hidden,
          .struct [⟨"#A", .definition, .struct [⟨"x", .regular, .kind .int⟩] true⟩] true⟩])]
        ⟨0, 0⟩ "#A") == none := by
  native_decide

/-- CYCLE SAFETY: a self-referential alias chain (`#A: #B`, `#B: #A`) terminates — the
    fuel-bounded follow does not diverge. `followAliasDefBody?` returns (terminating) for the
    cyclic body rather than looping forever; the result is `none` (no struct terminal reached). -/
theorem alias_follow_cycle_terminates :
    (followAliasDefBody? evalFuel
        [(0, [⟨"#A", .definition, .refId ⟨0, 1⟩⟩, ⟨"#B", .definition, .refId ⟨0, 0⟩⟩])]
        [⟨"#A", .definition, .refId ⟨0, 1⟩⟩, ⟨"#B", .definition, .refId ⟨0, 0⟩⟩]
        (.refId ⟨0, 1⟩)) == none := by
  native_decide

/-- DISJUNCTION SELECTION (argocd `#Secret` blocker, facet 1): selecting a field INTO a
    default disjunction (`d.a` where `d: *{a:1,c:9} | {a:2}`) collapses to the default arm
    first, then selects — CUE's default rule. Previously `selectEvaluatedField` had no `.disj`
    case and fell through to `.bottom`. -/
theorem select_into_default_disjunction :
    (selectEvaluatedField
      (.disj [(.default, .struct [⟨"a", .regular, .prim (.int 1)⟩, ⟨"c", .regular, .prim (.int 9)⟩] true),
              (.regular, .struct [⟨"a", .regular, .prim (.int 2)⟩] true)])
      "a"
      == .prim (.int 1)) = true := by
  native_decide

/-- NO OVER-FIRE: a NON-default disjunction with multiple live arms does NOT collapse on
    selection — it stays a deferred `.selector` (manifest then reports the ambiguity), never a
    spurious `bottom` and never a silent pick of one arm. -/
theorem select_into_nondefault_disjunction_defers :
    (selectEvaluatedField
      (.disj [(.regular, .struct [⟨"a", .regular, .prim (.int 1)⟩] true),
              (.regular, .struct [⟨"a", .regular, .prim (.int 2)⟩] true)])
      "a"
      == .selector
           (.disj [(.regular, .struct [⟨"a", .regular, .prim (.int 1)⟩] true),
                   (.regular, .struct [⟨"a", .regular, .prim (.int 2)⟩] true)])
           "a") = true := by
  native_decide

/-- EMBEDDED DEFAULT DISJUNCTION (argocd `#Secret` blocker, facet 2): an embedded default
    disjunction collapses to its default arm before merging into the host
    (`resolveEmbeddedDisjDefault`), so its fields land as regular host fields and a sibling
    `Self.a` resolves. A non-default disjunction passes through untouched. -/
theorem resolve_embedded_default_disjunction :
    (resolveEmbeddedDisjDefault
      (.disj [(.default, .struct [⟨"a", .regular, .prim (.int 1)⟩] true),
              (.regular, .struct [⟨"a", .regular, .prim (.int 2)⟩] true)])
      == .struct [⟨"a", .regular, .prim (.int 1)⟩] true) = true := by
  native_decide

theorem resolve_embedded_nondefault_disjunction_unchanged :
    (resolveEmbeddedDisjDefault
      (.disj [(.regular, .struct [⟨"a", .regular, .prim (.int 1)⟩] true),
              (.regular, .struct [⟨"b", .regular, .prim (.int 2)⟩] true)])
      == .disj [(.regular, .struct [⟨"a", .regular, .prim (.int 1)⟩] true),
                (.regular, .struct [⟨"b", .regular, .prim (.int 2)⟩] true)]) = true := by
  native_decide

/-- TWO-PASS GATE (perf): the embedding-`Self` re-evaluation fires ONLY when a static field
    selects `Self.<embedded-label>`. This pins the no-over-fire boundary that keeps cert-manager
    (a `parts.#Metadata` embed never read via `Self.metadata`) on the single-pass path. -/
theorem embedded_self_pass_fires_on_self_select :
    needsEmbeddedSelfPass
      [⟨"Self", .letBinding, .thisStruct⟩, ⟨"b", .regular, .selector (.refId ⟨0, 0⟩) "a"⟩]
      ["a"] = true := by
  native_decide

theorem embedded_self_pass_skips_unselected_embed_label :
    needsEmbeddedSelfPass
      [⟨"Self", .letBinding, .thisStruct⟩, ⟨"b", .regular, .selector (.refId ⟨0, 0⟩) "a"⟩]
      ["metadata"] = false := by
  native_decide

theorem embedded_self_pass_skips_when_no_self_select :
    needsEmbeddedSelfPass
      [⟨"Self", .letBinding, .thisStruct⟩, ⟨"b", .regular, .prim (.int 1)⟩]
      ["metadata"] = false := by
  native_decide

/-! ### argocd-secret-data sub-slice 1 — hidden-def embedding narrowing.

The argocd link-2 blocker: a hidden definition `_#OpaqueSecret` embedded into a host whose
use-site narrows a hidden field (`#data`). The embedded def's sibling self-ref (`data:
#data`, or a `for k,v in #data` comprehension) ran against the def's own ABSTRACT `#data`
before the use-site narrowing reached it → empty output instead of the populated map. Root
cause was a PARSER misclassification: `_#x` was tagged hidden-only (not a definition), so the
def-deferral path (`refDefClosureBody?`/`conjDefClosure?`) never fired for the embedding, and
the arm evaluated standalone (collapsing the self-ref) before the narrowing spliced in. Fixed
by classifying `_#x` as BOTH definition and hidden (see `parse_field_class_hidden_definition`).
Each pin is cue v0.16.1-exact. -/

-- HEADLINE: a `for k,v in #data` comprehension inside an embedded hidden-def populates AFTER
-- the use-site narrows `#data` (the secret-data shape). Pre-fix: `mapped: {}` (empty).
theorem hidden_def_embed_comprehension_narrows :
    evalSourceMatches
        "_#M: {#data: [string]: string, mapped: {for k, v in #data {\"\\(k)\": v}}}\n#S: {#data: [string]: string, _#M}\nout: #S & {#data: {a: \"x\"}}\n"
        "_#M: {#data: {[string]: string}, mapped: {}}\n#S: {#data: {[string]: string, [string]: string, [string]: string}, mapped: {}}\nout: {#data: {a: \"x\", [string]: string, [string]: string, [string]: string}, mapped: {a: \"x\"}}"
          = true := by
  native_decide

-- A plain SIBLING self-ref (`copy: #x`) in an embedded hidden-def sees the use-site narrowing
-- of `#x`. Pre-fix: `copy: string` (un-narrowed). The minimal scalar form of the headline.
theorem hidden_def_embed_sibling_narrows :
    evalSourceMatches
        "_#Hidden: {#x: string, copy: #x}\n#S: {#x: string, _#Hidden}\nout: #S & {#x: \"hi\"}\n"
        "_#Hidden: {#x: string, copy: string}\n#S: {#x: string, copy: string}\nout: {#x: \"hi\", copy: \"hi\"}"
          = true := by
  native_decide

-- EMPTY-NARROW (no over-population): narrowing the comprehension source to an empty struct
-- yields an empty `mapped`, matching cue — the comprehension iterates the NARROWED value, so
-- an empty narrowing is a real empty result, not a stale default.
theorem hidden_def_embed_comprehension_empty :
    evalSourceMatches
        "_#M: {#data: [string]: string, mapped: {for k, v in #data {\"\\(k)\": v}}}\n#S: {#data: [string]: string, _#M}\nout: #S & {#data: {}}\n"
        "_#M: {#data: {[string]: string}, mapped: {}}\n#S: {#data: {[string]: string, [string]: string, [string]: string}, mapped: {}}\nout: {#data: {[string]: string, [string]: string, [string]: string}, mapped: {}}"
          = true := by
  native_decide

-- A hidden definition is CLOSED (the parser fix's other half): `_#C & {a:1}` accepts the
-- declared `a`, `_#C & {a:1, b:2}` REJECTS the undeclared `b` (`b: _|_`). Pre-fix `_#C` was
-- open (hidden-only), so it wrongly admitted `b`. cue: "field not allowed".
theorem hidden_def_is_closed :
    evalSourceMatches
        "_#C: {a: int}\naccept: _#C & {a: 1}\nreject: _#C & {a: 1, b: 2}\n"
        "_#C: {a: int}\naccept: {a: 1}\nreject: {a: 1, b: _|_}" = true := by
  native_decide

-- NO-OVER-DEFER (regression): a plain `#Base` (non-hidden definition) embedding still narrows
-- correctly. The fix widened `_#x` classification without touching `#x`, so this stays green.
theorem plain_def_embed_sibling_narrows :
    evalSourceMatches
        "#Hidden: {#x: string, copy: #x}\n#S: {#x: string, #Hidden}\nout: #S & {#x: \"hi\"}\n"
        "#Hidden: {#x: string, copy: string}\n#S: {#x: string, copy: string}\nout: {#x: \"hi\", copy: \"hi\"}"
          = true := by
  native_decide

-- A comprehension over a CONCRETE source still expands EAGERLY (no over-defer): no use-site
-- narrowing involved, source is literal, so the map populates directly.
theorem hidden_def_embed_concrete_source :
    evalSourceMatches
        "_#M: {data: {x: \"1\", y: \"2\"}, mapped: {for k, v in data {\"\\(k)\": v}}}\nout: {_#M}\n"
        "_#M: {data: {x: \"1\", y: \"2\"}, mapped: {x: \"1\", y: \"2\"}}\nout: {data: {x: \"1\", y: \"2\"}, mapped: {x: \"1\", y: \"2\"}}"
          = true := by
  native_decide

/-! ### argocd-secret-data sub-slice 2 — embedded DEFAULT DISJUNCTION arm narrowing.

The exact argocd `#Secret` shape: a hidden-def `_#OpaqueSecret` in an embedded DEFAULT
DISJUNCTION arm `(*_#A | _#B)` whose body's `for k,v in #data` comprehension (or sibling
self-ref) is narrowed by the use-site. Pre-fix the disjunction evaluated standalone — its
default arm forced with NO use-operands collapsed the comprehension/self-ref BEFORE the
narrowing reached it (`resolveEmbeddedDisjDefault` picked the already-collapsed value).

Fix: DISTRIBUTE the narrowing into the disjunction arms at the UNEVALUATED level — both in
the `.conj` fold (`splitDisjConjunct`/`conjDisjArms?` → `*(_#A & narrow) | (_#B & narrow)`) and
in the embedded-disjunction merge (`meetEmbeddingsWithFuel` collapses to the default arm via
`conjDisjArms?` BEFORE deferral, so the arm force-splices the host's narrowing). `bodyNeedsDefer`
now recurses into a `.disj` embedding's default arm (`resolveEmbedDefBody?`), so the host defers.
Gated on a deferral-needing arm — a plain scalar/struct disjunction is untouched (no over-defer).
Each pin cue v0.16.1-exact. -/

-- HEADLINE: a `for k,v in #data` comprehension inside an embedded DEFAULT DISJUNCTION arm
-- populates AFTER the use-site narrows `#data` (the argocd `#Secret` shape). Pre-fix `mapped: {}`.
theorem disj_default_embed_comprehension_narrows :
    evalSourceMatches
        "_#A: {#data: [string]: string, mapped: {for k, v in #data {\"\\(k)\": v}}}\n_#B: {other: \"b\"}\n#S: {#data: [string]: string, (*_#A | _#B)}\nout: #S & {#data: {a: \"x\"}}\n"
        "_#A: {#data: {[string]: string}, mapped: {}}\n_#B: {other: \"b\"}\n#S: {#data: {[string]: string, [string]: string, [string]: string}, mapped: {}}\nout: {#data: {a: \"x\", [string]: string, [string]: string, [string]: string}, mapped: {a: \"x\"}}"
          = true := by
  native_decide

-- A plain SIBLING self-ref in an embedded DEFAULT DISJUNCTION arm sees the use-site narrowing.
-- Pre-fix `copy: string`. The minimal scalar form (matches `ds1`).
theorem disj_default_embed_sibling_narrows :
    evalSourceMatches
        "_#A: {#x: string, copy: #x}\n_#B: {#x: string, other: \"b\"}\n#S: {#x: string, (*_#A | _#B)}\nout: #S & {#x: \"hi\"}\n"
        "_#A: {#x: string, copy: string}\n_#B: {#x: string, other: \"b\"}\n#S: {#x: string, copy: string}\nout: {#x: \"hi\", copy: \"hi\"}"
          = true := by
  native_decide

-- EMPTY-NARROW through the disjunction (no over-population): empty `#data` → empty `mapped`.
theorem disj_default_embed_comprehension_empty :
    evalSourceMatches
        "_#A: {#data: [string]: string, mapped: {for k, v in #data {\"\\(k)\": v}}}\n_#B: {other: \"b\"}\n#S: {#data: [string]: string, (*_#A | _#B)}\nout: #S & {#data: {}}\n"
        "_#A: {#data: {[string]: string}, mapped: {}}\n_#B: {other: \"b\"}\n#S: {#data: {[string]: string, [string]: string, [string]: string}, mapped: {}}\nout: {#data: {[string]: string, [string]: string, [string]: string}, mapped: {}}"
          = true := by
  native_decide

-- NO-OVER-DEFER (scalar disjunction): a plain `*"prod" | "dev"` met with `string` keeps BOTH
-- arms (default preserved) — `conjDisjArms?` yields `none` (no deferral-needing arm), so the
-- standard distribute-at-meet path runs unchanged. A regression that over-deferred would alter it.
theorem disj_scalar_no_over_defer :
    evalSourceMatches "out: (*\"prod\" | \"dev\") & string\n" "out: *\"prod\" | \"dev\"" = true := by
  native_decide

-- NO-OVER-DEFER (struct disjunction, no sibling self-ref): `*{a:1,b:int} | {a:2}` met with
-- `{b:5}` distributes into BOTH arms at the meet, NOT via deferral (arms have no self-ref to
-- narrow). Confirms the deferral gate is tight on the embedded-disjunction-as-value path too.
theorem disj_struct_no_over_defer :
    evalSourceMatches
        "out: (*{a: 1, b: int} | {a: 2}) & {b: 5}\n"
        "out: *{a: 1, b: 5} | {a: 2, b: 5}" = true := by
  native_decide

/-- SATURATION GUARD (audit #6): `conjDisjArms?`'s `fuel = 0` arm returns `none` (declines to
    distribute) rather than dropping fields — it is NOT a truncation source, so it need not bump
    `truncCount`. Pin that the fuel-exhausted scan is a clean non-defer: at `fuel = 0` a
    `.refId`-bodied disjunction conjunct yields `none` (falls to the standard fold, which keeps
    its own bracketed truncation discipline). A regression that made it drop to a partial value
    without bumping would reopen the audit-#6 hole. -/
theorem conj_disj_arms_fuel_zero_declines :
    conjDisjArms? [(0, [])] 0 (.refId ⟨0, 0⟩) = none := by
  native_decide

end Kue
