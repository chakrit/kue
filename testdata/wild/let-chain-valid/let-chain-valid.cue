package repro

// A non-cyclic `let` chain: b sees a (a sibling let), a is concrete. No cycle,
// so both resolve. Guards that valid let-to-let references still evaluate.
let a = 1
let b = a
c: b
