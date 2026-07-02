import Kue.Regex

--
-- RX-1a parser pins. AST-shape assertions only — no matching yet (matching is RX-1b). Each
-- theorem pins `parseRegex` to the EXACT AST so the structure is the contract RX-1b/c compile
-- against. Patterns 1-7 are the audit's RX-1 repros that the old `Value.lean` engine
-- mis-parsed (group-with-quantifier vs first-group-expansion, `\b` as anchor not literal `b`,
-- `a+?` as lazy-plus not opt-of-`a`).
--
-- `Regex` derives only `BEq` (Lean cannot auto-derive `DecidableEq` through the nested
-- `List Regex` recursion), so the pins compare with `==` against `Bool` — the same `…= true`
-- shape the rest of the suite uses, fully reducible by `native_decide`.
--

namespace Kue

open Regex

-- Pin: `parseRegex p` produces exactly AST `r` (`Except` has no `BEq`, so match + the
-- derived `Regex` `==`).
private def parsesTo (p : String) (r : Regex) : Bool :=
  match parseRegex p with | .ok r' => r' == r | .error _ => false

-- A char class for `[a-z0-9]`, reused by repro 3.
private def az09 : Regex := .cls [('a', 'z'), ('0', '9')] false
private def d09 : Regex := .cls [('0', '9')] false

-- ## The 7 repro patterns parse into the correct structure

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

-- ## Greediness as a Bool field — greedy vs lazy across all quantifiers

theorem rx_greedy_star : parsesTo "a*" (.star true (.lit 'a')) = true := by native_decide
theorem rx_lazy_star : parsesTo "a*?" (.star false (.lit 'a')) = true := by native_decide
theorem rx_greedy_opt : parsesTo "a?" (.opt true (.lit 'a')) = true := by native_decide
theorem rx_lazy_opt : parsesTo "a??" (.opt false (.lit 'a')) = true := by native_decide

-- ## Repeat `{m,n}` shapes — `max : Option Nat` (no sentinel)

theorem rx_repeat_exact :
    parsesTo "a{3}" (.«repeat» true 3 (some 3) (.lit 'a')) = true := by native_decide
theorem rx_repeat_open :
    parsesTo "a{2,}" (.«repeat» true 2 none (.lit 'a')) = true := by native_decide
theorem rx_repeat_range :
    parsesTo "a{2,5}" (.«repeat» true 2 (some 5) (.lit 'a')) = true := by native_decide
theorem rx_repeat_lazy :
    parsesTo "a{2,5}?" (.«repeat» false 2 (some 5) (.lit 'a')) = true := by native_decide

-- ## Non-capturing group does NOT consume a capture index

theorem rx_noncapturing_group :
    parsesTo "(?:ab)(c)"
      (.concat
        [.group none (.concat [.lit 'a', .lit 'b']), .group (some 1) (.lit 'c')]) = true := by
  native_decide

-- ## Char classes — negation, perl-class fold, dot

theorem rx_negated_class :
    parsesTo "[^abc]" (.cls [('a', 'a'), ('b', 'b'), ('c', 'c')] true) = true := by
  native_decide
theorem rx_perl_digit_atom : parsesTo "\\d" (.cls [('0', '9')] false) = true := by native_decide
theorem rx_perl_digit_negated_atom :
    parsesTo "\\D" (.cls [('0', '9')] true) = true := by native_decide
theorem rx_dot : parsesTo "." .any = true := by native_decide

-- RX-2a: in-class `\D` folds to the COMPLEMENT ranges of the digits over the `Char` domain
-- (the two gaps `[\x00,'/']` and `[':',U+10FFFF]`), with whole-class `negated = false` — the
-- representation choice that lets it union with other members. (Contrast the ATOM form above,
-- which keeps a single positive range + the whole-atom `negated` flag.)
theorem rx_class_negshort_folds_to_complement :
    parsesTo "[\\D]"
      (.cls [(Char.ofNat 0, Char.ofNat 0x2F), (Char.ofNat 0x3A, Char.ofNat 0x10FFFF)] false)
      = true := by native_decide

-- ## Invalid patterns → error (NOT silent literal-fallback)

private def parseErrors (p : String) : Bool :=
  match parseRegex p with | .error _ => true | .ok _ => false

theorem rx_unbalanced_open : parseErrors "a(b" = true := by native_decide
theorem rx_unbalanced_close : parseErrors "ab)" = true := by native_decide
theorem rx_dangling_backslash : parseErrors "ab\\" = true := by native_decide
theorem rx_bad_repeat_order : parseErrors "a{5,2}" = true := by native_decide
theorem rx_nothing_to_repeat : parseErrors "*abc" = true := by native_decide

