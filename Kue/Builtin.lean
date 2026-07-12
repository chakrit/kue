import Kue.Lattice
import Kue.Regex
import Kue.Decimal
import Kue.Strconv
import Kue.Float
import Kue.Path
import Kue.Base64
import Kue.Json
import Kue.Yaml
import Kue.CaseTable
import Kue.TextTemplate

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
  | .struct fields _ _ _ _ => .prim (.int (Int.ofNat (countRegularFields fields)))
  | value =>
      match listItems? value with
      | some items => .prim (.int (Int.ofNat items.length))
      | none => .builtinCall "len" [value]

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

/-- Apply `transform` to the first character of each whitespace-delimited word (the first
    character of the string also starts a word); every other character passes through
    unchanged. The shared engine behind `strings.ToTitle` (transform = title/upper-case)
    and `strings.ToCamel` (transform = lower-case). ASCII-bounded: the separator set is the
    six ASCII whitespace runes and the case transforms are `Char.toUpper`/`Char.toLower`
    (ASCII-only) — non-ASCII whitespace never separates and non-ASCII letters pass through,
    the deferred boundary CUE covers via `unicode.IsSpace`/`unicode.ToTitle`. -/
def mapWordInitial (transform : Char -> Char) (value : String) : String := Id.run do
  let mut out : List Char := []
  let mut prevSep := true
  for c in value.toList do
    out := (if prevSep then transform c else c) :: out
    prevSep := asciiTitleSeparator c
  return String.ofList out.reverse

/-- Title-case the first ASCII letter of each whitespace-delimited word. Mirrors CUE's
    `strings.ToTitle` on ASCII — per-word capitalization, NOT "upper-case every letter". -/
def asciiToTitle (value : String) : String := mapWordInitial Char.toUpper value

/-- Lower-case the first ASCII letter of each whitespace-delimited word, leaving the rest
    unchanged. Mirrors CUE's `strings.ToCamel` — despite the name it does NOT camel-case;
    it only maps word-initial letters to lower case (`"Hello World"` → `"hello world"`,
    `"CamelCase"` → `"camelCase"`). -/
def asciiToCamel (value : String) : String := mapWordInitial Char.toLower value

/-- Concatenate a list of lists; any non-list element yields bottom.
    Each element is read through `listItems?`, so all three list carriers
    (`.list`/`.listTail`/`.embeddedList`) present their concrete-prefix elements —
    an open-tail sublist (`[a,b,...]`) or a list-embedding struct (`{[a,b], _x: 9}`)
    contributes `[a,b]`, reaching NESTED position. Mirrors CUE's `list.Concat`. -/
def listConcat (lists : List Value) : Value :=
  let rec collect : List Value -> Option (List Value)
    | [] => some []
    | value :: rest =>
        match listItems? value with
        | some items => (collect rest).map (items ++ ·)
        | none => none
  match collect lists with
  | some items => .list items
  | none => .bottom

/-- Flatten at most `fuel` nested levels of `items`; a non-list element is emitted
    as-is. Each element is read through `listItems?`, so every list carrier descends.
    Fuel decreases by one per level of descent, so the recursion is total. -/
def listFlattenFuel (fuel : Nat) (items : List Value) : List Value :=
  match fuel with
  | 0 => items
  | fuel + 1 =>
      items.flatMap fun item =>
        match listItems? item with
        | some inner => listFlattenFuel fuel inner
        | none => [item]

/-- A carrier's element list is structurally smaller than the carrier itself, so a
    flatten recursing through `listItems?` (into any list carrier) terminates. -/
theorem sizeOf_listItems?_lt {value : Value} {items : List Value}
    (h : listItems? value = some items) : sizeOf items < sizeOf value := by
  cases value <;> simp_all [listItems?] <;> omega

/-- Fully flatten every nested list carrier, at any depth. Reads each element through
    `listItems?`, so all three carriers descend; recursion is well-founded on the shrinking
    element list (`sizeOf_listItems?_lt`). The unbounded companion to `listFlattenFuel`. -/
def listFlattenAll (items : List Value) : List Value :=
  items.attach.flatMap fun ⟨item, _hmem⟩ =>
    match _h : listItems? item with
    | some inner => listFlattenAll inner
    | none => [item]
  termination_by sizeOf items
  decreasing_by
    have hinner : sizeOf inner < sizeOf item := sizeOf_listItems?_lt _h
    have hitem : sizeOf item < sizeOf items := List.sizeOf_lt_of_mem _hmem
    omega

/-- Flatten nested lists up to `depth` levels; `depth < 0` flattens fully.
    A non-list element is emitted as-is. Mirrors CUE's `list.FlattenN`. -/
def listFlattenN (items : List Value) (depth : Int) : List Value :=
  if depth < 0 then listFlattenAll items else listFlattenFuel depth.toNat items

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

/-- Whether `items` contains a value equal to `needle` under CUE's STRUCTURAL equality
    (`structuralEq`: open-tail-stripping, value-based prim leaves) — so an open-tail element
    `[1,2,...]` matches its concrete-prefix needle `[1,2]`, and an `int` element matches an
    equal-value `float` needle (`Contains([[1]],[1.0])` is `true`, spec-correct). Mirrors CUE's
    `list.Contains`. -/
