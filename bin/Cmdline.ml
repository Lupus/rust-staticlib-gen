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
  let action, output_dir =
    match args with
    | [ arg ] ->
      let action =
        if String.get arg 0 = '@'
        then (
          let cmd = String.sub arg 1 (String.length arg - 1) in
          Cargo_command cmd)
        else if Filename.check_suffix arg "Cargo.toml"
        then Build (Manifest_path arg)
        else Build (Crate_name arg)
      in
      action, None
    | [ arg; output_dir ] ->
      let target =
        if Filename.check_suffix arg "Cargo.toml"
        then Manifest_path arg
        else Crate_name arg
      in
      if not (Sys.file_exists output_dir && Sys.is_directory output_dir)
      then failwith "Error: Output directory does not exist or is not a directory";
      Build target, Some output_dir
    | [] -> print_usage ()
    | _ -> print_usage ()
  in
  { profile = !profile
  ; workspace_root = !workspace_root
  ; cargo_args = !cargo_args
  ; action
  ; output_dir
  }
;;
