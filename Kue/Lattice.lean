import Kue.Value

namespace Kue

def meetPrim (left right : Prim) : Value :=
  if left = right then
    .prim left
  else
    .bottomWith [.primitiveConflict left right]

def kindAcceptsPrim (kind : Kind) (prim : Prim) : Bool :=
  kind == Prim.kind prim || (kind == .number && (Prim.kind prim == .int || Prim.kind prim == .float))

def kindAcceptsKind (expected actual : Kind) : Bool :=
  expected == actual || (expected == .number && (actual == .int || actual == .float))

def meetNotPrimPrim (forbidden prim : Prim) : Value :=
  if forbidden = prim then
    .bottomWith [.excludedValue forbidden]
  else
    .prim prim

def meetStringRegexPrim (pattern : String) (prim : Prim) : Value :=
  match prim with
  | .string value =>
      if stringRegexMatches pattern value then
        .prim prim
      else
        .bottom
  | _ => .bottomWith [.kindConflict .string (Prim.kind prim)]

def minDecimal (left right : DecimalValue) : DecimalValue :=
  if decimalLeValues left right then left else right

def maxDecimal (left right : DecimalValue) : DecimalValue :=
  if decimalLeValues left right then right else left

/-- Meet a single bound (`>=`/`>`/`<=`/`<`) against a primitive. The bound's `domain`
    decides which numeric kinds engage: a `number`-domain (bare) bound admits both int and
    float, an `int`/`float`-domain bound only its own kind; a non-numeric prim conflicts on
    kind. The limit is decimal-compared so `>0.5 & 1.0` ⇒ `1.0`, `>0 & 1.5` ⇒ `1.5`. -/
def meetBoundPrim (bound : DecimalValue) (kind : BoundKind) (domain : NumberDomain) (prim : Prim) : Value :=
  if domain.admitsKind (Prim.kind prim) then
    match decimalFromPrim? prim with
    | some value =>
        if kind.admits bound value then
          .prim prim
        else
          .bottomWith [.intBoundConflict]
    | none => .bottomWith [.kindConflict domain.kind (Prim.kind prim)]
  else
    .bottomWith [.kindConflict domain.kind (Prim.kind prim)]

/-- Meet a two-sided range (a lower bound and an upper bound, sharing a `domain`) against a
    primitive. -/
def meetRangePrim
    (lowerBound upperBound : DecimalValue) (lowerKind upperKind : BoundKind)
    (domain : NumberDomain) (prim : Prim) : Value :=
  if domain.admitsKind (Prim.kind prim) then
    match decimalFromPrim? prim with
    | some value =>
        if lowerKind.admits lowerBound value && upperKind.admits upperBound value then
          .prim prim
        else
          .bottomWith [.intBoundConflict]
    | none => .bottomWith [.kindConflict domain.kind (Prim.kind prim)]
  else
    .bottomWith [.kindConflict domain.kind (Prim.kind prim)]

/-- Tighten two same-side bounds (both lower, or both upper) into one. For lower bounds the
    tighter is the larger limit; for upper bounds the smaller. When the two limits tie, the
    strict kind (`>`/`<`) wins as the tighter constraint. Both bounds already share `domain`. -/
def tightenSameSide
    (leftBound rightBound : DecimalValue) (leftKind rightKind : BoundKind) (domain : NumberDomain) : Value :=
  let lower := leftKind.lower
  let pickLeft :=
    if decimalEqValues leftBound rightBound then
      leftKind.strict || !rightKind.strict
    else if lower then
      decimalLeValues rightBound leftBound
    else
      decimalLeValues leftBound rightBound
  if pickLeft then .boundConstraint leftBound leftKind domain
  else .boundConstraint rightBound rightKind domain

/-- Is the interval bounded by `lowerKind lowerBound` below and `upperKind upperBound`
    above non-empty? A strict bound on either side requires strict inequality of the limits. -/
def rangeFeasible (lowerBound upperBound : DecimalValue) (lowerKind upperKind : BoundKind) : Bool :=
  if lowerKind.strict || upperKind.strict then decimalLtValues lowerBound upperBound
  else decimalLeValues lowerBound upperBound

