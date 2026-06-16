import Kue.Builtin
import Kue.Decimal
import Kue.Lattice
import Kue.Normalize

namespace Kue

/--
Evaluation mirrors resolution's lexical scope chain: the environment is a stack of
frames (innermost first), each frame the syntactic field list of an enclosing struct.
A `refId ⟨depth, index⟩` selects the field at `index` in the frame `depth` steps out.
Cycle detection tracks visited slot indices within the current frame; following an
outer reference (`depth > 0`) re-bases onto the outer stack, where lexical cycles back
into a deeper frame cannot form, so the visited set resets.
-/
def findEvalField (label : String) : List Field -> Option Field
  | [] => none
  | field :: fields =>
      if Field.label field = label then
        some field
      else
        findEvalField label fields

def indexedFieldsFrom (index : Nat) : List Field -> List (Nat × Field)
  | [] => []
  | field :: fields => (index, field) :: indexedFieldsFrom (index + 1) fields

def indexedFields (fields : List Field) : List (Nat × Field) :=
  indexedFieldsFrom 0 fields

def nthField (index : Nat) : List Field -> Option Field
  | [] => none
  | field :: fields =>
      match index with
      | 0 => some field
      | n + 1 => nthField n fields

def slotVisited (index : Nat) : List Nat -> Bool
  | [] => false
  | visited :: rest =>
      if visited == index then
        true
      else
        slotVisited index rest

def evalFuel : Nat :=
  100

def applyEvaluatedStructPattern
    (fields : List Field)
    (labelPattern constraint : Value)
    (open_ : Bool) : Value :=
  meet (.structPattern [] labelPattern constraint open_) (.struct fields true)

def applyEvaluatedStructPatterns
    (fields : List Field)
    (patterns : List (Value × Value))
    (open_ : Bool) : Value :=
  meet (.structPatterns [] patterns open_) (.struct fields true)

def allRegularAlternatives : List (Mark × Value) -> Bool
  | [] => true
  | alternative :: alternatives =>
      alternative.fst == .regular && allRegularAlternatives alternatives

def joinValues : List Value -> Value
  | [] => .bottom
  | value :: values => values.foldl join value

def mergeEvaluatedFields (fields : List Field) : Option (List Field) :=
  mergeFieldListWith meet fields

def normalizeEvaluatedDisj (alternatives : List (Mark × Value)) : Value :=
  if allRegularAlternatives alternatives then
    joinValues (alternatives.map Prod.snd)
  else
    .disj alternatives

def selectEvaluatedField (base : Value) (label : String) : Value :=
  match base with
  | .struct fields _ =>
      match findEvalField label fields with
      | some field => Field.value field
      | none => .selector base label
  | .structTail fields _ =>
      match findEvalField label fields with
      | some field => Field.value field
      | none => .selector base label
  | .structPattern fields _ _ _ =>
      match findEvalField label fields with
      | some field => Field.value field
      | none => .selector base label
  | .structPatterns fields _ _ =>
      match findEvalField label fields with
      | some field => Field.value field
      | none => .selector base label
  | .bottom => .bottom
  | .bottomWith reasons => .bottomWith reasons
  | _ => .bottom

def getListValue? : Nat -> List Value -> Option Value
  | _, [] => none
  | 0, value :: _ => some value
  | index + 1, _ :: values => getListValue? index values

def selectEvaluatedListIndex (base key : Value) (items : List Value) : Value :=
  match key with
  | .prim (.int index) =>
      if index < 0 then
        .bottomWith [.invalidIndex index]
      else
        match getListValue? index.toNat items with
        | some item => item
        | none => .bottomWith [.indexOutOfRange index items.length]
  | .prim _ => .bottom
  | _ => .index base key

def selectEvaluatedListTailIndex (base key : Value) (items : List Value) : Value :=
  match key with
  | .prim (.int index) =>
      if index < 0 then
        .bottomWith [.invalidIndex index]
      else
        match getListValue? index.toNat items with
        | some item => item
        | none => .index base key
  | .prim _ => .bottom
  | _ => .index base key

