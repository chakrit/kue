# necessary-quoted-label-preserved

**Source:** AUDIT-QUOTED-BEQ over-normalization guard.

**Adjudication:** `a-b` cannot be written as a bare identifier, so `"a-b":` is NECESSARY
quoting, not optional. The AUDIT-QUOTED-BEQ fix strips the `Field.quoted` PROVENANCE bit to
`false` at the parse→eval seam, but must NOT lose the label's syntactic quoting: formatting
and export re-derive quoting from the label STRING (`a-b` is not a valid bare ident → quoted),
never from the stripped bit. Pins that the strip normalizes provenance only, and does not
over-normalize a must-be-quoted label into an invalid bare form.
