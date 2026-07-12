import Kue.Decimal

namespace Kue

/-! # IEEE-754 binary float kernel (STDLIB-FLOAT F2)

The IEEE-754 binary64/binary32 surface CUE exposes through `strconv.FormatFloat` /
`strconv.ParseFloat` — distinct from the arbitrary-precision apd decimal that is CUE's
number model. A finite binary float is modelled EXACTLY as `(-1)^neg · mantissa · 2^binExp`
(`BinFloat`); every conversion is exact big-integer arithmetic (no hardware `Float`), so the
kernel is total and deterministic.

Two hard kernels, byte-identical to Go's `strconv` (cue v0.16.1 links a Go whose shortest-`'g'`
switch uses `eprec = 6`; the reference battery pins this):

- **decimal → binary** (`decimalToFloat`): correctly-rounded, round-half-to-even, with
  overflow → `.overflow` and underflow → ±0.
- **binary → shortest decimal** (`shortestDigits`): the Steele & White / Burger–Dybvig
  free-format shortest-round-trip digit generation, exact in integers.

Fixed-precision formatting (`exactDigits` + `roundToSig`) rounds the float's EXACT finite
decimal expansion to the requested digit count, matching Go (which rounds the exact value).

`ParseFloat`'s stored value is Go's shortest-`'g'` string fed through the existing float
renderer (`mkFloatText`) — the same path cue takes (`apd.SetFloat64` = `FormatFloat('g',-1)`
then `SetString`). See `docs/spec/cue-spec-gaps.md` STDLIB-FLOAT-F2. -/

/-- The parameters distinguishing binary64 from binary32: significand bit-width and the
    binary-exponent bounds of the normal range. `sigBits` normal mantissas span
    `[2^(sigBits-1), 2^sigBits)`; `minExp` is the exponent of the smallest subnormal; `maxExp`
    is the largest normal `binExp`. -/
structure FloatFormat where
  sigBits : Nat
  minExp : Int
  maxExp : Int

/-- binary64: 53 significand bits, min subnormal `2^-1074`, max normal `binExp` 971. -/
def f64Format : FloatFormat := { sigBits := 53, minExp := -1074, maxExp := 971 }

/-- binary32: 24 significand bits, min subnormal `2^-149`, max normal `binExp` 104. -/
def f32Format : FloatFormat := { sigBits := 24, minExp := -149, maxExp := 104 }

/-- A finite IEEE binary float: value `= (-1)^neg · mantissa · 2^binExp`. `mantissa = 0` is
    signed zero (`binExp` irrelevant). Normal values carry `mantissa ∈ [2^(sigBits-1),
    2^sigBits)`; subnormals `mantissa < 2^(sigBits-1)` with `binExp = minExp`. -/
structure BinFloat where
  neg : Bool
  mantissa : Nat
  binExp : Int
deriving Repr, BEq, DecidableEq

/-- Outcome of `decimalToFloat`: a finite float or IEEE overflow (magnitude `> maxfloat`).
    Underflow is NOT here — it yields a `.value` with `mantissa = 0`. -/
inductive FloatParse where
  | value (f : BinFloat)
  | overflow
deriving Repr, BEq

/-! ## Digit-list helpers (base-10, most-significant first) -/

/-- Decimal digits of `n`, most-significant first, no leading zeros (`0 ↦ [0]`). -/
def natDigits (n : Nat) : List Nat :=
  (toString n).toList.map (fun c => c.toNat - 48)

/-- The natural number a base-10 digit list denotes (`foldl`, tolerates a `10` entry so a
    round-up carry can be renormalized). -/
def digitsToNat (ds : List Nat) : Nat :=
  ds.foldl (fun acc d => acc * 10 + d) 0

/-- Drop trailing zeros, keeping at least one digit (`[1,2,0,0] ↦ [1,2]`, `[0] ↦ [0]`). -/
def trimTrailingZeros (ds : List Nat) : List Nat :=
  let trimmed := (ds.reverse.dropWhile (· == 0)).reverse
  if trimmed.isEmpty then [0] else trimmed

