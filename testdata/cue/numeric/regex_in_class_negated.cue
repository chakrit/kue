// RX-2a: negated shorthand classes (`\D` `\W` `\S`) INSIDE a `[…]` class. Each folds its
// full complement set into the class union (`[\D5]` = non-digits ∪ {5}), with whole-class
// `[^…]` negation applied after the fold (`[^\D]` = digits). Cross-checked vs cue v0.16.1.
classD:      "a" =~ "^[\\D]$"
classDdigit: "5" =~ "^[\\D]$"
classW:      " " =~ "^[\\W]$"
classS:      " " =~ "^[\\S]$"
union:       "5" =~ "^[\\D5]$"
unionDigit:  "7" =~ "^[\\D5]$"
unionMember: "a" =~ "^[a\\W]$"
everything:  " " =~ "^[\\d\\D]$"
negMember:   "5" =~ "^[^\\D]$"
negMemberNo: "a" =~ "^[^\\D]$"
notClass:    "5" !~ "^[\\D]$"
