import Kue.Value
import Kue.Regex

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
  match regexParseError? pattern with
  | some err => .bottomWith [.invalidRegex pattern err]
  | none =>
      match prim with
      | .string value =>
          if matchRegex pattern value then
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
          .bottomWith [.boundConflict]
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
          .bottomWith [.boundConflict]
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
        .bottomWith [.boundConflict]

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

/- `containsBottom` and its four list-helpers form one mutual block; the doc comment lives on
   `containsBottom`. `termination_by structural` elaborates them via the nested-inductive recursor,
   so they are total (no fuel, no depth bound) AND reduce by `rfl`/`decide` — the list-of-pair /
   list-of-field helpers destructure their element so the recursed-on subterm is a syntactic
   component the structural checker accepts. Keeping `rfl`-reducibility matters: existing `meet`/
   manifest proofs unfold through `containsBottom` (`liveAlternatives`), and well-founded recursion
   would make them irreducible. -/
mutual

/-- Does `value` contain a present `.bottom`/`.bottomWith` anywhere in its tree? Used to prune
    dead disjunction arms (`liveAlternatives`), to test pattern-label matches
    (`labelMatchesPatternWith`), and at builtin boundaries. TOTAL structural recursion over the
    finite `Value` inductive — no fuel. `Value` is well-founded (its `refId`/`closure` ids are
    leaf data, never back-edges), so every constructor's children are structurally smaller and the
    walk terminates with NO depth bound: a `.bottom` at ANY depth is found, closing the prior
    fuel-cap (100) soundness hole where a deep non-cyclic bottom was missed → a dead arm survived →
    a wrong value. The remaining pre-eval/deferred constructors (`comprehension`,
    `listComprehension`, `interpolation`, `dynamicField`, `closure`) are NOT descended (catch-all
    `false`): they never sit on the disjunction-pruning path as a resolved value.

    `.structComp` IS descended, but only into its RESOLVED `fields` (not its still-deferred
    `comprehensions`). MEET-RESID-1 (and the eager `withDeferredComprehensions` site) re-wrap a
    merged residual as a `.structComp` whose `fields` CAN carry a held `.bottomWith` field conflict
    (`{x:1,for…} & {x:2}` ⇒ `.structComp [x:_|_] …`); without descending, such a residual surviving
    as a disjunction ARM was NOT pruned by `liveAlternatives` (it tags `.structComp`, so the
    catch-all returned `false`) → a dead arm survived → a wrong value (a spurious unresolved `.disj`
    where cue resolves to the live arm). The `comprehensions` stay un-descended: they hold
    unexpanded clause bodies that are legitimately incomplete, never resolved conflicts — a conflict
    only materializes once a comprehension expands+merges, at which point it lands in `fields` (or
    short-circuits to `.bottom`). The `List`-nested children (`.conj`, `.disj`, `.struct`,
    `.structComp`, lists) recurse through the named helpers below so the structural decrease stays
    visible to Lean. -/
def containsBottom : Value -> Bool
  | .bottom => true
  | .bottomWith _ => true
  | .conj constraints => containsBottomList constraints
  | .builtinCall _ args => containsBottomList args
  | .unary _ value => containsBottom value
  | .binary _ left right => containsBottom left || containsBottom right
  | .selector base _ => containsBottom base
  | .index base key => containsBottom base || containsBottom key
  | .disj alternatives => containsBottomAlts alternatives
  | .struct fields _ tail patterns _ =>
      -- Fields, optional tail, patterns (closed clauses' predicates ⊆ patterns', so they add
      -- no new bottom sites).
      containsBottomFields fields
        || (match tail with | some t => containsBottom t | none => false)
        || containsBottomPatterns patterns
  -- A held residual: descend its RESOLVED fields only (a merged field conflict lives there as a
  -- present `.bottomWith`); the deferred comprehensions are unexpanded, never a resolved conflict.
  | .structComp fields _ _ => containsBottomFields fields
  | .list items => containsBottomList items
  | .listTail items tail => containsBottomList items || containsBottom tail
  | .embeddedList items tail decls =>
      containsBottomList items
        || (match tail with | some t => containsBottom t | none => false)
        || containsBottomFields decls
  | _ => false
  termination_by structural value => value

