/-
Regex AST + parser for Kue (RX-1a).

A true leaf module: depends only on `Char`/`String` from core, with NO `Value`/`Eval`
import, so the regex engine (compile + Pike-VM in RX-1b) can live free of the lattice's
`DecidableEq` perf carve-out and `Value.lean` can later shed its hand-rolled matcher.

The CUE spec mandates RE2 semantics ("the regular expression syntax is that accepted by
RE2 … except for `\C`"). This file implements the RE2-subset AST and a total
recursive-descent parser. No engine wiring yet (RX-1b/c); the parser is independently
testable. Invalid patterns become `Except.error`, NEVER a silent literal-fallback (the
old `Value.lean` engine's unsound behavior).
-/

namespace Kue

/-- Reason a pattern could not be parsed. Distinguishes genuine syntax errors from RE2
    constructs Kue defers (stub-not-silent-wrong). -/
inductive RegexParseError where
  /-- Generic malformed pattern (unbalanced `(`, dangling `\`, bad `{m,n}`, etc.). -/
  | malformed (message : String)
  /-- A backreference `\1` … `\9`. RE2 has no backreferences by design — a parse error,
      distinct from `ReplaceAll`'s `${n}` replacement-template grammar (RX-1c). -/
  | backreference (digit : Char)
  /-- A construct in RE2 that Kue has not implemented yet: named captures `(?P<…>)`,
      flags `(?i)`/`(?m)`/`(?s)`, `\A`/`\z`/`\Q…\E`, POSIX classes `[[:alpha:]]`, Unicode
      property classes `\p{…}`/`\pL`. Surfaced explicitly, never silently mis-parsed. -/
  | unsupportedRegex (feature : String)
deriving Repr, BEq, DecidableEq

/-- RE2-subset regex AST. Total, illegal-states-unrepresentable.

    Greediness is a `Bool` FIELD on each quantifier (not a separate lazy constructor) so
    the match-priority logic stays in one place. `repeat` carries `max : Option Nat` so
    `{m,}` is representable without a sentinel. `group`'s `index` is `none` for the
    non-capturing `(?:…)` and `some i` for a capturing group (i assigned left-to-right at
    parse time, starting at 1). -/
inductive Regex where
  /-- ε — the empty match (e.g. an empty alternation branch `(a|)`). -/
  | empty
  | lit (c : Char)
  /-- A character class: a union of inclusive ranges, optionally negated (`[^…]`). Perl
      classes `\d \w \s` desugar to ranges here; their negations either flip `negated` (as
      a standalone atom) or — inside a `[…]` — fold their ranges in. -/
  | cls (ranges : List (Char × Char)) (negated : Bool)
  /-- `.` — any char except newline (RE2 default, no `(?s)` flag). -/
  | any
  | anchorStart
  | anchorEnd
  /-- `\b` (negated = false) / `\B` (negated = true). -/
  | wordBoundary (negated : Bool)
  | concat (parts : List Regex)
  | alt (branches : List Regex)
  | star (greedy : Bool) (body : Regex)
  | plus (greedy : Bool) (body : Regex)
  | opt (greedy : Bool) (body : Regex)
  | «repeat» (greedy : Bool) (min : Nat) (max : Option Nat) (body : Regex)
  | group (index : Option Nat) (body : Regex)
deriving Repr, BEq

namespace Regex

/-- Perl `\d` digit ranges. -/
def digitRanges : List (Char × Char) := [('0', '9')]

/-- Perl `\w` word ranges. -/
def wordRanges : List (Char × Char) := [('0', '9'), ('A', 'Z'), ('_', '_'), ('a', 'z')]

/-- Perl `\s` whitespace ranges (RE2: `[\t\n\f\r ]`). -/
def spaceRanges : List (Char × Char) :=
  [('\t', '\t'), ('\n', '\n'), ('\x0C', '\x0C'), ('\r', '\r'), (' ', ' ')]

/-- The greatest Unicode scalar value (`U+10FFFF`); the upper bound of the `Char` domain a
    class complement is taken over. The surrogate hole `[U+D800, U+DFFF]` is irrelevant to
    matching (no input `Char` is a surrogate), so the complement may span it freely. -/
def maxCodePoint : Nat := 0x10FFFF

/-- Set-complement of a union of code-point ranges over the whole `Char` domain
    `[0, maxCodePoint]`. This is how a NEGATED shorthand (`\D`/`\W`/`\S`) folds into a `[…]`
    class: `\D` = `complementRanges digitRanges`, etc. — the complement is itself a union of
    ranges, so it composes with other class members through the ordinary range union (no new
    "signed member" state, and whole-class `[^…]` negation then flips the folded result).

    Total: sort the input by lower bound (`mergeSort`), fold once emitting the gaps between
    consecutive covered spans (an overlapping/nested range advances the cursor by `max`, so a
    gap is never inverted), then the tail gap up to `maxCodePoint`. Endpoints are rebuilt with
    `Char.ofNat`; for the ASCII perl sets every gap boundary is a valid scalar (`Char.ofNat`
    clamps invalid inputs, but no boundary here lands on a surrogate). -/
def complementRanges (ranges : List (Char × Char)) : List (Char × Char) :=
  let sorted := (ranges.map (fun r => (r.1.toNat, r.2.toNat))).mergeSort (fun a b => a.1 ≤ b.1)
  -- `cursor` is the lowest code point not yet covered; `acc` collects gap pairs (reversed).
  let (cursor, acc) := sorted.foldl
    (fun (st : Nat × List (Nat × Nat)) r =>
      let (cursor, acc) := st
      let (lo, hi) := r
      let acc := if lo > cursor then (cursor, lo - 1) :: acc else acc
      (Nat.max cursor (hi + 1), acc))
    (0, [])
  let acc := if cursor ≤ maxCodePoint then (cursor, maxCodePoint) :: acc else acc
  acc.reverse.map (fun g => (Char.ofNat g.1, Char.ofNat g.2))

end Regex

/-- Parser state threaded through the recursive descent: the remaining input and the next
    capturing-group index to assign (left-to-right, from 1). -/
structure RegexParseState where
  rest : List Char
  nextGroup : Nat
deriving Repr

namespace RegexParse

open Regex

/-- Is `c` a decimal digit? -/
private def isDigit (c : Char) : Bool := '0' ≤ c && c ≤ '9'

private def digitVal (c : Char) : Nat := c.toNat - '0'.toNat

/-- Read a maximal run of decimal digits: returns the parsed value, whether ≥1 digit was
    consumed, and the remainder. Total (structural on the list). -/
private def takeNat : List Char → Nat → Bool → (Nat × Bool × List Char)
  | c :: rest, acc, seen =>
      if isDigit c then takeNat rest (acc * 10 + digitVal c) true
      else (acc, seen, c :: rest)
  | [], acc, seen => (acc, seen, [])

/-- A `\`-escape used INSIDE a `[…]` class: yields a set of ranges to fold into the class
    union (perl class, a negated perl class via set-complement, or a single literal char as a
    degenerate range) or an error. A NEGATED shorthand (`\D`/`\W`/`\S`) folds its full
    complement set into the union (`[\D5]` = non-digits ∪ {5}); whole-class `[^…]` negation is
    applied AFTER the fold by `parseClass`'s `negated` flag, so `[^\D]` correctly yields the
    digits. -/
private def parseClassEscape : List Char → Except RegexParseError (List (Char × Char) × List Char)
  | 'd' :: rest => .ok (digitRanges, rest)
  | 'w' :: rest => .ok (wordRanges, rest)
  | 's' :: rest => .ok (spaceRanges, rest)
  | 'D' :: rest => .ok (complementRanges digitRanges, rest)
  | 'W' :: rest => .ok (complementRanges wordRanges, rest)
  | 'S' :: rest => .ok (complementRanges spaceRanges, rest)
  | 'n' :: rest => .ok ([('\n', '\n')], rest)
  | 't' :: rest => .ok ([('\t', '\t')], rest)
  | 'r' :: rest => .ok ([('\r', '\r')], rest)
  | 'f' :: rest => .ok ([('\x0C', '\x0C')], rest)
  | 'v' :: rest => .ok ([('\x0B', '\x0B')], rest)
  | 'a' :: rest => .ok ([('\x07', '\x07')], rest)
  | 'p' :: _ => .error (.unsupportedRegex "\\p Unicode property class")
  | 'P' :: _ => .error (.unsupportedRegex "\\P Unicode property class")
  | c :: rest => .ok ([(c, c)], rest)
  | [] => .error (.malformed "dangling backslash in character class")

/-- Parse the body of a `[…]` class (the leading `[` and optional `^` already consumed).
    Accumulates ranges until the closing `]`. Handles `a-z` ranges, `\d`/`\w`/`\s` and
    single escapes, and a literal `]` only if it is the FIRST char (RE2 rule) — handled by
    the caller seeding it. POSIX `[[:alpha:]]` is detected and deferred. Structural on the
    input list (each branch consumes ≥1 char). -/
private def parseClassBody :
    Nat → List Char → List (Char × Char) → Except RegexParseError (List (Char × Char) × List Char)
  | 0, _, _ => .error (.malformed "character class parser fuel exhausted")
  | _ + 1, [], _ => .error (.malformed "unterminated character class")
  | _ + 1, ']' :: rest, acc => .ok (acc.reverse, rest)
  | _ + 1, '[' :: ':' :: _, _ => .error (.unsupportedRegex "POSIX character class [[:…:]]")
  | fuel + 1, '\\' :: rest, acc =>
      match parseClassEscape rest with
      | .ok (ranges, rest') => parseClassBody fuel rest' (ranges.reverse ++ acc)
      | .error e => .error e
  | fuel + 1, lo :: '-' :: ']' :: rest, acc =>
      -- a trailing `-` before `]` is a literal dash, not a range opener
      parseClassBody fuel (']' :: rest) ((lo, lo) :: ('-', '-') :: acc)
  | fuel + 1, lo :: '-' :: hi :: rest, acc =>
      if lo ≤ hi then parseClassBody fuel rest ((lo, hi) :: acc)
      else .error (.malformed "character class range out of order")
  | fuel + 1, c :: rest, acc => parseClassBody fuel rest ((c, c) :: acc)

/-- Parse a `[…]`/`[^…]` class (leading `[` already consumed). Fuel = remaining length + 1
    bounds the body scan (each step consumes ≥1 char). -/
private def parseClass (input : List Char) : Except RegexParseError (Regex × List Char) :=
  let (negated, body) := match input with
    | '^' :: rest => (true, rest)
    | _ => (false, input)
  let fuel := body.length + 2
  -- a `]` immediately after `[` (or `[^`) is a literal `]`, not a close
  match body with
  | ']' :: rest =>
      match parseClassBody fuel rest [(']', ']')] with
      | .ok (ranges, rest') => .ok (.cls ranges negated, rest')
      | .error e => .error e
  | _ =>
      match parseClassBody fuel body [] with
      | .ok (ranges, rest') => .ok (.cls ranges negated, rest')
      | .error e => .error e

/-- A `\`-escape as a standalone atom (outside a class). -/
private def parseAtomEscape : List Char → Except RegexParseError (Regex × List Char)
  | 'd' :: rest => .ok (.cls digitRanges false, rest)
  | 'D' :: rest => .ok (.cls digitRanges true, rest)
  | 'w' :: rest => .ok (.cls wordRanges false, rest)
  | 'W' :: rest => .ok (.cls wordRanges true, rest)
  | 's' :: rest => .ok (.cls spaceRanges false, rest)
  | 'S' :: rest => .ok (.cls spaceRanges true, rest)
  | 'b' :: rest => .ok (.wordBoundary false, rest)
  | 'B' :: rest => .ok (.wordBoundary true, rest)
  | 'n' :: rest => .ok (.lit '\n', rest)
  | 't' :: rest => .ok (.lit '\t', rest)
  | 'r' :: rest => .ok (.lit '\r', rest)
  | 'f' :: rest => .ok (.lit '\x0C', rest)
  | 'v' :: rest => .ok (.lit '\x0B', rest)
  | 'a' :: rest => .ok (.lit '\x07', rest)
  | 'A' :: _ => .error (.unsupportedRegex "\\A anchor")
  | 'z' :: _ => .error (.unsupportedRegex "\\z anchor")
  | 'Q' :: _ => .error (.unsupportedRegex "\\Q…\\E literal span")
  | 'p' :: _ => .error (.unsupportedRegex "\\p Unicode property class")
  | 'P' :: _ => .error (.unsupportedRegex "\\P Unicode property class")
  | c :: rest =>
      if isDigit c && c != '0' then .error (.backreference c)
      else .ok (.lit c, rest)
  | [] => .error (.malformed "dangling backslash at end of pattern")

/-- Outcome of inspecting a `{…}` suffix after a quantifiable atom. -/
private inductive RepeatParse where
  /-- A well-formed quantifier `{m}`/`{m,}`/`{m,n}`. -/
  | quant (min : Nat) (max : Option Nat) (rest : List Char)
  /-- Brace shape is a valid repeat form but the count is illegal (e.g. `{5,2}`). RE2/cue
      reject this; we surface a parse error rather than fall back to a literal `{`. -/
  | invalid
  /-- Not a repeat at all (`{` with no digits, `{abc}`, …) — caller treats `{` as a
      literal. -/
  | notQuant

/-- RE2's repeat-count ceiling (`maxRepeat`): a bound `> 1000` is rejected, both for
    conformance (cue/RE2 raise `invalid repeat count`) and to bound `desugar`'s expansion
    (it unfolds `{m,n}` into `n` copies/optionals, so an uncapped `{0,1e8}` is a blowup). -/
private def maxRepeat : Nat := 1000

private def parseRepeatSuffix : List Char → RepeatParse
  | input =>
      match takeNat input 0 false with
      | (m, true, '}' :: rest) =>
          if m > maxRepeat then .invalid else .quant m (some m) rest
      | (m, true, ',' :: rest) =>
          match takeNat rest 0 false with
          | (n, true, '}' :: rest') =>
              if m ≤ n && n ≤ maxRepeat then .quant m (some n) rest' else .invalid
          | (_, false, '}' :: rest') =>
              if m > maxRepeat then .invalid else .quant m none rest'  -- {m,}
          | _ => .notQuant
      | _ => .notQuant

/-! The core descent. `alt → concat → quantified → atom`, mutually recursive through
    `group`. Lean cannot see structural decrease across the mutual cycle, so we thread an
    input-length fuel (the standing parser exception); each recursive call passes strictly
    less fuel, and atom consumption is bounded by the input, so the bound is exact and
    never spuriously reached. -/

mutual

/-- alt = concat (`|` concat)* — splits on top-level `|`. -/
private def pAlt (fuel : Nat) (s : RegexParseState) :
    Except RegexParseError (Regex × RegexParseState) :=
  match fuel with
  | 0 => .error (.malformed "regex parser fuel exhausted")
  | fuel + 1 =>
      match pConcatLoop fuel s [] with
      | .error e => .error e
      | .ok (first, s') =>
          match s'.rest with
          | '|' :: rest =>
              match pAlt fuel { s' with rest := rest } with
              | .error e => .error e
              | .ok (restAlt, s'') =>
                  let branches := match restAlt with
                    | .alt bs => first :: bs
                    | other => [first, other]
                  .ok (.alt branches, s'')
          | _ => .ok (first, s')
  termination_by fuel

/-- The accumulating loop for concat: gathers `quantified*` atoms until `|`, `)`, or end of
    input. Lifted into the mutual block so it shares the fuel measure. `acc` holds parsed
    atoms in reverse. -/
private def pConcatLoop (fuel : Nat) (st : RegexParseState) (acc : List Regex) :
    Except RegexParseError (Regex × RegexParseState) :=
  match fuel with
  | 0 => .error (.malformed "regex parser fuel exhausted")
  | fuel + 1 =>
      match st.rest with
      | [] | '|' :: _ | ')' :: _ =>
          let parts := acc.reverse
          let node := match parts with
            | [] => .empty
            | [single] => single
            | _ => .concat parts
          .ok (node, st)
      | _ =>
          match pQuantified fuel st with
          | .error e => .error e
          | .ok (atom, st') => pConcatLoop fuel st' (atom :: acc)
  termination_by fuel

/-- quantified = atom quantifier? where quantifier ∈ `* + ? {m,n}` optionally `?`-suffixed
    for laziness. -/
private def pQuantified (fuel : Nat) (s : RegexParseState) :
    Except RegexParseError (Regex × RegexParseState) :=
  match fuel with
  | 0 => .error (.malformed "regex parser fuel exhausted")
  | fuel + 1 =>
      match pAtom fuel s with
      | .error e => .error e
      | .ok (atom, s') =>
          let applyGreed (mk : Bool → Regex) (rest : List Char) :
              Except RegexParseError (Regex × RegexParseState) :=
            match rest with
            | '?' :: rest' => .ok (mk false, { s' with rest := rest' })
            | _ => .ok (mk true, { s' with rest := rest })
          match s'.rest with
          | '*' :: rest => applyGreed (fun g => .star g atom) rest
          | '+' :: rest => applyGreed (fun g => .plus g atom) rest
          | '?' :: rest => applyGreed (fun g => .opt g atom) rest
          | '{' :: rest =>
              match parseRepeatSuffix rest with
              | .quant m mx rest' => applyGreed (fun g => .«repeat» g m mx atom) rest'
              | .invalid => .error (.malformed "invalid repeat count in {m,n}")
              | .notQuant => .ok (atom, s')  -- bare `{` ⇒ literal (atom already the lit before `{`)
          | _ => .ok (atom, s')
  termination_by fuel

/-- atom = group | class | escape | `.` | anchor | literal. -/
private def pAtom (fuel : Nat) (s : RegexParseState) :
    Except RegexParseError (Regex × RegexParseState) :=
  match fuel with
  | 0 => .error (.malformed "regex parser fuel exhausted")
  | fuel + 1 =>
      match s.rest with
      | [] => .error (.malformed "expected an atom")
      | '(' :: '?' :: ':' :: rest => pGroupTail fuel none { s with rest := rest }
      | '(' :: '?' :: 'P' :: _ => .error (.unsupportedRegex "named capture (?P<…>)")
      | '(' :: '?' :: _ => .error (.unsupportedRegex "inline flags / group modifier (?…)")
      | '(' :: rest =>
          let idx := s.nextGroup
          pGroupTail fuel (some idx) { rest := rest, nextGroup := idx + 1 }
      | ')' :: _ => .error (.malformed "unexpected )")
      | '[' :: rest =>
          match parseClass rest with
          | .ok (node, rest') => .ok (node, { s with rest := rest' })
          | .error e => .error e
      | '\\' :: rest =>
          match parseAtomEscape rest with
          | .ok (node, rest') => .ok (node, { s with rest := rest' })
          | .error e => .error e
      | '.' :: rest => .ok (.any, { s with rest := rest })
      | '^' :: rest => .ok (.anchorStart, { s with rest := rest })
      | '$' :: rest => .ok (.anchorEnd, { s with rest := rest })
      | '*' :: _ | '+' :: _ | '?' :: _ => .error (.malformed "nothing to repeat")
      | c :: rest => .ok (.lit c, { s with rest := rest })
  termination_by fuel

/-- Parse a group body up to its closing `)`. The opening `(` (and any `?:` / index
    assignment) is already handled by the caller; `index` is the capture slot. -/
private def pGroupTail (fuel : Nat) (index : Option Nat) (s : RegexParseState) :
    Except RegexParseError (Regex × RegexParseState) :=
  match fuel with
  | 0 => .error (.malformed "regex parser fuel exhausted")
  | fuel + 1 =>
      match pAlt fuel s with
      | .error e => .error e
      | .ok (body, s') =>
          match s'.rest with
          | ')' :: rest => .ok (.group index body, { s' with rest := rest })
          | _ => .error (.malformed "unbalanced ( — missing )")
  termination_by fuel

end

end RegexParse

open RegexParse in
/-- Parse a regex pattern into the RE2-subset AST. Total via input-length fuel (the
    standing parser exception). Returns `.error` on any invalid or deferred construct —
    NEVER a silent literal-fallback. Capturing groups are numbered left-to-right from 1. -/
def parseRegex (pattern : String) : Except RegexParseError Regex :=
  let chars := pattern.toList
  -- Fuel: each descent step strips ≥1 char or recurses into a strictly smaller suffix; the
  -- mutual cycle (alt↔concat↔quantified↔atom↔group) can recurse without consuming on a
  -- single char (a `(`), so budget generously: a small multiple of the input length plus a
  -- floor for tiny/degenerate patterns. Exact bound, never spuriously reached.
  let fuel := (chars.length + 1) * 4 + 16
  match pAlt fuel { rest := chars, nextGroup := 1 } with
  | .error e => .error e
  | .ok (node, s) =>
      match s.rest with
      | [] => .ok node
      | ')' :: _ => .error (.malformed "unbalanced ) — too many close parens")
      | _ => .error (.malformed "unconsumed input after parse")

/-! ## RX-1b — Thompson compile + Pike-VM (total, linear)

    The matcher is a three-stage pipeline: parse (above) → compile to a flat instruction
    program (`compile`) → simulate with a Pike-VM (`run`). The VM carries capture slots
    even though `matchRegex` only needs the bool, so RX-1c's submatch / `ReplaceAll` reuse
    the same engine. No backtracking → linear in `input.length × program.size`; total. -/

/-- A zero-width assertion an `assert` instruction tests at the current input position. -/
inductive AssertKind where
  | start         -- ^  : at the beginning of input (RE2 default, no `(?m)`)
  | «end»         -- $  : at the end of input
  | wordBoundary  -- \b : between a word char and a non-word char
  | notWordBoundary -- \B
deriving Repr, BEq, DecidableEq

/-- A single Pike-VM instruction in the flat program. `next`/`a`/`b` are absolute pcs into
    the program array; `accept` has no successor. The split-arm ORDER encodes greediness
    (a tried before b), and "first thread to `accept` wins" gives RE2 leftmost-greedy/lazy
    priority. -/
inductive Inst where
  /-- Consume one char matching the class (or its complement when `negated`). -/
  | char (ranges : List (Char × Char)) (negated : Bool) (next : Nat)
  /-- Consume any char except newline (RE2 `.`). -/
  | any (next : Nat)
  /-- ε-fork: try `a`, then `b`. Order is the laziness mechanism. -/
  | split (a : Nat) (b : Nat)
  | jmp (next : Nat)
  /-- Record the current input position into capture `slot` (Pike submatch). -/
  | save (slot : Nat) (next : Nat)
  /-- Zero-width assertion; proceeds to `next` only if it holds at the position. -/
  | assert (kind : AssertKind) (next : Nat)
  | accept
deriving Repr, BEq

/-- A compiled program: a flat instruction array plus its entry pc and the count of capture
    slots (`2 * (#groups + 1)`; slots 0/1 bracket the whole match). -/
structure NFA where
  insts : Array Inst
  start : Nat
  slots : Nat
deriving Repr

namespace Compile

open Regex

/-- Highest capturing-group index referenced anywhere in the AST (0 when none). Used to
    size the capture-slot array. Structural recursion on the finite AST → total. -/
def maxGroupIndex : Regex → Nat
  | .group (some i) body => Nat.max i (maxGroupIndex body)
  | .group none body => maxGroupIndex body
  | .concat parts => parts.foldl (fun acc r => Nat.max acc (maxGroupIndex r)) 0
  | .alt branches => branches.foldl (fun acc r => Nat.max acc (maxGroupIndex r)) 0
  | .star _ body | .plus _ body | .opt _ body | .«repeat» _ _ _ body =>
      maxGroupIndex body
  | _ => 0

/-- Emit one instruction, returning the program with it appended and its pc. -/
private def emit (prog : Array Inst) (i : Inst) : Array Inst × Nat :=
  (prog.push i, prog.size)

/-! ### Desugar bounded repetition to `repeat`-free AST

    `{m,n}` is rewritten to a concat of exact + optional copies BEFORE compilation, so the
    Pike-VM never sees a counter (RE2 does this). The desugaring runs over an
    ALREADY-desugared body, so its helpers don't recurse through `desugar` and the whole
    pass is total. -/

/-- `n` copies of `body` in sequence (the mandatory `{m}` prefix). Structural on `Nat`. -/
private def replicateExact : Nat → Regex → List Regex
  | 0, _ => []
  | n + 1, body => body :: replicateExact n body

/-- `n` nested optionals: `(body(body(…)?)?)?` — the optional `{m,n}` tail. Structural on
    `Nat`. -/
private def nestedOpts (greedy : Bool) : Nat → Regex → Regex
  | 0, _ => .empty
  | n + 1, body => .opt greedy (.concat [body, nestedOpts greedy n body])

/-- Expand a `repeat` whose body is already desugared. `{m,}` = `m` copies then `*`;
    `{m,n}` = `m` copies then `n-m` nested optionals. -/
private def expandRepeat (greedy : Bool) (min : Nat) (max : Option Nat) (body : Regex) : Regex :=
  match max with
  | none => .concat (replicateExact min body ++ [.star greedy body])
  | some hi => .concat (replicateExact min body ++ [nestedOpts greedy (hi - min) body])

/-- Eliminate every `repeat` node, leaving an equivalent `repeat`-free AST. Structural
    recursion on the AST (each child is desugared first; `expandRepeat`/the list maps do not
    re-enter `desugar`), so TOTAL. -/
def desugar : Regex → Regex
  | .concat parts => .concat (parts.attach.map (fun ⟨p, _⟩ => desugar p))
  | .alt branches => .alt (branches.attach.map (fun ⟨b, _⟩ => desugar b))
  | .star g body => .star g (desugar body)
  | .plus g body => .plus g (desugar body)
  | .opt g body => .opt g (desugar body)
  | .group i body => .group i (desugar body)
  | .«repeat» g min max body => expandRepeat g min max (desugar body)
  | atom => atom

mutual

/-- Compile a `repeat`-free `re` so that, after matching, control flows to pc `cont`. Returns
    the extended program and this fragment's entry pc. Pure Thompson construction. The
    `concat`/`alt` list cases recurse via the mutual `compileSeq`/`compileAlt` so termination
    is by `sizeOf` of the AST (each recursive call is on a strict sub-term). TOTAL. -/
def compileFrag (prog : Array Inst) (re : Regex) (cont : Nat) : Array Inst × Nat :=
  match re with
  | .empty => (prog, cont)
  | .lit c => emit prog (Inst.char [(c, c)] false cont)
  | .cls ranges negated => emit prog (Inst.char ranges negated cont)
  | .any => emit prog (Inst.any cont)
  | .anchorStart => emit prog (Inst.assert .start cont)
  | .anchorEnd => emit prog (Inst.assert .end cont)
  | .wordBoundary negated =>
      emit prog (Inst.assert (if negated then .notWordBoundary else .wordBoundary) cont)
  | .concat parts => compileSeq prog parts cont
  | .alt branches => compileAlt prog branches cont
  | .group (some i) body =>
      let (p1, eClose) := emit prog (Inst.save (2 * i + 1) cont)
      let (p2, eBody) := compileFrag p1 body eClose
      emit p2 (Inst.save (2 * i) eBody)
  | .group none body => compileFrag prog body cont
  | .star greedy body =>
      -- L: split(body, cont) ; body → L  (greedy: body arm first; lazy: cont arm first)
      let split := prog.size
      let p0 := prog.push (Inst.split 0 0)          -- placeholder, patched below
      let (p1, eBody) := compileFrag p0 body split
      let patched :=
        if greedy then p1.set! split (Inst.split eBody cont)
        else p1.set! split (Inst.split cont eBody)
      (patched, split)
  | .plus greedy body =>
      -- body → L ; L: split(body, cont)
      let (p1, split) := emit prog (Inst.split 0 0)  -- reserve the split slot first
      let (p2, eBody) := compileFrag p1 body split
      let patched :=
        if greedy then p2.set! split (Inst.split eBody cont)
        else p2.set! split (Inst.split cont eBody)
      (patched, eBody)
  | .opt greedy body =>
      let (p1, eBody) := compileFrag prog body cont
      if greedy then emit p1 (Inst.split eBody cont)
      else emit p1 (Inst.split cont eBody)
  | .«repeat» _ _ _ _ =>
      -- `compile` runs `desugar` first, so no `repeat` reaches here; ε keeps the function
      -- total and structural (the case is provably dead, never silent-wrong in practice).
      (prog, cont)

/-- Compile a concat right-to-left so each part flows into the next. -/
def compileSeq (prog : Array Inst) (parts : List Regex) (cont : Nat) : Array Inst × Nat :=
  match parts with
  | [] => (prog, cont)
  | p :: rest =>
      let (p1, eRest) := compileSeq prog rest cont
      compileFrag p1 p eRest

/-- Compile an alternation into a chain of `split`s; arm order = match priority. -/
def compileAlt (prog : Array Inst) (branches : List Regex) (cont : Nat) : Array Inst × Nat :=
  match branches with
  | [] => (prog, cont)
  | [single] => compileFrag prog single cont
  | first :: rest =>
      let (p1, e1) := compileFrag prog first cont
      let (p2, e2) := compileAlt p1 rest cont
      emit p2 (Inst.split e1 e2)

end

end Compile

open Compile in
/-- Thompson-compile an AST into a flat program. Prepends `save 0` / appends `save 1` +
    `accept` to bracket the whole match in slots 0/1. TOTAL (structural on the AST). -/
def compile (re : Regex) : NFA :=
  let re := Compile.desugar re
  let groups := Compile.maxGroupIndex re
  let slots := 2 * (groups + 1)
  -- Emit `accept` at pc 0, then `save 1 → accept`, the body → (save 1), and `save 0 → body`
  -- so slots 0/1 bracket the whole match. Entry is the final `save 0`.
  let progAccept := (#[] : Array Inst).push Inst.accept
  let accept := 0
  let (p1, eClose) := Compile.emit progAccept (Inst.save 1 accept)
  let (p2, eBody) := compileFrag p1 re eClose
  let (p3, eStart) := Compile.emit p2 (Inst.save 0 eBody)
  { insts := p3, start := eStart, slots := slots }

namespace Vm

/-- Is `c` a word char (`[0-9A-Za-z_]`) — RE2's `\w`, the class `\b` is defined against. -/
private def isWordChar (c : Char) : Bool :=
  ('0' ≤ c && c ≤ '9') || ('A' ≤ c && c ≤ 'Z') || ('a' ≤ c && c ≤ 'z') || c == '_'

private def classMatches (ranges : List (Char × Char)) (negated : Bool) (c : Char) : Bool :=
  let inRange := ranges.any fun r => r.1 ≤ c && c ≤ r.2
  if negated then !inRange else inRange

/-- Does the zero-width assertion hold at the cursor? `prev`/`next?` are the chars
    immediately before/after the cursor (`none` at the respective edge); `atStart`/`atEnd`
    flag the input ends. -/
private def assertHolds (kind : AssertKind) (atStart atEnd : Bool)
    (prev : Option Char) (next? : Option Char) : Bool :=
  match kind with
  | .start => atStart
  | .end => atEnd
  | .wordBoundary | .notWordBoundary =>
      let before := match prev with | some c => isWordChar c | none => false
      let after := match next? with | some c => isWordChar c | none => false
      let boundary := before != after
      match kind with
      | .notWordBoundary => !boundary
      | _ => boundary

/-- A live thread: a program counter and its capture array. -/
structure Thread where
  pc : Nat
  caps : Array (Option Nat)
deriving Repr

/-- The ε-closure accumulator at one input position: threads parked on a `char`/`any`
    (in priority order, ready to consume the next char) and the captures of the first thread
    to reach `accept` here. `visited` dedups by pc so each instruction enters the closure at
    most once per position. -/
structure Closure where
  ready : Array Thread
  matched : Option (Array (Option Nat))
  visited : Array Bool

/-- Follow the ε-closure from `pc`, recording char/any threads into `cl.ready` and the first
    `accept` into `cl.matched`. `pos` is the current cursor offset (for `save`).

    TOTAL: structural recursion on `fuel`, seeded to `insts.size`. `visited` admits each pc
    at most once, so the ε-walk visits ≤ `insts.size` distinct pcs and the fuel is provably
    sufficient AND never spuriously exhausted — a `split`/`jmp` cycle re-hitting a pc is
    cut by `visited`, not by fuel. Priority order is preserved: `split`'s arm `a` is walked
    before `b`, and threads/`accept` are appended in walk order. -/
private def addThread (insts : Array Inst) (ctx : AssertKind → Bool)
    (pos : Nat) (fuel : Nat) (cl : Closure) (pc : Nat) (caps : Array (Option Nat)) : Closure :=
  match fuel with
  | 0 => cl
  | fuel + 1 =>
    if pc < cl.visited.size && cl.visited[pc]! then cl
    else
      let cl := { cl with visited := cl.visited.setIfInBounds pc true }
      match insts[pc]? with
      | none => cl
      | some (.jmp n) => addThread insts ctx pos fuel cl n caps
      | some (.save slot n) =>
          let caps := caps.setIfInBounds slot (some pos)
          addThread insts ctx pos fuel cl n caps
      | some (.split a b) =>
          let cl := addThread insts ctx pos fuel cl a caps
          addThread insts ctx pos fuel cl b caps
      | some (.assert kind n) =>
          if ctx kind then addThread insts ctx pos fuel cl n caps else cl
      | some .accept =>
          -- First accept in the closure wins (highest priority); it CUTS every
          -- lower-priority thread reached after it (they no longer get parked below).
          match cl.matched with
          | some _ => cl
          | none => { cl with matched := some caps }
      | some (.char _ _ _) | some (.any _) =>
          -- A char/any thread reached AFTER an accept in this closure is lower priority
          -- than the match → cut. Higher-priority char threads (parked before the accept)
          -- survive and may override at a later position.
          match cl.matched with
          | some _ => cl
          | none => { cl with ready := cl.ready.push { pc := pc, caps := caps } }

/-- Build the ε-closure of a list of seed threads at the cursor, in priority order. Seeds
    after the first that yields a match are cut (lower priority than the match). -/
private def closeThreads (insts : Array Inst) (ctx : AssertKind → Bool) (pos : Nat)
    (seeds : Array Thread) : Closure :=
  let empty : Closure := { ready := #[], matched := none, visited := Array.replicate insts.size false }
  seeds.foldl (fun cl t =>
    match cl.matched with
    | some _ => cl
    | none => addThread insts ctx pos insts.size cl t.pc t.caps) empty

/-- One VM step: from the closure's ready threads, consume `c` (advancing each char/any
    thread that matches), producing the seed threads for the next position. Priority order
    preserved (first ready thread first). -/
private def stepThreads (insts : Array Inst) (c : Char) (ready : Array Thread) : Array Thread :=
  ready.foldl (fun acc t =>
    match insts[t.pc]? with
    | some (Inst.char ranges negated next) =>
        if classMatches ranges negated c then acc.push { t with pc := next } else acc
    | some (Inst.any next) =>
        if c != '\n' then acc.push { t with pc := next } else acc
    | _ => acc) #[]

/-- The Pike-VM main loop. Structural recursion on the input `List Char` (decreasing) → the
    outer loop is TOTAL; the inner ε-closure is total by `addThread`'s argument.

    `best` holds the captures of the current winning thread. A match found at a LATER
    position OVERRIDES the earlier one: the surviving thread that reached it was — by the
    priority-preserving closure + cut — higher priority than any thread that accepted before.
    Leftmost-start is guaranteed by the unanchored prefix `.*?` being LAZY (it prefers the
    earliest start). The loop ends when input is exhausted or no threads remain. -/
private def loop (insts : Array Inst) (pos : Nat) (prev : Option Char)
    (seeds : Array Thread) (best : Option (Array (Option Nat))) :
    List Char → Option (Array (Option Nat))
  | [] =>
      let ctx := fun k => assertHolds k (pos == 0) true prev none
      let cl := closeThreads insts ctx pos seeds
      match cl.matched with | some m => some m | none => best
  | c :: rest =>
      let ctx := fun k => assertHolds k (pos == 0) false prev (some c)
      let cl := closeThreads insts ctx pos seeds
      let best := match cl.matched with | some m => some m | none => best
      let next := stepThreads insts c cl.ready
      loop insts (pos + 1) (some c) next best rest

end Vm

/-- Run the compiled program against `input`, returning the capture array of the leftmost
    highest-priority match (slots 0/1 = whole-match span), or `none` on no match. TOTAL.
    Anchoring: callers wanting an unanchored search compile a leading `.*?` (see
    `matchRegex`); `run` itself anchors at the program's `start`. -/
def NFA.run (nfa : NFA) (input : List Char) : Option (Array (Option Nat)) :=
  let initCaps := Array.replicate nfa.slots none
  Vm.loop nfa.insts 0 none #[{ pc := nfa.start, caps := initCaps }] none input

/-- The implicit prefix for an unanchored search: a LAZY star over a class matching EVERY
    char — `cls [] true` (negated empty = always in). NOT `.any`, because RE2's `.` excludes
    `\n`; the unanchored "skip to a start position" must cross newlines (cue's `=~`/`Match`
    matches `"two"` against `"one\ntwo"`). Lazy so it prefers the earliest start (leftmost). -/
private def unanchoredPrefix : Regex := .star false (.cls [] true)

/-- Unanchored boolean match — RE2 `Match` / CUE `=~` semantics: true iff `pattern` matches
    ANYWHERE in `s`. Achieved by prepending the lazy `unanchoredPrefix` (an any-char-incl-`\n`
    star) so the engine scans every start position in one linear pass. An invalid or deferred
    pattern is NOT a match (the dispatch sites surface the parse error separately; the boolean
    here is conservative-false). -/
def matchRegex (pattern s : String) : Bool :=
  match parseRegex pattern with
  | .error _ => false
  | .ok re =>
      let unanchored : Regex := .concat [unanchoredPrefix, re]
      (compile unanchored).run s.toList |>.isSome

/-- Parse outcome of a pattern, for dispatch sites that must distinguish an invalid pattern
    (a build error) from a non-match. `none` = parsed OK. -/
def regexParseError? (pattern : String) : Option RegexParseError :=
  match parseRegex pattern with | .error e => some e | .ok _ => none

/-! ## RX-1c — submatch / Find* / ReplaceAll over the Pike-VM capture array

    The Pike-VM already fills a capture array (`NFA.run`). RX-1c exposes it as the
    CUE/Go `regexp` package's string-returning forms. Everything here is a pure
    `String → … → Option …` over rune (`List Char`) offsets — the VM iterates `Char`
    (runes), matching cue's `=~` rune semantics, so spans are rune-indexed and extracted
    with `List.extract`/`String.ofList`. All functions are TOTAL (the search loop is
    structural on a `fuel` bounded by the input length, and a zero-width match advances one
    rune so it cannot stall). -/

/-- A capture array: slot 2i/2i+1 are the half-open rune-offset start/end of group i
    (group 0 = whole match), `none` for a non-participating group. -/
abbrev Captures := Array (Option Nat)

/-- Extract the rune span `[lo, hi)` of `chars` as a `String`. -/
private def spanString (chars : List Char) (lo hi : Nat) : String :=
  String.ofList ((chars.drop lo).take (hi - lo))

/-- Shift every capturing-group index in `re` up by one. Used to reserve group 1 for an
    explicit whole-match wrapper in the unanchored search (the program's slots 0/1 are pinned
    to offset 0 by the lazy `.*?` prefix, so they cannot report the true match START — the
    wrapper group does). Structural recursion on the finite AST → total. -/
private def bumpGroups : Regex → Regex
  | .group (some i) body => .group (some (i + 1)) (bumpGroups body)
  | .group none body => .group none (bumpGroups body)
  | .concat parts => .concat (parts.attach.map (fun ⟨p, _⟩ => bumpGroups p))
  | .alt branches => .alt (branches.attach.map (fun ⟨b, _⟩ => bumpGroups b))
  | .star g body => .star g (bumpGroups body)
  | .plus g body => .plus g (bumpGroups body)
  | .opt g body => .opt g (bumpGroups body)
  | .«repeat» g lo hi body => .«repeat» g lo hi (bumpGroups body)
  | atom => atom

/-- Find the leftmost match of `re` (the ALREADY-parsed AST) in `chars` at-or-after rune
    offset `from`, returning a capture array where slot 2i/2i+1 is group i's ABSOLUTE
    half-open rune span (group 0 = whole match). Implemented by wrapping a group-bumped `re`
    in an explicit whole-match group behind the unanchored lazy `.*?` prefix, then re-basing
    the wrapper-group slots by `from`. The wrapper (group 1) reports the TRUE match start —
    the program's own slot 0/1 are pinned to 0 by the lazy prefix. `none` if no match. -/
private def findFrom (re : Regex) (chars : List Char) (from_ : Nat) : Option Captures :=
  let unanchored : Regex := .concat [unanchoredPrefix, .group (some 1) (bumpGroups re)]
  match (compile unanchored).run (chars.drop from_) with
  | none => none
  | some caps =>
      -- Drop the program's whole-match slots 0/1 (prefix-pinned); the wrapper group's slots
      -- 2/3 become the true whole match, and each real group i+1 maps back to group i.
      some ((caps.extract 2 caps.size).map (·.map (· + from_)))

/-- The whole-match span `[start, end)` of a capture array (slots 0/1), if present. -/
private def matchSpan (caps : Captures) : Option (Nat × Nat) :=
  match caps[0]?.join, caps[1]?.join with
  | some s, some e => some (s, e)
  | _, _ => none

/-- Iterate all NON-overlapping leftmost matches of `re` in `chars`, left to right. A
    zero-width match advances the scan one rune (Go semantics — otherwise it stalls). `fuel`
    bounds the loop (one match consumes ≥1 rune of progress, so `chars.length + 1` is exact
    and never spuriously hit). Returns the matches in order. -/
private def allMatches (re : Regex) (chars : List Char) : List Captures :=
  let rec go (fuel pos : Nat) (acc : List Captures) : List Captures :=
    match fuel with
    | 0 => acc.reverse
    | fuel + 1 =>
        if pos > chars.length then acc.reverse
        else match findFrom re chars pos with
          | none => acc.reverse
          | some caps =>
              match matchSpan caps with
              | none => acc.reverse
              | some (_, e) =>
                  -- next scan starts after this match; a zero-width match (end == its own
                  -- start, i.e. end == pos) advances one rune to guarantee progress.
                  let next := if e ≤ pos then pos + 1 else e
                  go fuel next (caps :: acc)
  go (chars.length + 2) 0 []

/-- `regexp.FindSubmatch`-style: the leftmost match's group strings (group 0 = whole match,
    then group 1, 2, …). A non-participating group becomes the empty string (Go returns nil;
    cue's only consumer is the array shape — empty string matches cue's element). `none` on
    no match (cue raises `no match`, so the dispatch site bottoms). -/
def findSubmatch (pattern s : String) : Option (List String) :=
  match parseRegex pattern with
  | .error _ => none
  | .ok re =>
      let chars := s.toList
      match findFrom re chars 0 with
      | none => none
      | some caps =>
          let groups := caps.size / 2
          some <| (List.range groups).map fun i =>
            match caps[2 * i]?.join, caps[2 * i + 1]?.join with
            | some lo, some hi => spanString chars lo hi
            | _, _ => ""

/-- `regexp.Find`-style: the leftmost whole-match substring, or `none` on no match. -/
def find (pattern s : String) : Option String :=
  match parseRegex pattern with
  | .error _ => none
  | .ok re =>
      let chars := s.toList
      (findFrom re chars 0).bind matchSpan |>.map fun (lo, hi) => spanString chars lo hi

/-- `regexp.FindAll`-style: every non-overlapping whole-match substring (left to right).
    `none` (→ no-match bottom at the dispatch site) when there are zero matches. -/
def findAll (pattern s : String) : Option (List String) :=
  match parseRegex pattern with
  | .error _ => none
  | .ok re =>
      let chars := s.toList
      match allMatches re chars with
      | [] => none
      | ms => some <| ms.filterMap fun caps =>
          (matchSpan caps).map fun (lo, hi) => spanString chars lo hi

/-- `regexp.FindAllSubmatch`-style: for every non-overlapping match, its group strings (the
    `findSubmatch` shape per match). `none` when there are zero matches. -/
def findAllSubmatch (pattern s : String) : Option (List (List String)) :=
  match parseRegex pattern with
  | .error _ => none
  | .ok re =>
      let chars := s.toList
      match allMatches re chars with
      | [] => none
      | ms => some <| ms.map fun caps =>
          let groups := caps.size / 2
          (List.range groups).map fun i =>
            match caps[2 * i]?.join, caps[2 * i + 1]?.join with
            | some lo, some hi => spanString chars lo hi
            | _, _ => ""

/-! ### Go `Expand` replacement-template grammar (NOT regex backreferences)

    In `regexp.ReplaceAll(pattern, src, repl)`, `repl` is a Go `Expand` template:
    `$name`/`${name}` interpolate a capture group, `$$` is a literal `$`. A bare `$name`
    consumes the LONGEST run of `[0-9A-Za-z_]` as the name (so `$1suffix` names group
    `1suffix`, which does not exist → empty; `${1}suffix` names group `1` then literal
    `suffix`). A purely-numeric name selects the group by index; an unknown group → empty.
    Named groups (`$g`) require `(?P<name>…)` which Kue's parser defers, so only numeric
    references resolve here. -/

private def isExpandNameChar (c : Char) : Bool :=
  ('0' ≤ c && c ≤ '9') || ('A' ≤ c && c ≤ 'Z') || ('a' ≤ c && c ≤ 'z') || c == '_'

/-- Parse an all-digits name to a group index. -/
private def nameToIndex? (name : List Char) : Option Nat :=
  if name.isEmpty || !name.all (fun c => '0' ≤ c && c ≤ '9') then none
  else some (name.foldl (fun acc c => acc * 10 + (c.toNat - '0'.toNat)) 0)

/-- The captured string for group `i` of `caps` in `chars`, or `none` if the group is out of
    range or non-participating (Go interpolates empty for both). -/
private def groupText? (chars : List Char) (caps : Captures) (i : Nat) : Option String :=
  match caps[2 * i]?.join, caps[2 * i + 1]?.join with
  | some lo, some hi => some (spanString chars lo hi)
  | _, _ => none

/-- Expand a Go `Expand` template against one match's captures, appending to `out` (reversed,
    char list). `fuel` is the template length (structural bound; each branch consumes ≥1
    char). -/
private def expandTemplate (chars : List Char) (caps : Captures) :
    Nat → List Char → List Char → List Char
  | 0, _, out => out
  | _ + 1, [], out => out
  | fuel + 1, '$' :: '$' :: rest, out => expandTemplate chars caps fuel rest ('$' :: out)
  | fuel + 1, '$' :: '{' :: rest, out =>
      -- `${name}` — name is everything up to the closing `}`.
      let name := rest.takeWhile (· != '}')
      let after := (rest.dropWhile (· != '}')).drop 1  -- drop the `}`
      let text := (nameToIndex? name).bind (groupText? chars caps) |>.getD ""
      expandTemplate chars caps fuel after (text.toList.reverse ++ out)
  | fuel + 1, '$' :: rest, out =>
      -- `$name` — name is the LONGEST run of word chars; if empty, `$` is literal.
      let name := rest.takeWhile isExpandNameChar
      match name with
      | [] => expandTemplate chars caps fuel rest ('$' :: out)
      | _ =>
          let after := rest.dropWhile isExpandNameChar
          let text := (nameToIndex? name).bind (groupText? chars caps) |>.getD ""
          expandTemplate chars caps fuel after (text.toList.reverse ++ out)
  | fuel + 1, c :: rest, out => expandTemplate chars caps fuel rest (c :: out)

/-- Build the replacement for one match: expand the `Expand` template (`repl`) when
    `literal = false`, or use `repl` verbatim (`ReplaceAllLiteral`) when `true`. -/
private def replacementFor (chars : List Char) (repl : List Char) (literal : Bool)
    (caps : Captures) : List Char :=
  if literal then repl
  else (expandTemplate chars caps repl.length repl []).reverse

/-- Replace all non-overlapping leftmost matches of `re` in `chars`, splicing each match's
    expanded/literal replacement. Walks `chars` once over the (ordered) match list, copying
    the gaps between matches. TOTAL (structural on the match list; spans are non-overlapping
    and ordered). -/
private def replaceAllChars (re : Regex) (chars repl : List Char) (literal : Bool) : List Char :=
  let found := allMatches re chars
  -- fold over matches, tracking the cursor; copy [cursor, matchStart), then the replacement,
  -- then advance cursor to matchEnd. Finally copy the tail [cursor, end).
  let (cursor, acc) := found.foldl (fun (st : Nat × List Char) caps =>
    let (cursor, acc) := st
    match matchSpan caps with
    | none => st
    | some (lo, hi) =>
        let gap := (chars.drop cursor).take (lo - cursor)
        let rep := replacementFor chars repl literal caps
        (hi, acc ++ gap ++ rep)) (0, [])
  acc ++ chars.drop cursor

/-- `regexp.ReplaceAll(pattern, src, repl)` — replace every non-overlapping match in `src`,
    expanding `repl` as a Go `Expand` template. `none` only on an invalid/deferred pattern
    (the dispatch site bottoms); a valid pattern with no match returns `src` unchanged. -/
def replaceAll (pattern src repl : String) : Option String :=
  match parseRegex pattern with
  | .error _ => none
  | .ok re => some (String.ofList (replaceAllChars re src.toList repl.toList false))

/-- `regexp.ReplaceAllLiteral(pattern, src, repl)` — like `replaceAll` but `repl` is spliced
    VERBATIM (no `$` expansion). -/
def replaceAllLiteral (pattern src repl : String) : Option String :=
  match parseRegex pattern with
  | .error _ => none
  | .ok re => some (String.ofList (replaceAllChars re src.toList repl.toList true))

end Kue
