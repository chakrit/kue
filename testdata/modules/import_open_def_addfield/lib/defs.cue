package lib

// An OPEN definition (`...`) imported across packages. The eager selector must NOT over-close it:
// `normalizeDefinitionValueWithFuel` returns a `defOpenViaTail` body UNCHANGED, so a use-site
// added field is still admitted. The closed sibling rejecting the same field is the
// `import_closed_def_addfield` fixture.
#Open: {
	port: int
	...
}
