{ pkgs, runCommand }:

let
  rdt = pkgs.rust-dev-tools.setup {
    name = "rdt-example";
    dependencies = with pkgs; [ openssl ];
  };
in
runCommand "test-rust-package" { } ''
  if [ ! -e ${rdt.rust}/bin/rustc ]; then
    echo "Error: Rust package does not contain the expected rustc binary"
    exit 1
  fi

  ${rdt.rust}/bin/rustc --version

  touch $out
''
