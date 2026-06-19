// RX-1 RE2 conformance repros. Each `=~` exercises a construct the old backtracking engine
// mis-validated (grouped quantifiers, nested/multi groups, `\b`, lazy quantifiers, the
// unsound substring fallback). The RX-1 Pike-VM now matches RE2/cue.
groupPlus:    "abab" =~ "^(ab)+$"
groupPlusNo:  "aba" =~ "^(ab)+$"
nestedGroup:  "foo-bar-baz" =~ "^([a-z0-9]+(-[a-z0-9]+)*)$"
semver:       "v1.2.3" =~ "^(v[0-9]+)(\\.[0-9]+)*$"
altGroups:    "axyd" =~ "a(b|x)(c|y)d"
wordBoundary: "cat dog" =~ "\\bdog\\b"
wordBoundNo:  "dogcat" =~ "\\bdog\\b"
lazyPlus:     "aaa" =~ "a+?"
altPlusSub:   "xfoobarx" =~ "(foo|bar)+"
