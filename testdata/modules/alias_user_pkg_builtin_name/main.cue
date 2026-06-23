package main

import (
	f "example.com/json"
	g "example.com/list"
)

// OVER-fire guard: the import PATHs end in `json`/`list` (builtin names) but are USER
// packages. Aliased member access must resolve to the user package's fields, never be
// misdispatched as a builtin call / stdlib constant.
out: {
	bar:     f.Bar
	marshal: f.Marshal
	asc:     g.Ascending
}