def containsBottomList : List Value -> Bool
  | [] => false
  | value :: rest => containsBottom value || containsBottomList rest
  termination_by structural values => values

def containsBottomAlts : List (Mark × Value) -> Bool
  | [] => false
  | (_, value) :: rest => containsBottom value || containsBottomAlts rest
  termination_by structural alternatives => alternatives

/-- Whether any PRESENT field carries a bottom. An OPTIONAL field is skipped: it carries an
    unsatisfiable-IF-present constraint (`#u?: _|_`), not a present bottom, so it leaves the struct
    LIVE — CUE keeps `{#u?: _|_}` and bottoms only once `#u` is supplied (regular, checked at
    manifest). Without this skip, an embedded disjunction's arm carrying an impossible optional field
    (the argocd `#ArgoRepo` `(_#A{…,#u?:_|_} | _#B{…,#g?:_|_})` shape) was pruned as bottom even when
    the field was unset, killing BOTH arms → `_|_` instead of the surviving arm. -/
def containsBottomFields : List Field -> Bool
  | [] => false
  | ⟨_, fieldClass, value⟩ :: rest =>
      (match FieldClass.optionality fieldClass with
        | .optional => false
        | _ => containsBottom value)
        || containsBottomFields rest
  termination_by structural fields => fields

def containsBottomPatterns : List (Value × Value) -> Bool
  | [] => false
  | (labelPattern, constraint) :: rest =>
      containsBottom labelPattern || containsBottom constraint || containsBottomPatterns rest
  termination_by structural patterns => patterns
end

/-- Mark combination for the disjunction *cross product* (unification's `(a|b) & (c|d)`,
    spec rule `(v1,d1) & (v2,d2) = (v1&v2, d1&d2)`): a result alternative is a default iff
    it came from `default × default` — logical AND, not OR. ORing manufactures spurious
    defaults (`(1|*2)&(1|2|3)` would lose its lone surviving default and the operand-wide
    default set would over-collapse). The no-marked-default convention (a disjunction with
    no `*` has *every* arm in its default set) is applied by `withDefaultConvention` at the
    cross-product sites BEFORE this AND runs. -/
def combineMark : Mark -> Mark -> Mark
  | .default, .default => .default
  | _, _ => .regular

/-- True iff any alternative is explicitly marked default. -/
def hasDefaultMark (alternatives : List (Mark × Value)) : Bool :=
  alternatives.any fun alternative => alternative.fst == .default

/-- CUE's default-set convention: a disjunction with NO `*`-marked alternative has its
    *whole* value set as the default set. Used only where an operand's defaults are about to
    cross (unification) or be selected by a default-marked parent (nested flatten) — never at
    a top level, where a no-default disjunction must STAY ambiguous (`1|2` ≠ `*1|*2`). -/
def withDefaultConvention (alternatives : List (Mark × Value)) : List (Mark × Value) :=
  if hasDefaultMark alternatives then alternatives
  else alternatives.map fun alternative => (.default, alternative.snd)

/-- Within a single value, a default occurrence dominates a regular one (`*1` and `1` are
    the same value `1`, which is a default). Logical OR — the *intra*-value rule, distinct
    from the *inter*-value cross-product AND of `combineMark`. -/
def combineMarkOr : Mark -> Mark -> Mark
  | .regular, .regular => .regular
  | _, _ => .default

/-- Merge alternatives that share a value: a value is a default iff ANY of its occurrences
    is default (`combineMarkOr`). Collapses `*1|*1|2 → *1|2`, `*1|1 → *1`, `1|1 → 1`, so
    equal defaults dedup and resolve to one. First occurrence's position is preserved. -/
def dedupAlternatives (alternatives : List (Mark × Value)) : List (Mark × Value) :=
  alternatives.foldr
    (fun alternative merged =>
      if merged.any (fun existing => existing.snd == alternative.snd) then
        merged.map fun existing =>
          if existing.snd == alternative.snd then
            (combineMarkOr existing.fst alternative.fst, existing.snd)
          else existing
      else alternative :: merged)
    []

