{ pkgs, self }:
let
  inherit (pkgs) lib runCommandCC;

  toolchain =
    rust:
    (self.setup pkgs {
      name = "rdt-toolchain";
      inherit rust;
    }).rust;

  # The toolchain `rust` selects reports `expected` from rustc, carries the
  # given tools, and compiles a program.
  expect =
    name: rust: expected: tools:
    let
      selected = toolchain rust;
    in
    runCommandCC "test-toolchain-${name}" { nativeBuildInputs = [ selected ]; } ''
      version="$(rustc --version)"
      echo "$version"
      pattern='${expected}'
      [[ $version == $pattern ]] || { echo "expected $pattern" >&2; exit 1; }
      cargo --version
      ${lib.concatMapStrings (tool: ''
        test -x ${selected}/bin/${tool} || { echo "missing ${tool}" >&2; exit 1; }
      '') tools}
      echo 'fn main() { println!("ok"); }' > main.rs
      rustc main.rs -o main
      test "$(./main)" = ok
      touch "$out"
    '';

  # Selections that must fail during evaluation.
  rejects = rust: !(builtins.tryEval (toolchain rust).drvPath).success;

  developmentTools = [
    "cargo-clippy"
    "rustfmt"
    "rust-analyzer"
  ];
in
assert lib.assertMsg (rejects (self.version.fromToolchain "stable" "0.9")) "unknown releases fail";
assert lib.assertMsg (rejects (
  self.version.fromToolchain "nightly" "2001-01-01"
)) "unindexed nightly dates fail";
assert lib.assertMsg (rejects (self.version.fromToolchain "dev" "latest")) "unknown channels fail";
assert lib.assertMsg (rejects (
  self.version.fromToolchain "stable" "1.85.0" // { components = [ "no-such-component" ]; }
)) "missing requested components fail";
{
  testToolchainLatestStable =
    expect "latest-stable" self.version.stable "rustc 1.*[0-9] (*"
      developmentTools;

  testToolchainPinnedPatch =
    expect "pinned-patch" (self.version.fromToolchain "stable" "1.85.0") "rustc 1.85.0 (*"
      developmentTools;

  # A minor version takes its newest patch release.
  testToolchainMinor =
    expect "minor" (self.version.fromToolchain "stable" "1.85") "rustc 1.85.1 (*"
      [ ];

  testToolchainNightly = expect "nightly" self.version.nightly "rustc 1.*-nightly (*" [ ];

  testToolchainDatedNightly =
    expect "dated-nightly" (self.version.fromToolchain "nightly" "2025-06-01") "rustc 1.89.0-nightly (*"
      [ ];

  testToolchainCargoToml = expect "cargo-toml" (self.version.fromCargoToml (
    builtins.toFile "Cargo.toml" ''
      [package]
      name = "probe"
      version = "0.1.0"
      rust-version = "1.80"
    ''
  )) "rustc 1.80.1 (*" [ ];

  testToolchainLegacyFile = expect "legacy-file" (self.version.fromToolchainFile (
    builtins.toFile "rust-toolchain" "1.82.0\n"
  )) "rustc 1.82.0 (*" [ ];

  testToolchainFileComponents =
    let
      file = builtins.toFile "rust-toolchain.toml" ''
        [toolchain]
        channel = "1.85.0"
        profile = "minimal"
        components = [ "llvm-tools" ]
        targets = [ "wasm32-unknown-unknown" ]
      '';
      selected = toolchain (self.version.fromToolchainFile file);
    in
    runCommandCC "test-toolchain-file-components" { nativeBuildInputs = [ selected ]; } ''
      rustc --version | grep -q '^rustc 1.85.0 '
      # The minimal profile leaves out the development tools.
      test ! -e ${selected}/bin/rust-analyzer
      test -d "$(rustc --print sysroot)/lib/rustlib/wasm32-unknown-unknown/lib"
      ls "$(rustc --print sysroot)/lib/rustlib/"*/bin/llvm-objdump
      echo '#![no_std] pub fn f() {}' > lib.rs
      rustc --crate-type=rlib --target wasm32-unknown-unknown lib.rs
      touch "$out"
    '';

  # The bundled LLD still links, through Nix's wrapper: a binary that needs
  # libstdc++ finds it at run time.
  testToolchainLinksThroughWrapper =
    let
      selected = toolchain self.version.stable;
    in
    runCommandCC "test-toolchain-links-through-wrapper"
      {
        nativeBuildInputs = [
          selected
          pkgs.binutils
        ];
      }
      ''
        echo 'fn main() { println!("ok"); }' > main.rs
        rustc main.rs -o main -C link-arg=-Wl,--no-as-needed -C link-arg=-lstdc++
        readelf -d main | grep -q 'libstdc++'
        ${lib.optionalString pkgs.stdenv.hostPlatform.isx86_64 "readelf -p .comment main | grep -q 'Linker: LLD'"}
        test "$(./main)" = ok
        touch "$out"
      '';

  # A stable compiler formatting with a nightly's unstable rustfmt options.
  testToolchainNightlyRustfmt =
    let
      selected = toolchain (
        self.version.fromToolchain "stable" "1.85.0"
        // {
          rustfmt = self.version.fromToolchain "nightly" "2025-06-01";
        }
      );
    in
    runCommandCC "test-toolchain-nightly-rustfmt" { nativeBuildInputs = [ selected ]; } ''
      rustc --version | grep -q '^rustc 1.85.0 '
      rustfmt --version | grep -q -- '-nightly '
      cargo clippy --version
      mkdir -p probe/src && cd probe
      printf '[package]\nname = "probe"\nversion = "0.1.0"\nedition = "2021"\n' > Cargo.toml
      echo 'imports_granularity = "Crate"' > rustfmt.toml
      printf 'use std::fmt::Debug;\nuse std::fmt::Display;\nfn main() {}\n' > src/main.rs
      cargo fmt
      grep -qx 'use std::fmt::{Debug, Display};' src/main.rs
      touch "$out"
    '';
}
