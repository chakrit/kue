import Kue.Builtin
import Kue.Decimal
import Kue.EvalOps
import Kue.Lattice
import Kue.Regex
import Kue.Normalize
import Std.Data.HashMap
import Kue.EvalBase

namespace Kue

mutual
/-- Does `value` reference the def's OWN top frame from `depth` frame-pushers deep — a
    `refId ⟨depth, _⟩` reachable by descending `depth` struct/comprehension frames? Generalizes
    `hasDepth0Ref` (the `depth == 0` case) to the DEEP self-references real defs use: a hidden
    field read from a nested struct (`spec: acme: email: Self.#email`, where `#email` is a
    top-level def field referenced from 3 frames deep → `refId ⟨3, _⟩`). Descending a
    frame-pusher increments `depth`; a `refId ⟨d, _⟩` is a self-ref iff `d == depth` (it lands
    exactly on the def's frame). Refs to shallower (`d < depth`, an intervening struct's own
    sibling) or outer (`d > depth`, a cross-package/enclosing scope) frames are NOT def
    self-refs. Fuel-bounded for totality. -/
def hasSelfRefAtDepth (fuel : Nat) (depth : Nat) : Value -> Bool
  | .refId id => id.depth.val == depth
  | .conj constraints =>
      match fuel with
      | 0 => false
      | fuel + 1 => constraints.any (hasSelfRefAtDepth fuel depth)
  | .builtinCall _ args =>
      match fuel with
      | 0 => false
      | fuel + 1 => args.any (hasSelfRefAtDepth fuel depth)
  | .unary _ value =>
      match fuel with
      | 0 => false
      | fuel + 1 => hasSelfRefAtDepth fuel depth value
  | .binary _ left right =>
      match fuel with
      | 0 => false
      | fuel + 1 => hasSelfRefAtDepth fuel depth left || hasSelfRefAtDepth fuel depth right
  | .selector base _ =>
      match fuel with
      | 0 => false
      | fuel + 1 => hasSelfRefAtDepth fuel depth base
  | .index base key =>
      match fuel with
      | 0 => false
      | fuel + 1 => hasSelfRefAtDepth fuel depth base || hasSelfRefAtDepth fuel depth key
  | .disj alternatives =>
      match fuel with
      | 0 => false
      | fuel + 1 => alternatives.any (fun alt => hasSelfRefAtDepth fuel depth alt.snd)
  | .list items =>
      match fuel with
      | 0 => false
      | fuel + 1 => items.any (hasSelfRefAtDepth fuel depth)
  | .listTail items tail =>
      match fuel with
      | 0 => false
      | fuel + 1 =>
          items.any (hasSelfRefAtDepth fuel depth) || hasSelfRefAtDepth fuel depth tail
  | .interpolation parts =>
      match fuel with
      | 0 => false
      | fuel + 1 => parts.any (hasSelfRefAtDepth fuel depth)
  | .structComp fields comprehensions _ =>
      match fuel with
      | 0 => false
      | fuel + 1 =>
          fields.any (fun f => hasSelfRefAtDepth fuel (depth + 1) (Field.value f))
            || comprehensions.any (hasSelfRefAtDepth fuel (depth + 1))
  | .struct fields _ tail patterns _ =>
      -- Fields, optional tail, patterns.
      match fuel with
      | 0 => false
      | fuel + 1 =>
          fields.any (fun f => hasSelfRefAtDepth fuel (depth + 1) (Field.value f))
            || (match tail with | some t => hasSelfRefAtDepth fuel (depth + 1) t | none => false)
            || patterns.any (fun p =>
                 hasSelfRefAtDepth fuel (depth + 1) p.fst
                   || hasSelfRefAtDepth fuel (depth + 1) p.snd)
  | .comprehension clauses body =>
      -- Clause sources/guards resolve in the comprehension's enclosing frame; the body resolves
      -- `#forClauses` frames deeper (`for` pushes one, `guard` none). `hasSelfRefAtDepthClauses`
      -- threads the depth exactly as `resolveClausesWithFuel` does: a too-shallow body scan would
      -- compare a deep `Self.<own-field>` read (resolved at `depth + #for`) against `depth`, MISS
      -- it, and skip the deferral the use-site narrowing needs — a stale-value miss (A5-followup).
      match fuel with
      | 0 => false
      | fuel + 1 => hasSelfRefAtDepthClauses fuel depth clauses body
  | .listComprehension clauses body =>
      -- List-context comprehension (`out: [for x in xs {v: Self.#t}]`): same clause/body scoping
      -- as `.comprehension`. The body read of `Self.#t` lands `#forClauses` frames deeper, so it
      -- must be scanned there, not at `depth`.
      match fuel with
      | 0 => false
      | fuel + 1 => hasSelfRefAtDepthClauses fuel depth clauses body
  | .dynamicField key _ value =>
      -- A dynamic field pushes NO frame (the resolver resolves both key and value in the parent
      -- scope, `Resolve.lean`), so a self-ref in either resolves to the parent's frames — scanned
      -- at `depth`, not `depth + 1`. The over-deep `+1` made `defBodyHasSiblingSelfRef` MISS a def
      -- sibling read solely through a dyn-field value (`[for x in xs {("k"): kind}]`), gating off
      -- the deferral the use-site narrowing needs (A-EN3-DYN — the same depth-mirror invariant as
      -- `foldValueWithDepth`'s dyn-field arm).
      match fuel with
      | 0 => false
      | fuel + 1 => hasSelfRefAtDepth fuel depth key || hasSelfRefAtDepth fuel depth value
  | _ => false

/-- Does any clause source/guard or the body reference the def's OWN frame at `depth` (see
    `hasSelfRefAtDepth`), threading frame depth through the clause chain exactly as
    `resolveClausesWithFuel` does: each `forIn` source is scanned at the current `depth` and pushes
    one frame for subsequent clauses and the body; a `guard` condition scans at `depth` and pushes
    none. So a body self-ref at `depth + #forClauses` is detected, not missed. -/
