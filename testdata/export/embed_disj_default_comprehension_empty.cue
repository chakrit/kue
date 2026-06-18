_#A: {#data: [string]: string, mapped: {for k, v in #data {"\(k)": v}}}
_#B: {other: "b"}
#S: {#data: [string]: string, (*_#A | _#B)}
out: #S & {#data: {}}