/-- `max(a, 0)` on an `Int`, as a `Nat`. -/
def intClampNat (a : Int) : Nat :=
  if a ≤ 0 then 0 else a.toNat

/-! ## Kernel A — decimal → binary, correctly rounded (round-half-to-even) -/

/-- Round `num / den` (`den > 0`) to the nearest integer, ties to even. -/
def roundDivHalfEven (num den : Nat) : Nat :=
  let q := num / den
  let r := num % den
  if 2 * r < den then q
  else if 2 * r > den then q + 1
  else q + q % 2

/-- The exact scaled pair `(N, D)` with `num/den · 2^(-e) = N/D`, so `⌊N/D⌋` is the mantissa
    at binary exponent `e`. -/
def scaledAt (num den : Nat) (e : Int) : Nat × Nat :=
  if e ≤ 0 then (num * 2 ^ (-e).toNat, den)
  else (num, den * 2 ^ e.toNat)

/-- Adjust `e` (fuel-bounded) until the floor quotient `⌊num/(den·2^e)⌋` lands in
    `[lo, hi) = [2^(sigBits-1), 2^sigBits)`. The seed from bit-length estimates is within a
    couple of steps, so the fixed budget dwarfs the needed iterations. -/
def findExp (num den lo hi : Nat) : Int → Nat → Int
  | e, 0 => e
  | e, fuel + 1 =>
      let (n, d) := scaledAt num den e
      let q := n / d
      if q ≥ hi then findExp num den lo hi (e + 1) fuel
      else if q < lo then findExp num den lo hi (e - 1) fuel
      else e

/-- Round the exact positive rational `num/den` to a `fmt`-format float magnitude
    (round-half-to-even), returning `.overflow` when it exceeds `maxfloat`. Subnormal inputs
    re-round at the fixed minimum exponent; a magnitude below half the smallest subnormal
    rounds to `mantissa = 0`. Sign is applied by the caller. -/
