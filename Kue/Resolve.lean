import Kue.Value

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

def buildFrame (fields : List Field) : List (String × Nat) :=
  buildFrameFrom 0 fields

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
      | some index => some ⟨depth, index⟩
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

mutual
  def resolveFieldRefsWithFuel (fuel : Nat) (scopes : List (List (String × Nat))) (field : Field) : Field :=
    ⟨Field.label field, Field.fieldClass field, resolveValueWithFuel fuel scopes (Field.value field)⟩

  def resolveClausesWithFuel
      (fuel : Nat)
      (scopes : List (List (String × Nat)))
      (clauses : List (Clause Value))
      (body : Value) : List (Clause Value) × Value :=
    match clauses with
    | [] => ([], resolveValueWithFuel fuel scopes body)
    | .forIn key value source :: rest =>
        let resolvedSource := resolveValueWithFuel fuel scopes source
        let nested := clauseLoopFrame key value :: scopes
        let (restClauses, resolvedBody) := resolveClausesWithFuel fuel nested rest body
        (.forIn key value resolvedSource :: restClauses, resolvedBody)
    | .guard condition :: rest =>
        let resolvedCondition := resolveValueWithFuel fuel scopes condition
        let (restClauses, resolvedBody) := resolveClausesWithFuel fuel scopes rest body
        (.guard resolvedCondition :: restClauses, resolvedBody)

  def resolveValueWithFuel : Nat -> List (List (String × Nat)) -> Value -> Value
    | 0, _, value => value
    | _ + 1, scopes, .ref label =>
        match findInScopes label 0 scopes with
        | some id => .refId id
        | none => .ref label
    | fuel + 1, scopes, .conj constraints =>
        .conj (constraints.map (resolveValueWithFuel fuel scopes))
    | fuel + 1, scopes, .builtinCall name args =>
        .builtinCall name (args.map (resolveValueWithFuel fuel scopes))
    | fuel + 1, scopes, .unary op value =>
        .unary op (resolveValueWithFuel fuel scopes value)
    | fuel + 1, scopes, .binary op left right =>
        .binary op
          (resolveValueWithFuel fuel scopes left)
          (resolveValueWithFuel fuel scopes right)
    | fuel + 1, scopes, .selector base label =>
        .selector (resolveValueWithFuel fuel scopes base) label
    | fuel + 1, scopes, .index base key =>
        .index
          (resolveValueWithFuel fuel scopes base)
          (resolveValueWithFuel fuel scopes key)
    | fuel + 1, scopes, .disj alternatives =>
        .disj (alternatives.map fun alternative =>
          (alternative.fst, resolveValueWithFuel fuel scopes alternative.snd)
        )
    | fuel + 1, scopes, .struct fields openness tail patterns closingPatterns =>
        -- 1:1 ref-resolution preserving the coherent struct shape (rebuild directly; the
        -- openness/tail-presence/pattern-count are invariant under resolution).
        let nested := buildFrame fields :: scopes
        .struct
          (fields.map (resolveFieldRefsWithFuel fuel nested))
          openness
          (tail.map (resolveValueWithFuel fuel nested))
          (patterns.map fun pattern =>
            (
              resolveValueWithFuel fuel nested pattern.fst,
              resolveValueWithFuel fuel nested pattern.snd
            ))
          (closingPatterns.map (resolveValueWithFuel fuel nested))
    | fuel + 1, scopes, .list items =>
        .list (items.map (resolveValueWithFuel fuel scopes))
    | fuel + 1, scopes, .listTail items tail =>
        .listTail
          (items.map (resolveValueWithFuel fuel scopes))
          (resolveValueWithFuel fuel scopes tail)
    | fuel + 1, scopes, .comprehension clauses body =>
        let (resolvedClauses, resolvedBody) := resolveClausesWithFuel fuel scopes clauses body
        .comprehension resolvedClauses resolvedBody
    | fuel + 1, scopes, .listComprehension clauses body =>
        let (resolvedClauses, resolvedBody) := resolveClausesWithFuel fuel scopes clauses body
        .listComprehension resolvedClauses resolvedBody
    | fuel + 1, scopes, .structComp fields comprehensions openness =>
        let nested := buildFrame fields :: scopes
        .structComp
          (fields.map (resolveFieldRefsWithFuel fuel nested))
          (comprehensions.map (resolveValueWithFuel fuel nested))
          openness
    | fuel + 1, scopes, .interpolation parts =>
        .interpolation (parts.map (resolveValueWithFuel fuel scopes))
    | fuel + 1, scopes, .dynamicField label fieldClass value =>
        .dynamicField
          (resolveValueWithFuel fuel scopes label)
          fieldClass
          (resolveValueWithFuel fuel scopes value)
    | _, _, value => value
end

def resolveStructRefs : Value -> Value
  | .struct fields openness tail patterns closingPatterns =>
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
        (closingPatterns.map (resolveValueWithFuel resolveFuel scopes))
  | .structComp fields comprehensions openness =>
      let scopes := [buildFrame fields]
      .structComp
        (fields.map (resolveFieldRefsWithFuel resolveFuel scopes))
        (comprehensions.map (resolveValueWithFuel resolveFuel scopes))
        openness
  | value => value

end Kue
