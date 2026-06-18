_#A: {#x: string, copy: #x}
_#B: {#x: string, other: "b"}
#S: {#x: string, (*_#A | _#B)}
out: #S & {#x: "hi"}