/-- Meet two bounds. Same-side bounds tighten to one; opposite-side bounds form a canonical
    `lower & upper` conjunction (lower member first, matching CUE's display order) when
    feasible, else `⊥`. The two domains are narrowed (`number & int` ⇒ `int`); an
    incompatible pair (`int` vs `float`) has no inhabitant and conflicts. -/
def meetTwoBounds
    (leftBound rightBound : DecimalValue) (leftKind rightKind : BoundKind)
    (leftDomain rightDomain : NumberDomain) : Value :=
  match leftDomain.narrow rightDomain with
  | none => .bottomWith [.kindConflict leftDomain.kind rightDomain.kind]
  | some domain =>
    if leftKind.lower == rightKind.lower then
      tightenSameSide leftBound rightBound leftKind rightKind domain
    else
      let lowerBound := if leftKind.lower then leftBound else rightBound
      let lowerKind := if leftKind.lower then leftKind else rightKind
      let upperBound := if leftKind.lower then rightBound else leftBound
      let upperKind := if leftKind.lower then rightKind else leftKind
      if rangeFeasible lowerBound upperBound lowerKind upperKind then
        .conj [.boundConstraint lowerBound lowerKind domain, .boundConstraint upperBound upperKind domain]
      else
        .bottomWith [.intBoundConflict]

/-- Meet a numeric `kind` against a bound. CUE keeps an explicit `int &`/`float &` conjunct
    in the display (`int & >0`, `float & >0`) — a bare bound is number-typed, so `int` is
    load-bearing: it is the conjunct that rejects floats, not the bound. So `int`/`float`
    retain the kind as a conjunction alongside the (still number-domain) bound; `number` is
    redundant and drops to the bare bound; anything else conflicts on kind.

    The bound keeps its `number` domain rather than being narrowed because the kept kind
    conjunct already enforces the narrowing against any primitive, and leaving the bound
    untouched keeps meet commutative (a range `[>=0, <=n]` that `& int` reduces pairwise
    cannot narrow every member uniformly — but it does not need to: the `int` conjunct
    guards them all). The domain tag is load-bearing only for a *bare* bound (where `number`
    admits floats, matching `>0 & 1.5` ⇒ `1.5`). -/
def meetKindWithBound (kind : Kind) (bound : DecimalValue) (boundKind : BoundKind) (domain : NumberDomain) : Value :=
  let keep (k : Kind) (target : NumberDomain) : Value :=
    match domain.narrow target with
    | some _ => .conj [.kind k, .boundConstraint bound boundKind domain]
    | none => .bottomWith [.kindConflict kind domain.kind]
  match kind with
  | .int => keep .int .int
  | .float => keep .float .float
  | .number => .boundConstraint bound boundKind domain
  | _ => .bottomWith [.kindConflict kind domain.kind]

def isBottom : Value -> Bool
  | .bottom => true
  | .bottomWith _ => true
  | _ => false

def containsBottomFuel : Nat :=
  100

def containsBottomWithFuel : Nat -> Value -> Bool
  | 0, _ => false
  | _ + 1, .bottom => true
  | _ + 1, .bottomWith _ => true
  | fuel + 1, .conj constraints =>
      constraints.any (containsBottomWithFuel fuel)
  | fuel + 1, .builtinCall _ args =>
      args.any (containsBottomWithFuel fuel)
  | fuel + 1, .unary _ value =>
      containsBottomWithFuel fuel value
  | fuel + 1, .binary _ left right =>
      containsBottomWithFuel fuel left || containsBottomWithFuel fuel right
  | fuel + 1, .selector base _ =>
      containsBottomWithFuel fuel base
  | fuel + 1, .index base key =>
      containsBottomWithFuel fuel base || containsBottomWithFuel fuel key
  | fuel + 1, .disj alternatives =>
      alternatives.any fun alternative => containsBottomWithFuel fuel alternative.snd
  | fuel + 1, .struct fields _ =>
      fields.any fun field => containsBottomWithFuel fuel (Field.value field)
  | fuel + 1, .structTail fields tail =>
      fields.any (fun field => containsBottomWithFuel fuel (Field.value field))
        || containsBottomWithFuel fuel tail
  | fuel + 1, .structPattern fields labelPattern constraint _ =>
      fields.any (fun field => containsBottomWithFuel fuel (Field.value field))
        || containsBottomWithFuel fuel labelPattern
        || containsBottomWithFuel fuel constraint
  | fuel + 1, .structPatterns fields patterns _ =>
      fields.any (fun field => containsBottomWithFuel fuel (Field.value field))
        || patterns.any fun pattern =>
          containsBottomWithFuel fuel pattern.fst || containsBottomWithFuel fuel pattern.snd
  | fuel + 1, .list items =>
      items.any (containsBottomWithFuel fuel)
  | fuel + 1, .listTail items tail =>
      items.any (containsBottomWithFuel fuel) || containsBottomWithFuel fuel tail
  | fuel + 1, .embeddedList items tail decls =>
      items.any (containsBottomWithFuel fuel)
        || (match tail with | some t => containsBottomWithFuel fuel t | none => false)
        || decls.any (fun field => containsBottomWithFuel fuel (Field.value field))
  | _ + 1, _ => false

def containsBottom (value : Value) : Bool :=
  containsBottomWithFuel containsBottomFuel value

def combineMark : Mark -> Mark -> Mark
  | .default, _ => .default
  | _, .default => .default
  | .regular, .regular => .regular

def flattenAlternatives (alternatives : List (Mark × Value)) : List (Mark × Value) :=
  alternatives.foldr
    (fun alternative flattened =>
      match alternative with
      | (mark, .disj nested) =>
          nested.map (fun nestedAlternative =>
            (combineMark mark nestedAlternative.fst, nestedAlternative.snd)
          ) ++ flattened
      | alternative => alternative :: flattened)
    []

def normalizeDisj (alternatives : List (Mark × Value)) : Value :=
  let flattened := flattenAlternatives alternatives
  let live := flattened.filter fun alternative => !containsBottom alternative.snd
  match live with
  | [] => .bottom
  | [(.regular, value)] => value
  | alternatives => .disj alternatives

def disjOfValues (left right : Value) : Value :=
  normalizeDisj [(.regular, left), (.regular, right)]

def meetCore (left right : Value) : Value :=
  match left, right with
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
  | .top, value => value
  | value, .top => value
  | .kind leftKind, .kind rightKind =>
      if kindAcceptsKind leftKind rightKind then
        .kind rightKind
      else if kindAcceptsKind rightKind leftKind then
        .kind leftKind
      else
        .bottomWith [.kindConflict leftKind rightKind]
  | .kind kind, .prim prim =>
      if kindAcceptsPrim kind prim then
        .prim prim
      else
        .bottomWith [.kindConflict kind (Prim.kind prim)]
  | .prim prim, .kind kind =>
      if kindAcceptsPrim kind prim then
        .prim prim
      else
        .bottomWith [.kindConflict (Prim.kind prim) kind]
  | .prim leftPrim, .prim rightPrim => meetPrim leftPrim rightPrim
  | .notPrim forbidden, .prim prim => meetNotPrimPrim forbidden prim
  | .prim prim, .notPrim forbidden => meetNotPrimPrim forbidden prim
  | .kind kind, .notPrim forbidden =>
      if kindAcceptsPrim kind forbidden then
        .notPrim forbidden
      else
        .kind kind
  | .notPrim forbidden, .kind kind =>
      if kindAcceptsPrim kind forbidden then
        .notPrim forbidden
      else
        .kind kind
  | .notPrim leftForbidden, .notPrim rightForbidden =>
      if leftForbidden = rightForbidden then
        .notPrim leftForbidden
      else
        .conj [.notPrim leftForbidden, .notPrim rightForbidden]
  | .builtinCall leftName leftArgs, .builtinCall rightName rightArgs =>
      if leftName = rightName && leftArgs == rightArgs then
        .builtinCall leftName leftArgs
      else
        .bottom
  | .stringRegex leftPattern, .stringRegex rightPattern =>
      if leftPattern = rightPattern then
        .stringRegex leftPattern
      else
        .conj [.stringRegex leftPattern, .stringRegex rightPattern]
  | .stringRegex pattern, .prim prim => meetStringRegexPrim pattern prim
  | .prim prim, .stringRegex pattern => meetStringRegexPrim pattern prim
  | .kind kind, .stringRegex pattern =>
      if kindAcceptsKind kind .string then
        .stringRegex pattern
      else
        .bottomWith [.kindConflict kind .string]
  | .stringRegex pattern, .kind kind =>
      if kindAcceptsKind kind .string then
        .stringRegex pattern
      else
        .bottomWith [.kindConflict .string kind]
  | .notPrim forbidden, .stringRegex pattern =>
      if Prim.kind forbidden = .string then
        .conj [.stringRegex pattern, .notPrim forbidden]
      else
        .stringRegex pattern
  | .stringRegex pattern, .notPrim forbidden =>
      if Prim.kind forbidden = .string then
        .conj [.stringRegex pattern, .notPrim forbidden]
      else
        .stringRegex pattern
  | .stringRegex _, .boundConstraint _ _ d => .bottomWith [.kindConflict .string d.kind]
  | .boundConstraint _ _ d, .stringRegex _ => .bottomWith [.kindConflict d.kind .string]
  | .boundConstraint bound kind domain, .notPrim forbidden =>
      if domain.admitsKind (Prim.kind forbidden) then
        .conj [.boundConstraint bound kind domain, .notPrim forbidden]
      else
        .boundConstraint bound kind domain
  | .notPrim forbidden, .boundConstraint bound kind domain =>
      if domain.admitsKind (Prim.kind forbidden) then
        .conj [.boundConstraint bound kind domain, .notPrim forbidden]
      else
        .boundConstraint bound kind domain
  | .boundConstraint bound kind domain, .prim prim => meetBoundPrim bound kind domain prim
  | .prim prim, .boundConstraint bound kind domain => meetBoundPrim bound kind domain prim
  | .kind kind, .boundConstraint bound boundKind domain =>
      meetKindWithBound kind bound boundKind domain
  | .boundConstraint bound boundKind domain, .kind kind =>
      meetKindWithBound kind bound boundKind domain
  | .boundConstraint leftBound leftKind leftDomain, .boundConstraint rightBound rightKind rightDomain =>
      meetTwoBounds leftBound rightBound leftKind rightKind leftDomain rightDomain
  | .conj [.boundConstraint lowerBound lowerKind lowerDomain, .boundConstraint upperBound upperKind _], .prim prim =>
      meetRangePrim lowerBound upperBound lowerKind upperKind lowerDomain prim
  | .prim prim, .conj [.boundConstraint lowerBound lowerKind lowerDomain, .boundConstraint upperBound upperKind _] =>
      meetRangePrim lowerBound upperBound lowerKind upperKind lowerDomain prim
  | .conj _, _ => .bottom
  | _, .conj _ => .bottom
  | .builtinCall _ _, _ => .bottom
  | _, .builtinCall _ _ => .bottom
  | .unary leftOp leftValue, .unary rightOp rightValue =>
      if leftOp == rightOp && leftValue == rightValue then
        .unary leftOp leftValue
      else
        .bottom
  | .unary _ _, _ => .bottom
  | _, .unary _ _ => .bottom
  | .binary leftOp leftA leftB, .binary rightOp rightA rightB =>
      if leftOp == rightOp && leftA == rightA && leftB == rightB then
        .binary leftOp leftA leftB
      else
        .bottom
  | .binary _ _ _, _ => .bottom
  | _, .binary _ _ _ => .bottom
  | .ref leftLabel, .ref rightLabel =>
      if leftLabel = rightLabel then
        .ref leftLabel
      else
        .bottom
  | .refId leftId, .refId rightId =>
      if leftId == rightId then
        .refId leftId
      else
        .bottom
  | .selector leftBase leftLabel, .selector rightBase rightLabel =>
      if leftLabel = rightLabel && leftBase == rightBase then
        .selector leftBase leftLabel
      else
        .bottom
  | .index leftBase leftKey, .index rightBase rightKey =>
      if leftBase == rightBase && leftKey == rightKey then
        .index leftBase leftKey
      else
        .bottom
  | .thisStruct, .thisStruct => .thisStruct
  | .thisStruct, _ => .bottom
  | _, .thisStruct => .bottom
  | .refId _, _ => .bottom
  | _, .refId _ => .bottom
  | .selector _ _, _ => .bottom
  | _, .selector _ _ => .bottom
  | .index _ _, _ => .bottom
  | _, .index _ _ => .bottom
  | .list _, .list _ => .bottom
  | .listTail _ _, _ => .bottom
  | _, .listTail _ _ => .bottom
  | .list _, _ => .bottom
  | _, .list _ => .bottom
  | .ref _, _ => .bottom
  | _, .ref _ => .bottom
  | .struct _ _, .struct _ _ => .bottom
  | .structTail _ _, _ => .bottom
  | _, .structTail _ _ => .bottom
  | .structPattern _ _ _ _, _ => .bottom
  | _, .structPattern _ _ _ _ => .bottom
  | .structPatterns _ _ _, _ => .bottom
  | _, .structPatterns _ _ _ => .bottom
  | .disj _, _ => .bottom
  | _, .disj _ => .bottom
  | .structComp _ _ _, _ => .bottom
  | _, .structComp _ _ _ => .bottom
  | .comprehension _ _, _ => .bottom
  | _, .comprehension _ _ => .bottom
  | .interpolation _, _ => .bottom
  | _, .interpolation _ => .bottom
  | .dynamicField _ _ _, _ => .bottom
  | _, .dynamicField _ _ _ => .bottom
  | .struct .., _ => .bottom
  | _, .struct .. => .bottom
  | .embeddedList _ _ _, _ => .bottom
  | _, .embeddedList _ _ _ => .bottom

/-- Flatten a value into its top-level conjunction members, recursing into nested
    `.conj`. A non-conjunction is a singleton. Used so conjunction meets reduce over a
    flat constraint set instead of nesting `.conj` inside `.conj` (which the pairwise
    bound/kind merge arms in `meetCore` cannot collapse). -/
def flattenConj : Value -> List Value
  | .conj constraints => constraints.flatMap flattenConj
  | value => [value]

/-- A stable rank for the kinds that appear as conj members, in CUE display order. -/
def kindRank : Kind -> Nat
  | .null => 0
  | .bool => 1
  | .number => 2
  | .int => 3
  | .float => 4
  | .string => 5
  | .bytes => 6

/-- A textual sort key for an excluded primitive (`!=v`). -/
def primSortKey : Prim -> String
  | .null => "null"
  | .bool value => toString value
  | .int value => toString value
  | .float value => value
  | .string value => value
  | .bytes value => value

/-- The primary/secondary sort key for a constraint that may appear as a `.conj` member,
    minus a bound's decimal limit (which `conjMemberLe` compares directly so different
    scales order correctly). Primary rank is by constructor (kind before bounds before
    notPrim before stringRegex before residual), secondary by the constructor's own ordering
    (bound kind; prim kind for notPrim; pattern length-then-string for regex). -/
