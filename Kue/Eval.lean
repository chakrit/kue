import Kue.Builtin
import Kue.Decimal
import Kue.EvalOps
import Kue.Lattice
import Kue.Regex
import Kue.Normalize
import Std.Data.HashMap
import Kue.EvalDefer

namespace Kue

/-- The outcome of expanding a comprehension's clause chain, generic over the produced payload
    `β` (`List Field` for a STRUCT comprehension, `List Value` for a LIST comprehension). Three
    spec-distinct cases — a plain `Except Value (List Field)` cannot express the third,
    "defer":
    - `payload` — the comprehension resolved (concrete-true / `for`-expansion); emit these
      fields/elements.
    - `bottom` — a bottom must propagate out (D#1a evaluated-bottom guard, D#1c concrete-non-bool
      type error); the enclosing struct becomes that bottom.
    - `deferred` — an INCOMPLETE guard (D#1b): the comprehension cannot be decided yet, so the
      ORIGINAL `.comprehension`/`.listComprehension` node is kept residual (cue holds it under
      eval, errors incomplete under export). Nullary: the caller re-emits from the node it already
      holds.
    The struct/list twins differ ONLY in `β` and in the exhausted-chain (`[]`-clause) body
    handler — see `expandClauseChain` — so they share one outcome type and one driver. -/
inductive ClauseOutcome (β : Type) where
  | payload (value : β)
  | bottom (value : Value)
  | deferred

/-- A STRUCT comprehension's clause-chain outcome (`payload` carries the produced fields). -/
abbrev ClauseExpansion := ClauseOutcome (List Field)

/-- A LIST comprehension's clause-chain outcome (`payload` carries the produced elements);
    `bottom`/`deferred` mirror the struct twin (D#1a/c propagate, D#1b defers the whole
    `.listComprehension` residual). -/
abbrev ListClauseExpansion := ClauseOutcome (List Value)

/-- Stable monadic merge of two already-sorted runs under a monadic strict-less-than
    `lt`. Fuel = `left.length + right.length` (each step consumes one element), so the
    recursion is total. STABILITY: an element of `left` is emitted before an equal element
    of `right` unless `right`'s head is STRICTLY less (`lt rHead lHead`) — i.e. ties favor
    the left (earlier) run, which is what `list.SortStable` requires (and the unstable
    `list.Sort` tolerates). -/
def mergeRunsM (lt : Value -> Value -> EvalM Bool) :
    Nat -> List Value -> List Value -> EvalM (List Value)
  | 0, left, right => pure (left ++ right)
  | _ + 1, [], right => pure right
  | _ + 1, left, [] => pure left
  | fuel + 1, lHead :: lTail, rHead :: rTail => do
      if (<- lt rHead lHead) then
        let rest <- mergeRunsM lt fuel (lHead :: lTail) rTail
        pure (rHead :: rest)
      else
        let rest <- mergeRunsM lt fuel lTail (rHead :: rTail)
        pure (lHead :: rest)

/-- One bottom-up pass: merge adjacent runs pairwise (`[r0,r1,r2,r3,…]` ⇒
    `[merge r0 r1, merge r2 r3, …]`), halving the run count. Structural on the run list
    (two consumed per step), hence total. -/
def mergePassM (lt : Value -> Value -> EvalM Bool) :
    List (List Value) -> EvalM (List (List Value))
  | [] => pure []
  | [run] => pure [run]
  | a :: b :: rest => do
      let merged <- mergeRunsM lt (a.length + b.length) a b
      let restMerged <- mergePassM lt rest
      pure (merged :: restMerged)

/-- Bottom-up driver: repeat `mergePassM` until a single run remains. `fuel` bounds the
    number of passes (each pass at least halves the run count, so `runs.length` passes
    always suffice); structural decrement keeps it total. -/
def mergeRunsLoopM (lt : Value -> Value -> EvalM Bool) :
    Nat -> List (List Value) -> EvalM (List Value)
  | 0, runs => pure runs.flatten
  | _ + 1, [] => pure []
  | _ + 1, [run] => pure run
  | fuel + 1, runs => do
      let passed <- mergePassM lt runs
      mergeRunsLoopM lt fuel passed

/-- Total, stable monadic merge sort under a monadic strict-less-than `lt`. Seeds the
    bottom-up merge with singleton runs (already individually sorted), then merges passes
    to completion. Used by `list.Sort`/`list.SortStable`, whose comparator evaluates a CUE
    `{x, y, less}` struct per pair — an effectful (`EvalM`) comparison, so Lean's pure
    `List.mergeSort` does not apply. -/
def sortValuesM (lt : Value -> Value -> EvalM Bool) (items : List Value) :
    EvalM (List Value) :=
  mergeRunsLoopM lt items.length (items.map ([·]))

mutual
  def evalFieldRefsWithFuel
      (fuel : Nat)
      (env : Env)
      (visited : List Nat)
      (field : Field) : EvalM Field := do
    let evaluated <- evalValueWithFuel fuel env visited (Field.value field)
    pure { field with value := evaluated }
  termination_by (fuel, 2, 0)

  def evalFieldRefsListWithFuel
      (fuel : Nat)
      (env : Env)
      (indexed : List (Nat × Field)) : EvalM (List Field) := do
    match indexed with
    | [] => pure []
    | (index, field) :: rest =>
        let evaluated <- evalFieldRefsWithFuel fuel env [index] field
        let restEvaluated <- evalFieldRefsListWithFuel fuel env rest
        pure (evaluated :: restEvaluated)
  termination_by (fuel, 3, indexed.length)

  def evalValuesWithFuel
      (fuel : Nat)
      (env : Env)
      (visited : List Nat) : List Value -> EvalM (List Value)
    | [] => pure []
    | value :: rest => do
        let evaluated <- evalValueWithFuel fuel env visited value
        let restEvaluated <- evalValuesWithFuel fuel env visited rest
        pure (evaluated :: restEvaluated)
  termination_by values => (fuel, 3, values.length)

  /-- Evaluate a list's items, FLATTENING comprehension items. A plain item contributes one
      element; a `.listComprehension` contributes the zero-or-more elements its clause chain
      yields. Concatenation preserves source order, so plain elements and comprehensions
      interleave (`[1, for x in xs {x}, 2]`). -/
  def evalListItemsWithFuel
      (fuel : Nat)
      (env : Env)
      (visited : List Nat) : List Value -> EvalM (List Value)
    | [] => pure []
    | .listComprehension clauses body :: rest => do
        match (<- expandListClausesWithFuel fuel env clauses body) with
        | .bottom bot => pure [bot]
        | .deferred =>
            -- D#1b: an incomplete guard keeps the comprehension as a residual list ELEMENT (cue
            -- holds it under eval, errors incomplete under export) rather than dropping it.
            let restEvaluated <- evalListItemsWithFuel fuel env visited rest
            pure (.listComprehension clauses body :: restEvaluated)
        | .payload head =>
            let restEvaluated <- evalListItemsWithFuel fuel env visited rest
            pure (head ++ restEvaluated)
    | value :: rest => do
        let evaluated <- evalValueWithFuel fuel env visited value
        let restEvaluated <- evalListItemsWithFuel fuel env visited rest
        pure (evaluated :: restEvaluated)
  termination_by values => (fuel, 3, values.length)

  /-- Cached entry into the evaluator, with fuel-saturation caching.

      Lookup order: (1) the fuel-FREE `satCache` — a SATURATED result is fuel-insensitive, so a
      hit serves it at ANY remaining fuel and bumps NOTHING (a saturated value never touched the
      truncation counter, so the bracketing parent stays saturated). (2) the fuel-keyed `cache` —
      a hit of a `truncated` entry re-bumps `truncCount` so the bracketing parent still sees the
      truncation (cache-hit honesty); a `saturated` entry bumps nothing.

      On a miss, BRACKET the monotonic `truncCount`: snapshot before/after the core eval; the
      result is `saturated` iff the counter did not move (no `fuel = 0` base and no cycle `.top`
      anywhere in the transitive subtree). Store `(value, sat)` in the fuel-keyed `cache`; if
      saturated, ALSO store in the fuel-free `satCache` — the SINGLE insertion site, gated to the
      `saturated` arm, so a truncated value can never enter the fuel-free cache. -/
  def evalValueWithFuel
      (fuel : Nat)
      (env : Env)
      (visited : List Nat)
      (value : Value) : EvalM Value := do
    -- Fast path: an env-INDEPENDENT self-evaluating leaf (`selfEvaluatingLeaf?` — `.prim`,
    -- `.kind`, `.top`, `.bottom`, `.bottomWith`, `.notPrim`, `.stringRegex`,
    -- `.boundConstraint`, `.thisStruct`) is the identity of `evalValueCoreWithFuel` at every
    -- fuel `≥ 1` (the trailing `| _, value => pure value` arm, which reads none of
    -- `fuel`/`env`/`visited`), and at `fuel = 0` the core only adds a SPURIOUS truncation
    -- (`| 0, value => truncate value`) for a value that was never fuel-sensitive. Returning it
    -- directly is therefore value-identical AND saturation-correct: it removes only false
    -- `truncated` classifications a fuel-0 leaf would inject, never a genuine one (a subtree
    -- that truly needs fuel bottoms on a `.refId`/struct-unroll, which is NOT a leaf and still
    -- truncates). It also skips the satCache/cache probe+insert (each a `valueDigest` hash) for
    -- these leaves — the dominant flat-setup cost on a deep app: `.prim`+`.kind` alone are ~37%
    -- of argocd's core evals, re-keyed per distinct frame env. Sound: the leaf's value never
    -- depends on `env`, so caching it under an env-keyed key bought nothing but the hash cost.
    if selfEvaluatingLeaf? value then
      pure value
    else
    let satKey : SatKey := ⟨env.ids, visited, value⟩
    let st <- get
    match st.satCache.get? satKey with
    | some cached => do
        modify (fun state => { state with cacheHits := state.cacheHits + 1 })
        pure cached
    | none =>
      -- Fuel-keyed `cache` probe — but ONLY when it is non-empty. The `cache` holds ONLY the
      -- fuel-TRUNCATED population (saturated results go to `satCache`, gated below). An empty
      -- `cache` provably contains no key, so `cache.get? key = none` for EVERY key — skipping
      -- the probe is value-identical. Skipping also avoids the redundant `valueDigest
      -- DIGEST_DEPTH value` recomputation the `EvalKey` hash would do (the `SatKey` probe above
      -- already digested the SAME `value`) plus the `EvalKey` allocation. On a fully-saturating
      -- program (no truncation — the prod9 real apps, fuelInserts=0) the `cache` stays empty for
      -- the whole run, so this elides one full depth-3 digest traversal + an allocation + a
      -- HashMap probe on EVERY core eval. A program WITH truncation keeps the original behavior:
      -- once `cache` is populated the probe runs exactly as before.
      let fuelHit := if st.cache.isEmpty then none else st.cache.get? ⟨fuel, env.ids, visited, value⟩
      match fuelHit with
      | some (cached, sat) => do
          let bump := if sat == .truncated then 1 else 0
          modify (fun state => { state with cacheHits := state.cacheHits + 1, truncCount := state.truncCount + bump })
          pure cached
      | none =>
          let before := (<- get).truncCount
          modify (fun state => { state with evalCalls := state.evalCalls + 1 })
          let result <- evalValueCoreWithFuel fuel env visited value
          let after := (<- get).truncCount
          let sat : Saturation := if after == before then .saturated else .truncated
          match sat with
          | .saturated =>
              -- A saturated result is fuel-insensitive, so the fuel-free `satCache` (checked
              -- FIRST, before the fuel-keyed `cache`) serves it at every future lookup — the
              -- fuel-keyed `cache` entry would never be read (satCache always wins first). So
              -- store saturated results ONLY in `satCache`, never in `cache`; this keeps `cache`
              -- to the small fuel-TRUNCATED population, eliminating the per-eval cost of inserting
              -- every (overwhelmingly saturated) result into a second large map.
              modify (fun state => { state with satCache := state.satCache.insert satKey result })
          | .truncated =>
              -- A truncated result is fuel-SENSITIVE and is gated OUT of `satCache`; it must live
              -- in the fuel-keyed `cache` so a same-fuel re-lookup serves it (and re-bumps
              -- `truncCount` for cache-hit honesty).
              let key : EvalKey := ⟨fuel, env.ids, visited, value⟩
              modify (fun state => { state with cache := state.cache.insert key (result, sat) })
          pure result
  termination_by (fuel, 1, 0)

  def evalValueCoreWithFuel
      (fuel : Nat)
      (env : Env)
      (visited : List Nat)
      (value : Value) : EvalM Value := do
    match fuel, value with
    | 0, value => EvalState.truncate value
    | _ + 1, .ref label =>
        pure (.bottomWith [.unresolvedReference label])
    | fuel + 1, .refId id =>
        match env.drop id.depth.val with
        | [] => pure (.bottomWith [.unresolvedBinding id])
        | frame :: outer =>
            match nthField id.index.val frame.snd with
            | none => pure (.bottomWith [.unresolvedBinding id])
            | some field =>
              -- An UNSET OPTIONAL field reference resolves to ABSENT (`.bottom`), not its declared
              -- type — the resolution-time analog of `selectedFieldValue`'s optional-skip (Bug2-13).
              -- An optional declaration is a CONSTRAINT, not a value: until unification SUPPLIES the
              -- field (downgrading optionality to `.regular` via `mergeFieldClass`'s `lo.meet ro`), a
              -- reference/presence-test against it is `_|_`. The `.optional` rung itself is the
              -- discriminator, so a SET optional (now `.regular`) keeps resolving to its value, and a
              -- concrete-typed unset optional (`#opt?: 5`, still `.optional`) is still absent —
              -- presence, not concreteness, matching cue.
              match field.fieldClass.optionality with
              | .optional => pure .bottom
              | _ =>
                -- Producer (slice E): a bare ref to a self-ref def the lazy-merge can't handle
                -- (embed-bearing `.structComp`, or a nested `.struct`/`.structTail`) FORCES the def
                -- body against its own captured scope — forced HERE with no use-operands (a bare
                -- ref has no use-site to splice). When the ref sits inside a use-site conjunction
                -- (`#Outer & {#oname: "o"}`, or a nested embed `#Inner & {#name: …}`), the `.conj`
                -- fold re-produces the closure from the raw constraint (`conjDefClosure?`) and
                -- force-splices the narrowing — so the standalone force here is only ever the
                -- terminal value. The captured env is `frame :: outer` (the binding's scope): the
                -- body's depth-0 refs land on `frame`, its cross-pkg refs walk `outer`.
                match refDefClosureBody? env id with
                | some defBody => forceClosureWithConjunct fuel (frame :: outer) defBody []
                | none =>
                  -- Alias/import-selector indirection (`#B: parts.#M` / `#B: #A`, `#A: parts.#M`):
                  -- the body is not a directly-deferring struct, but follows the chain to one. Force
                  -- standalone over the TERMINAL package frame (the use-site splice, if any, comes
                  -- via the `.conj` fold re-producing through `refAliasSelectorDef?`).
                  match refAliasDefClosure? env id with
                  | some (capturedFrame, defBody) => do
                      let capturedEnv <- pushFrame capturedFrame env
                      forceClosureWithConjunct fuel capturedEnv defBody []
                  | none =>
                    -- Structural-cycle detection (D#2a). A ref whose resolved body is a STRUCT
                    -- re-evaluates that body with a fresh `visited`/frame — the unroll path. If the
                    -- SAME struct body is already in-progress on `structStack`, this re-entry is a
                    -- structural cycle (`#L: {next: #L}`, mutual `#A`/`#B`, regular `a: {next: a}`):
                    -- bottom it with `.structuralCycle` rather than unrolling fuel-deep. Otherwise
                    -- push the body, re-evaluate, and RESTORE the saved stack (not a bare pop, so a
                    -- divergent inner return cannot leak a stale ancestor). A non-struct body (a bare
                    -- self-ref `x: x`) is never pushed — the depth-0 `visited` slot check above keeps
                    -- it a reference cycle (`_`). Identity is exact `Value` equality: a finite-deep
                    -- nesting has a DISTINCT body per layer, so only true re-entrancy ever collides.
                    let bodyVal := Field.value field
                    let recurseBody : Env -> List Nat -> EvalM Value := fun e vis =>
                      if isStructLikeBody bodyVal then do
                        if (<- get).structStack.contains bodyVal then
                          pure (.bottomWith [.structuralCycle])
                        else do
                          let savedStack := (<- get).structStack
                          modify (fun state => { state with structStack := bodyVal :: savedStack })
                          let r <- evalValueWithFuel fuel e vis bodyVal
                          modify (fun state => { state with structStack := savedStack })
                          pure r
                      else
                        evalValueWithFuel fuel e vis bodyVal
                    if id.depth == 0 then
                      if slotVisited id.index.val visited then
                        EvalState.truncate .top
                      else
                        recurseBody env (id.index.val :: visited)
                    else
                      recurseBody (frame :: outer) [id.index.val]
    | fuel + 1, .conj rawConstraints => do
        -- Bug2-9: FLATTEN a referenced multi-conjunct named def into its constituent conjuncts
        -- (`#LS & {narrow}` where `#LS: #A & #B & {…}` → `#A & #B & {…} & {narrow}`) BEFORE the
        -- fold, so the def's conjuncts and the use-site narrowing evaluate in ONE pass — identical
        -- to the inlined meet. A constraint that is not a depth-0 ref to a `.conj`-bodied def is
        -- returned unchanged, so non-multi-conjunct-def conjuncts keep their path.
        let constraints := rawConstraints.flatMap (flattenConjDefRef env evalFuel [])
        -- DISJUNCTION DISTRIBUTION (argocd-secret-data sub-slice 2). A conjunct that is (or refs,
        -- at depth 0) a disjunction with a deferral-needing default arm must DISTRIBUTE the other
        -- conjuncts into each arm at the UNEVALUATED level — `(*_#A|_#B) & {narrow}` becomes
        -- `*(_#A & {narrow}) | (_#B & {narrow})` — so each arm-meet re-enters this fold and the
        -- post-ss1 def-deferral force-splices the narrowing BEFORE the arm's sibling self-ref
        -- (`copy: #x`, the `#OpaqueSecret` shape) collapses. The arm refs are depth-0-relative to
        -- the def's scope = THIS conj's `env`, so they thread in unchanged. A plain scalar/struct
        -- disjunction yields `none` from `conjDisjArms?` and keeps the existing distribute-at-meet
        -- path (no regression). Restricted to a depth-0 (or literal) disjunction conjunct so arm
        -- depths need no rebasing; a deeper disjunction ref falls through to the standard path.
        match splitDisjConjunct env constraints with
        | some (arms, others) =>
            let distributed <- arms.mapM fun arm => do
              let armValue <- evalValueWithFuel fuel env visited (.conj (arm.snd :: others))
              pure (arm.fst, armValue)
            pure (normalizeEvaluatedDisj distributed)
        | none => evalConjStandard fuel env visited constraints
    | fuel + 1, .builtinCall name args => do
        -- `list.Sort`/`list.SortStable` are handled HERE, not in `evalBuiltinCall` (the pure
        -- `Builtin` layer, which has no access to evaluation): their comparator is a CUE
        -- `{x, y, less}` struct, and deciding `a < b` means MEETING the comparator with
        -- `{x: a, y: b}` and EVALUATING its `less` field to a bool — an effectful comparison.
        -- The comparator is passed UNEVALUATED: `less`'s references to the `x`/`y` slots must
        -- survive into the per-pair meet (an evaluated comparator collapses `less` to a residual
        -- `_ < _` with the slot links lost, so the meet could never re-bind them). Only the LIST
        -- is pre-evaluated. `list.Sort` and `list.SortStable` share one stable sort here: cue's
        -- `Sort` is not guaranteed stable, but a stable result is a valid `Sort` result and matches
        -- cue's observable order on the comparators it defines.
        let runSort : Value -> Value -> EvalM Value := fun listArg cmp => do
          let listValue <- evalValueWithFuel fuel env visited listArg
          match listValue with
          | .list items => sortWithComparator fuel env visited cmp items
          | .bottom => pure .bottom
          | .bottomWith reasons => pure (.bottomWith reasons)
          -- A concrete first argument that is NOT a list is a CUE type error (`cannot use … as
          -- list`); an abstract one (a ref/kind a later pass could concretize to a list) stays
          -- unresolved.
          | other => pure (if isSettledArg other then .bottom else .builtinCall name [other, cmp])
        -- SEAM (effectful builtins). These two cases are the EFFECTFUL-builtin dispatch: a
        -- builtin whose semantics require `EvalM` (evaluating a CUE function/comparator argument
        -- per element), which the pure `Builtin` layer (`Builtin → Lattice`, never `→ Eval`)
        -- structurally cannot host — see `evalBuiltinCall`. Today the population is exactly Sort/
        -- SortStable (sharing `runSort`), and ONE logical case is below the threshold for a
        -- name-keyed dispatch table. EXTENSION RULE (Phase-B 2026-06-20 ruling): when the SECOND
        -- effectful builtin lands (`list.IsSorted`, reusing `sortWithComparator`'s `lt`; or the
        -- validator family `matchN`/`matchIf`/`list.MatchN`), do NOT add a third inline arm here —
        -- first extract these into a named `evalEffectfulBuiltin?` seam tried before the pure
        -- fallback, so the evaluator's top-level match stays free of per-builtin arms. A full
        -- registry of name→`EvalM` closures stays REJECTED (less traceable than an exhaustive
        -- `match`, and the population is ~3-4, not dozens). See `docs/spec/plan.md` (item BI-EFF).
        match name, args with
        | "list.Sort", [listArg, cmp] => runSort listArg cmp
        | "list.SortStable", [listArg, cmp] => runSort listArg cmp
        | _, _ => do
            let evaluated <- evalValuesWithFuel fuel env visited args
            pure (evalBuiltinCall name evaluated)
    | fuel + 1, .unary op value => do
        let evaluated <- evalValueWithFuel fuel env visited value
        pure (distributeUnary op evaluated)
    | fuel + 1, .binary op (.bottom) right =>
        if isPresenceTestOp op then do
          let evaluated <- evalValueWithFuel fuel env visited right
          pure (evalPresenceTest (op == .eq) evaluated)
        else do
          let rightEvaluated <- evalValueWithFuel fuel env visited right
          pure (evalBinary op .bottom rightEvaluated)
    | fuel + 1, .binary op left (.bottom) =>
        if isPresenceTestOp op then do
          let evaluated <- evalValueWithFuel fuel env visited left
          pure (evalPresenceTest (op == .eq) evaluated)
        else do
          let leftEvaluated <- evalValueWithFuel fuel env visited left
          pure (evalBinary op leftEvaluated .bottom)
    | fuel + 1, .binary op left right => do
        let leftEvaluated <- evalValueWithFuel fuel env visited left
        let rightEvaluated <- evalValueWithFuel fuel env visited right
        pure (distributeBinary op leftEvaluated rightEvaluated)
    | fuel + 1, .selector (.refId id) label =>
        match thisStructFieldIndex? env id label with
        | some labelId => evalValueWithFuel fuel env visited (.refId labelId)
        | none =>
            -- Producer (slice 3): selecting an imported definition whose body has a sibling
            -- self-reference defers to a `.closure` instead of eagerly evaluating the base —
            -- which would collapse the self-ref against the def's own frame before a use-site
            -- `meet` (slice 4) narrows it. Gated on `defBodyHasSiblingSelfRef`, the only shape
            -- that collapses today, so every currently-green selection stays on the eager path.
            match importDefClosureBody? env id label with
            | some (pkgFields, defBody) => do
                -- Force the deferred def body STANDALONE (no use-operands) — the terminal value of
                -- a `pkg.#Def` selected OUTSIDE a conjunction (`out: attr.#Ports`, or an embed
                -- `{attr.#Ports}` with no narrowing). When `pkg.#Def` instead sits inside a `.conj`
                -- (`pkg.#Def & {narrow}`), that fold re-produces the closure from the RAW selector
                -- constraint (`importSelectorDef?`) and force-splices the narrowing, so this
                -- standalone force is only ever the terminal value. Mirrors the `.refId` arm.
                let capturedEnv <- pushFrame pkgFields env
                forceClosureWithConjunct fuel capturedEnv defBody []
            | none => do
                let base <- evalValueWithFuel fuel env visited (.refId id)
                pure (selectEvaluatedField base label)
    | fuel + 1, .selector base label => do
        let baseEvaluated <- evalValueWithFuel fuel env visited base
        pure (selectEvaluatedField baseEvaluated label)
    | fuel + 1, .index base key => do
        let baseEvaluated <- evalValueWithFuel fuel env visited base
        let keyEvaluated <- evalValueWithFuel fuel env visited key
        pure (selectEvaluatedIndex baseEvaluated keyEvaluated)
    | fuel + 1, .disj alternatives => do
        let evaluated <- alternatives.mapM fun alternative => do
          let evaluatedValue <- evalValueWithFuel fuel env visited alternative.snd
          pure (alternative.fst, evaluatedValue)
        pure (normalizeEvaluatedDisj evaluated)
    | fuel + 1, .struct nestedFields openness tail patterns closedClauses => do
        -- The normalized struct: evaluate fields, the optional tail, patterns, and the closed
        -- clauses' patterns against the nested frame, then re-emit via `applyEvaluatedStructN`.
        let nestedFields := canonicalizeFields nestedFields
        let nested <- pushFrame nestedFields env
        let evaluatedFields <- evalFieldRefsListWithFuel fuel nested (indexedFields nestedFields)
        match mergeEvaluatedFields evaluatedFields with
        | some nestedFields =>
            let evaluatedTail <- match tail with
              | some t => do let t <- evalValueWithFuel fuel nested [] t; pure (some t)
              | none => pure none
            let evaluatedPatterns <- patterns.mapM fun pattern => do
              let evaluatedLabel <- evalValueWithFuel fuel nested [] pattern.fst
              let evaluatedConstraint <- evalValueWithFuel fuel nested [] pattern.snd
              pure (evaluatedLabel, evaluatedConstraint)
            let evaluatedClauses <- closedClauses.mapM fun clause => do
              let evaluatedPats <- clause.patterns.mapM (evalValueWithFuel fuel nested [])
              pure { clause with patterns := evaluatedPats }
            pure (applyEvaluatedStructN nestedFields openness evaluatedTail evaluatedPatterns
              evaluatedClauses)
        | none => pure .bottom
    | fuel + 1, .list items => do
        let evaluated <- evalListItemsWithFuel fuel env visited items
        pure (.list evaluated)
    | fuel + 1, .listTail items tail => do
        let evaluatedItems <- evalListItemsWithFuel fuel env visited items
        let evaluatedTail <- evalValueWithFuel fuel env visited tail
        pure (.listTail evaluatedItems evaluatedTail)
    | fuel + 1, .comprehension clauses body => do
        match (<- expandClausesWithFuel fuel env clauses body) with
        | .bottom bot => pure bot
        -- D#1b: an incomplete guard keeps the comprehension residual (cue holds it under eval),
        -- rather than collapsing to `{}` and losing the field a later meet could concretize.
        | .deferred => pure (.comprehension clauses body)
        | .payload expanded =>
            match mergeEvaluatedFields expanded with
            | some fields => pure (mkStruct fields .regularOpen none [])
            | none => pure .bottom
    | fuel + 1, .structComp fields comprehensions openness => do
        let fields := canonicalizeFields fields
        let embeddings := comprehensions.filter isEmbeddingValue
        -- Bug2-8 (eager mirror of the force arm): fold a PLAIN embedding's same-def-path decls into
        -- the static frame as an `embeddedDecl` operand so the host `ownDecl #m` × embed `embeddedDecl
        -- #m` pair close-once-UNIONS in `mergeConjOperands` AND a sibling `vis: #m` rendered EAGERLY
        -- resolves against the union (not the stale static `#m`). A deferral/disjunction-bearing embed
        -- keeps its existing narrowing path (gated by `plainEmbed`); a non-definition/non-shared label
        -- is untouched (cert-manager regular pattern stays a meet).
        let embedEnv : Env := (0, fields) :: env
        let hostDefLabels := (fields.filter (fun f => (Field.fieldClass f).isDefinition)).map Field.label
        let plainEmbed := fun embed =>
          match resolveEmbedDefBody? embedEnv embed with
          | some body => !bodyNeedsDefer embedEnv evalFuel body && !embedBodyEmbedsDisjDeep embedEnv evalFuel body
          | none => false
        let embedDeclOperands :=
          ((comprehensions.filter isEmbeddingValue).filter plainEmbed).filterMap fun embed =>
            match embedSameDefPathDecls embedEnv hostDefLabels embed with
            | [] => none
            | decls => some (ConjOperand.mk decls true .embeddedDecl)
        -- Merge OPEN (the host's closedness is re-applied once by `closeEmbeddedOver` after the
        -- embed meet-fold), so the static fold only UNIONS the same-def-path `#m` decls without
        -- prematurely closing — exactly the force arm's `(defFields, true)` treatment.
        let fields :=
          if embedDeclOperands.isEmpty then fields
          else canonicalizeFields (mergeConjOperands (⟨fields, true, .ownDecl⟩ :: embedDeclOperands)).fst
        -- Pass 1: evaluate the static fields and comprehensions against the static-only frame,
        -- then the embedding-contributed fields. A static field referencing `Self.<label>` where
        -- `<label>` is supplied by an EMBEDDING (`type: Self.#type` with `#type` from an embedded
        -- `(*_#Opaque | …)`) cannot resolve here — the frame holds only static labels.
        let nested <- pushFrame fields env
        let staticFields <- evalFieldRefsListWithFuel fuel nested (indexedFields fields)
        match (<- expandComprehensionsWithFuel fuel nested comprehensions) with
        | .error bot => pure bot
        | .ok (expanded, deferredComps) =>
        match mergeEvaluatedFields (staticFields ++ expanded) with
        | none => pure .bottom
        | some merged =>
            let embeddingFields <- evalEmbeddingFieldsWithFuel fuel nested merged embeddings
            -- Pass 2 (only when embeddings exist AND they contribute a label no static field
            -- declares): re-push a frame augmented with the embedded labels and re-evaluate the
            -- static fields, so a `Self.<embedded-label>` selection resolves against the embedded
            -- value. Gated tightly — no embeddings, or embeddings adding only already-static
            -- labels, keeps the single-pass path byte-identical. The augment carries the embedded
            -- fields as ALREADY-EVALUATED resolved values (so re-evaluation is idempotent on them).
            let newEmbeddedFields := embeddingFields.filter fun ef =>
              (findEvalField (Field.label ef) fields).isNone
            let reEvalIndices := embeddedSelfPassFieldIndices fields (newEmbeddedFields.map Field.label)
            let staticFields <-
              if reEvalIndices.isEmpty then
                pure staticFields
              else do
                -- Pass 2 (audit PART B selective re-eval): re-evaluate ONLY the static fields that
                -- depend (directly or transitively via a sibling `Self.<L>` read) on an embedded
                -- label, against a frame augmented with the embedded labels — so a
                -- `Self.<embedded-label>` selection resolves. Every other field reuses its Pass-1
                -- value (`reEvalIndices` excludes it precisely because its value cannot change under
                -- the Pass-2 frame): byte-identical, AND its eval is SKIPPED (we only feed the
                -- selected `(index, field)` entries to `evalFieldRefsListWithFuel`, preserving each
                -- field's slot index so refs still resolve against the full augmented frame). The
                -- augment carries embeds as ALREADY-EVALUATED resolved values.
                let augmented := canonicalizeFields (fields ++ newEmbeddedFields)
                let nested2 <- pushFrame augmented env
                let selected := (indexedFields fields).filter (fun (i, _) => reEvalIndices.contains i)
                let reEvaluated <- evalFieldRefsListWithFuel fuel nested2 selected
                -- Splice each re-evaluated value back at its original index; reuse the Pass-1 value
                -- for every unselected slot.
                let bySlot := (selected.map Prod.fst).zip reEvaluated
                pure ((staticFields.zipIdx).map fun (p1, i) =>
                  match bySlot.find? (fun (j, _) => j == i) with
                  | some (_, v) => v
                  | none => p1)
            -- Embedding-`Self` re-fold: a list-embedded `Self.<embedded-label>` read (`[{name:
            -- Self.#name}]` with `#name` from a sibling `#Meta` embed) lives in an EMBEDDING, not a
            -- static field, so the static-field two-pass above misses it and Pass-1 left it `_|_`.
            -- When an embedding reads such a label, re-evaluate the embeddings (and meet) against the
            -- augmented frame so the read resolves against the embedded value. Gated identically
            -- (byte-identical when no embedding reads a sibling-embedded `Self.<L>`).
            let refoldEmbeds := embeddingsReadEmbeddedSelf fields embeddings (newEmbeddedFields.map Field.label)
            let (nestedForEmbeds, embeddingFields) <- refoldEmbeddingsIfSelf fuel fields
              newEmbeddedFields embeddings env merged nested embeddingFields refoldEmbeds
            match mergeEvaluatedFields (staticFields ++ expanded) with
            | none => pure .bottom
            | some merged =>
                -- Meet the embeddings OPEN (each opened by `meetEmbeddingsWithFuel`) against an OPEN
                -- host, then re-close ONCE over `def ∪ embed` labels — an embedding widens the host's
                -- allowed set without imposing its own closedness (CUE rule). Closing the host
                -- BEFORE the meet would let a closed embed/host reject the other's regular fields.
                let met <- meetEmbeddingsWithFuel fuel nestedForEmbeds (mkStruct merged .regularOpen none []) embeddings
                -- Embedding a CLOSED def closes the host over `host ∪ embed` labels (CUE rule): a
                -- subsequent MEET against this struct (`{#Closed} & {extra}`) must reject `extra`.
                -- ONLY for a `regularOpen` host (open-by-default, no explicit `...`); an explicit
                -- `...` tail (`defOpenViaTail`) keeps the host open regardless of a closed embed.
                let hostOpen := openness.isOpen
                  && (openness != .regularOpen || !(embeddings.any (embeddingClosesHost embedEnv)))
                let resolved := closeEmbeddedOver merged embeddingFields hostOpen met
                -- D#1b: with deferred (incomplete-guard) comprehensions, the struct is NOT concrete
                -- — keep it a `.structComp` carrying the resolved fields + the residual comprehensions
                -- (cue holds it under eval, errors incomplete under export). `deferredComps` holds
                -- only `if`/`for` residuals (embeddings never defer), already meet into `resolved`.
                pure (withDeferredComprehensions resolved deferredComps openness)
    | fuel + 1, .interpolation parts => do
        let evaluated <- evalValuesWithFuel fuel env visited parts
        -- An interpolation hole requires a concrete operand, so a defaulted disjunction
        -- sheds to its default here via the shared `collapseDefaultDisjunction` (identity on
        -- every non-default-disjunction value) — `string | *"ghcr.io"` → `"ghcr.io"`. An
        -- ambiguous disjunction (no unique default) stays a `.disj` and renders incomplete.
        pure (evalInterpolation (evaluated.map collapseDefaultDisjunction))
    | fuel + 1, .dynamicField label fieldClass value => do
        let evaluatedLabel <- evalValueWithFuel fuel env visited label
        match classifyDynLabel (resolveDynLabelDefault evaluatedLabel) with
        | .concreteString name => do
            let evaluatedValue <- evalValueWithFuel fuel env visited value
            pure (mkStruct [⟨name, fieldClass, evaluatedValue, false⟩] .regularOpen none [])
        | .bottom bot => pure bot
        | .nonString ty => pure (.bottomWith [.nonStringLabel ty])
        -- DEFER: an abstract label holds the field unevaluated, so an enclosing context can
        -- re-key it once the label narrows (DYN-DEF-1) — never silently drop to `.bottom`.
        | .incomplete => pure (.dynamicField label fieldClass value)
    -- closure: force the deferred body against the lexical scope it captured. The
    -- call-site `env`/`visited` are discarded — a closure resolves against its definition
    -- site, not its use site (lexical, not dynamic, scope). `capturedEnv` is defeq to `Env`
    -- and carries the full id-stack, so it threads in with no coercion; `visited` resets to
    -- `[]` because the call-site slot markers index call-site frames, not captured ones.
    -- No producer yet (slice 3) ⇒ dead code, but this is the semantic anchor slices 3-4 hit.
    | fuel + 1, .closure capturedEnv body =>
        evalValueWithFuel fuel capturedEnv [] body
    | _, value => pure value
  termination_by (fuel, 0, 0)

  /-- Sort `items` by a CUE comparator struct (`list.Sort`/`list.SortStable`). The comparator
      `cmp` is a `{x, y, less}` struct (e.g. `list.Ascending`); `a < b` is decided by MEETING
      `cmp` with `{x: a, y: b}` and EVALUATING the resulting `less` field to a `bool`. A `less`
      that does not reduce to a concrete `bool` (an incomplete or incomparable comparator) is a
      CUE error: it is recorded in the eval-scoped `sortError` and surfaced as the call's bottom,
      rather than producing a bogus order. The merge itself is the total, stable `sortValuesM`.
      Calls `evalValueWithFuel fuel` (per comparison) — `(fuel,1,0) < (fuel,6,0)`. -/
  def sortWithComparator
      (fuel : Nat)
      (env : Env)
      (visited : List Nat)
      (cmp : Value)
      (items : List Value) : EvalM Value := do
    let savedError := (<- get).sortError
    modify (fun state => { state with sortError := none })
    let lt : Value -> Value -> EvalM Bool := fun a b => do
      let probe := .conj [cmp, mkStruct [⟨"x", .regular, a, false⟩, ⟨"y", .regular, b, false⟩] .regularOpen none []]
      let less <- evalValueWithFuel fuel env visited (.selector probe "less")
      match less with
      | .prim (.bool result) => pure result
      | other => do
          -- Not a concrete bool ⇒ the comparator is incomplete/incomparable (CUE error). Record
          -- the bottom and treat this comparison as `false` (a total fallback; the recorded error
          -- makes the whole sort bottom regardless of the order produced).
          let bot := if containsBottom other then other else .bottom
          modify (fun state => { state with sortError := some (state.sortError.getD bot) })
          pure false
    let sorted <- sortValuesM lt items
    let failure := (<- get).sortError
    modify (fun state => { state with sortError := savedError })
    match failure with
    | some bot => pure bot
    | none => pure (.list sorted)
  termination_by (fuel, 6, 0)

  /-- The standard `.conj` fold (extracted so the `.conj` arm can first try disjunction
      distribution and fall through here). Either the lazy same-scope struct merge
      (`lazyConjMergedFields`), or the deferral fold: a bare self-ref def / import-selector
      conjunct defers to its `.closure`, then every closure is force-spliced with the SHARED
      use-operand set so deferred defs' siblings narrow against the use-site at once. `fuel` is
      the predecessor of the `.conj` arm's `fuel + 1`, so calls to `evalValueWithFuel fuel`
      `(fuel,1,0)` and `forceClosureWithConjunct fuel` `(fuel,5,0)` decrease from `(fuel,6,0)`. -/
  def evalConjStandard
      (fuel : Nat)
      (env : Env)
      (visited : List Nat)
      (constraints : List Value) : EvalM Value := do
    match lazyConjMergedFields env constraints with
    | some (mergedFields, open_) =>
        let canonical := canonicalizeFields mergedFields
        let nested <- pushFrame canonical env
        let evaluatedFields <- evalFieldRefsListWithFuel fuel nested (indexedFields canonical)
        match mergeEvaluatedFields evaluatedFields with
        | some fields => pure (mkStruct fields (.ofBool open_) none [])
        | none => pure .bottom
    | none => do
        -- A bare ref to an embed-bearing self-ref def (`#Outer`, a `.structComp`) is DEFERRED
        -- to its `.closure` here (`conjDefClosure?`) rather than evaluated — the `.refId` arm
        -- would otherwise force it STANDALONE (no use-operands), collapsing its self-ref before
        -- this fold can splice the narrowing. A `pkg.#Def` import-selector conjunct is likewise
        -- deferred from the RAW constraint (`importSelectorDef?` + in-monad `pushFrame`), so the
        -- selector arm's standalone force (which fires when `pkg.#Def` is selected OUTSIDE a
        -- conjunction) does not collapse it here before the fold splices the use-site.
        -- Bug2-10 over-fire guard (has-a-narrowing-sibling half): only defer a `.structComp`
        -- HOST (`{#Meta}`) into the closure fold when a SIBLING conjunct carries a use-site
        -- narrowing to deliver (`& {#name:"x"}`). With no narrowing sibling the host evaluates
        -- standalone exactly as before — byte-identical for a no-narrowing `.conj`.
        let hasNarrowingSibling := constraints.any conjNarrowingSibling?
        let evaluated <- constraints.mapM fun constraint => do
          match conjDefClosure? env constraint with
          | some closure => pure closure
          | none =>
              -- Bug2-10: a `.structComp` host whose embed body has a sibling self-ref is deferred
              -- to its `.closure` (like the bare-ref case above) so the force-fold splices the
              -- sibling narrowing in before the embedded `Self.#name` collapses. Gated on a
              -- narrowing sibling existing — else it would perturb a no-narrowing host.
              match (if hasNarrowingSibling then conjStructCompDefer? env constraint else none) with
              | some closure => pure closure
              | none =>
              -- `importSelectorDef?`: a `pkg.#Def` selector conjunct (incl. one aliased to
              -- another selector via the alias-follow inside `importDefClosureBody?`).
              -- `refAliasSelectorDef?`: a bare ref conjunct (`#B`) whose body chains through
              -- an alias to a deferring struct — captured over the TERMINAL package frame.
              match importSelectorDef? env constraint with
              | some (pkgFields, defBody) => do
                  let capturedEnv <- pushFrame pkgFields env
                  pure (.closure capturedEnv defBody)
              | none =>
                match refAliasSelectorDef? env constraint with
                | some (capturedFrame, defBody) => do
                    let capturedEnv <- pushFrame capturedFrame env
                    pure (.closure capturedEnv defBody)
                | none => evalValueWithFuel fuel env visited constraint
        -- A `.closure` among the evaluated operands is a deferred imported def (slices 3-4).
        -- Instead of the inert `meet` (→ `.bottom`), force EVERY closure with the SHARED
        -- use-operand set spliced into its body (slice A — multi-operand fold). The use-site
        -- struct conjuncts narrow all the deferred defs' siblings at once (`#M & #N &
        -- {narrow}`); non-struct non-closure operands `meet` against the folded result,
        -- preserving honesty (still `.bottom` on a genuine conflict).
        match allClosures evaluated with
        | [] => pure (evaluated.foldl (fun current constraint => meet current constraint) .top)
        | closures =>
            let useOperands := (evaluated.filterMap spliceNarrowingOperand?).map stripLetBindings
            let others := nonClosureNonStructOperands evaluated
            -- Bug2-14c: a multi-closure conjunction (`defs.#ListenerSet & parts.#UseCertManager &
            -- {…}`) where one closure declares a REGULAR field (`kind: "ListenerSet"`) that another
            -- closure's BURIED disjunction let-local reads (`#Mixin`'s `let _patch = { kind: string;
            -- for … if kind == add.#kind … }`). The base `useOperands` carry only the plain-struct
            -- operands' fields — NOT a regular field that lives INSIDE a sibling closure — so forcing
            -- the disjunction-bearing closure in isolation leaves its `_patch.kind` abstract and the
            -- comprehension guard defers (annotations drop). Force the closures in TWO passes: pass 1
            -- with the base operands collects each closure's forced REGULAR-output fields; pass 2
            -- re-forces ONLY a disjunction-deep-bearing closure with the sibling closures' regular
            -- fields spliced as an extra operand, so its `_patch.kind` sees the narrowed `kind`. The
            -- regular-field splice is the SAME Gap-2b operand a single-closure embed gets; it is sound
            -- regardless of which conjunct the narrowing originates in (meet is idempotent on a field
            -- an arm already carries, a real conflict still bottoms). A closure with no buried
            -- disjunction keeps its pass-1 result (byte-identical — no extra splice, no re-force).
            let pass1 <- closures.mapM (fun cl => do
              let forced <- forceClosureWithConjunct fuel cl.fst cl.snd useOperands
              pure (cl, forced))
            let siblingRegulars := pass1.flatMap (fun (_, forced) =>
              match evaluatedStructOperand? forced with
              | some (fields, _) => fields.filter Field.isRegularOutput
              | none => [])
            let forced <- pass1.foldlM (fun current (cl, p1) => do
              let body := cl.snd
              let isDisjDeep := embedBodyEmbedsDisjDeep (bodyForceFrameEnv cl.fst body) evalFuel body
              if isDisjDeep then do
                -- Re-force with the sibling closures' regular fields spliced (drop THIS closure's own
                -- regulars from the extra operand — they already flow through its own force).
                let ownLabels := match evaluatedStructOperand? p1 with
                  | some (fields, _) => (fields.filter Field.isRegularOutput).map Field.label
                  | none => []
                let extra := siblingRegulars.filter (fun f => !ownLabels.contains (Field.label f))
                if extra.isEmpty then pure (meet current p1)
                else do
                  let reforced <- forceClosureWithConjunct fuel cl.fst body (useOperands ++ [(extra, true)])
                  pure (meet current reforced)
              else pure (meet current p1))
              .top
            pure (others.foldl (fun current v => meet current v) forced)
  termination_by (fuel, 6, 0)

  /-- Embedding-`Self` re-fold, shared by both struct-eval arms (`.structComp` and def-force):
      a list-embedded `Self.<embedded-label>` read lives in an EMBEDDING the static-field two-pass
      misses, so re-evaluate the embeddings against a frame augmented with the embedded labels when
      `refoldEmbeds` says one of them reads such a label. Byte-identical otherwise (returns the
      Pass-1 frame `nested` + `embeddingFieldsPass1` untouched). `refoldEmbeds` is the gate RESULT
      (`embeddingsReadEmbeddedSelf`), passed in so this stays orthogonal to the static-field gate
      `needsEmbeddedSelfPass`. Returns `(nestedForEmbeds, embeddingFields)` for the caller to thread
      into its `met`. -/
  def refoldEmbeddingsIfSelf
      (fuel : Nat)
      (canonical : List Field)
      (newEmbeddedFields : List Field)
      (embeddings : List Value)
      (env : Env)
      (merged : List Field)
      (nested : Env)
      (embeddingFieldsPass1 : List Field)
      (refoldEmbeds : Bool) : EvalM (Env × List Field) := do
    let nestedForEmbeds <-
      if refoldEmbeds then pushFrame (canonicalizeFields (canonical ++ newEmbeddedFields)) env
      else pure nested
    let embeddingFields <-
      if refoldEmbeds then evalEmbeddingFieldsWithFuel fuel nestedForEmbeds merged embeddings
      else pure embeddingFieldsPass1
    pure (nestedForEmbeds, embeddingFields)
  termination_by (fuel, 3, embeddings.length + 1)

  /-- The fields each embedding contributes, for computing a closed embed-def's allowed-label
      union (slice A): embedding `#Base = {kind}` into a closed `#Def` widens the allowed set by
      `{kind}`. Evaluates each embedding (forcing a `.closure` embed against `narrowing` — the
      host's hidden/definition fields) and concatenates the struct fields it yields; non-struct
      embeddings contribute nothing.

      `narrowing` is load-bearing: a `.closure` embed whose body has a CONDITIONAL comprehension
      (`if #port > 0 { ports: … }`) introduces `ports` ONLY when the guard fires, which depends on
      the host's narrowed `#port`. Forcing the embed WITHOUT the narrowing drops the conditional
      label from the allowed set, so the host's closedness then rejects the field the actual
      embed-meet produces → spurious `bottom`. So force the embed-closure WITH
      the host's hidden fields spliced (the same `useOperands` the value-producing `meet` uses). -/
  def evalEmbeddingFieldsWithFuel
      (fuel : Nat)
      (env : Env)
      (narrowing : List Field) : List Value -> EvalM (List Field)
    | [] => pure []
    | embedding :: rest =>
        match fuel with
        | 0 => EvalState.truncate []
        | nextFuel + 1 => do
            let evaluated <-
              match conjDefClosure? env embedding with
              | some closure => pure closure
              | none =>
                  match importSelectorDef? env embedding with
                  | some (pkgFields, defBody) => do
                      let capturedEnv <- pushFrame pkgFields env
                      pure (.closure capturedEnv defBody)
                  | none => evalValueWithFuel (nextFuel + 1) env [] embedding
            -- A `.closure` embed (self-ref imported def) is forced WITH the host's hidden narrowing
            -- so a conditional comprehension's labels surface (forcing drops a fuel tier — it sits
            -- above this measure); a non-closure embed already evaluated against the host frame,
            -- which carries the narrowing.
            let resolved <-
              match evaluated with
              | .closure capturedEnv body =>
                  -- Bug2-14b: the disjunction-deep gate resolves against the body's OWN def frame
                  -- (`bodyForceFrameEnv`), not the outer `env` — the force-fold site mirror.
                  forceClosureWithConjunct nextFuel capturedEnv (openStructValue body)
                    [spliceOperandForEmbed (embedBodyEmbedsDisjDeep (bodyForceFrameEnv capturedEnv body) evalFuel body) body (narrowing, true)]
              | .top | .bottom | .bottomWith _ | .prim _ | .kind _
              | .notPrim _ | .stringRegex _ | .stringFormat _ | .boundConstraint _ _ _ | .lengthConstraint _ _ _ | .uniqueItems | .conj _
              | .builtinCall _ _ | .unary _ _ | .binary _ _ _ | .ref _ | .refId _
              | .thisStruct | .selector _ _ | .index _ _ | .disj _ | .struct _ _ _ _ _
              | .list _ | .listTail _ _ | .embeddedList _ _ _ | .embeddedScalar _ _
              | .comprehension _ _ | .structComp _ _ _ | .listComprehension _ _
              | .interpolation _ | .dynamicField _ _ _ => pure evaluated
            let head :=
              match evaluatedStructOperand? (resolveEmbeddedDisjDefault resolved) with
              | some (fields, _) => fields
              | none => []
            let tail <- evalEmbeddingFieldsWithFuel (nextFuel + 1) env narrowing rest
            pure (head ++ tail)
  termination_by embeddings => (fuel, 3, embeddings.length)

  /-- Meet a struct against each embedding in turn, evaluating each in the nested frame. An
      embedding that evaluates to a `.closure` (a self-referential imported def embedded in a
      struct body, e.g. `parts.#Metadata`) is FORCED with the current struct's fields spliced in
      as the use-operand (slice A, facet c), so its self-references resolve against the
      surrounding narrowing instead of collapsing to a plain `meet → .bottom`. -/
  def meetEmbeddingsWithFuel
      (fuel : Nat)
      (env : Env)
      (current : Value) : List Value -> EvalM Value
    | [] => pure current
    | embedding :: rest =>
        match fuel with
        | 0 => EvalState.truncate current
        | nextFuel + 1 => do
            -- An embedded DEFAULT DISJUNCTION whose arms need deferral (`(*_#A|_#B)` with `_#A`'s
            -- body referencing a sibling the host narrows — the argocd `#OpaqueSecret` shape) is
            -- DISTRIBUTED: the host's narrowing is folded into EVERY arm (each re-entering this
            -- fold so the post-ss1 def-deferral force-splices the narrowing before the arm's
            -- self-ref collapses), bottoms are PRUNED (`normalizeDisj` via `liveAlternatives`), and
            -- the survivor resolves. Committing to the default arm first would bottom when the
            -- narrowing KILLS the default arm with no fall-through to a
            -- surviving arm (`#S & {v:"s"}` over `*_#A{v:int} | _#B{v:string}` → cue `{kind:"b",v:"s"}`,
            -- kue bottom). This mirrors the `.conj` fold's `splitDisjConjunct` arm-distribution.
            -- A plain scalar/struct disjunction yields `none` from `conjDisjArms?` and keeps the
            -- collapse-then-meet path below (no over-distribute). The per-arm fold drops a fuel tier
            -- (a single-embedding sub-fold of the host against the arm) to stay below this measure.
            match conjDisjArms? env evalFuel embedding with
            | some arms => do
                let distributed <- arms.mapM fun arm => do
                  let armResult <- meetEmbeddingsWithFuel nextFuel env current [arm.snd]
                  pure (arm.fst, armResult)
                meetEmbeddingsWithFuel (nextFuel + 1) env (normalizeDisj distributed) rest
            | none => do
              -- A bare ref to a self-ref def the lazy-merge can't handle is DEFERRED to its
              -- `.closure` here (not evaluated through `.refId`, which would force it STANDALONE with
              -- no use-operands), so the `.closure` branch below force-splices the HOST's current
              -- fields — the embedding analogue of the `.conj` fold's `conjDefClosure?`.
              let evaluated <-
                match conjDefClosure? env embedding with
                | some closure => pure closure
                | none =>
                    match importSelectorDef? env embedding with
                    | some (pkgFields, defBody) => do
                        let capturedEnv <- pushFrame pkgFields env
                        pure (.closure capturedEnv defBody)
                    | none =>
                        -- Bug2-14: a PLAIN embed (not a self-ref closure / imported def) that
                        -- declares a label ABSTRACTLY which the HOST narrows CONCRETELY keeps its
                        -- sibling/comprehension read (`echo: bk`, `if bk == …`) bound to the
                        -- EMBED-LOCAL un-narrowed value — the embed is its OWN frame, so the read is
                        -- depth-0 into its own slot, NOT the host's. The host's narrowing reaches the
                        -- embed-output only via the LATER `meet current (embed)` below — too late for
                        -- the already-captured read. Inject the host's (`current`'s) narrowing into
                        -- the embed body's same-label read-and-declared slot BEFORE evaluating, so the
                        -- read sees the merged value. The closure paths above deliver their narrowing
                        -- via `spliceOperandForEmbed`; this is the missing delivery for the plain path.
                        -- Gated to the read-and-declared × host-narrowed overlap
                        -- (`injectEmbedSiblingNarrowings`), so an embed-INTERNAL field the host does
                        -- not narrow stays embed-local (no over-rebase).
                        evalValueWithFuel (nextFuel + 1) env []
                          (injectEmbedSiblingNarrowings evalFuel (hostNarrowingPairs current) [] embedding)
              -- Fallback for a NON-closure, NON-disjunction embedding: the scalar/list-embedding
              -- collapse (`{5}`→`5`), done HERE where the host struct is KNOWN to be EMBEDDING a
              -- scalar — not reconstructed at meet time, where an empty struct `{}` is
              -- indistinguishable from `{5}`'s residual `.struct []` and would wrongly absorb any
              -- scalar an empty/decl-free struct meets (`{} & 5` must be a conflict, not `5`).
              -- Collapse only when LOSSLESS — no output field and no non-output decl to drop
              -- (`collapsesToScalarEmbed`) — and the embedding resolved to a TERMINAL scalar.
              -- Hoisted ahead of `match evaluated` so its enumerated catch-all arms carry no
              -- recursive call: enumerating a recursive-call-bearing shared arm duplicates the
              -- `decreasing_by` obligation across every constructor and blows elaboration.
              let scalarEmbeddingCollapse : EvalM Value :=
                -- A non-closure embedding is OPENED before the meet (an embedding UNIONS its labels
                -- into the host's allowed set but never imposes its OWN closedness — CUE rule); the
                -- host's closedness over `def ∪ embed` labels is re-applied by the caller.
                match current with
                | .struct fields _ none [] _ =>
                    if collapsesToScalarEmbed fields evaluated then
                      -- Pure `{5}`→`5`: no output field AND no decls. LEFT UNTOUCHED (soundness
                      -- boundary — never widened to admit decls).
                      meetEmbeddingsWithFuel (nextFuel + 1) env evaluated rest
                    else if !structHasOutputField fields && (asListPair evaluated).isSome then
                      -- List-embedding collapse — the LIST analog of the scalar-carrier collapse:
                      -- `evaluated` is the HOST's OWN embedding, so the decls-only host collapses to
                      -- that list carrying its decls. NOT the `.embeddedList & {foreign decls}` meet
                      -- (a genuine list-vs-struct conflict handled by `meetCore`); collapse at meet
                      -- time cannot distinguish the two, so it lives here. `declFields` keeps the
                      -- non-output `let ls` decl selectable.
                      let collapsed :=
                        match evaluated with
                        | .embeddedList items tail edecls =>
                            match mergeStructFieldsWith (meet) (declFields fields) edecls with
                            | some decls => .embeddedList items tail decls
                            | none => .bottom
                        | other =>
                            match asListPair other with
                            | some (items, tail) => .embeddedList items tail (declFields fields)
                            | none => other
                      meetEmbeddingsWithFuel (nextFuel + 1) env collapsed rest
                    else if !structHasOutputField fields && isTerminalScalar evaluated then
                      -- Scalar-WITH-decls carrier (`{#a:1, 5}`→`5`, `.#a` selectable): host has
                      -- decls but no output field, embedding is a terminal scalar. The
                      -- `.embeddedScalar` carrier is the direct analog of the `.embeddedList`
                      -- list-with-decls carrier — scalar manifests, decls stay selectable.
                      meetEmbeddingsWithFuel (nextFuel + 1) env
                        (.embeddedScalar evaluated (declFields fields)) rest
                    else
                      -- Bug2-8: union a same-def-path `#m` decl the host already carries with the
                      -- embed's arm so the meet is idempotent on `#m`. Other labels meet as before.
                      meetEmbeddingsWithFuel (nextFuel + 1) env
                        (meetEmbedUnioningDefDecls current evaluated) rest
                | .top | .bottom | .bottomWith _ | .prim _ | .kind _
                | .notPrim _ | .stringRegex _ | .stringFormat _ | .boundConstraint _ _ _ | .lengthConstraint _ _ _ | .uniqueItems | .conj _
                | .builtinCall _ _ | .unary _ _ | .binary _ _ _ | .ref _ | .refId _
                | .thisStruct | .selector _ _ | .index _ _ | .disj _
                | .struct _ _ _ _ _ | .list _ | .listTail _ _ | .embeddedList _ _ _
                | .embeddedScalar _ _ | .comprehension _ _ | .structComp _ _ _
                | .listComprehension _ _ | .interpolation _ | .dynamicField _ _ _
                | .closure _ _ =>
                    meetEmbeddingsWithFuel (nextFuel + 1) env
                      (meetEmbedUnioningDefDecls current evaluated) rest
              match evaluated with
              | .closure capturedEnv body => do
                  -- An embedded self-referential imported def (`parts.#Metadata`) evaluates to a
                  -- `.closure`. A plain `meet` collapses it to `.bottom`; instead FORCE it with the
                  -- host's current fields spliced in as the use-operand, so the embed's self-refs
                  -- (`kind: #kind`) resolve against the host's use-site narrowing (slice A, facet c).
                  -- The embed's body is OPENED so the splice does not reject the host's sibling
                  -- fields (`#Def`'s `#x`/`spec` are not declared by `parts.#Metadata`); the embed's
                  -- labels fold into the union closedness the structComp arm applies afterwards.
                  -- Forcing is a deferred sub-evaluation, so it drops fuel (force sits at a higher
                  -- measure tier and must consume fuel to re-enter here).
                  -- Splice the host's hidden/definition fields (`#name`, …) into the embed: those are
                  -- the SHARED bindings the embed self-references (`pname: Self.#name`). PLUS any
                  -- regular sibling a comprehension inside the embed reads (`spliceOperandForEmbed`
                  -- via `embedComprehensionReadLabels` — the `if kind == add.#kind` guard reads the
                  -- regular `kind`): those must reach the embed so the guard sees the narrowed value
                  -- at expansion time, else the comprehension drops. The other regular output fields
                  -- still unify at the outer `meet current forced`, not via the splice (splicing them
                  -- makes the embed re-evaluate and conflict on them). `hiddenFieldsOnly` also drops
                  -- the host's `Self=`/`let` aliases (the embed has its own).
                  -- Bug2-14b: the disjunction-deep gate must resolve the body's OWN embed-refs against
                  -- the def frame the force pushes (`bodyForceFrameEnv`), NOT the outer meet-fold `env`
                  -- — else a transitively-embedded `listShape | structShape | error` disjunction is
                  -- missed and the host's regular `kind` drops from the splice, never reaching the
                  -- buried `_patch.kind`.
                  let useOperands := (evaluatedStructOperand? current).toList.map
                    (spliceOperandForEmbed (embedBodyEmbedsDisjDeep (bodyForceFrameEnv capturedEnv body) evalFuel body) body)
                  let forced <-
                    forceClosureWithConjunct nextFuel capturedEnv (openStructValue body) useOperands
                  -- A deferral-bearing closure-embed keeps the plain meet — its def-path decls flow
                  -- through the force-splice narrowing machinery (Bug2-4/2-5), not the static
                  -- decl-union (Bug2-8 fires only for PLAIN embeds, handled at the `_` struct arm).
                  meetEmbeddingsWithFuel (nextFuel + 1) env (meet current (openStructValue forced)) rest
              | .disj alternatives =>
                  -- An embedded DEFAULT DISJUNCTION whose arms are already EVALUATED (no deferral
                  -- needed — `conjDisjArms?` returned `none`) must DISTRIBUTE the host's narrowing
                  -- into EVERY arm and PRUNE bottoms, not collapse to the default arm first. Picking
                  -- the default arm would bottom when the narrowing KILLS the default arm with no
                  -- fall-through: `(*_#A{v:int} | _#B{v:string})` met
                  -- with `{v:"s"}` → cue `{kind:"b",v:"s"}`, kue bottom. Each arm meets the OPENED
                  -- host (an embedding widens, never imposes its own closedness); `normalizeDisj`
                  -- prunes the dead default (`liveAlternatives`) so the survivor wins. The plain
                  -- scalar/struct disjunctions that have a unique default surviving still resolve to
                  -- it (cue-exact).
                  --
                  -- embed-disj-arm-closedness: each arm is then RE-CLOSED over (host ∪ arm) labels
                  -- when the arm was a closed def — the per-arm analog of the top-level
                  -- `closeEmbeddedOver` (line ~3539). Opening the arm widens the host's allowed set
                  -- (so a host regular field the arm does not declare survives), but `met` is a
                  -- residual `.disj` that `closeEmbeddedOver` passes through UNCLOSED — so each arm
                  -- lost its own closedness. A LATER use-site narrowing introducing a label DISJOINT
                  -- from a closed default arm must bottom that arm (`{(*_#A{n} | _#B{s})} & {s:"x"}`
                  -- → cue picks `_#B`, `{s:"x"}`), but an open default arm wrongly ADMITS `s` and
                  -- wins (`{n,s:"x"}`). Re-closing per-arm restores the rejection; the DIRECT
                  -- (non-embedded) `(*_#A | _#B) & {s}` path already gets this because its arms stay
                  -- closed defs at meet time.
                  let hostFields := (evaluatedStructOperand? current).map Prod.fst |>.getD []
                  let distributed <- alternatives.mapM fun alternative => do
                    let armOpened := openStructValue alternative.snd
                    let plainMet := meet current armOpened
                    -- An arm that is a LIST-shaped embedding (`{[...]}`, an `.embeddedList`, or a
                    -- bare list) must fold into the host through the SAME single-embedding sub-fold
                    -- the `conjDisjArms?` path uses (line ~3837), not the plain struct `meet` — so
                    -- the host's own list-collapse fires and a list-carrier host keeps the arm
                    -- (cue distributes `host & (listArm | structArm)` and the list arm survives).
                    -- The plain `meet` treats the arm as struct-vs-list and bottoms it, pruning the
                    -- live list arm → spurious overall bottom. Gated to list-shaped arms so the
                    -- struct-arm closedness reclosing below is untouched; provenance is the host's
                    -- OWN embedded disjunction (this `embedding`), so the collapse is sound (a
                    -- foreign list-vs-struct conjunct never reaches here — it stays a `meetCore`
                    -- conflict).
                    let armResult <-
                      if isBottom plainMet && (asListPair alternative.snd).isSome then
                        meetEmbeddingsWithFuel nextFuel env current [alternative.snd]
                      else
                        pure plainMet
                    let reclosed :=
                      match evaluatedStructOperand? alternative.snd with
                      | some (armFields, armOpen) =>
                          closeEmbeddedOver hostFields armFields armOpen armResult
                      | none => armResult
                    pure (alternative.fst, reclosed)
                  meetEmbeddingsWithFuel (nextFuel + 1) env (normalizeDisj distributed) rest
              | .top | .bottom | .bottomWith _ | .prim _ | .kind _
              | .notPrim _ | .stringRegex _ | .stringFormat _ | .boundConstraint _ _ _ | .lengthConstraint _ _ _ | .uniqueItems | .conj _
              | .builtinCall _ _ | .unary _ _ | .binary _ _ _ | .ref _ | .refId _
              | .thisStruct | .selector _ _ | .index _ _ | .struct _ _ _ _ _ | .list _
              | .listTail _ _ | .embeddedList _ _ _ | .embeddedScalar _ _
              | .comprehension _ _ | .structComp _ _ _ | .listComprehension _ _
              | .interpolation _ | .dynamicField _ _ _ => scalarEmbeddingCollapse
  termination_by embeddings => (fuel, 3, embeddings.length)

  /-- Force a closure (slice 4 — the closure-meet unlock) by splicing the use-site struct
      conjuncts INTO the deferred def body before evaluating, so a body field referencing a
      sibling the use-site narrows (`out: #name` with use-site `#name: "keel"`) sees the
      narrowed value instead of collapsing against the def's own `#name: string`.

      `capturedEnv` is the def's lexical scope (the package frame stack the producer captured);
      `body` is the def's UNEVALUATED struct; `useOperands` are the OTHER conjuncts' EVALUATED
      `(fields, open)` (struct-shaped). When `body` is a struct, def fields + use operands are
      merged into one frame via the same `mergeConjOperands` machinery same-package conjunction
      uses, pushed onto `capturedEnv`, and evaluated once — so the def's own depth>0 cross-pkg
      refs still resolve against `capturedEnv` while its depth-0 siblings see the spliced
      narrowing. Evaluated use operands carry no depth-0 frame refs (eval already resolved their
      siblings), so rebasing them is a no-op and the splice cannot leak use-site scope into the
      def frame. `visited := []` is sound: a forced closure is a fresh eval entry, so the
      ordinary `slotVisited` machinery on the pushed frame catches a self-referential captured
      binding and terminates (→ `.top`) rather than looping. A non-struct def body is forced
      under its scope, then `meet`-ed against the use structs (no frame to splice into). -/
  def forceClosureWithConjunct
      (fuel : Nat)
      (capturedEnv : Env)
      (body : Value)
      (useOperands : List (List Field × Bool)) : EvalM Value := do
    -- Force-memo: a `pkg.#Def` selected/referenced N times re-forces the same body N times
    -- (this path bypasses the `EvalKey` cache). Keyed on `(fuel, capturedEnv.ids, body,
    -- useOperands)` — the full pure-function input — the force runs once. Sound by the same
    -- proxy argument as `EvalKey` (see `ForceKey`); the id stack is canonical via frame sharing.
    let forceKey : ForceKey := ⟨fuel, capturedEnv.ids, body, useOperands⟩
    match (<- get).forceCache.get? forceKey with
    | some (cached, sat) => do
        -- Cache-hit honesty: a truncated force re-bumps `truncCount` so the bracketing
        -- `evalValueWithFuel` parent (this force is always reached from a core arm) still
        -- classifies itself truncated. A saturated force bumps nothing. Mirrors `cache`.
        let bump := if sat == .truncated then 1 else 0
        modify (fun state => { state with cacheHits := state.cacheHits + 1, truncCount := state.truncCount + bump })
        pure cached
    | none => do
      let before := (<- get).truncCount
      let result <- forceClosureWithConjunctCore fuel capturedEnv body useOperands
      let after := (<- get).truncCount
      let sat : Saturation := if after == before then .saturated else .truncated
      modify (fun state => { state with forceCache := state.forceCache.insert forceKey (result, sat) })
      pure result
  termination_by (fuel, 5, 0)

  def forceClosureWithConjunctCore
      (fuel : Nat)
      (capturedEnv : Env)
      (body : Value)
      (useOperands : List (List Field × Bool)) : EvalM Value := do
    match body with
    | .structComp defFields comprehensions defOpenness =>
        -- Embed-bearing def body (`#Def: { parts.#Metadata; #x; spec: #x }` — slice A). Splice
        -- the use operands into the static fields (so `spec: #x` sees the narrowed `#x`), eval
        -- them under `capturedEnv`, then meet-fold the embeddings in the same nested frame —
        -- mirroring the `.structComp` eval arm. An embedding that resolves to a `.closure` (a
        -- self-ref cross-package embed) is force-spliced by `meetEmbeddingsWithFuel` against the
        -- partial struct, so it resolves under the surrounding narrowing rather than collapsing.
        --
        -- Closedness UNIONS embed labels with the def's own (CUE: embedding `#Base` widens the
        -- closed set by `#Base`'s labels). So merge/meet OPEN, then — if the def was closed —
        -- close ONCE over `def static labels ∪ each embedding's evaluated labels`. Pre-closing
        -- the static frame would wrongly reject both the embed's fields and the def's own.
        -- Bug2-8: a def that declares `#m` once and EMBEDS another def also declaring `#m` (`#A:
        -- {#m:{a}}` then `#Use: {#A; #m:{c}}`) has TWO decls of the ONE def path `#m` spanning the
        -- embed boundary — cue close-once-UNIONS them. Surface each embedding's same-def-path decls
        -- (`embedSameDefPathDecls`, gated to labels the host ALSO declares as definitions) and fold
        -- them into the static frame as an `embeddedDecl`-provenance operand BEFORE static eval, so
        -- `mergeConjOperands` unions them (the Bug2-6 close-once lever) AND a sibling `vis: #m`
        -- resolves against the union. The embeddings resolve at depth 1 (the def's enclosing scope);
        -- a placeholder depth-0 frame carrying the static labels matches `refDefClosureBody?`'s
        -- `bodyEnv`. A non-definition embed field, or a label the host does not also declare as a
        -- definition, is NOT surfaced — it flows through the ordinary embed meet-fold below
        -- (cert-manager closed pattern stays a meet; distinct cross-conjunct values stay a meet).
        let hostDefLabels := (defFields.filter (fun f => (Field.fieldClass f).isDefinition)).map Field.label
        let embedEnv : Env := (0, defFields) :: capturedEnv
        -- Surface an embedding's same-def-path decls into the static frame ONLY for a PLAIN embed
        -- body (no deferral, no embedded disjunction). A deferral-bearing embed (`_#M` with a
        -- `for k,v in #data` comprehension reading the def path, or an embedded disjunction) keeps
        -- its existing narrowing machinery (Bug2-4/2-5 splice, disj distribution) — folding its
        -- def-path decl into the static frame would disturb the comprehension's own view of the
        -- narrowed field. Bug2-8's `#A: {#m:{a:1}}` is a plain struct, so the fold fires for it.
        let plainEmbed := fun embed =>
          match resolveEmbedDefBody? embedEnv embed with
          | some body => !bodyNeedsDefer embedEnv evalFuel body && !embedBodyEmbedsDisjDeep embedEnv evalFuel body
          | none => false
        let embedDeclOperands :=
          ((comprehensions.filter isEmbeddingValue).filter plainEmbed).filterMap fun embed =>
            match embedSameDefPathDecls embedEnv hostDefLabels embed with
            | [] => none
            | decls => some (ConjOperand.mk decls true .embeddedDecl)
        let (mergedFields, _) := mergeConjOperands
          (⟨defFields, true, .ownDecl⟩ :: embedDeclOperands ++ useOperands.map ConjOperand.ofPair)
        -- Bug2-4: meet the host's regular narrowings INTO any let-local that DECLARES and READS the
        -- narrowed label (`let _patch = { kind: string; for … { if kind == … } }`), so the buried
        -- comprehension expands against the narrowed `kind`. A splice that lands at the def frame as
        -- a SIBLING cannot reach the let-local (a distinct binding); cue narrows the promoted local
        -- lazily. Gated to read-and-declared locals only (byte-identical otherwise).
        let narrowings := useOperands.flatMap (fun op =>
          op.fst.filterMap (fun f => if Field.isRegularOutput f then some (Field.label f, Field.value f) else none))
        let mergedFields := if narrowings.isEmpty then mergedFields else
          mergedFields.map (fun fl =>
            if fl.fieldClass == .letBinding then
              { fl with value := injectLetLocalNarrowings evalFuel narrowings [] (Field.value fl) }
            else fl)
        let canonical := canonicalizeFields mergedFields
        let embeddings := comprehensions.filter isEmbeddingValue
        let nested <- pushFrame canonical capturedEnv
        let staticFields <- evalFieldRefsListWithFuel fuel nested (indexedFields canonical)
        -- Expand the conditional/`for` comprehensions against the post-splice frame, so an
        -- `if #x > 0 { y: #x }` guard fires AFTER the use-site narrowing landed in `#x` —
        -- mirroring the eager `.structComp` arm (`staticFields ++ expanded`). Without this the
        -- force arm silently dropped every `if`/`for` member (the F2 cert-manager `attr.#Ports`
        -- collapse). Embeddings (`isEmbeddingValue`) expand to `[]` here and flow to the
        -- embed-meet below unchanged.
        match (<- expandComprehensionsWithFuel fuel nested comprehensions) with
        | .error bot => pure bot
        | .ok (expanded, deferredComps) =>
        match mergeEvaluatedFields (staticFields ++ expanded) with
        | none => pure .bottom
        | some merged =>
            let embeddingFields <- evalEmbeddingFieldsWithFuel fuel nested merged embeddings
            -- Pass 2 (mirrors the eager `.structComp` arm): a static field referencing
            -- `Self.<label>` where `<label>` is supplied by an EMBEDDING (`type: Self.#type`,
            -- `#type` from an embedded `(*_#Opaque | …)`) cannot resolve against the static-only
            -- frame. Re-push a frame augmented with the embedded labels not already declared
            -- static, and re-evaluate the static fields so the selection resolves. Gated to fire
            -- only when an embedding adds a NEW label — byte-identical otherwise.
            let newEmbeddedFields := embeddingFields.filter fun ef =>
              (findEvalField (Field.label ef) canonical).isNone
            let reEvalIndices := embeddedSelfPassFieldIndices canonical (newEmbeddedFields.map Field.label)
            let staticFields <-
              if reEvalIndices.isEmpty then
                pure staticFields
              else do
                -- Pass 2 (audit PART B selective re-eval, mirrors the eager arm): re-evaluate ONLY
                -- the static fields that depend on an embedded label (feed just their `(index,
                -- field)` entries, so unselected fields are not recomputed); reuse Pass-1 values for
                -- the rest (byte-identical, no fresh-frame-id cache miss).
                let augmented := canonicalizeFields (canonical ++ newEmbeddedFields)
                let nested2 <- pushFrame augmented capturedEnv
                let selected := (indexedFields canonical).filter (fun (i, _) => reEvalIndices.contains i)
                let reEvaluated <- evalFieldRefsListWithFuel fuel nested2 selected
                let bySlot := (selected.map Prod.fst).zip reEvaluated
                pure ((staticFields.zipIdx).map fun (p1, i) =>
                  match bySlot.find? (fun (j, _) => j == i) with
                  | some (_, v) => v
                  | none => p1)
            -- Embedding-`Self` re-fold (mirrors the eager arm): a list-embedded `Self.<embedded-label>`
            -- read lives in an EMBEDDING the static-field two-pass misses; re-evaluate the embeddings
            -- (and meet) against the augmented frame so the read resolves. Byte-identical when no
            -- embedding reads a sibling-embedded `Self.<L>`.
            let refoldEmbeds := embeddingsReadEmbeddedSelf canonical embeddings (newEmbeddedFields.map Field.label)
            let (nestedForEmbeds, embeddingFields) <- refoldEmbeddingsIfSelf fuel canonical
              newEmbeddedFields embeddings capturedEnv merged nested embeddingFields refoldEmbeds
            match mergeEvaluatedFields (staticFields ++ expanded) with
            | none => pure .bottom
            | some merged =>
                -- A comprehension-introduced field (`y` from `if #x>0 {y:#x}`) is part of the def's
                -- own declared shape, so it must widen the closed allow-set alongside the static and
                -- embedding labels — otherwise re-closing rejects it as undeclared. `defFields` does
                -- NOT contain `y` (it lives only in the comprehension), so fold `expanded` in too.
                let met <- meetEmbeddingsWithFuel fuel nestedForEmbeds (mkStruct merged .regularOpen none []) embeddings
                -- Embedding a CLOSED def closes the host over `host ∪ embed` labels (CUE rule —
                -- mirrors the eager arm): a use-site narrowing reaches the embed's self-ref, but a
                -- use-site EXTRA the def does not declare is rejected. `defOpenness` is the deferred
                -- HOST body's openness (a `{#Closed}` wrapper is `regularOpen`); the closed embed
                -- overrides it ONLY for `regularOpen` (no explicit `...`), so `{#Meta} & {notallowed}`
                -- rejects `notallowed` (Bug2-10 closedness) while a `...`-tailed host stays open.
                let hostOpen := defOpenness.isOpen
                  && (defOpenness != .regularOpen || !(embeddings.any (embeddingClosesHost embedEnv)))
                let resolved := closeEmbeddedOver (defFields ++ expanded) embeddingFields hostOpen met
                -- D#1b: an incomplete-guard comprehension on the def-force path likewise keeps the
                -- struct residual (mirrors the eager arm). `deferredComps` holds only `if`/`for`
                -- residuals; embeddings are already meet into `resolved`.
                pure (withDeferredComprehensions resolved deferredComps defOpenness)
    -- Normalized struct def body: the no-tail no-pattern case splices the use fields and merges;
    -- the `defOpenViaTail` case splices open and keeps + rebases the tail. A pattern-bearing
    -- struct has no force-splice arm and falls to the `_` catch-all.
    | .struct defFields .defOpenViaTail (some defTail) [] _ =>
        let (mergedFields, _) := mergeConjOperands
          (⟨defFields, true, .ownDecl⟩ :: useOperands.map ConjOperand.ofPair)
        let canonical := canonicalizeFields mergedFields
        let mergedMap := labelIndexMap canonical
        let rebasedTail := remapConjRefs remapFuel 0 defFields mergedMap defTail
        let nested <- pushFrame canonical capturedEnv
        let evaluatedFields <- evalFieldRefsListWithFuel fuel nested (indexedFields canonical)
        match mergeEvaluatedFields evaluatedFields with
        | some fields =>
            let evaluatedTail <- evalValueWithFuel fuel nested [] rebasedTail
            pure (mkStruct fields .defOpenViaTail (some evaluatedTail) [])
        | none => pure .bottom
    | .struct defFields openness none [] _ =>
        let (mergedFields, open_) := mergeConjOperands
          (⟨defFields, openness.isOpen, .ownDecl⟩ :: useOperands.map ConjOperand.ofPair)
        let canonical := canonicalizeFields mergedFields
        let nested <- pushFrame canonical capturedEnv
        let evaluatedFields <- evalFieldRefsListWithFuel fuel nested (indexedFields canonical)
        match mergeEvaluatedFields evaluatedFields with
        | some fields => pure (mkStruct fields (.ofBool open_) none [])
        | none => pure .bottom
    | .conj arms =>
        -- Bug2-11: a deferred def-OF-def body (`#LS: defs.#LS & {…}`). Re-fold its arms WITH the
        -- use-site narrowing appended as synthetic struct conjuncts, under `capturedEnv` (the def's
        -- OWN package frame). This re-enters the `.conj` fold so a cross-package arm (`defs.#LS`)
        -- resolves its OWN import binding and defers correctly — exactly the inlined
        -- `defs.#LS & {…} & {narrow}` meet — instead of forcing the `.conj` standalone (which
        -- collapses the embedded self-ref before the narrowing arrives). Each arm keeps its own
        -- package frame because `capturedEnv` is the def's frame, NOT the use-site's.
        let narrowing := useOperands.map (fun op => mkStruct op.fst (.ofBool op.snd) none [])
        evalValueWithFuel fuel capturedEnv [] (.conj (arms ++ narrowing))
    | .top | .bottom | .bottomWith _ | .prim _ | .kind _
    | .notPrim _ | .stringRegex _ | .stringFormat _ | .boundConstraint _ _ _ | .lengthConstraint _ _ _ | .uniqueItems | .builtinCall _ _
    | .unary _ _ | .binary _ _ _ | .ref _ | .refId _ | .thisStruct
    | .selector _ _ | .index _ _ | .disj _ | .struct _ _ _ _ _ | .list _
    | .listTail _ _ | .embeddedList _ _ _ | .embeddedScalar _ _ | .comprehension _ _
    | .listComprehension _ _ | .interpolation _ | .dynamicField _ _ _
    | .closure _ _ => do
        let forced <- evalValueWithFuel fuel capturedEnv [] body
        pure (useOperands.foldl (fun current op => meet current (mkStruct op.fst (.ofBool op.snd) none [])) forced)
  termination_by (fuel, 4, 0)

  /-- Expand each embedded comprehension/dynamic field, accumulating the contributed fields AND
      the DEFERRED residual comprehensions (D#1b). The result is `(resolvedFields, deferredComps)`:
      a guard evaluating to BOTTOM short-circuits with `.error b` so the enclosing struct becomes
      that bottom (D#1a/c — bottom/type-error propagates, never vanishes); an INCOMPLETE guard
      keeps the original comprehension node in `deferredComps`, so the `.structComp` caller can
      re-emit it residual rather than dropping it. -/
  def expandComprehensionsWithFuel
      (fuel : Nat)
      (env : Env) : List Value -> EvalM (Except Value (List Field × List Value))
    | [] => pure (.ok ([], []))
    | comprehension :: rest => do
        match (<- expandComprehensionWithFuel fuel env comprehension) with
        | .error bot => pure (.error bot)
        | .ok (headFields, headDeferred) =>
            match (<- expandComprehensionsWithFuel fuel env rest) with
            | .error bot => pure (.error bot)
            | .ok (tailFields, tailDeferred) =>
                pure (.ok (headFields ++ tailFields, headDeferred ++ tailDeferred))
  termination_by comprehensions => (fuel, 3, comprehensions.length)

  /-- Expand one embedded comprehension/dynamic field into `(fields, deferredComps)`. An
      incomplete-guard comprehension (D#1b) contributes no fields and keeps ITSELF as the deferred
      residual; a resolved one contributes its fields and no residual. -/
  def expandComprehensionWithFuel
      (fuel : Nat)
      (env : Env)
      (value : Value) : EvalM (Except Value (List Field × List Value)) := do
    match fuel, value with
    | 0, _ => EvalState.truncate (.ok ([], []))
    | fuel + 1, .comprehension clauses body =>
        match (<- expandClausesWithFuel fuel env clauses body) with
        | .payload fields => pure (.ok (fields, []))
        | .bottom bot => pure (.error bot)
        | .deferred => pure (.ok ([], [value]))
    | fuel + 1, .dynamicField label fieldClass value => do
        let evaluatedLabel <- evalValueWithFuel fuel env [] label
        match classifyDynLabel (resolveDynLabelDefault evaluatedLabel) with
        | .concreteString name => do
            let evaluatedValue <- evalValueWithFuel fuel env [] value
            pure (.ok ([⟨name, fieldClass, evaluatedValue, false⟩], []))
        | .bottom bot => pure (.error bot)
        | .nonString ty => pure (.error (.bottomWith [.nonStringLabel ty]))
        -- DEFER: an abstract label keeps the field as a residual `.dynamicField` (carrying the
        -- UNEVALUATED key+value so a later struct re-eval against a narrowed frame can re-key it),
        -- rather than dropping it (DYN-DEF-1). Mirrors the incomplete-comprehension arm above.
        | .incomplete => pure (.ok ([], [.dynamicField label fieldClass value]))
    | _, _ => pure (.ok ([], []))
  termination_by (fuel, 0, 0)

  /--
  Walk a comprehension's clause chain, evaluating each clause's source/condition in the current
  env. Each `for` iteration pushes a fresh loop-variable frame; each `if` guard either admits or
  drops its remaining expansion. With no clauses left, the brace-block `body` is evaluated and
  handed to `onExhausted` to produce the payload.

  Generic over the payload `β` (struct → `List Field`, list → `List Value`): the struct/list
  comprehension twins were byte-identical on every clause arm and differed ONLY in the
  exhausted-chain `[]` handler, so that handler is the sole parameter. The asymmetry it carries is
  LOAD-BEARING and must NOT be unified away (`onExhausted` is the whole `[]`-arm body→outcome map,
  not a "wrap the body in `β`" shim):
  - STRUCT short-circuits a bare-`.bottom`/`.bottomWith` body to `.bottom` (D#1a — the bottom
    propagates and the enclosing struct becomes it); a non-`{...}` body yields no fields.
  - LIST wraps ANY body — INCLUDING a bottom — as the one-element payload `.payload [body]`. A
    bottom list ELEMENT (`[_|_]`) is NOT the list being bottom; `cue` renders the same value and
    errors on it only under concrete `export`. So the list twin deliberately does NOT
    bottom-propagate here.
  `onExhausted` is pure and non-recursive, so the fuel/clause recursion stays lexically visible to
  the well-founded `termination_by` measure (a combinator that hid the `fuel+1` pattern behind a
  control-flow lambda would lose the decrease equation — the truncate-primitive lesson). -/
  def expandClauseChain {β : Type} [EmptyCollection β] [Append β]
      (onExhausted : Value -> ClauseOutcome β)
      (fuel : Nat)
      (env : Env)
      (clauses : List (Clause Value))
      (body : Value) : EvalM (ClauseOutcome β) := do
    match fuel with
    -- `fuel=0` truncates to the empty payload, BUMPING `truncCount` (audit #6 saturation
    -- invariant — an uncounted truncation source corrupts results via the fuel-saturation cache).
    | 0 => EvalState.truncate (.payload ∅)
    | fuel + 1 =>
        match clauses with
        | [] => do
            let evaluatedBody <- evalValueWithFuel fuel env [] body
            pure (onExhausted evaluatedBody)
        | .guard condition :: rest => do
            let evaluatedCondition <- evalValueWithFuel fuel env [] condition
            -- A guard condition is a concrete-context use: a marked-default disjunction
            -- (`bool | *false`) collapses to its default before the boolean test, matching
            -- manifestation. A non-default disjunction does not collapse and the guard stays
            -- unsatisfied (the shared `collapseDefaultDisjunction` is identity on non-`.disj`).
            let testCondition := collapseDefaultDisjunction evaluatedCondition
            -- Fully classified (no catch-all): `true` admits, `false` drops, a BOTTOM guard
            -- propagates (D#1a), a CONCRETE non-bool is a type error (D#1c), an INCOMPLETE guard
            -- DEFERS — the whole comprehension stays residual (D#1b), surfaced by the caller.
            match classifyGuard testCondition with
            | .concreteTrue => expandClauseChain onExhausted fuel env rest body
            | .concreteFalse => pure (.payload ∅)
            | .bottom bot => pure (.bottom bot)
            | .nonBool ty => pure (.bottom (.bottomWith [.nonBoolGuard ty]))
            | .incomplete => pure .deferred
        | .letClause name value :: rest => do
            -- A `let` clause binds `name` in a NEW frame (+1, like `for`) visible to subsequent
            -- clauses + the body. Evaluate the value in the pre-push `env` (matching its
            -- resolve-time scope — symmetric with the `for` source), then bind the EVALUATED
            -- result in a one-slot frame. Binding the evaluated value (not the raw expr)
            -- keeps the frame's refs aligned exactly as `loopFrame` does for a `for` element.
            -- An unreferenced binding's value sits unread in the frame, so a bottom it would
            -- carry never propagates unless the body actually selects it.
            let evaluatedValue <- evalValueWithFuel fuel env [] value
            let nested <- pushFrame [⟨name, .regular, evaluatedValue, false⟩] env
            expandClauseChain onExhausted fuel nested rest body
        | .forIn key value source :: rest => do
            let evaluatedSource <- evalValueWithFuel fuel env [] source
            -- Fully classified (no catch-all): an iterable walks its pairs; a CONCRETE
            -- non-iterable is a type error (spec mandates `for` range over a list/struct); a
            -- BOTTOM source propagates (D#1a — short-circuits the comprehension); an INCOMPLETE
            -- source DEFERS the comprehension (it may still resolve to a list/struct).
            match classifyForSource evaluatedSource with
            | .iterable pairs => expandForPairs onExhausted fuel env key value rest body pairs
            | .concreteNonIterable ty => pure (.bottom (.bottomWith [.nonIterableSource ty]))
            | .bottom bot => pure (.bottom bot)
            | .incomplete => pure .deferred
  termination_by (fuel, 0, 0)

  /-- Expand the remaining clause chain once per iteration pair, concatenating payloads. A bottom
      from any iteration short-circuits the whole `for` (D#1a); an incomplete guard defers the
      whole comprehension (D#1b) — the residual is the original node, re-emitted by the caller.
      Generic over `β` with a `++`-appendable payload; `onExhausted` is threaded to the per-pair
      `expandClauseChain`. -/
  def expandForPairs {β : Type} [EmptyCollection β] [Append β]
      (onExhausted : Value -> ClauseOutcome β)
      (fuel : Nat)
      (env : Env)
      (key : Option String)
      (value : String)
      (rest : List (Clause Value))
      (body : Value) : List (Value × Value) -> EvalM (ClauseOutcome β)
    | [] => pure (.payload ∅)
    | pair :: pairs => do
        let nested <- pushFrame (loopFrame key pair.fst value pair.snd) env
        match (<- expandClauseChain onExhausted fuel nested rest body) with
        | .bottom bot => pure (.bottom bot)
        | .deferred => pure .deferred
        | .payload head =>
            match (<- expandForPairs onExhausted fuel env key value rest body pairs) with
            | .bottom bot => pure (.bottom bot)
            | .deferred => pure .deferred
            | .payload tail => pure (.payload (head ++ tail))
  termination_by pairs => (fuel, 3, pairs.length)

  /-- STRUCT comprehension clause-chain entry point: emit the body struct's fields,
      short-circuiting a bare-bottom body (D#1a — the bottom propagates out). Thin `β = List Field`
      wrapper that supplies `expandClauseChain` the struct exhausted-chain handler; the per-`for`
      iteration goes through the generic `expandForPairs`, so there is no struct-specific pairs
      walker. Measure tag 2 sits strictly between the tag-0 chain it calls at equal fuel
      (`0 < 2` ✓) and the tag-3 `evalListItemsWithFuel` that calls it at equal fuel (`2 < 3` ✓);
      its other callers decrement fuel. -/
  def expandClausesWithFuel
      (fuel : Nat) (env : Env) (clauses : List (Clause Value)) (body : Value) :
      EvalM ClauseExpansion :=
    expandClauseChain
      (fun evaluatedBody =>
        match evaluatedBody with
        -- A bottom body propagates (D#1a): a nested bottom guard surfaces here as a `.bottom`
        -- body, and must not be dropped.
        | .bottom => .bottom evaluatedBody
        | .bottomWith _ => .bottom evaluatedBody
        -- Emit the body's regular fields. The match is deliberately on ANY `.struct` (any
        -- openness/tail/patterns): a comprehension body's `...` tail and `[pat]:` constraints are
        -- body-local — they do NOT propagate out of the `for`/`if` block, only its named fields
        -- merge into the enclosing struct (cue: `for _ in [1] {a:1, ...}` ⇒ `{a:1}`). Matching all
        -- axes (`.struct fields _ _ _ _`) keeps the named fields regardless of tail/patterns; a
        -- narrower `.struct _ _ none [] _` arm would drop a tail/pattern-bearing body wholesale.
        | .struct fields _ _ _ _ => .payload fields
        -- D#1d-RESIDUAL: a comprehension BODY that itself evaluates to a HELD `.structComp`
        -- residual (an abstract-keyed dyn field `{(k):1}`, or a nested deferred `if`/`for`) is
        -- NOT resolved — defer the WHOLE comprehension (re-emit the original `.comprehension`
        -- node) so the residual is HELD, not dropped to `{}`. cue holds such a block under eval
        -- (errors incomplete under export). Under MEET-RESID-1 the held residual survives the
        -- `meet`/embed that would otherwise bottom it (the 7-TwoPassTests unnarrowed
        -- `#Outer` embed). A transient body resolves on the re-eval/force pass before reaching
        -- here, so this arm fires ONLY on a genuinely-undecidable residual.
        | .structComp .. => .deferred
        | _ => .payload [])
      fuel env clauses body
  termination_by (fuel, 2, 0)

  /-- LIST comprehension clause-chain entry point: with the clauses exhausted, evaluate the
      brace-block `body` to a single ELEMENT (`[evaluated]`) — wrapping ANY body, including a
      bottom, as a one-element list. This is the LOAD-BEARING asymmetry vs the struct twin: a
      bottom ELEMENT (`[_|_]`) is not the list being bottom (`cue` renders the same value and
      errors on it only under concrete `export`), so the list handler does NOT short-circuit.
      Thin `β = List Value` wrapper. -/
  def expandListClausesWithFuel
      (fuel : Nat) (env : Env) (clauses : List (Clause Value)) (body : Value) :
      EvalM ListClauseExpansion :=
    expandClauseChain (fun evaluatedBody => .payload [evaluatedBody]) fuel env clauses body
  termination_by (fuel, 2, 0)
end

/-- Run an evaluation action with a fresh cache, discarding the cache. The cache shares
    computed-once results within one top-level evaluation; it never escapes. -/
def runEval (action : EvalM α) : α :=
  (action.run { cache := ∅, nextFrameId := 0 }).fst

/-- Run an evaluation action and return `(result, evalCalls, cacheHits)`. The counts are a
    deterministic, build-checkable proxy for evaluation work: `evalCalls` is the number of
    core (cache-miss) evaluations, `cacheHits` the number of memo hits. On the synthetic
    `{a: prev, b: prev}` deep-sharing shape this witnesses exponential→linear without relying
    on wall-clock — used by the perf pins, not by any production path. -/
def runEvalStats (action : EvalM α) : α × Nat × Nat :=
  let (result, state) := action.run { cache := ∅, nextFrameId := 0 }
  (result, state.evalCalls, state.cacheHits)

def evalTopFieldsM (fields : List Field) : EvalM (Option (List Field)) := do
  let top <- pushFrame fields []
  let evaluated <- evalFieldRefsListWithFuel evalFuel top (indexedFields fields)
  pure (mergeEvaluatedFields evaluated)

def evalStructRefsM (value : Value) : EvalM Value := do
  match normalizeDefinitions value with
  | .struct fields openness tail patterns closedClauses =>
      let fields := canonicalizeFields fields
      match (<- evalTopFieldsM fields) with
      | some merged =>
          let top <- pushFrame fields []
          let evaluatedTail <- match tail with
            | some t => do let t <- evalValueWithFuel evalFuel top [] t; pure (some t)
            | none => pure none
          let evaluatedPatterns <- patterns.mapM fun pattern => do
            let evaluatedLabel <- evalValueWithFuel evalFuel top [] pattern.fst
            let evaluatedConstraint <- evalValueWithFuel evalFuel top [] pattern.snd
            pure (evaluatedLabel, evaluatedConstraint)
          let evaluatedClauses <- closedClauses.mapM fun clause => do
            let evaluatedPats <- clause.patterns.mapM (evalValueWithFuel evalFuel top [])
            pure { clause with patterns := evaluatedPats }
          pure (applyEvaluatedStructN merged openness evaluatedTail evaluatedPatterns
            evaluatedClauses)
      | none => pure .bottom
  | normalized@(.structComp _ _ _) => evalValueWithFuel evalFuel [] [] normalized
  | value => pure value

def evalStructRefs (value : Value) : Value :=
  runEval (evalStructRefsM value)

/-- Run eval and return the core-eval count, memo-hit count, and final cache sizes — a
    deterministic proxy for evaluation work and a witness that the fuel-keyed `cache` stays
    empty on a fully-saturating program (the basis for the empty-`cache`-skip fast path in
    `evalValueWithFuel`). Returns (result, evalCalls, cacheHits, satCacheSize, fuelCacheSize,
    forceCacheSize). -/
def evalStructRefsProfile (value : Value) :
    Value × Nat × Nat × Nat × Nat × Nat :=
  let (result, state) := (evalStructRefsM value).run { cache := ∅, nextFrameId := 0 }
  (result, state.evalCalls, state.cacheHits,
    state.satCache.size, state.cache.size, state.forceCache.size)

/-- `evalCalls` for `evalStructRefs value` — the core-eval count for the perf pins. A
    deterministic proxy for evaluation work that witnesses exponential→linear on the
    deep-sharing shape without wall-clock. -/
def evalStructRefsCalls (value : Value) : Nat :=
  (runEvalStats (evalStructRefsM value)).snd.fst

end Kue