def selectEvaluatedFieldIndex (base key : Value) (fields : List Field) : Value :=
  match key with
  | .prim (.string label) =>
      match findEvalField label fields with
      | some field => Field.value field
      | none => .index base key
  | .prim _ => .bottom
  | _ => .index base key

def selectEvaluatedIndex (base key : Value) : Value :=
  match base with
  | .struct fields _ => selectEvaluatedFieldIndex base key fields
  | .structTail fields _ => selectEvaluatedFieldIndex base key fields
  | .structPattern fields _ _ _ => selectEvaluatedFieldIndex base key fields
  | .structPatterns fields _ _ => selectEvaluatedFieldIndex base key fields
  | .list items => selectEvaluatedListIndex base key items
  | .listTail items _ => selectEvaluatedListTailIndex base key items
  | .bottom => .bottom
  | .bottomWith reasons => .bottomWith reasons
  | _ => .bottom

def evalAdd (left right : Value) : Value :=
  match left, right with
  | .prim (.int left), .prim (.int right) => .prim (.int (left + right))
  | .prim (.string left), .prim (.string right) => .prim (.string (left ++ right))
  | .prim (.bytes left), .prim (.bytes right) => .prim (.bytes (left ++ right))
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
  | .prim left, .prim right =>
      match evalDecimalBinary? addDecimalValues left right with
      | some value => .prim value
      | none => .bottom
  | _, _ => .binary .add left right

def evalSub (left right : Value) : Value :=
  match left, right with
  | .prim (.int left), .prim (.int right) => .prim (.int (left - right))
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
  | .prim left, .prim right =>
      match evalDecimalBinary? subDecimalValues left right with
      | some value => .prim value
      | none => .bottom
  | _, _ => .binary .sub left right

def evalMul (left right : Value) : Value :=
  match left, right with
  | .prim (.int left), .prim (.int right) => .prim (.int (left * right))
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
  | .prim left, .prim right =>
      match evalDecimalMultiply? left right with
      | some value => .prim value
      | none => .bottom
  | _, _ => .binary .mul left right

def evalDiv (left right : Value) : Value :=
  match left, right with
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
  | .prim left, .prim right =>
      match evalDecimalDivide? left right with
      | .ok text => .prim (.float text)
      | .divByZero => .bottomWith [.divisionByZero]
      | .nonNumeric => .bottom
  | _, _ => .binary .div left right

def evalEq (left right : Value) : Value :=
  match left, right with
  | .prim left, .prim right =>
      match evalDecimalCompare? decimalEqValues left right with
      | some value => .prim (.bool value)
      | none => .prim (.bool (left == right))
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
  | _, _ => .binary .eq left right

def evalNe (left right : Value) : Value :=
  match evalEq left right with
  | .prim (.bool value) => .prim (.bool (!value))
  | .binary .eq left right => .binary .ne left right
  | value => value

def charsLt : List Char -> List Char -> Bool
  | [], [] => false
  | [], _ :: _ => true
  | _ :: _, [] => false
  | left :: leftRest, right :: rightRest =>
      if left.toNat == right.toNat then
        charsLt leftRest rightRest
      else
        left.toNat < right.toNat

def stringsLt (left right : String) : Bool :=
  charsLt left.toList right.toList

def evalPrimitiveOrdering
    (decimalOp : DecimalValue -> DecimalValue -> Bool)
    (stringOp : String -> String -> Bool)
    (op : BinaryOp)
    (left right : Value) : Value :=
  match left, right with
  | .prim left, .prim right =>
      match evalDecimalCompare? decimalOp left right with
      | some value => .prim (.bool value)
      | none =>
          match left, right with
          | .string left, .string right => .prim (.bool (stringOp left right))
          | _, _ => .bottom
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
  | _, _ => .binary op left right