/-- Flatten one level of nested disjunction with CUE's two-level default precedence. An
    alternative `(m, .disj inner)` is replaced by `inner`'s alternatives, re-marked by the
    *parent* mark `m`:
    - `m = .default`: the parent selects `inner`'s default set — an inner arm becomes a
      result default iff it is in `inner`'s default set (its `*` arms, or ALL arms when
      `inner` has no `*`). So `*d | 5` with `d:1|2` carries `1` and `2` as defaults (inner
      has no `*` → both default), shedding the regular `5`; with `d:*1|2` only `1`.
    - `m = .regular`: the parent does NOT contribute `inner` to the default set — every
      inner arm is regular. So `d | *5` keeps `d`'s arms regular (shed unless no outer
      default exists).
    A non-disjunction alternative passes through unchanged. -/
def flattenAlternatives (alternatives : List (Mark × Value)) : List (Mark × Value) :=
  alternatives.foldr
    (fun alternative flattened =>
      match alternative with
      | (.default, .disj nested) =>
          let nestedDefaults := withDefaultConvention nested
          nestedDefaults ++ flattened
      | (.regular, .disj nested) =>
          (nested.map fun n => (Mark.regular, n.snd)) ++ flattened
      | alternative => alternative :: flattened)
    []

/-- Live alternatives: flatten nested disjunctions, drop bottoms, then merge equal values.
    A default at any level survives the flatten; bottom arms (from a failed cross-product or
    narrowing) are filtered before dedup so they never shadow a live equal value. -/
def liveAlternatives (alternatives : List (Mark × Value)) : List (Mark × Value) :=
  dedupAlternatives
    ((flattenAlternatives alternatives).filter fun alternative =>
      !containsBottom alternative.snd)

def defaultAlternatives (alternatives : List (Mark × Value)) : List (Mark × Value) :=
  alternatives.filter fun alternative => alternative.fst == .default

def normalizeDisj (alternatives : List (Mark × Value)) : Value :=
  match liveAlternatives alternatives with
  | [] => .bottom
  | [(.regular, value)] => value
  | alternatives => .disj alternatives

/-- Select the value a disjunction collapses to in a concrete context (manifestation, a
    boolean guard, an operation that forces a default). Mirrors CUE's default rule: a unique
    marked default wins; absent any default, a unique regular alternative wins; otherwise the
    disjunction stays ambiguous and `none` keeps it unresolved. Non-default disjunctions with
    more than one live alternative deliberately do NOT collapse. -/
def resolveDisjDefault? (alternatives : List (Mark × Value)) : Option Value :=
  let live := liveAlternatives alternatives
  match defaultAlternatives live with
  | [(_, value)] => some value
  | [] =>
      match live with
      | [(.regular, value)] => some value
      | _ => none
  | _ => none

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
  -- `meetCore` is the bottoms-everything fallthrough; the real `struct×struct` merge is the
  -- single arm in `meetWithFuel`. A struct reaching here meets a non-struct → bottom.
  | .struct .., _ => .bottom
  | _, .struct .. => .bottom
  | .disj _, _ => .bottom
  | _, .disj _ => .bottom
  | .structComp _ _ _, _ => .bottom
  | _, .structComp _ _ _ => .bottom
  | .comprehension _ _, _ => .bottom
  | _, .comprehension _ _ => .bottom
  | .listComprehension _ _, _ => .bottom
  | _, .listComprehension _ _ => .bottom
  | .interpolation _, _ => .bottom
  | _, .interpolation _ => .bottom
  | .dynamicField _ _ _, _ => .bottom
  | _, .dynamicField _ _ _ => .bottom
  | .embeddedList _ _ _, _ => .bottom
  | _, .embeddedList _ _ _ => .bottom
  -- closure: meet against a use-site struct is the unlock (slice 4); until a producer
  -- exists, no closure reaches meet, so the inert behavior is `.bottom` like any other
  -- opaque residual. The captured env makes this NOT pure-over-an-opaque-ref later.
  | .closure _ _, _ => .bottom
  | _, .closure _ _ => .bottom

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
    only with another `let` binding; an `importBinding` likewise merges only with another
    `importBinding`; two real fields merge by OR-ing definition-ness, OR-ing hidden-ness,
    and meeting on the presence lattice (`#x? & #x` → definition + present; `x? & x!` →
    required; `_x? & _x` → hidden + present). The non-field kinds do not merge with any
    other class (`none`), matching the old enum's refusal to combine `letBinding` with
    any other class. -/
