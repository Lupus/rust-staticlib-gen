(* Function to read the output of a Unix process *)
let read_output ic =
  let rec aux acc =
    match input_line ic with
    | line -> aux (acc ^ line ^ "\n") (* Append each line to the accumulator *)
    | exception End_of_file ->
      acc (* Return the accumulator when reaching the end of file *)
  in
  aux ""
;;

let capture_cmd cmd =
  (* Open a process to run the cargo metadata command *)
  let ic = Unix.open_process_in cmd in
  (* Read the output from the process *)
  let output = read_output ic in
  (* Close the process *)
  ignore (Unix.close_process_in ic);
  output
;;

let run_cmd command =
  match Unix.system command with
  | Unix.WEXITED 0 -> () (* Command succeeded *)
  | _ ->
    (* Command failed *)
    OpamConsole.error_and_exit
      `Bad_arguments
      "Command `%s` failed to execute successfully"
      command
;;

let format_timestamp tm =
  let year = 1900 + tm.Unix.tm_year in
  let month = tm.tm_mon + 1 in
  let day = tm.tm_mday in
  let hour = tm.tm_hour in
  let minute = tm.tm_min in
  let second = tm.tm_sec in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ" year month day hour minute second
;;

let current_utc_timestamp () =
  let time = Unix.gmtime (Unix.time ()) in
  format_timestamp time
;;
