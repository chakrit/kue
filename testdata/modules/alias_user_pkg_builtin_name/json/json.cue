package json

// A USER package whose final path element collides with the builtin `json`. An aliased
// import of it must resolve to THESE values, never the builtin Marshal/etc — the over-fire
// boundary: `isBuiltinImport` keys on the full import PATH (`example.com/json` ∉ the builtin
// set), so the alias canonicalization leaves `f.Marshal` as a user selector.
Marshal: "USER_MARSHAL"
Bar:     42