def mergeFieldClass (left right : FieldClass) : Option FieldClass :=
  match left, right with
  | .letBinding, .letBinding => some .letBinding
  | .letBinding, _ => none
  | _, .letBinding => none
  | .importBinding, .importBinding => some .importBinding
  | .importBinding, _ => none
  | _, .importBinding => none
  | .field ld lh lo, .field rd rh ro =>
      some (.field (ld || rd) (lh || rh) (lo.meet ro))

def fieldWithClass (fieldClass : FieldClass) (label : String) (value : Value) : Field :=
  ⟨label, fieldClass, value⟩

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

/-- SC-1b closing check for ONE closed clause (one closed conjunct's allowed-set). A field is
    admitted by the clause iff its label is one of the clause's declared field-labels, OR it
    matches one of the clause's CLOSING patterns. (The cross-cutting `ignoresClosedness`
    escape is checked once by the caller, not per clause.) The distinction from
    `applyPatternsClosednessWith`: only patterns a closed struct DECLARED close. An OPEN
    conjunct's pattern (absorbed into a closed meet result as a value-constraint) contributes
    NO clause, so it does not re-open the result — `#C & P & {z:9}` rejects `z` even though
    `P`'s `[string]` matches it. -/
def fieldAllowedByClauseWith
    (meetValue : Value -> Value -> Value)
    (clause : ClosedClause)
    (field : Field) : Bool :=
  clause.fieldLabels.contains (Field.label field)
    || clause.patterns.any fun labelPattern => fieldMatchesPatternWith meetValue labelPattern field

/-- A field is allowed by a CLAUSE CONJUNCTION (SC-1b) iff it ignores closedness, OR EVERY
    clause admits it. An empty clause list is open (admits all). This is the intersection of
    per-conjunct allowed-sets: a label must satisfy each closed conjunct independently, which
    a flat union of label-predicates cannot express. -/
def fieldAllowedByClausesWith
    (meetValue : Value -> Value -> Value)
    (clauses : List ClosedClause)
    (field : Field) : Bool :=
  Field.ignoresClosedness field
    || clauses.all (fun clause => fieldAllowedByClauseWith meetValue clause field)

def applyClausesWith
    (meetValue : Value -> Value -> Value)
    (clauses : List ClosedClause)
    (fields : List Field) : List Field :=
  if clauses.isEmpty then
    fields
  else
    fields.map fun field =>
      if fieldAllowedByClausesWith meetValue clauses field then
        field
      else
        markDisallowedField field

/-- The single normalized-struct meet (B2.4). Reproduces the legacy 12-arm matrix EXACTLY,
    emitting `struct` via `mkStruct`, by dispatching on which side carries a tail/patterns and
    preserving each legacy arm's field-merge ORDER and closedness application:

    * plain × plain (no tail, no patterns) → `mergeStructFieldsWith lf rf` + `applyStructClosedness`;
    * tail on the LEFT, plain RIGHT → `mergeStructFieldsWith lf rf`, left tail applied to extras;
    * tail on the RIGHT, plain LEFT → `mergeStructFieldsWith rf lf` (REVERSED, matching the legacy
      `struct × structTail` arm), right tail applied to extras;
    * tail on BOTH → `mergeStructFieldsWith lf rf`, meet the tails, apply BOTH to extras;
    * patterns on one side / both → the `mergeStructPattern(s)…` field+pattern fold, same orders.

    The cross-combination `tail-on-one-side × patterns-on-other` (and any tail+patterns mix) had
    NO legacy arm and wrongly bottomed; B2.5 flips it to a real unify via the final composition
    arm: the tail-bearing side is the merge base, the tails meet and constrain the other side's
    extras, and the patterns constrain every field (incl. tail-admitted extras). The unified
    `struct` co-represents both axes, so `{[string]: int} & {a: 5, ...}` → `{a: 5}` (cue-exact),
    not `.bottom`. -/
