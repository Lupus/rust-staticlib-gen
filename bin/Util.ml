let simplify_whitespace s =
  String.fold_left
    (fun (last_was_space, acc) c ->
      if c = ' '
      then if last_was_space then true, acc else true, acc ^ " "
      else false, acc ^ String.make 1 c)
    (false, "")
    s
  |> snd
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

let temporarily_change_directory ~f new_dir =
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