def conjMemberKey : Value -> Nat × Nat × String
  | .kind kind => (0, kindRank kind, "")
  | .boundConstraint _ kind _ => (1, kind.rank, "")
  | .notPrim prim => (2, 0, primSortKey prim)
  | .stringRegex pattern => (3, pattern.length, pattern)
  | _ => (4, 0, "")

/-- A canonical `<=` over two conj members: primary/secondary by `conjMemberKey`, then —
    for two bounds of equal kind — by decimal limit (so `>0.5 & >1` orders by limit across
    scales). Members it cannot distinguish keep stable order. Used to canonicalize `.conj`
    member order so `a & b` and `b & a` re-wrap to the same sorted list (meet commutative on
    the canonical form). -/
def conjMemberLe (left right : Value) : Bool :=
  let lk := conjMemberKey left
  let rk := conjMemberKey right
  if lk.1 != rk.1 then lk.1 <= rk.1
  else if lk.2.1 != rk.2.1 then lk.2.1 <= rk.2.1
  else
    match left, right with
    | .boundConstraint lb _ _, .boundConstraint rb _ _ => decimalLeValues lb rb
    | _, _ => lk.2.2 <= rk.2.2

/-- Sort a flat constraint list into canonical member order. -/
def sortConjMembers (members : List Value) : List Value :=
  members.mergeSort conjMemberLe