def mergeStructN
    (meetValue : Value -> Value -> Value)
    (leftFields : List Field) (leftOpenness : StructOpenness)
    (leftTail : Option Value) (leftPatterns : List (Value × Value))
    (leftClauses : List ClosedClause)
    (rightFields : List Field) (rightOpenness : StructOpenness)
    (rightTail : Option Value) (rightPatterns : List (Value × Value))
    (rightClauses : List ClosedClause) : Value :=
  -- SC-1/SC-1b: the meet of two structs is closed iff either conjunct is closed
  -- (`StructOpenness.meet`), and a field survives iff allowed by BOTH conjuncts. Each closed
  -- conjunct's allowed set is ONE clause (its declared fields + the patterns it closed with);
  -- an open conjunct contributes NO clause and admits everything. The result's allowed-set is
  -- the CONJUNCTION of the two clause lists — a field survives iff EVERY clause admits it.
  -- `bothClauses` (the concatenation) is carried forward verbatim, so a later meet against the
  -- result still honours each original conjunct's closedness independently. This is what the
  -- old flat-union `closingPatterns` store could not express: `#A:{[=~"^x"]} & #B:{[=~"^y"]}`
  -- must admit a label only if it matches `^x` AND `^y` (SC-1b), not either.
  let closedOpenness := StructOpenness.meet leftOpenness rightOpenness
  let bothClauses := leftClauses ++ rightClauses
  let applyBothClosedness (merged : List Field) : List Field :=
    applyClausesWith meetValue bothClauses merged
  -- SC-1e: finalize a meet that carried a `...` on at least one side. Closedness is monotone
  -- under meet, so a closed conjunct stays closed even against an open-`...` partner —
  -- `closedOpenness` (= `StructOpenness.meet`) already encodes this (`defClosed` dominates
  -- `defOpenViaTail`). When the meet is OPEN (every operand open), the `...` survives and no
  -- clause closes anything. When the meet is CLOSED, the partner's bare `...` is vacuous against
  -- the closed allowed-set: collapse to a no-tail closed struct carrying `bothClauses`; the extras
  -- the clauses forbid become `_|_` via `applyBothClosedness`, exactly as the no-tail control does.
  -- Shared by every tail-bearing arm so the carry rule lives in one place.
  let closeTailResult (mergedFields : List Field) (tail : Value)
      (patterns : List (Value × Value)) : Value :=
    if closedOpenness.isOpen then
      mkStruct mergedFields closedOpenness (some tail) patterns []
    else
      mkStruct (applyBothClosedness mergedFields) closedOpenness none patterns bothClauses
  match leftTail, leftPatterns, rightTail, rightPatterns with
  -- plain × plain
  | none, [], none, [] =>
      match mergeStructFieldsWith meetValue leftFields rightFields with
      | some merged =>
          mkStruct (applyBothClosedness merged) closedOpenness none [] bothClauses
      | none => .bottom
  -- tail on the LEFT, plain right (legacy structTail × struct). The plain right may be a closed
  -- `#Def` (no tail), so the meet can be closed — `closeTailResult` carries its clause (SC-1e).
  | some tail, [], none, [] =>
      match mergeStructFieldsWith meetValue leftFields rightFields with
      | some merged => closeTailResult (applyTailToExtrasWith meetValue leftFields tail merged) tail []
      | none => .bottom
  -- tail on the RIGHT, plain left (legacy struct × structTail — REVERSED field-merge order). The
  -- plain left may be a closed `#Def`, so the meet can be closed — `closeTailResult` carries it.
  | none, [], some tail, [] =>
      match mergeStructFieldsWith meetValue rightFields leftFields with
      | some merged => closeTailResult (applyTailToExtrasWith meetValue rightFields tail merged) tail []
      | none => .bottom
  -- tail on BOTH (legacy structTail × structTail). Both sides bear a tail ⇒ both open ⇒ the meet
  -- is open and `bothClauses = []`; routed through `closeTailResult` for uniformity (its closed
  -- branch is unreachable here, but the carry rule stays in one place).
  | some leftT, [], some rightT, [] =>
      match mergeStructFieldsWith meetValue leftFields rightFields with
      | some merged =>
          let tail := meetValue leftT rightT
          if isBottom tail then .bottom
          else
            closeTailResult
              (applyTailToExtrasWith meetValue leftFields leftT
                (applyTailToExtrasWith meetValue rightFields rightT merged))
              tail []
      | none => .bottom
  -- patterns on the LEFT, plain right (legacy structPattern(s) × struct): the pattern side is
  -- the merge-left, exactly as the legacy arms passed `patternFields` first regardless of order.
  -- SC-1: result openness = meet of BOTH sides (the plain side may be a closed `#Def`), and the
  -- closedness applies BOTH sides via the carried clauses. Left's patterns are applied as
  -- value-constraints; the closed allowed-set is the clause conjunction, so a plain-side closed
  -- def is not re-opened by an OPEN left's pattern (an open left contributes no clause).
  | none, (_ :: _), none, [] =>
      match mergeStructFieldsWith meetValue leftFields rightFields with
      | some merged =>
          mkStruct
            (applyBothClosedness
              (applyPatternsToFieldsWith meetValue leftPatterns merged))
            closedOpenness none leftPatterns bothClauses
      | none => .bottom
  -- patterns on the RIGHT, plain left (legacy struct × structPattern(s))
  | none, [], none, (_ :: _) =>
      match mergeStructFieldsWith meetValue rightFields leftFields with
      | some merged =>
          mkStruct
            (applyBothClosedness
              (applyPatternsToFieldsWith meetValue rightPatterns merged))
            closedOpenness none rightPatterns bothClauses
      | none => .bottom
  -- patterns on BOTH (legacy structPattern(s) × structPattern(s))
  | none, (_ :: _), none, (_ :: _) =>
      match mergeStructFieldsWith meetValue leftFields rightFields with
      | some merged =>
          mkStruct
            (applyBothClosedness
              (applyPatternsToFieldsWith meetValue rightPatterns
                (applyPatternsToFieldsWith meetValue leftPatterns merged)))
            closedOpenness none (leftPatterns ++ rightPatterns) bothClauses
      | none => .bottom
  -- tail-on-one-side × patterns-on-other, and any tail+patterns mix (B2.5). The legacy type
  -- could not co-represent a tail AND patterns, so these fell to `.bottom`; the unified `struct`
  -- carries both axes, so the merge composes them: the tail keeps the struct open and constrains
  -- the other side's extras, while the patterns constrain every field (incl. tail-admitted
  -- extras). The tail-bearing side is the merge base (its fields come first, matching cue); when
  -- both carry a tail the left is the base, as in the tail×tail arm.
  | _, _, _, _ =>
      let leftHasTail := leftTail.isSome
      let baseFields := if leftHasTail then leftFields else rightFields
      let otherFields := if leftHasTail then rightFields else leftFields
      match mergeStructFieldsWith meetValue baseFields otherFields with
      | none => .bottom
      | some merged =>
          -- meet the tails (one or both present), bottoming if the meet bottoms
          let mergedTail :=
            match leftTail, rightTail with
            | some lt, some rt => some (meetValue lt rt)
            | some lt, none => some lt
            | none, some rt => some rt
            | none, none => none
          match mergedTail with
          | some tail =>
              if isBottom tail then .bottom
              else
                let withLeftTail :=
                  match leftTail with
                  | some lt => applyTailToExtrasWith meetValue leftFields lt merged
                  | none => merged
                let withTails :=
                  match rightTail with
                  | some rt => applyTailToExtrasWith meetValue rightFields rt withLeftTail
                  | none => withLeftTail
                let allPatterns := leftPatterns ++ rightPatterns
                let withPatterns := applyPatternsToFieldsWith meetValue allPatterns withTails
                -- SC-1e: a closed operand (pattern- or field-closed) is not re-opened by the open
                -- partner's `...`; `closeTailResult` collapses to a closed no-tail result carrying
                -- `bothClauses` when the meet is closed, and keeps the open tail otherwise.
                closeTailResult withPatterns tail allPatterns
          -- unreachable: this arm is only entered with ≥1 tail (the no-tail cases are arms
          -- 1/5/6/7 above), so `mergedTail` is always `some`; `.bottom` is the total fallback.
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
def structHasOutputField (fields : List Field) : Bool :=
  fields.any (fun f => FieldClass.producesOutput (Field.fieldClass f))

