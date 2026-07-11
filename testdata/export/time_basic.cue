import "time"

// time package exact/structural surface (STDLIB-TIME). Only success cases live here —
// invalid inputs (bad durations, out-of-range timestamps) are pinned by native_decide
// (a validator conflict is a cue export error, no json).
parse_hm:       time.ParseDuration("1h30m")
parse_ms:       time.ParseDuration("300ms")
parse_neg:      time.ParseDuration("-2h")
parse_frac:     time.ParseDuration("1.5h")
parse_combo:    time.ParseDuration("1h30m45s")
parse_us:       time.ParseDuration("100us")
parse_ns:       time.ParseDuration("10ns")
nanosecond:     time.Nanosecond
second:         time.Second
hour:           time.Hour
rfc3339:        time.RFC3339
kitchen:        time.Kitchen
january:        time.January
sunday:         time.Sunday
dur_validated:  "1h30m" & time.Duration
time_validated: "2019-01-02T15:04:05Z" & time.Time()
time_offset:    "2020-02-29T23:59:59+07:00" & time.Time()
fmt_validated:  "2019-01-02T15:04:05Z" & time.Format(time.RFC3339)
