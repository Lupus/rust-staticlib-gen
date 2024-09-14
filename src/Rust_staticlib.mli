val gen_staticlib
  :  [< OpamStateTypes.unlocked > `Lock_write ] OpamStateTypes.switch_state
  -> string option
  -> 'a OpamFile.t
  -> OpamFile.OPAM.t
  -> string
  -> unit
