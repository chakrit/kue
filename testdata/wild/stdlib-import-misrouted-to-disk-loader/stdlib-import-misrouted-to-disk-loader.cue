// A recognized CUE standard-library import (`strconv`, dot-free first path element =
// no domain) that kue does not yet implement. kue must route it to the BUILTIN layer and
// emit a clear "unsupported builtin package" error naming it — NOT the disk module
// loader's misleading "no cue.mod/module.cue found" error. The struct/strconv function
// bodies are a later slice; this fixture pins only the ROUTING + error contract.
import "strconv"

x: strconv.Atoi("42")
