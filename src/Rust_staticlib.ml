open OpamStateTypes

(* The name of the extension in the opam file that specifies the Rust crate
   dependencies *)
let crate_extension_name = "x-rust-stubs-crate"

(* Type for storing cargo metadata *)
type cargo_metadata =
  { crate_to_path :
      (string, string) Hashtbl.t (* Hash table mapping crate names to paths *)
  ; workspace_root : string (* Root directory of the cargo workspace *)
  ; target_directory : string (* Directory where the build artifacts are stored *)
  }

(* Function to extract cargo metadata *)
let extract_cargo_metadata () =
  let open Yojson.Basic.Util in
  let output = Util.capture_cmd "cargo metadata --format-version=1 --no-deps" in
  (* Parse the output into JSON *)
  let json = Yojson.Basic.from_string output in
  (* Extract the workspace members from the JSON *)
  let workspace_members =
    json |> member "workspace_members" |> to_list |> List.map to_string
  in
  (* Extract the packages from the JSON *)
  let packages = json |> member "packages" |> to_list in
  (* Create a hashtable to store the crate name and path *)
  let crate_to_path = Hashtbl.create 10 in
  (* Iterate over each package *)
  List.iter
    (fun package ->
      let id = package |> member "id" |> to_string in
      if List.mem id workspace_members
      then (
        let crate_name = package |> member "name" |> to_string in
        let manifest_path = package |> member "manifest_path" |> to_string in
        Hashtbl.add crate_to_path crate_name manifest_path))
    packages;
  (* Extract the workspace root and target directory from the JSON *)
  let workspace_root = json |> member "workspace_root" |> to_string in
  let target_directory = json |> member "target_directory" |> to_string in
  (* Return the cargo metadata *)
  { crate_to_path; workspace_root; target_directory }
;;

