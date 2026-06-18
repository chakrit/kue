import Kue.Value

namespace Kue

def normalizeFuel : Nat :=
  100

mutual
  def normalizeDefinitionValueWithFuel : Nat -> Value -> Value
    | 0, value => value
    | fuel + 1, .structComp fields comprehensions openness =>
        -- Normalize nested DEFINITION fields (matching the `.struct` arm) and derive the def
        -- body's openness via `StructOpenness.closeDefBody`: a definition is closed by default,
        -- an explicit `...` (`defOpenViaTail`) opens it. So `#D: {e, ...}` stays OPEN — closing it
        -- here (the old bug) silently closed the def, bottoming `#D & {extra}` — while `#D: {e}`
        -- (`regularOpen`) closes (`defClosed`) and rejects an added field, exactly as CUE. The
        -- parser's open-by-default is irrelevant once this is a def body, so `closeDefBody` drops
        -- it. Embeddings (`comprehensions`) are left untouched: an embedding UNIONS its labels into
        -- the def's allowed set (CUE), it is not the def's own closed declaration — force-closing
        -- it would make the embed reject the def's own siblings.
        .structComp (fields.map (normalizeFieldWithFuel fuel)) comprehensions openness.closeDefBody
    -- A `defOpenViaTail` struct (the legacy `structTail` def body) keeps the def OPEN via its
    -- explicit `...`, so it is returned UNCHANGED. A no-pattern struct CLOSES (openness →
    -- `defClosed`). A pattern-bearing struct normalizes fields + patterns and keeps its openness.
    | _ + 1, .struct fields .defOpenViaTail tail patterns =>
        .struct fields .defOpenViaTail tail patterns
    | fuel + 1, .struct fields _ _ [] =>
        .struct (fields.map (normalizeFieldWithFuel fuel)) .defClosed none []
    | fuel + 1, .struct fields openness _ patterns =>
        .struct
          (fields.map (normalizeFieldWithFuel fuel))
          openness
          none
          (patterns.map fun pattern =>
            (
              normalizeDefinitionValueWithFuel fuel pattern.fst,
              normalizeDefinitionValueWithFuel fuel pattern.snd
            ))
    | fuel + 1, .disj alternatives =>
        .disj (alternatives.map fun alternative =>
          (alternative.fst, normalizeDefinitionValueWithFuel fuel alternative.snd)
        )
    | fuel + 1, .builtinCall name args =>
        .builtinCall name (args.map (normalizeDefinitionValueWithFuel fuel))
    | fuel + 1, .unary op value =>
        .unary op (normalizeDefinitionValueWithFuel fuel value)
    | fuel + 1, .binary op left right =>
        .binary op
          (normalizeDefinitionValueWithFuel fuel left)
          (normalizeDefinitionValueWithFuel fuel right)
    | fuel + 1, .selector base label =>
        .selector (normalizeDefinitionValueWithFuel fuel base) label
    | fuel + 1, .index base key =>
        .index
          (normalizeDefinitionValueWithFuel fuel base)
          (normalizeDefinitionValueWithFuel fuel key)
    | fuel + 1, .list items =>
        -- A struct literal nested in a definition body is itself closed (CUE: closedness
        -- propagates into nested struct literals within a definition), so descend list
        -- elements with the closing normalizer.
        .list (items.map (normalizeDefinitionValueWithFuel fuel))
    | fuel + 1, .listTail items tail =>
        .listTail
          (items.map (normalizeDefinitionValueWithFuel fuel))
          (normalizeDefinitionValueWithFuel fuel tail)
    | fuel + 1, .embeddedList items tail decls =>
        .embeddedList
          (items.map (normalizeDefinitionValueWithFuel fuel))
          (tail.map (normalizeDefinitionValueWithFuel fuel))
          (decls.map (normalizeFieldWithFuel fuel))
    | fuel + 1, .comprehension clauses body =>
        .comprehension
          (clauses.map (normalizeClauseWithFuel fuel))
          (normalizeDefinitionValueWithFuel fuel body)
    | fuel + 1, .listComprehension clauses body =>
        .listComprehension
          (clauses.map (normalizeClauseWithFuel fuel))
          (normalizeDefinitionValueWithFuel fuel body)
    | fuel + 1, .interpolation parts =>
        .interpolation (parts.map (normalizeDefinitionValueWithFuel fuel))
    | fuel + 1, .dynamicField label fieldClass value =>
        .dynamicField
          (normalizeDefinitionValueWithFuel fuel label)
          fieldClass
          (normalizeDefinitionValueWithFuel fuel value)
    | _, value => value

  def normalizeClauseWithFuel : Nat -> Clause Value -> Clause Value
    | 0, clause => clause
    | fuel + 1, .forIn key value source =>
        .forIn key value (normalizeDefinitionValueWithFuel fuel source)
    | fuel + 1, .guard condition =>
        .guard (normalizeDefinitionValueWithFuel fuel condition)

  /-- Field handler. A DEFINITION field's body is closed (recursively) — its own closedness
      declaration. A regular/optional/required field's value recurses with the SPINE walker, which
      PRESERVES the field's own openness (an instantiated regular struct stays open — cue keeps
      `(#D & {}).r` open) while still closing any nested `#Def` reached inside it (gap-1: a `#Def`
      under a regular field, `a.#Inner`, is now closed). A `let` binding (B6-A2) takes that SAME
      spine arm: `letBinding` is its OWN `FieldClass` kind, NOT entangled with the import-binding
      trap below, so a `let`-bound value can safely recurse the spine — closing its nested `#Def`s
      (cue closes `let x = {#I:…}; x.#I & {extra}`) while a `let` over a regular/open struct stays
      open. Hidden fields are import-package bindings (`Module.lean`) left UNTOUCHED so a bound
      package stays cue-lazy — recursing them re-closes unreferenced nested defs and re-bottoms
      cert-manager/argocd (the A2 trap; this is what decouples B6 from A2-followup). This `let` arm
      is the `letBinding` arm of the future A2-followup 4-way `FieldClass` split. -/
  def normalizeFieldWithFuel : Nat -> Field -> Field
    | 0, field => field
    | fuel + 1, field =>
        if FieldClass.isDefinition (Field.fieldClass field) then
          ⟨Field.label field, Field.fieldClass field, normalizeDefinitionValueWithFuel fuel (Field.value field)⟩
        else if FieldClass.isHidden (Field.fieldClass field) then
          field
        else
          ⟨Field.label field, Field.fieldClass field, normalizeDefinitionsWithFuel fuel (Field.value field)⟩

  def normalizeDefinitionsWithFuel : Nat -> Value -> Value
    | 0, value => value
    -- Normalize fields/patterns, keep openness. A `defOpenViaTail` struct (the legacy
    -- `structTail`) is returned unchanged.
    | _ + 1, .struct fields .defOpenViaTail tail patterns =>
        .struct fields .defOpenViaTail tail patterns
    | fuel + 1, .struct fields openness tail patterns =>
        .struct
          (fields.map (normalizeFieldWithFuel fuel))
          openness
          tail
          (patterns.map fun pattern =>
            (
              normalizeDefinitionsWithFuel fuel pattern.fst,
              normalizeDefinitionsWithFuel fuel pattern.snd
            ))
    | fuel + 1, .disj alternatives =>
        .disj (alternatives.map fun alternative =>
          (alternative.fst, normalizeDefinitionsWithFuel fuel alternative.snd)
        )
    | fuel + 1, .builtinCall name args =>
        .builtinCall name (args.map (normalizeDefinitionsWithFuel fuel))
    | fuel + 1, .unary op value =>
        .unary op (normalizeDefinitionsWithFuel fuel value)
    | fuel + 1, .binary op left right =>
        .binary op
          (normalizeDefinitionsWithFuel fuel left)
          (normalizeDefinitionsWithFuel fuel right)
    | fuel + 1, .selector base label =>
        .selector (normalizeDefinitionsWithFuel fuel base) label
    | fuel + 1, .index base key =>
        .index
          (normalizeDefinitionsWithFuel fuel base)
          (normalizeDefinitionsWithFuel fuel key)
    | fuel + 1, .structComp fields comprehensions openness =>
        -- The dominant `{embed;…;...}` shape: a nested `#Def` here (e.g. `a: {b, if c {}, #I:…}`)
        -- must have its body normalized/closed exactly as in a plain `.struct`.
        .structComp
          (fields.map (normalizeFieldWithFuel fuel))
          (comprehensions.map (normalizeDefinitionsWithFuel fuel))
          openness
    | fuel + 1, .list items =>
        .list (items.map (normalizeDefinitionsWithFuel fuel))
    | fuel + 1, .listTail items tail =>
        .listTail
          (items.map (normalizeDefinitionsWithFuel fuel))
          (normalizeDefinitionsWithFuel fuel tail)
    | fuel + 1, .embeddedList items tail decls =>
        .embeddedList
          (items.map (normalizeDefinitionsWithFuel fuel))
          (tail.map (normalizeDefinitionsWithFuel fuel))
          (decls.map (normalizeFieldWithFuel fuel))
    | fuel + 1, .comprehension clauses body =>
        .comprehension
          (clauses.map (normalizeDefinitionsClauseWithFuel fuel))
          (normalizeDefinitionsWithFuel fuel body)
    | fuel + 1, .listComprehension clauses body =>
        .listComprehension
          (clauses.map (normalizeDefinitionsClauseWithFuel fuel))
          (normalizeDefinitionsWithFuel fuel body)
    | fuel + 1, .interpolation parts =>
        .interpolation (parts.map (normalizeDefinitionsWithFuel fuel))
    | fuel + 1, .dynamicField label fieldClass value =>
        .dynamicField
          (normalizeDefinitionsWithFuel fuel label)
          fieldClass
          (normalizeDefinitionsWithFuel fuel value)
    | _, value => value

  def normalizeDefinitionsClauseWithFuel : Nat -> Clause Value -> Clause Value
    | 0, clause => clause
    | fuel + 1, .forIn key value source =>
        .forIn key value (normalizeDefinitionsWithFuel fuel source)
    | fuel + 1, .guard condition =>
        .guard (normalizeDefinitionsWithFuel fuel condition)
end

def normalizeDefinitions (value : Value) : Value :=
  normalizeDefinitionsWithFuel normalizeFuel value

end Kue