def hasSelfRefAtDepthClauses
    (fuel : Nat) (depth : Nat) (clauses : List (Clause Value)) (body : Value) : Bool :=
  descendClauses (· || ·)
    (fun d source => hasSelfRefAtDepth fuel d source)
    (fun d cond => hasSelfRefAtDepth fuel d cond)
    (fun d => hasSelfRefAtDepth fuel d body)
    depth clauses
end

/-- Does this unevaluated definition body reference one of its OWN top-level fields — directly
    (`out: #name`) OR from a nested position (`spec: acme: email: Self.#email`, the real-app
    shape)? Scans each top-level field's body for a self-ref landing on the def frame, descending
    nested frames via `hasSelfRefAtDepth` (depth 0 = the def's own frame). This is the exact set
    that collapses under the eager import-selector path: the use-site narrows a top-level hidden
    field, but an eager eval resolves the (possibly deep) reference to it BEFORE the narrowing. -/
def defBodyHasSiblingSelfRef : Value -> Bool
  | .structComp fields comprehensions _ =>
      fields.any (fun f => hasSelfRefAtDepth evalFuel 0 (Field.value f))
        || comprehensions.any (hasSelfRefAtDepth evalFuel 0)
  -- Scan fields + optional tail. A pattern-bearing struct falls through to `false`.
  | .struct fields _ tail [] _ =>
      fields.any (fun f => hasSelfRefAtDepth evalFuel 0 (Field.value f))
        || (match tail with | some t => hasSelfRefAtDepth evalFuel 0 t | none => false)
  | _ => false

/-- Resolve an embedding expression (`.refId` to a sibling/outer def, or a `pkg.#Def` selector
    into a package binding) to the UNEVALUATED def body it names, looked up in `env`. Returns the
    body struct/structComp/structTail or `none` for anything that is not a direct def reference.
    Used to decide whether an embedding's OWN body needs deferral — the host must defer too so the
    use-site narrowing reaches the embed before it collapses. -/
def resolveEmbedDefBody? (env : Env) : Value -> Option Value
  | .refId id =>
      match env.drop id.depth.val with
      | [] => none
      | frame :: _ =>
          match nthField id.index.val frame.snd with
          | some f => some (Field.value f)
          | none => none
  | .selector (.refId id) label =>
      match env.drop id.depth.val with
      | [] => none
      | frame :: _ =>
          match nthField id.index.val frame.snd with
          | some baseField =>
              match Field.value baseField with
              | .struct pkgFields _ _ _ _ =>
                  match findEvalField label pkgFields with
                  | some defField => some (Field.value defField)
                  | none => none
              | _ => none
          | none => none
  -- An embedded DEFAULT DISJUNCTION (`(*_#A|_#B)`) contributes its default arm to the host
  -- (argocd `#OpaqueSecret`). Resolve through to the default arm's def body, so `bodyNeedsDefer`
  -- recurses into it — the host must defer if the default arm's sibling self-ref/comprehension
  -- depends on a use-site-narrowed field. One level: the default arm is a single `.refId`.
  | .disj alternatives =>
      match resolveDisjDefault? alternatives with
      | some (.refId id) =>
          match env.drop id.depth.val with
          | [] => none
          | frame :: _ =>
              match nthField id.index.val frame.snd with
              | some f => some (Field.value f)
              | none => none
      | _ => none
  | _ => none

/-- Does the resolved field a reference/selector names denote a DEFINITION (`#`-prefixed)? A
    definition reference is closed (even when its UNEVALUATED body is still `regularOpen` — the
    parser marks struct literals open by default; def-closedness is applied at normalize/eval), so
    embedding it closes the host. -/
def embeddingFieldIsDefinition (env : Env) : Value -> Bool
  | .refId id =>
      match env.drop id.depth.val with
      | [] => false
      | frame :: _ =>
          match nthField id.index.val frame.snd with
          | some f => (Field.fieldClass f).isDefinition
          | none => false
  | .selector (.refId id) label =>
      match env.drop id.depth.val with
      | [] => false
      | frame :: _ =>
          match nthField id.index.val frame.snd with
          | some baseField =>
              match Field.value baseField with
              | .struct pkgFields _ _ _ _ =>
                  match findEvalField label pkgFields with
                  | some defField => (Field.fieldClass defField).isDefinition
                  | none => false
              | _ => false
          | none => false
  | _ => false

/-- Does embedding `embedding` CLOSE its host? CUE: embedding a closed def into a no-`...` struct
    closes the result over the union `host labels ∪ embed labels` (a SIBLING field declared in the
    same struct literal is still admitted, but a later MEET against the now-closed struct rejects
    an undeclared extra). Two ways to be closed: the embed is a DEFINITION reference
    (`embeddingFieldIsDefinition` — closed by def-class), OR a non-def struct embed whose resolved
    body is explicitly `defClosed`. An embed with an explicit `...` (`defOpenViaTail`) or a plain
    `regularOpen` non-def struct does NOT close. `none`/non-struct bodies do not close. -/
def embeddingClosesHost (env : Env) (embedding : Value) : Bool :=
  embeddingFieldIsDefinition env embedding ||
    match resolveEmbedDefBody? env embedding with
    | some (.struct _ openness _ _ _) => !openness.isOpen
    | some (.structComp _ _ openness) => !openness.isOpen
    | _ => false

/-- Does `body`, or any def it transitively EMBEDS, satisfy the non-recursive `leaf` predicate?
    Walks the embed chain (`resolveEmbedDefBody?` per embedding, resolved against `env`),
    fuel-bounded against embed cycles. The variation point is the pure, non-recursive `leaf :
    Value → Bool`; the recursion (the fixed chain-walk) is owned here, so the `fuel+1` decrease
    stays lexically visible to `termination_by` (the AD4-1 / `expandClauseChain` shape — a leaf
    that itself recursed would be the DRY-1 trap, but neither `leaf` does). Two instantiations:
    `bodyNeedsDefer` (leaf = `defBodyHasSiblingSelfRef`) and `embedBodyEmbedsDisjDeep`
    (leaf = `embedBodyEmbedsDisj`). -/
def embedChainAny (leaf : Value -> Bool) (env : Env) (fuel : Nat) (body : Value) : Bool :=
  leaf body ||
    match fuel, body with
    | nextFuel + 1, .structComp _ comprehensions _ =>
        (comprehensions.filter isEmbeddingValue).any fun embed =>
          match resolveEmbedDefBody? env embed with
          | some embedBody => embedChainAny leaf env nextFuel embedBody
          | none => false
    | _, _ => false
  termination_by fuel

/-- Does a body need deferral to a `.closure` — either a DIRECT sibling self-ref/guard
    (`defBodyHasSiblingSelfRef`), OR an EMBEDDING whose own referenced def needs deferral? The
    second clause is the embed-chain case (`Outer: {#Inner}` where `#Inner` has a guard whose
    output depends on a use-site-narrowed field): the embed is NOT a self-ref of `Outer`, so the
    direct check misses it, yet `Outer` must defer so the narrowing reaches `#Inner` before its
    guard is evaluated. Fuel-bounded; recurses through embeddings via `embedChainAny`. -/
def bodyNeedsDefer (env : Env) (fuel : Nat) (body : Value) : Bool :=
  embedChainAny defBodyHasSiblingSelfRef env fuel body

/-- Bug2-5: does an embed body embed a STRUCTURAL disjunction either DIRECTLY (`embedBodyEmbedsDisj`)
    or TRANSITIVELY through one of its OWN embeddings? The direct check (`embedBodyEmbedsDisj`) only
    inspects the body's own `cs`, so a body that merely RE-EMBEDS a disjunction-bodied def
    (`#Mid: {#Mixin; …}` where `#Mixin`'s body is `listShape | structShape | error`) is missed — and
    then the host's `spliceOperandForEmbed` into `#Mid` drops the regular fields (`kind`) the buried
    disjunction's let-local (`_patch.kind`) needs, so the narrowing never reaches the disjunction-arm
    path two embed levels down. This is the embed-chain analogue of `bodyNeedsDefer`: it recurses
    through embeddings (`embedChainAny`) so a host narrowing reaches a transitively-embedded
    disjunction. Returns `true` when the body, or any def it transitively embeds, embeds a disjunction.
    The splice it gates (Gap-2b: route ALL regular output fields into the embed) is sound regardless
    of depth — meet is idempotent on a field an arm already carries, a real conflict still bottoms —
    so widening the GATE through the embed chain never over-narrows. Fuel-bounded against embed
    cycles. -/
def embedBodyEmbedsDisjDeep (env : Env) (fuel : Nat) (body : Value) : Bool :=
  embedChainAny embedBodyEmbedsDisj env fuel body

/-- Bug2-14b: the env in which a closure body's OWN embed-refs resolve. `forceClosureWithConjunctCore`
    pushes the body's static def frame at depth 0 (`(0, defFields) :: capturedEnv`), so a body
    embedding (`#Use: { #Mixin; … }`'s `#Mixin`, a `.refId depth:=1`) skips that frame to land in
    `capturedEnv`. Resolving the same ref against the bare outer `env` (the meet-fold / conj-fold
    scope) lands in the WRONG frame — missing a transitively-embedded disjunction, so the
    `embedBodyEmbedsDisjDeep` gate falsely returns `false` and the host's regular narrowing is
    dropped from the splice. Mirror the force frame so the chain resolves. -/
def bodyForceFrameEnv (capturedEnv : Env) (body : Value) : Env :=
  (0, (match body with | .structComp fs _ _ => fs | .struct fs _ _ _ _ => fs | _ => [])) :: capturedEnv

/-- The DEFINITION-class fields a body declares directly (its own static `#x` decls). A `.struct`
    body exposes its fields; a `.structComp` exposes its static fields (the embed/comprehension
    members are not field decls). Non-struct bodies expose none. -/
def bodyDefinitionFields : Value -> List Field
  | .struct fields _ _ _ _ => fields.filter (fun f => (Field.fieldClass f).isDefinition)
  | .structComp fields _ _ => fields.filter (fun f => (Field.fieldClass f).isDefinition)
  | _ => []

/-- Bug2-8: the same-definition-PATH decls an EMBEDDING contributes that collide with the host
    def's OWN definition-class decls. When a def declares `#m` once and EMBEDS another def that
    also declares `#m` (`#A: {#m:{a}}` then `#Use: {#A; #m:{c}}`), the two `#m` decls are repeated
    declarations of the ONE def path `#m` merged across the embed boundary — cue close-once-UNIONS
    them. Resolving each embedding's body (`resolveEmbedDefBody?`) and keeping only the
    definition-class fields whose label is among the host's own def labels (`hostDefLabels`)
    surfaces exactly those decls, which the caller folds into the static frame as an
    `embeddedDecl`-provenance operand so `mergeConjOperands` unions them (and a sibling `vis: #m`
    resolves against the union). A non-definition embed field, or a label the host does not also
    declare as a definition, is NOT surfaced — it flows through the ordinary embed meet-fold,
    keeping the cert-manager closed-pattern meet and every cross-conjunct value-meet untouched. -/
def embedSameDefPathDecls (env : Env) (hostDefLabels : List String) (embedding : Value) :
    List Field :=
  match resolveEmbedDefBody? env embedding with
  | some body =>
      (bodyDefinitionFields body).filter (fun f => hostDefLabels.contains (Field.label f))
  | none => []

/-- Follow a def body that is itself an alias/import-selector indirection to the terminal
    struct-like body it ultimately names, paired with the package frame that body's refs
    resolve against. `frameEnv` is the env in which `body`'s refs resolve, with `body`'s own
    enclosing package frame at depth 0; `capturedFrame` is the field list of that enclosing
    frame (what the caller must `pushFrame` to force the returned body).

    The headline shape (`#A: parts.#M`, then `defs.#A & {…}`): `#A`'s body is the selector
    `parts.#M`, not a struct — so the direct producers (`importDefClosureBody?`/`refDefClosureBody?`)
    see no struct body and take the eager path, resolving `parts.#M` in the `defs` frame BEFORE
    the use-site narrows. Following the indirection here discovers the real `#M` body AND the
    `parts` package frame it captures, so the caller defers to a `.closure` over the RIGHT frame
    and the use-site conjunct splices at force time exactly as a direct `defs.#M & {…}` does.

    Two indirection arms, both fuel-bounded against cyclic alias chains (`#A: #A`):
    - `.selector (.refId baseId) label`: resolve `baseId` in `frameEnv` to a package `.struct`,
      find `label`, and recurse with that package's fields as the new captured frame.
    - `.refId id`: resolve `id` in `frameEnv` to a sibling/outer def and recurse (two-level
      `#B: #A`, `#A: parts.#M`), keeping the captured frame at the resolved binding's scope.

    Returns `(capturedFrame, terminalBody)` when the terminal is struct-like AND needs deferral
    (`bodyNeedsDefer`); `none` for a non-indirection body (left to the direct producers), a
    terminal that does not defer, or fuel exhaustion. The terminal is NOT re-normalized here —
    the callers normalize a definition body once they own it. -/
def followAliasDefBody? (fuel : Nat) (frameEnv : Env) (capturedFrame : List Field) :
    Value -> Option (List Field × Value)
  | .selector (.refId baseId) label =>
      match fuel with
      | 0 => none
      | fuel + 1 =>
          match frameEnv.drop baseId.depth.val with
          | [] => none
          | baseFrame :: _ =>
              match nthField baseId.index.val baseFrame.snd with
              | none => none
              | some baseField =>
                  match Field.value baseField with
                  | .struct pkgFields _ _ _ _ =>
                      match findEvalField label pkgFields with
                      | some defField =>
                          -- The found def lives in `pkgFields`; its body's refs resolve with
                          -- `pkgFields` at depth 0 over the package binding's outer scope.
                          let nextEnv : Env := (0, pkgFields) :: frameEnv.drop (baseId.depth.val + 1)
                          followAliasDefBody? fuel nextEnv pkgFields (Field.value defField)
                      | none => none
                  | _ => none
  | .refId id =>
      match fuel with
      | 0 => none
      | fuel + 1 =>
          match frameEnv.drop id.depth.val with
          | [] => none
          | frame :: outer =>
              match nthField id.index.val frame.snd with
              | none => none
              | some defField =>
                  -- The resolved def's body resolves with `frame` at depth 0 over `outer`.
                  followAliasDefBody? fuel (frame :: outer) frame.snd (Field.value defField)
  | body =>
      let isStructLike := match body with
        | .structComp _ _ _ => true
        | .struct _ _ _ [] _ => true | _ => false
      let bodyEnv : Env := (0, []) :: (0, capturedFrame) :: frameEnv.drop 1
      if isStructLike && bodyNeedsDefer bodyEnv evalFuel body then
        some (capturedFrame, body)
      else
        none

/-- Resolve a cross-package selector / bare ref to the UNEVALUATED def body it names, paired with
    the package frame that body's refs resolve against (`(capturedFrame, body)`). Unlike
    `followAliasDefBody?` this does NOT require the terminal to be a deferring struct — it returns
    the body whatever its shape (`.conj` def-of-def included), so a recursive deferral check can
    descend a def-OF-def-OF-def chain. `frameEnv` carries the selector's enclosing frame at depth 0.
    `none` for a non-ref/selector or an unresolvable binding. -/
def resolveSelectorDefBody? (frameEnv : Env) : Value -> Option (List Field × Value)
  | .selector (.refId baseId) label =>
      match frameEnv.drop baseId.depth.val with
      | [] => none
      | baseFrame :: _ =>
          match nthField baseId.index.val baseFrame.snd with
          | none => none
          | some baseField =>
              match Field.value baseField with
              | .struct pkgFields _ _ _ _ =>
                  match findEvalField label pkgFields with
                  | some defField =>
                      if defField.fieldClass.isDefinition then
                        some (pkgFields, Field.value defField)
                      else none
                  | none => none
              | _ => none
  | .refId id =>
      match frameEnv.drop id.depth.val with
      | [] => none
      | frame :: _ =>
          match nthField id.index.val frame.snd with
          | some defField =>
              if defField.fieldClass.isDefinition then some (frame.snd, Field.value defField)
              else none
          | none => none
  | _ => none

/-- Bug2-11: does a cross-package def body that is itself a `.conj` (`#LS: defs.#LS & {…}` — a
    def-OF-def indirection) have an ARM that resolves THROUGH a cross-package selector/alias to a
    deferral-needing struct, possibly via FURTHER `.conj` def-of-def levels? If so the WHOLE `.conj`
    must defer, so the use-site narrowing is re-folded into its arms
    (`forceClosureWithConjunctCore`'s `.conj` arm) — each arm resolving in ITS OWN package frame —
    rather than forced standalone (which collapses the embedded self-ref before the narrowing
    arrives). `frameEnv` carries the def's enclosing package frame at depth 0, so an arm `defs.#LS`'s
    `defs` import binding resolves there. An arm is deferring when `followAliasDefBody?` resolves it
    to a deferring struct, OR it resolves to a FURTHER `.conj` def-of-def with a deferring arm
    (`defaults2.#LS = defaults.#LS & {…}` — the 3-level chain). Fuel-bounded against alias cycles. -/
def conjBodyHasDeferringArm (fuel : Nat) (frameEnv : Env) (capturedFrame : List Field) :
    Value -> Bool
  | .conj arms => arms.any (fun arm =>
      (followAliasDefBody? evalFuel frameEnv capturedFrame arm).isSome ||
      (match fuel with
       | 0 => false
       | fuel + 1 =>
           match resolveSelectorDefBody? frameEnv arm with
           | some (argFrame, argBody) =>
               conjBodyHasDeferringArm fuel ((0, argFrame) :: frameEnv) argFrame argBody
           | none => false))
  | _ => false

/-- The producer gate for slice-3 closures. Given the selector `base.label` where `base` is
    the UNEVALUATED binding `id` resolves to in `env`, decide whether to defer instead of
    eagerly evaluating `base` and plucking `label`. Returns the def's UNEVALUATED body when
    ALL hold: (1) the binding is a `.struct` (an import/package or any struct base), (2) it
    has a field `label` that is a definition (`#`), (3) that def body has a sibling self-ref
    (`defBodyHasSiblingSelfRef`) — the only shape that collapses today, so deferring it
    regresses no currently-green fixture. `none` ⇒ take the existing eager path. The caller
    pairs the returned body with `pushFrame pkgFields env` as the captured env.

    The captured body is run through `normalizeDefinitionValueWithFuel` to close it as a
    definition body (`open_ := false`, recursively): an IMPORTED package's def bodies were not
    normalized at load time (`normalizeDefinitions` only normalizes the TOP value's own `#`
    fields, never the hidden import binding's), so without this a forced cross-package def
    would lose its closedness and wrongly admit use-site fields the def does not declare. -/
def importDefClosureBody? (env : Env) (id : BindingId) (label : String) :
    Option (List Field × Value) :=
  match env.drop id.depth.val with
  | [] => none
  | frame :: _ =>
      match nthField id.index.val frame.snd with
      | none => none
      | some baseField =>
          match Field.value baseField with
          | .struct pkgFields _ _ _ _ =>
              match findEvalField label pkgFields with
              | some defField =>
                  -- The def body's embeddings reference the package frame (`pkgFields`, pushed when
                  -- the body is forced) at depth-1, the body itself at depth-0. So resolve them
                  -- against a placeholder body-frame over the package frame over the binding scope.
                  let bodyEnv : Env := (0, []) :: (0, pkgFields) :: env.drop (id.depth.val + 1)
                  if defField.fieldClass.isDefinition
                      && bodyNeedsDefer bodyEnv evalFuel (Field.value defField) then
                    some (pkgFields,
                      normalizeDefinitionValueWithFuel normalizeFuel (Field.value defField))
                  else if defField.fieldClass.isDefinition then
                    -- The def body is NOT a directly-deferring struct — it may be an alias/import
                    -- selector (`#A: parts.#M`) that resolves THROUGH the package indirection to a
                    -- struct that does. Follow the chain to its terminal `(frame, body)` and defer
                    -- over THAT frame (the `parts` package, not `defs`), so the use-site splices
                    -- like a direct `parts.#M & {…}`. The body's refs resolve with `pkgFields` at
                    -- depth 0 over the binding's outer scope.
                    let frameEnv : Env := (0, pkgFields) :: env.drop (id.depth.val + 1)
                    match followAliasDefBody? evalFuel frameEnv pkgFields (Field.value defField) with
                    | some (capturedFrame, body) =>
                        some (capturedFrame, normalizeDefinitionValueWithFuel normalizeFuel body)
                    | none =>
                      -- Bug2-11: the def body is a `.conj` def-OF-def (`#LS: defs.#LS & {…}`) whose
                      -- ARM is a cross-package selector reaching a deferral-needing struct. Capture
                      -- the RAW `.conj` over `pkgFields` (the def's OWN package frame) so the force
                      -- re-folds the use-site narrowing into its arms with each arm resolving in its
                      -- own package frame (`forceClosureWithConjunctCore`'s `.conj` arm) — NOT a
                      -- standalone force that collapses the embedded self-ref. Unnormalized: each
                      -- arm carries its own closedness through the re-fold (the `.conj` is not a flat
                      -- struct to close).
                      if conjBodyHasDeferringArm evalFuel frameEnv pkgFields (Field.value defField) then
                        some (pkgFields, Field.value defField)
                      else
                        none
                  else
                    none
              | none => none
          | _ => none

/-- Bare-reference companion to `importDefClosureBody?` (slice E). A same-file def referenced
    DIRECTLY (`#Outer`, a `.refId`, not a `base.label` selector) whose body has a sibling self-ref
    must defer to a `.closure`, so a use-site conjunction (`#Outer & {#oname: "o"}`, or an
    embedding `#Inner & {#name: …}`) splices the narrowing into the def frame BEFORE its self-ref
    (`oname: Self.#oname`) collapses. Two gaps `conjStructOperand?`'s lazy-merge leaves:

    1. A `.structComp` body (embed-bearing) — no `.structComp` arm in `conjStructOperand?` at ANY
       depth, so it always took the eager collapse.
    2. A `.struct`/`.structTail` body referenced from a NESTED frame (`id.depth > 0` — e.g. the
       inner def of an embed chain, one frame deeper than the embedding's host) —
       `conjStructOperand?` is depth-0-only (`id.depth != 0 ⇒ none`), so a nested self-ref def ref
       lost the lazy-merge and collapsed.

    A DEPTH-0 `.struct`/`.structTail` self-ref ref keeps the existing lazy-merge path (the common
    same-file `#M & {narrow}` case) — deferring it too would churn every currently-green fixture.
    A definition body is normalized (closed, recursively), mirroring the selector producer; a
    NON-definition `.structComp` body (regular field `M: {x:int, if x>0 {y:x}}`, site 2 of F2)
    defers too but is left UNCLOSED — its open closedness is preserved so the use-site `meet`
    admits siblings as CUE does. -/
def refDefClosureBody? (env : Env) (id : BindingId) : Option Value :=
  match env.drop id.depth.val with
  | [] => none
  | frame :: _ =>
      match nthField id.index.val frame.snd with
      | none => none
      | some defField =>
          let body := Field.value defField
          let isStructComp := match body with | .structComp _ _ _ => true | _ => false
          let isStructLike := match body with
            | .structComp _ _ _ => true
            | .struct _ _ _ [] _ => true | _ => false
          let isDef := defField.fieldClass.isDefinition
          -- Fire on the lazy-merge gaps `conjStructOperand?` cannot reduce: an embed-/guard-bearing
          -- `.structComp` (any depth — definition OR regular field; the regular case is F2 site 2:
          -- a comprehension struct meet whose guard must fire AFTER the use-site narrowing), or a
          -- nested (`depth > 0`) self-ref `.struct`/`.structTail` definition. Depth-0 plain
          -- `.struct`/`.structTail` stays on the lazy-merge path.
          -- Embeddings inside `body` are written relative to `body`'s own (about-to-be-pushed)
          -- frame, so depth-0 is `body` itself and depth-1 reaches the binding's scope. Prepend a
          -- placeholder body-frame onto the binding's resolution env so `resolveEmbedDefBody?`
          -- resolves an embed's depth-1 ref to the right enclosing frame.
          let bodyEnv : Env := (0, []) :: env.drop id.depth.val
          if isStructLike && bodyNeedsDefer bodyEnv evalFuel body
              && (isStructComp || (isDef && id.depth.val > 0)) then
            if isDef then
              some (normalizeDefinitionValueWithFuel normalizeFuel body)
            else
              some body
          else
            none

/-- Produce the captured `.closure` for a conjunct that is a bare ref to a self-ref def the
    lazy-merge path cannot handle (`#Outer & {narrow}` or a nested embed `#Inner & {narrow}` —
    slice E). The `.conj` fold uses this to defer such an operand BEFORE eval so the multi-operand
    force-fold splices the use-site narrowing into the def frame (`oname: Self.#oname` /
    `iname: Self.#name` see the narrowed siblings). Mirrors the selector producer's role in the
    `.conj` path. `none` for any other operand (evaluated normally). -/
def conjDefClosure? (env : Env) : Value -> Option Value
  | .refId id =>
      match env.drop id.depth.val with
      | [] => none
      | frame :: outer =>
          match refDefClosureBody? env id with
          | some defBody => some (.closure (frame :: outer) defBody)
          | none => none
  | _ => none

/-- Defer a `.structComp` HOST conjunct (`{#Meta}` — a struct whose only content is an embedded
    self-ref def) into a `.closure` so the `.conj` fold force-splices the sibling use-site
    narrowing into it BEFORE its embedded self-ref collapses (Bug2-10). Without this the host
    evaluates STANDALONE through the `.structComp` eval arm with no use-operands, freezing the
    embed's `Self.#name` at its abstract `string`; the outer `{narrow}` then meets too late.
    `conjDefClosure?` defers a BARE `.refId` only — a `.structComp` wrapper bypasses it, which is
    exactly the gap this closes. Captures `env` (the host conjunct's own scope): the standalone
    arm pushes the host fields onto `env`, and `forceClosureWithConjunct`'s `.structComp` arm
    pushes the spliced fields onto `capturedEnv = env`, so the two paths agree modulo the splice.

    Fires ONLY when the host genuinely needs the narrowing — `bodyNeedsDefer` (host body OR a
    transitively-embedded def body carries a sibling self-ref). A plain narrowing struct
    (`{#name:"x"}`) has no embed, so `bodyNeedsDefer` is false and it is never deferred; a
    no-self-ref embed host likewise stays standalone. The has-a-narrowing-SIBLING half of the
    over-fire guard is enforced at the call site (only the `.conj` fold reaches here, so a bare
    `{#Meta}` with no sibling never enters this path). `none` for any non-structComp operand. -/
def conjStructCompDefer? (env : Env) : Value -> Option Value
  | body@(.structComp _ _ _) =>
      -- The host's embed refs resolve against the frame the standalone `.structComp` arm pushes
      -- (`pushFrame fields env` adds one frame), so resolve the deferral check over a placeholder
      -- host-frame `(0, []) :: env` — exactly the body-frame `forceClosureWithConjunct` will use.
      let bodyEnv : Env := (0, []) :: env
      if bodyNeedsDefer bodyEnv evalFuel body then some (.closure env body) else none
  | _ => none

/-- Is `constraint` a struct-shaped conjunct that can SPLICE a use-site narrowing into a deferred
    sibling (the has-a-narrowing-sibling half of the Bug2-10 over-fire guard)? A plain struct or a
    `.structComp` carrying at least one field qualifies; an embed-only host (`{#Meta}` — fields
    empty, content in `comprehensions`) does NOT (it is the deferral TARGET, not a narrowing
    source). Conservative: a `.refId`/selector that resolves to a struct is not counted (the
    structComp-defer path targets the embed-host shape, where the sibling is a literal narrowing
    struct), so the gate stays tight and never fires for a no-narrowing `.conj`. -/
def conjNarrowingSibling? : Value -> Bool
  | .struct fields _ _ _ _ => !fields.isEmpty
  | .structComp fields _ _ => !fields.isEmpty
  | .embeddedScalar _ decls => !decls.isEmpty
  | .embeddedList _ _ decls => !decls.isEmpty
  | _ => false

/-- Same-file alias companion to `importSelectorDef?`. A def referenced DIRECTLY (`#B`, a
    `.refId`) whose body is an alias/import-selector indirection (`#B: #A` where `#A: parts.#M`,
    OR `#B: parts.#M` directly) resolves THROUGH the chain to a struct that needs deferral, but
    over a DIFFERENT captured frame than `#B`'s own scope — the terminal package frame. The
    direct `refDefClosureBody?`/`conjDefClosure?` capture `#B`'s scope, which is wrong here.
    Follows the chain and returns `(terminalFrame, terminalBody)` so the consumer `pushFrame`s
    the right frame. `none` for a non-alias body (left to `refDefClosureBody?`). Mirrors
    `importSelectorDef?`'s `(pkgFields, defBody)` shape so the `.conj` fold and the `.refId` arm
    consume it identically. -/
def refAliasDefClosure? (env : Env) (id : BindingId) : Option (List Field × Value) :=
  match env.drop id.depth.val with
  | [] => none
  | frame :: outer =>
      match nthField id.index.val frame.snd with
      | none => none
      | some defField =>
          if defField.fieldClass.isDefinition then
            -- The body's refs resolve with `frame` at depth 0 over `outer` (the binding's scope).
            match followAliasDefBody? evalFuel (frame :: outer) frame.snd (Field.value defField) with
            | some (capturedFrame, body) =>
                some (capturedFrame, normalizeDefinitionValueWithFuel normalizeFuel body)
            | none => none
          else
            none

/-- Is this conjunct a raw `pkg.#Def` import-selector whose body defers to a closure? The `.conj`
    fold uses this to keep the RAW selector unevaluated (so the producer arm's eventual standalone
    force does not collapse it) and instead build the closure in-monad via `pushFrame`. -/
def importSelectorDef? (env : Env) : Value -> Option (List Field × Value)
  | .selector (.refId id) label => importDefClosureBody? env id label
  | _ => none

/-- Conjunct-level alias producer: a bare ref (`#B`) whose body chains through an alias/import
    selector to a deferring struct. Mirrors `importSelectorDef?` for the `.refId` conjunct form,
    returning the terminal `(frame, body)` to `pushFrame`. `none` for non-ref conjuncts. -/
def refAliasSelectorDef? (env : Env) : Value -> Option (List Field × Value)
  | .refId id => refAliasDefClosure? env id
  | _ => none

/-- The UNEVALUATED disjunction arms of a conjunct that is (or refs) a disjunction whose
    default arm needs deferral — so the `.conj` fold can DISTRIBUTE the other (narrowing)
    conjuncts into each arm BEFORE the arms collapse (`(*_#A|_#B) & {narrow}` →
    `*(_#A & {narrow}) | (_#B & {narrow})`). Without distribution, the disjunction evaluates
    standalone, forcing its def arms with NO use-operands, so a default arm's sibling self-ref
    (`copy: #x`, the argocd `#OpaqueSecret` shape) collapses to its abstract value before the
    narrowing reaches it.

    Returns `none` UNLESS the disjunction has a deferral-needing arm (`bodyNeedsDefer` on the
    arm's resolved def body) — a plain scalar/struct disjunction (`*1 | 2`, `*{a:1} | {a:2}`)
    keeps the existing distribute-at-meet path (no regression, no over-defer). The arms are the
    RAW (unevaluated) values, resolving in the SAME frame as the disjunction ref itself (a
    `.disj`-bodied def's arm refs are depth-relative to the def's scope = the conjunct's scope). -/
def conjDisjArms? (env : Env) (fuel : Nat) : Value -> Option (List (Mark × Value))
  | .disj alternatives =>
      if alternatives.any (fun a => bodyNeedsDefer ((0, []) :: env) fuel a.snd
          || (match a.snd with
              | .refId id =>
                  match (env.drop id.depth.val) with
                  | [] => false
                  | frame :: _ =>
                      match nthField id.index.val frame.snd with
                      | some f => bodyNeedsDefer ((0, []) :: env.drop id.depth.val) fuel (Field.value f)
                      | none => false
              | _ => false)) then
        some alternatives
      else
        none
  | .refId id =>
      match fuel with
      | 0 => none
      | fuel + 1 =>
          match env.drop id.depth.val with
          | [] => none
          | frame :: _ =>
              match nthField id.index.val frame.snd with
              | some field => conjDisjArms? env fuel (Field.value field)
              | none => none
  | _ => none

/-- Split a conjunction's constraints into (a distributable disjunction's unevaluated arms,
    the remaining constraints) IF exactly the first distributable disjunction conjunct is found —
    a depth-0 (or literal) disjunction with a deferral-needing arm (`conjDisjArms?`). Returns
    `none` when no constraint distributes (the standard fold applies). The remaining constraints
    are meet into EACH arm by the caller. -/
def splitDisjConjunct (env : Env) :
    List Value -> Option (List (Mark × Value) × List Value)
  | [] => none
  | c :: rest =>
      let distributes :=
        (match c with | .disj _ => true | .refId id => id.depth == 0 | _ => false)
      match (if distributes then conjDisjArms? env evalFuel c else none) with
      | some arms => some (arms, rest)
      | none =>
          match splitDisjConjunct env rest with
          | some (arms, others) => some (arms, c :: others)
          | none => none

end Kue
