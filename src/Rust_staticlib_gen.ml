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

let main params =
  Random.self_init ();
  OpamClientConfig.opam_init ();
  OpamClientConfig.init ();
  generate_command params
;;

let cmd =
  let doc = "Generate Rust static libraries from opam files" in
  let info = Cmd.info "rust_staticlib_gen" ~doc in
  Cmd.v info Term.(const main $ Cmdline.params_t)
;;

let () = exit (Cmd.eval cmd)
