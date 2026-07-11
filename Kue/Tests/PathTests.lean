import Kue.Builtin
import Kue.Tests.EvalTestHelpers

namespace Kue

-- STDLIB-PATH: the `path` builtin package. Each theorem pins one function against cue v0.16.1
-- on representative, boundary, and error inputs (values spec-adjudicated via the cue oracle for
-- this non-core, cue-compat surface). `Value` is a mutual inductive (`BEq`, no `DecidableEq`),
-- so theorems assert `(lhs == rhs) = true`, matching the repo's builtin-test convention.

private def call (name : String) (args : List Value) : Value := evalBuiltinCall name args
private def s (v : String) : Value := .prim (.string v)
private def unix : Value := s "unix"

-- Clean: normalization — multiple slashes, `.`, `..`, rooted `..` clamp, empty ⇒ ".".
theorem clean_dots :
    (call "path.Clean" [s "a//b/../c/./d"] == s "a/c/d") = true := by native_decide
theorem clean_empty : (call "path.Clean" [s ""] == s ".") = true := by native_decide
theorem clean_dot : (call "path.Clean" [s "."] == s ".") = true := by native_decide
theorem clean_dotdot : (call "path.Clean" [s ".."] == s "..") = true := by native_decide
theorem clean_double_dotdot : (call "path.Clean" [s "../.."] == s "../..") = true := by native_decide
theorem clean_rooted_dotdot : (call "path.Clean" [s "/../a"] == s "/a") = true := by native_decide
theorem clean_rel_climb : (call "path.Clean" [s "a/../.."] == s "..") = true := by native_decide
theorem clean_root : (call "path.Clean" [s "/"] == s "/") = true := by native_decide
theorem clean_all_slash : (call "path.Clean" [s "///"] == s "/") = true := by native_decide
theorem clean_trailing_slash : (call "path.Clean" [s "a/"] == s "a") = true := by native_decide
theorem clean_leading_dot : (call "path.Clean" [s "./a"] == s "a") = true := by native_decide
theorem clean_with_os : (call "path.Clean" [s "a//b", unix] == s "a/b") = true := by native_decide

-- Join: multiple segments, embedded/leading empties, `.`/`..`, absolute, empty list.
theorem join_basic : (call "path.Join" [.list [s "a", s "b", s "c"]] == s "a/b/c") = true := by
  native_decide
theorem join_slashes :
    (call "path.Join" [.list [s "a", s "b/", s "/c"]] == s "a/b/c") = true := by native_decide
theorem join_dotdot : (call "path.Join" [.list [s "a", s "..", s "c"]] == s "c") = true := by
  native_decide
theorem join_empty : (call "path.Join" [.list []] == s "") = true := by native_decide
theorem join_embedded_empties :
    (call "path.Join" [.list [s "", s "a", s "", s "b"]] == s "a/b") = true := by native_decide
theorem join_only_empty : (call "path.Join" [.list [s ""]] == s "") = true := by native_decide
theorem join_root : (call "path.Join" [.list [s "/", s "a"]] == s "/a") = true := by native_decide
theorem join_with_os :
    (call "path.Join" [.list [s "a", s "b"], unix] == s "a/b") = true := by native_decide
theorem join_nonstring_bottom :
    (call "path.Join" [.list [s "a", .prim (.int 1)]] == .bottom) = true := by native_decide

-- Base: last element; trailing slash stripped; root ⇒ "/"; empty ⇒ ".".
theorem base_basic : (call "path.Base" [s "/a/b/c"] == s "c") = true := by native_decide
theorem base_root : (call "path.Base" [s "/"] == s "/") = true := by native_decide
theorem base_all_slash : (call "path.Base" [s "//"] == s "/") = true := by native_decide
theorem base_empty : (call "path.Base" [s ""] == s ".") = true := by native_decide
theorem base_trailing : (call "path.Base" [s "a/b/"] == s "b") = true := by native_decide
theorem base_no_slash : (call "path.Base" [s "abc"] == s "abc") = true := by native_decide

-- Dir: parent; no slash ⇒ "."; root; trailing slash.
theorem dir_basic : (call "path.Dir" [s "/a/b/c"] == s "/a/b") = true := by native_decide
theorem dir_no_slash : (call "path.Dir" [s "a"] == s ".") = true := by native_decide
theorem dir_root : (call "path.Dir" [s "/"] == s "/") = true := by native_decide
theorem dir_trailing : (call "path.Dir" [s "a/b/"] == s "a/b") = true := by native_decide
theorem dir_empty : (call "path.Dir" [s ""] == s ".") = true := by native_decide