/-- Meet a single constraint into a flat, already-reduced constraint list. Tries to merge
    `constraint` pairwise with each existing member via `meetValue`: a merge that collapses
    to a single non-conjunction (e.g. two bounds → a tighter bound, `kind int & >0` →
    nothing tighter so it stays paired) replaces that member; a bottom short-circuits; a
    result that re-splits into a conjunction means no single-member simplification was
    possible, so the constraint is kept alongside (appended). This keeps the constraint set
    flat and order-insensitive, so `int & >=0 & <=65535` reduces to the flat
    `[kind int, >=0, <=65535]` rather than ping-ponging into nested conjunctions. -/
def addConstraintWith
    (meetValue : Value -> Value -> Value) : List Value -> Value -> List Value
  | [], constraint => [constraint]
  | member :: rest, constraint =>
      match meetValue member constraint with
      | .bottom => [.bottom]
      | .bottomWith reasons => [.bottomWith reasons]
      | .conj _ => member :: addConstraintWith meetValue rest constraint
      | merged => addConstraintWith meetValue rest merged

/-- Meet a conjunction's constraints into a value by reducing the whole constraint set
    flat. Both sides are flattened (`flattenConj`), then folded pairwise via
    `addConstraintWith`. The final list re-wraps as a single value (`.bottom`/the lone
    member/`.conj`). Replaces the previous left-fold-into-accumulator form, which nested
    `.conj` results and bottomed multi-bound int ranges like `int & >=0 & <=65535`. -/
def meetConjValueWith
    (meetValue : Value -> Value -> Value) (constraints : List Value) (value : Value) : Value :=
  let initial := constraints.flatMap flattenConj
  let reduced :=
    (flattenConj value).foldl
      (fun current constraint =>
        match current with
        | [.bottom] => [.bottom]
        | [.bottomWith reasons] => [.bottomWith reasons]
        | _ => addConstraintWith meetValue current constraint)
      initial
  match reduced with
  | [] => .top
  | [single] => single
  | members => .conj (sortConjMembers members)

def meetListPrefixTailWith
    (meetValue : Value -> Value -> Value) : List Value -> Value -> List Value -> Option (List Value)
  | [], tail, items => some (items.map (fun item => meetValue tail item))
  | expected :: expectedItems, tail, actual :: actualItems =>
      match meetListPrefixTailWith meetValue expectedItems tail actualItems with
      | some items => some (meetValue expected actual :: items)
      | none => none
  | _ :: _, _, [] => none

/-- Merge two field classes by composing each orthogonal axis: a `let` binding merges
    only with another `let` binding; two real fields merge by OR-ing definition-ness,
    OR-ing hidden-ness, and meeting on the presence lattice (`#x? & #x` → definition +
    present; `x? & x!` → required; `_x? & _x` → hidden + present). A `let` and a non-`let`
    do not merge (`none`), matching the old enum's refusal to combine `letBinding` with
    any other class. -/
def mergeFieldClass (left right : FieldClass) : Option FieldClass :=
  match left, right with
  | .letBinding, .letBinding => some .letBinding
  | .letBinding, _ => none
  | _, .letBinding => none
  | .field ld lh lo, .field rd rh ro =>
      some (.field (ld || rd) (lh || rh) (lo.meet ro))

def fieldWithClass (fieldClass : FieldClass) (label : String) (value : Value) : Field :=
  (label, fieldClass, value)

