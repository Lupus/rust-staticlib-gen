open Yojson.Safe
open Yojson.Safe.Util

let parse_line line =
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

let get_compiler_message json = json |> member "message" |> member "message" |> to_string

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
