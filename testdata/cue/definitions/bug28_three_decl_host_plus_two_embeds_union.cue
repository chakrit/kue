#A1: {#additions: {cert_gw: {x: 1}}}
#A2: {#additions: {cert_ls: {z: 3}}}
#Use: {
	#A1
	#A2
	#additions: {cert_ing: {y: 2}}
	vis: #additions
}
out: #Use.vis