def evalRegexMatch (left right : Value) : Value :=
  match left, right with
  | .prim (.string value), .prim (.string pattern) => .prim (.bool (stringRegexMatches pattern value))
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
  | .prim _, .prim _ => .bottom
  | _, _ => .binary .regexMatch left right

def evalRegexNotMatch (left right : Value) : Value :=
  match evalRegexMatch left right with
  | .prim (.bool value) => .prim (.bool (!value))
  | .binary .regexMatch left right => .binary .regexNotMatch left right
  | value => value

def evalIntKeywordBinary
    (op : BinaryOp)
    (intEval : Value -> Value -> Value)
    (left right : Value) : Value :=
  match intEval left right with
  | .builtinCall _ _ => .binary op left right
  | value => value

def evalBoolBinary (op : BinaryOp) (boolOp : Bool -> Bool -> Bool) (left right : Value) : Value :=
  match left, right with
  | .prim (.bool left), .prim (.bool right) => .prim (.bool (boolOp left right))
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
  | .prim _, .prim _ => .bottom
  | _, _ => .binary op left right

def evalBoolNot (value : Value) : Value :=
  match value with
  | .prim (.bool value) => .prim (.bool (!value))
  | .bottom => .bottom
  | .bottomWith reasons => .bottomWith reasons
  | .prim _ => .bottom
  | _ => .unary .boolNot value

def negateFloatText (value : String) : String :=
  match value.toList with
  | '-' :: rest => String.ofList rest
  | _ => "-" ++ value

def evalNumPos (value : Value) : Value :=
  match value with
  | .prim (.int value) => .prim (.int value)
  | .prim (.float value) => .prim (.float value)
  | .bottom => .bottom
  | .bottomWith reasons => .bottomWith reasons
  | .prim _ => .bottom
  | _ => .unary .numPos value

def evalNumNeg (value : Value) : Value :=
  match value with
  | .prim (.int value) => .prim (.int (-value))
  | .prim (.float value) => .prim (.float (negateFloatText value))
  | .bottom => .bottom
  | .bottomWith reasons => .bottomWith reasons
  | .prim _ => .bottom
  | _ => .unary .numNeg value

def evalUnary (op : UnaryOp) (value : Value) : Value :=
  match op with
  | .boolNot => evalBoolNot value
  | .numPos => evalNumPos value
  | .numNeg => evalNumNeg value

def evalBinary (op : BinaryOp) (left right : Value) : Value :=
  match op with
  | .add => evalAdd left right
  | .sub => evalSub left right
  | .mul => evalMul left right
  | .div => evalDiv left right
  | .intDiv => evalIntKeywordBinary .intDiv divValue left right
  | .intMod => evalIntKeywordBinary .intMod modValue left right
  | .intQuo => evalIntKeywordBinary .intQuo quoValue left right
  | .intRem => evalIntKeywordBinary .intRem remValue left right
  | .eq => evalEq left right
  | .ne => evalNe left right
  | .lt => evalPrimitiveOrdering decimalLtValues stringsLt .lt left right
  | .le =>
      evalPrimitiveOrdering
        (fun left right => decimalEqValues left right || decimalLtValues left right)
        (fun left right => !stringsLt right left)
        .le
        left
        right
  | .gt => evalPrimitiveOrdering (fun left right => decimalLtValues right left) (fun left right => stringsLt right left) .gt left right
  | .ge =>
      evalPrimitiveOrdering
        (fun left right => decimalEqValues left right || decimalLtValues right left)
        (fun left right => !stringsLt left right)
        .ge
        left
        right
  | .regexMatch => evalRegexMatch left right
  | .regexNotMatch => evalRegexNotMatch left right
  | .boolAnd => evalBoolBinary .boolAnd (fun left right => left && right) left right
  | .boolOr => evalBoolBinary .boolOr (fun left right => left || right) left right

