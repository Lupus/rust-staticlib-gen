open OpamStateTypes

let program_name = "rust-staticlib-gen"

(* The name of the extension in the opam file that specifies the Rust crate
   dependencies *)
let crate_extension_name = "x-rust-stubs-crate"

type dependency_source =
  | Commandline
  | Opam_package of string

let string_of_dependency_source = function
  | Commandline -> "command-line arguments"
  | Opam_package name -> Printf.sprintf "opam package `%s'" name
;;

(* Defining the type for crate dependency *)
type crate_dependency =
  { name : string
  ; version : string option
  ; path : string option
  ; registry : string option
  ; dependency_source : dependency_source
  }

(* Function to parse metadata from opam file *)
let parse_metadata opamext pkg =
  match opamext with
  | OpamParserTypes.FullPos.List elements ->
    (match elements.pelem with
     (* If the extension is a list with crate and registry, return a crate_dependency object *)
     | [ { pelem = String crate; _ }; { pelem = String registry; _ } ] ->
       Some
         { name = crate
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
      { name = crate
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
let get_crate_ext opam pkg =
  match
    OpamStd.String.Map.find_opt crate_extension_name (OpamFile.OPAM.extensions opam)
  with
  | Some { OpamParserTypes.FullPos.pelem; _ } -> parse_metadata pelem pkg
  | None -> None
;;

(* Function to get the crates from the opam file *)
let get_crates st opam =
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

(* Function to replace '-' with '_' in crate name *)
let rustify_crate_name crate_name =
  String.map (fun c -> if c = '-' then '_' else c) crate_name
;;

(* Function to generate content for dune file *)
let generate_dune_content crate_name dune_staticlib_name =
  let buffer = Buffer.create 256 in
  (* Shorter eta-expanded helper function with automatic newline *)
  let pf fmt = Printf.bprintf buffer (fmt ^^ "\n") in
  pf "";
  let lib_name = rustify_crate_name crate_name in
  pf
    {|
; This rule generates an S-expression file to be included into dune's rule
; `(deps)` section later. Inside this S-expression file will be full list of
; Rust-related dependencies in project source tree (Rust sources and Cargo
; manifests and lock file).
; Make sure to exclude `target` Rust output dir by using `dirs` stanza in
; project root like this:
;   (dirs :standard \ target)
; Otherwise dune's glob_files_rec would scan everything in `target` dir as well,
; possibly causing problems.
|};
  pf "(rule";
  pf " (target rust-deps.inc)";
  pf " (deps";
  pf "  (alias generated/populate-rust-staticlib)";
  pf "  (glob_files_rec %%{workspace_root}/*.rs)";
  pf "  (glob_files_rec %%{workspace_root}/Cargo.toml)";
  pf "  (glob_files_rec %%{workspace_root}/Cargo.lock))";
  pf " (action";
  pf "  (with-stdout-to %%{target}";
  pf "   (echo \"(%%{deps})\"))))";
  pf
    {|
; Below rule actually compiles Rust staticlib, using a wrapper tool which
; invokes cargo and copies the resulting artifacts into current directory.
; Cargo has a flag to do that on its own, but it's still unstable.
; see https://github.com/rust-lang/cargo/issues/6790
|};
  pf "(rule";
  pf " (targets lib%s.a dll%s.so)" lib_name lib_name;
  pf " (deps";
  pf "  (include rust-deps.inc) ; depend on all Rust bits in your project";
  pf "                          ; this allows not to run Cargo build each time,";
  pf "                          ; as it will stil do the static linking, which is slow";
  pf
    "  (alias generated/populate-rust-staticlib)) ; wait for crate generation to complete";
  pf " (locks cargo-build)";
  pf " (action";
  pf "  (run rust-staticlib-build %s)))" crate_name;
  pf
    {|
; This library is deliberately very lightweight from OCaml perspective. It's
; only purpose is to drag Rust stubs static lib into the final executable
; linkage by dune.  Bear in mind that two libs like this can not be linked into
; one binary, as static libs produced by Rust expose all Rust stdlib symbols,
; and linking will explode with collision errors.
;
; The `Rust_staticlib` module implements the interface of the virtual library
; `rust-staticlib`.  This virtual library exists to notify users that there are
; Rust dependencies that need Rust staticlib to be generated. Each Rust
; staticlib actually implements this dummy interface via this generated file.
; This allows to communicate Rust dependency requirements to the end user in a
; bit nicier way than via the linker errors.
;
|};
  pf "";
  pf "(library";
  pf " (name %s_stubs)" dune_staticlib_name;
  pf " (foreign_archives %s) ; link Rust bits into the final executable" lib_name;
  pf " (modules Rust_staticlib) ; generated virtual lib implementation";
  pf " (implements rust-staticlib) ; mark this lib as the one implementing rust-staticlib";
  pf " (c_library_flags";
  pf "  (-lpthread -lc -lm)))";
  Buffer.contents buffer
;;

(* Function to generate lib.rs content *)
let generate_lib_rs_content dependencies local_crate =
  let buffer = Buffer.create 256 in
  (* Shorter eta-expanded helper function with automatic newline *)
  let pf fmt = Printf.bprintf buffer (fmt ^^ "\n") in
  pf "/* Generated by %s */" program_name;
  pf "";
  let names = List.map (fun { name; _ } -> name) dependencies in
  let names =
    match local_crate with
    | None -> names
    | Some (name, _) -> name :: names
  in
  let sorted_names = List.sort String.compare names in
  List.iter (fun name -> pf "pub use %s;" (rustify_crate_name name)) sorted_names;
  Buffer.contents buffer
;;

(* Function to generate Cargo.toml content *)
let generate_cargo_toml_content crate_name dependencies local_crate opam_package_name =
  let buffer = Buffer.create 256 in
  (* Shorter eta-expanded helper function with automatic newline *)
  let pf fmt = Printf.bprintf buffer (fmt ^^ "\n") in
  pf "# Generated by %s for opam package: %s" program_name opam_package_name;
  pf
    {|
# This crate depends on all Rust crates, that were specified via
# `%s` metadata field in opam files in the dependencie tree of your
# project opam file.
#
# Dependencies are listed as exact version matches, and versions are taken
# verbatim from corresponding opam package versions. This is done this way to
# ensure 100%% compatibility between OCaml bindings and their Rust stubs crates.
# In case of any confclits at cargo level, they should be resolved at opam
# level, and this file needs to be re-generated.
|}
    crate_extension_name;
  pf "";
  pf "[package]";
  pf "name = \"%s\"" crate_name;
  pf "version = \"0.1.0\"";
  pf "edition = \"2021\"";
  pf "";
  pf "[lib]";
  pf "crate-type = [\"staticlib\", \"cdylib\", \"rlib\"]";
  pf "path = \"lib.rs\"";
  pf "";
  (match dependencies, local_crate with
   | [], None -> ()
   | _ ->
     pf "[dependencies]";
     (match local_crate with
      | None -> ()
      | Some (name, path) ->
        pf "# Declared by local opam package (%s)" opam_package_name;
        pf "%s = { path = \"%s\" }" name path);
     List.iter
       (fun { name; version; registry; path; dependency_source } ->
         pf "# Declared by: %s" (string_of_dependency_source dependency_source);
         match version, registry, path with
         | None, None, None ->
           failwith
             (Printf.sprintf
                "dependency `%s' does not specify both version and path"
                name)
         | ver, reg, path ->
           let ver = Option.map (( ^ ) "=") ver in
           [ "version", ver; "registry", reg; "path", path ]
           |> List.filter_map (fun (key, maybe_value) ->
             Option.map (fun value -> key, value) maybe_value)
           |> List.map (fun (key, value) -> Printf.sprintf "%s = \"%s\"" key value)
           |> String.concat ", "
           |> pf "%s = { %s }" name)
       dependencies);
  Buffer.contents buffer
;;

let generate_ml_source () =
  let buffer = Buffer.create 256 in
  (* Shorter eta-expanded helper function with automatic newline *)
  let pf fmt = Printf.bprintf buffer (fmt ^^ "\n") in
  pf "(* Generated by %s *)" program_name;
  pf {|
let please_generate_and_link_rust_staticlib = ()
|};
  Buffer.contents buffer
;;

let escape_sexp_content content =
  let buf = Buffer.create (String.length content) in
  String.iter
    (function
      | '\n' -> Buffer.add_string buf "\\n"
      | '"' -> Buffer.add_string buf "\\\""
      | c -> Buffer.add_char buf c)
    content;
  Buffer.contents buf
;;

let generate_dune_write_file_rule filename content =
  let escaped_content = escape_sexp_content content in
  Printf.sprintf
    {|
; Create %s file in this folder within source directory
(subdir
  generated ; do the actual generation in `generated` subdir
            ; this helps to hide generated files from cargo
            ; as cargo looks for workspace by scanning the
            ; directory tree upwards from current dir
  (rule
    (alias populate-rust-staticlib)
    (targets %s)
    (mode
      (promote 
        (into ..))) ; promote back to current dir
    (action
      (write-file ; file contents
        %s
        "%s"))))
|}
    filename
    filename
    filename
    escaped_content
;;

let generate_dune_write_file_rule_simple filename content =
  let escaped_content = escape_sexp_content content in
  Printf.sprintf
    {|
; Create %s file in this folder within build directory only
(rule
  (targets %s)
  (action
    (write-file ; file contents
      %s
      "%s")))
|}
    filename
    filename
    filename
    escaped_content
;;

(* Function to write the crate files *)
let write_content filename content =
  let path = OpamFilename.of_string filename in
  OpamFilename.write path content
;;

let add_header buffer opam_package_name =
  Printf.sprintf
    "; Generated by %s for opam package: %s\n\n"
    program_name
    opam_package_name
  |> Buffer.add_string buffer;
  Printf.sprintf
    {|
; Generated by %s. Do not edit by hand!
; Run `dune runtest` to regenerate.

; Rules in this file generate cargo crate with the so called rust staticlib.
; This crate depends on all the crates, which are marked as Rust stubs by
; `%s` metadata field in corresponding opam packages that your
; opam file depend on. The Rust staticlib crate re-exports all the dependencies
; and builds statically and dynamically linked libraries, which consequently
; have all the defined symbols which are used by OCaml bindings.
|}
    program_name
    crate_extension_name
  |> Buffer.add_string buffer
;;

let add_cargo_toml buffer crate_name dependencies local_crate opam_package_name =
  generate_cargo_toml_content crate_name dependencies local_crate opam_package_name
  |> generate_dune_write_file_rule "Cargo.toml"
  |> Buffer.add_string buffer
;;

let add_lib_rs buffer dependencies local_crate =
  generate_lib_rs_content dependencies local_crate
  |> generate_dune_write_file_rule "lib.rs"
  |> Buffer.add_string buffer
;;

let add_ml_source buffer =
  generate_ml_source ()
  |> generate_dune_write_file_rule_simple "Rust_staticlib.ml"
  |> Buffer.add_string buffer
;;

let add_dune_content buffer crate_name dune_staticlib_name =
  generate_dune_content crate_name dune_staticlib_name |> Buffer.add_string buffer
;;

let write_crate
  crate_name
  dependencies
  local_crate
  dune_staticlib_name
  output_filename
  opam_package_name
  =
  let buffer = Buffer.create 256 in
  add_header buffer opam_package_name;
  add_cargo_toml buffer crate_name dependencies local_crate opam_package_name;
  add_lib_rs buffer dependencies local_crate;
  add_ml_source buffer;
  add_dune_content buffer crate_name dune_staticlib_name;
  write_content output_filename (Buffer.contents buffer)
;;

let load_extra_crate_manifests extra_crate_paths =
  List.map
    (fun path ->
      let manifest = Cargo_manifest.get_cargo_info path in
      { name = manifest.name
      ; version = None
      ; path = Some path
      ; registry = None
      ; dependency_source = Commandline
      })
    extra_crate_paths
;;

(* Function to generate a Rust static library *)
let gen_staticlib st params f opam =
  let { Cmdline.opam_file = _; output_filename; local_crate_path; extra_crate_paths } =
    params
  in
  (* Get the filename of the opam file *)
  let opam_filename = OpamFile.filename f in
  (* Get the base name of the opam file without the extension *)
  let base = OpamFilename.Base.to_string (OpamFilename.basename opam_filename) in
  let base_without_ext = Filename.remove_extension base in
  (* Create the crate name *)
  let crate_name = "rust-staticlib-" ^ base_without_ext in
  (* Get the crate dependencies *)
  let extra_crate_dependencies = load_extra_crate_manifests extra_crate_paths in
  let crate_deps = get_crates st opam @ extra_crate_dependencies in
  (* Get the local crate *)
  let local_crate =
    (* Get the crate extension from the opam file *)
    get_crate_ext opam (OpamFile.OPAM.package opam)
    |> Option.map (fun { name = crate_name; _ } ->
      let local_crate_path =
        match local_crate_path with
        | Some x -> x
        | None ->
          OpamConsole.error_and_exit
            `Bad_arguments
            "Opam file (%s) defines local crate %s, you need to provide a relative path \
             to this crate via --local-crate-path"
            (OpamFile.to_string f)
            crate_name
      in
      (* Return the crate name and the relative path as a tuple *)
      crate_name, local_crate_path)
  in
  match crate_deps, local_crate with
  | [], None ->
    (* If there are no crate dependencies and no local crate, we're unable to
       generate the Rust static library *)
    OpamConsole.error_and_exit
      `Bad_arguments
      "Generation of Rust staticlib for %s failed as it does not have Rust dependencies\n"
      (OpamFilename.to_string opam_filename)
  | _ ->
    (* Generate the name for the dune static library *)
    let dune_staticlib_name = base_without_ext |> rustify_crate_name in
    (* Write the crate files *)
    let opam_package_name =
      OpamFile.OPAM.package opam |> OpamPackage.name |> OpamPackage.Name.to_string
    in
    write_crate
      crate_name
      crate_deps
      local_crate
      dune_staticlib_name
      output_filename
      opam_package_name
;;
