import Kue.Regex

/-!
RX-1a parser pins. AST-shape assertions only — no matching yet (matching is RX-1b). Each
theorem pins `parseRegex` to the EXACT AST so the structure is the contract RX-1b/c compile
against. Patterns 1-7 are the audit's RX-1 repros that the old `Value.lean` engine
mis-parsed (group-with-quantifier vs first-group-expansion, `\b` as anchor not literal `b`,
`a+?` as lazy-plus not opt-of-`a`).

`Regex` derives only `BEq` (Lean cannot auto-derive `DecidableEq` through the nested
`List Regex` recursion), so the pins compare with `==` against `Bool` — the same `…= true`
shape the rest of the suite uses, fully reducible by `native_decide`.
-/

namespace Kue

open Regex

/-- Pin: `parseRegex p` produces exactly AST `r` (`Except` has no `BEq`, so match + the
    derived `Regex` `==`). -/
private def parsesTo (p : String) (r : Regex) : Bool :=
  match parseRegex p with | .ok r' => r' == r | .error _ => false

/-- A char class for `[a-z0-9]`, reused by repro 3. -/
private def az09 : Regex := .cls [('a', 'z'), ('0', '9')] false
private def d09 : Regex := .cls [('0', '9')] false

/-! ## The 7 repro patterns parse into the correct structure -/

-- 1. grouped `+` binds the GROUP, not the trailing `b`.
theorem rx_repro_group_plus :
    parsesTo "^(ab)+$"
      (.concat
        [.anchorStart, .plus true (.group (some 1) (.concat [.lit 'a', .lit 'b'])),
         .anchorEnd]) = true := by native_decide

-- 2. grouped `*` binds the GROUP.
theorem rx_repro_group_star :
    parsesTo "^(ab)*$"
      (.concat
        [.anchorStart, .star true (.group (some 1) (.concat [.lit 'a', .lit 'b'])),
         .anchorEnd]) = true := by native_decide

-- 3. nested groups: outer (1) captures, inner (2) captures, group-`*` over a `-`-led group.
theorem rx_repro_nested_groups :
    parsesTo "^([a-z0-9]+(-[a-z0-9]+)*)$"
      (.concat
        [.anchorStart,
         .group (some 1) (.concat
           [.plus true az09,
            .star true (.group (some 2) (.concat [.lit '-', .plus true az09]))]),
         .anchorEnd]) = true := by native_decide

-- 4. multi-group semver-ish: two capturing groups, second under a `*`; `\.` is a literal dot.
theorem rx_repro_multi_group :
    parsesTo "^(v[0-9]+)(\\.[0-9]+)*$"
      (.concat
        [.anchorStart,
         .group (some 1) (.concat [.lit 'v', .plus true d09]),
         .star true (.group (some 2) (.concat [.lit '.', .plus true d09])),
         .anchorEnd]) = true := by native_decide

-- 5. two adjacent alternation groups, numbered left-to-right.
theorem rx_repro_two_alt_groups :
    parsesTo "a(b|x)(c|y)d"
      (.concat
        [.lit 'a',
         .group (some 1) (.alt [.lit 'b', .lit 'x']),
         .group (some 2) (.alt [.lit 'c', .lit 'y']),
         .lit 'd']) = true := by native_decide

-- 6. `\b` is a word-boundary anchor on BOTH ends, not a literal `b`.
theorem rx_repro_word_boundary :
    parsesTo "\\bdog\\b"
      (.concat
        [.wordBoundary false, .lit 'd', .lit 'o', .lit 'g', .wordBoundary false]) = true := by
  native_decide

-- 7. `a+?` is a LAZY plus, not opt-of-`a`.
theorem rx_repro_lazy_plus :
    parsesTo "a+?" (.plus false (.lit 'a')) = true := by native_decide

/-! ## Greediness as a Bool field — greedy vs lazy across all quantifiers -/

theorem rx_greedy_star : parsesTo "a*" (.star true (.lit 'a')) = true := by native_decide
theorem rx_lazy_star : parsesTo "a*?" (.star false (.lit 'a')) = true := by native_decide
theorem rx_greedy_opt : parsesTo "a?" (.opt true (.lit 'a')) = true := by native_decide
theorem rx_lazy_opt : parsesTo "a??" (.opt false (.lit 'a')) = true := by native_decide

/-! ## Repeat `{m,n}` shapes — `max : Option Nat` (no sentinel) -/

theorem rx_repeat_exact :
    parsesTo "a{3}" (.«repeat» true 3 (some 3) (.lit 'a')) = true := by native_decide
theorem rx_repeat_open :
    parsesTo "a{2,}" (.«repeat» true 2 none (.lit 'a')) = true := by native_decide
theorem rx_repeat_range :
    parsesTo "a{2,5}" (.«repeat» true 2 (some 5) (.lit 'a')) = true := by native_decide
theorem rx_repeat_lazy :
    parsesTo "a{2,5}?" (.«repeat» false 2 (some 5) (.lit 'a')) = true := by native_decide

/-! ## Non-capturing group does NOT consume a capture index -/

theorem rx_noncapturing_group :
    parsesTo "(?:ab)(c)"
      (.concat
        [.group none (.concat [.lit 'a', .lit 'b']), .group (some 1) (.lit 'c')]) = true := by
  native_decide

/-! ## Char classes — negation, perl-class fold, dot -/

theorem rx_negated_class :
    parsesTo "[^abc]" (.cls [('a', 'a'), ('b', 'b'), ('c', 'c')] true) = true := by
  native_decide
theorem rx_perl_digit_atom : parsesTo "\\d" (.cls [('0', '9')] false) = true := by native_decide
theorem rx_perl_digit_negated_atom :
    parsesTo "\\D" (.cls [('0', '9')] true) = true := by native_decide
theorem rx_dot : parsesTo "." .any = true := by native_decide

/-! ## Invalid patterns → error (NOT silent literal-fallback) -/

private def parseErrors (p : String) : Bool :=
  match parseRegex p with | .error _ => true | .ok _ => false

theorem rx_unbalanced_open : parseErrors "a(b" = true := by native_decide
theorem rx_unbalanced_close : parseErrors "ab)" = true := by native_decide
theorem rx_dangling_backslash : parseErrors "ab\\" = true := by native_decide
theorem rx_bad_repeat_order : parseErrors "a{5,2}" = true := by native_decide
theorem rx_nothing_to_repeat : parseErrors "*abc" = true := by native_decide

/-- `\1` backreference is rejected (RE2 has none) — with the SPECIFIC reason, distinct from
    a generic malformed error. -/
private def isBackref (p : String) (d : Char) : Bool :=
  match parseRegex p with | .error (.backreference d') => d == d' | _ => false

theorem rx_backreference_rejected : isBackref "(a)\\1" '1' = true := by native_decide

/-! ## Deferred RE2 constructs → explicit `.unsupportedRegex`, never silent-wrong -/

private def isUnsupported (p : String) : Bool :=
  match parseRegex p with | .error (.unsupportedRegex _) => true | _ => false

theorem rx_flags_unsupported : isUnsupported "(?i)abc" = true := by native_decide
theorem rx_unicode_prop_unsupported : isUnsupported "\\p{L}" = true := by native_decide
theorem rx_named_capture_unsupported : isUnsupported "(?P<n>a)" = true := by native_decide
theorem rx_posix_class_unsupported : isUnsupported "[[:alpha:]]" = true := by native_decide

end Kue