-- RE2 caps repeat counts at 1000: `{0,1000}` parses, `{0,1001}` and `{1001}` / `{1001,}`
-- error (matching cue's `invalid repeat count`); also bounds `desugar`'s expansion.
theorem rx_repeat_at_cap : parseErrors "a{0,1000}" = false := by native_decide
theorem rx_repeat_over_cap_range : parseErrors "a{0,1001}" = true := by native_decide
theorem rx_repeat_over_cap_exact : parseErrors "a{1001}" = true := by native_decide
theorem rx_repeat_over_cap_open : parseErrors "a{1001,}" = true := by native_decide

-- `\1` backreference is rejected (RE2 has none) — with the SPECIFIC reason, distinct from
-- a generic malformed error.
private def isBackref (p : String) (d : Char) : Bool :=
  match parseRegex p with | .error (.backreference d') => d == d' | _ => false

theorem rx_backreference_rejected : isBackref "(a)\\1" '1' = true := by native_decide

-- ## Deferred RE2 constructs → explicit `.unsupportedRegex`, never silent-wrong

private def isUnsupported (p : String) : Bool :=
  match parseRegex p with | .error (.unsupportedRegex _) => true | _ => false

theorem rx_flags_unsupported : isUnsupported "(?i)abc" = true := by native_decide
theorem rx_unicode_prop_unsupported : isUnsupported "\\p{L}" = true := by native_decide
theorem rx_named_capture_unsupported : isUnsupported "(?P<n>a)" = true := by native_decide
theorem rx_posix_class_unsupported : isUnsupported "[[:alpha:]]" = true := by native_decide

-- ## RX-2b — `regexParseError?` is the shared invalid-pattern decision
--
-- The 4 `matchRegex` dispatch sites (`=~`/`!~`, `Order.subsumesWithFuel`,
-- `Lattice.meetStringRegexPrim`, `regexp.Match`) guard on this one helper, so a concrete
-- invalid/deferred pattern bottoms uniformly instead of swallowing to a non-match. A VALID
-- pattern returns `none` (no behavior change for the matching corpus above).

theorem rx_parse_error_malformed : regexParseError? "a(" = some (.malformed "unbalanced ( — missing )") := by
  native_decide
theorem rx_parse_error_deferred : regexParseError? "(?i)a" = some (.unsupportedRegex "inline flags / group modifier (?…)") := by
  native_decide
theorem rx_parse_error_valid_is_none : regexParseError? "^a" = none := by native_decide
theorem rx_parse_error_valid_group_is_none : regexParseError? "^([a-z0-9]+(-[a-z0-9]+)*)$" = none := by
  native_decide

-- ## RX-1b — Pike-VM match pins (the behavior change)
--
-- `matchRegex` is the unanchored RE2 `Match`/CUE `=~` boolean. Each repro below was
-- cross-checked against `cue` v0.16.1 (the spec authority is RE2; cue delegates to Go's
-- RE2 and agrees on every one). The 7 audit repros now MATCH correctly — the whole point
-- of RX-1: the old `Value.lean` engine mis-validated all of them.

-- True iff the unanchored engine matches.
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

-- ## Existing simple-pattern behavior stays correct (the old engine got these right)

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

-- ## RX-2a — negated shorthand classes (`\D` `\W` `\S`) INSIDE a `[…]` char class
--
-- The lone remaining regex-corpus divergence: a negated shorthand inside a class folds its
-- full COMPLEMENT set into the class union (via `Regex.complementRanges` over the whole
-- `Char` domain), instead of erroring. Each pin below was cross-checked against `cue`
-- v0.16.1 (RE2 semantics; the spec authority). The interaction the prompt flags — member
-- `\D` complement vs whole-class `[^…]` negation — is pinned by `[^\D]` (the class negates
-- AFTER the member folds, recovering the digits) and `[\d\D]` (every char).

-- `[\D]`/`[\W]`/`[\S]` = the complement set, matching/rejecting a representative char each.
-- `\D` covers below '0' (space), above '9', and non-ASCII; `\S` excludes newline (whitespace).
theorem rx_class_negshort_D_yes : m "^[\\D]$" "a" = true := by native_decide
theorem rx_class_negshort_D_no : m "^[\\D]$" "5" = false := by native_decide
theorem rx_class_negshort_D_space : m "^[\\D]$" " " = true := by native_decide
theorem rx_class_negshort_D_newline : m "^[\\D]$" "\n" = true := by native_decide
theorem rx_class_negshort_W_yes : m "^[\\W]$" " " = true := by native_decide
theorem rx_class_negshort_W_no : m "^[\\W]$" "a" = false := by native_decide
theorem rx_class_negshort_S_yes : m "^[\\S]$" "a" = true := by native_decide
theorem rx_class_negshort_S_no : m "^[\\S]$" " " = false := by native_decide
theorem rx_class_negshort_S_newline : m "^[\\S]$" "\n" = false := by native_decide

-- `\D`/`\W`/`\S` are ASCII-only shorthands: a non-ASCII rune is `\W` (non-word), not `\w`.
theorem rx_class_negshort_W_nonascii : m "^[\\W]$" "é" = true := by native_decide

-- Union with another member: `[\D5]` = non-digits ∪ {5}; `[a\W]` = {a} ∪ non-word.
theorem rx_class_union_D5_five : m "^[\\D5]$" "5" = true := by native_decide
theorem rx_class_union_D5_letter : m "^[\\D5]$" "a" = true := by native_decide
theorem rx_class_union_D5_other_digit : m "^[\\D5]$" "7" = false := by native_decide
theorem rx_class_union_aW_a : m "^[a\\W]$" "a" = true := by native_decide
theorem rx_class_union_aW_space : m "^[a\\W]$" " " = true := by native_decide
theorem rx_class_union_aW_word : m "^[a\\W]$" "b" = false := by native_decide

-- `[\d\D]` is the everything-class (a set and its complement) — matches any char.
theorem rx_class_everything_digit : m "^[\\d\\D]$" "5" = true := by native_decide
theorem rx_class_everything_letter : m "^[\\d\\D]$" "a" = true := by native_decide
theorem rx_class_everything_space : m "^[\\d\\D]$" " " = true := by native_decide

-- Whole-class `[^…]` negation over a negated member: `[^\D]` folds `\D` to non-digits, then
-- the class negates → digits. The subtle member-vs-class negation interaction.
theorem rx_class_neg_over_negmember_digit : m "^[^\\D]$" "5" = true := by native_decide
theorem rx_class_neg_over_negmember_letter : m "^[^\\D]$" "a" = false := by native_decide

-- Regression guard: positive shorthands inside a class keep their existing behavior.
theorem rx_class_pos_d_yes : m "^[\\d]$" "5" = true := by native_decide
theorem rx_class_pos_d_no : m "^[\\d]$" "a" = false := by native_decide

-- `regexParseError?` no longer flags an in-class negated shorthand as deferred.
theorem rx_class_negshort_now_parses : regexParseError? "[\\D5]" = none := by native_decide

-- ## Capture slots are computed (groundwork for RX-1c submatch / `ReplaceAll`)
--
-- `matchRegex` returns only the bool, but the Pike-VM fills a capture array. We pin the
-- whole-match span (slots 0/1) and group spans directly off `run` to prove the slots are
-- live and correct, so RX-1c can expose them without re-deriving. The unanchored prefix
-- (`.*?`) means slot 0 is the match START offset, slot 1 the END (half-open).

-- Run the unanchored program and read slot `i` of the first match.
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

-- ## RX-1c — submatch / Find* / ReplaceAll engine layer (pure String entrypoints)
--
-- Pins on the Regex-leaf functions directly (the builtin dispatch is pinned in
-- BuiltinTests). Every `expected` oracle-checked vs cue v0.16.1.

-- `findSubmatch` returns group 0 (whole match) then each group's span, leftmost (RE2).
theorem rx_findsubmatch_spans : findSubmatch "a(x*)b" "-axxb-" = some ["axxb", "xx"] := by
  native_decide
-- No match → `none` (the dispatch site bottoms; cue raises `no match`).
theorem rx_findsubmatch_none : findSubmatch "zz" "ab" = none := by native_decide
-- A non-participating group becomes "" (cue's array-shape consumer matches empty).
theorem rx_findsubmatch_nonparticipating :
    findSubmatch "a(b)?c" "ac" = some ["ac", ""] := by native_decide

theorem rx_find_leftmost : find "a(x*)b" "-axxb-" = some "axxb" := by native_decide
theorem rx_find_none : find "zz" "ab" = none := by native_decide

theorem rx_findall_all : findAll "ab" "abab" = some ["ab", "ab"] := by native_decide
theorem rx_findall_none : findAll "zz" "abab" = none := by native_decide
theorem rx_findallsubmatch :
    findAllSubmatch "a(x*)b" "-axb-axxb-" = some [["axb", "x"], ["axxb", "xx"]] := by
  native_decide

-- ReplaceAll Expand template (oracle-checked).
theorem rx_replaceall_literal : replaceAll "a(x*)b" "-axxb-" "T" = some "-T-" := by native_decide
theorem rx_replaceall_group : replaceAll "a(x*)b" "-axxb-" "$1" = some "-xx-" := by native_decide
theorem rx_replaceall_brace :
    replaceAll "a(x*)b" "-axxb-" "${1}suffix" = some "-xxsuffix-" := by native_decide
theorem rx_replaceall_bare_name :
    replaceAll "a(x*)b" "-axxb-" "$1suffix" = some "--" := by native_decide
theorem rx_replaceall_dollar : replaceAll "a(x*)b" "-axxb-" "$$" = some "-$-" := by native_decide
theorem rx_replaceall_group0 :
    replaceAll "a(x*)b" "-axxb-" "${0}!" = some "-axxb!-" := by native_decide
theorem rx_replaceall_unknown_group :
    replaceAll "a(x*)b" "-axxb-" "$2" = some "--" := by native_decide
theorem rx_replaceall_multi : replaceAll "a(x*)b" "-axxb-axxxb-" "T" = some "-T-T-" := by
  native_decide
theorem rx_replaceall_no_match : replaceAll "a(x*)b" "-aQb-" "T" = some "-aQb-" := by native_decide
-- Zero-width match advances one rune (Go) — otherwise it loops.
theorem rx_replaceall_zero_width : replaceAll "x*" "abc" "-" = some "-a-b-c-" := by native_decide
theorem rx_replaceall_empty_pattern : replaceAll "" "abc" "-" = some "-a-b-c-" := by native_decide
-- ReplaceAllLiteral splices verbatim.
theorem rx_replaceall_literal_no_expand :
    replaceAllLiteral "a(x*)b" "-axxb-" "$1" = some "-$1-" := by native_decide
-- Invalid pattern → none at the engine layer (the dispatch site turns it into a bottom).
theorem rx_replaceall_invalid : replaceAll "a(" "x" "y" = none := by native_decide
-- The prod9 filter case.
theorem rx_replaceall_prod9 :
    replaceAll "([hb][^\\s]+)lo" "hello jello bello" "${1}ly"
      = some "helly jello belly" := by native_decide

-- The unanchored search must CROSS newlines: the implicit prefix is an any-char-incl-`\n`
-- star, NOT RE2 `.` (which excludes `\n`). cue's `=~`/`Match`/Find* all match across `\n`.
-- (A pre-existing RX-1b bug RX-1c surfaced via the prod9 multiline `([^\n]+)--two\n` filter.)
theorem rx_match_crosses_newline : matchRegex "two" "one\ntwo" = true := by native_decide
-- …but the fix must NOT make a bare `.` match `\n` (RE2: `.` excludes newline, no `(?s)`).
-- The unanchored PREFIX crosses `\n`; an explicit `.` in the PATTERN does not. Both pinned
-- against cue v0.16.1 (`"a\nb" =~ "a.b"` → false; `"a\nb" =~ "a.*b"` → false; `"abc" =~ "a.c"`
-- → true). Regression guard for the `ac354ab` prefix fix.
theorem rx_dot_excludes_newline : matchRegex "a.b" "a\nb" = false := by native_decide
theorem rx_dotstar_excludes_newline : matchRegex "a.*b" "a\nxb" = false := by native_decide
theorem rx_dot_matches_nonnewline : matchRegex "a.c" "abc" = true := by native_decide
theorem rx_findall_crosses_newline :
    findAll "[^\n]+" "\t--one\n\t--two\n\t--three"
      = some ["\t--one", "\t--two", "\t--three"] := by native_decide
-- The prod9 multiline insert filter (`${0}${1}--insert\n`) now matches across the newline.
theorem rx_replaceall_prod9_multiline :
    replaceAll "([^\n]+)--two\n" "\t--one\n\t--two\n\t--three" "${0}${1}--insert\n"
      = some "\t--one\n\t--two\n\t--insert\n\t--three" := by native_decide



-- COVERAGE TRIPWIRE (test-health). Anchors the last theorem of each section;
-- a swallowed section makes its anchor an unknown identifier and fails `#check`
-- elaboration.
#check @rx_repro_lazy_plus                      -- The 7 repro patterns parse into the correct struc...
#check @rx_lazy_opt                             -- Greediness as a Bool field — greedy vs lazy acros...
#check @rx_repeat_lazy                          -- Repeat `{m,n}` shapes — `max : Option Nat` (no se...
#check @rx_noncapturing_group                   -- Non-capturing group does NOT consume a capture index
#check @rx_class_negshort_folds_to_complement   -- Char classes — negation, perl-class fold, dot
#check @rx_backreference_rejected               -- Invalid patterns → error (NOT silent literal-fall...
#check @rx_posix_class_unsupported              -- Deferred RE2 constructs → explicit `.unsupportedR...
#check @rx_parse_error_valid_group_is_none      -- RX-2b — `regexParseError?` is the shared invalid-...
#check @rx_match_alt_plus_none                  -- RX-1b — Pike-VM match pins (the behavior change)
#check @rx_match_perl_word_neg                  -- Existing simple-pattern behavior stays correct (t...
#check @rx_class_negshort_now_parses            -- RX-2a — negated shorthand classes (`\D` `\W` `\S`...
#check @rx_lazy_stops                           -- Capture slots are computed (groundwork for RX-1c...
#check @rx_replaceall_prod9_multiline           -- RX-1c — submatch / Find* / ReplaceAll engine laye...

end Kue
