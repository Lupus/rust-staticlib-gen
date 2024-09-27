val gen_staticlib
  :  [< OpamStateTypes.unlocked > `Lock_write ] OpamStateTypes.switch_state
  -> string option
  -> string list
  -> 'a OpamFile.t
  -> OpamFile.OPAM.t
  -> string
  -> unit
