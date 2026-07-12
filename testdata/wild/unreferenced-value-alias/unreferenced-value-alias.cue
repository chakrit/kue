package repro

// A value alias (`a: X=1`) that is never referenced is an ERROR in CUE: aliases
// must be used. cue v0.16.1 hard-errors `unreferenced alias or let clause X`.
// kue silently accepts it (`{a: 1, b: 1}`) — a missing load-time validation
// (the alias/let unreferenced-use check), the alias analog of the unused-import
// error kue already enforces.
// Spec-adjudicated verdict: a load error for the unreferenced alias.
a: X=1
b: a
