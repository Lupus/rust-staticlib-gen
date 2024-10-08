val gen_staticlib
  :  [< OpamStateTypes.unlocked > `Lock_write ] OpamStateTypes.switch_state
  -> Cmdline.params
  -> 'a OpamFile.t
  -> OpamFile.OPAM.t
  -> unit
