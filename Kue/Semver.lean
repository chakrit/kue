/-!
# Semantic-version comparison (B3d-6a, PURE)

A Lean-native, total port of Go's `golang.org/x/mod/semver` `Compare` — the exact ordering
`cue` uses for module versions (`cue` depends on this package; it is the authoritative source,
NOT strict semver.org). Versions are `vMAJOR[.MINOR[.PATCH[-PRERELEASE][+BUILD]]]`.

Authoritative source (read-only, locally): `~/go/pkg/mod/golang.org/x/mod@v0.15.0/semver/semver.go`
(`parse`, `parseInt`, `parsePrerelease`, `compareInt`, `comparePrerelease`, `nextIdent`,
`isNum`). The behaviours pinned here, mirroring that file exactly:

- `vMAJOR` and `vMAJOR.MINOR` are shorthands for `vMAJOR.0.0` / `vMAJOR.MINOR.0`.
- Numeric major/minor/patch compared by `compareInt`: shorter decimal string < longer (no
  leading zeros are allowed, so length IS magnitude order), then ASCII for equal length.
- A version WITH a prerelease sorts BEFORE the same version without (`v1.2.3-rc < v1.2.3`).
- Prerelease identifiers compared dot-by-dot: numeric-vs-numeric by length-then-ASCII,
  numeric < non-numeric, otherwise ASCII; a longer set of equal-prefix identifiers wins.
- Build metadata (`+…`) is parsed for validity but IGNORED in precedence.
- An INVALID version sorts before any valid one; two invalids compare equal (`Compare` contract).

Totality: every function is structurally/`termination_by`-justified; `parse` returns an
`Option`, comparison never throws. No `partial`, no `sorry`.
-/

namespace Kue
namespace Semver

/-- A parsed semantic version: numeric `major`/`minor`/`patch` as their *decimal digit strings*
    (Go keeps them as substrings and compares via `compareInt` — length-then-ASCII — so we keep
    the string form to reproduce that ordering exactly, never converting to `Nat`), the
    prerelease identifier list (without the leading `-`, split on `.`; empty list = no
    prerelease), and the build metadata (ignored in precedence, retained for fidelity). -/
structure Parsed where
  major : String
  minor : String
  patch : String
  prerelease : List String
  build : String
deriving Repr, BEq, DecidableEq

/-- An ASCII decimal digit `0`–`9`. -/
def isDigit (c : Char) : Bool := '0' ≤ c && c ≤ '9'

/-- An identifier character `[0-9A-Za-z-]` (`isIdentChar`). -/
def isIdentChar (c : Char) : Bool :=
  ('A' ≤ c && c ≤ 'Z') || ('a' ≤ c && c ≤ 'z') || isDigit c || c == '-'

/-- Whether every character of `s` is a decimal digit (and `s` is non-empty) — Go's `isNum`
    treats `""` as numeric (`i == len`), but every call site guarantees a non-empty identifier,
    so requiring non-empty here matches the reachable behaviour. -/
def isNum (s : String) : Bool := !s.isEmpty && s.all isDigit

/-- Go's `parseInt`: consume a leading run of digits with NO extra leading zero (a lone `0` is
    fine; `01` is rejected). Returns the digit string and the rest, or `none` if there is no
    valid integer at the head. -/
def parseInt (s : String) : Option (String × String) :=
  let cs := s.toList
  match cs with
  | [] => none
  | c :: _ =>
    if !isDigit c then none
    else
      let digits := cs.takeWhile isDigit
      -- Reject a multi-digit run starting with '0' (leading zero), per `parseInt`.
      if digits.length > 1 && digits.head? == some '0' then none
      else some (String.ofList digits, String.ofList (cs.drop digits.length))

/-- An all-numeric prerelease identifier with a leading zero is malformed (`isBadNum`):
    only-digits, length > 1, first char `'0'`. -/
def isBadNum (s : String) : Bool :=
  let cs := s.toList
  cs.all isDigit && cs.length > 1 && cs.head? == some '0'

/-- Validate one prerelease/build identifier: non-empty, all `isIdentChar`. Prerelease also
    rejects `isBadNum`; build does not. -/
def validIdent (forPrerelease : Bool) (s : String) : Bool :=
  !s.isEmpty && s.toList.all isIdentChar && (!forPrerelease || !isBadNum s)

/-- Parse the full version. `none` ⇒ invalid (sorts before all valid versions). Mirrors Go's
    `parse`: a leading `v`, then `MAJOR[.MINOR[.PATCH]]` via `parseInt` with `.0` shorthands,
    an optional `-PRERELEASE`, an optional `+BUILD`, and nothing trailing. -/
