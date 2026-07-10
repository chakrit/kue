import "strconv"

// strconv pure conversions (STDLIB-C). Only success cases live here — error inputs are
// pinned by native_decide (a parse failure is a cue export error, no json).
atoi:            strconv.Atoi("42")
atoi_neg:        strconv.Atoi("-7")
atoi_big:        strconv.Atoi("99999999999999999999999")
format_int_hex:  strconv.FormatInt(255, 16)
format_int_neg:  strconv.FormatInt(-255, 16)
format_int_bin:  strconv.FormatInt(5, 2)
format_int_b36:  strconv.FormatInt(35, 36)
format_uint_hex: strconv.FormatUint(255, 16)
parse_int_hex:   strconv.ParseInt("ff", 16, 64)
parse_int_auto:  strconv.ParseInt("0x1F", 0, 64)
parse_int_us:    strconv.ParseInt("1_000", 0, 64)
parse_uint_max:  strconv.ParseUint("18446744073709551615", 10, 64)
format_bool:     strconv.FormatBool(true)
parse_bool:      strconv.ParseBool("T")
roundtrip:       strconv.ParseInt(strconv.FormatInt(48879, 16), 16, 64)
