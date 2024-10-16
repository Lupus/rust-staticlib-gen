val parse_line : string -> Yojson.Safe.t option
val is_compiler_artifact : Yojson.Safe.t -> bool
val is_diagnostic_message : Yojson.Safe.t -> bool
val get_compiler_message : Yojson.Safe.t -> string
val get_target_name : Yojson.Safe.t -> string
val get_manifest_path : Yojson.Safe.t -> string
val get_filenames : Yojson.Safe.t -> string list
val get_executable : Yojson.Safe.t -> string option
