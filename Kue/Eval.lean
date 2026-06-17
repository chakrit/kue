import Kue.Builtin
import Kue.Decimal
import Kue.Lattice
import Kue.Normalize
import Std.Data.HashMap

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

def fieldLabelIndexFrom (label : String) (index : Nat) : List Field -> Option Nat
  | [] => none
  | field :: fields =>
      if Field.label field = label then
        some index
      else
        fieldLabelIndexFrom label (index + 1) fields

/-- Resolve a `Self.label` selection on a value-alias binding. When `id` points at a
    `.thisStruct` binding (a `label: Self={…}` value alias), `Self.label` is just a sibling
    reference resolved in the aliased struct's own frame, so this rewrites it to the
    `BindingId` of `label` in that frame — inheriting the ordinary same-struct cycle and
    resolution machinery. `none` when `id` is not a `thisStruct` binding or `label` is
    absent, leaving the generic selector path to handle it. -/
def thisStructFieldIndex? (env : List (Nat × List Field)) (id : BindingId) (label : String) : Option BindingId :=
  match env.drop id.depth with
  | [] => none
  | frame :: _ =>
      match nthField id.index frame.snd with
      | some field =>
          match Field.value field with
          | .thisStruct =>
              match fieldLabelIndexFrom label 0 frame.snd with
              | some labelIndex => some ⟨id.depth, labelIndex⟩
              | none => none
          | _ => none
      | none => none

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

/--
Memoization key. Evaluation of a `Value` is a pure function of `(fuel, env, visited,
value)`: the same tuple always yields the same result, so caching on the full tuple is
behavior-preserving — it shares an already-computed result rather than re-deriving it.
The `visited` slot set is part of the key, so a binding caught mid-cycle is keyed
separately from the same binding reached fresh; cycle detection is untouched.

The hash is deliberately *shallow* — `fuel`, `visited`, the env frame-count, and the
value's top constructor tag — so a cache probe never traverses the (large) env/value
subtree. Structural `BEq` only runs on a hash-bucket match, i.e. on a genuine hit or a
tag collision; misses stay O(1) on the hash.

The fan-out this kills: a `Self.#components.X` selector re-evaluates the entire
`#components` struct per selection; three sibling selections in a struct embedding (the
`packs.#Argo` shape) re-derive it three times, multiplying per fuel level. Cached,
`#components` is computed once and shared.
-/
def valueTag : Value -> UInt64
  | .top => 0
  | .bottom => 1
  | .bottomWith _ => 2
  | .prim _ => 3
  | .kind _ => 4
  | .notPrim _ => 5
  | .stringRegex _ => 6
  | .intGe _ => 7
  | .intGt _ => 8
  | .intLe _ => 9
  | .intLt _ => 10
  | .conj _ => 11
  | .builtinCall _ _ => 12
  | .unary _ _ => 13
  | .binary _ _ _ => 14
  | .ref _ => 15
  | .refId _ => 16
  | .thisStruct => 17
  | .selector _ _ => 18
  | .index _ _ => 19
  | .disj _ => 20
  | .struct _ _ => 21
  | .structTail _ _ => 22
  | .structPattern _ _ _ _ => 23
  | .structPatterns _ _ _ => 24
  | .list _ => 25
  | .listTail _ _ => 26
  | .comprehension _ _ => 27
  | .structComp _ _ _ => 28
  | .interpolation _ => 29
  | .dynamicField _ _ _ => 30

/--
A scope frame paired with a process-unique identity. Each frame push allocates a fresh
`id` from the evaluation state's counter; the id is the frame's identity for caching.
Two evaluations that thread the *same* frame object (the depth-0 self-reference and the
`env.drop` rebase both reuse an existing frame) carry the same id, so they share a cache
entry; independently-built frames get distinct ids and never falsely share.
-/
abbrev Frame := Nat × List Field

namespace Frame
def id (frame : Frame) : Nat := frame.fst
def fields (frame : Frame) : List Field := frame.snd
end Frame

abbrev Env := List Frame

/-- The id stack of an env — its cheap identity for cache-key equality. -/
def Env.ids (env : Env) : List Nat := env.map Frame.id

