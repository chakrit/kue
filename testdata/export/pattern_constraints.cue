// Pattern-constraint conformance surface (CORE-CONFORMANCE-PROBE, 2026-07-12).
// Measures pattern-constraint application: regex label predicates filtering fields,
// overlapping patterns intersecting their value constraints (comparator bounds),
// disjunction-valued patterns, and recursive patterns. Byte-identical to cue v0.16.1.
regexFilter: {[=~"^a"]: int, apple: 1, box: 2}

// Overlapping patterns: `ab` matches BOTH, so its value is constrained by `<10 & >5`.
multiPatternIntersect: {[=~"a"]: <10, [=~"b"]: >5, ab: 7}

// Disjunction-valued pattern applied to each added field.
disjunctionValued: {[string]: int | string, a: 1, b: "s"}

// Recursive pattern: the constraint is itself a pattern struct.
recursivePattern: {[string]: {y: int}, a: {y: 1}, b: {y: 2}}

// Pattern introduced via unification with a later struct.
viaUnification: {[string]: int} & {n: 3}

// Numeric-bound label predicate over a string field name.
boundLabel: {[>=3]: int, "5": 9}
