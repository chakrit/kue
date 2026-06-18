_#Mapper: {#data: [string]: string, mapped: {for k, v in #data {"\(k)": v}}}
#S: {#data: [string]: string, _#Mapper}
out: #S & {#data: {baz: "qux", foo: "bar"}}