/--
The synthetic env frame a `for` iteration introduces. Mirrors `clauseLoopFrame`
in `Resolve`: keyed iterations bind the key at index 0 and the value at index 1,
unkeyed iterations bind the value at index 0. The bound values are already
evaluated, so referencing them re-evaluates a concrete value.
-/
def loopFrame (key : Option String) (keyValue : Value) (value : String) (element : Value) : List Field :=
  match key with
  | some key => [(key, .regular, keyValue), (value, .regular, element)]
  | none => [(value, .regular, element)]

/--
CUE renders interpolation holes by their natural string form: a string contributes its
raw content, numbers and booleans and null their literal spelling. Non-string-coercible
primitives (bytes) and non-primitive holes have no interpolation rendering.
-/
def interpolationText? : Value -> Option String
  | .prim (.string value) => some value
  | .prim (.int value) => some (toString value)
  | .prim (.float value) => some value
  | .prim (.bool true) => some "true"
  | .prim (.bool false) => some "false"
  | .prim .null => some "null"
  | _ => none

def interpolatePartsText? : List Value -> Option String
  | [] => some ""
  | part :: parts =>
      match interpolationText? part, interpolatePartsText? parts with
      | some head, some rest => some (head ++ rest)
      | _, _ => none

def partIsBottom : Value -> Bool
  | .bottom => true
  | .bottomWith _ => true
  | _ => false

def evalInterpolation (parts : List Value) : Value :=
  if parts.any partIsBottom then
    .bottom
  else
    match interpolatePartsText? parts with
    | some text => .prim (.string text)
    | none => .interpolation parts

/--
A `structComp` carries three kinds of member in its `comprehensions` bucket: field
comprehensions, dynamic fields, and plain embeddings. The first two expand to fields
merged into the struct; an embedding is an arbitrary value unified (`meet`) with the
whole struct, so a struct embedding merges its fields and a non-struct embedding
conflicts. Both kinds resolve in the enclosing struct's lexical frame.
-/
def isEmbeddingValue : Value -> Bool
  | .comprehension _ _ => false
  | .dynamicField _ _ _ => false
  | _ => true

def listPairsFrom (index : Nat) : List Value -> List (Value × Value)
  | [] => []
  | item :: items => (.prim (.int index), item) :: listPairsFrom (index + 1) items

def structPairs : List Field -> List (Value × Value)
  | [] => []
  | field :: fields =>
      match Field.fieldClass field with
      | .regular => (.prim (.string (Field.label field)), Field.value field) :: structPairs fields
      | _ => structPairs fields

/-- The (key, value) iteration pairs a source produces, or `none` if it is not iterable. -/
def comprehensionPairs : Value -> Option (List (Value × Value))
  | .list items => some (listPairsFrom 0 items)
  | .listTail items _ => some (listPairsFrom 0 items)
  | .struct fields _ => some (structPairs fields)
  | .structTail fields _ => some (structPairs fields)
  | .structPattern fields _ _ _ => some (structPairs fields)
  | .structPatterns fields _ _ => some (structPairs fields)
  | _ => none