def listContains (items : List Value) (needle : Value) : Bool :=
  items.any (structuralEq · needle)

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

/-- The raw UTF-8 byte carrier of a `bytes`-or-`string` argument. `strings.ByteAt` and
    `strings.ByteSlice` accept both kinds (`BytesKind | StringKind`); a string decodes to
    its UTF-8 encoding. Any other kind is `none` (a type error at the call site). -/
def primBytes : Prim -> Option (Array UInt8)
  | .string s => s.toUTF8.data
  | .bytes b => b
  | _ => none

/-- `strings.ByteAt(b, i)`: the `i`th BYTE of the UTF-8 carrier as an int (`0`–`255`).
    Indexes bytes, not runes — `ByteAt("é", 0) = 195`, the first byte of the two-byte
    UTF-8 sequence. Out of range (`i < 0` or `i ≥ len`) is an error (bottom), matching
    CUE (`index out of range`). -/
def stringByteAt (bytes : Array UInt8) (i : Int) : Value :=
  if i < 0 || i >= Int.ofNat bytes.size then
    .bottom
  else
    .prim (.int (Int.ofNat bytes[i.toNat]!.toNat))

/-- `strings.ByteSlice(b, start, end)`: the half-open `[start, end)` window of the UTF-8
    carrier, indexed by BYTE, returned as `bytes` (CUE renders it a byte literal; JSON
    export base64-encodes it). `start < 0`, `start > end`, or `end > len` is an error
    (bottom), matching CUE (`index out of range`). -/
def stringByteSlice (bytes : Array UInt8) (start endIdx : Int) : Value :=
  if start < 0 || start > endIdx || endIdx > Int.ofNat bytes.size then
    .bottom
  else
    .prim (.bytes (bytes.extract start.toNat endIdx.toNat))

/-- Whether the rune `c` is one of the code points in the set string `chars`. The shared
    membership test behind the `*Any` family — `chars` is a SET of runes, not a substring. -/
def runeInSet (chars : String) (c : Char) : Bool :=
  chars.toList.contains c

/-- `strings.ContainsAny(s, chars)`: whether any rune of `s` is in the set `chars`. An
    empty `chars` is the empty set, so the answer is `false`. -/
def stringContainsAny (s chars : String) : Bool :=
  s.toList.any (runeInSet chars)

/-- `strings.IndexAny(s, chars)`: the BYTE index of the first rune of `s` that is in the
    set `chars`, or `-1` if none (empty `chars` ⇒ `-1`). The index is a byte offset even
    though the scan is by rune — `IndexAny("héllo", "l") = 3`, past the two-byte `é`. -/
def stringIndexAny (s chars : String) : Int := Id.run do
  let mut offset := 0
  for c in s.toList do
    if runeInSet chars c then
      return Int.ofNat offset
    offset := offset + c.toString.utf8ByteSize
  return -1

/-- `strings.LastIndexAny(s, chars)`: the BYTE index of the LAST rune of `s` in the set
    `chars`, or `-1` if none. Byte offset like `IndexAny`. -/
def stringLastIndexAny (s chars : String) : Int := Id.run do
  let mut offset := 0
  let mut last : Int := -1
  for c in s.toList do
    if runeInSet chars c then
      last := Int.ofNat offset
    offset := offset + c.toString.utf8ByteSize
  return last

/-- Emit successive `SplitAfter` pieces: each match of `sep` ends a piece WITH the
    separator attached, and the unconsumed tail becomes the final piece. `remaining` caps
    the piece count (`SplitAfterN`): `remaining == 1` stops and takes the whole tail;
    `remaining < 0` is unbounded. `fuel` is a structural bound — each non-final step
    consumes ≥ 1 byte of `rest`, so its UTF-8 size suffices. -/
def stringSplitAfterLoop (fuel : Nat) (acc : List String) (rest sep : String)
    (remaining : Int) : List String :=
  match fuel with
  | 0 => acc ++ [rest]
  | fuel + 1 =>
      if remaining == 1 then
        acc ++ [rest]
      else
        let idx := stringByteIndex rest sep
        if idx < 0 then
          acc ++ [rest]
        else
          let cut := idx.toNat + sep.utf8ByteSize
          let piece := String.fromUTF8! (rest.toUTF8.extract 0 cut)
          let after := String.fromUTF8! (rest.toUTF8.extract cut rest.utf8ByteSize)
          let nextRemaining := if remaining > 0 then remaining - 1 else remaining
          stringSplitAfterLoop fuel (acc ++ [piece]) after sep nextRemaining

/-- Raw `strings.SplitAfter`/`SplitAfterN` pieces of `value` on `sep`, keeping each `sep`
    at the end of the piece it terminates (unlike `Split`, which drops it). `n == 0` yields
    `[]`; `n < 0` is unbounded; `n > 0` caps the piece count. An empty `sep` splits into
    runes (capped like `SplitN`), matching Go/CUE. -/
def stringSplitAfterParts (value sep : String) (n : Int) : List String :=
  if n == 0 then
    []
  else if sep.isEmpty then
    let runes := value.toList.map (·.toString)
    if n < 0 || runes.length <= n.toNat then
      runes
    else
      runes.take (n.toNat - 1) ++ [String.join (runes.drop (n.toNat - 1))]
  else
    stringSplitAfterLoop value.utf8ByteSize [] value sep n