def mergeFieldValueWith (meetValue : Value -> Value -> Value) (left right : Field) : Option Field :=
  match mergeFieldClass (Field.fieldClass left) (Field.fieldClass right) with
  | some fieldClass =>
      let value := meetValue (Field.value left) (Field.value right)
      if isBottom value then
        some (fieldWithClass fieldClass (Field.label left) (.bottomWith [.fieldConflict (Field.label left)]))
      else
        some (fieldWithClass fieldClass (Field.label left) value)
  | none => none

def mergeFieldIntoWith
    (meetValue : Value -> Value -> Value) (fields : List Field) (field : Field) : Option (List Field) :=
  match fields with
  | [] => some [field]
  | current :: rest =>
      if Field.label current = Field.label field then
        match mergeFieldValueWith meetValue current field with
        | some merged => some (merged :: rest)
        | none => none
      else
        match mergeFieldIntoWith meetValue rest field with
        | some mergedRest => some (current :: mergedRest)
        | none => none

def mergeStructFieldsWith
    (meetValue : Value -> Value -> Value) (leftFields rightFields : List Field) : Option (List Field) :=
  rightFields.foldl
    (fun merged field =>
      match merged with
      | some fields => mergeFieldIntoWith meetValue fields field
      | none => none)
    (some leftFields)

def mergeFieldListWith (meetValue : Value -> Value -> Value) (fields : List Field) : Option (List Field) :=
  some
    (fields.foldl
      (fun merged field =>
        match mergeFieldIntoWith meetValue merged field with
        | some fields => fields
        | none => merged ++ [field])
      [])

def hasFieldLabel (label : String) : List Field -> Bool
  | [] => false
  | field :: fields =>
      if Field.label field = label then
        true
      else
        hasFieldLabel label fields

def markDisallowedField (field : Field) : Field :=
  fieldWithClass (Field.fieldClass field) (Field.label field)
    (.bottomWith [.fieldNotAllowed (Field.label field)])

def applyClosednessFrom (allowedFields : List Field) (isOpen : Bool) (fields : List Field) : List Field :=
  if isOpen then
    fields
  else
    fields.map fun field =>
      if hasFieldLabel (Field.label field) allowedFields || Field.ignoresClosedness field then
        field
      else
        markDisallowedField field

def applyStructClosedness
    (leftFields rightFields mergedFields : List Field)
    (leftOpen rightOpen : Bool) : List Field :=
  let checkedByLeft := applyClosednessFrom leftFields leftOpen mergedFields
  applyClosednessFrom rightFields rightOpen checkedByLeft

def applyTailToFieldWith
    (meetValue : Value -> Value -> Value)
    (declaredFields : List Field)
    (tail : Value)
    (field : Field) : Field :=
  if hasFieldLabel (Field.label field) declaredFields then
    field
  else
    let value := meetValue tail (Field.value field)
    if isBottom value then
      fieldWithClass (Field.fieldClass field) (Field.label field)
        (.bottomWith [.fieldConstraint (Field.label field)])
    else
      fieldWithClass (Field.fieldClass field) (Field.label field) value

def applyTailToExtrasWith
    (meetValue : Value -> Value -> Value) (declaredFields : List Field) (tail : Value) (fields : List Field) :
    List Field :=
  fields.map (applyTailToFieldWith meetValue declaredFields tail)

def labelMatchesPatternWith
    (meetValue : Value -> Value -> Value)
    (labelPattern : Value)
    (label : String) : Bool :=
  !containsBottom (meetValue labelPattern (.prim (.string label)))

def applyPatternToFieldWith
    (meetValue : Value -> Value -> Value)
    (labelPattern constraint : Value)
    (field : Field) : Field :=
  let isRegular := Field.fieldClass field == .regular
  let labelMatches := labelMatchesPatternWith meetValue labelPattern (Field.label field)
  if isRegular && labelMatches then
    let value := meetValue constraint (Field.value field)
    if isBottom value then
      fieldWithClass (Field.fieldClass field) (Field.label field)
        (.bottomWith [.fieldConstraint (Field.label field)])
    else
      fieldWithClass (Field.fieldClass field) (Field.label field) value
  else
    field

def applyPatternToFieldsWith
    (meetValue : Value -> Value -> Value)
    (labelPattern constraint : Value)
    (fields : List Field) : List Field :=
  fields.map (applyPatternToFieldWith meetValue labelPattern constraint)

def patternStructValue (fields : List Field) : List (Value × Value) -> Bool -> Value
  | [], open_ => .struct fields open_
  | [pattern], open_ => .structPattern fields pattern.fst pattern.snd open_
  | patterns, open_ => .structPatterns fields patterns open_

def applyPatternsToFieldsWith
    (meetValue : Value -> Value -> Value)
    (patterns : List (Value × Value))
    (fields : List Field) : List Field :=
  patterns.foldl
    (fun fields pattern => applyPatternToFieldsWith meetValue pattern.fst pattern.snd fields)
    fields

def fieldMatchesPatternWith
    (meetValue : Value -> Value -> Value)
    (labelPattern : Value)
    (field : Field) : Bool :=
  Field.fieldClass field == .regular && labelMatchesPatternWith meetValue labelPattern (Field.label field)

def fieldAllowedByPatternWith
    (meetValue : Value -> Value -> Value)
    (declaredFields : List Field)
    (labelPattern : Value)
    (field : Field) : Bool :=
  hasFieldLabel (Field.label field) declaredFields
    || Field.ignoresClosedness field
    || fieldMatchesPatternWith meetValue labelPattern field

def applyPatternClosednessToFieldWith
    (meetValue : Value -> Value -> Value)
    (declaredFields : List Field)
    (labelPattern : Value)
    (open_ : Bool)
    (field : Field) : Field :=
  if open_ || fieldAllowedByPatternWith meetValue declaredFields labelPattern field then
    field
  else
    markDisallowedField field

