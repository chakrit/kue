import Kue.Lattice

namespace Kue

def closeValue : Value -> Value
  | .struct fields _ => .struct fields false
  | .structPattern fields labelPattern constraint _ =>
      .structPattern fields labelPattern constraint false
  | .structPatterns fields patterns _ => .structPatterns fields patterns false
  | value => value

def countRegularFields : List Field -> Nat
  | [] => 0
  | field :: fields =>
      let rest := countRegularFields fields
      if Field.fieldClass field == .regular then
        rest + 1
      else
        rest

def lenValue : Value -> Value
  | .prim (.string value) => .prim (.int (Int.ofNat value.utf8ByteSize))
  | .prim (.bytes value) => .prim (.int (Int.ofNat value.utf8ByteSize))
  | .kind .string => .builtinCall "len" [.kind .string]
  | .kind .bytes => .builtinCall "len" [.kind .bytes]
  | .list items => .prim (.int (Int.ofNat items.length))
  | .listTail items _ => .prim (.int (Int.ofNat items.length))
  | .struct fields _ => .prim (.int (Int.ofNat (countRegularFields fields)))
  | .structTail fields _ => .prim (.int (Int.ofNat (countRegularFields fields)))
  | .structPattern fields _ _ _ => .prim (.int (Int.ofNat (countRegularFields fields)))
  | .structPatterns fields _ _ => .prim (.int (Int.ofNat (countRegularFields fields)))
  | value => .builtinCall "len" [value]

def andValues (values : List Value) : Value :=
  values.foldl (fun current value => meet current value) .top

def orValues : List Value -> Value
  | [] => .builtinCall "or" [.list []]
  | value :: values => values.foldl (fun current next => join current next) value

def intBinaryBuiltinValue (name : String) (op : Int -> Int -> Int) (left right : Value) : Value :=
  match left, right with
  | .bottom, _ => .bottom
  | _, .bottom => .bottom
  | .bottomWith reasons, _ => .bottomWith reasons
  | _, .bottomWith reasons => .bottomWith reasons
  | .prim (.int leftInt), .prim (.int rightInt) =>
      if rightInt == 0 then
        .bottomWith [.divisionByZero]
      else
        .prim (.int (op leftInt rightInt))
  | left, right =>
      let leftAsInt := meet (.kind .int) left
      let rightAsInt := meet (.kind .int) right
      if containsBottom leftAsInt then
        leftAsInt
      else if containsBottom rightAsInt then
        rightAsInt
      else
        .builtinCall name [left, right]

def divValue (left right : Value) : Value :=
  intBinaryBuiltinValue "div" Int.ediv left right

def modValue (left right : Value) : Value :=
  intBinaryBuiltinValue "mod" Int.emod left right

def quoValue (left right : Value) : Value :=
  intBinaryBuiltinValue "quo" Int.tdiv left right

def remValue (left right : Value) : Value :=
  intBinaryBuiltinValue "rem" Int.tmod left right

/-- Byte index of the first occurrence of `needle` in `hay`, or `-1`.
    Mirrors Go's `strings.Index` (byte-based), as CUE's `strings.Index` does. -/
def stringByteIndex (hay needle : String) : Int := Id.run do
  let h := hay.toUTF8
  let n := needle.toUTF8
  if n.size == 0 then
    return 0
  if n.size > h.size then
    return -1
  for i in [0:h.size - n.size + 1] do
    let mut matched := true
    for j in [0:n.size] do
      if h[i + j]! != n[j]! then
        matched := false
    if matched then
      return Int.ofNat i
  return -1

/-- Whether `hay` contains `needle` as a (byte) substring. -/
def stringContains (hay needle : String) : Bool :=
  stringByteIndex hay needle != -1

/-- Non-overlapping count of `needle` in `hay`.
    Empty needle yields rune-count + 1, matching Go's `strings.Count`. -/
def stringCount (hay needle : String) : Nat := Id.run do
  if needle.isEmpty then
    return hay.toList.length + 1
  let h := hay.toUTF8
  let n := needle.toUTF8
  if n.size > h.size then
    return 0
  let mut total := 0
  let mut i := 0
  while i + n.size <= h.size do
    let mut matched := true
    for j in [0:n.size] do
      if h[i + j]! != n[j]! then
        matched := false
    if matched then
      total := total + 1
      i := i + n.size
    else
      i := i + 1
  return total