/-- `strings.SplitAfter`/`SplitAfterN` as a `Value` list of string pieces. -/
def stringSplitAfter (value sep : String) (n : Int) : List Value :=
  (stringSplitAfterParts value sep n).map (fun piece => .prim (.string piece))

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

/-- Whether an argument has a dispatch-settled, non-deferrable SHAPE — a value no later
    evaluation pass will reshape, so a builtin dispatcher may commit its fallback. NOT a
    groundness check: an abstract `.list [int]` is settled (true) while a concrete
    `.struct {a: 1}` is not a dispatch target here (false). For groundness use
    `Value.isGround`. Used to decide a builtin dispatcher's fallback. -/
def isSettledArg : Value -> Bool
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

/-- Shared catch-all for every package builtin dispatcher: a call that matched no known arm
    resolves to bottom when any argument is bottom or all arguments are concrete (a genuine CUE
    type error — a nonexistent leaf, which `cue` also rejects as `cannot call non-function`),
    and otherwise stays unresolved as a `.builtinCall` so a later evaluation pass can complete it
    once references resolve. A leaf Kue RECOGNIZES as real-but-deferred routes instead through
    `unsupportedOrBottom` from its own explicit arm — recognition is a positive claim the
    catch-all cannot substantiate, so it defaults to the honest bare bottom. -/
def unresolvedOrBottom (name : String) (args : List Value) : Value :=
  if args.any containsBottom then
    .bottom
  else if args.all isSettledArg then
    .bottom
  else
    .builtinCall name args

/-- Fallback for a builtin leaf Kue RECOGNIZES as a real `cue` function but does not compute (a
    `Float`-model or Go-Unicode-table dependency, or a parser-deferred form). A bottom argument
    propagates to bottom; all-concrete arguments resolve to `.bottomWith [.unsupportedBuiltin
    name]` — a clear "recognized, not yet implemented" signal instead of a silent wrong answer;
    a still-abstract argument stays a `.builtinCall` residual for a later pass. Reached only from
    an EXPLICIT dispatch arm that names the leaf: the `unsupportedBuiltin` marker is a positive
    recognition claim, never emitted from a catch-all (which cannot tell a deferred-but-real leaf
    from a genuinely nonexistent one — that is a plain type error, bottomed bare by
    `unresolvedOrBottom`). -/
def unsupportedOrBottom (name : String) (args : List Value) : Value :=
  if args.any containsBottom then
    .bottom
  else if args.all isSettledArg then
    .bottomWith [.unsupportedBuiltin name]
  else
    .builtinCall name args

/-- Every list carrier presents its concrete-prefix elements to a value-level list
    operation, consistent with `len([1,2,3,...]) = 3`. Normalize any list carrier
    (`.list`/`.listTail`/`.embeddedList`, via `listItems?`) to a plain `.list` so a
    dispatch that destructures `.list` serves all three; the open-tail `...` marker and a
    struct-embed's non-output decls govern only unification/closedness, never a value read. -/
def openListOperand (value : Value) : Value :=
  match listItems? value with
  | some items => .list items
  | none => value

/-- Dispatch a `list.*` builtin over already-evaluated arguments.
    Wrong argument shapes resolve to bottom (CUE error), per total-function design.
    An open-tail list operand (`[1,2,...]`) is normalized to its concrete prefix
    (`openListOperand`) so it slices/reverses/sums like the closed prefix.
    Deferred (kept unresolved/not matched): `Sort`/`SortStable`
    (comparator-struct evaluation). -/
