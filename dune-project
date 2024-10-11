(lang dune 2.0)

(name rust-staticlib-gen)

(generate_opam_files true)

(package
 (name rust-staticlib-gen)
 (maintainers "The rust-staticlib-gen contributors")
 (synopsis "Rust staticlib generation utility")
 (authors "The rust-staticlib-gen contributors")
 (homepage "https://github.com/Lupus/rust-staticlib-gen")
 (bug_reports "https://github.com/Lupus/rust-staticlib-gen/issues")
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
 (maintainers "The rust-staticlib-gen contributors")
 (synopsis "A dummy package to define staticlib virtual library")
 (authors "The rust-staticlib-gen contributors")
 (homepage "https://github.com/Lupus/rust-staticlib-gen")
 (bug_reports "https://github.com/Lupus/rust-staticlib-gen/issues")
 (depends))

(package
 (name dune-cargo-build)
 (maintainers "The rust-staticlib-gen contributors")
 (synopsis "A tool to invoke Cargo to build the Cargo crates from within dune sandbox")
 (authors "The rust-staticlib-gen contributors")
 (homepage "https://github.com/Lupus/rust-staticlib-gen")
 (bug_reports "https://github.com/Lupus/rust-staticlib-gen/issues")
 (depends
  (yojson
   (>= 2.2.2))
  (ocamlformat
   (and
    :with-test
    (>= 0.26.2)
    (< 0.27.0)))
  (odoc :with-doc)))
