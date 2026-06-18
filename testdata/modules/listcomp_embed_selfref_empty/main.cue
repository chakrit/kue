package main

import "example.com/lib"

// Guard FALSE: `#host` is NOT narrowed, so the embedded `#Hosts` guard leaves `#hosts` empty and
// the list comprehension yields zero listeners — matching cue. Pins that the two-pass does not
// fabricate elements when the embedded field stays empty.
out: lib.#Route & {}
