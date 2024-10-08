type dependency_source =
  | Commandline
  | Opam_package of string

let string_of_dependency_source = function
  | Commandline -> "command-line arguments"
  | Opam_package name -> Printf.sprintf "opam package `%s'" name
;;

(* Defining the type for crate dependency *)
type t =
  { name : string
  ; version : string option
  ; path : string option
  ; registry : string option
  ; dependency_source : dependency_source
  }
