// A recognized CUE standard-library import (`net`, dot-free first path element =
// no domain) that kue does not yet implement. kue must route it to the BUILTIN layer and
// emit a clear "unsupported builtin package" error naming it — NOT the disk module
// loader's misleading "no cue.mod/module.cue found" error. This fixture pins the ROUTING +
// error contract for any unimplemented stdlib package. (Originally `strconv`, then `time`;
// repointed to `net` when STDLIB-TIME implemented time — the routing guard outlives any
// one package.)
import "net"

x: net.ParseIP("1.2.3.4")
