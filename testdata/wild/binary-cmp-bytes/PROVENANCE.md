# binary-cmp-bytes

- **Source:** BINARY-CMP-BYTES, filed by the BINARY-CMP-OPERAND slice (`4bb40b3`) while
  measuring the ordered-comparison operand matrix. The last active wrong-value bug.
- **Defect:** `evalPrimitiveOrdering` threaded only a decimal and a string compare fn.
  A bytes×bytes operand pair matched neither and fell to the `| _, _ => .bottom` arm, so
  every bytes ordered comparison (`'a' < 'b'`) bottomed instead of comparing.
- **Spec basis:** CUE ordered comparison (`< <= > >=`) is defined over operands of the
  same ordered type — number, string, AND bytes — bytes compared lexically by byte
  value. So `'a' < 'b'` is `true`, not a type error.
- **cue:** v0.16.1 — every field holds (`lt: true`, `gtFalse: false`, …); kue previously
  rendered `_|_` for all of them.
- **Fix:** `evalPrimitiveOrdering` routes the prim×prim case through `primOrdCompare?`
  (the single ordered-comparison primitive, already handling number/string/bytes) and
  interprets the resulting `Ordering` with the op's `Ordering -> Bool` reader
  (`isLT`/`isLE`/`isGT`/`isGE`). Bytes flow through for free; cross-type pairs
  (bytes-vs-string, bytes-vs-number) still yield `none` ⇒ ⊥.
