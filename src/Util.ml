let escape_sexp_content content =
  let buf = Buffer.create (String.length content) in
  String.iter
    (function
      | '\n' -> Buffer.add_string buf "\\n"
      | '"' -> Buffer.add_string buf "\\\""
      | c -> Buffer.add_char buf c)
    content;
  Buffer.contents buf
;;

let generate_dune_write_file_rule filename content =
  let escaped_content = escape_sexp_content content in
  Printf.sprintf
    {|
; Create %s file in this folder within source directory
(subdir
  generated ; do the actual generation in `generated` subdir
            ; this helps to hide generated files from cargo
            ; as cargo looks for workspace by scanning the
            ; directory tree upwards from current dir
  (rule
    (alias populate-rust-staticlib)
    (targets %s)
    (mode
      (promote 
        (into ..))) ; promote back to current dir
    (action
      (write-file ; file contents
        %s
        "%s"))))
|}
    filename
    filename
    filename
    escaped_content
;;

let generate_dune_write_file_rule_simple filename content =
  let escaped_content = escape_sexp_content content in
  Printf.sprintf
    {|
; Create %s file in this folder within build directory only
(rule
  (targets %s)
  (action
    (write-file ; file contents
      %s
      "%s")))
|}
    filename
    filename
    filename
    escaped_content
;;

let write_content filename content =
  let path = OpamFilename.of_string filename in
  OpamFilename.write path content
;;

(* Function to replace '-' with '_' in crate name *)
let rustify_crate_name crate_name =
  String.map (fun c -> if c = '-' then '_' else c) crate_name
;;