/--
Memoization key. Evaluation is a pure function of `(fuel, env, visited, value)`, so
caching on it is behavior-preserving. The env is keyed by its *id stack* (`envIds`), not
its (deep) frame contents — frame ids uniquely identify frame objects within one run, so
`List Nat` equality is sound and O(depth). `visited` is part of the key, so a binding
caught mid-cycle is keyed apart from the same binding reached fresh; cycle detection is
untouched. The hash is shallow (fuel, visited, env depth, value's top tag) so a probe
never traverses the value subtree; `BEq` runs only on a hash-bucket match.

The fan-out this kills: a `Self.#components.X` selector re-evaluates the whole
`#components` struct per selection; three sibling selections in a struct embedding (the
`packs.#Argo` shape) re-derive it three times, multiplying per fuel level. Cached,
`#components` is computed once and shared.
-/
structure EvalKey where
  fuel : Nat
  envIds : List Nat
  visited : List Nat
  value : Value
deriving BEq

instance : Hashable EvalKey where
  hash key := mixHash (hash key.fuel) (mixHash (hash key.visited)
    (mixHash (hash key.envIds.length) (valueTag key.value)))

/-- Evaluation state: the memo cache plus the next frame id to hand out. -/
structure EvalState where
  cache : Std.HashMap EvalKey Value
  nextFrameId : Nat

abbrev EvalM := StateM EvalState

/-- Push a frame onto the env, allocating it a fresh identity. -/
def pushFrame (fields : List Field) (env : Env) : EvalM Env := do
  let state <- get
  set { state with nextFrameId := state.nextFrameId + 1 }
  pure ((state.nextFrameId, fields) :: env)

mutual
  def evalFieldRefsWithFuel
      (fuel : Nat)
      (env : Env)
      (visited : List Nat)
      (field : Field) : EvalM Field := do
    let evaluated <- evalValueWithFuel fuel env visited (Field.value field)
    pure (Field.label field, Field.fieldClass field, evaluated)
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

  /-- Cached entry into the evaluator: read the memo, computing and storing on a miss. -/
  def evalValueWithFuel
      (fuel : Nat)
      (env : Env)
      (visited : List Nat)
      (value : Value) : EvalM Value := do
    let key : EvalKey := ⟨fuel, env.ids, visited, value⟩
    match (<- get).cache.get? key with
    | some cached => pure cached
    | none =>
        let result <- evalValueCoreWithFuel fuel env visited value
        modify (fun state => { state with cache := state.cache.insert key result })
        pure result
  termination_by (fuel, 1, 0)

  def evalValueCoreWithFuel
      (fuel : Nat)
      (env : Env)
      (visited : List Nat)
      (value : Value) : EvalM Value := do
    match fuel, value with
    | 0, value => pure value
    | _ + 1, .ref label =>
        pure (.bottomWith [.unresolvedReference label])
    | fuel + 1, .refId id =>
        match env.drop id.depth with
        | [] => pure (.bottomWith [.unresolvedBinding id])
        | frame :: outer =>
            match nthField id.index frame.snd with
            | none => pure (.bottomWith [.unresolvedBinding id])
            | some field =>
                if id.depth == 0 then
                  if slotVisited id.index visited then
                    pure .top
                  else
                    evalValueWithFuel fuel env (id.index :: visited) (Field.value field)
                else
                  evalValueWithFuel fuel (frame :: outer) [id.index] (Field.value field)
    | fuel + 1, .conj constraints => do
        let evaluated <- evalValuesWithFuel fuel env visited constraints
        pure (evaluated.foldl (fun current constraint => meet current constraint) .top)
    | fuel + 1, .builtinCall name args => do
        let evaluated <- evalValuesWithFuel fuel env visited args
        pure (evalBuiltinCall name evaluated)
    | fuel + 1, .unary op value => do
        let evaluated <- evalValueWithFuel fuel env visited value
        pure (evalUnary op evaluated)
    | fuel + 1, .binary op left right => do
        let leftEvaluated <- evalValueWithFuel fuel env visited left
        let rightEvaluated <- evalValueWithFuel fuel env visited right
        pure (evalBinary op leftEvaluated rightEvaluated)
    | fuel + 1, .selector (.refId id) label =>
        match thisStructFieldIndex? env id label with
        | some labelId => evalValueWithFuel fuel env visited (.refId labelId)
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
    | fuel + 1, .struct nestedFields open_ => do
        let nested <- pushFrame nestedFields env
        let evaluatedFields <- evalFieldRefsListWithFuel fuel nested (indexedFields nestedFields)
        match mergeEvaluatedFields evaluatedFields with
        | some nestedFields => pure (.struct nestedFields open_)
        | none => pure .bottom
    | fuel + 1, .structTail nestedFields tail => do
        let nested <- pushFrame nestedFields env
        let evaluatedFields <- evalFieldRefsListWithFuel fuel nested (indexedFields nestedFields)
        match mergeEvaluatedFields evaluatedFields with
        | some nestedFields =>
            let evaluatedTail <- evalValueWithFuel fuel nested [] tail
            pure (.structTail nestedFields evaluatedTail)
        | none => pure .bottom
    | fuel + 1, .structPattern nestedFields labelPattern constraint open_ => do
        let nested <- pushFrame nestedFields env
        let evaluatedFields <- evalFieldRefsListWithFuel fuel nested (indexedFields nestedFields)
        match mergeEvaluatedFields evaluatedFields with
        | some nestedFields =>
            let evaluatedLabel <- evalValueWithFuel fuel nested [] labelPattern
            let evaluatedConstraint <- evalValueWithFuel fuel nested [] constraint
            pure (applyEvaluatedStructPattern nestedFields evaluatedLabel evaluatedConstraint open_)
        | none => pure .bottom
    | fuel + 1, .structPatterns nestedFields patterns open_ => do
        let nested <- pushFrame nestedFields env
        let evaluatedFields <- evalFieldRefsListWithFuel fuel nested (indexedFields nestedFields)
        match mergeEvaluatedFields evaluatedFields with
        | some nestedFields =>
            let evaluatedPatterns <- patterns.mapM fun pattern => do
              let evaluatedLabel <- evalValueWithFuel fuel nested [] pattern.fst
              let evaluatedConstraint <- evalValueWithFuel fuel nested [] pattern.snd
              pure (evaluatedLabel, evaluatedConstraint)
            pure (applyEvaluatedStructPatterns nestedFields evaluatedPatterns open_)
        | none => pure .bottom
    | fuel + 1, .list items => do
        let evaluated <- evalValuesWithFuel fuel env visited items
        pure (.list evaluated)
    | fuel + 1, .listTail items tail => do
        let evaluatedItems <- evalValuesWithFuel fuel env visited items
        let evaluatedTail <- evalValueWithFuel fuel env visited tail
        pure (.listTail evaluatedItems evaluatedTail)
    | fuel + 1, .comprehension clauses body => do
        let expanded <- expandClausesWithFuel fuel env clauses body
        match mergeEvaluatedFields expanded with
        | some fields => pure (.struct fields true)
        | none => pure .bottom
    | fuel + 1, .structComp fields comprehensions open_ => do
        let nested <- pushFrame fields env
        let staticFields <- evalFieldRefsListWithFuel fuel nested (indexedFields fields)
        let expanded <- expandComprehensionsWithFuel fuel nested comprehensions
        match mergeEvaluatedFields (staticFields ++ expanded) with
        | none => pure .bottom
        | some merged =>
            let embeddings := comprehensions.filter isEmbeddingValue
            meetEmbeddingsWithFuel fuel nested (.struct merged open_) embeddings
    | fuel + 1, .interpolation parts => do
        let evaluated <- evalValuesWithFuel fuel env visited parts
        pure (evalInterpolation evaluated)
    | fuel + 1, .dynamicField label _ value => do
        let evaluatedLabel <- evalValueWithFuel fuel env visited label
        match evaluatedLabel with
        | .prim (.string name) => do
            let evaluatedValue <- evalValueWithFuel fuel env visited value
            pure (.struct [(name, .regular, evaluatedValue)] true)
        | _ => pure .bottom
    | _, value => pure value
  termination_by (fuel, 0, 0)

  /-- Meet a struct against each embedding in turn, evaluating each in the nested frame. -/
  def meetEmbeddingsWithFuel
      (fuel : Nat)
      (env : Env)
      (current : Value) : List Value -> EvalM Value
    | [] => pure current
    | embedding :: rest => do
        let evaluated <- evalValueWithFuel fuel env [] embedding
        meetEmbeddingsWithFuel fuel env (meet current evaluated) rest
  termination_by embeddings => (fuel, 3, embeddings.length)

  /-- Expand each embedded comprehension/dynamic field and concatenate the contributed fields. -/
  def expandComprehensionsWithFuel
      (fuel : Nat)
      (env : Env) : List Value -> EvalM (List Field)
    | [] => pure []
    | comprehension :: rest => do
        let head <- expandComprehensionWithFuel fuel env comprehension
        let tail <- expandComprehensionsWithFuel fuel env rest
        pure (head ++ tail)
  termination_by comprehensions => (fuel, 3, comprehensions.length)

  /-- Expand one embedded comprehension/dynamic field into the fields it contributes. -/
  def expandComprehensionWithFuel
      (fuel : Nat)
      (env : Env)
      (value : Value) : EvalM (List Field) := do
    match fuel, value with
    | 0, _ => pure []
    | fuel + 1, .comprehension clauses body => expandClausesWithFuel fuel env clauses body
    | fuel + 1, .dynamicField label fieldClass value => do
        let evaluatedLabel <- evalValueWithFuel fuel env [] label
        match evaluatedLabel with
        | .prim (.string name) => do
            let evaluatedValue <- evalValueWithFuel fuel env [] value
            pure [(name, fieldClass, evaluatedValue)]
        | _ => pure []
    | _, _ => pure []
  termination_by (fuel, 0, 0)

  /--
  Walk a comprehension's clause chain, evaluating each clause's source/condition in
  the current env. Each `for` iteration pushes a fresh loop-variable frame; each `if`
  guard either admits or drops its remaining expansion. With no clauses left, the body
  struct is evaluated and its fields are emitted for merging.
  -/
  def expandClausesWithFuel
      (fuel : Nat)
      (env : Env)
      (clauses : List (Clause Value))
      (body : Value) : EvalM (List Field) := do
    match fuel with
    | 0 => pure []
    | fuel + 1 =>
        match clauses with
        | [] => do
            let evaluatedBody <- evalValueWithFuel fuel env [] body
            match evaluatedBody with
            | .struct fields _ => pure fields
            | _ => pure []
        | .guard condition :: rest => do
            let evaluatedCondition <- evalValueWithFuel fuel env [] condition
            match evaluatedCondition with
            | .prim (.bool true) => expandClausesWithFuel fuel env rest body
            | _ => pure []
        | .forIn key value source :: rest => do
            let evaluatedSource <- evalValueWithFuel fuel env [] source
            match comprehensionPairs evaluatedSource with
            | none => pure []
            | some pairs => expandForPairsWithFuel fuel env key value rest body pairs
  termination_by (fuel, 0, 0)

  /-- Expand the remaining clause chain once per iteration pair, concatenating results. -/
  def expandForPairsWithFuel
      (fuel : Nat)
      (env : Env)
      (key : Option String)
      (value : String)
      (rest : List (Clause Value))
      (body : Value) : List (Value × Value) -> EvalM (List Field)
    | [] => pure []
    | pair :: pairs => do
        let nested <- pushFrame (loopFrame key pair.fst value pair.snd) env
        let head <- expandClausesWithFuel fuel nested rest body
        let tail <- expandForPairsWithFuel fuel env key value rest body pairs
        pure (head ++ tail)
  termination_by pairs => (fuel, 3, pairs.length)
end

/-- Run an evaluation action with a fresh cache, discarding the cache. The cache shares
    computed-once results within one top-level evaluation; it never escapes. -/
def runEval (action : EvalM α) : α :=
  (action.run { cache := ∅, nextFrameId := 0 }).fst

def evalTopFieldsM (fields : List Field) : EvalM (Option (List Field)) := do
  let top <- pushFrame fields []
  let evaluated <- evalFieldRefsListWithFuel evalFuel top (indexedFields fields)
  pure (mergeEvaluatedFields evaluated)

def evalStructRefsM (value : Value) : EvalM Value := do
  match normalizeDefinitions value with
  | .struct fields open_ =>
      match (<- evalTopFieldsM fields) with
      | some fields => pure (.struct fields open_)
      | none => pure .bottom
  | .structTail fields tail =>
      match (<- evalTopFieldsM fields) with
      | some merged =>
          let top <- pushFrame fields []
          let evaluatedTail <- evalValueWithFuel evalFuel top [] tail
          pure (.structTail merged evaluatedTail)
      | none => pure .bottom
  | .structPattern fields labelPattern constraint open_ =>
      match (<- evalTopFieldsM fields) with
      | some merged =>
          let top <- pushFrame fields []
          let evaluatedLabel <- evalValueWithFuel evalFuel top [] labelPattern
          let evaluatedConstraint <- evalValueWithFuel evalFuel top [] constraint
          pure (applyEvaluatedStructPattern merged evaluatedLabel evaluatedConstraint open_)
      | none => pure .bottom
  | .structPatterns fields patterns open_ =>
      match (<- evalTopFieldsM fields) with
      | some merged =>
          let top <- pushFrame fields []
          let evaluatedPatterns <- patterns.mapM fun pattern => do
            let evaluatedLabel <- evalValueWithFuel evalFuel top [] pattern.fst
            let evaluatedConstraint <- evalValueWithFuel evalFuel top [] pattern.snd
            pure (evaluatedLabel, evaluatedConstraint)
          pure (applyEvaluatedStructPatterns merged evaluatedPatterns open_)
      | none => pure .bottom
  | normalized@(.structComp _ _ _) => evalValueWithFuel evalFuel [] [] normalized
  | value => pure value

def evalStructRefs (value : Value) : Value :=
  runEval (evalStructRefsM value)

end Kue
