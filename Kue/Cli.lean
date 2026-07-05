import Kue.Runtime

namespace Kue.Cli

open Kue (ExportFormat)

/-- Options for the `export` subcommand: the output encoding, an optional `-e`
    field-path selector (`none` = export the whole root), and the optional input file
    (none = read stdin). Mirrors the historical `parseExportArgs` shape. -/
structure ExportOpts where
  format : ExportFormat
  expr : Option String
  file : Option String
deriving Repr, BEq, DecidableEq

/-- The subcommand a help request targets: `none` is the top-level usage. -/
inductive HelpTopic where
  | eval
  | export
  | mod
deriving Repr, BEq, DecidableEq

/-- A `mod` module-management operation. `tidy` resolves the requirement graph (MVS) and writes
    `cue.sum` (B3d-6b). `get` adds/updates a dependency in `cue.mod/module.cue`, carrying the raw
    `<module>[@version]` argument (parsed + resolved in `ModCmd.runModGet`). -/
inductive ModOp where
  | tidy
  | get (arg : String)
deriving Repr, BEq, DecidableEq

/-- A fully parsed invocation. `eval` carries the positional file list (empty = stdin via
    explicit `kue eval`); the bare `kue <file…>` shorthand routes through `parse`'s
    fallthrough to `.eval files`. `error` carries a usage diagnostic; the dispatcher prints
    it to stderr and exits with the usage code. -/
inductive Command where
  | eval (files : List String)
  | export (opts : ExportOpts)
  | mod (op : ModOp)
  | version
  | help (topic : Option HelpTopic)
  | error (message : String)
deriving Repr, BEq, DecidableEq

/-- Parse `export` flags into a `Command`. Default format is JSON, matching `cue export`'s
    default. A bare positional argument is the input file; absence means stdin. Only the
    first positional is taken as the file; trailing positionals are ignored, matching the
    historical parser. -/
def parseExport (format : ExportFormat) (expr file : Option String) :
    List String -> Command
  | [] => .export { format, expr, file }
  | "--help" :: _ => .help (some .export)
  | "-h" :: _ => .help (some .export)
  | "--out" :: "json" :: rest => parseExport .json expr file rest
  | "--out" :: "yaml" :: rest => parseExport .yaml expr file rest
  | "--out" :: other :: _ =>
      .error s!"unsupported --out format: {other} (expected json or yaml)"
  | "--out" :: [] => .error "missing value for --out"
  | "-e" :: value :: rest => parseExport format (some value) file rest
  | "-e" :: [] => .error "missing value for -e"
  | "--expression" :: value :: rest => parseExport format (some value) file rest
  | "--expression" :: [] => .error "missing value for --expression"
  | arg :: rest =>
      if arg.startsWith "-" then
        .error s!"unknown export flag: {arg}"
      else
        match file with
        | none => parseExport format expr (some arg) rest
        | some _ => parseExport format expr file rest

/-- Validate the positional arguments to `eval`: every argument is a file path; a flag-like
    token (leading `-`, other than the recognized help flags handled by the caller) is a
    usage error rather than a silently-accepted file name. -/
def parseEval : List String -> Command
  | [] => .eval []
  | "--help" :: _ => .help (some .eval)
  | "-h" :: _ => .help (some .eval)
  | args =>
      match args.find? (·.startsWith "-") with
      | some flag => .error s!"unknown eval flag: {flag}"
      | none => .eval args

/-- Parse the `mod` subcommand: `mod tidy` resolves the requirement graph (MVS) and writes
    `cue.sum`; `mod get <module>[@version]` adds/updates a dependency in `cue.mod/module.cue`
    (emitting the deps block, resolving `latest`/`@vN` against the registry tag list). An
    unknown/absent subcommand is a usage error. -/
def parseMod : List String -> Command
  | [] => .error "mod: expected a subcommand (tidy, get)"
  | "--help" :: _ => .help (some .mod)
  | "-h" :: _ => .help (some .mod)
  | "tidy" :: _ => .mod .tidy
  | "get" :: rest =>
      match rest with
      | [] => .error "mod get: expected a module path (e.g. `kue mod get example.com/foo@v1`)"
      | "--help" :: _ => .help (some .mod)
      | "-h" :: _ => .help (some .mod)
      | [arg] =>
          if arg.startsWith "-" then .error s!"mod get: unknown flag: {arg}"
          else .mod (.get arg)
      | _ => .error "mod get: expected exactly one module argument"
  | other :: _ => .error s!"mod: unknown subcommand: {other} (expected tidy, get)"

