type dependency_source =
  | Commandline
  | Opam_package of string

val string_of_dependency_source : dependency_source -> string

type t =
  { name : string
  ; version : string option
  ; path : string option
  ; registry : string option
  ; dependency_source : dependency_source
  }