-- Ext: extension incl. dot; no ext ⇒ ""; dotfile is all-ext; last dot only; dot in dir ignored.
theorem ext_basic : (call "path.Ext" [s "a/b.txt"] == s ".txt") = true := by native_decide
theorem ext_none : (call "path.Ext" [s "a/b"] == s "") = true := by native_decide
theorem ext_dotfile : (call "path.Ext" [s ".bashrc"] == s ".bashrc") = true := by native_decide
theorem ext_multi : (call "path.Ext" [s "a.b.c"] == s ".c") = true := by native_decide
theorem ext_dir_dot : (call "path.Ext" [s "dir.d/file"] == s "") = true := by native_decide

-- IsAbs: leading slash true / relative false.
theorem isabs_true : (call "path.IsAbs" [s "/a"] == .prim (.bool true)) = true := by native_decide
theorem isabs_false : (call "path.IsAbs" [s "a"] == .prim (.bool false)) = true := by native_decide

-- Split: (dir-with-trailing-slash, file).
theorem split_basic :
    (call "path.Split" [s "/a/b/c"] == .list [s "/a/b/", s "c"]) = true := by native_decide
theorem split_no_dir : (call "path.Split" [s "a"] == .list [s "", s "a"]) = true := by native_decide
theorem split_root : (call "path.Split" [s "/"] == .list [s "/", s ""]) = true := by native_decide

-- SplitList: `:`-separated (unix); empty ⇒ []. No os default in cue ⇒ os arg required.
theorem splitlist_basic :
    (call "path.SplitList" [s "a:b:c", unix] == .list [s "a", s "b", s "c"]) = true := by
  native_decide
theorem splitlist_empty : (call "path.SplitList" [s "", unix] == .list []) = true := by
  native_decide

-- Resolve: absolute sub wins; else Clean(dir/sub).
theorem resolve_rel : (call "path.Resolve" [s "/a", s "b"] == s "/a/b") = true := by native_decide
theorem resolve_abs : (call "path.Resolve" [s "/a", s "/b"] == s "/b") = true := by native_decide
theorem resolve_both_rel : (call "path.Resolve" [s "a", s "b"] == s "a/b") = true := by native_decide

-- Rel: relative path; up-walk; identity ⇒ "."; mixed abs/rel ⇒ bottom.
theorem rel_down : (call "path.Rel" [s "/a", s "/a/b/c"] == s "b/c") = true := by native_decide
theorem rel_up : (call "path.Rel" [s "/a", s "/b"] == s "../b") = true := by native_decide
theorem rel_same : (call "path.Rel" [s "/a", s "/a"] == s ".") = true := by native_decide
theorem rel_up_multi : (call "path.Rel" [s "/a/b/c", s "/a"] == s "../..") = true := by native_decide
theorem rel_sibling : (call "path.Rel" [s "/a/b", s "/a/c"] == s "../c") = true := by native_decide
theorem rel_mixed_bottom : (call "path.Rel" [s "a", s "/b"] == .bottom) = true := by native_decide

-- Match: `*`/`?`/class hits and misses; `*` and `?` never cross `/`; negation via `^`;
-- `!` is literal; escapes; malformed pattern ⇒ bottom; `**` rejected.
theorem match_star : (call "path.Match" [s "*.go", s "a.go"] == .prim (.bool true)) = true := by
  native_decide
theorem match_star_miss :
    (call "path.Match" [s "*.go", s "a.txt"] == .prim (.bool false)) = true := by native_decide
theorem match_star_no_sep :
    (call "path.Match" [s "*", s "a/b"] == .prim (.bool false)) = true := by native_decide
theorem match_star_subpath :
    (call "path.Match" [s "a/*", s "a/b"] == .prim (.bool true)) = true := by native_decide
theorem match_question :
    (call "path.Match" [s "a?c", s "abc"] == .prim (.bool true)) = true := by native_decide
theorem match_question_no_sep :
    (call "path.Match" [s "?", s "/"] == .prim (.bool false)) = true := by native_decide
theorem match_class :
    (call "path.Match" [s "[a-c]", s "b"] == .prim (.bool true)) = true := by native_decide
theorem match_class_negated :
    (call "path.Match" [s "[^a]", s "b"] == .prim (.bool true)) = true := by native_decide
theorem match_class_negated_hit :
    (call "path.Match" [s "[^a]", s "a"] == .prim (.bool false)) = true := by native_decide
