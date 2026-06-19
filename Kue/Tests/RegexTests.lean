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

/-! ## RX-1b — Pike-VM match pins (the behavior change)

    `matchRegex` is the unanchored RE2 `Match`/CUE `=~` boolean. Each repro below was
    cross-checked against `cue` v0.16.1 (the spec authority is RE2; cue delegates to Go's
    RE2 and agrees on every one). The 7 audit repros now MATCH correctly — the whole point
    of RX-1: the old `Value.lean` engine mis-validated all of them. -/

/-- True iff the unanchored engine matches. -/
private def m (p s : String) : Bool := matchRegex p s

-- 1. Grouped `+` binds the GROUP: `^(ab)+$` matches `abab`, rejects `aba`.
theorem rx_match_group_plus_yes : m "^(ab)+$" "abab" = true := by native_decide
theorem rx_match_group_plus_no : m "^(ab)+$" "aba" = false := by native_decide

-- 2. Nested + multi group DNS-label form matches `foo-bar-baz`, rejects a trailing dash.
theorem rx_match_nested_group_yes :
    m "^([a-z0-9]+(-[a-z0-9]+)*)$" "foo-bar-baz" = true := by native_decide
theorem rx_match_nested_group_no :
    m "^([a-z0-9]+(-[a-z0-9]+)*)$" "foo-" = false := by native_decide

-- 3. Multi-group semver with `\.` literal and group-`*`.
theorem rx_match_semver_yes : m "^(v[0-9]+)(\\.[0-9]+)*$" "v1.2.3" = true := by native_decide
theorem rx_match_semver_no : m "^(v[0-9]+)(\\.[0-9]+)*$" "v1.2." = false := by native_decide

-- 4. Two alternation groups: `a(b|x)(c|y)d` matches `axyd` (cross of the second arms).
theorem rx_match_alt_groups_yes : m "a(b|x)(c|y)d" "axyd" = true := by native_decide
theorem rx_match_alt_groups_no : m "a(b|x)(c|y)d" "axzd" = false := by native_decide

-- 5. Word boundary `\b` is an anchor, not a literal `b`.
theorem rx_match_wordbound_yes : m "\\bdog\\b" "cat dog" = true := by native_decide
theorem rx_match_wordbound_no : m "\\bdog\\b" "dogcat" = false := by native_decide

-- 6. Lazy plus `a+?` still MATCHES (laziness is priority, not "match less or fail").
theorem rx_match_lazy_plus : m "a+?" "aaa" = true := by native_decide

-- 7. The unsound-fallback case: unanchored `(foo|bar)+` is now a consistent anywhere-search.
theorem rx_match_alt_plus_substr : m "(foo|bar)+" "xfoobarx" = true := by native_decide
theorem rx_match_alt_plus_none : m "(foo|bar)+" "xbazx" = false := by native_decide

/-! ## Existing simple-pattern behavior stays correct (the old engine got these right) -/

