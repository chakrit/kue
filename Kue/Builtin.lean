import Kue.Lattice
import Kue.Regex
import Kue.Decimal
import Kue.Base64
import Kue.Json
import Kue.Yaml
import Kue.CaseTable

namespace Kue

def closeValue : Value -> Value
  -- A tail-bearing struct passes through unchanged (an explicit `...` keeps it open); every
  -- other struct closes (openness → `defClosed`, tail is `none` by coherence).
  | .struct fields .defOpenViaTail tail patterns closedClauses =>
      .struct fields .defOpenViaTail tail patterns closedClauses
  -- An ALREADY-closed struct is returned as-is: `close()` is idempotent and must not collapse
  -- a meet-result's per-conjunct clauses into a single self-clause (that would re-admit fields
  -- an individual conjunct rejects — SC-1b). `defClosed` always carries ≥1 clause.
  | s@(.struct _ .defClosed _ _ _) => s
  -- An OPEN (no-tail) struct closes: `mkStruct`'s default gives the single self-clause
  -- `{fieldLabels := fields.map .label, patterns := patterns.map .fst}`.
  | .struct fields .regularOpen _ patterns _ => mkStruct fields .defClosed none patterns
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
  | .prim (.bytes value) => .prim (.int (Int.ofNat value.size))
  | .kind .string => .builtinCall "len" [.kind .string]
  | .kind .bytes => .builtinCall "len" [.kind .bytes]
  | .list items => .prim (.int (Int.ofNat items.length))
  | .listTail items _ => .prim (.int (Int.ofNat items.length))
  | .struct fields _ _ _ _ => .prim (.int (Int.ofNat (countRegularFields fields)))
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

/-- Raw string pieces of `value` split on `sep`; an empty separator splits into runes
    (CUE/Go semantics), keeping trailing empty fields. -/
def stringSplitParts (value sep : String) : List String :=
  if sep.isEmpty then
    value.toList.map String.singleton
  else
    value.splitOn sep

/-- Split `value` on `sep`; an empty separator splits into runes
    (CUE/Go semantics), keeping trailing empty fields. -/
def stringSplit (value sep : String) : List Value :=
  (stringSplitParts value sep).map (fun piece => .prim (.string piece))

/-- `strings.SplitN`: split `value` on `sep`, capping at `n` pieces. `n < 0` is
    unbounded (= `Split`); `n == 0` yields the empty list; `n > 0` keeps the first
    `n - 1` pieces verbatim and rejoins the remainder (with `sep`) as the last piece.
    Mirrors Go's `strings.SplitN`, which CUE follows. -/
def stringSplitN (value sep : String) (n : Int) : List Value :=
  if n == 0 then
    []
  else if n < 0 then
    stringSplit value sep
  else
    let parts := stringSplitParts value sep
    let cap := n.toNat
    if parts.length <= cap then
      parts.map (fun piece => .prim (.string piece))
    else
      let head := parts.take (cap - 1)
      let tail := String.intercalate sep (parts.drop (cap - 1))
      (head ++ [tail]).map (fun piece => .prim (.string piece))

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

/-- `strings.Runes`: the string's Unicode code points, one INT per rune. A Lean `Char` is a
    Unicode scalar value, so multibyte and astral characters each yield a single element
    (their full code point) — never bytes or surrogate halves. -/
def stringRunes (value : String) : List Value :=
  value.toList.map (fun c => .prim (.int (Int.ofNat c.val.toNat)))

/-- Binary-search the `[lo, hi)` window of a `(src, dst)` table sorted ascending by `src`.
    Total: each recursive call strictly shrinks `hi - lo` (the measure), so it terminates on
    the window width regardless of the table contents — no `partial`. -/
def caseTableSearch (table : Array (UInt32 × UInt32)) (key : UInt32) (lo hi : Nat) : Option UInt32 :=
  if lo < hi then
    let mid := lo + (hi - lo) / 2
    let (src, dst) := table[mid]!
    if key == src then some dst
    else if key < src then caseTableSearch table key lo mid
    else caseTableSearch table key (mid + 1) hi
  else
    none
  termination_by hi - lo
  decreasing_by
    all_goals simp_wf
    all_goals omega

/-- Look up `key`'s mapped code point in a `(src, dst)` table sorted ascending by `src`,
    returning `dst` on a hit and `none` on a miss (the caller treats a miss as identity).
    The table is the single source of truth for both ASCII and non-ASCII case mapping. -/
def caseTableLookup (table : Array (UInt32 × UInt32)) (key : UInt32) : Option UInt32 :=
  caseTableSearch table key 0 table.size

/-- Unicode simple case mapping for a single rune via the oracle-derived BMP table; a rune
    with no table entry (no case, or outside the covered set) maps to itself. -/
def caseMapChar (table : Array (UInt32 × UInt32)) (c : Char) : Char :=
  match caseTableLookup table c.val with
  | some dst => Char.ofNat dst.toNat
  | none => c