def parse (v : String) : Option Parsed := do
  let rest0 ← if v.startsWith "v" then some (v.drop 1).toString else none
  let (major, r1) ← parseInt rest0
  if r1.isEmpty then
    return { major, minor := "0", patch := "0", prerelease := [], build := "" }
  let r1' ← if r1.startsWith "." then some (r1.drop 1).toString else none
  let (minor, r2) ← parseInt r1'
  if r2.isEmpty then
    return { major, minor, patch := "0", prerelease := [], build := "" }
  let r2' ← if r2.startsWith "." then some (r2.drop 1).toString else none
  let (patch, r3) ← parseInt r2'
  -- Split off the optional `-prerelease` and `+build` tails. `hasPre`/`hasBuild` record
  -- whether the marker was actually present, so an EMPTY tail (`v1.2.3-`, `v1.2.3+`,
  -- `v1.2.3-a+`) is rejected exactly as Go's `parsePrerelease`/`parseBuild` reject `start == i`,
  -- rather than being conflated with "no tail at all".
  let (hasPre, preStr, afterPre) :=
    if r3.startsWith "-" then
      let body := (r3.drop 1).toString
      match body.splitOn "+" with
      | pre :: rest => (true, pre, if rest.isEmpty then "" else "+" ++ String.intercalate "+" rest)
      | [] => (true, "", "")
    else (false, "", r3)
  let (hasBuild, buildStr, tail) :=
    if afterPre.startsWith "+" then (true, (afterPre.drop 1).toString, "")
    else if !hasPre && r3.startsWith "+" then (true, (r3.drop 1).toString, "")
    else (false, "", afterPre)
  if !tail.isEmpty then none
  -- An empty prerelease/build segment after its marker is malformed.
  else if hasPre && preStr.isEmpty then none
  else if hasBuild && buildStr.isEmpty then none
  else
    -- Validate prerelease identifiers (each non-empty, valid, not bad-num).
    let preIds := if preStr.isEmpty then [] else preStr.splitOn "."
    if !preStr.isEmpty ∧ !preIds.all (validIdent true) then none
    else
      let buildIds := if buildStr.isEmpty then [] else buildStr.splitOn "."
      if !buildStr.isEmpty ∧ !buildIds.all (validIdent false) then none
      else some { major, minor, patch, prerelease := preIds, build := buildStr }

/-- Go's `compareInt` on two no-leading-zero decimal strings: shorter < longer, else ASCII.
    Returns `-1`/`0`/`+1`. -/
def compareInt (x y : String) : Int :=
  if x == y then 0
  else if x.length < y.length then -1
  else if x.length > y.length then 1
  else if x < y then -1 else 1

/-- Compare two single prerelease identifiers (`comparePrerelease`'s inner rule): numeric <
    non-numeric; two numerics by length-then-ASCII; otherwise ASCII. -/
def compareIdent (x y : String) : Int :=
  if x == y then 0
  else
    let nx := isNum x
    let ny := isNum y
    if nx != ny then (if nx then -1 else 1)
    else if nx then
      -- both numeric (no leading zeros): length then ASCII
      if x.length < y.length then -1
      else if x.length > y.length then 1
      else if x < y then -1 else 1
    else if x < y then -1 else 1

/-- Identifier-list comparison once BOTH versions are known to have a prerelease: dot-by-dot,
    and on exhaustion the SHORTER set is lower ("a larger set of pre-release fields has a higher
    precedence, if all preceding identifiers are equal"). This is the inner loop of Go's
    `comparePrerelease` AFTER its top-level empty-string checks. Returns `-1`/`0`/`+1`. -/
def comparePrereleaseIds : List String → List String → Int
  | [], [] => 0
  | [], _ :: _ => -1    -- ran out first ⇒ shorter set, lower precedence
  | _ :: _, [] => 1
  | x :: xs, y :: ys =>
    let c := compareIdent x y
    if c != 0 then c else comparePrereleaseIds xs ys

/-- Full prerelease comparison (`comparePrerelease`): an EMPTY list means "no prerelease", which
    sorts AFTER (higher than) any non-empty list; two non-empty lists compare by
    `comparePrereleaseIds`. Returns `-1`/`0`/`+1`. -/
def comparePrerelease : List String → List String → Int
  | [], [] => 0
  | [], _ :: _ => 1     -- no prerelease > has prerelease
  | _ :: _, [] => -1
  | xs@(_ :: _), ys@(_ :: _) => comparePrereleaseIds xs ys

/-- Compare two semantic versions per Go's `semver.Compare`: invalid < valid, two invalids
    equal; else numeric major/minor/patch, then prerelease. Build metadata ignored. Returns
    `-1`/`0`/`+1`. Total. -/
def compare (v w : String) : Int :=
  match parse v, parse w with
  | none, none => 0
  | none, some _ => -1
  | some _, none => 1
  | some pv, some pw =>
    let cMaj := compareInt pv.major pw.major
    if cMaj != 0 then cMaj else
    let cMin := compareInt pv.minor pw.minor
    if cMin != 0 then cMin else
    let cPat := compareInt pv.patch pw.patch
    if cPat != 0 then cPat else
    comparePrerelease pv.prerelease pw.prerelease

/-- `true` iff `v < w` under `compare`. -/
def lt (v w : String) : Bool := compare v w < 0

/-- The greater of `v` and `w` under `compare`, returning the SECOND argument on a tie (so
    `max v w == w` whenever `v ≤ w`). Used by MVS to fold a per-path maximum. -/
def maxVersion (v w : String) : String :=
  if compare v w > 0 then v else w

/-- `true` iff `v` parses as a valid semantic version (`IsValid`). -/
def isValid (v : String) : Bool := (parse v).isSome

end Semver
end Kue
