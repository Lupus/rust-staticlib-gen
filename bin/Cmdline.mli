type build_target =
  | Crate_name of string
  | Manifest_path of string

type action =
  | Build of build_target
  | Cargo_command of string

type t =
  { profile : string
  ; workspace_root : string option
  ; cargo_args : string list
  ; action : action
  ; output_dir : string option
  }

val parse : unit -> t
