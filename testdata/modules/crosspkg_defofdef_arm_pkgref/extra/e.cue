package extra

// A constant the def-of-def's arm references PACKAGE-QUALIFIED. `main` does NOT import
// `extra`; only `defaults` does. So `extra.Const` can only resolve in defaults' frame.
Const: "from-extra"