/-- Split `value` on `sep`; an empty separator splits into runes
    (CUE/Go semantics), keeping trailing empty fields. -/
def stringSplit (value sep : String) : List Value :=
  if sep.isEmpty then
    value.toList.map (fun c => .prim (.string (String.singleton c)))
  else
    (value.splitOn sep).map (fun piece => .prim (.string piece))

/-- Replace one occurrence per step until `fuel`/`remaining` runs out, then append
    the unconsumed tail. `remaining < 0` means "no count cap" (replace every match);
    `fuel` is a structural bound on the number of steps (one match consumes ≥ 1 byte
    of `rest`, so its UTF-8 size bounds the matches). -/
def stringReplaceLoop (fuel : Nat) (acc rest old new : String) (remaining : Int) : String :=
  match fuel with
  | 0 => acc ++ rest
  | fuel + 1 =>
      if remaining == 0 then
        acc ++ rest
      else
        let idx := stringByteIndex rest old
        if idx < 0 then
          acc ++ rest
        else
          let before := String.fromUTF8! (rest.toUTF8.extract 0 idx.toNat)
          let after := String.fromUTF8! (rest.toUTF8.extract (idx.toNat + old.utf8ByteSize) rest.utf8ByteSize)
          let nextRemaining := if remaining > 0 then remaining - 1 else remaining
          stringReplaceLoop fuel (acc ++ before ++ new) after old new nextRemaining

/-- Replace the first `count` non-overlapping occurrences of `old` with `new`
    in `value`; `count < 0` replaces all. Mirrors Go's `strings.Replace`. -/
def stringReplace (value old new : String) (count : Int) : String :=
  if count == 0 || old.isEmpty then
    value
  else
    stringReplaceLoop value.utf8ByteSize "" value old new count

/-- Concatenate `pieces` with `sep`; any non-string element yields bottom. -/
def stringJoin (pieces : List Value) (sep : String) : Value :=
  let rec collect : List Value -> Option (List String)
    | [] => some []
    | .prim (.string s) :: rest => (collect rest).map (s :: ·)
    | _ => none
  match collect pieces with
  | some parts => .prim (.string (String.intercalate sep parts))
  | none => .bottom

/-- `count` copies of `value` concatenated; negative count is an error (bottom). -/
def stringRepeat (value : String) (count : Int) : Value :=
  if count < 0 then
    .bottom
  else
    .prim (.string (String.join (List.replicate count.toNat value)))

/-- Split on runs of unicode whitespace, dropping empty fields (Go `strings.Fields`). -/
def stringFields (value : String) : List Value := Id.run do
  let mut fields := #[]
  let mut current : List Char := []
  for c in value.toList do
    if c.isWhitespace then
      if !current.isEmpty then
        fields := fields.push (.prim (.string (String.ofList current.reverse)))
        current := []
    else
      current := c :: current
  if !current.isEmpty then
    fields := fields.push (.prim (.string (String.ofList current.reverse)))
  return fields.toList

/-- Concatenate a list of lists; any non-list element yields bottom.
    Mirrors CUE's `list.Concat`. -/
def listConcat (lists : List Value) : Value :=
  let rec collect : List Value -> Option (List Value)
    | [] => some []
    | .list items :: rest => (collect rest).map (items ++ ·)
    | _ => none
  match collect lists with
  | some items => .list items
  | none => .bottom

/-- Maximum nesting depth of list values in `items`: how many `.list` levels can be
    peeled before only non-list elements remain. A structural upper bound on the
    fuel `list.FlattenN` needs to flatten fully. -/
def listNestingDepth : List Value -> Nat
  | [] => 0
  | item :: rest =>
      let here :=
        match item with
        | .list inner => listNestingDepth inner + 1
        | _ => 0
      max here (listNestingDepth rest)

/-- Flatten at most `fuel` nested levels of `items`; a non-list element is emitted
    as-is. Fuel decreases by one per level of descent, so the recursion is total. -/
def listFlattenFuel (fuel : Nat) (items : List Value) : List Value :=
  match fuel with
  | 0 => items
  | fuel + 1 =>
      items.flatMap fun item =>
        match item with
        | .list inner => listFlattenFuel fuel inner
        | other => [other]

