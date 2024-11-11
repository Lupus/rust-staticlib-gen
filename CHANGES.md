## 0.2.2 (2024-11-11)

### Added

- **dune-cargo-build**
  - Support for copying of Cargo artifacts on macos and windows platforms

### Fixed

- **rust-staticlib-gen**
  - Dropped unused dune rule that prevented building on macos

## 0.2.1 (2024-11-04)

### Added

- **dune-cargo-build**
  - Add support for executing arbitrary cargo sub-commands via @-prefixed command-line argument

### Fixed

- **rust-staticlib-gen**
  - Properly generate definition for `populate-rust-staticlib` alias (was
    missing before, causing errors in certain dune commands)

## 0.2.0 (2024-10-16)

### Added

- **rust-staticlib-gen**
  - Ensure we generate code for compatible versions of libs/tools

- **dune-cargo-build**
  - Emit debug output and exit with error when no artifacts are copied
  - Add -help option and detailed usage
  - Pass --offline to cargo only if network is unavailable (checks crates.io:443)
  - Add support for manifest path along with crate name to specify what to build
  - Add support for passing arbitrary flags to cargo after "--"
  - Add --profile flag to select release/debug build for cargo (compatible with dune profile naming)

### Fixed

- **rust-staticlib-gen**
  - Fix opam lib initialization (was not working in CI)

## 0.1.0 (2024-10-11)

* Initial release