theorem rx_match_anchor_start : m "^a" "abc" = true := by native_decide
theorem rx_match_miss : m "z" "abc" = false := by native_decide
theorem rx_match_full_anchor : m "^abc$" "abc" = true := by native_decide
theorem rx_match_cat_dog_yes : m "^(cat|dog)$" "dog" = true := by native_decide
theorem rx_match_cat_dog_no : m "^(cat|dog)$" "cow" = false := by native_decide
theorem rx_match_toplevel_alt_yes : m "^cat$|^dog$" "dog" = true := by native_decide
theorem rx_match_toplevel_alt_no : m "^cat$|^dog$" "cow" = false := by native_decide
theorem rx_match_bounded_lo : m "^a\\d{2,3}z$" "a12z" = true := by native_decide
theorem rx_match_bounded_hi : m "^a\\d{2,3}z$" "a123z" = true := by native_decide
theorem rx_match_bounded_under : m "^a\\d{2,3}z$" "a1z" = false := by native_decide
theorem rx_match_exact_rep_yes : m "^a\\d{2}z$" "a12z" = true := by native_decide
theorem rx_match_exact_rep_no : m "^a\\d{2}z$" "a1z" = false := by native_decide
theorem rx_match_star_wild : m "^a.*z$" "abcz" = true := by native_decide
theorem rx_match_plus_wild_empty : m "^a.+z$" "az" = false := by native_decide
theorem rx_match_plus_wild_one : m "^a.+z$" "abz" = true := by native_decide
theorem rx_match_opt_no : m "^colou?r$" "color" = true := by native_decide
theorem rx_match_opt_yes : m "^colou?r$" "colour" = true := by native_decide
theorem rx_match_opt_two : m "^colou?r$" "colouur" = false := by native_decide
theorem rx_match_class_yes : m "^[ab]cz$" "acz" = true := by native_decide
theorem rx_match_class_no : m "^[ab]cz$" "ccz" = false := by native_decide
theorem rx_match_class_digit : m "^a[0-9]z$" "a5z" = true := by native_decide
theorem rx_match_escaped_dot_yes : m "^a\\.z$" "a.z" = true := by native_decide
theorem rx_match_escaped_dot_no : m "^a\\.z$" "abz" = false := by native_decide
theorem rx_match_perl_digit : m "^a\\dz$" "a5z" = true := by native_decide
theorem rx_match_perl_digit_neg : m "^a\\Dz$" "adz" = true := by native_decide
theorem rx_match_perl_space : m "^a\\sz$" "a z" = true := by native_decide
theorem rx_match_perl_space_neg : m "^a\\Sz$" "a_z" = true := by native_decide
theorem rx_match_perl_word : m "^a\\wz$" "a_z" = true := by native_decide
theorem rx_match_perl_word_neg : m "^a\\Wz$" "a-z" = true := by native_decide

/-! ## Capture slots are computed (groundwork for RX-1c submatch / `ReplaceAll`)

    `matchRegex` returns only the bool, but the Pike-VM fills a capture array. We pin the
    whole-match span (slots 0/1) and group spans directly off `run` to prove the slots are
    live and correct, so RX-1c can expose them without re-deriving. The unanchored prefix
    (`.*?`) means slot 0 is the match START offset, slot 1 the END (half-open). -/

/-- Run the unanchored program and read slot `i` of the first match. -/
private def slot (p s : String) (i : Nat) : Option Nat :=
  match parseRegex p with
  | .error _ => none
  | .ok re => ((compile (.concat [.star false .any, re])).run s.toList).bind (·[i]?) |>.join

-- `(a+)(b+)` over "aabbb": whole match [0,5), group 1 = [0,2), group 2 = [2,5).
theorem rx_cap_whole_start : slot "(a+)(b+)" "aabbb" 0 = some 0 := by native_decide
theorem rx_cap_whole_end : slot "(a+)(b+)" "aabbb" 1 = some 5 := by native_decide
theorem rx_cap_g1_start : slot "(a+)(b+)" "aabbb" 2 = some 0 := by native_decide
theorem rx_cap_g1_end : slot "(a+)(b+)" "aabbb" 3 = some 2 := by native_decide
theorem rx_cap_g2_start : slot "(a+)(b+)" "aabbb" 4 = some 2 := by native_decide
theorem rx_cap_g2_end : slot "(a+)(b+)" "aabbb" 5 = some 5 := by native_decide

-- Greedy vs lazy priority shows up in the whole-match span. Unanchored `a.*c` over
-- "abcabc": greedy `.*` extends to the LAST c → match [0,6); lazy `a.*?c` stops at the
-- FIRST c → match [0,3).
theorem rx_greedy_extends : slot "a.*c" "abcabc" 1 = some 6 := by native_decide
theorem rx_lazy_stops : slot "a.*?c" "abcabc" 1 = some 3 := by native_decide

end Kue
