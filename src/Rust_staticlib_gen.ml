open OpamStateTypes

let read_file filename =
  let lines = ref [] in
  let chan = open_in filename in
  try
    while true do
      lines := input_line chan :: !lines
    done;
    !lines
  with
  | End_of_file ->
    close_in chan;
    List.rev !lines
;;

let flag_exists flag =
  let rec check_flag = function
    | [] -> false
    | x :: _ when x = flag -> true
    | _ :: xs -> check_flag xs
  in
  check_flag (Array.to_list Sys.argv)
;;

let lock_command files =
  let files =
    List.fold_left
      (fun acc f ->
        if Sys.is_directory f
        then (
          let d = OpamFilename.Dir.of_string f in
          let fs =
            OpamPinned.files_in_source d
            |> List.map (fun { pin_name; pin } -> pin_name, pin.pin_file, None)
          in
          if fs = []
          then
            OpamConsole.error_and_exit
              `Bad_arguments
              "No package definition files found at %s"
              (let open OpamFilename.Dir in
               to_string d);
          List.rev_append fs acc)
        else (
          let file = OpamFilename.of_string f in
          ( OpamPinned.name_of_opam_filename (OpamFilename.dirname file) file
          , OpamFile.make file
          , None )
          :: acc))
      []
      files
    |> List.rev
  in
  let opams =
    List.map
      (fun (nameopt, f, _) ->
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
        then
          OpamConsole.error_and_exit
            `File_error
            "Errors present in opam file, bailing out";
        f, opam)
      files
  in
  let gt = OpamGlobalState.load `Lock_none in
  OpamRepositoryState.with_ `Lock_none gt (fun _rt ->
    OpamSwitchState.with_ `Lock_none gt (fun st ->
      let cargo_metadata = lazy (Rust_staticlib.extract_cargo_metadata ()) in
      let project_root = Project_root.extract_project_root () in
      List.iter
        (fun (f, opam) ->
          Rust_staticlib.gen_staticlib st cargo_metadata project_root f opam)
        opams))
;;

let () =
  Random.self_init ();
  OpamSystem.init ();
  let root = OpamStateConfig.opamroot () in
  ignore (OpamStateConfig.load_defaults root);
  OpamFormatConfig.init ();
  OpamRepositoryConfig.init ();
  OpamSolverConfig.init ();
  OpamStateConfig.init ();
  lock_command [ "." ]
;;
