# rust-staticlib-gen

**rust-staticlib-gen** is a tool designed to streamline the integration of Rust
code into OCaml projects. It automates the generation of build files and
orchestrates the build process, allowing OCaml code to seamlessly interface with
Rust libraries. It's accompanied by the `rust-staticlib-build` wrapper tool to
call `cargo build` and fetch artifacts, and the `rust-staticlib` virtual library
to flag the presence of Rust dependencies for the end users.

**WARNING**: This is still highly experimental, use at your own risk!

## Table of Contents

- [Problem Statement](#problem-statement)
- [Opam metadata-level linkage to Cargo crates](#opam-metadata-level-linkage-to-cargo-crates)
- [Rust "tainting" and scary linker errors](#rust-tainting-and-scary-linker-errors)
- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
- [How It Works](#how-it-works)
- [Contributing](#contributing)
- [License](#license)

## Problem statement

Integrating Rust components into OCaml libraries at scale presents significant
challenges due to differences in package management and build systems. The main
issue lies in effectively combining Opam (OCaml's package manager) and Cargo
(Rust's package manager) to ensure seamless integration without compromising
dependency resolution or build reproducibility.

Key challenges include:

* ABI Compatibility: Rust lacks a stable ABI, necessitating recompilation from
  source for each project, which conflicts with Opam's handling of precompiled
  libraries.
* Dependency Management: Opam resolves dependencies before builds, whereas Cargo
  does so during the build process. This can lead to conflicts if dependencies
  are not managed consistently.
* Sandboxing and Network Access: Opam restricts network access during builds,
  complicating Cargo's dependency fetching process.
* Build System Integration: Aligning Cargo with Dune (OCaml's build system) is
  complex, requiring both systems to recognize and manage each other's build
  artifacts.

A proposed solution involves compiling all Rust components from source within
the final project that links executables. This approach circumvents direct
management of Rust dependencies by relying on Opam packages that encapsulate
these dependencies, ensuring compatibility and consistency across the build
process.

### Prior discussions on this:

* https://github.com/zshipko/ocaml-rs/issues/139
* https://discuss.ocaml.org/t/cargo-opam-packaging-of-a-rust-ocaml-project/5743
* https://users.rust-lang.org/t/integrating-rust-crates-into-ocaml-package-management/99818

## Opam metadata-level linkage to Cargo crates

Libraries with bindings to certain Cargo crates start forming their own
dependency graph. One library with bindings may want to use already defined
bindings for some other Rust entities, provided by another library with
bindings. For example, there is
[ocaml-lwt-interop](https://github.com/Lupus/ocaml-lwt-interop), which provides
integration between the Rust async world and OCaml's LWT monadic concurrency
library. It offers some OCaml API which wraps some Rust entities. Some
hypothetical bindings to the `hyper` HTTP framework would be willing to leverage
some types defined by `ocaml-lwt-interop`, so that `ocaml-hyper` could build on
top of that infrastructure. This forms independent dependency graphs within the
opam and cargo realms, and there is still this implicit knowledge that certain
Cargo crates provide some `extern "C"` functions which are used by specific opam
packages with bindings.

```mermaid
flowchart
olwti["ocaml-lwt-interop (rust crate)"]
style olwti fill:#e38d8d
olwti_stubs["ocaml-lwt-interop-stubs (rust stubs crate)"]
style olwti_stubs fill:#e38d8d,stroke:#e3dc8d,stroke-width:3px
rust_async["rust-async (dune library)"]
style rust_async fill:#e3dc8d
ocaml_hyper["ocaml-hyper (rust crate)"]
style ocaml_hyper fill:#e38d8d
ocaml_hyper_stubs["ocaml-hyper-stubs (rust stubs crate)"]
style ocaml_hyper_stubs fill:#e38d8d,stroke:#e3dc8d,stroke-width:3px
rust_hyper["rust-hyper (dune library)"]
style rust_hyper fill:#e3dc8d
olwti_stubs -->|cargo dependency| olwti
rust_async -->|implicit?| olwti_stubs
rust_hyper -->|dune dependency| rust_async
ocaml_hyper -->|cargo dependency| olwti
ocaml_hyper_stubs -->|cargo dependency| ocaml_hyper
ocaml_hyper_stubs -->|cargo dependency| olwti
rust_hyper -->|implicit?| ocaml_hyper_stubs
```

To encode these implicit links between opam packages and cargo crates, we
leverage the fact that opam allows arbitrary metadata to be contained within
opam package definitions. `dune` allows you to come up with a template for the
generation of an opam package, which `ocaml-lwt-interop` is using by providing
`rust-async.opam.template` file with the following content:

```bash
# This extensions connects this opam package to its corresponding Rust stubs
# crate. An automated tool could traverse opam dependencies, find ones
# containing such extension fields and combine a full set of Rust crate
# dependencies for a given opam file.
x-rust-stubs-crate: "ocaml-lwt-interop"
```

This special `x-rust-stubs-crate` metadata allows declaring that a specific opam
package requires certain Cargo crates to be built and linked into the final
executable so that the required `extern "C"` functions are available during the
linking phase.

## Rust "tainting" and scary linker errors

We can't just have Rust bits compiled independently into `.a` libraries and
throw them into the linker at the end. Rust drags in its whole stdlib into each
`.a` file that it produces, and having multiple such `.a` libraries at the
linking phase results in sporadic linker errors regarding duplicates (especially
when link-time optimization is enabled in Rust).

So we have to build Rust bits only once into a single `.a` library that would
get linked into the final executable(s). We call it a "Rust static library", or
"Rust staticlib". It seems that Debian is using this strategy to distribute Rust
libraries - they actually distribute source code inside `*-rust` packages and
whenever some package needs to build a Rust executable - it uses installed
sources to build it completely in one go and have the executable linked (see
[Debian Rust packaging policy for more details](https://wiki.debian.org/Teams/RustPackaging/Policy)).

Having special metadata in opam files allows automating the creation of such a
Rust staticlib and ensures it's correct and includes all the required Cargo
crates to fulfill the symbols expected by OCaml binding packages.

Yet for the opam ecosystem, this comes with a downside that some library deep in
the dependency tree of your application, requiring Rust dependencies, will
expect certain `extern "C"` functions to be available at link time, and as you
don't know anything about Rust in your app - it will explode at linking your
executable with scary-looking linker errors complaining about missing symbols,
and having special metadata inside opam packages alone does not help here.

To alleviate the unfriendly way of complaining about missing Rust dependencies,
we leverage dune virtual libraries. A well-known virtual library `rust-staticlib`
should be required by dune libraries, which depend on Rust bits, and the
generated Rust staticlib will implement this library. In this case, linker
errors will be avoided, dune will complain about missing virtual library
implementation, and while looking for how to satisfy this dependency, users
should reach out to the `rust-staticlib-gen` tool, which will provide this
virtual library within their project. Still far from ideal, but better than
leaving the users with linker errors that they will unlikely resolve on their
own at all.

Rust dependencies still will "taint" the entire dependency tree up to the final
executable (and including some test runner executables along the way), but this
looks like the best way forward so far.

## Features

`rust-staticlib-gen` currently is offering the following features:

- **Automatic Dependency Extraction**: Reads opam files to extract Rust crate
  dependencies specified via the `x-rust-stubs-crate` metadata field.
- **Build File Generation**: Generates necessary `dune` and `Cargo.toml` files
  for building Rust static libraries. Generated files have some comments to
  allow the reader to understand what they are doing and why.
- **Seamless Integration**: Orchestrates the build steps to integrate Rust code
  into OCaml projects without manual intervention, except for initial Rust
  project configuration.
- **Version Compatibility**: Ensures compatibility between OCaml bindings and
  Rust crates by specifying exact versions in `Cargo.toml`.

## Installation

This package is currently not publishes onto opam repository. To install
`rust-staticlib-gen`, you can use `opam` to pin it to your project:

```bash
opam pin https://github.com/Lupus/rust-staticlib-gen.git
```

## Usage

One should typically have the following dune file to generate the Rust staticlib:

```
(include dune.inc)

(rule
 (deps ../foo-bar.opam)
 (target dune.inc.gen)
 (action
  (run rust-staticlib-gen -o %{target} %{deps})))

(rule
 (alias runtest)
 (action
  (diff dune.inc dune.inc.gen)))
```

The following options ara available for `rust-staticlib-gen`:

- `--local-crate-path PATH`: Specify a relative path to a local Rust crate if
  your opam package defines a local crate.
- `--output FILENAME`: Specify the output filename for the generated `dune` file.

**--local-crate-path**: This option is required when your opam package actually
implements bindings to some Rust library, and you have the `x-rust-stubs-crate`
metadata field set right in your opam file. This path should be a relative path
from the directory where `rust-staticlib-gen` is called to the directory
containing the `Cargo.toml` of your crate, configured in `x-rust-stubs-crate`.
This is required to emit a proper path dependency in the generated `Cargo.toml`
to your local crate. You would need to configure a Cargo workspace at the root
of your project and include both your local crate and the generated staticlib
crate as workspace members.

## How It Works

`rust-staticlib-gen` automates the integration of Rust code into OCaml projects
by performing the following steps:

1. **Dependency Extraction**: Reads an opam file to extract Rust crate
   dependencies specified via the `x-rust-stubs-crate` metadata field (this
   involves scanning the transitive dependencies of the provided opam file).

2. **Generating Build Files**: Using the extracted dependencies, it generates a
   `dune.inc` file containing rules to produce `Cargo.toml`, `lib.rs`, and
   `Rust_staticlib.ml`.

3. **Building Rust Static Library**:
   - The `dune.inc` rules trigger `rust-staticlib-build`, which invokes Cargo to
     build the Rust static library.
   - `Cargo.toml` and `lib.rs` are used in the Cargo build process to compile
     the Rust code into static and dynamic libraries.
   - The `rust-staticlib-build` tool parses JSON output from the Cargo build to
     know which artifacts it produced and copies them to the current directory,
     also renaming them to match what OCaml expects for foreign stubs.
   - Important note: This whole pipeline relies on Cargo detecting the original
     project directory and effectively escaping dune sandboxing
     (`_build/default`). Cargo is perfectly capable of maintaining incremental
     builds and hygiene around its build cache, so it does not make much sense
     to try to squeeze Cargo into dune sandbox. `dune.inc` has rules to
     accurately track all Rust bits in the project, so that Cargo is called to
     rebuild the static library truly incrementally.
   - Important note #2: Cargo is run with the `--offline` flag, so one has to
     ensure that `cargo fetch` was called somewhere in the CI pipeline, or by
     hand before building the project locally. Offline mode is required to
     successfully build under the opam sandbox, where no network access is
     present. If calling `cargo fetch` is not feasible, one can use `cargo
     vendor` to bundle all Rust dependencies right into the source tree, making
     it self-contained and 100% offline compatible.

4. **Linking and Integration**:
   - The resulting Rust static library is linked into an OCaml library
     (`xxx_stubs`).
   - This OCaml library provides the `Rust_staticlib` module and implements the
     virtual library `rust-staticlib`.
   - The `xxx_stubs` library is then linked into the final executable, bringing
     all the (transitive) Rust dependencies required for successful linking. You
     should not use `xxx_stubs` outside of your project. The generated rules do
     not assign any public name to this library, so dune should prevent you from
     depending on this library in your public libraries - those should depend on
     the virtual library `rust-staticlib` if they need Rust bindings to be
     present, or depend on some other library, which itself depends on
     `rust-staticlib`.

**Diagram illustrating the build process:**

```mermaid
flowchart TD
    subgraph rust_staticlib_gen["rust-staticlib-gen"]
        opam_files["xxx.opam file"] -->|Extracts crate dependencies| extracted_deps["Crate dependencies"]
    end
    extracted_deps -->|Generates| dune_file["dune inc file"]
    dune_file -->|Included into| main_dune_file["dune"]
    main_dune_file -->|Contains rule to invoke| rust_staticlib_gen
    dune_file -->|Contains rules to generate| cargo_toml["Cargo.toml"]
    dune_file -->|Contains rules to generate| lib_rs["lib.rs"]
    dune_file -->|Contains rules to generate| rust_staticlib_ml["Rust_staticlib.ml"]
    dune_file -->|Contains rule to build| rust_staticlib_build["rust-staticlib-build"]
    dune_file -->|Defines| ocaml_library
    rust_staticlib_build -->|Invokes| cargo_build["Cargo build"]
    cargo_build -->|Uses| cargo_toml
    cargo_build -->|Uses| lib_rs
    cargo_build -->|Builds| rust_staticlib["Rust staticlib (libxxx.a, dllxxx.so)"]
    rust_staticlib -->|Linked into| ocaml_library["OCaml library (xxx_stubs)"]
    ocaml_library -->|Provides module| rust_staticlib_ml
    ocaml_library -->|Implements| virtual_library["Virtual library rust-staticlib"]
    ocaml_library -->|Linked into| ocaml_code["Final OCaml executable"]
```

## Contributing

Contributions are welcome! Please open an issue or submit a pull request on
GitHub.


## License

This project is licensed under the Apache License Version 2.0. See the
[LICENSE](LICENSE) file for details.
