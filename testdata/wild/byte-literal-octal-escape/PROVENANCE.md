# byte-literal-octal-escape

- **Source:** BYTE-LITERAL-LEXING slice 2026-07-04, escape-matrix coverage (sibling of the
  graduated `byte-literal-hex-escape` seed).
- **CUE construct:** the `\NNN` octal byte escape inside a BYTE literal (`'...'`). `'\101\102\103'`
  is the three bytes `0x41 0x42 0x43` (`ABC`).
- **Spec basis (cue is right, kue now matches):** CUE byte literals support `\NNN` (exactly three
  octal digits) as a raw byte. `cue export --out json` → `{ "a": "QUJD" }` (base64 of `ABC`). Pins
  the octal escape path against cue's base64 oracle (the hex/`\x` family is pinned by
  `byte-literal-hex-escape`).
- **Status:** GREEN from birth — a coverage lock for the octal escape family, landed with the
  byte-literal escape-decoding lexer.