mutual
  def evalFieldRefsWithFuel
      (fuel : Nat)
      (env : List (List Field))
      (visited : List Nat)
      (field : Field) : Field :=
    (Field.label field, Field.fieldClass field, evalValueWithFuel fuel env visited (Field.value field))

  def evalValueWithFuel : Nat -> List (List Field) -> List Nat -> Value -> Value
    | 0, _, _, value => value
    | _ + 1, _, _, .ref label =>
        .bottomWith [.unresolvedReference label]
    | fuel + 1, env, visited, .refId id =>
        match env.drop id.depth with
        | [] => .bottomWith [.unresolvedBinding id]
        | frame :: outer =>
            match nthField id.index frame with
            | none => .bottomWith [.unresolvedBinding id]
            | some field =>
                if id.depth == 0 then
                  if slotVisited id.index visited then
                    .top
                  else
                    evalValueWithFuel fuel env (id.index :: visited) (Field.value field)
                else
                  evalValueWithFuel fuel (frame :: outer) [id.index] (Field.value field)
    | fuel + 1, env, visited, .conj constraints =>
        let evaluated := constraints.map (evalValueWithFuel fuel env visited)
        evaluated.foldl (fun current constraint => meet current constraint) .top
    | fuel + 1, env, visited, .builtinCall name args =>
        evalBuiltinCall name (args.map (evalValueWithFuel fuel env visited))
    | fuel + 1, env, visited, .unary op value =>
        evalUnary op (evalValueWithFuel fuel env visited value)
    | fuel + 1, env, visited, .binary op left right =>
        evalBinary op
          (evalValueWithFuel fuel env visited left)
          (evalValueWithFuel fuel env visited right)
    | fuel + 1, env, visited, .selector base label =>
        selectEvaluatedField (evalValueWithFuel fuel env visited base) label
    | fuel + 1, env, visited, .index base key =>
        selectEvaluatedIndex
          (evalValueWithFuel fuel env visited base)
          (evalValueWithFuel fuel env visited key)
    | fuel + 1, env, visited, .disj alternatives =>
        let evaluated := alternatives.map fun alternative =>
          (alternative.fst, evalValueWithFuel fuel env visited alternative.snd)
        normalizeEvaluatedDisj evaluated
    | fuel + 1, env, _, .struct nestedFields open_ =>
        let nested := nestedFields :: env
        match mergeEvaluatedFields
          ((indexedFields nestedFields).map fun indexed =>
            evalFieldRefsWithFuel fuel nested [indexed.fst] indexed.snd) with
        | some nestedFields => .struct nestedFields open_
        | none => .bottom
    | fuel + 1, env, _, .structTail nestedFields tail =>
        let nested := nestedFields :: env
        match mergeEvaluatedFields
          ((indexedFields nestedFields).map fun indexed =>
            evalFieldRefsWithFuel fuel nested [indexed.fst] indexed.snd) with
        | some nestedFields =>
            .structTail nestedFields (evalValueWithFuel fuel nested [] tail)
        | none => .bottom
    | fuel + 1, env, _, .structPattern nestedFields labelPattern constraint open_ =>
        let nested := nestedFields :: env
        match mergeEvaluatedFields
          ((indexedFields nestedFields).map fun indexed =>
            evalFieldRefsWithFuel fuel nested [indexed.fst] indexed.snd) with
        | some nestedFields =>
            applyEvaluatedStructPattern
              nestedFields
              (evalValueWithFuel fuel nested [] labelPattern)
              (evalValueWithFuel fuel nested [] constraint)
              open_
        | none => .bottom
    | fuel + 1, env, _, .structPatterns nestedFields patterns open_ =>
        let nested := nestedFields :: env
        match mergeEvaluatedFields
          ((indexedFields nestedFields).map fun indexed =>
            evalFieldRefsWithFuel fuel nested [indexed.fst] indexed.snd) with
        | some nestedFields =>
            applyEvaluatedStructPatterns
              nestedFields
              (patterns.map fun pattern =>
                (
                  evalValueWithFuel fuel nested [] pattern.fst,
                  evalValueWithFuel fuel nested [] pattern.snd
                ))
              open_
        | none => .bottom
    | fuel + 1, env, visited, .list items =>
        .list (items.map (evalValueWithFuel fuel env visited))
    | fuel + 1, env, visited, .listTail items tail =>
        .listTail
          (items.map (evalValueWithFuel fuel env visited))
          (evalValueWithFuel fuel env visited tail)
    | fuel + 1, env, _, .comprehension clauses body =>
        match mergeEvaluatedFields (expandClausesWithFuel fuel env clauses body) with
        | some fields => .struct fields true
        | none => .bottom
    | fuel + 1, env, _, .structComp fields comprehensions open_ =>
        let nested := fields :: env
        let staticFields :=
          (indexedFields fields).map fun indexed =>
            evalFieldRefsWithFuel fuel nested [indexed.fst] indexed.snd
        let expanded :=
          comprehensions.foldl
            (fun acc comprehension => acc ++ expandComprehensionWithFuel fuel nested comprehension)
            []
        match mergeEvaluatedFields (staticFields ++ expanded) with
        | none => .bottom
        | some merged =>
            let embeddings := comprehensions.filter isEmbeddingValue
            embeddings.foldl
              (fun current embedding => meet current (evalValueWithFuel fuel nested [] embedding))
              (.struct merged open_)
    | fuel + 1, env, visited, .interpolation parts =>
        evalInterpolation (parts.map (evalValueWithFuel fuel env visited))
    | fuel + 1, env, visited, .dynamicField label _ value =>
        match evalValueWithFuel fuel env visited label with
        | .prim (.string name) =>
            .struct [(name, .regular, evalValueWithFuel fuel env visited value)] true
        | _ => .bottom
    | _, _, _, value => value

  /-- Expand one embedded comprehension/dynamic field into the fields it contributes. -/
  def expandComprehensionWithFuel : Nat -> List (List Field) -> Value -> List Field
    | 0, _, _ => []
    | fuel + 1, env, .comprehension clauses body => expandClausesWithFuel fuel env clauses body
    | fuel + 1, env, .dynamicField label fieldClass value =>
        match evalValueWithFuel fuel env [] label with
        | .prim (.string name) => [(name, fieldClass, evalValueWithFuel fuel env [] value)]
        | _ => []
    | _, _, _ => []

  /--
  Walk a comprehension's clause chain, evaluating each clause's source/condition in
  the current env. Each `for` iteration pushes a fresh loop-variable frame; each `if`
  guard either admits or drops its remaining expansion. With no clauses left, the body
  struct is evaluated and its fields are emitted for merging.
  -/
  def expandClausesWithFuel
      (fuel : Nat)
      (env : List (List Field))
      (clauses : List (Clause Value))
      (body : Value) : List Field :=
    match fuel with
    | 0 => []
    | fuel + 1 =>
        match clauses with
        | [] =>
            match evalValueWithFuel fuel env [] body with
            | .struct fields _ => fields
            | _ => []
        | .guard condition :: rest =>
            match evalValueWithFuel fuel env [] condition with
            | .prim (.bool true) => expandClausesWithFuel fuel env rest body
            | _ => []
        | .forIn key value source :: rest =>
            match comprehensionPairs (evalValueWithFuel fuel env [] source) with
            | none => []
            | some pairs =>
                pairs.foldl
                  (fun acc pair =>
                    let frame := loopFrame key pair.fst value pair.snd
                    acc ++ expandClausesWithFuel fuel (frame :: env) rest body)
                  []
