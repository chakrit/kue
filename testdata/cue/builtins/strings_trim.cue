import "strings"

trim:      strings.Trim("¡¡hi!!", "¡!")
trimSpace: strings.Trim("  héllo  ", " ")
trimLeft:  strings.TrimLeft("abcabX", "abc")
trimRight: strings.TrimRight("Xcba", "abc")
trimPre:   strings.TrimPrefix("hello", "he")
trimPreNo: strings.TrimPrefix("hello", "xy")
trimSuf:   strings.TrimSuffix("hello", "lo")
trimSufNo: strings.TrimSuffix("hello", "xy")
