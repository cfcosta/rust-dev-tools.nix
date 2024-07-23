{ pkgs, runCommand }:

let
  rdt = pkgs.rust-dev-tools.setup {
    name = "rdt-example";
    dependencies = with pkgs; [ openssl ];
    version = pkgs.rust-dev-tools.version.fromToolchainFile ../example/rust-toolchain.toml;
  };

  package = rdt.buildRustPackage {
    src = ../example;
    cargoLock.lockFile = ../example/Cargo.lock;
  };
in
runCommand "test-from-toolchain-file" { } ''
  if [ ! -e ${package}/bin/rdt-example ]; then
    echo "Error: Built package does not contain the expected binary"
    exit 1
  fi

  ${package}/bin/rdt-example

  touch $out
''
