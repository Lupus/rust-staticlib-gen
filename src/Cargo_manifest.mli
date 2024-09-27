type cargo_info =
  { name : string
  ; version : string
  }

val get_cargo_info : string -> cargo_info
