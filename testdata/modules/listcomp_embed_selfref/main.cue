package main

import "example.com/lib"

// `#host` narrows the embedded `#Hosts` guard to `#hosts: ["x.com"]`; the nested list
// comprehension over `Self.#hosts` must yield one listener.
out: lib.#Route & {#host: "x.com"}
