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
  (* Open a process to run the command *)
  let ic = Unix.open_process_in cmd in
  (* Read the output from the process *)
  let output = read_output ic in
  (* Close the process *)
  ignore (Unix.close_process_in ic);
  output
;;
