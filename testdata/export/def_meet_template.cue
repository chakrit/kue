#Argo: {
	name:      string
	namespace: string
	out: {
		meta: {
			n:  name
			ns: namespace
		}
	}
}

app: #Argo & {
	name:      "web"
	namespace: "prod"
}
