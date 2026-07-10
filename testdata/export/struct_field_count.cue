import "struct"

// struct.MinFields / struct.MaxFields validators (STDLIB-B). Only satisfied cases live
// here — a violation is a cue export error (no json), pinned by native_decide theorems.
min_exact: {a: 1, b: 2} & struct.MinFields(2)
min_zero: {} & struct.MinFields(0)
min_optional_excluded: {a: 1, b?: 2} & struct.MinFields(1)
max_ok: {a: 1, b: 2} & struct.MaxFields(3)
min_and_max: {a: 1, b: 2} & struct.MinFields(1) & struct.MaxFields(3)
accrete_across_conjuncts: {a: 1} & struct.MinFields(2) & {b: 2}
negative_min: {a: 1} & struct.MinFields(-1)