def evalListBuiltin (name : String) (rawArgs : List Value) : Value :=
  match name, (rawArgs.map openListOperand) with
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
  -- Constraint validators (participate in `meet`, like `struct.MinFields`). `MinItems`/`MaxItems`
  -- lower to a `lengthConstraint .listItems`; `UniqueItems` to `.uniqueItems`. The `()`-call form
  -- passes `[]`; the bare `list.UniqueItems` form (no call) is handled at the reference site.
  | "list.MinItems", [.prim (.int n)] => .lengthConstraint .listItems .min n
  | "list.MaxItems", [.prim (.int n)] => .lengthConstraint .listItems .max n
  -- Call form `list.UniqueItems(list)`: decide structural uniqueness directly via `hasGroundDup`
  -- (the SAME predicate the `.uniqueItems` validator's meet uses — value-based prim leaves). The
  -- operand is carrier-normalized by `openListOperand` (mapped over args above), so embedded/
  -- open-tail lists descend to their concrete prefix.
  | "list.UniqueItems", [.list items] => .prim (.bool (!hasGroundDup items))
  | "list.UniqueItems", [] => .uniqueItems
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
  | "strings.ByteAt", [.prim p, .prim (.int i)] =>
      match primBytes p with
      | some bytes => stringByteAt bytes i
      | none => .bottom
  | "strings.ByteSlice", [.prim p, .prim (.int start), .prim (.int endIdx)] =>
      match primBytes p with
      | some bytes => stringByteSlice bytes start endIdx
      | none => .bottom
  | "strings.ContainsAny", [.prim (.string s), .prim (.string chars)] =>
      .prim (.bool (stringContainsAny s chars))
  | "strings.IndexAny", [.prim (.string s), .prim (.string chars)] =>
      .prim (.int (stringIndexAny s chars))
  | "strings.LastIndexAny", [.prim (.string s), .prim (.string chars)] =>
      .prim (.int (stringLastIndexAny s chars))
  | "strings.SplitAfter", [.prim (.string s), .prim (.string sep)] =>
      .list (stringSplitAfter s sep (-1))
  | "strings.SplitAfterN", [.prim (.string s), .prim (.string sep), .prim (.int n)] =>
      .list (stringSplitAfter s sep n)
  | "strings.ToCamel", [.prim (.string s)] =>
      .prim (.string (asciiToCamel s))
  -- Constraint validators (participate in `meet`, like `struct.MinFields`). Bound a string's
  -- rune (Unicode code-point) count, NOT its byte length: a multi-byte rune counts as one.
  | "strings.MinRunes", [.prim (.int n)] => .lengthConstraint .runes .min n
  | "strings.MaxRunes", [.prim (.int n)] => .lengthConstraint .runes .max n
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

/-- The `math.Log`/`Log2`/`Log10` family over the domain Kue computes EXACTLY (34-digit apd
    decimal via `decimalLnScaled`): `Log` is the natural log, `Log2`/`Log10` divide by
    `ln 2`/`ln 10`. `none` when the argument is non-numeric (caller defers). A non-positive
    argument is a domain error → `.bottom` (`cue` yields `-Inf`, which it then fails to render
    for `x = 0`, and errors `invalid operation` for `x < 0`; Kue has no `Inf`, so both bottom —
    see `cue-spec-gaps.md`). -/
def mathLog? (kernel : DecimalValue -> Value) (value : Prim) : Option Value :=
  (decimalFromPrim? value).map (fun d => if d.numerator <= 0 then .bottom else kernel d)

/-- The `math.Exp`/`Exp2` family — `e^x` / `2^x` in 34-digit apd decimal, total over every
    real argument. `none` when the argument is non-numeric (caller defers). -/
def mathExp? (kernel : DecimalValue -> Value) (value : Prim) : Option Value :=
  (decimalFromPrim? value).map kernel

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
  | "math.Log", [.prim value] =>
      (mathLog? mathLogValue value).getD (unresolvedOrBottom "math.Log" [.prim value])
  | "math.Log2", [.prim value] =>
      (mathLog? mathLog2Value value).getD (unresolvedOrBottom "math.Log2" [.prim value])
  | "math.Log10", [.prim value] =>
      (mathLog? mathLog10Value value).getD (unresolvedOrBottom "math.Log10" [.prim value])
  | "math.Exp", [.prim value] =>
      (mathExp? mathExpValue value).getD (unresolvedOrBottom "math.Exp" [.prim value])
  | "math.Exp2", [.prim value] =>
      (mathExp? mathExp2Value value).getD (unresolvedOrBottom "math.Exp2" [.prim value])
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

    Two deferral shapes, distinguished by whether the leaf exists in cue. `FindNamedSubmatch`/
    `FindAllNamedSubmatch` ARE real cue functions Kue defers (named captures `(?P<…>)` which
    Kue's parser does not yet build, RX-1a): explicit arms route them through
    `unsupportedOrBottom` for a clear "recognized, not implemented" signal. `FindString*`/
    `FindAllString*`/`Split` are NOT cue functions at all (calling them is a `cannot call
    non-function` error there); they have no arm and fall to the `unresolvedOrBottom` catch-all,
    which bottoms bare — the cue-compatible verdict for a nonexistent leaf. -/
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
  -- Real cue functions Kue recognizes but defers (named captures, RX-1a) → clear unsupported
  -- signal; a nonexistent leaf (`FindString`/`Split`) has no arm and bottoms bare below.
  | "regexp.FindNamedSubmatch", args => unsupportedOrBottom "regexp.FindNamedSubmatch" args
  | "regexp.FindAllNamedSubmatch", args => unsupportedOrBottom "regexp.FindAllNamedSubmatch" args
  | name, args => unresolvedOrBottom name args

/-- Dispatch the `time` package builtins (STDLIB-TIME). The exact/structural surface:
    `ParseDuration` (Go-duration → int64 nanoseconds), the `Duration`/`Time` validators (both
    the zero-arg validator form yielding a `.stringFormat` node and the concrete-arg boolean
    function form), and `Format` restricted to the RFC3339 / RFC3339Nano layouts.

    A validator (`time.Duration()`, `time.Time()`, `time.Format(RFC3339)`) resolves to a
    `.stringFormat` value that participates in `meet` (a ground non-conforming string bottoms,
    an abstract string retains). A function form (`time.Duration(s)`, `time.Time(s)`,
    `time.Format(s, layout)`) returns `true` on a valid concrete string and BOTTOMS on an
    invalid one — cue errors rather than returning `false`.

    DEFERRED with a clear `unsupportedBuiltin` marker (all need a civil-calendar/epoch engine or
    Go's format machinery, see `docs/spec/cue-spec-gaps.md`): `Unix`, `Parse`, `FormatString`,
    `Split`, `FormatDuration`, and any non-RFC3339 custom `Format` layout. A nonexistent leaf
    (`time.Date`) has no arm and bottoms bare via `unresolvedOrBottom`. -/
def evalTimeBuiltin : String -> List Value -> Value
  | "time.ParseDuration", [.prim (.string s)] =>
      match parseGoDuration s with
      | some nanos => .prim (.int nanos)
      | none => .bottom
  | "time.Duration", [] => .stringFormat .duration
  | "time.Duration", [.prim (.string s)] =>
      if isValidDuration s then .prim (.bool true) else .bottom
  | "time.Time", [] => .stringFormat .rfc3339
  | "time.Time", [.prim (.string s)] =>
      if isValidRFC3339 s then .prim (.bool true) else .bottom
  | "time.Format", [.prim (.string layout)] =>
      if isRFC3339Layout layout then .stringFormat .rfc3339
      else .bottomWith [.unsupportedBuiltin "time.Format"]
  | "time.Format", [.prim (.string value), .prim (.string layout)] =>
      if isRFC3339Layout layout then
        (if isValidRFC3339 value then .prim (.bool true) else .bottom)
      else .bottomWith [.unsupportedBuiltin "time.Format"]
  -- Real cue functions Kue recognizes but defers (civil-calendar / epoch / Go format engine).
  | "time.Unix", args => unsupportedOrBottom "time.Unix" args
  | "time.Parse", args => unsupportedOrBottom "time.Parse" args
  | "time.FormatString", args => unsupportedOrBottom "time.FormatString" args
  | "time.Split", args => unsupportedOrBottom "time.Split" args
  | "time.FormatDuration", args => unsupportedOrBottom "time.FormatDuration" args
  | name, args => unresolvedOrBottom name args

/-- Dispatch the `net` package builtins (STDLIB-NET). Scoped to the IP string-validator
    surface: `IP`/`IPv4`/`IPv6`, `IPCIDR`, and the address-class predicates (`LoopbackIP`,
    `MulticastIP`, `InterfaceLocalMulticastIP`, `LinkLocalMulticastIP`, `LinkLocalUnicastIP`,
    `GlobalUnicastIP`, `UnspecifiedIP`).

    Each validator has two forms, mirroring `time`: the zero-arg VALIDATOR (`net.IPv4()`)
    resolves to a `.stringFormat` node that participates in `meet` (a ground non-conforming
    string bottoms, an abstract string retains); the concrete-arg FUNCTION (`net.IPv4("…")`)
    returns a bool — and, unlike `time`, an invalid address returns `false`, NOT bottom (cue's
    `Is*` return `false`). The one exception is `IPCIDR`, whose cue form returns `(bool, error)`
    and so BOTTOMS on an unparseable CIDR.

    DEFERRED with a clear `unsupportedBuiltin` marker (need an idna engine or return
    structs/lists/tuples, see `docs/spec/cue-spec-gaps.md`): `FQDN` (full IDNA2008 via
    `golang.org/x/net/idna`), `SplitHostPort`/`JoinHostPort`, `ToIP4`/`ToIP16`, `ParseCIDR`,
    `ParseIP`, `AddIP`/`AddIPCIDR`, `InCIDR`, `CompareIP`. A nonexistent leaf (`net.Host`,
    `net.CIDR`) has no arm and bottoms bare via `unresolvedOrBottom`; a non-string validator
    argument (a byte-list IP) likewise defers there (a documented gap). -/
def evalNetBuiltin : String -> List Value -> Value
  | "net.IP", [] => .stringFormat .netIP
  | "net.IP", [.prim (.string s)] => .prim (.bool (isNetIP s))
  | "net.IPv4", [] => .stringFormat .netIPv4
  | "net.IPv4", [.prim (.string s)] => .prim (.bool (isNetIPv4 s))
  | "net.IPv6", [] => .stringFormat .netIPv6
  | "net.IPv6", [.prim (.string s)] => .prim (.bool (isNetIPv6 s))
  | "net.IPCIDR", [] => .stringFormat .netIPCIDR
  | "net.IPCIDR", [.prim (.string s)] =>
      if isNetIPCIDRString s then .prim (.bool true) else .bottom
  | "net.LoopbackIP", [] => .stringFormat .netLoopbackIP
  | "net.LoopbackIP", [.prim (.string s)] => .prim (.bool (isNetLoopbackIP s))
  | "net.MulticastIP", [] => .stringFormat .netMulticastIP
  | "net.MulticastIP", [.prim (.string s)] => .prim (.bool (isNetMulticastIP s))
  | "net.InterfaceLocalMulticastIP", [] => .stringFormat .netInterfaceLocalMulticastIP
  | "net.InterfaceLocalMulticastIP", [.prim (.string s)] => .prim (.bool (isNetInterfaceLocalMulticastIP s))
  | "net.LinkLocalMulticastIP", [] => .stringFormat .netLinkLocalMulticastIP
  | "net.LinkLocalMulticastIP", [.prim (.string s)] => .prim (.bool (isNetLinkLocalMulticastIP s))
  | "net.LinkLocalUnicastIP", [] => .stringFormat .netLinkLocalUnicastIP
  | "net.LinkLocalUnicastIP", [.prim (.string s)] => .prim (.bool (isNetLinkLocalUnicastIP s))
  | "net.GlobalUnicastIP", [] => .stringFormat .netGlobalUnicastIP
  | "net.GlobalUnicastIP", [.prim (.string s)] => .prim (.bool (isNetGlobalUnicastIP s))
  | "net.UnspecifiedIP", [] => .stringFormat .netUnspecifiedIP
  | "net.UnspecifiedIP", [.prim (.string s)] => .prim (.bool (isNetUnspecifiedIP s))
  -- Real cue functions Kue defers (idna engine, or struct/list/tuple results).
  | "net.FQDN", args => unsupportedOrBottom "net.FQDN" args
  | "net.SplitHostPort", args => unsupportedOrBottom "net.SplitHostPort" args
  | "net.JoinHostPort", args => unsupportedOrBottom "net.JoinHostPort" args
  | "net.ToIP4", args => unsupportedOrBottom "net.ToIP4" args
  | "net.ToIP16", args => unsupportedOrBottom "net.ToIP16" args
  | "net.ParseCIDR", args => unsupportedOrBottom "net.ParseCIDR" args
  | "net.ParseIP", args => unsupportedOrBottom "net.ParseIP" args
  | "net.AddIP", args => unsupportedOrBottom "net.AddIP" args
  | "net.AddIPCIDR", args => unsupportedOrBottom "net.AddIPCIDR" args
  | "net.InCIDR", args => unsupportedOrBottom "net.InCIDR" args
  | "net.CompareIP", args => unsupportedOrBottom "net.CompareIP" args
  | name, args => unresolvedOrBottom name args

mutual
  /-- Bridge an already-manifested value into the `text/template` data tree. A FLOAT (or a
      `bytes` payload, whose Go-`fmt` byte-list rendering is likewise out of T1 scope) is NOT
      representable in `TemplateData` — its presence returns `none`, which the caller routes to
      `unsupportedBuiltin` (the deferred `strconv.FormatFloat` shortest-round-trip kernel is the
      wall; a wrong float rendering is never emitted). Struct fields are KEY-SORTED here so both
      the `map[…]` rendering and `range` iterate in Go's key order. -/
  def manifestToTemplateData : ManifestValue → Option TextTemplate.TemplateData
    | .prim .null => some .null
    | .prim (.bool b) => some (.bool b)
    | .prim (.int i) => some (.int i)
    | .prim (.string s) => some (.str s)
    | .prim (.float _ _) => none
    | .prim (.bytes _) => none
    | .list items => (manifestToTemplateList items).map .list
    | .struct fields =>
        (manifestToTemplateFields fields).map (fun fs =>
          .struct (fs.mergeSort (fun a b => a.fst < b.fst)))

  def manifestToTemplateList : List ManifestValue → Option (List TextTemplate.TemplateData)
    | [] => some []
    | x :: rest =>
        match manifestToTemplateData x, manifestToTemplateList rest with
        | some d, some ds => some (d :: ds)
        | _, _ => none

  def manifestToTemplateFields :
      List (String × ManifestValue) → Option (List (String × TextTemplate.TemplateData))
    | [] => some []
    | kv :: rest =>
        match manifestToTemplateData kv.snd, manifestToTemplateFields rest with
        | some d, some ds => some ((kv.fst, d) :: ds)
        | _, _ => none
end

/-- Evaluate `template.Execute(tmpl, data)`. Both arguments are manifested (forcing defaults /
    incompleteness): a non-concrete argument that may still resolve stays a `.builtinCall`
    residual, an incomplete-but-settled one bottoms (mirroring `json.Marshal`); a concrete
    non-string template bottoms (cue type error). A float in the data ⇒ `unsupportedBuiltin`;
    a template parse/eval error ⇒ bottom; a deferred construct ⇒ `unsupportedBuiltin`. -/
def executeTemplate (tmplVal dataVal : Value) : Value :=
  match manifest tmplVal with
  | .error _ =>
      if isPendingArg tmplVal then .builtinCall "template.Execute" [tmplVal, dataVal] else .bottom
  | .ok (.prim (.string tmpl)) =>
      match manifest dataVal with
      | .error _ =>
          if isPendingArg dataVal then .builtinCall "template.Execute" [tmplVal, dataVal] else .bottom
      | .ok mdata =>
          match manifestToTemplateData mdata with
          | none => .bottomWith [.unsupportedBuiltin "text/template.Execute"]
          | some data =>
              match TextTemplate.runTemplate tmpl data with
              | .ok s => .prim (.string s)
              | .error .unsupported => .bottomWith [.unsupportedBuiltin "text/template.Execute"]
              | .error .bottom => .bottom
  | .ok _ => .bottom

/-- Dispatch the `text/template` package builtins (STDLIB-TEXTTEMPLATE-T1). cue v0.16.1 exposes
    exactly three callable leaves — `Execute(tmpl, data)`, `HTMLEscape(s)`, `JSEscape(s)`, all
    returning a string; every other name is a nonexistent leaf that bottoms bare via
    `unresolvedOrBottom` (cue's `cannot call non-function`). `JSEscape` of a non-ASCII string
    defers (`unicode.IsPrint` table, see `cue-spec-gaps.md`). -/
def evalTextTemplateBuiltin : String → List Value → Value
  | "template.Execute", [tmplVal, dataVal] => executeTemplate tmplVal dataVal
  | "template.HTMLEscape", [.prim (.string s)] => .prim (.string (TextTemplate.htmlEscape s))
  | "template.JSEscape", [.prim (.string s)] =>
      match TextTemplate.jsEscape s with
      | some out => .prim (.string out)
      | none => .bottomWith [.unsupportedBuiltin "text/template.JSEscape"]
  | name, args => unresolvedOrBottom name args

/-- The closed set of builtin families on the FAMILY axis. `core` holds the nine exact
    unqualified builtins (`close`/`len`/`and`/`or`/`div`/`mod`/`quo`/`rem`, plus the `slice`
    desugar of `x[lo:hi]`); the rest are the thirteen qualified stdlib packages
    (`strings`/`list`/`math`/`struct`/`regexp`/`strconv`/`base64`/`json`/`yaml`/`path`/`time`/`net`/`textTemplate`). The
    within-family LEAF (e.g. `math.Pow`) stays a
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
  | strconv
  | base64
  | json
  | yaml
  | path
  | time
  | net
  | textTemplate
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
  else if name.startsWith "strconv." then some .strconv
  else if name.startsWith "base64." then some .base64
  else if name.startsWith "json." then some .json
  else if name.startsWith "yaml." then some .yaml
  else if name.startsWith "path." then some .path
  else if name.startsWith "time." then some .time
  else if name.startsWith "net." then some .net
  else if name.startsWith "template." then some .textTemplate
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
  -- non-concrete bound falls through to the residual defer. Every list carrier
  -- (`.list`/`.listTail`/`.embeddedList`) presents its concrete-prefix elements via
  -- `listItems?`, so all three slice like the closed prefix; a high bound past the prefix
  -- is out of range (bottom). A non-list operand routes to the residual/bottom defer.
  | "slice", [value, .prim (.int low), .prim (.int high)] =>
      match listItems? value with
      | some items => listSlice items low high
      | none => unresolvedOrBottom "slice" [value, .prim (.int low), .prim (.int high)]
  | name, args => unresolvedOrBottom name args

/-- Dispatch the `struct` package builtins. `MinFields`/`MaxFields` lower to a
    `.lengthConstraint .fields` validator that unifies with a struct (checked in `meet`); a
    non-integer argument is a resolution error routed through `unresolvedOrBottom` (a concrete
    non-int ⇒ bottom, an abstract arg ⇒ a deferred residual). -/
def evalStructBuiltin : String -> List Value -> Value
  | "struct.MinFields", [.prim (.int n)] => .lengthConstraint .fields .min n
  | "struct.MaxFields", [.prim (.int n)] => .lengthConstraint .fields .max n
  | name, args => unresolvedOrBottom name args

/-- Dispatch the `strconv` package builtins (STDLIB-C). Numeric parsing/formatting is
    arbitrary-precision, matching cue's `Atoi` of an over-`int64` literal and Kue's exact `Int`.
    Base `2..36` per Go's documented contract (cue leaks `math/big`'s `2..62`; see
    `cue-divergences.md`).

    Two deferral shapes, distinguished by whether the leaf exists in cue. `FormatFloat`/
    `ParseFloat` (float shortest-round-trip formatting is incompatible with Kue's exact-decimal
    core) and the `Quote`/`Unquote` family (needs Go's full Unicode `IsPrint` table) ARE real cue
    functions Kue defers: explicit arms route them through `unsupportedOrBottom` for a clear
    "recognized, not implemented" signal. `Itoa` is NOT a callable function in cue v0.16.1
    (`cannot call non-function`); it has no arm and falls to the `unresolvedOrBottom` catch-all,
    which bottoms bare — the cue-compatible verdict for a nonexistent leaf. -/
def evalStrconvBuiltin : String -> List Value -> Value
  | "strconv.Atoi", [.prim (.string s)] => strconvAtoi s
  | "strconv.FormatInt", [.prim (.int i), .prim (.int base)] => strconvFormatInt i base
  | "strconv.FormatUint", [.prim (.int i), .prim (.int base)] => strconvFormatInt i base
  | "strconv.ParseInt", [.prim (.string s), .prim (.int base), .prim (.int bits)] =>
      strconvParse true s base bits
  | "strconv.ParseUint", [.prim (.string s), .prim (.int base), .prim (.int bits)] =>
      strconvParse false s base bits
  | "strconv.FormatBool", [.prim (.bool b)] => .prim (.string (if b then "true" else "false"))
  | "strconv.ParseBool", [.prim (.string s)] => strconvParseBool s
  -- IEEE binary float surface (STDLIB-FLOAT-F2). ParseFloat parses to a correctly-rounded
  -- float; FormatFloat renders one with Go's verb/precision. Both accept int or float numbers.
  | "strconv.ParseFloat", [.prim (.string s), .prim (.int bits)] => strconvParseFloat s bits
  | "strconv.FormatFloat", [.prim n, .prim (.int verb), .prim (.int prec), .prim (.int bits)] =>
      strconvFormatFloat n verb prec bits
  -- Real cue functions Kue recognizes but defers (Unicode `IsPrint` table) → clear unsupported
  -- signal; a nonexistent leaf (`Itoa`) has no arm and bottoms bare below.
  | "strconv.Quote", args => unsupportedOrBottom "strconv.Quote" args
  | "strconv.Unquote", args => unsupportedOrBottom "strconv.Unquote" args
  | "strconv.QuoteToASCII", args => unsupportedOrBottom "strconv.QuoteToASCII" args
  | name, args => unresolvedOrBottom name args

/-- Dispatch the `path` package builtins (STDLIB-PATH). Every function is OS-parameterized; the
    os-less arms take cue's default (`unix`, except `VolumeName` whose default is `windows`, so a
    bare call defers). `ToSlash`/`FromSlash`/`SplitList` have no os default (cue requires the
    arg), so no os-less arm. Unix/plan9 compute exactly; a `windows` os argument defers with a
    clear `unsupportedBuiltin` (faithful volume/UNC handling is a documented deferral, see
    `cue-spec-gaps.md`); an invalid os string bottoms. A malformed `Match` pattern or an
    impossible `Rel` bottoms (cue error). Unknown leaves route through `unresolvedOrBottom`. -/
def evalPathBuiltin : String -> List Value -> Value
  | "path.Base", [.prim (.string p)] => pathStrVal (unixBase p)
  | "path.Base", [.prim (.string p), .prim (.string os)] =>
      pathDispatch "path.Base" os (pathStrVal (unixBase p))
  | "path.Dir", [.prim (.string p)] => pathStrVal (unixDir p)
  | "path.Dir", [.prim (.string p), .prim (.string os)] =>
      pathDispatch "path.Dir" os (pathStrVal (unixDir p))
  | "path.Ext", [.prim (.string p)] => pathStrVal (unixExt p)
  | "path.Ext", [.prim (.string p), .prim (.string os)] =>
      pathDispatch "path.Ext" os (pathStrVal (unixExt p))
  | "path.Clean", [.prim (.string p)] => pathStrVal (unixClean p)
  | "path.Clean", [.prim (.string p), .prim (.string os)] =>
      pathDispatch "path.Clean" os (pathStrVal (unixClean p))
  | "path.IsAbs", [.prim (.string p)] => .prim (.bool (unixIsAbs p))
  | "path.IsAbs", [.prim (.string p), .prim (.string os)] =>
      pathDispatch "path.IsAbs" os (.prim (.bool (unixIsAbs p)))
  | "path.Join", [.list elems] =>
      match pathAllStrings? elems with
      | some ss => pathStrVal (unixJoin ss)
      | none => .bottom
  | "path.Join", [.list elems, .prim (.string os)] =>
      match pathAllStrings? elems with
      | some ss => pathDispatch "path.Join" os (pathStrVal (unixJoin ss))
      | none => .bottom
  | "path.Split", [.prim (.string p)] =>
      let (d, f) := unixSplit p
      pathPairList d f
  | "path.Split", [.prim (.string p), .prim (.string os)] =>
      let (d, f) := unixSplit p
      pathDispatch "path.Split" os (pathPairList d f)
  | "path.SplitList", [.prim (.string p), .prim (.string os)] =>
      pathDispatch "path.SplitList" os (.list ((unixSplitList p).map pathStrVal))
  | "path.ToSlash", [.prim (.string p), .prim (.string os)] =>
      pathDispatch "path.ToSlash" os (pathStrVal p)
  | "path.FromSlash", [.prim (.string p), .prim (.string os)] =>
      pathDispatch "path.FromSlash" os (pathStrVal p)
  | "path.VolumeName", [.prim (.string _)] =>
      -- VolumeName's os default is Windows; a bare call defers.
      .bottomWith [.unsupportedBuiltin "path.VolumeName"]
  | "path.VolumeName", [.prim (.string _), .prim (.string os)] =>
      pathDispatch "path.VolumeName" os (pathStrVal "")
  | "path.Resolve", [.prim (.string dir), .prim (.string sub)] =>
      pathStrVal (unixResolve dir sub)
  | "path.Resolve", [.prim (.string dir), .prim (.string sub), .prim (.string os)] =>
      pathDispatch "path.Resolve" os (pathStrVal (unixResolve dir sub))
  | "path.Rel", [.prim (.string b), .prim (.string t)] => pathRelVal (unixRel b t)
  | "path.Rel", [.prim (.string b), .prim (.string t), .prim (.string os)] =>
      pathDispatch "path.Rel" os (pathRelVal (unixRel b t))
  | "path.Match", [.prim (.string pat), .prim (.string name)] =>
      pathMatchVal (unixMatch pat name)
  | "path.Match", [.prim (.string pat), .prim (.string name), .prim (.string os)] =>
      pathDispatch "path.Match" os (pathMatchVal (unixMatch pat name))
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
  | some .strconv => evalStrconvBuiltin name args
  | some .base64 => evalBase64Builtin name args
  | some .json => evalJsonBuiltin name args
  | some .yaml => evalYamlBuiltin name args
  | some .path => evalPathBuiltin name args
  | some .time => evalTimeBuiltin name args
  | some .net => evalNetBuiltin name args
  | some .textTemplate => evalTextTemplateBuiltin name args
  | none => unresolvedOrBottom name args

end Kue
