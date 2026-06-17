base: "stage9"
components: {
	repo: {who: base}
	project: {who: base}
	app: {who: base}
}
repoWho:    components.repo.who
projectWho: components.project.who
appWho:     components.app.who
