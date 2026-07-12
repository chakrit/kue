package repro

// Bytes are an ORDERED type in CUE — `< <= > >=` are defined over number, string,
// AND bytes, comparing bytes lexically by byte value. kue previously bottomed every
// bytes ordered comparison: `evalPrimitiveOrdering` threaded only decimal/string
// compare fns, so a bytes×bytes pair matched neither and fell to ⊥. Spec-correct
// verdict: compare by byte value. cue v0.16.1 agrees (all fields below hold).
lt:       'a' < 'b'
gtFalse:  'b' < 'a'
leEq:     'a' <= 'a'
byteVal:  '\x01' < '\x02'
lexical:  'ab' < 'ac'
emptyLt:  '' < 'a'
geFalse:  'a' >= 'b'
gtLonger: 'ab' > 'a'
