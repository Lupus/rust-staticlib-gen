open Yojson.Safe
open Yojson.Safe.Util

let profile = ref "release"
let workspace_root = ref None
let args = ref []
let cargo_args = ref []

type build_target =
  | Crate_name of string
  | Manifest_path of string

let speclist =
  [ "-profile", Arg.Set_string profile, "Build profile: release (default) or dev"
  ; ( "-workspace-root"
    , Arg.String (fun root -> workspace_root := Some root)
    , "Workspace root (in dune rules: -workspace-root %{workspace_root})" )
  ; ( "--"
    , Arg.Rest (fun arg -> cargo_args := arg :: !cargo_args)
    , "Pass the remaining arguments to cargo" )
  ]
;;

let parse_json_line line =
  try Some (from_string line) with
  | Yojson.Json_error msg -> failwith ("Error parsing JSON: " ^ msg)
  | _ -> None
;;

let is_compiler_artifact json =
  match json |> member "reason" |> to_string_option with
  | Some "compiler-artifact" -> true
  | _ -> false
;;

let is_diagnostic_message json =
  match json |> member "reason" |> to_string_option with
  | Some "compiler-message" -> true
  | _ -> false
;;

let run_cargo_build target =
  let cargo_profile_flag = if !profile = "dev" then "" else "--release" in
  let cargo_args_str = String.concat " " (List.rev !cargo_args) in
  let command =
    match target with
    | Crate_name crate_name ->
      Printf.sprintf
        "cargo build %s --offline --package %s --message-format json %s"
        cargo_profile_flag
        crate_name
        cargo_args_str
    | Manifest_path manifest_path ->
      Printf.sprintf
        "cargo build %s --offline --manifest-path %s --message-format json %s"
        cargo_profile_flag
        manifest_path
        cargo_args_str
  in
  Printf.printf "Running cargo build command: %s\n%!" command;
  let input = Unix.open_process_in command in
  let rec read_lines acc =
    try
      let line = input_line input in
      let acc =
        match parse_json_line line with
        | Some json when is_diagnostic_message json ->
          Printf.fprintf
            stderr
            "Compiler message: %s\n%!"
            (json |> member "message" |> member "message" |> to_string);
          line :: acc
        | _ -> line :: acc
      in
      read_lines acc
    with
    | End_of_file -> List.rev acc
    | e ->
      Printf.fprintf stderr "Error reading cargo output: %s\n%!" (Printexc.to_string e);
      exit 1
  in
  let lines = read_lines [] in
  match Unix.close_process_in input with
  | WEXITED 0 -> lines
  | WEXITED code -> failwith ("Cargo build failed with exit code " ^ string_of_int code)
  | WSIGNALED signal -> failwith ("Cargo build killed by signal " ^ string_of_int signal)
  | WSTOPPED signal -> failwith ("Cargo build stopped by signal " ^ string_of_int signal)
;;

let get_target_name json =
  try json |> member "target" |> member "name" |> to_string with
  | _ -> failwith "Error: Could not get target name from JSON"
;;

let get_manifest_path json =
  try json |> member "manifest_path" |> to_string with
  | _ -> failwith "Error: Could not get manifest path from JSON"
;;

let get_filenames json =
  try json |> member "filenames" |> to_list |> List.map to_string with
  | _ -> failwith "Error: Could not get filenames from JSON"
;;

let get_executable json =
  try json |> member "executable" |> to_string_option with
  | x ->
    Printexc.to_string x |> print_endline;
    None
;;

let copy_file src dst =
  let buf_size = 8192 in
  let buf = Bytes.create buf_size in
  (* Error handling for file open *)
  let fd_in =
    try Unix.openfile src [ O_RDONLY ] 0 with
    | Unix.Unix_error (err, _, _) ->
      failwith ("Error opening source file: " ^ Unix.error_message err)
  in
  let fd_out =
    try Unix.openfile dst [ O_WRONLY; O_CREAT; O_TRUNC ] 0o644 with
    | Unix.Unix_error (err, _, _) ->
      Unix.close fd_in;
      failwith ("Error opening destination file: " ^ Unix.error_message err)
  in
  let rec copy_loop () =
    match Unix.read fd_in buf 0 buf_size with
    | 0 -> ()
    | n ->
      if Unix.write fd_out buf 0 n <> n then failwith "Error writing to destination file";
      copy_loop ()
  in
  try
    copy_loop ();
    Unix.close fd_in;
    Unix.close fd_out
  with
  | Unix.Unix_error (err, _, _) ->
    Unix.close fd_in;
    Unix.close fd_out;
    failwith ("Error copying file: " ^ Unix.error_message err)
;;