/-- Unicode upper-case map over the oracle-derived BMP simple-mapping table
    (`CaseTable.upperEntries`). Covers ASCII and the full BMP cased-letter set; a rune
    absent from the table (no case, or a length-changing special case like German ß that
    CUE's simple mapping also leaves unchanged) passes through. Mirrors CUE's
    `strings.ToUpper` (Go `unicode.ToUpper` simple mapping). -/
def unicodeToUpper (value : String) : String :=
  String.ofList (value.toList.map (caseMapChar CaseTable.upperEntries))

/-- Unicode lower-case map over `CaseTable.lowerEntries`; same coverage and passthrough
    rule as `unicodeToUpper`. Mirrors CUE's `strings.ToLower`. -/
def unicodeToLower (value : String) : String :=
  String.ofList (value.toList.map (caseMapChar CaseTable.lowerEntries))

/-- ASCII whitespace word-boundary predicate for `asciiToTitle`. CUE's `strings.ToTitle`
    capitalizes the first character of each whitespace-delimited word (separator =
    `unicode.IsSpace`), NOT after every non-letter — `-`, `.`, `_`, digits do NOT start a
    word. This covers the six ASCII whitespace runes (`\t \n \v \f \r` and space); non-ASCII
    whitespace (e.g. NBSP) is treated as a non-separator — the deferral boundary. -/
def asciiTitleSeparator (c : Char) : Bool :=
  c == ' ' || c == '\t' || c == '\n' || c == '\r'
    || c == Char.ofNat 0x0b || c == Char.ofNat 0x0c

/-- Title-case the first ASCII letter of each whitespace-delimited word; the first
    character of the string also starts a word. Non-ASCII runes pass through unchanged
    (`Char.toUpper` is ASCII-only) and never start a word. Mirrors CUE's `strings.ToTitle`
    on ASCII — per-word capitalization, NOT "upper-case every letter". -/
def asciiToTitle (value : String) : String := Id.run do
  let mut out : List Char := []
  let mut prevSep := true
  for c in value.toList do
    if prevSep then
      out := c.toUpper :: out
    else
      out := c :: out
    prevSep := asciiTitleSeparator c
  return String.ofList out.reverse

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

/-- Element count of the integer arithmetic sequence `[start, start+step, …)`
    bounded by `limit` (ceiling division of the span by the step magnitude),
    ascending when `step > 0`, descending when `step < 0`. Assumes `step ≠ 0`.
    Shared by the integer and (scaled-to-common-denominator) decimal `list.Range`. -/
def rangeCount (start limit step : Int) : Int :=
  if step > 0 then
    if limit <= start then 0 else (limit - start + step - 1) / step
  else
    if start <= limit then 0 else (start - limit + (-step) - 1) / (-step)

/-- Integer arithmetic sequence `[start, start+step, …)` bounded by `limit`,
    ascending when `step > 0`, descending when `step < 0`; `step == 0` is an
    error (bottom). Mirrors CUE's `list.Range` on integers. -/
def listRange (start limit step : Int) : Value :=
  if step == 0 then
    .bottom
  else
    let count := rangeCount start limit step
    .list ((List.range count.toNat).map fun i => .prim (.int (start + step * Int.ofNat i)))

/-- Decimal arithmetic sequence `[start, start+step, …)` bounded by `limit`,
    ascending when `step > 0`, descending when `step < 0`; `step == 0` ⇒ bottom.
    Operands are scaled to a common denominator so the count reduces to the integer
    `list.Range` formula; each element collapses an integral value back to int (CUE:
    `list.Range(0.0,2.0,0.5) = [0,0.5,1,1.5]`). Mirrors CUE's `list.Range` on floats. -/
def listRangeDecimal (start limit step : DecimalValue) : Value :=
  let scale := maxNat (maxNat start.scale limit.scale) step.scale
  let s := scaleDecimalNumerator scale start
  let l := scaleDecimalNumerator scale limit
  let st := scaleDecimalNumerator scale step
  if st == 0 then
    .bottom
  else
    let count := rangeCount s l st
    .list ((List.range count.toNat).map fun i =>
      collapseDecimalToValue { numerator := s + st * Int.ofNat i, scale := scale })

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

/-- Lexicographic `≤` on UTF-8 byte sequences — the ordering Go's `sort.Strings`
    (hence CUE's `list.SortStrings`) uses. For valid UTF-8 this coincides with
    Unicode codepoint order, so `"Z" < "a" < "é"`. -/
def byteSeqLe : List UInt8 -> List UInt8 -> Bool
  | [], _ => true
  | _ :: _, [] => false
  | a :: as, b :: bs =>
      if a < b then true
      else if b < a then false
      else byteSeqLe as bs

/-- Sort a list of strings ascending by UTF-8 byte order; any non-string element
    yields bottom. Uses the total, stable `List.mergeSort` with a byte-lexicographic
    `≤`. Mirrors CUE's `list.SortStrings`. -/
def listSortStrings (items : List Value) : Value :=
  let rec collect : List Value -> Option (List String)
    | [] => some []
    | .prim (.string s) :: rest => (collect rest).map (s :: ·)
    | _ => none
  match collect items with
  | some strings =>
      let sorted := strings.mergeSort fun a b => byteSeqLe a.toUTF8.toList b.toUTF8.toList
      .list (sorted.map (fun s => .prim (.string s)))
  | none => .bottom

/-- Collect a numeric list as exact decimals; any non-numeric element ⇒ `none`.
    Shared by the float-domain `Sum`/`Min`/`Max`/`Avg` arms. -/
def listToDecimals : List Value -> Option (List DecimalValue)
  | [] => some []
  | .prim p :: rest =>
      match decimalFromPrim? p with
      | some d => (listToDecimals rest).map (d :: ·)
      | none => none
  | _ => none

/-- Whether every element of a numeric list is an integer (`.int`). The all-int
    fast path renders `Sum`/`Min`/`Max` as plain ints; a `.float` element promotes
    the whole computation to the decimal path, then collapses integral results. -/
def listAllInts (items : List Value) : Bool :=
  items.all fun item => match item with
    | .prim (.int _) => true
    | _ => false

/-- Reverse the elements of `items`. Mirrors CUE's `list.Reverse`. -/
def listReverse (items : List Value) : Value :=
  .list items.reverse

/-- Byte index of the LAST occurrence of `needle` in `hay`, or `-1`. An empty
    needle yields the UTF-8 byte length (Go's `strings.LastIndex`, which CUE follows).
    Forward scan recording the highest match start, so it stays a bounded `for` (total). -/
def stringLastByteIndex (hay needle : String) : Int := Id.run do
  let h := hay.toUTF8
  let n := needle.toUTF8
  if n.size == 0 then
    return Int.ofNat h.size
  if n.size > h.size then
    return -1
  let mut last : Int := -1
  for i in [0:h.size - n.size + 1] do
    let mut matched := true
    for j in [0:n.size] do
      if h[i + j]! != n[j]! then
        matched := false
    if matched then
      last := Int.ofNat i
  return last

/-- Three-way lexicographic comparison of UTF-8 byte sequences: `-1`, `0`, or `1`.
    Mirrors Go's `strings.Compare`, which CUE's `strings.Compare` follows. -/
def byteSeqCompare : List UInt8 -> List UInt8 -> Int
  | [], [] => 0
  | [], _ :: _ => -1
  | _ :: _, [] => 1
  | a :: xs, b :: ys =>
      if a < b then -1
      else if b < a then 1
      else byteSeqCompare xs ys

/-- `strings.Compare(a, b)`: byte-lexicographic `-1`/`0`/`1`. -/
def stringCompare (a b : String) : Int :=
  byteSeqCompare a.toUTF8.toList b.toUTF8.toList

/-- Drop leading runes of `s` that are members of the rune SET `cutset`
    (Go/CUE `strings.TrimLeft` — cutset is a set of code points, not a prefix). -/
def stringTrimLeft (s cutset : String) : String :=
  String.ofList (s.toList.dropWhile (fun c => cutset.toList.contains c))

/-- Drop trailing runes of `s` that are members of the rune set `cutset`. -/
def stringTrimRight (s cutset : String) : String :=
  String.ofList (s.toList.reverse.dropWhile (fun c => cutset.toList.contains c)).reverse

/-- Drop leading and trailing runes of `s` in the rune set `cutset`
    (Go/CUE `strings.Trim`). -/
def stringTrim (s cutset : String) : String :=
  stringTrimRight (stringTrimLeft s cutset) cutset

/-- Remove `pre` from the front of `s` iff present, else return `s` unchanged
    (Go/CUE `strings.TrimPrefix` — a single fixed affix, not a cutset). -/
def stringTrimPrefix (s pre : String) : String :=
  if s.startsWith pre then String.ofList (s.toList.drop pre.length) else s

/-- Remove `suf` from the end of `s` iff present, else return `s` unchanged
    (Go/CUE `strings.TrimSuffix`). -/
def stringTrimSuffix (s suf : String) : String :=
  if s.endsWith suf then String.ofList (s.toList.take (s.length - suf.length)) else s

/-- `strings.SliceRunes(s, lo, hi)`: the half-open `[lo, hi)` window of `s` indexed by
    RUNE (Unicode scalar), not byte — a `Char` is a scalar, so multibyte/astral runes are
    single units. Negative bounds, `hi` past the rune count, or `lo > hi` are errors
    (bottom), matching CUE (`index out of range`). -/
def stringSliceRunes (s : String) (lo hi : Int) : Value :=
  let runes := s.toList
  if lo < 0 || hi < 0 then
    .bottom
  else if hi > Int.ofNat runes.length || lo > hi then
    .bottom
  else
    .prim (.string (String.ofList ((runes.drop lo.toNat).take (hi - lo).toNat)))

/-- Sum of a numeric list. All-int ⇒ exact int (empty list ⇒ 0). Any `.float`
    element promotes to exact decimal accumulation, collapsing an integral result
    back to int (CUE: `list.Sum([1.0,2.0,3.0]) = 6`). A non-numeric element ⇒
    bottom. Mirrors CUE's `list.Sum`. -/
def listSum (items : List Value) : Value :=
  if listAllInts items then
    let total := items.foldl (fun acc item =>
      match item with
      | .prim (.int n) => acc + n
      | _ => acc) 0
    .prim (.int total)
  else
    match listToDecimals items with
    | some decimals =>
        let total := decimals.foldl addDecimalValues { numerator := 0, scale := 0 }
        collapseDecimalToValue total
    | none => .bottom

/-- Minimum of a non-empty numeric list; empty list or a non-numeric element ⇒
    bottom. All-int stays int; a `.float` element promotes to the decimal compare
    path, collapsing the chosen element (CUE: `list.Min([3.0,1.0,2.0]) = 1`).
    Mirrors CUE's `list.Min`. -/
def listMin (items : List Value) : Value :=
  match listToDecimals items with
  | some (first :: rest) =>
      let best := rest.foldl (fun acc d => if decimalLtValues d acc then d else acc) first
      collapseDecimalToValue best
  | _ => .bottom

/-- Maximum of a non-empty numeric list; empty list or a non-numeric element ⇒
    bottom. All-int stays int; a `.float` element promotes to the decimal compare
    path, collapsing the chosen element. Mirrors CUE's `list.Max`. -/
def listMax (items : List Value) : Value :=
  match listToDecimals items with
  | some (first :: rest) =>
      let best := rest.foldl (fun acc d => if decimalLtValues acc d then d else acc) first
      collapseDecimalToValue best
  | _ => .bottom

/-- Exact-rational mean of a numeric list; empty list or a non-numeric element ⇒
    bottom. Sums the elements as exact decimals and divides by the count: integral
    means collapse to int (`list.Avg([1,2,3]) = 2`), else a 34-sig-digit float
    (`list.Avg([1,1,2]) = 1.333…333`). Mirrors CUE's `list.Avg`. -/
def listAvg (items : List Value) : Value :=
  match listToDecimals items with
  | some decimals =>
      let total := decimals.foldl addDecimalValues { numerator := 0, scale := 0 }
      match avgDecimalValue? total decimals.length with
      | some value => value
      | none => .bottom
  | none => .bottom

/-- Whether an argument is a fully-evaluated concrete value (no kinds, refs, or
    unresolved calls). Used to decide a builtin dispatcher's fallback. -/
def isConcreteArg : Value -> Bool
  | .prim _ => true
  | .list _ => true
  | _ => false

/-- Whether a value is still an unresolved reference-like form that a later evaluation
    pass might complete (so a builtin should defer rather than bottom). Distinguished
    from a genuinely-incomplete concrete shape such as `{a: int}`, which is a CUE error. -/
def isPendingArg : Value -> Bool
  | .ref _ => true
  | .refId _ => true
  | .selector _ _ => true
  | .index _ _ => true
  | .builtinCall _ _ => true
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
    Deferred (kept unresolved/not matched): `Sort`/`SortStable`
    (comparator-struct evaluation). -/
def evalListBuiltin : String -> List Value -> Value
  | "list.Concat", [.list lists] => listConcat lists
  | "list.FlattenN", [.list items, .prim (.int depth)] => .list (listFlattenN items depth)
  | "list.Repeat", [.list items, .prim (.int n)] => listRepeat items n
  | "list.Range", [.prim (.int start), .prim (.int limit), .prim (.int step)] =>
      listRange start limit step
  | "list.Range", [.prim start, .prim limit, .prim step] =>
      match decimalFromPrim? start, decimalFromPrim? limit, decimalFromPrim? step with
      | some start, some limit, some step => listRangeDecimal start limit step
      | _, _, _ => .bottom
  | "list.Slice", [.list items, .prim (.int low), .prim (.int high)] =>
      listSlice items low high
  | "list.Take", [.list items, .prim (.int n)] => listTake items n
  | "list.Drop", [.list items, .prim (.int n)] => listDrop items n
  | "list.Contains", [.list items, .prim p] => .prim (.bool (listContains items (.prim p)))
  | "list.Contains", [.list items, .list needle] => .prim (.bool (listContains items (.list needle)))
  | "list.Sum", [.list items] => listSum items
  | "list.Min", [.list items] => listMin items
  | "list.Max", [.list items] => listMax items
  | "list.Avg", [.list items] => listAvg items
  | "list.SortStrings", [.list items] => listSortStrings items
  | "list.Reverse", [.list items] => listReverse items
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
  | "strings.LastIndex", [.prim (.string s), .prim (.string sub)] =>
      .prim (.int (stringLastByteIndex s sub))
  | "strings.Compare", [.prim (.string a), .prim (.string b)] =>
      .prim (.int (stringCompare a b))
  | "strings.Trim", [.prim (.string s), .prim (.string cutset)] =>
      .prim (.string (stringTrim s cutset))
  | "strings.TrimLeft", [.prim (.string s), .prim (.string cutset)] =>
      .prim (.string (stringTrimLeft s cutset))
  | "strings.TrimRight", [.prim (.string s), .prim (.string cutset)] =>
      .prim (.string (stringTrimRight s cutset))
  | "strings.TrimPrefix", [.prim (.string s), .prim (.string pre)] =>
      .prim (.string (stringTrimPrefix s pre))
  | "strings.TrimSuffix", [.prim (.string s), .prim (.string suf)] =>
      .prim (.string (stringTrimSuffix s suf))
  | "strings.Count", [.prim (.string s), .prim (.string sub)] =>
      .prim (.int (Int.ofNat (stringCount s sub)))
  | "strings.Split", [.prim (.string s), .prim (.string sep)] =>
      .list (stringSplit s sep)
  | "strings.SplitN", [.prim (.string s), .prim (.string sep), .prim (.int n)] =>
      .list (stringSplitN s sep n)
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
  | "strings.Runes", [.prim (.string s)] =>
      .list (stringRunes s)
  | "strings.ToUpper", [.prim (.string s)] =>
      .prim (.string (unicodeToUpper s))
  | "strings.ToLower", [.prim (.string s)] =>
      .prim (.string (unicodeToLower s))
  | "strings.ToTitle", [.prim (.string s)] =>
      .prim (.string (asciiToTitle s))
  | "strings.SliceRunes", [.prim (.string s), .prim (.int lo), .prim (.int hi)] =>
      stringSliceRunes s lo hi
  | name, args => unresolvedOrBottom name args

/-- Absolute value, preserving the numeric domain: int stays int, float stays float.
    Mirrors CUE's `math.Abs` (int → int, float → float). -/
def mathAbs : Prim -> Value
  | .int value => .prim (.int value.natAbs)
  | .float value _ =>
      let absValue := { value with numerator := value.numerator.natAbs }
      .prim (mkFloatText (formatFiniteDecimal absValue true))
  | _ => .bottom

/-- Whether `value` is an integer multiple of `divisor`; a zero divisor is an
    error (bottom), mirroring CUE's `math.MultipleOf` division-by-zero. -/
def mathMultipleOf (value divisor : Int) : Value :=
  if divisor == 0 then
    .bottomWith [.divisionByZero]
  else
    .prim (.bool (value % divisor == 0))

/-- `math.Mod(x, y)`: the floating-point remainder `x - trunc(x/y)·y` — Go `math.Mod`
    semantics, where the result takes the SIGN OF THE DIVIDEND. Computed EXACTLY in
    decimal (scale to a common denominator, truncated-toward-zero integer quotient),
    so on finite decimals the remainder is exact: `Mod(5.5, 2.1) = 1.3` where CUE's
    float64 emits the artifact `1.2999999999999998` (Kue is exact and more precise —
    same posture as `math.Sqrt`; see `cue-divergences.md`). An integral result
    collapses to `int` (`Mod(7, 2.5) = 2`). A zero divisor is an error (bottom); CUE
    errors (`NaN`). A non-numeric argument is bottom. -/
def mathMod (dividend divisor : Prim) : Value :=
  match decimalFromPrim? dividend, decimalFromPrim? divisor with
  | some x, some y =>
      let scale := maxNat x.scale y.scale
      let xn := scaleDecimalNumerator scale x
      let yn := scaleDecimalNumerator scale y
      if yn == 0 then
        .bottom
      else
        collapseDecimalToValue { numerator := xn - Int.tdiv xn yn * yn, scale := scale }
  | _, _ => .bottom

/-- `math.Signbit(x)` — true iff `x` is negative. CUE normalizes a `-0.0` literal to
    `0.0` at parse, so `Signbit(-0.0) = false`; a negative zero has numerator `0` here
    too, so the `numerator < 0` test agrees. A non-numeric argument is bottom. -/
def mathSignbit (value : Prim) : Value :=
  match decimalFromPrim? value with
  | some d => .prim (.bool (d.numerator < 0))
  | none => .bottom

/-- Exact decimal `base^exponent` for a NON-NEGATIVE integer `exponent`, by repeated
    exact multiplication (`mulDecimalValues`: numerators multiply, scales add). Structural
    on `exponent`, hence total. `base^0 = 1` (scale 0). This is the only sound power
    domain Kue computes WITHOUT a decimal-pow/Float bridge — a non-negative integer
    exponent keeps the result a finite base-10 rational, exactly representable. -/
def decimalPowNat (base : DecimalValue) : Nat -> DecimalValue
  | 0 => { numerator := 1, scale := 0 }
  | exponent + 1 => mulDecimalValues base (decimalPowNat base exponent)

/-- Reciprocal of a non-zero decimal `p = pn / 10^ps`, as an exact-rational `Value`:
    `1/p = 10^ps / pn`. Collapses to `int` when whole (`Pow(1,-5) = 1`), renders the
    exact terminating expansion when finite (`Pow(2,-3) = 0.125` — trimmed; `cue` pads
    to 34 digits, a recorded display divergence), else 34 significant digits round-half-up
    via the shared division renderer. `pn = 0` (reciprocal of zero) is unreachable here —
    the caller bottoms `Pow(0, neg)` before this — and yields `.bottom` defensively. -/
def reciprocalDecimalToValue (p : DecimalValue) : Value :=
  let num := Int.ofNat (evalPow10 p.scale)
  if p.numerator == 0 then
    .bottom
  else if num % p.numerator == 0 then
    .prim (.int (num / p.numerator))
  else
    match divideDecimalRational? num p.numerator with
    | some text => .prim (mkFloatText text)
    | none => .bottom

/-- Exact-decimal square root over a SIGNED decimal: non-negative → `decimalSqrt`
    (34 significant digits, perfect squares collapsed to `int`); negative → a
    real-domain error, so Kue BOTTOMS (`cue` emits the float artifact `NaN` — Kue
    does not manufacture `NaN`; see `cue-divergences.md`). Shared by `math.Sqrt`
    and `Pow(·, ½)` so both stay self-consistent. -/
def decimalSqrtSigned (value : DecimalValue) : Value :=
  if value.numerator < 0 then .bottom
  else decimalSqrt value

/-- `math.Sqrt(value)` — `none` when the argument is non-numeric (caller defers). -/
def mathSqrt? (value : Prim) : Option Value :=
  (decimalFromPrim? value).map decimalSqrtSigned

/-- Is the trimmed exponent exactly `½`? `num / 10^scale = 1/2 ⇔ 2·num = 10^scale`,
    so `0.5`, `0.50`, … all qualify regardless of how the literal was written. -/
def isHalfExponent (exponent : DecimalValue) : Bool :=
  2 * exponent.numerator == Int.ofNat (evalPow10 exponent.scale)

/-- `math.Pow(base, exponent)` over the domain Kue computes EXACTLY: a non-negative
    integer exponent (whether typed `int` like `3` or a whole-valued `float` like
    `3.0` — `cue` treats `Pow(3, 2.0) = 9`), by exact repeated decimal multiplication,
    collapsing an integral value back to `int` (`Pow(2,10) = 1024`, `Pow(1.5,3) =
    3.375`, `Pow(-2,3) = -8`); plus the `½` exponent, routed through `decimalSqrt`
    for self-consistency with `math.Sqrt` (`Pow(2, 0.5) = 1.414…698`, `Pow(4, 0.5) =
    2`). `Pow(0, 0)` is a `cue` error (bottom). `Pow(neg, ½)` is out of the real
    domain (complex) — bottom (`cue` errors `invalid operation`). `none` signals
    "outside the computed domain" (a general negative/fractional exponent — `cue`'s
    apd 34-digit decimal `Pow`/`Infinity`, deferred to `BI-2-residual`'s exp/ln
    increment); the caller leaves such calls bottom rather than emit a wrong value. -/
def mathPow? (base exponent : Prim) : Option Value :=
  match decimalFromPrim? base, decimalFromPrim? exponent with
  | some base, some exponent =>
      if isHalfExponent exponent then
        -- `Pow(x, ½) = √x` — routed through the same decimal sqrt as `math.Sqrt`
        -- (exact, self-consistent), NOT the general exp/ln path.
        some (decimalSqrtSigned base)
      else
        -- `trimDecimalZerosWith` reduces `3.0` to scale 0; a residual non-zero scale
        -- is a genuine fraction (`0.25`, `1.5`, `0.333…`). Split the domain:
        let exp := trimDecimalZerosWith exponent.numerator exponent.scale
        if exp.scale == 0 then
          -- Integer exponent.
          if exp.numerator == 0 then
            -- `Pow(x, 0) = 1`, except `Pow(0, 0)` — `cue` errors `invalid operation`.
            if base.numerator == 0 then some .bottom
            else some (.prim (.int 1))
          else if exp.numerator > 0 then
            -- Non-negative integer exponent — exact repeated decimal multiplication.
            some (collapseDecimalToValue (decimalPowNat base exp.numerator.toNat))
          else
            -- Negative integer exponent: `x^(-n) = 1 / x^n`, an exact rational.
            -- `Pow(0, neg)` is a division by zero (`cue` → `Infinity`); Kue bottoms.
            if base.numerator == 0 then some .bottom
            else some (reciprocalDecimalToValue (decimalPowNat base (-exp.numerator).toNat))
        else
          -- Genuine non-integer fractional exponent: `x^y = exp(y · ln x)` in decimal.
          if base.numerator > 0 then
            some (decimalPowGeneral base exp)
          else if base.numerator == 0 then
            -- `Pow(0, positive) = 0`; `Pow(0, negative)` is `Infinity` in `cue` —
            -- Kue bottoms (no `Infinity`). The ½ case never reaches here.
            if exp.numerator > 0 then some (.prim (.int 0)) else some .bottom
          else
            -- Negative base, non-integer exponent: out of the real domain (complex).
            -- `cue` errors `invalid operation`; Kue bottoms.
            some .bottom
  | _, _ => none

/-- Rounding mode for the `math.Floor`/`Ceil`/`Round`/`Trunc` family: each maps a
    finite decimal to the integer part chosen by its mode. -/
inductive RoundMode where
  | floor
  | ceil
  | round
  | trunc
deriving Repr, BEq

/-- Integer part of `value` under `mode`. `divisor = 10^scale`, so an integer
    input (`scale = 0`, `divisor = 1`) is returned unchanged. -/
def roundDecimalToInt (mode : RoundMode) (value : DecimalValue) : Int :=
  let divisor := Int.ofNat (evalPow10 value.scale)
  match mode with
  | .floor => Int.fdiv value.numerator divisor
  | .ceil => -(Int.fdiv (-value.numerator) divisor)
  | .trunc => Int.tdiv value.numerator divisor
  | .round =>
      let magnitude := (value.numerator.natAbs + (evalPow10 value.scale) / 2) / (evalPow10 value.scale)
      if value.numerator < 0 then -(Int.ofNat magnitude) else Int.ofNat magnitude

/-- Round a numeric argument to an integer under `mode`. An int passes through;
    a float is parsed to an exact decimal first. Mirrors CUE, where
    `math.Floor`/`Ceil`/`Round`/`Trunc` return an integer. -/
def mathRound (mode : RoundMode) : Prim -> Value
  | .int value => .prim (.int value)
  | .float value _ => .prim (.int (roundDecimalToInt mode value))
  | _ => .bottom

/-- Dispatch a `math.*` builtin over already-evaluated arguments.
    Wrong argument shapes resolve to bottom (CUE error), per total-function design.

    `math.Sqrt` and `math.Pow` are computed in EXACT DECIMAL (Kue is exact-rational by
    design — no `Float`/`NaN`/`Infinity`). `math.Sqrt` returns `decimalSqrt` (34 significant
    digits, perfect squares collapsed to `int`); a negative input BOTTOMS (real-domain error,
    not `NaN`). `math.Pow` covers a non-negative integer exponent (exact repeated decimal
    multiplication) and the `½` exponent (routed through `decimalSqrt`, so `Pow(x, ½)` and
    `Sqrt(x)` agree); outside that (`mathPow?` ⇒ `none`) it falls through to bottom rather than
    emit a wrong value. DEFERRED (`BI-2-residual` exp/ln increment, see `cue-spec-gaps.md`): a
    GENERAL negative/fractional exponent (needs `decimalExp`/`decimalLn` to 34 digits; `cue`
    uses apd, and `Pow(0, neg) = Infinity` — Kue would bottom). Kue's decimal `Sqrt` diverges
    from `cue`'s float64 `Sqrt` (Kue is more precise and self-consistent with `Pow`; `cue`'s
    `Sqrt ≠ Pow(·, ½)` — see `cue-divergences.md`). -/
def evalMathBuiltin : String -> List Value -> Value
  | "math.Abs", [.prim p] => mathAbs p
  | "math.MultipleOf", [.prim (.int value), .prim (.int divisor)] =>
      mathMultipleOf value divisor
  | "math.Mod", [.prim dividend, .prim divisor] => mathMod dividend divisor
  | "math.Signbit", [.prim value] => mathSignbit value
  | "math.Floor", [.prim p] => mathRound .floor p
  | "math.Ceil", [.prim p] => mathRound .ceil p
  | "math.Round", [.prim p] => mathRound .round p
  | "math.Trunc", [.prim p] => mathRound .trunc p
  | "math.Sqrt", [.prim value] =>
      match mathSqrt? value with
      | some result => result
      | none => unresolvedOrBottom "math.Sqrt" [.prim value]
  | "math.Pow", [.prim base, .prim exponent] =>
      match mathPow? base exponent with
      | some value => value
      | none => unresolvedOrBottom "math.Pow" [.prim base, .prim exponent]
  | name, args => unresolvedOrBottom name args

/-- Dispatch a `base64.*` builtin over already-evaluated arguments. `Encode`'s first
    argument is the encoding selector: only `null` (standard padded base64) is
    supported — any other concrete value is bottom (`cue` errors with "unsupported
    encoding"). The payload is a string or bytes value, encoded over its UTF-8 bytes.
    Deferred: non-null encodings, `base64.Decode` (Kue has no error/bytes-result path
    for malformed input yet). -/
def evalBase64Builtin : String -> List Value -> Value
  | "base64.Encode", [.prim .null, .prim (.string s)] =>
      .prim (.string (base64Encode s.toUTF8.toList))
  | "base64.Encode", [.prim .null, .prim (.bytes b)] =>
      .prim (.string (base64Encode b.toList))
  | name, args => unresolvedOrBottom name args

/-- Dispatch a `json.*` builtin over already-evaluated arguments. `Marshal` manifests
    its argument and serializes the result to compact JSON; an incomplete or
    contradictory value is bottom (`cue` errors). Deferred: `json.MarshalStream`,
    `json.Indent`, `json.Unmarshal`, `json.Validate` (need multi-doc, pretty-printing,
    or parsing Kue does not yet model). -/
def evalJsonBuiltin : String -> List Value -> Value
  | "json.Marshal", [value] =>
      match valueToJson value with
      | .ok text => .prim (.string text)
      | .error _ =>
          if isPendingArg value then .builtinCall "json.Marshal" [value]
          else .bottom
  | name, args => unresolvedOrBottom name args

/-- Dispatch a `yaml.*` builtin over already-evaluated arguments. `Marshal` manifests
    its argument and serializes it to a YAML document (with the trailing newline `cue`
    emits); an incomplete or contradictory value is bottom, an unresolved ref form is
    preserved. Deferred: `yaml.MarshalStream` (multi-doc `---`), `yaml.Unmarshal`,
    `yaml.Validate`, `yaml.ValidatePartial`. -/
def evalYamlBuiltin : String -> List Value -> Value
  | "yaml.Marshal", [value] =>
      match valueToYaml value with
      | .ok text => .prim (.string text)
      | .error _ =>
          if isPendingArg value then .builtinCall "yaml.Marshal" [value]
          else .bottom
  | name, args => unresolvedOrBottom name args

/-- Wrap a list of strings as a `.list` of string prims (the `FindSubmatch`/`FindAll` shape). -/
private def stringListValue (xs : List String) : Value :=
  .list (xs.map (fun s => .prim (.string s)))

/-- Dispatch a `regexp.*` builtin over already-evaluated arguments (RX-1c).

    `Match(pattern, string)` is an UNANCHORED search — true when `pattern` matches anywhere
    in `string`, identical to Go's `regexp.MatchString` and CUE's `=~` operator. It shares
    the SAME engine entrypoint as `=~` (`matchRegex`, the RX-1 Pike-VM with an implicit
    leading `.*?` for the anywhere search), so `regexp.Match` and `=~` agree by construction.

    `ReplaceAll`/`ReplaceAllLiteral` substitute every non-overlapping match (the former
    expanding the Go `Expand` template `$n`/`${n}`/`$$` in the replacement; the latter
    splicing it verbatim). `Find`/`FindSubmatch`/`FindAll`/`FindAllSubmatch` expose the
    leftmost / all match spans. All route through the RX-1c capture-array entrypoints in the
    Regex leaf, so they agree with `=~`/`Match` by construction.

    **No-match is a BOTTOM, not null** for the `Find*` family — cue's builtins raise
    `no match` (verified vs cue v0.16.1), unlike Go's nil return. An INVALID pattern bottoms
    with `.invalidRegex` (inherited from RX-2b's contract). `ReplaceAll*` never bottoms on a
    valid pattern (a no-match returns `src` unchanged).

    **Kept DEFERRED** (`unsupportedBuiltin`, not silent-wrong): cue v0.16.1's `regexp`
    package does NOT expose `FindString*`/`FindAllString*`/`Split` as functions (calling
    them is itself a non-function error there), and `FindNamedSubmatch`/`FindAllNamedSubmatch`
    require named captures `(?P<…>)` which Kue's parser defers (RX-1a). Those fall through to
    the unsupported arm. -/
def evalRegexpBuiltin : String -> List Value -> Value
  | "regexp.Match", [.prim (.string pattern), .prim (.string s)] =>
      match regexParseError? pattern with
      | some err => .bottomWith [.invalidRegex pattern err]
      | none => .prim (.bool (matchRegex pattern s))
  | "regexp.ReplaceAll", [.prim (.string pattern), .prim (.string src), .prim (.string repl)] =>
      match regexParseError? pattern with
      | some err => .bottomWith [.invalidRegex pattern err]
      | none => match replaceAll pattern src repl with
        | some out => .prim (.string out)
        | none => .bottom  -- unreachable: parse already checked above
  | "regexp.ReplaceAllLiteral",
      [.prim (.string pattern), .prim (.string src), .prim (.string repl)] =>
      match regexParseError? pattern with
      | some err => .bottomWith [.invalidRegex pattern err]
      | none => match replaceAllLiteral pattern src repl with
        | some out => .prim (.string out)
        | none => .bottom
  | "regexp.Find", [.prim (.string pattern), .prim (.string s)] =>
      match regexParseError? pattern with
      | some err => .bottomWith [.invalidRegex pattern err]
      | none => match find pattern s with
        | some out => .prim (.string out)
        | none => .bottom  -- cue raises `no match`
  | "regexp.FindSubmatch", [.prim (.string pattern), .prim (.string s)] =>
      match regexParseError? pattern with
      | some err => .bottomWith [.invalidRegex pattern err]
      | none => match findSubmatch pattern s with
        | some groups => stringListValue groups
        | none => .bottom
  | "regexp.FindAll", [.prim (.string pattern), .prim (.string s), .prim (.int n)] =>
      match regexParseError? pattern with
      | some err => .bottomWith [.invalidRegex pattern err]
      | none => match findAll pattern s with
        | some all =>
            let kept := if n < 0 then all else all.take n.toNat
            if kept.isEmpty then .bottom else stringListValue kept
        | none => .bottom
  | "regexp.FindAllSubmatch", [.prim (.string pattern), .prim (.string s), .prim (.int n)] =>
      match regexParseError? pattern with
      | some err => .bottomWith [.invalidRegex pattern err]
      | none => match findAllSubmatch pattern s with
        | some all =>
            let kept := if n < 0 then all else all.take n.toNat
            if kept.isEmpty then .bottom else .list (kept.map stringListValue)
        | none => .bottom
  | name, args =>
      if args.any containsBottom then
        .bottom
      else if args.all isConcreteArg then
        -- A concrete call to a still-deferred form (`FindString*`/`Split`/named-submatch):
        -- a clear unsupported signal, never a silent wrong answer.
        .bottomWith [.unsupportedBuiltin name]
      else
        .builtinCall name args

/-- The closed set of builtin families on the FAMILY axis. `core` holds the eight exact
    unqualified builtins (`close`/`len`/`and`/`or`/`div`/`mod`/`quo`/`rem`); the rest are the
    seven qualified stdlib packages. The within-family LEAF (e.g. `math.Pow`) stays a
    `String` — genuinely many-valued and string-dispatched inside each `eval*Builtin`. This
    is the closed, versionable axis: a new family forces a new constructor, and the
    exhaustive match in `evalBuiltinCall` then forces a dispatch decision (no silent
    fall-through). -/
inductive BuiltinFamily where
  | core
  | strings
  | list
  | math
  | struct
  | regexp
  | base64
  | json
  | yaml
deriving Repr, BEq, DecidableEq

/-- Classify a builtin name into its family at the one point the name is interpreted as a
    builtin. `none` is a genuinely non-builtin name (an unknown package `foobar.Baz`, an
    unqualified non-builtin `nosuchfn`, a bare prefix `strings.` with no leaf) — past this
    boundary an unknown family is unrepresentable. A KNOWN package with an unknown LEAF
    (`math.NoSuch`) classifies to its family; the leaf is rejected inside the family
    dispatcher, not here. -/
def BuiltinFamily.ofName? (name : String) : Option BuiltinFamily :=
  if [ "close", "len", "and", "or", "div", "mod", "quo", "rem", "slice" ].contains name then
    some .core
  else if name.startsWith "strings." then some .strings
  else if name.startsWith "list." then some .list
  else if name.startsWith "math." then some .math
  else if name.startsWith "struct." then some .struct
  else if name.startsWith "regexp." then some .regexp
  else if name.startsWith "base64." then some .base64
  else if name.startsWith "json." then some .json
  else if name.startsWith "yaml." then some .yaml
  else none

/-- Dispatch the `core` exact-name builtins (import-free: the eight CUE built-ins plus the
    `slice` desugar of `x[lo:hi]`). Reached only for a name `ofName?` classified as `.core`;
    a non-concrete `slice` bound routes through `unresolvedOrBottom` to defer, as does the
    unreachable final arm, keeping the dispatch total. -/
def evalCoreBuiltin : String -> List Value -> Value
  | "close", [value] => closeValue value
  | "len", [value] => lenValue value
  | "and", [.list values] => andValues values
  | "or", [.list values] => orValues values
  | "div", [left, right] => divValue left right
  | "mod", [left, right] => modValue left right
  | "quo", [left, right] => quoValue left right
  | "rem", [left, right] => remValue left right
  -- The slice-syntax desugar (`x[lo:hi]`); a language operator that, unlike the public
  -- `list.Slice` package function, needs no `import "list"`. Concrete bounds slice; a
  -- non-concrete bound falls through to the residual defer.
  | "slice", [.list items, .prim (.int low), .prim (.int high)] => listSlice items low high
  | name, args => unresolvedOrBottom name args

/-- Dispatch the `struct` package builtins. `MinFields`/`MaxFields` lower to a
    `.fieldCountConstraint` validator that unifies with a struct (checked in `meet`); a
    non-integer argument is a resolution error routed through `unresolvedOrBottom` (a concrete
    non-int ⇒ bottom, an abstract arg ⇒ a deferred residual). -/
def evalStructBuiltin : String -> List Value -> Value
  | "struct.MinFields", [.prim (.int n)] => .fieldCountConstraint .min n
  | "struct.MaxFields", [.prim (.int n)] => .fieldCountConstraint .max n
  | name, args => unresolvedOrBottom name args

/-- Dispatch a builtin call over already-evaluated arguments. The family is classified once
    (`BuiltinFamily.ofName?`) and matched EXHAUSTIVELY — every family has an arm, with no
    catch-all over `BuiltinFamily` that could swallow a future family. A non-builtin name
    (`none`) routes through `unresolvedOrBottom`: concrete args ⇒ bottom (a CUE resolution
    error), abstract args ⇒ a deferred residual for a later pass. -/
def evalBuiltinCall (name : String) (args : List Value) : Value :=
  match BuiltinFamily.ofName? name with
  | some .core => evalCoreBuiltin name args
  | some .strings => evalStringsBuiltin name args
  | some .list => evalListBuiltin name args
  | some .math => evalMathBuiltin name args
  | some .struct => evalStructBuiltin name args
  | some .regexp => evalRegexpBuiltin name args
  | some .base64 => evalBase64Builtin name args
  | some .json => evalJsonBuiltin name args
  | some .yaml => evalYamlBuiltin name args
  | none => unresolvedOrBottom name args

end Kue
