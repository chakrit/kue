import Kue.Value

namespace Kue

/-! # `path` standard-library primitives (STDLIB-PATH)

CUE's `path` package is OS-parameterized: every function takes a trailing `os` argument
selecting the separator convention (`path.Unix` / `path.Windows` / `path.Plan9`, the string
constants `"unix"` / `"windows"` / `"plan9"`). The CUE package exposes ONLY those three
constants — there is NO `path.OS` field (a common misconception; `getOS` maps `runtime.GOOS`
values internally, but nothing surfaces it). Mirrors `cuelang.org/go/pkg/path` (itself a
vendored, OS-parameterized copy of Go's `path/filepath`).

**Unix and Plan9 collapse.** Both use `/` as separator, `0` volume length, and a leading-`/`
`IsAbs`; they are behaviorally identical for every function here, so one code path serves both.
The `unixOS` fallback names (`darwin`, `linux`, …) also route to the unix path, matching cue's
`getOS` default case.

**Windows is deferred.** Faithful volume-name / UNC / backslash handling is a large, error-prone
surface. Every function on a `windows` os argument returns a clear `unsupportedBuiltin` residual
(never a silently-wrong value); `VolumeName`'s os default is `windows`, so a bare
`path.VolumeName(p)` defers. Recorded in `docs/spec/cue-spec-gaps.md`. -/

/-- The three OS conventions the `path` package selects between. Unix and Plan9 share one
    separator/volume behavior; Windows is a distinct (deferred) convention. -/
inductive PathOS where
  | unix
  | windows
  | plan9
deriving Repr, BEq

/-- Classify an `os` argument string. `"windows"` / `"plan9"` map to their conventions; `"unix"`
    and every `unixOS` fallback name (`getOS`'s default case) map to `.unix`; any other string is
    `none` — an invalid os the caller bottoms (cue: a disjunction unification error). -/
def PathOS.ofString? (s : String) : Option PathOS :=
  match s with
  | "windows" => some .windows
  | "plan9" => some .plan9
  | "unix" | "aix" | "android" | "darwin" | "dragonfly" | "freebsd"
  | "hurd" | "illumos" | "ios" | "js" | "linux" | "nacl" | "netbsd"
  | "openbsd" | "solaris" | "zos" => some .unix
  | _ => none

/-! ## Unix/Plan9 lexical primitives (separator `/`) -/

/-- Byte-free char index of the LAST `/` in `p`, or `none`. `/` is ASCII, so a char index is
    unambiguous over any UTF-8 content. -/
def lastSlashIndex (p : String) : Option Nat := Id.run do
  let mut idx : Option Nat := none
  let mut i := 0
  for c in p.toList do
    if c == '/' then idx := some i
    i := i + 1
  return idx

/-- Char index of the LAST `.` in `p`, or `none`. -/
def lastDotIndex (p : String) : Option Nat := Id.run do
  let mut idx : Option Nat := none
  let mut i := 0
  for c in p.toList do
    if c == '.' then idx := some i
    i := i + 1
  return idx

/-- The path element after the final `/` (the whole string when there is no `/`). -/
def afterLastSlash (p : String) : String :=
  match lastSlashIndex p with
  | some i => String.ofList (p.toList.drop (i + 1))
  | none => p

/-- Drop trailing `/` runs from `p`. -/
def stripTrailingSlash (p : String) : String :=
  String.ofList ((p.toList.reverse.dropWhile (· == '/')).reverse)

/-- One step of `Clean`'s element stack (segments held in reverse). A `..` pops the previous
    real element, is dropped at a rooted top, and is retained (stacked) when relative-and-above
    or already sitting on a `..`. Mirrors Go's lazybuf backtrack rule. -/
def cleanPush (rooted : Bool) (stack : List String) (seg : String) : List String :=
  if seg == ".." then
    match stack with
    | top :: rest => if top == ".." then ".." :: stack else rest
    | [] => if rooted then [] else [".."]
  else
    seg :: stack

/-- `path.Clean` on unix/plan9: purely lexical normalization. Drops `.` and empty segments,
    resolves `..`, preserves a leading `/`, and yields `"."` for an empty result. -/
def unixClean (p : String) : String :=
  if p.isEmpty then "."
  else
    let rooted := p.startsWith "/"
    let segs := (p.splitOn "/").filter (fun s => s != "" && s != ".")
    let stack := (segs.foldl (cleanPush rooted) []).reverse
    let body := String.intercalate "/" stack
    let res := (if rooted then "/" else "") ++ body
    if res.isEmpty then "." else res

/-- `path.Base`: the last element of `p`. Empty ⇒ `"."`; an all-slash path ⇒ `"/"`. -/
def unixBase (p : String) : String :=
  if p.isEmpty then "."
  else
    let s := stripTrailingSlash p
    if s.isEmpty then "/" else afterLastSlash s

/-- `path.Dir`: `Clean` of everything up to and including the final `/` (`"."` when there is
    none). -/
def unixDir (p : String) : String :=
  match lastSlashIndex p with
  | some i => unixClean (String.ofList (p.toList.take (i + 1)))
  | none => unixClean ""

/-- `path.Split`: split `p` immediately after the final `/` into `(dir, file)`; the `dir` keeps
    the trailing `/`. -/
def unixSplit (p : String) : String × String :=
  match lastSlashIndex p with
  | some i => (String.ofList (p.toList.take (i + 1)), String.ofList (p.toList.drop (i + 1)))
  | none => ("", p)

/-- `path.Ext`: the extension (from the last `.` of the final element, inclusive), or `""`. A
    leading-dot-only name like `.bashrc` is all extension, matching Go. -/
def unixExt (p : String) : String :=
  let base := afterLastSlash p
  match lastDotIndex base with
  | some i => String.ofList (base.toList.drop i)
  | none => ""

/-- `path.IsAbs` on unix/plan9: a leading `/`. -/
def unixIsAbs (p : String) : Bool :=
  p.startsWith "/"

/-- `path.Join`: `Clean` of the non-leading-empty elements joined by `/`. Empty (or all-empty)
    input ⇒ `""`. -/
def unixJoin (elems : List String) : String :=
  match elems.dropWhile (· == "") with
  | [] => ""
  | nonEmpty => unixClean (String.intercalate "/" nonEmpty)

/-- `path.SplitList` on unix/plan9: split on the `:` list separator. Empty input ⇒ `[]`. -/
def unixSplitList (p : String) : List String :=
  if p.isEmpty then [] else p.splitOn ":"

/-- `path.Resolve`: an absolute `sub` wins (cleaned); else `Clean(dir/sub)`. -/
def unixResolve (dir sub : String) : String :=
  if sub.startsWith "/" then unixClean sub
  else unixClean (dir ++ "/" ++ sub)

/-- Segments of a `Clean`-ed path for `Rel`, dropping the root/empty markers; a cleaned `"."`
    yields `[]` (the empty relative path). -/
def relSegments (p : String) : List String :=
  let c := unixClean p
  if c == "." then [] else (c.splitOn "/").filter (· != "")

/-- Longest common prefix length of two segment lists. -/
def commonPrefixLen : List String → List String → Nat
  | a :: as, b :: bs => if a == b then 1 + commonPrefixLen as bs else 0
  | _, _ => 0

/-- `path.Rel`: the relative path from `basep` to `targp`. `none` (⇒ bottom) when one is
    absolute and the other relative, or the base cannot be walked up to (a lone `..` remainder),
    mirroring cue's `Rel` errors. -/
def unixRel (basep targp : String) : Option String :=
  let base := unixClean basep
  let targ := unixClean targp
  if base == targ then some "."
  else if base.startsWith "/" != targ.startsWith "/" then none
  else
    let bs := relSegments basep
    let ts := relSegments targp
    let k := commonPrefixLen bs ts
    let baseRest := bs.drop k
    let targRest := ts.drop k
    if baseRest == [".."] then none
    else
      let ups := List.replicate baseRest.length ".."
      match ups ++ targRest with
      | [] => some "."
      | segs => some (String.intercalate "/" segs)

/-! ## `path.Match` — Go `filepath.Match` glob (unix/plan9)

A faithful port of cue's (Go's) shell-pattern matcher: `*` matches a run of non-`/`, `?` one
non-`/`, `[...]` a character class (`^`-negated), `\` escapes. A malformed pattern is `none`
(⇒ bottom, cue's `syntax error in pattern`); `**` is rejected. Every helper is total: fuel on
the outer/class loops (bounded by the pattern length), structural on the position scan. -/

/-- Read one possibly-escaped class char. `none` on the malformed-class conditions Go's `getEsc`
    reports: an empty chunk, a leading unescaped `-`/`]`, or nothing left after the char (an
    unterminated class). Returns the char and the remaining chunk. -/
def getEsc : List Char → Option (Char × List Char)
  | [] => none
  | c :: rest =>
    if c == '-' || c == ']' then none
    else
      let chunk := if c == '\\' then rest else c :: rest
      match chunk with
      | [] => none
      | ec :: tl => if tl.isEmpty then none else some (ec, tl)

/-- Accumulate a character class's ranges, testing rune `r`. `matched` tracks whether any range
    so far covers `r`; `nrange` gates the closing `]`. Returns `(matched, chunkAfterClass)` or
    `none` on a malformed class. Fuel bounds the range count by the chunk length. -/
def matchClassRanges (fuel : Nat) (r : Char) : List Char → Nat → Bool → Option (Bool × List Char)
  | chunk, nrange, matched =>
    match fuel with
    | 0 => none
    | fuel + 1 =>
      match chunk with
      | ']' :: rest =>
        if nrange > 0 then some (matched, rest)
        else none
      | _ =>
        match getEsc chunk with
        | none => none
        | some (lo, c1) =>
          match c1 with
          | '-' :: c2 =>
            match getEsc c2 with
            | none => none
            | some (hi, c3) =>
              let hit := lo.val ≤ r.val && r.val ≤ hi.val
              matchClassRanges fuel r c3 (nrange + 1) (matched || hit)
          | _ =>
            matchClassRanges fuel r c1 (nrange + 1) (matched || r == lo)

/-- Result of matching one non-star chunk against the head of the name. -/
inductive MatchChunk where
  | bad
  | fail
  | ok (rest : List Char)
deriving Repr, BEq

/-- Match a non-star `chunk` against the head of `s`. Like Go's `matchChunk`, it keeps scanning
    the chunk after a failure (`failed`) to surface a malformed class as `.bad`. Fuel bounds the
    step count by the chunk length. -/
def matchChunk (fuel : Nat) (chunk s : List Char) (failed : Bool) : MatchChunk :=
  match fuel with
  | 0 => .bad
  | fuel + 1 =>
    match chunk with
    | [] => if failed then .fail else .ok s
    | ch :: chunkRest =>
      let failed := failed || s.isEmpty
      match ch with
      | '[' =>
        let r := if failed then Char.ofNat 0 else s.headD (Char.ofNat 0)
        let s1 := if failed then s else s.tail
        let (negated, c0) :=
          match chunkRest with
          | '^' :: t => (true, t)
          | _ => (false, chunkRest)
        match matchClassRanges (c0.length + 1) r c0 0 false with
        | none => .bad
        | some (matched, chunkAfter) =>
          matchChunk fuel chunkAfter s1 (failed || (matched == negated))
      | '?' =>
        let (failed2, s1) :=
          if failed then (failed, s) else (s.headD (Char.ofNat 0) == '/', s.tail)
        matchChunk fuel chunkRest s1 failed2
      | '\\' =>
        match chunkRest with
        | [] => .bad
        | lit :: chunkRest2 =>
          let (failed2, s1) :=
            if failed then (failed, s) else (lit != s.headD (Char.ofNat 0), s.tail)
          matchChunk fuel chunkRest2 s1 failed2
      | other =>
        let (failed2, s1) :=
          if failed then (failed, s) else (other != s.headD (Char.ofNat 0), s.tail)
        matchChunk fuel chunkRest s1 failed2

/-- Length of the leading non-star chunk (Go's `scanChunk` end): scan until an unescaped `*`
    outside a `[...]` range. `\` skips the next char; `[`/`]` toggle the range. Structural. -/
def scanChunkLen : List Char → Bool → Nat
  | [], _ => 0
  | c :: rest, inrange =>
    match c with
    | '\\' =>
      match rest with
      | [] => 1
      | _ :: rest2 => 2 + scanChunkLen rest2 inrange
    | '[' => 1 + scanChunkLen rest true
    | ']' => 1 + scanChunkLen rest false
    | '*' => if inrange then 1 + scanChunkLen rest inrange else 0
    | _ => 1 + scanChunkLen rest inrange

/-- `scanChunk`: peel an optional leading `*` then the next non-star chunk, returning
    `(star, chunk, rest)`. `none` on `**` (rejected, as cue does). -/
def scanChunk (pattern : List Char) : Option (Bool × List Char × List Char) :=
  let (star, p1) :=
    match pattern with
    | '*' :: rest => (true, rest)
    | _ => (false, pattern)
  if star && p1.head? == some '*' then none
  else
    let i := scanChunkLen p1 false
    some (star, p1.take i, p1.drop i)

/-- Result of the `*`-skip search over name positions. -/
inductive StarSkip where
  | bad
  | fallthrough
  | cont (rest : List Char)
deriving Repr, BEq

/-- Go's star-backtracking: try `matchChunk` at each name position up to the first `/`.
    `cont t` = a usable match leaving `t` (continue the outer loop with `rest, t`); `bad` = a
    malformed chunk; `fallthrough` = no position matched. Structural on the name suffix. -/
def starSkip (chunk rest : List Char) : List Char → StarSkip
  | [] => .fallthrough
  | c :: restName =>
    if c == '/' then .fallthrough
    else
      match matchChunk (chunk.length + 1) chunk restName false with
      | .bad => .bad
      | .ok t => if rest.isEmpty && !t.isEmpty then starSkip chunk rest restName else .cont t
      | .fail => starSkip chunk rest restName

/-- Validate that the remaining pattern is syntactically well-formed (so a no-match returns
    `false`, not a spurious success). `none` on a malformed remainder. Fuel bounds the chunk
    count by the pattern length. -/
def validateRest (fuel : Nat) (pattern : List Char) : Option Bool :=
  match fuel with
  | 0 => some false
  | fuel + 1 =>
    if pattern.isEmpty then some false
    else
      match scanChunk pattern with
      | none => none
      | some (_, _, rest) => validateRest fuel rest

/-- The outer `Match` loop. `none` ⇒ malformed pattern (cue bottom); `some b` ⇒ match result.
    Fuel bounds the chunk count by the pattern length. -/
def matchLoop (fuel : Nat) (pattern name : List Char) : Option Bool :=
  match fuel with
  | 0 => none
  | fuel + 1 =>
    if pattern.isEmpty then some name.isEmpty
    else
      match scanChunk pattern with
      | none => none
      | some (star, chunk, rest) =>
        if star && chunk.isEmpty then some (!name.contains '/')
        else
          let starOrValidate : Option Bool :=
            if star then
              match starSkip chunk rest name with
              | .bad => none
              | .cont t => matchLoop fuel rest t
              | .fallthrough => validateRest (pattern.length + 1) rest
            else validateRest (pattern.length + 1) rest
          match matchChunk (chunk.length + 1) chunk name false with
          | .bad => none
          | .ok t => if t.isEmpty || !rest.isEmpty then matchLoop fuel rest t else starOrValidate
          | .fail => starOrValidate

/-- `path.Match(pattern, name)` on unix/plan9. `none` ⇒ malformed pattern. -/
def unixMatch (pattern name : String) : Option Bool :=
  matchLoop (pattern.length + 1) pattern.toList name.toList

/-! ## OS dispatch helpers (the `evalPathBuiltin` dispatch lives in `Builtin.lean`, alongside
the other `eval*Builtin` families, where `unresolvedOrBottom` is defined) -/

/-- Resolve the os argument, then either run the (eager, pure) unix/plan9 result, defer windows
    with a clear `unsupportedBuiltin`, or bottom on an invalid os string. -/
def pathDispatch (name : String) (os : String) (unixResult : Value) : Value :=
  match PathOS.ofString? os with
  | none => .bottom
  | some .windows => .bottomWith [.unsupportedBuiltin name]
  | some _ => unixResult

/-- Collect a value list as strings; a non-string element ⇒ `none` (⇒ bottom). -/
def pathAllStrings? : List Value → Option (List String)
  | [] => some []
  | .prim (.string s) :: rest => (pathAllStrings? rest).map (s :: ·)
  | _ => none

def pathStrVal (s : String) : Value := .prim (.string s)
def pathPairList (a b : String) : Value := .list [pathStrVal a, pathStrVal b]
def pathRelVal : Option String → Value
  | some s => pathStrVal s
  | none => .bottom
def pathMatchVal : Option Bool → Value
  | some b => .prim (.bool b)
  | none => .bottom

end Kue
