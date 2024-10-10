val crate_extension_name : string
val get_crate_ext : OpamFile.OPAM.t -> OpamPackage.t -> Crate_dependency.t option

val get_crates
  :  [< OpamStateTypes.unlocked > `Lock_write ] OpamStateTypes.switch_state
  -> OpamFile.OPAM.t
  -> Crate_dependency.t list
