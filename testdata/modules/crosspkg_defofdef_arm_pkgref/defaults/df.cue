package defaults

import (
	"example.com/defs"
	"example.com/extra"
)

// Frame witness on the IMPORT-BINDING dimension: the captured `.conj` arm carries a
// package-qualified ref `extra.Const`. The fix captures the arm over defaults' OWN frame
// (which imports `extra`); a use-site splice (into `main`, which does NOT import `extra`)
// would fail to resolve `extra.Const`. Result must be `source: "from-extra"`.
#ListenerSet: defs.#ListenerSet & {
	#gateway_name: "nginx"
	source:        extra.Const
}
