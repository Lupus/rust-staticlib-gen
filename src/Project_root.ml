open Sexplib0

let parse_dune_describe_output output =
  match output with
  | Sexp.List (Sexp.List (Sexp.Atom "root" :: Sexp.Atom path :: _) :: _) -> path
  | _ ->
    OpamConsole.error_and_exit
      `Internal_error
      "Dune describe output is not correctly formatted. Expected format to contain (root \
       <path>)."
;;

let extract_project_root () =
  let output = Util.capture_cmd "opam exec -- dune describe" in
  let sexp = Parsexp.Single.parse_string_exn output in
  parse_dune_describe_output sexp
;;