def applyPatternClosednessWith
    (meetValue : Value -> Value -> Value)
    (declaredFields : List Field)
    (labelPattern : Value)
    (open_ : Bool)
    (fields : List Field) : List Field :=
  fields.map (applyPatternClosednessToFieldWith meetValue declaredFields labelPattern open_)

def fieldAllowedByPatternsWith
    (meetValue : Value -> Value -> Value)
    (declaredFields : List Field)
    (patterns : List (Value × Value))
    (field : Field) : Bool :=
  hasFieldLabel (Field.label field) declaredFields
    || Field.ignoresClosedness field
    || patterns.any fun pattern => fieldMatchesPatternWith meetValue pattern.fst field

def applyPatternsClosednessToFieldWith
    (meetValue : Value -> Value -> Value)
    (declaredFields : List Field)
    (patterns : List (Value × Value))
    (open_ : Bool)
    (field : Field) : Field :=
  if open_ || fieldAllowedByPatternsWith meetValue declaredFields patterns field then
    field
  else
    markDisallowedField field

def applyPatternsClosednessWith
    (meetValue : Value -> Value -> Value)
    (declaredFields : List Field)
    (patterns : List (Value × Value))
    (open_ : Bool)
    (fields : List Field) : List Field :=
  fields.map (applyPatternsClosednessToFieldWith meetValue declaredFields patterns open_)

def mergeStructTailWithStructWith
    (meetValue : Value -> Value -> Value)
    (tailFields : List Field)
    (tail : Value)
    (fields : List Field) : Value :=
  match mergeStructFieldsWith meetValue tailFields fields with
  | some mergedFields => .structTail (applyTailToExtrasWith meetValue tailFields tail mergedFields) tail
  | none => .bottom

def mergeStructPatternWithStructWith
    (meetValue : Value -> Value -> Value)
    (patternFields : List Field)
    (labelPattern constraint : Value)
    (open_ : Bool)
    (fields : List Field) : Value :=
  match mergeStructFieldsWith meetValue patternFields fields with
  | some mergedFields =>
      .structPattern
        (applyPatternsClosednessWith
          meetValue
          patternFields
          [(labelPattern, constraint)]
          open_
          (applyPatternsToFieldsWith meetValue [(labelPattern, constraint)] mergedFields))
        labelPattern
        constraint
        open_
  | none => .bottom

def mergeStructPatternsWithStructWith
    (meetValue : Value -> Value -> Value)
    (patternFields : List Field)
    (patterns : List (Value × Value))
    (open_ : Bool)
    (fields : List Field) : Value :=
  match mergeStructFieldsWith meetValue patternFields fields with
  | some mergedFields =>
      patternStructValue
        (applyPatternsClosednessWith
          meetValue
          patternFields
          patterns
          open_
          (applyPatternsToFieldsWith meetValue patterns mergedFields))
        patterns
        open_
  | none => .bottom

def mergeStructPatternsWithStructPatternsWith
    (meetValue : Value -> Value -> Value)
    (leftFields : List Field)
    (leftPatterns : List (Value × Value))
    (leftOpen : Bool)
    (rightFields : List Field)
    (rightPatterns : List (Value × Value))
    (rightOpen : Bool) : Value :=
  match mergeStructFieldsWith meetValue leftFields rightFields with
  | some mergedFields =>
      let patterns := leftPatterns ++ rightPatterns
      let open_ := leftOpen && rightOpen
      patternStructValue
        (applyPatternsClosednessWith
          meetValue
          leftFields
          leftPatterns
          leftOpen
          (applyPatternsClosednessWith
            meetValue
            rightFields
            rightPatterns
            rightOpen
            (applyPatternsToFieldsWith
              meetValue
              rightPatterns
              (applyPatternsToFieldsWith meetValue leftPatterns mergedFields))))
        patterns
        open_
  | none => .bottom

def meetListWith (meetValue : Value -> Value -> Value) : List Value -> List Value -> Option (List Value)
  | [], [] => some []
  | left :: leftItems, right :: rightItems =>
      match meetListWith meetValue leftItems rightItems with
      | some items => some (meetValue left right :: items)
      | none => none
  | _, _ => none

/-- Does the struct field list carry a member that produces manifest output
    (a `regular`/`required` field)? Such a field makes a list embedding conflict. -/
def structHasOutputField (fields : List (String × FieldClass × Value)) : Bool :=
  fields.any (fun f => FieldClass.producesOutput (Field.fieldClass f))

/-- The non-output (hidden/definition/optional/let) fields — those that survive as
    selectable declarations when a struct becomes its embedded list. -/
def declFields (fields : List (String × FieldClass × Value)) : List (String × FieldClass × Value) :=
  fields.filter (fun f => !FieldClass.producesOutput (Field.fieldClass f))

/-- Normalize a list-shaped value to `(items, optional-tail)`: `none` for the
    non-list values, `some` otherwise. `[...]` is `([], some .top)`. -/
def asListPair : Value -> Option (List Value × Option Value)
  | .list items => some (items, none)
  | .listTail items tail => some (items, some tail)
  | .embeddedList items tail _ => some (items, tail)
  | _ => none

/-- Meet two `(items, tail)` list shapes. Closed×closed needs equal length;
    a tail constrains the other list's overflow / open tail. -/
def meetListPairWith
    (meetValue : Value -> Value -> Value)
    : (List Value × Option Value) -> (List Value × Option Value) -> Option (List Value × Option Value)
  | (leftItems, none), (rightItems, none) =>
      match meetListWith meetValue leftItems rightItems with
      | some items => some (items, none)
      | none => none
  | (fixed, some tail), (items, none) =>
      match meetListPrefixTailWith meetValue fixed tail items with
      | some items => some (items, none)
      | none => none
  | (items, none), (fixed, some tail) =>
      match meetListPrefixTailWith meetValue fixed tail items with
      | some items => some (items, none)
      | none => none
  | (leftFixed, some leftTail), (rightFixed, some rightTail) =>
      -- two open lists: align the shared prefix, longer prefix's overflow meets the
      -- shorter's tail, result stays open with the met tail.
      let met := meetValue leftTail rightTail
      let rec align : List Value -> List Value -> Option (List Value)
        | [], rs => some (rs.map (meetValue leftTail))
        | ls, [] => some (ls.map (meetValue rightTail))
        | l :: ls, r :: rs =>
            match align ls rs with
            | some rest => some (meetValue l r :: rest)
            | none => none
      match align leftFixed rightFixed with
      | some items => some (items, some met)
      | none => none

