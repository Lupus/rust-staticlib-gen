type build_target =
  | Crate_name of string
  | Manifest_path of string

type t =
  { profile : string
  ; workspace_root : string option
  ; cargo_args : string list
  ; target : build_target
  ; output_dir : string option
  }

val parse : unit -> t