/-- Flatten nested lists up to `depth` levels; `depth < 0` flattens fully.
    A non-list element is emitted as-is. Mirrors CUE's `list.FlattenN`. -/
def listFlattenN (items : List Value) (depth : Int) : List Value :=
  let fuel := if depth < 0 then listNestingDepth items else depth.toNat
  listFlattenFuel fuel items

/-- `count` copies of `items` concatenated; negative count is an error (bottom).
    Mirrors CUE's `list.Repeat`. -/
def listRepeat (items : List Value) (count : Int) : Value :=
  if count < 0 then
    .bottom
  else
    .list (List.flatten (List.replicate count.toNat items))

/-- Integer arithmetic sequence `[start, start+step, …)` bounded by `limit`,
    ascending when `step > 0`, descending when `step < 0`; `step == 0` is an
    error (bottom). Mirrors CUE's `list.Range` on integers. -/
def listRange (start limit step : Int) : Value :=
  if step == 0 then
    .bottom
  else
    let count : Int :=
      if step > 0 then
        if limit <= start then 0 else (limit - start + step - 1) / step
      else
        if start <= limit then 0 else (start - limit + (-step) - 1) / (-step)
    .list ((List.range count.toNat).map fun i => .prim (.int (start + step * Int.ofNat i)))

/-- Sub-slice `items[low:high]`; out-of-range or inverted bounds yield bottom.
    Mirrors CUE's `list.Slice`. -/
def listSlice (items : List Value) (low high : Int) : Value :=
  if low < 0 || high < 0 then
    .bottom
  else if high > Int.ofNat items.length || low > high then
    .bottom
  else
    .list ((items.drop low.toNat).take (high - low).toNat)

/-- First `count` elements; negative count yields bottom. Mirrors `list.Take`. -/
def listTake (items : List Value) (count : Int) : Value :=
  if count < 0 then .bottom else .list (items.take count.toNat)

/-- All but the first `count` elements; negative count yields bottom.
    Mirrors `list.Drop`. -/
def listDrop (items : List Value) (count : Int) : Value :=
  if count < 0 then .bottom else .list (items.drop count.toNat)

/-- Whether `items` contains a value equal to `needle` (structural `BEq`).
    Mirrors CUE's `list.Contains`. -/
def listContains (items : List Value) (needle : Value) : Bool :=
  items.any (· == needle)

/-- Sum of an integer list; a non-integer element yields bottom. The float
    domain is deferred (needs the shared decimal arithmetic in `Eval`).
    Mirrors CUE's `list.Sum` on integers (empty list ⇒ 0). -/
def listSumInt (items : List Value) : Value :=
  let rec go : List Value -> Option Int
    | [] => some 0
    | .prim (.int n) :: rest => (go rest).map (n + ·)
    | _ => none
  match go items with
  | some total => .prim (.int total)
  | none => .bottom

/-- Minimum of a non-empty integer list; empty list or a non-integer element
    yields bottom. Float domain deferred. Mirrors CUE's `list.Min`. -/
def listMinInt : List Value -> Value
  | [] => .bottom
  | .prim (.int first) :: rest =>
      let rec go : Int -> List Value -> Value
        | acc, [] => .prim (.int acc)
        | acc, .prim (.int n) :: rest => go (if n < acc then n else acc) rest
        | _, _ => .bottom
      go first rest
  | _ => .bottom

/-- Maximum of a non-empty integer list; empty list or a non-integer element
    yields bottom. Float domain deferred. Mirrors CUE's `list.Max`. -/
def listMaxInt : List Value -> Value
  | [] => .bottom
  | .prim (.int first) :: rest =>
      let rec go : Int -> List Value -> Value
        | acc, [] => .prim (.int acc)
        | acc, .prim (.int n) :: rest => go (if n > acc then n else acc) rest
        | _, _ => .bottom
      go first rest
  | _ => .bottom

/-- Whether an argument is a fully-evaluated concrete value (no kinds, refs, or
    unresolved calls). Used to decide a builtin dispatcher's fallback. -/
def isConcreteArg : Value -> Bool
  | .prim _ => true
  | .list _ => true
  | _ => false

