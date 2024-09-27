open Unix
open Yojson.Safe
open Yojson.Safe.Util

let run_cargo_build crate_name =
  let command =
    Printf.sprintf
      "cargo build --release --offline --package %s --message-format json"
      crate_name
  in
  Printf.printf "Running cargo build command: %s\n%!" command;
  let input = open_process_in command in
  let rec read_lines acc =
    try
      let line = input_line input in
      read_lines (line :: acc)
    with
    | End_of_file -> List.rev acc
    | e -> failwith ("Error reading cargo output: " ^ Printexc.to_string e)
  in
  let lines = read_lines [] in
  match close_process_in input with
  | WEXITED 0 -> lines
  | WEXITED code -> failwith ("Cargo build failed with exit code " ^ string_of_int code)
  | WSIGNALED signal -> failwith ("Cargo build killed by signal " ^ string_of_int signal)
  | WSTOPPED signal -> failwith ("Cargo build stopped by signal " ^ string_of_int signal)
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

let get_target_name json =
  try json |> member "target" |> member "name" |> to_string with
  | _ -> failwith "Error: Could not get target name from JSON"
;;

let get_filenames json =
  try json |> member "filenames" |> to_list |> List.map to_string with
  | _ -> failwith "Error: Could not get filenames from JSON"
;;

let copy_file src dst =
  let buf_size = 8192 in
  let buf = Bytes.create buf_size in
  (* Error handling for file open *)
  let fd_in =
    try openfile src [ O_RDONLY ] 0 with
    | Unix_error (err, _, _) ->
      failwith ("Error opening source file: " ^ error_message err)
  in
  let fd_out =
    try openfile dst [ O_WRONLY; O_CREAT; O_TRUNC ] 0o644 with
    | Unix_error (err, _, _) ->
      close fd_in;
      failwith ("Error opening destination file: " ^ error_message err)
  in
  let rec copy_loop () =
    match read fd_in buf 0 buf_size with
    | 0 -> ()
    | n ->
      if write fd_out buf 0 n <> n then failwith "Error writing to destination file";
      copy_loop ()
  in
  try
    copy_loop ();
    close fd_in;
    close fd_out
  with
  | Unix_error (err, _, _) ->
    close fd_in;
    close fd_out;
    failwith ("Error copying file: " ^ error_message err)
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

let process_cargo_output crate_name output_dir =
  let workspace_root = Workspace_root.get () in
  let lines =
    temporarily_change_directory workspace_root.dir (fun () -> run_cargo_build crate_name)
  in
  List.iter
    (fun line ->
      let crate_name = rustify_crate_name crate_name in
      match parse_json_line line with
      | Some json when is_compiler_artifact json && get_target_name json = crate_name ->
        let filenames = get_filenames json in
        List.iter
          (fun src ->
            if Filename.check_suffix src (Printf.sprintf "lib%s.a" crate_name)
            then (
              let dst = Filename.concat output_dir (Filename.basename src) in
              copy_file src dst;
              Printf.printf "Copied %s to %s\n" src dst)
            else if Filename.check_suffix src (Printf.sprintf "lib%s.so" crate_name)
            then (
              let dst =
                Filename.concat output_dir (Printf.sprintf "dll%s.so" crate_name)
              in
              copy_file src dst;
              Printf.printf "Copied %s to %s\n" src dst))
          (List.filter
             (fun src ->
               Filename.check_suffix src (Printf.sprintf "lib%s.a" crate_name)
               || Filename.check_suffix src (Printf.sprintf "lib%s.so" crate_name))
             filenames)
      | _ -> ())
    lines
;;

let () =
  if Array.length Sys.argv < 2
  then Printf.eprintf "Usage: %s <crate_name> [output_dir]\n" Sys.argv.(0)
  else (
    let crate_name = Sys.argv.(1) in
    let output_dir =
      if Array.length Sys.argv >= 3
      then Sys.argv.(2)
      else Sys.getcwd () (* Use current directory as default *)
    in
    if not (Sys.file_exists output_dir && Sys.is_directory output_dir)
    then failwith "Error: Output directory does not exist or is not a directory"
    else process_cargo_output crate_name output_dir)
;;
