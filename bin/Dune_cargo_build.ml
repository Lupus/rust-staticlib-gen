let cargo_offline_flag () =
  match Connectivity.check_cargo_connectivity () with
  | true ->
    print_endline "Test connection to crates.io worked, assuming online mode for cargo";
    ""
  | false ->
    print_endline "[WARN] unable to connect to crates.io, assuming offline mode for cargo";
    "--offline"
;;

let cargo_read_lines input =
  let rec aux acc =
    let open Cargo_json in
    try
      let line = input_line input in
      let acc =
        match parse_line line with
        | Some json when is_diagnostic_message json ->
          Printf.fprintf stderr "Compiler message: %s\n%!" (get_compiler_message json);
          line :: acc
        | _ -> line :: acc
      in
      aux acc
    with
    | End_of_file -> List.rev acc
    | e ->
      Printf.fprintf stderr "Error reading cargo output: %s\n%!" (Printexc.to_string e);
      exit 1
  in
  aux []
;;

let run_cargo_build cmdline =
  let profile_flag = if cmdline.Cmdline.profile = "dev" then "" else "--release" in
  let offline_flag = cargo_offline_flag () in
  let cargo_args_str = String.concat " " (List.rev cmdline.cargo_args) in
  let target_flag =
    match cmdline.target with
    | Cmdline.Crate_name crate_name -> Printf.sprintf "--package %s" crate_name
    | Cmdline.Manifest_path manifest_path ->
      Printf.sprintf "--manifest-path %s" manifest_path
  in
  let command =
    Printf.sprintf
      "cargo build %s %s %s --message-format json %s"
      profile_flag
      offline_flag
      target_flag
      cargo_args_str
  in
  let command = Util.simplify_whitespace command in
  Printf.printf "Running cargo build command: %s\n%!" command;
  let input = Unix.open_process_in command in
  let lines = cargo_read_lines input in
  match Unix.close_process_in input with
  | WEXITED 0 -> lines
  | WEXITED code -> failwith ("Cargo build failed with exit code " ^ string_of_int code)
  | WSIGNALED signal -> failwith ("Cargo build killed by signal " ^ string_of_int signal)
  | WSTOPPED signal -> failwith ("Cargo build stopped by signal " ^ string_of_int signal)
;;

(* Function to replace '-' with '_' in crate name *)
let rustify_crate_name crate_name =
  String.map (fun c -> if c = '-' then '_' else c) crate_name
;;

let process_cargo_output cmdline output_dir =
  let in_source_workspace_root = Workspace_root.get () in
  let cd_to =
    match cmdline.Cmdline.workspace_root with
    | Some root ->
      let relative_path = Util.reconstruct_relative_path root in
      Filename.concat in_source_workspace_root.dir relative_path
    | None ->
      (match cmdline.target with
       | Cmdline.Crate_name _ -> ()
       | Cmdline.Manifest_path _ ->
         failwith "Error: please provide -workspace-root when building by manifest path");
      in_source_workspace_root.dir
  in
  let lines =
    Util.temporarily_change_directory cd_to ~f:(fun () -> run_cargo_build cmdline)
  in
  List.iter
    (fun line ->
      let open Cargo_json in
      let filter =
        match cmdline.target with
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
      match parse_line line with
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
                Util.copy_file src dst;
                Printf.printf "Copied %s to %s\n" src dst)
              else if Filename.check_suffix base ".so"
              then (
                (* Rename .so files from lib<name>.so to dll<name>.so *)
                let name_no_ext = Filename.chop_extension rest in
                let dst = Filename.concat output_dir ("dll" ^ name_no_ext ^ ".so") in
                Util.copy_file src dst;
                Printf.printf "Copied %s to %s\n" src dst)))
          filenames;
        let executable = get_executable json in
        (match executable with
         | Some path ->
           let dst = Filename.concat output_dir (Filename.basename path) in
           Util.copy_file path dst;
           Util.set_executable_mode dst;
           Printf.printf "Copied %s to %s\n" path dst
         | None -> ())
      | _ -> ())
    lines
;;

let main () =
  let cmdline = Cmdline.parse () in
  let output_dir =
    match cmdline.output_dir with
    | Some dir -> dir
    | None -> Sys.getcwd ()
  in
  process_cargo_output cmdline output_dir
;;

let () = main ()
