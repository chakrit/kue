import Kue.Builtin
import Kue.Format
import Kue.Lattice
import Kue.Runtime
import Kue.Tests.EvalTestHelpers

namespace Kue

-- Pattern-constraint LABEL aliases (`[Name=string]: {n: Name}`): the alias binds each matched
-- field's concrete label as a string, in scope within the constraint body. `evalSourceMatches`
-- pins BOTH the applied fields and the residual pattern (whose unbound placeholder renders as the
-- alias name), so a regression in either the per-match substitution or the marker is caught.

theorem pattern_alias_binds_matched_label :
    evalSourceMatches
      "[Name=string]: {n: Name}\nfoo: {}"
      "{foo: {n: \"foo\"}, [string]: {n: Name}}" := by
  native_decide

theorem pattern_alias_each_field_own_label :
    evalSourceMatches
      "a: {[Name=string]: {n: Name}, foo: {}, bar: {}}"
      "a: {foo: {n: \"foo\"}, bar: {n: \"bar\"}, [string]: {n: Name}}" := by
  native_decide

theorem pattern_alias_top_pattern :
    evalSourceMatches
      "a: {[Name=_]: {n: Name}, foo: {}}"
      "a: {foo: {n: \"foo\"}, [_]: {n: Name}}" := by
  native_decide

-- A comparator pattern with an alias binds on the matched labels and skips non-matching ones.
theorem pattern_alias_comparator_pattern :
    evalSourceMatches
      "a: {[Name= <\"m\"]: {n: Name}, aa: {}, zz: {}}"
      "a: {aa: {n: \"aa\"}, zz: {}, [<\"m\"]: {n: Name}}" := by
  native_decide

-- Nested aliases each resolve to their own matched label; the OUTER alias is visible inside the
-- INNER constraint (lexical scoping), so `m` takes the outer label and `i` the inner one.
theorem pattern_alias_nested_crossref :
    evalSourceMatches
      "a: {[Name=string]: {sub: {[Inner=string]: {m: Name, i: Inner}}}, foo: {sub: {bar: {}}}}"
      "a: {foo: {sub: {bar: {m: \"foo\", i: \"bar\"}, [string]: {m: \"foo\", i: Inner}}}, [string]: {sub: {[string]: {m: Name, i: Inner}}}}" := by
  native_decide

theorem pattern_alias_two_level_own_labels :
    evalSourceMatches
      "a: {[X=string]: {[Y=string]: {p: X, q: Y}}, foo: {bar: {}}}"
      "a: {foo: {bar: {p: \"foo\", q: \"bar\"}, [string]: {p: \"foo\", q: Y}}, [string]: {[string]: {p: X, q: Y}}}" := by
  native_decide

-- A concrete field agreeing with the alias-derived value unifies; a disagreeing one bottoms.
theorem pattern_alias_concrete_agrees :
    evalSourceMatches
      "a: {[Name=string]: {n: Name}, foo: {n: \"foo\"}}"
      "a: {foo: {n: \"foo\"}, [string]: {n: Name}}" := by
  native_decide

theorem pattern_alias_concrete_conflict_bottoms :
    exportJsonBottoms
      "a: {[Name=string]: {n: Name}, foo: {n: \"bar\"}}" := by
  native_decide

-- The alias name does NOT leak outside the constraint: a sibling reference to `Name` at the struct
-- level is an unresolved reference (the alias is scoped to the pattern body only).
theorem pattern_alias_does_not_leak_to_sibling :
    exportJsonBottoms
      "a: {[Name=string]: {n: Name}, foo: {}, leak: Name}" := by
  native_decide

-- `[x=~"re"]` is a regex-match pattern (the `=~` operator), NOT a label alias: the `=~` is not
-- consumed as an alias `=`, so the bracket parses as the comparison expression `x =~ "re"`. Were it
-- mis-read as an alias, `parseExpression` would face `~"re"` and fail.
theorem regex_match_pattern_is_not_alias :
    (match parseSource "{[x=~\"re\"]: int}" with | .ok _ => true | .error _ => false) = true := by
  native_decide

#check @pattern_alias_binds_matched_label     -- basic label binding
#check @pattern_alias_nested_crossref         -- nested + cross-scope
#check @pattern_alias_does_not_leak_to_sibling -- scope non-leak
#check @regex_match_pattern_is_not_alias      -- `=~` is not an alias

end Kue
