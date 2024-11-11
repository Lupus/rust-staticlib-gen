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

(* Commands that support the --offline flag *)
let allowed_offline_commands =
  [ "build" (* https://doc.rust-lang.org/cargo/commands/cargo-build.html *)
  ; "check" (* https://doc.rust-lang.org/cargo/commands/cargo-check.html *)
  ; "run" (* https://doc.rust-lang.org/cargo/commands/cargo-run.html *)
  ; "test" (* https://doc.rust-lang.org/cargo/commands/cargo-test.html *)
  ; "bench" (* https://doc.rust-lang.org/cargo/commands/cargo-bench.html *)
  ; "doc" (* https://doc.rust-lang.org/cargo/commands/cargo-doc.html *)
  ; "generate-lockfile"
    (* https://doc.rust-lang.org/cargo/commands/cargo-generate-lockfile.html
       - With --offline, it can only generate a lockfile based on locally
         available information *)
  ; "install" (* https://doc.rust-lang.org/cargo/commands/cargo-install.html *)
  ; "uninstall"
    (* https://doc.rust-lang.org/cargo/commands/cargo-uninstall.html
       - --offline flag is valid but typically not necessary for this
         operation *)
  ; "clean"
    (* https://doc.rust-lang.org/cargo/commands/cargo-clean.html
       - --offline flag is valid but typically not necessary for this
         operation *)
  ; "fetch"
    (* https://doc.rust-lang.org/cargo/commands/cargo-fetch.html
       - While it supports --offline, it primarily downloads dependencies,
         so using it with --offline limits functionality *)
  ; "update"
    (* https://doc.rust-lang.org/cargo/commands/cargo-update.html
       - With --offline, it can only update based on locally cached
         information *)
  ]
;;

(* Commands that support the --release flag *)
let allowed_release_commands =
  [ "build" (* https://doc.rust-lang.org/cargo/commands/cargo-build.html *)
  ; "run" (* https://doc.rust-lang.org/cargo/commands/cargo-run.html *)
  ; "test" (* https://doc.rust-lang.org/cargo/commands/cargo-test.html *)
  ; "doc" (* https://doc.rust-lang.org/cargo/commands/cargo-doc.html *)
  ; "install"
    (* https://doc.rust-lang.org/cargo/commands/cargo-install.html
       - Uses release profile by default, so --release is usually redundant *)
  ]
;;

let build_flags cmdline command =
  let profile_flag =
    if List.mem command allowed_release_commands
    then if cmdline.Cmdline.profile = "dev" then "" else "--release"
    else ""
  in
  let offline_flag =
    if List.mem command allowed_offline_commands then cargo_offline_flag () else ""
  in
  let cargo_args_str = String.concat " " (List.rev cmdline.cargo_args) in
  profile_flag, offline_flag, cargo_args_str
;;

let run_cargo_build cmdline target =
  let profile_flag, offline_flag, cargo_args_str = build_flags cmdline "build" in
  let target_flag =
    match target with
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

let run_cargo_command cmdline cmd =
  let profile_flag, offline_flag, cargo_args_str = build_flags cmdline cmd in
  let command =
    Printf.sprintf "cargo %s %s %s %s" cmd profile_flag offline_flag cargo_args_str
  in
  let command = Util.simplify_whitespace command in
  let in_source_workspace_root = Workspace_root.get () in
  Printf.printf
    "Changing dir to in-source workspace root: %s\n%!"
    in_source_workspace_root.dir;
  Sys.chdir in_source_workspace_root.dir;
  Printf.printf "Running cargo command: %s\n%!" command;
  Unix.execvp "cargo" (Array.of_list (String.split_on_char ' ' command))
;;

(* Function to replace '-' with '_' in crate name *)
let rustify_crate_name crate_name =
  String.map (fun c -> if c = '-' then '_' else c) crate_name
;;

let check_suffixes ~suffixes name =
  suffixes |> List.fold_left (fun acc x -> acc || Filename.check_suffix name x) false
;;

(*
   OCaml expects .so suffix even on macos:

   ```
   Run opam exec -- ocamlc -config
   version: 4.14.1
   architecture: arm64
   system: macosx
   ext_exe:
   ext_obj: .o
   ext_asm: .s
   ext_lib: .a
   ext_dll: .so
   os_type: Unix
   ```

   While cargo produces .dylib on macos, so we match whatever suffixes are expected
   on any platform, and rename them to whatever OCaml expects for this specific
   platform later.
*)
let classify src =
  let base = Filename.basename src in
  if String.length base >= 3 && String.sub base 0 3 = "lib"
  then
    if check_suffixes ~suffixes:[ ".a" ] base
    then (
      (* Copy static lib without renaming *)
      let name_no_ext = Filename.chop_extension base in
      Some (`Static name_no_ext))
    else if check_suffixes ~suffixes:[ ".dylib"; ".so"; ".dll" ] base
    then (
      (* Rename dynamic lib files from lib<name>.XXX to dll<name>.XXX *)
      let rest = String.sub base 3 (String.length base - 3) in
      let name_no_ext = Filename.chop_extension rest in
      Some (`Dynamic ("dll" ^ name_no_ext)))
    else None
  else None
;;

let process_cargo_output cmdline target output_dir =
  let in_source_workspace_root = Workspace_root.get () in
  let cd_to =
    match cmdline.Cmdline.workspace_root with
    | Some root ->
      let relative_path = Util.reconstruct_relative_path root in
      Filename.concat in_source_workspace_root.dir relative_path
    | None ->
      (match target with
       | Cmdline.Crate_name _ -> ()
       | Cmdline.Manifest_path _ ->
         failwith "Error: please provide -workspace-root when building by manifest path");
      in_source_workspace_root.dir
  in
  let lines =
    Util.temporarily_change_directory cd_to ~f:(fun () -> run_cargo_build cmdline target)
  in
  let buffer = Buffer.create 256 in
  let pf fmt = Printf.bprintf buffer ("[process_cargo_output] " ^^ fmt ^^ "\n") in
  let filter =
    let open Cargo_json in
    match target with
    | Cmdline.Crate_name name ->
      let orig_crate_name = name in
      let crate_name = rustify_crate_name name in
      fun json ->
        let target = get_target_name json in
        let decision = target = crate_name || target = orig_crate_name in
        pf
          "Crate_name filter: crate_name='%s', orig_crate_name='%s', target='%s', \
           (target = crate_name || target = orig_crate_name) = %b"
          crate_name
          orig_crate_name
          target
          decision;
        decision
    | Manifest_path path ->
      let manifest_path = Unix.realpath (Filename.concat cd_to path) in
      fun json ->
        let test_path = get_manifest_path json in
        let decision = test_path = manifest_path in
        pf
          "Manifest_path filter: test_path='%s', manifest_path='%s', (test_path = \
           manifest_path) = %b"
          test_path
          manifest_path
          decision;
        decision
  in
  let is_compiler_artifact json =
    let decision = Cargo_json.is_compiler_artifact json in
    pf "Cargo_json.is_compiler_artifact = %b" decision;
    decision
  in
  let count = ref 0 in
  List.iter
    (fun line ->
      pf "CARGO JSON LINE: %s" line;
      match Cargo_json.parse_line line with
      | Some json when is_compiler_artifact json && filter json ->
        let filenames = Cargo_json.get_filenames json in
        pf "Filenames: %s" (String.concat ", " filenames);
        let ext_lib = Ocamlc_config.get "ext_lib" in
        let ext_dll = Ocamlc_config.get "ext_dll" in
        List.iter
          (fun src ->
            let dst_name =
              classify src
              |> Option.map (fun src ->
                match src with
                | `Static name -> name ^ ext_lib
                | `Dynamic name -> name ^ ext_dll)
            in
            match dst_name with
            | Some name ->
              let dst = Filename.concat output_dir name in
              Util.copy_file src dst;
              incr count;
              pf "COPY %s => %s" src dst;
              Printf.printf "Copied %s to %s\n" src dst
            | None -> ())
          filenames;
        let executable = Cargo_json.get_executable json in
        pf "Executable: %s" (Option.value ~default:"(none)" executable);
        (match executable with
         | Some path ->
           let dst = Filename.concat output_dir (Filename.basename path) in
           Util.copy_file path dst;
           Util.set_executable_mode dst;
           incr count;
           pf "COPY %s => %s" path dst;
           Printf.printf "Copied %s to %s\n" path dst
         | None -> ())
      | _ -> ())
    lines;
  if !count = 0
  then (
    Printf.eprintf
      "%s\n\nNo artifacts were copied, debug output is above...%!\n"
      (Buffer.contents buffer);
    exit 1)
;;

let main () =
  let cmdline = Cmdline.parse () in
  let output_dir =
    match cmdline.output_dir with
    | Some dir -> dir
    | None -> Sys.getcwd ()
  in
  match cmdline.Cmdline.action with
  | Cmdline.Cargo_command cmd -> run_cargo_command cmdline cmd
  | Build target -> process_cargo_output cmdline target output_dir
;;

let () = main ()
