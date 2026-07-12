import Kue.Value
import Kue.Lattice

namespace Kue

/--
A lexical scope frame: each label in a struct mapped to its positional index.
Resolution carries a stack of frames (innermost first); a reference resolves to
a `BindingId` whose `depth` counts frames outward and whose `index` is the slot
within that frame. This represents lexical scope explicitly instead of relying on
dynamic name lookup at evaluation time.
-/
def buildFrameFrom (index : Nat) : List Field -> List (String × Nat)
  | [] => []
  | field :: fields => (Field.label field, index) :: buildFrameFrom (index + 1) fields

/--
The deduplicated slot layout the evaluator indexes, sharing `canonicalizeFields`' exact
collapse decision via `mergeFieldLayoutInto` (Lattice): a field collapses into the FIRST
kept slot of the same label whose field-class merges; a same-label slot whose class does
NOT merge (a `let`/`import` binding against a regular field) is kept separate. Resolution
assigns lexical indices against THIS layout — not the raw positional one — so a reference
to a field sitting after a collapsed duplicate lands on its evaluator slot rather than a
stale higher index that dangles into `unresolvedBinding`. The layout keeps only the first
slot (`fun _ current _ => current`); the value-merge is the evaluator's concern.
-/
def canonicalFieldLayout (fields : List Field) : List Field :=
  fields.foldl
    (fun kept field =>
      match mergeFieldLayoutInto (fun _ current _ => current) kept field with
      | some fields => fields
      | none => kept ++ [field])
    []

def buildFrame (fields : List Field) : List (String × Nat) :=
  buildFrameFrom 0 (canonicalFieldLayout fields)

def findInFrame (label : String) : List (String × Nat) -> Option Nat
  | [] => none
  | entry :: rest =>
      if entry.fst = label then
        some entry.snd
      else
        findInFrame label rest

def findInScopes (label : String) (depth : Nat) : List (List (String × Nat)) -> Option BindingId
  | [] => none
  | frame :: outer =>
      match findInFrame label frame with
      | some index => some ⟨⟨depth⟩, ⟨index⟩⟩
      | none => findInScopes label (depth + 1) outer

def resolveFuel : Nat :=
  100

/--
The lexical frame a `for` clause introduces for its loop variables. A keyed
`for k, v in …` binds `k` at index 0 and `v` at index 1; an unkeyed `for v in …`
binds `v` at index 0. Resolution and evaluation must agree on this ordering, since
`refId` uses positional indices.
-/
def clauseLoopFrame (key : Option String) (value : String) : List (String × Nat) :=
  match key with
  | some key => [(key, 0), (value, 1)]
  | none => [(value, 0)]

/- The single frame-pushing reference traversal, parameterized over a leaf `onRef` handler
   (`scopes → label → Value`). Both reference passes ride this ONE walker so their scoping can
   never drift: `resolveValueWithFuel` supplies a handler that emits a positional `.refId`, and
   the file-scoped-import rewrite (`rewriteFileImportRefs`) supplies one that relabels an
   unshadowed import ref. Only the leaf differs; every binder push (struct/`structComp` field
   frame, `for`/`let` clause frame) is shared. -/
