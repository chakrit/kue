import (
	"list"
	"strings"
)

// list.MinItems / MaxItems / UniqueItems and strings.MinRunes / MaxRunes constraint validators
// (STDLIB-VALIDATORS). Only satisfied cases live here — a violation is a cue export error (no
// json), pinned by native_decide theorems.
min_items: [1, 2, 3] & list.MinItems(2)
max_items: [1, 2] & list.MaxItems(3)
items_exact: [1, 2] & list.MinItems(2)
unique_ok: [1, 2, 3] & list.UniqueItems()
unique_bare: [4, 5] & list.UniqueItems
unique_structs: [{a: 1}, {a: 2}] & list.UniqueItems
min_and_max_items: [1, 2] & list.MinItems(1) & list.MaxItems(3)
unique_and_min: [1, 2, 3] & list.UniqueItems() & list.MinItems(2)
min_runes:       "abc" & strings.MinRunes(2)
max_runes:       "abcd" & strings.MaxRunes(4)
runes_multibyte: "é" & strings.MaxRunes(1)
