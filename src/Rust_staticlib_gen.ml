open Cmdliner

let check_opam_file_errors f opam =
  let n_errors =
    OpamFileTools.lint opam
    |> List.fold_left
         (fun acc (num, kind, msg) ->
           match kind with
           | `Error ->
             OpamConsole.msg "%s: Error %d: %s\n" (OpamFile.to_string f) num msg;
             acc + 1
           | `Warning when num = 62 -> acc
           | `Warning ->
             OpamConsole.msg "%s: Warning %d: %s\n" (OpamFile.to_string f) num msg;
             acc)
         0
  in
  if n_errors > 0
  then OpamConsole.error_and_exit `File_error "Errors present in opam file, bailing out"
;;

let generate_command params =
  let file = OpamFilename.of_string params.Cmdline.opam_file in
  let nameopt, f =
    OpamPinned.name_of_opam_filename (OpamFilename.dirname file) file, OpamFile.make file
  in
  let opam = OpamFile.OPAM.read f in
  let opam =
    match nameopt with
    | None -> opam
    | Some n -> OpamFile.OPAM.with_name n opam
  in
  let opam =
    match OpamFile.OPAM.version_opt opam with
    | None -> OpamFile.OPAM.with_version (OpamPackage.Version.of_string "dev") opam
    | Some _version -> opam
  in
  check_opam_file_errors f opam;
  let gt = OpamGlobalState.load `Lock_none in
  OpamRepositoryState.with_ `Lock_none gt (fun _rt ->
    OpamSwitchState.with_ `Lock_none gt (fun st ->
      Rust_staticlib.gen_staticlib st params f opam))
;;

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

let main params =
  Random.self_init ();
  OpamSystem.init ();
  let root = OpamStateConfig.opamroot () in
  ignore (OpamStateConfig.load_defaults root);
  OpamFormatConfig.init ();
  OpamRepositoryConfig.init ();
  OpamSolverConfig.init ();
  OpamStateConfig.init ();
  generate_command params
;;

let cmd =
  let doc = "Generate Rust static libraries from opam files" in
  let info = Cmd.info "rust_staticlib_gen" ~doc in
  Cmd.v info Term.(const main $ Cmdline.params_t)
;;

let () = exit (Cmd.eval cmd)
