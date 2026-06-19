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

/-- A `\`-escape used INSIDE a `[…]` class: yields either a set of ranges to fold in (perl
    class or a single literal char as a degenerate range) or an error. Negated perl classes
    (`\D \W \S`) are illegal inside our class representation (would need set complement) —
    deferred rather than silently mis-folded. -/
private def parseClassEscape : List Char → Except RegexParseError (List (Char × Char) × List Char)
  | 'd' :: rest => .ok (digitRanges, rest)
  | 'w' :: rest => .ok (wordRanges, rest)
  | 's' :: rest => .ok (spaceRanges, rest)
  | 'D' :: _ => .error (.unsupportedRegex "\\D inside character class")
  | 'W' :: _ => .error (.unsupportedRegex "\\W inside character class")
  | 'S' :: _ => .error (.unsupportedRegex "\\S inside character class")
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

private def parseRepeatSuffix : List Char → RepeatParse
  | input =>
      match takeNat input 0 false with
      | (m, true, '}' :: rest) => .quant m (some m) rest
      | (m, true, ',' :: rest) =>
          match takeNat rest 0 false with
          | (n, true, '}' :: rest') => if m ≤ n then .quant m (some n) rest' else .invalid
          | (_, false, '}' :: rest') => .quant m none rest'  -- {m,}
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

end Kue
