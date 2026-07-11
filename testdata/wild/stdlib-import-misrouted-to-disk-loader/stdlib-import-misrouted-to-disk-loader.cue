// A recognized CUE standard-library import (`uuid`, dot-free first path element =
// no domain) that kue does not yet implement. kue must route it to the BUILTIN layer and
// emit a clear "unsupported builtin package" error naming it — NOT the disk module
// loader's misleading "no cue.mod/module.cue found" error. This fixture pins the ROUTING +
// error contract for any unimplemented stdlib package. (Originally `strconv`, then `time`,
// then `net`; repointed to `uuid` when STDLIB-NET implemented net — the routing guard
// outlives any one package.)
import "uuid"

x: uuid.Valid("abc")
