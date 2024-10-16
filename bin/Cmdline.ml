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

let usage_msg = "Usage: dune_cargo_build <crate_name|manifest_path> [output_dir]"

let parse () =
  let profile = ref "release" in
  let workspace_root = ref None in
  let args = ref [] in
  let cargo_args = ref [] in
  let speclist =
    [ "--profile", Arg.Set_string profile, "Build profile: release (default) or dev"
    ; ( "--workspace-root"
      , Arg.String (fun root -> workspace_root := Some root)
      , "Workspace root (in dune rules: -workspace-root %{workspace_root})" )
    ; ( "--"
      , Arg.Rest (fun arg -> cargo_args := arg :: !cargo_args)
      , "Pass the remaining arguments to cargo" )
    ]
  in
  let anon_fun arg = args := arg :: !args in
  let print_usage () =
    Arg.usage speclist usage_msg;
    exit 1
  in
  Arg.parse speclist anon_fun usage_msg;
  let args = List.rev !args in
  let target, output_dir =
    match args with
    | [ arg ] ->
      let target =
        if Filename.check_suffix arg "Cargo.toml"
        then Manifest_path arg
        else Crate_name arg
      in
      target, None
    | [ arg; output_dir ] ->
      let target =
        if Filename.check_suffix arg "Cargo.toml"
        then Manifest_path arg
        else Crate_name arg
      in
      if not (Sys.file_exists output_dir && Sys.is_directory output_dir)
      then failwith "Error: Output directory does not exist or is not a directory";
      target, Some output_dir
    | [] -> print_usage ()
    | _ -> print_usage ()
  in
  { profile = !profile
  ; workspace_root = !workspace_root
  ; cargo_args = !cargo_args
  ; target
  ; output_dir
  }
;;
