val simplify_whitespace : string -> string
val copy_file : string -> string -> unit
val set_executable_mode : string -> unit
val reconstruct_relative_path : string -> string
val temporarily_change_directory : f:(unit -> 'a) -> string -> 'a