def decimalRatioToFloat (fmt : FloatFormat) (num den : Nat) : FloatParse :=
  let lo := 2 ^ (fmt.sigBits - 1)
  let hi := 2 ^ fmt.sigBits
  let e0 : Int := Int.ofNat (Nat.log2 num) - Int.ofNat (Nat.log2 den) - Int.ofNat fmt.sigBits
  let e := findExp num den lo hi e0 32
  if e < fmt.minExp then
    let (n, d) := scaledAt num den fmt.minExp
    FloatParse.value { neg := false, mantissa := roundDivHalfEven n d, binExp := fmt.minExp }
  else
    let (n, d) := scaledAt num den e
    let m0 := roundDivHalfEven n d
    let (m, e') := if m0 == hi then (lo, e + 1) else (m0, e)
    if e' > fmt.maxExp then FloatParse.overflow
    else FloatParse.value { neg := false, mantissa := m, binExp := e' }

/-- Correctly-rounded `± coeff · 10^exp10` → `fmt` float. Zero coefficient → signed zero. -/
def decimalToFloat (fmt : FloatFormat) (neg : Bool) (coeff : Nat) (exp10 : Int) : FloatParse :=
  if coeff == 0 then FloatParse.value { neg := neg, mantissa := 0, binExp := 0 }
  else
    let (num, den) :=
      if exp10 ≥ 0 then (coeff * evalPow10 exp10.toNat, 1)
      else (coeff, evalPow10 (-exp10).toNat)
    match decimalRatioToFloat fmt num den with
    | .overflow => .overflow
    | .value f => .value { f with neg := neg }

/-! ## Kernel B — binary → shortest decimal (Steele & White / Burger–Dybvig) -/

/-- Renormalize a digit list whose final entry may be `10` (a round-up carry) into a proper
    digit list, returning the carried digits and the resulting change in decimal-point
    position (`[9,10] ↦ ([1,0,0], +1)`). -/
def fixCarry (ds : List Nat) : List Nat × Int :=
  let out := natDigits (digitsToNat ds)
  (out, Int.ofNat out.length - Int.ofNat ds.length)

/-- Generate shortest decimal digits from the scaled Burger–Dybvig state `(R, mp, mm)` over
    the fixed scale `S`, terminating at the first digit where the remaining interval is
    covered by the rounding margins. `even` selects inclusive vs. strict boundary tests
    (round-half-to-even). Fuel bounds the significant-digit count (≤ 17 for binary64). -/
def genDigits (s : Nat) (even : Bool) : Nat → Nat → Nat → Nat → List Nat
  | _, _, _, 0 => []
  | r, mp, mm, fuel + 1 =>
      let r10 := r * 10
      let mp10 := mp * 10
      let mm10 := mm * 10
      let d := r10 / s
      let rem := r10 % s
      let low := if even then rem ≤ mm10 else rem < mm10
      let high := if even then rem + mp10 ≥ s else rem + mp10 > s
      if !low && !high then d :: genDigits s even rem mp10 mm10 fuel
      else
        let last :=
          if low && !high then d
          else if high && !low then d + 1
          else if 2 * rem < s then d
          else if 2 * rem > s then d + 1
          else d + d % 2
        [last]

/-- Scale the Burger–Dybvig state (fuel-bounded fixup after a bit-length pre-scale) so the
    first generated digit is the most significant, tracking the decimal-point position `k`. -/
def scaleFixup (even : Bool) : Nat → Nat → Nat → Nat → Int → Nat → (Nat × Nat × Nat × Nat × Int)
  | r, s, mp, mm, k, 0 => (r, s, mp, mm, k)
  | r, s, mp, mm, k, fuel + 1 =>
      let high := if even then r + mp ≥ s else r + mp > s
      if high then scaleFixup even r (s * 10) mp mm (k + 1) fuel
      else
        let low := if even then (r + mp) * 10 ≤ s else (r + mp) * 10 < s
        if low then scaleFixup even (r * 10) s (mp * 10) (mm * 10) (k - 1) fuel
        else (r, s, mp, mm, k)

/-- Shortest round-trip decimal digits of a NON-ZERO float, most-significant first, with the
    decimal-point position `dp` (value `= 0.d₁d₂… · 10^dp`). -/
def shortestDigits (fmt : FloatFormat) (f : BinFloat) : List Nat × Int :=
  let m := f.mantissa
  let e := f.binExp
  let boundary := m == 2 ^ (fmt.sigBits - 1)
  let even := m % 2 == 0
  let (r0, s0, mp0, mm0) : Nat × Nat × Nat × Nat :=
    if e ≥ 0 then
      let en := e.toNat
      if boundary then (m * 2 ^ (en + 2), 4, 2 ^ (en + 1), 2 ^ en)
      else (m * 2 ^ (en + 1), 2, 2 ^ en, 2 ^ en)
    else
      let ne := (-e).toNat
      if e == fmt.minExp || !boundary then (m * 2, 2 ^ (ne + 1), 1, 1)
      else (m * 4, 2 ^ (ne + 2), 2, 1)
  let k0 : Int := Int.ofNat (decimalDigitCount r0) - Int.ofNat (decimalDigitCount s0)
  let (r1, s1, mp1, mm1) : Nat × Nat × Nat × Nat :=
    if k0 ≥ 0 then (r0, s0 * evalPow10 k0.toNat, mp0, mm0)
    else
      let scale := evalPow10 (-k0).toNat
      (r0 * scale, s0, mp0 * scale, mm0 * scale)
  let (r, s, mp, mm, k) := scaleFixup even r1 s1 mp1 mm1 k0 16
  let rawDigits := genDigits s even r mp mm 30
  let (digits, delta) := fixCarry rawDigits
  -- A round-up carry (`[10] ↦ [1,0]`) introduces a trailing zero; shortest output carries
  -- none, so trim it (dp is measured from the left, unaffected).
  (trimTrailingZeros digits, k + delta)

/-! ## Kernel C — binary → exact finite decimal, for fixed-precision rounding -/

/-- The EXACT finite decimal expansion of a NON-ZERO float: digits most-significant first
    (leading and trailing zeros trimmed) with decimal-point position `dp`. Exact because
    `mantissa · 2^binExp` is a terminating decimal (`= mantissa · 5^(-binExp) / 10^(-binExp)`
    when `binExp < 0`). -/
def exactDigits (f : BinFloat) : List Nat × Int :=
  let m := f.mantissa
  let e := f.binExp
  if e ≥ 0 then
    let n := m * 2 ^ e.toNat
    let ds := natDigits n
    (trimTrailingZeros ds, Int.ofNat ds.length)
  else
    let ne := (-e).toNat
    let n := m * 5 ^ ne
    let ds := natDigits n
    (trimTrailingZeros ds, Int.ofNat ds.length - Int.ofNat ne)

/-- Round the exact digit list to `want` significant digits (round-half-to-even), returning
    the rounded digits and the possibly-shifted decimal-point position. `want ≥ length` is
    identity (already exact); `want = 0` rounds the leading digit into or out of view. -/
def roundToSig (ds : List Nat) (dp : Int) (want : Nat) : List Nat × Int :=
  if want ≥ ds.length then (ds, dp)
  else
    let kept := ds.take want
    let rest := ds.drop want
    let nextD := rest.headD 0
    let tailNonzero := (rest.drop 1).any (· ≠ 0)
    let lastKept := (kept.reverse.headD 0)
    let roundUp :=
      if nextD > 5 then true
      else if nextD < 5 then false
      else tailNonzero || lastKept % 2 == 1
    if roundUp then
      let inc := digitsToNat kept + 1
      let incDigits := natDigits inc
      (incDigits, dp + (Int.ofNat incDigits.length - Int.ofNat want))
    else if kept.isEmpty then ([0], dp)
    else (kept, dp)

/-! ## Go-compatible formatting of a decimal-slice `(digits, dp)` -/

/-- The ASCII character for decimal digit `d` (`d ≤ 9`). -/
def digitToChar (d : Nat) : Char := Char.ofNat (48 + d)

/-- `String` of a digit list. -/
def digitsToStr (ds : List Nat) : String := String.ofList (ds.map digitToChar)

/-- Go's `fmtF`: `[-]ddd.ddd`, no exponent, exactly `prec` fractional digits. -/
def fmtF (neg : Bool) (ds : List Nat) (dp : Int) (prec : Nat) : String :=
  let nd := ds.length
  let sign := if neg then "-" else ""
  let intPart :=
    if dp > 0 then
      let m := Nat.min nd dp.toNat
      digitsToStr (ds.take m) ++ String.ofList (List.replicate (dp.toNat - m) '0')
    else "0"
  let frac :=
    if prec > 0 then
      "." ++ String.ofList ((List.range prec).map (fun i =>
        let j : Int := dp + Int.ofNat i
        if 0 ≤ j ∧ j < Int.ofNat nd then digitToChar (ds.getD j.toNat 0) else '0'))
    else ""
  sign ++ intPart ++ frac

/-- Go's `fmtE`: `[-]d.ddde±dd` — one leading digit, `prec` fractional digits, signed
    exponent of at least two digits. `upper` selects `E` over `e`. -/
def fmtE (neg : Bool) (ds : List Nat) (dp : Int) (prec : Nat) (upper : Bool) : String :=
  let nd := ds.length
  let sign := if neg then "-" else ""
  let lead := digitToChar (ds.headD 0)
  let frac :=
    if prec > 0 then
      "." ++ String.ofList ((List.range prec).map (fun i =>
        let j := i + 1
        if j < nd then digitToChar (ds.getD j 0) else '0'))
    else ""
  let exp : Int := dp - 1
  let expAbs := exp.natAbs
  let expStr :=
    (if exp < 0 then "-" else "+") ++ (if expAbs < 10 then "0" else "") ++ toString expAbs
  sign ++ String.singleton lead ++ frac ++ (if upper then "E" else "e") ++ expStr

/-- Go's `formatDigits` for `'g'`/`'G'`: choose `%e` when `exp < -4 ∨ exp ≥ eprec`, else `%f`
    (`eprec = 6` for shortest, else the significant-digit precision). Assumes trailing zeros
    are already trimmed by the caller for the fixed path. -/
def fmtG (neg : Bool) (ds : List Nat) (dp : Int) (prec : Nat) (shortest upper : Bool) : String :=
  let nd := ds.length
  let eprec : Int :=
    if shortest then 6
    else
      let ep : Int := Int.ofNat prec
      if ep > Int.ofNat nd ∧ Int.ofNat nd ≥ dp then Int.ofNat nd else ep
  let exp := dp - 1
  if exp < -4 ∨ exp ≥ eprec then
    let prec' := if Int.ofNat prec > Int.ofNat nd then nd else prec
    fmtE neg ds dp (prec' - 1) upper
  else
    let prec' := if Int.ofNat prec > dp then nd else prec
    fmtF neg ds dp (intClampNat (Int.ofNat prec' - dp))

/-- Format a finite float with Go's `strconv.FormatFloat` verb + precision. `prec < 0` is
    shortest round-trip; `prec ≥ 0` is fixed. Verbs `e E f F g G`; other verbs (`b`, `x`, `X`)
    return `none` (deferred). -/
def formatBinFloat (fmt : FloatFormat) (verb : Char) (prec : Int) (f : BinFloat) : Option String :=
  let neg := f.neg
  let (ds, dp) := if f.mantissa == 0 then ([0], (1 : Int)) else shortestDigits fmt f
  if prec < 0 then
    let nd := ds.length
    match verb with
    | 'e' => some (fmtE neg ds dp (nd - 1) false)
    | 'E' => some (fmtE neg ds dp (nd - 1) true)
    | 'f' | 'F' => some (fmtF neg ds dp (intClampNat (Int.ofNat nd - dp)))
    | 'g' => some (fmtG neg ds dp nd true false)
    | 'G' => some (fmtG neg ds dp nd true true)
    | _ => none
  else
    let p := prec.toNat
    let (ed, edp) := if f.mantissa == 0 then ([0], (1 : Int)) else exactDigits f
    match verb with
    | 'e' | 'E' =>
        let (rd, rdp) := roundToSig ed edp (p + 1)
        some (fmtE neg rd rdp p (verb == 'E'))
    | 'f' | 'F' =>
        let want : Int := edp + Int.ofNat p
        let (rd, rdp) := if want < 0 then ([0], edp) else roundToSig ed edp want.toNat
        some (fmtF neg rd rdp p)
    | 'g' | 'G' =>
        let want := if p == 0 then 1 else p
        let (rd, rdp) := roundToSig ed edp want
        some (fmtG neg (trimTrailingZeros rd) rdp want false (verb == 'G'))
    | _ => none

/-! ## `strconv.ParseFloat` decimal grammar -/

/-- The digit value of an ASCII decimal digit, else `none`. -/
def asciiDigit? (c : Char) : Option Nat :=
  let n := c.toNat
  if n ≥ 48 ∧ n ≤ 57 then some (n - 48) else none

/-- Consume a maximal run of decimal digits, returning their value, count, and the tail. -/
def takeDigits : List Char → Nat → Nat → (Nat × Nat × List Char)
  | c :: cs, acc, cnt =>
      match asciiDigit? c with
      | some d => takeDigits cs (acc * 10 + d) (cnt + 1)
      | none => (acc, cnt, c :: cs)
  | [], acc, cnt => (acc, cnt, [])

/-- Parse Go's decimal-float grammar `[sign] ( D[.D] | .D ) [ (e|E)[sign]D ]` into
    `(neg, coeff, exp10)` with value `= (-1)^neg · coeff · 10^exp10`. `none` on any syntax
    deviation (Go's `Inf`/`NaN`/hex-float/underscore forms are deferred → syntax error). -/
def parseFloatDecimal (s : String) : Option (Bool × Nat × Int) :=
  let chars := s.toList
  let (neg, rest0) :=
    match chars with
    | '+' :: t => (false, t)
    | '-' :: t => (true, t)
    | t => (false, t)
  let (intVal, intCnt, rest1) := takeDigits rest0 0 0
  let (coeffBase, fracCnt, rest2) :=
    match rest1 with
    | '.' :: t =>
        let (fracVal, fracCnt, t') := takeDigits t 0 0
        (intVal * evalPow10 fracCnt + fracVal, fracCnt, t')
    | _ => (intVal, 0, rest1)
  if intCnt + fracCnt == 0 then none
  else
    match rest2 with
    | [] => some (neg, coeffBase, -(Int.ofNat fracCnt))
    | e :: t =>
        if e == 'e' || e == 'E' then
          let (expNeg, t') :=
            match t with
            | '+' :: u => (false, u)
            | '-' :: u => (true, u)
            | u => (false, u)
          let (expVal, expCnt, t'') := takeDigits t' 0 0
          if expCnt == 0 || t'' ≠ [] then none
          else
            let signedExp := if expNeg then -(Int.ofNat expVal) else Int.ofNat expVal
            some (neg, coeffBase, signedExp - Int.ofNat fracCnt)
        else none

/-- The `FloatFormat` for a `strconv` `bitSize`, `none` for an unsupported size (only 32/64
    are implemented; other sizes are deferred). -/
def floatFormatOfBits? (bits : Int) : Option FloatFormat :=
  if bits == 64 then some f64Format
  else if bits == 32 then some f32Format
  else none

/-- `strconv.ParseFloat(s, bitSize)`. Parses `s` to the correctly-rounded float, then stores
    Go's shortest-`'g'` string as the result float's render anchor (the path cue takes via
    `apd.SetFloat64`). Overflow → `strconvRange`; syntax error → `strconvSyntax`; an
    unsupported `bitSize` is deferred (`unsupportedBuiltin`). -/
def strconvParseFloat (input : String) (bits : Int) : Value :=
  match floatFormatOfBits? bits with
  | none => .bottomWith [.unsupportedBuiltin "strconv.ParseFloat (bitSize ∉ {32,64})"]
  | some fmt =>
      match parseFloatDecimal input with
      | none => .bottomWith [.strconvSyntax input]
      | some (neg, coeff, exp10) =>
          match decimalToFloat fmt neg coeff exp10 with
          | .overflow => .bottomWith [.strconvRange input]
          | .value f =>
              -- cue stores `apd.SetFloat64(f)` = the shortest SCIENTIFIC (`'e'`) string, then
              -- re-renders via its own GDA — so `ParseFloat("100")` renders `1E+2`, not `100`.
              -- Anchoring on `'e'` (not `'g'`) reproduces that apd `(coefficient, exponent)` split.
              match formatBinFloat fmt 'e' (-1) f with
              | some text => .prim (mkFloatText text)
              | none => .bottomWith [.strconvSyntax input]

/-- `strconv.FormatFloat(f, fmt, prec, bitSize)`. Converts the CUE number (apd decimal) to the
    `bitSize` float, then formats with Go's verb/precision. Unsupported verb or `bitSize` is
    deferred; an overflowing magnitude renders Go's `±Inf`. -/
def strconvFormatFloat (num : Prim) (verb prec bits : Int) : Value :=
  match floatFormatOfBits? bits, primApdForm? num with
  | some fmt, some apd =>
      let verbChar := Char.ofNat verb.toNat
      match decimalToFloat fmt apd.negative apd.coefficient apd.exponent with
      | .overflow => .prim (.string (if apd.negative then "-Inf" else "+Inf"))
      | .value f =>
          match formatBinFloat fmt verbChar prec f with
          | some text => .prim (.string text)
          | none => .bottomWith [.unsupportedBuiltin "strconv.FormatFloat (verb ∉ {e,E,f,F,g,G})"]
  | none, _ => .bottomWith [.unsupportedBuiltin "strconv.FormatFloat (bitSize ∉ {32,64})"]
  | _, none => .bottomWith [.unsupportedBuiltin "strconv.FormatFloat (non-numeric)"]

end Kue
