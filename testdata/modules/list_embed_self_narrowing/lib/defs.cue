package lib

// The `packs.#Argo` shape (argocd link 5). A definition whose only manifested content is a
// trailing LIST embed referencing `Self.<hidden-field>` — so the def manifests AS that list.
// The hidden fields carry the def's defaults; the use site narrows them. A `Self.#name` read
// INSIDE the list embed must resolve against the USE-SITE narrowing, not the def default.
//
// The use site is `#ListDef & { [...]; #name: "web" }` — a struct embedding an OPEN list with a
// hidden-field narrowing. It evaluates to an `.embeddedList` whose decls carry `#name: "web"`.
// The conjunction-deferral fold dropped that narrowing (the use operand collapsed to a list and
// `evaluatedStructOperand?` recovered no struct fields), so the def's list embed saw the def
// default `*"def-name" | string` → exported `"def-name"`. cue narrows to `"web"`.
#ListDef: Self={
	#name:   *"def-name" | string
	#suffix: *"-x" | string
	#components: {
		repo: {n: Self.#name, s: Self.#suffix}
		app: {n: Self.#name}
	}
	[Self.#components.repo, Self.#components.app]
}