/-- Shared fallback for every package builtin dispatcher (`strings.*`, `list.*`,
    and the upcoming `math.*`): a call that matched no known arm resolves to
    bottom when any argument is bottom or all arguments are concrete (a genuine
    CUE type error), and otherwise stays unresolved as a `.builtinCall` so a later
    evaluation pass can complete it once references resolve. -/
def unresolvedOrBottom (name : String) (args : List Value) : Value :=
  if args.any containsBottom then
    .bottom
  else if args.all isConcreteArg then
    .bottom
  else
    .builtinCall name args

/-- Dispatch a `list.*` builtin over already-evaluated arguments.
    Wrong argument shapes resolve to bottom (CUE error), per total-function design.
    Deferred (kept unresolved/not matched): `Avg`, float-domain `Sum`/`Min`/`Max`,
    `Sort`/`SortStable`/`SortStrings` (comparator-struct evaluation). -/
def evalListBuiltin : String -> List Value -> Value
  | "list.Concat", [.list lists] => listConcat lists
  | "list.FlattenN", [.list items, .prim (.int depth)] => .list (listFlattenN items depth)
  | "list.Repeat", [.list items, .prim (.int n)] => listRepeat items n
  | "list.Range", [.prim (.int start), .prim (.int limit), .prim (.int step)] =>
      listRange start limit step
  | "list.Slice", [.list items, .prim (.int low), .prim (.int high)] =>
      listSlice items low high
  | "list.Take", [.list items, .prim (.int n)] => listTake items n
  | "list.Drop", [.list items, .prim (.int n)] => listDrop items n
  | "list.Contains", [.list items, .prim p] => .prim (.bool (listContains items (.prim p)))
  | "list.Contains", [.list items, .list needle] => .prim (.bool (listContains items (.list needle)))
  | "list.Sum", [.list items] => listSumInt items
  | "list.Min", [.list items] => listMinInt items
  | "list.Max", [.list items] => listMaxInt items
  | name, args => unresolvedOrBottom name args

/-- Dispatch a `strings.*` builtin over already-evaluated arguments.
    Wrong argument shapes resolve to bottom (CUE error), per total-function design. -/
def evalStringsBuiltin : String -> List Value -> Value
  | "strings.Contains", [.prim (.string s), .prim (.string sub)] =>
      .prim (.bool (stringContains s sub))
  | "strings.HasPrefix", [.prim (.string s), .prim (.string pre)] =>
      .prim (.bool (s.startsWith pre))
  | "strings.HasSuffix", [.prim (.string s), .prim (.string suf)] =>
      .prim (.bool (s.endsWith suf))
  | "strings.Index", [.prim (.string s), .prim (.string sub)] =>
      .prim (.int (stringByteIndex s sub))
  | "strings.Count", [.prim (.string s), .prim (.string sub)] =>
      .prim (.int (Int.ofNat (stringCount s sub)))
  | "strings.Split", [.prim (.string s), .prim (.string sep)] =>
      .list (stringSplit s sep)
  | "strings.Join", [.list pieces, .prim (.string sep)] =>
      stringJoin pieces sep
  | "strings.Replace", [.prim (.string s), .prim (.string old), .prim (.string new), .prim (.int n)] =>
      .prim (.string (stringReplace s old new n))
  | "strings.Repeat", [.prim (.string s), .prim (.int n)] =>
      stringRepeat s n
  | "strings.TrimSpace", [.prim (.string s)] =>
      .prim (.string (String.ofList (s.toList.dropWhile (·.isWhitespace) |>.reverse.dropWhile (·.isWhitespace) |>.reverse)))
  | "strings.Fields", [.prim (.string s)] =>
      .list (stringFields s)
  | name, args => unresolvedOrBottom name args

def evalBuiltinCall : String -> List Value -> Value
  | "close", [value] => closeValue value
  | "len", [value] => lenValue value
  | "and", [.list values] => andValues values
  | "or", [.list values] => orValues values
  | "div", [left, right] => divValue left right
  | "mod", [left, right] => modValue left right
  | "quo", [left, right] => quoValue left right
  | "rem", [left, right] => remValue left right
  | name, args =>
      if name.startsWith "strings." then
        evalStringsBuiltin name args
      else if name.startsWith "list." then
        evalListBuiltin name args
      else
        .builtinCall name args

end Kue
