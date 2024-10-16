open OpamStateTypes

let program_name = "rust-staticlib-gen"

(* The name of the extension in the opam file that specifies the Rust crate
   dependencies *)
let crate_extension_name = "x-rust-stubs-crate"

(* Type used to track the name and path of the crate that is referred to from
   the original .opam file that this tool was run against.
   This type represents a local Rust crate specified in the opam file via the
   x-rust-stubs-crate metadata field. *)
type local_crate =
  { name : string
  ; path : string
  }

(* Type representing the parameters required for generating the dune.inc file.
   This type includes the crate name, the dune static library name, the list of
   dependencies, the local crate (if any), and the opam package name. These
   parameters are used to construct the necessary rules and content for building
   the Rust static library. *)
type dune_params =
  { crate_name : string
  ; dune_staticlib_name : string
  ; dependencies : Crate_dependency.t list
  ; local_crate : local_crate option
  ; opam_package_name : string
  }

(* Generates the main dune.inc file, which contains rules to create additional
   files and build the Rust static library.
   This function constructs the content for the dune.inc file, including rules
   for generating dependencies, compiling the Rust static library, and linking
   it into the final OCaml executable. The generated file ensures that all
   Rust-related dependencies are tracked and that Cargo is invoked to build the
   static library incrementally. *)
let generate_dune_content ~crate_name ~dune_staticlib_name =
  let buffer = Buffer.create 256 in
  let pf fmt = Printf.bprintf buffer (fmt ^^ "\n") in
  pf "";
  let lib_name = Util.rustify_crate_name crate_name in
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
  pf "  (alias populate-rust-staticlib)";
  pf "  (glob_files_rec %%{workspace_root}/*.rs)";
  pf "  (glob_files_rec %%{workspace_root}/Cargo.toml)";
  pf "  (glob_files_rec %%{workspace_root}/Cargo.lock))";
  pf " (action";
  pf "  (with-stdout-to %%{target}";
  pf "   (echo \"(%%{deps})\"))))";
  pf
    {|
; Below alias is handy if you want to depend on changes to any Rust/Cargo
; sources in your project, you can safely depend on it outside of this subdir
|};
  pf "(alias";
  pf " (name rust-universe)";
  pf " (deps";
  pf "  (include rust-deps.inc) ; depend on all Rust bits in your project";
  pf "  (alias populate-rust-staticlib))) ; and on Rust staticlib generation";
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
  pf "  (alias rust-universe) ; rebuild only if Rust bits change, linking is slow";
  pf "  Cargo.toml)";
  pf " (locks cargo-build)";
  pf " (action";
  pf "  (run dune-cargo-build";
  pf "   --profile=%%{profile}";
  pf "   --workspace-root=%%{workspace_root}";
  pf "   ./Cargo.toml)))";
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
  pf
    " (implements rust-staticlib-virtual) ; mark this lib as the one implementing \
     rust-staticlib";
  pf " (c_library_flags";
  pf "  (-lpthread -lc -lm)))";
  Buffer.contents buffer
;;

(* Generates the content for the lib.rs file, which re-exports all the Rust
   crates specified via the x-rust-stubs-crate metadata in the opam dependencies.
   This function constructs the lib.rs file by iterating over the list of
   dependencies and local crates, and adding a `pub use` statement for each
   crate.  The resulting lib.rs file ensures that all required Rust crates are
   available for use in the Rust static library. *)
let generate_lib_rs_content ~dependencies ~local_crate =
  let buffer = Buffer.create 256 in
  let pf fmt = Printf.bprintf buffer (fmt ^^ "\n") in
  pf "/* Generated by %s */" program_name;
  pf "";
  let names = List.map (fun { Crate_dependency.name; _ } -> name) dependencies in
  let names =
    match local_crate with
    | None -> names
    | Some { name; _ } -> name :: names
  in
  let sorted_names = List.sort String.compare names in
  List.iter (fun name -> pf "pub use %s;" (Util.rustify_crate_name name)) sorted_names;
  Buffer.contents buffer
;;

(* Generates the Cargo.toml file for the Rust static library, including
   dependencies specified via the x-rust-stubs-crate metadata in the opam files.
   This function constructs the Cargo.toml file by adding sections for the
   package, library, and dependencies. It ensures that the dependencies are
   listed with exact version matches to maintain compatibility between OCaml
   bindings and their Rust stubs crates. The generated file includes comments
   for better debugging and understanding of where each dependency is coming
   from. *)
