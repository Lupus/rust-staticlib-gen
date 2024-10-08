open Cmdliner

type params =
  { opam_file : string
  ; output_filename : string
  ; local_crate_path : string option
  ; extra_crate_paths : string list
  }

let output_filename =
  let doc = "Output filename for the generated dune file" in
  Arg.(value & opt string "dune.inc.gen" & info [ "o"; "output" ] ~docv:"OUTPUT" ~doc)
;;

let local_crate_path =
  let doc =
    "Path (relative) to local crate which contains stubs for specified opam file"
  in
  Arg.(
    value
    & opt (some string) None
    & info [ "l"; "local-crate-path" ] ~docv:"LOCAL_CRATE_PATH" ~doc)
;;

let opam_file =
  let doc = "Opam file to process" in
  Arg.(required & pos 0 (some file) None & info [] ~docv:"OPAM_FILE" ~doc)
;;

let extra_crate_paths =
  let doc = "Additional paths (relative) to extra crates to be included in Cargo.toml" in
  Arg.(
    value
    & opt_all string []
    & info [ "e"; "extra-crate-path" ] ~docv:"EXTRA_CRATE_PATH" ~doc)
;;

let params_t =
  let make_params opam_file output_filename local_crate_path extra_crate_paths =
    { opam_file; output_filename; local_crate_path; extra_crate_paths }
  in
  Term.(
    const make_params $ opam_file $ output_filename $ local_crate_path $ extra_crate_paths)
;;