mutual
  def mapRefsFieldWithFuel
      (onRef : List (List (String × Nat)) -> String -> Value)
      (fuel : Nat) (scopes : List (List (String × Nat))) (field : Field) : Field :=
    { field with value := mapRefsValueWithFuel onRef fuel scopes field.value }

  def mapRefsClausesWithFuel
      (onRef : List (List (String × Nat)) -> String -> Value)
      (fuel : Nat)
      (scopes : List (List (String × Nat)))
      (clauses : List (Clause Value))
      (body : Value) : List (Clause Value) × Value :=
    match clauses with
    | [] => ([], mapRefsValueWithFuel onRef fuel scopes body)
    | .forIn key value source :: rest =>
        let resolvedSource := mapRefsValueWithFuel onRef fuel scopes source
        let nested := clauseLoopFrame key value :: scopes
        let (restClauses, resolvedBody) := mapRefsClausesWithFuel onRef fuel nested rest body
        (.forIn key value resolvedSource :: restClauses, resolvedBody)
    | .guard condition :: rest =>
        let resolvedCondition := mapRefsValueWithFuel onRef fuel scopes condition
        let (restClauses, resolvedBody) := mapRefsClausesWithFuel onRef fuel scopes rest body
        (.guard resolvedCondition :: restClauses, resolvedBody)
    | .letClause name value :: rest =>
        -- The bound value resolves in the scope BEFORE the let's own frame is pushed (it sees
        -- earlier `for`/`let` bindings + the enclosing scope, never itself), exactly like a
        -- `for` source. The let then pushes ONE frame binding `name` at slot 0
        -- (`clauseLoopFrame none name` = `[(name, 0)]`), so later clauses + the body resolve a
        -- `.refId ⟨0, 0⟩` to it. Spec: a `let` clause defines a new scope (+1 frame).
        let resolvedValue := mapRefsValueWithFuel onRef fuel scopes value
        let nested := clauseLoopFrame none name :: scopes
        let (restClauses, resolvedBody) := mapRefsClausesWithFuel onRef fuel nested rest body
        (.letClause name resolvedValue :: restClauses, resolvedBody)

  def mapRefsValueWithFuel
      (onRef : List (List (String × Nat)) -> String -> Value) :
      Nat -> List (List (String × Nat)) -> Value -> Value
    | 0, _, value => value
    | _ + 1, scopes, .ref label => onRef scopes label
    | fuel + 1, scopes, .conj constraints =>
        .conj (constraints.map (mapRefsValueWithFuel onRef fuel scopes))
    | fuel + 1, scopes, .builtinCall name args =>
        .builtinCall name (args.map (mapRefsValueWithFuel onRef fuel scopes))
    | fuel + 1, scopes, .unary op value =>
        .unary op (mapRefsValueWithFuel onRef fuel scopes value)
    | fuel + 1, scopes, .binary op left right =>
        .binary op
          (mapRefsValueWithFuel onRef fuel scopes left)
          (mapRefsValueWithFuel onRef fuel scopes right)
    | fuel + 1, scopes, .selector base label =>
        .selector (mapRefsValueWithFuel onRef fuel scopes base) label
    | fuel + 1, scopes, .index base key =>
        .index
          (mapRefsValueWithFuel onRef fuel scopes base)
          (mapRefsValueWithFuel onRef fuel scopes key)
    | fuel + 1, scopes, .disj alternatives =>
        .disj (alternatives.map fun alternative =>
          (alternative.fst, mapRefsValueWithFuel onRef fuel scopes alternative.snd)
        )
    | fuel + 1, scopes, .struct fields openness tail patterns closedClauses =>
        -- 1:1 ref-resolution preserving the coherent struct shape (rebuild directly; the
        -- openness/tail-presence/pattern-count are invariant under resolution).
        let nested := buildFrame fields :: scopes
        .struct
          (fields.map (mapRefsFieldWithFuel onRef fuel nested))
          openness
          (tail.map (mapRefsValueWithFuel onRef fuel nested))
          (patterns.map fun pattern =>
            (
              mapRefsValueWithFuel onRef fuel nested pattern.fst,
              mapRefsValueWithFuel onRef fuel nested pattern.snd
            ))
          (closedClauses.map (ClosedClause.mapPatterns (mapRefsValueWithFuel onRef fuel nested)))
    | fuel + 1, scopes, .list items =>
        .list (items.map (mapRefsValueWithFuel onRef fuel scopes))
    | fuel + 1, scopes, .listTail items tail =>
        .listTail
          (items.map (mapRefsValueWithFuel onRef fuel scopes))
          (mapRefsValueWithFuel onRef fuel scopes tail)
    | fuel + 1, scopes, .comprehension clauses body =>
        let (resolvedClauses, resolvedBody) := mapRefsClausesWithFuel onRef fuel scopes clauses body
        .comprehension resolvedClauses resolvedBody
    | fuel + 1, scopes, .listComprehension clauses body =>
        let (resolvedClauses, resolvedBody) := mapRefsClausesWithFuel onRef fuel scopes clauses body
        .listComprehension resolvedClauses resolvedBody
    | fuel + 1, scopes, .structComp fields comprehensions openness =>
        let nested := buildFrame fields :: scopes
        .structComp
          (fields.map (mapRefsFieldWithFuel onRef fuel nested))
          (comprehensions.map (mapRefsValueWithFuel onRef fuel nested))
          openness
    | fuel + 1, scopes, .interpolation parts =>
        .interpolation (parts.map (mapRefsValueWithFuel onRef fuel scopes))
    | fuel + 1, scopes, .dynamicField label fieldClass value =>
        .dynamicField
          (mapRefsValueWithFuel onRef fuel scopes label)
          fieldClass
          (mapRefsValueWithFuel onRef fuel scopes value)
    -- Leaves and eval-only forms: no rewritable `.ref` is reachable through any of these at
    -- this pre-eval traversal's call sites, so each passes through unchanged. `embeddedList`/
    -- `embeddedScalar` are produced only by eval (never present here); `closure` owns its own
    -- `capturedEnv` and must NOT be recursed into. Enumerated with no catch-all so a new
    -- `Value` constructor forces a decision at this rewrite site (CLAUDE.md bright-line).
    | _ + 1, _, value@(.top) => value
    | _ + 1, _, value@(.bottom) => value
    | _ + 1, _, value@(.bottomWith _) => value
    | _ + 1, _, value@(.prim _) => value
    | _ + 1, _, value@(.kind _) => value
    | _ + 1, _, value@(.notPrim _) => value
    | _ + 1, _, value@(.stringRegex _) => value
    | _ + 1, _, value@(.stringFormat _) => value
    | _ + 1, _, value@(.boundConstraint _ _) => value
    | _ + 1, _, value@(.lengthConstraint _ _ _) => value
    | _ + 1, _, value@(.uniqueItems) => value
    | _ + 1, _, value@(.refId _) => value
    | _ + 1, _, value@(.patternLabel _) => value
    | _ + 1, _, value@(.thisStruct) => value
    | _ + 1, _, value@(.embeddedList _ _ _) => value
    | _ + 1, _, value@(.embeddedScalar _ _) => value
    | _ + 1, _, value@(.closure _ _) => value