let generate_cargo_toml_content ~crate_name ~dependencies ~local_crate ~opam_package_name =
  let buffer = Buffer.create 256 in
  let pf fmt = Printf.bprintf buffer (fmt ^^ "\n") in
  let add_header () =
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
      crate_extension_name
  in
  let add_package_section () =
    pf "";
    pf "[package]";
    pf "name = \"%s\"" crate_name;
    pf "version = \"0.1.0\"";
    pf "edition = \"2021\""
  in
  let add_lib_section () =
    pf "";
    pf "[lib]";
    pf "crate-type = [\"staticlib\", \"cdylib\", \"rlib\"]";
    pf "path = \"lib.rs\""
  in
  let add_dependencies_section () =
    match dependencies, local_crate with
    | [], None -> ()
    | _ ->
      pf "";
      pf "[dependencies]";
      (match local_crate with
       | None -> ()
       | Some { name; path } ->
         pf "# Declared by local opam package (%s)" opam_package_name;
         pf "%s = { path = \"%s\" }" name path);
      List.iter
        (fun { Crate_dependency.name; version; registry; path; dependency_source } ->
          pf
            "# Declared by: %s"
            (Crate_dependency.string_of_dependency_source dependency_source);
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
        dependencies
  in
  add_header ();
  add_package_section ();
  add_lib_section ();
  add_dependencies_section ();
  Buffer.contents buffer
;;

(* Generates a dummy OCaml source file that satisfies the rust-staticlib virtual
   library interface.
   This function creates a minimal OCaml source file, Rust_staticlib.ml, which
   implements the virtual library rust-staticlib. *)
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

(* Generates the header for the main dune.inc file.
   This function adds a header to the dune.inc file, including comments that
   indicate the file was generated by rust-staticlib-gen.
   The header provides context about the purpose of the file and the rules it
   contains for generating the Rust static library. *)
let add_header (buffer : Buffer.t) (opam_package_name : string) =
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

(* Adds the Cargo.toml generation rule to the dune.inc file.
   This function generates the content for the Cargo.toml file and adds a rule
   to the dune.inc file to write this content to Cargo.toml.
   The rule ensures that the Cargo.toml file is created with the correct
   dependencies and configuration for building the Rust static library. *)
let add_cargo_toml ~buffer ~params =
  generate_cargo_toml_content
    ~crate_name:params.crate_name
    ~dependencies:params.dependencies
    ~local_crate:params.local_crate
    ~opam_package_name:params.opam_package_name
  |> Util.generate_dune_write_file_rule "Cargo.toml"
  |> Buffer.add_string buffer
;;

(* Adds the lib.rs generation rule to the dune.inc file.
   This function generates the content for the lib.rs file and adds a rule to
   the dune.inc file to write this content to lib.rs.
   The rule ensures that the lib.rs file is created with the correct re-exports
   for all required Rust crates. *)
let add_lib_rs ~buffer ~params =
  generate_lib_rs_content
    ~dependencies:params.dependencies
    ~local_crate:params.local_crate
  |> Util.generate_dune_write_file_rule "lib.rs"
  |> Buffer.add_string buffer
;;

(* Adds the OCaml source file generation rule to the dune.inc file.
   This function generates the content for the Rust_staticlib.ml file and adds a
   rule to the dune.inc file to write this content to Rust_staticlib.ml.  The
   rule ensures that the Rust_staticlib.ml file is created with the necessary
   implementation of the rust-staticlib virtual library interface. *)
let add_ml_source ~buffer =
  generate_ml_source ()
  |> Util.generate_dune_write_file_rule_simple "Rust_staticlib.ml"
  |> Buffer.add_string buffer
;;

(* Adds the main dune content generation rule to the dune.inc file.
   This function generates the main content for the dune.inc file, including
   rules for generating dependencies, compiling the Rust static library, and
   linking it into the final OCaml executable. The rule ensures that all
   necessary steps are included in the dune.inc file for building the Rust
   static library. *)
let add_dune_content ~buffer ~params =
  generate_dune_content
    ~crate_name:params.crate_name
    ~dune_staticlib_name:params.dune_staticlib_name
  |> Buffer.add_string buffer
;;

(* Loads Cargo manifests for extra crate paths and builds crate dependencies
   with the source listed as command-line.
   This function iterates over the list of extra crate paths, loads the Cargo
   manifest for each path, and constructs a Crate_dependency.t record for each
   crate. The resulting list of crate dependencies includes the name, version,
   path, registry, and dependency source for each crate. *)
let load_extra_crate_manifests (extra_crate_paths : string list) =
  List.map
    (fun path ->
      let manifest = Cargo_manifest.get_cargo_info path in
      { Crate_dependency.name = manifest.name
      ; version = None
      ; path = Some path
      ; registry = None
      ; dependency_source = Commandline
      })
    extra_crate_paths
;;

let get_base_without_ext opam_filename =
  let base = OpamFilename.Base.to_string (OpamFilename.basename opam_filename) in
  Filename.remove_extension base
;;

(* Retrieves the x-rust-stubs-crate metadata from the local opam file and
   validates the --local-crate-path argument.
   This function checks if the local opam file specifies a Rust crate via the
   x-rust-stubs-crate metadata field. If a local crate is specified, it
   validates the --local-crate-path argument and constructs a local_crate record
   with the crate name and path. If the --local-crate-path argument is not
   provided, the function raises an error. *)
let get_local_crate local_crate_path opam f =
  Opam_pkg_meta.get_crate_ext opam (OpamFile.OPAM.package opam)
  |> Option.map (fun { Crate_dependency.name = crate_name; _ } ->
    let local_crate_path =
      match local_crate_path with
      | Some x -> x
      | None ->
        OpamConsole.error_and_exit
          `Bad_arguments
          "Opam file (%s) defines local crate %s, you need to provide a relative path to \
           this crate via --local-crate-path"
          (OpamFile.to_string f)
          crate_name
    in
    { name = crate_name; path = local_crate_path })
;;

(* Retrieves the dune and opam names for the static library and validates the presence of Rust dependencies.
   This function constructs the dune_staticlib_name and opam_package_name based
   on the base name of the opam file and the opam package name.
   If there are no Rust dependencies specified in the opam file or via the
   --local-crate-path argument, the function raises an error. *)
let get_dune_and_opam_names crate_deps local_crate base_without_ext opam_filename opam =
  match crate_deps, local_crate with
  | [], None ->
    OpamConsole.error_and_exit
      `Bad_arguments
      "Generation of Rust staticlib for %s failed as it does not have Rust dependencies\n"
      (OpamFilename.to_string opam_filename)
  | _ ->
    let dune_staticlib_name = base_without_ext |> Util.rustify_crate_name in
    let opam_package_name =
      OpamFile.OPAM.package opam |> OpamPackage.name |> OpamPackage.Name.to_string
    in
    dune_staticlib_name, opam_package_name
;;

(* Main entry point to generate the Rust static library for a single opam file.
   This function orchestrates the generation of the dune.inc file, which
   contains rules to create additional files and build the Rust static library.
   It extracts Rust crate dependencies from the opam file, validates the
   --local-crate-path argument, and constructs the necessary parameters for
   generating the dune.inc file. The resulting dune.inc file includes rules for
   generating the Cargo.toml, lib.rs, and Rust_staticlib.ml files, as well as
   rules for compiling the Rust static library and linking it into the final
   OCaml executable. *)
let gen_staticlib
  (st : [< unlocked > `Lock_write ] switch_state)
  (params : Cmdline.params)
  (f : 'a OpamFile.t)
  (opam : OpamFile.OPAM.t)
  =
  let { Cmdline.opam_file = _; output_filename; local_crate_path; extra_crate_paths } =
    params
  in
  let opam_filename = OpamFile.filename f in
  let base_without_ext = get_base_without_ext opam_filename in
  let crate_name = "rust-staticlib-" ^ base_without_ext in
  let extra_crate_dependencies = load_extra_crate_manifests extra_crate_paths in
  let crate_deps = Opam_pkg_meta.get_crates st opam @ extra_crate_dependencies in
  let local_crate = get_local_crate local_crate_path opam f in
  let dune_staticlib_name, opam_package_name =
    get_dune_and_opam_names crate_deps local_crate base_without_ext opam_filename opam
  in
  let buffer = Buffer.create 256 in
  let params =
    { crate_name
    ; dune_staticlib_name
    ; dependencies = crate_deps
    ; local_crate
    ; opam_package_name
    }
  in
  add_header buffer opam_package_name;
  add_cargo_toml ~buffer ~params;
  add_lib_rs ~buffer ~params;
  add_ml_source ~buffer;
  add_dune_content ~buffer ~params;
  Util.write_content output_filename (Buffer.contents buffer)
;;