def meetFuel : Nat :=
  100

def meetWithFuel : Nat -> Value -> Value -> Value
  | 0, left, right => meetCore left right
  | fuel + 1, left, right =>
    match left, right with
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
  | .top, value => value
  | value, .top => value
  | .conj constraints, value => meetConjValueWith (meetWithFuel fuel) constraints value
  | value, .conj constraints => meetConjValueWith (meetWithFuel fuel) constraints value
  | .struct leftFields leftOpen, .struct rightFields rightOpen =>
      match mergeStructFieldsWith (meetWithFuel fuel) leftFields rightFields with
      | some fields =>
          .struct
            (applyStructClosedness leftFields rightFields fields leftOpen rightOpen)
            (leftOpen && rightOpen)
      | none => .bottom
  | .structTail tailFields tail, .struct fields _ =>
      mergeStructTailWithStructWith (meetWithFuel fuel) tailFields tail fields
  | .struct fields _, .structTail tailFields tail =>
      mergeStructTailWithStructWith (meetWithFuel fuel) tailFields tail fields
  | .structTail leftFields leftTail, .structTail rightFields rightTail =>
      match mergeStructFieldsWith (meetWithFuel fuel) leftFields rightFields with
      | some mergedFields =>
          let tail := meetWithFuel fuel leftTail rightTail
          if isBottom tail then
            .bottom
          else
            .structTail
              (applyTailToExtrasWith
                (meetWithFuel fuel)
                leftFields
                leftTail
                (applyTailToExtrasWith (meetWithFuel fuel) rightFields rightTail mergedFields))
              tail
      | none => .bottom
  | .structPattern patternFields labelPattern constraint open_, .struct fields _ =>
      mergeStructPatternWithStructWith (meetWithFuel fuel) patternFields labelPattern constraint open_ fields
  | .struct fields _, .structPattern patternFields labelPattern constraint open_ =>
      mergeStructPatternWithStructWith (meetWithFuel fuel) patternFields labelPattern constraint open_ fields
  | .structPatterns patternFields patterns open_, .struct fields _ =>
      mergeStructPatternsWithStructWith (meetWithFuel fuel) patternFields patterns open_ fields
  | .struct fields _, .structPatterns patternFields patterns open_ =>
      mergeStructPatternsWithStructWith (meetWithFuel fuel) patternFields patterns open_ fields
  | .structPattern leftFields leftLabel leftConstraint leftOpen,
    .structPattern rightFields rightLabel rightConstraint rightOpen =>
      mergeStructPatternsWithStructPatternsWith
        (meetWithFuel fuel)
        leftFields
        [(leftLabel, leftConstraint)]
        leftOpen
        rightFields
        [(rightLabel, rightConstraint)]
        rightOpen
  | .structPattern leftFields leftLabel leftConstraint leftOpen,
    .structPatterns rightFields rightPatterns rightOpen =>
      mergeStructPatternsWithStructPatternsWith
        (meetWithFuel fuel)
        leftFields
        [(leftLabel, leftConstraint)]
        leftOpen
        rightFields
        rightPatterns
        rightOpen
  | .structPatterns leftFields leftPatterns leftOpen,
    .structPattern rightFields rightLabel rightConstraint rightOpen =>
      mergeStructPatternsWithStructPatternsWith
        (meetWithFuel fuel)
        leftFields
        leftPatterns
        leftOpen
        rightFields
        [(rightLabel, rightConstraint)]
        rightOpen
  | .structPatterns leftFields leftPatterns leftOpen,
    .structPatterns rightFields rightPatterns rightOpen =>
      mergeStructPatternsWithStructPatternsWith
        (meetWithFuel fuel)
        leftFields
        leftPatterns
        leftOpen
        rightFields
        rightPatterns
        rightOpen
  | .list leftItems, .list rightItems =>
      match meetListWith (meetWithFuel fuel) leftItems rightItems with
      | some items => .list items
      | none => .bottom
  | .listTail fixed tail, .list items =>
      match meetListPrefixTailWith (meetWithFuel fuel) fixed tail items with
      | some items => .list items
      | none => .bottom
  | .list items, .listTail fixed tail =>
      match meetListPrefixTailWith (meetWithFuel fuel) fixed tail items with
      | some items => .list items
      | none => .bottom
  | .disj leftAlternatives, .disj rightAlternatives =>
      let flatLeft := flattenAlternatives leftAlternatives
      let flatRight := flattenAlternatives rightAlternatives
      let alternatives :=
        flatLeft.foldr
          (fun leftAlternative combined =>
            let paired :=
              flatRight.map fun rightAlternative =>
                (
                  combineMark leftAlternative.fst rightAlternative.fst,
                  meetWithFuel fuel leftAlternative.snd rightAlternative.snd
                )
            paired ++ combined)
          []
      normalizeDisj alternatives
  | .disj alternatives, value =>
      let flatAlternatives := flattenAlternatives alternatives
      let distributed :=
        flatAlternatives.map fun alternative =>
          (alternative.fst, meetWithFuel fuel alternative.snd value)
      normalizeDisj distributed
  | value, .disj alternatives =>
      let flatAlternatives := flattenAlternatives alternatives
      let distributed :=
        flatAlternatives.map fun alternative =>
          (alternative.fst, meetWithFuel fuel value alternative.snd)
      normalizeDisj distributed
  -- A struct with only non-output members embedding a list IS that list, carrying its
  -- declarations as selectable. With an output (regular/required) field present it
  -- conflicts (falls through to bottom). CUE v0.16.1: `{ #a:1, [1,2] }` → `[1,2]`;
  -- `{ a:1, [1,2] }` → conflict. The `.embeddedList` arms precede the struct arms so a
  -- left embeddedList keeps its own decls instead of being swallowed by `listLike, .struct`.
  | .embeddedList leftItems leftTail leftDecls, rightLike =>
      match asListPair rightLike with
      | some rightPair =>
          match meetListPairWith (meetWithFuel fuel) (leftItems, leftTail) rightPair with
          | some (items, tail) =>
              -- right side may carry its own decls (another embeddedList)
              let rightDecls := match rightLike with | .embeddedList _ _ d => d | _ => []
              match mergeStructFieldsWith (meetWithFuel fuel) leftDecls rightDecls with
              | some decls => .embeddedList items tail decls
              | none => .bottom
          | none => .bottom
      | none =>
          match rightLike with
          | .struct fields _ =>
              if structHasOutputField fields then .bottom
              else
                match mergeStructFieldsWith (meetWithFuel fuel) leftDecls (declFields fields) with
                | some decls => .embeddedList leftItems leftTail decls
                | none => .bottom
          | _ => meetCore (.embeddedList leftItems leftTail leftDecls) rightLike
  | leftLike, .embeddedList rightItems rightTail rightDecls =>
      match asListPair leftLike with
      | some leftPair =>
          match meetListPairWith (meetWithFuel fuel) leftPair (rightItems, rightTail) with
          | some (items, tail) => .embeddedList items tail rightDecls
          | none => .bottom
      | none =>
          match leftLike with
          | .struct fields _ =>
              if structHasOutputField fields then .bottom
              else
                match mergeStructFieldsWith (meetWithFuel fuel) (declFields fields) rightDecls with
                | some decls => .embeddedList rightItems rightTail decls
                | none => .bottom
          | _ => meetCore leftLike (.embeddedList rightItems rightTail rightDecls)
  | .struct fields _, listLike =>
      match asListPair listLike with
      | some (items, tail) =>
          if structHasOutputField fields then .bottom
          else .embeddedList items tail (declFields fields)
      | none => meetCore (.struct fields true) listLike
  | listLike, .struct fields _ =>
      match asListPair listLike with
      | some (items, tail) =>
          if structHasOutputField fields then .bottom
          else .embeddedList items tail (declFields fields)
      | none => meetCore listLike (.struct fields true)
  | value, other => meetCore value other

