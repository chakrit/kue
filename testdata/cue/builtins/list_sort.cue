import "list"

ascending: list.Sort([3, 1, 2], list.Ascending)
descending: list.Sort([1, 3, 2], list.Descending)
alreadySort: list.Sort([1, 2, 3], list.Ascending)
empty: list.Sort([], list.Ascending)
single: list.Sort([5], list.Ascending)
duplicates: list.Sort([3, 1, 2, 1, 3], list.Ascending)
strings: list.Sort(["banana", "apple", "cherry"], list.Ascending)
negatives: list.Sort([3, -1, 2, -5, 0], list.Ascending)
inlineCmp: list.Sort([3, 1, 2], {x: _, y: _, less: x < y})
byField: list.Sort([{k: 3}, {k: 1}, {k: 2}], {x: {k: _}, y: {k: _}, less: x.k < y.k})
stableTies: list.SortStable([{k: 1, v: "a"}, {k: 1, v: "b"}, {k: 0, v: "c"}, {k: 1, v: "d"}], {x: {k: _}, y: {k: _}, less: x.k < y.k})
stableEmpty: list.SortStable([], list.Ascending)
