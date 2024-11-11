module String_map = Map.Make (String)

let load () =
  let ic = Unix.open_process_in "ocamlc -config" in
  let rec read_lines map =
    try
      let line = input_line ic in
      match String.index_opt line ':' with
      | Some idx ->
        let key = String.trim (String.sub line 0 idx) in
        let value =
          String.trim (String.sub line (idx + 1) (String.length line - idx - 1))
        in
        read_lines (String_map.add key value map)
      | None -> read_lines map
    with
    | End_of_file -> map
  in
  let config_map = read_lines String_map.empty in
  let _ = Unix.close_process_in ic in
  config_map
;;

let config = lazy (load ())

let get key =
  let cfg = Lazy.force config in
  match String_map.find_opt key cfg with
  | Some value -> value
  | None ->
    failwith (Printf.sprintf "key `%s` was not found in `ocamlc -config` output" key)
;;
