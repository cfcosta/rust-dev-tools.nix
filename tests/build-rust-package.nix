{ pkgs, runCommand }:

let
  rdt = pkgs.rust-dev-tools.setup {
    name = "rdt-example";
    dependencies = with pkgs; [ openssl ];
  };

  package = rdt.buildRustPackage {
    src = ../example;
    cargoLock.lockFile = ../example/Cargo.lock;
  };
in
runCommand "test-build-rust-package" { } ''
  if [ ! -e ${package}/bin/rdt-example ]; then
    echo "Error: Built package does not contain the expected binary"
    exit 1
  fi

  ${package}/bin/rdt-example

  touch $out
''