theorem match_bang_literal :
    (call "path.Match" [s "[!a]", s "!"] == .prim (.bool true)) = true := by native_decide
theorem match_star_middle :
    (call "path.Match" [s "a*c", s "abbbc"] == .prim (.bool true)) = true := by native_decide
theorem match_exact : (call "path.Match" [s "a", s "a"] == .prim (.bool true)) = true := by
  native_decide
theorem match_empty : (call "path.Match" [s "", s ""] == .prim (.bool true)) = true := by
  native_decide
theorem match_bad_open : (call "path.Match" [s "[", s "a"] == .bottom) = true := by native_decide
theorem match_bad_range : (call "path.Match" [s "[a-", s "x"] == .bottom) = true := by native_decide
theorem match_bad_dangling : (call "path.Match" [s "a[", s "x"] == .bottom) = true := by
  native_decide
theorem match_starstar : (call "path.Match" [s "**", s "a"] == .bottom) = true := by native_decide
theorem match_with_os :
    (call "path.Match" [s "*.go", s "a.go", unix] == .prim (.bool true)) = true := by native_decide

-- OS parameterization: plan9 == unix; explicit unix; windows deferred; invalid os ⇒ bottom.
theorem plan9_base : (call "path.Base" [s "/a/b", s "plan9"] == s "b") = true := by native_decide
theorem plan9_clean : (call "path.Clean" [s "a//b", s "plan9"] == s "a/b") = true := by native_decide
theorem fallback_os_linux : (call "path.Base" [s "/a/b", s "linux"] == s "b") = true := by
  native_decide
theorem windows_deferred :
    (call "path.Clean" [s "a/b", s "windows"]
      == .bottomWith [.unsupportedBuiltin "path.Clean"]) = true := by native_decide
theorem invalid_os_bottom : (call "path.Base" [s "/a/b", s "bogus"] == .bottom) = true := by
  native_decide

-- VolumeName: os default is Windows ⇒ bare call defers; explicit unix ⇒ "".
theorem volumename_bare_deferred :
    (call "path.VolumeName" [s "C:/a"]
      == .bottomWith [.unsupportedBuiltin "path.VolumeName"]) = true := by native_decide
theorem volumename_unix_empty : (call "path.VolumeName" [s "C:/a", unix] == s "") = true := by
  native_decide

-- ToSlash / FromSlash: unix identity (no os default in cue ⇒ os arg required).
theorem toslash_unix : (call "path.ToSlash" [s "a/b", unix] == s "a/b") = true := by native_decide
theorem fromslash_unix : (call "path.FromSlash" [s "a/b", unix] == s "a/b") = true := by
  native_decide

-- Unknown leaf routes through unresolvedOrBottom (concrete ⇒ bottom).
theorem unknown_leaf_bottom : (call "path.NoSuch" [s "x"] == .bottom) = true := by native_decide

-- Family classification.
theorem path_family : (BuiltinFamily.ofName? "path.Base" == some .path) = true := by native_decide

-- End-to-end: the `path.Unix` CONSTANT resolves (import-gated) and a defaulted call exports.
theorem const_unix_exports :
    exportJsonMatches "import \"path\"\nx: path.Unix\n" "{\n    \"x\": \"unix\"\n}\n" = true := by
  native_decide
theorem base_default_exports :
    exportJsonMatches "import \"path\"\nx: path.Base(\"/a/b/c\")\n" "{\n    \"x\": \"c\"\n}\n"
      = true := by native_decide
theorem base_os_const_exports :
    exportJsonMatches "import \"path\"\nx: path.Base(\"/a/b/c\", path.Unix)\n"
      "{\n    \"x\": \"c\"\n}\n" = true := by native_decide

-- COVERAGE TRIPWIRE (test-health): anchors the last theorem of each group.
#check @clean_with_os                -- Clean
#check @join_nonstring_bottom        -- Join
#check @base_no_slash                -- Base
#check @dir_empty                    -- Dir
#check @ext_dir_dot                  -- Ext
#check @isabs_false                  -- IsAbs
#check @split_root                   -- Split
#check @splitlist_empty              -- SplitList
#check @resolve_both_rel             -- Resolve
#check @rel_mixed_bottom             -- Rel
#check @match_with_os                -- Match
#check @invalid_os_bottom            -- OS parameterization
#check @volumename_unix_empty        -- VolumeName
#check @fromslash_unix               -- ToSlash / FromSlash
#check @base_os_const_exports        -- end-to-end (constant + export)

end Kue
