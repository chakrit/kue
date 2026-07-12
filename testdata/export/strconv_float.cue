import "strconv"

// strconv IEEE float64 surface (STDLIB-FLOAT-F2). ParseFloat stores the shortest-round-trip
// value (rendered by the float JSON style); FormatFloat returns Go-format strings. Only
// success cases live here; errors (overflow, syntax) are pinned by native_decide. Negative
// zero (ParseFloat("-0")) is EXCLUDED — cue emits `-0`, kue's float model normalizes to `0`
// (see cue-divergences.md STDLIB-FLOAT-F2).
parse_tenth:     strconv.ParseFloat("0.1", 64)
parse_pi:        strconv.ParseFloat("3.14", 64)
parse_e10:       strconv.ParseFloat("1e10", 64)
parse_hundred:   strconv.ParseFloat("100", 64)
parse_third:     strconv.ParseFloat("0.3333333333333333333", 64)
parse_denorm:    strconv.ParseFloat("2.2250738585072014e-308", 64)
parse_min:       strconv.ParseFloat("5e-324", 64)
parse_max:       strconv.ParseFloat("1.7976931348623157e308", 64)
parse_e23:       strconv.ParseFloat("1e23", 64)
parse_neg:       strconv.ParseFloat("-0.1", 64)
parse_underflow: strconv.ParseFloat("1e-400", 64)

fmt_g_short:  strconv.FormatFloat(1234.5678, 103, -1, 64)
fmt_e_short:  strconv.FormatFloat(1234.5678, 101, -1, 64)
fmt_f_short:  strconv.FormatFloat(1234.5678, 102, -1, 64)
fmt_g_big:    strconv.FormatFloat(1e20, 103, -1, 64)
fmt_g_e23:    strconv.FormatFloat(1e23, 103, -1, 64)
fmt_g_small:  strconv.FormatFloat(1e-5, 103, -1, 64)
fmt_g_whole:  strconv.FormatFloat(100000.0, 103, -1, 64)
fmt_int_in:   strconv.FormatFloat(100, 103, -1, 64)
fmt_e_prec:   strconv.FormatFloat(1234.5678, 101, 2, 64)
fmt_f_prec:   strconv.FormatFloat(1234.5678, 102, 2, 64)
fmt_g_prec:   strconv.FormatFloat(1234.5678, 103, 3, 64)
fmt_f_round:  strconv.FormatFloat(2.5, 102, 0, 64)
fmt_f_round2: strconv.FormatFloat(3.5, 102, 0, 64)