def meet (left right : Value) : Value :=
  meetWithFuel meetFuel left right

def joinPrim (left right : Prim) : Value :=
  if left = right then
    .prim left
  else
    disjOfValues (.prim left) (.prim right)

def join (left right : Value) : Value :=
  match left, right with
  | .top, _ => .top
  | _, .top => .top
  | .bottom, value => value
  | value, .bottom => value
  | .kind leftKind, .kind rightKind =>
      if kindAcceptsKind leftKind rightKind then
        .kind leftKind
      else if kindAcceptsKind rightKind leftKind then
        .kind rightKind
      else
        disjOfValues (.kind leftKind) (.kind rightKind)
  | .kind kind, .prim prim =>
      if kindAcceptsPrim kind prim then
        .kind kind
      else
        disjOfValues (.kind kind) (.prim prim)
  | .prim prim, .kind kind =>
      if kindAcceptsPrim kind prim then
        .kind kind
      else
        disjOfValues (.prim prim) (.kind kind)
  | .boundConstraint leftBound leftKind leftDomain, .boundConstraint rightBound rightKind rightDomain =>
      if leftKind == rightKind && leftDomain == rightDomain then
        -- Same comparator and domain: the join (least upper bound) is the looser limit — the
        -- smaller limit for a lower bound, the larger for an upper bound.
        let widened := if leftKind.lower then minDecimal leftBound rightBound else maxDecimal leftBound rightBound
        .boundConstraint widened leftKind leftDomain
      else
        disjOfValues (.boundConstraint leftBound leftKind leftDomain) (.boundConstraint rightBound rightKind rightDomain)
  | .kind kind, .boundConstraint bound boundKind domain =>
      if kindAcceptsKind kind domain.kind then .kind kind
      else disjOfValues (.kind kind) (.boundConstraint bound boundKind domain)
  | .boundConstraint bound boundKind domain, .kind kind =>
      if kindAcceptsKind kind domain.kind then .kind kind
      else disjOfValues (.boundConstraint bound boundKind domain) (.kind kind)
  | .kind kind, .stringRegex pattern =>
      if kindAcceptsKind kind .string then .kind kind else disjOfValues (.kind kind) (.stringRegex pattern)
  | .stringRegex pattern, .kind kind =>
      if kindAcceptsKind kind .string then .kind kind else disjOfValues (.stringRegex pattern) (.kind kind)
  | .stringRegex pattern, .prim prim =>
      if containsBottom (meetStringRegexPrim pattern prim) then
        disjOfValues (.stringRegex pattern) (.prim prim)
      else
        .stringRegex pattern
  | .prim prim, .stringRegex pattern =>
      if containsBottom (meetStringRegexPrim pattern prim) then
        disjOfValues (.prim prim) (.stringRegex pattern)
      else
        .stringRegex pattern
  | .stringRegex leftPattern, .stringRegex rightPattern =>
      if leftPattern = rightPattern then
        .stringRegex leftPattern
      else
        disjOfValues (.stringRegex leftPattern) (.stringRegex rightPattern)
  | .builtinCall leftName leftArgs, .builtinCall rightName rightArgs =>
      if leftName = rightName && leftArgs == rightArgs then
        .builtinCall leftName leftArgs
      else
        disjOfValues (.builtinCall leftName leftArgs) (.builtinCall rightName rightArgs)
  | .prim leftPrim, .prim rightPrim => joinPrim leftPrim rightPrim
  | .disj leftAlternatives, .disj rightAlternatives =>
      normalizeDisj (leftAlternatives ++ rightAlternatives)
  | .disj alternatives, value =>
      normalizeDisj (alternatives ++ [(.regular, value)])
  | value, .disj alternatives =>
      normalizeDisj ((.regular, value) :: alternatives)
  | value, other => disjOfValues value other

end Kue