(* Defining the type for crate dependency *)
type crate_dependency =
  { name : string
  ; version : string
  ; registry : string option
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
         ; version = OpamPackage.version_to_string pkg
         ; registry = Some registry
         }
     (* If the extension is not correctly formatted, exit with an error *)
     | _ ->
       OpamConsole.error_and_exit
         `Internal_error
         "List extension in package is not correctly formatted. Expected format: [ \
          String crate; String registry ]")
  (* If the extension is a string, return a crate_dependency object with no registry *)
  | OpamParserTypes.FullPos.String crate ->
    Some { name = crate; version = OpamPackage.version_to_string pkg; registry = None }
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
  pf "(rule";
  pf " (targets lib%s.a dll%s.so)" lib_name lib_name;
  pf " (deps (universe) (alias generated/populate-rust-staticlib))";
  pf " (locks cargo-build)";
  pf " (action";
  pf
    "  (run \
     /home/kolkhovskiy/git/ocaml/rust-staticlib-gen/_build/default/bin/build_cargo_crate.exe \
     %s)))"
    crate_name;
  pf "";
  pf "(library";
  pf " (name %s_stubs)" dune_staticlib_name;
  pf " (foreign_archives %s)" lib_name;
  pf " (modules ())";
  pf " (c_library_flags";
  pf "  (-lpthread -lc -lm)))";
  Buffer.contents buffer
;;

(* Function to generate lib.rs content *)
let generate_lib_rs_content dependencies local_crate =
  let buffer = Buffer.create 256 in
  (* Shorter eta-expanded helper function with automatic newline *)
  let pf fmt = Printf.bprintf buffer (fmt ^^ "\n") in
  pf "/* Generated by nst-lock */";
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
let generate_cargo_toml_content crate_name dependencies local_crate =
  let buffer = Buffer.create 256 in
  (* Shorter eta-expanded helper function with automatic newline *)
  let pf fmt = Printf.bprintf buffer (fmt ^^ "\n") in
  pf "# Generated by nst-lock";
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
      | Some (name, path) -> pf "%s = { path = \"%s\" }" name path);
     List.iter
       (function
         | { name; version; registry = Some registry } ->
           pf "%s = { version = \"=%s\", registry=\"%s\" }" name version registry
         | { name; version; registry = None } -> pf "%s = \"=%s\"" name version)
       dependencies);
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

let generate_dune_rule filename content =
  let escaped_content = escape_sexp_content content in
  Printf.sprintf
    {|
(subdir
  generated
  (rule
    (alias populate-rust-staticlib)
    (targets %s)
    (mode
      (promote
        (into ..)))
    (action
      (write-file
        %s
        "%s"))))
        |}
    filename
    filename
    escaped_content
;;

(* Function to write the crate files *)
let write_crate
  crate_directory
  crate_name
  dependencies
  local_crate
  dune_staticlib_name
  output_filename
  =
  let write_content filename content =
    (* Convert strings to the appropriate types *)
    let basename = OpamFilename.Base.of_string filename in
    (* Create the complete file path *)
    let path = OpamFilename.create crate_directory basename in
    (* Write the content to the file *)
    OpamFilename.write path content
  in
  let buffer = Buffer.create 256 in
  (* Write the generated content to the Cargo.toml, lib.rs, and dune files *)
  generate_cargo_toml_content crate_name dependencies local_crate
  |> generate_dune_rule "Cargo.toml"
  |> Buffer.add_string buffer;
  generate_lib_rs_content dependencies local_crate
  |> generate_dune_rule "lib.rs"
  |> Buffer.add_string buffer;
  generate_dune_content crate_name dune_staticlib_name |> Buffer.add_string buffer;
  write_content output_filename (Buffer.contents buffer)
;;

(* Function to calculate the relative path from a base path to a target path *)
let relative_path_from ~base ~target =
  (* Normalize and split the base and target paths into segments *)
  let base_segs = Fpath.segs (Fpath.normalize base) in
  let target_segs = Fpath.segs (Fpath.normalize target) in
  (* Recursive function to calculate the length of the common prefix of two lists *)
  let rec common_prefix_length xs ys len =
    match xs, ys with
    | x :: xs', y :: ys' when x = y -> common_prefix_length xs' ys' (len + 1)
    | _ -> len
  in
  (* Calculate the length of the common prefix of the base and target path segments *)
  let prefix_len = common_prefix_length base_segs target_segs 0 in
  (* Calculate the number of remaining segments in the base path after removing the common prefix *)
  let base_remainder = List.length base_segs - prefix_len in
  (* Recursive function to drop the first n elements of a list *)
  let rec drop n lst = if n <= 0 then lst else drop (n - 1) (List.tl lst) in
  (* Drop the common prefix from the target path segments *)
  let target_remainder = drop prefix_len target_segs in
  (* Recursive function to generate a list of ".." strings of a given length *)
  let rec make_dots n acc = if n <= 0 then acc else make_dots (n - 1) (".." :: acc) in
  (* Generate the relative parts of the path *)
  let relative_parts = make_dots base_remainder [] in
  (* Combine the relative parts and the remainder of the target path *)
  let final_parts = relative_parts @ target_remainder in
  (* Convert the final parts back into a path *)
  match final_parts with
  | [] -> Fpath.v "."
  | hd :: tl -> List.fold_left (fun acc p -> Fpath.(acc // v p)) (Fpath.v hd) tl
;;

(* Function to generate a Rust static library *)
let gen_staticlib st cargo_metadata project_dir f opam output_filename =
  let project_dir = OpamFilename.Dir.of_string project_dir in
  (* Get the filename of the opam file *)
  let opam_filename = OpamFile.filename f in
  (* Get the base name of the opam file without the extension *)
  let base = OpamFilename.Base.to_string (OpamFilename.basename opam_filename) in
  let base_without_ext = Filename.remove_extension base in
  (* Create the crate name *)
  let crate_name = "rust-staticlib-" ^ base_without_ext in
  (* Create the directory path for the new directory *)
  let crate_directory =
    OpamFilename.Op.(project_dir / "rust-staticlibs" / base_without_ext)
  in
  (* Get the crate dependencies *)
  let crate_deps = get_crates st opam in
  (* Get the local crate *)
  let local_crate =
    (* Get the crate extension from the opam file *)
    get_crate_ext opam (OpamFile.OPAM.package opam)
    |> Option.map (fun { name = crate_name; _ } ->
      (* Force the evaluation of the cargo metadata *)
      let cargo_metadata = Lazy.force cargo_metadata in
      (* Try to find the path of the crate in the cargo metadata *)
      match Hashtbl.find_opt cargo_metadata.crate_to_path crate_name with
      | Some path ->
        (* If the path is found, calculate the relative path from the crate
           directory to the input path *)
        let crate_directory = Fpath.v (crate_directory |> OpamFilename.Dir.to_string) in
        let input_path = Fpath.v path in
        let path = relative_path_from ~base:crate_directory ~target:input_path in
        (* Return the crate name and the relative path as a tuple *)
        crate_name, Fpath.to_string path
      | None ->
        (* If the path is not found, exit with an error *)
        OpamConsole.error_and_exit
          `Bad_arguments
          "Crate %s (specified in %s) not found in local cargo workspace"
          crate_name
          (OpamFile.to_string f))
  in
  match crate_deps, local_crate with
  | [], None ->
    (* If there are no crate dependencies and no local crate, skip the generation
       of the Rust static library *)
    OpamConsole.msg
      "Skipping generation of Rust staticlib for %s as it does not have Rust dependencies\n"
      (OpamFilename.to_string opam_filename)
  | _ ->
    (* Otherwise, create the directory for the Rust static library *)
    OpamConsole.msg "Creating directory %s\n" (OpamFilename.Dir.to_string crate_directory);
    if not (OpamFilename.exists_dir crate_directory)
    then OpamFilename.mkdir crate_directory;
    (* Generate the name for the dune static library *)
    let dune_staticlib_name = base_without_ext |> rustify_crate_name in
    (* Write the crate files *)
    write_crate
      crate_directory
      crate_name
      crate_deps
      local_crate
      dune_staticlib_name
      output_filename;
    OpamConsole.msg
      "Generated Rust staticlib for %s in %s\n"
      (OpamFilename.to_string opam_filename)
      (OpamFilename.Dir.to_string crate_directory)
;;
