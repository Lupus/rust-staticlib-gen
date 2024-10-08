open OpamStateTypes

(* The name of the extension in the opam file that specifies the Rust crate
   dependencies *)
let crate_extension_name = "x-rust-stubs-crate"

(* Function to parse metadata from opam file *)
let parse_metadata (opamext : OpamParserTypes.FullPos.value_kind) (pkg : OpamPackage.t) =
  match opamext with
  | OpamParserTypes.FullPos.List elements ->
    (match elements.pelem with
     (* If the extension is a list with crate and registry, return a crate_dependency object *)
     | [ { pelem = String crate; _ }; { pelem = String registry; _ } ] ->
       Some
         { Crate_dependency.name = crate
         ; version = Some (OpamPackage.version_to_string pkg)
         ; path = None
         ; registry = Some registry
         ; dependency_source = Opam_package (OpamPackage.to_string pkg)
         }
     (* If the extension is not correctly formatted, exit with an error *)
     | _ ->
       OpamConsole.error_and_exit
         `Internal_error
         "List extension in package is not correctly formatted. Expected format: [ \
          String crate; String registry ]")
  (* If the extension is a string, return a crate_dependency object with no registry *)
  | OpamParserTypes.FullPos.String crate ->
    Some
      { Crate_dependency.name = crate
      ; version = Some (OpamPackage.version_to_string pkg)
      ; path = None
      ; registry = None
      ; dependency_source = Opam_package (OpamPackage.to_string pkg)
      }
  (* If the extension is not a string or a list, exit with an error *)
  | _ ->
    OpamConsole.error_and_exit `Internal_error "Extension is not a string value or a list"
;;

(* Function to get the crate extension from the opam file *)
let get_crate_ext (opam : OpamFile.OPAM.t) (pkg : OpamPackage.t) =
  match
    OpamStd.String.Map.find_opt crate_extension_name (OpamFile.OPAM.extensions opam)
  with
  | Some { OpamParserTypes.FullPos.pelem; _ } -> parse_metadata pelem pkg
  | None -> None
;;

(* Function to get the crates from the opam file *)
let get_crates (st : [< unlocked > `Lock_write ] switch_state) (opam : OpamFile.OPAM.t) =
  let opam = OpamFormatUpgrade.opam_file opam in
  let nv = OpamFile.OPAM.package opam in
  let st = { st with opams = OpamPackage.Map.add nv opam st.opams } in
  (* Get the dependencies of the package *)
  let depends =
    OpamSwitchState.dependencies
      ~depopts:true
      ~build:true
      ~post:true
      ~installed:true
      st
      (OpamPackage.Set.singleton nv)
    |> OpamPackage.Set.to_list_map (fun x -> x)
    |> List.filter (fun nv1 -> nv1 <> nv)
  in
  (* Filter the dependencies to get the crate dependencies *)
  List.filter_map
    (fun pkg ->
      let opam = OpamSwitchState.opam st pkg in
      get_crate_ext opam pkg)
    depends
;;
