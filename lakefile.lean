import Lake
open Lake DSL

package kue where
  version := v!"0.1.0"

lean_lib Kue where

@[default_target]
lean_exe kue where
  root := `Main
