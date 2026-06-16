import "list"

basic: list.SortStrings(["banana", "apple", "cherry"])
dup: list.SortStrings(["b", "a", "b", "a"])
empty: list.SortStrings([])
single: list.SortStrings(["x"])
sorted: list.SortStrings(["a", "b", "c"])
reverse: list.SortStrings(["c", "b", "a"])
caps: list.SortStrings(["b", "A", "a", "B"])
unicode: list.SortStrings(["é", "a", "z", "Z"])
