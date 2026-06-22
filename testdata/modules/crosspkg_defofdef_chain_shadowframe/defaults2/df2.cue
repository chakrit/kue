package defaults2

import "example.com/defaults"

// Frame witness, TOP level: `_region`/`_tier` SHADOW both below (JP/top). `region2` reads the
// top `_region`. The 3-level def-of-def-of-def chain: each level's internal ref must resolve
// in ITS OWN package frame — zone="US", tier="mid", region2="JP".
_region: "JP"
_tier:   "top"

#ListenerSet: defaults.#ListenerSet & {
	region2: _region
}
