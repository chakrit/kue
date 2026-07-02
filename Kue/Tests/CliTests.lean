import Kue.Cli

namespace Kue.Cli

-- No arguments prints the top-level help (cue/git/docker convention), never the eval
-- path — this is what makes bare `kue` print usage instead of hanging on stdin.
theorem parse_empty : parse [] = .help none := by native_decide

theorem parse_bare_file : parse ["a.cue"] = .eval ["a.cue"] := by native_decide

theorem parse_bare_files : parse ["a.cue", "b.cue"] = .eval ["a.cue", "b.cue"] := by
  native_decide

theorem parse_eval_subcommand : parse ["eval", "a.cue"] = .eval ["a.cue"] := by native_decide

theorem parse_eval_stdin : parse ["eval"] = .eval [] := by native_decide

theorem parse_export_default :
    parse ["export"] = .export { format := .json, expr := none, file := none } := by
  native_decide

theorem parse_export_yaml :
    parse ["export", "--out", "yaml"]
      = .export { format := .yaml, expr := none, file := none } := by
  native_decide

theorem parse_export_json_file :
    parse ["export", "--out", "json", "x.cue"]
      = .export { format := .json, expr := none, file := some "x.cue" } := by
  native_decide

theorem parse_export_file_only :
    parse ["export", "x.cue"]
      = .export { format := .json, expr := none, file := some "x.cue" } := by
  native_decide

theorem parse_export_expr_short :
    parse ["export", "-e", "foo", "f.cue"]
      = .export { format := .json, expr := some "foo", file := some "f.cue" } := by
  native_decide

theorem parse_export_expr_long :
    parse ["export", "--expression", "a.b.c", "f.cue"]
      = .export { format := .json, expr := some "a.b.c", file := some "f.cue" } := by
  native_decide

theorem parse_export_expr_with_out_yaml :
    parse ["export", "-e", "common", "--out", "yaml", "f.cue"]
      = .export { format := .yaml, expr := some "common", file := some "f.cue" } := by
  native_decide

theorem parse_export_expr_stdin :
    parse ["export", "-e", "foo"]
      = .export { format := .json, expr := some "foo", file := none } := by
  native_decide

theorem parse_export_expr_missing_value_is_error :
    parse ["export", "-e"] = .error "missing value for -e" := by native_decide

theorem parse_export_expression_missing_value_is_error :
    parse ["export", "--expression"] = .error "missing value for --expression" := by
  native_decide

theorem parse_version_subcommand : parse ["version"] = .version := by native_decide

theorem parse_version_long : parse ["--version"] = .version := by native_decide

theorem parse_version_short : parse ["-V"] = .version := by native_decide

theorem parse_help_long : parse ["--help"] = .help none := by native_decide

theorem parse_help_short : parse ["-h"] = .help none := by native_decide

theorem parse_help_subcommand : parse ["help"] = .help none := by native_decide

theorem parse_help_eval : parse ["help", "eval"] = .help (some .eval) := by native_decide

theorem parse_help_export : parse ["help", "export"] = .help (some .export) := by native_decide

theorem parse_eval_help_flag : parse ["eval", "--help"] = .help (some .eval) := by native_decide

theorem parse_export_help_flag :
    parse ["export", "--help"] = .help (some .export) := by native_decide

theorem parse_unknown_flag_is_error :
    parse ["--bogus"] = .error "unknown flag: --bogus" := by native_decide

theorem parse_export_bad_out_is_error :
    parse ["export", "--out", "toml"]
      = .error "unsupported --out format: toml (expected json or yaml)" := by
  native_decide

theorem parse_export_missing_out_is_error :
    parse ["export", "--out"] = .error "missing value for --out" := by native_decide

theorem parse_export_unknown_flag_is_error :
    parse ["export", "--bogus"] = .error "unknown export flag: --bogus" := by native_decide

theorem parse_eval_unknown_flag_is_error :
    parse ["eval", "--bogus"] = .error "unknown eval flag: --bogus" := by native_decide


-- COVERAGE TRIPWIRE (test-health). Anchors the last theorem of each section;
-- a swallowed section makes its anchor an unknown identifier and fails `#check`
-- elaboration.
#check @parse_eval_unknown_flag_is_error

end Kue.Cli