end

/-- The reference-resolution leaf: a bare `.ref` becomes a positional `.refId` when its label
    is in scope, else stays an unresolved `.ref`. -/
def resolveRefLeaf (scopes : List (List (String × Nat))) (label : String) : Value :=
  match findInScopes label 0 scopes with
  | some id => .refId id
  | none => .ref label

def resolveValueWithFuel (fuel : Nat) (scopes : List (List (String × Nat))) (value : Value) : Value :=
  mapRefsValueWithFuel resolveRefLeaf fuel scopes value

def resolveFieldRefsWithFuel (fuel : Nat) (scopes : List (List (String × Nat))) (field : Field) : Field :=
  mapRefsFieldWithFuel resolveRefLeaf fuel scopes field

def resolveClausesWithFuel (fuel : Nat) (scopes : List (List (String × Nat)))
    (clauses : List (Clause Value)) (body : Value) : List (Clause Value) × Value :=
  mapRefsClausesWithFuel resolveRefLeaf fuel scopes clauses body

/-- The file-scoped-import rewrite leaf: relabel a bare `.ref name` to `relabel name` ONLY when
    `name` is one of this file's imports (`importNames`) AND is NOT shadowed by an enclosing
    binder — a name bound in any outer frame (a struct field, a `let`, a `for` variable, or a
    value/field alias, all of which the shared walker pushes into `scopes`). Every other ref
    passes through untouched, so sibling package fields and stdlib references are undisturbed.
    Shadow detection reuses `findInScopes`, so it cannot drift from reference resolution. -/
def rewriteImportRefLeaf (importNames : List String) (relabel : String -> String)
    (scopes : List (List (String × Nat))) (label : String) : Value :=
  if (findInScopes label 0 scopes).isSome then
    .ref label
  else if importNames.contains label then
    .ref (relabel label)
  else
    .ref label

/-- Rewrite one parsed file's import references to file-scoped labels BEFORE the sibling
    meet-merge, so an import bound in one file cannot leak into a sibling. Rides the shared
    `mapRefsValueWithFuel` traversal (identical frame-pushing to the resolver), so an enclosing
    binder that shadows an import name is honoured exactly as reference resolution would. Starts
    with empty `scopes`: the file body's own outermost struct pushes its field frame. -/
def rewriteFileImportRefs (importNames : List String) (relabel : String -> String)
    (value : Value) : Value :=
  mapRefsValueWithFuel (rewriteImportRefLeaf importNames relabel) resolveFuel [] value

def resolveStructRefs : Value -> Value
  | .struct fields openness tail patterns closedClauses =>
      let scopes := [buildFrame fields]
      .struct
        (fields.map (resolveFieldRefsWithFuel resolveFuel scopes))
        openness
        (tail.map (resolveValueWithFuel resolveFuel scopes))
        (patterns.map fun pattern =>
          (
            resolveValueWithFuel resolveFuel scopes pattern.fst,
            resolveValueWithFuel resolveFuel scopes pattern.snd
          ))
        (closedClauses.map (ClosedClause.mapPatterns (resolveValueWithFuel resolveFuel scopes)))
  | .structComp fields comprehensions openness =>
      let scopes := [buildFrame fields]
      .structComp
        (fields.map (resolveFieldRefsWithFuel resolveFuel scopes))
        (comprehensions.map (resolveValueWithFuel resolveFuel scopes))
        openness
  | value => value

end Kue
