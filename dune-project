(lang dune 2.7)

(name rust-staticlib-gen)

(generate_opam_files true)

(source
 (github Lupus/rust-staticlib-gen))

(license Apache-2.0)

(authors "The rust-staticlib-gen contributors")

(maintainers "The rust-staticlib-gen contributors")

(package
 (name rust-staticlib-gen)
 (synopsis "Rust staticlib generation utility")
 (depends
  (toml
   (>= 7.1.0))
  (yojson
   (>= 2.2.2))
  (sexplib0
   (>= v0.16.0))
  (parsexp
   (>= v0.16.0))
  (opam-state
   (>= 2.2.1))
  (opam-solver
   (>= 2.2.1))
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
 (name rust-staticlib)
 (synopsis "A dummy package to define staticlib virtual library")
 (depends))

(package
 (name dune-cargo-build)
 (synopsis
  "A tool to invoke Cargo to build the Cargo crates from within dune sandbox")
 (depends
  (yojson
   (>= 2.2.2))
  (ocamlformat
   (and
    :with-test
    (>= 0.26.2)
    (< 0.27.0)))
  (odoc :with-doc)))
