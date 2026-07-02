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
        -- here would silently close the def, bottoming `#D & {extra}` — while `#D: {e}`
        -- (`regularOpen`) closes (`defClosed`) and rejects an added field, exactly as CUE. The
        -- parser's open-by-default is irrelevant once this is a def body, so `closeDefBody` drops
        -- it. Non-disjunction embeddings (`comprehensions`) are left untouched: an embedding UNIONS
        -- its labels into the def's allowed set (CUE), it is not the def's own closed declaration —
        -- force-closing it would make the embed reject the def's own siblings.
        --
        -- def-closedness-thru-embedded-disj: an embedded STRUCTURAL DISJUNCTION (`#M: {{a:int} |
        -- {kind:string}}`) is the exception. Its arms are struct LITERALS written inside the def
        -- body, so closedness DISTRIBUTES into them exactly as it does for a non-embedded disj body
        -- (`#M: {a:int} | {kind:string}`, which the `.disj` arm below closes). Without this, the
        -- arms stay parser-default `regularOpen`, so `#M & {kind:"k"}` admits the `kind` field on
        -- the `{a:int}` arm too → both arms survive → a SOUNDNESS over-accept (kue admits what
        -- cue/spec close-and-reject). Recursing the CLOSING normalizer into a disj embedding closes
        -- each struct-literal arm; a non-struct-literal arm (a `.refId` to another def) is a no-op
        -- pass-through, so referenced-def arms keep their own closedness — no over-close.
        let normalizedComprehensions := comprehensions.map fun c =>
          match c with
          | .disj _ => normalizeDefinitionValueWithFuel fuel c
          | _ => c
        .structComp (fields.map (normalizeDefinitionFieldWithFuel fuel)) normalizedComprehensions openness.closeDefBody
    -- A `defOpenViaTail` struct (the legacy `structTail` def body) keeps the def OPEN via its
    -- explicit `...`, so it is returned UNCHANGED. A no-pattern struct CLOSES (openness →
    -- `defClosed`). A pattern-bearing struct normalizes fields + patterns and keeps its openness.
    | _ + 1, .struct fields .defOpenViaTail tail patterns closedClauses =>
        .struct fields .defOpenViaTail tail patterns closedClauses
    | fuel + 1, .struct fields _ _ [] _ =>
        -- Through `mkStruct` so the closed no-pattern body gets its single self-clause
        -- (`{fieldLabels := fields.map .label, patterns := []}`); a raw `.struct … []` would
        -- leave it clause-less, which the closing check reads as OPEN.
        mkStruct (fields.map (normalizeDefinitionFieldWithFuel fuel)) .defClosed none []
    -- A closed def declaring its OWN patterns: a no-`...` pattern-bearing body CLOSES exactly
    -- like the no-pattern arm above (`closeDefBody` turns the parser's open-by-default
    -- `regularOpen` into `defClosed`; the `defOpenViaTail` case is already returned unchanged
    -- earlier). Once closed, the patterns close (widen the allowed set), so `mkStruct`'s default
    -- single self-clause is exactly right; leaving `openness` open here would default
    -- `closedClauses` to `[]` and silently re-open the def (SC-1c).
    | fuel + 1, .struct fields openness _ patterns _ =>
        let normalizedPatterns := patterns.map fun pattern =>
          (
            normalizeDefinitionValueWithFuel fuel pattern.fst,
            normalizeDefinitionValueWithFuel fuel pattern.snd
          )
        mkStruct (fields.map (normalizeDefinitionFieldWithFuel fuel)) openness.closeDefBody none normalizedPatterns
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
    | fuel + 1, .embeddedScalar scalar decls =>
        .embeddedScalar
          (normalizeDefinitionValueWithFuel fuel scalar)
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
    | fuel + 1, .letClause name value =>
        .letClause name (normalizeDefinitionValueWithFuel fuel value)

  /-- Field handler — a principled 4-way split on `FieldClass` (A2-followup, subsuming B6-A2):
      - DEFINITION (`#x`): body closed recursively (its own closedness declaration).
      - `importBinding`: a bound imported package (`Module.bindImports`) left UNTOUCHED so it
        stays cue-lazy. Recursing it re-closes unreferenced nested defs and re-bottoms
        cert-manager/argocd (the A2 trap). The marker scopes this skip PRECISELY to bound
        packages — a real in-file `_x` does not escape through it (B6-A1).
      - real in-file hidden (`_x`) OR `let` binding: value recurses the SPINE walker
        `normalizeDefinitionsWithFuel`, closing nested `#Def`s while preserving the field's own
        openness — same treatment regular fields get (cue closes `_pkg.#Svc & {extra}` and
        `let x={#I:…}; x.#I & {extra}`, oracle-confirmed v0.16.1).
      - regular/optional/required: same spine recurse, preserving openness. -/
  def normalizeFieldWithFuel : Nat -> Field -> Field
    | 0, field => field
    | fuel + 1, field =>
        match Field.fieldClass field with
        | .field true _ _ =>
            ⟨Field.label field, Field.fieldClass field, normalizeDefinitionValueWithFuel fuel (Field.value field)⟩
        | .importBinding =>
            field
        | .field false true _ =>
            ⟨Field.label field, Field.fieldClass field, normalizeDefinitionsWithFuel fuel (Field.value field)⟩
        | .letBinding =>
            ⟨Field.label field, Field.fieldClass field, normalizeDefinitionsWithFuel fuel (Field.value field)⟩
        | .field false false _ =>
            ⟨Field.label field, Field.fieldClass field, normalizeDefinitionsWithFuel fuel (Field.value field)⟩

  /-- CLOSING field-walker twin (SC-2 + SC-4). Identical to `normalizeFieldWithFuel` EXCEPT the
      regular/optional/required arm, the in-file HIDDEN (`_x`) arm, AND the `letBinding` arm all
      recurse the CLOSING walker `normalizeDefinitionValueWithFuel` (not the spine
      `normalizeDefinitionsWithFuel`), so a def's nested PLAIN-struct field values close recursively
      regardless of how the value is carried: `#A: {a: {b: int}}` closes `a`'s value
      (oracle #1/#2/#3/#6), `#A: {_h: {x: int}}` closes `_h`'s value, and `#A: {let _t={x:int}, v:_t}`
      closes `_t`'s value (read into `v`) — so an added `extra` is rejected at any depth (SC-4).
      Closedness is a property of the definition and is monotone; neither the visibility of the
      carrying field nor the let-vs-regular carrier changes whether the nested value is closed. The
      one remaining UNCHANGED arm is the trap defence:
      - `importBinding` → SKIP: a bound package is never recursed, so cert-manager/argocd cannot
        re-bottom (the A2 trap; the marker scopes the skip precisely to bound packages).
      A separate function (not a `closing : Bool` flag) keeps the call site's intent encoded in
      WHICH function it calls — illegal-states philosophy. A plain (non-def) struct never reaches
      this twin (it goes through the spine / no normalization-close), so control #5 stays open. -/
  def normalizeDefinitionFieldWithFuel : Nat -> Field -> Field
    | 0, field => field
    | fuel + 1, field =>
        match Field.fieldClass field with
        | .field true _ _ =>
            ⟨Field.label field, Field.fieldClass field, normalizeDefinitionValueWithFuel fuel (Field.value field)⟩
        | .importBinding =>
            field
        | .field false true _ =>
            ⟨Field.label field, Field.fieldClass field, normalizeDefinitionValueWithFuel fuel (Field.value field)⟩
        | .letBinding =>
            ⟨Field.label field, Field.fieldClass field, normalizeDefinitionValueWithFuel fuel (Field.value field)⟩
        | .field false false _ =>
            ⟨Field.label field, Field.fieldClass field, normalizeDefinitionValueWithFuel fuel (Field.value field)⟩

  def normalizeDefinitionsWithFuel : Nat -> Value -> Value
    | 0, value => value
    -- Normalize fields/patterns, keep openness. A `defOpenViaTail` struct (the legacy
    -- `structTail`) is returned unchanged.
    | _ + 1, .struct fields .defOpenViaTail tail patterns closedClauses =>
        .struct fields .defOpenViaTail tail patterns closedClauses
    | fuel + 1, .struct fields openness tail patterns closedClauses =>
        .struct
          (fields.map (normalizeFieldWithFuel fuel))
          openness
          tail
          (patterns.map fun pattern =>
            (
              normalizeDefinitionsWithFuel fuel pattern.fst,
              normalizeDefinitionsWithFuel fuel pattern.snd
            ))
          (closedClauses.map (ClosedClause.mapPatterns (normalizeDefinitionsWithFuel fuel)))
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
    | fuel + 1, .embeddedScalar scalar decls =>
        .embeddedScalar
          (normalizeDefinitionsWithFuel fuel scalar)
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
    | fuel + 1, .letClause name value =>
        .letClause name (normalizeDefinitionsWithFuel fuel value)
end

def normalizeDefinitions (value : Value) : Value :=
  normalizeDefinitionsWithFuel normalizeFuel value

end Kue
