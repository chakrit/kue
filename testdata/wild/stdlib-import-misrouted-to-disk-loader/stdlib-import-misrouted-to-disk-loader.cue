// A recognized CUE standard-library import (`time`, dot-free first path element =
// no domain) that kue does not yet implement. kue must route it to the BUILTIN layer and
// emit a clear "unsupported builtin package" error naming it — NOT the disk module
// loader's misleading "no cue.mod/module.cue found" error. This fixture pins the ROUTING +
// error contract for any unimplemented stdlib package. (Originally `strconv`; repointed to
// `time` when STDLIB-C implemented strconv — the routing guard outlives any one package.)
import "time"

x: time.Now()