/-- The non-output (hidden/definition/optional/let) fields — those that survive as
    selectable declarations when a struct becomes its embedded list. -/
def declFields (fields : List Field) : List Field :=
  fields.filter (fun f => !FieldClass.producesOutput (Field.fieldClass f))

/-- Whether a struct embedding a scalar-ish value collapses to that value (CUE: `{5}`→`5`).
    Collapses only when the struct has no output member AND no non-output decls — i.e. the
    collapse is LOSSLESS (there is no scalar carrier for selectable decls, unlike
    `.embeddedList`; a `{#a:1, 5}` keeping `.#a` selectable is out of scope, falls through to
    `meetCore` unchanged). `other` is a positive allow-list of fully-evaluated TERMINAL values:
    a closure/conj/unevaluated form stays inert (`meet closure (struct[])` is bottom, not the
    closure). Disjunctions are handled by the earlier `.disj` meet arms and never reach here. -/
def collapsesToScalarEmbed (fields : List Field) (other : Value) : Bool :=
  !structHasOutputField fields && declFields fields == [] &&
    (match other with
     | .prim _ => true
     | .kind _ => true
     | .notPrim _ => true
     | .stringRegex _ => true
     | .boundConstraint _ _ _ => true
     | _ => false)

/-- MEET-RESID-1: reduce the RIGHT operand of a `.structComp`-residual meet to the resolved
    `(fields, openness, deferredComps)` it contributes, or `none` when it is not a struct-shaped
    operand (a scalar/list/bound — a genuine struct-vs-nonstruct type error that must `.bottom`
    via the `meetCore` fall-through, NOT hold). A plain `.struct` contributes its fields and an
    empty deferred-comp list; another unresolved `.structComp` contributes its resolved fields AND
    its own deferred comps (the union held in the result). Tail/pattern-bearing structs are refused
    (`none`) — they are not the residual-merge shape and bottom honestly. The `.structComp`
    openness is a BARE `...` flag (no tail value), so it collapses to open/closed via `ofBool`. -/
