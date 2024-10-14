(lang dune 2.7)

(name rust-staticlib-gen)

(generate_opam_files true)

(source
 (github Lupus/rust-staticlib-gen))

(license Apache-2.0)

(authors "Konstantin Olkhovskiy <lupus@oxnull.net>")

(maintainers "Konstantin Olkhovskiy <lupus@oxnull.net>")

(package
 (name rust-staticlib-gen)
 (synopsis "Utility for generating Rust static libraries for OCaml projects")
 (description
  "rust-staticlib-gen is a tool designed to streamline the integration of Rust code into OCaml projects. It automates the generation of build files and orchestrates the build process, allowing OCaml code to seamlessly interface with Rust libraries. This tool extracts Rust crate dependencies from opam files, generates necessary dune and Cargo.toml files, and builds the Rust static libraries. It ensures compatibility between OCaml bindings and Rust crates by specifying exact versions in Cargo.toml.")
 (depends
  (toml
   (>= 7.1.0))
  (yojson
   (>= 2.2.2))
  (sexplib0
   (>= v0.16.0))
  (parsexp
   (>= v0.16.0))
  (opam-client
   (and
    (>= 2.2.1)
    (< 2.3)))
  (opam-state
   (and
    (>= 2.2.1)
    (< 2.3)))
  (opam-solver
   (and
    (>= 2.2.1)
    (< 2.3)))
  (fpath
   (>= 0.7.3))
  (cmdliner
   (>= 1.3.0))
  (ocamlformat
   (and
    :with-test
    (>= 0.26.2)
    (< 0.27.0)))))

(package
 (name rust-staticlib-virtual)
 (synopsis
  "A Sentinel/marker package to define the rust staticlib virtual library")
 (description
  "The rust-staticlib-virtual package is a sentinel/marker package that defines a virtual dune library that indicates presence of Rust dependencies somewhere down the dependency chain. To have an implementation of this virtual library in your project, please use `rust-staticlib-gen` tool: https://github.com/Lupus/rust-staticlib-gen")
 (depends))

(package
 (name dune-cargo-build)
 (synopsis
  "Tool to invoke Cargo for building Rust crates within the dune sandbox")
 (description
  "dune-cargo-build is a tool that runs cargo build in offline mode for a specified crate, ensuring compatibility with dune's/opam's sandboxing. It parses Cargo's JSON output to determine the produced artifacts and copies them to the current directory, renaming them to match what OCaml expects for foreign stubs. This tool is useful for integrating Rust build processes into OCaml projects managed by dune.")
 (depends
  (yojson
   (>= 2.2.2))
  (ocamlformat
   (and
    :with-test
    (>= 0.26.2)
    (< 0.27.0)))
  (odoc :with-doc)))