/-- Parse the whole argv into a `Command`. Dispatch rule: no arguments prints the
    top-level help (like `cue`/`git`/`docker`); a recognized subcommand as the first token
    routes to it; a recognized top-level flag (`--help`/`-h`, `--version`/`-V`) maps to its
    command; anything else is the `eval` path, so the bare `kue <file…>` shorthand keeps
    working. Stdin eval is explicit: `kue eval` (piped or `<`), never bare `kue`. -/
def parse : List String -> Command
  | [] => .help none
  | "eval" :: rest => parseEval rest
  | "export" :: rest => parseExport .json none none rest
  | "mod" :: rest => parseMod rest
  | "version" :: _ => .version
  | "--version" :: _ => .version
  | "-V" :: _ => .version
  | "help" :: "eval" :: _ => .help (some .eval)
  | "help" :: "export" :: _ => .help (some .export)
  | "help" :: _ => .help none
  | "--help" :: _ => .help none
  | "-h" :: _ => .help none
  | args =>
      match args.find? (·.startsWith "-") with
      | some flag => .error s!"unknown flag: {flag}"
      | none => .eval args

/-- Top-level usage text: synopsis, the subcommand list with one-line descriptions, and
    the global flags. -/
def topLevelHelp : String :=
  "kue — a Lean 4 reimplementation of the CUE language

Usage:
  kue <command> [arguments]
  kue <file...>             evaluate files (shorthand for `kue eval`)

Commands:
  eval [file...]            evaluate stdin or files; print the resolved value
  export [--out fmt] [file] manifest a value to JSON (default) or YAML
  mod tidy                  resolve the module requirement graph (MVS); write cue.sum
  mod get <module>[@ver]    add/update a dependency in cue.mod/module.cue
  version                   print the kue version
  help [command]            print help for kue or a command

Global flags:
  -h, --help                print this help
  -V, --version             print the kue version

Examples:
  kue eval config.cue       evaluate a file
  echo 'a: 1' | kue eval    evaluate CUE from stdin
  kue export --out yaml x.cue   manifest x.cue as YAML"

/-- Per-command usage for `eval`. -/
def evalHelp : String :=
  "kue eval — evaluate CUE and print the resolved value (internal format)

Usage:
  kue eval [file...]

With no file argument, reads CUE from stdin. With one or more files, evaluates their
merged contents. Prints the resolved top-level value."

/-- Per-command usage for `export`. -/
def exportHelp : String :=
  "kue export — manifest a concrete value and serialize it

Usage:
  kue export [--out json|yaml] [-e expr] [file]

With no file argument, reads CUE from stdin. Emits the manifested value as JSON (the
default) or YAML, byte-compatible with `cue export`. With `-e`, exports only the value at
the given dotted field path (e.g. `-e common` or `-e a.b.c`) instead of the whole root.

Flags:
  --out json|yaml          output format (default: json)
  -e, --expression expr    export the value at field path expr (e.g. common.name)"

/-- Per-command usage for `mod`. -/
def modHelp : String :=
  "kue mod — module management

Usage:
  kue mod tidy
  kue mod get <module>[@version]

`tidy` reads the main module's declared dependencies, fetches each transitive dependency's
cue.mod/module.cue over the (read-only) registry, runs Minimal Version Selection to pick one
version per module path (max-of-mins), and writes cue.sum with the verified h1: digests.

`get` adds or updates one dependency in cue.mod/module.cue's deps block. With no version (or
`@latest`) it selects the highest non-prerelease version from the registry's tag list; a partial
`@v1` or `@v1.2` selects the highest matching that prefix; a full `@v1.2.3` pins exactly. The deps
key is `\"<module>@v<major>\"`, so distinct majors of one module coexist.

The registry GETs are read-only; cue.sum is written into the module root."

/-- Resolve a help request to its usage text. -/
def helpText : Option HelpTopic -> String
  | none => topLevelHelp
  | some .eval => evalHelp
  | some .export => exportHelp
  | some .mod => modHelp

end Kue.Cli
