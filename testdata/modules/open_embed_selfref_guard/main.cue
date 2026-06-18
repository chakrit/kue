package main

import "example.com/lib"

// The use-site narrows `#host` (so the embedded `#Hosts` guard yields `#hosts: ["x.com"]`) and
// `#gateway_name`; the OPEN def's nested `Self.#hosts`/`Self.#gateway_name` must see both.
out: lib.#ListenerSet & {#host: "x.com", #gateway_name: "nginx"}
