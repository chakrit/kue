package dep

// `#Probe` carries an interior conflict (`cmd: string & int`) but is NEVER referenced by the
// importing `main` package. cue is LAZY on unreferenced imported content: `main` exports clean
// even though `#Probe` would bottom in isolation. This is the cert-manager trap distilled — the
// A2-followup deep-bottom recurse must NOT fire here, which the `FieldClass.importBinding` marker
// guarantees by construction (the whole `dep` package binds as an `.importBinding`, kept shallow).
#Probe: {cmd: string} & {cmd: int}

#Used: {name: string}
