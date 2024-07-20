{ pkgs, runCommand }:

let
  rdt = pkgs.rust-dev-tools.setup {
    name = "rdt-example";
    dependencies = with pkgs; [ openssl ];
    version = pkgs.rust-dev-tools.version.nightly;
  };

  package = rdt.buildRustPackage {
    src = ../example;
    cargoLock.lockFile = ../example/Cargo.lock;
  };
in
runCommand "test-nightly" { } ''
  if [ ! -e ${package}/bin/rdt-example ]; then
    echo "Error: Built package does not contain the expected binary"
    exit 1
  fi

  # Check if we're using a nightly compiler
  RUSTC_VERSION=$(${rdt.rust}/bin/rustc --version)
  if ! echo "$RUSTC_VERSION" | grep -q "nightly"; then
    echo "Error: Not using a nightly compiler"
    echo "Current compiler version: $RUSTC_VERSION"
    exit 1
  fi

  ${package}/bin/rdt-example

  touch $out
''