end

def evalTopFields (fields : List Field) : Option (List Field) :=
  mergeEvaluatedFields
    ((indexedFields fields).map fun indexed =>
      evalFieldRefsWithFuel evalFuel [fields] [indexed.fst] indexed.snd)

def evalStructRefs (value : Value) : Value :=
  match normalizeDefinitions value with
  | .struct fields open_ =>
      match evalTopFields fields with
      | some fields => .struct fields open_
      | none => .bottom
  | .structTail fields tail =>
      match evalTopFields fields with
      | some merged => .structTail merged (evalValueWithFuel evalFuel [fields] [] tail)
      | none => .bottom
  | .structPattern fields labelPattern constraint open_ =>
      match evalTopFields fields with
      | some merged =>
          applyEvaluatedStructPattern
            merged
            (evalValueWithFuel evalFuel [fields] [] labelPattern)
            (evalValueWithFuel evalFuel [fields] [] constraint)
            open_
      | none => .bottom
  | .structPatterns fields patterns open_ =>
      match evalTopFields fields with
      | some merged =>
          applyEvaluatedStructPatterns
            merged
            (patterns.map fun pattern =>
              (
                evalValueWithFuel evalFuel [fields] [] pattern.fst,
                evalValueWithFuel evalFuel [fields] [] pattern.snd
              ))
            open_
      | none => .bottom
  | normalized@(.structComp _ _ _) => evalValueWithFuel evalFuel [] [] normalized
  | value => value

end Kue
