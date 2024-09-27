type cargo_info =
  { name : string
  ; version : string
  }

let get_cargo_info folder =
  let filename = Filename.concat folder "Cargo.toml" in
  let content = open_in filename in
  let toml_table = Toml.Parser.from_channel content |> Toml.Parser.unsafe in
  close_in content;
  let name_opt =
    Toml.Lenses.(get toml_table (key "package" |-- table |-- key "name" |-- string))
  in
  let version_opt =
    Toml.Lenses.(get toml_table (key "package" |-- table |-- key "version" |-- string))
  in
  match name_opt, version_opt with
  | Some name, Some version -> { name; version }
  | _ -> failwith "Cannot find name or version in [package] section"
;;