def asResidualMergeOperand? : Value -> Option (List Field × StructOpenness × List Value)
  | .struct fields openness none [] _ => some (fields, openness, [])
  | .structComp fields comprehensions openness =>
      some (fields, StructOpenness.ofBool openness.isOpen, comprehensions)
  | _ => none

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
  -- MEET-RESID-1: an UNRESOLVED `.structComp` residual (a held comprehension whose dynamic
  -- key/`if`/`for` is non-concrete) must SURVIVE a meet against a struct, not bottom. cue holds
  -- `a & {x:2}` where `a` is a residual comprehension; `meetCore` bottomed it. The gate is
  -- STRUCTURAL: a `.structComp` is ALWAYS an unresolved residual whose `fields` are already
  -- conflict-free (a field conflict surfaces as `.bottom` at production, never a `.structComp` —
  -- see the MEET-RESID-1 soundness argument in plan.md). So merge the RESOLVED fields via the
  -- proven struct×struct path (`mergeStructN`): a genuine field conflict (`a:{x:1,for…} & {x:2}`)
  -- BOTTOMS there (NOT masked); otherwise re-wrap the merged struct as a `.structComp` carrying
  -- the still-deferred comprehensions, which the two-pass `.conj` re-eval retries to a fixpoint.
  -- A NON-struct `other` (`a & 5`) yields `none` from `asResidualMergeOperand?` and falls through
  -- to `meetCore` → `.bottom` (a real struct-vs-nonstruct type error, unchanged). These arms sit
  -- ABOVE the struct/embeddedList arms so a `.structComp` is never first swallowed by a
  -- `listLike`/`leftLike` catch (which would `meetCore`-bottom it). Symmetric in operand order.
  | .structComp lf lcomps lo, other =>
      match asResidualMergeOperand? other with
      | none => meetCore (.structComp lf lcomps lo) other
      | some (rf, ro, rcomps) =>
          match mergeStructN (meetWithFuel fuel)
                  lf (StructOpenness.ofBool lo.isOpen) none [] []
                  rf ro none [] [] with
          | .struct merged mo _ _ _ => .structComp merged (lcomps ++ rcomps) mo
          | collapsed => collapsed
  | value, .structComp rf rcomps ro =>
      match asResidualMergeOperand? value with
      | none => meetCore value (.structComp rf rcomps ro)
      | some (lf, lo, lcomps) =>
          match mergeStructN (meetWithFuel fuel)
                  lf lo none [] []
                  rf (StructOpenness.ofBool ro.isOpen) none [] [] with
          | .struct merged mo _ _ _ => .structComp merged (lcomps ++ rcomps) mo
          | collapsed => collapsed
  | .conj constraints, value => meetConjValueWith (meetWithFuel fuel) constraints value
  | value, .conj constraints => meetConjValueWith (meetWithFuel fuel) constraints value
  | .struct lf lo lt lp lClauses, .struct rf ro rt rp rClauses =>
      mergeStructN (meetWithFuel fuel) lf lo lt lp lClauses rf ro rt rp rClauses
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
      -- Spec rule `(v1,d1) & (v2,d2) = (v1&v2, d1&d2)`: cross the value sets, AND the
      -- default sets. `withDefaultConvention` makes a no-`*` operand contribute its whole
      -- set as defaults; `combineMark` (AND) keeps a result default iff both inputs were.
      -- The empty-intersection case (no surviving default) falls out automatically — every
      -- cross alternative is then regular, so `resolveDisjDefault?` stays ambiguous.
      let flatLeft := withDefaultConvention (flattenAlternatives leftAlternatives)
      let flatRight := withDefaultConvention (flattenAlternatives rightAlternatives)
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
      -- Unifying a disjunction with a non-disjunction value narrows each arm but leaves the
      -- mark untouched: the scalar carries no default set of its own, so a marked arm that
      -- survives stays the default (`(*"prod"|"dev") & string → *"prod"|"dev"`).
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
          | .struct fields _ none [] _ =>
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
          | .struct fields _ none [] _ =>
              if structHasOutputField fields then .bottom
              else
                match mergeStructFieldsWith (meetWithFuel fuel) (declFields fields) rightDecls with
                | some decls => .embeddedList rightItems rightTail decls
                | none => .bottom
          | _ => meetCore leftLike (.embeddedList rightItems rightTail rightDecls)
  -- A plain-struct-equivalent struct embeds a list; a tail/pattern-bearing struct has no
  -- list-embedding arm and falls through to `meetCore` → `.bottom`. A genuine struct ∩ scalar
  -- is a type conflict (CUE: `{} & 5`); the `{5}`→`5` scalar-embedding collapse lives in
  -- `meetEmbeddingsWithFuel` where the provenance is known, not here (an empty `{}` and the
  -- residual `[]`-decls of `{5}` are indistinguishable at meet time).
  | .struct fields _ none [] _, listLike =>
      match asListPair listLike with
      | some (items, tail) =>
          if structHasOutputField fields then .bottom
          else .embeddedList items tail (declFields fields)
      | none =>
          meetCore (mkStruct fields .regularOpen none []) listLike
  | listLike, .struct fields _ none [] _ =>
      match asListPair listLike with
      | some (items, tail) =>
          if structHasOutputField fields then .bottom
          else .embeddedList items tail (declFields fields)
      | none =>
          meetCore listLike (mkStruct fields .regularOpen none [])
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