(* Function to replace '-' with '_' in crate name *)
let rustify_crate_name crate_name =
  String.map (fun c -> if c = '-' then '_' else c) crate_name
;;

let temporarily_change_directory new_dir f =
  let original_dir = Sys.getcwd () in
  try
    Printf.printf "Temporarily changing current dir to %s\n" new_dir;
    Sys.chdir new_dir;
    let result = f () in
    Sys.chdir original_dir;
    Printf.printf "Returning back to %s\n" original_dir;
    result
  with
  | e ->
    Printf.printf "Returning back to %s\n" original_dir;
    Sys.chdir original_dir;
    raise e
;;

let set_executable_mode filename =
  let current_perms = (Unix.stat filename).st_perm in
  let executable_perms = current_perms lor 0o111 in
  Unix.chmod filename executable_perms
;;

let reconstruct_relative_path workspace_root =
  let split_path path = String.split_on_char Filename.dir_sep.[0] path in
  let current_dir = Sys.getcwd () in
  let root_path = Filename.concat current_dir workspace_root in
  let normalized_root = split_path (Unix.realpath root_path) in
  let normalized_current = split_path (Unix.realpath current_dir) in
  let rec find_common_prefix l1 l2 =
    match l1, l2 with
    | x :: xs, y :: ys when x = y -> find_common_prefix xs ys
    | _ -> l2
  in
  let relative_path = find_common_prefix normalized_root normalized_current in
  String.concat Filename.dir_sep relative_path
;;

let process_cargo_output target output_dir =
  let in_source_workspace_root = Workspace_root.get () in
  let cd_to =
    match !workspace_root with
    | Some root ->
      let relative_path = reconstruct_relative_path root in
      Filename.concat in_source_workspace_root.dir relative_path
    | None ->
      (match target with
       | Crate_name _ -> ()
       | Manifest_path _ ->
         failwith "Error: please provide -workspace-root when building by manifest path");
      in_source_workspace_root.dir
  in
  let lines = temporarily_change_directory cd_to (fun () -> run_cargo_build target) in
  List.iter
    (fun line ->
      let filter =
        match target with
        | Crate_name name ->
          let orig_crate_name = name in
          let crate_name = rustify_crate_name name in
          fun json ->
            let target = get_target_name json in
            target = crate_name || target = orig_crate_name
        | Manifest_path path ->
          let full_path = Unix.realpath (Filename.concat cd_to path) in
          fun json ->
            let path = get_manifest_path json in
            path = full_path
      in
      match parse_json_line line with
      | Some json when is_compiler_artifact json && filter json ->
        let filenames = get_filenames json in
        List.iter
          (fun src ->
            let base = Filename.basename src in
            if String.length base >= 3 && String.sub base 0 3 = "lib"
            then (
              let rest = String.sub base 3 (String.length base - 3) in
              if Filename.check_suffix base ".a"
              then (
                (* Copy .a files without renaming *)
                let dst = Filename.concat output_dir base in
                copy_file src dst;
                Printf.printf "Copied %s to %s\n" src dst)
              else if Filename.check_suffix base ".so"
              then (
                (* Rename .so files from lib<name>.so to dll<name>.so *)
                let name_no_ext = Filename.chop_extension rest in
                let dst = Filename.concat output_dir ("dll" ^ name_no_ext ^ ".so") in
                copy_file src dst;
                Printf.printf "Copied %s to %s\n" src dst)))
          filenames;
        let executable = get_executable json in
        (match executable with
         | Some path ->
           let dst = Filename.concat output_dir (Filename.basename path) in
           copy_file path dst;
           set_executable_mode dst;
           Printf.printf "Copied %s to %s\n" path dst
         | None -> ())
      | _ -> ())
    lines
;;

let usage_msg = "Usage: dune_cargo_build <crate_name|manifest_path> [output_dir]"
let anon_fun arg = args := arg :: !args

let () =
  Arg.parse speclist anon_fun usage_msg;
  let args = List.rev !args in
  match args with
  | [ arg ] ->
    let target =
      if Filename.check_suffix arg "Cargo.toml" then Manifest_path arg else Crate_name arg
    in
    process_cargo_output target (Sys.getcwd ())
  | [ arg; output_dir ] ->
    let target =
      if Filename.check_suffix arg "Cargo.toml" then Manifest_path arg else Crate_name arg
    in
    if not (Sys.file_exists output_dir && Sys.is_directory output_dir)
    then failwith "Error: Output directory does not exist or is not a directory";
    process_cargo_output target output_dir
  | _ -> Printf.eprintf "Usage: %s <crate_name|manifest_path> [output_dir]\n" Sys.argv.(0)
;;
