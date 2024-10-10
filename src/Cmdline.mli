type params = {
  opam_file : string;
  output_filename : string;
  local_crate_path : string option;
  extra_crate_paths : string list;
}

val params_t : params Cmdliner.Term.t
