package repro

// GUARD (over-truncation, other direction): a GENUINE conflict across a duplicate-field
// merge must STILL bottom — the index-rebase / cycle-truncation fix must not swallow a
// real conflict. `x = 1` and `x = y = 2` is `1 & 2` = _|_.
// Spec-adjudicated: cue v0.16.1 reports "conflicting values 2 and 1".
x: 1
x: y
y: 2
